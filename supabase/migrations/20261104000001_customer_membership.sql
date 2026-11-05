CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.customer_memberships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cafe_id UUID NOT NULL REFERENCES public.cafes(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  pin_hash TEXT NOT NULL,
  points INTEGER NOT NULL DEFAULT 0 CHECK (points >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (cafe_id, name)
);

CREATE TABLE IF NOT EXISTS public.membership_point_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id UUID NOT NULL REFERENCES public.customer_memberships(id) ON DELETE CASCADE,
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  points INTEGER NOT NULL CHECK (points != 0),
  description TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (member_id, order_id)
);

ALTER TABLE public.customer_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.membership_point_transactions ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.register_customer_member(p_name TEXT, p_pin TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions, pg_temp AS $$
DECLARE v_cafe UUID; v_name TEXT;
BEGIN
  v_name := btrim(regexp_replace(COALESCE(p_name, ''), '\s+', ' ', 'g'));
  IF length(v_name) NOT BETWEEN 2 AND 40 THEN RAISE EXCEPTION 'Nama harus 2 sampai 40 karakter.' USING ERRCODE='22023'; END IF;
  IF COALESCE(p_pin, '') !~ '^\d{4,6}$' THEN RAISE EXCEPTION 'PIN harus 4 sampai 6 angka.' USING ERRCODE='22023'; END IF;
  SELECT id INTO STRICT v_cafe FROM public.cafes WHERE slug = 'corei';
  INSERT INTO public.customer_memberships(cafe_id, name, pin_hash)
  VALUES (v_cafe, v_name, extensions.crypt(p_pin, extensions.gen_salt('bf')));
  RETURN jsonb_build_object('name', v_name, 'points', 0);
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Nama membership sudah terdaftar. Gunakan menu Masuk.' USING ERRCODE='23505';
END; $$;

CREATE OR REPLACE FUNCTION public.login_customer_member(p_name TEXT, p_pin TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions, pg_temp AS $$
DECLARE v_cafe UUID; v_member public.customer_memberships%ROWTYPE;
BEGIN
  SELECT id INTO STRICT v_cafe FROM public.cafes WHERE slug = 'corei';
  SELECT * INTO v_member FROM public.customer_memberships
  WHERE cafe_id=v_cafe AND lower(name)=lower(btrim(COALESCE(p_name,'')));
  IF NOT FOUND OR NOT extensions.crypt(COALESCE(p_pin,''), v_member.pin_hash)=v_member.pin_hash THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object('name', v_member.name, 'points', v_member.points);
END; $$;

CREATE OR REPLACE FUNCTION public.claim_customer_order_points(p_name TEXT, p_pin TEXT, p_public_id TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions, pg_temp AS $$
DECLARE v_cafe UUID; v_member public.customer_memberships%ROWTYPE; v_order public.orders%ROWTYPE; v_points INTEGER; v_new_points INTEGER;
BEGIN
  SELECT id INTO STRICT v_cafe FROM public.cafes WHERE slug='corei';
  SELECT * INTO v_member FROM public.customer_memberships WHERE cafe_id=v_cafe AND lower(name)=lower(btrim(COALESCE(p_name,'')));
  IF NOT FOUND OR NOT extensions.crypt(COALESCE(p_pin,''), v_member.pin_hash)=v_member.pin_hash THEN
    RETURN jsonb_build_object('success', false, 'message', 'PIN salah.');
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE public_id=p_public_id AND cafe_id=v_cafe;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'message', 'Pesanan tidak ditemukan.'); END IF;
  IF lower(trim(v_order.customer_name)) <> lower(trim(v_member.name)) THEN
    RETURN jsonb_build_object('success', false, 'message', 'Pesanan ini tidak terdaftar atas nama member yang sama.');
  END IF;
  IF v_order.status <> 'selesai' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Poin baru bisa ditambahkan setelah pesanan selesai.');
  END IF;
  IF EXISTS (SELECT 1 FROM public.membership_point_transactions WHERE member_id=v_member.id AND order_id=v_order.id) THEN
    SELECT points INTO v_new_points FROM public.customer_memberships WHERE id=v_member.id;
    RETURN jsonb_build_object('success', true, 'points', v_new_points, 'earned', 0, 'message', 'Poin untuk pesanan ini sudah ditambahkan.');
  END IF;
  v_points := floor(v_order.total / 1000)::INTEGER * 10;
  UPDATE public.customer_memberships
  SET points = points + v_points
  WHERE id = v_member.id
  RETURNING points INTO v_new_points;
  INSERT INTO public.membership_point_transactions(member_id, order_id, points, description)
  VALUES (v_member.id, v_order.id, v_points, 'Poin pesanan ' || p_public_id);
  RETURN jsonb_build_object('success', true, 'points', v_new_points, 'earned', v_points, 'message', 'Poin berhasil ditambahkan.');
END; $$;

GRANT EXECUTE ON FUNCTION public.register_customer_member(TEXT,TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.login_customer_member(TEXT,TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_customer_order_points(TEXT,TEXT,TEXT) TO anon, authenticated;
