// inspect_live.mjs — load live.mcrr frame, seed RAM, dump per-body node details:
// node addr, cat, sprite_id, GFX1/GFX2 pointers, whether node==a char-struct base,
// and whether GFX2 lands in a shipped STATIC region. Truth for the read-set audit.
import { readFileSync } from 'node:fs';
const path = process.argv[2] || 'live.mcrr';
const frameIdx = +(process.argv[3] || 0);
const buf = new Uint8Array(readFileSync(path));
const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
let p=0; const u32=()=>{const v=dv.getUint32(p,true);p+=4;return v>>>0;};
if (u32()!==0x5252434D) throw new Error('bad MCRR');
const version=u32(), nStatic=u32(), nDynamic=u32(), nFrames=u32(), vramBytes=u32(), pvrBytes=u32(); u32();
const region=()=>{const addr=u32(),len=u32();let tag='';for(let i=0;i<8;i++){const c=buf[p+i];if(c)tag+=String.fromCharCode(c);}p+=8;return{addr,len,tag};};
const staticRegs=Array.from({length:nStatic},region);
const dynamicRegs=Array.from({length:nDynamic},region);
const vramOff=p;p+=vramBytes;const pvrOff=p;p+=pvrBytes;
const staticData=staticRegs.map(r=>{const b=buf.subarray(p,p+r.len);p+=r.len;return b;});
const frameStart=p;
const RAM=16*1024*1024; const ram=new Uint8Array(RAM);
staticRegs.forEach((r,i)=>{ if(r.tag==='ram16') ram.set(staticData[i],0); else ram.set(staticData[i], r.addr&0xFFFFFF); });
// index + apply requested frame
p=frameStart; const frames=[];
for(let f=0;f<nFrames;f++){ const fm=u32();const vframe=u32();const taSize=u32();const dynOff=p;for(const r of dynamicRegs)p+=r.len;const taOff=p;p+=taSize;frames.push({vframe,taSize,dynOff,taOff}); }
let off=frames[frameIdx].dynOff; for(const r of dynamicRegs){ ram.set(buf.subarray(off,off+r.len), r.addr&0xFFFFFF); off+=r.len; }
console.log(`frame ${frameIdx} vframe=${frames[frameIdx].vframe}`);

const G=a=>a&0xFFFFFF;
const r8=a=>ram[G(a)];
const r8s=a=>(ram[G(a)]<<24)>>24;
const r16u=a=>ram[G(a)]|(ram[G(a)+1]<<8);
const r32=a=>(ram[G(a)]|(ram[G(a)+1]<<8)|(ram[G(a)+2]<<16)|(ram[G(a)+3]<<24))>>>0;
const rf=a=>{const u=r32(a);const b=Buffer.alloc(4);b.writeUInt32LE(u);return b.readFloatLE(0);};
const isRam=g=>(((g>>>24)&0x7F)===0x0C)&&g!==0;
const CHAR_SLOT=[[0x8C268340,16],[0x8C2688E4,24],[0x8C268E88,32],[0x8C26942C,40],[0x8C2699D0,48],[0x8C269F74,56]];

// shipped static GFX regions (server logic: & ~0xFFF, len 0x20000)
const gfxRegions = staticRegs.filter(r=>r.tag==='GFX1'||r.tag==='GFX2').map(r=>({lo:r.addr>>>0, hi:(r.addr>>>0)+r.len, tag:r.tag}));
console.log('shipped GFX static regions:', gfxRegions.map(r=>`${r.tag}@${r.lo.toString(16)}..${r.hi.toString(16)}`).join(' '));
const inStatic = g => gfxRegions.some(r=> (g>>>0)>=r.lo && (g>>>0)<r.hi);

const COUNT=0x8C2895E0, PTR=0x8C287DE0, STR=0x180;
for(let L=0;L<16;L++){
  const cnt=r8s(COUNT+L); if(cnt<=0) continue;
  for(let i=0;i<cnt;i++){
    const node=r32(PTR+L*STR+i*4);
    if(!isRam(node)){ console.log(`  L${L}[${i}] node=${node.toString(16)} NOT-RAM`); continue; }
    const cat=r8s(node+3);
    const sid=r16u(node+0x144);
    const gfx1=r32(node+0x15C), gfx2=r32(node+0x160);
    const cid=r8(node+1);
    const slotMatch=CHAR_SLOT.find(s=>s[0]===node);
    const dc=r16u(node+0xDC);
    const ec=rf(node+0xEC), fc=rf(node+0xF0);
    const e0=rf(node+0xE0), e4=rf(node+0xE4);
    const v12c=r32(node+0x12C);
    console.log(`  L${L}[${i}] node=0x${node.toString(16)} cat=${cat} cid=${cid} sid=0x${sid.toString(16)} `+
      `slotBase=${slotMatch?('YES pal'+slotMatch[1]):'NO'} +0xDC=${dc} +0x12C=0x${v12c.toString(16)} `+
      `anchor(${e0.toFixed(1)},${e4.toFixed(1)}) scale(${ec.toFixed(3)},${fc.toFixed(3)})`);
    console.log(`         GFX1=0x${gfx1.toString(16)} ${inStatic(gfx1)?'[shipped]':'*** NOT IN STATIC ***'}  GFX2=0x${gfx2.toString(16)} ${inStatic(gfx2)?'[shipped]':'*** NOT IN STATIC ***'}`);
  }
}
