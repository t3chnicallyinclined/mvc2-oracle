// diag_tiling_slip.mjs — PROVE the body_decoder sel<->quad slip under tiling.
// Seeds RAM from a .mcrr frame, then for each active body:
//   (a) walks GFX2 cell records -> per-cell sel (u16@+6) and per-cell TILE COUNT
//       (= u8(0x8C1F9F9C + (dc+rec)*4 + 1) + 1, exactly as gen_walker.c loc_8c0344d4 reads it)
//   (b) builds the TRUE per-quad sel list (each cell's sel repeated tile_count times)
//   (c) builds the body_decoder ASSUMED list (sels[i] <-> quad[i], 1:1)
//   (d) prints the first quad where they diverge = the scramble onset.
import { readFileSync } from 'node:fs';
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
const vramOff=p;p+=vramBytes;const pvrOff=p;p+=pvrBytes;
const staticData=staticRegs.map(r=>{const b=buf.subarray(p,p+r.len);p+=r.len;return b;});
const frameStart=p;
const RAM=16*1024*1024; const ram=new Uint8Array(RAM);
staticRegs.forEach((r,i)=>{ if(r.tag==='ram16') ram.set(staticData[i],0); else ram.set(staticData[i], r.addr&0xFFFFFF); });
p=frameStart; const frames=[];
for(let f=0;f<nFrames;f++){ const fm=u32();const vframe=u32();const taSize=u32();const dynOff=p;for(const r of dynamicRegs)p+=r.len;const taOff=p;p+=taSize;frames.push({vframe,taSize,dynOff,taOff}); }
let off=frames[frameIdx].dynOff; for(const r of dynamicRegs){ ram.set(buf.subarray(off,off+r.len), r.addr&0xFFFFFF); off+=r.len; }

const G=a=>a&0xFFFFFF;
const r8=a=>ram[G(a)];
const r8s=a=>(ram[G(a)]<<24)>>24;
const r16u=a=>ram[G(a)]|(ram[G(a)+1]<<8);
const r32=a=>(ram[G(a)]|(ram[G(a)+1]<<8)|(ram[G(a)+2]<<16)|(ram[G(a)+3]<<24))>>>0;
const isRam=g=>(((g>>>24)&0x7F)===0x0C)&&g!==0;
const DESC=0x8C1F9F9C;
const COUNT=0x8C2895E0, PTR=0x8C287DE0, STR=0x180;

console.log(`frame ${frameIdx} vframe=${frames[frameIdx].vframe}  (file ${path})\n`);

for(let L=0;L<16;L++){
  const cnt=r8s(COUNT+L); if(cnt<=0) continue;
  for(let i=0;i<cnt;i++){
    const node=r32(PTR+L*STR+i*4);
    if(!isRam(node)) continue;
    const cat=r8s(node+3); if(cat!==0) continue;          // BODY only
    const sid=r16u(node+0x144);
    const gfx2=r32(node+0x160);
    const dc=r16u(node+0xDC);
    if(!isRam(gfx2)) continue;
    // GFX2 cell walk
    const cellOff=r32(gfx2 + (sid&0x7FFF)*4);
    const cb=gfx2+cellOff;
    const ncell=r16u(cb);
    if(ncell===0||ncell>64) continue;
    let trueQuadSel=[];     // per emitted quad: the sel the walker actually used
    let perCell=[];
    let q=0;
    for(let c=0;c<ncell;c++){
      const rec=cb+2+c*8;
      const sel=r16u(rec+6);
      // tile count: gen_walker.c -> r13 = (dc<<2)+DESC, advances +4/record; count=u8(r13+1)+1
      const descRec=DESC + (dc + c)*4;
      const tcount = r8(descRec+1) + 1;
      perCell.push({c, sel, tcount, q0:q});
      for(let t=0;t<tcount;t++) trueQuadSel.push(sel);
      q += tcount;
    }
    const totalQuads=q;
    // body_decoder ASSUMED pairing: quad[i] gets sels[i] (1:1, only ncell entries)
    const assumedSel=i=> i<ncell ? perCell[i].sel : '(OOB)';
    // find first divergence
    let firstSlip=-1;
    for(let i=0;i<totalQuads;i++){ if(trueQuadSel[i]!==assumedSel(i)){ firstSlip=i; break; } }
    console.log(`BODY node=0x${node.toString(16)} cid=${r8(node+1)} sid=0x${sid.toString(16)} dc=${dc}: ${ncell} cells -> ${totalQuads} QUADS`);
    console.log(`  per-cell [c sel tcount q0]:`);
    for(const pc of perCell) console.log(`    c=${pc.c} sel=${pc.sel} tcount=${pc.tcount} firstQuad=${pc.q0}${pc.tcount>1?'  <-- TILED (expands to '+pc.tcount+' quads)':''}`);
    if(firstSlip<0) console.log(`  >>> NO SLIP (no cell tiled; ncell==quads) — pairing happens to be correct here`);
    else {
      console.log(`  >>> SLIP at quad ${firstSlip}: walker uses sel=${trueQuadSel[firstSlip]}, body_decoder assigns sel=${assumedSel(firstSlip)}  *** WRONG SPRITE -> SCRAMBLE ***`);
      // show a few
      console.log(`      quad:  true_sel  assumed_sel`);
      for(let i=Math.max(0,firstSlip-1);i<Math.min(totalQuads,firstSlip+6);i++)
        console.log(`      [${i}]    ${trueQuadSel[i]}        ${assumedSel(i)}   ${trueQuadSel[i]!==assumedSel(i)?'<-- mismatch':''}`);
    }
    console.log('');
  }
}
