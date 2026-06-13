// REPRODUCE the grid + isolate it to the INPUT: run the transpiled render_frame.wasm over
// the captured live prefix+frame (the client's exact RAM image), and report per-quad sels.
// A coherent body emits a SPREAD of distinct sels; a grid emits ONE sel repeated.
//   node repro_grid.mjs live2.mcrr [frameIndex]
import { readFileSync } from 'node:fs';
import createRenderFrame from './render_frame_node.mjs';

const path = process.argv[2] || 'live2.mcrr';
const wantF = +(process.argv[3] ?? 0);
const buf = new Uint8Array(readFileSync(path));
const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
let p=0; const u32=()=>{const v=dv.getUint32(p,true);p+=4;return v>>>0;};
if(u32()!==0x5252434D) throw new Error('bad MCRR');
u32(); const nStatic=u32(), nDynamic=u32(), nFrames=u32(), vramBytes=u32(), pvrBytes=u32(); u32();
const region=()=>{const addr=u32(),len=u32();let tag='';for(let i=0;i<8;i++){const c=buf[p+i];if(c)tag+=String.fromCharCode(c);}p+=8;return{addr,len,tag};};
const staticRegs=Array.from({length:nStatic},region);
const dynamicRegs=Array.from({length:nDynamic},region);
p+=vramBytes; p+=pvrBytes;
const staticData=staticRegs.map(r=>{const b=buf.subarray(p,p+r.len);p+=r.len;return b;});
const frameStart=p;

const RAM=16*1024*1024;
const ram=new Uint8Array(RAM);
staticRegs.forEach((r,i)=>{ if(r.tag==='ram16') ram.set(staticData[i],0); else ram.set(staticData[i], r.addr&0xFFFFFF); });

// seek to frame wantF
let q=frameStart;
for(let f=0; f<wantF; f++){ let len=12; for(const r of dynamicRegs) len+=r.len; len+=dv.getUint32(q+8,true); q+=len; }
const vframe=dv.getUint32(q+4,true), taSize=dv.getUint32(q+8,true);
{ let o=q+12; for(const r of dynamicRegs){ ram.set(buf.subarray(o,o+r.len), r.addr&0xFFFFFF); o+=r.len; } }

const M = await createRenderFrame({ locateFile:(p)=>p });
const ramPtr=M._malloc(ram.length); M.HEAPU8.set(ram, ramPtr);
const cap=256*1024, outPtr=M._malloc(cap);
const len=M._render_frame_ta(ramPtr, outPtr, cap);
const quads=M._render_frame_quad_count();
const bodies=M._render_frame_body_count();
const selPtr=M._malloc(quads*2||2), gfxPtr=M._malloc(quads*4||4);
M._render_frame_quad_sels(selPtr, quads);
M._render_frame_quad_gfx1s(gfxPtr, quads);
const sels=new Uint16Array(M.HEAPU8.buffer.slice(selPtr, selPtr+quads*2));
const gfxs=new Uint32Array(M.HEAPU8.buffer.slice(gfxPtr, gfxPtr+quads*4));

// group quads by owning gfx1 (=body) and show the sel distribution per body
const byGfx=new Map();
for(let i=0;i<quads;i++){ const g=gfxs[i]>>>0; if(!byGfx.has(g)) byGfx.set(g,[]); byGfx.get(g).push(sels[i]); }
console.log(`${path} frame ${wantF} vframe=${vframe} taSize(carried)=${taSize} -> quads=${quads} bodies=${bodies}`);
for(const [g,ss] of byGfx){
  const uniq=new Set(ss);
  const grid = uniq.size<=2 && ss.length>=6;
  console.log(`  gfx1=${g.toString(16)} quads=${ss.length} distinctSels=${uniq.size} ${grid?'<<< GRID (one part repeated)':'(coherent)'}`);
  console.log(`     sels: ${ss.join(',')}`);
}
M._free(selPtr);M._free(gfxPtr);M._free(ramPtr);M._free(outPtr);
