#!/usr/bin/env bash
# apply-hook.sh — copy the tracked Oracle hook into the flycast submodule and apply the
# dynarec injection patch. Idempotent: safe to re-run. Run after `git submodule update --init`.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLY="$ROOT/extern/flycast"

if [ ! -d "$FLY/core" ]; then
  echo "ERROR: $FLY is empty. Run:  git submodule update --init extern/flycast" >&2
  exit 1
fi

# 1. Copy the hook module into the submodule's core/network/ (tracked source lives in hook/).
echo "[apply-hook] copying hook/ -> extern/flycast/core/network/"
cp "$ROOT"/hook/maplecast_oracle_hook.{cpp,h} "$FLY/core/network/"
cp "$ROOT"/hook/maplecast_replica_live.{cpp,h} "$FLY/core/network/" 2>/dev/null || true

# 2. Add the two .cpp to the network CMake list if not already present (idempotent).
#    (CMakeLists.snippet documents the exact target_sources lines.)
echo "[apply-hook] ensuring CMake includes the hook sources"
# TODO(phase1): wire the snippet into core/network/CMakeLists.txt (guarded grep+append).

# 3. Apply the dynarec injection patch (rec_x64.cpp + decoder.cpp). --forward = skip if already applied.
echo "[apply-hook] applying patch/0001-oracle-hook-injection.patch"
if [ -f "$ROOT/patch/0001-oracle-hook-injection.patch" ]; then
  git -C "$FLY" apply --reverse --check "$ROOT/patch/0001-oracle-hook-injection.patch" 2>/dev/null \
    && echo "  (already applied)" \
    || git -C "$FLY" apply "$ROOT/patch/0001-oracle-hook-injection.patch"
else
  echo "  NOTE: patch not present yet (Phase 1)."
fi
echo "[apply-hook] done."
