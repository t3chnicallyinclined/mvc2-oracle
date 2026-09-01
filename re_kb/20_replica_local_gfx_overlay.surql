-- ============================================================================
-- 20: render-replica LIVE — the LOCAL-ROM GFX overlay (confirmed) AND the proof
-- that it does NOT fix the live scramble (scramble is NON-GFX = the body_decoder
-- tiled-texture decode model). Pinned 2026-06-13 from _scramble_actual.mcrr
-- (the user's REAL live PL34/PL17 session, 120 frames, 2 bodies in layers 5+6),
-- reproduced offline by tools/render-replica-poc/repro_scramble.mjs. NOT guessed.
-- ============================================================================
USE NS re DB kb;

UPSERT source:local_gfx_overlay_mjs SET kind='code',
  ref='web/render-replica/local_gfx_overlay.mjs applyLocalGfx()',
  note='Per-frame, BEFORE render_frame/transpiledTA: walk the 6 char-struct slots (0x8C268340 stride 0x5A4); for each active slot read char_id@+0x001, gfx1base@+0x15C, gfx2base@+0x160; load web/render-replica/gfx/PL{NN}_gfx{1,2}.bin (NN=char_id hex); ram.set into the seeded RAM at base&0xFFFFFF. Memoized by char_id (load once, overlay every frame). Restores COMPLETE disc art over any stale/truncated shipped GFX.';

UPSERT source:extract_replica_gfx SET kind='tool',
  ref='tools/extract_replica_gfx.py --verify-ram',
  note='Extracts PLxx GFX1/GFX2 segments from the disc PLDAT and verifies them BYTE-IDENTICAL to a live RAM dump at node+0x15C/0x160. PL34 GFX1 1064736B@0x0c420040, PL17 GFX1 964736B@0x0c810040 -> both 0 diff vs RAM; GFX2 likewise. char_id (struct+0x001) IS the PLxx index in hex.';

UPSERT source:scramble_actual_mcrr SET kind='capture',
  ref='_scramble_actual.mcrr (120 frames, live PL34/PL17, 2 bodies in slot-table layers 5+6)',
  note='THE REAL live scramble capture. Header: v1, 3 static (GFX2@c8fb000, GFX1@c810000, ram16@8c000000:16MB), 14 dynamic (slot_cn/slot_pt/char_st/arena/tiledes/cam_mat/camZ/ggp_ptr/ggp_acc/rparam/tab_ptr/rmode/idxtab/rectab), 120 frames, taSize=0 (no embedded engine_ta). frame0 vframe=101417 emits 4 GFX-tail regions; later steady frames emit 0.';

UPSERT source:repro_scramble_mjs SET kind='tool',
  ref='tools/render-replica-poc/repro_scramble.mjs (+ _probe_dims.mjs / _probe_desc.mjs)',
  note='Drives the EXACT live client pipeline offline: parse MCRR -> seed 16MB RAM -> per frame apply DYNAMIC regions + GFX tail + applyLocalGfx overlay -> render_frame_node.wasm (render_frame_ta + quad_sels/quad_gfx1s) -> body_decoder.ensureBodyTextures -> pvr2-renderer -> PNG. REPRODUCES the user-visible scramble (frame0 PNG: smear of identical fragments top-right + scattered fragments left).';

-- ---- CONFIRMED finding: the overlay itself is correct ----------------------
UPSERT finding:render_replica_local_gfx_overlay SET
  statement='The render-replica LOCAL-ROM GFX overlay (web/render-replica/local_gfx_overlay.mjs applyLocalGfx) is CONFIRMED correct as a mechanism: char_id (char struct +0x001, read as hex) == the PLxx index (PL00=Ryu, PL17=cid 0x23, PL34=cid 0x52); the disc-extracted GFX1/GFX2 segments are BYTE-IDENTICAL to live RAM at node+0x15C/0x160 (tools/extract_replica_gfx.py --verify-ram: PL34 GFX1 1064736B@0x0c420040, PL17 GFX1 964736B@0x0c810040, both 0 diff); writing them into the seeded RAM at base&0xFFFFFF before the walker/decoder read restores COMPLETE, never-truncated art. On _scramble_actual.mcrr both active bodies overlay cleanly (PL34 slot@8c268340 cid=52, PL17 slot@8c2688e4 cid=23) and the render_frame TA is coherent (2 bodies, 83 quads frame0, 16+13 distinct sels, NO grid, monotone-distinct TCWs, 0 collisions). So the overlay closes the static-GFX-gap (finding 18) and is the local-ROM cache foundation.',
  status='confirmed', confidence='high', date='2026-06-13';

-- ---- NEW fact: the overlay does NOT fix the live scramble -------------------
UPSERT finding:render_replica_scramble_is_nongfx SET
  statement='The overlay does NOT fix the live scramble => the scramble is NON-GFX. BISECTED on _scramble_actual.mcrr (repro_scramble.mjs, overlay ACTIVE): render_frame s TA is CORRECT (branch B, not A). Evidence: (1) quad GEOMETRY is coherent — PL17 body quads spread screenX 511..608 / screenY 193..415, PL34 body quads screenX 139..-72 (a limb) / screenY 199..420; sels animate frame-to-frame (frame0 PL17 sels 316,315,227.. ; frame60 344,332,277..); (2) per-quad TCWs are MONOTONE-DISTINCT (frame0: 0x2b083780,c0,800,... stepping 0x40), 83/83 distinct VRAM addrs, ZERO collisions, ZERO cross-body collisions; (3) body_decoder.ensureBodyTextures reports decoded=29 written=83 quads=83 (no skips). YET the rendered PNG is scrambled (smear of identical fragments + scattered fragments) = the user s screen. ROOT CAUSE (the actual bug): a TEXTURE-DECODE MODEL mismatch in web/render-replica/body_decoder.mjs decodePart/ensureBodyTextures, NOT geometry. The engine renders each cell as N TILES of m x m px (m = tile-descriptor byte0 @ 0x8C1F9F9C+(dc+c)*4, here 8 or 16; tilecnt = descbyte1+1), each tile a SEPARATE quad at its OWN twiddled TCW, with the rectab-template TSP a FIXED tile size (texU=texV=2 => 32x32 for ALL 82/83 quads) and the quad UV sub-rect = m/32. body_decoder instead decodes the WHOLE GFX1 part at its STORAGE span sw*8 x sh*8 (e.g. 64x128, 128x128) and writes that linear blob at a SINGLE TCW, repeated identically to each of the cell s N tile-TCWs. So: dimension mismatch (GFX1 storage span vs the 32x32 the renderer twiddle-samples) on 82/83 quads, wrong twiddle order, and the same big-part blob smeared across N tile slots = the scramble. The single-char _ryu_capture passed only because that pose s cells were largely single-tile m=32 with no multi-tile expansion.',
  status='confirmed', confidence='high', date='2026-06-13';

UPSERT finding:render_replica_scramble_fix SET
  statement='FIX (client web/render-replica/body_decoder.mjs only; render_frame.wasm + the geometry are correct and need NO change): replace the whole-part linear write with the engine s PER-TILE m x m twiddled sub-image model. For each EMITTED quad k (already keyed tiling-safe by its own (gfx1,sel)), the engine carves the GFX1 part into tilecnt sub-tiles of m x m (m = tiledesc byte0 @ 0x8C1F9F9C+(dc+k)*4; the tile s grid position within the part comes from the descriptor byte2 / the per-tile record), TWIDDLES each m x m PAL4 sub-tile into the fixed 32x32 (rectab-TSP texU/texV) VRAM texture-tile order, and writes it at that quad s OWN TCW with the quad s UV sub-rect = m/32 (render_frame already emits q->u1 = m/tile). i.e. the decode unit is the m x m tile (twiddled to the 32x32 storage layout the renderer samples), NOT the sw*8 x sh*8 whole part. Verify by re-running repro_scramble.mjs and confirming _probe_dims.mjs DIM-MISMATCH drops to 0 and the PNG renders a coherent character. (Defer the exact twiddle / tile-grid sub-addressing to mvc2-sh4-re-expert: it is the loc_8c033d78 load-time decoder + loc_8c0354c0 LZSS output placement into the 32x32 PVR PAL4_TW tile, the SAME path the engine DMAs at load — the offline decode must match THAT storage order per m x m tile.)',
  status='proposed', confidence='high', date='2026-06-13';

-- ---- CONFIRMED FIX (2026-06-13): the per-tile placement model, PROVEN vs resident VRAM --------
-- The PROPOSED fix above HYPOTHESIZED per-tile m x m twiddled sub-images. The disassembly +
-- resident-VRAM byte-check REFUTE that and CONFIRM a simpler model: the part is stored ONCE,
-- CONTIGUOUS, and a tiled cell's N quads index INTO that one blob at +0x200 (512B = one 32x32
-- PAL4 tile) offsets. The fix is therefore "write each part ONCE at its base", NOT per-tile decode.
UPSERT routine:loc_8c033d78 SET label='loc_8c033d78', pc='0x8C033D78', bank='bank03',
  role='LOAD-TIME body-sprite sheet decoder driver — CONFIRMS whole-part contiguous VRAM storage',
  note='Re-traced (bank03.asm:9092-9409) for the tiling question. Per GFX2 cell sel (@r13+6): part = GFX1 + GFX1[sel*4]; reads part[+2]=sw, part[+3]=sh; r9 = (sw*8 * sh*8) >> 1 = destLen (PAL4); jsr loc_8c0354c0 (LZSS) with r6 = running dest (base 0x0CE60000), then r8 += r9 (advance dest CONTIGUOUSLY, NO per-tile gap), r14 += 0x10 (next OAM record). After ALL parts decoded into 0x0CE60000 as ONE contiguous LINEAR blob, ONE bulk DMA loc_8c1240a0 uploads it VERBATIM to VRAM (loc_8c033f14, r4=(texaddr<<8)+0x0390). => the engine decodes each WHOLE part contiguously and there is NO per-m x m-tile twiddle at load time. The per-frame walker loc_8c0344d4 then renders a TILED cell as N quads whose TCWs STEP +0x200 across that ONE contiguous part blob (each a 32x32 PAL4_TW sub-window of the part), each with a FIXED 32x32 TSP.';

UPSERT finding:render_replica_scramble_fix SET
  statement='CONFIRMED FIX (client web/render-replica/body_decoder.mjs ensureBodyTextures only; render_frame.wasm + geometry UNCHANGED). The proposed per-tile m x m twiddle was REFUTED; the engine stores each GFX1 part ONCE, CONTIGUOUS, in VRAM (decodeA output VERBATIM, byte-exact — re-confirms finding:gfx1_decode_equals_vram), and a tiled cell emits N quads whose TCWs STEP +0x200 (=512B = one 32x32 PAL4 tile) INTO that same whole-part blob, each quad a 32x32 PAL4_TW sub-window (fixed 32x32 TSP). GROUND TRUTH = loc_8c033d78 (decodes whole parts to 0x0CE60000 contiguously, bulk-DMAs VERBATIM, NO per-tile twiddle) + the resident VRAM of _scramble_actual.mcrr. THE BUG: the old code wrote the whole-part blob at EACH quad OWN TCW, so a 2048B part was re-written at 0x415400 AND +0x200 AND +0x400 AND +0x600 -> self-overwrite smear (each later write shifts the part +512B over the prior) = the scramble. THE FIX: group emitted quads by (gfx1,sel), compute each run PART-BASE = MIN tile TCW vaddr, decode the part ONCE and write it ONCE at that base; the other tiles index into the blob and are NOT re-written. PROOFS (all tools-verified): (1) resident-pose render (PL17 sid 0xd4) through the FIXED decoder into a fresh client VRAM == engine resident VRAM 4/4 parts, 2688/2688 bytes byte-exact (sel1264 64x64 2048B @ 0x415400 spans 4 tiles 0x415400/600/800/a00 = exactly the 2048B part; sels 1267/1265/1266 likewise). (2) repro_scramble.mjs frame0 over _scramble_actual.mcrr: BEFORE = scramble (right body a smear of repeated fragments, 7436 nonblack px); AFTER = a COHERENT character (clean head/arm/torso/legs, 15163 nonblack px); PL34 left body renders coherent fragments (it is mostly OFF-SCREEN at frame0, screenX 139..-72, not scrambled). (3) validate_sel_pairing.mjs (corrected to the tile-slice model: VRAM[tile TCW]==decode(sel)[tileTCW - runBase]) = 49 OK, 0 BAD, RESULT PASS; STRUCTURAL sel-runs==cellSels PASS. (4) render_frame_test.exe regression PCW/ISP/TSP/TCW 9/9 byte-exact, cursor proof OK, RESULT PASS (geometry untouched). NOTE: _probe_dims.mjs DIM-MISMATCH (GFX1 storage span vs the fixed 32x32 TSP) is INHERENT to the engine model (TSP is ALWAYS 32x32; a part is tiled into 32x32 windows) and is NOT a bug metric — superseded by the resident-VRAM byte-check. Branch feat/render-replica-live.',
  status='confirmed', confidence='high', date='2026-06-13';

RELATE finding:render_replica_scramble_fix->cites->routine:loc_8c033d78;
RELATE finding:render_replica_scramble_fix->cites->routine:loc_8c0344d4;
RELATE finding:render_replica_scramble_fix->cites->routine:loc_8c0354c0;
RELATE finding:render_replica_scramble_fix->cites->source:scramble_actual_mcrr;
RELATE finding:render_replica_local_gfx_overlay->cites->source:local_gfx_overlay_mjs;
RELATE finding:render_replica_local_gfx_overlay->cites->source:extract_replica_gfx;
RELATE finding:render_replica_local_gfx_overlay->cites->source:scramble_actual_mcrr;
RELATE finding:render_replica_scramble_is_nongfx->cites->source:scramble_actual_mcrr;
RELATE finding:render_replica_scramble_is_nongfx->cites->source:repro_scramble_mjs;
RELATE finding:render_replica_scramble_is_nongfx->cites->source:local_gfx_overlay_mjs;
RELATE finding:render_replica_scramble_fix->cites->source:repro_scramble_mjs;
