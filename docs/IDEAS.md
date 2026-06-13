# Ideas index

Side-ideas and design explorations for MvC2 Oracle. Each gets its own doc; this is the one-line index.

- **[Memory Map Visualizer](IDEAS-MEMORY-MAP-VIZ.md)** — WinDirStat-style color-coded RAM radar; heat-decay
  on per-frame writes, hybrid treemap-of-Hilbert layout, semantic taxonomy (paint memory by meaning),
  gray = the un-RE'd frontier → click-to-label feeds `re_kb`. **MVP (M1) built** → `web/memmap.html`.
- **[Linked View](IDEAS-LINKED-VIEW.md)** — game render on top, memory radar on bottom, every object tinted
  the same color in both → see pixels↔memory correspondence. Reuses the DIFF-v7 tint debugger from
  `webgpu-test.html`. Needs sub-page resolution for the labeled struct/pool regions.

Build plan for the memory-map line of work: **[WORKSTREAM-MEMORY-MAP.md](WORKSTREAM-MEMORY-MAP.md)**.
Data sources / how to get real prod data: **[MEMMAP-DATA-SOURCES.md](MEMMAP-DATA-SOURCES.md)**.
