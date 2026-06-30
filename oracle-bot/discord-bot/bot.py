#!/usr/bin/env python3
"""
MvC2 Oracle — Discord bot.

Listens in one channel; on `!oracle <question>` or an @mention, opens a Managed Agents session
(agent + marvelous2 repo mount + re_kb memory store from ../managed-agent/oracle_ids.json),
streams the cited answer back. Rate-limited per user + a hard daily $ budget, persisted to SQLite.

The answer lands in a thread that stays open for follow-ups: the original asker can keep asking
in that thread (up to ORACLE_FOLLOWUP_MAX, default 5), each routed back into the SAME session so
context carries over. Follow-ups count against the daily $ budget but not the per-user question
quota. Threads idle past ORACLE_THREAD_TTL_SEC are archived. By default (chat-box mode) any message
the asker types in the thread continues it — pure acknowledgements ("thanks") are ignored so they
don't burn a turn. Set ORACLE_MESSAGE_CONTENT=0 to fall back to mention-only (follow-ups then need
an @mention).

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
# Conversation: after the first answer the question's thread stays open for follow-ups, each
# routed back into the SAME managed-agent session (full context carries over). Capped per thread.
FOLLOWUP_MAX = int(os.environ.get("ORACLE_FOLLOWUP_MAX", "5"))
THREAD_TTL_SEC = int(os.environ.get("ORACLE_THREAD_TTL_SEC", "3600"))
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
        CREATE TABLE IF NOT EXISTS threads(thread_id INTEGER PRIMARY KEY, session_id TEXT,
            owner TEXT, turns INTEGER DEFAULT 0, cost REAL DEFAULT 0, ts REAL DEFAULT 0);
    """)
    return c


def _today():
    return dt.datetime.now(dt.timezone.utc).date().isoformat()


def gate(user_id: str, exempt: bool, followup: bool = False):
    """Return (ok, reason). Server daily budget always applies. Follow-ups inside an already-open
    thread (followup=True) skip the per-user daily quota + cooldown — they're bounded by the
    per-thread FOLLOWUP_MAX cap instead."""
    day = _today()
    c = _db()
    try:
        spent = c.execute("SELECT cost FROM daily WHERE day=?", (day,)).fetchone()
        if spent and spent[0] >= DAILY_BUDGET_USD:
            return False, (f"The Oracle's daily budget (${DAILY_BUDGET_USD:.0f}) is used up — "
                           "it resets at 00:00 UTC. Back tomorrow.")
        if exempt or followup:
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


def record(user_id: str, cost: float, count: bool = True):
    """Charge `cost` to the daily budget. count=True also burns one of the user's daily questions
    and bumps the question tally; follow-ups pass count=False (cost still counts, quota doesn't)."""
    day = _today()
    n = 1 if count else 0
    c = _db()
    try:
        c.execute("INSERT INTO usage(user_id,day,count,cost) VALUES(?,?,?,?) "
                  "ON CONFLICT(user_id,day) DO UPDATE SET count=count+?, cost=cost+?",
                  (user_id, day, n, cost, n, cost))
        c.execute("INSERT INTO daily(day,count,cost) VALUES(?,?,?) "
                  "ON CONFLICT(day) DO UPDATE SET count=count+?, cost=cost+?", (day, n, cost, n, cost))
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


def open_oracle_session(ids: dict, gh: str) -> str:
    """Create a managed-agent session (repo mounts + memory store) and return its id. Kept alive so
    the question's Discord thread can carry follow-up turns; archive it when the thread is done."""
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
    return session.id


def ask_in_session(session_id: str, question: str, prev_cost: float = 0.0):
    """Send one user turn into an existing session and stream the reply. Returns
    (answer_text, delta_cost_usd, cumulative_cost_usd). Blocking — call via to_thread.
    Session usage is cumulative, so we bill the delta over prev_cost."""
    c = anthropic.Anthropic()
    parts = []
    with c.beta.sessions.events.stream(session_id=session_id) as stream:
        c.beta.sessions.events.send(
            session_id=session_id,
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
    cum = prev_cost
    try:
        cum = _cost(getattr(c.beta.sessions.retrieve(session_id), "usage", None))
    except Exception:
        pass
    delta = max(0.0, cum - prev_cost)
    return ("".join(parts).strip() or "_(no answer)_"), delta, cum


def archive_session(session_id: str):
    try:
        anthropic.Anthropic().beta.sessions.archive(session_id)
    except Exception:
        pass


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
# Message Content is a privileged intent (portal toggle, enabled per the README setup). Default ON
# so threads act like a chat box — follow-ups (and `!oracle ...`) work WITHOUT an @mention. If the
# portal toggle isn't granted, discord.py raises PrivilegedIntentsRequired at startup; either enable
# it in the Developer Portal or set ORACLE_MESSAGE_CONTENT=0 to fall back to mention-only. The
# members intent isn't needed — message.author.roles is available for guild message authors as-is.
if os.environ.get("ORACLE_MESSAGE_CONTENT", "1") != "0":
    intents.message_content = True
client = discord.Client(intents=intents)
_sem = asyncio.Semaphore(MAX_CONCURRENT)

# Open Oracle threads that accept follow-ups: thread_id -> {session, owner, turns, cost, ts}.
# Mirrored to the `threads` SQLite table so follow-ups survive a bot restart (see restore_threads).
_threads: dict[int, dict] = {}


def _save_thread(thread_id: int, e: dict):
    c = _db()
    try:
        c.execute("INSERT INTO threads(thread_id,session_id,owner,turns,cost,ts) VALUES(?,?,?,?,?,?) "
                  "ON CONFLICT(thread_id) DO UPDATE SET session_id=excluded.session_id, "
                  "owner=excluded.owner, turns=excluded.turns, cost=excluded.cost, ts=excluded.ts",
                  (thread_id, e["session"], e["owner"], e["turns"], e["cost"], e["ts"]))
        c.commit()
    finally:
        c.close()


def _delete_thread(thread_id: int):
    c = _db()
    try:
        c.execute("DELETE FROM threads WHERE thread_id=?", (thread_id,))
        c.commit()
    finally:
        c.close()


async def restore_threads():
    """On startup, reload open threads from SQLite. Any already past the TTL get archived + dropped."""
    now = time.time()
    c = _db()
    try:
        rows = c.execute("SELECT thread_id,session_id,owner,turns,cost,ts FROM threads").fetchall()
    finally:
        c.close()
    restored = 0
    for tid, sid, owner, turns, cost, ts in rows:
        if now - (ts or 0) > THREAD_TTL_SEC:
            await asyncio.to_thread(archive_session, sid)
            _delete_thread(tid)
        else:
            _threads[int(tid)] = {"session": sid, "owner": owner, "turns": turns,
                                  "cost": cost, "ts": ts}
            restored += 1
    if restored:
        print(f"restored {restored} open Oracle thread(s) from db", flush=True)


def _follow_hint() -> str:
    if intents.message_content:
        return f"💬 _Ask follow-ups right here in this thread — up to {FOLLOWUP_MAX} more._"
    return f"💬 _Follow-ups: @mention me in this thread to keep going — up to {FOLLOWUP_MAX} more._"


# Pure acknowledgements that shouldn't spend one of the limited follow-up turns in chat-box mode.
_ACKS = {"thanks", "thank you", "ty", "tysm", "thx", "thnx", "ok", "okay", "k", "kk", "nice", "cool",
         "got it", "gotcha", "great", "perfect", "gg", "lol", "lmao", "nvm", "never mind", "np",
         "yw", "sweet", "awesome", "based", "word", "facts", "fire", "dope", "neat", "huh", "wow"}


def _is_chatter(text: str) -> bool:
    """True for bare acknowledgements / emoji-only — seen but not worth a follow-up turn."""
    t = re.sub(r"[^\w\s]", "", text).strip().lower()
    return t == "" or t in _ACKS


def thread_followup_text(message) -> str | None:
    """Pull a follow-up question out of a message inside a tracked Oracle thread. Reads @mention
    text (always available) or raw text when the message-content intent is enabled."""
    if client.user in getattr(message, "mentions", []):
        txt = re.sub(rf"<@!?{client.user.id}>", "", message.content).strip()
    elif intents.message_content:
        txt = message.content.strip()
    else:
        return None
    if txt.lower().startswith("!oracle"):
        txt = txt[len("!oracle"):].strip()
    return txt or None


async def end_thread(thread_id: int):
    e = _threads.pop(thread_id, None)
    _delete_thread(thread_id)
    if e:
        await asyncio.to_thread(archive_session, e["session"])


async def reap_threads():
    """Archive + forget threads idle past the TTL so server sessions don't dangle."""
    now = time.time()
    for tid in [t for t, e in list(_threads.items()) if now - e["ts"] > THREAD_TTL_SEC]:
        await end_thread(tid)


async def handle_followup(message, entry: dict, question: str, exempt: bool):
    """Continue an open thread's session with one more turn (no new thread, no quota burn)."""
    if len(question) < 5:
        return
    if entry["turns"] >= FOLLOWUP_MAX:
        await message.reply(f"This thread's hit its {FOLLOWUP_MAX}-follow-up limit — start a fresh "
                            "question with `!oracle …` or an @mention in the channel.",
                            mention_author=False)
        await end_thread(message.channel.id)
        return
    ok, reason = gate(str(message.author.id), exempt, followup=True)
    if not ok:
        await message.reply(reason, mention_author=False)
        return
    placeholder = await message.reply("🔮 consulting the disassembly…", mention_author=False)
    try:
        async with _sem:
            answer, delta, cum = await asyncio.to_thread(
                ask_in_session, entry["session"], question, entry["cost"])
        entry["turns"] += 1
        entry["cost"] = cum
        entry["ts"] = time.time()
        _save_thread(message.channel.id, entry)
        record(str(message.author.id), delta, count=False)
        pieces = chunk(answer)
        await placeholder.edit(content=pieces[0])
        for p in pieces[1:]:
            await message.channel.send(p)
        left = FOLLOWUP_MAX - entry["turns"]
        if left <= 0:
            await message.channel.send(f"_(Last of {FOLLOWUP_MAX} follow-ups for this thread — "
                                       "start a new question for more.)_")
            await end_thread(message.channel.id)
        else:
            await message.channel.send(f"_({left} follow-up{'' if left == 1 else 's'} left.)_")
    except Exception as e:
        await placeholder.edit(content="⚠️ The Oracle hit an error (the thread may have expired — "
                                       f"start a new question): `{e}`")
        await end_thread(message.channel.id)

# Slash commands (/bug, /feature -> GitHub issues). Requires the bot to be invited
# with the applications.commands scope. See dev_commands.py.
from discord import app_commands  # noqa: E402
import dev_commands  # noqa: E402
tree = app_commands.CommandTree(client)
dev_commands.setup_dev_commands(tree)


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
    mode = ("chat-box (thread follow-ups need no @mention) + !oracle prefix" if intents.message_content
            else "mention-only (set ORACLE_MESSAGE_CONTENT=1 + portal toggle for chat-box mode)")
    print(f"Oracle bot online as {client.user} | trigger={mode} | channels={CHANNEL_IDS or 'any'} "
          f"| per-user/day={PER_USER_DAILY} | budget=${DAILY_BUDGET_USD}", flush=True)
    await restore_threads()
    # Register slash commands. Guild-scoped sync (DEV_GUILD_ID) is instant; global takes ~1h.
    try:
        gid = os.environ.get("DEV_GUILD_ID")
        if gid:
            g = discord.Object(id=int(gid))
            tree.copy_global_to(guild=g)
            synced = await tree.sync(guild=g)
        else:
            synced = await tree.sync()
        print(f"slash commands synced: {[c.name for c in synced]}", flush=True)
    except Exception as e:
        print(f"slash sync failed: {e}", flush=True)


@client.event
async def on_message(message):
    if message.author.bot:
        return
    if os.environ.get("ORACLE_DEBUG") == "1":
        print(f"[recv] ch={message.channel.id} from={message.author} "
              f"mentioned={client.user in getattr(message, 'mentions', [])} "
              f"content={message.content!r}", flush=True)
    is_oracle_thread = message.channel.id in _threads
    if CHANNEL_IDS and not is_oracle_thread and message.channel.id not in CHANNEL_IDS:
        return
    roles = roles_of(message.author)

    # Follow-up inside an open Oracle thread → continue the same session (no new thread / quota).
    if is_oracle_thread:
        entry = _threads[message.channel.id]
        if str(message.author.id) != entry["owner"] and not (roles & EXEMPT_ROLES):
            return  # only the original asker (or staff) drives the thread
        follow = thread_followup_text(message)
        if follow and _is_chatter(follow):
            try:
                await message.add_reaction("👍")  # acknowledge without spending a turn
            except Exception:
                pass
        elif follow:
            await handle_followup(message, entry, follow, bool(roles & EXEMPT_ROLES))
        return

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
    sid = None
    try:
        async with _sem:
            ids = json.loads(IDS_FILE.read_text())
            gh = os.environ["GITHUB_TOKEN"]
            sid = await asyncio.to_thread(open_oracle_session, ids, gh)
            answer, delta, cum = await asyncio.to_thread(ask_in_session, sid, question, 0.0)
        record(str(message.author.id), delta, count=True)
        pieces = chunk(answer)
        await placeholder.edit(content=pieces[0])
        for p in pieces[1:]:
            await sink.send(p)
        # Keep the session alive for follow-ups only when we answered in a real thread.
        if target is not None:
            await reap_threads()
            _threads[target.id] = {"session": sid, "owner": str(message.author.id),
                                   "turns": 0, "cost": cum, "ts": time.time()}
            _save_thread(target.id, _threads[target.id])
            await sink.send(_follow_hint())
        else:
            await asyncio.to_thread(archive_session, sid)
    except Exception as e:
        await placeholder.edit(content=f"⚠️ The Oracle hit an error: `{e}`")
        if sid:
            await asyncio.to_thread(archive_session, sid)


def main():
    for var in ("DISCORD_BOT_TOKEN", "ANTHROPIC_API_KEY", "GITHUB_TOKEN"):
        if not os.environ.get(var):
            sys.exit(f"Set {var} first.")
    if not IDS_FILE.exists():
        sys.exit(f"{IDS_FILE} missing — run ../managed-agent/provision.py first.")
    try:
        client.run(os.environ["DISCORD_BOT_TOKEN"])
    except discord.errors.PrivilegedIntentsRequired:
        sys.exit("Message Content Intent is not enabled for this bot. Either turn it on in the "
                 "Discord Developer Portal (Bot → Privileged Gateway Intents → Message Content), "
                 "or run with ORACLE_MESSAGE_CONTENT=0 for mention-only mode.")


if __name__ == "__main__":
    main()
