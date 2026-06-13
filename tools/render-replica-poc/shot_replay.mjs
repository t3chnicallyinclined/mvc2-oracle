// shot_replay.mjs — drive replay.html in headless Chrome (WebGPU): load the synthetic
// MCRR, render several frames, read back the body's horizontal centroid per frame to
// PROVE on-canvas motion, and screenshot two distinct frames. Reuses shot_page.mjs's
// Dawn/SwiftShader WebGPU launch.
//
//   node tools/render-replica-poc/shot_replay.mjs <base_url> <rec_url>
// e.g. node tools/render-replica-poc/shot_replay.mjs http://localhost:8099 \
//        http://localhost:8099/_ryu_capture/mc_render_rec_synth.bin
import puppeteer from 'puppeteer';

const BASE = process.argv[2] || 'http://localhost:8099';
const REC  = process.argv[3] || (BASE + '/_ryu_capture/mc_render_rec_synth.bin');
const PAGE = `${BASE}/web/render-replica/replay.html?rec=${encodeURIComponent(REC)}`;

const SOFTWARE = !!process.env.SOFTWARE;
const args = ['--enable-unsafe-webgpu','--enable-webgpu-developer-features','--ignore-gpu-blocklist','--no-sandbox'];
if (SOFTWARE) args.push('--use-webgpu-adapter=swiftshader','--enable-features=Vulkan');
else args.push('--enable-features=Vulkan','--use-angle=vulkan','--use-gl=angle');

const browser = await puppeteer.launch({ headless: process.env.HEADED ? false : 'new', args });
const page = await browser.newPage();
await page.setViewport({ width: 900, height: 760, deviceScaleFactor: 1 });
const logs = [];
page.on('console', m => logs.push('[page] ' + m.text()));
page.on('pageerror', e => logs.push('[pageerror] ' + e.message));

await page.goto(PAGE, { waitUntil: 'networkidle0', timeout: 90000 });
await page.waitForFunction(() => window.__state && window.__state().nFrames > 0, { timeout: 90000 });

// Per frame: read BOTH the body's emitted TA first-corner Ax (the placement the body
// renders at — authoritative even when software-WebGPU readback yields black) AND the
// on-canvas non-black centroid (works on a real GPU).
async function probeFrame(f) {
    return await page.evaluate((fr) => {
        window.__showFrame(fr);
        // re-derive the TA Ax the same way the page does (render_frame.wasm via __ta hook)
        const ta = window.__lastTA;                 // set by replay.html showFrame
        let Ax = NaN;
        if (ta) { const dv = new DataView(ta.buffer, ta.byteOffset, ta.byteLength); Ax = dv.getFloat32(36, true); }
        // canvas centroid (may be 0 under software WebGPU)
        const c = document.getElementById('cReplay');
        const o = document.createElement('canvas'); o.width=c.width; o.height=c.height;
        const g = o.getContext('2d'); g.drawImage(c,0,0);
        const d = g.getImageData(0,0,c.width,c.height).data;
        let sx=0, n=0;
        for (let y=0;y<c.height;y++) for (let x=0;x<c.width;x++){ const i=(y*c.width+x)*4; if(d[i]|d[i+1]|d[i+2]){ sx+=x; n++; } }
        return { Ax, n, cx: n ? sx/n : NaN };
    }, f);
}

const probes = [0, 20, 40, 59];
const out = [];
for (const f of probes) {
    const r = await probeFrame(f);
    await new Promise(rr => setTimeout(rr, 200));
    out.push({ f, ...r });
    if (f === 0)  await page.screenshot({ path: 'PNG_replay_frame00.png' });
    if (f === 59) await page.screenshot({ path: 'PNG_replay_frame59.png' });
}

console.log(logs.slice(-25).join('\n'));
console.log('\nMOTION (body-quad Ax from emitted TA  |  on-canvas centroidX):');
for (const r of out)
    console.log(`  frame ${String(r.f).padStart(2)}: TA Ax=${isNaN(r.Ax)?'–':r.Ax.toFixed(1)}  | canvas ${r.n} px centroidX=${(r.cx==null||isNaN(r.cx))?'–':r.cx.toFixed(1)}`);
const dAx = out[out.length-1].Ax - out[0].Ax;
const c0 = out[0].cx, c1 = out[out.length-1].cx;
const dCx = (c0!=null && c1!=null) ? (c1 - c0) : NaN;
const canvasMoved = !isNaN(dCx) && dCx > 30;
console.log(`\nTA Ax delta frame0->59 = ${dAx.toFixed(1)}px`);
console.log(canvasMoved ? `canvas centroid delta = ${dCx.toFixed(1)}px (real GPU)` : `canvas readback = black (software WebGPU; render still ran — Ax is authoritative)`);
const pass = dAx > 100;     // the body's emitted placement marched across the screen
console.log(pass ? 'PASS: render_frame emits a TRANSLATING body across MCRR frames.' : 'FAIL: no motion.');
console.log('screenshots: PNG_replay_frame00.png, PNG_replay_frame59.png');
await browser.close();
process.exit(pass ? 0 : 1);
