// Find the full VRAM address span ALL body TCWs reference across the whole capture,
// for BOTH bodies. That span is the per-frame texture region the read-set must ship.
import { readFileSync } from 'node:fs';
import createRenderFrame from './render_frame_node.mjs';
const buf=new Uint8Array(readFileSync(process.argv[2]||'live.mcrr'));const dv=new DataView(buf.buffer,buf.byteOffset,buf.byteLength);
let p=0;const u32=()=>{const v=dv.getUint32(p,true);p+=4;return v>>>0;};
u32();const ver=u32(),nS=u32(),nD=u32(),nF=u32(),vb=u32(),pb=u32();u32();
const reg=()=>{const a=u32(),l=u32();let t='';for(let i=0;i<8;i++){const c=buf[p+i];if(c)t+=String.fromCharCode(c);}p+=8;return{addr:a,len:l,tag:t};};
const sR=Array.from({length:nS},reg);const dR=Array.from({length:nD},reg);
p+=vb;p+=pb;const sD=sR.map(r=>{const b=buf.subarray(p,p+r.len);p+=r.len;return b;});const fs=p;
const RAM=16*1024*1024;const ram=new Uint8Array(RAM);
sR.forEach((r,i)=>{if(r.tag==='ram16')ram.set(sD[i],0);else ram.set(sD[i],r.addr&0xFFFFFF);});
p=fs;const frames=[];for(let f=0;f<nF;f++){const fm=u32();const vf=u32();const ts=u32();const dof=p;for(const r of dR)p+=r.len;const tof=p;p+=ts;frames.push({dof});}
const Mod=await createRenderFrame();const ramPtr=Mod._malloc(RAM);const cap=512*1024;const outPtr=Mod._malloc(cap);
function texByteSize(fmt,w,h){ // pal4=0.5B/px, others ~2B/px; over-estimate w*h*2
  return w*h*2; }
let lo=0xFFFFFFFF,hi=0;
for(let f=0;f<nF;f++){let off=frames[f].dof;for(const r of dR){ram.set(buf.subarray(off,off+r.len),r.addr&0xFFFFFF);off+=r.len;}
 Mod.HEAPU8.set(ram,ramPtr);const len=Mod._render_frame_ta(ramPtr,outPtr,cap);const q=Mod._render_frame_quad_count();const odv=new DataView(Mod.HEAPU8.buffer);
 for(let k=0;k<q;k++){const o=outPtr+k*96;const tsp=odv.getUint32(o+8,true);const tcw=odv.getUint32(o+12,true);
  const addr=(tcw&0x1FFFFF)<<3;const texU=(tsp>>>3)&7,texV=tsp&7;const w=8<<texU,h=8<<texV;const sz=texByteSize((tcw>>>27)&7,w,h);
  if(addr<lo)lo=addr; if(addr+sz>hi)hi=addr+sz; }
}
console.log(`ALL body TCW texel addresses span VRAM [0x${lo.toString(16)} .. 0x${hi.toString(16)}]  size=0x${(hi-lo).toString(16)} (${((hi-lo)/1024).toFixed(0)}KB)`);
