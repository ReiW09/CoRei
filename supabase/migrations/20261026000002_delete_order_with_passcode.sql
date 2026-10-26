-- Migrasi: Fungsi Hapus Pesanan Kasir dengan Kode Keamanan (PIN / Passcode Khusus)
-- Jalankan query ini di Supabase SQL Editor

CREATE OR REPLACE FUNCTION public.delete_customer_order(
    p_public_id TEXT,
    p_passcode TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    order_cafe_id UUID;
    -- Ganti atau atur PIN khusus pemilik kafe di sini (default: '8899')
    v_correct_passcode CONSTANT TEXT := '8899';
BEGIN
    -- 1. Validasi Kode Keamanan Khusus
    IF p_passcode IS NULL OR trim(p_passcode) <> v_correct_passcode THEN
        RAISE EXCEPTION 'Kode khusus salah! Akses hapus data ditolak.' USING ERRCODE = '42501';
    END IF;

    -- 2. Dapatkan Cafe ID dari pesanan
    SELECT cafe_id INTO order_cafe_id
    FROM public.orders
    WHERE public_id = p_public_id;

    -- 3. Pastikan staf yang login terdaftar di cafe_memberships
    IF NOT FOUND OR NOT public.is_cafe_member(order_cafe_id) THEN
        RAISE EXCEPTION 'Pesanan tidak ditemukan atau akses ditolak.' USING ERRCODE = '42501';
    END IF;

    -- 4. Hapus data pesanan
    DELETE FROM public.orders
    WHERE public_id = p_public_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_customer_order(TEXT, TEXT) TO authenticated;

