/**
 * =========================================================================
 * GOOGLE APPS SCRIPT: CoRei - Pencatatan Pesanan ke Google Sheets
 * =========================================================================
 * 
 * Panduan Pemasangan:
 * 1. Buka Google Sheets Anda (tempat mencatat penjualan CoRei).
 * 2. Klik menu: Ekstensi (Extensions) > Apps Script.
 * 3. Hapus kode bawaan, lalu tempelkan seluruh kode ini.
 * 4. Klik "Simpan" (ikon disket).
 * 5. Klik tombol biru "Terapkan" (Deploy) di kanan atas > "Penerapan baru" (New deployment).
 * 6. Pilih jenis: "Aplikasi Web" (Web app).
 * 7. Konfigurasi:
 *    - Deskripsi: CoRei Order Logger v2
 *    - Jalankan sebagai (Execute as): Saya (Me / email Anda)
 *    - Siapa yang memiliki akses (Who has access): Siapa saja (Anyone / Termasuk anonim)
 * 8. Klik "Terapkan" (Deploy) dan salin URL Web App yang berakhiran /exec.
 * 9. Tempelkan URL tersebut ke variabel SHEET_URL di aplikasi CoRei.
 */

function doPost(e) {
  var lock = LockService.getScriptLock();
  // Kunci script selama 10 detik agar tidak ada bentrokan saat pesanan masuk berdekatan
  try {
    lock.waitLock(10000);
  } catch (lockErr) {
    return ContentService.createTextOutput(JSON.stringify({ status: "error", message: "Server sibuk, coba lagi." }))
      .setMimeType(ContentService.MimeType.JSON);
  }

  try {
    var raw = e.parameter.data || (e.postData && e.postData.contents);
    if (!raw) {
      return ContentService.createTextOutput(JSON.stringify({ status: "empty" }))
        .setMimeType(ContentService.MimeType.JSON);
    }

    var data = typeof raw === "string" ? JSON.parse(raw) : raw;
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    
    // Cari tab 'Penjualan', jika belum ada buat otomatis
    var sheet = ss.getSheetByName("Penjualan");
    if (!sheet) {
      sheet = ss.insertSheet("Penjualan");
    }

    // Inisialisasi Header jika sheet masih kosong
    if (sheet.getLastRow() === 0) {
      sheet.appendRow([
        "Waktu",
        "No. Antrean",
        "Nama Pelanggan",
        "Nomor Meja",
        "Metode Pembayaran",
        "Menu",
        "Ukuran / Varian",
        "Jumlah (Qty)",
        "Harga Satuan",
        "Subtotal",
        "Suhu",
        "Es",
        "Manis",
        "Catatan",
        "Total Pesanan"
      ]);
      // Format baris header
      sheet.getRange(1, 1, 1, 15).setFontWeight("bold").setBackground("#EEF3F0");
    }

    var now = new Date();
    var timeFormatted = Utilities.formatDate(now, "Asia/Jakarta", "yyyy-MM-dd HH:mm:ss");

    var customerName = cleanCell(data.nama || "-");
    var paymentMethod = cleanCell(data.bayar || "-");
    var tableLabel = cleanCell(data.meja || "-");
    var queueNum = cleanCell(data.antrean || "-");
    var totalOrder = Number(data.total || 0);

    var items = data.items || [];

    // Jika items tidak memiliki total dari luar, hitung total dari subtotal items
    if (!totalOrder) {
      totalOrder = items.reduce(function(acc, it) {
        return acc + (Number(it.qty || 1) * Number(it.price || 0));
      }, 0);
    }

    // Catat tiap item sebagai satu baris transaksi
    items.forEach(function(item) {
      var qty = Number(item.qty || 1);
      var price = Number(item.price || 0);
      var subtotal = qty * price;

      sheet.appendRow([
        timeFormatted,
        queueNum,
        customerName,
        tableLabel,
        paymentMethod,
        cleanCell(item.menu || item.productName || "-"),
        cleanCell(item.size || item.variantLabel || "-"),
        qty,
        price,
        subtotal,
        cleanCell(item.temp || "-"),
        cleanCell(item.ice || "-"),
        cleanCell(item.sweet || "-"),
        cleanCell(item.note || "-"),
        totalOrder
      ]);
    });

    return ContentService.createTextOutput(JSON.stringify({ status: "success", count: items.length }))
      .setMimeType(ContentService.MimeType.JSON);

  } catch (err) {
    return ContentService.createTextOutput(JSON.stringify({ status: "error", error: err.toString() }))
      .setMimeType(ContentService.MimeType.JSON);
  } finally {
    lock.releaseLock();
  }
}

/**
 * Sanitasi terhadap Formula Injection (CSV/Sheets Formula Injection)
 * Cegah teks yang diawali dengan = + - @ agar tidak dieksekusi sebagai formula
 */
function cleanCell(val) {
  if (val === null || val === undefined) return "-";
  var s = String(val).trim();
  if (/^[=\+\-@]/.test(s)) {
    return "'" + s;
  }
  return s;
}

