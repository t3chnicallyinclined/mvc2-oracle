#!/usr/bin/env python3
"""
MvC2 Oracle — a public reverse-engineering Q&A bot over the marvelous2 SH4 disassembly,
the re_kb knowledge graph, and the project docs.

The brain is `system_prompt.md` (adapted from the mvc2-sh4-re-expert agent). The re_kb graph
and the memory-map / frame-data docs are loaded into a CACHED system prefix so the bot always
has the knowledge; the large disassembly stays out of context and is fetched on demand by tools.

Usage:
    export ANTHROPIC_API_KEY=...
    python oracle.py "Where is the per-frame body emitter and what does it read?"
    python oracle.py            # interactive REPL

Source paths are env-overridable (see CONFIG). Model defaults to claude-opus-4-8.
"""
import os
import re
import sys
import json
import base64
import urllib.request
import urllib.error
from pathlib import Path

try:
    import anthropic
except ImportError:
    sys.exit("Install the SDK first:  pip install anthropic")

# ----------------------------------------------------------------------------- config
HERE = Path(__file__).resolve().parent


def _p(env, default):
    return Path(os.environ.get(env, default))


MARV_RE = _p("MARV_RE_DIR", r"C:/Users/trist/projects/_marv_re")
DOCS_DIR = _p("ORACLE_DOCS", r"C:/Users/trist/projects/mvc2-oracle/docs")
REKB_DIR = _p("REKB_DIR", r"C:/Users/trist/projects/mvc2-oracle/re_kb")
REKB_URL = os.environ.get("REKB_URL", "http://127.0.0.1:8001/sql")
REKB_AUTH = os.environ.get("REKB_AUTH", "root:root")
REKB_NS = os.environ.get("REKB_NS", "re")
REKB_DB = os.environ.get("REKB_DB", "kb")
MODEL = os.environ.get("ORACLE_MODEL", "claude-opus-4-8")

DISASM_DIRS = [MARV_RE / "build", MARV_RE / "memory"]
MAX_GREP_HITS = 80
MAX_READ_LINES = 500

# ------------------------------------------------------------------------- prompt build
# Docs included verbatim in the cached prefix (full detail beyond the condensed map in the
# persona). Keep this list stable — any change reprices the whole cache.
CONTEXT_DOCS = ["MVC2-MEMORY-MAP.md", "MVC2-FRAMEDATA-FIELDS.md"]


def _read(path):
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        return f"[could not read {path}: {e}]"


def build_system_blocks():
    """Persona + re_kb seed graph + key docs, as cacheable system blocks (stable bytes)."""
    persona = _read(HERE / "system_prompt.md")

    kb_parts = ["# re_kb knowledge graph (version-controlled seeds — the canonical findings)\n"]
    for seed in sorted(REKB_DIR.glob("*.surql")):
        kb_parts.append(f"\n===== re_kb/{seed.name} =====\n{_read(seed)}")
    for name in CONTEXT_DOCS:
        kb_parts.append(f"\n===== docs/{name} =====\n{_read(DOCS_DIR / name)}")
    kb_text = "".join(kb_parts)

    # Two blocks; cache_control on the last caches the whole prefix together.
    return [
        {"type": "text", "text": persona},
        {"type": "text", "text": kb_text, "cache_control": {"type": "ephemeral"}},
    ]


# ------------------------------------------------------------------------------ tools
def _safe(base: Path, name: str) -> Path | None:
    """Resolve `name` under `base`, refusing anything that escapes the directory."""
    base = base.resolve()
    target = (base / name).resolve()
    try:
        target.relative_to(base)
    except ValueError:
        return None
    return target


def grep_files(roots, glob, pattern, ignore_case):
    flags = re.IGNORECASE if ignore_case else 0
    try:
        rx = re.compile(pattern, flags)
    except re.error as e:
        return f"bad regex: {e}"
    hits = []
    for root in roots:
        if not root.exists():
            continue
        for f in sorted(root.rglob(glob)):
            try:
                with f.open(encoding="utf-8", errors="replace") as fh:
                    for i, line in enumerate(fh, 1):
                        if rx.search(line):
                            rel = f.relative_to(root.parent if root.parent.exists() else root)
                            hits.append(f"{rel}:{i}: {line.rstrip()}")
                            if len(hits) >= MAX_GREP_HITS:
                                hits.append(f"... (truncated at {MAX_GREP_HITS} hits — narrow the pattern)")
                                return "\n".join(hits)
            except OSError:
                continue
    return "\n".join(hits) if hits else "(no matches)"


def tool_grep_disasm(pattern, ignore_case=False):
    return grep_files(DISASM_DIRS, "*.asm", pattern, ignore_case)


def tool_read_disasm(file, start_line, end_line):
    # accept "build/bank03.asm", "bank03.asm", or "memory/work.asm"
    cand = _safe(MARV_RE, file)
    if cand is None or not cand.exists():
        for d in DISASM_DIRS:
            c = _safe(d, Path(file).name)
            if c and c.exists():
                cand = c
                break
    if cand is None or not cand.exists():
        return f"file not found: {file} (try a path like build/bank03.asm)"
    start = max(1, int(start_line))
    end = int(end_line)
    if end - start + 1 > MAX_READ_LINES:
        end = start + MAX_READ_LINES - 1
    out = []
    with cand.open(encoding="utf-8", errors="replace") as fh:
        for i, line in enumerate(fh, 1):
            if i < start:
                continue
            if i > end:
                break
            out.append(f"{i}: {line.rstrip()}")
    return "\n".join(out) if out else f"(no lines {start}-{end} in {file})"


def tool_grep_docs(pattern, ignore_case=False):
    return grep_files([DOCS_DIR], "*.md", pattern, ignore_case)


def tool_read_doc(path, start_line=None, end_line=None):
    cand = _safe(DOCS_DIR, Path(path).name if "/" not in path and "\\" not in path else path)
    if cand is None or not cand.exists():
        return f"doc not found: {path}"
    lines = cand.read_text(encoding="utf-8", errors="replace").splitlines()
    if start_line is None:
        text = "\n".join(lines[:600])
        if len(lines) > 600:
            text += "\n... (truncated — pass start_line/end_line for more)"
        return text
    s = max(1, int(start_line))
    e = min(len(lines), int(end_line) if end_line else s + MAX_READ_LINES - 1)
    e = min(e, s + MAX_READ_LINES - 1)
    return "\n".join(f"{i}: {lines[i-1]}" for i in range(s, e + 1))


def tool_rekb_query(query):
    user, _, pw = REKB_AUTH.partition(":")
    token = base64.b64encode(f"{user}:{pw}".encode()).decode()
    req = urllib.request.Request(REKB_URL, data=query.encode(), method="POST")
    req.add_header("Authorization", f"Basic {token}")
    req.add_header("Accept", "application/json")
    req.add_header("NS", REKB_NS)
    req.add_header("DB", REKB_DB)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.read().decode()
    except urllib.error.URLError as e:
        return (f"re_kb live query not reachable ({e}). The DB likely isn't running. "
                "Fall back to the re_kb seed text in your context, and tell the user the answer "
                "came from the seeds rather than a live query.\n"
                "To start it: surreal start --user root --pass root --bind 127.0.0.1:8001 "
                "rocksdb:re_kb_data/re_kb")


TOOLS = [
    {
        "name": "rekb_query",
        "description": "Run a SurrealDB SQL query against the live re_kb graph (ns=re, db=kb). "
                       "Use for precise graph traversals when the re_kb seed text in context "
                       "isn't enough. If it returns 'not reachable', the DB is down — use the "
                       "seed text instead.",
        "input_schema": {
            "type": "object",
            "properties": {"query": {"type": "string", "description": "SurrealQL, e.g. "
                           "SELECT name FROM field WHERE owner='char_struct' ORDER BY offset;"}},
            "required": ["query"],
        },
    },
    {
        "name": "grep_disasm",
        "description": "Regex search across the marvelous2 disassembly (all bank*.asm + "
                       "pl_mem.asm + work.asm). Returns file:line: text. Start here to locate a "
                       "loc_8c… label, symbol, or instruction.",
        "input_schema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string"},
                "ignore_case": {"type": "boolean"},
            },
            "required": ["pattern"],
        },
    },
    {
        "name": "read_disasm",
        "description": "Read a line range from one disasm file (e.g. file='build/bank03.asm', "
                       "start_line=10218, end_line=10320). Use after grep_disasm to read the code.",
        "input_schema": {
            "type": "object",
            "properties": {
                "file": {"type": "string"},
                "start_line": {"type": "integer"},
                "end_line": {"type": "integer"},
            },
            "required": ["file", "start_line", "end_line"],
        },
    },
    {
        "name": "grep_docs",
        "description": "Regex search the project docs (memory map, frame-data fields, GFX notes, "
                       "re-catalog).",
        "input_schema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string"},
                "ignore_case": {"type": "boolean"},
            },
            "required": ["pattern"],
        },
    },
    {
        "name": "read_doc",
        "description": "Read a project doc by name (e.g. 'MVC2-MEMORY-MAP.md'), optionally a line "
                       "range.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "start_line": {"type": "integer"},
                "end_line": {"type": "integer"},
            },
            "required": ["path"],
        },
    },
]

DISPATCH = {
    "rekb_query": lambda i: tool_rekb_query(i["query"]),
    "grep_disasm": lambda i: tool_grep_disasm(i["pattern"], i.get("ignore_case", False)),
    "read_disasm": lambda i: tool_read_disasm(i["file"], i["start_line"], i["end_line"]),
    "grep_docs": lambda i: tool_grep_docs(i["pattern"], i.get("ignore_case", False)),
    "read_doc": lambda i: tool_read_doc(i["path"], i.get("start_line"), i.get("end_line")),
}


# ------------------------------------------------------------------------------- agent
def ask(client, system_blocks, question, verbose=True):
    messages = [{"role": "user", "content": question}]
    while True:
        resp = client.messages.create(
            model=MODEL,
            max_tokens=16000,
            system=system_blocks,
            thinking={"type": "adaptive"},
            output_config={"effort": "high"},
            tools=TOOLS,
            messages=messages,
        )
        if verbose:
            u = resp.usage
            cached = getattr(u, "cache_read_input_tokens", 0)
            print(f"\033[90m[in {u.input_tokens} +cache_read {cached} / out {u.output_tokens}]\033[0m",
                  file=sys.stderr)
        for block in resp.content:
            if block.type == "text":
                print(block.text)
        if resp.stop_reason != "tool_use":
            return resp
        messages.append({"role": "assistant", "content": resp.content})
        results = []
        for block in resp.content:
            if block.type == "tool_use":
                if verbose:
                    print(f"\033[36m→ {block.name}({json.dumps(block.input)[:160]})\033[0m",
                          file=sys.stderr)
                try:
                    out = DISPATCH[block.name](block.input)
                except Exception as e:  # never kill the loop on a tool bug
                    out = f"tool error: {e}"
                results.append({"type": "tool_result", "tool_use_id": block.id,
                                "content": str(out)[:60000]})
        messages.append({"role": "user", "content": results})


def main():
    # Windows consoles default to cp1252; model output (em-dashes, arrows) would crash print().
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except Exception:
            pass
    if not os.environ.get("ANTHROPIC_API_KEY"):
        sys.exit("Set ANTHROPIC_API_KEY first.")
    client = anthropic.Anthropic()
    system_blocks = build_system_blocks()
    kb_kb = len(system_blocks[1]["text"]) // 1024
    print(f"\033[90mMvC2 Oracle · {MODEL} · re_kb+docs context: ~{kb_kb} KB (cached)\033[0m",
          file=sys.stderr)

    if len(sys.argv) > 1:
        ask(client, system_blocks, " ".join(sys.argv[1:]))
        return
    print("MvC2 Oracle — ask a question (Ctrl-D / 'exit' to quit).", file=sys.stderr)
    while True:
        try:
            q = input("\n\033[1moracle>\033[0m ").strip()
        except EOFError:
            break
        if q.lower() in ("exit", "quit"):
            break
        if q:
            ask(client, system_blocks, q)


if __name__ == "__main__":
    main()
