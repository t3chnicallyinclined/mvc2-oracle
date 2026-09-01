-- ============================================================================
-- 21_wide_part_tile_storage_order.surql
-- 2026-06-13 — THE CANONICAL WIDE-PART TILE-STORAGE ORDER (the LAST untraced
-- algorithm in the render chain). Traced from the load-time decoder + DMA +
-- per-frame walker in marvelous2, PROVEN BYTE-EXACT against the reproduced scramble
-- (_sentinel_scramble.mcrr frame0: PL34 Sentinel gfx1=0xc420040 sel124 128x128
--  16 tiles; PL17 Magneto gfx1=0xc810040 sel285 64x128 8 tiles).
--
-- Closes the gap left OPEN by finding:tiling_grid_is_engine_correct (which suspected
-- the quad CORNER LAYOUT under flip). The real divergence was the DECODE-TO-VRAM
-- CHUNK ORDER for parts that are >=2 tiles wide AND >=2 tiles tall.
--
-- Apply AFTER 20_replica_local_gfx_overlay.surql, then run 07_dedup_edges.surql.
-- ============================================================================
USE NS re DB kb;

-- ---- 1. the load-time VRAM storage order (decoder + DMA) --------------------
UPSERT finding:wide_part_vram_storage SET date='2026-06-13', confidence='high', status='confirmed',
  note='HOW A WxH BODY PART IS STORED IN VRAM AT LOAD TIME (traced from marvelous2). The load-time GFX1 packer loc_8c033d78 iterates the GFX2 cell records; per part it reads sel=u16@(0x6,r13), indexes the GFX1 part table (gfx1 + sel*4) -> part data, reads sw=u8@(part+2), sh=u8@(part+3), sets W=sw*8, H=sh*8 (the shll2;shll = *8 at loc_8c033e90), and LZSS-decodes the part CONTIGUOUSLY into the decompress scratch 0x0CE60000 (loc_8c033e28) via loc_8c0354c0, advancing the scratch ptr r8 by destLen=(W*H)>>1 per part (4bpp). loc_8c0354c0 is a PLAIN byte-stream LZSS (r6 dest increments +1/byte, NO twiddle, NO tile reorder) so the scratch holds each part in its NATIVE SOURCE byte order. After all parts decode, loc_8c033d78 (at loc_8c033f14) DMAs the whole scratch to VRAM via loc_8c1240a0 with r4=(texaddr<<8)+0x0390 (loc_8c033f76=0x0390); loc_8c1240a0->loc_8C123E00 walks the per-part record table (0x3C stride) assigning each part its rectab texaddr and writing the part bytes to VRAM AS-IS. NET: the part lives in VRAM as ONE CONTIGUOUS BLOB in FULL-WxH PVR RECTANGULAR-TWIDDLE order (the source bytes ARE the full-WxH twiddle; flycast texPAL4_TW reads them back identically, byte-exact in finding:gfx1_decode_equals_vram). It is NOT stored as independent row-major or column-major 32x32 tiles. CITE: loc_8c033d78, loc_8c033e90, loc_8c0354c0, loc_8c1240a0, loc_8C123E00.';

-- ---- 2. the per-frame walker per-tile TCW (storage) order -------------------
UPSERT finding:wide_part_walker_tile_order SET date='2026-06-13', confidence='high', status='confirmed',
  note='HOW THE PER-FRAME WALKER EMITS EACH TILE TCW FOR A WIDE PART (traced + measured). The body walker loc_8c0344d4 expands one GFX2 cell into N tiles (finding:body_walker_tiling); for a WxH part it emits N=(W/32)*(H/32) tiles, each a FIXED 32x32 PAL4_TW quad (TSP texU=2). The N tiles TCW vaddrs STEP +0x200 (=512B = one 32x32 PAL4 tile = 1024 px) CONTIGUOUSLY across the same whole-part blob: tile k vaddr = base + k*0x200, k=0..N-1 (MEASURED on _sentinel_scramble.mcrr: PL34 sel124 128x128 steps [0..15], PL17 sel285 64x128 steps [0..7], both perfectly contiguous). So vaddr-chunk-k = the k-th 512B chunk of the full-WxH twiddle = the part tile at STORAGE position invtw(k). The renderer (texture-manager _pal4) reads each tile as an INDEPENDENT 32x32 LOCAL twiddle (twop x,y,5,5) at addr = that tile TCW vaddr; the low 10 bits of the full-WxH twiddle over a 32x32 region ARE the standalone 32x32 twiddle, so each 512B chunk is a self-contained valid 32x32 tile. CITE: loc_8c0344d4, bank12 submit loc_8c1244b0, texture-manager.mjs _pal4/twop.';

-- ---- 3. the canonical (col,row) -> chunk rule (THE algorithm) ---------------
UPSERT finding:wide_part_tile_storage_order SET date='2026-06-13', confidence='high', status='confirmed',
  contribution_candidate=false,
  note='CANONICAL WIDE-PART TILE-ORDER (closes the last render bug). GATE: applies ONLY when W>32 AND H>32 (the part is >=2 tiles wide AND >=2 tiles tall). For parts with a single tile-column OR a single tile-row (W<=32 OR H<=32) the full-WxH-twiddle chunk order COINCIDES with the walker per-tile vaddr emission order (identity) -- why Cable/Magneto <=2-col 64x64 and tall 32xN poses passed byte-exact (finding:gfx1_decode_equals_vram, now SCOPED). For W>32 AND H>32 they DIVERGE by a tile-grid permutation. PROVEN RELATION (probe_consistency.mjs + probe_twiddle_math.mjs): the screen grid cell of the quad at vaddr-chunk k != the storage tile invtw(k); off-diagonal cells permute (a tile-grid transpose for SQUARE grids, a different perm for rectangular). CONSEQUENCE for the asset-driven renderer: writing the FULL-WxH decode CONTIGUOUSLY at the run base puts the WRONG 32x32 chunk under each wide tile (mostly the transparent corner tiles) -> the near-empty Sentinel. THE ALGORITHM (general, square AND rectangular): for a W>32 && H>32 part with Tw=W/32, Th=H/32, take each emitted tile OWN intra-part cell (col,row) [the tile screen cell within the part grid, exposed by render_frame_quad_colrow = ranking the per-tile descriptor screen anchor Ax desc (col) / Ay desc (row) within the (gfx1,sel) run], carve the full-WxH-blob 512B chunk at storage index twTile(col,row,Tw,Th) [PVR rect-twiddle of the tile coords, bx=log2(Tw),by=log2(Th)], and write that 32x32-local-twiddle slice to the tile OWN TCW vaddr. VERIFIED BYTE-EXACT (tools/render-replica-poc _validate_carve.mjs/_validate_mag.mjs on _sentinel_scramble.mcrr): reassembling the carved 32x32 tiles at their (col,row) == the full-WxH twiddle decode, diff=0 px for BOTH PL34 sel124 128x128 4x4 [0/16384] AND PL17 sel285 64x128 2x4 [0/8192]. WARNING: a pure bit-transpose tw(invtw(k).y,invtw(k).x) of the vaddr-chunk index is correct ONLY for SQUARE grids (4x4 carve=[0,2,1,3,8,10,9,11,4,6,5,7,12,14,13,15]); for RECTANGULAR grids it is WRONG (2x4 correct carve=[1,3,0,2,5,7,4,6]). USE the (col,row)->twTile(col,row,Tw,Th) rule (correct for both). <=2-column / single-row parts keep the proven contiguous (identity) path. PORT: render_frame.c render_frame_quad_colrow_impl + wasm_entry_frame.c export render_frame_quad_colrow; web/render-replica/body_decoder.mjs ensureBodyTextures(...,quadColRow) wide-part carve. Branch feat/render-replica-live. CITE: loc_8c0344d4 (walker per-tile vaddr +0x200), loc_8c033d78 / loc_8c1240a0 (full-WxH-twiddle VRAM storage), texture-manager.mjs _pal4 (per-tile 32x32-local-twiddle read).';

-- ---- scope the now-incomplete byte-exact claim -----------------------------
UPDATE finding:gfx1_decode_equals_vram SET
  note=note + ' [SCOPE 2026-06-13: the write-the-full-WxH-decode-contiguously-at-run-base model is byte-exact ONLY for parts <=2 tiles WIDE OR <=2 tiles tall such that the full-WxH-twiddle chunk order == the walker per-tile vaddr order (identity). For W>32 AND H>32 the two orders DIVERGE and the client must carve each emitted tile from the full decode per finding:wide_part_tile_storage_order (chunk = twTile(col,row,Tw,Th)). Prior byte-exact validations (Cable sid 0xd4, _ryu_capture) were all <=2-col poses.]';

-- ---- 4. CORRECTION 2026-06-13: the chunk-permutation was SCOPED to 32px tiles --
UPSERT finding:wide_part_tile_storage_order_v2 SET date='2026-06-13', confidence='high', status='confirmed',
  note='CORRECTION + GENERALIZATION of finding:wide_part_tile_storage_order. The twTile(col,row,Tw,Th) chunk-permutation (which derived the grid as Tw=W>>5,Th=H>>5 and carved 512B storage chunks) was BYTE-EXACT only for parts whose tile size is 32px (sel124 128x128 4x4, sel285 64x128 2x4). It SCATTERED sub-32px wide rows because the walker does NOT always tile at 32px: Sentinel sel121 is a 128x16 part painted as an 8x1 grid of 16x16 tiles (m=16) and sel125 64x16 as 4x1 m16 (MEASURED: render_frame quad screen-width 26.7px = half sel124\'s 53.3px => m=16 not 32; texU=2 declares a 32x32 texture but the walker\'s u1 UV-clamp samples only the top-left m x m). For these Th=H>>5=0 -> the OLD code\'s Tw>=2&&Th>=2 gate FELL THROUGH to the contiguous whole-blob write -> tiles 2..7 read past the 1024B decode -> scatter. UNIVERSAL TRUTH (probed across EVERY multi-tile sel in the synced Sentinel/Magneto frame): the walker lays a cols x rows grid of m x m SQUARE tiles where cols/rows = the emitted per-tile screen cells (render_frame_quad_colrow) and m = W/cols = H/rows (always 8/16/32, integer, square for all 19 runs). THE GENERAL CARVE (replaces twTile): de-twiddle the part ONCE to its full-WxH row-major nibble IMAGE, then for each emitted tile (col,row) build a fresh 32x32 PAL4 LOCAL-twiddle tile whose top-left m x m holds image[(row*m..)+(col*m..)] and write it to that tile\'s OWN TCW vaddr. VERIFIED BYTE-EXACT 0px on ALL 19 multi-tile runs of _sentinel_scramble.mcrr (square 4x4 m32, wide 8x1/4x1/2x1 m16/m8, tall 1x8/1x4/1x2 m16/m8, rect 2x4 m32) AND sel112 (128x128 4x4 m32, offline) via tools/render-replica-poc/_validate_all_multi.mjs + _validate_sel121.mjs + _validate_sel112.mjs; visually coherent Sentinel upper+lower body (_sel121_AFTER.png 22555 nonblack vs _sel121_BEFORE.png 13345). PORT: web/render-replica/body_decoder.mjs ensureBodyTextures -> twop()/detwiddleImage()/carveTile(); the C side render_frame_quad_colrow is UNCHANGED (already emits the authoritative per-tile col/row). NO disasm change needed: the engine\'s per-tile tile-size m and grid are exactly what render_frame already reproduces; the earlier twTile derivation simply used the wrong grid source (sw/sh>>5 instead of the emitted cells). Branch feat/render-replica-live.';
RELATE finding:wide_part_tile_storage_order_v2->about->finding:wide_part_tile_storage_order SET kind='corrects';
RELATE finding:wide_part_tile_storage_order_v2->cites->routine:loc_8c0344d4 SET kind='cites';

-- ---- the tools that traced/proved it (reproducible) ------------------------
UPSERT tool:probe_twiddle_math CONTENT {
  kind:'tool',
  ref:'tools/render-replica-poc/probe_twiddle_math.mjs',
  note:'PURE MATH (no capture): slices a full WxH PVR rect-twiddle into 512B (1024px) chunks and reports, per +0x200 chunk, which 32x32 tile it covers + whether the chunk is a single PURE tile. RESULT: every square/rect 2^n chunk IS one pure 32x32 tile, and the chunk order over the tile grid IS the PVR twiddle of the tile coordinates.'
};
UPSERT tool:probe_consistency CONTENT {
  kind:'tool',
  ref:'tools/render-replica-poc/probe_consistency.mjs',
  note:'Runs the real render_frame.wasm over a capture, collects each emitted tile of a (gfx1,sel) -> (vaddr, screenX/Y), derives the screen (col,row), and compares the render_frame SCREEN tile order to the full-WxH twiddle STORAGE chunk order. RESULT: INCONSISTENT for W>32&&H>32 (off-diagonal cells permute). Decisive proof of the wide-part divergence with NO resident VRAM needed.'
};
UPSERT tool:validate_carve_mjs CONTENT {
  kind:'tool',
  ref:'tools/render-replica-poc/_validate_carve.mjs (Sentinel 4x4) and _validate_mag.mjs (Magneto 2x4)',
  note:'Strict byte-exact gate for the wide-part carve: runs render_frame_node.wasm + body_decoder.ensureBodyTextures (with render_frame_quad_colrow), then reassembles the carved 32x32 tiles at their (col,row) and diffs vs the full-WxH twiddle decode. PASS = diff 0 px. Confirmed 0/16384 (sel124) and 0/8192 (sel285).'
};

-- ---- edges -----------------------------------------------------------------
RELATE finding:wide_part_vram_storage->cites->routine:loc_8c033d78 SET kind='cites';
RELATE finding:wide_part_vram_storage->cites->routine:loc_8c0354c0 SET kind='cites';
RELATE finding:wide_part_walker_tile_order->cites->routine:loc_8c0344d4 SET kind='cites';
RELATE finding:wide_part_tile_storage_order->cites->routine:loc_8c0344d4 SET kind='cites';
RELATE finding:wide_part_tile_storage_order->cites->routine:loc_8c033d78 SET kind='cites';
RELATE finding:wide_part_tile_storage_order->about->finding:wide_part_vram_storage SET kind='about';
RELATE finding:wide_part_tile_storage_order->about->finding:wide_part_walker_tile_order SET kind='about';
RELATE finding:wide_part_tile_storage_order->about->finding:tiling_grid_is_engine_correct SET kind='about';
RELATE finding:wide_part_tile_storage_order->about->finding:gfx1_decode_equals_vram SET kind='about';
-- ============================================================================
