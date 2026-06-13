// converge_frame.mjs — PHASE-2 pixel proof: render the FULL-SCENE BODY TA built by
// render_frame (frame_sprites.json — all bodies the slot-walk produced) through the
// gold-standard pvr2-renderer and diff vs the engine's own body pixels.
//
// Reuses the proven converge_full_computed.mjs scaffolding: take each engine 96B sprite
// as the fixed PVR container format, OVERWRITE the load-bearing fields (PCW/ISP/TSP/TCW +
// 4 corners + UV) with render_frame's COMPUTED values. Identical to Phase 1 but the
// sprites now come from the slot-walk's whole-scene accumulator (frame_sprites.json),
// proving the multi-object root walk + cursor produce the engine's body TA.
import { readFileSync, writeFileSync } from 'node:fs';
const RYU = new URL('../../_ryu_capture/', import.meta.url);

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
const CXY = [[36,40],[48,52],[60,64],[72,76]];
const h16 = (f) => { const t=new Float32Array([f]); const u=new Uint32Array(t.buffer)[0]; return (u>>>16)&0xFFFF; };
function spriteBlock(s, tmpl) {
    const b = tmpl.slice();
    const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
    dv.setUint32(0, s.pcw, true); dv.setUint32(4, s.isp, true);
    dv.setUint32(8, s.tsp, true); dv.setUint32(12, s.tcw, true);
    const C = [[s.Ax,s.Ay],[s.Bx,s.By],[s.Cx,s.Cy],[s.Dx,s.Dy]];
    for (let i=0;i<4;i++){ dv.setFloat32(CXY[i][0],C[i][0],true); dv.setFloat32(CXY[i][1],C[i][1],true); }
    const U=s.u1, V=s.u1;
    dv.setUint16(84,h16(V),true); dv.setUint16(86,h16(0.0),true);
    dv.setUint16(88,h16(V),true); dv.setUint16(90,h16(U),true);
    dv.setUint16(92,h16(0.0),true); dv.setUint16(94,h16(U),true);
    return b;
}

const computed = JSON.parse(readFileSync(new URL('frame_sprites.json', import.meta.url)));
const E = readEngineBody();
console.log(`render_frame scene sprites: ${computed.length}; engine body sprites: ${E.length}`);
if (computed.length !== E.length)
    console.log(`NOTE: count differs — engine frame has ${E.length} body sprites (this capture = single body).`);

const blocks = computed.map((s,k)=>spriteBlock(s, E[k % E.length])); blocks.push(new Uint8Array(32));
let n=0; for(const c of blocks) n+=c.length;
const buf=new Uint8Array(n); { let p=0; for(const c of blocks){ buf.set(c,p); p+=c.length; } }
writeFileSync(new URL('ta_frame_render.bin', import.meta.url), buf);

const engOwn=[...E,new Uint8Array(32)]; let m=0; for(const c of engOwn) m+=c.length;
const engBuf=new Uint8Array(m); { let p=0; for(const c of engOwn){ engBuf.set(c,p); p+=c.length; } }
writeFileSync(new URL('ta_frame_engine.bin', import.meta.url), engBuf);

const dvE=new DataView(engBuf.buffer); let pok=0;
for(let k=0;k<Math.min(computed.length,E.length);k++){
    const o=k*96;
    if (dvE.getUint32(o,true)===computed[k].pcw && dvE.getUint32(o+4,true)===computed[k].isp
     && dvE.getUint32(o+8,true)===computed[k].tsp && dvE.getUint32(o+12,true)===computed[k].tcw) pok++;
}
console.log(`PARAM byte-exact (render_frame vs engine): ${pok}/${Math.min(computed.length,E.length)}`);
console.log('wrote ta_frame_render.bin (slot-walk scene) + ta_frame_engine.bin (engine GT)');
