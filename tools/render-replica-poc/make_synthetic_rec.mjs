// make_synthetic_rec.mjs — Live-Wire Phase 4b DE-RISK builder.
//
// Emits a VALID MCRR recording (docs/RENDER-REPLICA-RECORDING-FORMAT.md) from the
// single-frame _ryu_capture dump, with N synthetic frames in which the active char's
// world posX (+0x34) is translated a few px/frame so the transpiled body VISIBLY
// MOVES across the screen when replay.html plays it through render_frame -> pvr2.
//
// This is the MOTION de-risk: no real recording exists yet, so we manufacture one that
// exercises the ENTIRE 4b path (parse header+tables -> overlay static once -> per-frame
// apply dynamic regions -> render_frame -> ta-parser -> pvr2-renderer -> animate).
//
// Synthetic frames carry NO valid engine TA (taSize=0) -> the player SKIPS the
// ground-truth byte-compare for them. The GT path is exercised later by the REAL prod
// recording (mc_render_rec.bin), which embeds engine_ta per frame.
//
// ROM-DERIVED -> the OUTPUT .bin is gitignored. Only THIS source is committed.
//
//   node tools/render-replica-poc/make_synthetic_rec.mjs [out.bin] [nFrames] [pxPerFrame]
//
import { readFileSync, writeFileSync } from 'node:fs';

const RYU = new URL('../../_ryu_capture/', import.meta.url);
const argv = process.argv.slice(2).filter(a => a !== '--gt');
const GT   = process.argv.includes('--gt');        // embed engine_ta on frame 0 (validator PASS demo)
const OUT = argv[0] || new URL('mc_render_rec_synth.bin', RYU).pathname;
const N_FRAMES   = Number(argv[1] || 60);
const PX_PER_FR  = Number(argv[2] || 4);   // world units (≈px) per frame

// Optional ground-truth body TA for frame 0 (converge_frame.mjs output: render_frame's body
// sprites in the engine's own 96B block layout, proven 9/9 param byte-exact). When --gt is set,
// frame 0 is UN-translated and carries this as engine_ta so the validator demonstrates a PASS.
let GT_TA = null;
if (GT) {
    try { GT_TA = new Uint8Array(readFileSync(new URL('ta_frame_engine.bin', import.meta.url))); }
    catch { throw new Error('--gt needs ta_frame_engine.bin (run: node tools/render-replica-poc/converge_frame.mjs)'); }
}

const VRAM_BYTES = 0x800000;     // 8 MB
const PVR_BYTES  = 0x8000;       // 32 KB

const ram  = new Uint8Array(readFileSync(new URL('mc_ram_dump.bin', RYU)));   // 16 MB area-3
const vram = new Uint8Array(readFileSync(new URL('mc_vram_dump.bin', RYU)));  // 8 MB
const pvr  = new Uint8Array(readFileSync(new URL('mc_pvr_regs.bin', RYU)));   // 32 KB
if (ram.length !== 0x1000000) throw new Error('RAM dump must be 16MB, got ' + ram.length);
if (vram.length !== VRAM_BYTES) throw new Error('VRAM dump must be 8MB, got ' + vram.length);

// ---- The read-set (re_kb finding:render_replica_readset; RECORDING-FORMAT.md "read-set") ----
// DYNAMIC regions ship per frame; tag[8] is a human label. Whole-region sizes (multi-char-safe).
// idxtab/rectab are pointer-indirected (their guest base is *(ptr)); the player resolves the
// indirection from the RAM image when applying, but the RECORDED guest_addr is the *resolved*
// base captured here, so playback is a plain addr&0xFFFFFF write. We resolve the two indirect
// bases from THIS dump.
const dv = new DataView(ram.buffer);
const idxtabBase = dv.getUint32(0x8C2DAD3C & 0xFFFFFF, true) >>> 0;
const rectabBase = dv.getUint32(0x8C2DAD4C & 0xFFFFFF, true) >>> 0;

const DYNAMIC = [
    { addr: 0x8C2895E0, len: 0x10,    tag: 'slotcnt'  },  // slot-table count array
    { addr: 0x8C287DE0, len: 16*0x180, tag: 'slotptr' },  // slot-table ptr arrays
    { addr: 0x8C268340, len: 6*0x5A4, tag: 'charstr'  },  // 6 char structs (the movers)
    { addr: 0x8C1F9D80, len: 0x20,    tag: 'arena'    },  // arena-control globals
    { addr: 0x8C1F9F9C, len: 0x200,   tag: 'tiledesc' },  // tile-descriptor scratch
    { addr: 0x8C2D6AD8, len: 0xC0,    tag: 'camM2M1'  },  // camera matrices
    { addr: 0x8C26A510, len: 0x40,    tag: 'camZ'     },  // camera-Z scale block
    { addr: 0x8C26823C, len: 0x04,    tag: 'GGPptr'   },  // GameGlobalPointer
    { addr: 0x8C268240, len: 0x40,    tag: 'GGPstruct'},  // *(GGP) global-accum
    { addr: 0x8C26A974, len: 0x100,   tag: 'rparmtab' },  // per-char render-param table
    { addr: 0x8C2DAD30, len: 0x40,    tag: 'rec/idxp' },  // rectab/idxtab pointer pair
    { addr: 0x8C2AA4C0, len: 0x10,    tag: 'rmodeword'},  // global render-mode word
    { addr: idxtabBase, len: 0x2000,  tag: 'idxtab'   },  // *(0x8C2DAD3C)
    { addr: rectabBase, len: 0x8000,  tag: 'rectab'   },  // *(0x8C2DAD4C)
];

// STATIC regions (ship once). VRAM+PVR are special header-counted blocks; GFX1/GFX2 are the
// two character-art tables, resolved from the active node's +0x15C/+0x160 pointers.
// For the synthetic case we DON'T need GFX1/GFX2 as separate static regions because the
// render_frame.wasm reads them straight out of the 16MB RAM image (they sit in area-3 RAM in
// this dump). We therefore emit ZERO discrete static regions and rely on the static RAM that
// ships implicitly: the player seeds the 16MB image from the DYNAMIC frame-0 + a static RAM
// backdrop. To make that backdrop available we add ONE catch-all static region = the whole
// 16MB RAM image (so every byte render_frame reads that ISN'T a per-frame dynamic region is
// present). This is correctness-first (large); the real prod hook ships only the read-set
// static GFX bands. Tag it 'ram16' so the player seeds the base image from it.
const STATIC = [
    { addr: 0x8C000000, len: 0x1000000, tag: 'ram16' },  // whole area-3 RAM backdrop (frame-0 base)
];

function tag8(s) { const b = new Uint8Array(8); for (let i=0;i<Math.min(8,s.length);i++) b[i]=s.charCodeAt(i); return b; }
const guestOff = a => (a >>> 0) & 0xFFFFFF;

// ---- assemble (growing chunk list; taSize can vary per frame) ----
const chunks = [];
const push = u8 => chunks.push(u8);
const u32le = v => { const b = new Uint8Array(4); new DataView(b.buffer).setUint32(0, v>>>0, true); return b; };

// HEADER
push(u32le(0x5252434D));   // "MCRR"
push(u32le(1));            // version
push(u32le(STATIC.length));
push(u32le(DYNAMIC.length));
push(u32le(N_FRAMES));
push(u32le(VRAM_BYTES));
push(u32le(PVR_BYTES));
push(u32le(0));            // reserved

// STATIC then DYNAMIC region tables
for (const r of [...STATIC, ...DYNAMIC]) { push(u32le(r.addr)); push(u32le(r.len)); push(tag8(r.tag)); }

// STATIC PAYLOAD (once): vram, pvr, then each static region's bytes
push(vram); push(pvr);
for (const r of STATIC) push(ram.subarray(guestOff(r.addr), guestOff(r.addr) + r.len));

// PER-FRAME RECORDS: clone the dynamic regions from the base RAM, then mutate the char struct
// so P2C1 (the active Cable body, +0x34 world posX) translates PX_PER_FR each frame.
const P2C1_off = guestOff(0x8C2688E4);
for (let f = 0; f < N_FRAMES; f++) {
    // --gt: frame 0 is UN-translated and carries the body engine TA as ground truth.
    const isGT = GT && f === 0;
    const taSize = isGT ? GT_TA.length : 0;
    push(u32le(0x784D5246));   // "FRMx"
    push(u32le(f));            // vframe
    push(u32le(taSize));       // engine TA byte count (ground truth, or 0)

    for (const r of DYNAMIC) {
        const src = ram.subarray(guestOff(r.addr), guestOff(r.addr) + r.len);
        if (r.tag === 'charstr' && !isGT) {
            const blk = src.slice();
            const bdv = new DataView(blk.buffer);
            const localPosX = (P2C1_off - guestOff(0x8C268340)) + 0x34;
            bdv.setFloat32(localPosX, bdv.getFloat32(localPosX, true) + PX_PER_FR * f, true);
            push(blk);
        } else {
            push(src);          // GT frame (or non-char region): verbatim base bytes
        }
    }
    if (taSize) push(GT_TA);   // engine_ta ground truth
}

// flatten
let total = 0; for (const c of chunks) total += c.length;
const out = new Uint8Array(total);
{ let p = 0; for (const c of chunks) { out.set(c, p); p += c.length; } }

let dynPerFrame = 0; for (const r of DYNAMIC) dynPerFrame += r.len;
writeFileSync(OUT, out);
console.log(`MCRR ${GT?'GT-demo':'synthetic'}: ${N_FRAMES} frames, ${PX_PER_FR}px/frame translate of P2C1 posX(+0x34)${GT?'; frame 0 carries body engine_ta ('+GT_TA.length+'B) for validator PASS':''}.`);
console.log(`  static regions: ${STATIC.length} (+VRAM 8MB +PVR 32KB), dynamic regions: ${DYNAMIC.length} (${dynPerFrame}B/frame)`);
console.log(`  idxtab base=0x${idxtabBase.toString(16)}  rectab base=0x${rectabBase.toString(16)}`);
console.log(`  wrote ${OUT} (${(total/1048576).toFixed(1)} MB)`);
