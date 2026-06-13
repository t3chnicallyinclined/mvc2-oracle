-- ============================================================================
-- 17_tiling_geometry_validated.surql
-- 2026-06-13 — render_frame's TILED-CELL GEOMETRY is BYTE-FAITHFUL to the engine.
-- REFUTES the INFERRED suspect "render_frame.c:185 m=(dc+k) descriptor index is wrong".
-- Numerically proven on a heavily-tiled live frame (maxq_86.mcrr) via a native harness
-- that loads the .mcrr RAM and runs the transpiled render_frame, comparing PER-TILE
-- to the proven walker (gen_walker.c = loc_8c0344d4) and to the engine ASMTRACE.
-- Apply AFTER 16_emitter_tiling_sel_pairing.surql, then 07_dedup_edges.surql.
-- ============================================================================
USE NS re DB kb;

UPSERT finding:tiling_geometry_byte_faithful SET date='2026-06-13', confidence='high', status='confirmed',
  contribution_candidate=false,
  note='render_frame (tools/render-replica-poc/render_frame.c) produces TILED-CELL TA GEOMETRY that is BYTE-FAITHFUL to the engine walker loc_8c0344d4. PROVEN on maxq_86.mcrr frame0 (2 heavily-tiled bodies: cid9 sid0x85 19 cells->35 tiles incl 4x/8x cells; cid23 sid0x47 19 cells->51 tiles incl 8x cells) with a native harness (diag_tile_pos.c, MSVC) that loads the .mcrr resident RAM and runs render_frame, dumping per-tile anchor (bx,by), m-extent, recidx, TCW. THREE checks all PASS: (1) PER-TILE ANCHORS (g_cap[k].bx/by) come straight from the proven 9/9 walker (it writes the final per-tile screen X/Y to stack r15+0x30/0x34 and submit_1244b0 reads r4+0x04/+0x08); they STEP correctly (sel285 8-tile -> 2-col x 4-row grid of stepped anchors; sel275 4-tile -> 1D row) matching the engine ASMTRACE _ryu_capture/asm_angled_fist.log step pattern (which itself shows the engine emits 1D CHAINS and 2D GRIDS of the SAME repeated part per tiled cell, e.g. sid42 232 tiles = an 8-row x N-col grid, sid70 88 tiles = 1D rows, sentinel sel2334 x4 stepping ~(-47,-25)). (2) PER-TILE m-EXTENT: render_frame.c:185 m=u8(DESC_TABLE + (dc+k)*4) with dc=node+0xDC, k=GLOBAL per-object tile index == the walker per-tile m=u8(@r13) captured at submit -> 86/86 EXACT, 0 mismatch. The (dc+k) index is CORRECT because the walker seeds r13 = DESC_TABLE + (node+0xDC)<<2 (gen_walker.c:66-79) then advances r13 +=4 PER TILE inside the inner loop (gen_walker.c:863), so global tile k lands at DESC_TABLE+(dc+k)*4 exactly. (3) PER-TILE TCW/recidx are resident-rectab-exact (already covered by the render_frame_test byte-exact gate, still PCW/ISP/TSP/TCW 9/9 RESULT PASS). VERDICT: the off-SH4 emitter TILING GEOMETRY needs NO fix; the descriptor-index INFERENCE (prior task flag on render_frame.c:185/177) is REFUTED.';

UPSERT finding:tiling_grid_is_engine_correct SET date='2026-06-13', confidence='high', status='confirmed',
  note='RECONCILIATION of the "grid of identical parts" live symptom. The engine loc_8c0344d4 RENDERS A TILED CELL AS THE SAME PART (one GFX1 sel, one decoded sprite) REPEATED at N stepped anchors — a 1D chain OR a 2D grid depending purely on the per-tile descriptor dx_unit/dy_unit stream (asm_angled_fist.log shows BOTH: sid42 = 8-row grid, sid70 = 1D row). So a grid of identical parts is the engine-CORRECT layout for a grid-tiled cell; it is NOT inherently a bug. Each tile carries its OWN distinct TCW (resident rectab texaddr steps by 0x200/tile = one rectab slot per tile, INDEPENDENT of part pixel size: maxq_86 destLen ranged 32..4096 bytes with tcount 1/2/4/8, so the 0x200 stride is rectab allocation granularity NOT a texture slice). body_decoder.mjs:177 writes the decoded part (memoized by gfx1|sel) to EACH tile own TCW, which REPLICATES the engine load-time packer per-tile VRAM copies. CONSEQUENCE for debugging the live grid symptom: since geometry+m+TCW are all byte-faithful, a wrong-looking grid is NOT a render_frame TA-generation bug. Remaining unproven term = the quad CORNER LAYOUT (render_frame lays an axis-aligned WxH box upward from bx,by; lines 196-199) vs the engine submit loc_8c1244b0 corner transform (gen_submit.c loc_8c124ab0) under X/Y-mirror flags (FLAGS 0x4000/0x8000) and non-axis-aligned cases — that is the ONLY divergence candidate left and overlaps the OPEN re_kb item emitter_flip_unvalidated. Next step if the live grid persists: capture an ALIGNED tiled-pose engine TA (MAPLECAST_DUMP_RAM) and byte-diff render_frame TA corners vs engine TA corners on a tiled cell, focusing on flipped tiles.';

-- the harness used (a tool source, reproducible)
UPSERT tool:diag_tile_pos CONTENT {
  kind: 'tool',
  ref: 'tools/render-replica-poc/diag_tile_pos.c (scratch, MSVC) — loads an .mcrr resident RAM image, runs the transpiled render_frame over it, dumps per-tile anchor/m/recidx/TCW and compares render_frame m to the walker per-tile m=u8(@r13). Use to validate tiled-cell geometry vs the proven walker without a live capture.',
  note: 'Built with vcvars64 (VS2022 BuildTools) + cl; links gen_walker_root.c render_frame.c gen_render_object.c gen_transform_obj.c gen_submit_params.c gen_walker.c gen_leaf.c.'
};

-- edges
RELATE finding:tiling_geometry_byte_faithful->cites->routine:loc_8c0344d4 SET kind='cites';
RELATE finding:tiling_geometry_byte_faithful->about->finding:body_walker_tiling SET kind='about';
RELATE finding:tiling_grid_is_engine_correct->cites->routine:loc_8c0344d4 SET kind='cites';
RELATE finding:tiling_grid_is_engine_correct->about->finding:body_walker_tiling SET kind='about';
RELATE finding:tiling_grid_is_engine_correct->about->finding:tiling_sel_pairing_fix SET kind='about';
