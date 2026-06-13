// PIN the grid divergence: for each captured live frame, walk the slot table (engine's own
// loc_8c0308c2 count/ptr layout), and for every BODY node read GFX2 base (node+0x160) + the
// walker's cell-table header (count u16 the walker trusts) from the RAM image AS THE CLIENT
// SEES IT (static prefix seeded once + per-frame dynamic regions splatted). Then check, per
// body, whether that GFX2 base is covered by a SHIPPED static GFX region or any dynamic region.
//
// A body whose GFX2 is NOT shipped (neither static-GFX nor dynamic) is reading FROZEN/STALE
// cell records -> if the count is out of a sane range it drives the walker into the grid.
//
//   node pin_gfx_stale.mjs live.mcrr
import { readFileSync } from 'node:fs';
const path = process.argv[2] || 'live.mcrr';
const buf = new Uint8Array(readFileSync(path));
const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
let p=0; const u32=()=>{const v=dv.getUint32(p,true);p+=4;return v>>>0;};
if(u32()!==0x5252434D) throw new Error('bad MCRR');
const version=u32(), nStatic=u32(), nDynamic=u32(), nFrames=u32(), vramBytes=u32(), pvrBytes=u32(); u32();
const region=()=>{const addr=u32(),len=u32();let tag='';for(let i=0;i<8;i++){const c=buf[p+i];if(c)tag+=String.fromCharCode(c);}p+=8;return{addr,len,tag};};
const staticRegs=Array.from({length:nStatic},region);
const dynamicRegs=Array.from({length:nDynamic},region);
const vram=buf.subarray(p,p+vramBytes); p+=vramBytes;
const pvr =buf.subarray(p,p+pvrBytes);  p+=pvrBytes;
const staticData=staticRegs.map(r=>{const b=buf.subarray(p,p+r.len);p+=r.len;return b;});
const frameStart=p;

const gfxStatic = staticRegs.filter(r=>r.tag==='GFX1'||r.tag==='GFX2');
console.log('SHIPPED static GFX regions:', gfxStatic.map(r=>`${r.tag}@${(r.addr>>>0).toString(16)}:${r.len}`).join(' ') || '(NONE)');
console.log('DYNAMIC region tags:', dynamicRegs.map(r=>r.tag).join(','));

// seed 16MB RAM once
const ram = new Uint8Array(16*1024*1024);
staticRegs.forEach((r,i)=>{ if(r.tag==='ram16') ram.set(staticData[i],0); else ram.set(staticData[i], r.addr&0xFFFFFF); });

const inStaticGFX = g => gfxStatic.some(r=>(g>>>0)>=(r.addr>>>0)&&(g>>>0)<(r.addr>>>0)+r.len);
const inDyn       = g => dynamicRegs.some(r=>(g>>>0)>=(r.addr>>>0)&&(g>>>0)<(r.addr>>>0)+r.len);

const r8s=a=>(ram[a]<<24)>>24;
const r32=a=>(ram[a]|(ram[a+1]<<8)|(ram[a+2]<<16)|(ram[a+3]<<24))>>>0;
const r16=a=>(ram[a]|(ram[a+1]<<8))>>>0;
const G=a=>a&0xFFFFFF;

// apply dynamic regions for a frame buffer (FRMx: magic+vframe+taSize+dyn bytes)
function applyDyn(frameBuf){
  const fdv=new DataView(frameBuf.buffer,frameBuf.byteOffset,frameBuf.byteLength);
  const vframe=fdv.getUint32(4,true);
  let q=12;
  for(const r of dynamicRegs){ ram.set(frameBuf.subarray(q,q+r.len), r.addr&0xFFFFFF); q+=r.len; }
  return vframe;
}

// walk slot table -> body nodes, read GFX2 + cell-table count the walker trusts
function bodies(){
  const COUNT=0x2895E0, PTR=0x287DE0, STR=0x180;
  const out=[];
  for(let L=0;L<16;L++){
    const cnt=r8s(COUNT+L); if(cnt<=0||cnt>0x60) continue;
    const base=PTR+L*STR;
    for(let i=0;i<cnt;i++){
      const nodeG=r32(base+i*4); if(((nodeG>>>24)&0x7F)!==0x0C||nodeG===0) continue;
      const node=G(nodeG);
      const cat=(ram[node+3]<<24)>>24; if(cat!==0) continue;  // body only
      const sid=r16(node+0x144)&0x7FFF;
      const gfx2=r32(node+0x160), gfx1=r32(node+0x15C);
      // walker: r11 = GFX2 + *(GFX2 + sid*4); count = *(u16)r11
      let count=-1, recOff=-1;
      if(((gfx2>>>24)&0x7F)===0x0C){
        recOff=r32(G(gfx2)+sid*4);
        count=r16(G(gfx2)+recOff);
      }
      out.push({L,nodeG:nodeG>>>0,sid,gfx1:gfx1>>>0,gfx2:gfx2>>>0,count,
                gfxShipped:inStaticGFX(gfx2), gfxDyn:inDyn(gfx2)});
    }
  }
  return out;
}

let q=frameStart, f=0;
const seen=new Set();
while(q<buf.length && f<nFrames){
  if(dv.getUint32(q,true)!==0x784D5246) break;
  const taSize=dv.getUint32(q+8,true);
  let len=12; for(const r of dynamicRegs) len+=r.len; len+=taSize;
  const frameBuf=buf.subarray(q,q+len);
  const vframe=applyDyn(frameBuf);
  const bs=bodies();
  // report frames where ANY body's count is insane (grid driver) OR a body's GFX is un-shipped
  const bad = bs.filter(b=>b.count<0||b.count>64||(!b.gfxShipped&&!b.gfxDyn));
  const key = bs.map(b=>`${b.nodeG.toString(16)}:${b.sid}:${b.count}:${b.gfxShipped?'S':b.gfxDyn?'D':'STALE'}`).join('|');
  if(f<4 || bad.length || !seen.has(key)){
    seen.add(key);
    console.log(`f${f} vframe=${vframe} bodies=${bs.length}`);
    for(const b of bs){
      const tag = b.gfxShipped?'SHIPPED':(b.gfxDyn?'DYN':'!!STALE!!');
      const cnt = b.count<0?'NOGFX':(b.count>64?`GRID(${b.count})`:b.count);
      console.log(`   node=${b.nodeG.toString(16)} L${b.L} sid=${b.sid} gfx2=${b.gfx2.toString(16)} count=${cnt} ${tag}`);
    }
  }
  q+=len; f++;
}
console.log(`\nscanned ${f} frames.`);
