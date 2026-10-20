CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.cafes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL
);

INSERT INTO public.cafes (slug, name)
VALUES ('corei', 'CoRei')
ON CONFLICT (slug) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.cafe_memberships (
    cafe_id UUID NOT NULL REFERENCES public.cafes(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('owner', 'manager', 'cashier')),
    PRIMARY KEY (cafe_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.menu_variants (
    id TEXT PRIMARY KEY,
    product_name TEXT NOT NULL,
    variant_label TEXT NOT NULL,
    price INTEGER NOT NULL CHECK (price >= 0),
    has_temperature BOOLEAN NOT NULL DEFAULT FALSE,
    has_ice BOOLEAN NOT NULL DEFAULT FALSE,
    has_sweetness BOOLEAN NOT NULL DEFAULT FALSE
);

INSERT INTO public.menu_variants (id, product_name, variant_label, price, has_temperature, has_ice, has_sweetness)
VALUES
    ('americano-cup', 'Americano', 'Cup', 10000, TRUE, TRUE, FALSE),
    ('americano-botol', 'Americano', 'Botol 250 ml', 13000, FALSE, FALSE, FALSE),
    ('latte-cup', 'White Latte', 'Cup', 12000, FALSE, TRUE, TRUE),
    ('latte-botol', 'White Latte', 'Botol 250 ml', 15000, FALSE, FALSE, TRUE),
    ('aren-cup', 'Aren', 'Cup', 13000, FALSE, TRUE, TRUE),
    ('aren-botol', 'Aren', 'Botol 250 ml', 18000, FALSE, FALSE, TRUE)
ON CONFLICT (id) DO UPDATE SET
    product_name = EXCLUDED.product_name,
    variant_label = EXCLUDED.variant_label,
    price = EXCLUDED.price,
    has_temperature = EXCLUDED.has_temperature,
    has_ice = EXCLUDED.has_ice,
    has_sweetness = EXCLUDED.has_sweetness;

CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    public_id TEXT NOT NULL UNIQUE CHECK (public_id ~ '^[a-f0-9]{32}$'),
    cafe_id UUID NOT NULL REFERENCES public.cafes(id) ON DELETE CASCADE,
    queue_number INTEGER NOT NULL CHECK (queue_number > 0),
    customer_name TEXT NOT NULL CHECK (length(trim(customer_name)) BETWEEN 1 AND 40),
    table_label TEXT NOT NULL DEFAULT '',
    payment_method TEXT NOT NULL CHECK (payment_method IN ('QRIS', 'Cash')),
    payment_status TEXT NOT NULL DEFAULT 'belum_bayar'
        CHECK (payment_status IN ('belum_bayar', 'lunas')),
    status TEXT NOT NULL DEFAULT 'baru'
        CHECK (status IN ('baru', 'diproses', 'siap', 'selesai', 'batal')),
    items JSONB NOT NULL CHECK (jsonb_typeof(items) = 'array'),
    subtotal INTEGER NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
    discount INTEGER NOT NULL DEFAULT 0 CHECK (discount >= 0),
    total INTEGER NOT NULL CHECK (total >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS items JSONB NOT NULL DEFAULT '[]'::JSONB;
ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS subtotal INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS discount INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS orders_cafe_created_idx
    ON public.orders (cafe_id, created_at DESC);

ALTER TABLE public.cafes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cafe_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.menu_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.cafes, public.menu_variants TO anon, authenticated;
GRANT SELECT ON public.cafe_memberships, public.orders TO authenticated;

DROP POLICY IF EXISTS "Public read active cafes" ON public.cafes;
DROP POLICY IF EXISTS "Customer read own order by public_id" ON public.orders;
DROP POLICY IF EXISTS "Customer insert order" ON public.orders;
DROP POLICY IF EXISTS "Staff manage orders" ON public.orders;

DO $$
BEGIN
    IF to_regclass('public.order_items') IS NOT NULL THEN
        EXECUTE 'DROP POLICY IF EXISTS "Public read order items" ON public.order_items';
        EXECUTE 'DROP POLICY IF EXISTS "Customer insert order items" ON public.order_items';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_cafe_member(check_cafe_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.cafe_memberships
        WHERE cafe_id = check_cafe_id
          AND user_id = auth.uid()
    );
$$;

CREATE POLICY "Cafe members can read their cafe"
    ON public.cafes FOR SELECT TO authenticated
    USING (public.is_cafe_member(id));

CREATE POLICY "Members can read their memberships"
    ON public.cafe_memberships FOR SELECT TO authenticated
    USING (user_id = auth.uid());

CREATE POLICY "Public can read cafe menu"
    ON public.menu_variants FOR SELECT TO anon, authenticated
    USING (TRUE);

CREATE POLICY "Cafe members can read orders"
    ON public.orders FOR SELECT TO authenticated
    USING (public.is_cafe_member(cafe_id));

CREATE OR REPLACE FUNCTION public.create_customer_order(
    p_customer_name TEXT,
    p_table_label TEXT,
    p_payment_method TEXT,
    p_items JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    cafe UUID;
    menu_item JSONB;
    variant_record public.menu_variants%ROWTYPE;
    normalized_items JSONB := '[]'::JSONB;
    calculated_total INTEGER := 0;
    item_qty INTEGER;
    temp_value TEXT;
    ice_value TEXT;
    sweet_value TEXT;
    local_day DATE;
    next_queue_number INTEGER;
    generated_public_id TEXT := REPLACE(gen_random_uuid()::TEXT, '-', '');
    created_order_id UUID;
BEGIN
    IF p_customer_name IS NULL OR length(trim(p_customer_name)) NOT BETWEEN 1 AND 40 THEN
        RAISE EXCEPTION 'Nama wajib diisi dulu ya.' USING ERRCODE = '22023';
    END IF;
    IF p_payment_method IS NULL OR p_payment_method NOT IN ('QRIS', 'Cash') THEN
        RAISE EXCEPTION 'Pilih cara bayar dulu ya (QRIS atau Cash).' USING ERRCODE = '22023';
    END IF;
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array'
       OR jsonb_array_length(p_items) NOT BETWEEN 1 AND 50 THEN
        RAISE EXCEPTION 'Isi pesanan tidak valid.' USING ERRCODE = '22023';
    END IF;

    SELECT id INTO STRICT cafe
    FROM public.cafes
    WHERE slug = 'corei';

    FOR menu_item IN SELECT value FROM jsonb_array_elements(p_items)
    LOOP
        SELECT * INTO variant_record
        FROM public.menu_variants
        WHERE id = menu_item->>'variant_id';
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Menu sudah tidak tersedia.' USING ERRCODE = '22023';
        END IF;

        item_qty := (menu_item->>'qty')::INTEGER;
        IF item_qty IS NULL OR item_qty NOT BETWEEN 1 AND 20 THEN
            RAISE EXCEPTION 'Jumlah menu harus antara 1 sampai 20.' USING ERRCODE = '22023';
        END IF;

        temp_value := NULLIF(menu_item->>'temp', '');
        ice_value := NULLIF(menu_item->>'ice', '');
        sweet_value := NULLIF(menu_item->>'sweet', '');

        IF variant_record.has_temperature THEN
            IF temp_value IS NULL OR temp_value NOT IN ('Ice', 'Hot') THEN
                RAISE EXCEPTION 'Pilihan suhu tidak valid.' USING ERRCODE = '22023';
            END IF;
        ELSIF temp_value IS NOT NULL THEN
            RAISE EXCEPTION 'Menu ini tidak menyediakan pilihan suhu.' USING ERRCODE = '22023';
        END IF;

        IF variant_record.has_ice AND (NOT variant_record.has_temperature OR temp_value = 'Ice') THEN
            IF ice_value IS NULL OR ice_value NOT IN ('Less ice', 'Normal ice', 'More ice') THEN
                RAISE EXCEPTION 'Pilihan es tidak valid.' USING ERRCODE = '22023';
            END IF;
        ELSIF ice_value IS NOT NULL THEN
            RAISE EXCEPTION 'Menu ini tidak menyediakan pilihan es tersebut.' USING ERRCODE = '22023';
        END IF;

        IF variant_record.has_sweetness THEN
            IF sweet_value IS NULL OR sweet_value NOT IN ('Less sweet', 'Normal sweet', 'Sweet') THEN
                RAISE EXCEPTION 'Pilihan manis tidak valid.' USING ERRCODE = '22023';
            END IF;
        ELSIF sweet_value IS NOT NULL THEN
            RAISE EXCEPTION 'Menu ini tidak menyediakan pilihan manis.' USING ERRCODE = '22023';
        END IF;

        calculated_total := calculated_total + variant_record.price * item_qty;
        normalized_items := normalized_items || jsonb_build_array(
            jsonb_build_object(
                'productName', variant_record.product_name,
                'variantLabel', variant_record.variant_label,
                'variantId', variant_record.id,
                'qty', item_qty,
                'price', variant_record.price,
                'temp', temp_value,
                'ice', CASE
                    WHEN variant_record.has_ice AND (NOT variant_record.has_temperature OR temp_value = 'Ice') THEN ice_value
                    ELSE NULL
                END,
                'sweet', sweet_value,
                'note', LEFT(COALESCE(menu_item->>'note', ''), 80)
            )
        );
    END LOOP;

    local_day := (NOW() AT TIME ZONE 'Asia/Jakarta')::DATE;
    PERFORM pg_advisory_xact_lock(
        hashtextextended(cafe::TEXT || ':' || local_day::TEXT, 0)
    );

    SELECT COALESCE(MAX(queue_number), 0) + 1 INTO next_queue_number
    FROM public.orders
    WHERE cafe_id = cafe
      AND (created_at AT TIME ZONE 'Asia/Jakarta')::DATE = local_day;

    INSERT INTO public.orders (
        public_id, cafe_id, queue_number, customer_name, table_label,
        payment_method, items, subtotal, discount, total
    )
    VALUES (
        generated_public_id, cafe, next_queue_number, trim(p_customer_name),
        LEFT(COALESCE(p_table_label, ''), 20), p_payment_method,
        normalized_items, calculated_total, 0, calculated_total
    )
    RETURNING id INTO created_order_id;

    RETURN jsonb_build_object(
        'public_id', generated_public_id,
        'queue_number', next_queue_number,
        'total', calculated_total,
        'items', normalized_items,
        'status', 'baru',
        'payment_status', 'belum_bayar'
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_customer_order_status(p_public_id TEXT)
RETURNS JSONB
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT jsonb_build_object(
        'public_id', public_id,
        'queue_number', queue_number,
        'customer_name', customer_name,
        'payment_method', payment_method,
        'payment_status', payment_status,
        'status', status,
        'table_label', table_label,
        'items', items,
        'total', total
    )
    FROM public.orders
    WHERE public_id = p_public_id
      AND p_public_id ~ '^[a-f0-9]{32}$';
$$;

CREATE OR REPLACE FUNCTION public.update_customer_order_status(
    p_public_id TEXT,
    p_status TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    order_cafe_id UUID;
    current_status TEXT;
BEGIN
    SELECT cafe_id, status INTO order_cafe_id, current_status
    FROM public.orders
    WHERE public_id = p_public_id
    FOR UPDATE;

    IF NOT FOUND OR NOT public.is_cafe_member(order_cafe_id) THEN
        RAISE EXCEPTION 'Pesanan tidak ditemukan atau akses ditolak.' USING ERRCODE = '42501';
    END IF;

    IF NOT (
        (current_status = 'baru' AND p_status = 'diproses')
        OR (current_status = 'diproses' AND p_status = 'siap')
        OR (current_status = 'siap' AND p_status = 'selesai')
    ) THEN
        RAISE EXCEPTION 'Perubahan status pesanan tidak valid.' USING ERRCODE = '22023';
    END IF;

    UPDATE public.orders
    SET status = p_status
    WHERE public_id = p_public_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_customer_order_payment(
    p_public_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    order_cafe_id UUID;
BEGIN
    SELECT cafe_id INTO order_cafe_id
    FROM public.orders
    WHERE public_id = p_public_id;

    IF NOT FOUND OR NOT public.is_cafe_member(order_cafe_id) THEN
        RAISE EXCEPTION 'Pesanan tidak ditemukan atau akses ditolak.' USING ERRCODE = '42501';
    END IF;

    UPDATE public.orders
    SET payment_status = 'lunas'
    WHERE public_id = p_public_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_subscribe_to_order_topic(topic TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.orders
        WHERE public_id = substring(topic FROM '^order:([a-f0-9]{32})$')
    );
$$;

CREATE OR REPLACE FUNCTION public.broadcast_order_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'UPDATE'
       AND (OLD.status IS DISTINCT FROM NEW.status
            OR OLD.payment_status IS DISTINCT FROM NEW.payment_status) THEN
        PERFORM realtime.send(
            jsonb_build_object(
                'status', NEW.status,
                'payment_status', NEW.payment_status,
                'queue_number', NEW.queue_number
            ),
            'status_updated',
            'order:' || NEW.public_id,
            TRUE
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS broadcast_order_status_trigger ON public.orders;
CREATE TRIGGER broadcast_order_status_trigger
    AFTER UPDATE ON public.orders
    FOR EACH ROW EXECUTE FUNCTION public.broadcast_order_status();

DROP POLICY IF EXISTS "Customers can receive their order status" ON realtime.messages;
CREATE POLICY "Customers can receive their order status"
    ON realtime.messages FOR SELECT TO anon
    USING (public.can_subscribe_to_order_topic((SELECT realtime.topic())));

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'orders'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.is_cafe_member(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_cafe_member(UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.can_subscribe_to_order_topic(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_subscribe_to_order_topic(TEXT) TO anon;

REVOKE ALL ON FUNCTION public.create_customer_order(TEXT, TEXT, TEXT, JSONB) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.create_customer_order(TEXT, TEXT, TEXT, JSONB) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.get_customer_order_status(TEXT) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.get_customer_order_status(TEXT) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.update_customer_order_status(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_customer_order_status(TEXT, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.update_customer_order_payment(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_customer_order_payment(TEXT) TO authenticated;
