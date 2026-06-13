// converge_first_pixels.mjs — FIRST PIXELS from the transpiled render.
//
// Builds a PVR2 TA command buffer of textured SPRITE quads and emits it to a .ta
// file that render_ta.mjs (the real WebGPU pipeline) consumes. Two modes:
//
//   --mode reference   Use the CHARQ probe's OWN quads: real screen corners
//                      (A,B,C,D) + real tcw + real per-corner UVs from
//                      probe_body_uv.json. Renders the engine's actual body =>
//                      proves VRAM + PVR regs + tcw resolution + harness all work
//                      on THIS prod data (recognizable character pixels).
//
//   --mode transpiled  Use the TRANSPILED corners from ta_buffer.bin (the
//                      lift-to-C output, 0.00px-exact geometry), each PAIRED with
//                      a REAL tcw + UV (by tile-span class) borrowed from the
//                      probe so the quad samples real character pixels. Proves the
//                      transpiled GEOMETRY renders real character texels through
//                      the real renderer.
//
// Output: a .ta file. Then run:
//   node render_ta.mjs --ta <out.ta> --vram <vram.bin> --pvr <pvr.bin> \
//        --no-bg --out <out.png>
//
// The probe + the aligned VRAM/PVR live in ../../_ryu_capture/ :
//   probe_body_uv.json  (CHARQ capture, node 0x8C268340, vframe 216663)
//   vram.bin / pvr.bin  (the SYNC contemporaneous with that probe — its part
//                        tiles are present at the probe's tcw addresses)

import { readFileSync, writeFileSync } from 'node:fs';

const RYU = new URL('../../_ryu_capture/', import.meta.url);
const HERE = new URL('./', import.meta.url);

function f32toU16(f) {
    // top 16 bits of the f32 bit pattern (the TA UV16 encoding the parser reverses)
    const b = new ArrayBuffer(4); new Float32Array(b)[0] = f;
    return (new Uint32Array(b)[0] >>> 16) & 0xFFFF;
}

// ---- TA writer: one textured SPRITE per quad ----------------------------------
// The parser's sprite path (ta-parser.mjs:165-196) reads, per sprite:
//   Sprite PARAM (32B): pcw(paraType5,listType lt), isp, tsp, tcw, baseColor
//   Sprite VTX  (64B):  ctrl, Ax,Ay,Az, Bx,By,Bz, Cx,Cy,Cz, Dx,Dy(+pad),
//                       then @+0x34: AV,AU, BV,BU, CV,CU as u16 (f16 top half)
// A=TL, B=TR, C=BR, D=BL.  D's z/uv are derived by the sprite-plane solve.
class TAWriter {
    constructor() { this.chunks = []; }
    _w32(view, vals) {
        const ab = new ArrayBuffer(32); const dv = new DataView(ab);
        for (let i = 0; i < vals.length; i++) dv.setUint32(i * 4, vals[i] >>> 0, true);
        this.chunks.push(new Uint8Array(ab));
    }
    spriteParam(tcw, tsp, baseColor) {
        // pcw: paraType=5 (<<29), listType=0 opaque (<<24), obj_ctrl: texture=1 (bit3),
        //      uv16=1 (bit0) so vertex UVs are f16.  => low byte = 0x09 (tex|uv16)
        const pcw = (5 << 29) | (0 << 24) | 0x09;
        const isp = (4 << 29) | (1 << 27); // depthMode=4(GE? use parser default), cull off
        this._w32(null, [pcw, isp, tsp, tcw, baseColor, 0, 0, 0]);
    }
    spriteVtx(A, B, C, D, uv /* [AU,AV,BU,BV,CU,CV] */, z = 0.5) {
        const ab = new ArrayBuffer(64); const dv = new DataView(ab);
        dv.setUint32(0, (7 << 29) >>> 0, true); // vertex paraType=7
        // corners A,B,C at +4.., D x,y at +40,+44
        dv.setFloat32(4, A[0], true);  dv.setFloat32(8, A[1], true);  dv.setFloat32(12, z, true);
        dv.setFloat32(16, B[0], true); dv.setFloat32(20, B[1], true); dv.setFloat32(24, z, true);
        dv.setFloat32(28, C[0], true); dv.setFloat32(32, C[1], true); dv.setFloat32(36, z, true);
        dv.setFloat32(40, D[0], true); dv.setFloat32(44, D[1], true);
        // UVs as u16 (f16): @+0x34 AV,AU ; +0x38 BV,BU ; +0x3C CV,CU
        const [AU, AV, BU, BV, CU, CV] = uv;
        dv.setUint16(0x34, f32toU16(AV), true); dv.setUint16(0x36, f32toU16(AU), true);
        dv.setUint16(0x38, f32toU16(BV), true); dv.setUint16(0x3A, f32toU16(BU), true);
        dv.setUint16(0x3C, f32toU16(CV), true); dv.setUint16(0x3E, f32toU16(CU), true);
        this.chunks.push(new Uint8Array(ab));
    }
    endList() { this._w32(null, [0, 0, 0, 0, 0, 0, 0, 0]); }
    bytes() {
        let n = 0; for (const c of this.chunks) n += c.length;
        const out = new Uint8Array(n); let o = 0;
        for (const c of this.chunks) { out.set(c, o); o += c.length; }
        return out;
    }
}

// Derive the source tile (texU,texV) -> tsp from the on-screen span.
// CPS body scale ~ 0.8333 (53.33px span <- 64px tile). Round src to power-of-2.
// The probe part tiles are a fixed 32x32 PAL4 sheet (VRAM addresses are 0x200 =
// 512 bytes apart = exactly one 32x32 PAL4 tile). The probe's per-corner UVs
// (0.25 / 0.5 / 1.0) select the sub-rect within that 32x32 sheet. So ALWAYS decode
// 32x32: texU=texV=2 -> tsp texshift = (2<<3)|2 = 0x12.  This matches the CPU
// reference rasterizer (composite_uv.mjs, TW=TH=32) verbatim.
function tspForSpan(_spanW, _spanH) {
    const texU = 2, texV = 2; // 8<<2 = 32
    return (texU << 3) | texV;
}

function loadProbe(vram) {
    const d = JSON.parse(readFileSync(new URL('probe_body_uv.json', RYU)));
    return d.quads.map((q) => {
        const tcw = parseInt(q.tcw, 16);
        const addr = (tcw & 0x1FFFFF) << 3;
        let nz = 0;
        if (vram) for (let i = addr; i < addr + 512 && i < vram.length; i++) if (vram[i]) nz++;
        return {
            sel: q.sel, tcw,
            A: q.A, B: q.B, C: q.C, D: q.D,
            uv: q.uv, // [AU,AV,BU,BV,CU,CV]
            spanW: q.B[0] - q.A[0], spanH: q.C[1] - q.B[1],
            nz, // non-zero bytes in the 32x32 PAL4 tile (empty tiles = skipped for pairing)
        };
    });
}

// Parse the transpiled ta_buffer.bin into quads (param + 4 strip verts TL,TR,BL,BR).
function loadTranspiled() {
    const buf = readFileSync(new URL('ta_buffer.bin', HERE));
    const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
    const quads = []; let off = 0;
    while (off + 32 <= buf.length) {
        const pcw = dv.getUint32(off, true); const pt = (pcw >>> 29) & 7;
        if (pt === 4) {
            const tcw = dv.getUint32(off + 12, true); off += 32;
            const v = [];
            for (let k = 0; k < 4; k++) { v.push([dv.getFloat32(off + 4, true), dv.getFloat32(off + 8, true)]); off += 32; }
            // strip order TL,TR,BL,BR -> A=TL,B=TR,C=BR,D=BL
            quads.push({ sel: tcw & 0xFF, tcwStub: tcw, A: v[0], B: v[1], C: v[3], D: v[2],
                spanW: v[1][0] - v[0][0], spanH: v[2][1] - v[0][1] });
        } else { off += 32; }
    }
    return quads;
}

function main() {
    const mode = process.argv.includes('--transpiled') ? 'transpiled'
        : (process.argv.includes('--reference') ? 'reference'
            : (process.argv[process.argv.indexOf('--mode') + 1] || 'reference'));
    const outArg = process.argv[process.argv.indexOf('--out') + 1];
    const out = outArg && outArg !== '--out' ? outArg : `ta_${mode}.ta`;

    // Load the aligned VRAM so we can avoid pairing transpiled quads to EMPTY tiles
    // (a few of the probe's part tiles are blank in this SYNC).
    let vram = null;
    try { vram = new Uint8Array(readFileSync(new URL('vram.bin', RYU))); } catch {}

    const probe = loadProbe(vram);
    const W = new TAWriter();

    if (mode === 'reference') {
        for (const q of probe) {
            W.spriteParam(q.tcw, tspForSpan(q.spanW, q.spanH), 0xFFFFFFFF);
            W.spriteVtx(q.A, q.B, q.C, q.D, q.uv);
        }
        W.endList();
        console.log(`[reference] ${probe.length} probe quads (real corners + real tcw + real UV)`);
    } else {
        // Transpiled geometry: real corners from ta_buffer, paired to a real tcw+UV
        // by matching tile-span CLASS (so the quad samples a real, same-resolution
        // body part). Span classes in the probe: 16px(13.3x17.1), 32px(26.7x34.3),
        // 64px(53.3x68.6). Pick a probe part whose span best matches each transpiled
        // quad's span; reuse its tcw+UV+tsp.
        const tq = loadTranspiled();
        // Candidate pool = only NON-EMPTY probe tiles, richest first within a span class.
        const nonEmpty = probe.filter((p) => p.nz > 0);
        const used = new Set();
        const pick = (sw, sh) => {
            // rank by span-class match, then by texture richness (nz), preferring unused
            const ranked = nonEmpty.slice().sort((a, b) => {
                const da = Math.abs(a.spanW - sw) + Math.abs(a.spanH - sh);
                const db = Math.abs(b.spanW - sw) + Math.abs(b.spanH - sh);
                if (Math.abs(da - db) > 0.5) return da - db;
                const ua = used.has(a.tcw) ? 1 : 0, ub = used.has(b.tcw) ? 1 : 0;
                if (ua !== ub) return ua - ub;       // unused first
                return b.nz - a.nz;                  // richest tile first
            });
            const p = ranked[0]; used.add(p.tcw); return p;
        };
        for (const q of tq) {
            const p = pick(q.spanW, q.spanH);
            W.spriteParam(p.tcw, tspForSpan(p.spanW, p.spanH), 0xFFFFFFFF);
            // draw at the TRANSPILED corners, sample the REAL part's UV+texture
            W.spriteVtx(q.A, q.B, q.C, q.D, p.uv);
        }
        W.endList();
        console.log(`[transpiled] ${tq.length} transpiled quads (transpiled corners + paired NON-EMPTY real tcw/UV by span class)`);
    }

    const bytes = W.bytes();
    writeFileSync(out, bytes);
    console.log(`wrote ${out} (${bytes.length} bytes)`);
}

main();
