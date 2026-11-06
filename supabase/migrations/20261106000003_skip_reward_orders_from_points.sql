CREATE OR REPLACE FUNCTION public.award_completed_order_membership_points(p_order_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_member public.customer_memberships%ROWTYPE;
  v_points INTEGER;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND OR v_order.status <> 'selesai' OR COALESCE(v_order.total, 0) <= 0 THEN
    RETURN;
  END IF;

  SELECT * INTO v_member
  FROM public.customer_memberships
  WHERE cafe_id = v_order.cafe_id
    AND lower(btrim(name)) = lower(btrim(v_order.customer_name));
  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.membership_point_transactions
    WHERE member_id = v_member.id AND order_id = v_order.id
  ) THEN
    RETURN;
  END IF;

  v_points := floor(v_order.total / 1000)::INTEGER * 10;
  IF v_points <= 0 THEN
    RETURN;
  END IF;

  UPDATE public.customer_memberships
  SET points = points + v_points
  WHERE id = v_member.id;

  INSERT INTO public.membership_point_transactions(member_id, order_id, points, description)
  VALUES (v_member.id, v_order.id, v_points, 'Poin pesanan ' || v_order.public_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_customer_order_points(p_name TEXT, p_pin TEXT, p_public_id TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions, pg_temp AS $$
DECLARE
  v_cafe UUID;
  v_member public.customer_memberships%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_points INTEGER;
  v_new_points INTEGER;
BEGIN
  SELECT id INTO STRICT v_cafe FROM public.cafes WHERE slug='corei';
  SELECT * INTO v_member FROM public.customer_memberships
  WHERE cafe_id=v_cafe AND lower(name)=lower(btrim(COALESCE(p_name,'')));
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
  IF COALESCE(v_order.total, 0) <= 0 THEN
    RETURN jsonb_build_object('success', true, 'points', v_member.points, 'earned', 0, 'message', 'Pesanan reward tidak menghasilkan poin.');
  END IF;
  IF EXISTS (SELECT 1 FROM public.membership_point_transactions WHERE member_id=v_member.id AND order_id=v_order.id) THEN
    SELECT points INTO v_new_points FROM public.customer_memberships WHERE id=v_member.id;
    RETURN jsonb_build_object('success', true, 'points', v_new_points, 'earned', 0, 'message', 'Poin untuk pesanan ini sudah ditambahkan.');
  END IF;
  v_points := floor(v_order.total / 1000)::INTEGER * 10;
  IF v_points <= 0 THEN
    RETURN jsonb_build_object('success', true, 'points', v_member.points, 'earned', 0, 'message', 'Nilai pesanan belum mencapai 1.000 untuk mendapatkan poin.');
  END IF;
  UPDATE public.customer_memberships SET points = points + v_points WHERE id = v_member.id
  RETURNING points INTO v_new_points;
  INSERT INTO public.membership_point_transactions(member_id, order_id, points, description)
  VALUES (v_member.id, v_order.id, v_points, 'Poin pesanan ' || p_public_id);
  RETURN jsonb_build_object('success', true, 'points', v_new_points, 'earned', v_points, 'message', 'Poin berhasil ditambahkan.');
END; $$;

REVOKE ALL ON FUNCTION public.award_completed_order_membership_points(UUID) FROM PUBLIC, anon, authenticated;
