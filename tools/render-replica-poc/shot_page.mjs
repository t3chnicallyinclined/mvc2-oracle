// shot_page.mjs — drive the LIVE page in real headless Chrome (WebGPU) and
// screenshot it, proving the transpiled MVC2 render displays in-browser via
// pvr2-renderer.mjs. Also reads back each canvas' pixels and reports a
// transpiled-body-vs-engine on-canvas comparison.
import puppeteer from 'puppeteer';
import { writeFileSync } from 'node:fs';

const URL_PAGE = process.argv[2] || 'http://localhost:8099/web/render-replica/index.html';
const OUT = process.argv[3] || 'PNG_page_browser.png';

const HEADLESS = process.env.HEADED ? false : 'new';
const SOFTWARE = !!process.env.SOFTWARE;
const args = [
    '--enable-unsafe-webgpu',
    '--enable-webgpu-developer-features',
    '--ignore-gpu-blocklist',
    '--no-sandbox',
];
if (SOFTWARE) {
    // Dawn's software (SwiftShader/WARP) WebGPU adapter — works headless with no GPU.
    args.push('--use-webgpu-adapter=swiftshader', '--enable-features=Vulkan');
} else {
    args.push('--enable-features=Vulkan', '--use-angle=vulkan', '--use-gl=angle');
}
const browser = await puppeteer.launch({ headless: HEADLESS, args });
const page = await browser.newPage();
await page.setViewport({ width: 1480, height: 760, deviceScaleFactor: 1 });
const logs = [];
page.on('console', m => logs.push('[page] ' + m.text()));
page.on('pageerror', e => logs.push('[pageerror] ' + e.message));

await page.goto(URL_PAGE, { waitUntil: 'networkidle0', timeout: 60000 });

// Wait until both canvases have drawn (the page logs "Rendered both panes").
await page.waitForFunction(() => {
    const el = document.getElementById('log');
    return el && /Rendered both panes/.test(el.textContent);
}, { timeout: 60000 }).catch(() => {});

// Give the GPU a beat to present.
await new Promise(r => setTimeout(r, 400));

// Read back non-black pixel counts from each canvas (proves they actually drew).
const counts = await page.evaluate(async () => {
    function nz(id) {
        const c = document.getElementById(id);
        // copy to a 2D canvas to read pixels (webgpu canvas is readable via drawImage)
        const o = document.createElement('canvas'); o.width = c.width; o.height = c.height;
        const g = o.getContext('2d'); g.drawImage(c, 0, 0);
        const d = g.getImageData(0, 0, c.width, c.height).data;
        let n = 0; for (let i = 0; i < d.length; i += 4) if (d[i] | d[i + 1] | d[i + 2]) n++;
        return n;
    }
    return { transpiled: nz('cTranspiled'), engine: nz('cEngine') };
});

await page.screenshot({ path: OUT });
console.log(logs.join('\n'));
console.log('\nNON-BLACK PIXELS  transpiled-canvas=%d  engine-canvas=%d', counts.transpiled, counts.engine);
console.log('screenshot:', OUT);
await browser.close();
