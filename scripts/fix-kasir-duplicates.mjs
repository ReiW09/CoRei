// scripts/fix-kasir-duplicates.mjs
// Hapus fungsi duplicate lama di kasir.html:
// - openReportModal (lama) 
// - closeReportModal (lama)
// - calculateAndRenderReport (lama — akses #top-items-tbody yang sudah tidak ada)
// - exportOrdersToCSV (lama)
// - report-open-btn listener (lama)
import { readFileSync, writeFileSync } from "fs";

const file = "kasir.html";
let html = readFileSync(file, "utf8").replace(/\r\n/g, "\n");

// Blok lama yang perlu dihapus (L632–733)
const oldBlock = `    
    
    // ==========================================
    // LAPORAN OMZET & EKSPOR CSV
    // ==========================================
    function openReportModal() {
      calculateAndRenderReport();
      document.getElementById("report-modal").classList.add("open");
    }

    function closeReportModal() {
      document.getElementById("report-modal").classList.remove("open");
    }

    document.getElementById("report-open-btn")?.addEventListener("click", openReportModal);

    function calculateAndRenderReport() {
      let totalOmzet = 0;
      let paidOrdersCount = 0;
      let countQris = 0;
      let countCash = 0;
      const itemMap = {};

      allOrders.forEach(o => {
        if (o.payment_status === "lunas" && o.status !== "batal") {
          totalOmzet += Number(o.total || 0);
          paidOrdersCount++;
          if (o.payment_method === "QRIS") countQris++;
          if (o.payment_method === "Cash") countCash++;

          (o.items || []).forEach(item => {
            const key = item.productName + " (" + item.variantLabel + ")";
            if (!itemMap[key]) {
              itemMap[key] = { qty: 0, revenue: 0 };
            }
            itemMap[key].qty += Number(item.qty || 0);
            itemMap[key].revenue += Number((item.price || 0) * (item.qty || 0));
          });
        }
      });

      document.getElementById("stat-total-omzet").textContent = formatRupiah(totalOmzet);
      document.getElementById("stat-total-orders").textContent = paidOrdersCount + " pesanan";
      document.getElementById("stat-payment-split").textContent = "QRIS: " + countQris + " | Cash: " + countCash;

      const tbody = document.getElementById("top-items-tbody");
      tbody.replaceChildren();

      const sortedItems = Object.entries(itemMap).sort((a, b) => b[1].qty - a[1].qty);
      if (sortedItems.length === 0) {
        tbody.innerHTML = '<tr><td colspan="3" style="text-align:center;color:var(--muted);padding:14px;">Belum ada pesanan lunas.</td></tr>';
      } else {
        sortedItems.forEach(([name, data]) => {
          const tr = document.createElement("tr");
          tr.innerHTML = \`
            <td style="font-weight:600;">\${name}</td>
            <td style="text-align:right;">\${data.qty}x</td>
            <td style="text-align:right;">\${formatRupiah(data.revenue)}</td>
          \`;
          tbody.appendChild(tr);
        });
      }
    }

    function exportOrdersToCSV() {
      if (!allOrders.length) {
        alert("Belum ada data pesanan untuk diekspor.");
        return;
      }

      // Header CSV
      let csvContent = "data:text/csv;charset=utf-8,";
      csvContent += "No Antrean,Waktu,Nama Pelanggan,Meja,Cara Bayar,Status Bayar,Status Pesanan,Rincian Menu,Total (Rp)\\r\\n";

      allOrders.forEach(o => {
        const queue = "#" + String(o.queue_number).padStart(3, "0");
        const time = new Date(o.created_at).toLocaleString("id-ID", { dateStyle: "short", timeStyle: "short" }).replace(",", "");
        const name = '"' + (o.customer_name || "").replace(/"/g, '""') + '"';
        const table = '"' + (o.table_label || "").replace(/"/g, '""') + '"';
        const method = o.payment_method || "-";
        const payStatus = o.payment_status === "lunas" ? "Lunas" : "Belum Lunas";
        const status = o.status || "-";
        
        const itemsSummary = (o.items || []).map(i => {
          const opts = [i.temp, i.ice, i.sweet].filter(Boolean).join("/");
          return i.qty + "x " + i.productName + "(" + i.variantLabel + (opts ? "-" + opts : "") + ")";
        }).join(" | ");
        const itemsClean = '"' + itemsSummary.replace(/"/g, '""') + '"';
        const total = o.total || 0;

        csvContent += [queue, time, name, table, method, payStatus, status, itemsClean, total].join(",") + "\\r\\n";
      });

      const encodedUri = encodeURI(csvContent);
      const link = document.createElement("a");
      const filename = "Laporan_Penjualan_CoRei_" + new Date().toISOString().slice(0, 10) + ".csv";
      link.setAttribute("href", encodedUri);
      link.setAttribute("download", filename);
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
    }`;

if (html.includes(oldBlock)) {
  html = html.replace(oldBlock, "");
  console.log("✅ Removed duplicate report functions (old block)");
} else {
  console.log("⚠️ Old block not found with exact match. Trying line-by-line approach...");
  
  // Approach: find and remove lines between markers
  const lines = html.split("\n");
  const startMarker = "    // LAPORAN OMZET & EKSPOR CSV";
  const endMarker = "      document.body.removeChild(link);";
  
  let firstStart = -1;
  let firstEnd = -1;
  
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes("LAPORAN OMZET & EKSPOR CSV") && firstStart === -1) {
      // Go back 2 lines to capture the comment separator
      firstStart = Math.max(0, i - 1);
    }
    if (firstStart !== -1 && firstEnd === -1 && lines[i].includes("document.body.removeChild(link)")) {
      // Find closing brace
      for (let j = i + 1; j < lines.length; j++) {
        if (lines[j].trim() === "}") {
          firstEnd = j;
          break;
        }
      }
      break;
    }
  }
  
  if (firstStart !== -1 && firstEnd !== -1) {
    // Check if there's a SECOND occurrence
    let secondStart = -1;
    for (let i = firstEnd + 1; i < lines.length; i++) {
      if (lines[i].includes("LAPORAN OMZET")) {
        secondStart = i;
        break;
      }
    }
    
    if (secondStart !== -1) {
      // Remove the FIRST occurrence (the old one)
      lines.splice(firstStart, firstEnd - firstStart + 1);
      console.log(`✅ Removed lines ${firstStart}-${firstEnd} (old duplicate block)`);
    } else {
      console.log("ℹ️ Only one occurrence found, no duplicates to remove");
    }
  } else {
    console.log("❌ Could not find duplicate block boundaries");
  }
  
  html = lines.join("\n");
}

writeFileSync(file, html, "utf8");
console.log("✅ kasir.html duplicate fix complete");
