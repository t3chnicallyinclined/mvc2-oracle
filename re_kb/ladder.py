# -*- coding: utf-8 -*-
"""ladder.py -- the evidence ladder, parsed from 77_epistemics.surql.

THERE IS ONE DEFINITION OF THE LADDER AND THIS IS NOT IT.

77_epistemics.surql is. This module reads the `UPDATE source SET strength=...
WHERE kind IN [...]` blocks out of that file and hands back the same mapping,
so that a kind added in one place cannot be missing in another.

It was already drifting. On 2026-09-01 the kind->strength map existed three
times -- in 77 (applied to the database), in audit_seeds.py (used to grade the
seeds offline) and implicitly in kb.py's CONFIRMING set. Twelve source kinds in
live use were absent from at least one of them, which is how a confirmation
could be graded differently depending on which tool you asked. That is the same
shape as every other defect in this directory: the primitive was right and
nothing kept the copies honest.

    from ladder import STRENGTH_OF, CONFIRMING, strength_of_kind
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = os.path.join(HERE, "77_epistemics.surql")

#: strengths sufficient ON THEIR OWN to promote inferred -> confirmed.
#: This is the promotion rule; it lives in 77's prose and is enforced in kb.py.
CONFIRMING = frozenset(["reproduction", "code"])

#: ordinal, strongest first
ORDER = ["reproduction", "code", "metric", "recurrence", "attestation", "unranked"]

_BLOCK = re.compile(
    r"UPDATE\s+source\s+SET\s+strength='(\w+)'\s+WHERE\s+kind\s+IN\s*\[(.*?)\]\s*;",
    re.S | re.I)


def _load():
    try:
        text = open(SPEC, encoding="utf-8").read()
    except OSError:
        return {}
    out = {}
    for strength, body in _BLOCK.findall(text):
        for kind in re.findall(r"'([^']+)'", body):
            out[kind] = strength
    return out


STRENGTH_OF = _load()


def strength_of_kind(kind):
    """Rank a source kind. An unmapped kind is `unranked`, never `attestation`.

    77 makes that choice deliberately: an unknown kind must stay visibly
    unknown rather than blending in with evidence that is weak on purpose.
    """
    if not kind:
        return "unranked"
    return STRENGTH_OF.get(kind, "unranked")


def strength_of_cite(table, ident, source_kinds):
    """Rank one cites edge. A cite may land on a source, a routine or a finding.

    A `routine` id IS its PC in the marvelous2 disassembly
    (routine:loc_8c0344d4), so it is code-grade and satisfies the promotion
    rule. Counting only `source` under-reports compliance badly -- it produced
    a "40% violations" figure when the real number was half that.
    """
    if table == "routine":
        return "code"
    if table == "finding":
        return "derived"        # derived from another claim, not primary
    return strength_of_kind(source_kinds.get(ident))


if __name__ == "__main__":
    print("ladder parsed from %s" % os.path.relpath(SPEC))
    buckets = {}
    for k, v in STRENGTH_OF.items():
        buckets.setdefault(v, []).append(k)
    for s in ORDER:
        if s in buckets:
            print("  %-13s %s" % (s, ", ".join(sorted(buckets[s]))))
    print("\nconfirming strengths: %s" % ", ".join(sorted(CONFIRMING)))
