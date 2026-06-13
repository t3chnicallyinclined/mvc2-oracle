#!/usr/bin/env bash
# apply-hook.sh — VERIFY the flycast submodule already carries the Oracle hook.
#
# NOTE: the submodule pins the MapleCast FORK (github.com/t3chnicallyinclined/maplecast-flycast
# @ 3cfcf0d03), which already has the hook module AND the dynarec injection committed. So there is
# NOTHING to copy/patch — just init the submodule and build. This script only sanity-checks that.
# (The repo's hook/ + patch/ dirs hold the hook as a STANDALONE EXTRACTION for eventual upstream
# contribution to clean flycast — they are not needed to build here.)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLY="$ROOT/extern/flycast"

if [ ! -d "$FLY/core" ]; then
  echo "ERROR: submodule empty. Run:  git submodule update --init extern/flycast" >&2
  exit 1
fi
ok=1
check() { if grep -q "$2" "$FLY/$1" 2>/dev/null; then echo "  ✓ $1 ($3)"; else echo "  ✗ MISSING in $1 ($3)"; ok=0; fi; }
echo "[verify-hook] checking the fork submodule carries the hook…"
[ -f "$FLY/core/network/maplecast_oracle_hook.cpp" ] && echo "  ✓ core/network/maplecast_oracle_hook.cpp" || { echo "  ✗ hook module MISSING"; ok=0; }
check core/rec-x64/rec_x64.cpp        "mc_oracle_blockEntry" "dynarec GenCall injection"
check core/hw/sh4/dyna/decoder.cpp    "mc_isHookedPC"        "decoder force-split"
[ "$ok" = 1 ] && echo "[verify-hook] OK — build with ./scripts/build-headless.sh" \
              || { echo "[verify-hook] hook not present at this submodule commit — check the pin."; exit 2; }
