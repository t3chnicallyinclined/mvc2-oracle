# web/ — the live RE dashboard

A single-page WebGPU dashboard with a **frame bus** (one per-frame snapshot fed by the live WS mirror,
the Oracle tail-WS, or a recorded capture). Rebuilt clean; reuses proven logic.

- `dashboard.html` — the shell. Today it runs on a synthetic demo feed (`linked-source-synthetic.mjs`)
  with pause and step.
- `memmap.html` — the color-coded memory-map visualizer; scrubs a recorded memory capture
  (see `../docs/IDEAS-MEMORY-MAP-VIZ.md`).
- `panels/` — what exists: `struct-panel.mjs`, `inspector.mjs`, `memmap-panel.mjs`, `re-cockpit.mjs`,
  `sprite-preview.mjs`, `tile-editor.mjs`, `anim-export.mjs`, `gif-encode.mjs`. Planned and not built:
  the DIFF, WATCH and ASMTRACE overlay panels.
- `webgpu/` — reused as-is: `pvr2-renderer.mjs` (TA truth → offscreen renderTarget), `sprite-client.mjs`
  (state model + wire intakes), `sprite-gpu.mjs` (reconstruction), `transport.mjs` (live ingest).

Planned panel set: TA-truth · Reconstruct · DIFF (tint green/red/yellow) · Struct inspector · WATCH
RAM-diff · ASMTRACE pen overlay · Memory map. Transport: pause / step / scrub.

Gotchas: render to **offscreen renderTargets** (WebGPU swap-chain textures are consumed on present —
the diff must read mirrors/offscreen, never the live canvas). Use a single serve-time `?v=` to avoid
per-file cache drift. The RE panels must **degrade gracefully with no atlas art** (TA truth, struct
inspector, WATCH, memory map are all self-contained; only Reconstruct needs decoded sprites).
