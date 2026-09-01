# -*- coding: utf-8 -*-
"""fix_quotes.py -- escape the apostrophes that keep seed statements from parsing.

SurrealDB 3.1.4 takes ONLY backslash escaping inside a '...' string. The seeds
carry two older habits:

    'the engine''s own order'     doubled  -- rejected outright
    'the engine's own order'      raw      -- rejected outright

Both end the string early. Because a .surql file is POSTed as one script, the
parser then eats the following statements as string content, returns 200, and
every block says OK. 58 findings across 12 files had never reached the live
graph while every apply looked clean.

This is deliberately SURGICAL. It splits a file into statements, POSTs each
one, and only rewrites the ones the server actually rejects -- then re-POSTs
to confirm the rewrite parses. A statement that already works is never
touched, so a bad heuristic cannot silently damage a good statement.

    PYTHONIOENCODING=utf-8 python tools/re_kb/fix_quotes.py --dry-run
    PYTHONIOENCODING=utf-8 python tools/re_kb/fix_quotes.py
"""
import glob
import io
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apply_seed import split_statements, post, is_script_scoped   # noqa: E402

BACKSLASH = chr(92)          # spelled this way so no shell/tool layer can eat it

# A literal OPENS right after one of these and CLOSES right before one of them.
# `&`, `+` and `|` are in both because several seeds build a long value by
# concatenating segments across lines:
#
#     statement='part one '
#          & 'part two, with the engine's own wording '
#          & 'part three';
#
# Without the concatenation operators, the quote after `&` reads as interior
# text and gets escaped -- which breaks a statement that was fine.
OPENERS = "=:,([{&+|"
CLOSERS = ",;)]}&+|"
ASSIGN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*[ ]*=[ ]*'")
# Deliberately anchored to an assignment VALUE (`ident = 0x...` followed by a
# comma, a semicolon or end-of-line). A looser pattern also matches the many
# addresses written inside prose -- "ASMTRACE PC 0x8C034864, ground truth" --
# and quoting one of those corrupts the sentence and breaks the string.
HEXLIT = re.compile(
    r"([A-Za-z_][A-Za-z0-9_]*[ ]*=[ ]*)(0[xX][0-9a-fA-F]+)(?=[ ]*(?:[,;]|$))",
    re.M)


def escape_interior(stmt):
    """Backslash-escape every apostrophe that is neither opening nor closing
    a string literal.

    In these files a literal always OPENS right after one of `=:,([{` and
    always CLOSES right before one of `,;)]}` or end-of-line. Anything else --
    engine's, isn't, 'wrong sprite' quoted mid-sentence -- is interior text.
    Lines that are pure comments are skipped.
    """
    out_lines = []
    for line in stmt.split("\n"):
        if line.lstrip().startswith("--"):
            out_lines.append(line)
            continue
        buf = []
        i = 0
        while i < len(line):
            c = line[i]
            if c != "'":
                buf.append(c)
                i += 1
                continue
            if i > 0 and line[i - 1] == "\\":       # already escaped
                buf.append(c)
                i += 1
                continue
            j = i - 1
            while j >= 0 and line[j] == " ":
                j -= 1
            prev = line[j] if j >= 0 else ""
            k = i + 1
            while k < len(line) and line[k] == " ":
                k += 1
            nxt = line[k] if k < len(line) else ""
            is_open = prev in OPENERS
            is_close = (nxt in CLOSERS) or (k >= len(line))
            buf.append(c if (is_open or is_close) else BACKSLASH + c)
            i += 1
        out_lines.append("".join(buf))
    return "\n".join(out_lines)


def fix_concat(stmt):
    """`&` is not SurrealQL string concatenation -- `+` is.

    Several seeds build a long value as segments joined by a leading `&` on
    each continuation line. SurrealDB answers "single `&` are not a valid
    token, did you mean `&&`?", so those statements have never applied.
    """
    out = []
    for line in stmt.split("\n"):
        stripped = line.lstrip()
        if stripped.startswith("& ") and len(stripped) > 2 and stripped[2] in "'\"":
            indent = line[:len(line) - len(stripped)]
            out.append(indent + "+ " + stripped[2:])
        else:
            out.append(line)
    return "\n".join(out)


def fix_hex(stmt):
    """Quote bare 0x literals.

    SurrealDB reads `0x8c1244b0` as the number 0 followed by an identifier
    ("unexpected character `x` after number token"). Every other seed already
    writes an address as a string -- pc='0x8C044F12' -- so this makes the
    outliers match, and keeps addresses greppable as text.
    """
    return HEXLIT.sub(lambda m: m.group(1) + "'" + m.group(2) + "'", stmt)


def fix_create(stmt):
    """CREATE -> UPSERT, so re-applying a seed is idempotent.

    README.md says the seeds are re-appliable. A CREATE fails the second time
    with "record already exists", which makes a full reapply report errors
    that are not errors -- and trains the reader to ignore them.
    """
    if stmt.lstrip().startswith("CREATE "):
        return stmt.replace("CREATE ", "UPSERT ", 1)
    return stmt


def main(argv):
    dry = "--dry-run" in argv
    files = [a for a in argv if not a.startswith("--")] or sorted(
        glob.glob(os.path.join("tools", "re_kb", "*.surql")))
    fixed = failed = 0
    for path in files:
        text = io.open(path, encoding="utf-8").read()
        changed = False
        if is_script_scoped(text):
            # Never split these -- see apply_seed.is_script_scoped. Probing a
            # statement here means EXECUTING it, and a lone `DELETE reads;`
            # wipes the table.
            continue
        for stmt in split_statements(text):
            if not post(stmt):
                continue                                  # already parses
            # Structural repairs first -- they are unambiguous, so they are
            # applied unconditionally. Then the two escaping strategies, which
            # ARE guesses, so the first one the server accepts wins. Nothing
            # is written unless the final text actually parses.
            base = stmt
            for repair in (fix_concat, fix_hex, fix_create):
                base = repair(base)

            new, errs = None, None
            if base != stmt and not post(base):
                new = base
            else:
                for strategy in (escape_interior, escape_assignment_scoped):
                    cand = strategy(base)
                    if cand == stmt:
                        continue
                    errs = post(cand)
                    if not errs:
                        new = cand
                        break
            if new is None:
                print("  STILL BAD: %s\n    %s\n      -> %s"
                      % (os.path.basename(path), stmt.split("\n")[0][:90],
                         (errs or ["not a quote problem"])[0]))
                failed += 1
                continue
            if not dry:
                assert stmt in text, "statement not found verbatim"
                text = text.replace(stmt, new, 1)
                changed = True
            fixed += 1
            print("  fixed: %-40s %s" % (os.path.basename(path),
                                         stmt.split("\n")[0][:70]))
        if changed and not dry:
            io.open(path, "w", encoding="utf-8", newline="\n").write(text)
    print("-" * 70)
    print("%d statements repaired, %d still failing%s"
          % (fixed, failed, " (DRY RUN -- nothing written)" if dry else ""))
    return 1 if failed else 0




# ---------------------------------------------------------------------------
# strategy B -- anchor on the assignment, not on local context
# ---------------------------------------------------------------------------
def escape_assignment_scoped(stmt):
    """Escape every apostrophe INSIDE a `field='...'` value.

    Strategy A reads each quote's neighbours to guess whether it opens or
    closes a literal. That fails on a phrase the author quoted inside the
    prose -- DepthMode 0 ('Never') looks exactly like a real delimiter pair,
    because locally it IS one.

    So instead: find where a value actually starts (an identifier, '=', a
    quote) and where it actually ends (a quote followed by ',' or ';' or the
    end of the line -- which is the only shape a seed file terminates a value
    with). Everything between them is text, whatever it looks like.
    """
    out_lines = []
    for line in stmt.split("\n"):
        if line.lstrip().startswith("--"):
            out_lines.append(line)
            continue
        buf = []
        i = 0
        n = len(line)
        while i < n:
            m = ASSIGN.match(line, i)
            if not m:
                buf.append(line[i])
                i += 1
                continue
            buf.append(m.group(0))            # ident = '
            i = m.end()
            # walk to the real terminator
            j = i
            end = None
            while j < n:
                if line[j] == "'":
                    k = j + 1
                    while k < n and line[k] == " ":
                        k += 1
                    if k >= n or line[k] in ",;":
                        end = j
                        break
                j += 1
            if end is None:                   # value continues past this line
                buf.append(line[i:].replace("'", BACKSLASH + "'"))
                i = n
            else:
                buf.append(line[i:end].replace("'", BACKSLASH + "'"))
                buf.append("'")
                i = end + 1
        out_lines.append("".join(buf))
    return "\n".join(out_lines)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
