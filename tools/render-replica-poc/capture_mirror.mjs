// capture_mirror.mjs — capture a live ZCST mirror stream to a .zcst file that
// render_ta.mjs --mirror can replay headless.
//
// Each WebSocket binary message from the relay is ONE complete ZCST envelope
// (the cockpit calls FrameDecoder.applyFrame(msg) per message — transport.mjs:172).
// We persist them with a [u32 LE length][bytes] frame header per message, which
// render_ta.mjs's decodeMirror() reads back in order. We deliberately keep:
//   - the FIRST SYNC/FSYN we see (seeds full VRAM + PVR), and
//   - the next few TA keyframe/delta frames (so a delta has its predecessor).
//
// Usage:
//   node capture_mirror.mjs --url wss://nobd.net/ws --out frame.zcst --frames 8
// (Node 22 has a global WebSocket.)

import { writeFileSync } from 'node:fs';

function arg(name, def) { const i = process.argv.indexOf(name); return i >= 0 ? process.argv[i + 1] : def; }
const url = arg('--url', 'wss://nobd.net/ws');
const out = arg('--out', 'frame.zcst');
const wantFrames = +arg('--frames', '8');

const MAGIC = { ZCST: 0x5453435A, SYNC: 0x434E5953, FSYN: 0x4E595346 };
const chunks = [];
let haveSync = false, taFrames = 0;

function magicOf(u8) {
    if (u8.length < 4) return 0;
    const dv = new DataView(u8.buffer, u8.byteOffset, 4);
    return dv.getUint32(0, true);
}
// ZCST is compressed; the inner magic (SYNC/FSYN) is only visible after
// decompress. For capture we don't decompress — we keep the first message
// (almost always the SYNC that the relay replays on connect) plus the next N.
const ws = new WebSocket(url);
ws.binaryType = 'arraybuffer';
ws.onopen = () => console.error('[capture] connected', url);
ws.onerror = (e) => { console.error('[capture] ws error', e.message || e); process.exit(1); };
ws.onclose = () => finish();
ws.onmessage = (e) => {
    const u8 = new Uint8Array(e.data);
    // keep the first message unconditionally (the connect-replay SYNC), then
    // accumulate until we have wantFrames messages total.
    chunks.push(u8);
    if (magicOf(u8) === MAGIC.ZCST || true) taFrames++;
    if (chunks.length === 1) haveSync = true;
    console.error(`[capture] msg ${chunks.length} (${u8.length}B)`);
    if (chunks.length >= wantFrames + 1) finish();
};

function finish() {
    if (!chunks.length) { console.error('[capture] no messages'); process.exit(1); }
    let total = 0; for (const c of chunks) total += 4 + c.length;
    const buf = new Uint8Array(total);
    const dv = new DataView(buf.buffer);
    let off = 0;
    for (const c of chunks) { dv.setUint32(off, c.length, true); off += 4; buf.set(c, off); off += c.length; }
    writeFileSync(out, Buffer.from(buf.buffer, 0, total));
    console.error(`[capture] wrote ${out}: ${chunks.length} messages, ${total} bytes`);
    process.exit(0);
}

setTimeout(() => { console.error('[capture] timeout'); finish(); }, 15000);
