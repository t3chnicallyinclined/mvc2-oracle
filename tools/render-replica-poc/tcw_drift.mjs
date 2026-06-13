// Do the body's TCW texture addresses CHANGE across frames? If MVC2 re-uploads sprite
// textures to a cycling VRAM scratch region per animation frame, the once-shipped VRAM
// snapshot is stale -> textures resolve to empty/garbage. Compare q0 tcw addr over frames.
import { readFileSync } from 'node:fs';
import createRenderFrame from './render_frame_node.mjs';
const buf=new Uint8Array(readFileSync(process.argv[2]||'live.mcrr'));const dv=new DataView(buf.buffer,buf.byteOffset,buf.byteLength);
let p=0;const u32=()=>{const v=dv.getUint32(p,true);p+=4;return v>>>0;};
u32();const ver=u32(),nS=u32(),nD=u32(),nF=u32(),vb=u32(),pb=u32();u32();
const reg=()=>{const a=u32(),l=u32();let t='';for(let i=0;i<8;i++){const c=buf[p+i];if(c)t+=String.fromCharCode(c);}p+=8;return{addr:a,len:l,tag:t};};
const sR=Array.from({length:nS},reg);const dR=Array.from({length:nD},reg);
const vram=buf.subarray(p,p+vb);p+=vb;p+=pb;const sD=sR.map(r=>{const b=buf.subarray(p,p+r.len);p+=r.len;return b;});const fs=p;
const RAM=16*1024*1024;const ram=new Uint8Array(RAM);
sR.forEach((r,i)=>{if(r.tag==='ram16')ram.set(sD[i],0);else ram.set(sD[i],r.addr&0xFFFFFF);});
p=fs;const frames=[];for(let f=0;f<nF;f++){const fm=u32();const vf=u32();const ts=u32();const dof=p;for(const r of dR)p+=r.len;const tof=p;p+=ts;frames.push({vf,dof});}
const Mod=await createRenderFrame();const ramPtr=Mod._malloc(RAM);const cap=512*1024;const outPtr=Mod._malloc(cap);
const G=a=>a&0xFFFFFF;
function vnz(a){let n=0;for(let i=0;i<512;i++)if(vram[a+i])n++;return n;}
const seen=new Set();
for(let f=0;f<nF;f+=20){let off=frames[f].dof;for(const r of dR){ram.set(buf.subarray(off,off+r.len),r.addr&0xFFFFFF);off+=r.len;}
 Mod.HEAPU8.set(ram,ramPtr);const len=Mod._render_frame_ta(ramPtr,outPtr,cap);const odv=new DataView(Mod.HEAPU8.buffer);
 const tcw=odv.getUint32(outPtr+12,true);const addr=(tcw&0x1FFFFF)<<3;
 console.log(`f${f} vframe=${frames[f].vf} q0 tcw=0x${tcw.toString(16)} addr=0x${addr.toString(16)} vramNZ@addr=${vnz(addr)}`);
 seen.add(tcw>>>0);
}
console.log(`distinct q0 TCW across sampled frames: ${seen.size}`);
