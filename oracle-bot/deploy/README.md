# Deploy the MvC2 Oracle bot to a host (e.g. nobd.net)

Runs `bot.py` as a persistent **systemd** service in a venv, so it survives reboots and stops
dying with anyone's terminal session. Secrets live in a `chmod 600` `.env` **on the VPS only** —
never in git, never on a command line.

## One command (from your machine, which has working SSH to the host)
```bash
bash oracle-bot/deploy/deploy.sh root@66.55.128.93
```
- **First run** copies `.env.example` → `discord-bot/.env` on the VPS and stops. SSH in, fill the
  three secrets, then start it:
  ```bash
  ssh root@66.55.128.93
  nano /opt/nobd-oracle/oracle-bot/discord-bot/.env   # DISCORD_BOT_TOKEN, ANTHROPIC_API_KEY, GITHUB_TOKEN
  systemctl enable --now nobd-oracle
  ```
- **Later runs** sync the code and `systemctl restart` automatically.

## What it sets up
- `/opt/nobd-oracle/oracle-bot/` — the bot code (rsynced; includes `oracle_ids.json`, which is
  gitignored but required at runtime).
- `/opt/nobd-oracle/venv/` — Python venv with `anthropic` + `discord.py`.
- `/etc/systemd/system/nobd-oracle.service` — the unit (auto-restart, journald logs).
- `…/discord-bot/.env` — secrets (chmod 600, gitignored).

## Logs / control
```bash
ssh root@66.55.128.93 journalctl -u nobd-oracle -f      # live logs ("Oracle bot online …")
ssh root@66.55.128.93 systemctl restart nobd-oracle
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
