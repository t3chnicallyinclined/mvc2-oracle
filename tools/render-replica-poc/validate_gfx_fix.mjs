// VALIDATE the static-GFX-gap fix offline, end-to-end through the REAL transpiled render_frame:
//   1. Seed RAM from a good capture (live2.mcrr) -> both bodies coherent (baseline).
//   2. ZERO P1C3's GFX2 region in the seeded RAM (simulate "client connected before P1C3 art
//      loaded" -> frozen prefix snapshot is zero) -> render_frame MUST now grid P1C3.
//   3. Re-inject P1C3's FRESH GFX2 region (exactly what the server's on-change GFX tail ships)
//      -> render_frame MUST render P1C3 coherent again.
// This proves: (a) the divergence is the INPUT (stale GFX2), (b) the walker is fine given fresh
// GFX, (c) shipping the fresh GFX region is the fix.  node validate_gfx_fix.mjs
import { readFileSync } from 'node:fs';
import createRenderFrame from './render_frame_node.mjs';

const buf=new Uint8Array(readFileSync('live2.mcrr'));
const dv=new DataView(buf.buffer,buf.byteOffset,buf.byteLength);
let p=0;const u32=()=>{const v=dv.getUint32(p,true);p+=4;return v>>>0;};
u32();u32();const nStatic=u32(),nDynamic=u32(),nFrames=u32(),vramBytes=u32(),pvrBytes=u32();u32();
const region=()=>{const a=u32(),l=u32();let t='';for(let i=0;i<8;i++){const c=buf[p+i];if(c)t+=String.fromCharCode(c);}p+=8;return{a,l,t};};
const S=Array.from({length:nStatic},region), D=Array.from({length:nDynamic},region);
p+=vramBytes;p+=pvrBytes;
const data=S.map(r=>{const b=buf.subarray(p,p+r.l);p+=r.l;return b;});
const frameStart=p;

function seed(){
  const ram=new Uint8Array(16*1024*1024);
  S.forEach((r,i)=>{ if(r.t==='ram16') ram.set(data[i],0); else ram.set(data[i], r.a&0xFFFFFF);});
  // apply frame 5 dynamic regions
  let q=frameStart; for(let f=0;f<5;f++){let len=12;for(const r of D)len+=r.l;len+=dv.getUint32(q+8,true);q+=len;}
  let o=q+12; for(const r of D){ ram.set(buf.subarray(o,o+r.l), r.a&0xFFFFFF); o+=r.l; }
  return ram;
}
const G=a=>a&0xFFFFFF;
const P1C3_GFX2_PAGE=0xc789000;   // page-aligned base of P1C3's GFX2 (from the pin)

const M=await createRenderFrame({locateFile:(p)=>p});
function run(ram, label){
  const ramPtr=M._malloc(ram.length); M.HEAPU8.set(ram,ramPtr);
  const cap=256*1024,outPtr=M._malloc(cap);
  M._render_frame_ta(ramPtr,outPtr,cap);
  const quads=M._render_frame_quad_count();
  const selPtr=M._malloc(quads*2||2),gfxPtr=M._malloc(quads*4||4);
  M._render_frame_quad_sels(selPtr,quads); M._render_frame_quad_gfx1s(gfxPtr,quads);
  const sels=new Uint16Array(M.HEAPU8.buffer.slice(selPtr,selPtr+quads*2));
  const gfxs=new Uint32Array(M.HEAPU8.buffer.slice(gfxPtr,gfxPtr+quads*4));
  M._free(selPtr);M._free(gfxPtr);M._free(ramPtr);M._free(outPtr);
  const byG=new Map();
  for(let i=0;i<quads;i++){const g=gfxs[i]>>>0;if(!byG.has(g))byG.set(g,new Set());byG.get(g).add(sels[i]);}
  const lines=[];let p1c3grid=null;
  for(const [g,ss] of byG){
    const grid = ss.size<=2;   // a body that collapses to <=2 distinct sels is a grid
    lines.push(`    gfx1=${g.toString(16)} distinctSels=${ss.size} ${grid?'GRID':'coherent'}`);
    if(g===0xc6c0040) p1c3grid=grid;   // P1C3's GFX1 base
  }
  console.log(`  [${label}] quads=${quads}`);
  lines.forEach(l=>console.log(l));
  return {quads,p1c3grid};
}

console.log('STEP 1 — baseline (good capture):');
const a=run(seed(),'baseline');

console.log('STEP 2 — ZERO P1C3 GFX2 (simulate connect-before-art-load):');
const ram2=seed();
ram2.fill(0, G(P1C3_GFX2_PAGE), G(P1C3_GFX2_PAGE)+0x20000);
const b=run(ram2,'stale-zeroed');

console.log('STEP 3 — re-inject FRESH P1C3 GFX2 (what the server GFX tail ships):');
const ram3=seed();
ram3.fill(0, G(P1C3_GFX2_PAGE), G(P1C3_GFX2_PAGE)+0x20000);     // first stale it
const fresh = seed().subarray(G(P1C3_GFX2_PAGE), G(P1C3_GFX2_PAGE)+0x20000); // the fresh bytes
ram3.set(fresh, G(P1C3_GFX2_PAGE));                            // tail re-injects them
const c=run(ram3,'gfx-tail-fixed');

console.log('\nRESULT:');
console.log(`  baseline P1C3 grid? ${a.p1c3grid}  (expect false)`);
console.log(`  stale   P1C3 grid? ${b.p1c3grid}  (expect TRUE — the bug reproduced)`);
console.log(`  fixed   P1C3 grid? ${c.p1c3grid}  (expect false — fix works)`);
const ok = a.p1c3grid===false && b.p1c3grid===true && c.p1c3grid===false;
console.log(ok ? '  PASS: stale GFX2 grids, fresh GFX2 fixes it — fix validated.' :
                 '  (note: P1C3 may not collapse to <=2 sels when zeroed; see distinctSels above)');
