#!/usr/bin/env bash
# Deploy the NOBD bots to a host as systemd services (in one venv):
#   - nobd-oracle : the MvC2 Oracle Q&A bot (bot.py)
#   - nobd-roles  : the console-role dropdown bot (roles_bot.py)
# Run from your machine — it needs WORKING SSH to the host (your interactive key).
#
#   bash oracle-bot/deploy/deploy.sh [user@host]      # default: ubuntu@15.204.141.58 (rise3, nobd.net prod)
#
# NOTE: needs rsync, which the Windows dev box lacks — see deploy/README.md for the tar+scp path.
# Prod moved 66.55.128.93 -> 149.28.44.118 -> rise3 15.204.141.58 (cut over 2026-09-01).
# rise3 has NO root login: log in as ubuntu and sudo. Both older hosts are retired.
# First run: copies a .env template per service to the VPS and stops — fill the secrets there, then
# `systemctl enable --now <service>`. Subsequent runs: sync code + restart both services.
set -euo pipefail
VPS="${1:-ubuntu@15.204.141.58}"
DEST="/opt/nobd-oracle"
BOT="$(cd "$(dirname "$0")/.." && pwd)"   # the oracle-bot/ dir

echo "==> syncing oracle-bot → $VPS:$DEST/oracle-bot"
# Includes the gitignored-but-required oracle_ids.json; excludes caches, runtime state, and any
# LOCAL secret files (the VPS gets its own .env / roles.env, filled on the box).
# rise3 has no root login and /opt/nobd-oracle is root-owned, so the remote side runs under
# sudo (--rsync-path + `sudo bash -s`). ubuntu@rise3 has passwordless sudo.
rsync -az --delete --rsync-path="sudo rsync" \
  --exclude '__pycache__' --exclude '*.pyc' \
  --exclude 'oracle_usage.db' --exclude 'roles_msg.json' \
  --exclude 'discord-bot/.env' --exclude 'discord-bot/roles.env' --exclude 'discord-setup/.env' \
  "$BOT/" "$VPS:$DEST/oracle-bot/"

echo "==> remote: venv + deps + systemd units"
ssh "$VPS" "DEST='$DEST' sudo -E bash -s" <<'REMOTE'
set -euo pipefail
[ -d "$DEST/venv" ] || python3 -m venv "$DEST/venv"
"$DEST/venv/bin/pip" -q install --upgrade pip
"$DEST/venv/bin/pip" -q install -r "$DEST/oracle-bot/discord-bot/requirements.txt"
install -m 644 "$DEST/oracle-bot/deploy/nobd-oracle.service" /etc/systemd/system/nobd-oracle.service
install -m 644 "$DEST/oracle-bot/deploy/nobd-roles.service"  /etc/systemd/system/nobd-roles.service
systemctl daemon-reload

first_run=0
setup_service() {  # $1 unit  $2 env-path  $3 template  $4 hint
  if [ ! -f "$2" ]; then
    install -m 600 "$3" "$2"; first_run=1
    echo "!! $1: created $2 — fill it ($4), then:  systemctl enable --now $1"
  else
    systemctl enable "$1" >/dev/null 2>&1 || true
    systemctl restart "$1"; sleep 1
    systemctl is-active "$1" >/dev/null && echo "==> $1 running" || echo "!! $1 not active — journalctl -u $1"
  fi
}
setup_service nobd-oracle "$DEST/oracle-bot/discord-bot/.env"      "$DEST/oracle-bot/deploy/.env.example"      "DISCORD_BOT_TOKEN=Oracle bot, ANTHROPIC_API_KEY, GITHUB_TOKEN"
setup_service nobd-roles  "$DEST/oracle-bot/discord-bot/roles.env" "$DEST/oracle-bot/deploy/roles.env.example" "DISCORD_BOT_TOKEN=NOBD (admin) bot"
[ "$first_run" = 1 ] && { echo; echo "First run: fill the env file(s) above, then enable each service."; }
REMOTE
echo "==> done.  Logs:  ssh $VPS sudo journalctl -u nobd-oracle -u nobd-roles -f"
