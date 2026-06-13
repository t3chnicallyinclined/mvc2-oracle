import { readFileSync, writeFileSync } from 'node:fs';
const path=process.argv[2]||'live.mcrr'; const fi=+(process.argv[3]||0); const out=process.argv[4]||'live_ram.bin';
const buf=new Uint8Array(readFileSync(path)); const dv=new DataView(buf.buffer,buf.byteOffset,buf.byteLength);
let p=0;const u32=()=>{const v=dv.getUint32(p,true);p+=4;return v>>>0;};
u32();const ver=u32(),nS=u32(),nD=u32(),nF=u32(),vb=u32(),pb=u32();u32();
const reg=()=>{const a=u32(),l=u32();let t='';for(let i=0;i<8;i++){const c=buf[p+i];if(c)t+=String.fromCharCode(c);}p+=8;return{addr:a,len:l,tag:t};};
const sR=Array.from({length:nS},reg);const dR=Array.from({length:nD},reg);
p+=vb;p+=pb;const sD=sR.map(r=>{const b=buf.subarray(p,p+r.len);p+=r.len;return b;});
const RAM=16*1024*1024;const ram=new Uint8Array(RAM);
sR.forEach((r,i)=>{if(r.tag==='ram16')ram.set(sD[i],0);else ram.set(sD[i],r.addr&0xFFFFFF);});
const fs=p;const frames=[];for(let f=0;f<nF;f++){const fm=u32();const vf=u32();const ts=u32();const dof=p;for(const r of dR)p+=r.len;const tof=p;p+=ts;frames.push({dof});}
let off=frames[fi].dof;for(const r of dR){ram.set(buf.subarray(off,off+r.len),r.addr&0xFFFFFF);off+=r.len;}
writeFileSync(out,Buffer.from(ram)); console.error(`wrote ${out} (16MB) frame ${fi}`);
