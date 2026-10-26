-- ============================================================================
-- SOLUSI: Hapus function lama yang mendua, lalu buat satu function definitif
-- Jalankan SELURUH script ini di Supabase SQL Editor
-- ============================================================================

-- 1. Hapus kedua variasi function yang konflik
DROP FUNCTION IF EXISTS public.create_customer_order(text, text, jsonb, text);
DROP FUNCTION IF EXISTS public.create_customer_order(text, text, text, jsonb);
DROP FUNCTION IF EXISTS public.create_customer_order;

-- 2. Buat kembali function tunggal yang bersih dengan urutan parameter standar
CREATE OR REPLACE FUNCTION public.create_customer_order(
    p_customer_name TEXT,
    p_payment_method TEXT,
    p_items JSONB,
    p_table_label TEXT DEFAULT ''
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
    item_qty INTEGER;
    calculated_total INTEGER := 0;
    normalized_items JSONB := '[]'::JSONB;
    temp_value TEXT;
    ice_value TEXT;
    sweet_value TEXT;
    local_month TEXT;
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

    -- Periode Bulanan (Reset setiap berganti bulan di zona waktu Asia/Jakarta)
    local_month := TO_CHAR(NOW() AT TIME ZONE 'Asia/Jakarta', 'YYYY-MM');
    PERFORM pg_advisory_xact_lock(
        hashtextextended(cafe::TEXT || ':' || local_month, 0)
    );

    -- Urut nomor antrean per bulan
    SELECT COALESCE(MAX(queue_number), 0) + 1 INTO next_queue_number
    FROM public.orders
    WHERE cafe_id = cafe
      AND TO_CHAR(created_at AT TIME ZONE 'Asia/Jakarta', 'YYYY-MM') = local_month;

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

-- Berikan izin panggil fungsi ke pengguna anon dan authenticated
GRANT EXECUTE ON FUNCTION public.create_customer_order(TEXT, TEXT, JSONB, TEXT) TO anon, authenticated;
