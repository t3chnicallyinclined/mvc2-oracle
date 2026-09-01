#!/usr/bin/env bash
# sync-re-kb.sh — refresh this repo's re_kb/ MIRROR from the canonical graph.
#
# re_kb/ in THIS repo is a mirror, not the source of truth. The graph is
# maintained in maplecast-flycast at tools/re_kb/, and this repo vendors a copy
# so the toolkit stays standalone (you can clone it alone and still query the
# RE knowledge).
#
# WHY THIS SCRIPT EXISTS
# ----------------------
# The mirror went stale silently. Measured 2026-09-01: this repo carried 16 of
# the canonical 89 seed files, frozen at 2026-06-13, while re_kb/README.md
# called the directory "the canonical place RE findings live and get queried."
# Every shared file was byte-identical — no fork, just ~69 missing files — and
# the numbering jumps 09 -> 15 -> 18, so the truncation was invisible to anyone
# reading the directory listing. Someone following that README would query an
# incomplete graph and re-derive things that are already recorded.
#
# Nothing detects that on its own. So: one command, run it after any RE work.
#
#   ./scripts/sync-re-kb.sh                    # from ../maplecast-flycast
#   ./scripts/sync-re-kb.sh /path/to/tools/re_kb
#   ./scripts/sync-re-kb.sh --check            # report drift, change nothing
#
# The submodule at extern/flycast is the same repository and is used as a
# fallback source — but it is pinned for BUILDING flycast, so it is usually
# older than a sibling working copy, and this script never bumps that pin.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HERE/re_kb"

CHECK=0
SRC=""
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    -*) echo "unknown flag: $a" >&2; exit 2 ;;
    *) SRC="$a" ;;
  esac
done

if [ -z "$SRC" ]; then
  for cand in "$HERE/../maplecast-flycast/tools/re_kb" "$HERE/extern/flycast/tools/re_kb"; do
    if [ -d "$cand" ]; then SRC="$cand"; break; fi
  done
fi

if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
  cat >&2 <<'MSG'
sync-re-kb.sh: cannot find the canonical re_kb.

Looked for:
  ../maplecast-flycast/tools/re_kb   (a sibling working copy — preferred)
  extern/flycast/tools/re_kb         (the pinned submodule — usually older)

Pass the path explicitly, or check out maplecast-flycast beside this repo.
MSG
  exit 1
fi

echo "canonical: $SRC"
echo "mirror   : $DEST"
echo

missing=0
changed=0
# README.md is deliberately NOT compared: the mirror's copy says it is a
# mirror, so it must differ from the canonical one forever. Including it would
# make --check report permanent drift and train the reader to ignore the check.
for f in "$SRC"/*.surql "$SRC"/*.py "$SRC"/rekb.sh "$SRC"/rekb.cmd; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  if [ ! -e "$DEST/$b" ]; then
    missing=$((missing + 1))
    [ "$CHECK" = 1 ] && echo "  MISSING  $b"
  elif ! diff -q "$f" "$DEST/$b" >/dev/null 2>&1; then
    changed=$((changed + 1))
    [ "$CHECK" = 1 ] && echo "  STALE    $b"
  fi
done

if [ "$CHECK" = 1 ]; then
  echo
  echo "$missing missing, $changed stale"
  [ $((missing + changed)) -eq 0 ] && echo "mirror is current." || \
    echo "run ./scripts/sync-re-kb.sh to refresh."
  exit 0
fi

mkdir -p "$DEST/ingest" "$DEST/hooks"
cp -f "$SRC"/*.surql "$DEST/" 2>/dev/null || true
cp -f "$SRC"/*.py "$DEST/" 2>/dev/null || true
cp -f "$SRC"/rekb.sh "$SRC"/rekb.cmd "$DEST/" 2>/dev/null || true
[ -d "$SRC/hooks" ] && cp -f "$SRC"/hooks/*.py "$DEST/hooks/" 2>/dev/null || true
[ -d "$SRC/ingest" ] && cp -f "$SRC"/ingest/*.py "$DEST/ingest/" 2>/dev/null || true
chmod +x "$DEST/rekb.sh" 2>/dev/null || true

echo "synced: $(ls -1 "$DEST"/*.surql 2>/dev/null | wc -l) seed files, \
$(ls -1 "$DEST"/*.py 2>/dev/null | wc -l) tools"
echo
echo "NOTE: re_kb/README.md is NOT overwritten by this script — the mirror's"
echo "      README deliberately differs (it says it is a mirror). If the"
echo "      canonical README changes materially, port the change by hand."
