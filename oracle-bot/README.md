# MvC2 Oracle — RE Q&A bot

A public reverse-engineering assistant for Marvel vs Capcom 2 (Sega Naomi / Dreamcast, SH4).
Ask it technical questions; it answers grounded in the **marvelous2 disassembly**, the **re_kb
knowledge graph**, and the project docs — citing `bankNN.asm:line` / `re_kb` and tagging every
claim **CONFIRMED** vs **INFERRED**. It never guesses an address.

It's the [`mvc2-sh4-re-expert`](../../maplecast-flycast/.claude/agents/mvc2-sh4-re-expert.md)
agent given an API-driven body: same cite-or-don't-claim discipline, reachable from a CLI (and,
next, Discord) instead of only inside Claude Code.

## How it works

- **Brain:** `system_prompt.md` (the persona + cardinal rules + how to read marvelous2).
- **Always-in-context (cached):** the `re_kb/*.surql` seed graph + `MVC2-MEMORY-MAP.md` +
  `MVC2-FRAMEDATA-FIELDS.md`. The seeds are the version-controlled source of truth, so the bot
  knows the graph even when SurrealDB is down. Sent as a cached system prefix (Opus 4.8) — ~0.1×
  cost on every follow-up question.
- **Retrieved on demand (tools):** the ~17 MB disassembly is far too big for context, so the bot
  pulls only what it needs:
  | tool | what |
  |---|---|
  | `rekb_query` | live SurrealDB query (precise graph traversals) |
  | `grep_disasm` / `read_disasm` | search + read the `marvelous2` banks + `pl_mem`/`work` |
  | `grep_docs` / `read_doc` | search + read the project docs |
- **Out of scope:** the live Oracle / ASMTRACE captures (source *e*) need a running flycast + your
  ROM. The bot can't run them — it describes how you'd capture, and answers statically otherwise.

## Run

```bash
pip install -r requirements.txt
export ANTHROPIC_API_KEY=...

# one-shot
python oracle.py "Where is the per-frame body emitter and what does it read?"

# interactive
python oracle.py
```

Optional — for live `rekb_query` (otherwise it falls back to the cached seed text):

```bash
cd ../re_kb
surreal start --user root --pass root --bind 127.0.0.1:8001 rocksdb:re_kb_data/re_kb
```

## Config (env)

| var | default |
|---|---|
| `ANTHROPIC_API_KEY` | — (required) |
| `ORACLE_MODEL` | `claude-opus-4-8` |
| `MARV_RE_DIR` | `C:/Users/trist/projects/_marv_re` |
| `ORACLE_DOCS` | `C:/Users/trist/projects/mvc2-oracle/docs` |
| `REKB_DIR` | `C:/Users/trist/projects/mvc2-oracle/re_kb` |
| `REKB_URL` / `REKB_AUTH` / `REKB_NS` / `REKB_DB` | `http://127.0.0.1:8001/sql` / `root:root` / `re` / `kb` |

## Next

- Wire the same `ask()` into a Discord bot for **#re-and-tech**.
- Optional: an anotak field-semantics tool (currently covered by the `dataformat` nodes in re_kb).
