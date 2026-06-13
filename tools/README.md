# tools/ — decode / rip / validate / transpile

Phase 1 copies the Oracle-side tools from the MapleCast repo:
- **`rip_gfx2_assembly.py`** — entry point; `read_cells()` enumerates every sel (cell index == sprite_id).
- **`extract_gfx1_atlas.py`** — offline GFX1 LZSS decode → parts atlas.
- **`validate_emitter_geom.py`** + **`emitter_truth_gate.py`** — the numeric per-part geometry GATE
  (diff predicted quads vs the ASMTRACE/CHARQ ground truth; 0.00px = exact).
- `decode_*`, `rip_*`, `pack_*` — part/effect/stage decode + atlas packing.
- **`render-replica-poc/`** — the SH4→C transpiler harness (`lift.py`→`codegen.py`→`gen_*`,
  `render_ta.mjs` gold rasterizer). Copy `package.json`/lock; `npm install` fresh (no `node_modules/`).
- **NEW `oracle_query.py`** — consolidate the scattered `_oracle/*.py` ETL into one tail-parse-serve tool.

All operate on assets decoded FROM your own ROM (into the gitignored `assets/`). None ship ROM data.
