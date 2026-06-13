import { readFileSync } from 'node:fs';
const ram=new Uint8Array(readFileSync(process.argv[2]||'live_ram.bin'));
const G=a=>a&0xFFFFFF;
const r16u=a=>ram[G(a)]|(ram[G(a)+1]<<8);
const r32=a=>(ram[G(a)]|(ram[G(a)+1]<<8)|(ram[G(a)+2]<<16)|(ram[G(a)+3]<<24))>>>0;
const r8s=a=>(ram[G(a)]<<24)>>24;
const isRam=g=>(((g>>>24)&0x7F)===0x0C)&&g!==0;
// arena base + cursor
console.log('arena_base *(0x8C1F9D94)=',r32(0x8C1F9D94),' obj_cursor *(0x8C1F9D98)=',r32(0x8C1F9D98));
const COUNT=0x8C2895E0,PTR=0x8C287DE0,STR=0x180;
for(let L=0;L<16;L++){const cnt=r8s(COUNT+L);if(cnt<=0)continue;
 for(let i=0;i<cnt;i++){const node=r32(PTR+L*STR+i*4);if(!isRam(node))continue;
  if(r8s(node+3)!==0)continue;
  const dc=r16u(node+0xDC);
  const gfx2=r32(node+0x160);
  const sid=r16u(node+0x144);
  // GFX2 cell = GFX2 + *(u32)(GFX2 + (sid&0x7FFF)*4); first u16 = record count
  const cellOff=r32(gfx2+(sid&0x7FFF)*4);
  const cell=gfx2+cellOff;
  const recCount=r16u(cell);
  console.log(`L${L}[${i}] node=${node.toString(16)} sid=0x${sid.toString(16)} +0xDC=${dc} GFX2=0x${gfx2.toString(16)} cellOff=0x${cellOff.toString(16)} recCount=${recCount}`);
 }
}
