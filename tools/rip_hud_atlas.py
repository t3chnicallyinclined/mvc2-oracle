#!/usr/bin/env python3
"""
rip_hud_atlas.py — decode MVC2's FONT.BIN into a HUD sprite atlas (PNG + JSON).

Source: "MVC2 Dev Files/FONT.BIN" (disc asset, gitignored / copyrighted — NEVER
commit its pixels). Output: atlas/hud/hud_atlas.png + hud_atlas.json (atlas/ is
gitignored at .gitignore /atlas/).

FONT.BIN container (reverse-engineered + byte-verified this session, matches
docs/RENDER-MASTER-PLAN-V2.md §2.3 "Asset source — FONT.BIN"):
  0x00  header: N records, stride 0x10, terminated by 0xFFFF.. padding
        rec = { u16 w, u16 h, u16 fmt, u16 _, u32 fileOffset, u32 _ }
  rec0  @0x40    256x128 ARGB1555 TWIDDLED  — main proportional font (A-Z,a-z,0-9,WINS,symbols)
  rec1  @0x10040  64x64  ARGB4444 TWIDDLED  — HUD glyph sheet: boxed digits 0-9, EXP/LV gauges
  EOF   @0x12040 (byte-exact, no gap)

Format + twiddle were locked by visual A/B of all (fmt,twiddle) combos:
  tex0 decodes legibly ONLY as ARGB1555 twiddled; tex1 ONLY as ARGB4444 twiddled.

What we emit (the load-bearing HUD pixels):
  - digit_0 .. digit_9 : the 10 boxed digits from tex1's 16x16 grid, DE-ROTATED
    90deg CCW to upright and luminance-keyed (white glyph on transparent). These
    are the HUD's own digits — used for the round TIMER and the HIT counter.
  - bar_white : a solid-white 4x4 swatch ripped from tex0 (a glyph stroke). The
    life bar / super meter are this white texel STRETCHED and tinted per team
    slot (the faithful Canvas2D equivalent of MVC2's "white tex modulated by the
    per-slot vertex color", loc_8c15FFB0). The renderer tints it.
  - font_sheet / hud_sheet : the two full decoded textures are also packed so the
    atlas carries every glyph (extra digits/letters available for later use).

The renderer (web/webgpu/sprite-client.mjs drawHUD) Canvas2D-drawImage's these
rects — no PVR / no T1 re-map.
"""
import json, os, struct, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "MVC2 Dev Files", "FONT.BIN")
OUT_DIR = os.path.join(ROOT, "atlas", "hud")


def morton(x, y):
    m = 0
    for i in range(16):
        m |= ((x >> i) & 1) << (2 * i)
        m |= ((y >> i) & 1) << (2 * i + 1)
    return m


def tw_off(x, y, w, h):
    """PVR twiddle offset for a possibly-non-square texture: tile into min-dim
    squares, Morton-order within each square."""
    mn = min(w, h)
    bx, by = x // mn, y // mn
    blocks_x = w // mn
    return (by * blocks_x + bx) * mn * mn + morton(x % mn, y % mn)


def dec1555(v):
    return (((v >> 10) & 31) * 255 // 31, ((v >> 5) & 31) * 255 // 31,
            (v & 31) * 255 // 31, 255 if v & 0x8000 else 0)


def dec4444(v):
    return (((v >> 8) & 15) * 17, ((v >> 4) & 15) * 17,
            (v & 15) * 17, ((v >> 12) & 15) * 17)


def decode_tex(data, off, w, h, fmt):
    """fmt: 0=ARGB1555, 2=ARGB4444. Twiddled 16-bit."""
    dec = dec1555 if fmt == 0 else dec4444
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            o = off + tw_off(x, y, w, h) * 2
            if o + 1 < len(data):
                px[x, y] = dec(data[o] | (data[o + 1] << 8))
    return img


def parse_header(data):
    recs = []
    for i in range(0, 64, 0x10):
        w, h, fmt, _, foff, _ = struct.unpack_from("<HHHHII", data, i)
        if w == 0xFFFF or w == 0 or h == 0:
            break
        recs.append({"w": w, "h": h, "fmt": fmt, "off": foff})
    return recs


def key_white(cell):
    """Luminance-key a digit cell (white glyph on dark capsule) -> white-on-alpha."""
    px = cell.load()
    for y in range(cell.height):
        for x in range(cell.width):
            r, g, b, _ = px[x, y]
            lum = (r + g + b) // 3
            na = 0 if lum < 110 else min(255, int((lum - 110) * 255 / 120))
            px[x, y] = (255, 255, 255, na)
    return cell


def main():
    if not os.path.exists(FONT):
        sys.exit(f"FONT.BIN not found at {FONT} (disc asset, gitignored)")
    data = open(FONT, "rb").read()
    recs = parse_header(data)
    if len(recs) < 2:
        sys.exit(f"expected >=2 FONT records, got {len(recs)}")

    # rec0 = ARGB1555 (fmt code 0); rec1 = ARGB4444 (fmt code 2). The header's
    # raw fmt half-word is container-specific; the pixel format was locked by A/B.
    tex0 = decode_tex(data, recs[0]["off"], recs[0]["w"], recs[0]["h"], 0)  # 256x128 font
    tex1 = decode_tex(data, recs[1]["off"], recs[1]["w"], recs[1]["h"], 2)  # 64x64 HUD glyphs

    # --- tex1 boxed-digit grid -> upright 0-9 (16x16 cells, rotated 90 CCW) ---
    # (col,row) of each digit value in the 4x4 cell grid (verified by inspection).
    DIGIT_CELL = {0: (2, 2), 1: (2, 3), 2: (1, 0), 3: (1, 1), 4: (1, 2),
                  5: (1, 3), 6: (0, 0), 7: (0, 1), 8: (0, 2), 9: (0, 3)}
    digits = {}
    for dv, (cx, cy) in DIGIT_CELL.items():
        cell = tex1.crop((cx * 16, cy * 16, cx * 16 + 16, cy * 16 + 16))
        cell = cell.rotate(90, expand=True).convert("RGBA")  # CCW -> upright
        digits[dv] = key_white(cell)

    # --- solid white bar swatch ripped from a tex0 glyph stroke ---
    px0 = tex0.load()
    sw = None
    for y in range(0, tex0.height - 4):
        for x in range(0, tex0.width - 4):
            if all(px0[x + i, y + j][3] > 250 and min(px0[x + i, y + j][:3]) > 240
                   for i in range(4) for j in range(4)):
                sw = (x, y)
                break
        if sw:
            break
    if sw is None:
        sys.exit("no solid-white swatch found in tex0")
    bar = tex0.crop((sw[0], sw[1], sw[0] + 4, sw[1] + 4))

    # ---- pack atlas: digits row (10x 16-wide), bar swatch, + the two full sheets ----
    GAP = 1
    dig_w, dig_h = 16, 16
    digits_w = 10 * (dig_w + GAP)
    atlas_w = max(digits_w, tex0.width, tex1.width)
    # rows: [digits | bar][font_sheet 256x128][hud_sheet 64x64]
    y_digits = 0
    y_font = dig_h + GAP
    y_hud = y_font + tex0.height + GAP
    atlas_h = y_hud + tex1.height
    atlas = Image.new("RGBA", (atlas_w, atlas_h), (0, 0, 0, 0))

    rects = {}
    for dv in range(10):
        x = dv * (dig_w + GAP)
        atlas.paste(digits[dv], (x, y_digits))
        rects[f"digit_{dv}"] = {"x": x, "y": y_digits, "w": dig_w, "h": dig_h}
    bx = 10 * (dig_w + GAP)
    atlas.paste(bar, (bx, y_digits))
    rects["bar_white"] = {"x": bx, "y": y_digits, "w": 4, "h": 4}

    atlas.paste(tex0, (0, y_font))
    rects["font_sheet"] = {"x": 0, "y": y_font, "w": tex0.width, "h": tex0.height}
    atlas.paste(tex1, (0, y_hud))
    rects["hud_sheet"] = {"x": 0, "y": y_hud, "w": tex1.width, "h": tex1.height}

    os.makedirs(OUT_DIR, exist_ok=True)
    png_path = os.path.join(OUT_DIR, "hud_atlas.png")
    json_path = os.path.join(OUT_DIR, "hud_atlas.json")
    atlas.save(png_path)
    meta = {
        "source": "MVC2 Dev Files/FONT.BIN",
        "atlasW": atlas_w, "atlasH": atlas_h,
        "rects": rects,
        # per-team-slot life-bar modulate colors (loc_8c15FFB0; vertex gradient
        # left->right). The renderer tints the white bar swatch with these.
        "barColors": {
            "C1": ["#FF40FF", "#FFFF00"],
            "C2": ["#00FF00", "#FFFF00"],
            "C3": ["#00C0FF", "#FFFF00"],
        },
        "notes": "digits 0-9 = tex1 boxed digits de-rotated+keyed; bar_white = "
                 "tex0 solid swatch (stretch+tint per team). font_sheet/hud_sheet "
                 "= full decoded textures for any extra glyphs.",
    }
    with open(json_path, "w") as f:
        json.dump(meta, f, indent=1)
    print(f"wrote {png_path} ({atlas_w}x{atlas_h})")
    print(f"wrote {json_path}  rects={list(rects)}")


if __name__ == "__main__":
    main()
