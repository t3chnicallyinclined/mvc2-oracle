-- ============================================================================
-- 80: split the doc ingest out of `finding`
--
-- THE PROBLEM (measured 2026-09-01 on the live graph)
-- ---------------------------------------------------
--   INGESTED (finding:doc_*)   576 rows   478 confirmed   93 inferred    5 open
--   HAND-CURATED RE             62 rows    51 confirmed    0 inferred
--
-- 90% of the `finding` table was markdown bullets scraped out of the repo's
-- own docs by ingest/docs_parse.py. Every aggregate over `finding` was
-- therefore an aggregate over the docs. The graph advertised a healthy
-- 529:93 confirmed-to-inferred ratio; the real curated ratio was 51:0, which
-- is the signature of a promotion rule that is not being enforced.
--
-- Worse, the `status` on those rows was assigned from the DOC'S OWN prose:
-- docs_parse.py maps a checkmark to status='confirmed'. So 478 changelog
-- ticks were indistinguishable, by query, from reverse-engineering results
-- backed by a disassembly PC.
--
-- WHAT THIS DOES
-- --------------
-- Moves them to `docnote`, where they are still queryable and still cite
-- their source, but can never again be mistaken for RE knowledge. They keep
-- their doc cue as `doc_cue`; they get no `status`, because a bullet in a
-- markdown file does not have one.
--
-- SAFE TO DELETE AND RE-CREATE. Verified before writing this file:
--   * all 576 rows carry exactly the 6 fields ingest.py writes -- no hand edits
--   * ingest/generated/docs_findings.surql reproduces all 576 + all 764 edges
--   * of the 15 finding->cites->finding edges in the graph, ZERO point at a
--     doc_* row, so no curated claim depends on one
--   * the 238 curated findings that cite a source:doc_* keep that evidence --
--     `source:doc_*` rows are NOT touched, only `finding:doc_*`
--
-- The generator is fixed at the root (ingest/ingest.py gen_docs), so a
-- re-ingest writes docnote and this does not regrow.
--
-- Apply:  tools/re_kb/rekb.sh @tools/re_kb/80_doc_split.surql
--    then tools/re_kb/rekb.sh @tools/re_kb/ingest/generated/docs_findings.surql
-- ============================================================================
USE NS re DB kb;

DEFINE TABLE IF NOT EXISTS docnote SCHEMALESS
  COMMENT 'A bullet lifted from a repo markdown doc by ingest/docs_parse.py. An ASSERTION SOMEONE WROTE DOWN, not an RE result. Fields: statement, doc_cue, confidence, source_file, section. Deliberately has NO status -- it is not a finding and must never be counted as one.';

-- drop the edges first: deleting a record does not remove edges pointing at it,
-- and a dangling cites edge is exactly the integrity hole 79 had to repair.
DELETE cites WHERE record::tb(in)='finding' AND string::starts_with(record::id(in), 'doc_');
DELETE about WHERE record::tb(in)='finding' AND string::starts_with(record::id(in), 'doc_');

DELETE finding WHERE string::starts_with(record::id(id), 'doc_');
