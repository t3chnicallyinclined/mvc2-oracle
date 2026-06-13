#!/usr/bin/env python3
"""
rip_stage.py — decode an MVC2 stage (STGxxPOL.BIN + STGxxTEX.BIN) into a
client-loadable geometry JSON + texture PNGs, by porting the ModNao
(github.com/rob2d/modnao) NaomiLib / libspr "NLOBJPUT" decoder.

This is the offline rip step for RENDER-MASTER-PLAN-V2 §2.2 "Stage". MVC2 stage
data is a pre-relocated Sega NinjaLibrary object tree loaded at base 0x0cea0000.
We decode it OFFLINE (no SH4) and emit geometry projected exactly as the disc
art is, which is why it feeds PVR2Renderer (which consumes ta_parse-shape output)
as the OP (background) layer.

PORTED FROM MODNAO (verbatim logic, cited):
  - scanForModelPointers.ts  -> header: modelRamOffset = u32@0 & 0xffffff00;
                                 modelTablePtr = u32@0 - ramOff; count = u32@4
  - scanTextureHeaderData.ts  -> texture list: u32@8 (pvrStart) .. u32@0x10 (pvrEnd),
                                 16-byte recs {u16 w, u16 h, u8 fmt, u8 type, ...,
                                 u32 baseLocation@+8}; ramOffset = first baseLocation
  - scanModel.ts              -> MODEL_HEADER 0x18, then meshes (MESH 0x50) each with
                                 polygonDataLength@+0x4c; within each mesh, polygons
                                 (POLYGON_HEADER 0x08) {vertexGroupType@0, vertexCount@4};
                                 vertices VERTEX_A 0x20 (direct) or VERTEX_B 0x08 (reference)
  - NLPropConversionDefs.ts   -> mesh fields: textureSize@+8, uvFlip@+0xa,
                                 textureColorFormat@+0xf, textureNumber@+0x20,
                                 vertexColorMode@+0x24 (-3 => colored verts),
                                 alpha@+0x2c; vertex: pos@+0, normals@+0xc,
                                 colors@+0x10 (BGRA u8), uv@+0x18
  - getVertexAddressingMode.ts -> reference vert if (u32@+0 >> 16) in [0x5ff0,0x5fff]
  - getPolyTypeFlags.ts       -> cullingType = bit0 (1=back); triple = bit3
  - loadTextureFileWorker.ts  -> realLocation = baseLocation - ramOffset; per-texel
                                 morton (encodeZMortonPosition) twiddle; fmt decode
  - color-conversions/*.ts    -> ARGB1555 / RGB565 / ARGB4444 -> RGBA8888

OUTPUT (gitignored atlas/stages/):
  STGxx.json  — { stageId, ramOffset, textures:[{index,w,h,fmt,file}],
                  meshes:[{texIndex, hasColor, alpha, blend, tris:[{pos,uv,col}...] }] }
  STGxx_tNN.png — decoded RGBA texture NN

The JSON is consumed by web/webgpu/stage-client.mjs which converts it to the
PVR2Renderer parsed-object shape (28B VBL strip + PolyParam) — see that file.

Usage:
  python3 tools/rip_stage.py 00            # rip one stage (hex id)
  python3 tools/rip_stage.py all           # rip all 17
"""
import os, sys, json, struct

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DEVDIR = os.path.join(REPO, "MVC2 Dev Files")
OUTDIR = os.path.join(REPO, "atlas", "stages")
# Mirror copy served to web/stage-test.html (web root is web/). Same gitignored
# disc-derived data, just reachable by the static server.
WEBOUT = os.path.join(REPO, "web", "test-atlas", "stages")

# ---- StructSizes.ts ----
MODEL_HEADER = 0x18
MESH = 0x50
POLYGON_HEADER = 0x08
VERTEX_A = 0x20
VERTEX_B = 0x08

# ---- StructOffsets.ts (Mesh / Vertex) ----
M_BASE_PARAMS = 0x00
M_TEX_INSTR = 0x04
M_TEX_SIZE = 0x08
M_UV_FLIP = 0x0a
M_TEX_FMT = 0x0f
M_POSITION = 0x10
M_TEX_NUM = 0x20
M_VCOLOR_MODE = 0x24
M_ALPHA = 0x2c
M_VDATA_LEN = 0x4c
V_UV = 0x18
V_COLORS = 0x10


def u32(b, o): return struct.unpack_from("<I", b, o)[0]
def u16(b, o): return struct.unpack_from("<H", b, o)[0]
def u8(b, o):  return b[o]
def f32(b, o): return struct.unpack_from("<f", b, o)[0]


# ---- encodeZMortonPosition.ts (Z-order / twiddle) ----
def morton(x, y):
    x &= 0xffff; y &= 0xffff
    x = (x | (x << 8)) & 0x00ff00ff
    y = (y | (y << 8)) & 0x00ff00ff
    x = (x | (x << 4)) & 0x0f0f0f0f
    y = (y | (y << 4)) & 0x0f0f0f0f
    x = (x | (x << 2)) & 0x33333333
    y = (y | (y << 2)) & 0x33333333
    x = (x | (x << 1)) & 0x55555555
    y = (y | (y << 1)) & 0x55555555
    return x | (y << 1)


# ---- color-conversions/*.ts ----
def argb1555(c):
    a = ((c >> 15) & 1) * 255
    r = ((c >> 10) & 0x1f) * 8
    g = ((c >> 5) & 0x1f) * 8
    b = (c & 0x1f) * 8
    return (r, g, b, a)

def rgb565(c):
    r = (c >> 11) & 0x1f; g = (c >> 5) & 0x3f; b = c & 0x1f
    r = (r << 3) | (r >> 2); g = (g << 2) | (g >> 4); b = (b << 3) | (b >> 2)
    return (r, g, b, 255)

def argb4444(c):
    a = ((c >> 12) & 0xf) * 0x11
    r = ((c >> 8) & 0xf) * 0x11
    g = ((c >> 4) & 0xf) * 0x11
    b = (c & 0xf) * 0x11
    return (r, g, b, a)

FMT_CONV = {0: argb1555, 1: rgb565, 2: argb4444}
FMT_NAME = {0: "ARGB1555", 1: "RGB565", 2: "ARGB4444"}


def get_texture_size(value):
    base_w = (value % 64) // 8
    base_h = value % 8
    return (1 << (3 + base_w), 1 << (3 + base_h))


def scan_texture_headers(pol, ram_off):
    """Port of scanTextureHeaderData.ts. Returns list of texture defs."""
    pvr_start = u32(pol, 0x08) - ram_off
    pvr_end = u32(pol, 0x10) - ram_off
    texs = []
    ramoffset = None
    a = pvr_start
    while a < pvr_end:
        w = u16(pol, a); h = u16(pol, a + 2)
        fmt = u8(pol, a + 4); typ = u8(pol, a + 5)
        loc = u32(pol, a + 8)
        if ramoffset is None:
            ramoffset = loc
        if w > 0:
            texs.append({"w": w, "h": h, "fmt": fmt, "type": typ,
                         "baseLocation": loc, "ramOffset": ramoffset})
        a += 16
    return texs


def decode_texture(tex_file, t):
    """Port of loadTextureFileWorker.createTexturePixelBuffers (type!=VQ branch).
    Returns (w, h, bytes RGBA8888)."""
    w, h, fmt = t["w"], t["h"], t["fmt"]
    conv = FMT_CONV.get(fmt)
    if conv is None:
        return w, h, None
    real_loc = t["baseLocation"] - t["ramOffset"]
    out = bytearray(w * h * 4)
    for y in range(h):
        row = w * y
        for x in range(w):
            off_drawn = morton(x, y)
            ro = real_loc + off_drawn * 2
            if ro + 2 > len(tex_file):
                continue
            color = struct.unpack_from("<H", tex_file, ro)[0]
            r, g, b, a = conv(color)
            ci = (row + x) * 4
            out[ci] = r; out[ci + 1] = g; out[ci + 2] = b; out[ci + 3] = a
    return w, h, bytes(out)


def vertex_addressing_mode(value):
    sv = (value & 0xffff0000) >> 16
    return "reference" if 0x5ff0 <= sv <= 0x5fff else "direct"


def scan_model(pol, address):
    """Port of scanModel.ts. Returns list of meshes; each mesh has triangles
    (already strip-expanded with winding from ModNao) carrying pos/uv/col."""
    meshes = []
    detected_end = False
    sa = address + MODEL_HEADER
    n = len(pol)
    while sa < n and not detected_end:
        if u32(pol, sa) == 0:
            break
        m_base = sa
        base_params = u32(pol, m_base + M_BASE_PARAMS)
        tex_instr = u32(pol, m_base + M_TEX_INSTR)
        tex_size_val = u8(pol, m_base + M_TEX_SIZE)
        uv_flip = u8(pol, m_base + M_UV_FLIP)
        tex_fmt = u8(pol, m_base + M_TEX_FMT)
        tex_num = u8(pol, m_base + M_TEX_NUM)
        vcolor_mode = struct.unpack_from("<i", pol, m_base + M_VCOLOR_MODE)[0]
        has_colored = (vcolor_mode == -3)
        alpha = f32(pol, m_base + M_ALPHA)
        poly_data_len = u32(pol, m_base + M_VDATA_LEN)

        sa += MESH
        mesh_end = sa + poly_data_len
        tris = []

        while sa < mesh_end and sa + VERTEX_B < n and not detected_end:
            poly_addr = sa
            vgroup_val = u32(pol, poly_addr + 0x00)
            is_triple = ((vgroup_val >> 3) & 1) == 1
            vgroup_mode = "triple" if is_triple else "regular"
            culling_back = (vgroup_val & 1) == 1
            vcount = u32(pol, poly_addr + 0x04)
            actual_vc = vcount * (3 if is_triple else 1)

            sa = poly_addr + POLYGON_HEADER

            verts = []
            detected_mesh_end = False
            for i in range(actual_vc):
                if u32(pol, sa) == 0:
                    detected_end = True; detected_mesh_end = True
                    sa += 8
                    break
                if detected_mesh_end:
                    break
                if sa + VERTEX_B >= n:
                    break
                cmv = u32(pol, sa)
                amode = vertex_addressing_mode(cmv)
                content_addr = sa
                if amode == "reference":
                    voff = struct.unpack_from("<i", pol, sa + 0x04)[0]
                    content_addr = sa + voff + POLYGON_HEADER
                # position @ content+0x00
                if content_addr + 0x20 <= n:
                    px = f32(pol, content_addr + 0x00)
                    py = f32(pol, content_addr + 0x04)
                    pz = f32(pol, content_addr + 0x08)
                    uu = f32(pol, content_addr + V_UV)
                    vv = f32(pol, content_addr + V_UV + 4)
                    if has_colored:
                        b_ = u8(pol, content_addr + V_COLORS + 0)
                        g_ = u8(pol, content_addr + V_COLORS + 1)
                        r_ = u8(pol, content_addr + V_COLORS + 2)
                        a_ = u8(pol, content_addr + V_COLORS + 3)
                        col = [r_, g_, b_, a_]
                    else:
                        col = [255, 255, 255, 255]
                    verts.append({"pos": [px, py, pz], "uv": [uu, vv], "col": col})
                else:
                    verts.append({"pos": [0, 0, 0], "uv": [0, 0],
                                  "col": [255, 255, 255, 255]})
                sa += VERTEX_A if amode == "direct" else VERTEX_B
                if sa >= mesh_end:
                    detected_mesh_end = True

            # ---- strip -> triangle indices (scanModel.ts winding) ----
            indices = []
            if vgroup_mode == "regular":
                for i in range(max(0, len(verts) - 2)):
                    if i % 2 == 0:
                        if not culling_back:
                            indices += [i + 1, i, i + 2]
                        else:
                            indices += [i, i + 1, i + 2]
                    else:
                        if not culling_back:
                            indices += [i, i + 1, i + 2]
                        else:
                            indices += [i + 1, i, i + 2]
            else:  # triple
                for i in range(2, len(verts), 3):
                    if not culling_back:
                        indices += [i - 1, i - 2, i]
                    else:
                        indices += [i - 2, i - 1, i]

            for k in range(0, len(indices) - 2, 3):
                a_, b_, c_ = indices[k], indices[k + 1], indices[k + 2]
                if a_ < len(verts) and b_ < len(verts) and c_ < len(verts):
                    tris.append([verts[a_], verts[b_], verts[c_]])

        # blend deduction: textureInstructions/baseParams (isOpaque) per NLPropConversionDefs
        is_opaque = False
        if tex_instr in (0x83000000, 0x83400000):
            is_opaque = base_params in (
                0x8000001c, 0x8000002c, 0x8000003c, 0x8000009c, 0x800000ac, 0x800000bc,
                0x8000001d, 0x8000002d, 0x8000003d, 0x8000009d, 0x800000ad, 0x800000bd)
        meshes.append({
            "texIndex": tex_num,
            "texSizeVal": tex_size_val,
            "uvFlip": uv_flip,
            "hasColor": has_colored,
            "alpha": alpha,
            "isOpaque": is_opaque,
            "baseParams": base_params,
            "texInstr": tex_instr,
            "tris": tris,
        })
    return meshes


def rip_stage(stage_id_hex):
    sid = stage_id_hex.upper()
    pol_path = os.path.join(DEVDIR, f"STG{sid}POL.BIN")
    tex_path = os.path.join(DEVDIR, f"STG{sid}TEX.BIN")
    if not os.path.exists(pol_path):
        print(f"  SKIP STG{sid}: no POL file"); return
    pol = open(pol_path, "rb").read()
    texf = open(tex_path, "rb").read()

    ram_off = u32(pol, 0x00) & 0xffffff00
    model_table = u32(pol, 0x00) - ram_off
    model_count = u32(pol, 0x04)

    textures = scan_texture_headers(pol, ram_off)

    from PIL import Image
    os.makedirs(OUTDIR, exist_ok=True)
    tex_meta = []
    for ti, t in enumerate(textures):
        w, h, rgba = decode_texture(texf, t)
        fn = f"STG{sid}_t{ti:02d}.png"
        if rgba is not None:
            Image.frombytes("RGBA", (w, h), rgba).save(os.path.join(OUTDIR, fn))
        tex_meta.append({"index": ti, "w": w, "h": h, "fmt": t["fmt"],
                         "fmtName": FMT_NAME.get(t["fmt"], "?"),
                         "baseLocation": t["baseLocation"], "file": fn})

    all_meshes = []
    for mi in range(model_count):
        ram_addr = u32(pol, model_table + 4 * mi)
        addr = ram_addr - ram_off
        if addr < 0 or addr >= len(pol):
            continue
        meshes = scan_model(pol, addr)
        for m in meshes:
            m["model"] = mi
        all_meshes.extend(meshes)

    out = {
        "stageId": int(sid, 16),
        "ramOffset": ram_off,
        "modelCount": model_count,
        "textures": tex_meta,
        "meshes": all_meshes,
    }
    jpath = os.path.join(OUTDIR, f"STG{sid}.json")
    with open(jpath, "w") as f:
        json.dump(out, f)
    # mirror JSON + PNGs into the web-served dir
    os.makedirs(WEBOUT, exist_ok=True)
    with open(os.path.join(WEBOUT, f"STG{sid}.json"), "w") as f:
        json.dump(out, f)
    import shutil
    for t in tex_meta:
        src = os.path.join(OUTDIR, t["file"])
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(WEBOUT, t["file"]))
    ntris = sum(len(m["tris"]) for m in all_meshes)
    print(f"  STG{sid}: {model_count} models, {len(all_meshes)} meshes, "
          f"{ntris} tris, {len(tex_meta)} textures -> {os.path.basename(jpath)}")


def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    arg = sys.argv[1].lower()
    if arg == "all":
        ids = [f"{i:02X}" for i in range(0x11)]
    else:
        ids = [arg.upper().zfill(2)]
    print(f"Ripping to {OUTDIR}")
    for sid in ids:
        rip_stage(sid)


if __name__ == "__main__":
    main()
