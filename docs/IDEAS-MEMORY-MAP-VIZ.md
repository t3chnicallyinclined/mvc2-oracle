# Idea: the Memory Map Visualizer ("memory weather radar")

A WinDirStat-style, color-coded, pixel-dense view of the SH4 address space, live and frame-stepped.
Each pixel = a memory cell (or a block of N bytes). Hover → address + value + RE label. Per frame:
cells that **changed** glow; **ROM/data reads** flash at their source. Status: **idea / Phase 4+**.
Target component: `web/panels/memmap-panel.mjs`.

## Why it's powerful for RE
- **See structure emerge.** Address-ordered, the 6 char structs (0x8C268340, stride 0x5A4) appear as
  six identical bands; the object pool (0x8C26AA54, stride 0x1D0) as a ladder; the slot table as a
  block. You *see* the layout, not just read offsets.
- **See behavior.** A super freeze, a tag-in, a projectile spawn each have a write signature. Watching
  the heatmap during a known action localizes the responsible fields faster than a static diff.
- **See the ROM working.** When the game decodes Ryu's parts, the GFX/PLDAT data region lights up —
  you watch on-demand asset streaming happen.

## The address space (what we map; ground truth = docs/MVC2-MEMORY-MAP.md + re_kb)
- **Main RAM** 0x0C000000, 16 MB (cached mirror 0x8C000000) — the bulk; the char structs, globals,
  object pool, the decode scratch 0x0CE60000, the SPL overlay 0x0CE30000.
- **VRAM** 8 MB, **PVR regs** 32 KB — already shipped as dirty-page diffs on the mirror wire
  (region 1 = VRAM, region 3 = PVR).
- **ROM / data files** — the source the decoder reads (PLxx_DAT/GFX/PAL). Reads here = "asset access."

## Layouts (expose as a toggle)
1. **Linear row-major** — address order, row by row. Simplest; preserves the contiguous-band locality
   above. 1 byte/px over 16 MB = a 4096×4096 texture (fine for WebGPU); coarser block sizes shrink it.
2. **Hilbert curve** — maps the 1-D address line onto 2-D so *nearby pixels = nearby addresses* in both
   axes (the WinDirStat-ish locality trick). Best for spotting clustered activity.
3. **Region treemap** — partition by known regions (RAM / VRAM / PVR / ROM-data / char-page / pool /
   slot-table) sized by byte-extent, like WinDirStat folders; click a region to drill/zoom in.

## Color modes (the core "what does a pixel mean" knob)
- **Value** — grayscale or palette of the byte/word value (reveals text, zeros, data patterns).
- **Write-heat / recency** — recently-written cells glow, decaying over N frames. The "what's changing"
  view. (Primary mode for frame-stepping.)
- **Access type** — read (blue) / write (red) / instruction-fetch (green) / **ROM-or-data read (yellow)**.
  Shows *how* a cell is used, not just that it changed.
- **RE label (knowledge overlay)** — color by `re_kb` node type: char-field, engine-owned pointer
  cluster (0x154–0x184), global, buffer, unknown(gray). Projects the knowledge graph onto memory.
- **Region / owner** — color by which struct/slot/object owns the cell.

## Knobs / configuration to expose
| Knob | Options |
|------|---------|
| **Block size** (bytes/pixel) | 1 · 16 · 64 · 256 · 4096(page) — trades detail for whole-RAM overview |
| **Layout** | linear row-major · Hilbert · region-treemap |
| **Address window** | full 16 MB · a named region · custom `[start,len]` zoom |
| **Color mode** | value · write-heat · access-type · RE-label · region-owner |
| **Heat decay** | frames until a write-glow fades (1 = strobe, ∞ = cumulative "ever touched") |
| **Block aggregation** (when >1 byte/px) | any-changed · change-count · mean-value · OR-of-access-flags |
| **Diff baseline** | vs previous frame · vs a pinned snapshot · vs match-start |
| **Change threshold** | hide cells changed < N times (mute noisy counters) / show only static / show only volatile |
| **Overlays (toggles)** | re_kb labels · the 6 char-struct bands · object pool · slot table · ROM-access flashes |
| **Frame control** | shared with the dashboard transport bar (pause / step / scrub) — diff any two frames |
| **Region mask** | include/exclude RAM · VRAM · PVR · ROM-data |

## Hover / click interactions
- **Hover** → address (hex), raw value (hex/dec, + u16/u32/float interpretations), the `re_kb` label +
  note, **last-write frame**, **write-count**, owning struct/field (if known).
- **Click** → pin to a watch list (ties into the WATCH probe) and/or jump the **struct inspector** to
  that address. Shift-click → set the diff baseline to here.
- **Drag-select** → zoom the address window to the selection.

## Data pipeline (how it gets fed)
- **What changed** — reuse the dirty-page mechanism: VRAM/PVR already ship as region-tagged dirty pages
  on the mirror wire; extend a **main-RAM dirty-page feed** (the state-sync/replica path already
  snapshots RAM — confirm what it exposes). Per frame the panel updates only the dirty pages (sparse).
- **Access type** — heavier: needs the dynarec mem ops or `addrspace` read/write wrappers to emit
  read/write/fetch events. Offer it as a **sampling mode** (every Nth frame) to bound cost. ROM/data
  reads can be lit cheaply from the **decode-hook events we already have** (DECODETRACE @ 0x8C03552A/
  0x8C0354C0, PARTDUMP) — a decode burst → flash the source data region.
- **Full baseline** — the SYNC frame already ships a full VRAM snapshot; a periodic full-RAM snapshot
  seeds the map, then dirty pages keep it live.
- **Render** — a WebGPU R8/R32 texture per channel (value, write-recency, access-flags); a fragment/
  compute shader maps block→color per the selected mode; decay applied in-shader; hover reads back one
  block. 16 MB at 1 B/px is a single 4096² texture — cheap; updates are sparse (dirty set only).

## Open questions / risks
- Does the replica/state-sync path expose **main-RAM dirty pages**, or only VRAM? (Determines whether
  the "what changed in RAM" view is free or needs a new feed.) — confirm in the MapleCast wire code.
- Access-type capture cost: full read/write tracing may be too heavy for 60 fps live — sampling or a
  "record-then-scrub" mode (capture access events to a file, visualize offline) may be the realistic path.
- Hilbert mapping + arbitrary block size needs a clean address↔pixel function (precompute a LUT).
- All of this is RAM/VRAM state → **not ROM-derived to display**, but a saved capture file IS (gitignored).
