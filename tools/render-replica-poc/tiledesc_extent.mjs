import { readFileSync } from 'node:fs';
const ram=new Uint8Array(readFileSync('live_ram.bin'));
const G=a=>a&0xFFFFFF;
// descriptor table 0x8C1F9F9C: print last non-zero offset within 0x2000
let last=-1; for(let i=0;i<0x2000;i++) if(ram[G(0x8C1F9F9C)+i]!==0) last=i;
console.log(`tiledesc 0x8C1F9F9C extends to offset 0x${last.toString(16)} (${last} bytes) of live non-zero data; shipped=512`);
console.log(`=> with 2 calm bodies the engine table already has ${last>512?'MORE':'<='} than 512B populated`);
