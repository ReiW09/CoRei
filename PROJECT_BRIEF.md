# PROJECT BRIEF: CoRei Platform (menu digital + pemesanan + kasir untuk banyak kafe)

> Tempel seluruh dokumen ini ke agent Antigravity. Simpan juga sebagai `PROJECT_BRIEF.md` di root proyek supaya agent bisa merujuknya kembali.

---

## 0. Cara kamu (agent) bekerja

1. **Jangan langsung menulis kode.** Baca dokumen ini sampai selesai, lalu keluarkan **rencana kerja** (artifact/plan) berisi: arsitektur final, struktur folder, daftar fase, dan **maksimal 10 pertanyaan** yang masih ambigu. Tunggu jawabanku sebelum mulai.
2. Kerjakan **per fase** (Bagian 9). Setelah satu fase selesai, jalankan semua tes dan checklist penerimaan fase itu, laporkan hasilnya, lalu **berhenti dan minta persetujuan** sebelum fase berikutnya.
3. Commit kecil dan sering, dengan pesan commit yang jelas (Conventional Commits).
4. **Jangan pernah** menaruh rahasia (API key, service role key, kunci webhook) di kode klien atau di repository. Gunakan environment variable dan sediakan `.env.example`.
5. **Minta izin dulu** sebelum memakai layanan berbayar, menambah dependency besar, atau mengubah keputusan arsitektur.
6. Semua teks yang dilihat pengguna memakai **Bahasa Indonesia** yang santai dan sopan. Nama variabel, fungsi, tabel, dan komentar kode memakai bahasa Inggris.
7. Tulis dokumentasi dalam Bahasa Indonesia yang bisa diikuti orang non-teknis (README, panduan pemasangan, panduan pemilik kafe).

---

## 1. Latar belakang

Aku punya kafe bernama **CoRei**. Saat ini sistemnya berupa **satu file `index.html` statis** (di GitHub Pages) yang:
- menampilkan menu, dibuka lewat scan QR di meja;
- membiarkan pelanggan memilih menu, ukuran, opsi, catatan, lalu mengirim pesanan ke **WhatsApp** (link `wa.me` dengan teks terisi);
- mencatat pesanan ke **Google Sheets** lewat Google Apps Script;
- bisa dipasang sebagai PWA.

Aku ingin mengembangkannya menjadi **platform yang canggih dan bisa dipakai banyak kafe**, dengan tiga tingkat yang dikerjakan berurutan:

1. **Tingkat 1** sistem lengkap untuk satu kafe (kasir, menu dinamis, pembayaran, laporan).
2. **Tingkat 2** template yang bisa dipakai kafe lain (semua pengaturan lewat dashboard, tanpa edit kode).
3. **Tingkat 3** platform multi-kafe (pendaftaran mandiri, langganan, panel admin).

File lama akan kuletakkan di `legacy/index.html` sebagai **acuan perilaku**. Baca dulu file itu. File itu berisi gambar QRIS yang di-embed base64; **jangan cetak isi base64 ke log atau chat**, cukup ekstrak jadi aset terpisah.

---

## 2. Perilaku yang WAJIB dipertahankan dari versi lama

Ini adalah kriteria penerimaan minimum. Semua harus tetap bekerja di sistem baru.

**Menu CoRei (data awal / seed)**

| Menu | Cup | Botol 250 ml | Catatan |
|---|---|---|---|
| Americano | Rp10.000 | Rp13.000 | Espresso dengan air, panas atau dingin |
| White Latte | Rp12.000 | Rp15.000 | Espresso dengan susu, lembut dan creamy |
| Aren | Rp13.000 (coret Rp15.000) | Rp18.000 (coret Rp20.000) | Kopi susu dengan gula aren, label **Promo** |

**Aturan opsi**
- **Americano**: ukuran Cup punya pilihan **Suhu** (Ice / Hot, default Ice). Pilihan **Es** (Less ice, Normal ice, More ice; default Normal ice) hanya tampil kalau Suhu = Ice. Americano **tidak** punya pilihan manis. Americano Botol tidak punya opsi apa pun.
- **White Latte & Aren**: **Manis** (Less sweet, Normal sweet, Sweet; default Normal sweet) untuk Cup dan Botol. **Es** hanya untuk Cup. Botol tidak punya pilihan es.
- Sistem baru harus mengekspresikan aturan ini sebagai **data** (option group per varian dengan aturan tampil bersyarat), bukan hard-code.

**Alur pelanggan**
- Tiap varian punya tombol **Tambah**, stepper jumlah (1 sampai 20), dan kolom **catatan** (maks 80 karakter).
- Bar bawah menampilkan jumlah item dan total, dan menautkan ke ringkasan pesanan.
- **Nama pelanggan wajib** (spasi saja dianggap kosong). Pesan error merah: "Nama wajib diisi dulu ya."
- **Cara bayar wajib dipilih**: **QRIS** atau **Cash**. Error: "Pilih cara bayar dulu ya (QRIS atau Cash)."
- Memilih QRIS menampilkan gambar QRIS; memilih Cash menampilkan "Bayar tunai langsung ke kasir."
- Tidak ada input nomor meja (opsional lewat pengaturan kafe, default mati).
- Setelah kirim, tampil layar penuh **"Terima kasih, {nama}!"** dengan instruksi bayar sesuai pilihan, dan tombol **Pesan lagi** yang mengosongkan keranjang. Halaman tidak bisa menutup dirinya sendiri; jangan mencoba `window.close()`.
- Footer: "Harga belum termasuk pajak. Info lebih lanjut bisa langsung ke WA" (WA = tautan ke nomor kafe).
- Kartu QR "Scan untuk buka menu ini" **tersembunyi** untuk pelanggan, dan hanya muncul kalau URL memuat `?qr`.
- PWA: bisa dipasang ke layar utama (tombol "Pasang di layar utama" di Android, manifest + ikon + service worker).
- Mode terang dan gelap otomatis, aman untuk layar berponi (safe-area), responsif.

**Format pesan WhatsApp (pertahankan, sebagai opsi notifikasi)**
```
Halo CoRei, saya mau pesan:
Nama: Budi
Pembayaran: QRIS

1. Aren (Cup, Less sweet, More ice) x2 - Rp26.000
   Catatan: gula aren dipisah
2. Americano (Botol 250 ml) x1 - Rp13.000

Total: Rp39.000
```
Di sistem baru, WhatsApp menjadi **opsi per kafe** (notifikasi/konfirmasi ke nomor kafe), bukan satu-satunya jalur pesanan.

---

## 3. Tujuan produk

- **Pelanggan**: scan, pilih, bayar, dapat nomor antrean, melihat status pesanan, tanpa instal aplikasi dan tanpa login.
- **Kasir/dapur**: melihat pesanan masuk secara langsung (realtime), mengubah status, menandai lunas, mencetak atau menampilkan struk.
- **Pemilik**: mengatur menu, harga, promo, stok, opsi, tampilan (logo, warna, foto), staf, dan melihat laporan.
- **Platform (Tingkat 3)**: pemilik kafe lain daftar sendiri, memasang kafenya dalam kurang dari 15 menit, dan berlangganan.

Prinsip: **cepat di HP murah dan sinyal lemah**, mudah dipakai orang awam, aman untuk uang dan data pribadi.

---

## 4. Tech stack yang diusulkan (boleh diubah, tapi jelaskan alasannya di rencana)

- **Frontend & backend**: Next.js (App Router) + TypeScript (strict) + Tailwind CSS.
- **Database, Auth, Realtime, Storage**: Supabase (PostgreSQL + Row Level Security).
- **Hosting**: Vercel atau Cloudflare Pages (HTTPS otomatis).
- **Pembayaran**: antarmuka `PaymentProvider` yang bisa diganti. Implementasi pertama: **Midtrans atau Xendit** untuk **QRIS dinamis** (nominal otomatis) + webhook. Sediakan juga provider `manual` (QRIS statis + konfirmasi kasir) sebagai default agar tetap jalan tanpa penyedia.
- **Validasi**: Zod di semua batas (API, form).
- **Tes**: Vitest (unit), Playwright (end-to-end), tes RLS di database.
- **PWA**: manifest dinamis per kafe + service worker (Workbox atau `next-pwa` yang aktif dirawat).
- **Anti-spam**: Cloudflare Turnstile atau hCaptcha pada pembuatan pesanan + rate limiting per IP dan per kafe.
- **Pelaporan error**: Sentry (opsional, tanyakan dulu).

Hindari ketergantungan yang berat atau tidak terawat. Jelaskan tiap library yang kamu tambahkan.

---

## 5. Arsitektur & model data

**Multi-tenant sejak awal.** Setiap data bisnis punya `cafe_id` dan dilindungi **RLS**. CoRei adalah tenant pertama (seed).

**URL**
- Pelanggan: `/{cafe_slug}` (menu), `/{cafe_slug}/pesanan/{order_public_id}` (status), mode meja opsional `?meja=7`.
- Dashboard: `/dashboard/*` (pemilik/kasir), `/kasir` (layar kasir/dapur layar penuh).
- Platform: `/` (landing), `/daftar`, `/masuk`, `/admin` (super admin).
- Subdomain per kafe (`{slug}.domainmu.id`) disiapkan di fase akhir, tapi desain routing jangan menghalanginya.

**Tabel utama (minimal)**
- `cafes` (id, slug unik, name, logo_url, theme jsonb, whatsapp_number, settings jsonb, status, plan, created_at)
- `memberships` (user_id, cafe_id, role: owner | manager | cashier)
- `categories`, `products` (name, description, image_url, tag, is_active, sort)
- `variants` (product_id, label, price, compare_at_price, is_active)
- `option_groups` (cafe_id, name, selection: single | multi, required, min, max)
- `options` (group_id, label, price_delta, is_default, sort)
- `variant_option_groups` (variant_id, group_id, `visible_when` jsonb) — aturan tampil bersyarat, mis. grup "Es" tampil hanya jika opsi "Suhu" = "Ice"
- `orders` (id, public_id acak, cafe_id, queue_number per hari, customer_name, table_label, payment_method, payment_status, status, subtotal, discount, total, note, created_at)
- `order_items` (order_id, product_name, variant_label, unit_price, qty, note, selected_options jsonb) — **simpan snapshot** nama dan harga saat dipesan
- `payments` (order_id, provider, provider_ref, amount, status, raw_event jsonb, paid_at)
- `promos` (cafe_id, type, value, starts_at, ends_at, rules jsonb)
- `stock_flags` (variant_id, is_sold_out) — habis cepat, tanpa inventori kompleks dulu
- `audit_logs` (cafe_id, actor_id, action, entity, entity_id, diff jsonb, at)
- `subscriptions` (cafe_id, plan, status, current_period_end, provider_ref) — Tingkat 3

**Status pesanan**: `baru` → `diproses` → `siap` → `selesai` | `batal`. **Status bayar**: `belum_bayar` → `lunas` | `gagal` | `kedaluwarsa`.

---

## 6. Keamanan (WAJIB, bukan opsional)

1. **Harga dihitung di server.** Klien hanya mengirim `variant_id`, `option_ids`, `qty`, `note`. Server mengambil harga dari database, memvalidasi aturan opsi (wajib, tampil bersyarat, batas jumlah), lalu menghitung total. Tolak data yang tidak cocok.
2. **RLS** di semua tabel. Pelanggan anonim hanya boleh: membaca menu aktif kafe, membuat pesanan lewat endpoint server, membaca status **pesanannya sendiri** lewat `public_id` yang acak (panjang, tak bisa ditebak). Tidak ada pembacaan daftar pesanan oleh anonim.
3. **Auth sungguhan** untuk pemilik dan staf (email + magic link atau OAuth). Tidak ada PIN statis di klien. Kasir boleh memakai PIN **di atas** sesi login perangkat yang sudah terdaftar.
4. **Webhook pembayaran**: verifikasi tanda tangan, idempotensi (event yang sama tidak diproses dua kali), jangan percaya status dari klien.
5. **Rate limiting** dan captcha pada pembuatan pesanan. Batasi ukuran payload dan jumlah item.
6. **Sanitasi** semua teks (nama, catatan) saat ditampilkan agar bebas XSS; pasang **CSP** ketat dan header keamanan. Cegah formula injection pada ekspor CSV/Sheets (awali sel yang diawali `= + - @`).
7. **Upload gambar**: batasi tipe dan ukuran, kompres otomatis, simpan di storage dengan path per kafe.
8. **Pemisahan data antar kafe** harus dibuktikan dengan **tes otomatis** (pengguna kafe A tidak bisa membaca atau mengubah data kafe B).
9. **Audit log** untuk perubahan harga, menu, status bayar, dan peran staf.
10. Jangan menyimpan data kartu. Pembayaran sepenuhnya lewat penyedia.

**Data pribadi (UU Pelindungan Data Pribadi)**: kumpulkan seminimal mungkin (nama panggilan saja untuk pelanggan), sediakan halaman Kebijakan Privasi dan Syarat Layanan (draf, tandai bahwa perlu ditinjau ahli hukum), kebijakan retensi (mis. anonimkan nama pelanggan setelah 90 hari, bisa diatur), serta fitur hapus/ekspor data kafe.

---

## 7. Fitur per tingkat

### Tingkat 1 — sistem lengkap untuk satu kafe (CoRei)
1. **Menu dinamis dari database**: kategori, produk, varian, foto, label (Promo, Favorit), harga coret, stok habis. Perubahan tampil langsung tanpa deploy.
2. **Option groups** fleksibel (Manis, Es, Suhu, topping) dengan aturan tampil bersyarat dan harga tambahan.
3. **Halaman kasir/dapur** realtime: kartu pesanan baru dengan bunyi notifikasi, filter status, tombol ubah status, tombol **Tandai lunas**, pencarian, layar penuh yang nyaman di tablet.
4. **Nomor antrean** harian dan **halaman status pesanan** untuk pelanggan (realtime, dengan estimasi sederhana).
5. **Pembayaran**: pilihan QRIS / Cash. QRIS dinamis lewat `PaymentProvider` (nominal otomatis, status lunas otomatis via webhook), dengan fallback QRIS statis + konfirmasi kasir.
6. **Struk digital** (halaman publik + tombol cetak/bagikan) dan struk thermal opsional via cetak browser.
7. **Promo**: diskon persen/nominal, jadwal tayang, harga coret otomatis, promo per varian.
8. **Laporan**: omzet harian/mingguan/bulanan, menu terlaris, jam ramai, rasio QRIS vs Cash, pesanan batal. Ekspor **CSV** dan opsi sinkron ke **Google Sheets** (satu arah) bagi yang masih ingin memakai spreadsheet.
9. **Impor data lama**: skrip untuk mengimpor riwayat dari Google Sheets (tab `Penjualan`) ke database.
10. **Notifikasi WhatsApp opsional**: tombol "Kirim konfirmasi ke WhatsApp kafe" memakai format pesan di Bagian 2.
11. **PWA** pelanggan dan **PWA kasir** (bisa dipasang, tahan sinyal lemah, halaman menu bisa dibuka dari cache).
12. **Tampilan**: logo, warna merek, foto, mode terang/gelap, aksesibilitas (kontras, fokus keyboard, label ARIA).

### Tingkat 2 — template yang bisa dipakai kafe lain
1. Semua yang dulu hard-code (nama, WhatsApp, QRIS, warna, logo, teks footer, kebijakan nama wajib, nomor meja opsional) pindah ke **pengaturan kafe** yang diedit di dashboard.
2. **Wizard onboarding** 5 langkah: profil kafe → menu (tambah manual atau **impor CSV/Excel**) → opsi → pembayaran → cetak QR.
3. **Generator QR** dan **kartu meja siap cetak** (PDF A6/A5, dengan logo dan nama kafe), QR per meja opsional.
4. **Tema**: beberapa preset desain + warna kustom + pilihan font aman.
5. **Template menu bawaan** (kafe, warung makan, bubble tea) untuk mempercepat mulai.
6. Mode **self-host**: panduan pemasangan satu kafe di akun Supabase + Vercel milik sendiri (`docs/SELF_HOST.md`), tombol deploy sekali klik bila memungkinkan.

### Tingkat 3 — platform multi-kafe
1. **Pendaftaran mandiri** (`/daftar`), verifikasi email, pembuatan kafe otomatis dengan slug unik dan aman (daftar slug terlarang).
2. **Peran dan undangan staf** (owner, manager, cashier) lewat email.
3. **Paket langganan**: Gratis (batas pesanan/bulan dan produk) dan Pro; penagihan berulang lewat penyedia pembayaran, status langganan memengaruhi fitur (feature flag), masa tenggang bila gagal bayar.
4. **Panel super admin**: daftar kafe, status, penggunaan, nonaktifkan kafe, impersonasi **dengan audit log**, tinjauan laporan penyalahgunaan.
5. **Domain kustom/subdomain** per kafe.
6. **Observabilitas**: log terstruktur, pelaporan error, dasbor kesehatan (antrean webhook gagal, latensi), pencadangan database terjadwal dan **prosedur pemulihan yang diuji**.
7. **Halaman pemasaran** (landing, harga, FAQ), Kebijakan Privasi, Syarat Layanan.
8. **Multi-bahasa** (Indonesia default, Inggris) dengan struktur i18n sejak awal.

---

## 8. Persyaratan non-fungsional

- **Performa**: halaman menu pelanggan LCP < 2,5 dtk di Android kelas menengah dengan 4G; JS awal sekecil mungkin; gambar dikompres, ukuran responsif, lazy-load; font di-self-host atau `font-display: swap`.
- **Offline/sinyal lemah**: menu terakhir bisa dibuka dari cache; pembuatan pesanan menampilkan status jelas ("mengirim", "gagal, coba lagi") dan **tidak membuat pesanan ganda** (idempotency key).
- **Aksesibilitas**: WCAG 2.1 AA, target sentuh minimal 44px, bisa dipakai dengan pembaca layar.
- **Kompatibilitas**: Android Chrome, iOS Safari 15+, dan tablet untuk kasir.
- **Keandalan**: tangani webhook ganda dan tertunda; pesanan tidak boleh hilang; pembulatan harga konsisten (simpan integer rupiah, tanpa float).
- **Zona waktu**: simpan UTC, tampilkan sesuai zona kafe (default Asia/Jakarta); nomor antrean reset per hari menurut zona kafe.
- **Kualitas kode**: TypeScript strict, ESLint + Prettier, tidak ada `any` tanpa alasan, komponen kecil dan teruji, tidak ada kode mati.

---

## 9. Fase kerja dan kriteria penerimaan

**Fase 0 — Fondasi**
- Inisialisasi repo, struktur folder, lint/format, CI (lint, tipe, tes), `.env.example`, README awal.
- Skema database + migrasi + RLS + seed CoRei (Bagian 2).
- ✅ Penerimaan: `npm run dev` jalan, migrasi bersih dari nol, tes RLS lulus, seed menghasilkan menu CoRei persis seperti tabel Bagian 2.

**Fase 1 — Halaman pelanggan setara versi lama**
- Menu dari database, varian, opsi bersyarat, catatan, keranjang, validasi nama dan cara bayar, API pembuatan pesanan (harga dihitung server), layar terima kasih, PWA, mode gelap.
- ✅ Penerimaan: semua poin Bagian 2 lolos lewat tes Playwright; manipulasi harga dari klien ditolak server; satu pesanan tidak pernah tercatat dua kali.

**Fase 2 — Kasir dan operasional (Tingkat 1)**
- Auth staf, layar kasir realtime, status pesanan, tandai lunas, nomor antrean, halaman status pelanggan, struk.
- ✅ Penerimaan: pesanan dari HP pelanggan muncul di layar kasir dalam < 2 dtk; perubahan status terlihat di HP pelanggan; semua aksi tercatat di audit log.

**Fase 3 — Pembayaran, promo, laporan (Tingkat 1)**
- `PaymentProvider` + provider `manual` dan satu penyedia QRIS dinamis (mode sandbox), webhook idempoten, promo, laporan, ekspor CSV, sinkron Sheets opsional, impor riwayat lama.
- ✅ Penerimaan: pembayaran sandbox menandai pesanan lunas otomatis; webhook ganda tidak mengubah apa pun; angka laporan cocok dengan data pesanan dalam tes.

**Fase 4 — Template (Tingkat 2)**
- Pengaturan kafe di dashboard, wizard onboarding, impor menu CSV, generator QR dan kartu meja PDF, tema, `SELF_HOST.md`.
- ✅ Penerimaan: orang non-teknis bisa membuat kafe baru dari nol sampai QR tercetak dalam < 15 menit mengikuti panduan; tidak ada nilai CoRei yang tersisa di kode.

**Fase 5 — Platform (Tingkat 3)**
- Pendaftaran mandiri, undangan staf, langganan, super admin, subdomain, observabilitas, backup, halaman legal, i18n.
- ✅ Penerimaan: tes isolasi antar kafe lulus; kafe yang tidak membayar turun ke paket Gratis tanpa kehilangan data; prosedur pemulihan backup terdokumentasi dan sudah diuji.

**Fase 6 — Pengerasan dan peluncuran**
- Uji beban sederhana, audit aksesibilitas, tinjauan keamanan (checklist OWASP), uji pada HP Android murah dan iPhone, dokumentasi akhir, rencana peluncuran bertahap (CoRei dulu, lalu 3 sampai 5 kafe percobaan).

---

## 10. Hal yang harus kamu tanyakan padaku sebelum mulai

Kumpulkan dalam satu daftar, antara lain: pilihan penyedia QRIS dinamis dan apakah aku sudah punya akunnya; domain yang akan dipakai; apakah Supabase/Vercel dibuat di akunku; skema harga paket Pro; apakah nomor meja perlu aktif untuk CoRei; label opsi manis yang final (Less sweet, Normal sweet, Sweet); kebijakan retensi data; apakah perlu bahasa Inggris sejak awal.

---

## 11. Larangan

- Jangan menghitung atau mempercayai harga dari klien.
- Jangan menaruh kunci rahasia di klien atau repository.
- Jangan membuat tabel tanpa RLS.
- Jangan menyimpan data kartu atau data pribadi yang tidak perlu.
- Jangan menyalin gambar, logo, atau teks dari internet tanpa hak; gunakan aset milikku atau placeholder.
- Jangan melewati tes yang gagal agar fase terlihat selesai.
- Jangan mengklaim sebuah fitur selesai sebelum diuji; laporkan jujur apa yang belum berfungsi atau belum bisa diuji.

---

## 12. Format laporan di akhir setiap fase

1. Ringkasan apa yang dibuat (maksimal 10 baris).
2. Hasil tes (jumlah lulus/gagal) dan cara menjalankannya.
3. Cara mencoba secara manual (langkah demi langkah).
4. Masalah yang diketahui dan keputusan yang perlu kuambil.
5. Perubahan pada variabel lingkungan atau akun/layanan yang perlu kusiapkan.

