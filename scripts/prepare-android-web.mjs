import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const isCashierApp = process.argv.includes("--cashier");
const webRoot = join(projectRoot, isCashierApp ? "www-kasir" : "www");
const commonAssets = [
  "supabase-config.js",
  "icon-192.png",
  "icon-512.png",
  "apple-touch-icon.png"
];
const customerAssets = ["manifest.json", "qris.jpg", "legacy/qris-legacy.jpg"];

await rm(webRoot, { recursive: true, force: true });
await mkdir(webRoot, { recursive: true });

let appPage = await readFile(join(projectRoot, isCashierApp ? "kasir.html" : "index.html"), "utf8");
if (isCashierApp) {
  const customerLink = '<a href="./">← Menu pelanggan</a>';
  if (!appPage.includes(customerLink)) {
    throw new Error("Could not locate the customer link to exclude it from the cashier app.");
  }
  appPage = appPage.replace(customerLink, "");
} else {
  const cashierLink = '<p style="margin-top:14px;"><a href="kasir.html">Masuk kasir / dapur</a></p>';
  if (!appPage.includes(cashierLink)) {
    throw new Error("Could not locate the cashier link to exclude it from the customer app.");
  }
  appPage = appPage.replace(cashierLink, "");
}
await writeFile(join(webRoot, "index.html"), appPage);

for (const asset of [...commonAssets, ...(!isCashierApp ? customerAssets : [])]) {
  await cp(join(projectRoot, asset), join(webRoot, asset));
}

console.log(`Prepared ${isCashierApp ? "cashier" : "customer"}-only Android web assets in ${webRoot}.`);
