-- ============================================================================
-- 24_per_side_facing_texu_mirror.surql
-- 2026-06-13 — THE PER-SIDE RENDER ASYMMETRY ROOT CAUSE + FIX.
-- Symptom: the SAME character renders coherent on one side but GARBLED on the
-- opposite side (Sentinel/Cable scramble on the facing=1 side). NOT geometry
-- (per-part screenX/Y are 0.00px vs ASMTRACE on BOTH sides, finding:
-- render_frame_positions_validated). It is the TEXTURE decode: the client never
-- applied the engine's facing texU mirror, and derived the wide-part carve column
-- from SCREEN-X rank (which flips with facing) instead of the facing-independent
-- STORAGE column.
--
-- Apply AFTER 21_wide_part_tile_storage_order.surql. Then 07_dedup_edges.surql.
-- ============================================================================
USE NS re DB kb;

-- ---- 1. the ASMTRACE truth: storage column -> screenX REVERSES with facing ----
UPSERT finding:per_side_storage_col_reverses SET date='2026-06-13', confidence='high', status='confirmed',
  contribution_candidate=false,
  note='MEASURED on prod /dev/shm/mc_assembly.log (the engine ASMTRACE @ PC 0x8C034864, loc_8c0344d4). For the SAME multi-column body part, the mapping from STORAGE column (the r13/col17 emission order = the +0xDC-cursor prefix walk order) to SCREEN-X (col10) REVERSES with the body facing (char+0x110): facing=0 (faces LEFT; e.g. Sentinel cid52 sel124 128x128 4x4, sel121 128x16 8x1): emission r13-ASCENDING => screenX DESCENDING => storage-col-0 lands at the HIGHEST screenX. facing=1 (faces RIGHT; e.g. Cable cid23 sel232/sel231 2-col): emission r13-ASCENDING => screenX ASCENDING => storage-col-0 lands at the LOWEST screenX. PROOF LINES: Sentinel RIGHT frame sel124 r13 8c1fa018..054 screenX 587.67(first)->427.67(last); Cable LEFT frame sel232 r13 8c1fa044/048 screenX 466.33->519.67, sel231 ascending. The ASMTRACE flip col14 is the PER-PART 0x4000 authoring flag (NOT the body facing) -- it is 0 on both Sentinel sides and only set on inherently-flipped parts (Cable sel346). The body facing lives ONLY in the screen positions + the texU mirror, gated by char+0x110.';

-- ---- 2. the ROM mechanism (consumes the existing facing subgraph) -----------
UPSERT finding:client_missing_facing_texu_mirror SET date='2026-06-13', confidence='high', status='confirmed',
  contribution_candidate=false,
  note='ROOT CAUSE of the per-side scramble in the asset-driven client (render_frame + body_decoder). The ENGINE stores each WxH body part in VRAM ONCE in facing-INDEPENDENT storage order (finding:wide_part_vram_storage) and applies the L/R flip at DRAW time via TWO coupled, facing-gated steps (re_kb routine:loc_8c03453a render gate -> loc_8c034548 neg r10 POSITION pen reflect + loc_8c0346c4 neg r8 TEXTURE-U mirror; one byte char+0x110, position and texture NEVER decouple). The client had BOTH halves wrong for the flipped side: (a) it never emitted the texU mirror -- wasm_entry_frame.c hardcoded UV u0=0,u1=u2=U regardless of facing; (b) it derived the wide-part carve column by ranking the per-tile SCREEN anchor Ax DESCENDING (render_frame_quad_colrow_impl), which == the storage column ONLY for facing=0; for facing=1 the screen-X rank is REVERSED vs storage (finding:per_side_storage_col_reverses), so the carve sliced the COLUMN-MIRRORED storage chunk of every wide part -> the garbled facing=1 side (worst on Sentinel: big wide parts sel124 4x4 / sel121 8x1 / sel125 4x1). The position pen was already correct (0.00px) because the engine pen-reflect was captured; col + texU were the only remaining facing-coupled DECODE terms. This also explains the earlier "carve OFF closer for Cable" note: Cable happened to be on the facing-0 side in that capture, where storage col == screen rank (identity).';

-- ---- 3. the fix (byte-exact, traced -- no model) ---------------------------
UPSERT finding:per_side_facing_fix SET date='2026-06-13', confidence='high', status='confirmed',
  contribution_candidate=true,
  note='THE FIX (branch feat/render-replica-live), in two ROM-faithful parts. (1) TEXU MIRROR: render_frame.c attaches per-quad facing=char+0x110!=0 and the GFX2 cell record per-part 0x4000 flag (r11+0x4 & 0x4000); the resolved mirror bit = facing XOR (0x4000!=0) -- exactly the loc_8c0346c4 neg-r8 gate. wasm_entry_frame.c emits the sprite UVs mirrored (u0=U,u1=u2=0) when set, else (u0=0,u1=u2=U). New export render_frame_quad_mirror. (2) CARVE STORAGE COLUMN: render_frame_quad_colrow_impl now ranks Ax DESCENDING for facing==0 and ASCENDING for facing==1 -> col is the FACING-INDEPENDENT storage column for both sides (so body_decoder.detwiddleImage/carveTile always slice the same fixed storage chunk; the visual flip is the texU mirror alone, never a re-store). VALIDATED vs the ASMTRACE truth (tools/render-replica-poc/_validate_facing.mjs on live captures): for EVERY wide part, facing=0 body => col++ => screenX-- & mirror=0; facing=1 body => col++ => screenX++ & mirror=1 (consistent storage convention both sides; mirror set on exactly the facing-XOR-0x4000 quads). VISUAL: Cable-on-P1 (facing=1) goes from a scattered limb jumble (gun + forearm detached, parts mirror-misplaced) to a coherent facing-right Cable (tools/render-replica-poc/_cable_p1_BEFORE_AFTER.png; _before_f0.png vs _cable_p1_after.png). NOTE: the residual Sentinel-on-P1 BLACKNESS in that capture is a SEPARATE pre-existing palette read-set gap (PVR bank 512+ for P1C2 was all-zero in the shipped pvr snapshot), NOT this facing bug -- carve+geometry are correct (47 quads written, valid TCWs); track under the read-set palette gap. PORT: render_frame.c (TileCap.flip4000, SceneQuad.mirror/facing, submit r11+4 read, colrow facing rank, render_frame_quad_mirror_impl), wasm_entry_frame.c (mirrored UV + export), build_wasm_frame.sh (EXPORTS += _render_frame_quad_mirror), web/render-replica/replay.html cockpit knobs (texU mirror, force-flip, per-side carve, col-reverse, within-tile mirror; mir+col in the readout). body_decoder.mjs carveTile gained an inTileMir A/B option (default off). CITE: ASMTRACE col5/col10/col14/col17; re_kb routine:loc_8c0346c4 / loc_8c034548 / loc_8c03453a / field:facing; finding:per_side_storage_col_reverses; finding:render_frame_positions_validated.';

-- ---- edges -----------------------------------------------------------------
RELATE finding:client_missing_facing_texu_mirror->about->finding:per_side_storage_col_reverses SET kind='about';
RELATE finding:client_missing_facing_texu_mirror->cites->routine:loc_8c0346c4 SET kind='cites';
RELATE finding:client_missing_facing_texu_mirror->cites->routine:loc_8c034548 SET kind='cites';
RELATE finding:client_missing_facing_texu_mirror->cites->routine:loc_8c03453a SET kind='cites';
RELATE finding:client_missing_facing_texu_mirror->about->field:facing SET kind='about';
RELATE finding:per_side_facing_fix->about->finding:client_missing_facing_texu_mirror SET kind='fixes';
RELATE finding:per_side_facing_fix->about->finding:wide_part_tile_storage_order_v2 SET kind='about';
RELATE finding:per_side_facing_fix->cites->routine:loc_8c0346c4 SET kind='cites';
RELATE finding:per_side_storage_col_reverses->cites->routine:loc_8c0344d4 SET kind='cites';
RELATE finding:per_side_storage_col_reverses->about->field:facing SET kind='about';
-- ============================================================================
