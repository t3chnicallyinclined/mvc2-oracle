# patch/ — flycast dynarec injection (applied into the submodule)

`0001-oracle-hook-injection.patch` (Phase 1) carries the two small edits that turn the tracked
`hook/` module into a live hook. Generate it from the fork:

```bash
git -C extern/flycast diff core/rec-x64/rec_x64.cpp core/hw/sh4/dyna/decoder.cpp \
  > patch/0001-oracle-hook-injection.patch
```

The hunks (both gated on `mc_oracleHookEnabled`, x64 dynarec only):
- **`rec_x64.cpp`** — in `BlockCompiler::compile()`, after `sub(rsp, STACK_ALIGN)` and before regalloc:
  `if (mc_oracleHookEnabled && mc_isHookedPC(block->vaddr)) { mov(call_regs[0], block->vaddr); GenCall(mc_oracle_blockEntry); }`
- **`decoder.cpp`** — in the `NDO_NextOp` loop, force `dec_End(rpc, BET_StaticJump, false)` when
  `mc_isHookedPC(rpc)` falls mid-block, so the hooked PC becomes a block start.

`scripts/apply-hook.sh` applies it idempotently (`git apply --reverse --check` then `git apply`).
