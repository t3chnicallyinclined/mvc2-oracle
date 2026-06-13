#!/usr/bin/env bash
# capture.sh <ROM> <probe> — run headless flycast+hook with one Oracle probe enabled and
# point you at its /dev/shm output. READ-ONLY; flycast stays byte-stock except for the probe.
#
#   ./scripts/capture.sh /opt/mvc2/mvc2.gdi asmtrace
#
# Probes: asmtrace (per-part assembly ground truth) | bodycap (part pixels) |
#         charq (PVR quads) | oracle (frame anchors) | probe (generic, live-reloadable)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROM="${1:?usage: capture.sh <ROM> <probe>}"
PROBE="${2:-asmtrace}"
BIN="$ROOT/extern/flycast/build/headless/flycast"

[ -f "$BIN" ] || { echo "ERROR: build first — ./scripts/build-headless.sh" >&2; exit 1; }
[ -f "$ROM" ] || { echo "ERROR: ROM not found: $ROM" >&2; exit 1; }

declare -A ENVV=(
  [asmtrace]="MAPLECAST_ASMTRACE=1"        [bodycap]="MAPLECAST_BODYCAP=1"
  [charq]="MAPLECAST_CHARQ_RENDER=1"       [oracle]="MAPLECAST_FRAME_ORACLE_HOOK=1"
  [probe]="MAPLECAST_ORACLE_PROBE=1"
)
declare -A OUT=(
  [asmtrace]="/dev/shm/mc_assembly.log"    [bodycap]="/dev/shm/PLxx_part_*.ppm"
  [charq]="/dev/shm/mc_charq_render.jsonl" [oracle]="/dev/shm/mc_oracle_hook.jsonl"
  [probe]="/dev/shm/mc_probe.log"
)
[ -n "${ENVV[$PROBE]:-}" ] || { echo "ERROR: unknown probe '$PROBE'" >&2; exit 1; }

echo "[capture] ${ENVV[$PROBE]}  ->  ${OUT[$PROBE]}"
echo "[capture] start a match and let frames render; Ctrl-C to stop. Then:  tail -f ${OUT[$PROBE]}"
env ${ENVV[$PROBE]} "$BIN" "$ROM"
