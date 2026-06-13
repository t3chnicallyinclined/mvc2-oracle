# Workstream: the Memory Map Visualizer

Build plan for `web/panels/memmap-panel.mjs` + its data feed. Design: `IDEAS-MEMORY-MAP-VIZ.md`.
Grounded in a confirmed audit of the existing change-tracking infra (cites below). Ordering is by
dependency + risk, **not** time estimates.

## What we reuse vs build (audited, cited)

| Capability | Status | Source | Heatmap use |
|---|---|---|---|
| **VRAM dirty pages** (4KB, region 1, per-frame memcmp + DMA bitmap) | **FREE** | `core/network/maplecast_mirror.cpp` `serverPublish()` (memcmp loop + `_vramDirtyBitmap`) | direct — already on the wire |
| **Full-RAM snapshot** (baseline) | **FREE** | `maplecast_mirror.cpp` `buildFullSaveState()` → `dc_serialize()`; SYNC/MCSV transport | the heatmap seed |
| **State-sync full blobs** (port 7102) | **FREE** | `core/network/maplecast_state_sync.cpp` `broadcastFreshState()` | late-join / baseline, not deltas |
| **Main-RAM dirty pages** (0x0C…, 16 MB) | **BUILD** (machinery exists) | skipped in `initRegions()`; but `core/hw/mem/mem_watch.h` `RamWatcher`/`memwatch::writeAccess` already page-protects RAM for GGPO | mirror the VRAM shadow+memcmp, OR wire `RamWatcher` → per-frame dirty set |
| **ROM/data-access flashes** | **CHEAP** (reuse hooks) | decode hooks `DECODETRACE` @ `0x8C03552A`/`0x8C0354C0`, `PARTDUMP` | flash the GFX/PLDAT source region on a decode burst |
| **WRITE activity by page** | **CHEAP / LIVE** | `core/hw/mem/mem_watch.h` `RamWatcher` page-protect — fault-driven, already runs live for GGPO | live write-heat, no per-op tax |
| **READ attribution by address** | **DEFER** (volume-bound) | none — instrumenting every load = ~millions of ops/frame | per-address *read* tracking only; sample or record-then-scrub |

> **The expensive thing is granularity, not "live."** ASMTRACE and the Oracle hooks already run on the live
> game fine because they fire at **one bounded PC** (~tens of times/frame). The dirty-page diff is the same
> class of cheap-live mechanism (it IS the 60fps TA mirror). Writes are cheap too (page-fault driven). The
> ONLY expensive capture is **per-address reads** — because that's every load instruction (~millions/frame),
> not because it's live. And this is a **dev/RE tool gated OFF for prod**, so even a 16 MB/frame memcmp is
> fine on a dev box.

**Verdict:** the whole heat/value/write-activity/ROM-flash/semantic view runs **live and cheap** — VRAM is
free today, main-RAM write-heat is a small `RamWatcher`-backed add, baseline + value are free, labels are a
static `re_kb` overlay. The **only** deferred piece is **per-address read attribution** (volume-bound; do it
by sampling or record-then-scrub).

## Data-feed architecture

```
flycast (hooked)                                wire                         dashboard
─────────────────                               ────                         ─────────
serverPublish():                                                             memmap-panel.mjs
  VRAM memcmp+DMA bitmap ─┐                                                   ┌─ memory model (sparse)
  RAM shadow/RamWatcher ──┼─► dirty page set ──► MEMMAP frame ──(WS)──────────┤  baseline + dirty deltas
  (NEW, env-gated)        │   {region,pageIdx,                                │
buildFullSaveState() ─────┘    [+pageData | +changeMeta]}                     ├─ WebGPU textures:
  full baseline ──────────────► MMBASE (once) ──(WS)─────────────────────────┤   value · heat · access
decode hooks ───────────────► access events ──(WS)──────────────────────────┘   (decay in-shader)
                                                                             re_kb label manifest ──► hue
```

Two wire modes (env/handshake-selected):
- **HEAT mode (lean):** ship only `{region, pageIdx, changedByteCount|hash}` per dirty page — NOT the 4KB
  payload. The heatmap mostly needs *which* pages changed, not their bytes. Big bandwidth win.
- **VALUE mode (full):** ship the 4KB page payload (the existing format) when the user wants hover-values
  or the value color mode. Reuse the existing `regionId(1)+pageIdx(4)+pageData(4096)` struct verbatim.

## Tracks

### Track A — Backend memory-change feed (flycast side; carried via hook/ + patch/)
- **A1. VRAM dirty list (FREE).** Expose `serverPublish()`'s per-frame dirty-page set to a MEMMAP consumer.
- **A2. Main-RAM dirty feed (BUILD).** Add a RAM region to the diff: either (i) `_shadowRAM` + per-frame
  memcmp mirroring the VRAM path, or (ii) wire the existing `RamWatcher` page-protect to emit the dirty
  set without a 16 MB memcmp. **Env-gated** (`MAPLECAST_MEMMAP`), default OFF (determinism-safe; this is
  READ-ONLY diffing of state we already snapshot, never injection). Mitigate cost: sample every Nth frame.
- **A3. Baseline (FREE).** Ship a full-RAM snapshot once via `buildFullSaveState()` as the MMBASE seed.
- **A4. ROM-access flashes (CHEAP).** Emit decode-region access events from the existing decode hooks.

### Track B — Wire / transport
- **B1.** Define the MEMMAP frame: reuse the dirty-page struct; add a region id for main RAM; add the HEAT
  vs VALUE mode flag.
- **B2.** HEAT-mode encoding (page index + changed-byte-count/hash only).
- **B3.** MMBASE baseline transport (reuse the SYNC/MCSV full-snapshot path).

### Track C0 — Preserve the RE debugger (do this when the dashboard shell lands)
**Port the DIFF-v7 / RE COCKPIT from `web/webgpu-test.html` verbatim** into clean panel modules
(`diff-panel.mjs` = `diffTick`/`objDeltas`/`alignHost`; `etl-panel.mjs` = `classify()`), including the
**WebGPU mirror-canvas readback fix**. It's the most battle-tested code we have for "what's on screen and
who owns it"; the Linked View (`IDEAS-LINKED-VIEW.md`) re-keys its tint from truth-vs-ours to object-identity.
Don't re-derive it.

### Track C — Frontend panel (`web/panels/memmap-panel.mjs`)
- **C1.** Frame-bus integration: apply MMBASE then per-frame dirty deltas into a sparse client memory model.
- **C2.** Address→(x,y) LUT: region tree (from `re_kb`) → squarified treemap → Hilbert/Gilbert per box
  (the hybrid default). Precompute once per layout config.
- **C3.** WebGPU textures (value / write-recency / access-flags); fragment shader → color per mode;
  in-shader heat decay; sparse per-frame updates from the dirty set. Render to an **offscreen target**
  (the dashboard swap-chain readback rule).
- **C4.** Hover/click: address + value (hex/dec/float) + `re_kb` label + last-write frame + write-count;
  click → pin to WATCH / jump struct inspector; drag → zoom; shift-click → set diff baseline.

### Track D — Semantic knowledge layer
- **D1.** Export `re_kb` → a **label manifest** (address ranges → class/field) that drives BOTH the layout
  region tree AND the semantic hue. Static; regenerated when `re_kb` changes. Zero runtime cost.
- **D2.** Fold anotak attack/anim field semantics into the manifest.
- **D3.** Coverage meter (% labeled per region) + click-to-label → upsert a stub `re_kb` node (closes the
  loop: the viz feeds the graph).

## Milestones (dependency order; each is demoable)
1. **M1 — VRAM activity radar (free data).** A1 + minimal C1–C3 (linear layout) + A3 baseline. Proves the
   pipeline end-to-end with zero new backend. *Risk: low.*
2. **M2 — Full address-space map.** A2 + B1/B2 (main-RAM dirty feed) → watch RAM change live.
   *Risk: the 16 MB diff cost — mitigated by env-gate + RamWatcher reuse + frame sampling.*
3. **M3 — Labeled atlas.** D1/D2 (semantic manifest) + C2 hybrid treemap-Hilbert layout + coverage meter.
   The "paint by meaning" view; the un-RE'd frontier becomes visible.
4. **M4 — Interactive RE loop.** C4 interactions + D3 click-to-label + A4 ROM-access flashes +
   move-reachability tint.
5. **M5 (future) — per-address READ attribution.** Volume-bound (every load ~millions/frame); do it by
   sampling or a "record-then-scrub" offline mode. NOTE: *writes* and the entire heat view are live-cheap
   and land in M1–M2 — only per-address *reads* are deferred here.

## MVP (M1) approach
Build `web/panels/memmap-panel.mjs` as a **self-contained module with a pluggable data source**, driven
first by a **synthetic source** (simulated per-frame dirty pages) so it runs in a browser with **zero
emulator**. Page granularity (4 KB), linear row-major layout, **Canvas2D** heat render with decay, hover →
address + value. Known regions (char structs, globals, object pool, decode scratch) tinted from the memory
map so structure is visible immediately. The real dirty-page source (the wire feed) plugs into the same
source interface later; WebGPU + Hilbert layout are the scale-up after the concept is proven.

## Risks / open items
- **Main-RAM diff cost.** Full 16 MB memcmp/frame is heavy; prefer `RamWatcher` page-protect (writes only,
  no scan) and/or sample every Nth frame. Always env-gated so prod stays byte-stock.
- **Determinism.** The feed is READ-ONLY (diffing snapshots we already take) — never a guest write. Gate OFF
  by default per the cardinal rule.
- **Bandwidth.** HEAT mode (page metadata only) keeps the full-RAM feed lean; VALUE mode is opt-in.
- **WebGPU offscreen/readback** discipline (shared dashboard gotcha) — render to offscreen targets.
- **Decision:** does M2 reuse `RamWatcher` (no memcmp, GGPO-coupled) or clone the VRAM shadow loop
  (independent, simpler, costs a 16 MB memcmp)? Lean `RamWatcher` if it can run decoupled from GGPO.
