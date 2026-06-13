#!/usr/bin/env python3
"""
marv_parse.py — parse the LOCAL _marv (marvelous2) checkout into structured JSON.

Inputs (relative to the repo root, configurable via --marv):
  memory/pl_mem.asm   -> char_struct field offsets (#symbol NAME 0xNNN, < 0x1000)
                         + the Char_ID_* roster map (#symbol Char_ID_X 0xNN).
  memory/work.asm     -> global RAM vars (#symbol NAME 0x8c......)
                         + stage-id constants + scattered ;0x.... annotations.
  build/bankNN.asm    -> loc_8c...... routine labels (the PC is the label).

The pl_mem.asm file mixes three kinds of #symbol lines:
  * field offsets      : value < 0x1000              -> field records
  * absolute RAM addrs : value starts 0x8c / 0x0c    -> address/buffer records
  * small enum consts  : Char_ID_* / value < 0x80    -> roster / ignored

Inline `; comment` after a symbol (or the preceding ;-block) is captured as
the field's note — this is the gold: anotak gives layout, marv gives meaning.

Output: data/marv_symbols.json
Usage:
  python marv_parse.py                 # parse mem + globals (no routine enum)
  python marv_parse.py --routines      # also enumerate loc_ PCs from build/*.asm
  python marv_parse.py --marv PATH     # point at a different _marv checkout
"""
import os
import re
import sys
import glob
import argparse

import common

REPO = os.path.abspath(os.path.join(common.HERE, "..", "..", ".."))
DEFAULT_MARV = os.path.join(REPO, "_marv")

SYM_RE = re.compile(
    r"^#symbol\s+(\S+)\s+(0x[0-9A-Fa-f]+)\s*(?:;(.*))?$"
)
LOC_RE = re.compile(r"^(loc_8c[0-9A-Fa-f]+):")


def _read_lines(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read().splitlines()


def parse_pl_mem(path):
    """Return {fields:[...], roster:[...], pointers:[...]} from pl_mem.asm."""
    fields, roster, pointers = [], [], []
    lines = _read_lines(path)
    pending = []  # accumulate preceding ;-comment block as context note
    for raw in lines:
        line = raw.rstrip()
        stripped = line.strip()
        if stripped.startswith(";"):
            txt = stripped.lstrip(";").strip()
            if txt:
                pending.append(txt)
            continue
        m = SYM_RE.match(stripped)
        if not m:
            if stripped == "":
                pending = []  # blank line breaks a comment block
            continue
        name, hexval, inline = m.group(1), m.group(2), (m.group(3) or "").strip()
        val = int(hexval, 16)
        note = inline or (" / ".join(pending[-4:]) if pending else "")
        pending = []

        if name.startswith("Char_ID_"):
            roster.append({"name": name[len("Char_ID_"):], "char_id": hexval})
        elif val < 0x1000:
            # struct-relative field offset
            ftype = inline.split()[-1] if inline and inline.split()[-1] in (
                "byte", "word", "float", "int16", "pointer", "int8") else None
            fields.append({
                "name": name, "offset": hexval, "offset_int": val,
                "type": ftype, "note": note,
            })
        elif (hexval.lower().startswith("0x8c")
              or hexval.lower().startswith("0x0c")
              or hexval.lower().startswith("0xc")):
            pointers.append({"name": name, "addr": hexval, "note": note})
        else:
            # small misc constants we don't model
            pass
    return {"fields": fields, "roster": roster, "pointers": pointers}


def parse_work(path):
    """Return {globals:[...], stages:[...]} from work.asm."""
    globals_, stages = [], []
    lines = _read_lines(path)
    pending = []
    for raw in lines:
        stripped = raw.strip()
        if stripped.startswith(";"):
            txt = stripped.lstrip(";").strip()
            if txt:
                pending.append(txt)
            continue
        m = SYM_RE.match(stripped)
        if not m:
            if stripped == "":
                pending = []
            continue
        name, hexval, inline = m.group(1), m.group(2), (m.group(3) or "").strip()
        val = int(hexval, 16)
        note = inline or (" / ".join(pending[-3:]) if pending else "")
        pending = []
        if name.startswith("stg_"):
            stages.append({"name": name, "stage_id": hexval, "note": inline})
        elif hexval.lower().startswith("0x8c"):
            globals_.append({"name": name, "addr": hexval, "note": note})
        # else: scale constants etc. — skip
    return {"globals": globals_, "stages": stages}


def parse_routines(marv):
    """Enumerate loc_8c... labels across build/bankNN.asm -> [{pc, bank}]."""
    routines = []
    for path in sorted(glob.glob(os.path.join(marv, "build", "bank*.asm"))):
        bank = re.search(r"bank(\w+)\.asm", os.path.basename(path)).group(1)
        seen = set()
        for raw in _read_lines(path):
            m = LOC_RE.match(raw)
            if m:
                pc = m.group(1)
                if pc not in seen:
                    seen.add(pc)
                    routines.append({"pc": pc, "bank": bank})
    return routines


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--marv", default=DEFAULT_MARV, help="_marv checkout path")
    ap.add_argument("--routines", action="store_true",
                    help="also enumerate loc_ PCs from build/bank*.asm")
    args = ap.parse_args(argv)

    pl_mem = os.path.join(args.marv, "memory", "pl_mem.asm")
    work = os.path.join(args.marv, "memory", "work.asm")
    if not os.path.exists(pl_mem):
        print(f"ERROR: {pl_mem} not found", file=sys.stderr)
        sys.exit(2)

    out = {"source": "marvelous2", "marv_path": args.marv}
    out.update(parse_pl_mem(pl_mem))
    out.update(parse_work(work))
    if args.routines:
        out["routines"] = parse_routines(args.marv)

    p = common.write_json("marv_symbols.json", out)
    print(f"marv_parse -> {p}")
    print(f"  fields={len(out['fields'])} roster={len(out['roster'])} "
          f"pointers={len(out['pointers'])} globals={len(out['globals'])} "
          f"stages={len(out['stages'])} routines={len(out.get('routines', []))}")


if __name__ == "__main__":
    main(sys.argv[1:])
