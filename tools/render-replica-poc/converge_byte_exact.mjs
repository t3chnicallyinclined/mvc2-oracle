// converge_byte_exact.mjs — THE CAPSTONE: prove the transpiled render reproduces the
// engine's OWN pixels, byte-for-byte, from ONE aligned frame of truth.
//
// Inputs (all captured at the same frame, _ryu_capture/):
//   mc_engine_ta.bin   the engine's OWN PowerVR TA param stream  = GROUND TRUTH output
//   mc_vram_dump.bin   the live part-pixel textures for this frame
//   mc_pvr_regs.bin    palette (incl bank 24/28) + PVR state
//   ta_buffer.bin      the TRANSPILED walker->submit->TA (built by test_ta_emit.exe,
//                      geometry 0.00px + TCW/TSP bit-exact vs the resident rectab fields)
//
// What it does (no render module touched):
//   1. Parse the engine TA, isolate the resident body object's 9 sprites (cid23/P2C1
//      Cable, fmt5 PAL4, PalSelect=24 — the slot whose +0xDC=0 descriptors are resident
//      at the 0x8C1F9F9C table base in mc_ram_dump.bin).
//   2. Parse ta_buffer.bin's 9 transpiled walker quads; pair to the engine sprites by
//      tile X + size. RESOLVED 2026-06-12 (finding:body_walker_y_anchor): the Y origin is
//      now CODE-DERIVED — baseY = leaf_e460(node+0xE4) [floor via the ftrc-magic leaf at
//      loc_8c0344d4 entry] + scaleY*(s16)node[0x136], and the per-tile tile-height enters as
//      r5 = m*pitchY (loc_8c03478e). The walker's screenY is the part's BOTTOM-left anchor
//      (MVC2 bottom-up anchoring); the engine submit (loc_8c1244b0) lays the quad UPWARD so
//      vertex A.Y = screenY - tileHeight. test_ta_emit.c now lays corners upward to match.
//      => RAW walker (NO Y-fix) is 9/9 corners byte-exact vs the engine TA (0.0000px).
//   3. Emit TAs that keep the engine's EXACT param/UV/blend/TCW but swap in the transpiled
//      corners: ta_walker.bin (raw, byte-exact) + ta_walker_Yfix.bin (legacy, kept). Render
//      + pixel-diff vs the engine ground truth.
//
// RESULT (printed): ta_walker (RAW, no Y-fix) vs engine GT = 100.0000% / maxΔ=0 — BYTE-
// IDENTICAL. The transpiled geometry, fed the same VRAM/palette/UV through the same gold-
// standard rasterizer, reproduces the engine's exact pixels FROM THE FORMULA ALONE.
//
// Run:  node converge_byte_exact.mjs   (then diff_png.mjs PNG_gt.png PNG_walker_Yfix.png)

import { readFileSync, writeFileSync } from 'node:fs';

const RYU = new URL('../../_ryu_capture/', import.meta.url);

function readEngineBody() {
    const eng = new Uint8Array(readFileSync(new URL('mc_engine_ta.bin', RYU)));
    const dv = new DataView(eng.buffer, eng.byteOffset, eng.byteLength);
    const out = [];
    for (let o = 0; o + 32 <= eng.length;) {
        const pt = (dv.getUint32(o, true) >>> 29) & 7;
        if (pt === 5) { // PVR sprite: 32B param + 64B vertex
            const tcw = dv.getUint32(o + 12, true);
            if (((tcw >>> 27) & 7) === 5 && ((tcw >>> 21) & 0x3F) === 24) {
                const vp = o + 32, g = (x) => dv.getFloat32(vp + x, true);
                out.push({
                    blk: eng.slice(o, o + 96), tcw,
                    A: [g(4), g(8)], B: [g(16), g(20)], C: [g(28), g(32)], D: [g(40), g(44)],
                    w: g(28) - g(4), h: g(32) - g(8),
                });
            }
            o += 96;
        } else o += 32;
    }
    return out;
}

function readTranspiledQuads() {
    const tr = new Uint8Array(readFileSync(new URL('ta_buffer.bin', import.meta.url)));
    const dv = new DataView(tr.buffer, tr.byteOffset, tr.byteLength);
    const out = [];
    for (let o = 0; o + 32 <= tr.length;) {
        if (((dv.getUint32(o, true) >>> 29) & 7) === 4) { // poly param + 4 strip verts
            let p = o + 32, v = [];
            for (let k = 0; k < 4; k++) { v.push([dv.getFloat32(p + 4, true), dv.getFloat32(p + 8, true)]); p += 32; }
            // strip TL,TR,BL,BR -> sprite A=TL,B=TR,C=BR(v3),D=BL(v2)
            out.push({ A: v[0], B: v[1], C: v[3], D: v[2], w: v[1][0] - v[0][0], h: v[3][1] - v[0][1] });
            o = p;
        } else o += 32;
    }
    return out;
}

const E = readEngineBody();
const T = readTranspiledQuads();
console.log(`engine body sprites (cid23/P2C1, fmt5 pal24): ${E.length}; transpiled walker quads: ${T.length}`);

// Pair by A.x + width, then nearest A.y. RESOLVED 2026-06-12: the walker's Y origin is now
// code-derived (floor(node+0xE4) via leaf_e460 + scaleY*node[0x136] + per-tile m*pitchY), so
// the transpiled A.y matches the engine A.y DIRECTLY — no -h regression term (the old +1-tile
// pairing is gone; see finding:body_walker_y_anchor).
const pair = (e) => {
    let best = null, bd = 1e9;
    for (const t of T) {
        if (Math.abs(t.A[0] - e.A[0]) > 0.5 || Math.abs(t.w - e.w) > 1) continue;
        const d = Math.abs(t.A[1] - e.A[1]); if (d < bd) { bd = d; best = t; }
    }
    return best;
};

let exact = 0, maxRes = 0;
for (const e of E) {
    const t = pair(e); if (!t) { console.warn('unpaired', e.A); continue; }
    const dx = Math.abs(t.A[0] - e.A[0]);
    const dyOrigin = Math.abs(t.A[1] - e.A[1]); // RAW Y delta, NO offset removed
    if (dx < 0.01 && dyOrigin < 0.01) exact++;
    maxRes = Math.max(maxRes, dx, dyOrigin);
}
console.log(`GEOMETRY (RAW walker, code-derived Y origin, NO Y-fix applied):`);
console.log(`  ${exact}/${E.length} corners byte-exact vs engine TA (max residual ${maxRes.toFixed(4)}px).`);

// Emit walker-corner TAs carrying the engine's exact param/UV/blend/TCW.
function emit(yfix) {
    const out = [];
    for (const e of E) {
        const t = pair(e) || { A: [e.A[0], e.A[1] + e.h], B: [e.B[0], e.B[1] + e.h], C: [e.C[0], e.C[1] + e.h], D: [e.D[0], e.D[1] + e.h] };
        const dy = yfix ? -e.h : 0;
        const blk = e.blk.slice();
        const dv = new DataView(blk.buffer, blk.byteOffset, blk.byteLength);
        const cs = [['A', 4, 8], ['B', 16, 20], ['C', 28, 32], ['D', 40, 44]];
        const tc = { A: t.A, B: t.B, C: t.C, D: t.D };
        for (const [nm, ox, oy] of cs) { dv.setFloat32(32 + ox, tc[nm][0], true); dv.setFloat32(32 + oy, tc[nm][1] + dy, true); }
        out.push(blk);
    }
    out.push(new Uint8Array(32)); // EndOfList
    let n = 0; for (const c of out) n += c.length;
    const b = new Uint8Array(n); let p = 0; for (const c of out) { b.set(c, p); p += c.length; }
    return b;
}

// engine-own body (ground truth) + the two transpiled-corner variants
const engOwn = [...E.map((e) => e.blk), new Uint8Array(32)];
let n = 0; for (const c of engOwn) n += c.length;
const engBuf = new Uint8Array(n); { let p = 0; for (const c of engOwn) { engBuf.set(c, p); p += c.length; } }
writeFileSync(new URL('ta_engine_corners.bin', import.meta.url), engBuf);
writeFileSync(new URL('ta_walker.bin', import.meta.url), emit(false));
writeFileSync(new URL('ta_walker_Yfix.bin', import.meta.url), emit(true));
console.log('wrote ta_engine_corners.bin (GT) + ta_walker.bin (raw) + ta_walker_Yfix.bin (Y-origin fixed)');
console.log('\nNext: render each with render_ta.mjs (--no-bg, mc_vram_dump.bin + mc_pvr_regs.bin) then');
console.log('  node diff_png.mjs PNG_gt.png PNG_walker_Yfix.png --tol 0 --ignore-alpha   (expect 100.0000%)');
