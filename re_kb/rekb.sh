#!/usr/bin/env bash
# rekb.sh — query the MapleCast RE knowledge graph (SurrealDB ns=re db=kb).
# Usage:
#   tools/re_kb/rekb.sh "SELECT * FROM field WHERE owner='char_struct';"
#   echo "SELECT * FROM finding;" | tools/re_kb/rekb.sh
#   tools/re_kb/rekb.sh @tools/re_kb/02_char_struct.surql      # apply a file
# Reads SQL from $1 or stdin; auto-prepends `USE NS re DB kb;`.
# If $1 starts with '@' it is passed through verbatim (file apply; that file
# already carries its own USE line).
set -euo pipefail
URL="${REKB_URL:-http://127.0.0.1:8001/sql}"
AUTH="${REKB_AUTH:-root:root}"

if [ "${1:-}" != "" ] && [ "${1:0:1}" = "@" ]; then
  exec curl -s -X POST "$URL" -u "$AUTH" -H "Accept: application/json" --data-binary "$1"
fi

if [ "${1:-}" != "" ]; then
  SQL="$1"
else
  SQL="$(cat)"
fi

curl -s -X POST "$URL" -u "$AUTH" -H "Accept: application/json" \
  --data-binary "USE NS re DB kb; $SQL"
