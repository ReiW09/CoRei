-- Tambahkan kategori Signature dan Promo Bundle serta pengubahan kategori dari panel admin.

CREATE OR REPLACE FUNCTION public.update_menu_variant_category(
  p_variant_id TEXT,
  p_category TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cafe_id UUID;
  v_category TEXT := trim(COALESCE(p_category, ''));
BEGIN
  SELECT id INTO v_cafe_id FROM public.cafes WHERE slug = 'corei';
  IF NOT public.is_cafe_member(v_cafe_id) THEN
    RAISE EXCEPTION 'Akses ditolak: hanya staf CoRei yang dapat mengubah kategori menu.' USING ERRCODE = '42501';
  END IF;

  IF v_category NOT IN ('Kopi', 'Non Kopi', 'Signature', 'Promo Bundle', 'Makanan', 'Snack', 'Lainnya') THEN
    RAISE EXCEPTION 'Kategori menu tidak valid.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.menu_variants
  SET category = v_category
  WHERE id = p_variant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Varian menu tidak ditemukan.' USING ERRCODE = '22023';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_menu_variant_category(TEXT, TEXT) TO authenticated;
