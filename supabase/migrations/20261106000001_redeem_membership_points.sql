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
BEGIN
  SELECT id INTO STRICT v_cafe FROM public.cafes WHERE slug = 'corei';
  SELECT * INTO v_member
  FROM public.customer_memberships
  WHERE cafe_id = v_cafe
    AND lower(name) = lower(btrim(COALESCE(p_name, '')));

  IF NOT FOUND OR NOT extensions.crypt(COALESCE(p_pin, ''), v_member.pin_hash) = v_member.pin_hash THEN
    RETURN jsonb_build_object('success', false, 'message', 'PIN salah.');
  END IF;

  v_reward_cost := CASE upper(trim(COALESCE(p_reward, '')))
    WHEN 'AMERICANO' THEN 21970
    WHEN 'WHITE LATTE' THEN 25350
    WHEN 'AREN' THEN 33800
    ELSE NULL
  END;

  IF v_reward_cost IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Pilihan penukaran tidak valid.');
  END IF;

  IF v_member.points < v_reward_cost THEN
    RETURN jsonb_build_object('success', false, 'message', 'Poin belum cukup untuk penukaran ini.');
  END IF;

  UPDATE public.customer_memberships
  SET points = points - v_reward_cost
  WHERE id = v_member.id
  RETURNING points INTO v_new_points;

  v_code := upper(substr(replace(gen_random_uuid()::TEXT, '-', ''), 1, 8));
  INSERT INTO public.membership_point_transactions(member_id, order_id, points, description)
  VALUES (
    v_member.id,
    NULL,
    -v_reward_cost,
    'Penukaran ' || upper(trim(p_reward)) || ' - kode ' || v_code
  );

  RETURN jsonb_build_object(
    'success', true,
    'points', v_new_points,
    'cost', v_reward_cost,
    'reward', upper(trim(p_reward)),
    'code', v_code
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.redeem_customer_member_points(TEXT, TEXT, TEXT) TO anon, authenticated;
