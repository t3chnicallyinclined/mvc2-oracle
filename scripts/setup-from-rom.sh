#!/usr/bin/env bash
# setup-from-rom.sh — the "bring your own ROM" full setup. Decodes everything this toolkit
# needs FROM YOUR ROM into the gitignored assets/ + captures/. Commits nothing ROM-derived.
#
#   export MVC2_ROM=/opt/mvc2/mvc2.gdi   # MUST be outside this repo
#   ./scripts/setup-from-rom.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROM="${MVC2_ROM:?set MVC2_ROM to your MVC2 image path (outside this repo)}"

# --- Guard: refuse a ROM that lives inside the repo (never copy a ROM into the tree) ---
case "$(cd "$(dirname "$ROM")" && pwd)/" in
  "$ROOT"/*) echo "ERROR: \$MVC2_ROM is inside the repo. Move it OUT (see CONTRIBUTING.md)." >&2; exit 1;;
esac
[ -f "$ROM" ] || { echo "ERROR: ROM not found: $ROM" >&2; exit 1; }

mkdir -p "$ROOT/assets" "$ROOT/captures"

echo "=== [1/5] build flycast + Oracle hook ==="
"$ROOT/scripts/build-headless.sh"

echo "=== [2/5] decode sprites/parts/palettes FROM your rom -> assets/ ==="
# Live path: run the part/assembly probes during play, then pack with the rip tool.
#   MAPLECAST_PARTDUMP=N + MAPLECAST_ASMTRACE=1 ./extern/flycast/build/headless/flycast "$ROM"
#   tools/rip_gfx2_assembly.py --realparts /dev/shm --out "$ROOT/assets" --char PLxx ...
# TODO(phase1): wire once tools/ are copied in. Offline disc-extract path is an alternative
#               where a GDI extractor is available.
echo "  (Phase 1: wire rip_gfx2_assembly.py / extract_gfx1_atlas.py against \$MVC2_ROM)"

echo "=== [3/5] seed the re_kb knowledge graph ==="
# surreal start --user root --pass root --bind 127.0.0.1:8001 rocksdb:re_kb_data/re_kb &
# for f in schema_seed 01_schema 02_char_struct 03_routines 04_memory_data 05_characters \
#          06_findings_sources 08_emitter_render_model 09_facing_subgraph; do
#   re_kb/rekb.sh @re_kb/$f.surql; done
# re_kb/rekb.sh @re_kb/07_dedup_edges.surql   # RELATE is not idempotent — dedup last
echo "  (Phase 1: wire once re_kb/ is copied in)"

echo "=== [4/5] produce a recorded capture for the dashboard -> captures/ ==="
echo "  (Phase 2: emit captures/oracle_capture.bin = TA frames + GSTA/OBJS/WATCH + asmtrace slice)"

echo "=== [5/5] done. Your decoded setup is in ./assets (gitignored). Open web/dashboard.html. ==="
