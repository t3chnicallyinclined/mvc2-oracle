#!/usr/bin/env python3
"""
decode_truth_diff.py — FLYCAST GROUND-TRUTH decode comparison for GFX1 parts.

For each PL00 sel that has a clean live PARTDUMP PPM (flycast's OWN decoded part
pixels), decode the part OUR way (offline GFX1 LZSS + PVR PAL4 detwiddle + palette)
and pixel-diff against flycast's PPM. Reports per-sel %-identical (opaque RGB) and
writes a side-by-side montage of mismatches.

GROUND TRUTH:  _ryu_capture/partdump_20260611/PL00_part_<sel>.ppm
  P6 W H 255 linear, magenta(255,0,255)=transparent. W/H = STORAGE dims (sw*8 x sh*8).
  The PPM is the LINEAR-written dump of the scratch 0x0CE60000 buffer, which holds the
  texels TWIDDLED. So PPM[y*w+x] == the twiddled byte stream at linear position y*w+x.
  To recover the TRUE image: true(tx,ty) = PPM-linear[ part_twiddle_idx(tx,ty,w,h) ]
  (the canonical flycast non-square twiddle, partdump_detwiddle.py).

OUR DECODE:    GFX1 LZSS (decodeA) -> raw index/twiddled stream -> palette -> detwiddle.

We compare in TRUE-IMAGE space (both detwiddled with the SAME canonical twiddle), opaque
RGB only. Clean-gate: a sel is trustworthy ground truth only if its opaque-RGB agreement
is high under at least one decode path (rejects scratch-aliasing-contaminated PPMs).
"""
import argparse, os, struct, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "_ryu_capture"))
from partdump_detwiddle import part_twiddle_idx, MAGENTA  # canonical flycast twiddle

# our decoder + palette (import from extract_gfx1_atlas)
sys.path.insert(0, HERE)
from extract_gfx1_atlas import decodeA, detwiddle_pal4, pal_row, _DETW

TILE = 8


# ---- our detwiddle, expressed PER-PIXEL via the canonical idx (reference) ----
def detwiddle_pal4_canonical(raw, w, h):
    """Reference PAL4 detwiddle using the canonical per-pixel partTwiddleIdx.
    raw = 4bpp twiddled nibble stream (2 px/byte, low-nibble = even twiddle index).
    Returns a linear W*H index buffer. This is the byte-exact flycast order."""
    idx = bytearray(w * h)
    for ty in range(h):
        for tx in range(w):
            tw = part_twiddle_idx(tx, ty, w, h)   # position in the twiddled stream
            byte = raw[tw >> 1] if (tw >> 1) < len(raw) else 0
            nib = (byte & 0xF) if (tw & 1) == 0 else ((byte >> 4) & 0xF)
            idx[ty * w + tx] = nib
    return idx


def load_ppm(path):
    d = open(path, "rb").read()
    assert d[:2] == b"P6"
    # parse header: P6\n W H\n 255\n
    i = 2
    toks = []
    while len(toks) < 3:
        while i < len(d) and d[i] in b" \t\r\n":
            i += 1
        s = i
        while i < len(d) and d[i] not in b" \t\r\n":
            i += 1
        toks.append(int(d[s:i]))
    i += 1  # single whitespace after maxval
    w, h, _mx = toks
    px = d[i:i + w * h * 3]
    return w, h, px


def ppm_to_true_rgb(px, w, h):
    """Invert the twiddle: PPM-linear[twiddle_idx(tx,ty)] -> true(tx,ty)."""
    out = bytearray(w * h * 3)
    opaque = bytearray(w * h)
    for ty in range(h):
        for tx in range(w):
            src = part_twiddle_idx(tx, ty, w, h)
            j = src * 3
            if j + 2 >= len(px):
                continue
            r, g, b = px[j], px[j + 1], px[j + 2]
            d = (ty * w + tx) * 3
            if (r, g, b) == MAGENTA:
                out[d:d + 3] = b"\x00\x00\x00"
                opaque[ty * w + tx] = 0
            else:
                out[d:d + 3] = bytes((r, g, b))
                opaque[ty * w + tx] = 1
    return bytes(out), bytes(opaque)


def idx_to_true_rgb(idxbuf, palrgba, w, h):
    """idxbuf = linear W*H palette indices (already detwiddled). idx0 = transparent."""
    out = bytearray(w * h * 3)
    opaque = bytearray(w * h)
    for p in range(w * h):
        ix = idxbuf[p]
        r, g, b, a = palrgba[ix]
        if ix == 0 or a == 0:
            opaque[p] = 0
        else:
            out[p * 3:p * 3 + 3] = bytes((r, g, b))
            opaque[p] = 1
    return bytes(out), bytes(opaque)


def diff_stats(rgbA, opA, rgbB, opB, w, h):
    """Compare two TRUE-image RGB buffers on the union of opaque masks."""
    npx = w * h
    union = same = aOnly = bOnly = colordiff = 0
    for p in range(npx):
        oa, ob = opA[p], opB[p]
        if not oa and not ob:
            continue
        union += 1
        if oa and not ob:
            aOnly += 1
        elif ob and not oa:
            bOnly += 1
        else:
            if rgbA[p*3:p*3+3] == rgbB[p*3:p*3+3]:
                same += 1
            else:
                colordiff += 1
    pct = (100.0 * same / union) if union else 0.0
    return dict(union=union, same=same, colordiff=colordiff,
                aOnly=aOnly, bOnly=bOnly, pct=pct)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gfx1", default="dasm_PLDAT/Output/PL00_DAT/PL00_DAT_GFX_DATA_00.BIN")
    ap.add_argument("--pal",  default="dasm_PLDAT/Output/PL00_DAT/PL00_DAT_PALETTE_DATA.BIN")
    ap.add_argument("--ppmdir", default="_ryu_capture/partdump_20260611")
    ap.add_argument("--bank", type=int, default=0)
    ap.add_argument("--out", default="_ryu_capture/truthdiff")
    ap.add_argument("--detw", choices=["block", "canonical", "both"], default="both",
                    help="which OUR-detwiddle to test: extract_gfx1's 4x4-block, the "
                         "canonical per-pixel, or both.")
    args = ap.parse_args()

    gfx1 = open(args.gfx1, "rb").read()
    pal = open(args.pal, "rb").read()
    palrgba = pal_row(pal, args.bank)
    n = struct.unpack_from("<I", gfx1, 0)[0] >> 2
    offs = [struct.unpack_from("<I", gfx1, i * 4)[0] for i in range(n)]
    srt = sorted(set(offs) | {len(gfx1)})
    import bisect
    def end_of(o):
        i = bisect.bisect_right(srt, o)
        return srt[i] if i < len(srt) else len(gfx1)

    os.makedirs(args.out, exist_ok=True)
    ppms = sorted(int(f.split("_")[2].split(".")[0])
                  for f in os.listdir(args.ppmdir)
                  if f.startswith("PL00_part_") and f.endswith(".ppm"))

    rows = []
    montage = []
    for sel in ppms:
        ppmpath = os.path.join(args.ppmdir, f"PL00_part_{sel}.ppm")
        pw, ph, px = load_ppm(ppmpath)
        if sel >= n:
            continue
        base = offs[sel]
        lw, lh, sw, sh = gfx1[base], gfx1[base+1], gfx1[base+2], gfx1[base+3]
        W, H = sw * TILE, sh * TILE
        if (W, H) != (pw, ph):
            rows.append((sel, W, H, pw, ph, "DIMMISMATCH", 0, 0))
            continue
        stream = gfx1[base+4:end_of(base)]
        raw = decodeA(stream, (W * H) // 2)

        # ground-truth true image
        gt_rgb, gt_op = ppm_to_true_rgb(px, W, H)

        best = None
        variants = {}
        if args.detw in ("block", "both"):
            idx_b = detwiddle_pal4(raw, W, H)
            r_b, o_b = idx_to_true_rgb(idx_b, palrgba, W, H)
            variants["block"] = (r_b, o_b)
        if args.detw in ("canonical", "both"):
            idx_c = detwiddle_pal4_canonical(raw, W, H)
            r_c, o_c = idx_to_true_rgb(idx_c, palrgba, W, H)
            variants["canonical"] = (r_c, o_c)

        st = {}
        for name, (rr, oo) in variants.items():
            st[name] = diff_stats(rr, oo, gt_rgb, gt_op, W, H)
        # pick the best variant for the headline pct
        bestname = max(st, key=lambda k: st[k]["pct"])
        bs = st[bestname]
        rows.append((sel, W, H, pw, ph,
                     " ".join(f"{k}:{v['pct']:.1f}%" for k, v in st.items()),
                     bestname, bs["pct"]))
        # save montage tile (GT | our-best) for visual
        if bs["pct"] < 99.9 or sel in (256, 258, 260, 267, 268, 278):
            montage.append((sel, W, H, gt_rgb, variants[bestname][0]))

    # print table sorted by pct
    print(f"{'sel':>5} {'WxH':>9} {'ppmWxH':>9}  best   detail")
    for r in sorted(rows, key=lambda x: x[7]):
        sel, W, H, pw, ph, detail, bn, pct = r
        print(f"{sel:>5} {W:>4}x{H:<4} {pw:>4}x{ph:<4}  {bn:>9}  {detail}")

    clean = [r for r in rows if r[7] >= 99.0]
    print(f"\nclean (>=99% best): {len(clean)}/{len(rows)} sels")
    # summarize per-variant means on clean set
    print("\nfull rows:", len(rows))

    # write montage
    if montage:
        cell_pad = 4
        maxw = max(W for _, W, H, _, _ in montage)
        maxh = max(H for _, W, H, _, _ in montage)
        cols = 1  # one row per sel: [GT | ours]
        rowh = maxh + 16
        img = Image.new("RGB", (maxw * 2 + cell_pad * 3, rowh * len(montage)),
                        (40, 40, 56))
        from PIL import ImageDraw
        dr = ImageDraw.Draw(img)
        for k, (sel, W, H, gt, ours) in enumerate(montage):
            gti = Image.frombytes("RGB", (W, H), gt)
            oui = Image.frombytes("RGB", (W, H), ours)
            y = k * rowh + 14
            img.paste(gti, (cell_pad, y))
            img.paste(oui, (cell_pad * 2 + maxw, y))
            dr.text((cell_pad, k * rowh + 2), f"sel {sel} {W}x{H}  GT|ours", fill=(255, 255, 0))
        mpath = os.path.join(args.out, "mismatch_montage.png")
        img.save(mpath)
        print(f"montage -> {mpath} ({len(montage)} sels)")


if __name__ == "__main__":
    main()
