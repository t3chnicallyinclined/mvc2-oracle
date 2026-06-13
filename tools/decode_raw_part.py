#!/usr/bin/env python3
"""
decode_raw_part.py — offline format/twiddle locker for the part-capture probe.

The probe dumps RAW texels per part (PL{hex}_part_NNN.raw = w*h*2 LE bytes, no decode).
This tool tries every (pixel-format x twiddle) combination and writes a PNG per combo,
so you can eyeball which one is correct WITHOUT redeploying the probe per guess.

Pixel formats:  argb1555, rgb565, argb4444, abgr1555, xrgb1555
Twiddle modes:  linear      — row-major, no swizzle (likely for large char textures)
                twiddled    — full PVR Morton interleave (square; HUD textures)
                nonsquare   — Morton within min(w,h) square blocks, blocks linear

Usage:
  # one part, all combos -> /tmp/PLxx_part_000.<fmt>.<twid>.png
  python3 tools/decode_raw_part.py --raw /dev/shm/PL2A_part_000.raw --w 256 --h 256

  # pull w,h from the manifest automatically for a given part_idx
  python3 tools/decode_raw_part.py --in /dev/shm --char 2A --part 0

  # only a specific combo
  python3 tools/decode_raw_part.py --raw ... --w 32 --h 32 --fmt rgb565 --twid linear

ROM-derived -> /tmp only, gitignored, never committed.
"""
import argparse, os, sys

def read_raw(path, w, h, bpp=16):
    with open(path, 'rb') as f:
        data = f.read()
    need = w * h * bpp // 8
    if len(data) < need:
        print(f"WARN: {path} has {len(data)} bytes, need {need} ({w}x{h} @ {bpp}bpp); padding")
        data = data + b'\x00' * (need - len(data))
    return data

def px16(data, i):
    return data[i*2] | (data[i*2+1] << 8)

# ---- format decoders: u16 -> (r,g,b,a) 8-bit ----
def f_argb1555(v):
    a = 255 if (v & 0x8000) else 0
    r = ((v >> 10) & 0x1f) * 255 // 31
    g = ((v >> 5) & 0x1f) * 255 // 31
    b = (v & 0x1f) * 255 // 31
    return r, g, b, a

def f_xrgb1555(v):  # same bits, ignore the top bit (always opaque)
    r = ((v >> 10) & 0x1f) * 255 // 31
    g = ((v >> 5) & 0x1f) * 255 // 31
    b = (v & 0x1f) * 255 // 31
    return r, g, b, 255

def f_abgr1555(v):
    a = 255 if (v & 0x8000) else 0
    b = ((v >> 10) & 0x1f) * 255 // 31
    g = ((v >> 5) & 0x1f) * 255 // 31
    r = (v & 0x1f) * 255 // 31
    return r, g, b, a

def f_rgb565(v):
    r = ((v >> 11) & 0x1f) * 255 // 31
    g = ((v >> 5) & 0x3f) * 255 // 63
    b = (v & 0x1f) * 255 // 31
    return r, g, b, 255

def f_argb4444(v):
    a = ((v >> 12) & 0xf) * 17
    r = ((v >> 8) & 0xf) * 17
    g = ((v >> 4) & 0xf) * 17
    b = (v & 0xf) * 17
    return r, g, b, (0 if a == 0 else a)

FMTS = {
    "argb1555": f_argb1555, "xrgb1555": f_xrgb1555, "abgr1555": f_abgr1555,
    "rgb565": f_rgb565, "argb4444": f_argb4444,
}

# The DM00 Poly directory entry carries the part FORMAT at +0x4 (e4); the format
# selector is e4 BYTE 1 ((e4>>8)&0xff), byte 0 (0x01) being a constant "present" flag.
# Confirmed from bank12:loc_8c123e00 (e4 = a descriptor index over the 0x10-stride
# directory) + empirical decode. NOTE: ec (+0xC) is 0 on this directory — it is NOT
# the TCW (that was the VRAM-upload builder, a different structure).
#   e4 byte1  format        bpp
#   0x00      argb1555       16
#   0x01      rgb565         16   (32x32 parts decode clean)
#   0x02      argb4444       16
#   0x03      pal8            8   (256x256 body — operator-confirmed paletted PAL8)
#   0x04      pal4            4
# PAL4 vs PAL8 is ALSO settable from the raw dump size: PAL4 = w*h/2, PAL8 = w*h.
E4_SELECTOR = {
    0x00: ("argb1555", "twiddled", 16),
    0x01: ("rgb565",   "twiddled", 16),
    0x02: ("argb4444", "twiddled", 16),
    0x03: ("pal8",     "twiddled",  8),
    0x04: ("pal4",     "twiddled",  4),
}

# PVR PixelFmt (TCW bits 27-29) -> (fmt_name, bpp). flycast ta_structs.h `union TCW`.
PVR_FMT = {0: ("argb1555", 16), 1: ("rgb565", 16), 2: ("argb4444", 16),
           5: ("pal4", 4), 6: ("pal8", 8)}

def tcw_format(tcw):
    """tcw (int|hex-str) = the PVR Texture Control Word the game resolved for this part
    (descriptor+0x0C, dumped by the probe via partResolveTCW). The AUTHORITATIVE format:
    fmt = (tcw>>27)&7, twiddle = !(tcw>>26)&1. Returns (fmt_name, twiddle, bpp) or None
    for an unresolved/zero TCW (caller falls back to e4_format)."""
    if isinstance(tcw, str):
        tcw = int(tcw, 16)
    if tcw == 0:
        return None
    fmt = (tcw >> 27) & 7
    if fmt not in PVR_FMT:
        return None
    twid = "linear" if ((tcw >> 26) & 1) else "twiddled"
    fname, bpp = PVR_FMT[fmt]
    return (fname, twid, bpp)

def e4_format(e4, rawbytes=None, w=None, h=None):
    """FALLBACK only (when the resolved TCW is 0/unavailable). e4 (int|hex-str) ->
    (fmt_name, twiddle, bpp); rawbytes+w+h disambiguate PAL4 (w*h/2) vs PAL8 (w*h)."""
    if isinstance(e4, str):
        e4 = int(e4, 16)
    sel = (e4 >> 8) & 0xff
    fname, twid, bpp = E4_SELECTOR.get(sel, ("rgb565", "twiddled", 16))
    if rawbytes and w and h and fname in ("pal4", "pal8"):
        if rawbytes >= w * h:        # 1 byte/pixel -> PAL8
            fname, bpp = "pal8", 8
        elif rawbytes >= (w * h) // 2:
            fname, bpp = "pal4", 4
    return (fname, twid, bpp)

def part_format(tcw, e4, rawbytes=None, w=None, h=None):
    """Authoritative format resolution: prefer the resolved TCW (descriptor+0x0C); fall
    back to the e4-byte1 heuristic only if the TCW is 0/unresolvable."""
    r = tcw_format(tcw) if tcw is not None else None
    return r if r is not None else e4_format(e4, rawbytes, w, h)

# ---- paletted (PAL4/PAL8) decode: index -> ARGB4444 palette lookup ----
def read_palette(path, banks=128):
    """Read the dumped Dat_Pal (ARGB4444 LE, 16 colors/bank). Returns a flat list of
    (r,g,b,a) — index 0 of each bank is transparent."""
    with open(path, 'rb') as f:
        data = f.read()
    pal = []
    n = min(len(data) // 2, banks * 16)
    for i in range(n):
        v = data[i*2] | (data[i*2+1] << 8)
        a = ((v >> 12) & 0xf) * 17; r = ((v >> 8) & 0xf) * 17
        g = ((v >> 4) & 0xf) * 17;  b = (v & 0xf) * 17
        pal.append((r, g, b, 0 if (i % 16) == 0 else a))   # index 0/bank = transparent
    return pal

def decode_paletted(data, w, h, bpp, palette, pal_base, twid):
    """Decode a PAL4/PAL8 part using the same twiddle index as the 16-bit path."""
    from PIL import Image
    tix = TWIDS[twid]
    sq = min(w, h); sqbits = 0
    while (1 << sqbits) < sq:
        sqbits += 1
    img = Image.new('RGBA', (w, h)); px = img.load()
    n = w * h
    for y in range(h):
        for x in range(w):
            i = tix(x, y, w, h, sq, sqbits)
            if i < 0 or i >= n:
                px[x, y] = (255, 0, 255, 0); continue
            if bpp == 4:
                byte = data[i >> 1] if (i >> 1) < len(data) else 0
                pidx = (byte >> 4) if (i & 1) else (byte & 0xf)
            else:
                pidx = data[i] if i < len(data) else 0
            if pidx == 0:
                px[x, y] = (0, 0, 0, 0); continue
            pe = pal_base + pidx
            px[x, y] = palette[pe] if pe < len(palette) else (255, 0, 255, 255)
    return img

# ---- twiddle index: (x,y) -> linear texel index in the raw buffer ----
# EXACT port of flycast's core/rend/texconv.cpp (detwiddle table + twop). The PVR
# interleaves **y-bit first, then x** per pair; the old x-first version transposed the
# image, scrambling large square textures (the 256x256 body) while looking OK on small
# symmetric parts. twiddle_slow / detwiddle / twop match flycast bit-for-bit (the same
# math mcfx uses to decode real VRAM in maplecast_mirror.cpp).
def idx_linear(x, y, w, h, sq, sqbits):
    return y * w + x

def _twiddle_slow(x, y, x_sz, y_sz):
    rv = 0; sh = 0; x_sz >>= 1; y_sz >>= 1
    while x_sz != 0 or y_sz != 0:
        if y_sz != 0:
            rv |= (y & 1) << sh; y_sz >>= 1; y >>= 1; sh += 1
        if x_sz != 0:
            rv |= (x & 1) << sh; x_sz >>= 1; x >>= 1; sh += 1
    return rv

# detwiddle[0][s][i] = twiddle_slow(i,0,1024,1<<s); detwiddle[1][s][i] = twiddle_slow(0,i,1<<s,1024)
_DETW = [[[0] * 1024 for _ in range(11)] for _ in range(2)]
for _s in range(11):
    _ysz = 1 << _s
    for _i in range(1024):
        _DETW[0][_s][_i] = _twiddle_slow(_i, 0, 1024, _ysz)
        _DETW[1][_s][_i] = _twiddle_slow(0, _i, _ysz, 1024)

def _bitscanrev(v):
    r = 0
    while (1 << (r + 1)) <= v:
        r += 1
    return r

def idx_twiddled(x, y, w, h, sq, sqbits):
    # flycast-canonical (y-first): twop(x,y,bcx,bcy) = detwiddle[0][bcy][x] + detwiddle[1][bcx][y]
    bcx = _bitscanrev(w); bcy = _bitscanrev(h)
    return _DETW[0][bcy][x] + _DETW[1][bcx][y]

def idx_twiddleX(x, y, w, h, sq, sqbits):
    # The OLD x-first interleave = a transpose of the canonical twiddle. Kept ONLY so the
    # 256x256 body can be A/B'd against the oracle: if the small parts are right under
    # `twiddled` (y-first) but the body needs this, the DM00 texels for large parts are
    # laid out transposed and we'd select per-size. (Normally `twiddled` is correct.)
    bcx = _bitscanrev(w); bcy = _bitscanrev(h)
    return _DETW[0][bcx][y] + _DETW[1][bcy][x]

def idx_nonsquare(x, y, w, h, sq, sqbits):
    return idx_twiddled(x, y, w, h, sq, sqbits)

TWIDS = {"linear": idx_linear, "twiddled": idx_twiddled,
         "twiddleX": idx_twiddleX, "nonsquare": idx_nonsquare}

def decode(data, w, h, fmt, twid):
    from PIL import Image
    dec = FMTS[fmt]; tix = TWIDS[twid]
    sq = min(w, h); sqbits = 0
    while (1 << sqbits) < sq:
        sqbits += 1
    img = Image.new('RGBA', (w, h))
    px = img.load()
    n = w * h
    for y in range(h):
        for x in range(w):
            i = tix(x, y, w, h, sq, sqbits)
            if i < 0 or i >= n:
                px[x, y] = (255, 0, 255, 255); continue
            px[x, y] = dec(px16(data, i))
    return img

def manifest_dims(indir, char, part):
    # manifest: "part_idx key raw ppm w h e4 texptr ec [rawbytes tcw fmt twid descU16 desc]"
    mn = os.path.join(indir, f'PL{char}_parts.manifest')
    with open(mn) as f:
        for line in f:
            t = line.split()
            if line.startswith('#') or len(t) < 9 or t[-1] == 'SKIP':
                continue
            if int(t[0]) == part:
                rawbytes = int(t[9]) if len(t) >= 10 else None
                tcw = t[10] if len(t) >= 11 else None          # resolved PVR TCW (hex)
                return int(t[4]), int(t[5]), t[2], t[6], rawbytes, tcw  # w,h,raw,e4,rawbytes,tcw
    return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--raw'); ap.add_argument('--w', type=int); ap.add_argument('--h', type=int)
    ap.add_argument('--in', dest='indir', default='/dev/shm')
    ap.add_argument('--char'); ap.add_argument('--part', type=int)
    ap.add_argument('--fmt', choices=list(FMTS)); ap.add_argument('--twid', choices=list(TWIDS))
    ap.add_argument('--out', default='/tmp')
    args = ap.parse_args()
    try:
        from PIL import Image  # noqa
    except ImportError:
        sys.exit("need Pillow: pip install Pillow")

    raw, w, h, e4, rawbytes, tcw = args.raw, args.w, args.h, None, None, None
    if raw is None:
        if args.char is None or args.part is None:
            sys.exit("pass --raw --w --h, or --char --part (reads manifest)")
        dims = manifest_dims(args.indir, args.char.upper(), args.part)
        if not dims:
            sys.exit(f"part {args.part} not found in manifest")
        w, h, rawname, e4, rawbytes, tcw = dims
        raw = os.path.join(args.indir, rawname)
    base = os.path.splitext(os.path.basename(raw))[0]

    # Format = the resolved PVR TCW (descriptor+0x0C) the game uses; e4 only as fallback.
    # Paletted parts decode via the palette dump.
    if e4 is not None and not (args.fmt or args.twid):
        fname, twid, bpp = part_format(tcw, e4, rawbytes, w, h)
        src = f"tcw={tcw}" if (tcw and tcw_format(tcw)) else f"e4={e4} (fallback)"
        if fname in ('pal4', 'pal8'):
            palpath = os.path.join(args.indir, f'PL{args.char.upper()}_palette.bin')
            if not os.path.exists(palpath):
                sys.exit(f"part {args.part} is {fname} ({src}) but no palette: {palpath}")
            palette = read_palette(palpath)
            data = read_raw(raw, w, h, bpp)
            img = decode_paletted(data, w, h, bpp, palette, 0, twid)
            out = os.path.join(args.out, f'{base}.{fname}.{twid}.png')
            img.save(out)
            print(f"  {fname:9s} {twid:9s} -> {out}  ({src})")
            print(f"[done] {w}x{h} paletted; if colors are off, try a different palette bank")
            return
        # 16-bit: still loop combos by default unless format selects a single fmt.
        if not args.fmt:
            args.fmt = fname
        if not args.twid:
            args.twid = twid

    data = read_raw(raw, w, h)
    fmts = [args.fmt] if args.fmt else list(FMTS)
    twids = [args.twid] if args.twid else list(TWIDS)
    for fmt in fmts:
        for twid in twids:
            img = decode(data, w, h, fmt, twid)
            out = os.path.join(args.out, f'{base}.{fmt}.{twid}.png')
            img.save(out)
            print(f"  {fmt:9s} {twid:9s} -> {out}")
    print(f"[done] {w}x{h}; open the PNGs and pick the clean one, then tell me fmt+twid")

if __name__ == '__main__':
    main()
