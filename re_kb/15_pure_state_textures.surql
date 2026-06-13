-- ============================================================================
-- 15_pure_state_textures.surql
-- PHASE 5 — PURE-STATE TEXTURES (2026-06-13). The render-replica-live wire is
-- returned to STATE-ONLY: the CLIENT reconstructs each active body part's sprite
-- TEXTURE from the shipped-once compressed GFX (PLxx_DAT GFX1/GFX2) + the live
-- sprite_id, instead of streaming a decoded-pixel VRAM band. This file seeds:
--   * the load-time decoder driver routine loc_8c033d78 (traced),
--   * the byte-exact-vs-VRAM proof (decodeA output == engine VRAM, VERBATIM),
--   * the client decoder + wire-removal finding,
--   * about/cites edges.
-- Apply AFTER 06_findings_sources.surql + 08_emitter_render_model.surql,
-- then run 07_dedup_edges.surql.
-- ============================================================================
USE NS re DB kb;

-- ---- the LOAD-TIME body-sheet decoder driver (now fully traced) -------------
UPSERT routine:loc_8c033d78 SET label='loc_8c033d78', pc='0x8C033D78', bank='bank03',
  role='LOAD-TIME body-sprite sheet decoder driver (per char, once at match load)',
  note='Called from the load loop loc_8c03dd6c (r14=0..5 chars; r13 = 0x8c268340 + r14*0x05a4; jsr with r4=char struct) — ONCE per char at match LOAD, NOT per animation frame. Walks the per-char sprite/anim index table at *(char+0x180) (u16 sprite_id list), and for each referenced part: GFX1=*(char+0x15C); partBase = GFX1 + *(u32)(GFX1 + sel*4); reads header [lw][lh][sw][sh]; dest_len = (sw*8)*(sh*8) >> 1 (PAL4, shar r9 = /2); jsr loc_8c0354c0 (the LZSS decoder) with r4=partBase+4, r5=dest_len, r6=running dest (base 0x0CE60000); then bank12.loc_8c1240a0 DMAs 0x0CE60000 -> VRAM at TCW addr (r4=(texaddr<<8)+0x0390, r5=*(r15+0x30)). LINEAR decode output is uploaded VERBATIM (twiddled STORAGE order == the LZSS output). Per-sel side tables: 0x8c26aa24[sel]=u16, 0x8c26aa34[sel]=u32. This is the LOAD-TIME path; the per-frame body PLACEMENT is loc_8c0344d4 (which consumes these already-decoded VRAM pixels and calls NO decoder).';

-- ---- the LZSS decoder itself (re-assert, now client-ported) -----------------
UPSERT routine:loc_8c0354c0 SET label='loc_8c0354c0', pc='0x8C0354C0', bank='bank03',
  role='GFX1 LZSS part decoder (the body/effect sprite codec)',
  note='Byte-oriented LZSS. r4=src(part+4), r5=dest_len, r6=dest, r9=r5+r6=end. Flag byte loaded MSB-first when the 0x80-countdown (r7/r10) hits 0. bit CLEAR -> literal (*dst++=*src++); bit SET -> b=*src++, dist=b>>4, count=(b&0x0F)+2 copied from dst-(dist+1) (output buffer IS the window). Verified line-for-line == extract_gfx1_atlas.py decodeA == web/render-replica/body_decoder.mjs decodeA. Output is bit-exact vs the live decode buffer 0x0CE60000 AND, written VERBATIM to VRAM, == the engine decoded VRAM byte-exact.';

-- ---- THE BYTE-EXACT PROOF (decodeA == engine VRAM) --------------------------
UPSERT finding:gfx1_decode_equals_vram SET date='2026-06-13', confidence='high', status='confirmed',
  note='decodeA(GFX1[sel]) written VERBATIM (no detwiddle) == the engine''s decoded VRAM byte-exact. VRAM stores PVR PAL4_TW in TWIDDLED order, which IS the LZSS output order (so NO twiddle step on the client; flycast texPAL4_TW reads it back). Per-part VRAM addr = TCW: byteAddr=(TCW & 0x1FFFFF)<<3 (fmt5). PROOF (vs _ryu_capture/mc_ram_dump.bin + mc_vram_dump.bin, frame-coherent): (1) the RAM-resident GFX1 @0xC420040 is BYTE-IDENTICAL to the disc PL34_DAT_GFX_DATA_00.BIN -> client has the exact asset. (2) Cable (char23, P2C1, sid 0xd4) cell sels [1264,1267,1265,1266] decoded -> VRAM @ [0x415400,0x415c00,0x416000,0x416200] = 4/4 byte-exact (FULL pose, frame-coherent). (3) 110 rectab-TCW-referenced resident parts -> 110 byte-exact, 0 mismatch; 151 total resident parts all byte-exact. (4) The shipped JS decoder web/render-replica/body_decoder.mjs reproduces (2) 4/4 under node. GFX2 cell + TA quad ordering: the per-frame body walker emits ONE TA quad per cell record IN ORDER, so TA-quad TCW order == cell-sel order per char (verified vs mc_render_rec_gt.bin) -> the client pairs sel[i]<->quad-TCW[i] search-free.';

-- ---- the client decoder + wire-removal -------------------------------------
UPSERT finding:pure_state_textures SET date='2026-06-13', confidence='high', status='confirmed',
  note='PHASE 5: render-replica-live wire returned to STATE-ONLY. REMOVED the per-frame bodytex VRAM band (server D(0x410000,0x50000) + captureFrame vram copy; client pane.vram routing) — it streamed ~320KB/frame of decoded pixels, off-thesis. KEPT the tiledesc(0x1800) + rectab(0x10000) enlargements (legit state; rectab is 93%-utilized on a 2-body frame so 0x10000 is needed, NOT truncation). The CLIENT now decodes body textures: web/render-replica/body_decoder.mjs ensureBodyTextures(ram,vram,ta,quadCount,cache) walks active chars (slot order), resolves each sprite_id''s GFX2 cell -> sels, decodes each via decodeA (loc_8c0354c0 port) VERBATIM, and writes to pane.vram at the TCW addr read from render_frame''s emitted TA (byte-exact TCW per test_ta_emit.c). DECODE-ON-CHANGE: cached by slot|sprite_id (static poses cost ZERO; a pose decode is 4-19 parts, sub-ms in JS). WIRE: raw dynamic payload 93KB -> zstd L1 11.9KB/frame (state only) on the real dump; ~27x below the ~330KB/frame the shortcut shipped. (The ~7KB target corresponds to the older 0x8000 rectab, which truncated busy frames; 0x10000 is the correct/safe size at 11.9KB.) Wired into replay.html showFrame + liveApplyFrame before pane.render.';

-- ---- tool ------------------------------------------------------------------
UPSERT tool:body_decoder_mjs SET kind='client body-sprite decoder', path='web/render-replica/body_decoder.mjs',
  date='2026-06-13',
  note='Client-side JS port of the GFX1 LZSS decoder (loc_8c0354c0) + GFX2 cell walk. ensureBodyTextures(ram,vram,ta,quadCount,cache): decode-on-sprite_id-change, writes decoded parts VERBATIM to pane.vram at the TCW addresses render_frame''s TA carries. Byte-exact vs engine VRAM (node parity gate 4/4 on Cable). Replaces the per-frame bodytex pixel band.';

-- ---- edges -----------------------------------------------------------------
RELATE finding:gfx1_decode_equals_vram->cites->routine:loc_8c0354c0 SET kind='cites';
RELATE finding:gfx1_decode_equals_vram->cites->routine:loc_8c033d78 SET kind='cites';
RELATE finding:pure_state_textures->cites->routine:loc_8c0354c0 SET kind='cites';
RELATE finding:pure_state_textures->cites->routine:loc_8c0344d4 SET kind='cites';
RELATE finding:pure_state_textures->about->tool:body_decoder_mjs SET kind='about';
RELATE finding:pure_state_textures->about->finding:gfx1_decode_equals_vram SET kind='about';
