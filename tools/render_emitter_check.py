#!/usr/bin/env python3
"""
render_emitter_check.py — VISUAL render of the off-SH4 emitter selKeyed branch,
a faithful Python port of web/webgpu/sprite-client.mjs buildEmitterDrawList +
the sprite-gpu.mjs vertex-shader flip/flipY (texture U/V mirror). Composites the
REAL PL00_parts.png pixels at the computed screen rects so the operator can SEE
default facing + per-part side consistency. Read-only; no atlas/tool edits.

Geometry == validate_emitter_geom.py (the 0.70px-validated model). The ONLY thing
this adds is the texture flip applied to actual pixels (PIL transpose) and a
640x480 composite.
"""
import json, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHARS = os.path.join(ROOT, "web", "test-atlas", "chars")
CPSX = 1.6666666269302368
CPSY = 2.1428570747375490

def load():
    asm = json.load(open(os.path.join(CHARS, "PL00_asm.json")))
    parts = json.load(open(os.path.join(CHARS, "PL00_parts.json")))
    parts = {int(k): v for k, v in parts.items()}
    png = Image.open(os.path.join(CHARS, "PL00_parts.png")).convert("RGBA")
    return asm, parts, png

def render(sid, facing, anchor=(106.7, 433.4), scale=(1.0, 1.0),
           faceInv=True, faceFlip=False, emitFlipY=True, tileScale=1.0, S=1.0,
           reflEdge=False, partFlipX=True):
    asm, parts, png = load()
    exx, eyy = anchor
    pcX = CPSX * scale[0] * S
    pcY = CPSY * scale[1] * S
    tsX = pcX * tileScale
    tsY = pcY * tileScale
    bodyFace = ((not facing) if faceInv else bool(facing)) != faceFlip
    F = bodyFace
    posReflect = F
    recs = asm["assemblies"].get(str(sid)) or asm["assemblies"].get(sid)
    if not recs:
        print(f"sid {sid}: MISSING"); return None
    canvas = Image.new("RGBA", (640, 480), (30, 30, 40, 255))
    # draw anchor line (magenta)
    for yy in range(480):
        if 0 <= int(round(exx)) < 640:
            canvas.putpixel((int(round(exx)), yy), (255, 0, 255, 255))
    quads = []
    for r in recs:
        part = parts.get(r["part"])
        if not part:
            continue
        w = part["w"] * tsX
        h = part["h"] * tsY
        # FACING FIX 2026-06-11: texture-U mirror follows RAW ROM `facing XOR 0x4000`,
        # decoupled from posReflect (= !F XOR r.flip, with F=!facing => facing XOR r.flip).
        flip = (not F) != bool(r.get("flip"))
        flipY = bool(r.get("flipy"))
        tlx = exx + r["dx"] * tsX
        tly = eyy + r["dy"] * tsY
        if not posReflect:
            tlx = tlx - w
        else:
            axisX = exx
            tlx = (2 * axisX - tlx + w) if reflEdge else (2 * axisX - tlx)
        # PER-PART X-MIRROR GEOMETRY (0x4000) — BUG 2 FIX 2026-06-11. Mirror the rect
        # across the owner anchor when r.flip is set, in symmetry with flipY (Y-mirror)
        # below. No-op when r.flip=0 (idle sids unchanged). partFlipX=False = pre-fix
        # (texture-only) for A/B.
        if partFlipX and r.get("flip"):
            tlx = 2 * exx - (tlx + w)
        if flipY:
            tly = 2 * eyy - (tly + h)
        flipYTex = (flipY != emitFlipY)
        quads.append((r["part"], tlx, tly, w, h, flip, flipYTex, r["dx"]))
    # composite back-to-front (recs already in z order as listed)
    for (sel, tlx, tly, w, h, flip, flipYTex, dx) in quads:
        p = parts[sel]
        sub = png.crop((p["x"], p["y"], p["x"] + p["w"], p["y"] + p["h"]))
        if flip:
            sub = sub.transpose(Image.FLIP_LEFT_RIGHT)
        if flipYTex:
            sub = sub.transpose(Image.FLIP_TOP_BOTTOM)
        dw = max(1, int(round(w))); dh = max(1, int(round(h)))
        sub = sub.resize((dw, dh), Image.NEAREST)
        canvas.alpha_composite(sub, (int(round(tlx)), int(round(tly))))
    return canvas, quads, exx

def main():
    sid = int(sys.argv[1]) if len(sys.argv) > 1 else 62
    tag = sys.argv[2] if len(sys.argv) > 2 else "out"
    kw = {}
    for a in sys.argv[3:]:
        k, _, v = a.partition("=")
        if v.lower() in ("true", "false"):
            kw[k] = v.lower() == "true"
        else:
            try: kw[k] = float(v)
            except ValueError: kw[k] = v
    for facing in (1, 0):
        res = render(sid, facing, **kw)
        if not res: continue
        canvas, quads, exx = res
        fn = os.path.join(ROOT, f"_emitter_render_sid{sid}_face{facing}_{tag}.png")
        canvas.save(fn)
        print(f"\n=== sid {sid} facing={facing} ({tag}) anchor_x={exx:.1f} -> {os.path.basename(fn)}")
        for (sel, tlx, tly, w, h, flip, flipYTex, dx) in quads:
            cx = tlx + w / 2
            side = "R" if cx > exx else "L"
            print(f"   sel {sel:4d} dx={dx:4d} x[{tlx:6.1f}..{tlx+w:6.1f}] cx={cx:6.1f} {side}  texFlip={'X' if flip else '.'}")

if __name__ == "__main__":
    main()
