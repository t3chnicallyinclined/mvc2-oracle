#!/usr/bin/env python3
"""
validate_emitter_geom.py — NUMERIC per-part validation of the off-SH4 emitter's
reconstructed body geometry against the SH4's ACTUAL captured per-part quads.

GROUND TRUTH: _ryu_capture/probe_body_uv.json — the CHARQ live-Oracle capture of
node 0x8C268340 (P1C1 Ryu), 19 per-TILE PVR quads with screen corners A/B/C/D, each
tagged with its GFX2 +6 selector (`sel`). The owner anchor / facing / scale for that
node come from the sibling capture (rich_frame.json / chosen_body.json):
    screen_xy = [106.7, 433.4]   facing = 1   scale = [1.0, 1.0]

EMITTER MODEL (faithful port of web/webgpu/sprite-client.mjs buildEmitterDrawList
selKeyed branch, defaults ?v=74). For sprite_id -> GFX2 cell records (dx,dy,FLAGS,sel):
    cumulative pen baked FACING-NEUTRAL (rip: Xacc+=dx, Yacc-=dy)  [stored in PL00_asm.json assemblies]
    tsX = CPSX * zoom * S * tileScale     tsY = CPSY * zoom * S * tileScale
    tlx = exx + r.dx*tsX ;  tly = eyy + r.dy*tsY
    w   = part.w*tsX     ;  h   = part.h*tsY
    bodyFace  = faceInv ? !facing : facing        (faceInv default TRUE)
    posReflect= bodyFace                          -> tlx = 2*exx - tlx
    flipY(0x8000): tly = 2*eyy - (tly+h)
The emitter draws ONE quad per SEL (the whole multi-tile part blob). The live probe
draws ONE quad per 8x8/16x16 TILE, so a sel maps to a GROUP of probe quads. We
therefore aggregate the probe quads BY SEL into a bounding box and compare against
the emitter's single per-sel predicted rect.

DISASM ground (bank03 loc_8c0344d4, _marv/build/bank03.asm):
    anchor X/Y @ node+0x00E0/0x00E4   (loc_8c034602/04)
    scale  X/Y @ node+0x00EC/0x00F0   (loc_8c03460c/0e ; loc_8c0346f4/f6)
    pen seed   @ node+0x0134/0x0136   (loc_8c034608/0a) ; neg r10 when facing!=0
    final: screen = anchor + (pen+tile)*scale  ; X-mirror 0x4000, Y-mirror 0x8000
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CPSX = 1.6666666269302368   # work.asm:44  CpsXScale 5/3
CPSY = 2.1428570747375490   # work.asm:45  CpsYScale 15/7

def load_probe():
    p = json.load(open(os.path.join(ROOT, "_ryu_capture", "probe_body_uv.json")))
    # aggregate quads by sel -> screen bounding box (axis-aligned over A/B/C/D)
    bysel = {}
    for q in p["quads"]:
        sel = q["sel"]
        xs = [q["A"][0], q["B"][0], q["C"][0], q["D"][0]]
        ys = [q["A"][1], q["B"][1], q["C"][1], q["D"][1]]
        bb = bysel.setdefault(sel, [1e9, 1e9, -1e9, -1e9, 0])
        bb[0] = min(bb[0], min(xs)); bb[1] = min(bb[1], min(ys))
        bb[2] = max(bb[2], max(xs)); bb[3] = max(bb[3], max(ys)); bb[4] += 1
    out = {}
    for sel, (x0, y0, x1, y1, n) in bysel.items():
        out[sel] = {"x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0, "ntiles": n}
    return out, p

def load_asm():
    a = json.load(open(os.path.join(ROOT, "web", "test-atlas", "chars", "PL00_asm.json")))
    return a

def load_baked_parts():
    """The ACTUAL deployed atlas rects (sel -> {x,y,w,h}). After the 2026-06-11 full-span
    baker fix these w/h ARE the full tile span (sw*8 x sh*8); pre-fix they were the logical
    crop. The validator reads these verbatim — NO hardcoded dim override — so a 0.00px result
    here proves the BAKED atlas (not a model fudge) matches the live engine."""
    p = json.load(open(os.path.join(ROOT, "web", "test-atlas", "chars", "PL00_parts.json")))
    return {int(k): v for k, v in p.items()}

def emitter_predict(sid, asm, parts_dims, anchor, facing, scale, cfg):
    """Faithful port of buildEmitterDrawList selKeyed branch. Returns {sel:[rects...]}.
    A sel can appear in MULTIPLE records of one assembly -> list of predicted rects.
    `parts_dims` = the BAKED PL00_parts.json rects (sel -> {x,y,w,h}); the part SCREEN
    size = part.w*tsX x part.h*tsY straight from the atlas — NO dim override. With the
    full-span baker the multi-tile sels now carry sw*8 x sh*8, so this is exact."""
    exx, eyy = anchor
    # ANCHOR-FLOOR FIX (2026-06-11, tools/emitter_truth_gate.py): flycast places the
    # per-part PVR quads against the INTEGER-TRUNCATED screen anchor (floor of node
    # +0xE0/+0xE4), not the float. The old constant dX=0.70/dY=0.40 residual was
    # EXACTLY frac(106.7)/frac(433.4). Flooring drives the residual to 0.000 px.
    # Pass anchorFloor=false to reproduce the legacy 0.70px.
    if cfg.get("anchorFloor", True):
        import math
        exx = math.floor(exx); eyy = math.floor(eyy)
    zoomX = scale[0]; zoomY = scale[1]
    tileScale = cfg.get("tileScale", 1.0)
    S = cfg.get("S", 1.0)
    tsX = CPSX * zoomX * S * tileScale
    tsY = CPSY * zoomY * S * tileScale
    faceInv = cfg.get("faceInv", True)
    bodyFace = (not facing) if faceInv else bool(facing)
    posReflect = bodyFace            # _emitFaceFlip default false
    reflEdge = cfg.get("reflectEdge", False)
    gdx = cfg.get("dx0", 0.0); gdy = cfg.get("dy0", 0.0)
    recs = asm["assemblies"].get(str(sid)) or asm["assemblies"].get(sid)
    pred = {}
    for r in recs:
        part = parts_dims.get(r["part"]) or parts_dims.get(str(r["part"]))
        if not part:
            continue
        w = part["w"] * tsX        # BAKED atlas dims (full tile span post-fix) — no override
        h = part["h"] * tsY
        tlx = exx + gdx + r["dx"] * tsX     # ax0/ay0 part residual = 0 in this atlas
        tly = eyy + gdy + r["dy"] * tsY
        flipY = bool(r.get("flipy"))
        # X PLACEMENT (validated 2026-06-11): with the pen negated by facing the part
        # extends LEFT of the pen point, so tlx -= w for the validated facing (bodyFace
        # false). The opposite facing mirrors the rect across the anchor.
        # tlx here = the PEN POINT (exx+gdx+dx*tsX). Validated facing: part RIGHT edge sits
        # at the pen, so left = pen - w. Reflected facing (disasm loc_8c034548 neg r10 =
        # negate the pen ORIGIN only): the pen point mirrors across axisX and the part
        # extends RIGHT, so its LEFT edge sits AT the mirrored pen: tlx = 2A - pen. There is
        # NO +/-w on reflection (width enters via the tile span IDENTICALLY in both branches);
        # the old guess 2A-pen+w injected a spurious +w = one full part-width offset.
        if not posReflect:
            tlx = tlx - w
        else:
            axisX = exx + gdx
            tlx = 2 * axisX - tlx if not reflEdge else (2 * axisX - tlx + w)
        if flipY:
            tly = 2 * (eyy + gdy) - (tly + h)
        # TEXTURE U-mirror (facing fix 2026-06-11): the U-mirror follows the RAW ROM rule
        # `texU = facing XOR 0x4000`, DECOUPLED from posReflect (the calibrated position form
        # absorbs facing into the baked pen). With bodyFace = !facing, (not bodyFace) == facing,
        # so this == facing XOR r.flip — a literal port of bank03 neg r8. The geometry residual
        # (the gate) is independent of this; it is reported for documentation.
        flip = (not bodyFace) != bool(r.get("flip"))
        pred.setdefault(r["part"], []).append(
            {"x": tlx, "y": tly, "w": w, "h": h, "flip": flip, "flipY": flipY})
    return pred

def main():
    asm = load_asm()
    parts_dims = load_baked_parts()      # the ACTUAL deployed atlas rects — no dim override
    probe, raw = load_probe()
    SID = 68
    anchor = (106.7, 433.4)   # rich_frame.json node 0x268340 screen_xy
    facing = 1
    scale = (1.0, 1.0)
    # NO hardcoded full-span override anymore: the baked PL00_parts.json now carries the
    # full tile span (sw*8 x sh*8) for every sel after the 2026-06-11 baker fix, so a 0.00px
    # residual here proves the DEPLOYED ATLAS matches the live engine (not a model fudge).
    cfg = {}
    for arg in sys.argv[1:]:
        k, _, v = arg.partition("=")
        if v.lower() in ("true", "false"):
            cfg[k] = v.lower() == "true"
        else:
            try: cfg[k] = float(v)
            except ValueError: cfg[k] = v
    if "sid" in cfg: SID = int(cfg.pop("sid"))

    # confirm the cell exists and lists exactly the captured sels
    recs = asm["assemblies"].get(str(SID))
    print(f"=== sprite_id {SID}: {len(recs)} static records, sels={[r['part'] for r in recs]}")
    print(f"=== probe captured {len(probe)} distinct sels, "
          f"{sum(s['ntiles'] for s in probe.values())} tile-quads")
    print(f"=== anchor exx,eyy=({anchor[0]},{anchor[1]}) facing={facing} scale={scale} "
          f"cfg={cfg or 'DEFAULTS (faceInv=T tileScale=1.0 reflEdge=F)'}")
    print(f"=== CPSX={CPSX:.6f} CPSY={CPSY:.6f}\n")

    # report the baked dims for the captured sels so the table is self-documenting
    captured_sels = sorted(probe)
    print("=== baked PL00_parts.json dims for captured sels (atlas w x h, tiles):")
    for sel in captured_sels:
        pd = parts_dims.get(sel)
        if pd:
            print(f"      sel {sel:4d}: {pd['w']:3d} x {pd['h']:3d} px "
                  f"({pd['w']//8} x {pd['h']//8} tiles)")
    print()

    pred = emitter_predict(SID, asm, parts_dims, anchor, facing, scale, cfg)

    hdr = f"{'sel':>4} {'nT':>3} | {'pred x,y,w,h':>26} | {'capt x,y,w,h':>26} | {'dX':>6} {'dY':>6} {'dW':>6} {'dH':>6} | flp"
    print(hdr); print("-" * len(hdr))
    rows = []
    for sel in sorted(probe):
        cap = probe[sel]
        ps = pred.get(sel, [])
        # a sel may have >1 predicted rect (rare); choose the closest to the captured bbox
        if not ps:
            print(f"{sel:>4} {cap['ntiles']:>3} | {'(sel not in pred)':>26} | "
                  f"{cap['x']:7.1f},{cap['y']:6.1f},{cap['w']:5.1f},{cap['h']:5.1f} | -- MISSING")
            continue
        best = min(ps, key=lambda p: abs(p["x"]-cap["x"])+abs(p["y"]-cap["y"]))
        dX = best["x"]-cap["x"]; dY = best["y"]-cap["y"]
        dW = best["w"]-cap["w"]; dH = best["h"]-cap["h"]
        rows.append((sel, dX, dY, dW, dH))
        print(f"{sel:>4} {cap['ntiles']:>3} | "
              f"{best['x']:7.1f},{best['y']:6.1f},{best['w']:5.1f},{best['h']:5.1f} | "
              f"{cap['x']:7.1f},{cap['y']:6.1f},{cap['w']:5.1f},{cap['h']:5.1f} | "
              f"{dX:6.1f} {dY:6.1f} {dW:6.1f} {dH:6.1f} | "
              f"{'X' if best['flip'] else '.'}{'Y' if best['flipY'] else '.'}")

    if rows:
        import statistics as st
        for lbl, idx in [("dX", 1), ("dY", 2), ("dW", 3), ("dH", 4)]:
            v = [abs(r[idx]) for r in rows]
            print(f"\n{lbl}: max={max(v):6.2f}  mean={st.mean(v):6.2f}  "
                  f"#>1px={sum(1 for x in v if x > 1.0)}/{len(v)}")
        allmax = max(max(abs(r[i]) for i in (1,2,3,4)) for r in rows)
        print(f"\nOVERALL max |residual| (any of x,y,w,h) = {allmax:.2f} px over {len(rows)} sels")

    # ===== SYNTHETIC OPPOSITE-FACING (facing=0) MIRROR VALIDATION =====
    # No facing=0 capture exists, so construct the EXPECTED facing=0 quads by mirroring
    # the captured facing=1 quads across the foot anchor axisX = exx (a part's left edge L
    # with width w maps to left edge 2*exx-(L+w)). Then predict with facing=0 (posReflect
    # ON) and diff. If the reflected branch is the EXACT algebraic mirror of the validated
    # branch, the residual is the SAME pure anchor-quantization (dX~0.70,dY~0.40), dW=dH=0.
    print("\n=== SYNTHETIC facing=0 mirror check (expected = facing=1 capture mirrored across exx) ===")
    cfg0 = dict(cfg)
    pred0 = emitter_predict(SID, asm, parts_dims, anchor, 0, scale, cfg0)
    print(f"{'sel':>4} | {'pred(facing0) x,w':>20} | {'mirror(capt) x,w':>20} | {'dX':>6} {'dW':>6}")
    print("-" * 64)
    rows0 = []
    for sel in sorted(probe):
        cap = probe[sel]
        ps = pred0.get(sel, [])
        if not ps:
            continue
        # mirror the captured facing=1 rect across axisX = exx
        mx = 2 * anchor[0] - (cap["x"] + cap["w"])
        best = min(ps, key=lambda p: abs(p["x"] - mx))
        dX = best["x"] - mx
        dW = best["w"] - cap["w"]
        rows0.append((dX, dW))
        print(f"{sel:>4} | {best['x']:9.1f},{best['w']:7.1f} | {mx:9.1f},{cap['w']:7.1f} | "
              f"{dX:6.2f} {dW:6.2f}")
    if rows0:
        mx_dx = max(abs(r[0]) for r in rows0); mx_dw = max(abs(r[1]) for r in rows0)
        print(f"\nSYNTHETIC facing=0 mirror: max |dX|={mx_dx:.2f}px  max |dW|={mx_dw:.2f}px  "
              f"(<=0.70 dX, 0.00 dW => EXACT mirror)")

if __name__ == "__main__":
    main()
