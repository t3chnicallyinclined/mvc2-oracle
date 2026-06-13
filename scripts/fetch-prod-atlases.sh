#!/usr/bin/env bash
# fetch-prod-atlases.sh [PLxx ...] — pull DECODED character atlases from prod into the gitignored
# web/test-atlas/chars/. READ-ONLY (scp pull; never writes/deploys to prod). These atlases are
# ROM-derived (full roster baked offline-from-disc, deployed to prod) → NEVER committed (.gitignore
# blocks PLxx.{json,png}). The fastest way to get real sprites into the dashboard without re-decoding.
#
#   ./scripts/fetch-prod-atlases.sh                 # the 6 demo chars
#   ./scripts/fetch-prod-atlases.sh PL2C PL34       # specific chars (Magneto, Sentinel)
#   MC_PROD=root@HOST ./scripts/fetch-prod-atlases.sh all   # whole roster
set -euo pipefail
HOST="${MC_PROD:-root@149.28.44.118}"
SRC="/var/www/maplecast/test-atlas/chars"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; DST="$ROOT/web/test-atlas/chars"
mkdir -p "$DST"

chars=("$@")
if [ "${chars[0]:-}" = "all" ]; then
  mapfile -t chars < <(ssh -o BatchMode=yes "$HOST" "ls -1 $SRC/PL*.json" | sed 's#.*/##; s#\.json##')
elif [ ${#chars[@]} -eq 0 ]; then
  chars=(PL00 PL0D PL17 PL1E PL2A PL2C)
fi

for plx in "${chars[@]}"; do
  scp -o BatchMode=yes "$HOST:$SRC/$plx.json" "$HOST:$SRC/$plx.png" "$DST/" >/dev/null 2>&1 && echo "  ✓ $plx" || echo "  ✗ $plx (missing on prod?)"
done
echo "done -> $DST (gitignored; the dashboard's SpritePreview loads these as PL{HEX}.json/.png)"
