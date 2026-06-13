// shot_replay_live.mjs — Phase 4c LIVE-path end-to-end proof in headless Chrome (WebGPU).
//
// Starts (a) a tiny static HTTP server for the repo root and (b) the mock replica-live WS
// server, then opens replay.html?live=ws://127.0.0.1:<wsPort>, lets it seed from the ZCST
// static prefix and stream FRMx frames, and probes window.__lastTA's first-corner Ax over
// ~2s to PROVE the body's emitted placement MARCHES across the screen — live from the socket,
// SH4 OFF. (Software-WebGPU canvas readback is black, so Ax from the emitted TA is the
// authoritative motion telltale, same as shot_replay.mjs.)
//
//   node tools/render-replica-poc/shot_replay_live.mjs
import puppeteer from 'puppeteer';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { extname, join, normalize } from 'node:path';

const ROOT  = normalize(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const HTTP_PORT = 8131;
const WS_PORT   = 7218;
const REC = join(ROOT, '_ryu_capture', 'mc_render_rec_synth.bin');

const MIME = { '.html':'text/html', '.mjs':'text/javascript', '.js':'text/javascript', '.wasm':'application/wasm', '.bin':'application/octet-stream', '.json':'application/json', '.png':'image/png', '.css':'text/css' };

// --- static server (repo root) ---
const httpd = createServer(async (req, res) => {
    try {
        const url = decodeURIComponent(req.url.split('?')[0]);
        const fp = join(ROOT, url);
        const body = await readFile(fp);
        res.writeHead(200, { 'content-type': MIME[extname(fp)] || 'application/octet-stream' });
        res.end(body);
    } catch { res.writeHead(404); res.end('404'); }
});
await new Promise(r => httpd.listen(HTTP_PORT, r));
console.log(`[shot-live] static http://127.0.0.1:${HTTP_PORT} -> ${ROOT}`);

// --- mock replica-live WS server (child process) ---
const mock = spawn(process.execPath, [join(ROOT, 'tools', 'render-replica-poc', 'mock_replica_live_server.mjs'), REC, String(WS_PORT), '60'], { stdio: 'inherit' });
await new Promise(r => setTimeout(r, 1200));

const SOFTWARE = !!process.env.SOFTWARE;
const args = ['--enable-unsafe-webgpu','--enable-webgpu-developer-features','--ignore-gpu-blocklist','--no-sandbox'];
if (SOFTWARE) args.push('--use-webgpu-adapter=swiftshader','--enable-features=Vulkan');
else args.push('--enable-features=Vulkan','--use-angle=vulkan','--use-gl=angle');

const browser = await puppeteer.launch({ headless: process.env.HEADED ? false : 'new', args });
const page = await browser.newPage();
await page.setViewport({ width: 900, height: 820, deviceScaleFactor: 1 });
const logs = [];
page.on('console', m => logs.push('[page] ' + m.text()));
page.on('pageerror', e => logs.push('[pageerror] ' + e.message));

const wsUrl = `ws://127.0.0.1:${WS_PORT}`;
const PAGE = `http://127.0.0.1:${HTTP_PORT}/web/render-replica/replay.html?live=${encodeURIComponent(wsUrl)}`;
await page.goto(PAGE, { waitUntil: 'networkidle0', timeout: 90000 });

// wait until the live stream has seeded + delivered some frames
await page.waitForFunction(() => window.__liveState && window.__liveState().seeded, { timeout: 90000 });
console.log('[shot-live] seeded from ZCST static prefix');

// sample the live TA Ax over ~2.2s
const samples = [];
for (let i = 0; i < 12; i++) {
    await new Promise(r => setTimeout(r, 180));
    const s = await page.evaluate(() => {
        const ta = window.__lastTA; let Ax = NaN;
        if (ta) { const dv = new DataView(ta.buffer, ta.byteOffset, ta.byteLength); Ax = dv.getFloat32(36, true); }
        return { Ax, lastFrame: window.__liveState().lastFrame };
    });
    samples.push(s);
}
await page.screenshot({ path: 'PNG_replay_live.png' });

console.log(logs.slice(-18).join('\n'));
console.log('\nLIVE (body-quad Ax from socket-driven render_frame  |  vframe#):');
let minAx = Infinity, maxAx = -Infinity;
for (const s of samples) {
    if (!isNaN(s.Ax)) { minAx = Math.min(minAx, s.Ax); maxAx = Math.max(maxAx, s.Ax); }
    console.log(`  vframe ${String(s.lastFrame).padStart(2)}: Ax=${isNaN(s.Ax)?'–':s.Ax.toFixed(1)}`);
}
const span = (isFinite(minAx) && isFinite(maxAx)) ? (maxAx - minAx) : 0;
console.log(`\nAx span over live window = ${span.toFixed(1)}px`);
const pass = span > 60;   // the synthetic body marches ~4px/frame; a 2s window covers ample motion
console.log(pass ? 'PASS: replay.html renders a TRANSLATING body LIVE from the WebSocket (SH4 OFF).'
                 : 'FAIL: no live motion observed.');
console.log('screenshot: PNG_replay_live.png');

await browser.close();
httpd.close();
mock.kill();
process.exit(pass ? 0 : 1);
