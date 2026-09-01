-- ============================================================================
-- 44_carve_nonsquare_linear_fix.surql
-- 2026-06-15 — CORRECTS finding:carve_wide_square_twiddle_fix (re_kb/43) for the
-- NON-SQUARE case. The Storm-torso DARK/GARBLED patch in the native GSTA client.
-- CONFIRMED-BY-MEASUREMENT (gsta audit pass: VRAM+palette diff, full-part decode,
-- flycast-twop sampling simulation, live screenshots). Apply AFTER 43, then
-- 07_dedup_edges.surql.
-- ============================================================================
USE NS re DB kb;

UPSERT finding:carve_nonsquare_linear_fix SET date='2026-06-15', confidence='high', status='confirmed',
  contribution_candidate=false,
  note='FIXES the Storm-torso DARK/GARBLED patch in the native GSTA client (gstaDecodeBodies + '
     + 'body_decoder.ensureBodyTextures). COMPREHENSIVE GROUND-TRUTH AUDIT (engine memory = arbiter): '
     + '(1) PALETTE: dumped palette32_ram (post PAL_RAM_CTRL) from BOTH the engine (mirror client :7200) '
     + 'and the GSTA reconstruction (:7212) at a palette-LOCKED frame pair (0/1024 entries differ) -> '
     + 'palette IDENTICAL, and index-0 = 0x00000000 (alpha=0, transparent) in EVERY bank in BOTH. So the '
     + 'dark patch is NOT a palette/index-0/blend defect (rules out the primary hypothesis). '
     + '(2) BLEND/LIST: the engine body PCW/TSP (gen_submit_params finalize_body, byte-exact 0xA2000009 / '
     + '0x949004D2) is ListType=2 Translucent, Src=SRC_ALPHA Dst=INV_SRC_ALPHA, UseAlpha=1 — which the '
     + 'GSTA emit already reproduces. Rules out list/blend. '
     + '(3) ROOT CAUSE = the per-tile CARVE for NON-SQUARE multi-tile parts. sel254 (Storm, W=64 H=128, '
     + '2x4) and sel285 (Sentinel, 2x4): the native-chunk path (m==32 && cols>1 && rows>1) copied the raw '
     + 'twiddled blob chunk at twTile(col,row,log2Tw,log2Th). MEASURED: reading those carved 32x32 tiles '
     + 'through FLYCAST\'S REAL twop sampling (core/rend/texconv.cpp twop = detwiddle[0][bcy][x]+'
     + 'detwiddle[1][bcx][y], + ConvertTwiddlePal4 4x4 _PAL4_ORDER blocks) yields the EXACT on-screen '
     + 'garble (FLYCAST_native.png), while the LINEAR-slice carve (slice the part\'s correct full-part '
     + 'detwiddle pd.lin at (col*32,row*32), retwiddle32) yields the COHERENT body (FLYCAST_linear.png) — '
     + 'for BOTH Storm AND Sentinel. The square twTile interleave is correct ONLY for SQUARE parts '
     + '(Tw==Th, e.g. sel124 128x128 4x4 still 0/16384 byte-exact); a 64x128 part\'s twiddle does NOT '
     + 'decompose into independent 32x32 twop tiles. '
     + 'THE FIX: gate the native-chunk path on Tw==Th; for Tw!=Th fall through to the linear-slice carve. '
     + 'Applied to core/network/maplecast_mirror.cpp gstaDecodeBodies AND web/render-replica/body_decoder.mjs '
     + 'ensureBodyTextures. This scene had 4 broken non-square 2x4 Storm parts (sel 254,267,271,276) = the '
     + 'whole dark/garbled patch; all now coherent. '
     + 'VALIDATOR CORRECTED: tools/render-replica-poc/_validate_all_multi.mjs `ref` assumed single-blob '
     + 'storage (valid for SQUARE only); it gave a FALSE diff=0 for the native-chunk non-square carve '
     + '(self-consistent under the wrong model). Now it reads tiles via flycast twop and only flags SQUARE; '
     + 'non-square is validated visually (flycast-twop). Result: 19/19 SQUARE byte-exact. '
     + 'RESIDUAL (open, low severity): faint pink/blue fragments near a heavily-clipped Storm at the '
     + 'screen edge = EFFECT sprites (dust/landing), present in the engine ground truth too; NOT a body '
     + 'carve defect.';

UPSERT source:gsta_carve_audit_2026_06_15 SET kind='measurement', date='2026-06-15',
  note='Native GSTA client comprehensive divergence audit. Tools: palette32_ram dump in both VRAM hooks '
     + '(maplecast_mirror.cpp), tools/gsta_vram_diff.py (content-aligned band diff), MAPLECAST_DUMP_PART_SEL '
     + 'one-shot full-part decode dump, flycast-twop sampling simulation, _validate_all_multi.mjs (corrected), '
     + 'simultaneous :7200 engine vs :7212 GSTA screenshots. Arbiter = engine palette/VRAM + flycast twop.';

RELATE finding:carve_nonsquare_linear_fix->cites->source:gsta_carve_audit_2026_06_15;
RELATE finding:carve_nonsquare_linear_fix->corrects->finding:carve_wide_square_twiddle_fix;
