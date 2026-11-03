// scripts/upgrade-kasir.mjs
// Upgrade kasir.html dengan:
// 1. Badge tab browser (pesanan aktif)
// 2. Timestamp "X menit lalu" di kartu pesanan
// 3. Modal Laporan diperluas: chart jam sibuk (SVG), progress bar top menu, avg transaksi
// 4. Auto-refresh fallback jika realtime disconnect
// 5. Dark mode toggle di topbar
// 6. Push notification support
import { readFileSync, writeFileSync } from "fs";

const file = "kasir.html";
let html = readFileSync(file, "utf8").replace(/\r\n/g, "\n");

// ─── 1. CSS tambahan ─────────────────────────────────────────────────────────
const extraCSS = `
    /* ── Dark mode toggle ── */
    .theme-btn{padding:6px 12px;border-radius:999px;background:var(--surface);border:1px solid var(--line);font-size:12px;font-weight:600;cursor:pointer;color:var(--ink)}
    /* ── Timestamp badge ── */
    .time-ago{font-size:11px;color:var(--muted);font-style:italic}
    /* ── Notif push btn ── */
    .push-btn{padding:6px 12px;border-radius:999px;background:var(--surface);border:1px solid var(--line);font-size:12px;font-weight:600;cursor:pointer;color:var(--ink);display:flex;align-items:center;gap:5px}
    .push-btn.granted{border-color:var(--success);color:var(--success)}
    /* ── Laporan tabs ── */
    .report-tabs{display:flex;gap:6px;margin:14px 0 0}
    .report-tab{padding:7px 16px;border-radius:999px;border:1px solid var(--line);background:var(--surface);font-size:13px;font-weight:600;cursor:pointer;color:var(--muted)}
    .report-tab.active{background:var(--accent);color:var(--accent-ink);border-color:var(--accent)}
    .report-tab-panel{display:none}
    .report-tab-panel.active{display:block}
    /* ── Progress bar ── */
    .prog-bar-wrap{margin:6px 0}
    .prog-bar-label{display:flex;justify-content:space-between;font-size:12px;margin-bottom:3px}
    .prog-bar-bg{background:var(--surface-subtle);border-radius:999px;height:10px;overflow:hidden;border:1px solid var(--line)}
    .prog-bar-fill{height:100%;border-radius:999px;background:var(--accent);transition:width .4s}
    /* ── Hourly chart ── */
    .hour-chart{width:100%;overflow-x:auto;margin-top:10px}
    .hour-chart svg{display:block;width:100%;min-width:320px}
    /* ── Avg stat ── */
    .stat-card.accent{background:var(--accent-subtle);border-color:var(--accent)}
    .stat-card.accent .stat-val{color:var(--accent)}
    /* ── Auto reconnect notice ── */
    #reconnect-notice{display:none;padding:8px 14px;background:var(--promo-bg);color:var(--promo-ink);font-size:13px;border-radius:10px;margin:8px 0;text-align:center}
`;

html = html.replace(
  `    #receipt-print-area{display:none}`,
  extraCSS + `    #receipt-print-area{display:none}`
);

// ─── 2. Topbar: tambah dark mode + push notification button ──────────────────
html = html.replace(
  `<button id="sound-toggle-btn" class="sound-btn active" type="button" title="Bunyi notifikasi pesanan baru">🔔 Bunyi: Nyala</button>`,
  `<button id="push-notif-btn" class="push-btn" type="button" title="Aktifkan notifikasi push">🔕 Notif</button>
          <button id="sound-toggle-btn" class="sound-btn active" type="button" title="Bunyi notifikasi pesanan baru">🔔 Bunyi: Nyala</button>
          <button id="theme-btn" class="theme-btn" type="button" title="Ganti tema">🌙</button>`
);

// ─── 3. Tambah reconnect notice + per-order timestamp di bawah filter-bar ────
html = html.replace(
  `      <div id="kitchen-notice" class="notice hidden" role="status"></div>`,
  `      <div id="reconnect-notice" role="status">🔄 Koneksi realtime terputus — mencoba sambung ulang...</div>
      <div id="kitchen-notice" class="notice hidden" role="status"></div>`
);

// ─── 4. Ganti modal Laporan: tambah tabs + panel statistik lanjutan ──────────
const oldReportContent = `          <p class="small" style="margin:4px 0 16px;">Ringkasan transaksi dari daftar pesanan kasir</p>

          <div class="report-stats-grid">
            <div class="stat-card">
              <div class="stat-label">Total Omzet Lunas</div>
              <div class="stat-val" id="stat-total-omzet" style="color:var(--success);">Rp0</div>
            </div>
            <div class="stat-card">
              <div class="stat-label">Pesanan Lunas</div>
              <div class="stat-val" id="stat-total-orders">0</div>
            </div>
            <div class="stat-card">
              <div class="stat-label">QRIS vs Tunai</div>
              <div class="stat-val" id="stat-payment-split" style="font-size:14px;margin-top:6px;">0 / 0</div>
            </div>
          </div>

          <h3 style="font-size:15px;margin:18px 0 6px;">Menu Paling Banyak Dipesan</h3>
          <div style="max-height:180px;overflow-y:auto;border:1px solid var(--line);border-radius:10px;">
            <table class="report-table">
              <thead>
                <tr>
                  <th>Menu</th>
                  <th style="text-align:right;">Terjual</th>
                  <th style="text-align:right;">Subtotal</th>
                </tr>
              </thead>
              <tbody id="top-items-tbody"></tbody>
            </table>
          </div>

          <div style="display:flex;gap:10px;margin-top:20px;flex-wrap:wrap;">
            <button type="button" class="action" onclick="exportOrdersToCSV()" style="flex:1;background:var(--success);">📥 Ekspor ke CSV (Excel)</button>
            <button type="button" class="action secondary" onclick="closeReportModal()" style="flex:1;">Tutup</button>
          </div>`;

const newReportContent = `          <p class="small" style="margin:4px 0 10px;">Ringkasan transaksi dari daftar pesanan kasir</p>

          <!-- Stat ring atas -->
          <div class="report-stats-grid">
            <div class="stat-card">
              <div class="stat-label">Total Omzet Lunas</div>
              <div class="stat-val" id="stat-total-omzet" style="color:var(--success);">Rp0</div>
            </div>
            <div class="stat-card">
              <div class="stat-label">Pesanan Lunas</div>
              <div class="stat-val" id="stat-total-orders">0</div>
            </div>
            <div class="stat-card">
              <div class="stat-label">Rata-rata Transaksi</div>
              <div class="stat-val" id="stat-avg-order" style="font-size:15px;margin-top:6px;">Rp0</div>
            </div>
            <div class="stat-card">
              <div class="stat-label">QRIS vs Tunai</div>
              <div class="stat-val" id="stat-payment-split" style="font-size:14px;margin-top:6px;">0 / 0</div>
            </div>
          </div>

          <!-- Tabs -->
          <div class="report-tabs">
            <button class="report-tab active" data-rtab="top-menu" type="button">🏆 Top Menu</button>
            <button class="report-tab" data-rtab="jam-sibuk" type="button">⏰ Jam Sibuk</button>
          </div>

          <!-- Panel: Top Menu -->
          <div class="report-tab-panel active" id="rtab-top-menu" style="margin-top:12px;">
            <div id="top-items-bars"></div>
          </div>

          <!-- Panel: Jam Sibuk -->
          <div class="report-tab-panel" id="rtab-jam-sibuk" style="margin-top:12px;">
            <p style="font-size:12px;color:var(--muted);margin:0 0 6px;">Jumlah pesanan per jam (semua pesanan, termasuk yang belum lunas)</p>
            <div class="hour-chart" id="hour-chart-wrap"></div>
          </div>

          <div style="display:flex;gap:10px;margin-top:20px;flex-wrap:wrap;">
            <button type="button" class="action" onclick="exportOrdersToCSV()" style="flex:1;background:var(--success);">📥 Ekspor ke CSV (Excel)</button>
            <button type="button" class="action secondary" onclick="closeReportModal()" style="flex:1;">Tutup</button>
          </div>`;

html = html.replace(oldReportContent, newReportContent);

// ─── 5. Upgrade JavaScript (ganti seluruh blok <script>) ─────────────────────
const oldScriptEnd = `    // Auto-restore session jika staf sudah pernah login
    if (client) {
      client.auth.getSession().then(({ data: { session } }) => {
        if (session && session.user) {
          openKitchen(session.user.id);
        }
      });
    }

    if (!client) showError("Supabase belum dikonfigurasi. Isi supabase-config.js lalu muat ulang.");

  </script>`;

const newScriptEnd = `    // ==========================================
    // DARK MODE TOGGLE
    // ==========================================
    (function() {
      const saved = localStorage.getItem("corei_kasir_theme");
      if (saved === "dark") document.documentElement.setAttribute("data-theme", "dark");
    })();

    document.addEventListener("DOMContentLoaded", () => {
      const themeBtn = document.getElementById("theme-btn");
      if (themeBtn) {
        const isDark = () => document.documentElement.getAttribute("data-theme") === "dark";
        const updateThemeBtn = () => { themeBtn.textContent = isDark() ? "☀️" : "🌙"; };
        updateThemeBtn();
        themeBtn.addEventListener("click", () => {
          const newTheme = isDark() ? "light" : "dark";
          document.documentElement.setAttribute("data-theme", newTheme);
          localStorage.setItem("corei_kasir_theme", newTheme);
          updateThemeBtn();
        });
      }
    });

    // ==========================================
    // BADGE TAB BROWSER (pesanan aktif)
    // ==========================================
    let originalTitle = document.title;
    function updateTabBadge() {
      const aktif = allOrders.filter(o => o.status === "baru" || o.status === "diproses" || o.status === "siap").length;
      document.title = aktif > 0 ? "(" + aktif + ") " + originalTitle : originalTitle;
    }

    // ==========================================
    // TIMESTAMP "X menit lalu"
    // ==========================================
    function timeAgo(dateStr) {
      const diff = Math.floor((Date.now() - new Date(dateStr)) / 1000);
      if (diff < 60) return diff + " dtk lalu";
      if (diff < 3600) return Math.floor(diff / 60) + " mnt lalu";
      return Math.floor(diff / 3600) + " jam lalu";
    }

    // Update timestamp setiap 30 detik
    setInterval(() => {
      document.querySelectorAll(".time-ago[data-created]").forEach(el => {
        el.textContent = timeAgo(el.dataset.created);
      });
    }, 30000);

    // ==========================================
    // AUTO-RECONNECT FALLBACK
    // ==========================================
    let reconnectTimer = null;
    let lastRealtimeOk = Date.now();

    function onRealtimeStatus(status) {
      const notice = document.getElementById("reconnect-notice");
      if (status === "SUBSCRIBED") {
        lastRealtimeOk = Date.now();
        if (notice) notice.style.display = "none";
        if (reconnectTimer) { clearInterval(reconnectTimer); reconnectTimer = null; }
        connectionState.textContent = "Tersambung · pembaruan langsung aktif";
      } else {
        connectionState.textContent = "Menghubungkan ulang...";
        if (notice) notice.style.display = "block";
        if (!reconnectTimer) {
          reconnectTimer = setInterval(() => {
            if (Date.now() - lastRealtimeOk > 30000) {
              loadOrders(); // manual fallback
            }
          }, 15000);
        }
      }
    }

    // ==========================================
    // PUSH NOTIFICATION (Web Push API)
    // ==========================================
    async function initPushNotification() {
      const btn = document.getElementById("push-notif-btn");
      if (!btn) return;
      if (!("Notification" in window) || !("serviceWorker" in navigator)) {
        btn.style.display = "none";
        return;
      }
      const updatePushBtn = (perm) => {
        if (perm === "granted") {
          btn.textContent = "🔔 Notif: Aktif";
          btn.classList.add("granted");
        } else if (perm === "denied") {
          btn.textContent = "🚫 Notif: Diblokir";
          btn.classList.remove("granted");
        } else {
          btn.textContent = "🔕 Notif";
          btn.classList.remove("granted");
        }
      };
      updatePushBtn(Notification.permission);
      btn.addEventListener("click", async () => {
        if (Notification.permission === "denied") {
          alert("Notifikasi diblokir di pengaturan browser. Buka Pengaturan Site → Notifikasi → Izinkan.");
          return;
        }
        const perm = await Notification.requestPermission();
        updatePushBtn(perm);
        if (perm === "granted") {
          new Notification("CoRei Kasir", {
            body: "Notifikasi pesanan baru aktif! 🎉",
            icon: "./icon-192.png"
          });
        }
      });
    }

    function sendBrowserNotification(order) {
      if (Notification.permission !== "granted") return;
      const queue = "#" + String(order.queue_number).padStart(3, "0");
      new Notification("Pesanan Baru " + queue + " — CoRei", {
        body: order.customer_name + " memesan " + (order.items || []).length + " item · " + formatRupiah(order.total),
        icon: "./icon-192.png",
        tag: "order-" + order.public_id,
        requireInteraction: false
      });
    }

    // ==========================================
    // REPORT TABS
    // ==========================================
    document.addEventListener("DOMContentLoaded", () => {
      document.querySelectorAll(".report-tab").forEach(tab => {
        tab.addEventListener("click", () => {
          document.querySelectorAll(".report-tab").forEach(t => t.classList.remove("active"));
          document.querySelectorAll(".report-tab-panel").forEach(p => p.classList.remove("active"));
          tab.classList.add("active");
          const panelId = "rtab-" + tab.dataset.rtab;
          const panel = document.getElementById(panelId);
          if (panel) panel.classList.add("active");
        });
      });
    });

    // ==========================================
    // LAPORAN OMZET — EXTENDED
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
      const hourMap = {};

      allOrders.forEach(o => {
        // Hourly distribution (semua pesanan)
        const h = new Date(o.created_at).getHours();
        hourMap[h] = (hourMap[h] || 0) + 1;

        if (o.payment_status === "lunas" && o.status !== "batal") {
          totalOmzet += Number(o.total || 0);
          paidOrdersCount++;
          if (o.payment_method === "QRIS") countQris++;
          if (o.payment_method === "Cash") countCash++;

          (o.items || []).forEach(item => {
            const key = item.productName + " (" + item.variantLabel + ")";
            if (!itemMap[key]) itemMap[key] = { qty: 0, revenue: 0 };
            itemMap[key].qty += Number(item.qty || 0);
            itemMap[key].revenue += Number((item.price || 0) * (item.qty || 0));
          });
        }
      });

      const avgOrder = paidOrdersCount > 0 ? Math.round(totalOmzet / paidOrdersCount) : 0;

      document.getElementById("stat-total-omzet").textContent = formatRupiah(totalOmzet);
      document.getElementById("stat-total-orders").textContent = paidOrdersCount + " pesanan";
      document.getElementById("stat-avg-order").textContent = formatRupiah(avgOrder);
      document.getElementById("stat-payment-split").textContent = "QRIS: " + countQris + " | Cash: " + countCash;

      // ── Top Menu: progress bars ──
      const barsWrap = document.getElementById("top-items-bars");
      barsWrap.replaceChildren();
      const sortedItems = Object.entries(itemMap).sort((a, b) => b[1].qty - a[1].qty).slice(0, 8);
      if (sortedItems.length === 0) {
        barsWrap.innerHTML = '<p style="color:var(--muted);font-size:13px;text-align:center;padding:14px 0;">Belum ada pesanan lunas.</p>';
      } else {
        const maxQty = sortedItems[0][1].qty;
        sortedItems.forEach(([name, d]) => {
          const pct = maxQty > 0 ? Math.round((d.qty / maxQty) * 100) : 0;
          const wrap = document.createElement("div");
          wrap.className = "prog-bar-wrap";
          wrap.innerHTML = \`
            <div class="prog-bar-label">
              <span style="font-weight:600;font-size:13px;">\${name}</span>
              <span style="color:var(--muted);">\${d.qty}x · \${formatRupiah(d.revenue)}</span>
            </div>
            <div class="prog-bar-bg"><div class="prog-bar-fill" style="width:\${pct}%"></div></div>
          \`;
          barsWrap.appendChild(wrap);
        });
      }

      // ── Jam Sibuk: SVG bar chart ──
      const chartWrap = document.getElementById("hour-chart-wrap");
      chartWrap.replaceChildren();
      if (Object.keys(hourMap).length === 0) {
        chartWrap.innerHTML = '<p style="color:var(--muted);font-size:13px;text-align:center;padding:14px 0;">Belum ada data pesanan.</p>';
      } else {
        // Build 24-hour array
        const hours = Array.from({ length: 24 }, (_, i) => ({ h: i, count: hourMap[i] || 0 }));
        const maxCount = Math.max(...hours.map(h => h.count), 1);
        const W = 600, H = 120, PAD = 28, BAR_W = Math.floor((W - PAD * 2) / 24) - 2;

        let bars = "";
        let labels = "";
        hours.forEach((hObj, i) => {
          if (hObj.count === 0) return;
          const x = PAD + i * ((W - PAD * 2) / 24);
          const barH = Math.max(4, Math.round((hObj.count / maxCount) * (H - 30)));
          const y = H - 20 - barH;
          bars += \`<rect x="\${x.toFixed(1)}" y="\${y}" width="\${BAR_W}" height="\${barH}" rx="3" fill="var(--accent)" opacity="0.85"/>\`;
          bars += \`<text x="\${(x + BAR_W/2).toFixed(1)}" y="\${y - 3}" text-anchor="middle" font-size="9" fill="var(--ink)">\${hObj.count}</text>\`;
        });
        // X-axis labels every 3 hours
        [0,3,6,9,12,15,18,21].forEach(h => {
          const x = PAD + h * ((W - PAD * 2) / 24) + BAR_W / 2;
          labels += \`<text x="\${x.toFixed(1)}" y="\${H - 5}" text-anchor="middle" font-size="9" fill="var(--muted)">\${String(h).padStart(2,"0")}:00</text>\`;
        });
        chartWrap.innerHTML = \`<svg viewBox="0 0 \${W} \${H}" xmlns="http://www.w3.org/2000/svg">\${bars}\${labels}</svg>\`;
      }
    }

    function exportOrdersToCSV() {
      if (!allOrders.length) { alert("Belum ada data pesanan untuk diekspor."); return; }
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
        csvContent += [queue, time, name, table, method, payStatus, status, itemsClean, o.total || 0].join(",") + "\\r\\n";
      });
      const link = document.createElement("a");
      link.setAttribute("href", encodeURI(csvContent));
      link.setAttribute("download", "Laporan_Penjualan_CoRei_" + new Date().toISOString().slice(0, 10) + ".csv");
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
    }

    // ==========================================
    // PATCH renderOrders — tambah time-ago + badge
    // ==========================================
    const _origRenderOrders = renderOrders;
    renderOrders = function(orders) {
      _origRenderOrders(orders);
      updateTabBadge();
      // Patch time-ago ke tiap kartu
      document.querySelectorAll(".order-card").forEach((card, i) => {
        if (orders[i]) {
          const timeEl = card.querySelector(".time");
          if (timeEl && orders[i].created_at) {
            const ago = document.createElement("span");
            ago.className = "time-ago";
            ago.dataset.created = orders[i].created_at;
            ago.textContent = " · " + timeAgo(orders[i].created_at);
            timeEl.appendChild(ago);
          }
        }
      });
    };

    // PATCH loadOrders — tambah sendBrowserNotification
    const _origLoadOrders = loadOrders;
    loadOrders = async function() {
      const prevKnown = new Set(knownOrderIds);
      await _origLoadOrders();
      // Deteksi order baru setelah initial load
      if (initialLoadDone) {
        allOrders.forEach(o => {
          if (!prevKnown.has(o.public_id) && o.status === "baru") {
            sendBrowserNotification(o);
          }
        });
      }
    };

    // PATCH openKitchen — pakai onRealtimeStatus
    const _origOpenKitchen = openKitchen;
    openKitchen = async function(userId) {
      await _origOpenKitchen(userId);
      // Patch channel subscribe callback
      if (kitchenChannel) {
        kitchenChannel.subscribe(onRealtimeStatus);
      }
      initPushNotification();
    };

    // Auto-restore session jika staf sudah pernah login
    if (client) {
      client.auth.getSession().then(({ data: { session } }) => {
        if (session && session.user) {
          openKitchen(session.user.id);
        }
      });
    }

    if (!client) showError("Supabase belum dikonfigurasi. Isi supabase-config.js lalu muat ulang.");

  </script>`;

html = html.replace(oldScriptEnd, newScriptEnd);

// ─── 6. CSS dark mode root (kasir.html pakai compact CSS, tambahkan di bawah media) ─
html = html.replace(
  `    @media(prefers-color-scheme:dark){:root{`,
  `    :root[data-theme="dark"]{--bg:#0D1614;--surface:#15221F;--surface-subtle:#1C2D29;--ink:#EEF4F1;--muted:#8FA49C;--line:#263832;--accent:#5CC8AF;--accent-subtle:#132D26;--accent-ink:#0A1412;--promo:#FBBF24;--promo-bg:#352605;--promo-ink:#FDE68A;--success:#34D399;--success-bg:#0E3426;--danger:#F87171;--danger-bg:#391515;color-scheme:dark}
    @media(prefers-color-scheme:dark){:root:not([data-theme="light"]){`
);

writeFileSync(file, html, "utf8");
console.log("✅ kasir.html upgraded successfully");
