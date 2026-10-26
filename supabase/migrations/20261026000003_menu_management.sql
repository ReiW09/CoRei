-- Migrasi: Menambahkan kolom pengelolaan menu dinamis
-- Jalankan di Supabase SQL Editor

-- 1. Tambah kolom is_active dan compare_price (harga coret promo) ke menu_variants
ALTER TABLE public.menu_variants
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS compare_price INTEGER NOT NULL DEFAULT 0 CHECK (compare_price >= 0),
  ADD COLUMN IF NOT EXISTS tag TEXT CHECK (tag IN ('promo', 'favorit', 'baru', NULL));

-- 2. Update menu yang ada agar memiliki tag promo untuk Aren
UPDATE public.menu_variants
SET tag = 'promo', compare_price = CASE
  WHEN id = 'aren-cup' THEN 15000
  WHEN id = 'aren-botol' THEN 20000
  ELSE 0
END
WHERE id IN ('aren-cup', 'aren-botol');

-- 3. Fungsi untuk staf membaca semua menu variants (termasuk yang nonaktif, untuk admin)
CREATE OR REPLACE FUNCTION public.get_all_menu_variants()
RETURNS JSONB
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', id,
      'product_name', product_name,
      'variant_label', variant_label,
      'price', price,
      'compare_price', compare_price,
      'has_temperature', has_temperature,
      'has_ice', has_ice,
      'has_sweetness', has_sweetness,
      'is_active', is_active,
      'tag', tag
    ) ORDER BY product_name, variant_label
  )
  FROM public.menu_variants;
$$;

-- 4. Fungsi untuk update harga, tag, is_active oleh staf yang login
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
BEGIN
  -- Cek apakah user adalah anggota kafe CoRei
  SELECT id INTO v_cafe_id FROM public.cafes WHERE slug = 'corei';
  IF NOT public.is_cafe_member(v_cafe_id) THEN
    RAISE EXCEPTION 'Akses ditolak: hanya staf CoRei yang dapat mengubah menu.' USING ERRCODE = '42501';
  END IF;

  IF p_price IS NULL OR p_price < 0 THEN
    RAISE EXCEPTION 'Harga tidak valid.' USING ERRCODE = '22023';
  END IF;
  IF p_compare_price IS NULL OR p_compare_price < 0 THEN
    RAISE EXCEPTION 'Harga coret tidak valid.' USING ERRCODE = '22023';
  END IF;
  IF p_tag IS NOT NULL AND p_tag NOT IN ('promo','favorit','baru') THEN
    RAISE EXCEPTION 'Tag tidak valid.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.menu_variants SET
    product_name = trim(p_product_name),
    variant_label = trim(p_variant_label),
    price = p_price,
    compare_price = p_compare_price,
    is_active = p_is_active,
    tag = NULLIF(p_tag, '')
  WHERE id = p_variant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Varian menu tidak ditemukan.' USING ERRCODE = '22023';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_all_menu_variants() TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_menu_variant(TEXT, TEXT, TEXT, INTEGER, INTEGER, BOOLEAN, TEXT) TO authenticated;
