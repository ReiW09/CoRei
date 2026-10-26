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

Untuk nomor antrean yang urut dan reset setiap **awal bulan** (bukan harian), jalankan juga query:
`supabase/migrations/20261026000001_monthly_queue_number.sql`

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

## 5. Siapkan APK Android pelanggan

APK Android membungkus halaman pelanggan saja; halaman kasir tidak dimasukkan.
Pesanan dan pembaruan status tetap memerlukan koneksi internet. Formulir pesanan
meminta nama dan nomor HP. Nomor HP dan nama tersimpan hanya di perangkat
pelanggan untuk pengisian otomatis berikutnya; nomor HP tidak dikirim ke
database CoRei dan tidak diverifikasi sebagai identitas/akun. Nama pesanan tetap
dikirim ke kasir. Pelanggan dapat menonaktifkan penyimpanan lokal melalui kotak
centang pada formulir.

1. Pasang Node.js 22 atau lebih baru, Java JDK 21, dan Android Studio dengan
   Android SDK yang direkomendasikan.
2. Dari folder proyek, jalankan `npm install`.
3. Jalankan `npm run android:apk`. Gradle menghasilkan APK debug di
   `android/app/build/outputs/apk/debug/app-debug.apk`.
4. Salin APK ke ponsel Android untuk instalasi. Android mungkin meminta izin
   memasang aplikasi dari sumber ini.

Jika memakai Android Studio, jalankan `npm run android:sync`, lalu
`npm run android:open`. Untuk dibagikan di luar pengujian, buat APK rilis yang
ditandatangani dengan signing key milik pemilik aplikasi; jangan membagikan
debug APK sebagai rilis publik.

## 6. Siapkan APK Android kasir

APK kasir adalah aplikasi terpisah dari APK pelanggan, sehingga keduanya dapat
dipasang bersamaan. Aplikasi kasir hanya untuk staf CoRei yang akunnya sudah
terdaftar di `cafe_memberships`.

1. Buat proyek Android kasir sekali dengan `npm run android:add:cashier`.
2. Jalankan `npm run android:apk:cashier`. Gradle menghasilkan APK di
   `android-kasir/app/build/outputs/apk/debug/app-debug.apk`.
3. Salin APK ke HP staf untuk dipasang. Login memakai email dan password staf
   CoRei. Jangan membagikan APK debug sebagai rilis publik.
