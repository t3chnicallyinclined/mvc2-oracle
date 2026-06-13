#!/usr/bin/env python3
"""
bake_hybrid_parts.py — HYBRID part-atlas baker (the Ryu detached-forearm rollout tool).

PROBLEM it solves
-----------------
The deployed PL{HEX}_parts.png is baked OFFLINE (extract_gfx1_atlas.py). For body/torso
parts whose GFX1 header has lw < sw (e.g. PL00 sel 257/278: lw=6, sw=8) the offline LZSS
yields only the logical lw*8 columns — the engine fills the full sw*8 span at runtime from
the live decode scratch (0x0CE60000). Result: columns 6-7 are blank -> a ~26.7px gap ->
the forearm reads as DETACHED. Geometry is correct (validate_emitter_geom.py = 0.70px);
this is a MISSING-PIXELS defect ONLY.

The fix source = live MAPLECAST_PARTDUMP PPMs (the ONLY correct pixel source per the dead
offline-LZSS finding). But a PARTDUMP run is a PARTIAL capture (a sel is only dumped if its
cell rendered during the window), AND a fraction of captured sels are CONTAMINATED by the
0x0CE60000 ping-pong scratch (two selectors sharing one texptr -> the loser reads residue).

DESIGN (monotonic, never-drop, matched-pair)
---------------------------------------------
* The deployed PL{HEX}_parts.png + _parts.json + _asm.json are the BASE. Rects and the
  assembly table are taken verbatim from the base and NEVER changed -> _parts.json/_asm.json
  stay byte-identical, so they remain a matched pair with the new PNG and GEOMETRY is
  provably unaffected (we change PIXELS inside existing rects, not rects).
* For every sel that has a rect in the base atlas:
    - if a live PPM exists for that sel AND it passes the clean-gate (see below) AND its
      decoded dims == the base rect dims -> BLIT the live (detwiddle-inverted) pixels into
      the sel's existing rect, REPLACING the truncated/old pixels.
    - else -> KEEP the base atlas pixels for that rect (no part is ever dropped or blanked).
* Coverage improves MONOTONICALLY: feed the prior hybrid PNG back in as --base on the next
  run and accumulate more captures; clean live pixels only ever overwrite, never remove.

CLEAN-GATE (reject scratch-contaminated captures)
-------------------------------------------------
A captured sel is accepted only if its decoded pixels match the current base atlas crop by
>= --clean-thresh (default 0.55) opaque-RGB agreement, OR it is a known full-span body part
being intentionally extended (--force-sel). The rationale: a clean capture of an UN-truncated
part is ~identical to base; a clean capture of a TRUNCATED body part agrees on the lw*8 cols
it shares (>=0.55 for lw=6/sw=8 = 6/8 cols) and legitimately ADDS cols 6-7; a scratch-residue
capture agrees on neither and scores far lower (<0.50, empirically 0.19-0.48 on the
2026-06-11 Ryu run). Tune --clean-thresh per run; the --report flag prints every sel's score
so the operator can audit the gate before committing the PNG.

The detwiddle is the EXACT flycast non-square inversion (partdump_detwiddle.detwiddle_linear_ppm),
since the per-frame PARTDUMP writes the PPM linear=true from the TWIDDLED planar scratch
(maplecast_gamestate.cpp:1366).

Usage:
  python3 tools/bake_hybrid_parts.py \
      --base   web/test-atlas/chars \
      --char   PL00 \
      --realparts _ryu_capture/partdump_20260611 \
      --out    _atlas_out/PL00_hybrid \
      --clean-thresh 0.55 --report
  # then validate: python3 tools/validate_emitter_geom.py   (still 0.70px — rects unchanged)
  # then (operator, gated): scp the matched trio to prod test-atlas/chars (NEVER king.html).
"""
import argparse, json, os, sys, re
import importlib.util
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "_ryu_capture"))
import partdump_detwiddle as pdw  # exact flycast non-square twiddle inversion

MAGENTA = (255, 0, 255)


def read_ppm(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:2] != b"P6":
        return None
    idx, toks = 2, []
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
    w, h, _ = toks
    return w, h, data[idx:idx + w * h * 3]


def opaque_match(live_img, base_crop):
    """Fraction of pixels whose opacity agrees and (where both opaque) RGB matches."""
    pa, pb = live_img.load(), base_crop.load()
    W, H = base_crop.size
    same = tot = 0
    for y in range(H):
        for x in range(W):
            ca, cb = pa[x, y], pb[x, y]
            ao, bo = ca[3] > 0, cb[3] > 0
            tot += 1
            if ao != bo:
                continue
            if not ao:
                same += 1
            elif ca[:3] == cb[:3]:
                same += 1
    return same / tot if tot else 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True, help="dir with deployed PL{HEX}_parts.{png,json} + _asm.json")
    ap.add_argument("--char", required=True)
    ap.add_argument("--realparts", required=True, help="dir of MAPLECAST_PARTDUMP PL{HEX}_part_NNN.ppm")
    ap.add_argument("--out", required=True, help="output dir for the hybrid trio")
    ap.add_argument("--clean-thresh", type=float, default=0.55)
    ap.add_argument("--force-sel", default="", help="comma sels to accept regardless of score (audited)")
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()

    hexn = args.char.upper()
    base_png = os.path.join(args.base, f"{hexn}_parts.png")
    base_parts = os.path.join(args.base, f"{hexn}_parts.json")
    base_asm = os.path.join(args.base, f"{hexn}_asm.json")
    atlas = Image.open(base_png).convert("RGBA")
    parts = json.load(open(base_parts))           # {sel:{x,y,w,h}}  (matched-pair: copied verbatim)
    force = {int(s) for s in args.force_sel.split(",") if s.strip()}

    cap = {}
    for f in os.listdir(args.realparts):
        m = re.match(rf"{hexn}_part_(\d+)\.ppm$", f)
        if m:
            cap[int(m.group(1))] = os.path.join(args.realparts, f)

    os.makedirs(args.out, exist_ok=True)
    replaced, kept_base, dim_skip, dirty_skip = [], 0, [], []
    rows = []
    for sel_s, rect in parts.items():
        sel = int(sel_s)
        if sel not in cap:
            kept_base += 1
            continue
        got = read_ppm(cap[sel])
        if not got:
            kept_base += 1
            continue
        w, h, px = got
        if (w, h) != (rect["w"], rect["h"]):
            dim_skip.append((sel, (w, h), (rect["w"], rect["h"])))
            kept_base += 1
            continue
        live = Image.frombytes("RGBA", (w, h), pdw.detwiddle_linear_ppm(px, w, h))
        crop = atlas.crop((rect["x"], rect["y"], rect["x"] + w, rect["y"] + h))
        score = opaque_match(live, crop)
        rows.append((sel, w, h, score))
        if score >= args.clean_thresh or sel in force:
            atlas.alpha_composite(_blank(w, h), (rect["x"], rect["y"]))  # clear rect first
            atlas.alpha_composite(live, (rect["x"], rect["y"]))
            replaced.append(sel)
        else:
            dirty_skip.append((sel, round(score, 3)))
            kept_base += 1

    # write the matched trio: NEW png, VERBATIM parts.json + asm.json (byte-identical copies)
    out_png = os.path.join(args.out, f"{hexn}_parts.png")
    atlas.save(out_png)
    with open(os.path.join(args.out, f"{hexn}_parts.json"), "w") as f:
        json.dump(parts, f)
    with open(base_asm) as f:
        asm_bytes = f.read()
    with open(os.path.join(args.out, f"{hexn}_asm.json"), "w") as f:
        f.write(asm_bytes)   # byte-identical -> rects/asm stay a matched pair, geometry unchanged

    if args.report:
        print(f"{'sel':>4} {'wxh':>9} {'score':>6}  decision")
        for sel, w, h, sc in sorted(rows):
            dec = "REPLACE (live)" if (sc >= args.clean_thresh or sel in force) else "keep base (dirty)"
            print(f"{sel:>4} {f'{w}x{h}':>9} {sc:6.0%}  {dec}")
    print(f"\nhybrid bake {hexn}: {len(replaced)} sels replaced w/ live, {kept_base} kept base")
    print(f"  replaced: {sorted(replaced)}")
    if dirty_skip:
        print(f"  dirty (kept base): {dirty_skip}")
    if dim_skip:
        print(f"  dim-mismatch (kept base): {dim_skip}")
    print(f"  -> {out_png}  + matched _parts.json/_asm.json (verbatim)")


def _blank(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


if __name__ == "__main__":
    main()
