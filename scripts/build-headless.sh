#!/usr/bin/env bash
# build-headless.sh — build the headless flycast server WITH the Oracle hook (x64 dynarec).
# The hook is x64-only and writes to /dev/shm, so this targets x86-64 Linux / WSL2.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLY="$ROOT/extern/flycast"
BUILD="$FLY/build/headless"

"$ROOT/scripts/apply-hook.sh"

echo "[build] configuring headless (MAPLECAST_HEADLESS=ON)"
cmake -S "$FLY" -B "$BUILD" -DMAPLECAST_HEADLESS=ON -DCMAKE_BUILD_TYPE=Release
echo "[build] compiling"
cmake --build "$BUILD" -j"$(nproc)"
echo "[build] binary: $BUILD/flycast"
