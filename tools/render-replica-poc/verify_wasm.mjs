// verify_wasm.mjs — confirm render_replica.wasm emits the SAME TA bytes as the
// proven byte-exact ta_buffer.bin (built by test_ta_emit.exe).
import { readFileSync } from 'node:fs';
import createRenderReplica from '../../web/render-replica/render_replica.mjs';

const RYU = new URL('../../_ryu_capture/', import.meta.url);
const ram = new Uint8Array(readFileSync(new URL('mc_ram_dump.bin', RYU)));   // 16MB
const ref = new Uint8Array(readFileSync(new URL('ta_buffer.bin', import.meta.url)));

const Mod = await createRenderReplica();
const ramPtr = Mod._malloc(ram.length);
Mod.HEAPU8.set(ram, ramPtr);
const cap = 64 * 1024;
const outPtr = Mod._malloc(cap);

const NODE = 0x8C2688E4 >>> 0;   // P2C1 / Cable resident body node
const len = Mod._render_object(ramPtr, NODE, outPtr, cap);
const quads = Mod._render_object_quad_count();
const caps  = Mod._render_object_capture_count();
const out = Mod.HEAPU8.slice(outPtr, outPtr + len);
Mod._free(ramPtr); Mod._free(outPtr);

console.log(`wasm: ta_len=${len}B quads=${quads} captures=${caps}  ref=${ref.length}B`);
let diff = 0, first = -1;
const n = Math.max(len, ref.length);
for (let i = 0; i < n; i++) { if ((out[i] | 0) !== (ref[i] | 0)) { diff++; if (first < 0) first = i; } }
console.log(diff === 0 && len === ref.length
    ? `BYTE-EXACT: render_replica.wasm output == ta_buffer.bin (${len} bytes)`
    : `MISMATCH: ${diff} differing bytes (first @${first}), len ${len} vs ${ref.length}`);
process.exit(diff === 0 && len === ref.length ? 0 : 1);
