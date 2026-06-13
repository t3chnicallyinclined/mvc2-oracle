# Assembly-Driven Part Renderer — Design & Feasibility

> **Goal.** Ship only compact game STATE per frame (`sprite_id` + screen pos per body
> and per pool object — already in the GSTA). The client reconstructs each frame by
> looking up a precomputed assembly (`sprite_id → parts + offsets`) and drawing PARTS
> from a locally-cached part atlas. This is the most-compact, pixel-exact, zero-
> copyrighted-assets-on-the-wire path.
>
> **Companion docs:** `docs/MARVELOUS2-GFX-NOTES.md` (SH4 render model),
> `docs/PART-ASSEMBLY-PLAN.md` (RE status), `docs/MARVELOUS2-RE-HANDOFF.md` (codec),
> `web/webgpu/pldat-codec.mjs` (offline decoder + the codec wall).
>
> Clean-room: addresses / field offsets / algorithm descriptions in our own words.
> No verbatim disassembly. **Never commit ROM-derived pixels.**

---

## 0. The blocker, and the way around it

Offline static decode of the part pixels is **blocked**. The PLDAT GFX codec (flag-bit
LZSS over u16 LE, `pldat-codec.mjs`) is cracked, but the game decodes each part into a
**single fixed scratch buffer** and large parts back-reference the residue of the
*previously* decoded part sitting in that scratch. Only ~14% of parts are self-contained
and decode offline; the other ~86% need the live scratch state, which the static
`GFX_DATA_00` file does not capture. So we cannot build the atlas purely offline.

**But we run the game.** The feasibility question is therefore: *can the headless server
capture the already-decoded parts at runtime?* The answer — traced end to end in the
marvelous2 disassembly — is **yes, cleanly, from SH4 main RAM the mirror already reads.**

---

## 1. KEY FEASIBILITY FINDING — runtime part capture is feasible; decoded parts live in main RAM

### Where the decoded parts end up (the copy-out destination)

The per-part decode loop is `bank03.asm:loc_8c032696`. Per part it:

1. Loads the compressed source from the GFX offset table (`src = table_base + table[idx]`).
2. Calls the LZSS decoder (`loc_8c03552a`) with the destination **pinned to the constant
   scratch `0x0CE60000`** (the literal `0x0ce60000` at `loc_8c032854`). This is the
   `Texture_Decompress_Buffer` — confirmed by name in `marvelous2/memory/work.asm`
   (`;0ce60000 - Texture_Decompress_Buffer`). Every part decodes into the **same** scratch,
   overwriting the previous one (this is exactly why offline decode underflows).
3. **Copies the decoded result OUT of the scratch** into the part's persistent texture
   slot. Two `mov.l @rN+ ... mov.l rM,@rDest` copy loops move the result word-by-word into
   a destination pointer fetched from a per-part directory: `dest = *(dir_entry + 0x8)`,
   where the directory has **0x10-byte stride** per part and its base is read from the GFX
   work header at `*(0x0CE80008)`.

### The persistent home: `0x0CE80000` — "DM00 Poly"

The directory base and the destination slots live in the region starting at **`0x0CE80000`**,
labelled **`;0ce80000 - DM00 Poly`** in `work.asm` (the neighbouring poly/texture regions
are `0x0CEA0000` Stage Poly, `0x0CED0000` Effect Poly). After the decode loop runs for a
character, every one of its parts sits **decompressed, in plain 4bpp indexed texels, in
main RAM at a stable, directory-addressable address** — not transient.

**Crucial address-space fact:** `0x0C000000`–`0x0CFFFFFF` is the Dreamcast **system RAM**
(the 16 MB SH4 main RAM, `mem_b[]`). `0x0CE60000` and `0x0CE80000` are offsets
`0x00E60000` / `0x00E80000` into that array — i.e. **they are inside `mem_b`, NOT VRAM.**
The mirror already memcpy's all of `mem_b[]` (`maplecast_mirror.cpp:529`,
`memcpy(&mem_b[0], snap+off, 16MB)`) and the gamestate reader already random-access reads
it via `addrspace::read32(0x8C......)` (`maplecast_gamestate.cpp`). So **reading the
decoded parts is the exact same mechanism we already use for `sprite_id`, palettes, and
the EXTRAS list — no new emulator surface.**

### The capture mechanism (precise)

A server-side hook reads, once per character after its DAT loads (`Dat_FilePointer`
player+0x17c becomes non-null and the GFX directory at `0x0CE80000` is populated):

```
dir_base  = read32(0x8CE80008)          ; per-part directory base (DM00 Poly header +8)
nParts    = (GFX1 offset-table[0]) >> 2 ; part count from the offline table (we already parse this)
for idx in 0..nParts-1:
    entry   = dir_base + idx*0x10        ; 0x10-byte stride
    dest    = read32(entry + 0x8)        ; the part's persistent texel slot (in mem_b)
    # part dims come from the 4-byte blob header (w,h,sw,sh in 8px tiles) we already read
    # offline from the GFX offset table; texel count = sw*sh*64 nibbles.
    texels  = read_bytes(dest, sw*sh*64/2)   ; raw 4bpp indexed texels, already de-LZSS'd
    emit part rectangle (de-interleave 8x8 tiles via tileToImage(), index 0 = transparent)
```

i.e. the **directory at `0x0CE80000` enumerates the parts; field +0x8 of each 0x10-byte
entry is the part's decoded address; the blob header (already parsed offline) gives the
dimensions.** No need to reverse the scratch residue — we read the *output* of the copy-out,
which is the clean, fully-decoded part. The offline codec stays useful only as the
**part-count / dimensions / directory cross-check oracle**, not as the pixel source.

> Two small live confirmations to do at the box (read-only, one capture each, per the
> "confirm presence first" rule):
> 1. Confirm the directory header field — that `*(0x0CE80008)` is the part directory base
>    and entry+0x8 is the dest (vs +0x0 / a different stride); single-step
>    `loc_8c032696`'s two copy loops or just dump 0x0CE80000..+0x40 and match against the
>    part dims.
> 2. Confirm the dest slots stay resident (DM00 Poly is per-character-persistent, not
>    reused mid-frame). If they're reused, capture during the load gap instead of in the
>    hot path; the load happens once per character entrance, so timing is generous.

### Why not read parts straight from VRAM?

We could, but it's strictly worse here. The TA's TCW addresses point at uploaded textures
in VRAM (the mirror already reads `vram[]` and decodes TCW formats —
`maplecast_mirror.cpp:1310-1347`). However: (a) by the time a part is in VRAM it is
**twiddled / format-encoded** for the PVR and would need un-twiddling per format; (b) VRAM
textures are paletted/packed at upload granularity, not 1:1 with our part rectangles; (c)
VRAM churns every frame, so isolating one character's parts means tracking uploads. The
**`0x0CE80000` copy-out is the canonical, format-clean, per-part, once-per-load source** —
plain 4bpp indexed texels in the exact tile layout `tileToImage()` already expects. Use
VRAM only as a fallback cross-check.

**Bottom line:** runtime part capture is feasible and clean. Decoded parts live at
`0x0CE80000` (DM00 Poly) in main RAM, enumerated by a 0x10-stride directory at
`*(0x0CE80008)`, each entry's +0x8 pointing at the part's decompressed 4bpp texels —
all reachable by the same `addrspace::read*` / `mem_b[]` path the mirror already uses.

---

## 1b. THE part_idx → directory-entry MAPPING (resolved from the disassembly)

> **History.** A first attempt resolved the per-character base by *dimension-matching*
> the char's GFX-pool part dims against directory entry dims. **That was structurally
> wrong** and was dropped. The `0x0CE80000` directory is a **LIVE WORKING SET** — it holds
> only the textures currently uploaded (this frame's parts + HUD + stage + BOTH fighters,
> interleaved), so (a) the first 32 GFX1 parts aren't all loaded unless the current frame
> uses them, and (b) a character's parts are **not** a contiguous window keyed by GFX1
> order. The mapping below is read from the marvelous2 SH4 routines instead — exact, not
> guessed.

### The mapping (clean-room, from the SH4 trace)
The per-part fetch wrapper **`bank03.asm:loc_8c0322c0`** computes, for a directory **key**
`k` and the directory struct in `r6`:

```
entry = *(r6 + 0x8) + (k << 4)     # (k << 4) == k * 0x10  (the 0x10 entry stride)
dest  = *(entry + 0x8)             # the part's decoded texel slot (in mem_b)
```

so **the directory is keyed by a small integer `k`, and `entry = dir_base + k * 0x10`**
(`dir_base = *(0x0CE80008)`, the same base we already read).

The **body-parts loader** `bank03.asm:loc_8c032ae0` calls that wrapper in a loop with the
key = a **plain incrementing counter** `r11` (`k = char_base, char_base+1, …`, one per
part). The start value `char_base` is chosen per character at `loc_8c032a66` from the player
struct **byte at +0xad** (a slot/side selector): **default `9`, or `13` (0x0D) when
+0xad == 1** (a third branch at +0xad == 2 reuses 9). A parallel resolve at `loc_8c032b14`
uses the same +0xad byte with a fixed `8 << 4 = 0x80` directory offset. So:

```
dir_entry(char, part_idx) = dir_base + (char_base + part_idx) * 0x10
char_base = (player[+0xad] == 1) ? 13 : 9      # small fixed constant, NOT dim-matched
```

Each loaded entity (P1 body, P2 body, assist, HUD, stage) gets its **own contiguous key
run**; the +0xad selector keeps the two fighters from colliding. `part_idx` is the offset
within the run. **No dimension matching, no GFX1-order assumption.**

### How the probe applies it (and stays honest)
`maplecast_gamestate.cpp:partDump` reads `player[+0xad]`, picks `char_base = 9` or `13`,
then **validates**: it logs a `±` window of directory entries around the candidate base
(dims + tex ptr) so the true base is visible if an assist/other selector shifts it, and it
dumps the **whole directory with all four u32 fields** (`+0x0` dims, `+0x4`, `+0x8` tex,
`+0xc`) so the `+0x4`/`+0xc` semantics (format vs source-key) can be locked from one capture.
It then walks the character's **current `sprite_id` assembly** from the live EXTRAS
(`player+0x178`, records at `+0x18`, 8-byte stride, `mode==0xFF` ends) and dumps each
referenced part via `dir_entry(char_base + part_idx)`. **First test = the current frame's
parts only.** The full per-character atlas **accumulates across frames** (the probe appends
to `PL{hex}_parts.manifest`, deduping by `part_idx`) — set `MAPLECAST_PARTDUMP=N` to capture
`N` fires (~every 8th in-match frame) as the animation cycles through stances. *(FOLLOW-UP:
to force-cover every `part_idx` deterministically, drive the char through an idle/attack
cycle, or — later — call the loader's key sequence directly. The append+dedupe path already
builds a growing atlas from normal play.)*

### Cross-checks available (Dev Files)
`MVC2 Dev Files/PL{hex}PAK.BIN` is the full per-char DAT (gfx1 @0x20, gfx2, palette, extras).
Use it to (a) confirm a captured part's identity by matching its decoded pixels against the
offline GFX, and (b) build the `sprite_id → cell/slot` resolver from GFX_DATA_01 (441 entries)
for the assembly re-keying (§2.2). The PAKs are present locally (`PL00/PL17/PL2A PAK.BIN`).

### Format branch — FOLLOW THE DESCRIPTOR (e4 is an index, not the format)
The decoded parts in DM00 Poly are in **PVR texture format** — NOT the 4bpp indexed form the
offline codec emits (that 4bpp form is the *pre-upload* scratch at `0x0CE60000`).

**`entry+0x4` (`e4`) is a DESCRIPTOR INDEX, not the format.** The real per-part format is a
PVR Texture Control Word (TCW) reached through a two-level runtime-table indirection, traced
clean-room from the per-entry texture builder `bank12.asm:loc_8c123e00` (driven over the
0x10-stride directory by `bank12.asm:loc_8c1240a0`, which terminates on `e4 == 0xFF`). For
directory key `k` (= `charBase + part_idx`, the loop counter):

```
t1   = *(0x8C2DAD3C)        ; ptr to a u16 index table
u16  = t1[k]               ; mov.w @(t1 + k*2)            (k = r10, loc_8c123e56)
t2   = *(0x8C2DAD4C)        ; ptr to a 0x20-stride descriptor table
desc = t2 + u16*0x20       ; r13 = (u16<<5) + *(0x8C2DAD4C)   (loc_8c123eee)
TCW  = *(desc + 0x0C)      ; mov.l @(0x0C,r13)
fmt  = (TCW >> 27) & 7     ; mov 0xE5,r3; shld r3,r0; and 0x07   (PVR PixelFmt)
scan = (TCW >> 26) & 1     ; ScanOrder: 1 = linear/strided, 0 = twiddled
```

PVR PixelFmt (`ta_structs.h` `union TCW`): 0=1555 1=565 2=4444 5=PAL4 6=PAL8. The texel
pointer is still `entry+0x8` (the texels there are correct — only the format/twiddle was being
mis-read). `entry+0xC` (`ec`) is `0` on the DM00 directory and is **not** the TCW.

The probe (`partResolveTCW`) walks this exact chain per part and writes the resolved **TCW**,
the decoded **fmt/twiddle**, the **descriptor u16 index**, and the **0x20-byte descriptor
bytes** into the manifest (`tcw fmt twid descU16 desc` columns), so the format is verifiable
offline. The tools decode each part with the resolved TCW (`tools/decode_raw_part.py
:tcw_format`), falling back to the e4-byte1 heuristic only if the runtime tables weren't
resolvable (TCW == 0). Twiddle honours the TCW ScanOrder bit. Paletted parts use the dumped
`PL{hex}_palette.bin` (live `Dat_Pal`, 128 banks × 16 ARGB4444). Transparent texels → magenta
in the PPM (PPM has no alpha); the packer keys magenta → alpha 0.

> **History (three rounds).** (1) `e4`-byte1 guess mapped `0x03`→PAL4 — the 256×256 body
> decoded as noise. (2) Read a TCW at `entry+0xC`, but `ec` is `0` on the DM00 directory, so
> every part fell to fmt 0 and the working RGB565 parts broke. (3) **Correct:** `e4` is a
> *descriptor index* (`bank12:loc_8c123e00` does `tex_table + e4*0x3C` for one table and the
> format-TCW chain above for the real format); the format lives in `descriptor+0x0C` of the
> 0x20-stride table at `*(0x8C2DAD4C)`. The e4-byte1 mapping only matched the RGB565 parts by
> coincidence (their descriptor format happened to equal the byte).

### Twiddle (de-Morton) — exact flycast port (the 256×256 body de-scramble)
The de-twiddle is now an **exact port of flycast's `core/rend/texconv.cpp`** (`detwiddle`
table + `twop` + `twiddle_slow`), the same math `mcfx` uses to decode real VRAM. The PVR
interleaves **y-bit first, then x** per pair (`twiddle_slow` checks `y_sz` before `x_sz`):

```
detwiddle[0][s][i] = twiddle_slow(i,0, 1024, 1<<s)   ; x bits, depth gated by y size
detwiddle[1][s][i] = twiddle_slow(0,i, 1<<s, 1024)   ; y bits, depth gated by x size
idx(x,y) = detwiddle[0][bitscanrev(h)][x] + detwiddle[1][bitscanrev(w)][y]
```

The earlier hand-rolled twiddle interleaved **x-first** — a *transpose* of the canonical
order for square textures. That is invisible on small near-symmetric parts but **transposes
the 256×256 body** into the "structured greenish scramble" seen. The probe + tools default
to the canonical (y-first) order; the probe also emits a transposed (`x-first`) preview
`PL{hex}_part_NNN.altTw.ppm` for parts ≥64px, and the packer takes `--twid-large twiddleX`,
so the body can be A/B'd against the oracle `MvC2_Spritesheets_*/PL{hex}.png` without a
redeploy. (If the small parts turn out to need x-first and the body y-first — i.e. DM00 lays
large parts out differently — `--twid-large` pins them independently.)

**Composite-page check.** A 256×256 "part" could be a texture PAGE holding several smaller
sprites (each twiddled in its own sub-rect), which would also scramble under a whole-image
de-twiddle. The probe now dumps the **full 0x3C descriptor** (`desc[0x3C]` manifest column)
so any sub-rect / stride / page-UV field is inspectable offline; if present, the real sprite
rect is decoded from the descriptor instead of the whole 256×256.

---

## 2. The deliverable design

### 2.1 Part atlas (offline-once-per-char, runtime-captured)

Per character, run a one-time capture pass on the headless server:

- **Trigger:** load the character (training/character-select forces the DAT load); detect
  `Dat_GFX1` (player+0x15c) populated and the `0x0CE80000` directory built.
- **Enumerate:** part count from the GFX1 offset table (`table[0]>>2`); per part, read the
  directory entry (`*(0x0CE80008) + idx*0x10`), follow +0x8 to the decoded texels, read
  `sw*sh*64` nibbles.
- **Emit:** `PL{hex}_parts.png` — a packed atlas of all part rectangles (indexed, with a
  rect table), plus `PL{hex}_asm.json` (§2.2). **ROM-derived → gitignored** (`.gitignore`
  already blocks the dasm/Output/Dev-Files trees; the atlas joins them). Never committed.
- **Validation oracle:** composite an assembly from captured parts and diff against the
  community indexed sprite-sheet rip (`MvC2_Spritesheets_*/PL{hex}.png`) — pixel-for-pixel,
  same oracle the codec used. The runtime capture is *exact* (it is the game's own output),
  so this is a sanity check, not a tuning loop.

This replaces the blocked offline LZSS decode entirely as the atlas source. The decoder in
`pldat-codec.mjs` is retained for part-count / dims / self-contained-part cross-checks.

### 2.2 Assembly table (`sprite_id → parts + offsets`)

Precompute offline from EXTRAS + ANIMATION (per `MARVELOUS2-GFX-NOTES.md` §3–4).
**The packer `tools/pack_part_atlas.py` emits exactly this** (validated on PL00):

```
PL{hex}_asm.json = {
  char:    "PL00",
  atlas:   "PL00_parts.png",  atlas_w, atlas_h,
  parts:   { "<part_idx>": {x, y, w, h}, ... },         # rects into PL{hex}_parts.png
  assemblies: {                                          # see keying note below
    "<key>": [ {dx, dy, part, flip, b5, mode} ... ]      # one record per placement
  }
}
```

**Assembly keying — `sprite_id → assembly` (SOLVED from the LIVE CELL).** The GSTA sprite_id
the client keys by is `read16(player+0x144)`. The live log settled what `0x144` is:
`*(player+0x144) = 0x0000005d` — i.e. **0x144 holds the plain sid `0x5d`, not a pointer.** But
`player+0x154` (`current_cell_data`) *is* a valid pointer to the live 20-byte keyframe (log:
`cell=0x0c52ebfc`). The anim tick (`bank03:loc_8c034ed2`) copies that keyframe into
`player+0x140..` via the Duff-copy `bank12:loc_8c1294c8`, so `read16(player+0x144) == keyframe[4]`.
Therefore the re-key reads from the **live cell**:

```
cell      = read32(player+0x154)        ; valid keyframe pointer (live)
live_sid  = read16(cell + 4)            ; == read16(player+0x144), the client's exact key (0x5d)
slot      = read16(cell + 0x12)         ; keyframe -> EXTRAS slot index
records   = EXTRAS(player+0x178) + slot*0x400 + 0x08   ; 8-byte recs, mode==0xFF ends
```

The probe walks those records and writes them keyed by `live_sid` into `PL{hex}_sidasm.txt`
(`<sid> <slot> <nrecs> dx,dy,part,flip;…`); the packer keys `assemblies[live_sid]` from that.
Because `live_sid` comes from the live cell, it matches `read16(player+0x144)` exactly. Across
fires (`MAPLECAST_PARTDUMP=N`) every on-screen sid → its exact assembly accumulates. (If a
slot's assembly is empty the probe dumps the cell's 20 bytes to the log so the slot-field
offset is verifiable.)

> **History (the render blocker, three wrong reads).** (a) Live cell arithmetic
> `(cell-extras-0x18)/0x400` → `slot=-1` for everything. (b) Offline ANIMATION-table scan for
> `sprite_id=keyframe[4]`/`slot=keyframe[0x12]` → 178 mappings, **none matching** the live
> `read16(player+0x144)` (different namespace; idle 0x48 absent). (c) Treating `*(player+0x144)`
> as a pointer (`+0x18`) → the log proved `*(0x144)=0x5d` is the plain sid, so `0x5d+0x18` is
> garbage → 0 records. **Correct:** read the keyframe from the **live cell pointer (0x154)** —
> `keyframe[4]` is the client's exact sid, `keyframe[0x12]` is the verified slot, assembly at
> `EXTRAS+slot*0x400+8`.

`palette`: ship separately (the skin system already handles `Dat_Pal` per char/bank); the
ARGB1555/RGB565 parts captured here are **already colored** (PVR format), so the atlas is
display-ready without a palette step. Recolor (skins) still applies the palette-bank override
as today.

- **EXTRAS walk** (`bank10.asm:loc_8C108060/86`): 8-byte records
  `{dx s16, dy s16, part_idx u8, b5 u8, mode u8, flip u8}`; `mode==0xFF` ends an assembly;
  `flip & 0x80` = horizontal mirror. (Already cracked: 42 assemblies for PL00, parts 0–21.)
- **ANIMATION → assembly**: `sprite_id` (player+0x144) selects the cell; the keyframe table
  (player+0x168, 20-byte records, `sprite_id` at bytes 4–6) resolves `sprite_id → cell →
  EXTRAS assembly`. **The GSTA already ships the resolved `sprite_id`, so no timer emulation
  is needed** — map `sprite_id → assembly index` once, offline.
- **Per-object z from the priority byte**: per `MARVELOUS2-RE-HANDOFF.md §3`, the pool has
  no numeric z; order is category (`record+0x03`) + sprite_id range (cape behind body,
  lightning/super in front). Bake a `z` per assembly from (category, sprite_id band) so the
  client can stable-sort. For the body, z = base layer.

### 2.3 Per-frame wire (unchanged)

The GSTA already carries everything: per body, `sprite_id` + `screen_x/y` + facing +
palette id; per pool object, `sprite_id` + `screen_x/y` + category + xflip (the planned
OBJS 9-byte stride). **No wire change.** Client per frame:

```
for each live object (6 bodies + N pool objects):
    asm = atlas[char_id].assemblies[object.sprite_id]
    for rec in asm:                                   # z-ordered across all objects
        part = atlas[char_id].parts[rec.part_idx]
        x = object.screen_x + (rec.flip^facing ? -rec.dx - part.w : rec.dx) * Sx
        y = object.screen_y + rec.dy * Sy
        blit(part, x, y, hflip = rec.flip ^ facing,
             palette = palette_for(char_id, object.pal_id))   # recolor as today
```

Scale `Sx=1.6667 / Sy=2.1428` (`CpsXScale/CpsYScale` from `work.asm`), zoom=1.

### 2.4 Numbers

| Quantity | Value | Basis |
|---|---|---|
| **Per-frame wire (bodies)** | 261 B/frame → **~15.3 KB/s** | `maplecast_gamestate.h` `WIRE_SIZE=261`, 60fps |
| **Per-frame wire (+ pool objs)** | +9 B/obj; ~20–48 objs typical | OBJS block; worst case ~36 KB/s |
| **Steady-state total** | **~15–36 KB/s** | identical to current GSTA — no change |
| **Atlas per char** | **~0.5–1.5 MB** | ~1500 parts × ~small rects, indexed 4bpp + PNG-deflate; PL00 GFX_00 is 425 KB *compressed on disc*, decoded-then-packed-then-PNG lands ~1 MB |
| **Assembly JSON per char** | **~20–80 KB** | ~42–200 assemblies × ~24 records × small ints + part rects |
| **Total client footprint (59 chars)** | **~60–110 MB** | one-time download, cached locally; ~1–1.8 MB/char |

The atlas downloads **once** (cached, like a texture pack). Steady-state bandwidth is
*only* the ~15–36 KB/s GSTA — the same as today.

---

## 3. Honest comparison: assembly-driven vs texture-cache / stripped-TA

The sibling design ("texture-cache"): keep streaming a stripped TA display list, but ship
texture pixels **once** (client texture cache keyed by TCW/hash), so steady-state frames
carry only geometry + cache references.

| Axis | **Assembly-driven (this doc)** | **Texture-cache / stripped-TA** |
|---|---|---|
| **Steady-state bandwidth** | **Lowest.** ~15–36 KB/s (GSTA only). No geometry on the wire — the client *derives* it from `sprite_id`. | Higher. Per-frame TA geometry (vertices/UVs/poly headers per object) even with cached textures — typically 100s of KB/s. |
| **Pixel-exactness** | Exact *if* the assembly+atlas are faithful. We capture the game's own decoded parts and replay its own assembly list, so geometry is the SH4's geometry. Residual risk = our `sprite_id→assembly` map + scale. | Exact by construction (it's the actual TA output) — modulo whatever the strip drops. |
| **Build effort** | **More.** Runtime part-capture hook, atlas baker, assembly extractor, client assembly renderer, per-char validation, cape/pool object handling. | Less. Mostly a TA-strip + client texture cache; reuses the existing mirror/TA path. |
| **Copyrighted assets on the wire** | **Zero.** Only `sprite_id`+pos cross the wire. Atlas is built locally from the operator's own ROM, gitignored, downloaded by clients from the operator (same trust boundary as today's skins). | **Texture pixels cross the wire** (once, but they do). Those are ROM-derived. Higher exposure. |
| **Cape (and crouch) correctness** | **Definitively fixed.** The cape is a *separate pool object* with its **own `sprite_id`/assembly** (`MARVELOUS2-GFX-NOTES.md §7`). The per-object render loop draws it as "just another object," at its own z, with its own assembly — including its **crouch** cell, because crouch is simply a different `sprite_id` selecting a different cape assembly. We never special-case attach; the object table drives it. | Cape "just works" because it's whatever the TA emitted — but at the cost of streaming its geometry every frame. |

### The cape / crouch confirmation (per-object render handles it exactly)

The whole-sprite branch fought cape-attach because it reconstructed placement from body
state. The assembly-driven model **eliminates that class of bug**: each object (body, cape,
projectile, super overlay) is rendered independently from *its own* `sprite_id → assembly →
parts`, z-ordered by category. Crouch is not a special case — it is the cape object's
`sprite_id` changing to its crouch cell, which selects the crouch assembly automatically.
The only requirement is that the **OBJS pool reader enumerates the cape object** (it does:
pool base `0x8C26AA54`, stride `0x1D0`, owner@+0x80, sprite_id@+0x12C —
`MARVELOUS2-RE-HANDOFF.md §3`). One live capture confirms the cape appears as a sibling
object during a cape frame (`MARVELOUS2-GFX-NOTES.md §7`, final bullet).

### Recommendation

**Assembly-driven wins on our stated goals** (lowest bandwidth, pixel-exact cape, zero
copyrighted assets) — it is the only path that ships *zero* ROM-derived pixels on the wire,
holds steady-state at the ~15–36 KB/s GSTA, and fixes cape/crouch structurally rather than
by special-casing. It costs more build than texture-cache, and carries the residual risk in
the `sprite_id→assembly` map and scale constants (mitigated by the sprite-sheet oracle).
Given the project's identity (compact state, recolorable skins, distributed clients that
already download skin data), **pursue assembly-driven as the primary path; keep the existing
whole-sprite path on `feat/rom-asset-probe` as the working fallback** until the assembly
renderer validates per-character.

---

## 4. Phased build plan

Each phase has a concrete `verify:` check.

- **Phase 0 — Live confirmation of the capture point (read-only, 1 capture).**
  At the box, dump `0x0CE80000..+0x80` and a few `*(dir+idx*0x10+0x8)` targets after a
  character loads. *verify:* the dims at the dest match the offline blob headers (w,h,sw,sh)
  and the first self-contained part (PL00 part 326, the clean 8×8 tile) matches the offline
  decode pixel-for-pixel.

- **Phase 1 — Server part-capture hook.**
  Add a `MAPLECAST_DUMP_PARTS` path in the gamestate/mirror layer: on character load, walk
  the directory, read each part's texels, write `PL{hex}_parts.png` + rect table (gitignored).
  *verify:* re-run on PL00; composite assembly 0 from captured parts and diff against
  `MvC2_Spritesheets_*/PL00.png` — zero mismatched non-transparent pixels.

- **Phase 2 — Assembly extractor.**
  Offline tool: EXTRAS grouping + ANIMATION keyframe map → `PL{hex}_asm.json`
  (`sprite_id → [{part_idx,dx,dy,flip,z}]` + part rects + palette).
  *verify:* every `sprite_id` the GSTA emits for PL00 in a recorded match resolves to a
  non-empty assembly; composited frames match the sprite sheet.

- **Phase 3 — Client assembly renderer.**
  In `sprite-client.mjs` / `sprite-gpu.mjs`: per object, `sprite_id → assembly → parts`,
  z-ordered by category, flip = facing XOR record bit, scale `CpsX/CpsY`, palette recolor as
  today. Replaces whole-sprite draw for body **and** each pool object.
  *verify:* side-by-side a recorded match vs the real game frame; body + projectiles align.

- **Phase 4 — Cape / crouch.**
  Ensure the OBJS reader ships cape objects; client renders them as independent objects.
  *verify:* a cape character (Magneto/Storm/Doom) crouches and the cape follows exactly,
  with correct z (behind body); no attach special-case in the code.

- **Phase 5 — Roster bake.**
  Run the Phase-1 hook across all 59 PAKs → atlas + assembly JSON per char (gitignored).
  Client lazy-loads per character.
  *verify:* every roster character renders from state alone; steady-state bandwidth unchanged
  (~15–36 KB/s, `MAPLECAST_DUMP_TA=1` determinism rig clean at phase end).

---

## 4b. Running the capture (operator steps)

The capture needs the game running **in a match** (the directory at `0x0CE80000` is only
populated once a character's DAT has loaded). The probe is **read-only and one-shot** — it
fires the first in-match frame after the directory is built, then disables itself.

**On the box (build is `cmake --build build-headless --target flycast`, deploy is**
**`scp build-headless/flycast root@149.28.44.118:/usr/local/bin/flycast` — COORDINATE deploys):**

```bash
# 1. Enable the probe via env on the headless service.
#    MAPLECAST_PARTDUMP=1  -> single-frame capture (current assembly only).
#    MAPLECAST_PARTDUMP=N  -> N captures, ~every 8th in-match frame (accumulates the
#                            atlas across stances; manifest is appended + deduped).
MAPLECAST_PARTDUMP=40 /usr/local/bin/flycast ...   # (or set in maplecast-headless.service)
sudo systemctl restart maplecast-headless

# 2. Play the target character (training/versus). With N>1, move/attack so the animation
#    cycles through more part_idx. Outputs land in /dev/shm:
#      /dev/shm/mc_partdump.log              — FULL directory dump (all 4 u32 fields/entry)
#                                              + per-char base + a ±window around the base
#      /dev/shm/mc_partdump_sidtrace.log     — one [FIRE] line per capture: live sid +
#                                              part_idx list (append-only; see it change)
#      /dev/shm/PL{hex}_parts.manifest       — "part_idx key raw ppm w h e4 texptr ec"
#      /dev/shm/PL{hex}_part_NNN.raw          — RAW texels w*h*2 LE (no decode) — AUTHORITATIVE
#      /dev/shm/PL{hex}_part_NNN.ppm          — best-effort preview (magenta = transparent)
#      /dev/shm/PL{hex}_extras.bin            — 16KB live EXTRAS assembly region

# 3a. LOCK THE PIXEL FORMAT once, offline, from a .raw (no redeploy per guess):
python3 tools/decode_raw_part.py --in /dev/shm --char 2A --part 0   # all fmt x twiddle combos
#   open the PNGs, pick the clean one (e.g. argb1555/linear) — that's the locked format.

# 3b. Pack the atlas + assembly JSON. Default uses the PPM preview; pass the locked
#     --fmt/--twid to build from the authoritative .raw instead:
python3 tools/pack_part_atlas.py --char 2A --in /dev/shm --out /tmp --fmt argb1555 --twid linear
python3 tools/pack_part_atlas.py --char 00 --in /dev/shm --out /tmp \
    --validate MvC2_Spritesheets_20260516/PL00.png --asm-slot <slot>
#   -> /tmp/PL{hex}_parts.png, /tmp/PL{hex}_asm.json, /tmp/PL{hex}_composite_slot<slot>.png

# 4. DISABLE the probe when done (unset MAPLECAST_PARTDUMP, restart) — it is a dev probe.
```

**Reading `mc_partdump.log` / `mc_partdump_sidtrace.log`:**
- `[DIR]` lines list every directory entry with all four u32 fields (`e0` dims, `e4`, tex
  `e8`, `ec`). Use these + the `.raw` decode to lock the format. (Observed so far: HUD
  128×128/64×64 = ARGB1555 + 12-bit square twiddle; large char body textures looked
  scrambled under that — likely LINEAR, and the `e4` low byte `0x01` may be a flag with the
  *next* byte the real format. The `.raw` dump + `decode_raw_part.py` settle it.)
- `[CHAR]` lines report `sel@0xad`, the chosen `charBase` (9 or 13), the live `sid`,
  `cell(0x154)` / `extras(0x178)`, and a **base window** (`key N: WxH tex=…  <= base`).
  Confirmed: Storm `charBase=9` is a clean contiguous run (key9=256×256 body, keys10–21=32×32,
  keys22–24=128×128).
- `mc_partdump_sidtrace.log` `[FIRE]` lines show `sid=… parts=…` per capture, so you can see
  the part set track `sid` and grow across fires.

**Why the part set now grows:** the probe scans **all 0x400-byte EXTRAS slots** (each slot =
one assembly), not just slot 0 (the old bug pinned it to one fixed assembly). The per-fire
`sid` log lets you correlate which slot is live; the accumulated manifest covers the full set.

**Outputs are ROM-derived → `/dev/shm` and `/tmp` only, gitignored, NEVER committed.**
Only the probe code (`maplecast_gamestate.cpp`), the packer + raw decoder (`tools/*.py`),
and this doc are committable.

---

## 5. Citations (into the local, gitignored marvelous2 clone — re-grep to extend)

| Fact | Where |
|---|---|
| Per-part decode loop, scratch dest `0x0CE60000`, copy-out loops | `bank03.asm:loc_8c032696` (~5668), const `loc_8c032854` |
| **Dir key → entry: `entry = *(r6+8) + (k<<4)`, dest = `*(entry+8)`** | `bank03.asm:loc_8c0322c0` (5069) |
| **Body-parts loader: key = incrementing counter `r11` from `char_base`** | `bank03.asm:loc_8c032ae0` (6330) |
| **`char_base` = `(player[+0xad]==1) ? 13 : 9`** (slot/side selector) | `bank03.asm:loc_8c032a66` (6252), `loc_8c032b14` (6360) |
| File-load stage path (`0x0CC00000` staged GFX) | `bank03.asm:loc_8c0323b2` (5221) |
| Scratch = `Texture_Decompress_Buffer`; `0x0CE80000` = DM00 Poly | `memory/work.asm:36-39` |
| GFX directory base read from work header `*(0x0CE80008)` | `bank03.asm` decode loop (`r8 = @(0x8,r4)`, r4=`0x0ce80000`) |
| LZSS decoder (codec) | `bank03.asm:loc_8c03552a` (12740) |
| **`e4` is a DESCRIPTOR INDEX, not the format** (dir walk terminates on `e4==0xFF`) | `bank12.asm:loc_8c1240a0`, `loc_8c123e00` |
| **Real format = TCW chain: `u16=(*0x8C2DAD3C)[k]`; `TCW=(*0x8C2DAD4C)[u16*0x20+0x0C]`; `fmt=(TCW>>27)&7`, `scan=(TCW>>26)&1`** | `bank12.asm:loc_8c123e56`/`loc_8c123eee` (`mov 0xE5,r3;shld;and 0x07`); flycast `ta_structs.h union TCW` |
| **De-twiddle = flycast `detwiddle`/`twop` (y-bit first); x-first transposes large square parts** | flycast `core/rend/texconv.cpp` `twiddle_slow`/`twop`; matches `mcfx` (maplecast_mirror.cpp) |
| EXTRAS list iterator / 8-byte records / `mode==0xFF` | `bank10.asm:loc_8C108060/86`; `MARVELOUS2-GFX-NOTES.md §3` |
| `sprite_id`→cell→assembly; 20-byte keyframes | `bank03.asm:loc_8c034dee` (11567); `MARVELOUS2-GFX-NOTES.md §4` |
| **Re-key from LIVE cell: `cell=read32(0x154)`; `sid=read16(cell+4)==read16(0x144)`; `slot=read16(cell+0x12)`; asm @ `EXTRAS+slot*0x400+8`** | keyframe→`0x140` copy `bank12:loc_8c1294c8`; live log `*(0x144)=0x5d` (plain sid), `cell=0x0c52ebfc` (valid ptr) |
| Pool base/stride; cape = separate object | `bank04.asm:loc_8c044dce`; `MARVELOUS2-RE-HANDOFF.md §3`, `GFX-NOTES §7` |
| Scale constants `CpsXScale/CpsYScale` | `memory/work.asm:44-45` |
| Mirror reads `mem_b[]` / `vram[]`; gamestate `addrspace::read*` | `core/network/maplecast_mirror.cpp:529`; `maplecast_gamestate.cpp` |
| GSTA wire size 261 B/frame | `core/network/maplecast_gamestate.h:80` |
