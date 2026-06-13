# Ideas index

Side-ideas and design explorations for MvC2 Oracle. Each gets its own doc; this is the one-line index.

- **[Memory Map Visualizer](IDEAS-MEMORY-MAP-VIZ.md)** — WinDirStat-style color-coded RAM radar; heat-decay
  on per-frame writes, hybrid treemap-of-Hilbert layout, semantic taxonomy (paint memory by meaning),
  gray = the un-RE'd frontier → click-to-label feeds `re_kb`. **MVP (M1) built** → `web/memmap.html`.
- **[Linked View](IDEAS-LINKED-VIEW.md)** — game render on top, memory radar on bottom, every object tinted
  the same color in both → see pixels↔memory correspondence. Reuses the DIFF-v7 tint debugger from
  `webgpu-test.html`. Needs sub-page resolution for the labeled struct/pool regions. **Demo built** →
  `web/linked-view.html`.
- **[Click-to-Decode](IDEAS-CLICK-DECODE.md)** — click a memory location → decode the fields → render that
  object's actual sprite + play its animation (replay the captured `sprite_id` history, or decode the
  canonical anim cells). Ties memory ↔ atlas ↔ renderer.
- **[Labeled Inspector + Live Edit](IDEAS-INSPECTOR-EDIT.md)** — every location labeled from `re_kb` (what
  it is / does); view a struct's attached fields decoded with live values; and — guarded, mod-layer
  RAM_WRITE, logical-fields-only — live-edit. Read side safe & near-term; write side is the gated mod surface.

Build plan for the memory-map line of work: **[WORKSTREAM-MEMORY-MAP.md](WORKSTREAM-MEMORY-MAP.md)**.
Data sources / how to get real prod data: **[MEMMAP-DATA-SOURCES.md](MEMMAP-DATA-SOURCES.md)**.
