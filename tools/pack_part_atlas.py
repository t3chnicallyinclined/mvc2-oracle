#!/usr/bin/env python3
"""
pack_part_atlas.py — offline packer for MapleCast's assembly-driven part renderer.

Consumes the runtime capture produced by the MAPLECAST_PARTDUMP probe
(core/network/maplecast_gamestate.cpp) and emits the two client artifacts:

  PL{hex}_parts.png   — packed atlas of every captured part rectangle (RGBA)
  PL{hex}_asm.json    — { parts: [{x,y,w,h}], assemblies: {sprite_id|slot: [recs]} }

and, with --validate, a composite of one assembly diffed against the community
sprite sheet (the same oracle used to crack the codec).

Inputs (the probe writes these to /dev/shm; copy them next to this tool or pass --in):
  PL{hex}_parts.manifest   "# part_idx key raw ppm w h e4 texptr ec"
                           then "<part_idx> <key> <raw> <ppm> <w> <h> <e4> <texptr> <ec>"
                           (appended across frames; deduped here, last write per part wins)
  PL{hex}_part_NNN.ppm      best-effort preview (P6 RGB; magenta = transparent key)
  PL{hex}_part_NNN.raw      RAW texels (w*h*2 LE) — authoritative source once the format
                            is locked offline via tools/decode_raw_part.py
  PL{hex}_extras.bin        16KB of the live EXTRAS region (assembly placement records)

By default the atlas is built from the PPM previews. Once the pixel format is locked
(see tools/decode_raw_part.py), pass --fmt/--twid to build the atlas from the .raw
files instead (correct pixels). NO ROM-DERIVED PIXELS ARE COMMITTED — outputs gitignored.

Usage:
  python3 tools/pack_part_atlas.py --char 00 --in /dev/shm --out /tmp
  python3 tools/pack_part_atlas.py --char 2A --in /dev/shm --out /tmp \
      --fmt argb1555 --twid linear        # build from raw with the locked format
  python3 tools/pack_part_atlas.py --char 00 --in /dev/shm --out /tmp \
      --validate MvC2_Spritesheets_20260516/PL00.png --asm-slot 0
"""
import argparse, json, os, struct, sys

MAGENTA = (0xFF, 0x00, 0xFF)   # the probe's transparent key (PPM has no alpha)

# ---- EXTRAS assembly parsing -------------------------------------------------
# REAL 8-byte record layout (CONFIRMED against the quad emitter loc_8c033d78/e90,
# marvelous2 build/bank03.asm:9092-9305):
#   [dx:s16 @+0][dy:s16 @+2][palette:u16 @+4][GFX_SELECTOR:u16 @+6]
#   terminator   = GFX_SELECTOR(@+6) == 0x00FF   (sentinel quad, loc_8c033f14)
#   GFX_SELECTOR = index into the GFX1 offset table (in-range 29..65) — the part KEY
#   palette row  = (rec[+0x4] & 0x3ff) >> 4      (static form)
#
# THE PRIOR BUG: read the GFX index from +4 (= palette, a near-constant ~16) and
# treated +6 as a terminator-only attr — collapsing every key to a palette constant,
# so the assembly part-keys never matched any captured part. The texture SELECTOR is
# +6 (range 29-65); +4 is the palette.
#
# The EXTRAS region is a flat stream of assemblies; an assembly is a run of records
# ending at the +6==0x00FF terminator (an all-zero 8-byte record also separates).
# Assemblies are keyed here by their ordinal index; the sprite_id -> assembly map
# comes from the runtime PARTDUMP (live cell gives the real sprite_id).
REC = 8

def parse_extras(buf):
    """Return {assembly_index: [ {dx,dy,part,flip,pal} ... ]} for every assembly.
    `part` is the +6 GFX_SELECTOR (the atlas key)."""
    asms = {}
    cur = []
    idx = 0
    pos = 0
    n = len(buf)
    while pos + REC <= n:
        dx, dy = struct.unpack_from('<hh', buf, pos)
        palw = struct.unpack_from('<H', buf, pos + 4)[0]   # palette word
        sel  = struct.unpack_from('<H', buf, pos + 6)[0]   # GFX_SELECTOR (key)
        lo = struct.unpack_from('<I', buf, pos)[0]
        pos += REC
        if sel == 0x00FF or (lo == 0 and sel == 0 and palw == 0):
            if cur:
                asms[idx] = cur; idx += 1; cur = []
            continue
        cur.append({"dx": dx, "dy": dy, "part": sel,
                    "flip": 0, "pal": (palw & 0x3ff) >> 4})
    if cur:
        asms[idx] = cur
    return asms

# ---- PPM reader --------------------------------------------------------------
def read_ppm(path):
    with open(path, 'rb') as f:
        data = f.read()
    assert data[:2] == b'P6', path
    # parse header tokens
    idx = 2; toks = []
    while len(toks) < 3:
        while idx < len(data) and data[idx] in b' \t\n\r':
            idx += 1
        if idx < len(data) and data[idx:idx+1] == b'#':
            while idx < len(data) and data[idx] not in b'\n':
                idx += 1
            continue
        st = idx
        while idx < len(data) and data[idx] not in b' \t\n\r':
            idx += 1
        toks.append(int(data[st:idx]))
    idx += 1  # single whitespace after maxval
    w, h, _mx = toks
    px = data[idx:idx + w*h*3]
    return w, h, px

# ---- sprite_id -> LIVE assembly re-key (Gap 2) -------------------------------
# The probe writes "PL{H}_sidasm.txt" per fire from the LIVE CELL (player+0x154, the
# current 20-byte keyframe). The GSTA sprite_id the client keys by is read16(0x144),
# which the anim tick copies from keyframe[4] — so the cell's keyframe[4] IS that exact
# sid. keyframe[0x12] is the EXTRAS slot; the assembly is EXTRAS + slot*0x400 + 0x08.
# The probe emits, keyed by the live sid, the assembly's records directly:
#   "<sprite_id> <slot> <nrecs> dx,dy,part,flip;dx,dy,part,flip;..."
# Dedupe: last write per sprite_id wins. Returns {sprite_id: [ {dx,dy,part,flip} ... ]}.
def read_sidasm(path):
    m = {}
    if not os.path.exists(path):
        return m
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            t = line.split(None, 3)               # sid, slot, nrecs, "recs..."
            if len(t) < 4:
                continue
            sid = int(t[0])
            recs = []
            for r in t[3].split(';'):
                if not r:
                    continue
                f4 = r.split(',')
                if len(f4) < 4:
                    continue
                dx, dy, part, flip = int(f4[0]), int(f4[1]), int(f4[2]), int(f4[3])
                pal = int(f4[4]) if len(f4) >= 5 else 0     # new probe also emits pal_row (attr low byte)
                recs.append({"dx": dx, "dy": dy, "part": part, "flip": flip, "pal": pal})
            if recs:
                m[sid] = recs                      # last write per sid wins
    return m

# ---- manifest ----------------------------------------------------------------
def read_manifest(path):
    # "<part_idx> <key> <raw> <ppm> <w> <h> <e4> <texptr> <ec> [<rawbytes> <tcw> ...]".
    # Appended across frames -> dedupe by part_idx, last non-SKIP write wins.
    parts = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            t = line.split()
            if t[-1] == 'SKIP' or len(t) < 9:
                continue
            idx = int(t[0]); key = int(t[1]); raw = t[2]; ppm = t[3]
            w = int(t[4]); h = int(t[5]); e4 = t[6]; ptr = t[7]; ec = t[8]
            rawbytes = int(t[9]) if len(t) >= 10 else None
            tcw = t[10] if len(t) >= 11 else None      # resolved PVR TCW (descriptor+0x0C)
            parts[idx] = {"key": key, "raw": raw, "ppm": ppm, "w": w, "h": h,
                          "e4": e4, "ptr": ptr, "ec": ec, "rawbytes": rawbytes, "tcw": tcw}
    return parts

# ---- atlas packing (simple shelf packer) -------------------------------------
def pack_atlas(parts_px, atlas_w=1024, pad=1):
    """parts_px: {idx: (w,h,rgba_bytes)}. Returns (atlas_w, atlas_h, rgba, rects)."""
    from PIL import Image
    order = sorted(parts_px.keys(), key=lambda k: -parts_px[k][1])  # tallest first
    rects = {}
    x = y = row_h = 0
    placements = []
    for idx in order:
        w, h, _ = parts_px[idx]
        if x + w + pad > atlas_w:
            x = 0; y += row_h + pad; row_h = 0
        rects[idx] = {"x": x, "y": y, "w": w, "h": h}
        placements.append((idx, x, y))
        x += w + pad
        row_h = max(row_h, h)
    atlas_h = y + row_h + pad
    # round up to pow2-ish
    ah = 1
    while ah < atlas_h:
        ah <<= 1
    atlas = Image.new('RGBA', (atlas_w, ah), (0, 0, 0, 0))
    for idx, px, py in placements:
        w, h, rgba = parts_px[idx]
        im = Image.frombytes('RGBA', (w, h), rgba)
        atlas.paste(im, (px, py))
    return atlas, rects

def ppm_to_rgba(w, h, ppm):
    out = bytearray(w*h*4)
    for i in range(w*h):
        r, g, b = ppm[i*3], ppm[i*3+1], ppm[i*3+2]
        if (r, g, b) == MAGENTA:
            out[i*4:i*4+4] = b'\x00\x00\x00\x00'
        else:
            out[i*4+0] = r; out[i*4+1] = g; out[i*4+2] = b; out[i*4+3] = 255
    return bytes(out)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--char', required=True, help='hex char id, e.g. 00')
    ap.add_argument('--in', dest='indir', default='/dev/shm')
    ap.add_argument('--out', default='/tmp')
    ap.add_argument('--validate', help='sprite-sheet PNG to diff a composite against')
    ap.add_argument('--asm-slot', type=int, default=0, help='assembly slot to composite')
    ap.add_argument('--fmt', help='locked pixel format -> build atlas from .raw (see decode_raw_part.py)')
    ap.add_argument('--twid', help='locked twiddle mode -> build atlas from .raw')
    ap.add_argument('--twid-large', dest='twid_large',
                    help='override twiddle for parts >=64px (e.g. twiddleX) — for the 256x256 body')
    args = ap.parse_args()
    H = args.char.upper()

    try:
        from PIL import Image
    except ImportError:
        sys.exit("need Pillow: pip install Pillow")

    man = os.path.join(args.indir, f'PL{H}_parts.manifest')
    ext = os.path.join(args.indir, f'PL{H}_extras.bin')
    if not os.path.exists(man):
        sys.exit(f"missing {man} — run the probe first (see docs/ASSEMBLY-DRIVEN-DESIGN.md)")

    # The raw decoder is needed for BOTH the per-part default and the forced
    # --fmt/--twid path (only the ppm-preview fallback skips it).
    use_raw = bool(args.fmt and args.twid)
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "decode_raw_part", os.path.join(os.path.dirname(__file__), "decode_raw_part.py"))
    drp = importlib.util.module_from_spec(spec); spec.loader.exec_module(drp)

    parts = read_manifest(man)

    # PER-PART format: 32x32 parts are RGB565-twiddled, the 256x256 body is PALETTED
    # 8bpp (PAL8) — so ONE global --fmt/--twid is wrong. Default behaviour reads each
    # part's e4 byte-1 selector (manifest e4 field) and decodes it with its OWN format
    # (16-bit direct or paletted via the dumped palette); the manifest rawbytes field
    # disambiguates PAL4 (w*h/2) vs PAL8 (w*h). --fmt/--twid FORCE a single format.
    use_per_part = not (args.fmt and args.twid)
    palette = None
    if use_per_part:
        palpath = os.path.join(args.indir, f'PL{H}_palette.bin')
        if os.path.exists(palpath):
            palette = drp.read_palette(palpath)

    parts_px = {}
    nfmt = {}
    for idx, p in parts.items():
        w, h = p["w"], p["h"]
        rpath = os.path.join(args.indir, p["raw"])
        ppath = os.path.join(args.indir, p["ppm"])
        if use_per_part:
            # Auto per-part decode: format = the resolved PVR TCW (descriptor+0x0C the
            # game uses), with the e4-byte1 heuristic only as fallback. PAL4/PAL8 also
            # disambiguated by the dumped raw size. Prefer .raw; fall back PPM.
            fname, twid, bpp = drp.part_format(p.get("tcw"), p["e4"], p.get("rawbytes"), p["w"], p["h"])
            # Per-size twiddle override: large parts (>=64px) can use a different twiddle
            # order than the small parts if the oracle shows they're laid out transposed.
            if args.twid_large and twid != "linear" and w >= 64 and h >= 64:
                twid = args.twid_large
            nfmt[fname] = nfmt.get(fname, 0) + 1
            # PREFER the PPM preview: the probe bakes it with the part's CORRECT live
            # palette row (Dat_Pal + palRow*32). The .raw + decode_paletted() path uses
            # pal_base=0 (palette bank 0) which loses the per-part palette row, so it is
            # only a fallback when no PPM exists. (The .raw stays the authoritative source
            # for offline format-locking via tools/decode_raw_part.py.)
            if os.path.exists(ppath):
                pw, ph, px = read_ppm(ppath)
                parts_px[idx] = (pw, ph, ppm_to_rgba(pw, ph, px))
            elif os.path.exists(rpath):
                if fname in ('pal4', 'pal8'):
                    if palette is None:
                        # paletted part but no palette dump -> skip (logged below)
                        continue
                    data = drp.read_raw(rpath, w, h, bpp)
                    img = drp.decode_paletted(data, w, h, bpp, palette, 0, twid)
                else:
                    data = drp.read_raw(rpath, w, h, bpp)
                    img = drp.decode(data, w, h, fname, twid)
                parts_px[idx] = (w, h, img.convert('RGBA').tobytes())
        elif use_raw:
            if not os.path.exists(rpath):
                continue
            data = drp.read_raw(rpath, w, h)
            img = drp.decode(data, w, h, args.fmt, args.twid).convert('RGBA')
            parts_px[idx] = (w, h, img.tobytes())
        else:
            if not os.path.exists(ppath):
                continue
            pw, ph, px = read_ppm(ppath)
            parts_px[idx] = (pw, ph, ppm_to_rgba(pw, ph, px))
    if use_per_part:
        src = "per-part TCW/e4" + (" (paletted via palette.bin)" if palette else " (NO palette.bin — paletted parts skipped)")
        if nfmt:
            src += " [" + ", ".join(f"{k}:{v}" for k, v in sorted(nfmt.items())) + "]"
    else:
        src = f"raw ({args.fmt}/{args.twid})" if use_raw else "ppm preview"
    print(f"[pack] PL{H}: {len(parts_px)} parts loaded from {src}")

    atlas, rects = pack_atlas(parts_px)
    atlas_path = os.path.join(args.out, f'PL{H}_parts.png')
    atlas.save(atlas_path)
    print(f"[pack] atlas -> {atlas_path}  ({atlas.width}x{atlas.height})")

    # Slot-keyed assemblies from the static EXTRAS region (debug/reference only).
    asms = {}
    if os.path.exists(ext):
        with open(ext, 'rb') as f:
            asms = parse_extras(f.read())
        print(f"[pack] {len(asms)} non-empty assembly slots from EXTRAS (reference)")

    # Gap 2: re-key by the EXACT live GSTA sprite_id. The probe captured, per fire, the
    # LIVE assembly (records at *(player+0x144)+0x18) keyed by read16(player+0x144) — the
    # very value the client looks up. So assemblies come straight from PL{H}_sidasm.txt.
    asm_by_sid = read_sidasm(os.path.join(args.indir, f'PL{H}_sidasm.txt'))
    if asm_by_sid:
        print(f"[pack] re-keyed {len(asm_by_sid)} LIVE sprite_ids -> assemblies "
              f"(from PL{H}_sidasm.txt)")
    else:
        # No live capture -> fall back to slot-keyed (won't match the client's sids).
        asm_by_sid = asms
        print("[pack] WARNING: no PL{}_sidasm.txt — assemblies keyed by SLOT, not the "
              "live sprite_id. Re-capture with the updated probe.".format(H))

    parts_list = []
    idx_remap = {}
    for i, idx in enumerate(sorted(rects.keys())):
        idx_remap[idx] = i
        r = rects[idx]
        parts_list.append({"part_idx": idx, **r})

    out = {
        "char": f"PL{H}",
        "atlas": f"PL{H}_parts.png",
        "atlas_w": atlas.width, "atlas_h": atlas.height,
        "parts": {str(idx): rects[idx] for idx in sorted(rects.keys())},
        "assemblies": {str(k): v for k, v in asm_by_sid.items()},     # keyed by sprite_id
        "assemblies_by_slot": {str(k): v for k, v in asms.items()},   # raw slot index (debug)
    }
    asm_path = os.path.join(args.out, f'PL{H}_asm.json')
    with open(asm_path, 'w') as f:
        json.dump(out, f, indent=1)
    print(f"[pack] assembly table -> {asm_path}")

    # The client also fetches PL{H}_parts.json separately (rects). Emit it too so the
    # assembly path's loadAsmChar() has both files.
    parts_json_path = os.path.join(args.out, f'PL{H}_parts.json')
    with open(parts_json_path, 'w') as f:
        json.dump({"parts": {str(idx): rects[idx] for idx in sorted(rects.keys())}}, f, indent=1)
    print(f"[pack] parts rects -> {parts_json_path}")

    if args.validate:
        composite_validate(args, H, parts_px, asms)

def composite_validate(args, H, parts_px, asms):
    from PIL import Image
    slot = args.asm_slot
    if slot not in asms:
        print(f"[validate] slot {slot} not in assemblies {sorted(asms)[:8]}...")
        return
    recs = asms[slot]
    # composite onto a canvas centered at (cx,cy)
    cx, cy = 256, 320
    canvas = Image.new('RGBA', (512, 512), (0, 0, 0, 0))
    for rec in recs:
        pi = rec["part"]
        if pi not in parts_px:
            continue
        w, h, rgba = parts_px[pi]
        im = Image.frombytes('RGBA', (w, h), rgba)
        if rec["flip"]:
            im = im.transpose(Image.FLIP_LEFT_RIGHT)
            x = cx - rec["dx"] - w
        else:
            x = cx + rec["dx"]
        y = cy + rec["dy"]
        canvas.alpha_composite(im, (max(0, x), max(0, y)))
    comp_path = os.path.join(args.out, f'PL{H}_composite_slot{slot}.png')
    canvas.save(comp_path)
    print(f"[validate] composite slot {slot} ({len(recs)} parts) -> {comp_path}")
    print(f"[validate] compare against {args.validate} by eye (alignment/silhouette)")

if __name__ == '__main__':
    main()
