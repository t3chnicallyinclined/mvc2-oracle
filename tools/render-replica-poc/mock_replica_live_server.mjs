// mock_replica_live_server.mjs — Phase 4c LIVE-path DE-RISK server.
//
// Replica-Live protocol = the SAME MCRR format, STREAMED over a WebSocket, so the
// browser reuses its MCRR parser verbatim. This mock proves the live path end-to-end
// BEFORE the real headless render-replica hook exists:
//
//   msg 1 (on connect) = STATIC PREFIX, ZCST-compressed:
//       "ZCST"(4) + u32 uncompressedSize(LE) + zstd(blob)
//     blob decompresses to the MCRR PREFIX =
//       header(32B "MCRR"…) + STATIC region table + DYNAMIC region table
//       + STATIC payload (VRAM 8MB + PVR 32KB + each static region's bytes).
//     i.e. EVERYTHING in the .bin BEFORE the first "FRMx" record.
//
//   msg N (per frame) = FRAME RECORD, raw (uncompressed):
//       "FRMx"(4) + vframe(u32 LE) + taSize(u32 LE) + DYNAMIC-region bytes + [engine_ta]
//     i.e. one whole "FRMx" record copied verbatim out of the .bin. The browser already
//     knows the DYNAMIC region addr/len from the prefix's dynamic table, so it just
//     splats each region into the RAM image (addr & 0xFFFFFF) and runs render_frame.
//
// Source = a synthetic MCRR (tools/render-replica-poc/make_synthetic_rec.mjs output) or
// any real .mcrr capture. We DON'T re-encode anything — we slice the file at the first
// frame record, ZCST the prefix, and dribble the frame records out at ~60/s.
//
// zstd: node v22's built-in zlib.zstdCompressSync; the browser decompresses with the SAME
// fzstd.decompress the TA-mirror cockpit uses (round-trip verified compatible).
//
//   node tools/render-replica-poc/mock_replica_live_server.mjs [rec.bin] [port] [fps]
// defaults: rec=../../_ryu_capture/mc_render_rec_synth.bin  port=7212  fps=60
//
// ROM-DERIVED .bin is gitignored; only this source is committed.

import { readFileSync } from 'node:fs';
import { zstdCompressSync } from 'node:zlib';
import { WebSocketServer } from 'ws';

const HERE = new URL('.', import.meta.url);
const argv = process.argv.slice(2).filter(a => a !== '--zstd');
const ZSTD_FRAMES = process.argv.includes('--zstd');   // ZCST-wrap each frame (match the prod server exactly)
const REC_PATH = argv[0] || new URL('../../_ryu_capture/mc_render_rec_synth.bin', HERE).pathname;
const PORT     = Number(argv[1] || 7212);
const FPS      = Number(argv[2] || 60);
const FRAME_MS = 1000 / FPS;

// ---------------------------------------------------------------- load + index MCRR
// We mirror replay.html's parseMCRR layout EXACTLY so the prefix/frame split is byte-correct.
const buf = new Uint8Array(readFileSync(REC_PATH));
const dv  = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
let p = 0;
const u32 = () => { const v = dv.getUint32(p, true); p += 4; return v >>> 0; };

if (u32() !== 0x5252434D) throw new Error(`${REC_PATH}: bad MCRR magic (not "MCRR")`);
const version  = u32();
const nStatic  = u32();
const nDynamic = u32();
const nFrames  = u32();
const vramBytes= u32();
const pvrBytes = u32();
u32();  // reserved

const region = () => { const addr = u32(); const len = u32(); let tag=''; for (let i=0;i<8;i++){const c=buf[p+i]; if(c)tag+=String.fromCharCode(c);} p+=8; return {addr,len,tag}; };
const staticRegs  = Array.from({length:nStatic },  region);
const dynamicRegs = Array.from({length:nDynamic}, region);

// static payload: vram + pvr + each static region
p += vramBytes;
p += pvrBytes;
for (const r of staticRegs) p += r.len;

// p now sits at the FIRST "FRMx" record — this is the prefix/frames boundary.
const prefixEnd = p;
const prefix = buf.subarray(0, prefixEnd);

// index the frame records (offset + total length of each "FRMx" block)
const frames = [];
for (let f = 0; f < nFrames; f++) {
    const fStart = p;
    if (u32() !== 0x784D5246) throw new Error(`frame ${f}: bad "FRMx" magic at off ${fStart}`);
    /*vframe*/ u32();
    const taSize = u32();
    for (const r of dynamicRegs) p += r.len;   // dynamic payload
    p += taSize;                               // engine_ta
    frames.push(buf.subarray(fStart, p));
}

let dynPerFrame = 0; for (const r of dynamicRegs) dynPerFrame += r.len;

// ---------------------------------------------------------------- ZCST static prefix
// "ZCST"(4) + u32 uncompressedSize(LE) + zstd(prefix) — exactly the TA-mirror envelope.
const comp = zstdCompressSync(Buffer.from(prefix));
const env = Buffer.alloc(8 + comp.length);
env.writeUInt32LE(0x5453435A, 0);        // "ZCST" little-endian bytes (Z,C,S,T)
env.writeUInt32LE(prefix.length, 4);     // uncompressed size
comp.copy(env, 8);

// Optionally ZCST-wrap each FRMx frame to EXACTLY mirror the prod server (which compresses
// every message). Precompute so the per-tick path stays cheap.
const zcstWrap = (u8) => { const c = zstdCompressSync(Buffer.from(u8)); const e = Buffer.alloc(8 + c.length); e.writeUInt32LE(0x5453435A, 0); e.writeUInt32LE(u8.length, 4); c.copy(e, 8); return e; };
const wireFrames = ZSTD_FRAMES ? frames.map(zcstWrap) : frames;

console.log(`[mock-replica-live] ${REC_PATH}${ZSTD_FRAMES ? '  [ZCST frames -> exact prod protocol]' : '  [raw frames]'}`);
console.log(`  MCRR v${version}: ${nStatic} static, ${nDynamic} dynamic, ${nFrames} frames; vram=${vramBytes} pvr=${pvrBytes}`);
console.log(`  prefix ${(prefix.length/1048576).toFixed(1)} MB -> ZCST ${(env.length/1048576).toFixed(2)} MB  | dynamic ${dynPerFrame}B/frame`);
console.log(`  serving ws://127.0.0.1:${PORT}  @ ${FPS} fps (${FRAME_MS.toFixed(2)} ms/frame), looping ${nFrames} frames`);

// ---------------------------------------------------------------- WS server
const wss = new WebSocketServer({ port: PORT });
wss.on('connection', (ws, req) => {
    const who = req.socket.remoteAddress + ':' + req.socket.remotePort;
    console.log(`[mock-replica-live] + client ${who}`);

    // msg 1: ZCST static prefix
    ws.send(env);

    // then one FRMx record per frame, looping
    let i = 0;
    const timer = setInterval(() => {
        if (ws.readyState !== ws.OPEN) { clearInterval(timer); return; }
        // bufferedAmount backpressure: skip a tick if the socket is congested
        if (ws.bufferedAmount > 4 * 1024 * 1024) return;
        ws.send(wireFrames[i]);
        i = (i + 1) % wireFrames.length;
    }, FRAME_MS);

    ws.on('close', () => { clearInterval(timer); console.log(`[mock-replica-live] - client ${who}`); });
    ws.on('error', () => clearInterval(timer));
});

wss.on('listening', () => console.log('[mock-replica-live] listening. Point replay.html ?live=ws://127.0.0.1:' + PORT));
