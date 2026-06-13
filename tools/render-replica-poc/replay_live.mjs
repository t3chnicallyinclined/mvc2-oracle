// replay_live.mjs — feed a captured live.mcrr through render_frame.wasm exactly as the
// browser does, report per-frame quad counts + per-body diagnostics. Truth, not guesses.
import { readFileSync } from 'node:fs';
import createRenderFrame from './render_frame_node.mjs';

const path = process.argv[2] || 'live.mcrr';
const buf = new Uint8Array(readFileSync(path));
const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
let p=0; const u32=()=>{const v=dv.getUint32(p,true);p+=4;return v>>>0;};
if (u32()!==0x5252434D) throw new Error('bad MCRR');
const version=u32(), nStatic=u32(), nDynamic=u32(), nFrames=u32(), vramBytes=u32(), pvrBytes=u32(); u32();
const region=()=>{const addr=u32(),len=u32();let tag='';for(let i=0;i<8;i++){const c=buf[p+i];if(c)tag+=String.fromCharCode(c);}p+=8;return{addr,len,tag};};
const staticRegs=Array.from({length:nStatic},region);
const dynamicRegs=Array.from({length:nDynamic},region);
// static payload
const vramOff=p; p+=vramBytes; const pvrOff=p; p+=pvrBytes;
const staticData=staticRegs.map(r=>{const b=buf.subarray(p,p+r.len);p+=r.len;return b;});
const frameStart=p;

// seed RAM
const RAM=16*1024*1024;
const ram=new Uint8Array(RAM);
staticRegs.forEach((r,i)=>{ if(r.tag==='ram16') ram.set(staticData[i],0); else ram.set(staticData[i], r.addr&0xFFFFFF); });

// index frames
const frames=[]; p=frameStart;
for(let f=0;f<nFrames;f++){
  const fm=u32(); if(fm!==0x784D5246) throw new Error(`frame ${f} bad FRMx`);
  const vframe=u32(); const taSize=u32(); const dynOff=p;
  for(const r of dynamicRegs) p+=r.len; const taOff=p; p+=taSize;
  frames.push({vframe,taSize,dynOff,taOff});
}
console.error(`MCRR: ${nFrames} frames, ${nDynamic} dyn regions`);

function applyDyn(f){ let off=frames[f].dynOff; for(const r of dynamicRegs){ ram.set(buf.subarray(off,off+r.len), r.addr&0xFFFFFF); off+=r.len; } }

const Mod=await createRenderFrame();
const ramPtr=Mod._malloc(RAM); const cap=512*1024; const outPtr=Mod._malloc(cap);

const which = process.argv[3] ? process.argv[3].split(',').map(Number) : null;
let maxQ=0, maxF=-1;
const hist={};
for(let f=0;f<nFrames;f++){
  applyDyn(f);
  Mod.HEAPU8.set(ram, ramPtr);
  const len=Mod._render_frame_ta(ramPtr,outPtr,cap);
  const bodies=Mod._render_frame_body_count();
  const quads=Mod._render_frame_quad_count();
  if(quads>maxQ){maxQ=quads;maxF=f;}
  const bucket = quads>=1024?'1024':(quads>=256?'256+':(quads>=128?'128+':'<128'));
  hist[bucket]=(hist[bucket]||0)+1;
  if((which && which.includes(f)) || quads>=256 || f<3){
    const odv=new DataView(Mod.HEAPU8.buffer);
    const Ax=quads>0?odv.getFloat32(outPtr+36,true).toFixed(0):'-';
    console.log(`f${f} vframe=${frames[f].vframe} bodies=${bodies} quads=${quads} ta=${len}B Ax=${Ax}`);
  }
}
console.log('---'); console.log('quad histogram:', hist);
console.log(`max quads=${maxQ} @ frame ${maxF}`);
Mod._free(ramPtr); Mod._free(outPtr);
