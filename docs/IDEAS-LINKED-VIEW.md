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
> Being expanded by `mvc2-sh4-re-expert` (background): the per-object memory footprint table (char slots
> 0x8C268340/stride 0x5A4; pool nodes 0x8C26AA54/stride 0x1D0), the stable identity→color key, the
> authoritative live screen-rect source (+0xE0/+0xE4 / OBJS wire / Frame Oracle), the live data flow, and
> the **granularity** call. The known crux: the 6 char structs and the pool nodes are all **sub-4KB-page**,
> so page-granularity heat can't separate them — the linked view almost certainly needs **sub-page
> (field/struct-level) resolution** for the labeled regions, even while the broad radar stays at 4KB.
> [agent spec folds in here]

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
