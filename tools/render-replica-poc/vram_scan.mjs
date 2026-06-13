import { readFileSync } from 'node:fs';
const vram=new Uint8Array(readFileSync('live_vram.bin'));
// total non-zero, and where the data concentrates (per 256KB bucket)
let total=0; const buckets=new Array(32).fill(0);
for(let i=0;i<vram.length;i++){ if(vram[i]){ total++; buckets[(i>>18)]++; } }
console.log(`VRAM total non-zero: ${total}/${vram.length} (${(100*total/vram.length).toFixed(1)}%)`);
console.log('per-256KB bucket non-zero:');
buckets.forEach((b,i)=>{ if(b>1000) console.log(`  [0x${(i<<18).toString(16)}..] ${b}`); });
// the tcw addr 0x448a00 is in bucket 0x40000 (256KB). Check neighbors.
const a=0x448a00; let nz=0; for(let i=a-0x2000;i<a+0x2000;i++) if(vram[i])nz++;
console.log(`around 0x448a00 (+-0x2000): ${nz} non-zero`);
