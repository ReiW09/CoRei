CREATE OR REPLACE FUNCTION public.update_menu_variant(
  p_variant_id TEXT,
  p_product_name TEXT,
  p_variant_label TEXT,
  p_price INTEGER,
  p_compare_price INTEGER,
  p_is_active BOOLEAN,
  p_tag TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cafe_id UUID;
  v_tag TEXT := NULLIF(trim(COALESCE(p_tag, '')), '');
BEGIN
  SELECT id INTO v_cafe_id FROM public.cafes WHERE slug = 'corei';
  IF NOT public.is_cafe_member(v_cafe_id) THEN
    RAISE EXCEPTION 'Akses ditolak: hanya staf CoRei yang dapat mengubah menu.' USING ERRCODE = '42501';
  END IF;

  IF p_product_name IS NULL OR trim(p_product_name) = '' THEN
    RAISE EXCEPTION 'Nama produk wajib diisi.' USING ERRCODE = '22023';
  END IF;
  IF p_price IS NULL OR p_price < 0 THEN
    RAISE EXCEPTION 'Harga tidak valid.' USING ERRCODE = '22023';
  END IF;
  IF p_compare_price IS NULL OR p_compare_price < 0 THEN
    RAISE EXCEPTION 'Harga coret tidak valid.' USING ERRCODE = '22023';
  END IF;
  IF v_tag IS NOT NULL AND v_tag NOT IN ('promo','favorit','baru') THEN
    RAISE EXCEPTION 'Tag tidak valid.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.menu_variants SET
    product_name = trim(p_product_name),
    variant_label = trim(COALESCE(p_variant_label, '')),
    price = p_price,
    compare_price = p_compare_price,
    is_active = p_is_active,
    tag = v_tag
  WHERE id = p_variant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Varian menu tidak ditemukan.' USING ERRCODE = '22023';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_menu_variant(TEXT, TEXT, TEXT, INTEGER, INTEGER, BOOLEAN, TEXT) TO authenticated;
