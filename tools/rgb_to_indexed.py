#!/usr/bin/env python3
"""
rgb_to_indexed.py — convert a baked RGB character atlas (atlas/chars/PLxx.png) into
an INDEXED atlas + a multi-bank palette LUT, so the web renderer can do EXACT palette
recoloring (hit-flash hurt-bank swap + community skins) instead of the additive-tint
approximation in sprite-gpu.mjs.

WHY MULTI-BANK (the thing the naive "16-color LUT" plan missed)
---------------------------------------------------------------
MVC2 sprites are 4bpp/16-color paletted, but a single character ATLAS is baked from
MANY parts, and different parts use different 16-color palette ROWS out of the char's
PALETTE_DATA (1824 B = 57 banks of 16 ARGB4444 colors for Ryu/PL00). Empirically PL00's
atlas has 28 unique opaque colors and needs 3 banks (0,1,3) to cover them all:
  bank 0  = the BODY (gi/skin/hair) — 87% of pixels, the ONLY bank hit-flash/skins swap
  bank 1  = hadouken/fireball energy (cyan)   bank 3 = more fireball (blue/teal)
Some colors (white 0xFFFFFF, dark 0x111111) appear in MULTIPLE banks, so a pure
per-pixel RGB->index map is AMBIGUOUS. We resolve it with a deterministic PREFERENCE
order: bank 0 wins; a color is only assigned to bank 1/3 when it is NOT in bank 0.

OUTPUT (per char):
  <out>/PLxx_idx.png   — indexed atlas, RGBA8 where the data is PACKED, not visual:
                          R = bankSel (0,1,2,...; 255 = transparent)
                          G = palette index 0..15
                          B = 0, A = 255  (A=0 only for fully-transparent pixels)
                          This is loaded as a data texture (NEAREST) by the LUT shader.
  <out>/PLxx_lut.json  — { "banks": [[ [r,g,b,a]*16 ], ... ], "bodyBank": 0,
                          "bankList": [0,1,3], "name": "Ryu" }
                          banks[k] is the 16-color RGBA (0-255) LUT for bankSel k.
                          bodyBank = the index INTO bankList that the live PVR body
                          palette / hit-flash / skin overrides apply to.

The shader: sample _idx.png -> (bankSel, index) -> LUT[bankSel][index] -> RGBA.
Identity holds because every atlas pixel maps to an EXACT palette color (we REPORT the
non-exact %, which must be ~0). Swapping LUT bank `bodyBank` recolors only the body.

USAGE
  # one char (verify-first):
  python3 tools/rgb_to_indexed.py --png atlas/chars/PL00.png \
      --pal dasm_PLDAT/Output/paletteData/PL00_DAT_PALETTE_DATA.BIN \
      --name Ryu --out web/test-atlas/chars
  # verify pixel identity (re-expands the indexed atlas through the LUT and diffs):
  python3 tools/rgb_to_indexed.py ... --verify
"""
import argparse, json, os, struct, sys
from collections import Counter

try:
    from PIL import Image
except ImportError:
    sys.exit("PIL/Pillow required: pip install Pillow")


def argb4444(w):
    a = (w >> 12) & 0xF; r = (w >> 8) & 0xF; g = (w >> 4) & 0xF; b = w & 0xF
    return (r * 17, g * 17, b * 17, a * 17)


def load_banks(pal_path):
    data = open(pal_path, "rb").read()
    n = len(data) // 32
    banks = []
    for bk in range(n):
        row = [argb4444(struct.unpack_from("<H", data, bk * 32 + i * 2)[0]) for i in range(16)]
        banks.append(row)
    return banks


def greedy_cover(atlas_colors, banks):
    """Return the minimal ordered list of bank ids covering every atlas color.
    Bank 0 (body) is forced FIRST so it always wins ties / ambiguous colors."""
    remaining = set(atlas_colors)
    chosen = []
    # force bank 0 first if it contributes anything
    if banks and any(banks[0][i][:3] in remaining for i in range(1, 16)):
        chosen.append(0)
        remaining -= {banks[0][i][:3] for i in range(1, 16)}
    while remaining:
        best_bk, best_cov = None, 0
        for bk in range(len(banks)):
            if bk in chosen:
                continue
            cov = len(remaining & {banks[bk][i][:3] for i in range(1, 16)})
            if cov > best_cov:
                best_cov, best_bk = cov, bk
        if best_bk is None:
            break
        chosen.append(best_bk)
        remaining -= {banks[best_bk][i][:3] for i in range(1, 16)}
    return chosen, remaining


def build_color_map(bank_list, banks):
    """color(rgb)-> (bankSelPosInList, index). First bank in bank_list wins (body)."""
    cmap = {}
    for pos, bk in enumerate(bank_list):
        for i in range(1, 16):
            rgb = banks[bk][i][:3]
            if rgb not in cmap:        # earlier (preferred) bank keeps the color
                cmap[rgb] = (pos, i)
    return cmap


def nearest(rgb, cmap_items):
    br, bg, bb = rgb
    best, bestd = None, 1 << 30
    for col, sel in cmap_items:
        d = (col[0] - br) ** 2 + (col[1] - bg) ** 2 + (col[2] - bb) ** 2
        if d < bestd:
            bestd, best = d, sel
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--png", required=True, help="RGB atlas e.g. atlas/chars/PL00.png")
    ap.add_argument("--pal", required=True, help="PALETTE_DATA .BIN for that char")
    ap.add_argument("--name", default="")
    ap.add_argument("--out", required=True)
    ap.add_argument("--maxbanks", type=int, default=8,
                    help="cap bankList length to the shader's MAXB (default 8); colors "
                         "beyond it fall back to nearest-color in the kept banks")
    ap.add_argument("--verify", action="store_true",
                    help="re-expand indexed atlas via the LUT and diff vs source (pixel-identity gate)")
    args = ap.parse_args()

    im = Image.open(args.png).convert("RGBA")
    W, H = im.size
    src = im.load()
    banks = load_banks(args.pal)

    # gather opaque atlas colors
    cc = Counter()
    for y in range(H):
        for x in range(W):
            p = src[x, y]
            if p[3] >= 128:
                cc[p[:3]] += 1
    bank_list, uncovered = greedy_cover(set(cc), banks)
    if len(bank_list) > args.maxbanks:
        dropped = bank_list[args.maxbanks:]
        bank_list = bank_list[:args.maxbanks]
        print(f"  NOTE: {len(dropped)} extra banks {dropped} exceed --maxbanks={args.maxbanks}; "
              f"their colors will use nearest-color fallback (reported below).")
    cmap = build_color_map(bank_list, banks)
    cmap_items = list(cmap.items())

    # build the indexed image
    out = Image.new("RGBA", (W, H))
    op = out.load()
    tot = 0; nonexact = 0
    for y in range(H):
        for x in range(W):
            p = src[x, y]
            if p[3] < 128:
                op[x, y] = (255, 0, 0, 0)        # transparent sentinel (bankSel=255,a=0)
                continue
            tot += 1
            rgb = p[:3]
            sel = cmap.get(rgb)
            if sel is None:
                nonexact += 1
                sel = nearest(rgb, cmap_items)   # fallback only if no exact match
            op[x, y] = (sel[0], sel[1], 0, 255)

    os.makedirs(args.out, exist_ok=True)
    base = os.path.splitext(os.path.basename(args.png))[0]
    idx_path = os.path.join(args.out, base + "_idx.png")
    out.save(idx_path)

    lut = {
        "name": args.name,
        "bankList": bank_list,
        "bodyBank": 0,                 # position in bankList that hit-flash/skin overrides
        "banks": [[list(banks[bk][i]) for i in range(16)] for bk in bank_list],
    }
    lut_path = os.path.join(args.out, base + "_lut.json")
    json.dump(lut, open(lut_path, "w"))

    pct = 100.0 * nonexact / tot if tot else 0.0
    print(f"[rgb_to_indexed] {base}: {len(cc)} unique opaque colors, "
          f"banks used (in order) {bank_list}, bodyBank=bank{bank_list[0]}")
    print(f"  opaque pixels={tot}  non-exact (nearest-fallback)={nonexact}  = {pct:.4f}%")
    if uncovered:
        print(f"  WARNING: {len(uncovered)} colors not covered by any bank: {list(uncovered)[:8]}")
    print(f"  wrote {idx_path}")
    print(f"  wrote {lut_path}")

    if args.verify:
        # re-expand and diff
        diff = 0; maxd = 0
        for y in range(H):
            for x in range(W):
                s = src[x, y]
                o = op[x, y]
                if s[3] < 128:
                    continue
                col = banks[bank_list[o[0]]][o[1]]
                d = abs(col[0]-s[0]) + abs(col[1]-s[1]) + abs(col[2]-s[2])
                if d:
                    diff += 1; maxd = max(maxd, d)
        print(f"  [VERIFY] LUT re-expansion vs source: {diff} differing opaque px / {tot}"
              f"  (maxChannelSumDiff={maxd})")
        print(f"  [VERIFY] {'PIXEL-IDENTICAL' if diff == 0 else 'MISMATCH'}")


if __name__ == "__main__":
    main()
