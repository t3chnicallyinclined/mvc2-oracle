-- ============================================================================
-- 16_emitter_tiling_sel_pairing.surql
-- 2026-06-13 — THE TILING SEL<->QUAD SLIP (the "right colors, wrong quad" scramble
-- in the live render-replica) ROOT-CAUSED + FIXED.
--
-- Corrects the FALSE 1:1 assumption recorded in finding:gfx1_decode_equals_vram
-- ("the per-frame body walker emits ONE TA quad per cell record IN ORDER, so TA-quad
--  TCW order == cell-sel order per char"). That holds ONLY for poses with no tiled
-- cells (the single-char _ryu_capture). The body walker loc_8c0344d4 EXPANDS one GFX2
-- cell record into N TILES (N = the inner tile loop bound), all sharing that cell's
-- GFX1 sel — so quad-count > cell-count whenever any cell tiles, and the 1:1 pairing
-- slips after the first tiled cell.
--
-- Apply AFTER 15_pure_state_textures.surql, then run 07_dedup_edges.surql.
-- ============================================================================
USE NS re DB kb;

-- ---- the walker's tiling mechanism (from gen_walker.c = transpiled loc_8c0344d4) ----
UPSERT finding:body_walker_tiling SET date='2026-06-13', confidence='high', status='confirmed',
  note='The per-frame BODY geometry emitter loc_8c0344d4 (bank03:10218; gen_walker.c) has TWO nested loops. OUTER loop (loc_8c0345c4..loc_8c03488e) iterates GFX2 CELL RECORDS: r11 = the 8-byte cell record pointer; the GFX1 sel is read ONCE per cell at `mov.w @(0x6,r11),r0` (sel=u16@r11+6); r11 advances +8 per cell at loc_8c03488e. INNER loop (loc_8c03478e..) is the TILE loop: its bound is set at the cell top to count=u8(desc[r13+1])+1 (r13 walks the 0x8C1F9F9C tile-descriptor table, +4 per cell); each inner iteration calls submit (bank12 loc_8c1244b0) -> ONE emitted screen quad. r11 is NOT touched inside the inner loop, so ALL of a cell tiles carry that ONE cell sel. => 1 GFX2 cell -> N quads (N>=1), all sharing (sel@r11+6, gfx1@node+0x15C), each with its OWN TCW/anchor. PROVED on live frames (maxq_86.mcrr/live.mcrr/live2.mcrr via the transpiled wasm + render_frame_quad_sels): each body per-tile sel runs collapse EXACTLY to its 19 GFX2 cell-record sels in order (e.g. Cable sid 0x47: 19 cells -> 51 quads; cid9 sid 0x85: 19 cells -> 35 quads).';

-- ---- the scramble bug + the fix ----
UPSERT finding:tiling_sel_pairing_fix SET date='2026-06-13', confidence='high', status='confirmed',
  note='SCRAMBLE ROOT CAUSE (live render-replica, "right colors / wrong quad"): web/render-replica/body_decoder.mjs ensureBodyTextures paired quad[i] <-> the char GFX2 cell-sel[i] 1:1 (search-free), assuming one quad per cell. But loc_8c0344d4 emits N tiles per tiled cell (finding:body_walker_tiling), so quad-count > cell-count and the pairing SLIPS after the first tiled cell -> each later quad gets a NEIGHBOR cell sprite decoded to its TCW = right colors, wrong quad. Measured slip (OLD pairing mis-assigns): maxq_86=82/86, live=55/62, live2=76/80 quads. THE FIX: render_frame now EXPOSES, per emitted quad, the SOURCE sel the walker actually used (captured in submit_1244b0 from c->r[11]+6) AND the owning body GFX1 (node+0x15C) via two new wasm exports render_frame_quad_sels(u16*) / render_frame_quad_gfx1s(u32*). body_decoder iterates the EMITTED QUADS (not cell records) and decodes each quad OWN (gfx1,sel) -> its OWN TCW (decode-memoized by gfx1|sel, so a tiled cell decodes once and re-writes to each tile). NO 1:1 walk, NO slip. VALIDATION (tools/render-replica-poc/validate_sel_pairing.mjs on the real wasm + 3 live frames): (3) walker per-tile sel runs == GFX2 cell-sel order per body PASS; (4) every quad written VRAM sprite == decode(walker sel) -> 86/86, 62/62, 80/80 OK, 0 BAD. Regression: render_frame_test.exe byte-exact gate still PCW/ISP/TSP/TCW 9/9, cursor PROOF OK, RESULT PASS (the new SceneQuad sel/gfx1 fields are appended after the validated fields, TA emit unchanged). Files: render_frame.c (submit_1244b0 sel capture, SceneQuad.sel/.gfx1), wasm_entry_frame.c (the 2 exports), build_wasm_frame.sh, body_decoder.mjs (per-quad pairing), replay.html (transpiledTA returns quadSels/quadGfx1s; both showFrame + live path pass them). Branch feat/render-replica-live.';

-- ---- correct the stale 1:1 claim on the byte-exact finding (scope it) -------
UPDATE finding:gfx1_decode_equals_vram SET
  note=note + ' [CORRECTION 2026-06-13: the "ONE TA quad per cell record IN ORDER -> TA-quad TCW order == cell-sel order, pair search-free" claim is TRUE ONLY for poses with NO tiled cells (the _ryu_capture validation pose). In general loc_8c0344d4 expands one cell into N tiles sharing that cell sel (finding:body_walker_tiling), so the client must pair per-EMITTED-QUAD via render_frame_quad_sels/_gfx1s, NOT quad[i]<->cell-sel[i] 1:1. See finding:tiling_sel_pairing_fix.]';

-- ---- edges -----------------------------------------------------------------
RELATE finding:tiling_sel_pairing_fix->cites->routine:loc_8c0344d4 SET kind='cites';
RELATE finding:tiling_sel_pairing_fix->about->finding:body_walker_tiling SET kind='about';
RELATE finding:tiling_sel_pairing_fix->about->tool:body_decoder_mjs SET kind='about';
RELATE finding:body_walker_tiling->cites->routine:loc_8c0344d4 SET kind='cites';
