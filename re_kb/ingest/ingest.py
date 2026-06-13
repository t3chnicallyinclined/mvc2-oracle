#!/usr/bin/env python3
"""
ingest.py — load the extracted JSON into the live RE-KB (SurrealDB ns=re db=kb).

Maps the extractor output to the existing 13-node / 12-edge schema:

  anotak char            -> character note refinement (UPSERT by char:plXX)
  anotak animation groups -> animgroup:plXX_gNN  (+ owns/part_of -> character)
  anotak char stats       -> field:stat_<char>_<slug> (logical fields) on the char
  anotak field-semantics  -> dataformat:anim_<Field>  (+ a `source` row)
  marvelous2 fields       -> field:<name> (char_struct offsets) + has_field edge
                             + address:<name> + lives_at edge
  marvelous2 globals      -> global:<name> (+ lives_at -> address)
  marvelous2 routines     -> routine:loc_8c......  (pc, bank)
  marvelous2 stages       -> dataformat:stage_ids note (compact)
  docs addresses/offsets  -> address:doc_* / field:doc_* (doc-pinned locations)
  docs canonical offsets  -> MERGE-SAFE cites + doc_refs[] onto field:<canon>
                             (e.g. field:sprite_id keeps its marv note, GAINS a doc cite)
  docs findings           -> finding:doc_* (status from the doc's confidence cues)
  disc file families      -> dataformat:disc_* + region:disc_devfiles (catalog only)
  disc PLDAT format       -> dataformat:pldat_header / pldat_<section>
                             (GFX1->maps_to->field:gfx00_ptr, about part-decode finding)

Strategy: GENERATE a .surql file per source under generated/, then apply it via
curl @file (HTTP POST). All UPSERT (idempotent) + RELATE (deduped afterwards by
the caller running 07_dedup_edges.surql). Re-runnable.

Usage:
  python ingest.py --anotak PL00          # ingest one crawled char + the field dict
  python ingest.py --marv                 # ingest marvelous2 symbols
  python ingest.py --anotak PL00 --marv   # both
  python ingest.py --docs                 # repo RE docs + auto-memory
  python ingest.py --disc                 # MVC2 Dev Files catalog + PLDAT format
  python ingest.py --dedup                # run 07_dedup_edges after
"""
import os
import re
import sys
import argparse

import common
import label

S = common.sql_str  # SurrealQL string escaper


def _slug(s):
    return re.sub(r"[^a-z0-9]+", "_", str(s).lower()).strip("_")


# ---------------------------------------------------------------------------
# anotak -> KB
# ---------------------------------------------------------------------------
def gen_anotak(pl):
    pl = pl.upper()
    rec = common.read_json(f"anotak_{pl}.json")
    cid = pl[2:].lower()                 # PL00 -> '00'
    char_id = f"character:pl{cid}"
    lines = ["USE NS re DB kb;", ""]
    base = "https://zachd.com/mvc2/data/anotak/"

    # refine the character note with anotak's name + counts
    nstats = len(rec.get("stats", []))
    ngroups = len(rec.get("anim_groups", []))
    cname = rec.get("name")
    cnote = (f"{cname} (char_id 0x{cid.upper()}). anotak: {ngroups} animation "
             f"groups, {nstats} char-stat fields. src {base}{pl}_DAT_atk.html")
    lines.append(
        f"UPSERT {char_id} SET name={S(cname)}, note={S(cnote)};")
    lines.append("")

    # animation groups -> animgroup + owns + part_of(region n/a) -> character
    for g in rec.get("anim_groups", []):
        gnum = g["group_num"]
        gid = f"animgroup:pl{cid}_g{gnum:02x}"
        name = g.get("name") or f"group {gnum}"
        cnt = g.get("entry_count")
        ncells = len(g.get("cells", []))
        # collect non-empty sprite ids for the note
        sprites = sorted({c["sprite_id"] for c in g.get("cells", [])
                          if c.get("sprite_id")})
        sprite_s = (", sprites " + ",".join(sprites[:8])) if sprites else ""
        note = (f"{rec.get('name')} anim group #{gnum} \"{name}\""
                f"{f' ({cnt} entries)' if cnt else ''}; {ncells} cells{sprite_s}. "
                f"src {base}{pl}_DAT_animgroup{gnum}.html")
        lines.append(
            f"UPSERT {gid} SET char='pl{cid}', group_id='0x{gnum:02X}', "
            f"name={S(name)}, entry_count={cnt if cnt is not None else 'NONE'}, "
            f"cell_count={ncells}, note={S(note)};")
        lines.append(f"RELATE {char_id}->owns->{gid};")
    lines.append("")

    # char stats -> logical fields hung off the character (note carries value)
    for st in rec.get("stats", []):
        nm = st.get("Name", "")
        if not nm:
            continue
        fid = f"field:stat_pl{cid}_{_slug(nm)}"
        val = st.get("Converted Value", "")
        raw = st.get("Raw Data", "")
        notes = st.get("Notes", "")
        note = (f"{rec.get('name')} stat '{nm}' = {val} (raw {raw})"
                f"{f'; {notes}' if notes else ''}. src {base}{pl}_DAT_atk.html")
        lines.append(
            f"UPSERT {fid} SET name={S(nm)}, owner='pl{cid}_stats', "
            f"class='logical', value={S(val)}, raw={S(raw)}, note={S(note)};")
        lines.append(f"RELATE {char_id}->owns->{fid};")
    lines.append("")
    return "\n".join(lines)


def gen_anotak_fields(do_label):
    """Field-semantics dictionary -> dataformat rows + a source row."""
    fields = common.read_json("anotak_fields.json")
    recs = [{"name": k, **v} for k, v in fields.items()]
    if do_label:
        label.label_records(recs, "anotak_field", "anotak/possible_anim")
    else:
        for r in recs:
            r["note"] = label._curation_note(r, "anotak_field", "anotak/possible_anim")

    base = "https://zachd.com/mvc2/data/anotak/"
    lines = ["USE NS re DB kb;", ""]
    lines.append(
        "UPSERT source:anotak_possible_anim SET kind='anotak', "
        f"ref={S(base + 'possible_anim.html')}, "
        "note='anotak animation field-semantics dictionary (per-field value enums).';")
    lines.append("")
    for r in recs:
        fname = r["name"]
        did = f"dataformat:anim_{_slug(fname)}"
        nval = len(r.get("values", []))
        url = f"{base}possible_anim_{fname}.html"
        lines.append(
            f"UPSERT {did} SET name={S(fname)}, kind='anim_field', "
            f"value_count={nval}, source_url={S(url)}, note={S(r['note'])};")
        lines.append(f"RELATE {did}->cites->source:anotak_possible_anim;")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# marvelous2 -> KB
# ---------------------------------------------------------------------------
def gen_marv(do_label):
    sym = common.read_json("marv_symbols.json")
    lines = ["USE NS re DB kb;", ""]

    # provenance sources
    lines.append(
        "UPSERT source:marv_pl_mem SET kind='marvelous2', "
        "ref='_marv/memory/pl_mem.asm', "
        "note='marvelous2 char_struct field offsets + Char_ID roster (#symbol).';")
    lines.append(
        "UPSERT source:marv_work SET kind='marvelous2', "
        "ref='_marv/memory/work.asm', "
        "note='marvelous2 global game-state RAM vars + stage IDs (#symbol).';")
    if sym.get("routines"):
        lines.append(
            "UPSERT source:marv_banks SET kind='marvelous2', "
            "ref='_marv/build/bank*.asm', "
            "note='marvelous2 disassembly; loc_ labels == routine PCs.';")
    lines.append("")

    # ensure the char_struct node exists (idempotent refine)
    lines.append(
        "UPSERT struct:char_struct SET base='0x8C268340', stride='0x5A4', count=6, "
        "note='per-character RAM struct (6 live slots). marvelous2 pl_mem.asm offsets.';")
    lines.append("")

    # fields (char_struct offsets) -> label notes
    fields = sym.get("fields", [])
    if do_label:
        label.label_records(fields, "marv_field", "marvelous2/pl_mem.asm")
    else:
        for r in fields:
            r["note"] = label._curation_note(r, "marv_field", "marvelous2/pl_mem.asm")

    for f in fields:
        nm = f["name"]
        fid = f"field:{_slug(nm)}"
        off = f["offset"]
        ftype = f.get("type") or "unknown"
        lines.append(
            f"UPSERT {fid} SET name={S(nm)}, offset={S(off)}, owner='char_struct', "
            f"type={S(ftype)}, class='engine', note={S(f['note'])};")
        lines.append(f"RELATE struct:char_struct->has_field->{fid};")
        # an address node for the struct-relative offset + lives_at
        aid = f"address:cs_{_slug(nm)}"
        lines.append(
            f"UPSERT {aid} SET addr={S(off)}, kind='struct_offset', "
            f"note={S(f'char_struct+{off} ({nm}).')};")
        lines.append(f"RELATE {fid}->lives_at->{aid};")
    lines.append("")

    # globals -> global + address + lives_at
    for g in sym.get("globals", []):
        nm = g["name"]
        gid = f"global:{_slug(nm)}"
        addr = g["addr"]
        note = (g.get("note") or "").strip() or f"global RAM var {nm}"
        note = f"{note}. src marvelous2/work.asm"
        lines.append(
            f"UPSERT {gid} SET name={S(nm)}, addr={S(addr)}, type='ram_abs', "
            f"note={S(note)};")
        aid = f"address:{_slug(nm)}"
        lines.append(
            f"UPSERT {aid} SET addr={S(addr)}, kind='ram_abs', "
            f"note={S(f'absolute RAM addr of {nm}.')};")
        lines.append(f"RELATE {gid}->lives_at->{aid};")
        lines.append(f"RELATE {gid}->cites->source:marv_work;")
    lines.append("")

    # stages -> a single compact dataformat note (avoid 17 thin nodes)
    stages = sym.get("stages", [])
    if stages:
        st = "; ".join(f"{s['stage_id']}={s.get('note') or s['name']}" for s in stages)
        st_note = "MVC2 stage IDs: " + st[:1000] + ". src marvelous2/work.asm"
        lines.append(
            "UPSERT dataformat:stage_ids SET name='stage_ids', kind='enum', "
            f"value_count={len(stages)}, note={S(st_note)};")
        lines.append("RELATE dataformat:stage_ids->cites->source:marv_work;")
    lines.append("")

    # routines -> routine nodes (pc, bank). Cap for the proof run; full set is huge.
    routines = sym.get("routines", [])
    if routines:
        cap = int(os.environ.get("MARV_ROUTINE_CAP", "400"))
        subset = routines[:cap]
        for r in subset:
            pc = r["pc"]
            bank = r["bank"]
            rid = f"routine:{pc}"
            rnote = (f"marvelous2 routine {pc} (bank {bank}). "
                     f"src _marv/build/bank{bank}.asm")
            lines.append(
                f"UPSERT {rid} SET pc={S(pc)}, bank={S(bank)}, note={S(rnote)};")
            lines.append(f"RELATE {rid}->cites->source:marv_banks;")
        lines.append(f"-- routines ingested: {len(subset)} of {len(routines)} "
                     f"(cap={cap}; raise via MARV_ROUTINE_CAP)")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# docs (repo RE docs + auto-memory) -> KB
# ---------------------------------------------------------------------------
# Canonical char_struct field offsets we already model from marvelous2/anotak.
# When a doc mentions one of these offsets, we MUST NOT clobber the richer
# existing field note — we only ADD a `cites` edge to the doc source and push
# the doc ref onto a `doc_refs` array (idempotent ARRAY-union UPSERT).
# offset (upper-hex, no leading zeros normalised) -> canonical field slug.
CANON_OFFSETS = {
    "0x0": "active", "0x1": "character_id", "0x25": "pl_palid_match",
    "0x34": "x_pos", "0x38": "y_pos", "0x40": "char_pal_effect",
    "0xE0": "screen_x", "0xE4": "screen_y", "0x110": "facing",
    "0x142": "anim_timer", "0x144": "sprite_id", "0x14A": "anim_flags",
    "0x154": "current_cell_data", "0x158": "anim_id", "0x15C": "gfx00_ptr",
    "0x164": "pal_ptr", "0x168": "anim_pointer", "0x170": "hitbox_ptr",
    "0x178": "extras_ptr", "0x1D0": "animation_state", "0x1D2": "xflip",
    "0x1E9": "sp_move_id", "0x1F9": "stance", "0x201": "flight_flag",
    "0x420": "health", "0x424": "red_health", "0x52D": "palette",
}


def _norm_off(off):
    """Normalise '+0x0E0' / '0xE0' -> '0xE0' (upper, no leading zeros)."""
    h = off.lower().replace("0x", "").lstrip("0") or "0"
    return "0x" + h.upper()


def gen_docs():
    """
    Repo RE docs + auto-memory -> doc sources, doc-pinned address/offset records,
    findings (status from the doc's confidence language), and edges:
      finding -> about -> the canonical field (when an offset is known)
      finding -> cites -> the doc source
      <canonical field> -> cites -> doc source  (+ doc_refs[] union; NO note clobber)
    All UPSERT/RELATE — idempotent (edges deduped by 07_dedup_edges).
    """
    rec = common.read_json("docs_findings.json")
    lines = ["USE NS re DB kb;", ""]

    # ---- doc sources (one per file) ----
    for s in rec.get("sources", []):
        sid = f"source:doc_{s['slug']}"
        lines.append(
            f"UPSERT {sid} SET kind='doc', ref={S(s['ref'])}, "
            f"note={S(s['note'])};")
    lines.append("")

    # ---- known canonical offsets cited by docs (MERGE-SAFE: no note clobber) ----
    # group doc refs per canonical field so we add each cite once
    canon_refs = {}  # field_slug -> set of (source_id, ref)
    for o in rec.get("offsets", []):
        key = _norm_off(o["offset"])
        fld = CANON_OFFSETS.get(key)
        if not fld:
            continue
        ssl = _slug(o["file"])
        canon_refs.setdefault(fld, set()).add((f"source:doc_{ssl}", o["file"]))
    for fld, refs in sorted(canon_refs.items()):
        fid = f"field:{fld}"
        ref_list = sorted({r for _, r in refs})
        arr = "[" + ", ".join(S(r) for r in ref_list) + "]"
        # array-union: append doc refs without duplicating, never touch `note`.
        lines.append(
            f"UPSERT {fid} SET doc_refs=array::distinct("
            f"array::concat(doc_refs ?? [], {arr}));")
        for ssl, _ in sorted(refs):
            lines.append(f"RELATE {fid}->cites->{ssl};")
    lines.append("")

    # ---- doc-pinned offsets NOT in the canonical set -> field:doc_<slug> ----
    # (these are doc-only offsets; safe to own a `doc_` namespace, won't clobber)
    seen_doc_off = set()
    for o in rec.get("offsets", []):
        key = _norm_off(o["offset"])
        if CANON_OFFSETS.get(key):
            continue
        nm = (o.get("name") or "").strip()
        # skip noise: table cells that are clearly not field names
        if not nm or nm.startswith(("✅", "🟡", "❓", "0x")) or "|" in nm:
            nm = ""
        slug = _slug(f"{key}_{o['file']}")
        did = f"field:doc_{slug}"
        if did in seen_doc_off:
            continue
        seen_doc_off.add(did)
        note = f"{o['meaning']} (doc {o['file']}#{o['section']})"
        lines.append(
            f"UPSERT {did} SET offset={S(key)}, owner='doc', class='doc', "
            f"name={S(nm) if nm else 'NONE'}, note={S(note)};")
        lines.append(f"RELATE {did}->cites->source:doc_{_slug(o['file'])};")
    lines.append("")

    # ---- absolute addresses -> address records (doc namespace) ----
    seen_addr = set()
    for a in rec.get("addresses", []):
        addr = a["addr"]
        slug = _slug(f"{addr}_{a['file']}")
        aid = f"address:doc_{slug}"
        if aid in seen_addr:
            continue
        seen_addr.add(aid)
        note = f"{a['meaning']} (doc {a['file']}#{a['section']})"
        lines.append(
            f"UPSERT {aid} SET addr={S(addr)}, kind='doc_ram', note={S(note)};")
        lines.append(f"RELATE {aid}->cites->source:doc_{_slug(a['file'])};")
    lines.append("")

    # ---- findings -> finding records (+ about canonical fields, + cites) ----
    for f in rec.get("findings", []):
        fid = f"finding:doc_{_slug(f['slug'])}"
        lines.append(
            f"UPSERT {fid} SET statement={S(f['statement'])}, "
            f"status={S(f['status'])}, confidence='doc', "
            f"source_file={S(f['file'])}, section={S(f['section'])};")
        lines.append(f"RELATE {fid}->cites->source:doc_{_slug(f['file'])};")
        # link the finding to any canonical field whose offset it names
        for key, fld in CANON_OFFSETS.items():
            if key.lower() in f["statement"].lower():
                lines.append(f"RELATE {fid}->about->field:{fld};")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# disc (MVC2 Dev Files catalog + decoded PLDAT structure) -> KB
# ---------------------------------------------------------------------------
def gen_disc():
    """
    Disc file inventory + PLDAT format -> dataformat/region records + sources.
    PLDAT sections link to the existing GFX1/GFX2 fields (maps_to) + the
    part-decode finding (about). RE METADATA only — no ROM bytes. UPSERT/RELATE.
    """
    rec = common.read_json("disc_catalog.json")
    lines = ["USE NS re DB kb;", ""]

    # ---- sources ----
    for s in rec.get("sources", []):
        sid = f"source:{s['slug']}"
        lines.append(
            f"UPSERT {sid} SET kind={S(s['kind'])}, ref={S(s['ref'])}, "
            f"note={S(s['note'])};")
    lines.append("")

    # ---- a region describing the whole disc layout ----
    nbins = rec.get("bin_count", 0)
    families = rec.get("families", [])
    fam_summary = ", ".join(f"{f['prefix']}x{f['count']}" for f in families[:12])
    region_note = (f"MVC2 disc Dev Files: {nbins} .BIN files in "
                   f"{len(families)} families ({fam_summary}). "
                   f"RE inventory; not ROM bytes.")
    lines.append(
        f"UPSERT region:disc_devfiles SET name='disc_devfiles', "
        f"note={S(region_note)};")
    lines.append("RELATE region:disc_devfiles->cites->source:disc_mvc2_devfiles;")
    lines.append("")

    # ---- one dataformat per disc file family ----
    for f in rec.get("families", []):
        did = f"dataformat:disc_{_slug(f['prefix'])}"
        note = (f"Disc file family '{f['prefix']}*': {f['count']} files, "
                f"{f['total_bytes'] // 1024} KB. {f['purpose']}. "
                f"e.g. {', '.join(f['samples'][:3])}.")
        lines.append(
            f"UPSERT {did} SET name={S(f['prefix'])}, kind='disc_family', "
            f"file_count={f['count']}, total_bytes={f['total_bytes']}, "
            f"note={S(note)};")
        lines.append(f"RELATE {did}->cites->source:disc_mvc2_devfiles;")
        lines.append(f"RELATE {did}->part_of->region:disc_devfiles;")
    lines.append("")

    # ---- PLDAT top-level header (the pointer table) as one dataformat ----
    hdr = "; ".join(f"{h['offset']}={h['name']} {h['note']}"
                    for h in rec.get("pldat_header", []))
    lines.append(
        "UPSERT dataformat:pldat_header SET name='pldat_header', "
        "kind='pldat', "
        f"note={S('PLxx_DAT.BIN top-level pointer table: ' + hdr[:900])};")
    if rec.get("sources"):
        lines.append("RELATE dataformat:pldat_header->cites->source:pldat_decoded;")
    lines.append("")

    # ---- one dataformat per decoded PLDAT section ----
    for sec in rec.get("pldat_sections", []):
        did = f"dataformat:pldat_{_slug(sec['name'])}"
        note = (f"PLDAT {sec['name']} section ({sec['file_suffix']}): "
                f"{sec['layout']} Decoded for {sec['char_count']} chars.")
        lines.append(
            f"UPSERT {did} SET name={S(sec['name'])}, kind='pldat_section', "
            f"char_count={sec['char_count']}, note={S(note)};")
        lines.append(f"RELATE {did}->cites->source:pldat_decoded;")

    # link GFX1/GFX2/PALETTE sections to the existing char-struct pointer fields
    # (marv: Dat_GFX1@+0x15C, Dat_GFX2@+0x160, Dat_Pal@+0x164).
    lines.append("RELATE dataformat:pldat_gfx1->maps_to->field:dat_gfx1;")
    lines.append("RELATE dataformat:pldat_gfx2->maps_to->field:dat_gfx2;")
    lines.append("RELATE dataformat:pldat_palette->maps_to->field:dat_pal;")
    # link the GFX section to the documented part-decode finding (schema_seed id)
    lines.append(
        "RELATE finding:part_decode_mechanism->about->dataformat:pldat_gfx1;")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
def apply(name, sql):
    path = os.path.join(common.GEN_DIR, name)
    with open(path, "w", encoding="utf-8") as f:
        f.write(sql)
    res = common.kb_apply_file(path, label=name)
    ok = sum(1 for r in res if isinstance(r, dict) and r.get("status") == "OK")
    err = sum(1 for r in res if isinstance(r, dict) and r.get("status") == "ERR")
    print(f"[ingest] {name}: {ok} OK / {err} ERR statements")
    return err


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--anotak", nargs="*", help="PLxx ids to ingest")
    ap.add_argument("--marv", action="store_true", help="ingest marvelous2 symbols")
    ap.add_argument("--docs", action="store_true",
                    help="ingest repo RE docs + auto-memory")
    ap.add_argument("--disc", action="store_true",
                    help="ingest MVC2 Dev Files catalog + PLDAT format")
    ap.add_argument("--no-label", action="store_true",
                    help="skip the LLM-label layer (force curation flags)")
    ap.add_argument("--dedup", action="store_true",
                    help="run 07_dedup_edges.surql after ingest")
    args = ap.parse_args(argv)

    do_label = (not args.no_label) and label.have_llm()
    total_err = 0

    if args.anotak is not None:
        total_err += apply("anotak_fields.surql", gen_anotak_fields(do_label))
        for pl in (args.anotak or ["PL00"]):
            total_err += apply(f"anotak_{pl.upper()}.surql", gen_anotak(pl))

    if args.marv:
        total_err += apply("marv_symbols.surql", gen_marv(do_label))

    if args.docs:
        total_err += apply("docs_findings.surql", gen_docs())

    if args.disc:
        total_err += apply("disc_catalog.surql", gen_disc())

    if args.dedup:
        dedup = os.path.join(common.HERE, "..", "07_dedup_edges.surql")
        dedup = os.path.abspath(dedup)
        common.kb_apply_file(dedup, label="07_dedup_edges")
        print("[ingest] edges deduped (07_dedup_edges.surql)")

    print(f"[ingest] done. total ERR statements: {total_err}")


if __name__ == "__main__":
    main(sys.argv[1:])
