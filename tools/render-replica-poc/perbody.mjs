// perbody.mjs — render a live frame and dump per-body tile count + first few quad corners,
// plus the cursor proof (resident +0xDC vs computed prefix-sum). Uses the wasm's exported
// per-object proof arrays if available; else re-derives via the scene quads.
import { readFileSync } from 'node:fs';
import createRenderFrame from './render_frame_node.mjs';
const path = process.argv[2]||'live.mcrr'; const fi=+(process.argv[3]||0);
const buf=new Uint8Array(readFileSync(path)); const dv=new DataView(buf.buffer,buf.byteOffset,buf.byteLength);
let p=0;const u32=()=>{const v=dv.getUint32(p,true);p+=4;return v>>>0;};
u32();const version=u32(),nStatic=u32(),nDynamic=u32(),nFrames=u32(),vramBytes=u32(),pvrBytes=u32();u32();
const region=()=>{const addr=u32(),len=u32();let tag='';for(let i=0;i<8;i++){const c=buf[p+i];if(c)tag+=String.fromCharCode(c);}p+=8;return{addr,len,tag};};
const staticRegs=Array.from({length:nStatic},region);const dynamicRegs=Array.from({length:nDynamic},region);
p+=vramBytes;p+=pvrBytes;const staticData=staticRegs.map(r=>{const b=buf.subarray(p,p+r.len);p+=r.len;return b;});
const frameStart=p;const RAM=16*1024*1024;const ram=new Uint8Array(RAM);
staticRegs.forEach((r,i)=>{if(r.tag==='ram16')ram.set(staticData[i],0);else ram.set(staticData[i],r.addr&0xFFFFFF);});
p=frameStart;const frames=[];for(let f=0;f<nFrames;f++){const fm=u32();const vframe=u32();const taSize=u32();const dynOff=p;for(const r of dynamicRegs)p+=r.len;const taOff=p;p+=taSize;frames.push({vframe,taSize,dynOff,taOff});}
let off=frames[fi].dynOff;for(const r of dynamicRegs){ram.set(buf.subarray(off,off+r.len),r.addr&0xFFFFFF);off+=r.len;}

const Mod=await createRenderFrame();
const ramPtr=Mod._malloc(RAM);Mod.HEAPU8.set(ram,ramPtr);
const cap=512*1024;const outPtr=Mod._malloc(cap);
const len=Mod._render_frame_ta(ramPtr,outPtr,cap);
const bodies=Mod._render_frame_body_count();const quads=Mod._render_frame_quad_count();
console.log(`frame ${fi}: bodies=${bodies} quads=${quads} ta=${len}`);
const odv=new DataView(Mod.HEAPU8.buffer);
// dump every quad's PCW/TCW + Ax/Ay/Cx/Cy
for(let k=0;k<Math.min(quads,quads);k++){
  const o=outPtr+k*96;
  const pcw=odv.getUint32(o,true),tsp=odv.getUint32(o+8,true),tcw=odv.getUint32(o+12,true);
  const Ax=odv.getFloat32(o+36,true),Ay=odv.getFloat32(o+40,true),Cx=odv.getFloat32(o+60,true),Cy=odv.getFloat32(o+64,true);
  if(k<6||k>=quads-6) console.log(`  q${k} tcw=0x${tcw.toString(16)} A(${Ax.toFixed(0)},${Ay.toFixed(0)}) C(${Cx.toFixed(0)},${Cy.toFixed(0)}) W=${(Cx-Ax).toFixed(0)} H=${(Cy-Ay).toFixed(0)}`);
}
Mod._free(ramPtr);Mod._free(outPtr);
