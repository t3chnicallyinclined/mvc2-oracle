-- ============================================================================
-- 43_carve_wide_square_twiddle_fix.surql
-- 2026-06-15 — CLOSES finding:carve_wide_square_twiddle_open (re_kb/42).
-- The Storm (P1) cape garbling = the W>32 AND H>32 SQUARE-part carve.
-- CONFIRMED-BY-MEASUREMENT. Apply AFTER 42_carve_tile_pitch_m_fix.surql,
-- then 07_dedup_edges.surql.
-- ============================================================================
USE NS re DB kb;

UPSERT finding:carve_wide_square_twiddle_fix SET date='2026-06-15', confidence='high', status='confirmed',
  contribution_candidate=false,
  note='FIXES finding:carve_wide_square_twiddle_open. SYMPTOM: Storm (P1) CAPE parts rendered '
     + 'DISPLACED/DUPLICATED (detached cape block to her LEFT frame120; mirrored cape + displaced '
     + 'forearm to her RIGHT frame132) while Magneto (P2) was fully coherent. CHAR-SPECIFIC because '
     + 'ONLY Storm\'s large flowing cape is a W>32 AND H>32 SQUARE body part; Magneto\'s parts in that '
     + 'pose are all m<32 or <=2-tile (the already-byte-exact linear-slice path). ROOT CAUSE (HYP 1 of '
     + 'the task, MEASURED, NOT the facing/U-mirror HYP 2): the engine stores each part as ONE full-WxH '
     + 'PVR rect-twiddle blob (finding:wide_part_vram_storage); the per-frame walker (loc_8c0344d4) '
     + 'emits N tiles whose +0x200 VRAM chunks step CONTIGUOUSLY across that blob, and the pvr2 renderer '
     + 'reads tile (col,row) as a standalone 32x32 PAL4_TW from the storage chunk at twTile(col,row,Tw,Th) '
     + '(finding:wide_part_tile_storage_order). The carve (gstaDecodeBodies + body_decoder.ensureBodyTextures) '
     + 'instead detwiddled the whole part to a LINEAR WxH image, sliced the (col*32,row*32) cell, and '
     + 're-twiddled it (retwiddle32). That linear-slice->retwiddle32 ROUNDTRIP reproduces the native chunk '
     + 'ONLY for parts <=32 in at least one dim (m<32, where the linear cell IS the chunk); for parts >32 '
     + 'in BOTH dims the full-WxH twiddle interleave spans the whole part so the 32x32 region of the linear '
     + 'image != the native 512B storage chunk -> the displaced/scrambled cape. '
     + 'MEASURED ARBITER (tools/render-replica-poc/_measure_chunk.mjs, OFFLINE from disc gfx1, no capture): '
     + 'the raw decodeA chunk at twTile(col,row,log2Tw,log2Th)*512, read as a standalone 32x32 twiddle, == '
     + 'the reference detwiddled cell EXACTLY: PL34 Sentinel sel124 128x128 4x4 diff=0/16384; PL17 Magneto '
     + 'sel285 64x128 2x4 diff=0/8192 (the two parts _validate_all_multi.mjs left failing at 17/19). '
     + 'FIX (IDENTICAL in both decoders, keep in lockstep): for m==32 && cols>1 && rows>1, copy the NATIVE '
     + '512B storage chunk at twTile(col,row,log2(Tw),log2(Th))*512 from the raw decodeA output VERBATIM to '
     + 'the tile\'s TCW vaddr — bypassing the lossy detwiddle/retwiddle. m<32 wide/tall/short parts keep the '
     + 'linear-slice path (already byte-exact, finding:carve_tile_pitch_m). NO disasm/geometry change: the '
     + 'walker per-tile (col,row) and screen positions are untouched (0.00px). PORTED: web/render-replica/'
     + 'body_decoder.mjs (twTile() + decodePart keeps raw + ensureBodyTextures square branch); core/network/'
     + 'maplecast_mirror.cpp (gstaTwTile() + GstaDecodedPart.raw + gstaDecodeBodies square branch). '
     + 'VERIFIED: _validate_all_multi.mjs 17/19 -> 19/19 multi-tile runs BYTE-EXACT (sel124 0/16384, sel285 '
     + '0/8192 now PASS). LIVE: native flycast.exe rebuilt clean; GSTA client _gsta_storm frames 120/132 '
     + 'show Storm\'s cape coherent (no detached/duplicated block) vs _gsta_p1_132.png (before = duplicated '
     + 'displaced cape to her right); Magneto unaffected. Commit 274d09474, branch feat/render-replica-live. '
     + 'NOTE: a residual single dark 32x32 patch on Storm\'s torso is a SEPARATE transparency/palette artifact, '
     + 'NOT this carve garbling (cape geometry + duplication fully resolved). CITE: loc_8c0344d4; '
     + 'finding:wide_part_tile_storage_order twTile; _measure_chunk.mjs; _validate_all_multi.mjs.';

UPDATE finding:carve_wide_square_twiddle_open SET status='fixed',
  note=note + ' [CLOSED 2026-06-15 by finding:carve_wide_square_twiddle_fix: the native-chunk carve '
     + '(copy raw decodeA chunk at twTile(col,row)*512 verbatim for m==32 && cols>1 && rows>1) makes both '
     + 'square parts byte-exact (19/19) and the live Storm cape coherent. Was HYP 1, MEASURED — not the '
     + 'facing/U-mirror HYP 2.]';

RELATE finding:carve_wide_square_twiddle_fix->about->finding:carve_wide_square_twiddle_open SET kind='fixes';
RELATE finding:carve_wide_square_twiddle_fix->about->finding:wide_part_tile_storage_order SET kind='about';
RELATE finding:carve_wide_square_twiddle_fix->about->finding:carve_tile_pitch_m SET kind='about';
RELATE finding:carve_wide_square_twiddle_fix->cites->routine:loc_8c0344d4 SET kind='cites';
-- ============================================================================
