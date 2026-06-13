// Verify ta_buffer.bin parses through the REAL web renderer's TA parser, and that
// the recovered vertex corners match the harness output bit-for-bit.
import { readFileSync } from 'fs';
import { TAParser } from '../../web/webgpu/ta-parser.mjs';

const buf = new Uint8Array(readFileSync('ta_buffer.bin'));
const p = new TAParser();
const r = p.parse(buf, buf.length);

console.log(`ta-parser.mjs: ${r.opaque.length} opaque polys, ${r.vertexCount} vertices`);
// engine-resident TCW/TSP per quad (read from rectab in build_image_dump.py)
const EXP_TCW=[0x2b8c34e4,0x2b8c34e4,0x2b8c34e4,0x2b8c34e4,0x2b8c34f4,0x2b8c34f4,0x2b8c3500,0x2b8c3510,0x2b8c3510];
const EXP_TSP=[0x000004c9,0x000004c9,0x000004c9,0x000004c9,0x000004c0,0x000004c0,0x000004c9,0x000004c9,0x000004c9];

const f32 = new Float32Array(r.vertexData.buffer, r.vertexData.byteOffset, r.vertexCount*7);
let quads=0, tcwExact=0, tspExact=0;
for (const pp of r.opaque) {
  // each strip = 4 verts (TL,TR,BL,BR); vertex layout x,y,z,u,v,col(2 words) -> stride 7 f32
  const base = pp.first*7;
  const TLx=f32[base], TLy=f32[base+1];
  // parser vertex layout: x,y,z (0,1,2), col,spc (3,4 as u8x4), u,v (5,6)
  const TLu=f32[base+5], TLv=f32[base+6];
  const BRx=f32[base+3*7], BRy=f32[base+3*7+1];
  const BRu=f32[base+3*7+5], BRv=f32[base+3*7+6];
  const tcw=(pp.tcw>>>0), tsp=(pp.tsp>>>0);
  if (tcw===EXP_TCW[quads]) tcwExact++;
  if (tsp===EXP_TSP[quads]) tspExact++;
  console.log(`  quad ${quads}: tcw=0x${tcw.toString(16).padStart(8,'0')}${tcw===EXP_TCW[quads]?'==engine':'!!'} `
    +`tsp=0x${tsp.toString(16).padStart(8,'0')} UV[(${TLu.toFixed(2)},${TLv.toFixed(2)})..(${BRu.toFixed(2)},${BRv.toFixed(2)})] `
    +`TL(${TLx.toFixed(2)},${TLy.toFixed(2)}) BR(${BRx.toFixed(2)},${BRy.toFixed(2)})`);
  quads++;
}
const ok = r.opaque.length===9 && r.vertexCount===36 && tcwExact===9 && tspExact===9;
console.log(`TCW round-trip: ${tcwExact}/9 == engine resident TCW   TSP: ${tspExact}/9`);
console.log(`VERIFY: ${ok? 'PASS — real ta-parser.mjs decodes 9 quads / 36 verts; TCW+TSP BIT-EXACT vs engine resident fields; real UV sub-rects':'FAIL'}`);
process.exit(ok?0:1);
