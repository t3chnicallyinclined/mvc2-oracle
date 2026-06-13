// livecap_wasm.mjs — connect prod, run render_frame.wasm per frame LIVE, save any frame
// whose quad count >= THRESH (default 200) as a standalone .mcrr (prefix + that 1 frame).
import { writeFileSync } from 'node:fs';
import { zstdDecompressSync } from 'node:zlib';
import { WebSocket } from 'ws';
import createRenderFrame from './render_frame_node.mjs';
function arg(n,d){const i=process.argv.indexOf(n);return i>=0?process.argv[i+1]:d;}
const url=arg('--url','wss://nobd.net/replica-live'); const want=+arg('--frames','2000'); const THRESH=+arg('--thresh','150');
const MZ=0x5453435A,MM=0x5252434D,MF=0x784D5246;
function unz(u8){const dv=new DataView(u8.buffer,u8.byteOffset,u8.byteLength);if(u8.length>=8&&dv.getUint32(0,true)===MZ)return new Uint8Array(zstdDecompressSync(Buffer.from(u8.subarray(8))));return u8;}
const Mod=await createRenderFrame(); const RAM=16*1024*1024; const ramPtr=Mod._malloc(RAM); const cap=2*1024*1024; const outPtr=Mod._malloc(cap);
let pre=null,prefixRaw=null,dyn=[],seen=0,maxQ=0,maxRaw=null,saved=0;
function parsePrefix(buf){const dv=new DataView(buf.buffer,buf.byteOffset,buf.byteLength);let p=0;const u32=()=>{const v=dv.getUint32(p,true);p+=4;return v>>>0;};u32();const ver=u32(),nS=u32(),nD=u32(),nF=u32(),vb=u32(),pb=u32();u32();const reg=()=>{const a=u32(),l=u32();let t='';for(let i=0;i<8;i++){const c=buf[p+i];if(c)t+=String.fromCharCode(c);}p+=8;return{addr:a,len:l,tag:t};};const sR=Array.from({length:nS},reg);const dR=Array.from({length:nD},reg);return{nS,nD,vb,pb,sR,dR,he:p,buf};}
let ram=new Uint8Array(RAM);
function seed(pre){let p=pre.he+pre.vb+pre.pb;for(const r of pre.sR){const b=pre.buf.subarray(p,p+r.len);p+=r.len;if(r.tag==='ram16')ram.set(b,0);else ram.set(b,r.addr&0xFFFFFF);}}
const ws=new WebSocket(url);ws.binaryType='arraybuffer';
ws.on('open',()=>console.error('[cap] open'));ws.on('error',e=>{console.error('[cap]',e.message);process.exit(1);});ws.on('close',()=>fin());
ws.on('message',d=>{const u8=new Uint8Array(d);let raw;try{raw=unz(u8);}catch{return;}const dv=new DataView(raw.buffer,raw.byteOffset,raw.byteLength);const m=dv.getUint32(0,true);
 if(m===MM&&!pre){pre=parsePrefix(raw);prefixRaw=raw;seed(pre);console.error(`[cap] prefix ${pre.nS}st/${pre.nD}dyn`);return;}
 if(m===MF&&pre){ let p=12;for(const r of pre.dR){ram.set(raw.subarray(p,p+r.len),r.addr&0xFFFFFF);p+=r.len;}
   Mod.HEAPU8.set(ram,ramPtr);const len=Mod._render_frame_ta(ramPtr,outPtr,cap);const q=Mod._render_frame_quad_count();const b=Mod._render_frame_body_count();
   if(q>maxQ){maxQ=q;maxRaw=raw.slice();}
   if(q>=THRESH&&saved<3){ const pb=Buffer.from(prefixRaw);pb.writeUInt32LE(1,16);writeFileSync(`hot_${saved}_q${q}.mcrr`,Buffer.concat([pb,Buffer.from(raw)]));console.error(`[cap] SAVED hot_${saved}_q${q}.mcrr bodies=${b} quads=${q}`);saved++; }
   if(seen%60===0||q>=THRESH)console.error(`[f${seen}] vframe=${dv.getUint32(4,true)} bodies=${b} quads=${q}`);
   seen++; if(seen>=want)fin(); }
});
function fin(){ if(maxRaw){const pb=Buffer.from(prefixRaw);pb.writeUInt32LE(1,16);writeFileSync(`maxq_${maxQ}.mcrr`,Buffer.concat([pb,Buffer.from(maxRaw)]));console.error(`[cap] max quads=${maxQ} saved maxq_${maxQ}.mcrr`);} process.exit(0); }
