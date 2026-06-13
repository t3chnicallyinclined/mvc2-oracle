#!/usr/bin/env python3
"""
rip_pldat_segments.py — correct DAT/PAK segment extractor for MVC2 PLxx data.

Replaces the fragile pairwise pointer-walk in dasm_PLDAT_v005a.py, which mis-segments
EXTRAS and ANIMATION on the STRIPPED PAK files (the ones in dasm_PLDAT/PLDATs/*.BIN).

THE BUG IN dasm_PLDAT_v005a.py
------------------------------
`export_data_from_list` treats the 16-entry header as a flat list and pairs each
non-zero pointer with the NEXT non-zero pointer as (start, end), assigning blocks
0,1,2,... in order. That is only valid for a FULL DAT whose pointers are monotonic.

The repo's PLxx_DAT.BIN are actually PLxxPAK.BIN renamed: a STRIPPED pack containing
only GFX1 (+0x00), GFX2 (+0x04), PALETTE (+0x08), EXTRAS (+0x0C). Header +0x10..+0x1C
are 0 (ANIMATION/HITBOX/ATTACK pointers null), but +0x20..+0x3C hold small leftover
values (e.g. 0x17F4). The pairwise walk skips the zeros, then pairs EXTRAS_start
(0x6EB40) with the stray 0x17F4 -> negative length -> EXTRAS extracted as 0 bytes,
and every later block shifts (ANIMATION becomes 89 bytes of garbage, etc.).

THE FIX
-------
1. Read the header by FIXED slot (offset -> block), do not compact zeros.
2. A segment runs from its pointer to the NEXT GREATER valid pointer (or EOF). Ignore
   any header entry whose value is < the segment start or > filesize (the stray
   leftovers). This makes EXTRAS = ptr(+0x0C)..EOF for the stripped PAKs.
3. For a stripped PAK the ANIMATION/HITBOX/ATTACK segments are simply ABSENT; the real
   ANIMATION table is the sibling PLxx_TBL.BIN file (identical to a full DAT's
   ANIMATION segment: 0x000-0x3FF header of u16 durations, 0x400+ u32-LE group table).

Header slot -> block (DAT/PAK):
  +0x00 GFX_DATA_00   +0x04 GFX_DATA_01   +0x08 PALETTE_DATA   +0x0C EXTRAS_DATA
  +0x10 (blank)       +0x14 ANIMATION     +0x18 HITBOX_PATTERN +0x1C HITBOX_DATA
  +0x20 ATTACK_DATA   +0x24..+0x34 AI_SCRIPT_00..04   +0x38/+0x3C blank

USAGE
  python3 tools/rip_pldat_segments.py --in PLxxPAK.BIN --out OUTDIR
  python3 tools/rip_pldat_segments.py --in PLxxPAK.BIN --print   # just list segments
"""
import argparse, os, struct

HEADER = [
    (0x00, "GFX_DATA_00"), (0x04, "GFX_DATA_01"), (0x08, "PALETTE_DATA"),
    (0x0C, "EXTRAS_DATA"), (0x10, None), (0x14, "ANIMATION_DATA"),
    (0x18, "HITBOX_PATTERN_TABLE"), (0x1C, "HITBOX_DATA"), (0x20, "ATTACK_DATA"),
    (0x24, "AI_SCRIPT_DATA_00"), (0x28, "AI_SCRIPT_DATA_01"), (0x2C, "AI_SCRIPT_DATA_02"),
    (0x30, "AI_SCRIPT_DATA_03"), (0x34, "AI_SCRIPT_DATA_04"), (0x38, None), (0x3C, None),
]


def segments(data):
    """Return [(name, start, end)] using fixed-slot header + next-greater-pointer end."""
    size = len(data)
    # collect valid absolute pointers (0 < p <= size) for boundary search
    valid = sorted({struct.unpack_from("<I", data, off)[0]
                    for off, _ in HEADER} | {size})
    valid = [p for p in valid if 0 < p <= size]
    out = []
    for off, name in HEADER:
        if name is None:
            continue
        start = struct.unpack_from("<I", data, off)[0]
        if start == 0 or start > size:
            continue                              # absent in this (stripped) file
        # end = smallest valid pointer strictly greater than start, else EOF
        end = size
        for p in valid:
            if p > start:
                end = p
                break
        out.append((name, start, end))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--out")
    ap.add_argument("--print", dest="show", action="store_true")
    args = ap.parse_args()
    data = open(args.inp, "rb").read()
    base = os.path.splitext(os.path.basename(args.inp))[0]
    segs = segments(data)
    if args.out:
        os.makedirs(args.out, exist_ok=True)
    for name, start, end in segs:
        n = end - start
        print("%-22s 0x%08X .. 0x%08X  %8d bytes" % (name, start, end, n))
        if args.out and n > 0:
            with open(os.path.join(args.out, "%s_%s.BIN" % (base, name)), "wb") as f:
                f.write(data[start:end])


if __name__ == "__main__":
    main()
