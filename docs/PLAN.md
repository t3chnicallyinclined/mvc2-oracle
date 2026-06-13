# MvC2 Oracle — Build Plan

Consolidated from the `mvc2-sh4-re-expert` (backend) + `mvc2-sprite-render-expert` (frontend)
scoping passes. Decisions locked: **flycast = submodule + patch**; **dashboard = rebuilt clean,
reusing proven logic**; **onboarding = bring-your-own-ROM auto-decode**, with a recorded-capture
path for no-emulator devs.

## Architecture decision: flycast dependency
flycast is a **git submodule** pinned to the MapleCast fork commit that carries the latest hook
(NOT upstream flycast). The hook lives as **tracked files in `hook/`** + a **patch set in `patch/`**
(the two dynarec edits), applied into the submodule by `scripts/apply-hook.sh`. A prebuilt
headless+hook binary is also published per release for tools-only devs.

Why: the hook surface is tiny and stable — one self-contained `core/network/` module + two ~10-line
edits (`rec_x64.cpp` GenCall injection after `sub(rsp,STACK_ALIGN)`; `decoder.cpp` force-split in
the `NDO_NextOp` loop). Submodule+patch keeps the hook hackable and flycast bumpable; vendoring the
500k-LOC fork or shipping binary-only were rejected.

## What moves into this repo (Phase 1+)
- **hook/** ← `core/network/maplecast_oracle_hook.{cpp,h}` + `maplecast_replica_live.{cpp,h}`
- **patch/** ← the `rec_x64.cpp` + `decoder.cpp` injection hunks
- **re_kb/** ← `tools/re_kb/` (all `*.surql`, `rekb.sh/.cmd`, README, `ingest/` incl. the cached anotak corpus)
- **tools/** ← `rip_gfx2_assembly.py`, `extract_gfx1_atlas.py`, `validate_emitter_geom.py`,
  `emitter_truth_gate.py`, `decode_*`, `rip_*`, `pack_*`, and `render-replica-poc/` (the SH4→C
  transpiler harness; copy `package.json`/lock, NOT `node_modules/`). **NEW: `oracle_query.py`** —
  consolidate the scattered `_oracle/*.py` ETL (`oracle_live.py`, `oracle_layers.py`,
  `oracle_attribute.py`, `oracle_anchor.py`, `seltcw_*.py`) into one tail-parse-serve tool.
- **web/webgpu/** ← `pvr2-renderer.mjs`, `sprite-client.mjs`, `sprite-gpu.mjs`, `transport.mjs` (as-is)
- **docs/** ← `FRAME-ORACLE-SPEC.md`, `MARVELOUS2-GFX-NOTES.md`, `MARVELOUS2-RE-HANDOFF.md`,
  `MVC2-MEMORY-MAP.md`, `PER-OBJECT-QUAD-SPEC.md`, `CHARQ-PLAN.md`, `ASSEMBLY-DRIVEN-DESIGN.md`,
  `PART-ASSEMBLY-PLAN.md`, the framedata/wire-gap docs, and `re-catalog/`.

## Referenced, never vendored
flycast (submodule), marvelous2 (`_marv_re/` external checkout / optional submodule of upstream),
anotak (live URL + the cached corpus moves with re_kb), the MVC2 disc / Dev Files (ROM-copyright —
dev-box path only).

## NEVER copied
ROMs, savestates, baked atlases, texture/sprite/palette dumps, `/dev/shm` scratch, `node_modules/`,
`re_kb_data/`, recorded captures. (See `CONTRIBUTING.md` + `.gitignore`.)

## Bring-your-own-ROM onboarding (the "full setup")
`scripts/setup-from-rom.sh $MVC2_ROM`:
1. Validates the ROM exists and is **outside** the repo (refuses otherwise).
2. Builds flycast+hook (via `apply-hook.sh` + `build-headless.sh`) if not already built.
3. Decodes the dev's ROM into `assets/` (gitignored) — two sources:
   - **Live**: run headless flycast with `MAPLECAST_PARTDUMP`/`ASMTRACE`/`CHARQ` during play →
     `/dev/shm` dumps → `rip_gfx2_assembly.py --realparts` packs atlases + the assembly recipe.
   - **Offline** (where a disc extractor is available): pull the PLxx_DAT/GFX/PAL files and run
     `extract_gfx1_atlas.py` / `rip_gfx2_assembly.py`.
4. Seeds `re_kb` from the `*.surql` files (ending with `07_dedup_edges.surql` — RELATE isn't idempotent).
5. Produces a recorded capture in `captures/` for the dashboard.

## Dashboard (rebuilt clean, reusing proven logic)
A single-page WebGPU dashboard with a **frame bus** (one per-frame snapshot:
`{frameNum, parsed(TA), slot[6], objects[], watch, pvrSnap, asmtrace[], charq[]}`) fed by the live
WS mirror, an Oracle tail-WS, or a recorded capture. Panels:
1. **TA-truth** — `PVR2Renderer.renderFrame` to an **offscreen renderTarget** (sidesteps the WebGPU
   swap-chain readback gotcha).
2. **Reconstruct** — `sprite-client` build-draw-list → `sprite-gpu`.
3. **DIFF v7** — extract `diffTick`/`objDeltas` from the old cockpit into `panels/diff-panel.mjs`
   (tint = green/red/yellow; per-object Δpx).
4. **Struct inspector** — the 6 char structs + OBJS + globals, live.
5. **WATCH bit-probe diff** — the per-frame RAM differ.
6. **ASMTRACE pen overlay** — draw the cumulative pen + final screenX/Y per part over TA truth.
Transport bar: pause / step / scrub (client-side for recorded; a `:7211` control-WS frame-advance for live).

Reuse as-is: `pvr2-renderer`, `sprite-client`, `sprite-gpu`, `transport`. Extract logic from
`webgpu-test.html` into clean panel modules. Rebuild the shell. `bake.mjs` = a separate capture tab.

## Phases (ordering, not time estimates)
- **Phase 0 — Skeleton + guardrails (THIS COMMIT).** Tree, `.gitignore` + `CONTRIBUTING` (ROM rule),
  README, this plan, script stubs. ⚠️ Before Phase 1: reconcile **which fork commit** has the latest hook.
- **Phase 1 — Backend loop.** Add the flycast submodule, copy `hook/` + `patch/` + `re_kb/` + tools/docs,
  prove `apply-hook.sh` → build → `MAPLECAST_ASMTRACE=1` capture → re_kb query end-to-end.
- **Phase 2 — Dashboard offline.** Copy renderers, extract DIFF/ETL panels, build the shell + frame bus,
  the recorded-capture path (extend the `replay.html` format to carry GSTA/OBJS/WATCH/asmtrace).
- **Phase 3 — Live mode.** `oracle_query.py` tail-WS + the `:7211` frame step/scrub channel.
- **Phase 4 — Polish.** Struct inspector, ASMTRACE pen overlay, graceful no-art degradation, bake tab.

## Open items to confirm before Phase 1
1. The exact **fork branch/commit** the submodule pins (prod source is ahead of git — reconcile first).
2. `oracle_query.py` is a **consolidation** of `_oracle/*.py`, not a copy — confirm the source scripts.
3. Whether a GDI/disc extractor exists for the fully-offline decode path, or if live-capture is the
   only ROM→assets route on day one.
