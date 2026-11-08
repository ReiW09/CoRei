CREATE TABLE IF NOT EXISTS public.menu_bundle_components (
  bundle_variant_id TEXT NOT NULL REFERENCES public.menu_variants(id) ON DELETE CASCADE,
  component_variant_id TEXT NOT NULL REFERENCES public.menu_variants(id) ON DELETE RESTRICT,
  quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  PRIMARY KEY (bundle_variant_id, component_variant_id)
);

ALTER TABLE public.menu_bundle_components ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.create_menu_bundle(
  p_product_name TEXT,
  p_component_ids TEXT[],
  p_quantities INTEGER[],
  p_bundle_price INTEGER
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
  v_normal_total INTEGER := 0;
  v_component_price INTEGER;
  v_component_name TEXT;
  v_component_label TEXT := '';
  i INTEGER;
BEGIN
  SELECT id INTO v_cafe_id FROM public.cafes WHERE slug = 'corei';
  IF NOT public.is_cafe_member(v_cafe_id) THEN
    RAISE EXCEPTION 'Akses ditolak: hanya staf CoRei yang dapat membuat bundle.' USING ERRCODE = '42501';
  END IF;

  IF btrim(COALESCE(p_product_name, '')) = '' THEN
    RAISE EXCEPTION 'Nama menu bundle wajib diisi.' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(array_length(p_component_ids, 1), 0) = 0 THEN
    RAISE EXCEPTION 'Bundle wajib memiliki minimal satu menu penyusun.' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(array_length(p_component_ids, 1), 0) <> COALESCE(array_length(p_quantities, 1), 0) THEN
    RAISE EXCEPTION 'Jumlah menu dan quantity tidak sesuai.' USING ERRCODE = '22023';
  END IF;
  IF (SELECT count(DISTINCT id) FROM unnest(p_component_ids) AS ids(id)) <> array_length(p_component_ids, 1) THEN
    RAISE EXCEPTION 'Menu penyusun tidak boleh dipilih lebih dari satu baris.' USING ERRCODE = '22023';
  END IF;
  IF p_bundle_price IS NULL OR p_bundle_price < 0 THEN
    RAISE EXCEPTION 'Harga bundle tidak valid.' USING ERRCODE = '22023';
  END IF;

  FOR i IN 1..array_length(p_component_ids, 1) LOOP
    IF COALESCE(p_quantities[i], 0) <= 0 THEN
      RAISE EXCEPTION 'Quantity menu bundle harus lebih dari nol.' USING ERRCODE = '22023';
    END IF;
    SELECT price, product_name || CASE WHEN btrim(COALESCE(variant_label, '')) = '' THEN '' ELSE ' ' || variant_label END
      INTO v_component_price, v_component_name
    FROM public.menu_variants
    WHERE id = p_component_ids[i] AND is_active = TRUE AND category IS DISTINCT FROM 'Promo Bundle';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Menu penyusun tidak valid atau tidak aktif.' USING ERRCODE = '22023';
    END IF;
    v_normal_total := v_normal_total + v_component_price * p_quantities[i];
    IF v_component_label <> '' THEN v_component_label := v_component_label || ', '; END IF;
    v_component_label := v_component_label || CASE WHEN p_quantities[i] > 1 THEN p_quantities[i]::TEXT || 'x ' ELSE '' END || v_component_name;
  END LOOP;

  IF p_bundle_price >= v_normal_total THEN
    RAISE EXCEPTION 'Harga bundle harus lebih rendah dari harga normal Rp%s.', v_normal_total USING ERRCODE = '22023';
  END IF;

  v_base_id := 'bundle-' || regexp_replace(lower(trim(p_product_name)), '[^a-z0-9]+', '-', 'g');
  v_base_id := trim(both '-' from v_base_id);
  IF v_base_id = 'bundle-' OR v_base_id = '' THEN v_base_id := 'bundle-menu'; END IF;
  v_variant_id := v_base_id;
  WHILE EXISTS (SELECT 1 FROM public.menu_variants WHERE id = v_variant_id) LOOP
    v_variant_id := v_base_id || '-' || v_counter;
    v_counter := v_counter + 1;
  END LOOP;

  INSERT INTO public.menu_variants (
    id, product_name, category, variant_label, price, compare_price, tag,
    has_temperature, has_ice, has_sweetness, is_active
  ) VALUES (
    v_variant_id, trim(p_product_name), 'Promo Bundle', v_component_label,
    p_bundle_price, v_normal_total, 'promo', FALSE, FALSE, FALSE, TRUE
  );

  FOR i IN 1..array_length(p_component_ids, 1) LOOP
    INSERT INTO public.menu_bundle_components (bundle_variant_id, component_variant_id, quantity)
    VALUES (v_variant_id, p_component_ids[i], p_quantities[i]);
  END LOOP;

  RETURN v_variant_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_menu_bundle(TEXT, TEXT[], INTEGER[], INTEGER) TO authenticated;
