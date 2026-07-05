# Deploy the NOBD Discord bots to a host (nobd.net)

Runs **both** bots as persistent **systemd** services in one venv, so they survive reboots and stop
dying with anyone's terminal session. Secrets live in `chmod 600` env files **on the VPS only** —
never in git, never on a command line.
- **`nobd-oracle`** — the MvC2 Oracle Q&A bot (`bot.py`)
- **`nobd-roles`** — the console-role dropdown bot (`roles_bot.py`)

> **Production host: `root@149.28.44.118`** (nobd.net). The old `66.55.128.93` was **decommissioned
> 2026-04-15** — do not use it (and note `deploy.sh`'s historical default pointed there).
> **Status: both services are already deployed and live** (since 2026-07-05). This is a redeploy/reference
> runbook, not a from-scratch requirement.

## Deploying from Windows — no rsync (`deploy.sh` won't run there)
`deploy.sh` uses `rsync`, which the Windows dev box doesn't have. Deploy by hand instead:
```bash
# from mvc2-oracle/ — package (exclude secrets + runtime state), ship, install
tar -czf /tmp/oracle-bot.tgz \
  --exclude='__pycache__' --exclude='*.pyc' --exclude='oracle_usage.db' \
  --exclude='roles_msg.json' --exclude='discord-setup/.env' \
  --exclude='discord-bot/.env' --exclude='discord-bot/roles.env' oracle-bot
scp /tmp/oracle-bot.tgz root@149.28.44.118:/tmp/
ssh root@149.28.44.118 'D=/opt/nobd-oracle; mkdir -p $D; tar -xzf /tmp/oracle-bot.tgz -C $D;
  [ -d $D/venv ] || python3 -m venv $D/venv;              # needs python3.12-venv pkg
  $D/venv/bin/pip -q install -r $D/oracle-bot/discord-bot/requirements.txt;
  install -m644 $D/oracle-bot/deploy/nobd-oracle.service /etc/systemd/system/;
  install -m644 $D/oracle-bot/deploy/nobd-roles.service  /etc/systemd/system/;
  systemctl daemon-reload; systemctl restart nobd-oracle nobd-roles'
```
`oracle_ids.json` is gitignored-but-required at runtime — the tar above includes it (only `.env`-type and
runtime-state files are excluded).

## `deploy.sh` (on a machine that HAS rsync + SSH)
```bash
bash oracle-bot/deploy/deploy.sh root@149.28.44.118
```
- **First run** copies `.env.example`/`roles.env.example` → the VPS and stops. Fill the secrets, then start:
  ```bash
  ssh root@149.28.44.118
  nano /opt/nobd-oracle/oracle-bot/discord-bot/.env      # Oracle: DISCORD_BOT_TOKEN, ANTHROPIC_API_KEY, GITHUB_TOKEN
  nano /opt/nobd-oracle/oracle-bot/discord-bot/roles.env # Roles: DISCORD_BOT_TOKEN (NOBD admin) + guild/channel ids
  systemctl enable --now nobd-oracle nobd-roles
  ```
- **Later runs** sync the code and `systemctl restart` both automatically.

## Healthcheck
```bash
ssh root@149.28.44.118 /opt/nobd-oracle/status.sh
```
Shows both services' active/enabled/uptime, last 3 log lines each, and today's Oracle question count +
$ spent vs the $10/day budget.

## What it sets up
- `/opt/nobd-oracle/oracle-bot/` — the bot code (includes `oracle_ids.json`, gitignored but required).
- `/opt/nobd-oracle/venv/` — one Python venv (`anthropic` + `discord.py`) shared by both bots.
- `/etc/systemd/system/nobd-oracle.service` + `nobd-roles.service` — the units (auto-restart, journald).
- `…/discord-bot/.env` + `…/discord-bot/roles.env` — secrets (chmod 600, gitignored).
- `/opt/nobd-oracle/status.sh` — the healthcheck (see above).

## Logs / control
```bash
ssh root@149.28.44.118 journalctl -u nobd-oracle -f     # live logs ("Oracle bot online …")
ssh root@149.28.44.118 journalctl -u nobd-roles -f      # roles bot
ssh root@149.28.44.118 systemctl restart nobd-oracle nobd-roles
```

## Notes
- **Only one instance per bot token.** Stop any local `python bot.py` before the VPS service runs,
  or you'll get duplicate replies / gateway conflicts.
- **Chat-box mode** (`ORACLE_MESSAGE_CONTENT=1`, the default) needs the **Message Content Intent**
  — already enabled for this bot. Set `0` for mention-only.
- **Rotate + update secrets** by editing the VPS `.env` and `systemctl restart nobd-oracle` — no
  redeploy needed.
- If `deploy.sh` can't SSH, authorize your deploy key on the host first
  (`ssh-copy-id`, or add `~/.ssh/maplecast_automation.pub` to the host's `~/.ssh/authorized_keys`).
