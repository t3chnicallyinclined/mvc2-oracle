# MvC2 Oracle — Managed Agents build

The public Oracle, hosted on Claude's Managed Agents surface. Anthropic runs the agent loop and a
per-session container; the agent uses its **built-in toolset** (grep/read/glob/bash) over:

- **the marvelous2 disassembly** — the public `mountainmanjed/marvelous2` repo, mounted at
  `/workspace/marvelous2/` (cloned via Anthropic's git proxy)
- **the re_kb findings + docs** — a **memory store** (`mvc2-re-kb`) seeded from `re_kb/*.surql` +
  the memory-map / frame-data docs, mounted at `/mnt/memory/mvc2-re-kb/`

No hand-written retrieval tools, no local SurrealDB in the cloud. The memory store is the
persistence layer (and, on a trusted `--curate` path, where confirmed findings accumulate).

## Files

| file | what |
|---|---|
| `system_prompt_cma.md` | the agent persona (knows the mount paths) |
| `environment.yaml` / `agent.yaml` | version-controlled control-plane definitions (for the `ant` CLI) |
| `provision.py` | SDK alternative: create env + memory store (seeded) + agent → `oracle_ids.json` |
| `run_session.py` | data plane: open a session, mount repo + memory, ask, stream the answer |

## Two ways to create it

**A — Python SDK (what I can run for you):**
```bash
pip install anthropic
set ANTHROPIC_API_KEY=...        # FUNDED key for the target workspace
python provision.py             # creates env + memory store + agent, writes oracle_ids.json
set GITHUB_TOKEN=...             # fine-grained PAT, Contents: Read (public repo, minimal)
python run_session.py "Where is the per-frame body emitter and what does it read?"
```

**B — `ant` CLI (version-controlled, recommended long-term):**
```bash
ENV_ID=$(ant beta:environments create < environment.yaml --transform id -r)
AGENT_ID=$(ant beta:agents create < agent.yaml --transform id -r)
# memory store + seeding + sessions: provision.py / run_session.py, or ant beta:memory-stores …
```

## Credentials needed (to provision + run)

1. **Anthropic API key — FUNDED**, for the workspace you want this in. A standard key (or an
   `ant auth login` profile) is enough; Managed Agents create/session/memory are normal
   workspace operations — **no `org:admin` scope needed**. The workspace must have a spend limit
   > $0 and Managed Agents (beta) access.
2. **GitHub PAT — fine-grained, `Contents: Read`** for `mountainmanjed/marvelous2`. The repo is
   public, so this is minimal scope; it's only the clone-auth token the mount requires.

## Memory: read-only by default
`run_session.py` mounts the memory store **read-only**. A writable memory store + untrusted public
input is a poisoning vector — append confirmed findings only via the trusted `--curate` flag.
Keep your local SurrealDB `re_kb` as the authoritative graph; periodically re-export it into the
memory store (re-run `provision.py` seeding).

## Cost / billing
Same pay-as-you-go API credits as any Claude API use. Per-session container provisioning + Opus
4.8 inference; prompt caching applies to the agent's static prefix. Pennies-to-cents per question.

## Discord
Still your glue: a small service that, on a Discord message, calls `run_session.py`'s flow (open
session → send → stream) and posts the answer to **#re-and-tech**. Managed Agents hosts the agent,
container, and memory — not the Discord connection.
