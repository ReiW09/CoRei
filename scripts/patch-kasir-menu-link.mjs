import { readFileSync, writeFileSync } from 'fs';

const KASIR = 'c:/Users/User/OneDrive/文档/RMSW9/JOHN/CoRei/kasir.html';
const WWWKASIR = 'c:/Users/User/OneDrive/文档/RMSW9/JOHN/CoRei/www-kasir/index.html';

let content = readFileSync(KASIR, 'utf8').replace(/\r\n/g, '\n');

// Check if already patched
if (content.includes('menu-admin.html')) {
  console.log('Link already exists — syncing www-kasir only');
  writeFileSync(WWWKASIR, content, 'utf8');
  console.log('Synced www-kasir/index.html OK');
  process.exit(0);
}

// Find and replace the topbar link section
// The exact text is: <a href="./">← Menu pelanggan</a>\n    </header>
// Right after the brand div
const OLD_PART = '<a href="./">\u2190 Menu pelanggan</a>\n    </header>';
const NEW_PART = '<div style="display:flex;gap:12px;align-items:center">\n        <a href="menu-admin.html">\u2699\ufe0f Kelola Menu</a>\n        <a href="./">\u2190 Menu pelanggan</a>\n      </div>\n    </header>';

console.log('OLD found:', content.includes(OLD_PART));

if (content.includes(OLD_PART)) {
  content = content.replace(OLD_PART, NEW_PART);
  writeFileSync(KASIR, content, 'utf8');
  writeFileSync(WWWKASIR, content, 'utf8');
  console.log('Patched kasir.html + synced www-kasir/index.html OK');
} else {
  console.error('ERROR: target not found');
  process.exit(1);
}

