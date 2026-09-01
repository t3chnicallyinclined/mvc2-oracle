# -*- coding: utf-8 -*-
"""normalize_seeds.py -- the two mechanical fixes every re_kb seed file needs.

Both were found on 2026-09-01 by applying the seeds ONE STATEMENT AT A TIME
(apply_seed.py) instead of POSTing whole files, which is what had been hiding
them.

1. A MISSING `USE NS re DB kb;` LINE.
   7 of 89 seed files carry no USE line. rekb.sh used to pass a file to curl
   verbatim, on the assumption that "the file carries its own USE line", so
   every statement in those 7 came back "Specify a namespace to use" -- while
   the HTTP request returned 200 and rekb.sh exited 0. (rekb.sh now always
   prepends USE, so this is belt and braces; the files should still be
   self-contained.)

2. DOUBLED-QUOTE ESCAPING.
   The seeds escape an apostrophe as '' (SQL style). SurrealDB 3.1.4 rejects
   it: "Unexpected token `a strand`". Only backslash escaping works. Since a
   .surql file is POSTed as one script, the parser then swallows every
   FOLLOWING statement as string content and still answers 200/OK -- so one
   bad apostrophe silently drops the rest of the file.

Run this first, then fix_quotes.py for the remaining per-statement repairs:

    PYTHONIOENCODING=utf-8 python tools/re_kb/normalize_seeds.py
    PYTHONIOENCODING=utf-8 python tools/re_kb/fix_quotes.py
    PYTHONIOENCODING=utf-8 python tools/re_kb/apply_seed.py

Idempotent.
"""
import glob
import io
import os
import sys

ESCQ = chr(92) + chr(39)      # backslash + apostrophe
DOUBLED = chr(39) + chr(39)   # ''
USE_LINE = "USE NS re DB kb;"


def add_use_line(path):
    s = io.open(path, encoding="utf-8").read()
    if "USE NS re DB kb" in s:
        return False
    lines = s.split("\n")
    i = 0
    while i < len(lines) and (lines[i].startswith("--") or not lines[i].strip()):
        i += 1
    lines.insert(i, USE_LINE)
    lines.insert(i + 1, "")
    io.open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    return True


def fix_doubled_quotes(path):
    s = io.open(path, encoding="utf-8").read()
    n = s.count(DOUBLED)
    if not n:
        return 0
    io.open(path, "w", encoding="utf-8", newline="\n").write(s.replace(DOUBLED, ESCQ))
    return n


def main():
    paths = sorted(glob.glob(os.path.join("tools", "re_kb", "*.surql")))
    if not paths:
        print("no seeds found -- run this from the REPO ROOT")
        return 2
    used, quoted = [], 0
    for p in paths:
        if add_use_line(p):
            used.append(os.path.basename(p))
        quoted += fix_doubled_quotes(p)
    print("USE line added to %d file(s): %s" % (len(used), ", ".join(used) or "-"))
    print("doubled-quote escapes converted: %d" % quoted)
    return 0


if __name__ == "__main__":
    sys.exit(main())
