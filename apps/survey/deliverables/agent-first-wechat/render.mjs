import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import fs from "node:fs/promises";

const require = createRequire(import.meta.url);
const runtimeModules = process.env.CODEX_NODE_MODULES;
if (!runtimeModules) throw new Error("CODEX_NODE_MODULES is required");

const { chromium } = require(`${runtimeModules}/playwright`);
const sharp = require(`${runtimeModules}/sharp`);

const [htmlPath, outPath, widthArg, heightArg, outWidthArg] = process.argv.slice(2);
if (!htmlPath || !outPath || !widthArg || !outWidthArg) {
  throw new Error("usage: render.mjs <html> <out.png> <viewport-width> <height|auto> <out-width>");
}

const viewportWidth = Number(widthArg);
const fixedHeight = heightArg === "auto" ? null : Number(heightArg);
const outWidth = Number(outWidthArg);
const hiPath = `${outPath}.hi.png`;

const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE;
const browser = await chromium.launch({
  headless: true,
  ...(executablePath ? { executablePath } : {}),
});
const page = await browser.newPage({
  viewport: { width: viewportWidth, height: fixedHeight || 900 },
  deviceScaleFactor: 1,
});
await page.goto(pathToFileURL(htmlPath).href, { waitUntil: "networkidle" });
await page.evaluate(() => document.fonts.ready);

if (fixedHeight) {
  await page.screenshot({ path: hiPath, clip: { x: 0, y: 0, width: viewportWidth, height: fixedHeight } });
} else {
  await page.locator("body").screenshot({ path: hiPath });
}
await browser.close();

await sharp(hiPath)
  .resize({ width: outWidth })
  .png({ compressionLevel: 9, adaptiveFiltering: true, palette: false })
  .toFile(outPath);
await fs.unlink(hiPath);
