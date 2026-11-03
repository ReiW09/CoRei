const CACHE = "corei-v3";
const OFFLINE_URL = "./";

// ── Install: cache shell aset utama ──────────────────────────────────────────
self.addEventListener("install", e => {
  self.skipWaiting();
  e.waitUntil(
    caches.open(CACHE).then(cache =>
      cache.addAll([
        "./",
        "./index.html",
        "./manifest.json",
        "./icon-192.png",
        "./sw.js"
      ]).catch(() => {}) // graceful if some assets missing
    )
  );
});

// ── Activate: bersihkan cache lama ───────────────────────────────────────────
self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// ── Fetch: network-first, fallback to cache ───────────────────────────────────
self.addEventListener("fetch", e => {
  const r = e.request;
  const u = new URL(r.url);
  if (r.method !== "GET" || u.origin !== location.origin) return;
  e.respondWith(
    fetch(r)
      .then(res => {
        const c = res.clone();
        caches.open(CACHE).then(cache => cache.put(r, c));
        return res;
      })
      .catch(() => caches.match(r).then(m => m || caches.match(OFFLINE_URL)))
  );
});

// ── Push Notification handler ─────────────────────────────────────────────────
self.addEventListener("push", e => {
  let data = { title: "CoRei", body: "Ada pesanan baru masuk!" };
  try {
    if (e.data) data = e.data.json();
  } catch (_) {}

  e.waitUntil(
    self.registration.showNotification(data.title || "CoRei Kasir", {
      body: data.body || "Pesanan baru masuk!",
      icon: "./icon-192.png",
      badge: "./icon-192.png",
      tag: data.tag || "corei-order",
      requireInteraction: data.requireInteraction || false,
      data: { url: data.url || "./kasir.html" }
    })
  );
});

// ── Notification click: buka kasir ───────────────────────────────────────────
self.addEventListener("notificationclick", e => {
  e.notification.close();
  const targetUrl = (e.notification.data && e.notification.data.url) || "./kasir.html";
  e.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(clients => {
      for (const client of clients) {
        if (client.url.includes("kasir") && "focus" in client) return client.focus();
      }
      if (self.clients.openWindow) return self.clients.openWindow(targetUrl);
    })
  );
});

// ── Background Sync fallback ──────────────────────────────────────────────────
self.addEventListener("sync", e => {
  if (e.tag === "sync-orders") {
    // Future: retry failed order submissions
    console.log("[SW] Background sync triggered:", e.tag);
  }
});
