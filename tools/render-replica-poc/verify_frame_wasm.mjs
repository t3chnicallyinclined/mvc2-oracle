// verify_frame_wasm.mjs — confirm render_frame.wasm (the WHOLE-FRAME slot-walk) emits
// the SAME scene TA as the native render_frame_test (frame_sprites.json), feeding the
// REAL 16MB RAM dump (NOT a baked image — the slot-walk enumerates bodies live).
import { readFileSync } from 'node:fs';
import createRenderFrame from './render_frame_node.mjs';

const RYU = new URL('../../_ryu_capture/', import.meta.url);
const ram = new Uint8Array(readFileSync(new URL('mc_ram_dump.bin', RYU)));   // 16MB, verbatim LE
const ref = JSON.parse(readFileSync(new URL('frame_sprites.json', import.meta.url)));

const Mod = await createRenderFrame();
const ramPtr = Mod._malloc(ram.length); Mod.HEAPU8.set(ram, ramPtr);
const cap = 256*1024; const outPtr = Mod._malloc(cap);

const len  = Mod._render_frame_ta(ramPtr, outPtr, cap);
const bodies = Mod._render_frame_body_count();
const quads  = Mod._render_frame_quad_count();
const out = Mod.HEAPU8.slice(outPtr, outPtr+len);
Mod._free(ramPtr); Mod._free(outPtr);

const dv = new DataView(out.buffer, out.byteOffset, out.byteLength);
console.log(`wasm render_frame: bodies=${bodies} quads=${quads} ta_len=${len}B  (native ref: ${ref.length} quads)`);

let pok=0, cok=0;
for(let k=0;k<Math.min(quads,ref.length);k++){
    const o=k*96;
    const pcw=dv.getUint32(o,true), isp=dv.getUint32(o+4,true), tsp=dv.getUint32(o+8,true), tcw=dv.getUint32(o+12,true);
    const Ax=dv.getFloat32(o+36,true), Ay=dv.getFloat32(o+40,true);
    const r=ref[k];
    if(pcw===r.pcw>>>0 && isp===r.isp>>>0 && tsp===r.tsp>>>0 && tcw===r.tcw>>>0) pok++;
    if(Math.abs(Ax-r.Ax)<1e-3 && Math.abs(Ay-r.Ay)<1e-3) cok++;
}
console.log(`PARAM match wasm-vs-native: ${pok}/${ref.length}   CORNER match: ${cok}/${ref.length}`);
const ok = (quads===ref.length && pok===ref.length && cok===ref.length);
console.log(ok ? `WASM-VERIFY: render_frame.wasm == native render_frame (${quads} body tiles, from live 16MB RAM)`
              : `WASM-VERIFY MISMATCH`);
process.exit(ok?0:1);
