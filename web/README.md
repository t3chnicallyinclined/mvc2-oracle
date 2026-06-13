# web/ — the live RE dashboard

A single-page WebGPU dashboard with a **frame bus** (one per-frame snapshot fed by the live WS mirror,
the Oracle tail-WS, or a recorded capture). Rebuilt clean; reuses proven logic.

- `dashboard.html` — the shell (panel grid + transport bar). Phase 2.
- `panels/` — `diff-panel.mjs`, `etl-panel.mjs`, `struct-inspector.mjs`, `watch-panel.mjs`,
  `asmtrace-overlay.mjs`, `controls.mjs`, and (planned) **`memmap-panel.mjs`** — the color-coded
  memory-map visualizer (see `../docs/IDEAS-MEMORY-MAP-VIZ.md`).
- `webgpu/` — reused as-is: `pvr2-renderer.mjs` (TA truth → offscreen renderTarget), `sprite-client.mjs`
  (state model + wire intakes), `sprite-gpu.mjs` (reconstruction), `transport.mjs` (live ingest).

Panels: TA-truth · Reconstruct · DIFF v7 (tint green/red/yellow) · Struct inspector · WATCH RAM-diff ·
ASMTRACE pen overlay · Memory map. Transport: pause / step / scrub.

Gotchas: render to **offscreen renderTargets** (WebGPU swap-chain textures are consumed on present —
the diff must read mirrors/offscreen, never the live canvas). Use a single serve-time `?v=` to avoid
per-file cache drift. The RE panels must **degrade gracefully with no atlas art** (TA truth, struct
inspector, WATCH, memory map are all self-contained; only Reconstruct needs decoded sprites).
