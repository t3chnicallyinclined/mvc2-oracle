// For each live frame, compute: max descriptor index the walker reads into 0x8C1F9F9C
// (tiledesc, shipped len=512), and max idxtab index (idxtab shipped len=8192=>4096 u16).
// If any body's (resident+0xDC + ntiles) exceeds the shipped tiledesc/idxtab span, that
// body reads STALE/OOB -> garble/over-read.
import { readFileSync } from 'node:fs';
const buf=new Uint8Array(readFileSync(process.argv[2]||'live.mcrr'));const dv=new DataView(buf.buffer,buf.byteOffset,buf.byteLength);
let p=0;const u32=()=>{const v=dv.getUint32(p,true);p+=4;return v>>>0;};
u32();const ver=u32(),nS=u32(),nD=u32(),nF=u32(),vb=u32(),pb=u32();u32();
const reg=()=>{const a=u32(),l=u32();let t='';for(let i=0;i<8;i++){const c=buf[p+i];if(c)t+=String.fromCharCode(c);}p+=8;return{addr:a,len:l,tag:t};};
const sR=Array.from({length:nS},reg);const dR=Array.from({length:nD},reg);
p+=vb;p+=pb;const sD=sR.map(r=>{const b=buf.subarray(p,p+r.len);p+=r.len;return b;});const fs=p;
const RAM=16*1024*1024;const ram=new Uint8Array(RAM);
sR.forEach((r,i)=>{if(r.tag==='ram16')ram.set(sD[i],0);else ram.set(sD[i],r.addr&0xFFFFFF);});
p=fs;const frames=[];for(let f=0;f<nF;f++){const fm=u32();const vf=u32();const ts=u32();const dof=p;for(const r of dR)p+=r.len;const tof=p;p+=ts;frames.push({vf,dof});}
const tiledesc=dR.find(r=>r.tag==='tiledes'); const idxtab=dR.find(r=>r.tag==='idxtab');
console.log('tiledesc len',tiledesc.len,'=> max desc idx',tiledesc.len/4,' | idxtab len',idxtab.len,'=> max u16 idx',idxtab.len/2,' arena=400');
const G=a=>a&0xFFFFFF;const r16u=a=>ram[G(a)]|(ram[G(a)+1]<<8);const r32=a=>(ram[G(a)]|(ram[G(a)+1]<<8)|(ram[G(a)+2]<<16)|(ram[G(a)+3]<<24))>>>0;const r8s=a=>(ram[G(a)]<<24)>>24;const isRam=g=>(((g>>>24)&0x7F)===0x0C)&&g!==0;
let worstDesc=0,worstIdx=0,bad=0;
for(let f=0;f<nF;f++){let off=frames[f].dof;for(const r of dR){ram.set(buf.subarray(off,off+r.len),r.addr&0xFFFFFF);off+=r.len;}
 const arena=r32(0x8C1F9D94);
 const COUNT=0x8C2895E0,PTR=0x8C287DE0,STR=0x180;
 for(let L=0;L<16;L++){const cnt=r8s(COUNT+L);if(cnt<=0)continue;
  for(let i=0;i<cnt;i++){const node=r32(PTR+L*STR+i*4);if(!isRam(node)||r8s(node+3)!==0)continue;
   const dc=r16u(node+0xDC);const gfx2=r32(node+0x160);const sid=r16u(node+0x144);
   const cell=gfx2+r32(gfx2+(sid&0x7FFF)*4);const rc=r16u(cell);
   const maxDesc=dc+rc; const maxIdx=dc+arena+rc;
   if(maxDesc>worstDesc)worstDesc=maxDesc; if(maxIdx>worstIdx)worstIdx=maxIdx;
   if(maxDesc> tiledesc.len/4 || maxIdx> idxtab.len/2 || rc>200){ if(bad<10)console.log(`f${f} node=${node.toString(16)} dc=${dc} rc=${rc} maxDesc=${maxDesc} maxIdx=${maxIdx}`); bad++; }
  }}}
console.log(`scanned ${nF} frames: worst descIdx=${worstDesc} (cap ${tiledesc.len/4}), worst idxtabIdx=${worstIdx} (cap ${idxtab.len/2}), bad-frames=${bad}`);
