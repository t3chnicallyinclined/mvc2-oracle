// render_ta.mjs — HEADLESS exact-pixel render of a TA command buffer.
//
//   TA buffer (+ VRAM 8MB + pvr_regs 32KB + pvrSnapshot 16xu32)
//        -> ta-parser.mjs (TAParser.parse [+ fillBGP])      [reused VERBATIM]
//        -> pvr2-renderer.mjs (PVR2Renderer.renderFrame)    [reused VERBATIM]
//        -> offscreen WebGPU render target -> readback -> PNG
//
// This is the SAME pipeline the live cockpit (web/webgpu-test.html) runs; here it
// runs headless on a file, on demand, so we can pixel-test the Option-C
// render-replica's emitted TA offline and diff vs ground truth.
//
// INPUT INTERFACE (see render-replica-poc/README.md for the byte layout):
//   --mirror <file.zcst>   A captured ZCST mirror stream (one or more length-
//                          prefixed messages: SYNC seeds VRAM+PVR, then a TA
//                          keyframe/delta). FrameDecoder turns it into exactly
//                          the renderFrame() inputs. EASIEST path; what prod dumps.
//   OR the raw triple (what the transpiled replica + a VRAM/PVR dump produce):
//   --ta <file>            raw TA command stream (PVR2 TA format the parser eats)
//   --vram <file>          8 MiB VRAM image (textures the TA samples by tcw)
//   --pvr <file>           32 KiB PVR register block (palette @ +0x1000, ctrl @ +0x108)
//   --snap <file>          optional 64 B = 16x u32 LE pvrSnapshot (FB dims etc.).
//                          If omitted, synthesized for a 640x480 framebuffer.
//   --out <file.png>       output PNG (default out.png)
//   --width/--height       render size (default 640x480)
//   --no-bg                skip fillBGP (background polygon)
//   --frame <N>            with --mirror, render the Nth TA frame (default: last)
//   --self-test            render a synthetic textured quad (proves WebGPU+readback)

import './webgpu-headless.mjs';           // installs GPU globals + navigator.gpu (side effect)
import { initDevice } from './webgpu-headless.mjs';
import { readFileSync, writeFileSync } from 'node:fs';
import { PNG } from 'pngjs';

const W_DIR = new URL('../../web/webgpu/', import.meta.url);
const { PVR2Renderer } = await import(new URL('pvr2-renderer.mjs', W_DIR));
const { TAParser }     = await import(new URL('ta-parser.mjs', W_DIR));
const { TextureManager } = await import(new URL('texture-manager.mjs', W_DIR));
const { FrameDecoder } = await import(new URL('frame-decoder.mjs', W_DIR));

const VRAM_SIZE = 8 * 1024 * 1024;
const PVR_REG_SIZE = 32 * 1024;

function parseArgs(argv) {
    const a = { out: 'out.png', width: 640, height: 480, bg: true, frame: -1, selfTest: false };
    for (let i = 2; i < argv.length; i++) {
        const k = argv[i];
        const next = () => argv[++i];
        if (k === '--mirror') a.mirror = next();
        else if (k === '--ta') a.ta = next();
        else if (k === '--vram') a.vram = next();
        else if (k === '--pvr') a.pvr = next();
        else if (k === '--snap') a.snap = next();
        else if (k === '--out') a.out = next();
        else if (k === '--width') a.width = +next();
        else if (k === '--height') a.height = +next();
        else if (k === '--frame') a.frame = +next();
        else if (k === '--no-bg') a.bg = false;
        else if (k === '--self-test') a.selfTest = true;
        else { console.error('unknown arg', k); process.exit(2); }
    }
    return a;
}

function readU8(path, expectSize) {
    const buf = readFileSync(path);
    const u8 = new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
    if (expectSize && u8.length !== expectSize) {
        console.warn(`[warn] ${path}: ${u8.length} bytes (expected ${expectSize}) — padding/truncating to ${expectSize}`);
        const fixed = new Uint8Array(expectSize);
        fixed.set(u8.subarray(0, expectSize));
        return fixed;
    }
    return u8;
}

// Build the renderTarget the GOLD-STANDARD renderFrame() expects for offscreen
// output: a color texture (COPY_SRC so we can read it back) + a depth texture.
function makeRenderTarget(device, fmt, w, h) {
    const color = device.createTexture({
        size: [w, h], format: fmt,
        usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC | GPUTextureUsage.TEXTURE_BINDING,
    });
    const depth = device.createTexture({
        size: [w, h], format: 'depth32float',
        usage: GPUTextureUsage.RENDER_ATTACHMENT,
    });
    return {
        color, depth,
        colorView: color.createView(), depthView: depth.createView(),
        width: w, height: h,
    };
}

// Copy a color texture (rgba8unorm/bgra8unorm) back to CPU and return RGBA bytes.
async function readbackRGBA(device, texture, w, h, fmt) {
    const bytesPerRow = Math.ceil(w * 4 / 256) * 256; // 256-byte row alignment
    const readBuf = device.createBuffer({
        size: bytesPerRow * h,
        usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ,
    });
    const enc = device.createCommandEncoder();
    enc.copyTextureToBuffer(
        { texture },
        { buffer: readBuf, bytesPerRow, rowsPerImage: h },
        [w, h, 1],
    );
    device.queue.submit([enc.finish()]);
    await readBuf.mapAsync(GPUMapMode.READ);
    const mapped = new Uint8Array(readBuf.getMappedRange()).slice();
    readBuf.unmap();
    readBuf.destroy();

    // Tightly pack + (if bgra) swap to rgba.
    const out = new Uint8Array(w * h * 4);
    const bgra = fmt.startsWith('bgra');
    for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
            const s = y * bytesPerRow + x * 4;
            const d = (y * w + x) * 4;
            if (bgra) { out[d] = mapped[s + 2]; out[d + 1] = mapped[s + 1]; out[d + 2] = mapped[s]; out[d + 3] = mapped[s + 3]; }
            else { out[d] = mapped[s]; out[d + 1] = mapped[s + 1]; out[d + 2] = mapped[s + 2]; out[d + 3] = mapped[s + 3]; }
        }
    }
    return out;
}

function writePNG(path, rgba, w, h) {
    const png = new PNG({ width: w, height: h });
    png.data = Buffer.from(rgba.buffer, rgba.byteOffset, rgba.byteLength);
    writeFileSync(path, PNG.sync.write(png));
}

// Synthesize a pvrSnapshot[0] for a WxH framebuffer. _ndcMat reads:
//   tx = g&0x3F, ty=(g>>16)&0x3F, fbW=(tx+1)*32, fbH=(ty+1)*32
function synthSnap(w, h) {
    const snap = new Uint32Array(16);
    const tx = Math.max(0, Math.round(w / 32) - 1) & 0x3F;
    const ty = Math.max(0, Math.round(h / 32) - 1) & 0x3F;
    snap[0] = (tx & 0x3F) | ((ty & 0x3F) << 16);
    return snap;
}

// Decode a captured ZCST mirror stream into renderFrame inputs via FrameDecoder
// (REUSED VERBATIM — the same decoder the cockpit runs). The stream is a sequence
// of length-prefixed messages: [u32 LE len][len bytes] per message. A leading
// SYNC/FSYN seeds full VRAM+PVR; subsequent TA keyframe/delta frames produce the
// per-frame {taBuffer, pvrSnapshot, dirtyPageList}. We return the Nth (or last)
// renderable frame + the decoder (which holds the accumulated VRAM + pvrRegs).
function decodeMirror(path, frameIdx) {
    const file = readFileSync(path);
    const dv = new DataView(file.buffer, file.byteOffset, file.byteLength);
    const D = new FrameDecoder();
    const frames = [];
    let off = 0, msgCount = 0;
    // Auto-detect framing: if it doesn't look length-prefixed, treat the whole
    // file as a single message.
    const looksFramed = file.length >= 4 && dv.getUint32(0, true) + 4 <= file.length && dv.getUint32(0, true) > 8;
    const msgs = [];
    if (looksFramed) {
        while (off + 4 <= file.length) {
            const len = dv.getUint32(off, true); off += 4;
            if (len === 0 || off + len > file.length) break;
            msgs.push(file.subarray(off, off + len)); off += len;
        }
    } else {
        msgs.push(file);
    }
    for (const m of msgs) {
        msgCount++;
        // Guard exactly like the cockpit (webgpu-test.html wraps applyFrame in
        // try/catch). A truncated delta / unexpected magic must not kill the run.
        let fr = null;
        try { fr = D.applyFrame(m); } catch (e) { console.warn(`[mirror] msg ${msgCount} (${m.length}B) parse skipped: ${e.message}`); continue; }
        if (D.syncPending) D.syncPending = false;
        if (fr) frames.push(fr);
    }
    if (!frames.length) throw new Error(`mirror ${path}: no renderable TA frame found in ${msgCount} messages`);
    const fr = frameIdx < 0 ? frames[frames.length - 1] : frames[Math.min(frameIdx, frames.length - 1)];
    return { D, fr, frameCount: frames.length, msgCount };
}

async function main() {
    const a = parseArgs(process.argv);
    const { device, info } = await initDevice();
    console.log('[gpu]', info.vendor || info.description || 'Dawn', '|', info.architecture || '', info.device || '');

    // Build the renderer WITHOUT a canvas: set fmt to our offscreen color format
    // and call _init() directly (bypasses init()'s canvas getContext/configure).
    const R = new PVR2Renderer();
    R.dev = device;
    R.fmt = 'rgba8unorm';                 // pipelines target this; must match render target
    device.addEventListener?.('uncapturederror', (e) => console.error('[wgpu-uncaptured]', e.error?.message || e));
    R._init(a.width, a.height);

    const rt = makeRenderTarget(device, R.fmt, a.width, a.height);

    // ---- SELF TEST: synthetic textured quad, proves WebGPU + readback + PNG ----
    if (a.selfTest) {
        const T = new TextureManager(device);
        // Minimal hand-built parsed frame: one translucent textured quad as a
        // triangle strip (4 verts). Vertex layout = 28 bytes (see VBL).
        const verts = 4;
        const ab = new ArrayBuffer(verts * 28);
        const f = new Float32Array(ab), u8 = new Uint8Array(ab);
        const quad = [
            [120, 100, 0.5, 0, 0], [520, 100, 0.5, 1, 0],
            [120, 380, 0.5, 0, 1], [520, 380, 0.5, 1, 1],
        ];
        for (let i = 0; i < 4; i++) {
            const [x, y, z, uu, vv] = quad[i];
            f[i * 7] = x; f[i * 7 + 1] = y; f[i * 7 + 2] = z;
            u8[i * 28 + 12] = 255; u8[i * 28 + 13] = 255; u8[i * 28 + 14] = 255; u8[i * 28 + 15] = 255; // white base
            f[i * 7 + 5] = uu; f[i * 7 + 6] = vv;
        }
        // A 2x2 checker fallback-ish texture pushed straight into the cache so
        // getTexture returns it for tcw=0 isn't trivial; instead use the gouraud
        // (untextured) path: pcw bit3=0 => fragment uses vertex color. Tint corners.
        const colors = [0xFFFF0000, 0xFF00FF00, 0xFF0000FF, 0xFFFFFF00];
        for (let i = 0; i < 4; i++) {
            const c = colors[i];
            u8[i * 28 + 12] = (c >> 16) & 0xFF; u8[i * 28 + 13] = (c >> 8) & 0xFF;
            u8[i * 28 + 14] = c & 0xFF; u8[i * 28 + 15] = (c >> 24) & 0xFF;
        }
        const pp = { first: 0, count: 4, isp: (4 << 29) | (1 << 27), tsp: (1 << 29), tcw: 0, pcw: (1 << 1) /*gouraud*/, tileclip: 0 };
        const parsed = {
            vertexData: u8, vertexCount: 4,
            opaque: [], punchThrough: [], translucent: [pp],
            renderPasses: [{ op_count: 0, pt_count: 0, tr_count: 1 }],
        };
        const snap = synthSnap(a.width, a.height);
        R.renderFrame(parsed, T, snap, new Uint8Array(VRAM_SIZE), { customBg: false, noSort: true }, rt);
        device.queue.submit([R._lastEncoder.finish()]);
        const rgba = await readbackRGBA(device, rt.color, a.width, a.height, R.fmt);
        writePNG(a.out, rgba, a.width, a.height);
        const nz = rgba.reduce((s, v, i) => s + (i % 4 !== 3 && v ? 1 : 0), 0);
        console.log(`[self-test] wrote ${a.out} (${a.width}x${a.height}); non-zero color samples=${nz}`);
        return;
    }

    // ---- REAL FRAME ----
    let parsed, vram, pvrRegs, snap;
    const P = new TAParser();
    const T = new TextureManager(device);

    if (a.mirror) {
        const { D, fr, frameCount, msgCount } = decodeMirror(a.mirror, a.frame);
        console.log(`[mirror] ${msgCount} messages, ${frameCount} TA frame(s); rendering frame ${a.frame < 0 ? frameCount - 1 : a.frame} (#${fr.frameNum})`);
        vram = D.vram; pvrRegs = D.pvrRegs; snap = fr.pvrSnapshot;
        T.setDirtyPages(fr.dirtyPageList, fr.pvrDirty);
        T.updatePalette(pvrRegs);
        parsed = P.parse(fr.taBuffer, fr.taSize);
        if (a.bg) { try { P.fillBGP(parsed, pvrRegs, vram); } catch (e) { console.warn('[fillBGP]', e.message); } }
    } else {
        if (!a.ta || !a.vram || !a.pvr) {
            console.error('Need --mirror <file>, or --ta + --vram + --pvr (+ optional --snap). See README.md.');
            process.exit(2);
        }
        const ta = readU8(a.ta);
        vram = readU8(a.vram, VRAM_SIZE);
        pvrRegs = readU8(a.pvr, PVR_REG_SIZE);
        snap = a.snap ? new Uint32Array(readU8(a.snap, 64).buffer.slice(0, 64)) : synthSnap(a.width, a.height);
        T.setDirtyPages(null, true);  // first frame: decode all textures, build palette
        T.updatePalette(pvrRegs);
        parsed = P.parse(ta, ta.length);
        if (a.bg) { try { P.fillBGP(parsed, pvrRegs, vram); } catch (e) { console.warn('[fillBGP]', e.message); } }
    }

    console.log(`[parse] ${parsed.vertexCount} verts | op=${parsed.opaque.length} pt=${parsed.punchThrough.length} tr=${parsed.translucent.length} | passes=${(parsed.renderPasses || []).length}`);

    // DBG matches the cockpit GOLD-STANDARD defaults: single-pass off, no-sort off
    // (per-triangle Z-sort like flycast). Leave everything else default.
    const DBG = {};
    R.renderFrame(parsed, T, snap, vram, DBG, rt);
    device.queue.submit([R._lastEncoder.finish()]);

    const rgba = await readbackRGBA(device, rt.color, a.width, a.height, R.fmt);
    writePNG(a.out, rgba, a.width, a.height);
    let nz = 0; for (let i = 0; i < rgba.length; i += 4) if (rgba[i] | rgba[i + 1] | rgba[i + 2]) nz++;
    console.log(`[done] wrote ${a.out} (${a.width}x${a.height}); ${nz}/${a.width * a.height} non-black pixels`);
}

main().catch((e) => { console.error(e); process.exit(1); });
