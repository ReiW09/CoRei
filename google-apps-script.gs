/**
 * Google Apps Script untuk CoRei.
 * Pasang sebagai Web App pada spreadsheet yang menerima pesanan dan membership,
 * lalu gunakan URL deployment /exec pada SHEET_URL.
 */

var SPREADSHEET_ID = "12BTjIwuv0e8ksWBALlGfJxwocbfocOhQs6ud4CDEg8E";
var MEMBERSHIP_SHEET = "Membership";
var ORDER_SHEET = "Penjualan";

function doPost(e) {
  var lock = LockService.getScriptLock();
  try {
    try { lock.waitLock(10000); }
    catch (lockErr) {
      return jsonResponse({ status: "error", message: "Server sibuk, coba lagi." });
    }

    var raw = e.parameter.data || (e.postData && e.postData.contents);
    if (!raw) return jsonResponse({ status: "empty" });

    var data = typeof raw === "string" ? JSON.parse(raw) : raw;
    var ss = getTargetSpreadsheet(data);

    if (data.action === "upsert_membership" || data.sheet === MEMBERSHIP_SHEET) {
      return logMembership(ss, data);
    }

    return logOrder(ss, data);
  } catch (err) {
    return jsonResponse({ status: "error", error: err.toString() });
  } finally {
    lock.releaseLock();
  }
}

function getTargetSpreadsheet(data) {
  var spreadsheetId = cleanValue(data.spreadsheetId || SPREADSHEET_ID);
  return SpreadsheetApp.openById(spreadsheetId);
}

function logMembership(ss, data) {
  var sheet = ss.getSheetByName(MEMBERSHIP_SHEET) || ss.insertSheet(MEMBERSHIP_SHEET);
  if (sheet.getLastRow() === 0) {
    sheet.appendRow(["Nama", "Password", "Poin", "Diperbarui"]);
    sheet.getRange(1, 1, 1, 4).setFontWeight("bold").setBackground("#EEF3F0");
  }

  var name = cleanCell(data.nama || data.name || "-");
  var pin = cleanCell(data.password || data.pin || "-");
  var points = Math.max(0, Number(data.points || data.point || 0));
  var updatedAt = cleanCell(data.updatedAt || new Date().toISOString());
  var values = sheet.getDataRange().getValues();

  for (var i = 1; i < values.length; i++) {
    if (String(values[i][0]).trim().toLowerCase() === String(name).trim().toLowerCase()) {
      sheet.getRange(i + 1, 1, 1, 4).setValues([[name, pin, points, updatedAt]]);
      return jsonResponse({ status: "success", action: "membership_updated", name: name });
    }
  }

  sheet.appendRow([name, pin, points, updatedAt]);
  return jsonResponse({ status: "success", action: "membership_created", name: name });
}

function logOrder(ss, data) {
  var sheet = ss.getSheetByName(ORDER_SHEET) || ss.insertSheet(ORDER_SHEET);
  if (sheet.getLastRow() === 0) {
    sheet.appendRow([
      "Waktu", "No. Antrean", "Nama Pelanggan", "Nomor Meja", "Metode Pembayaran",
      "Menu", "Ukuran / Varian", "Jumlah (Qty)", "Harga Satuan", "Subtotal",
      "Suhu", "Es", "Manis", "Catatan", "Total Pesanan"
    ]);
    sheet.getRange(1, 1, 1, 15).setFontWeight("bold").setBackground("#EEF3F0");
  }

  var now = Utilities.formatDate(new Date(), "Asia/Jakarta", "yyyy-MM-dd HH:mm:ss");
  var customerName = cleanCell(data.nama || "-");
  var paymentMethod = cleanCell(data.bayar || "-");
  var tableLabel = cleanCell(data.meja || "-");
  var queueNum = cleanCell(data.antrean || "-");
  var totalOrder = Number(data.total || 0);
  var items = data.items || [];

  if (!totalOrder) {
    totalOrder = items.reduce(function(acc, item) {
      return acc + (Number(item.qty || 1) * Number(item.price || 0));
    }, 0);
  }

  items.forEach(function(item) {
    var qty = Number(item.qty || 1);
    var price = Number(item.price || 0);
    sheet.appendRow([
      now, queueNum, customerName, tableLabel, paymentMethod,
      cleanCell(item.menu || item.productName || "-"), cleanCell(item.size || item.variantLabel || "-"),
      qty, price, qty * price,
      cleanCell(item.temp || "-"), cleanCell(item.ice || "-"), cleanCell(item.sweet || "-"),
      cleanCell(item.note || "-"), totalOrder
    ]);
  });

  return jsonResponse({ status: "success", count: items.length });
}

function cleanCell(value) {
  if (value === null || value === undefined) return "-";
  var text = String(value).trim();
  if (/^[=+\-@]/.test(text)) text = "'" + text;
  return text;
}

function cleanValue(value) {
  return String(value == null ? "" : value).trim();
}

function jsonResponse(value) {
  return ContentService.createTextOutput(JSON.stringify(value)).setMimeType(ContentService.MimeType.JSON);
}
