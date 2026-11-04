-- Registrasi varian menu baru oleh staf CoRei
ALTER TABLE public.menu_variants
  ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'Kopi';

UPDATE public.menu_variants SET category = 'Kopi'
WHERE category IS NULL OR btrim(category) = '';

CREATE OR REPLACE FUNCTION public.register_menu_variant(
  p_product_name TEXT,
  p_category TEXT,
  p_variant_label TEXT,
  p_price INTEGER,
  p_compare_price INTEGER DEFAULT 0,
  p_tag TEXT DEFAULT ''
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cafe_id UUID;
  v_variant_id TEXT;
  v_base_id TEXT;
  v_counter INTEGER := 1;
BEGIN
  SELECT id INTO v_cafe_id FROM public.cafes WHERE slug = 'corei';
  IF NOT public.is_cafe_member(v_cafe_id) THEN
    RAISE EXCEPTION 'Akses ditolak: hanya staf CoRei yang dapat mendaftarkan menu.' USING ERRCODE = '42501';
  END IF;

  IF btrim(COALESCE(p_product_name, '')) = '' THEN
    RAISE EXCEPTION 'Nama produk wajib diisi.' USING ERRCODE = '22023';
  END IF;
  IF btrim(COALESCE(p_variant_label, '')) = '' THEN
    RAISE EXCEPTION 'Label varian wajib diisi.' USING ERRCODE = '22023';
  END IF;
  IF p_price IS NULL OR p_price < 0 THEN
    RAISE EXCEPTION 'Harga tidak valid.' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(p_compare_price, 0) < 0 THEN
    RAISE EXCEPTION 'Harga coret tidak valid.' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(p_tag, '') NOT IN ('', 'promo', 'favorit', 'baru') THEN
    RAISE EXCEPTION 'Tag tidak valid.' USING ERRCODE = '22023';
  END IF;

  v_base_id := regexp_replace(lower(trim(p_product_name)), '[^a-z0-9]+', '-', 'g');
  v_base_id := trim(both '-' from v_base_id);
  IF v_base_id = '' THEN v_base_id := 'menu'; END IF;
  v_variant_id := v_base_id || '-' || regexp_replace(lower(trim(p_variant_label)), '[^a-z0-9]+', '-', 'g');
  v_variant_id := trim(both '-' from v_variant_id);

  WHILE EXISTS (SELECT 1 FROM public.menu_variants WHERE id = v_variant_id) LOOP
    v_variant_id := v_base_id || '-' || regexp_replace(lower(trim(p_variant_label)), '[^a-z0-9]+', '-', 'g') || '-' || v_counter;
    v_counter := v_counter + 1;
  END LOOP;

  INSERT INTO public.menu_variants (
    id, product_name, category, variant_label, price, compare_price, tag,
    has_temperature, has_ice, has_sweetness, is_active
  ) VALUES (
    v_variant_id, trim(p_product_name), COALESCE(NULLIF(trim(p_category), ''), 'Lainnya'), trim(p_variant_label),
    p_price, COALESCE(p_compare_price, 0), NULLIF(p_tag, ''), FALSE, FALSE, FALSE, TRUE
  );

  RETURN v_variant_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_all_menu_variants()
RETURNS JSONB
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', id,
      'product_name', product_name,
      'category', category,
      'variant_label', variant_label,
      'price', price,
      'compare_price', compare_price,
      'has_temperature', has_temperature,
      'has_ice', has_ice,
      'has_sweetness', has_sweetness,
      'is_active', is_active,
      'tag', tag
    ) ORDER BY product_name, variant_label
  ), '[]'::jsonb)
  FROM public.menu_variants;
$$;

GRANT EXECUTE ON FUNCTION public.register_menu_variant(TEXT, TEXT, TEXT, INTEGER, INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_all_menu_variants() TO authenticated;
