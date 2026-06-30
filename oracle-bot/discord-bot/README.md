# MvC2 Oracle — Discord bot

Puts the [Managed Agents Oracle](../managed-agent/) in a Discord channel. On `!oracle <question>`
or an @mention, it opens a session, the agent greps the marvelous2 disassembly + reads the re_kb
memory store, and it posts a cited answer. Rate-limited per user with a hard daily $ budget.

## Prerequisites
1. The agent is provisioned (`../managed-agent/provision.py` → `oracle_ids.json` exists).
2. A Discord **bot application** (recommend a dedicated one, not the NOBD setup bot):
   - https://discord.com/developers/applications → New Application → **Bot** → copy the token.
   - Under **Bot → Privileged Gateway Intents**, enable **Message Content Intent** and
     **Server Members Intent** (the bot needs message text + member roles).
   - Invite it with **Send Messages** + **Read Message History** in your server (and access to
     the target channel). Scope `bot`, permission `Send Messages`.

## Run
```bash
pip install -r requirements.txt
set DISCORD_BOT_TOKEN=...        # the Oracle bot's token
set ANTHROPIC_API_KEY=...        # funded
set GITHUB_TOKEN=...             # read token for the public marvelous2 repo  (gh auth token works)
set ORACLE_CHANNEL_ID=...        # the #re-and-tech channel id (recommended; 0 = any channel)
python bot.py
```
It must run on a persistent host (your machine or a small VPS) — Managed Agents hosts the agent
loop + container + memory, but the Discord gateway listener is yours.

## Usage (members)
- `!oracle <question>` or `@MvC2 Oracle <question>` in the configured channel.
- A "🔮 consulting…" message is replaced with the cited answer (split across messages if long).
- The answer opens a **thread** that stays a live conversation: the asker can keep asking there
  (up to `ORACLE_FOLLOWUP_MAX`, default 5) and each turn carries full context. In the default
  chat-box mode no @mention is needed in the thread; bare "thanks"-type messages get a 👍 and don't
  spend a turn. Follow-ups count against the daily $ budget but not the per-user question quota.

## Limits & management
All env-tunable (defaults shown):

| control | env | default | what |
|---|---|---|---|
| per-user daily quota | `ORACLE_PER_USER_DAILY` | 5 | questions/user/day, resets 00:00 UTC |
| cooldown | `ORACLE_COOLDOWN_SEC` | 30 | min seconds between a user's questions |
| **server daily budget** | `ORACLE_DAILY_BUDGET_USD` | 10 | hard $/day cap across everyone — the cost backstop |
| max concurrent | `ORACLE_MAX_CONCURRENT` | 3 | simultaneous sessions |
| channel lock | `ORACLE_CHANNEL_ID` | any | only respond in this channel |
| follow-ups/thread | `ORACLE_FOLLOWUP_MAX` | 5 | max follow-up turns per question thread |
| thread idle TTL | `ORACLE_THREAD_TTL_SEC` | 3600 | idle seconds before a thread's session is archived |
| chat-box mode | `ORACLE_MESSAGE_CONTENT` | 1 (on) | `0` = mention-only (follow-ups then need an @mention) |

- **Exempt roles** (bypass quota/cooldown): `Team`, `Mod`, `Dev / Contributor`.
- Usage is persisted in `oracle_usage.db` (SQLite) — survives restarts; resets logically at UTC midnight.

### Admin commands (Mod/Team only)
- `!oracle-stats` — today's question count, $ spent vs budget, top users.
- `!oracle-quota @user` — that user's remaining questions today.
- `!oracle-reset @user` — clear a user's quota + cooldown.

To change a limit, set the env var and restart. Edit `EXEMPT_ROLES` / `ADMIN_ROLES` in `bot.py`.

## The ultimate backstop: Anthropic workspace spend limit
The bot's `$DAILY_BUDGET` caps *intended* spend; set a **monthly spend limit on the Anthropic
workspace** (Console → Settings → Workspaces) as the hard ceiling that holds even if the bot
misbehaves. Belt and suspenders.

## Cost
~$0.13–0.37 per question (mostly answer length + the first cached-prefix write per 5-min window).
At a $10/day budget that's roughly 30–70 questions/day before the bot pauses till reset.

## Notes / next
- Each question opens its own session, kept alive for that thread's follow-ups (keyed per Discord
  thread, persisted in `oracle_usage.db` so it survives a restart). Distinct questions don't share
  memory; a thread's follow-ups do.
- Chat-box mode needs the **Message Content Intent** (portal toggle, step 2 above) — it's on by
  default. Without the toggle the bot exits at startup with a clear message; set
  `ORACLE_MESSAGE_CONTENT=0` for mention-only mode if you don't want the intent.
- Memory is mounted **read-only** (public input can't poison the graph). Curated writes happen via
  the trusted `../managed-agent/run_session.py --curate` path.
