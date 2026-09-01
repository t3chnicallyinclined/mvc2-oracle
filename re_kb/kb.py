# -*- coding: utf-8 -*-
"""kb.py -- the enforced write surface for the MapleCast RE knowledge graph.

WHY THIS EXISTS
---------------
rekb.sh hands a caller arbitrary SQL and root credentials. Given that
interface, `UPSERT finding:x SET status='confirmed'` with no citation is a
legal one-liner and nothing in the path can reject it. That is not a
discipline failure -- it is the only outcome the interface allows.

Measured 2026-09-01: of the hand-curated RE findings in the live graph,
51 are `confirmed` and 0 are `inferred`. (The graph's other 576 findings are
bulk doc ingestion from ingest/docs_parse.py; those DO carry 93 `inferred`,
which flatters every aggregate and is why the split matters.) The committed
seeds tell the same story independently: 162 confirmed, 1 inferred.

So the rules stop being prose in a README and become function signatures:

  * confirm() requires a `source`, and rejects one that is not
    reproduction- or code-grade. No source, no call.
  * propose() can only ever write status='inferred'.
  * rule_out() exists at all, so dead ends get a status instead of being
    buried in a note field.
  * record_attempt() requires an outcome, and `masks_only` is one of them.

The promotion rule and the evidence ladder are documented in
77_epistemics.surql. This file is where they are enforced.

USAGE
-----
    import kb
    kb.health()                       # the audit -- needs no arguments
    kb.query("SELECT * FROM finding WHERE status='open'")
    kb.propose('facing_neg_r10', 'neg r10 mirrors the pen origin', about='field:facing')
    kb.confirm('facing_neg_r10', source='marv_bank03')
    kb.record_attempt('reflect_whole_rect', on='facing_neg_r10',
                      outcome='ineffective',
                      note='injected a spurious -w, ~50-70 game-px, sign-flipped with facing')

Server: surreal start --user root --pass root --bind 127.0.0.1:8001 \
          rocksdb:re_kb_data/re_kb
"""
import json
import os
import urllib.error
import urllib.request

URL = os.environ.get("REKB_URL", "http://127.0.0.1:8001/sql")
AUTH = os.environ.get("REKB_AUTH", "root:root")

# --- the evidence ladder, strongest first ----------------------------------
STRENGTH = ["reproduction", "code", "metric", "recurrence", "attestation"]

#: strengths that are sufficient, on their own, to promote inferred -> confirmed
CONFIRMING = {"reproduction", "code"}

FINDING_STATUS = {"open", "inferred", "confirmed", "ruled_out", "superseded", "resolved"}
OUTCOMES = {"effective", "masks_only", "ineffective", "unproven"}


class KBError(RuntimeError):
    """A rule was violated, or the graph is unreachable."""


def _sql(stmt):
    """Execute SurrealQL. Internal -- callers use the typed helpers below."""
    body = ("USE NS re DB kb; " + stmt).encode("utf-8")
    req = urllib.request.Request(URL, data=body, method="POST")
    req.add_header("Accept", "application/json")
    import base64
    req.add_header("Authorization", "Basic " +
                   base64.b64encode(AUTH.encode()).decode())
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.URLError as e:
        raise KBError(
            "cannot reach the graph at %s (%s).\n"
            "start it with:  surreal start --user root --pass root "
            "--bind 127.0.0.1:8001 rocksdb:re_kb_data/re_kb" % (URL, e)) from None


def _q(s):
    """Escape a value for a single-quoted SurrealQL literal."""
    return str(s).replace("\\", "\\\\").replace("'", "\\'")


def _rows(res):
    """Collect result rows, RAISING if any statement failed.

    This used to skip non-OK blocks silently, which made every failure look
    like an empty result. On 2026-09-01 that turned health() into a liar: its
    unbacked-claims query hit `string::slice()` on a NULL statement, the whole
    statement errored, the error was dropped here, and health() reported
    ZERO confirmed findings without qualifying evidence. The true count was 37.

    A metric that fails open is worse than no metric -- it produces a clean
    bill of health on demand. So: errors raise.
    """
    out, errs = [], []
    for block in res if isinstance(res, list) else []:
        if not isinstance(block, dict):
            continue
        if block.get("status") == "OK":
            r = block.get("result")
            if isinstance(r, list):
                out.extend(r)
        else:
            errs.append(str(block.get("result"))[:300])
    if errs:
        raise KBError("the graph rejected a statement:\n  " + "\n  ".join(errs))
    return out


# --------------------------------------------------------------------------
# read
# --------------------------------------------------------------------------

def query(sql):
    """Run a read-only query. Rejects anything that writes.

    Writes go through the typed helpers, so the rules cannot be sidestepped
    by passing raw SQL to a function called `query`.
    """
    banned = ("UPSERT", "UPDATE", "DELETE", "CREATE", "RELATE", "REMOVE",
              "DEFINE", "INSERT")
    head = sql.upper()
    for b in banned:
        if b in head:
            raise KBError("query() is read-only; use the typed helpers for writes "
                          "(found %r)" % b)
    return _rows(_sql(sql))


def get(finding):
    """Fetch one finding WITH its status, evidence strengths and age.

    IKB, section 08: "Status is never optional in a result." A caller must not
    be able to receive a bare statement that looks like settled fact, so this
    never returns the statement on its own.
    """
    fid = finding if ":" in str(finding) else "finding:" + str(finding)
    rows = _rows(_sql(
        "SELECT id, statement, status, confidence, date, "
        "->cites->source.kind AS evidence_kind, "
        "->cites->source.strength AS evidence_strength, "
        "->supersedes->finding.id AS supersedes, "
        "<-supersedes<-finding.id AS superseded_by "
        "FROM %s;" % fid))
    return rows[0] if rows else None


# --------------------------------------------------------------------------
# write -- the rules live in these signatures
# --------------------------------------------------------------------------

def propose(slug, statement, about=None, reasoning=None, date=None):
    """Record a new claim. ALWAYS lands as status='inferred'.

    There is deliberately no `status` parameter. A model may propose; it may
    not promote. Promotion goes through confirm(), which requires evidence.
    """
    fid = "finding:" + slug
    sets = ["statement='%s'" % _q(statement), "status='inferred'"]
    if reasoning:
        sets.append("reasoning='%s'" % _q(reasoning))
    if date:
        sets.append("date='%s'" % _q(date))
    _sql("UPSERT %s SET %s;" % (fid, ", ".join(sets)))
    if about:
        _sql("RELATE %s->about->%s;" % (fid, about))
    return fid


def confirm(finding, source, note=None):
    """Promote a finding to confirmed. REQUIRES qualifying evidence.

    `source` is mandatory -- there is no way to call this without one -- and
    it must be reproduction- or code-grade. An attestation-grade source
    (a doc, an anotak page, a note) is enough for `inferred` and is rejected
    here, per the promotion rule in 77_epistemics.surql.
    """
    fid = finding if ":" in str(finding) else "finding:" + str(finding)
    sid = source if ":" in str(source) else "source:" + str(source)

    rows = _rows(_sql("SELECT id, kind, strength FROM %s;" % sid))
    if not rows:
        raise KBError("no such source %r. Record the source first -- "
                      "provenance is not optional." % sid)
    strength = rows[0].get("strength")
    if strength not in CONFIRMING:
        raise KBError(
            "%s is %s-grade (kind=%s). confirmed requires reproduction or code.\n"
            "This claim can be recorded as inferred; say what would confirm it."
            % (sid, strength or "unranked", rows[0].get("kind")))

    sets = ["status='confirmed'", "confidence='high'"]
    if note:
        sets.append("note='%s'" % _q(note))
    _sql("UPSERT %s SET %s;" % (fid, ", ".join(sets)))
    _sql("RELATE %s->cites->%s;" % (fid, sid))
    return fid


def rule_out(slug, statement, tried, evidence, date=None):
    """Record something investigated and ELIMINATED.

    IKB: "Negative results are the cheapest knowledge to record and the most
    expensive to rediscover." These currently exist in the graph only as
    prose inside note fields, which means they are greppable but not
    queryable -- so the next session re-walks them.
    """
    fid = "finding:" + slug
    sets = ["statement='%s'" % _q(statement),
            "status='ruled_out'",
            "tried='%s'" % _q(tried),
            "evidence='%s'" % _q(evidence)]
    if date:
        sets.append("date='%s'" % _q(date))
    _sql("UPSERT %s SET %s;" % (fid, ", ".join(sets)))
    return fid


def record_attempt(approach, on, outcome, note=None, date=None, how=None):
    """Record that an approach was tried against a problem, WITH its outcome.

    The outcome lives on the edge, not on the approach, because the same
    approach can work against one problem and fail against another -- and
    that difference is the most valuable data in the graph.

    outcome must be one of:
      effective    worked, mechanism understood (or 2+ reproductions)
      masks_only   right output, mechanism NOT understood. A tuned constant,
                   a fudged coordinate, a clamp hiding the real bug. Ship it
                   if you must; it is not a fix.
      ineffective  tried, did not help
      unproven     tried once, seemed to help. Correlation, not causation.
    """
    if outcome not in OUTCOMES:
        raise KBError("outcome must be one of %s (got %r). If it produced the "
                      "right pixels but you cannot explain why, that is "
                      "'masks_only', not 'effective'."
                      % (sorted(OUTCOMES), outcome))
    aid = approach if ":" in str(approach) else "approach:" + str(approach)
    tid = on if ":" in str(on) else "finding:" + str(on)

    sets = ["name='%s'" % _q(str(approach).split(":")[-1])]
    if how:
        sets.append("how='%s'" % _q(how))
    _sql("UPSERT %s SET %s;" % (aid, ", ".join(sets)))

    edge = ["outcome='%s'" % _q(outcome)]
    if note:
        edge.append("note='%s'" % _q(note))
    if date:
        edge.append("date='%s'" % _q(date))
    _sql("RELATE %s->tried_on->%s SET %s;" % (aid, tid, ", ".join(edge)))
    return aid


def supersede(old, new, why):
    """Replace a claim. The old row STAYS, with its reason.

    A superseded claim with a visible date is still a lead. Deleting it
    throws away the record of what was believed and why it was wrong.
    """
    o = old if ":" in str(old) else "finding:" + str(old)
    n = new if ":" in str(new) else "finding:" + str(new)
    _sql("UPSERT %s SET status='superseded', superseded_why='%s';" % (o, _q(why)))
    _sql("RELATE %s->supersedes->%s;" % (n, o))
    return n


# --------------------------------------------------------------------------
# the meta-queries -- questions the graph asks about itself
# --------------------------------------------------------------------------

def health():
    """The IKB health metric, section 10.

    "Suspected-to-confirmed ratio -- health of the store. All-confirmed means
    the promotion rules aren't being enforced."
    """
    dist = query("SELECT status, count() AS n FROM finding "
                 "GROUP BY status ORDER BY n DESC;")
    # A cite may land on a source OR on a routine. A routine id IS its PC in
    # the marvelous2 disassembly, so it is code-grade evidence and satisfies
    # the rule. Counting only `source` under-reports compliance badly.
    # NOTE: no string::slice here. `statement` is NULL on some rows (the claim
    # lives in `note`), and string::slice(NONE) errors out the whole statement.
    # Truncation happens in Python, where a missing field is just a missing
    # field. See _rows() for what that error used to cost.
    unbacked = query(
        "SELECT id, status, date, statement, note FROM finding "
        "WHERE status='confirmed' "
        "AND count(->cites->source[WHERE strength IN ['reproduction','code']]) = 0 "
        "AND count(->cites->routine) = 0;")
    for r in unbacked:
        claim = r.pop("statement", None) or r.pop("note", None) or ""
        r.pop("note", None)
        claim = " ".join(str(claim).split())
        r["claim"] = claim[:110] + ("…" if len(claim) > 110 else "")
    return {"status_distribution": dist,
            "confirmed_without_qualifying_evidence": unbacked}


def dead_ends(about=None):
    """What has already been ruled out, and what has already failed.

    The query that stops a re-walk. Almost no system stores this.
    """
    ruled = query("SELECT id, statement, tried, evidence, date FROM finding "
                  "WHERE status='ruled_out';")
    failed = query(
        "SELECT in.name AS approach, out.statement AS problem, outcome, note, date "
        "FROM tried_on WHERE outcome IN ['ineffective','masks_only'];")
    return {"ruled_out": ruled, "failed_or_masking": failed}


def false_wins():
    """Everything currently resting on a fix nobody can explain.

    The `masks_only` set. This project has repeatedly declared false wins;
    this is the query that lists them.
    """
    return query(
        "SELECT in.name AS approach, out.statement AS problem, note, date "
        "FROM tried_on WHERE outcome='masks_only';")


def contradictions():
    """Two live claims about the same entity with no supersedes between them.

    Nobody linked them, so traversal returns both and both look authoritative.
    A graph does not detect this on its own -- you have to ask.
    """
    return query(
        "SELECT ->about->(?) AS subject, "
        "  array::group(<-about<-finding.id) AS claims "
        "FROM finding WHERE status IN ['confirmed','inferred'] "
        "GROUP BY subject;")


if __name__ == "__main__":
    import pprint
    pprint.pprint(health())
