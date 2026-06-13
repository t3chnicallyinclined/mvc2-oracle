# Part-Assembly Rendering — Plan (branch `feat/part-assembly`)

> **Why:** the whole-sprite approach (branch `feat/rom-asset-probe`) places *pre-baked
> whole sprites* and *reconstructs* placement from state — which keeps fighting us on
> cape-attach, alive, z-order, because those are runtime/assembly facts we throw away.
> **MVC2 doesn't draw whole sprites — it assembles each frame from reusable PARTS** at
> per-frame offsets. If we render the same way (parts + the assembly list), it's
> pixel-exact and the whole class of bugs dissolves. Still low-bandwidth: the assembly
> is deterministic from `sprite_id`, which the GSTA already ships.

## What we confirmed (2026-06-06)
- **The codec is already cracked / decoded.** `dasm_PLDAT/` (the `dasm_PLDAT_v005a.py`
  tool + decoded `Output/PL00_DAT/`) gives us, per character DAT:
  - `GFX_DATA_00/01.BIN` — the **part pixels** (planar 4bpp tiles; `combine_planes()` decodes)
  - `EXTRAS_DATA.BIN` — the **assembly lists**: 8-byte records `dx(s16) dy(s16) part_idx(u8) b5 mode flip` (rec with `mode=0xFF` = separator/header; `flip` bit 0x80 = hflip)
  - `ANIMATION_DATA.BIN` — keyframes (the 20-byte records; → sprite_id → assembly)
  - `PALETTE_DATA.BIN` — the palette
  - `*_assembly_layout.png` — proves it: each frame = part rectangles at their offsets
- PLDAT header pointers: gfx1@0x00, gfx2@0x04, palette@0x08, extras@0x0C, animations@0x14,
  hitbox_pattern@0x18, hitbox@0x1C, attack@0x20, AI@0x24+.
- Only **PL00** is decoded locally; the rest extract from the operator's ROM (GDI → PLxx_DAT.BIN → the tool).

## Architecture: precompute offline, render by sprite_id at runtime
1. **Offline, per character:** parse GFX (parts) + EXTRAS (assemblies) + ANIMATION → emit
   a **part atlas** (`PL{hex}_parts.png`) + an **assembly table**
   (`PL{hex}_asm.json`: `sprite_id → [{part_idx, dx, dy, flip}], + part rects + pal`).
   Operator-local, gitignored (ROM-derived).
2. **Runtime (client, low-bandwidth):** the GSTA already ships `sprite_id` per char + pool
   object. The client looks up the assembly for that sprite_id and **draws the parts at
   their offsets** from the part atlas — exactly the SH4 render loop. No new wire data;
   the assembly is deterministic.
3. **Result:** cape/crouch/jump, effects, projectiles, supers — all exact, because we
   replay the game's own assembly instead of guessing placement. Same ~30 KB/s.

## Build steps + findings (2026-06-06 RE pass)
- [x] **EXTRAS grouping — CRACKED.** 8192 records → **42 assemblies**, parts **0–21**,
  each placement `(dx s16, dy s16, part_idx u8, flip u8)`; `mode=0xFF` record = separator.
  e.g. assembly 0 = 24 placements of parts {0,3,5,12,13,14,15,16}. This is the frame recipe.
- [~] **GFX part format — PARTIAL, needs the draw routine.** Both `GFX_00` (425KB) and
  `GFX_01` (25KB) **begin with u32 offset tables** pointing to variable-size blobs
  (GFX_00: 6132,6221,6895… → ~1533 entries; GFX_01: 1764,1774,1816… → ~441 entries).
  Neither count matches the 22 part_idx, so there is an **indirection layer** between
  `part_idx` and pixels — almost certainly the runtime sprite-draw routine resolves
  `part_idx` against a per-assembly or animation-indexed GFX base. **The offset-table
  structure alone is not enough; we need the SH4 draw routine as ground truth.**
- [ ] **NEXT: read the SH4 sprite-draw routine in marvelous2** — find where it walks the
  EXTRAS list and reads `Dat_GFX1@0x15c / Dat_GFX2@0x160` to fetch part pixels. That
  routine *is* the exact `part_idx → (gfx base, offset, w, h, bpp)` mapping. Everything
  downstream (decode, atlas, render) is mechanical once this is known.
- [ ] **ANIMATION → assembly** — 20960 B / 20 = 1048 keyframes; sprite_id @ bytes 4–6.
  Map `sprite_id` → assembly index (likely via the keyframe or an EXTRAS pointer table).
- [ ] **Prototype on PL00** → **Baker** → **Client assembly-render** → **Roster** (unchanged from plan).

## STATUS: RE COMPLETE — implementation phase next (2026-06-06)
Every layer is now reverse-engineered (see `docs/MARVELOUS2-GFX-NOTES.md` for the SH4
render model). No more guessing remains; what's left is implementation + validation.

**Decode chain (all known):**
1. `PLxxPAK.BIN` (= the DAT, 59 chars in `MVC2 Dev Files/`) → header gfx1@0x20, gfx2, palette, extras.
2. GFX block begins with a **u32 offset table** (part directory; ~1533 cells for PL00).
3. Each part blob = **flag-bit LZSS over u16 LE** (`docs/MARVELOUS2-RE-HANDOFF.md` §2,
   decoder `loc_8c03552a`): flag word; clear bit=literal u16; set bit=token (top5=count,
   low11=operand; operand 0 = transparent fill, else back-ref `offset=operand<<1` words).
   Two brute-forceable unknowns: copy-length off-by-one, offset direction.
4. Decoded output = indexed 4bpp texels → part rectangle (dims from the blob header
   `w,h` bytes — confirm: part0 `01 04…`, part1 `04 0a…`).
5. `part_idx` indexes the per-character part set; `sprite_id → assembly` from EXTRAS+ANIM.
6. **Oracle for validation:** `MvC2_Spritesheets_20260516/PL{hex}.png` (indexed whole-sprite
   rips) — decode a part, composite an assembly, diff against the sheet's frame.

## Implementation steps (the build)
- [ ] **`web/webgpu/pldat-codec.mjs`** — port flag-bit LZSS (~40 lines); brute-force the 2
  unknowns by decoding a part and matching the sprite-sheet oracle pixel-for-pixel.
- [ ] **Part decoder** — GFX offset table + blob header (w,h) + codec → part rectangles (a part atlas).
- [ ] **Assembly table** — EXTRAS grouping + ANIMATION → `sprite_id → [{part_idx,dx,dy,flip}]`.
- [ ] **Validate on PL00** — composite assembly, diff vs `MvC2_Spritesheets/PL00.png`.
- [ ] **Baker** — `PL{hex}_parts.png` + `PL{hex}_asm.json` for all 59 PAKs (ROM-derived, gitignored).
- [ ] **Client assembly-render** — per-object: `sprite_id → assembly → parts`, z by priority byte;
  replaces whole-sprite draw for body + each pool object. Palette per char (`Dat_Pal`).
- [ ] **Confirm cape** = sibling object in the live object table (else check FAC, player+0x184).

The whole-sprite branch (`feat/rom-asset-probe`) stays as the working fallback until this lands.

## Open questions
- The indirection: does `part_idx` index a per-assembly GFX sub-table, or a global one
  offset by an animation/assembly base? (the draw routine answers this)
- Does a body assembly include its cape parts, or is the cape a separate `sprite_id`
  assembly (pool object)? Determines whether cape "just works."
- Palette: per-part or per-character bank? (ties into existing skin/pal128 work)

## Keep
- The GSTA pipeline, prediction, HUD, palette-recolor — all unchanged, all reused.
- The whole-sprite path stays on `feat/rom-asset-probe` as the working fallback.
