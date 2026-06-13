// Is body-2's GFX present (non-stale) in the shipped 16MB RAM backdrop, and does it
// CHANGE across live frames (i.e. is it dynamic and therefore stale after frame 0)?
import { readFileSync } from 'node:fs';
const path = process.argv[2] || 'live.mcrr';
const buf = new Uint8Array(readFileSync(path));
const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
let p=0; const u32=()=>{const v=dv.getUint32(p,true);p+=4;return v>>>0;};
u32(); const version=u32(), nStatic=u32(), nDynamic=u32(), nFrames=u32(), vramBytes=u32(), pvrBytes=u32(); u32();
const region=()=>{const addr=u32(),len=u32();let tag='';for(let i=0;i<8;i++){const c=buf[p+i];if(c)tag+=String.fromCharCode(c);}p+=8;return{addr,len,tag};};
const staticRegs=Array.from({length:nStatic},region);
const dynamicRegs=Array.from({length:nDynamic},region);
p+=vramBytes; p+=pvrBytes;
const staticData=staticRegs.map(r=>{const b=buf.subarray(p,p+r.len);p+=r.len;return b;});
// the ram16 backdrop:
const ram16 = staticData[staticRegs.findIndex(r=>r.tag==='ram16')];
const G=a=>a&0xFFFFFF;
const peek=(a,n)=>Array.from(ram16.subarray(G(a),G(a)+n)).map(x=>x.toString(16).padStart(2,'0')).join('');
console.log('static regions:', staticRegs.map(r=>`${r.tag}@${(r.addr>>>0).toString(16)}:${r.len}`).join(' '));
// body-2 GFX from frame 0: GFX1=0xc6c0040 GFX2=0xc789500
console.log('backdrop @0xc6c0040 (body2 GFX1):', peek(0x0c6c0040,16));
console.log('backdrop @0xc789500 (body2 GFX2):', peek(0x0c789500,16));
console.log('backdrop @0xc810040 (body1 GFX1):', peek(0x0c810040,16));
console.log('backdrop @0xc8fb8c0 (body1 GFX2):', peek(0x0c8fb8c0,16));
// Are body2 GFX addresses covered by the shipped GFX1/GFX2 static (frozen at prefix)?
const gfx=staticRegs.filter(r=>r.tag==='GFX1'||r.tag==='GFX2');
const inG=g=>gfx.some(r=>(g>>>0)>=(r.addr>>>0)&&(g>>>0)<(r.addr>>>0)+r.len);
console.log('body2 GFX1 0xc6c0040 in frozen GFX static?', inG(0xc6c0040));
console.log('body2 GFX2 0xc789500 in frozen GFX static?', inG(0xc789500));
// frame-0 dyn: do any dynamic regions cover these GFX addrs? (they shouldn't — GFX is static art)
const inD=g=>dynamicRegs.some(r=>(g>>>0)>=(r.addr>>>0)&&(g>>>0)<(r.addr>>>0)+r.len);
console.log('body2 GFX in any DYNAMIC region?', inD(0xc6c0040), inD(0xc789500));
