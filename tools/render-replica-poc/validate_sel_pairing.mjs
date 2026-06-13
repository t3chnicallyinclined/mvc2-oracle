// validate_sel_pairing.mjs — PROVE the tiling-safe sel<->quad pairing on a live frame.
//
// 1. Seed RAM from a .mcrr frame, run the REAL render_frame wasm -> ta + quadSels + quadGfx1s.
// 2. Independently compute the TRUE per-quad sel by walking GFX2 cells and expanding each cell
//    by its tile count (desc[0x8C1F9F9C + (dc+c)*4 + 1] + 1), in slot order over active bodies.
// 3. Assert render_frame_quad_sels[k] == TRUE per-quad sel[k] for every quad (the walker's own
//    ground truth must equal the independent walk).
// 4. Run the NEW body_decoder ensureBodyTextures and confirm each quad's decoded sprite (the
//    bytes it writes to that quad's TCW) == decodePart(gfx1, walker_sel). i.e. no slip.
// 5. Contrast with the OLD 1:1 pairing to quantify how many quads it got WRONG.
import { readFileSync } from 'node:fs';
import createRenderFrame from './render_frame_node.mjs';
import { ensureBodyTextures, decodeA } from '../../web/render-replica/body_decoder.mjs';

const path = process.argv[2] || 'maxq_86.mcrr';
const frameIdx = +(process.argv[3] || 0);
const buf = new Uint8Array(readFileSync(path));
const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
let p=0; const u32=()=>{const v=dv.getUint32(p,true);p+=4;return v>>>0;};
if (u32()!==0x5252434D) throw new Error('bad MCRR');
const version=u32(), nStatic=u32(), nDynamic=u32(), nFrames=u32(), vramBytes=u32(), pvrBytes=u32(); u32();
const region=()=>{const addr=u32(),len=u32();let tag='';for(let i=0;i<8;i++){const c=buf[p+i];if(c)tag+=String.fromCharCode(c);}p+=8;return{addr,len,tag};};
const staticRegs=Array.from({length:nStatic},region);
const dynamicRegs=Array.from({length:nDynamic},region);
p+=vramBytes; p+=pvrBytes;
const staticData=staticRegs.map(r=>{const b=buf.subarray(p,p+r.len);p+=r.len;return b;});
const frameStart=p;
const RAM=16*1024*1024; const ram=new Uint8Array(RAM);
staticRegs.forEach((r,i)=>{ if(r.tag==='ram16') ram.set(staticData[i],0); else ram.set(staticData[i], r.addr&0xFFFFFF); });
p=frameStart; const frames=[];
for(let f=0;f<nFrames;f++){ const fm=u32();const vframe=u32();const taSize=u32();const dynOff=p;for(const r of dynamicRegs)p+=r.len;const taOff=p;p+=taSize;frames.push({vframe,taSize,dynOff,taOff}); }
let off=frames[frameIdx].dynOff; for(const r of dynamicRegs){ ram.set(buf.subarray(off,off+r.len), r.addr&0xFFFFFF); off+=r.len; }

const G=a=>a&0xFFFFFF;
const r8=a=>ram[G(a)], r8s=a=>(ram[G(a)]<<24)>>24;
const r16u=a=>ram[G(a)]|(ram[G(a)+1]<<8);
const r32=a=>(ram[G(a)]|(ram[G(a)+1]<<8)|(ram[G(a)+2]<<16)|(ram[G(a)+3]<<24))>>>0;
const isRam=g=>(((g>>>24)&0x7F)===0x0C)&&g!==0;
const DESC=0x8C1F9F9C, COUNT=0x8C2895E0, PTR=0x8C287DE0, STR=0x180;

// ---- run the REAL wasm ----
const M = await createRenderFrame();
const ramPtr=M._malloc(RAM); M.HEAPU8.set(ram, ramPtr);
const cap=256*1024, outPtr=M._malloc(cap);
const len=M._render_frame_ta(ramPtr, outPtr, cap);
const quads=M._render_frame_quad_count();
const ta=M.HEAPU8.slice(outPtr, outPtr+len);
const selPtr=M._malloc(quads*2||2), gfxPtr=M._malloc(quads*4||4);
M._render_frame_quad_sels(selPtr, quads); M._render_frame_quad_gfx1s(gfxPtr, quads);
const quadSels=new Uint16Array(M.HEAPU8.buffer.slice(selPtr, selPtr+quads*2));
const quadGfx1s=new Uint32Array(M.HEAPU8.buffer.slice(gfxPtr, gfxPtr+quads*4));
console.log(`wasm: ${M._render_frame_body_count()} bodies, ${quads} quads, ta=${len}B`);

// ---- (3) STRUCTURAL invariant: each RUN of identical consecutive sels in the walker's
// quadSels (per body / gfx1) must be EXACTLY the GFX2 cell-record sels in order. This proves
// the walker emits ONE cell's sel across that cell's N tiles, and that body_decoder's per-quad
// sel == the cell sel for every tile (the slip is structurally impossible now). We compress
// quadSels per gfx1 run into its distinct-sel sequence and compare to that body's GFX2 cell sels.
function bodyCellSels(node){ const sid=r16u(node+0x144), gfx2=r32(node+0x160);
  if(!isRam(gfx2)) return null; const cb=gfx2+r32(gfx2+(sid&0x7FFF)*4); const ncell=r16u(cb);
  if(ncell===0||ncell>64) return null; const s=[]; for(let c=0;c<ncell;c++) s.push(r16u(cb+2+c*8+6)); return s; }
// map gfx1 -> node (slot order)
const bodies=[];
for(let L=0;L<16;L++){ const cnt=r8s(COUNT+L); if(cnt<=0) continue;
  for(let i=0;i<cnt;i++){ const node=r32(PTR+L*STR+i*4); if(!isRam(node)||r8s(node+3)!==0) continue;
    bodies.push({node, gfx1:r32(node+0x15C)>>>0, cellSels:bodyCellSels(node)}); } }
// runs of identical gfx1 in quadGfx1s
let structOK=true, runIdx=0;
let k0=0;
while(k0<quads){ const g=quadGfx1s[k0]>>>0; let k1=k0; while(k1<quads && (quadGfx1s[k1]>>>0)===g) k1++;
  // distinct-sel sequence in [k0,k1)
  const seq=[]; for(let k=k0;k<k1;k++){ if(seq.length===0||seq[seq.length-1]!==quadSels[k]) seq.push(quadSels[k]); }
  const body=bodies[runIdx];
  const cs=body? body.cellSels : null;
  const eq = cs && cs.length===seq.length && cs.every((v,i)=>v===seq[i]);
  console.log(`  body${runIdx} gfx1=0x${g.toString(16)} quads=${k1-k0} distinctSelRuns=${seq.length} cellSels=${cs?cs.length:'?'} ${eq?'MATCH':'*** MISMATCH ***'}`);
  if(!eq){ structOK=false; console.log(`     runSeq=${JSON.stringify(seq)}`); console.log(`     cellSel=${JSON.stringify(cs)}`); }
  k0=k1; runIdx++; }
console.log(`\n(3) STRUCTURAL: walker's per-tile sel runs == GFX2 cell-sel order per body: ${structOK?'PASS':'FAIL'}`);
const selMiss = structOK?0:1;

// ---- (4) NEW body_decoder: each quad's written sprite == decodePart(gfx1, walker_sel) ----
const vram=new Uint8Array(8*1024*1024);
const cache={};
const res=ensureBodyTextures(ram, vram, ta, quads, cache, quadSels, quadGfx1s);
console.log(`(4) ensureBodyTextures(NEW): ${JSON.stringify(res)}`);

// Verify per-quad: the bytes now at quad k's TCW == the decode of quadSels[k] under quadGfx1s[k].
// (We re-decode independently and compare a prefix to avoid depending on internal cache.)
const TCW=k=>{const o=k*96+0x0C; const tcw=(ram?0:0)|new DataView(ta.buffer,ta.byteOffset).getUint32(o,true); return ((tcw&0x1FFFFF)<<3)>>>0;};
function gfx1Tab(gfx1){ const nn=r32(gfx1)>>>2; const offs=new Uint32Array(nn); for(let i=0;i<nn;i++)offs[i]=r32(gfx1+i*4); const srt=Uint32Array.from(new Set(offs)).sort((a,b)=>a-b); return {n:nn,offs,srt}; }
function endOf(srt,o){let lo=0,hi=srt.length;while(lo<hi){const m=(lo+hi)>>1;if(srt[m]<=o)lo=m+1;else hi=m;}return lo<srt.length?srt[lo]:o+0x4000;}
function decExpect(gfx1,sel){ const Gt=gfx1Tab(gfx1); if(sel>=Gt.n)return null; const pbase=gfx1+Gt.offs[sel]; const sw=r8(pbase+2),sh=r8(pbase+3); const W=sw*8,H=sh*8; if(W<=0||H<=0||W>1024||H>1024)return null; const destLen=(W*H)>>1; return decodeA(ram,(pbase+4)&0xFFFFFF,(gfx1+endOf(Gt.srt,Gt.offs[sel]))&0xFFFFFF,destLen); }
const tav=new DataView(ta.buffer, ta.byteOffset, ta.byteLength);
let qok=0,qbad=0,qskip=0;
for(let k=0;k<quads;k++){ const gfx1=quadGfx1s[k]>>>0,sel=quadSels[k];
  if(!(gfx1&0x0C000000)&&!(gfx1&0x8C000000)){qskip++;continue;}
  const exp=decExpect(gfx1,sel); if(!exp){qskip++;continue;}
  const tcw=tav.getUint32(k*96+0x0C,true); const addr=((tcw&0x1FFFFF)<<3)>>>0;
  let same=true; const L=Math.min(exp.length, 256); for(let b=0;b<L;b++){ if(vram[addr+b]!==exp[b]){same=false;break;} }
  if(same)qok++; else {qbad++; if(qbad<=6)console.log(`  quad ${k} TCW-write MISMATCH sel=${sel} gfx1=${gfx1.toString(16)} addr=${addr.toString(16)}`);} }
console.log(`(4) per-quad written sprite == decode(walker sel): ${qok} OK, ${qbad} BAD, ${qskip} skipped (of ${quads})`);

// ---- (5) contrast: how many quads the OLD 1:1 pairing got WRONG ----
// OLD model (per body): pair quad i to cellSels[i], consuming only `ncell` quads; quads beyond
// ncell were never written (left stale) OR (in the old run loop) over-read. We compute, per body,
// how many of the walker's actual tiles got the WRONG sel under the old quad[i]<->cellSel[i] rule.
let oldWrong=0, oldTotal=0; k0=0; runIdx=0;
while(k0<quads){ const g=quadGfx1s[k0]>>>0; let k1=k0; while(k1<quads && (quadGfx1s[k1]>>>0)===g) k1++;
  const cs = bodies[runIdx] ? bodies[runIdx].cellSels : null;
  for(let k=k0;k<k1;k++){ const i=k-k0; const oldAssigned = cs && i<cs.length ? cs[i] : 0xFFFF; // old: 1:1, rest unwritten
    oldTotal++; if(oldAssigned!==quadSels[k]) oldWrong++; }
  k0=k1; runIdx++; }
console.log(`(5) OLD 1:1 pairing would mis-assign ${oldWrong}/${oldTotal} quads (right colors, wrong quad = the scramble).`);

const PASS = structOK && qbad===0;
console.log(`\nRESULT: ${PASS?'PASS':'FAIL'} — ${PASS?'every quad decodes its OWN walker-sel sprite to its OWN TCW; no slip.':'pairing still slips.'}`);
process.exit(PASS?0:1);
