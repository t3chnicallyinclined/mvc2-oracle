// play_synthetic_rec.mjs — headless node proof that an MCRR plays through render_frame and
// the body TRANSLATES. Parses the MCRR (same logic replay.html uses), seeds the 16MB RAM
// image from the static 'ram16' backdrop, then per frame applies the dynamic regions and
// calls render_frame -> reads the first quad's Ax. If Ax marches across frames, MOTION is
// proven at the parse->patch->render_frame layer (the HTML page adds pvr2 + canvas).
//
//   node tools/render-replica-poc/play_synthetic_rec.mjs [rec.bin]
import { readFileSync } from 'node:fs';
import createRenderFrame from './render_frame_node.mjs';

const REC = process.argv[2] || new URL('../../_ryu_capture/mc_render_rec_synth.bin', import.meta.url).pathname;
const buf = new Uint8Array(readFileSync(REC));
const dv  = new DataView(buf.buffer);

// ---- parse header ----
let p = 0;
const magic = dv.getUint32(p, true); p += 4;
if (magic !== 0x5252434D) throw new Error('bad MCRR magic 0x' + magic.toString(16));
const version  = dv.getUint32(p, true); p += 4;
const nStatic  = dv.getUint32(p, true); p += 4;
const nDynamic = dv.getUint32(p, true); p += 4;
const nFrames  = dv.getUint32(p, true); p += 4;
const vramBytes= dv.getUint32(p, true); p += 4;
const pvrBytes = dv.getUint32(p, true); p += 4;
p += 4; // reserved
console.log(`MCRR v${version}: ${nStatic} static, ${nDynamic} dynamic, ${nFrames} frames, vram=${vramBytes} pvr=${pvrBytes}`);

const rdRegion = () => { const a = dv.getUint32(p,true); const l = dv.getUint32(p+4,true); let t=''; for(let i=0;i<8;i++){const c=buf[p+8+i]; if(c)t+=String.fromCharCode(c);} p+=16; return {addr:a,len:l,tag:t}; };
const staticRegs  = Array.from({length:nStatic },rdRegion);
const dynamicRegs = Array.from({length:nDynamic},rdRegion);

// ---- static payload ----
const vram = buf.subarray(p, p + vramBytes); p += vramBytes;
const pvr  = buf.subarray(p, p + pvrBytes);  p += pvrBytes;
const RAM_SIZE = 16*1024*1024;
const ram = new Uint8Array(RAM_SIZE);
for (const r of staticRegs) {
    const bytes = buf.subarray(p, p + r.len); p += r.len;
    if (r.tag === 'ram16') ram.set(bytes, 0);
    else ram.set(bytes, (r.addr>>>0) & 0xFFFFFF);
}
console.log(`seeded 16MB RAM from static (${staticRegs.map(r=>r.tag).join(',')}), vram ${vram.length}B pvr ${pvr.length}B`);

// ---- frames ----
const Mod = await createRenderFrame();
function renderTA(ramImg) {
    const ptr = Mod._malloc(ramImg.length); Mod.HEAPU8.set(ramImg, ptr);
    const cap = 256*1024, op = Mod._malloc(cap);
    const len = Mod._render_frame_ta(ptr, op, cap);
    const q = Mod._render_frame_quad_count();
    const ta = Mod.HEAPU8.slice(op, op+len);
    Mod._free(ptr); Mod._free(op);
    return { ta, q, len };
}

const FRAME_HEAD = 12;
let firstAx = null, lastAx = null;
for (let f = 0; f < nFrames; f++) {
    const fmagic = dv.getUint32(p, true);
    if (fmagic !== 0x784D5246) throw new Error(`frame ${f}: bad FRMx magic 0x${fmagic.toString(16)}`);
    const vframe = dv.getUint32(p+4, true);
    const taSize = dv.getUint32(p+8, true);
    p += FRAME_HEAD;
    for (const r of dynamicRegs) {
        ram.set(buf.subarray(p, p + r.len), (r.addr>>>0) & 0xFFFFFF);
        p += r.len;
    }
    const engTa = taSize ? buf.subarray(p, p + taSize) : null; p += taSize;

    const { ta, q, len } = renderTA(ram);
    const tdv = new DataView(ta.buffer, ta.byteOffset, ta.byteLength);
    const Ax = q > 0 ? tdv.getFloat32(36, true) : NaN;
    if (firstAx === null) firstAx = Ax;
    lastAx = Ax;

    let gt = '';
    if (engTa) {
        const tot = Math.min(engTa.length, len);
        let pOK = 0, pN = 0;
        for (let o = 0; o + 96 <= tot; o += 96) { pN++; let ok = 1; for (let i = 0; i < 16; i++) if (engTa[o+i] !== ta[o+i]) { ok = 0; break; } pOK += ok; }
        let whole = 0; for (let i = 0; i < tot; i++) if (engTa[i] === ta[i]) whole++;
        gt = `  GT params ${pOK}/${pN} ${pOK===pN?'PASS':'FAIL'} · bytes ${(100*whole/tot).toFixed(0)}%`;
    } else gt = '  GT skipped (synthetic)';
    if (f % 10 === 0 || f === nFrames-1)
        console.log(`frame ${f} vframe=${vframe} quads=${q} ta=${len}B Ax=${Ax.toFixed(1)}${gt}`);
}
console.log(`\nMOTION: first-frame Ax=${firstAx.toFixed(1)} -> last-frame Ax=${lastAx.toFixed(1)}  (Δ=${(lastAx-firstAx).toFixed(1)}px)`);
console.log((lastAx - firstAx) > 50 ? 'PASS: body translated across frames.' : 'FAIL: no motion detected.');
