-- ============================================================================
-- 28_faithful_texture_decode_transpile.surql
-- 2026-06-14 — COMPLETE THE TRANSPILE: the texture decode is now a FAITHFUL
-- instruction-by-instruction transpile of the engine decode path, replacing the
-- hand-MODELED wide-part carve in web/render-replica/body_decoder.mjs. A faithful
-- transpile is correct BY CONSTRUCTION (the disasm IS the decode), the same way
-- render_frame's geometry is 0.00px. Supersedes the carve/storage-order findings.
--
-- CITE: loc_8c033d78 (part-decode driver), loc_8c0354c0 (LZSS), loc_8c1240a0/
-- loc_8c123e00 (verbatim VRAM DMA), flycast texconv.cpp texture_TW/ConvertTwiddlePal4.
--
-- Apply AFTER 21_wide_part_tile_storage_order.surql, then run 07_dedup_edges.surql.
-- ============================================================================
USE NS re DB kb;

-- ---- 1. the faithful LZSS transpile (engine-validated byte-exact) -----------
UPSERT finding:faithful_lzss_transpile SET date='2026-06-14', confidence='high', status='confirmed',
  note='THE GFX1 PART LZSS DECODE IS A FAITHFUL TRANSPILE OF loc_8c0354c0 (read instruction-by-instruction from marvelous2 bank03:12661). Register contract: r4=src=part_base+4, r5=destLen, r6=dest_base, r9=r5+r6=dest_end (loop terminates when r6>=r9 via cmp/hs). Flag byte consumed MSB-first from 0x80 (mov.w 0x0080 -> r10; tst r7,r7 reload; shar r7 advance). bit CLEAR (tst r7,r11 == 0 -> loc_8c03550e) = LITERAL *dest++=*src++. bit SET = BACK-REF: b=*src++; r0=b&0x0F=n (and r12=0x0F); r14=b>>4=dist (two shlr2); src=r6-dist-1 (sub then add 0xFF); copy n+2 bytes total (1 initial @loc_8c0354dc + loop loc_8c0354fe runs n+1 times: tst-r0 is checked AFTER the byte write, bf.s loops while r0!=0, delay add 0xFF decrements). Output buffer IS the back-ref window, self-contained per part (no ring, no dictionary, no cross-part scratch carry). PROVEN BYTE-EXACT vs the ENGINE`S OWN decode output captured live (_ryu_capture/PL00_raw_{0001,0013,0024,0034,0061,0127}.bin) for square, WIDE (sel24 128x32), and TALL (sel1/13/34/127 16..64 x 128) parts: 6/6 diff=0. Same decoder over all 1533 Ryu sels (tools/extract_gfx1_atlas.py): 1.93M px, 0 fail. NOTE: validate from the DISC GFX1 (PLxx_DAT_GFX_DATA_00.BIN) or the in-RAM gfx1 base node+0x15C indexed by gfx1+sel*4 -- the in-RAM PLDAT is RELOCATED/RE-PACKED at load (RAM@0xc420040 != disc gfx1, 9/428 sampled bytes match), so part offsets differ; decode is byte-exact when the part stream is bounded correctly. PORT: web/render-replica/body_decoder.mjs decodeA() (==tools/extract_gfx1_atlas.py decodeA). CITE: loc_8c0354c0, loc_8c033d78.';

-- ---- 2. the verbatim contiguous VRAM storage (no carve) ---------------------
UPSERT finding:faithful_verbatim_vram_write SET date='2026-06-14', confidence='high', status='confirmed',
  note='THE FAITHFUL CLIENT TEXTURE OP = WRITE THE LZSS OUTPUT VERBATIM AT THE PART-BASE VRAM ADDR (NO carve/detwiddle/re-twiddle). Traced from loc_8c033d78: the driver LZSS-decodes each (gfx1,sel) part CONTIGUOUSLY into scratch 0x0CE60000 (advances dest ptr r8 by destLen=(sw*8)*(sh*8)/2 per part; the decode does NO twiddle and NO tile reorder), then DMAs the scratch to VRAM VERBATIM (loc_8c1240a0/loc_8c123e00 assign each part ONE base texaddr from the 0x3C-stride rectab and copy the bytes AS-IS). So a part lives in VRAM as ONE CONTIGUOUS full-WxH PVR-twiddle blob == exactly decodeA()`s output. The per-frame walker (loc_8c0344d4, reproduced 0.00px by render_frame) emits N tiles whose TCW vaddrs step by one tile chunk INTO that one blob; the renderer (web/webgpu/texture-manager.mjs getTexture/_pal4) reads each tile`s declared w x h twiddle (w=8<<texU, h=8<<texV from the TSP; addr=(tcw&0x1FFFFF)<<3; twop over w x h) -- byte-for-byte flycast texconv.cpp texture_TW / ConvertTwiddlePal4. ==> the client writes decodeA() output ONCE at the part-base (= the MINIMUM tile TCW vaddr of the (gfx1,sel) run); every emitted quad`s TCW already indexes the right chunk; the renderer reads it at its TSP dims. NO carve needed -- the chunk->screen-cell PERMUTATION is the ENGINE`s (the walker`s per-tile TCW pairing), already reproduced 0.00px by render_frame, so verbatim-write makes every tile read the right chunk FOR FREE. PROVEN OFFLINE (disc GFX1, flycast-exact twop): every (min(W,32) x min(H,32))-tile chunk of the contiguous blob, read as its own twiddle, EXACTLY equals the screen cell of the full-WxH twiddle -- Ryu sel1 32x128 4/4, sel13 64x128 8/8, sel24 128x32 4/4, sel34/127 16x128 4/4; Sentinel sel124 128x128 16/16, sel121 128x16 4/4, sel112 128x128 16/16, sel125 64x16 2/2; Magneto sel285 64x128 8/8, sel213 32x32 1/1; Cable 64x128 parts 8/8. CITE: loc_8c033d78, loc_8c0354c0, loc_8c1240a0, loc_8c123e00, texconv.cpp texture_TW.';

-- ---- 3. SUPERSEDE the hand-modeled carve -----------------------------------
UPSERT finding:faithful_texture_decode_transpile SET date='2026-06-14', confidence='high', status='confirmed',
  contribution_candidate=true,
  note='SUPERSEDES finding:wide_part_tile_storage_order / _v2 / wide_part_walker_tile_order. Those modeled the wide-part as: de-twiddle the whole part (with min(W,H) SQUARE blocks) into a row-major image, then RE-twiddle each tile into a fresh 32x32 LOCAL-twiddle tile at a SCREEN-RANK-derived (col,row), and write per-tile. That was a HAND MODEL validated vs a RECONSTRUCTED full-WxH-twiddle MODEL (the headless prod is norend -> VRAM is never populated; every resident-VRAM byte-check came back vramNZ=0 or non-coherent), NEVER vs the engine. It mis-ordered tiles under opposite facing / repeated tiles (the user`s live "carve-OFF is CLOSER for Cable-on-P2" symptom -- carve-off falls through to the verbatim write, which IS the faithful path). THE FAITHFUL TRANSPILE (this finding) removes the carve entirely: ensureBodyTextures now groups emitted quads by (gfx1,sel), finds each run`s part-base = min tile TCW vaddr, decodes the part ONCE via decodeA (engine-byte-exact LZSS), and writes the VERBATIM blob ONCE at the part-base. quadColRow/opts are accepted for call-site compatibility but UNUSED (the carve they fed is gone). render_frame.c geometry is UNTOUCHED (still 0.00px). NO wasm rebuild (body_decoder is pure JS; render_frame.wasm unchanged). VALIDATION GAP NOTE: a resident-VRAM byte-check vs a FULL-RENDER (non-norend) engine was NOT capturable (headless VRAM empty; mcrr/coherent dumps non-resident for the rendered sels), so the proof is (a) decodeA byte-exact vs the engine`s LIVE .raw decode output 6/6, and (b) the verbatim-blob chunks are provably valid per-tile twiddle cells for every shape across 4 chars incl all user-flagged wide parts. PORT: web/render-replica/body_decoder.mjs ensureBodyTextures (carve/detwiddleImage/carveTile/twiddleSlow REMOVED); replay.html import ?v=faithful-transpile, deployed prod 149.28.44.118 /var/www/maplecast/render-replica/ (md5 body_decoder b783ff2d, replay d18cff32). Branch feat/render-replica-live. CITE: loc_8c033d78, loc_8c0354c0.';

RELATE finding:faithful_texture_decode_transpile->about->finding:wide_part_tile_storage_order SET kind='supersedes';
RELATE finding:faithful_texture_decode_transpile->about->finding:wide_part_tile_storage_order_v2 SET kind='supersedes';
RELATE finding:faithful_texture_decode_transpile->about->finding:wide_part_walker_tile_order SET kind='about';
RELATE finding:faithful_texture_decode_transpile->about->finding:faithful_lzss_transpile SET kind='about';
RELATE finding:faithful_texture_decode_transpile->about->finding:faithful_verbatim_vram_write SET kind='about';
RELATE finding:faithful_texture_decode_transpile->cites->routine:loc_8c033d78 SET kind='cites';
RELATE finding:faithful_texture_decode_transpile->cites->routine:loc_8c0354c0 SET kind='cites';
RELATE finding:faithful_lzss_transpile->cites->routine:loc_8c0354c0 SET kind='cites';
RELATE finding:faithful_verbatim_vram_write->cites->routine:loc_8c033d78 SET kind='cites';

-- ---- mark the superseded findings ------------------------------------------
UPDATE finding:wide_part_tile_storage_order SET
  note=note + ' [SUPERSEDED 2026-06-14 by finding:faithful_texture_decode_transpile: the carve was a HAND MODEL validated vs a reconstructed twiddle model, never the engine, and mis-ordered tiles (Cable-P2 carve-off-is-closer). The faithful transpile writes the LZSS output VERBATIM at the part-base (loc_8c033d78 contiguous DMA); NO carve.]';
UPDATE finding:wide_part_tile_storage_order_v2 SET
  note=note + ' [SUPERSEDED 2026-06-14 by finding:faithful_texture_decode_transpile.]';

-- ---- the tools that proved it (reproducible) -------------------------------
UPSERT tool:engine_byte_check CONTENT {
  kind:'tool',
  ref:'tools/render-replica-poc/_engine_byte_check.mjs + _validate_faithful.mjs (and inline python over the disc GFX1)',
  note:'Faithful-decode validators: (1) decodeA vs the engine LIVE .raw decode (_ryu_capture/PL00_raw_*.bin) -> 6/6 byte-exact for square/wide/tall. (2) verbatim-blob chunk -> standalone tw x th twiddle == screen cell, across Ryu/Sentinel/Magneto/Cable incl sel124/121/112/285 and all 64x128 Cable parts. Establishes the faithful path is correct by construction; documents that headless VRAM is never resident for an in-engine byte-check (norend).'
};
-- ============================================================================
