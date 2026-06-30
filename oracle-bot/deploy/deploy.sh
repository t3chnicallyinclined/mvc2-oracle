#!/usr/bin/env bash
# Deploy the NOBD MvC2 Oracle bot to a host (systemd service in a venv).
# Run from your machine — it needs WORKING SSH to the host (your interactive key).
#
#   bash oracle-bot/deploy/deploy.sh [user@host]      # default: root@66.55.128.93
#
# First run: copies a .env template to the VPS and stops — you fill the secrets there, then
# `systemctl enable --now nobd-oracle`. Subsequent runs: syncs code + restarts the service.
set -euo pipefail
VPS="${1:-root@66.55.128.93}"
DEST="/opt/nobd-oracle"
BOT="$(cd "$(dirname "$0")/.." && pwd)"   # the oracle-bot/ dir

echo "==> syncing oracle-bot → $VPS:$DEST/oracle-bot"
# Includes the gitignored-but-required oracle_ids.json; excludes caches, the usage db, and any
# LOCAL .env (the VPS gets its own .env, filled on the box).
rsync -az --delete \
  --exclude '__pycache__' --exclude '*.pyc' \
  --exclude 'oracle_usage.db' \
  --exclude 'discord-bot/.env' --exclude 'discord-setup/.env' \
  "$BOT/" "$VPS:$DEST/oracle-bot/"

echo "==> remote: venv + deps + systemd unit"
ssh "$VPS" "DEST='$DEST' bash -s" <<'REMOTE'
set -euo pipefail
[ -d "$DEST/venv" ] || python3 -m venv "$DEST/venv"
"$DEST/venv/bin/pip" -q install --upgrade pip
"$DEST/venv/bin/pip" -q install -r "$DEST/oracle-bot/discord-bot/requirements.txt"
install -m 644 "$DEST/oracle-bot/deploy/nobd-oracle.service" /etc/systemd/system/nobd-oracle.service
systemctl daemon-reload
ENVF="$DEST/oracle-bot/discord-bot/.env"
if [ ! -f "$ENVF" ]; then
  install -m 600 "$DEST/oracle-bot/deploy/.env.example" "$ENVF"
  echo
  echo "!! FIRST RUN — fill secrets, then start:"
  echo "     nano $ENVF      # set DISCORD_BOT_TOKEN, ANTHROPIC_API_KEY, GITHUB_TOKEN"
  echo "     systemctl enable --now nobd-oracle"
else
  systemctl enable nobd-oracle >/dev/null 2>&1 || true
  systemctl restart nobd-oracle
  sleep 2
  systemctl status nobd-oracle --no-pager | head -6
fi
REMOTE
echo "==> done.  Logs:  ssh $VPS journalctl -u nobd-oracle -f"
