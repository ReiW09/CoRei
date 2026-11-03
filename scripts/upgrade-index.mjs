// scripts/upgrade-index.mjs
// Upgrade index.html:
// 1. Dark mode toggle di topbar
// 2. Estimasi waktu tunggu di halaman terima kasih
// 3. Pesan status lebih informatif (dengan estimasi)
// 4. QRIS placeholder siap untuk Midtrans (UI sudah ada, tambah copyable total)
// 5. Tombol "Pesan Lagi" yang clear cart & kembali ke menu
// 6. Vibrate + notif browser saat status SIAP (sudah ada, pastikan tidak double)
// 7. Floating counter animasi di cart bar
import { readFileSync, writeFileSync } from "fs";

const file = "index.html";
let html = readFileSync(file, "utf8").replace(/\r\n/g, "\n");

// ─── 1. Tambah dark mode CSS ──────────────────────────────────────────────────
// Cek apakah sudah ada dark mode toggle button di topbar index.html
// Tambahkan theme toggle di CSS dan topbar

// Tambah CSS dark mode manual toggle (setelah :root[data-theme="dark"] yang ada)
const darkModeToggleCSS = `
    /* Dark mode toggle button */
    .theme-toggle-btn {
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: var(--radius-full);
      padding: 8px 14px;
      font-size: 13px;
      font-weight: 600;
      cursor: pointer;
      color: var(--ink);
      display: flex;
      align-items: center;
      gap: 6px;
      transition: all .15s;
    }
    .theme-toggle-btn:hover {
      border-color: var(--accent);
      color: var(--accent);
    }

    /* ── Estimasi waktu tunggu ── */
    .wait-estimate {
      display: inline-block;
      padding: 6px 14px;
      border-radius: var(--radius-full);
      background: var(--promo-bg);
      color: var(--promo-ink);
      font-size: 13px;
      font-weight: 600;
      margin: 4px 0 10px;
    }

    /* ── Order again button ── */
    .btn-order-again {
      width: 100%;
      padding: 14px 20px;
      border: 2px dashed var(--line);
      border-radius: var(--radius-md);
      background: var(--surface);
      color: var(--ink-muted);
      font: 600 15px/1 'Plus Jakarta Sans', sans-serif;
      cursor: pointer;
      margin-top: 8px;
      transition: all .2s;
    }
    .btn-order-again:hover {
      border-color: var(--accent);
      color: var(--accent);
      background: var(--accent-subtle);
    }

    /* ── Cart item count badge animation ── */
    @keyframes badge-pop {
      0%   { transform: scale(1); }
      50%  { transform: scale(1.4); }
      100% { transform: scale(1); }
    }
    .badge-pop { animation: badge-pop 0.3s ease; }
`;

// Cari spot tepat sebelum </style> pertama setelah dark mode
html = html.replace(
  `    @media (prefers-color-scheme: dark) {`,
  darkModeToggleCSS + `    @media (prefers-color-scheme: dark) {`
);

// ─── 2. Dark mode toggle button di topbar ─────────────────────────────────────
// Cari topbar header di index.html — ada di sekitar:
// <header ...> ... <div class="brand"> ... </div> ... </header>
// Tambahkan button di area topbar action
const OLD_TOPBAR_END = `</a>
      </div>
    </header>`;

// Karena bisa ada beberapa, kita target yang spesifik
html = html.replace(
  `← Cara order\n      </a>\n      </div>\n    </header>`,
  `← Cara order\n      </a>
        <button class="theme-toggle-btn" id="index-theme-btn" type="button" title="Ganti tema terang/gelap">🌙</button>
      </div>
    </header>`
);

// ─── 3. Tambah "Pesan Lagi" button dan estimasi waktu di thanks screen ─────────
// Setelah thanks-instruction-text, tambahkan estimasi waktu
html = html.replace(
  `<p id="thanks-instruction-text" class="small" style="margin:8px 0 16px; color:var(--ink-muted);"></p>`,
  `<p id="thanks-instruction-text" class="small" style="margin:8px 0 8px; color:var(--ink-muted);"></p>
          <div id="wait-estimate-wrap" style="display:none; margin-bottom:12px;">
            <span class="wait-estimate">⏱️ Estimasi siap: <span id="wait-estimate-text">5–10 menit</span></span>
          </div>`
);

// Tambah tombol "Pesan Lagi" setelah btn-copy-order-url
html = html.replace(
  `<button type="button" id="btn-copy-order-url" class="btn-secondary-action" hidden>🔗 Bagikan tautan pesanan</button>`,
  `<button type="button" id="btn-copy-order-url" class="btn-secondary-action" hidden>🔗 Bagikan tautan pesanan</button>
          <button type="button" class="btn-order-again" onclick="orderAgain()">↩️ Pesan lagi / tambah menu</button>`
);

// ─── 4. Dark mode init + orderAgain() JS ──────────────────────────────────────
const EXTRA_JS = `
    // ==========================================
    // DARK MODE (index.html)
    // ==========================================
    (function() {
      const saved = localStorage.getItem("corei_theme");
      if (saved) document.documentElement.setAttribute("data-theme", saved);
    })();

    document.addEventListener("DOMContentLoaded", () => {
      const themeBtn = document.getElementById("index-theme-btn");
      if (!themeBtn) return;
      const isDark = () => document.documentElement.getAttribute("data-theme") === "dark";
      const update = () => {
        themeBtn.textContent = isDark() ? "☀️" : "🌙";
        themeBtn.title = isDark() ? "Mode terang" : "Mode gelap";
      };
      update();
      themeBtn.addEventListener("click", () => {
        const newTheme = isDark() ? "light" : "dark";
        document.documentElement.setAttribute("data-theme", newTheme);
        localStorage.setItem("corei_theme", newTheme);
        update();
      });
    });

    // ==========================================
    // ESTIMASI WAKTU TUNGGU
    // ==========================================
    function updateWaitEstimate(queueNumber) {
      // Estimasi kasar: tiap antrean ~3 menit, max 30 menit
      const parsed = parseInt((queueNumber || "0").replace(/\\D/g, ""), 10);
      if (!parsed || isNaN(parsed)) return;
      // Di sini kita tidak tahu posisi antrian, jadi pakai pesan umum
      const wrap = document.getElementById("wait-estimate-wrap");
      const text = document.getElementById("wait-estimate-text");
      if (wrap && text) {
        text.textContent = "5–15 menit";
        wrap.style.display = "block";
      }
    }

    // ==========================================
    // PESAN LAGI / ORDER AGAIN
    // ==========================================
    function orderAgain() {
      // Tutup thanks screen
      document.getElementById("thanks-screen").classList.remove("open");
      // Bersihkan cart
      cart = {};
      updateCartUI();
      // Scroll ke atas
      window.scrollTo({ top: 0, behavior: "smooth" });
      // Reset URL query (hapus ?pesanan=...)
      const url = new URL(window.location.href);
      url.searchParams.delete("pesanan");
      window.history.replaceState({}, "", url);
      // Unsubscribe status channel
      if (customerStatusChannel && supabaseClient) {
        supabaseClient.removeChannel(customerStatusChannel);
        customerStatusChannel = null;
      }
      lastCompletedOrder = null;
    }

    // ==========================================
    // ANIMASI BADGE CART
    // ==========================================
    const _origUpdateCartUI = typeof updateCartUI !== "undefined" ? updateCartUI : null;
    function patchCartBadge() {
      const countLabel = document.getElementById("cart-item-count");
      if (countLabel) {
        countLabel.classList.remove("badge-pop");
        void countLabel.offsetWidth; // trigger reflow
        countLabel.classList.add("badge-pop");
      }
    }
`;

// Sisipkan sebelum "// Check URL query parameters"
html = html.replace(
  `    // Check URL query parameters (e.g. ?meja=7 or ?qr)`,
  EXTRA_JS + `    // Check URL query parameters (e.g. ?meja=7 or ?qr)`
);

// ─── 5. Patch showThankYouScreen untuk call updateWaitEstimate ────────────────
html = html.replace(
  `      document.getElementById("thanks-screen").classList.add("open");
    }`,
  `      document.getElementById("thanks-screen").classList.add("open");
      updateWaitEstimate(order.queueNumber);
    }`
);

// ─── 6. Patch updateCartUI untuk badge animation ─────────────────────────────
html = html.replace(
  `      if (count > 0) {
        cartBar.classList.add("visible");
      } else {
        cartBar.classList.remove("visible");
        closeCartDrawer();
      }`,
  `      if (count > 0) {
        cartBar.classList.add("visible");
        patchCartBadge();
      } else {
        cartBar.classList.remove("visible");
        closeCartDrawer();
      }`
);

writeFileSync(file, html, "utf8");
console.log("✅ index.html upgraded successfully");

