import { chromium } from 'playwright';

const url = process.argv[2] || 'http://localhost:8765/compare_mathjax.html';
const browser = await chromium.launch();
const page = await browser.newPage();
await page.goto(url);
await page.waitForFunction(() => document.getElementById('status')?.textContent?.includes('expressions'), { timeout: 15000 });
await page.waitForTimeout(1500);

console.log(`URL: ${url}\n`);
console.log('label                  AlphaEqt(px)   MathJax(px)   wΔ%    hΔ%   status');
console.log('-'.repeat(72));

for (const label of ['overline', 'underline', 'accent-bar-multi', 'accent-bar', 'fraction']) {
  const ae = await page.locator(`img[src="${label}.png"]`).boundingBox();
  const mj = await page.locator(`#mj-${label} mjx-math`).boundingBox();
  if (!ae || !mj) {
    console.log(`${label.padEnd(22)} missing elements`);
    continue;
  }
  const wd = Math.abs(mj.width - ae.width) / Math.max(mj.width, ae.width) * 100;
  const hd = Math.abs(mj.height - ae.height) / Math.max(mj.height, ae.height) * 100;
  const status = Math.max(wd, hd) <= 10 ? 'OK' : Math.max(wd, hd) <= 20 ? 'WARN' : 'FAIL';
  console.log(
    `${label.padEnd(22)} ${ae.width.toFixed(1)}x${ae.height.toFixed(1).padStart(5)}   ` +
    `${mj.width.toFixed(1)}x${mj.height.toFixed(1).padStart(5)}   ` +
    `${wd.toFixed(1).padStart(5)} ${hd.toFixed(1).padStart(5)}   ${status}`
  );
}
await browser.close();
