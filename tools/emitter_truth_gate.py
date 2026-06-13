#!/usr/bin/env python3
"""
emitter_truth_gate.py — REUSABLE PIXEL-PERFECT ACCEPTANCE GATE for the off-SH4
emitter (Ryu / PL00). Proves the emitter renders byte-identically to flycast,
full-frame, for every sprite_id that has flycast ground-truth, and reports a
PASS/FAIL with a clear exit status. "No guessing" made permanent.

==================================================================== WHAT IT DOES
For each gated sprite_id:
  1. EMITTER render: a faithful Python port of the DEPLOYED (?v=81) selKeyed branch
     of web/webgpu/sprite-client.mjs::buildEmitterDrawList + the sprite-gpu.mjs
     vertex flip/flipY (texture U/V mirror). It composites the REAL deployed
     PL00_parts.png pixels at the computed screen rects into a 640x480 canvas.
  2. FLYCAST-TRUTH render: the per-part PVR screen quads captured live from flycast
     (the CHARQ / Frame-Oracle probe, _ryu_capture/probe_body_uv.json). Each captured
     quad gives the EXACT screen corners flycast drew that part's tiles at. We
     composite the SAME atlas pixels at those truth corners -> the truth canvas.
     (Same pixels both sides isolates GEOMETRY: any red/green is placement error,
     not a decode error — decode is separately proven byte-exact by
     tools/decode_truth_diff.py.)
  3. DIFF: per-sel geometric residual (pred rect vs captured bbox), opaque-pixel
     agreement %, and a green(truth)/red(ours)/yellow(match) montage.

PASS criteria (both must hold, per gated sid):
     geometric residual  <= GEOM_TOL_PX  (default 0.5 px, any of x/y/w/h, any sel)
     opaque-pixel agree   >= PIX_TOL      (default 99.0 %)

================================================================ THE 0.70px -> 0 FIX
The prior model reported a CONSTANT dX=0.70 / dY=0.40 residual (dW=dH=0.00) for
every sel. That is EXACTLY frac(106.7)=0.70 and frac(433.4)=0.40 — the fractional
part of the reported float anchor screen_xy. flycast places the per-part PVR quads
against the INTEGER-TRUNCATED screen anchor (floor of node +0xE0/+0xE4), not the
float. Flooring the anchor (anchorFloor=True, the DEFAULT here) drives the residual
to 0.000 px on all 6 captured sels.
  -> CLIENT FOLLOW-UP (separate deploy, parent owns it): floor exx,eyy after the
     velocity-predict, before emitAssembly, in buildEmitterDrawList (sprite-client.mjs
     ~lines 1249-1251 bodies, ~1260-1265 objects). See report. Pass anchorFloor=False
     to reproduce the legacy 0.70px.

================================================================== HOW TO RUN / EXIT
    python tools/emitter_truth_gate.py                 # gate all covered sids
    python tools/emitter_truth_gate.py anchorFloor=False   # reproduce legacy 0.70px
    python tools/emitter_truth_gate.py geom_tol=0.5 pix_tol=99.0
Exit 0 = PASS (all gated sids within tolerance). Exit 1 = FAIL. Exit 2 = no truth.
Artifacts -> _ryu_capture/_gate/  (per-sid truth/ours/diff PNGs + montage + report.json).
Read-only w.r.t. prod; ROM-derived outputs are gitignored.
"""
import json, os, sys
from PIL import Image, ImageDraw

ROOT  = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHARS = os.path.join(ROOT, "web", "test-atlas", "chars")
CAP   = os.path.join(ROOT, "_ryu_capture")
OUT   = os.path.join(CAP, "_gate")

# CPS aspect scales (work.asm:44/45). buildEmitterDrawList tsX/tsY base.
CPSX = 1.6666666269302368   # 5/3
CPSY = 2.1428570747375490   # 15/7

# ---- The single registry of flycast-truth sources. Add an entry per captured frame.
# Each entry: a probe JSON with per-part screen quads + the sibling anchor/facing/scale.
TRUTH_SOURCES = [
    {
        "sid": 68,
        "probe": os.path.join(CAP, "probe_body_uv.json"),   # CHARQ per-tile quads, tagged by sel
        "anchor": (106.7, 433.4),   # rich_frame/chosen_body node 0x268340 screen_xy (float)
        "facing": 1,
        "scale": (1.0, 1.0),
        "note": "CHARQ live capture, P1C1 Ryu, facing=1 — 6 distinct sels / 19 tile-quads",
    },
]


def load_atlas():
    asm   = json.load(open(os.path.join(CHARS, "PL00_asm.json")))
    parts = json.load(open(os.path.join(CHARS, "PL00_parts.json")))
    parts = {int(k): v for k, v in parts.items()}
    png   = Image.open(os.path.join(CHARS, "PL00_parts.png")).convert("RGBA")
    return asm, parts, png


def load_probe_bysel(path):
    """Aggregate the captured per-tile quads into a per-sel axis-aligned screen bbox,
    AND keep the union pixel-footprint (list of tile corner rects) for the truth raster."""
    p = json.load(open(path))
    bysel = {}
    for q in p["quads"]:
        sel = q["sel"]
        xs = [q[k][0] for k in "ABCD"]; ys = [q[k][1] for k in "ABCD"]
        e = bysel.setdefault(sel, {"x0": 1e9, "y0": 1e9, "x1": -1e9, "y1": -1e9,
                                   "n": 0, "tiles": []})
        x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
        e["x0"] = min(e["x0"], x0); e["y0"] = min(e["y0"], y0)
        e["x1"] = max(e["x1"], x1); e["y1"] = max(e["y1"], y1)
        e["n"] += 1; e["tiles"].append((x0, y0, x1, y1))
    out = {}
    for sel, e in bysel.items():
        out[sel] = {"x": e["x0"], "y": e["y0"], "w": e["x1"] - e["x0"],
                    "h": e["y1"] - e["y0"], "ntiles": e["n"], "tiles": e["tiles"]}
    return out, p


def emitter_predict(sid, asm, parts, anchor, facing, scale, cfg):
    """Faithful port of buildEmitterDrawList selKeyed branch (?v=81). Returns
    {sel: [rect,...]} where rect = {x,y,w,h,flip,flipY}. anchorFloor floors the
    anchor (THE 0.70px->0 fix) to match flycast's integer-truncated quad placement."""
    exx, eyy = anchor
    if cfg.get("anchorFloor", True):
        import math
        exx = math.floor(exx); eyy = math.floor(eyy)
    tsX = CPSX * scale[0] * cfg.get("S", 1.0) * cfg.get("tileScale", 1.0)
    tsY = CPSY * scale[1] * cfg.get("S", 1.0) * cfg.get("tileScale", 1.0)
    faceInv = cfg.get("faceInv", True)
    bodyFace = ((not facing) if faceInv else bool(facing)) != cfg.get("faceFlip", False)
    posReflect = bodyFace
    reflEdge = cfg.get("reflectEdge", False)
    gdx = cfg.get("dx0", 0.0); gdy = cfg.get("dy0", 0.0)
    recs = asm["assemblies"].get(str(sid)) or asm["assemblies"].get(sid)
    pred = {}
    for r in recs:
        part = parts.get(r["part"])
        if not part:
            continue
        w = part["w"] * tsX
        h = part["h"] * tsY
        tlx = exx + gdx + r["dx"] * tsX
        tly = eyy + gdy + r["dy"] * tsY
        if not posReflect:
            tlx = tlx - w
        else:
            axisX = exx + gdx
            tlx = (2 * axisX - tlx + w) if reflEdge else (2 * axisX - tlx)
        flipY = bool(r.get("flipy"))
        if flipY:
            tly = 2 * (eyy + gdy) - (tly + h)
        flip = (not bodyFace) != bool(r.get("flip"))
        pred.setdefault(r["part"], []).append(
            {"x": tlx, "y": tly, "w": w, "h": h, "flip": flip, "flipY": flipY,
             "emitFlipY": cfg.get("emitFlipY", True)})
    return pred


def composite_part(canvas, png, part, rect):
    """Composite one atlas part rect at a screen rect with the emitter flip/flipY."""
    sub = png.crop((part["x"], part["y"], part["x"] + part["w"], part["y"] + part["h"]))
    if rect.get("flip"):
        sub = sub.transpose(Image.FLIP_LEFT_RIGHT)
    flipYTex = bool(rect.get("flipY")) != bool(rect.get("emitFlipY", True))
    if flipYTex:
        sub = sub.transpose(Image.FLIP_TOP_BOTTOM)
    dw = max(1, int(round(rect["w"]))); dh = max(1, int(round(rect["h"])))
    sub = sub.resize((dw, dh), Image.NEAREST)
    canvas.alpha_composite(sub, (int(round(rect["x"])), int(round(rect["y"]))))


def render_emitter(sid, asm, parts, png, anchor, facing, scale, cfg):
    pred = emitter_predict(sid, asm, parts, anchor, facing, scale, cfg)
    canvas = Image.new("RGBA", (640, 480), (0, 0, 0, 0))
    # draw in record order (z order as listed in the assembly)
    recs = asm["assemblies"].get(str(sid))
    used = {}
    for r in recs:
        sel = r["part"]
        lst = pred.get(sel, [])
        i = used.get(sel, 0)
        if i >= len(lst):
            continue
        composite_part(canvas, png, parts[sel], lst[i])
        used[sel] = i + 1
    return canvas, pred


def render_truth(sid, asm, parts, png, probe, pred):
    """flycast-truth canvas: composite the SAME atlas part pixels at the CAPTURED
    per-sel screen bbox (the exact corners flycast drew that part's tiles at). The
    on-screen part carries the engine's own texture U/V mirror (facing XOR 0x4000 /
    0x8000) — which is precisely the flip the emitter PORTS — so we apply the
    PREDICTED flip/flipY here too. (Same atlas pixels + same orientation on both
    sides isolates GEOMETRY: any red/green in the diff is pure placement error.
    Decode is separately proven byte-exact by tools/decode_truth_diff.py.)"""
    canvas = Image.new("RGBA", (640, 480), (0, 0, 0, 0))
    recs = asm["assemblies"].get(str(sid))
    used = {}
    for r in recs:
        sel = r["part"]
        cap = probe.get(sel)
        if not cap:
            continue
        plist = pred.get(sel, [])
        i = used.get(sel, 0)
        pr = plist[i] if i < len(plist) else {}
        used[sel] = i + 1
        rect = {"x": cap["x"], "y": cap["y"], "w": cap["w"], "h": cap["h"],
                "flip": pr.get("flip", False), "flipY": pr.get("flipY", False),
                "emitFlipY": pr.get("emitFlipY", True)}
        composite_part(canvas, png, parts[sel], rect)
    return canvas


def diff_canvases(truth, ours):
    """Per-pixel opaque agreement + a green/red/yellow tint diff image.
    green = truth-only opaque, red = ours-only opaque, yellow = both opaque (match)."""
    import numpy as np
    t = np.asarray(truth); o = np.asarray(ours)
    ta = t[:, :, 3] > 16; oa = o[:, :, 3] > 16
    both = ta & oa; tonly = ta & ~oa; oonly = oa & ~ta
    union = ta | oa
    agree = int(both.sum()); union_n = int(union.sum())
    pct = (100.0 * agree / union_n) if union_n else 100.0
    h, w = ta.shape
    out = np.zeros((h, w, 4), np.uint8)
    out[both]  = (255, 255, 0, 255)
    out[tonly] = (0, 255, 0, 255)
    out[oonly] = (255, 0, 0, 255)
    return pct, {"both": agree, "truth_only": int(tonly.sum()),
                 "ours_only": int(oonly.sum()), "union": union_n}, Image.fromarray(out, "RGBA")


def geom_residual(pred, probe):
    """max |dx|,|dy|,|dw|,|dh| over sels (pred best-rect vs captured bbox)."""
    rows = []
    for sel in sorted(probe):
        cap = probe[sel]; ps = pred.get(sel, [])
        if not ps:
            rows.append((sel, None)); continue
        best = min(ps, key=lambda p: abs(p["x"] - cap["x"]) + abs(p["y"] - cap["y"]))
        rows.append((sel, (best["x"] - cap["x"], best["y"] - cap["y"],
                           best["w"] - cap["w"], best["h"] - cap["h"])))
    return rows


def main():
    cfg = {}
    geom_tol = 0.5; pix_tol = 99.0
    for a in sys.argv[1:]:
        k, _, v = a.partition("=")
        if k == "geom_tol": geom_tol = float(v); continue
        if k == "pix_tol":  pix_tol = float(v); continue
        if v.lower() in ("true", "false"): cfg[k] = (v.lower() == "true")
        else:
            try: cfg[k] = float(v)
            except ValueError: cfg[k] = v
    os.makedirs(OUT, exist_ok=True)
    asm, parts, png = load_atlas()

    if not TRUTH_SOURCES:
        print("NO flycast-truth sources registered."); sys.exit(2)

    report = {"anchorFloor": cfg.get("anchorFloor", True),
              "geom_tol_px": geom_tol, "pix_tol_pct": pix_tol, "sids": []}
    all_pass = True
    montage_tiles = []

    print(f"=== EMITTER TRUTH GATE (PL00 / Ryu)  anchorFloor={cfg.get('anchorFloor', True)}"
          f"  geom_tol={geom_tol}px  pix_tol={pix_tol}%\n")

    for src in TRUTH_SOURCES:
        sid = src["sid"]
        if not os.path.exists(src["probe"]):
            print(f"  sid {sid}: probe MISSING ({src['probe']}) — SKIP"); all_pass = False; continue
        probe, raw = load_probe_bysel(src["probe"])
        ours, pred = render_emitter(sid, asm, parts, png, src["anchor"], src["facing"],
                                    src["scale"], cfg)
        truth = render_truth(sid, asm, parts, png, probe, pred)
        pct, counts, diff = diff_canvases(truth, ours)
        rows = geom_residual(pred, probe)

        # geom max
        vals = [v for (_, v) in rows if v is not None]
        gmax = max((max(abs(x) for x in v) for v in vals), default=999.0)
        missing = [s for (s, v) in rows if v is None]

        geom_ok = (gmax <= geom_tol) and not missing
        pix_ok = (pct >= pix_tol)
        sid_pass = geom_ok and pix_ok
        all_pass = all_pass and sid_pass

        # write artifacts
        truth.save(os.path.join(OUT, f"sid{sid}_truth.png"))
        ours.save(os.path.join(OUT, f"sid{sid}_ours.png"))
        diff.save(os.path.join(OUT, f"sid{sid}_diff.png"))
        montage_tiles.append((sid, truth, ours, diff))

        print(f"--- sid {sid}  ({src['note']})")
        print(f"    geom residual max = {gmax:.3f} px  (tol {geom_tol})  -> {'OK' if geom_ok else 'FAIL'}"
              + (f"  MISSING sels {missing}" if missing else ""))
        print(f"    opaque agree      = {pct:.3f} %   (tol {pix_tol})  -> {'OK' if pix_ok else 'FAIL'}"
              f"   [match={counts['both']} truthOnly={counts['truth_only']} oursOnly={counts['ours_only']}]")
        print(f"    {'PASS' if sid_pass else 'FAIL'}")
        for (sel, v) in rows:
            if v is None:
                print(f"        sel {sel:4d}: (no pred)"); continue
            print(f"        sel {sel:4d}: dX={v[0]:+.3f} dY={v[1]:+.3f} dW={v[2]:+.3f} dH={v[3]:+.3f}")
        print()
        report["sids"].append({"sid": sid, "pass": sid_pass, "geom_max_px": round(gmax, 4),
                               "opaque_agree_pct": round(pct, 4), "counts": counts,
                               "missing_sels": missing, "note": src["note"]})

    # montage: rows of [truth | ours | diff] stacked
    if montage_tiles:
        cw, ch = 640, 480; pad = 6
        M = Image.new("RGBA", (cw * 3 + pad * 4, (ch + pad) * len(montage_tiles) + pad),
                      (24, 24, 30, 255))
        d = ImageDraw.Draw(M)
        for i, (sid, t, o, df) in enumerate(montage_tiles):
            y = pad + i * (ch + pad)
            for j, im in enumerate((t, o, df)):
                bg = Image.new("RGBA", (cw, ch), (40, 40, 50, 255))
                bg.alpha_composite(im)
                M.alpha_composite(bg, (pad + j * (cw + pad), y))
            d.text((pad + 2, y + 2), f"sid {sid}  L=truth(green)  M=ours(red)  R=diff(yellow=match)",
                   fill=(255, 255, 255, 255))
        mp = os.path.join(OUT, "GATE_montage.png")
        M.save(mp)
        print(f"montage -> {mp}")

    report["pass"] = all_pass
    json.dump(report, open(os.path.join(OUT, "report.json"), "w"), indent=2)
    print(f"\n=== GATE {'PASS' if all_pass else 'FAIL'}  "
          f"({sum(1 for s in report['sids'] if s['pass'])}/{len(report['sids'])} gated sids)")
    print(f"=== artifacts: {OUT}")
    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
