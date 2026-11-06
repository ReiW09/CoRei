CREATE OR REPLACE FUNCTION public.redeem_customer_member_points(
  p_name TEXT,
  p_pin TEXT,
  p_reward TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_cafe UUID;
  v_member public.customer_memberships%ROWTYPE;
  v_reward_cost INTEGER;
  v_new_points INTEGER;
  v_code TEXT;
  v_variant_id TEXT;
  v_variant public.menu_variants%ROWTYPE;
  v_public_id TEXT;
  v_queue_number INTEGER;
  v_order_id UUID;
  v_local_day DATE;
  v_reward_items JSONB;
BEGIN
  SELECT id INTO STRICT v_cafe FROM public.cafes WHERE slug = 'corei';
  SELECT * INTO v_member
  FROM public.customer_memberships
  WHERE cafe_id = v_cafe
    AND lower(name) = lower(btrim(COALESCE(p_name, '')));

  IF NOT FOUND OR NOT extensions.crypt(COALESCE(p_pin, ''), v_member.pin_hash) = v_member.pin_hash THEN
    RETURN jsonb_build_object('success', false, 'message', 'PIN salah.');
  END IF;

  v_variant_id := CASE upper(trim(COALESCE(p_reward, '')))
    WHEN 'AMERICANO' THEN 'americano-cup'
    WHEN 'WHITE LATTE' THEN 'latte-cup'
    WHEN 'AREN' THEN 'aren-cup'
    ELSE NULL
  END;
  v_reward_cost := CASE upper(trim(COALESCE(p_reward, '')))
    WHEN 'AMERICANO' THEN 21970
    WHEN 'WHITE LATTE' THEN 25350
    WHEN 'AREN' THEN 33800
    ELSE NULL
  END;

  IF v_variant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Pilihan penukaran tidak valid.');
  END IF;
  SELECT * INTO v_variant FROM public.menu_variants WHERE id = v_variant_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Menu reward tidak tersedia.');
  END IF;
  IF v_member.points < v_reward_cost THEN
    RETURN jsonb_build_object('success', false, 'message', 'Poin belum cukup untuk penukaran ini.');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_cafe::TEXT, 0));

  UPDATE public.customer_memberships
  SET points = points - v_reward_cost
  WHERE id = v_member.id AND points >= v_reward_cost
  RETURNING points INTO v_new_points;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Poin berubah. Silakan coba lagi.');
  END IF;

  v_code := upper(substr(replace(gen_random_uuid()::TEXT, '-', ''), 1, 8));
  v_public_id := replace(gen_random_uuid()::TEXT, '-', '');
  v_local_day := (NOW() AT TIME ZONE 'Asia/Jakarta')::DATE;
  SELECT COALESCE(MAX(queue_number), 0) + 1 INTO v_queue_number
  FROM public.orders
  WHERE cafe_id = v_cafe
    AND (created_at AT TIME ZONE 'Asia/Jakarta')::DATE = v_local_day;

  v_reward_items := jsonb_build_array(jsonb_build_object(
    'productName', v_variant.product_name,
    'variantLabel', v_variant.variant_label,
    'variantId', v_variant.id,
    'qty', 1,
    'price', 0,
    'category', 'MEMBERSHIP REWARD',
    'rewardCode', v_code
  ));

  INSERT INTO public.orders (
    public_id, cafe_id, queue_number, customer_name, table_label,
    payment_method, payment_status, status, items, subtotal, discount, total
  ) VALUES (
    v_public_id, v_cafe, v_queue_number, trim(p_name), 'MEMBERSHIP REWARD',
    'Cash', 'lunas', 'baru', v_reward_items, 0, 0, 0
  ) RETURNING id INTO v_order_id;

  INSERT INTO public.membership_point_transactions(member_id, order_id, points, description)
  VALUES (
    v_member.id,
    NULL,
    -v_reward_cost,
    'Penukaran ' || upper(trim(p_reward)) || ' - kode ' || v_code || ' - pesanan ' || v_public_id
  );

  RETURN jsonb_build_object(
    'success', true,
    'points', v_new_points,
    'cost', v_reward_cost,
    'reward', upper(trim(p_reward)),
    'code', v_code,
    'public_id', v_public_id,
    'queue_number', v_queue_number
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.redeem_customer_member_points(TEXT, TEXT, TEXT) TO anon, authenticated;
