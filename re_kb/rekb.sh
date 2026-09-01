#!/usr/bin/env bash
# rekb.sh — query the MapleCast RE knowledge graph (SurrealDB ns=re db=kb).
# Usage:
#   tools/re_kb/rekb.sh "SELECT * FROM field WHERE owner='char_struct';"
#   echo "SELECT * FROM finding;" | tools/re_kb/rekb.sh
#   tools/re_kb/rekb.sh @tools/re_kb/02_char_struct.surql      # apply a file
#
# `USE NS re DB kb;` is ALWAYS prepended, including for a file apply.
#
# It did not used to be. A file was passed to curl verbatim on the assumption
# that "the file carries its own USE line" -- and 5 of the 87 seed files do
# not. SurrealDB answers every statement in those files with "Specify a
# namespace to use", the HTTP request still returns 200, and this script
# printed that and exited 0. 29 statements across those 5 files had therefore
# never been applied, silently, for months. A second USE is harmless, so the
# assumption is now removed rather than documented.
#
# Exits 1 if ANY statement in the response failed, so a caller in a loop can
# actually tell. The JSON still goes to stdout unchanged.
set -euo pipefail
URL="${REKB_URL:-http://127.0.0.1:8001/sql}"
AUTH="${REKB_AUTH:-root:root}"
USE="USE NS re DB kb;"

if [ "${1:-}" != "" ] && [ "${1:0:1}" = "@" ]; then
  FILE="${1#@}"
  if [ ! -f "$FILE" ]; then
    echo "rekb.sh: no such file: $FILE" >&2
    exit 2
  fi
  BODY="$(printf '%s\n' "$USE"; cat "$FILE")"
elif [ "${1:-}" != "" ]; then
  BODY="$USE $1"
else
  BODY="$USE $(cat)"
fi

OUT="$(printf '%s' "$BODY" | curl -s -X POST "$URL" -u "$AUTH" \
        -H "Accept: application/json" --data-binary @-)"
printf '%s' "$OUT"

if printf '%s' "$OUT" | grep -q '"status":"ERR"'; then
  echo >&2
  echo "rekb.sh: at least one statement FAILED (\"status\":\"ERR\" in the response)." >&2
  exit 1
fi
