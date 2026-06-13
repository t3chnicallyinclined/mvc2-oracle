# hook/ — the Oracle hook (tracked here, applied into the flycast submodule)

Phase 1 copies these from the MapleCast fork's `core/network/`:
- `maplecast_oracle_hook.cpp` / `.h` — the block-entry handler `mc_oracle_blockEntry(pc)`, the probe
  family (ASMTRACE, BODYCAP, CHARQ, Frame Oracle, generic `MAPLECAST_ORACLE_PROBE`), `mc_isHookedPC`,
  the live-reload config parser. All READ-ONLY, all default OFF.
- `maplecast_replica_live.cpp` / `.h` — the Phase-4c render-replica live feed.
- `CMakeLists.snippet` — the `target_sources(...)` lines to add these to `core/network/CMakeLists.txt`.

`scripts/apply-hook.sh` copies these into `extern/flycast/core/network/` and applies
`../patch/0001-oracle-hook-injection.patch`.

⚠️ **Before copying:** reconcile which fork commit has the latest hook — prod source is ahead of git.
The two dynarec injection edits (NOT here — they're in `patch/`):
- `core/rec-x64/rec_x64.cpp` — `BlockCompiler::compile()`: emit `GenCall(mc_oracle_blockEntry)` for hooked PCs.
- `core/hw/sh4/dyna/decoder.cpp` — `NDO_NextOp`: force a block boundary at a hooked mid-block PC.
