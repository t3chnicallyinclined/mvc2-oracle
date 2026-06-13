#!/usr/bin/env python3
"""
docs_parse.py — parse the repo's RE docs + the operator's auto-memory into
structured JSON: memory locations (hex addresses / +offsets), their meanings
(the surrounding prose), and discrete documented FINDINGS.

This is the operator's "context files with memory locations" source. Where
marvelous2 gives clean #symbol offsets and anotak gives layout, the *docs*
give the human RE narrative: the memory map, the handoffs, the plans, and the
auto-memory's confirmed/inferred/open facts — each pinned to an address.

Sources (relative to the repo root, configurable via --repo / --memory):
  CLAUDE.md            -> the MVC2 memory map, char-struct offsets, skin/palette,
                          wire format. Tables of `+0xNNN field` and `0x8C...` vars.
  docs/*.md            -> RE handoffs, GFX notes, the render/recon plans.
  re-catalog/*.md      -> object-pool map (00-README), spreadsheet-data, PL2A-storm.
  <auto-memory>/*.md   -> MEMORY.md + project_*/reference_* findings (OUTSIDE the
                          repo, read-only). Default:
                          %USERPROFILE%/.claude/projects/.../memory

Extraction (pure regex + prose capture — NEVER invents an address):
  * ADDR_RE   : absolute RAM addrs  0x8C......, 0x0C......, 0x2C...... (PS2 mirror)
  * OFF_RE    : struct-relative offsets  +0xNNN  (1..4 hex digits)
  For each hit we capture the line it sits on (and a markdown table-cell name if
  the line is a `| +0xNN | name | ... |` row) as its `meaning`/note, plus the
  file:section (nearest `#`/`##` heading) as provenance.

  * findings  : sentences/bullets carrying a documented fact. The doc's own
                confidence language sets the status:
                  confirmed   <- "confirmed", "✅", "RESOLVED", "disasm-verified",
                                 "validated", "proven", "CONFIRMED-FROM-DISASM"
                  open        <- "open", "TBD", "❓", "unresolved", "unknown",
                                 "not yet", "unsolved"
                  inferred    <- everything else that reads like a claim
                                 ("🟡", "hypothesis", "likely", "infer")

Output: data/docs_findings.json
  { sources:[{slug,ref,note}],
    addresses:[{addr|offset, name, meaning, file, section, kind}],
    findings:[{slug, statement, status, file, section}] }

Usage:
  python docs_parse.py                    # parse repo docs + auto-memory
  python docs_parse.py --repo PATH        # different repo root
  python docs_parse.py --memory PATH      # different auto-memory dir
  python docs_parse.py --no-memory        # skip the (out-of-repo) auto-memory
"""
import os
import re
import sys
import glob
import argparse

import common

REPO = os.path.abspath(os.path.join(common.HERE, "..", "..", ".."))


def _default_memory():
    """The operator's auto-memory dir (OUTSIDE the repo — parse-only)."""
    env = os.environ.get("REKB_MEMORY_DIR")
    if env:
        return env
    home = os.path.expanduser("~")
    return os.path.join(
        home, ".claude", "projects",
        "c--Users-trist-projects-maplecast-flycast", "memory")


# absolute DC/PS2 RAM address: 0x8C......, 0x0C......, 0x2C...... (>=5 hex digits)
ADDR_RE = re.compile(r"\b(0[xX][0-9A-Fa-f]{2}[0-9A-Fa-f]{4,})\b")
# struct-relative offset: +0xNN .. +0xNNNN (1..4 hex, distinguishes from abs)
OFF_RE = re.compile(r"(?<![0-9A-Fa-f])\+0[xX]([0-9A-Fa-f]{1,4})\b")
# a markdown table cell row like: | +0x144 | sprite_id (u16) | note ... |
TABLE_ROW_RE = re.compile(r"^\s*\|(.+)\|\s*$")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")

# confidence-language buckets (lower-cased line is scanned)
CONFIRMED_CUES = ("confirmed", "✅", "resolved", "disasm-verified",
                  "validated", "proven", "confirmed-from-disasm",
                  "passed", "ground truth", "verified")
OPEN_CUES = ("open", "tbd", "❓", "unresolved", "unknown", "not yet",
             "unsolved", "still missing", "todo", "?? ")
INFERRED_CUES = ("🟡", "hypothesis", "likely", "infer", "candidate",
                 "probably", "suspect", "may ", "appears")

# a line is "finding-like" if it carries one of these fact verbs/markers
FINDING_MARKERS = ("✅", "🟡", "❓", "confirmed", "resolved", "validated",
                   "proven", "passed", "verdict", "discovery", "finding",
                   "decision:", "theory", "open verification", "supersed",
                   "deadend", "dead-end", "breakthrough")


def _slug(s):
    return re.sub(r"[^a-z0-9]+", "_", str(s).lower()).strip("_")[:80]


def _read(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def _status_for(line):
    low = line.lower()
    # confirmed wins, then open, then inferred (most-specific signal first)
    if any(c in low for c in CONFIRMED_CUES):
        return "confirmed"
    if any(c in low for c in OPEN_CUES):
        return "open"
    if any(c in low for c in INFERRED_CUES):
        return "inferred"
    return None


def _table_name(line):
    """If `line` is a markdown table row, return its 2nd cell (the name col)."""
    m = TABLE_ROW_RE.match(line)
    if not m:
        return None
    cells = [c.strip() for c in m.group(1).split("|")]
    if len(cells) < 2:
        return None
    # cell[0] is usually the addr/offset; cell[1] the field name
    name = cells[1]
    # strip markdown bold/backticks
    name = re.sub(r"[`*]", "", name).strip()
    # drop separator rows like |---|---|
    if set(name) <= set("-: "):
        return None
    return name or None


def _clean(text, limit=240):
    t = re.sub(r"\s+", " ", text).strip().strip("|").strip()
    t = re.sub(r"[`*]+", "", t)
    return t[:limit]


def parse_file(path, rel, kind):
    """
    Extract {addresses, offsets, findings, section_map} from one markdown file.
    Returns dict with lists. addr/offset records carry file/section/meaning.
    """
    text = _read(path)
    lines = text.splitlines()
    section = ""
    addresses, offsets, findings = [], [], []
    seen_find = set()

    for ln in lines:
        hm = HEADING_RE.match(ln)
        if hm:
            section = _clean(hm.group(2), 80)
            continue

        tname = _table_name(ln)
        meaning = _clean(ln)

        # --- absolute addresses ---
        for am in ADDR_RE.finditer(ln):
            addr = am.group(1)
            # normalise 0X -> 0x
            addr = "0x" + addr[2:]
            addresses.append({
                "addr": addr, "name": tname, "meaning": meaning,
                "file": rel, "section": section, "kind": kind,
            })

        # --- struct-relative offsets ---
        for om in OFF_RE.finditer(ln):
            off = "0x" + om.group(1).upper()
            offsets.append({
                "offset": off, "name": tname, "meaning": meaning,
                "file": rel, "section": section, "kind": kind,
            })

        # --- findings (fact-bearing lines) ---
        low = ln.lower()
        if any(mk in low for mk in FINDING_MARKERS):
            stmt = _clean(ln, 400)
            # require some substance + at least one letter
            if len(stmt) < 20 or not re.search(r"[A-Za-z]", stmt):
                continue
            status = _status_for(ln) or "inferred"
            key = stmt[:120].lower()
            if key in seen_find:
                continue
            seen_find.add(key)
            findings.append({
                "slug": f"{_slug(rel)}__{_slug(stmt[:48])}",
                "statement": stmt, "status": status,
                "file": rel, "section": section,
            })

    return {"addresses": addresses, "offsets": offsets, "findings": findings}


def _iter_sources(repo, memory_dir):
    """Yield (abs_path, rel_label, kind) for every doc source."""
    # CLAUDE.md (the memory map / offsets / skin / wire)
    cm = os.path.join(repo, "CLAUDE.md")
    if os.path.exists(cm):
        yield cm, "CLAUDE.md", "doc"
    # docs/*.md
    for p in sorted(glob.glob(os.path.join(repo, "docs", "*.md"))):
        yield p, "docs/" + os.path.basename(p), "doc"
    # re-catalog/*.md
    for p in sorted(glob.glob(os.path.join(repo, "re-catalog", "*.md"))):
        yield p, "re-catalog/" + os.path.basename(p), "recatalog"
    # auto-memory (OUTSIDE the repo, read-only)
    if memory_dir and os.path.isdir(memory_dir):
        for p in sorted(glob.glob(os.path.join(memory_dir, "*.md"))):
            yield p, "memory/" + os.path.basename(p), "memory"


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=REPO, help="repo root")
    ap.add_argument("--memory", default=_default_memory(),
                    help="auto-memory dir (outside repo, read-only)")
    ap.add_argument("--no-memory", action="store_true",
                    help="skip the out-of-repo auto-memory")
    args = ap.parse_args(argv)

    memory_dir = None if args.no_memory else args.memory

    sources, addresses, offsets, findings = [], [], [], []
    nfiles = 0
    for path, rel, kind in _iter_sources(args.repo, memory_dir):
        nfiles += 1
        sources.append({
            "slug": _slug(rel),
            "ref": rel,
            "kind": kind,
            "note": f"RE doc source {rel} ({kind}).",
        })
        out = parse_file(path, rel, kind)
        addresses += out["addresses"]
        offsets += out["offsets"]
        findings += out["findings"]

    # de-dup addresses/offsets by (key, file) keeping the richest meaning (with a name)
    def _dedup(records, keyfield):
        best = {}
        for r in records:
            k = (r[keyfield], r["file"], r["section"])
            cur = best.get(k)
            # prefer a record that has a table name + longer meaning
            score = (1 if r.get("name") else 0, len(r.get("meaning", "")))
            if cur is None or score > cur[0]:
                best[k] = (score, r)
        return [v[1] for v in best.values()]

    addresses = _dedup(addresses, "addr")
    offsets = _dedup(offsets, "offset")

    data = {
        "source": "docs",
        "repo": args.repo,
        "memory_dir": memory_dir,
        "file_count": nfiles,
        "sources": sources,
        "addresses": addresses,
        "offsets": offsets,
        "findings": findings,
    }
    p = common.write_json("docs_findings.json", data)
    print(f"docs_parse -> {p}")
    print(f"  files={nfiles} sources={len(sources)} "
          f"addresses={len(addresses)} offsets={len(offsets)} "
          f"findings={len(findings)}")


if __name__ == "__main__":
    main(sys.argv[1:])
