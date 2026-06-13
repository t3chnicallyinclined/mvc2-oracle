#!/usr/bin/env python3
"""
label.py — the LLM-enrichment layer for the RE-KB ingestion pipeline.

Takes extracted records (anotak field-semantics, marvelous2 fields, etc.) and
produces a concise plain-English KB `note` for each, citing its source. This is
the human-readable "what it is / does" that every KB node carries.

  * If ANTHROPIC_API_KEY is set: uses the anthropic SDK with model
    `claude-haiku-4-5` (cheap, built for bulk) to generate notes. Cheap +
    fast + cacheable; one batched call labels many records.
  * If NOT set: SKIPS gracefully — emits the deterministic record with a
    note flagged '[needs-curation] ...' so the pipeline is never blocked.

The labeler NEVER invents addresses/offsets — those come verbatim from the
extractor. The LLM only writes the prose `note`. Every note ends with a short
source citation (anotak URL stem or marvelous2 symbol file) so a KB reader can
tell CONFIRMED provenance from inference.

Public API:
    label_records(records, kind, source_hint) -> list[dict]   # adds 'note'
    have_llm() -> bool
"""
import os
import sys
import json

MODEL = "claude-haiku-4-5"          # cheap bulk labeler (per task spec)
_MAX_BATCH = 20                     # records per LLM call (keeps prompts tight)


def have_llm():
    """True iff we can run the LLM layer (key present + SDK importable)."""
    if not os.environ.get("ANTHROPIC_API_KEY"):
        return False
    try:
        import anthropic  # noqa: F401
        return True
    except ImportError:
        return False


def _curation_note(rec, kind, source_hint):
    """Deterministic fallback note (no LLM). Flagged for later curation."""
    bits = []
    if kind == "anotak_field":
        bits.append(f"anotak animation field '{rec.get('name')}'")
        vals = rec.get("values", [])
        if vals:
            sample = ", ".join(
                f"{v.get('name')}={v.get('hex')}" for v in vals[:4] if v.get("name"))
            if sample:
                bits.append(f"values: {sample}")
    elif kind == "marv_field":
        bits.append(f"char_struct field '{rec.get('name')}' @ {rec.get('offset')}")
        if rec.get("note"):
            bits.append(rec["note"][:120])
    else:
        bits.append(str(rec.get("name", rec)))
    base = "; ".join(bits)
    return f"[needs-curation] {base}. (src: {source_hint})"


def _llm_label_batch(records, kind, source_hint):
    """Label up to _MAX_BATCH records in one structured-output call."""
    import anthropic

    client = anthropic.Anthropic()
    # Compact the records for the prompt (don't dump the whole cross-reference).
    compact = []
    for i, r in enumerate(records):
        if kind == "anotak_field":
            compact.append({
                "i": i, "name": r.get("name"),
                "values": [{"name": v.get("name"), "hex": v.get("hex")}
                           for v in r.get("values", [])[:8]],
            })
        elif kind == "marv_field":
            compact.append({
                "i": i, "name": r.get("name"), "offset": r.get("offset"),
                "type": r.get("type"), "asm_comment": (r.get("note") or "")[:160],
            })
        else:
            compact.append({"i": i, "name": str(r.get("name", ""))})

    schema = {
        "type": "object",
        "properties": {
            "notes": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "i": {"type": "integer"},
                        "note": {"type": "string"},
                    },
                    "required": ["i", "note"],
                    "additionalProperties": False,
                },
            }
        },
        "required": ["notes"],
        "additionalProperties": False,
    }

    prompt = (
        "You are labeling reverse-engineering records for the MVC2 (Marvel vs "
        "Capcom 2, Dreamcast/Naomi, SH4 CPU) knowledge graph. For EACH record "
        "below, write ONE tight plain-English `note` (<=200 chars) saying what "
        "the field/value IS or DOES. Do NOT invent addresses or offsets — only "
        f"describe meaning. End each note with '(src: {source_hint})'. "
        "Records:\n" + json.dumps(compact, indent=0)
    )

    resp = client.messages.create(
        model=MODEL,
        max_tokens=4096,
        output_config={"format": {"type": "json_schema", "schema": schema}},
        messages=[{"role": "user", "content": prompt}],
    )
    text = next((b.text for b in resp.content if b.type == "text"), "{}")
    data = json.loads(text)
    by_i = {n["i"]: n["note"] for n in data.get("notes", [])}
    return by_i


def label_records(records, kind, source_hint):
    """
    Add a `note` to each record dict. Returns the same list (mutated).
    kind: 'anotak_field' | 'marv_field' | other. source_hint: short provenance.
    """
    if not records:
        return records

    if not have_llm():
        for r in records:
            r["note"] = _curation_note(r, kind, source_hint)
        print(f"[label] LLM skipped (no ANTHROPIC_API_KEY) — "
              f"{len(records)} '{kind}' records flagged [needs-curation]")
        return records

    print(f"[label] LLM labeling {len(records)} '{kind}' records with {MODEL}")
    labeled = 0
    for start in range(0, len(records), _MAX_BATCH):
        chunk = records[start:start + _MAX_BATCH]
        try:
            notes = _llm_label_batch(chunk, kind, source_hint)
        except Exception as e:  # noqa: BLE001 — never block the pipeline
            print(f"[label] LLM error ({e}); falling back to curation flag",
                  file=sys.stderr)
            notes = {}
        for j, r in enumerate(chunk):
            note = notes.get(j)
            r["note"] = note if note else _curation_note(r, kind, source_hint)
            if note:
                labeled += 1
    print(f"[label] {labeled}/{len(records)} got LLM notes")
    return records


if __name__ == "__main__":
    # tiny demo: label ~5 anotak fields from the cached dict
    import common
    try:
        fields = common.read_json("anotak_fields.json")
    except FileNotFoundError:
        print("Run anotak_crawl.py --fields first."); sys.exit(1)
    recs = [{"name": k, **v} for k, v in list(fields.items())[:5]]
    label_records(recs, "anotak_field", "anotak/possible_anim")
    for r in recs:
        print(f"  - {r['name']}: {r['note']}")
