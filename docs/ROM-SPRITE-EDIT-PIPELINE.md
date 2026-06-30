# MVC2 ROM Sprite-Edit / Bake Pipeline — Knowledge Base

> **What this is.** How to edit a character's sprite PIXELS and bake them back into the
> real MVC2 GD-ROM so they render on flycast, any emulator, **and real Dreamcast hardware**.
> Validated end-to-end 2026-06-13: a full-body recolored Cable rendering off a patched GDI.
>
> **BYOR / legal.** Never distribute or commit a ROM, a track, a DAT, or decoded sprite
> pixels (all ROM-derived). The deliverable is the *patcher tooling*; the user runs it on
> their own legally-owned GDI. Always operate on a COPY of the GDI, never the source.
>
> Clean-room: addresses/algorithms in our own words from the `marvelous2` disassembly.

---

## 0. The one-paragraph mental model

A character's sprite art lives in `PLxx_DAT.BIN` inside the disc. Its parts are stored
**LZSS-compressed, 4bpp-indexed, PVR-twiddled**, packed shoulder-to-shoulder with **zero
gaps**, located by a small **offset table** (the index). You CANNOT just overwrite a part's
pixels in place unless the result compresses to the *exact* original byte length — because
the next part is glued right after it and the loader is length-sensitive. The fix that
removes that constraint is to **rebuild the offset table**: re-encode parts at any size and
rewrite the index so the game finds them. With the rebuild, arbitrary edits work.

---

## 1. The pipeline (end-to-end)

```
extract PLxx_DAT from disc → decode part pixels (GFX1 LZSS + detwiddle)
   → EDIT pixels freely → re-encode (gfx1_lzss.encodeA)
   → REBUILD GFX1 offset table (rebuild_gfx1.rebuild_dat)   ← the unlock
   → splice rebuilt GFX1 back into the DAT (same total size)
   → write the DAT into the disc's track03 sectors (on a COPY)
   → load patched GDI → renders via the normal SH4→PVR path (hardware-ready)
```

Tools (all in `tools/`):
- **`gfx1_lzss.py`** — `decodeA(blob, dest_len)` / `encodeA(pixels)`. The GFX1 codec.
- **`rebuild_gfx1.py`** — `rebuild_dat(dat, edits={sel: pixels})` (the edit primitive),
  `find_dat`, `desector`. Offset-table rebuild + DAT splice + disc write.
- **`patch_gdi_part.py`** — legacy in-place exact-length patcher (pre-rebuild; kept for
  reference / tiny same-length edits).
- **`extract_gfx1_atlas.py`** — `decodeA` + the flycast detwiddle port (for true pixels).
- **`rip_gfx2_assembly.py`** — GFX2 cell/assembly reader.

---

## 2. The GFX1 LZSS codec  (CONFIRMED — decoder `loc_8c0354c0`)

Byte-oriented LZSS, **self-contained per part** (the output buffer IS the back-ref window —
no cross-part references; this is why the whole roster decodes offline):

```
read an 8-bit FLAG byte, MSB-first (0x80 → 0x01). per bit:
  bit CLEAR → literal:  copy 1 source byte to output
  bit SET   → back-ref: read 1 byte b; dist = b>>4 (0..15); count = (b&0x0F)+2 (2..17);
              copy `count` bytes from output[len-(dist+1)] forward (overlap = RLE)
stop when OUTPUT length reaches dest_len (output-bounded; NO in-stream length/terminator).
```

- `dest_len` for a PAL4 part = `(sw·8)·(sh·8)/2` bytes = `sw·sh·32` (CONFIRMED — packer
  `loc_8c033dee` computes `W·H>>1`).
- The pixel decoder is the **byte** variant `loc_8c0354c0` (NOT the 16-bit `loc_8c03552a`),
  proven from the load packer's `jsr` target.
- **No integrity/CRC/checksum** anywhere on the DAT load path (CONFIRMED — load primitive
  `loc_8c129668` is a plain memcpy; zero `crc/checksum/hash` hits across all 28 banks). So a
  structurally-correct edit is never rejected by a content gate.

### The encoder — and the #1 crash lesson
`encodeA` is a greedy LZSS that **MUST prefer the LARGEST distance** among equal-length
matches (iterate window from farthest to nearest). **Repeated `dist=0` RLE runs CRASH the
real decoder** even though they decode fine in our Python port — the ROM only ever uses
`dist=0` ONCE to bootstrap, then `dist=15`. A "nearest-match" greedy emits `dist=0` runs and
crashes at load. **LESSON: round-trip against our own decoder is NOT sufficient — the encoded
token DISTRIBUTION must match what the ROM emits.** The fixed `encodeA` reproduces ROM bytes
exactly for solid tiles and, scanned over all 4031 Cable parts, produces ZERO repeated
`dist=0` (and compresses 6 bytes *smaller* than Capcom over the whole character).

---

## 3. The PLxx_DAT / GFX1 structure  (CONFIRMED)

```
DAT header (u32 LE, file-relative offsets):
  +0x00 GFX1 ptr   +0x04 GFX2 ptr   +0x08 Pal ptr   (+more sections after)

GFX1 region [gfx1 .. gfx2):
  [ offset table: nParts × u32 ]   where table[0] = nParts*4 = first blob offset
                                    (NO sentinel entry; part i = [table[i], table[i+1]);
                                     the LAST part ends at the GFX2 base)
  [ part 0 ][ part 1 ] ...          each part = 4-byte header + LZSS blob, packed TIGHT
       part header = [lw][lh][sw][sh]  (logical W/H, storage W/H, in units of 8px tiles)

  nParts = table[0] / 4.   SLACK = 0: each blob's decode consumes EXACTLY its slot length
  (verified across all parts) → the loader is length/offset sensitive.
```

Pixels: **4bpp PAL4 indexed** (2 pixels/byte), **PVR-twiddled** in storage, **index 0 =
transparent**. Decoded texels sit in the bottom-left `lw·8 × lh·8` of the `sw·8 × sh·8`
storage. GFX2 cells reference parts **by SEL = the offset-table index**, so rebuilding the
table+blobs is sufficient — cells keep working (they resolve sel → new offset).

**Atlas ↔ disc identity:** our atlas part index == the GFX1 offset-table index (nParts
matches the atlas part count exactly, e.g. Cable PL17 = 4031). So `PLxx_parts.json` sel N is
disc GFX1 part N.

---

## 4. THE EXACT-LENGTH CONSTRAINT and the OFFSET-TABLE REBUILD (the unlock)

**The constraint (in-place edits):** parts are packed tight (slack=0). An in-place edit must
re-compress to the **exact** original slot byte length. You can pad a *shorter* compressed
stream up to length with extra literals (`encode_solid_len`), but (a) you can't always land
on the exact byte (flag-byte quantization → ~1/3 of solid tiles skip), and (b) a *larger*
result can't fit at all. A real drawing compresses to an arbitrary size → almost never the
exact slot → in-place editing is a dead end for real art.
- Proven failure modes: a shorter blob + **zero-padding** CRASHES (loader reads the next part
  from the wrong place); only an **exact-length** in-place blob runs.

**The fix — `rebuild_dat(dat, edits)`:** decode every part, apply `edits` (replace pixels for
the given sels), **re-encode ALL parts at natural size**, lay them out contiguously, and
**rewrite the offset table** to the new positions. Keep the DAT the same total size by padding
the rebuilt GFX1 to the original `[gfx1..gfx2)` span (GFX2/Pal/rest stay at their absolute
offsets → no ISO/GDI restructuring). A full re-encode FITS (our compression ≈ Capcom's).

**Validated (Test 0/1/2, Cable PL17, 4031 parts):**
- Test 0 (offline): all 4031 parts re-decode byte-identical; rebuilt GFX1 fits (6 bytes spare).
- Test 1 (in-game null rebuild): every part relocated/re-encoded, pixels identical → **Cable
  renders 100% normal** → the engine honors the rebuilt table; the length wall is dead.
- Test 2 (in-game real edit): full-body recolor (all parts, index remap) → **Cable renders
  cleanly recolored, every frame, no flicker, no crash.** Arbitrary edits CONFIRMED.

---

## 5. Editing the pixels

- **Solid fill** (one index everywhere): twiddle-invariant. A NON-zero fill paints the WHOLE
  `sw·sh` storage rect (including normally-transparent padding) → blocks bigger than the limb.
- **Recolor / index remap** (`i → f(i)`, keep 0): twiddle-invariant (it's per-nibble, position
  doesn't matter) → preserves silhouette + shading; the cheapest clean edit. (Pure index
  *permutation* even keeps the compressed size identical → fits in-place without a rebuild.)
- **Arbitrary art** (draw a face): must **detwiddle → edit in pixel space → re-twiddle** (use
  the flycast detwiddle port in `extract_gfx1_atlas.py`), then re-encode. Needs the rebuild
  (size changes). Bound to the 16-color palette unless you also edit `Pal`.

---

## 6. Finding which sels to edit — ASMTRACE is ground truth

A character's body renders from a **mid-range, per-character set of sels** — NOT the low
0–251 range (those are effect/UI parts packed at load; editing them does nothing to the body
but can crash on bad length). **Do not guess the sel range from the atlas.** Use ASMTRACE:

`mc_assembly.log` (Oracle hook at `loc_8c0344d4` @ PC `0x8C034864`, one line per rendered
body part):
```
# frame sid slot cid sel dx dy accX accY screenX screenY pal row flip flags r11 r13 node
```
Filter by `cid` (char id, decimal — Cable=23=0x17, Ryu=0, Magneto=44=0x2C) and rank `sel` by
count → the most-rendered sels are the always-on-screen body parts. Example: Cable's body =
sels ~197–290 (sel 198 = 6096 renders); Ryu's = ~530s. An existing capture
(`../maplecast-flycast/_ryu_capture/mc_assembly.log`) already covers Ryu + Cable, so a fresh
prod/live capture is often unnecessary — check first.

**Per-frame tile-ization:** each animation frame (sprite_id) draws the body from its OWN set
of sels (different angle/shading), with heavy near-duplication (this is Paxtez's "Magneto's
face is 100 tiles"). To change a region *consistently*, edit EVERY sel that participates —
the rebuild lets you cover all of them (flicker-free). Some sels ARE shared across frames
(edit once, propagates).

---

## 7. The disc / GDI read-write  (CONFIRMED on the US GDI)

- GDI = 3 tracks; `track03.bin` = the data track (raw **2352-byte** Mode-1 sectors, user data
  at **+16**). ISO9660 uses **absolute LBAs**; track03 starts at LBA **45000** (`.gdi`), so
  file offset = `(abs_lba - 45000) * 2352 + 16`.
- Per-character files: `PLxx_DAT.BIN` (sprites/cells/palette), `_FAC`/`_VOI`/`_WIN`. Resolve
  via the ISO9660 root dir (PVD at abs LBA 45016). 233 PL files; Cable = `PL17_DAT.BIN`.
- To bake: rebuild the DAT in memory, then write its 2048-byte user chunks back into the
  track's sectors (on a COPY of the whole `mvc2_us` dir). Keep the DAT size identical → no ISO
  directory / GDI changes.
- **EDC/ECC** is left stale by the in-place sector write. flycast ignores it (it just memcpys
  the 2048 user bytes — `core/imgread/common.cpp`), and GDEMU streams sectors as-is, so it's
  fine for emulator + ODE. **Regenerate EDC/ECC for a *burned* GD-R.** (TODO.)

---

## 8. Crash / failure modes (all observed + resolved)

| Symptom | Cause | Fix |
|---|---|---|
| Crash at match start | **Repeated `dist=0`** in our encoding | encoder prefers largest distance (§2) |
| Crash at match start | Shorter blob + **zero-pad** (length mismatch) | exact-length in-place, OR rebuild table |
| No visual change (no crash) | Editing the **wrong sel range** (0–251 effect/UI, not body) | ASMTRACE → real body sels (§6) |
| Flicker (parts on/off) | Partial sel coverage + per-frame tiles | cover all rendered sels (rebuild) |
| Red blocks bigger than limb | Non-zero solid fill paints the full storage rect | recolor (preserve index 0), not solid fill |
| Can't fit a real edit | exact-length constraint | offset-table rebuild (§4) |

**Ruled out:** no ROM/DAT integrity check (so edits aren't rejected for being "modified"); the
decoder has no special bytes/terminator/bounds beyond the output count.

---

## 9. What reaches real hardware (and what doesn't)

| Approach | Hardware? | Notes |
|---|---|---|
| **Disc edit (this pipeline)** | ✅ Dreamcast + every emulator + shareable patch | the real thing |
| flycast CustomTexture pack | ❌ flycast-only | render overlay; `DumpTextures`/`CustomTextures`, hash-keyed PNGs; never touches the disc |
| DM00 (`0x0CE80000`) RAM write-hook | ❌ + fragile | DM00 is a compacting CPU staging set, NOT the PVR sample source; dead-end |

---

## 10. Skin Studio — the dashboard editor (v1 SHIPPED)

`web/skin-studio.html` + `web/panels/tile-editor.mjs` (linked from `dashboard.html`). v1 =
**palette editor**: pick a character, recolor its body-palette swatches, live-preview the
recolor on the real part atlas (the atlas PNG uses exactly the 16 palette colors, so the
preview maps original→edited per pixel — exact), export `PLxx_skin.json`.

Bake: `tools/bake_skin.py PLxx_skin.json` → patched GDI in `C:\roms\mvc2_us_skin\`.
- `skin.json` keys: `palette` {bank:{index:[r,g,b,a]}} (patches the Pal section @ `DAT+0x08`,
  ARGB4444, 16 entries/bank, no GFX1 rebuild), `recolor` {fromIdx:toIdx} (global index remap),
  `parts` {sel: base64 twiddled-4bpp} (per-part pixel override) — recolor/parts go through
  `rebuild_dat`. Pal offset/format verified == `PLxx_lut.json` banks (bodyBank = the body).
- **Pixel-art bridge SHIPPED (`tools/part_png.py`):** export any part(s) as an INDEXED PNG
  (char's 16 colors, idx0 transparent, right-side-up) → edit in Aseprite/GIMP/Piskel → import
  back. The twiddle inverse `twiddle_pal4` (exact inverse of `extract_gfx1_atlas.detwiddle_pal4`,
  verified byte-exact 306/306) handles PVR storage; `png_to_blob` reads indexed PNGs natively
  (or quantizes RGBA to nearest palette color). `skin.json` gains `parts_png`: {sel: png_path}
  → `bake_skin.py` imports → `rebuild_dat`. Round-trip byte-exact (120/120); E2E verified
  (edit a PNG → bake → the edit decodes on disc). CLI: `part_png.py export PL17 198,205 ./edit`
  and `part_png.py roundtrip PL17`. Use the ASMTRACE render set (§6) to pick the sels for a
  region so a paint covers every frame.

**In-panel COMPOSITE FRAME editor SHIPPED (tile-editor.mjs?v=4).** Pick anim group→sub-anim
(`web/anim/PLxx.json`), STEP/PLAY its frames, and paint on the FULLY ASSEMBLED sprite at full
size. Each frame is composited in the browser from `PLxx_asm.json` (sprite_id→[{dx,dy,part,
flip,flipy}]) + the edit bundle pixels — VERIFIED right-side-up/correct (bundle+_asm composite =
recognizable Cable; bundle is the SAME orientation the bake expects, so display+bake share one
orientation, no conversion). Strokes are DECOMPOSED back to parts: each composite pixel maps to
the topmost-opaque part (else topmost box, to fill transparent padding), accounting for flips →
written to that part's local pixel (`painted[sel]`). **Part-box overlay** outlines every tile in
the frame (hover = yellow, edited = green, toggle). Brush=16 palette colors (idx0=erase),
pencil/fill/eyedropper/undo/zoom. Animation plays with edits live. NOTE: parts are shared across
frames → an edit propagates to every frame/anim using that part (consistent skin; per-frame
isolation would need part duplication — not built). Export bundles palette + painted parts into
ONE skin.json (`parts_png_b64`:
{sel: data-URL PNG}) → `bake_skin.py` decodes inline → `png_to_blob` → `rebuild_dat`. E2E
verified (browser export → bake → on-disc). Needs the editor bundle:
`tools/export_editor_bundle.py PLxx` → `PLxx_edit.{png,json}` (a parts atlas in the EXACT
bake-faithful orientation — the display `PLxx_parts.png` does NOT round-trip, 0/9, so the
bundle is separate; bundle crops bake byte-exact 9/9). Bundles built: PL17/00/2C/2A.

Run: `cd web && python3 -m http.server` → open `skin-studio.html`.

Auto-memory companion: `project_rom_sprite_mod_routeb.md`.
Defer to `mvc2-sh4-re-expert` for raw disassembly, `mvc2-sprite-render-expert` for the
off-SH4 client renderer / atlas bake.
