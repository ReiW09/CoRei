ALTER TABLE public.menu_variants
  ADD COLUMN IF NOT EXISTS image_url TEXT;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('menu-images', 'menu-images', TRUE, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET public = TRUE, file_size_limit = 5242880,
allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'];

DROP POLICY IF EXISTS "menu images are publicly readable" ON storage.objects;
CREATE POLICY "menu images are publicly readable" ON storage.objects FOR SELECT USING (bucket_id = 'menu-images');

DROP POLICY IF EXISTS "CoRei staff can upload menu images" ON storage.objects;
CREATE POLICY "CoRei staff can upload menu images" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'menu-images');

DROP POLICY IF EXISTS "CoRei staff can update menu images" ON storage.objects;
CREATE POLICY "CoRei staff can update menu images" ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'menu-images') WITH CHECK (bucket_id = 'menu-images');

DROP POLICY IF EXISTS "CoRei staff can delete menu images" ON storage.objects;
CREATE POLICY "CoRei staff can delete menu images" ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'menu-images');

CREATE OR REPLACE FUNCTION public.update_menu_variant_image(
  p_variant_id TEXT,
  p_image_url TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cafe_id UUID;
BEGIN
  SELECT id INTO v_cafe_id FROM public.cafes WHERE slug = 'corei';
  IF NOT public.is_cafe_member(v_cafe_id) THEN
    RAISE EXCEPTION 'Akses ditolak: hanya staf CoRei yang dapat mengubah foto menu.' USING ERRCODE = '42501';
  END IF;

  UPDATE public.menu_variants
  SET image_url = NULLIF(trim(COALESCE(p_image_url, '')), '')
  WHERE id = p_variant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Varian menu tidak ditemukan.' USING ERRCODE = '22023';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_menu_variant_image(TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_all_menu_variants()
RETURNS JSONB
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id, 'product_name', product_name, 'category', category,
    'variant_label', variant_label, 'price', price, 'compare_price', compare_price,
    'has_temperature', has_temperature, 'has_ice', has_ice, 'has_sweetness', has_sweetness,
    'is_active', is_active, 'tag', tag, 'image_url', image_url
  ) ORDER BY product_name, variant_label), '[]'::jsonb)
  FROM public.menu_variants;
$$;

GRANT EXECUTE ON FUNCTION public.get_all_menu_variants() TO authenticated;
