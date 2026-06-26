#!/usr/bin/env python3
"""
Drive one MvC2 Oracle session (data plane). Reads oracle_ids.json from provision.py, mounts the
public marvelous2 repo + the re_kb memory store, asks a question, streams the answer.

    set ANTHROPIC_API_KEY=...        (funded)
    set GITHUB_TOKEN=...             (fine-grained PAT, Contents: Read — public repo, minimal scope)
    python run_session.py "Where is the per-frame body emitter and what does it read?"
    python run_session.py --curate "..."   # mount memory read-WRITE (trusted/dev use only)

Public Discord use should stay read-only (default): a writable memory store + untrusted input is a
poisoning vector. Append confirmed findings only from a trusted/curate path.
"""
import os
import sys
import json
from pathlib import Path

try:
    import anthropic
except ImportError:
    sys.exit("pip install anthropic")

HERE = Path(__file__).resolve().parent
IDS_FILE = HERE / "oracle_ids.json"
REPO_URL = os.environ.get("MARV_REPO_URL", "https://github.com/mountainmanjed/marvelous2")
REPO_MOUNT = "/workspace/marvelous2"
FW_REPO_URL = os.environ.get("FW_REPO_URL", "https://github.com/t3chnicallyinclined/GP2040-CE-NOBD")
FW_MOUNT = "/workspace/gp2040"


def main():
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8")
        except Exception:
            pass

    argv = sys.argv[1:]
    curate = "--curate" in argv
    argv = [a for a in argv if a != "--curate"]
    if not argv:
        sys.exit("usage: python run_session.py [--curate] \"your question\"")
    question = " ".join(argv)

    if not os.environ.get("ANTHROPIC_API_KEY"):
        sys.exit("Set ANTHROPIC_API_KEY (funded) first.")
    gh = os.environ.get("GITHUB_TOKEN")
    if not gh:
        sys.exit("Set GITHUB_TOKEN (fine-grained PAT, Contents: Read) to mount the marvelous2 repo.")
    if not IDS_FILE.exists():
        sys.exit("oracle_ids.json missing — run provision.py first.")
    ids = json.loads(IDS_FILE.read_text())

    c = anthropic.Anthropic()
    access = "read_write" if curate else "read_only"
    session = c.beta.sessions.create(
        agent={"type": "agent", "id": ids["agent_id"], "version": ids["agent_version"]},
        environment_id=ids["environment_id"],
        title="oracle question",
        resources=[
            {"type": "github_repository", "url": REPO_URL,
             "authorization_token": gh, "mount_path": REPO_MOUNT},
            {"type": "github_repository", "url": FW_REPO_URL,
             "authorization_token": gh, "mount_path": FW_MOUNT},
            {"type": "memory_store", "memory_store_id": ids["memory_store_id"],
             "access": access,
             "instructions": "re_kb findings + memory map + frame-data fields. Read before "
                             "answering; cite what you use."},
        ],
    )
    print(f"\033[90msession {session.id} · memory {access} · "
          f"console: https://platform.claude.com/workspaces/default/sessions/{session.id}\033[0m",
          file=sys.stderr)

    # stream-first, then send
    with c.beta.sessions.events.stream(session_id=session.id) as stream:
        c.beta.sessions.events.send(
            session_id=session.id,
            events=[{"type": "user.message", "content": [{"type": "text", "text": question}]}],
        )
        for event in stream:
            t = event.type
            if t == "agent.message":
                for b in event.content:
                    if getattr(b, "type", None) == "text":
                        print(b.text)
            elif t in ("agent.tool_use", "agent.mcp_tool_use"):
                print(f"\033[36m→ {getattr(event, 'name', t)}\033[0m", file=sys.stderr)
            elif t == "session.error":
                print(f"\033[31m[error] {getattr(event, 'error', '')}\033[0m", file=sys.stderr)
                break
            elif t == "session.status_terminated":
                break
            elif t == "session.status_idle":
                sr = getattr(event, "stop_reason", None)
                if sr is None or getattr(sr, "type", None) != "requires_action":
                    break


if __name__ == "__main__":
    main()
