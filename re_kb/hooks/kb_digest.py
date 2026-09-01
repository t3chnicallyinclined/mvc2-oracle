# -*- coding: utf-8 -*-
"""kb_digest.py -- PreCompact hook: carry the settled facts across a compaction.

WHY
---
Compaction summarises the conversation. What survives is whatever the summary
happened to mention -- so a confirmed address, or a dead end that was ruled out
two hours ago, can quietly leave the session and get re-derived. The graph
already holds those facts durably; this puts them back in front of the model at
the one moment they are about to be dropped.

WHAT IT EMITS
-------------
Deliberately NOT the whole graph. Two things, smallest-first:

  1. RULED OUT / SUPERSEDED -- every one of them. These are the cheapest
     knowledge to record and the most expensive to rediscover, and almost no
     system stores them at all. They go first because they are what stops a
     re-walk.
  2. CONFIRMED -- one line each, newest first, until the budget runs out.

Statuses that are neither (open, inferred) are left out on purpose: an unsettled
claim re-injected as bare text reads like a fact, which is the exact confusion
the status vocabulary exists to prevent.

CONTRACT
--------
Writes plain text on stdout, exits 0. Advisory: if SurrealDB is not running it
prints nothing and exits 0. It must never be able to fail a compaction.

Install: see .claude/settings.json (PreCompact).
Test:    echo '{}' | python tools/re_kb/hooks/kb_digest.py
"""
import base64
import json
import os
import sys
import urllib.request

URL = os.environ.get("REKB_URL", "http://127.0.0.1:8001/sql")
AUTH = os.environ.get("REKB_AUTH", "root:root")
TIMEOUT = float(os.environ.get("REKB_HOOK_TIMEOUT", "4"))
BUDGET = int(os.environ.get("REKB_DIGEST_BUDGET", "9000"))   # characters


def sql(stmt):
    req = urllib.request.Request(
        URL, data=("USE NS re DB kb; " + stmt).encode("utf-8"), method="POST")
    req.add_header("Accept", "application/json")
    req.add_header("Authorization", "Basic " + base64.b64encode(AUTH.encode()).decode())
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return json.loads(r.read().decode("utf-8"))


def rows(res):
    out = []
    for b in res if isinstance(res, list) else []:
        if isinstance(b, dict) and b.get("status") == "OK" and isinstance(b.get("result"), list):
            out.extend(b["result"])
    return out


def trim(s, n):
    s = " ".join(str(s or "").split())
    return s if len(s) <= n else s[:n - 1] + "…"


def main():
    try:
        sys.stdin.read()
    except Exception:
        pass

    try:
        dead = rows(sql(
            "SELECT record::id(id) AS id, status, statement, tried, evidence "
            "FROM finding WHERE status IN ['ruled_out','superseded'] "
            "ORDER BY id;"))
        conf = rows(sql(
            "SELECT record::id(id) AS id, statement, date FROM finding "
            "WHERE status = 'confirmed' ORDER BY date DESC;"))
    except Exception:
        return 0

    if not dead and not conf:
        return 0

    out = ["## re_kb -- settled facts (re-injected before compaction)",
           "The RE knowledge graph in tools/re_kb holds these durably. Query it "
           "with tools/re_kb/rekb.sh rather than re-deriving. Anything not "
           "listed here is NOT settled -- open and inferred claims are "
           "deliberately omitted so they cannot be mistaken for facts."]

    if dead:
        out.append("")
        out.append("### Already ruled out -- do not re-walk without new evidence")
        for r in dead:
            out.append("- [%s] %s: %s"
                       % (r.get("status"), r.get("id"),
                          trim(r.get("tried") or r.get("statement"), 220)))

    used = sum(len(x) for x in out)
    if conf:
        out.append("")
        out.append("### Confirmed (newest first; truncated to fit)")
        used = sum(len(x) for x in out)
        shown = 0
        for r in conf:
            line = "- %s%s: %s" % (r.get("id"),
                                   " (%s)" % r["date"] if r.get("date") else "",
                                   trim(r.get("statement"), 200))
            if used + len(line) > BUDGET:
                out.append("- … +%d more confirmed findings -- "
                           "tools/re_kb/rekb.sh \"SELECT id, statement FROM finding "
                           "WHERE status='confirmed';\"" % (len(conf) - shown))
                break
            out.append(line)
            used += len(line)
            shown += 1

    sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
