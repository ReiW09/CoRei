import { cp, mkdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const customerProject = join(projectRoot, "android");
const cashierProject = join(projectRoot, "android-kasir");
const cashierAppId = "id.corei.cashier";
const cashierAppName = "CoRei Kasir";
const webRoot = join(projectRoot, "www-kasir");
const command = process.argv[2];

if (!["add", "sync"].includes(command)) {
  throw new Error("Usage: node scripts/android-cashier.mjs <add|sync>");
}

if (command === "add") {
  if (await exists(cashierProject)) {
    throw new Error("The cashier Android project already exists. Use the sync command instead.");
  }

  await cp(customerProject, cashierProject, {
    recursive: true,
    filter: source => !/(?:^|[\\/])(?:\.gradle|\.idea|build)(?:[\\/]|$)/.test(source)
      && !/[\\/]local\.properties$/.test(source)
      && !/[\\/]assets[\\/]public(?:[\\/]|$)/.test(source)
  });

  const appGradlePath = join(cashierProject, "app", "build.gradle");
  const appGradle = await readFile(appGradlePath, "utf8");
  const customerNamespace = /namespace\s*=\s*"id\.corei\.customer"/;
  const customerApplicationId = /applicationId\s+"id\.corei\.customer"/;
  if (!customerNamespace.test(appGradle) || !customerApplicationId.test(appGradle)) {
    throw new Error("Could not replace the customer app identifiers in the Android template.");
  }
  await writeFile(appGradlePath, appGradle
    .replace(customerNamespace, `namespace = "${cashierAppId}"`)
    .replace(customerApplicationId, `applicationId "${cashierAppId}"`));

  const stringsPath = join(cashierProject, "app", "src", "main", "res", "values", "strings.xml");
  let strings = await readFile(stringsPath, "utf8");
  strings = strings.replace('<string name="app_name">CoRei</string>', `<string name="app_name">${cashierAppName}</string>`)
    .replace('<string name="title_activity_main">CoRei</string>', `<string name="title_activity_main">${cashierAppName}</string>`)
    .replaceAll("id.corei.customer", cashierAppId);
  await writeFile(stringsPath, strings);

  const oldActivityPath = join(cashierProject, "app", "src", "main", "java", "id", "corei", "customer", "MainActivity.java");
  const newActivityPath = join(cashierProject, "app", "src", "main", "java", "id", "corei", "cashier", "MainActivity.java");
  let activity = await readFile(oldActivityPath, "utf8");
  if (!activity.includes("package id.corei.customer;")) {
    throw new Error("Could not replace the package name in the cashier MainActivity.");
  }
  activity = activity.replace("package id.corei.customer;", `package ${cashierAppId};`);
  await mkdir(dirname(newActivityPath), { recursive: true });
  await writeFile(newActivityPath, activity);
  await rm(join(cashierProject, "app", "src", "main", "java", "id", "corei", "customer"), { recursive: true });
}

if (!(await exists(join(cashierProject, "app", "build.gradle")))) {
  throw new Error("Cashier Android project is missing. Run `npm run android:add:cashier` first.");
}

const publicAssets = join(cashierProject, "app", "src", "main", "assets", "public");
await rm(publicAssets, { recursive: true, force: true });
await mkdir(publicAssets, { recursive: true });
await cp(webRoot, publicAssets, { recursive: true });
await writeFile(
  join(cashierProject, "app", "src", "main", "assets", "capacitor.config.json"),
  `${JSON.stringify({ appId: cashierAppId, appName: cashierAppName, webDir: "www-kasir" }, null, 2)}\n`
);
await writeFile(
  join(cashierProject, "app", "src", "main", "assets", "capacitor.plugins.json"),
  "[]\n"
);

console.log(`Prepared ${cashierAppName} Android project (${command}).`);

async function exists(path) {
  try {
    await stat(path);
    return true;
  } catch (error) {
    if (error.code === "ENOENT") return false;
    throw error;
  }
}
