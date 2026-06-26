# NOBD Discord — automated setup

Idempotent, stdlib-only Python script that builds the NOBD server: roles, categories,
channels (topics + read-only overwrites), server name/description, and posts + pins the
welcome / rules / why-nobd copy. Safe to re-run — it skips anything already created.

## Bootstrap (browser, ~5 min, one time — these can't be scripted)
1. **Create the server** in the Discord client. (A bot *could* create one, but it'd own it — don't.)
2. **Make a bot:** https://discord.com/developers/applications → New Application → **Bot** → copy the **token**.
3. **Invite the bot** with Administrator (or Manage Roles/Channels/Server + Send Messages):
   `https://discord.com/oauth2/authorize?client_id=<APP_ID>&scope=bot&permissions=8`
4. *(Optional, for the 120-char discovery description)* enable **Community** in Server Settings.
5. **Get the server ID:** Settings → Advanced → Developer Mode on, then right-click the server → **Copy Server ID**.

## Run
```bash
cp .env.example .env          # then edit .env with your token + server id
set -a; source .env; set +a   # load env vars
python3 setup_discord.py            # DRY RUN — prints the plan, creates nothing
python3 setup_discord.py --apply    # actually build it
```

## Security
- The bot token is a **credential**. It's gitignored (`.env`, `*.token`). Never commit or paste it publicly.
- After setup you can **regenerate** the token in the Developer Portal to invalidate the one you used.

## Editing the structure
Everything is data at the top of `setup_discord.py`: `ROLES`, `STRUCTURE` (categories → channels),
and `MESSAGES` (posted into freshly-created channels). Tweak and re-run; existing items are skipped.
