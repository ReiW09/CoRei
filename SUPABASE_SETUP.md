# Menyiapkan pesanan realtime CoRei

Halaman pelanggan ada di `index.html`; halaman staf terpisah ada di `kasir.html`.
Status pesanan dikirim realtime melalui Supabase. Pelanggan melihat pemberitahuan
di halaman status selama halaman tersebut masih terbuka.

## 1. Isi konfigurasi publik

Buka `supabase-config.js` dan isi Project URL serta publishable/anon key dari
Supabase **tanpa** service-role key:

```js
window.COREI_SUPABASE_URL = "https://PROJECT-REF.supabase.co";
window.COREI_SUPABASE_ANON_KEY = "PUBLIC_ANON_OR_PUBLISHABLE_KEY";
```

URL dan anon/publishable key memang digunakan di browser. Keamanan data pesanan
tetap ditegakkan oleh Row Level Security pada migrasi. Jangan pernah menaruh
service-role key di file ini atau file yang dipublikasikan.

## 2. Buat tabel, kebijakan, dan data menu

Di Supabase Dashboard, buka **SQL Editor → New query**, lalu jalankan sekali:

`supabase/migrations/20261020000001_orders_realtime.sql`

Migrasi membuat kafe CoRei, enam varian menu, tabel pesanan, fungsi transaksi,
akses realtime, dan kebijakan RLS. Jika ada error, hentikan setup dan periksa
pesan error sebelum mencoba query lain.

## 3. Buat akun staf

1. Di **Authentication → Users**, buat pengguna untuk kasir/dapur dengan email
   dan password.
2. Salin UUID pengguna tersebut.
3. Jalankan query berikut di SQL Editor dengan UUID akun staf:

```sql
INSERT INTO public.cafe_memberships (cafe_id, user_id, role)
SELECT id, 'UUID-AKUN-STAF', 'owner'
FROM public.cafes
WHERE slug = 'corei'
ON CONFLICT (cafe_id, user_id)
DO UPDATE SET role = EXCLUDED.role;
```

Simpan akun staf secara privat. Pengguna yang belum terdaftar di
`cafe_memberships` tidak dapat membaca atau mengubah pesanan.

## 4. Jalankan dan uji

Layani folder proyek melalui HTTPS atau server lokal, lalu buka:

- Pelanggan: `index.html`
- Kasir/dapur: `kasir.html`

Buat pesanan pelanggan, masuk sebagai staf, lalu ubah status **Baru → Diproses
→ Siap Diambil**. Halaman pelanggan untuk pesanan tersebut akan menampilkan
pemberitahuan status baru, termasuk “Pesananmu sudah siap diambil di kasir!”.
URL setelah checkout mengandung token pesanan acak; perlakukan URL itu sebagai
tautan privat pelanggan tersebut.

Halaman kasir memerlukan koneksi internet dan login. Pemberitahuan pelanggan
berjalan realtime saat halaman status terbuka. Push notification ketika browser
ditutup belum disiapkan.
