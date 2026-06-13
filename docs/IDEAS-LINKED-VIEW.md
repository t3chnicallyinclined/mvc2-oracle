# Idea: the Linked View — game ↔ memory, one tint

Stack the live game render on **top** and the memory-map radar on the **bottom**, and **tint every
on-screen object the same color in both views**. Hover/select Magneto and his char struct lights up on
the map; watch him throw a projectile and see the pool node + his struct flare. It makes the
pixels↔memory correspondence *visible* — the single most powerful thing an RE dashboard can show.
Status: **idea / builds on M1 + the dashboard**. Components: `web/panels/linked-view.mjs` (new),
reuses `memmap-panel.mjs` + the ported DIFF-v7 tint debugger.

## Reuse the RE debugger from `webgpu-test.html` — it's proven, don't rebuild blind
The DIFF OVERLAY v7 / RE COCKPIT in `web/webgpu-test.html` already does the hard parts: the **tint
compositing** (luminance-masked green/red/yellow), the per-object attribution (`classify()` bins every
TA poly to the nearest GSTA object), the per-object Δ readout (`objDeltas()`), and the **WebGPU
mirror-canvas readback fix** (swap-chain textures are consumed on present → read 2D mirrors). **Port
this verbatim into the dashboard** as clean panel modules (`diff-panel.mjs`, `etl-panel.mjs`) rather
than re-deriving — it's the most battle-tested code we have for "what's on screen and who owns it."
The linked view's screen-tint is exactly this tint machinery, re-keyed from truth-vs-ours to
**object-identity**.

## The concept
- **Top — game view.** The reconstructed render (`sprite-client` + `sprite-gpu`) or TA-truth
  (`pvr2-renderer`), with a tint overlay: each object's on-screen rect washed in its identity color.
- **Bottom — memory radar.** The `memmap-panel` heat grid, but each object's **memory footprint** is
  outlined/washed in the *same* identity color. The heat still shows what changed; the tint shows *whose*.
- **One color table.** A single object→color map drives both overlays. Magneto = hue A on screen AND on
  his struct's cells; his projectile = a related shade on screen AND on its pool node's cells.

## Interactions
- **Hover an on-screen object** → its memory footprint highlights on the map (others dim).
- **Hover a memory region** → the owning object's on-screen rect highlights (reverse link).
- **Select/pin** an object → lock its tint in both views, follow it across frames; pin its struct to the
  WATCH panel.
- **"Owned + changed"** → an object's footprint washed in its color, with the sub-cells that *also*
  changed this frame flared hot — "his struct lit up the frame he threw it."
- **Step/scrub** (shared transport) → watch the tint + heat evolve frame-by-frame.

## Object ↔ memory ↔ screen correlation (spec)
Confirmed against `re-catalog/00-README.md`, `tools/re_kb/02_char_struct.surql`, and
`core/network/maplecast_gamestate.cpp` (`readAllDrawn`, the `slotShadow`/`offChanged` diff machinery).

**1. Per-object memory footprint.**
- **6 character slots** — base `0x8C268340`, stride `0x5A4`, interleaved P1C1/P2C1/P1C2/P2C2/P1C3/P2C3
  (bases `…340/…8E4/…E88/…42C/…9D0/…F74`); full span `0x8C268340..0x8C26A518`. Split each `0x5A4` into a
  **LOGICAL band** (the discrete player-driven fields — `+0x144` sprite_id, `+0x34/38` pos, `+0xE0/E4`
  screen, `+0x110` facing, `+0x142` anim_timer, `+0x151` RenderExtra, `+0x420` health, …) and the
  **ENGINE cluster `[+0x154, 0x30]`** which the engine rewrites *every* frame → **heat noise; render it
  desaturated/striped** so "engine touched pointers" ≠ "player did something."
- **Pool objects** — base `0x8C26AA54`, stride `0x1D0`, 256 nodes. **Live set = `readAllDrawn()`** (the
  slot-table walk the renderer itself uses: counts @ `0x8C2895E0`, ptr array @ `0x8C287DE0`), NOT a static
  256-sweep. Footprint = `{ [N, 0x1D0] for N in readAllDrawn() }`.
- **Shared regions shown SEPARATELY (3-tier radar):** (1) per-object owned bands (tinted), (2) draw-list
  bookkeeping `0x8C2895E0`/`0x8C287DE0` (neutral), (3) globals `0x8C289000` + asset/DAT data the
  `+0x15C/160/164` pointers reference (neutral; shared per-*character*, not per-slot). Never heat-attribute
  shared regions to one object.

**2. Identity → color (same function drives both views).**
- **Bodies: key by SLOT INDEX 0–5**, NOT character_id (a mirror match has two of the same id → collision).
  Slot base never moves mid-match → rock-stable.
- **Projectiles/effects: inherit the OWNER's color** — resolve owner via `node+0x80` → match to one of the
  6 bases → slot index; vary lightness per node for siblings. **Capes: owner's exact hue.** Owner-less
  globals: neutral palette keyed by `category@+0x3`.
- `objectColor(node) = slotColor(indexOf(read_u32(node+0x80) in the 6 bases))`, else `neutral(cat)`. Keying
  on owner-slot (not the ephemeral node address) survives the free-list **node reuse**.

**3. Screen rect (top-view tint).** Use the **OBJS-wire `+0xE0/+0xE4` anchor** (authoritative — it's what
the GPU receives, already live on the wire) as the origin; derive the box from the baked atlas dims for
that `sprite_id` (+ facing/scale) — cheap, no capture. High-detail toggle: ASMTRACE/CHARQ per-part quads
(pixel-tight, but gated/not-live). Never use world `+0x34/38` (pre-transform).

**4. Live data flow + the ONE wire change.** `identity → {screen rect from OBJS/GSTA wire, memory range
from static layout}`. We already have GSTA (6 bodies) + OBJS (satellites). **Missing: add `node_base(u32)`
+ `owner_base(u32)` to each OBJS entry** — both already in hand inside `readAllDrawn`; without `node_base`
the client can't draw `[N,0x1D0]`, without `owner_base` it can't color-link a projectile to its owner.
(Confirm against the OBJS serializer; this is the single blocking wire change.)

**5. Granularity — the decisive call: FIELD-level, not page heat.** All 6 structs pack into ~2–3 pages and a
pool node is 464 B (~9/page), so 4 KB-page heat **cannot** separate objects. The machinery already exists:
`gamestate.cpp` `slotShadow[6][0x5A4]` + `offChanged[0x5A4]` already diff **per-offset within each struct**
every frame (cost: 6×`0x5A4` memcmp). Extend the same shadow-diff to live nodes (`nodeShadow[N][0x1D0]`,
~tens of nodes). **"Owned + changed" overlay** = static footprint at low alpha + **flare the specific
changed offsets** at full alpha; suppress the `+0x154..184` cluster. Cost ≈ 8.6 KB + ~15 KB shadow +
equivalent memcmp/frame — negligible; ship a changed-offset RLE (tiny).

**6. Risks.** READ-ONLY/determinism (viewer only — never write SH4 RAM, per cardinal rule 4). **Node-reuse
aliasing**: reset `nodeShadow[N]` when its `+0x80` owner or `+0x3` category changes (new object, not a
change). Owner-less globals → neutral, no owner band. Engine-cluster noise → demote visually.

**Follow-ups:** UPSERT this as a new `re_kb` finding (the identity→color function + field-granularity
recommendation); flag a `contribution_candidate` if the OBJS wire gains `owner_base`.

## Why this needs finer granularity than M1
M1's radar is 4KB/page (free, from the dirty-page wire). But the whole point of the linked view is
per-OBJECT resolution, and a char struct (1444 B) or pool node (464 B) is a fraction of a page. So the
labeled/linked regions need a **sub-page model**: render the char-page and pool-page zoomed, one cell
per struct (or per field), driven by the static layout + (for "changed") a finer diff than 4KB pages.
This is the natural bridge to the **semantic taxonomy** in `IDEAS-MEMORY-MAP-VIZ.md` (paint by meaning) —
the linked view is that taxonomy, keyed by *object instance* instead of *field class*.

## Dependencies / sequencing
Builds on: M1 radar (done), the ported DIFF-v7 tint (port task), the GSTA/OBJS wire (identity + screen),
and a sub-page diff for the labeled regions (small — those pages are tiny). Slots in after the dashboard
shell + the live feed land. See `WORKSTREAM-MEMORY-MAP.md`.
