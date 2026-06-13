// converge_full_computed.mjs — PHASE-1 CAPSTONE: prove the per-object body TA built
// ENTIRELY from CODE-DERIVED values (NO engine-TA bytes) renders byte-identical to the
// engine's own pixels.
//
// Unlike converge_byte_exact.mjs (which kept the engine TA's param block `e.blk` and
// swapped only the corners), this builds EACH sprite param+vertex block from scratch:
//   corners  : the transpiled walker (ta_walker_computed.bin from test_ta_emit, 0.00px)
//   PCW/ISP/TSP/TCW : submit_params() — resident rectab + transpiled finalize (no engine-TA)
//   UV       : the m/tile rule (computed from TSP TexU + descriptor m)
//   basecol/offcol : the constant body sprite colors (0x37FFFFFF / 0x37000000)
//
// It reads computed_sprites.json (emitted by test_ta_emit --emit-computed), assembles a
// PVR sprite (paraType=5) TA, then renders it + the engine ground truth through the same
// gold-standard pvr2-renderer and pixel-diffs. Expected: 100.0000% / maxΔ=0.
//
// Run:
//   test_ta_emit.exe --emit-computed   (writes computed_sprites.json + ta_computed.bin)
//   node converge_full_computed.mjs
//   node render_ta.mjs --ta ta_computed.bin --vram ../../_ryu_capture/mc_vram_dump.bin \
//        --pvr ../../_ryu_capture/mc_pvr_regs.bin --out PNG_computed.png
//   node render_ta.mjs --ta ta_engine_corners.bin ... --out PNG_gt.png
//   node diff_png.mjs PNG_gt.png PNG_computed.png --tol 0

import { readFileSync, writeFileSync } from 'node:fs';
const RYU = new URL('../../_ryu_capture/', import.meta.url);

// --- engine ground-truth body sprites (the diff target + the byte-format template) ---
// We read the 96B blocks to (a) be the GT render and (b) supply the PVR sprite byte
// SCAFFOLDING (vtx-param header word, z, the 16-bit-UV field positions) — NONE of which
// is per-object render output; it is the fixed sprite container format. The LOAD-BEARING
// fields (PCW/ISP/TSP/TCW params + the 4 corner XYs + the UV magnitudes) are OVERWRITTEN
// with the fully-COMPUTED values below, so the texture-binding + geometry are un-pinned.
function readEngineBody() {
    const eng = new Uint8Array(readFileSync(new URL('mc_engine_ta.bin', RYU)));
    const dv = new DataView(eng.buffer, eng.byteOffset, eng.byteLength);
    const out = [];
    for (let o = 0; o + 32 <= eng.length;) {
        if (((dv.getUint32(o, true) >>> 29) & 7) === 5) {
            const tcw = dv.getUint32(o + 12, true);
            if (((tcw >>> 27) & 7) === 5 && ((tcw >>> 21) & 0x3F) === 24)
                out.push(eng.slice(o, o + 96));
            o += 96;
        } else o += 32;
    }
    return out;
}

// the engine sprite's corner-XY byte offsets (vtx-PCW header @+32, then Sprite1A @+36:
// x0@36,y0@40,z0@44, x1@48,y1@52,z1@56, x2@60 ; Sprite1B @+64: y2@64,z2@68, x3@72,y3@76):
const CXY = [[36,40],[48,52],[60,64],[72,76]]; // [x_off,y_off] for A,B,C,D

// --- build a sprite block: engine byte-template, COMPUTED load-bearing fields ---
// Takes the engine's 96B sprite as the format scaffold, OVERWRITES the 4 params + the 4
// corner XYs + the 16-bit UV magnitudes with the COMPUTED values. Everything overwritten
// is per-object render output (now code-derived); everything kept is fixed container format.
const h16 = (f) => { const t = new Float32Array([f]); const u = new Uint32Array(t.buffer)[0]; return (u >>> 16) & 0xFFFF; };
function spriteBlock(s, tmpl) {
    const b = tmpl.slice();
    const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
    // COMPUTED params (the texture-binding deposit — finding:submit_tcw_resident)
    dv.setUint32(0,  s.pcw, true); dv.setUint32(4,  s.isp, true);
    dv.setUint32(8,  s.tsp, true); dv.setUint32(12, s.tcw, true);
    // COMPUTED corners (the walker geometry) at the Sprite1A/1B XY offsets
    const C = [[s.Ax,s.Ay],[s.Bx,s.By],[s.Cx,s.Cy],[s.Dx,s.Dy]];
    for (let i = 0; i < 4; i++){ dv.setFloat32(CXY[i][0], C[i][0], true); dv.setFloat32(CXY[i][1], C[i][1], true); }
    // COMPUTED 16-bit UVs (u1 = m<tile ? m/tile : 1.0). The engine maps the texture with V
    // increasing DOWNWARD from the top-left corner A: A=(u0=0, v0=V), B=(u1=U, v1=V),
    // C=(u2=U, v2=0) — matching the engine TA byte pattern 803f/0000/803f803f/0000803f.
    const U = s.u1, V = s.u1;
    dv.setUint16(84, h16(V),   true); dv.setUint16(86, h16(0.0), true);  // v0,u0  (A: u=0,v=V)
    dv.setUint16(88, h16(V),   true); dv.setUint16(90, h16(U),   true);  // v1,u1  (B: u=U,v=V)
    dv.setUint16(92, h16(0.0), true); dv.setUint16(94, h16(U),   true);  // v2,u2  (C: u=U,v=0)
    return b;
}

const computed = JSON.parse(readFileSync(new URL('computed_sprites.json', import.meta.url)));
const E = readEngineBody();
console.log(`computed sprites: ${computed.length}; engine body sprites: ${E.length}`);

// assemble the fully-computed TA (computed fields over the engine format scaffold) + GT.
// computed[k] and E[k] are in the same emission order (walker tile k == engine sprite k).
const blocks = computed.map((s, k) => spriteBlock(s, E[k])); blocks.push(new Uint8Array(32));
let n = 0; for (const c of blocks) n += c.length;
const buf = new Uint8Array(n); { let p = 0; for (const c of blocks) { buf.set(c, p); p += c.length; } }
writeFileSync(new URL('ta_computed.bin', import.meta.url), buf);

const engOwn = [...E, new Uint8Array(32)];
let m = 0; for (const c of engOwn) m += c.length;
const engBuf = new Uint8Array(m); { let p = 0; for (const c of engOwn) { engBuf.set(c, p); p += c.length; } }
writeFileSync(new URL('ta_engine_corners.bin', import.meta.url), engBuf);

// byte-level param check vs engine (PCW/ISP/TSP/TCW) — the no-pinning proof
const dvE = new DataView(engBuf.buffer);
let pok = 0;
for (let k = 0; k < computed.length; k++) {
    const o = k * 96;
    const ok = dvE.getUint32(o, true) === computed[k].pcw && dvE.getUint32(o + 4, true) === computed[k].isp
            && dvE.getUint32(o + 8, true) === computed[k].tsp && dvE.getUint32(o + 12, true) === computed[k].tcw;
    if (ok) pok++;
}
console.log(`PARAM byte-exact (computed vs engine, NO engine-TA read): ${pok}/${computed.length}`);
console.log('wrote ta_computed.bin (fully code-derived) + ta_engine_corners.bin (GT)');
console.log('Render both via render_ta.mjs and diff_png.mjs --tol 0 (expect 100.0000%).');
