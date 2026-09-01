USE NS re DB kb;

-- ============================================================================
-- 2026-07-10 — the TEXEL twin of re_kb/68: the native-chunk carve for dense
-- wide parts must be COLUMN-PAIR-MAJOR (bodytex=local Sentinel swap CLOSED).
-- ============================================================================

UPSERT source:zz_realblob_gate SET kind='measurement',
  ref='tools/render-replica-poc/_zz_realblob_gate.mjs (node _zz_realblob_gate.mjs band4.mcrr 34 60); real Sentinel gfx1 blob, production Y-first detwiddlePal4 readback',
  note='Byte-gate of the body_decoder native-chunk carve vs the engine VRAM chunk order for a DENSE 4x4 part (Sentinel sel124/sel112 128x128, all 16 tiles nonzero): row-band-major k=by*Tw+col*bh+(row-by) = 232/464 bad (exactly 50% = the off-diagonal 2x2-block swap); column-pair-major (colPairChunk == rebuild_tile_grid emit order) = 0/464 bad. Also 8x4: row-band 8/32 bad, col-pair 32/32 clean. Prior _live4 sel 0xD61 "row-band validated vs engine" had only 9/16 nonzero tiles -> the swapped off-diagonal (zero) blocks could not distinguish the two orders; the dense part is the discriminating test.';

UPSERT finding:texel_carve_colpair_major SET
  statement='CONFIRMED + FIXED 2026-07-10. The native-chunk texel carve (m==32 && cols>1 && rows>1: copy the engine\'s full-WxH twiddle blob\'s 32x32 chunks to per-tile VRAM addrs) must index the blob COLUMN-PAIR-MAJOR — the same order render_frame rebuild_tile_grid (widecarve1, re_kb/68) emits geometry/TCW slots. widecarve1 fixed the GEOMETRY twin (quad positions) but left the TEXEL carve at row-band-major, breaking geometry<->texel lockstep: on bodytex=local every dense >2x>2 part (Sentinel sel124/112) had its off-diagonal 2x2 tile-blocks swapped (re_kb/68 "swapped diagonally" on the texel side). The default TCW->TextureManager path was immune (each quad textures from its own TCW->engine VRAM). FIX: body_decoder.mjs colPairChunk(col,row,Tw,Th) replaces k=by*Tw+col*bh+(row-by). Byte-gate 0/464 (was 232/464). No regression: identical to row-band for Tw<=2 OR Th<=2 (all satellites + normal bodies, verified over 1x1..8x8). DEPLOYED browser: body_decoder.mjs ?v=scene8. C++ TWINS updated source-only (need native rebuild): maplecast_mirror.cpp gstaDecodeBodies + texel_gate.cpp decodeBodies. Supersedes the row-band-major claim in those files\' comments (the _live4 witness was sparse). re_kb/68 geometry twin: finding:wide_part_colpair_order.',
  status='confirmed', confidence='high', date='2026-07-10';

RELATE finding:texel_carve_colpair_major->cites->source:zz_realblob_gate;
RELATE finding:texel_carve_colpair_major->about->finding:wide_part_colpair_order;

-- Storm cape: texel carve is byte-CLEAN in every captured pose — the residual is NOT here.
UPSERT finding:storm_cape_texel_clean SET
  statement='OPEN (not a texel-carve bug). On bodytex=local the ensureBodyTextures carve for Storm\'s cape is byte-CLEAN: the cape = 3 satellite objects (nodes 26afc4/26adf4 cat=4 + a cat=3) all sharing Storm\'s own gfx1 c420040 (resolves fine), decomposing to ALL LINEAR-path parts (32x64 1x2, 64x16 4x1, ...) — ZERO 4x4+ native parts, so the re_kb/70 fix does not touch it. MEASURED (band/band2.mcrr, actual-carve Y-first readback, live-path srcdesc/mask): 0 quads skipped (all mask=1), 232/232 + 304/304 tiles byte-clean vs whole-part detwiddle truth. So the "cape renders wrong" symptom is NON-texel: render_frame satellite geometry/anchor, palette selection, draw-time texU mirror, or z-order/blend — OR an uncaptured pose (typhoon multi-instance sel 0xDEC=3564; band/band2 top out at sel 3017). Needs a Storm-cape-with-engine-VRAM capture (capture_break + re-arm ASMTRACE) to isolate; NOT a fabricated texel fix.',
  status='open', confidence='high', date='2026-07-10';

RELATE finding:storm_cape_texel_clean->cites->source:zz_realblob_gate;

-- ============================================================================
-- 2026-07-10 CORRECTION (roster-wide byte-gate, _zz_roster_carve_gate.mjs, all
-- 59 GFX1 bins): colPairChunk is NOT universal. The correct universal key is
-- twTileYFirst (whole-part Y-first tile-twiddle). This SUPERSEDES the above.
-- ============================================================================

UPSERT source:zz_roster_carve_gate SET kind='measurement',
  ref='tools/render-replica-poc/_zz_roster_carve_gate.mjs (all PL00..PL3A GFX1, whole-part Y-first detwiddle ground truth); _zz_carve_detail.mjs per-tile',
  note='1230 dense >2x2 parts / 21312 tiles gated, 0 UNGATED. colPairChunk bad=608 (every 4x8 128x256 = 16 tiles + the one 8x8 256x256 = 32 tiles, across 13 chars: Juggernaut, Abyss1, Sentinel sel570/790/1151/1161/1167, Venom, Felicia 8x8, Morrigan, Strider, Hulk, Hayato, SonSon, Amingo, Spiral, Blackheart). row-band bad=10868 (~51%). twTileYFirst bad=0 for EVERY shape. colPair==twTileYFirst only for 4x4 & 8x4 (where re_kb/68/70 were validated -> indistinguishable). 4 chars have NO dense parts (Chun-Li, Akuma, Charlie, Dan).';

UPSERT finding:texel_carve_colpair_major SET
  statement='CORRECTED + RESOLVED 2026-07-10. The native-chunk texel carve key is twTileYFirst (whole-part Y-FIRST tile-twiddle), NOT colPairChunk. The engine stores each >2x2 part as ONE verbatim WxH PVR-twiddle blob (shape-agnostic DMA loc_8c033d78), so tile (col,row)\'s 512B chunk = twTileYFirst(col,row). colPairChunk is the DESCRIPTOR/screen-position emit order (re_kb/68, correct for GEOMETRY) and COINCIDES with twTileYFirst only for 4x4 & 8x4 — it was accepted on 4x4-only evidence. Roster byte-gate MEASURED colPairChunk WRONG on all 4x8 (128x256) + the 8x8 (256x256): 608 bad tiles / 37 parts / 13 chars, incl Sentinel\'s ROCKET-PUNCH arm (sel570/790/1151/1161/1167, 4x8) = the user-reported "arm tiles not diagonal". twTileYFirst = 0 bad, all shapes; zero-regression superset (== colPair for Tw<=4&&Th<=4, only 4x8/8x8 change). FIXED: body_decoder.mjs ensureBodyTextures uses twTileYFirst (DEPLOYED ?v=scene9); C++ twins maplecast_mirror.cpp gstaDecodeBodies + texel_gate.cpp source-only (need native rebuild). OPEN caveat (INFERRED->needs SH4 confirm): ground truth is the whole-part detwiddle (DMA-verbatim thesis, proven on non-dense + shape-agnostic DMA); the engine\'s actual per-tile TCW order for a live 4x8/8x8 pose was never DIRECTLY read (only 4x4). Definitive close = capture_break + ASMTRACE (PC 0x8C034864) TCW read on a live rocket-punch (4x8) pose vs engine VRAM (mvc2-sh4-re-expert). re_kb/68 geometry twin (wide_part_colpair_order) shares the 4x4-only validation — its emit ORDER is ASMTRACE-confirmed for screen positions, distinct from the texel twiddle key.',
  status='confirmed', confidence='high', date='2026-07-10';

RELATE finding:texel_carve_colpair_major->cites->source:zz_roster_carve_gate;

-- 2026-07-10 — CAVEAT CLOSED: engine ground-truth confirmation (ASMTRACE, live 4x8 pose).
UPSERT source:asmtrace_rocket_4x8 SET kind='oracle',
  ref='rocket.mcrr (Sentinel LP rocket punch, vframe 27908-29707) + ASMTRACE PC 0x8C034864 sel790 (128x256 4x8 arm, 32 tiles); _tx per-tile emit-order derivation',
  note='The engine emit order (r13-ascending descriptor slots -> per-tile screenX/screenY) for the live 4x8 rocket-arm part MATCHES twTileYFirst EXACTLY and NOT colPairChunk: over 32 tiles engine==twTileYFirst true, engine==colPairChunk false (first 8 slots identical -> why 4x4 could not distinguish them). Definitive engine arbitration of the whole-part twiddle key, no thesis. Also fixed Storm HK tornado (another 4x8+ part) with the same scene9 -> universality demonstrated across 2 chars/2 moves.';
UPSERT finding:texel_carve_colpair_major SET
  statement='CONFIRMED (engine ground-truth) 2026-07-10. twTileYFirst is the native-chunk carve key. ENGINE-ARBITRATED: ASMTRACE on a live Sentinel 4x8 rocket-punch pose (sel790) shows the engine emit order == twTileYFirst, != colPairChunk (the prior caveat is CLOSED — no longer thesis-only). Universal, not per-character: ONE fix (body_decoder ?v=scene9) simultaneously corrected Sentinel rocket punch AND Storm HK tornado (both 4x8+ parts); roster gate 0 bad / 21312 tiles / 59 chars. colPairChunk (re_kb original) coincides with twTileYFirst only on 4x4 & 8x4. render_frame geometry emit order is ALSO twTileYFirst-consistent (same ASMTRACE, screen positions). body_decoder.mjs uses twTileYFirst (DEPLOYED); C++ twins gstaTwTileYFirst source-only (native rebuild pending).',
  status='confirmed', confidence='high', date='2026-07-10';
RELATE finding:texel_carve_colpair_major->cites->source:asmtrace_rocket_4x8;
