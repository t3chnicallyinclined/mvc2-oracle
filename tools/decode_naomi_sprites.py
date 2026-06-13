#!/usr/bin/env python3
"""
decode_naomi_sprites.py — Extract and decode PLxx character sprites from
MVC2 PLxx_DAT.BIN files using the confirmed pldat-codec.mjs algorithm.

Codec (from pldat-codec.mjs, clean-room disassembly of loc_8c03552a):
  - 16-bit WORD-based LZSS
  - MSB-first flag words (seed 0x8000, shift right after each op)
  - Bit CLEAR (0) = LITERAL: copy one u16 verbatim
  - Bit SET  (1) = TOKEN: count = tok>>11, operand = tok & 0x07FF
      count==0 -> extended: next u16 is count
      operand==0 -> zero fill (count zero words)
      operand!=0 -> back-ref (copy count words from out[-operand*2 bytes])
  - Self-contained parts: back-refs stay within own output -> correct offline
  - Multi-tile parts: back-refs reach scratch-buffer residue -> transparent fill

Blob header (4 bytes): w, h, sw, sh in 8px tile units.
Output: 4bpp tiles, sw*sh tiles in row-major order.

USAGE
  # Decode self-contained parts from PL2C (Magneto)
  python3 tools/decode_naomi_sprites.py --dat _naomi_work/PL2C_DAT.BIN --out /tmp/pl2c_parts
  # Decode a specific part index
  python3 tools/decode_naomi_sprites.py --dat _naomi_work/PL00_DAT.BIN --part 326 --out /tmp
  # Side-by-side for comparison (DC vs DC, since Naomi needs live boot)
  python3 tools/decode_naomi_sprites.py --dat _naomi_work/PL00_DAT.BIN --all-self-contained --out /tmp/pl00
"""
import argparse, os, struct, sys
from PIL import Image


# ─── LZSS decoder (exact port of pldat-codec.mjs decodeStream) ───────────────

OPERAND_MASK = 0x07FF
COUNT_SHIFT  = 11

def _read_u16(stream, pos):
    if pos + 1 < len(stream):
        return stream[pos] | (stream[pos+1] << 8)
    if pos < len(stream):
        return stream[pos]
    return 0

def decode_stream(stream, out, max_bytes=None):
    """Decode LZSS stream into out list (each entry is one byte).
    max_bytes: stop after this many bytes (the caller-provided output size bound —
    critical for extended-count tokens which carry no internal terminator).
    Back-refs before index 0 emit transparent (0) bytes."""
    n = len(stream)
    pos = 0
    mask = 0
    flag = 0

    def _full():
        return max_bytes is not None and len(out) >= max_bytes

    def _push2(a, b):
        if max_bytes is None or len(out) + 1 < max_bytes:
            out.append(a); out.append(b)
        elif len(out) < max_bytes:
            out.append(a)

    while pos + 1 < n and not _full():
        if mask == 0:
            flag = _read_u16(stream, pos); pos += 2
            mask = 0x8000
            continue

        bit = flag & mask
        mask >>= 1

        if bit == 0:  # literal: copy one u16 verbatim
            _push2(stream[pos], stream[pos+1] if pos+1 < n else 0)
            pos += 2
        else:          # token
            tok = _read_u16(stream, pos); pos += 2
            count   = tok >> COUNT_SHIFT
            operand = tok & OPERAND_MASK
            if count == 0:
                count = _read_u16(stream, pos); pos += 2
            if operand == 0:
                # zero / transparent fill
                for _ in range(count):
                    if _full(): break
                    _push2(0, 0)
            else:
                # back-reference: operand words = operand*2 bytes back
                src = len(out) - (operand << 1)
                for _ in range(count):
                    if _full(): break
                    if 0 <= src and src + 1 < len(out):
                        _push2(out[src], out[src+1])
                    else:
                        _push2(0, 0)  # before window
                    src += 2


def is_self_contained(stream, expected_words):
    """Check if all back-refs stay within own already-emitted output."""
    n = len(stream)
    pos = 0; mask = 0; flag = 0
    out_words = 0
    while pos + 1 < n:
        if out_words >= expected_words:
            return True
        if mask == 0:
            flag = _read_u16(stream, pos); pos += 2
            mask = 0x8000; continue
        bit = flag & mask; mask >>= 1
        if bit == 0:
            pos += 2; out_words += 1
        else:
            tok = _read_u16(stream, pos); pos += 2
            count = tok >> COUNT_SHIFT
            operand = tok & OPERAND_MASK
            if count == 0:
                count = _read_u16(stream, pos); pos += 2
            if operand != 0:
                src_word = out_words - operand
                if src_word < 0:
                    return False
            out_words += count
    return True


# ─── Blob / part table ────────────────────────────────────────────────────────

def parse_gfx1(gfx1_data):
    """Parse the GFX1 (GFX_DATA_00) offset table.
    Returns list of (blobOffset, blobEnd, header) for each part."""
    n = len(gfx1_data)
    table_bytes = struct.unpack_from('<I', gfx1_data, 0)[0]
    num_parts = table_bytes >> 2
    offsets = [struct.unpack_from('<I', gfx1_data, i*4)[0] for i in range(num_parts)]
    offsets.append(n)  # sentinel
    parts = []
    for i in range(num_parts):
        off = offsets[i]; end = offsets[i+1]
        if off + 4 > n: break
        w, h, sw, sh = gfx1_data[off], gfx1_data[off+1], gfx1_data[off+2], gfx1_data[off+3]
        parts.append({'idx': i, 'off': off, 'end': end, 'w': w, 'h': h, 'sw': sw, 'sh': sh})
    return parts


# ─── Palette ─────────────────────────────────────────────────────────────────

def parse_palette(pal_data):
    """Parse PALETTE_DATA: 16 ARGB4444 LE entries.
    Returns list of 16 (r,g,b,a) tuples, index 0 = transparent."""
    colors = []
    for i in range(min(16, len(pal_data) // 2)):
        v = struct.unpack_from('<H', pal_data, i*2)[0]
        a = ((v >> 12) & 0xF) * 17
        r = ((v >>  8) & 0xF) * 17
        g = ((v >>  4) & 0xF) * 17
        b = ( v        & 0xF) * 17
        colors.append((r, g, b, 0 if i == 0 else a))
    while len(colors) < 16:
        colors.append((255, 0, 255, 0))
    return colors


# ─── Tile-to-image ────────────────────────────────────────────────────────────

def render_part(texels, sw, sh, palette):
    """Convert 4bpp tiled texels to an RGBA PIL Image.
    Tiles are sw*sh in row-major order. Within a tile: y*8+x gives pixel index.
    4bpp packed: two pixels per byte, low nibble = first pixel."""
    pw = sw * 8; ph = sh * 8
    img = Image.new('RGBA', (pw, ph))
    px  = img.load()
    tile_words = 8 * 8 // 2  # bytes per tile (PAL4)

    for ty in range(sh):
        for tx in range(sw):
            tile_idx   = ty * sw + tx
            tile_start = tile_idx * tile_words
            for y in range(8):
                for x in range(8):
                    pix_idx = y * 8 + x
                    byte_off = tile_start + pix_idx // 2
                    if byte_off < len(texels):
                        byte = texels[byte_off]
                        nibble = (byte & 0xF) if (pix_idx & 1) == 0 else ((byte >> 4) & 0xF)
                    else:
                        nibble = 0
                    color = palette[nibble]
                    px[tx*8+x, ty*8+y] = color
    return img


# ─── Segment extraction from PLxx_DAT ────────────────────────────────────────

HEADER_SLOTS = [
    (0x00, 'GFX1'), (0x04, 'GFX2'), (0x08, 'PAL'), (0x0C, 'EXTRAS'),
    (0x14, 'ANIM'), (0x18, 'HITBOX_PAT'), (0x1C, 'HITBOX'),
    (0x20, 'ATTACK'), (0x24, 'AI0'), (0x28, 'AI1'),
    (0x2C, 'AI2'), (0x30, 'AI3'), (0x34, 'AI4'),
]

def get_segment(dat, slot_off):
    """Extract a segment from a PLxx_DAT.BIN by its header slot offset."""
    size = len(dat)
    start = struct.unpack_from('<I', dat, slot_off)[0]
    if start == 0 or start >= size: return None
    ptrs = sorted(p for (o,_) in HEADER_SLOTS
                  for p in [struct.unpack_from('<I', dat, o)[0]]
                  if 0 < p <= size)
    ptrs.append(size)
    end = min(p for p in ptrs if p > start)
    return dat[start:end]


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description='Decode MVC2 PLxx_DAT sprites')
    ap.add_argument('--dat', required=True, help='PLxx_DAT.BIN file')
    ap.add_argument('--part', type=int, default=None, help='Decode specific part index')
    ap.add_argument('--out', default='/tmp', help='Output directory')
    ap.add_argument('--max', type=int, default=50, help='Max parts to decode')
    ap.add_argument('--all-self-contained', action='store_true',
                    help='Decode all self-contained parts (no back-ref underflow)')
    ap.add_argument('--force', action='store_true',
                    help='Decode parts even with back-ref underflow (transparent fill)')
    args = ap.parse_args()

    with open(args.dat, 'rb') as f:
        dat = f.read()
    base = os.path.splitext(os.path.basename(args.dat))[0]

    gfx1_data = get_segment(dat, 0x00)
    pal_data  = get_segment(dat, 0x08)
    if not gfx1_data:
        sys.exit('No GFX1 segment found')

    palette = parse_palette(pal_data) if pal_data else [(i*17,i*17,i*17,255) for i in range(16)]
    parts   = parse_gfx1(gfx1_data)

    os.makedirs(args.out, exist_ok=True)
    print(f'{base}: {len(parts)} parts, GFX1={len(gfx1_data):,}B  PAL={len(pal_data) if pal_data else 0}B')
    print(f'Palette[0..7]: {palette[:8]}')

    targets = []
    if args.part is not None:
        targets = [p for p in parts if p['idx'] == args.part]
        if not targets:
            sys.exit(f'Part {args.part} not found')
    else:
        for p in parts:
            expected_words = p['sw'] * p['sh'] * 32  # 8x8 tile = 64 pix = 32 words PAL4
            stream = gfx1_data[p['off']+4 : p['end']]
            sc = is_self_contained(stream, expected_words)
            p['self_contained'] = sc
            if args.all_self_contained:
                if sc: targets.append(p)
            elif args.force:
                targets.append(p)

        if not args.all_self_contained and not args.force:
            sc_count = sum(1 for p in parts if p.get('self_contained'))
            print(f'Self-contained: {sc_count}/{len(parts)} parts')
            # Default: show first 20 self-contained small parts
            targets = [p for p in parts if p.get('self_contained') and p['sw'] <= 4][:args.max]

    print(f'Decoding {len(targets)} parts...')
    decoded_ok = 0
    for p in targets[:args.max]:
        stream = gfx1_data[p['off']+4 : p['end']]
        max_bytes = p['sw'] * p['sh'] * 8 * 8 // 2  # PAL4: 2 pix/byte
        out = []
        decode_stream(stream, out, max_bytes=max_bytes)
        texels = bytes(out)
        sw, sh = p['sw'], p['sh']
        if sw == 0 or sh == 0: continue

        img = render_part(texels, sw, sh, palette)
        fname = os.path.join(args.out, f'{base}_part{p["idx"]:04d}_{sw*8}x{sh*8}.png')
        img.save(fname)
        sc_str = ' (SC)' if p.get('self_contained') else ''
        print(f'  part[{p["idx"]:4d}] {sw*8}x{sh*8} comp={p["end"]-p["off"]-4}B '
              f'decoded={len(texels)}B{sc_str} -> {fname}')
        decoded_ok += 1

    print(f'Done: {decoded_ok} parts decoded to {args.out}')


if __name__ == '__main__':
    main()
