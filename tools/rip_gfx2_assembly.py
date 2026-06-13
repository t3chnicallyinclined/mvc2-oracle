#!/usr/bin/env python3
"""
rip_gfx2_assembly.py — CRACKED-structure offline assembly extractor (per character).

Replaces the old EXTRAS-based grouping (the "6 stacked poses / scramble") with the
GFX2 cell table indexed by sprite_id, per the 2026-06-08/09 cell-data RE:

  current-pose part list = GFX2[sprite_id & 0x7FFF]   (GFX2 = *(node+0x160))

  cell_rec = GFX2_base + *(u32)(GFX2_base + (sid & 0x7FFF)*4)
    first u16 of cell_rec = group/part COUNT
    then COUNT * 8-byte records:
       [dx s16 @+0] [dy s16 @+2] [FLAGS u16 @+4] [GFX-selector u16 @+6]
    The +4 field is the FLAGS word (NOT palette): X-mirror=0x4000, Y-mirror=0x8000
    (CONFIRMED 2026-06-10, bank03 loc_8c0344d4 lines 10477/10503/10568/10594). The
    texture selector is +6.

  part texture for a selector:
    gfx1 = *(node+0x15c)  (= GFX_DATA_00.BIN)
    blob = gfx1 + *(u32)(gfx1 + selector*4)
    w = blob[2]<<3, h = blob[3]<<3 ; texels at blob+4, LZSS-decoded (loc_8c0354c0),
    4bpp / PAL4.
    palette = PER-CHARACTER (Dat_Pal node+0x164) — NOT a per-record row.

GFX2 = the gfx2 segment (header slot +0x04 = GFX_DATA_01.BIN).
GFX1 = the gfx1 segment (header slot +0x00 = GFX_DATA_00.BIN).

Output (operator-local, ROM-derived, gitignored):
  <out>/PL{hex}_asm.json    { char, atlas, atlas_w, atlas_h, parts, assemblies, _note }
                              assemblies keyed by CELL INDEX == sprite_id (full table).
                              each rec = {dx, dy, part(=+6 selector), pal(row), flip:0}
  <out>/PL{hex}_parts.json  { <selector>: {x,y,w,h} }   (rect in the atlas)
  <out>/PL{hex}_parts.png   packed part rectangles (only selectors actually referenced)

Usage:
  python3 tools/rip_gfx2_assembly.py --gfx1 dasm_PLDAT/Output/PL00_DAT/PL00_DAT_GFX_DATA_00.BIN \
                                     --gfx2 dasm_PLDAT/Output/PL00_DAT/PL00_DAT_GFX_DATA_01.BIN \
                                     --pal  dasm_PLDAT/Output/PL00_DAT/PL00_DAT_PALETTE_DATA.BIN \
                                     --char PL00 --out web/test-atlas/chars
"""
import argparse, json, os, struct, bisect
from PIL import Image

TILE = 8
OPERAND_MASK = 0x07ff
MAGENTA = (0xFF, 0x00, 0xFF)   # MAPLECAST_PARTDUMP PPM transparent key (P6 has no alpha)


# ----- REAL part pixels from a live MAPLECAST_PARTDUMP capture ----------------
# The offline GFX1 LZSS decode (build_part_pixels) is a CONFIRMED DEAD END: the
# texture LZSS back-references the live 0x0CE60000 scratch residue, absent from the
# static GFX_DATA_00 file (see web/webgpu/pldat-codec.mjs "DECOMPRESSION ARCHITECTURE").
# The ONLY correct pixel source is the running emulator's decode buffer, captured by
# the MAPLECAST_PARTDUMP probe (core/network/maplecast_gamestate.cpp) as PPM previews
# keyed by the +6 GFX-selector, with the live per-part palette already baked in. This
# loader sources those PPMs so the emitter geometry (cumulative pen + selector->rect,
# both disasm-confirmed) is paired with REAL pixels. Returns { sel: (rgba, W, H) }.
def read_ppm(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:2] != b"P6":
        return None
    idx = 2
    toks = []
    while len(toks) < 3:
        while idx < len(data) and data[idx] in b" \t\n\r":
            idx += 1
        if idx < len(data) and data[idx:idx + 1] == b"#":
            while idx < len(data) and data[idx] not in b"\n":
                idx += 1
            continue
        st = idx
        while idx < len(data) and data[idx] not in b" \t\n\r":
            idx += 1
        toks.append(int(data[st:idx]))
    idx += 1
    w, h, _mx = toks
    return w, h, data[idx:idx + w * h * 3]


def _detwiddle_rgb(px, w, h):
    """The GFX1DUMP PPMs carry palette-correct RGB but in PVR-TWIDDLED storage order
    (partDecodeToPPM emits them un-detwiddled for these slots). Reorder via the same
    flycast PAL4 square-aware twop block-walk tile_to_indices uses. Magenta=transparent."""
    out = bytearray(w * h * 4)
    sq = min(w, h)
    si = 0
    for by0 in range(0, h, sq):
        for bx0 in range(0, w, sq):
            for y in range(0, sq, 4):
                for x in range(0, sq, 4):
                    blk = _twop(x, y, sq) >> 4
                    base = blk * 16
                    for i, (cx, cy) in enumerate(_PAL4_ORDER):
                        j = (si + base + i) * 3
                        if j + 2 >= len(px):
                            continue
                        r, g, b = px[j], px[j + 1], px[j + 2]
                        if (r, g, b) == MAGENTA:
                            continue
                        d = ((by0 + y + cy) * w + (bx0 + x + cx)) * 4
                        out[d:d + 4] = bytes((r, g, b, 255))
            si += sq * sq
    return bytes(out)


def load_real_parts(realdir, hexname, selectors):
    """Source clean part pixels from the GFX1DUMP. Prefers PL{HEX}_gfx1_NNNN.ppm (the
    selector-indexed clean DM00 dump, twiddled -> detwiddle here); falls back to the older
    PL{HEX}_part_NNN.ppm (linear). Both are MAPLECAST_GFX1DUMP/PARTDUMP output."""
    parts = {}
    miss = []
    for sel in selectors:
        g1 = os.path.join(realdir, f"{hexname}_gfx1_{sel:04d}.ppm")
        legacy = os.path.join(realdir, f"{hexname}_part_{sel:03d}.ppm")
        if os.path.exists(g1):
            got = read_ppm(g1)
            if got:
                w, h, px = got
                parts[sel] = (_detwiddle_rgb(px, w, h), w, h)
                continue
        if os.path.exists(legacy):
            got = read_ppm(legacy)
            if got:
                w, h, px = got
                rgba = bytearray(w * h * 4)
                for i in range(w * h):
                    r, g, b = px[i * 3], px[i * 3 + 1], px[i * 3 + 2]
                    if (r, g, b) == MAGENTA:
                        continue
                    rgba[i * 4:i * 4 + 4] = bytes((r, g, b, 255))
                parts[sel] = (bytes(rgba), w, h)
                continue
        miss.append(sel)
    return parts, miss


# ----- GFX2 cell table (the cracked assembly structure) ---------------------
def read_cells(gfx2):
    """Return { cell_index: [ {dx,dy,pal_raw,sel}, ... ] } for every valid cell."""
    n = struct.unpack_from("<I", gfx2, 0)[0] >> 2
    tbl = [struct.unpack_from("<I", gfx2, i * 4)[0] for i in range(n)]
    cells = {}
    for idx in range(n):
        off = tbl[idx]
        if off + 2 > len(gfx2):
            continue
        cnt = struct.unpack_from("<H", gfx2, off)[0]
        if cnt == 0 or cnt > 64 or off + 2 + cnt * 8 > len(gfx2):
            continue
        recs = []
        p = off + 2
        # CUMULATIVE RUNNING PEN (bank03.asm loc_8c0344d4 / loc_8c0345c4):
        # the geometry emitter does NOT place each record absolutely from the
        # object origin. It keeps a running pen (r10 = X acc, @(0x14,r15) = Y acc)
        # initialized to the cell hotspot (node+0x134/0x136, ~0 for the body) and
        # advances it by each record's (dx,dy) BEFORE emitting that record's part:
        #     X_acc += dx ;  Y_acc += dy   (facing-neutral; global flip is applied
        #     downstream in the emitter via owner.facing).  Each part is then drawn
        #     at  screen_xy(node+0xE0/E4) + (X_acc,Y_acc)*scale.
        # CONFIRMED 2026-06-10 (SH4 expert, marvelous2 bank03 loc_8c0344d4 +
        # bank12 loc_8c1244b0): the 8-byte record is
        #     [dx s16 @+0] [dy s16 @+2] [FLAGS u16 @+4] [sel u16 @+6]
        # The +4 field we historically read as "pal" is the FLAGS word, NOT palette.
        #   X-mirror = FLAGS & 0x4000  (bank03:10477/10568)  — XORs with facing
        #   Y-mirror = FLAGS & 0x8000  (bank03:10503/10594)  — does NOT XOR with facing
        # "Rotation" is not a separate field — it's these mirror bits re-expressed as
        # UV-corner flips in bank12; flipX/flipY at the part level reproduce orientation.
        # Palette is PER-CHARACTER (Dat_Pal node+0x164), NOT per-record — there is no
        # per-record palette-row. (The old (pal>>4)&7 / 0x10 / 0x20 reads were WRONG.)
        px = py = 0
        for _ in range(cnt):
            dx, dy, flags, sel = struct.unpack_from("<hhHH", gfx2, p)
            p += 8
            # DISASM (bank03:10454/10470, MARVELOUS2-GFX-NOTES §3a): X-acc += dx (facing-
            # neutral), Y-acc -= dy. (The old code did py += dy — inverted vertical layout.)
            px += dx
            py -= dy
            recs.append({"dx": px, "dy": py, "ddx": dx, "ddy": dy,
                         "flags": flags, "sel": sel})
        cells[idx] = recs
    return cells, n


# ----- GFX1 part LZSS decode (shared scratch window, loc_8c0354c0) ----------
def decode_into_capped(stream, out, cap):
    n = len(stream)

    def rd(p):
        if p + 1 < n:
            return stream[p] | (stream[p + 1] << 8)
        return stream[p] if p < n else 0

    start = len(out)
    pos = 0
    mask = 0
    flag = 0
    while pos + 1 < n and (len(out) - start) < cap:
        if mask == 0:
            flag = rd(pos)
            pos += 2
            mask = 0x8000
            continue
        bit = flag & mask
        mask >>= 1
        if bit == 0:
            out.append(stream[pos])
            out.append(stream[pos + 1])
            pos += 2
        else:
            tok = rd(pos)
            pos += 2
            count = tok >> 11
            operand = tok & OPERAND_MASK
            if count == 0:
                count = rd(pos)
                pos += 2
            if operand == 0:
                for _ in range(count):
                    if (len(out) - start) >= cap:
                        break
                    out.append(0)
                    out.append(0)
            else:
                src = len(out) - (operand << 1)
                for _ in range(count):
                    if (len(out) - start) >= cap:
                        break
                    if 0 <= src and src + 1 < len(out):
                        out.append(out[src])
                        out.append(out[src + 1])
                    else:
                        out.append(0)
                        out.append(0)
                    src += 2
    while (len(out) - start) < cap:
        out.append(0)


def build_part_pixels(gfx1, selectors):
    """Decode every referenced selector into the shared scratch (file order), then
    de-twiddle each into a 4bpp index image. Returns { sel: (idx_bytes, w, h, palrow_hint) }."""
    n_parts = struct.unpack_from("<I", gfx1, 0)[0] >> 2
    offs = [struct.unpack_from("<I", gfx1, i * 4)[0] for i in range(n_parts)]
    srt = sorted(set(offs) | {len(gfx1)})

    def blob_end(off):
        i = bisect.bisect_right(srt, off)
        return srt[i] if i < len(srt) else len(gfx1)

    # Decode ALL parts in file order into one growing buffer so back-refs resolve
    # against earlier parts' decoded output (the accumulated scratch window).
    order = sorted(range(n_parts), key=lambda i: offs[i])
    buf = bytearray()
    starts = {}
    dims = {}
    for idx in order:
        o = offs[idx]
        if o + 4 > len(gfx1):
            starts[idx] = len(buf)
            continue
        sw, sh = gfx1[o + 2], gfx1[o + 3]
        lw, lh = gfx1[o], gfx1[o + 1]
        cap = (sw * TILE * sh * TILE) >> 1
        if cap <= 0 or cap > (1024 * 1024) // 2:
            starts[idx] = len(buf)
            dims[idx] = (sw, sh, lw, lh)
            continue
        starts[idx] = len(buf)
        dims[idx] = (sw, sh, lw, lh)
        decode_into_capped(gfx1[o + 4:blob_end(o)], buf, cap)

    parts = {}
    for sel in selectors:
        if sel >= n_parts or sel not in dims:
            continue
        sw, sh, lw, lh = dims[sel]
        W, H = sw * TILE, sh * TILE
        if W <= 0 or H <= 0 or W > 1024 or H > 1024:
            continue
        need = (W * H) >> 1
        st = starts[sel]
        texels = bytes(buf[st:st + need])
        if len(texels) < need:
            texels = texels + bytes(need - len(texels))
        idxbuf = tile_to_indices(texels, sw, sh)
        cw = (lw * TILE) if 0 < lw <= sw else W
        ch = (lh * TILE) if 0 < lh <= sh else H
        parts[sel] = (idxbuf, W, H, cw, ch)
    return parts


# ----- PVR PAL4 TWIDDLE (flycast texconv.cpp port; proven on PL00 sel 1/34) -----
# CONFIRMED 2026-06-09: PAL4 is ALWAYS twiddled (texconv.cpp format table: linear PAL4
# = nullptr). The old row-major `tile_to_indices` produced stripe NOISE. Port of
# twiddle_slow (texconv.cpp:37) + twop (169) + ConvertTwiddlePal4 (289). Non-square
# textures are a run of min(w,h) squares, each twiddled internally (texture_TW loop).
# Validated against _ryu_capture/decode_flycast.py / HC_0001_twiddle.png (clean torso).
_TW_X = [0] * 1024
_TW_Y = [[0] * 1024 for _ in range(11)]
def _init_twiddle():
    def tw(x, y, x_sz, y_sz):
        rv = 0; sh = 0; x_sz >>= 1; y_sz >>= 1
        while x_sz or y_sz:
            if y_sz: rv |= (y & 1) << sh; y_sz >>= 1; y >>= 1; sh += 1
            if x_sz: rv |= (x & 1) << sh; x_sz >>= 1; x >>= 1; sh += 1
        return rv
    for s in range(11):
        ysz = 1 << s
        for i in range(1024):
            _TW_Y[s][i] = tw(0, i, ysz, 1024)
        if s == 0:
            for i in range(1024):
                _TW_X[i] = tw(i, 0, 1024, 1)  # depth gated by y; only y bits matter for X table base
_init_twiddle()
# detwiddle[0][bcy][x] (x bits, y-size gated) — recompute properly per call via tw
def _twiddle_slow(x, y, x_sz, y_sz):
    rv = 0; sh = 0; x_sz >>= 1; y_sz >>= 1
    while x_sz or y_sz:
        if y_sz: rv |= (y & 1) << sh; y_sz >>= 1; y >>= 1; sh += 1
        if x_sz: rv |= (x & 1) << sh; x_sz >>= 1; x >>= 1; sh += 1
    return rv
def _twop(x, y, sq):                       # square block, sq = side (pow2)
    return _twiddle_slow(x, 0, sq, sq) + _twiddle_slow(0, y, sq, sq)
_PAL4_ORDER = [(0,0),(0,1),(1,0),(1,1),(0,2),(0,3),(1,2),(1,3),
               (2,0),(2,1),(3,0),(3,1),(2,2),(2,3),(3,2),(3,3)]
def tile_to_indices(texels, sw, sh):
    """4bpp PAL4 TWIDDLED texels -> linear index buffer (W*H). sw/sh = tile dims (×8)."""
    W = sw * TILE; H = sh * TILE
    idx = bytearray(W * H)
    sq = min(W, H)
    pos = 0
    for by0 in range(0, H, sq):
        for bx0 in range(0, W, sq):
            sub = texels[pos:pos + (sq * sq >> 1)]; pos += (sq * sq >> 1)
            for y in range(0, sq, 4):
                for x in range(0, sq, 4):
                    blk = _twop(x, y, sq) >> 4   # block number (16 px/block)
                    base = blk * 8
                    for i, (cx, cy) in enumerate(_PAL4_ORDER):
                        b = sub[base + (i >> 1)] if base + (i >> 1) < len(sub) else 0
                        nib = (b & 0xF) if (i & 1) == 0 else ((b >> 4) & 0xF)
                        idx[(by0 + y + cy) * W + (bx0 + x + cx)] = nib
    return idx


# ----- palette --------------------------------------------------------------
def palette_rgba(pal, bank):
    out = []
    base = bank * 32
    for i in range(16):
        if base + i * 2 + 1 >= len(pal):
            out.append((0, 0, 0, 0))
            continue
        v = pal[base + i * 2] | (pal[base + i * 2 + 1] << 8)
        a = (v >> 12) & 0xf
        r = (v >> 8) & 0xf
        g = (v >> 4) & 0xf
        b = v & 0xf
        out.append((0, 0, 0, 0) if i == 0 else (r * 17, g * 17, b * 17, (a * 17) if a else 255))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gfx1", required=True)
    ap.add_argument("--gfx2", required=True)
    ap.add_argument("--pal", required=True)
    ap.add_argument("--char", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--palbank", type=int, default=0, help="palette bank for the atlas PNG (def 0 = PL00 body bank; was 1)")
    ap.add_argument("--realparts", default=None,
                    help="dir of MAPLECAST_PARTDUMP PPMs (PLxx_part_NNN.ppm, keyed by +6 selector). "
                         "When set, part PIXELS come from the live emulator decode (the ONLY correct "
                         "source) instead of the dead offline LZSS. Geometry/selectors are unchanged.")
    args = ap.parse_args()

    gfx1 = open(args.gfx1, "rb").read()
    gfx2 = open(args.gfx2, "rb").read()
    pal = open(args.pal, "rb").read()

    hexname = args.char.upper()
    cells, ncells = read_cells(gfx2)
    selectors = sorted({r["sel"] for recs in cells.values() for r in recs})

    ATLAS_W = 1024
    rects = {}

    if args.realparts:
        # REAL pixels from the live decode (correct). Pack RGBA PPMs by selector.
        real, miss = load_real_parts(args.realparts, hexname, selectors)
        print(f"realparts: {len(real)}/{len(selectors)} selectors resolved from "
              f"{args.realparts} ; missing {len(miss)}" + (f" e.g. {miss[:12]}" if miss else ""))
        items = sorted(real.items(), key=lambda kv: -kv[1][2])  # tallest first
        x = y = rowh = 0
        placed = []
        for sel, (rgba, W, H) in items:
            if x + W > ATLAS_W:
                x = 0
                y += rowh
                rowh = 0
            rects[sel] = {"x": x, "y": y, "w": W, "h": H}
            placed.append((sel, rgba, W, H, x, y))
            x += W + 1
            rowh = max(rowh, H + 1)
        atlas_h = y + rowh
        atlas = Image.new("RGBA", (ATLAS_W, max(atlas_h, 1)), (0, 0, 0, 0))
        for sel, rgba, W, H, ax, ay in placed:
            atlas.paste(Image.frombytes("RGBA", (W, H), rgba), (ax, ay))
    else:
        # OFFLINE LZSS decode — CONFIRMED DEAD (scratch-residue back-refs). Kept for the
        # GEOMETRY-only regen (assemblies/selectors are correct); pixels will be noise.
        parts_px = build_part_pixels(gfx1, selectors)
        palrgba = palette_rgba(pal, args.palbank)
        items = sorted(parts_px.items(), key=lambda kv: -kv[1][2])  # tallest first
        x = y = rowh = 0
        placed = []
        for sel, (idxbuf, W, H, cw, ch) in items:
            if x + cw > ATLAS_W:
                x = 0
                y += rowh
                rowh = 0
            rects[sel] = {"x": x, "y": y, "w": cw, "h": ch}
            placed.append((sel, idxbuf, W, H, cw, ch, x, y))
            x += cw + 1
            rowh = max(rowh, ch + 1)
        atlas_h = y + rowh
        atlas = Image.new("RGBA", (ATLAS_W, max(atlas_h, 1)), (0, 0, 0, 0))
        apx = atlas.load()
        for sel, idxbuf, W, H, cw, ch, ax, ay in placed:
            for yy in range(ch):
                row = yy * W
                for xx in range(cw):
                    pi = idxbuf[row + xx]
                    if pi == 0:
                        continue
                    apx[ax + xx, ay + yy] = palrgba[pi]

    os.makedirs(args.out, exist_ok=True)
    png_path = os.path.join(args.out, f"{hexname}_parts.png")
    atlas.save(png_path)

    # Assembly table keyed by cell index == sprite_id. pal row = (pal_raw & 0x3ff)>>4.
    assemblies = {}
    for idx, recs in cells.items():
        out_recs = []
        for r in recs:
            if r["sel"] not in rects:
                continue
            out_recs.append({
                "dx": r["dx"], "dy": r["dy"],          # CUMULATIVE pen (absolute in cell space)
                "part": r["sel"],
                # CONFIRMED 2026-06-10 (bank03 loc_8c0344d4): +4 is the FLAGS word.
                #   X-mirror = FLAGS & 0x4000 (XORs with facing in the emitter)
                #   Y-mirror = FLAGS & 0x8000 (does NOT XOR with facing)
                # Palette is per-CHARACTER (Dat_Pal node+0x164), not per-record — dropped.
                "flip":  1 if (r["flags"] & 0x4000) else 0,
                "flipy": 1 if (r["flags"] & 0x8000) else 0,
            })
        if out_recs:
            assemblies[str(idx)] = out_recs

    parts_json = {str(sel): rect for sel, rect in rects.items()}
    asm_json = {
        "char": hexname,
        "atlas": f"{hexname}_parts.png",
        "atlas_w": ATLAS_W, "atlas_h": max(atlas_h, 1),
        "screenW": 640, "screenH": 480,
        "parts": parts_json,
        "assemblies": assemblies,
        "_note": "CRACKED GFX2 cell table: assemblies keyed by cell-index==sprite_id; "
                 "rec part=+6 selector (GFX1 offset-table idx); +4 is the FLAGS word: "
                 "flip=(flags & 0x4000) X-mirror (XORs facing), flipy=(flags & 0x8000) "
                 "Y-mirror (no facing XOR). Palette is per-CHARACTER (Dat_Pal node+0x164), "
                 "NOT per-record. dx/dy "
                 "are CUMULATIVE (running pen): emitter loc_8c0344d4 advances X-acc += dx, "
                 "Y-acc -= dy per record and draws at screen_xy+(pen)*scale; JSON stores the "
                 "accumulated absolute pen. Part pixels = PAL4 TWIDDLED (flycast texconv "
                 "port, tile_to_indices). rip_gfx2_assembly.py (fixes 2026-06-09).",
    }
    with open(os.path.join(args.out, f"{hexname}_asm.json"), "w") as f:
        json.dump(asm_json, f)
    with open(os.path.join(args.out, f"{hexname}_parts.json"), "w") as f:
        json.dump({"parts": parts_json}, f)

    print(f"cells: {ncells}  with-parts: {len(assemblies)}")
    print(f"selectors referenced: {len(selectors)}  packed: {len(rects)}")
    print(f"atlas: {ATLAS_W}x{max(atlas_h,1)} -> {png_path}")
    import collections
    cc = collections.Counter(len(v) for v in assemblies.values())
    print("assembly record-count dist:", dict(sorted(cc.items())))


if __name__ == "__main__":
    main()
