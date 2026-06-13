// livecap.mjs — capture prod replica-live stream to an MCRR file + per-frame stats.
//   node livecap.mjs --url wss://nobd.net/replica-ws --out live.mcrr --frames 400
// Reconstructs a scrubbable .mcrr: prefix (decompressed) followed by N FRMx records
// (decompressed), with nFrames patched into the header. Also runs the slot-walk count
// scan offline to report per-frame body-node count + flag the 1024 over-read frames.

import { writeFileSync } from 'node:fs';
import { zstdDecompressSync } from 'node:zlib';
import { WebSocket } from 'ws';

function arg(n, d){ const i = process.argv.indexOf(n); return i>=0 ? process.argv[i+1] : d; }
const url    = arg('--url', 'wss://nobd.net/replica-ws');
const out    = arg('--out', 'live.mcrr');
const want   = +arg('--frames', '400');

const MAGIC_ZCST = 0x5453435A, MAGIC_MCRR = 0x5252434D, MAGIC_FRMX = 0x784D5246;

function unzcst(u8){
  const dv = new DataView(u8.buffer, u8.byteOffset, u8.byteLength);
  if (u8.length>=8 && dv.getUint32(0,true)===MAGIC_ZCST){
    return new Uint8Array(zstdDecompressSync(Buffer.from(u8.subarray(8))));
  }
  return u8;
}

// Parse prefix to learn dyn region table (for the offline count scan).
function parsePrefix(buf){
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  let p=0; const u32=()=>{const v=dv.getUint32(p,true);p+=4;return v>>>0;};
  if (u32()!==MAGIC_MCRR) throw new Error('bad MCRR magic');
  const version=u32(), nStatic=u32(), nDynamic=u32(), nFrames=u32(), vramBytes=u32(), pvrBytes=u32(); u32();
  const region=()=>{const addr=u32(),len=u32();let tag='';for(let i=0;i<8;i++){const c=buf[p+i];if(c)tag+=String.fromCharCode(c);}p+=8;return{addr,len,tag};};
  const staticRegs=Array.from({length:nStatic},region);
  const dynamicRegs=Array.from({length:nDynamic},region);
  return {version,nStatic,nDynamic,nFrames,vramBytes,pvrBytes,staticRegs,dynamicRegs,headerEnd:p,buf};
}

// Build a 16MB RAM image from the static prefix (ram16 + GFX regions).
function seedRam(pre){
  const ram = new Uint8Array(16*1024*1024);
  let p = pre.headerEnd + pre.vramBytes + pre.pvrBytes;
  for (const r of pre.staticRegs){
    const bytes = pre.buf.subarray(p, p + r.len); p += r.len;
    if (r.tag==='ram16') ram.set(bytes, 0);
    else ram.set(bytes, r.addr & 0xFFFFFF);
  }
  return ram;
}
function applyDyn(ram, pre, frameBuf){
  // frameBuf = FRMx record (decompressed): magic(4)+vframe(4)+taSize(4)+dyn bytes
  const dv=new DataView(frameBuf.buffer,frameBuf.byteOffset,frameBuf.byteLength);
  const vframe=dv.getUint32(4,true), taSize=dv.getUint32(8,true);
  let p=12;
  for (const r of pre.dynamicRegs){
    ram.set(frameBuf.subarray(p,p+r.len), r.addr & 0xFFFFFF);
    p += r.len;
  }
  return {vframe,taSize};
}

// Offline slot-walk count scan mirroring render_sprites_0308c2 EXACTLY (signed byte count).
function scanSlots(ram){
  const COUNT_BASE=0x2895E0, PTR_BASE=0x287DE0, STRIDE=0x180;
  const r8s = a => (ram[a]<<24)>>24;          // signed byte
  const r32 = a => (ram[a]|(ram[a+1]<<8)|(ram[a+2]<<16)|(ram[a+3]<<24))>>>0;
  let body=0, eff=0, total=0;
  const counts=[], nodesPerLayer=[];
  for (let L=0; L<16; L++){
    const cnt = r8s(COUNT_BASE + L);
    counts.push(cnt);
    const base = PTR_BASE + L*STRIDE;
    let lb=0;
    for (let i=0; i<cnt; i++){           // note: if cnt<0, loop body skipped (i<cnt false)
      const nodeG = r32(base + i*4);     // guest addr 0x8C...
      const node = nodeG & 0xFFFFFF;
      total++;
      if (node===0 || ((nodeG>>>24)&0x7F)!==0x0C){ continue; }
      const cat = (ram[node+3]<<24)>>24;
      if (cat===0) body++; else eff++;
      lb++;
    }
    nodesPerLayer.push(lb);
  }
  return {counts, body, eff, total, nodesPerLayer};
}

const ws = new WebSocket(url);
ws.binaryType = 'arraybuffer';
let pre=null, ram=null, seen=0;
const chunks=[];   // raw decompressed: [prefix][frmx][frmx]...
let prefixBytes=null;

ws.on('open', ()=>console.error('[livecap] open', url));
ws.on('error', e=>{ console.error('[livecap] ws error', e.message); process.exit(1); });
ws.on('close', ()=>finish());

ws.on('message', (data)=>{
  const u8 = new Uint8Array(data);
  let raw;
  try { raw = unzcst(u8); } catch(e){ console.error('[livecap] unzcst fail', e.message); return; }
  const dv = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);
  const magic = dv.getUint32(0,true);
  if (magic===MAGIC_MCRR && !pre){
    pre = parsePrefix(raw);
    prefixBytes = raw;
    ram = seedRam(pre);
    console.error(`[livecap] prefix: ${pre.nStatic} static / ${pre.nDynamic} dyn / vram=${pre.vramBytes} pvr=${pre.pvrBytes}`);
    console.error(`[livecap] dyn regions: ${pre.dynamicRegs.map(r=>`${r.tag}@${r.addr.toString(16)}:${r.len}`).join(' ')}`);
    return;
  }
  if (magic===MAGIC_FRMX && pre){
    chunks.push(raw);
    const {vframe,taSize} = applyDyn(ram, pre, raw);
    const s = scanSlots(ram);
    const flag = s.total>=1000 ? '  <<<< OVER-READ' : (s.total>=256?'  (>256)':'');
    if (seen<8 || s.total>=256 || seen%30===0)
      console.error(`[f${seen}] vframe=${vframe} counts=[${s.counts.join(',')}] bodies=${s.body} eff=${s.eff} total=${s.total}${flag}`);
    seen++;
    if (seen>=want) finish();
  }
});

function finish(){
  if (!pre){ console.error('[livecap] no prefix captured'); process.exit(1); }
  // Patch nFrames into the prefix header (offset 16) and concat prefix+frames.
  const pb = Buffer.from(prefixBytes);
  pb.writeUInt32LE(chunks.length, 16);
  const parts = [pb, ...chunks.map(c=>Buffer.from(c))];
  const file = Buffer.concat(parts);
  writeFileSync(out, file);
  console.error(`[livecap] wrote ${out}: ${chunks.length} frames, ${(file.length/1048576).toFixed(1)} MB`);
  process.exit(0);
}
