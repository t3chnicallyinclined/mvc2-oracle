#!/usr/bin/env python3
"""
MvC2 Oracle — Discord bot.

Listens in one channel; on `!oracle <question>` or an @mention, opens a Managed Agents session
(agent + marvelous2 repo mount + re_kb memory store from ../managed-agent/oracle_ids.json),
streams the cited answer back. Rate-limited per user + a hard daily $ budget, persisted to SQLite.

Env:
    DISCORD_BOT_TOKEN     the Oracle bot's token
    ANTHROPIC_API_KEY     funded key (the agent runs on this)
    GITHUB_TOKEN          read token for cloning the public marvelous2 repo
    ORACLE_CHANNEL_ID     (optional) restrict to this channel id; 0/unset = any channel

Tunables: see CONFIG below (also env-overridable).

    pip install -r requirements.txt
    python bot.py
"""
import os
import re
import sys
import json
import time
import asyncio
import sqlite3
import datetime as dt
from pathlib import Path

import discord
import anthropic

# --------------------------------------------------------------------------------- config
HERE = Path(__file__).resolve().parent
IDS_FILE = Path(os.environ.get("ORACLE_IDS", HERE.parent / "managed-agent" / "oracle_ids.json"))
DB_FILE = HERE / "oracle_usage.db"
REPO_URL = os.environ.get("MARV_REPO_URL", "https://github.com/mountainmanjed/marvelous2")
REPO_MOUNT = "/workspace/marvelous2"
FW_REPO_URL = os.environ.get("FW_REPO_URL", "https://github.com/t3chnicallyinclined/GP2040-CE-NOBD")
FW_MOUNT = "/workspace/gp2040"
# Comma/space-separated channel ids the bot answers in. Empty / "0" = any channel it can post in.
CHANNEL_IDS = {int(x) for x in os.environ.get("ORACLE_CHANNEL_ID", "").replace(",", " ").split()
               if x.strip() and x.strip() != "0"}

PER_USER_DAILY = int(os.environ.get("ORACLE_PER_USER_DAILY", "5"))
COOLDOWN_SEC = int(os.environ.get("ORACLE_COOLDOWN_SEC", "30"))
DAILY_BUDGET_USD = float(os.environ.get("ORACLE_DAILY_BUDGET_USD", "10"))
MAX_CONCURRENT = int(os.environ.get("ORACLE_MAX_CONCURRENT", "3"))
EXEMPT_ROLES = {"Team", "Mod", "Dev / Contributor"}
ADMIN_ROLES = {"Team", "Mod"}

# Opus 4.8 pricing ($/Mtok): input 5, output 25, cache-read 0.5, cache-write(5m) 6.25, (1h) 10
PRICE = {"in": 5.0, "out": 25.0, "cr": 0.5, "cw5": 6.25, "cw1h": 10.0}

DISCORD_STYLE = ("\n\n[Formatting: this answer is shown in Discord. Use short bullet points, not "
                 "markdown tables. Keep it tight. Still cite bankNN.asm:line and tag "
                 "CONFIRMED/INFERRED.]")

# --------------------------------------------------------------------------------- usage db
def _db():
    c = sqlite3.connect(DB_FILE)
    c.executescript("""
        CREATE TABLE IF NOT EXISTS usage(user_id TEXT, day TEXT, count INTEGER DEFAULT 0,
            cost REAL DEFAULT 0, PRIMARY KEY(user_id, day));
        CREATE TABLE IF NOT EXISTS daily(day TEXT PRIMARY KEY, count INTEGER DEFAULT 0,
            cost REAL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS cooldown(user_id TEXT PRIMARY KEY, last_ts REAL DEFAULT 0);
    """)
    return c


def _today():
    return dt.datetime.now(dt.timezone.utc).date().isoformat()


def gate(user_id: str, exempt: bool):
    """Return (ok, reason). Enforces cooldown, per-user daily quota, server daily budget."""
    day = _today()
    c = _db()
    try:
        spent = c.execute("SELECT cost FROM daily WHERE day=?", (day,)).fetchone()
        if spent and spent[0] >= DAILY_BUDGET_USD:
            return False, (f"The Oracle's daily budget (${DAILY_BUDGET_USD:.0f}) is used up — "
                           "it resets at 00:00 UTC. Back tomorrow.")
        if exempt:
            return True, ""
        last = c.execute("SELECT last_ts FROM cooldown WHERE user_id=?", (user_id,)).fetchone()
        if last and time.time() - last[0] < COOLDOWN_SEC:
            wait = int(COOLDOWN_SEC - (time.time() - last[0]))
            return False, f"Slow down — try again in {wait}s."
        row = c.execute("SELECT count FROM usage WHERE user_id=? AND day=?", (user_id, day)).fetchone()
        used = row[0] if row else 0
        if used >= PER_USER_DAILY:
            return False, (f"You've used your {PER_USER_DAILY} Oracle questions for today "
                           "(resets 00:00 UTC). Ask a **@Mod** if you need more.")
        return True, ""
    finally:
        c.close()


def record(user_id: str, cost: float):
    day = _today()
    c = _db()
    try:
        c.execute("INSERT INTO usage(user_id,day,count,cost) VALUES(?,?,1,?) "
                  "ON CONFLICT(user_id,day) DO UPDATE SET count=count+1, cost=cost+?",
                  (user_id, day, cost, cost))
        c.execute("INSERT INTO daily(day,count,cost) VALUES(?,1,?) "
                  "ON CONFLICT(day) DO UPDATE SET count=count+1, cost=cost+?", (day, cost, cost))
        c.execute("INSERT INTO cooldown(user_id,last_ts) VALUES(?,?) "
                  "ON CONFLICT(user_id) DO UPDATE SET last_ts=?",
                  (user_id, time.time(), time.time()))
        c.commit()
    finally:
        c.close()


def user_remaining(user_id: str) -> int:
    c = _db()
    try:
        row = c.execute("SELECT count FROM usage WHERE user_id=? AND day=?",
                        (user_id, _today())).fetchone()
        return max(0, PER_USER_DAILY - (row[0] if row else 0))
    finally:
        c.close()


def stats_today():
    c = _db()
    try:
        d = c.execute("SELECT count, cost FROM daily WHERE day=?", (_today(),)).fetchone() or (0, 0)
        top = c.execute("SELECT user_id, count, cost FROM usage WHERE day=? "
                        "ORDER BY count DESC LIMIT 5", (_today(),)).fetchall()
        return d[0], d[1], top
    finally:
        c.close()


def reset_user(user_id: str):
    c = _db()
    try:
        c.execute("DELETE FROM usage WHERE user_id=? AND day=?", (user_id, _today()))
        c.execute("DELETE FROM cooldown WHERE user_id=?", (user_id,))
        c.commit()
    finally:
        c.close()


# ------------------------------------------------------------------------------- the oracle
def _cost(usage) -> float:
    def g(o, k, default=0):
        if o is None:
            return default
        return (o.get(k) if isinstance(o, dict) else getattr(o, k, default)) or default
    cc = g(usage, "cache_creation")
    cw5 = g(cc, "ephemeral_5m_input_tokens")
    cw1h = g(cc, "ephemeral_1h_input_tokens")
    return (g(usage, "input_tokens") * PRICE["in"]
            + g(usage, "output_tokens") * PRICE["out"]
            + g(usage, "cache_read_input_tokens") * PRICE["cr"]
            + cw5 * PRICE["cw5"] + cw1h * PRICE["cw1h"]) / 1_000_000


def ask_oracle_blocking(ids: dict, gh: str, question: str):
    """Open a session, ask, return (answer_text, cost_usd). Blocking — call via to_thread."""
    c = anthropic.Anthropic()
    session = c.beta.sessions.create(
        agent={"type": "agent", "id": ids["agent_id"], "version": ids["agent_version"]},
        environment_id=ids["environment_id"],
        title="discord question",
        resources=[
            {"type": "github_repository", "url": REPO_URL,
             "authorization_token": gh, "mount_path": REPO_MOUNT},
            {"type": "github_repository", "url": FW_REPO_URL,
             "authorization_token": gh, "mount_path": FW_MOUNT},
            {"type": "memory_store", "memory_store_id": ids["memory_store_id"],
             "access": "read_only",
             "instructions": "re_kb findings + memory map + frame-data + NOBD knowledge. Read before "
                             "answering; cite what you use."},
        ],
    )
    parts = []
    with c.beta.sessions.events.stream(session_id=session.id) as stream:
        c.beta.sessions.events.send(
            session_id=session.id,
            events=[{"type": "user.message",
                     "content": [{"type": "text", "text": question + DISCORD_STYLE}]}],
        )
        for event in stream:
            t = event.type
            if t == "agent.message":
                for b in event.content:
                    if getattr(b, "type", None) == "text":
                        parts.append(b.text)
            elif t == "session.error":
                parts.append(f"\n_(session error: {getattr(event, 'error', '')})_")
                break
            elif t == "session.status_terminated":
                break
            elif t == "session.status_idle":
                sr = getattr(event, "stop_reason", None)
                if sr is None or getattr(sr, "type", None) != "requires_action":
                    break
    cost = 0.0
    try:
        cost = _cost(getattr(c.beta.sessions.retrieve(session.id), "usage", None))
    except Exception:
        pass
    try:
        c.beta.sessions.archive(session.id)  # tidy up
    except Exception:
        pass
    return ("".join(parts).strip() or "_(no answer)_"), cost


def chunk(text: str, limit: int = 1900):
    out, buf = [], ""
    for line in text.split("\n"):
        if len(buf) + len(line) + 1 > limit:
            if buf:
                out.append(buf)
            buf = line[:limit]
        else:
            buf = f"{buf}\n{line}" if buf else line
    if buf:
        out.append(buf)
    return out or ["_(empty)_"]


# ------------------------------------------------------------------------------- discord
intents = discord.Intents.default()
# Message Content is a privileged intent (portal toggle). Default OFF: Discord still delivers the
# text of messages that @mention the bot, so mention-triggering works with NO portal changes.
# Set ORACLE_MESSAGE_CONTENT=1 (and flip the toggle in the portal) to also catch `!oracle ...` in
# non-mention messages. The members intent isn't needed — message.author.roles is available for
# guild message authors as-is.
if os.environ.get("ORACLE_MESSAGE_CONTENT") == "1":
    intents.message_content = True
client = discord.Client(intents=intents)
_sem = asyncio.Semaphore(MAX_CONCURRENT)


def roles_of(member) -> set:
    return {r.name for r in getattr(member, "roles", [])}


def parse_trigger(message) -> str | None:
    content = message.content.strip()
    if content.lower().startswith("!oracle"):
        return content[len("!oracle"):].strip()
    if client.user in getattr(message, "mentions", []):
        return re.sub(rf"<@!?{client.user.id}>", "", content).strip()
    return None


@client.event
async def on_ready():
    mode = ("mention + !oracle prefix" if intents.message_content
            else "mention-only (set ORACLE_MESSAGE_CONTENT=1 + portal toggle for !oracle prefix)")
    print(f"Oracle bot online as {client.user} | trigger={mode} | channels={CHANNEL_IDS or 'any'} "
          f"| per-user/day={PER_USER_DAILY} | budget=${DAILY_BUDGET_USD}", flush=True)


@client.event
async def on_message(message):
    if message.author.bot:
        return
    if os.environ.get("ORACLE_DEBUG") == "1":
        print(f"[recv] ch={message.channel.id} from={message.author} "
              f"mentioned={client.user in getattr(message, 'mentions', [])} "
              f"content={message.content!r}", flush=True)
    if CHANNEL_IDS and message.channel.id not in CHANNEL_IDS:
        return
    roles = roles_of(message.author)

    # admin commands (Mod/Team only)
    low = message.content.strip().lower()
    if low.startswith("!oracle-") and roles & ADMIN_ROLES:
        if low.startswith("!oracle-stats"):
            n, cost, top = stats_today()
            lines = [f"**Oracle today:** {n} questions · ${cost:.2f} / ${DAILY_BUDGET_USD:.0f}"]
            for uid, cnt, cst in top:
                lines.append(f"• <@{uid}>: {cnt} (${cst:.2f})")
            await message.reply("\n".join(lines), mention_author=False)
            return
        if low.startswith("!oracle-reset") and message.mentions:
            for u in message.mentions:
                reset_user(str(u.id))
            await message.reply("Reset.", mention_author=False)
            return
        if low.startswith("!oracle-quota"):
            target = message.mentions[0] if message.mentions else message.author
            await message.reply(f"<@{target.id}> has {user_remaining(str(target.id))}/"
                                f"{PER_USER_DAILY} questions left today.", mention_author=False)
            return

    question = parse_trigger(message)
    if not question:
        return
    if len(question) < 5:
        await message.reply("Ask a real question, e.g. `!oracle where is sprite_id read?`",
                            mention_author=False)
        return

    exempt = bool(roles & EXEMPT_ROLES)
    ok, reason = gate(str(message.author.id), exempt)
    if not ok:
        await message.reply(reason, mention_author=False)
        return

    # Long answers flood a channel — reply in a THREAD off the question, keeping the main channel clean
    # while the full answer stays public + searchable. Falls back to an inline reply if the bot lacks
    # thread perms or the message is already inside a thread. Toggle off with ORACLE_THREADS=0.
    target = None
    if os.environ.get("ORACLE_THREADS", "1") != "0":
        try:
            target = await message.create_thread(name=f"Oracle: {question[:80]}",
                                                 auto_archive_duration=1440)
        except Exception:
            target = None
    if target:
        placeholder = await target.send(f"<@{message.author.id}> 🔮 consulting the disassembly…")
        sink = target
    else:
        placeholder = await message.reply("🔮 consulting the disassembly…", mention_author=False)
        sink = message.channel
    try:
        async with _sem:
            ids = json.loads(IDS_FILE.read_text())
            gh = os.environ["GITHUB_TOKEN"]
            answer, cost = await asyncio.to_thread(ask_oracle_blocking, ids, gh, question)
        record(str(message.author.id), cost)
        pieces = chunk(answer)
        await placeholder.edit(content=pieces[0])
        for p in pieces[1:]:
            await sink.send(p)
    except Exception as e:
        await placeholder.edit(content=f"⚠️ The Oracle hit an error: `{e}`")


def main():
    for var in ("DISCORD_BOT_TOKEN", "ANTHROPIC_API_KEY", "GITHUB_TOKEN"):
        if not os.environ.get(var):
            sys.exit(f"Set {var} first.")
    if not IDS_FILE.exists():
        sys.exit(f"{IDS_FILE} missing — run ../managed-agent/provision.py first.")
    client.run(os.environ["DISCORD_BOT_TOKEN"])


if __name__ == "__main__":
    main()
