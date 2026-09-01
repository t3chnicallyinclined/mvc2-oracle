-- ============================================================================
-- 79: source integrity -- define the sources that only ever existed as the
--     far end of a RELATE.
--
-- WHY THIS FILE EXISTS
-- --------------------
-- `RELATE finding:x->cites->source:y` does not require source:y to exist.
-- SurrealDB creates an empty row -- or, if the target is never touched again,
-- leaves the edge dangling. Either way the citation LOOKS satisfied: the
-- finding has a cites edge, traversal returns a row, and every "does this
-- confirmed claim cite anything?" query says yes.
--
-- Measured 2026-09-01 on the live graph: 6 source rows carried no kind, no
-- title and no url, and `source:marvelous2` did not exist at all while an
-- edge pointed at it. Seven confirmed findings rested on them. Under
-- 77_epistemics.surql an empty source ranks `unranked`, which cannot confirm
-- anything -- so without this file, applying 77 would demote seven sound
-- findings for a bookkeeping reason.
--
-- The kind/ref below are NOT invented. Each was read back out of the citing
-- finding's own statement, which names the artifact, the commit and the
-- validation. The provenance of that reconstruction is recorded on each row
-- in `reconstructed_from`, so a later reader can check the inference rather
-- than inherit it.
--
-- `strength` is set EXPLICITLY here rather than left to 77's kind->strength
-- UPDATE, so this file is order-independent: it is correct whether it runs
-- before or after 77.
--
-- Idempotent. Apply: tools/re_kb/rekb.sh @tools/re_kb/79_source_integrity.surql
-- ============================================================================
USE NS re DB kb;

-- ---- the render-replica transpile chain (2026-06-12) ------------------------
-- All five back findings that name commit 050c4a01b and tools/render-replica-poc/.
-- A lift-to-C transpile validated to 0.00px geometry / byte-exact TCW+TSP is a
-- deterministic differ pass -- reproduction-grade by the ladder in 77.
UPSERT source:render_replica_poc_20260612 SET
  kind='transpile_validation', strength='reproduction',
  title='render-replica PoC -- lift-to-C transpiler (lift.py + codegen.py + emit_func.py)',
  ref='tools/render-replica-poc/ @050c4a01b',
  date='2026-06-12',
  reconstructed_from='finding:render_replica_option_c_validated, finding:body_walker_tiling (2026-09-01)';

UPSERT source:render_replica_phase1_20260612 SET
  kind='transpile_validation', strength='reproduction',
  title='render-replica Phase 1 -- per-object body render fully code-derived',
  ref='tools/render-replica-poc/ @ branch feat/render-replica-experiment',
  date='2026-06-12',
  reconstructed_from='finding:render_replica_phase1_codederived (2026-09-01)';

UPSERT source:render_replica_phase2_20260612 SET
  kind='transpile_validation', strength='reproduction',
  title='render-replica Phase 2 -- render root loc_8c0308c2 (Render_sprites) transpiled',
  ref='tools/render-replica-poc/gen_walker_root.c -> render_sprites_0308c2',
  date='2026-06-12',
  reconstructed_from='finding:render_replica_phase2_slotwalk (2026-09-01)';

UPSERT source:render_replica_readset_20260612 SET
  kind='transpile_validation', strength='reproduction',
  title='render-replica Phase 4a -- exact per-render_frame guest-RAM read-set, derived not guessed',
  ref='tools/render-replica-poc/ (STATIC/DYNAMIC partition)',
  date='2026-06-12',
  reconstructed_from='finding:render_replica_readset (2026-09-01)';

UPSERT source:render_replica_byte_exact_20260612 SET
  kind='transpile_validation', strength='reproduction',
  title='BYTE-EXACT pixel reproduction -- body walker loc_8c0344d4 + submit loc_8c1244b0, geometry 0.00px, TCW/TSP bit-exact',
  ref='tools/render-replica-poc/ (capstone run)',
  date='2026-06-12',
  reconstructed_from='finding:render_replica_byte_exact_proven (2026-09-01)';

-- ---- the Oracle sentinel capture (2026-06-11) -------------------------------
-- Backs the sprite_id SAMPLING-PHASE root cause. A live Oracle probe slice is
-- a reproduction: re-run the probe at the same PC and the phase shows again.
UPSERT source:oracle_sentinel_sid_20260611 SET
  kind='oracle_capture', strength='reproduction',
  title='Oracle sentinel sprite_id capture -- Sentinel rocket 213/214 vs diagonal 428-430',
  ref='MAPLECAST_ORACLE_PROBE slice at the body walker loc_8c0344d4 (bank03:10232-10243)',
  date='2026-06-11',
  reconstructed_from='finding:gsta_sprite_id_sampling_phase (2026-09-01)';

-- ---- the dangling one -------------------------------------------------------
-- `source:marvelous2` had NO row at all -- the cites edge pointed into empty
-- space. The disassembly it names is the project's primary code reference and
-- is already represented by source:marv_pl_mem / marv_work / marv_banks; this
-- row exists so the edge resolves and so the generic id is findable.
UPSERT source:marvelous2 SET
  kind='marvelous2', strength='code',
  title='marvelous2 SH4 disassembly (generic reference -- prefer the specific bank/symbol source)',
  ref='../_marv_re/  (loc_8c...... label == PC)',
  note='Created 2026-09-01 to resolve a dangling cites edge from finding:sprite_id_0x144_is_authoritative_cell_selector. Prefer citing routine:loc_8c...... or source:marv_pl_mem/marv_work/marv_banks, which say WHERE.',
  reconstructed_from='dangling cites edge (2026-09-01)';
