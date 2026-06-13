#!/usr/bin/env python3
"""Reshape the prod fx_atlas.json (effects[]+triggers) into the whole-sprite
loadFxAtlas() format: a `sprites{ <sprite_id>: {x,y,w,h, dx,dy, wG,hG, facing} }`
map keyed by the EFFECT sprite_id (node+0x144) — the only stable key on the OBJS
wire for an effect object (cid, sid, type=layer, x, y, is_effect). The PNG is
untouched; we only re-index the rects.

Trigger keys are "category:sprite_id" (category = node+0x03, used by the offline
bake to GROUP effects; NOT shipped in OBJS). The client matches by sprite_id
alone, so we collapse on the sid (the part after ':') and, when a sid appears in
multiple atlas entries, keep the rect from the entry where it occurred MOST
(highest trigger count) — that's the dominant texture for that effect id.

Effects are point-centered on the object's screen pos (o.x/o.y): dx=-w/2,
dy=-h/2, wG=w, hG=h, facing=0 (no baked flip; the object's own xflip drives it).
"""
import json, sys

src = json.load(open(sys.argv[1]))
effects = src.get("effects", [])

# sid -> (count, rect-entry)
best = {}
for e in effects:
    rect = (e["x"], e["y"], e["w"], e["h"])
    for trig, cnt in (e.get("triggers") or {}).items():
        # "cat:sid" -> sid (decimal). Tolerate a bare "sid" too.
        sid = int(trig.split(":")[-1])
        prev = best.get(sid)
        if prev is None or cnt > prev[0]:
            best[sid] = (cnt, rect)

sprites = {}
for sid, (cnt, (x, y, w, h)) in sorted(best.items()):
    sprites[str(sid)] = {
        "x": x, "y": y, "w": w, "h": h,
        "dx": -w / 2.0, "dy": -h / 2.0,   # point-centered on screen_x/y (§6)
        "wG": w, "hG": h,
        "facing": 0,
    }

out = {
    "name": "effects",
    "image": src.get("image", "fx_atlas.png"),
    "screenW": 640, "screenH": 480,
    "w": src.get("w"), "h": src.get("h"),
    "sprites": sprites,
    # keep the original grouping for provenance / future re-bake
    "effects": effects,
}
json.dump(out, open(sys.argv[2], "w"), indent=1)
print(f"reshaped {len(effects)} effect entries -> {len(sprites)} sprite_id keys")
print("sids:", ",".join(sorted(sprites.keys(), key=int)))
