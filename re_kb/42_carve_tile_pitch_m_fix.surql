-- ============================================================================
-- 42_carve_tile_pitch_m_fix.surql
-- 2026-06-15 — The body re-tile CARVE pitch fix. CONFIRMED-BY-MEASUREMENT.
-- The multi-row/wide-part GREY BLOCKS were a CARVE over-step (hardcoded 32px
-- pitch), NOT a dropped walker Y-pen. ASMTRACE (PC 0x8C034864) proves the engine
-- steps screenY per row and render_frame reproduces it byte-exact.
-- Apply AFTER 41_gsta_body_ab_diff_fidelity.surql, then 07_dedup_edges.surql.
-- ============================================================================
USE NS re DB kb;

UPSERT finding:carve_tile_pitch_m SET date='2026-06-15', confidence='high', status='confirmed',
  contribution_candidate=false,
  note='THE MULTI-ROW / WIDE BODY-PART GREY BLOCKS = a CARVE-PITCH bug, NOT a dropped walker Y-pen. '
     + 'MEASURED ARBITER (MAPLECAST_ASMTRACE PC 0x8C034864, ground truth): the engine body walker '
     + 'loc_8c0344d4 STEPS screenY PER ROW for multi-row tiled cells (Magneto c810040 sel285 grid '
     + 'screenY={484.43,415.86,347.29,278.71}, 2col x 4row; the Y-pen is advanced, never dropped). '
     + 'render_frame.c reproduces this byte-exact (render_frame_test.exe 9/9 PCW/ISP/TSP/TCW; '
     + 'finding:tiling_geometry_byte_faithful 86/86; finding:gsta_native_carve_matches_web A/B geom '
     + '0.00%). So the degenerate-Ay symptom (quads at one anchor -> grey) was DOWNSTREAM of the '
     + 'walker, in the per-tile re-tile CARVE. ROOT CAUSE: gstaDecodeBodies (maplecast_mirror.cpp) and '
     + 'ensureBodyTextures (web/render-replica/body_decoder.mjs) carved each emitted tile at '
     + 'ox=col*32, oy=row*32 — a HARDCODED 32px pitch — but the engine tiles at m=W/cols=H/rows in '
     + '{8,16,32} (finding:wide_part_tile_storage_order_v2). For a part with m<32 (sel285 W=64 H=16 '
     + '-> 4x1 m16 or 8x2 m8; any wide/short or tall/narrow multi-tile part) row*32 / col*32 over-steps '
     + 'past W/H so every row>=1 (and col>=2) sampled past-end/zero -> the flat grey rows. FIX: per '
     + '(gfx1,sel) run derive cols=maxcol+1 / rows=maxrow+1 from the walker (col,row) ranks '
     + '(render_frame_quad_colrow), set m=min(W/cols,H/rows), carve the m x m source region at '
     + '(col*m,row*m) into the 32x32 tile top-left (engine UV-clamps via u1=m/tile). The walker '
     + '(gen_walker.c) and render_frame.c geometry are UNTOUCHED — 0.00px intact. VERIFIED: '
     + 'c420040 sel285 (W=64 H=16, the task-cited group) NEW carve diff=0/1024 BYTE-EXACT for both '
     + '4x1 m16 and 8x2 m8; _validate_all_multi.mjs on real Sentinel/Magneto assets went 0/19 -> 17/19 '
     + 'multi-tile runs BYTE-EXACT (every m<32 wide/tall/short run fixed). Commit 90533abc4, branch '
     + 'feat/render-replica-live. CITE: ASMTRACE _ryu_capture/asm_sentinel_20260612.log + mc_assembly.log; '
     + 'loc_8c0344d4; finding:wide_part_tile_storage_order_v2; tools/render-replica-poc/_validate_all_multi.mjs.';

-- The 2 still-failing SQUARE runs (W>32 AND H>32, m=32): NOT this bug, pre-existing.
UPSERT finding:carve_wide_square_twiddle_open SET date='2026-06-15', confidence='high', status='open',
  note='OPEN (pre-existing, distinct from the carve-pitch grey-gap fix). After finding:carve_tile_pitch_m, '
     + '17/19 multi-tile runs are BYTE-EXACT; the 2 remaining failures are the W>32 AND H>32 SQUARE parts '
     + '(sel124 128x128 4x4 m32 diff 10718/16384; sel285 64x128 2x4 m32 diff 2098/8192). These need the '
     + 'storage-TWIDDLE-aware carve (finding:wide_part_tile_storage_order_v2 twTile / full-WxH-twiddle '
     + 'chunk), because for parts >32 in BOTH dims the body_decoder detwiddlePal4 (_DETW block tables) and '
     + 'the per-tile linear-slice carve diverge from the full-WxH twiddle storage order. This is the old '
     + 'Sentinel-body wide-square scramble, was ALREADY failing (carve was 0/19 before the pitch fix), and '
     + 'overlaps re_kb emitter_flip_unvalidated. NOT the multi-row Y-pen grey-gap symptom (m<32) the '
     + '2026-06-15 task targeted. FIX WHEN PRIORITIZED: for m==32 && W>32 && H>32, carve each 32x32 tile '
     + 'from the full-WxH twiddle blob at twTile(col,row,Tw,Th) instead of the detwiddled-linear slice.';

RELATE finding:carve_tile_pitch_m->cites->routine:loc_8c0344d4 SET kind='cites';
RELATE finding:carve_tile_pitch_m->about->finding:wide_part_tile_storage_order_v2 SET kind='about';
RELATE finding:carve_tile_pitch_m->about->finding:tiling_geometry_byte_faithful SET kind='about';
RELATE finding:carve_tile_pitch_m->about->finding:gsta_native_carve_matches_web SET kind='corrects';
RELATE finding:carve_wide_square_twiddle_open->about->finding:carve_tile_pitch_m SET kind='about';
RELATE finding:carve_wide_square_twiddle_open->about->finding:wide_part_tile_storage_order_v2 SET kind='about';
