-- ============================================================================
-- 81: integrity follow-ups found by the first fully-clean seed apply
--
-- Two `cites` edges pointed at `routine` records that do not exist:
--
--   finding:gsta_super_effect_overtile      -> routine:loc_8c033b0a
--   finding:objpool_list_system_complete    -> routine:loc_8c04515e
--
-- A routine id IS its PC in the marvelous2 disassembly, which makes it
-- code-grade evidence under 77 -- so a MISSING routine row silently turns a
-- properly-cited finding into an unbacked `confirmed`. Same failure mode 79
-- repaired for `source`, and the same cause: RELATE does not require its
-- target to exist.
--
-- These are not invented. Both PCs were checked against the disassembly
-- before this file was written:
--
--   loc_8c033b0a  present in ../_marv_re/build/bank03.asm
--   loc_8c04515e  present in ../_marv_re/build/bank04.asm
--
-- The other ~390 routine rows in the graph come from
-- `python tools/re_kb/ingest/run.py --marv-routines`, which enumerates PCs
-- straight out of build/*.asm. These two are simply outside whatever slice
-- that run covered. Re-running the enumeration is the general fix; this file
-- makes the two cited ones resolve now, and is harmless afterwards (UPSERT).
--
-- Apply: tools/re_kb/rekb.sh @tools/re_kb/81_integrity_followups.surql
-- ============================================================================
USE NS re DB kb;

UPSERT routine:loc_8c033b0a SET
  label='loc_8c033b0a',
  pc='0x8C033B0A',
  bank='bank03',
  note='Cited by finding:gsta_super_effect_overtile. Row created 2026-09-01 to resolve a dangling cites edge; PC verified present in ../_marv_re/build/bank03.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';

UPSERT routine:loc_8c04515e SET
  label='loc_8c04515e',
  pc='0x8C04515E',
  bank='bank04',
  note='Cited by finding:objpool_list_system_complete. Row created 2026-09-01 to resolve a dangling cites edge; PC verified present in ../_marv_re/build/bank04.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
