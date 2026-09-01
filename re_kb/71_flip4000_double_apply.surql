USE NS re DB kb;

-- ============================================================================
-- 2026-07-10 — Storm Lightning-Strike "flipped/mirrored/wrong-spot" body =
-- the per-record 0x4000 flip applied TWICE (draw-time texU mirror + a spurious
-- storage-column reversal in the native carve). Confirms re_kb/24.
-- ============================================================================

UPSERT source:storm_native_gate SET kind='measurement',
  ref='tools/render-replica-poc/_storm_native_gate.mjs (runs the REAL production ensureBodyTextures w/ quadMirror+quadSrcDesc, per-tile byte-compare vs engine verbatim-DMA VRAM); torture.mcrr Storm cid42 + rocket.mcrr; _storm_ls_dump.mjs per-tile structure',
  note='Lightning Strike (re_kb/63 Lightning Attack) plays as pre-drawn sprite frames sid 0x1ea->0x1eb->0x1f0->0x1f1 at BOTH facings — ALL quads axis-aligned (0 rotated/sheared), so the perceived ~90deg upright->flying "rotation" is pre-drawn art, NOT a transform. Flying-pose sid0x1f1 uses native part sel0x35d 64x64 (2x2) with per-record 0x4000 SET (srcdesc fl=3). Pre-fix: sel0x35d fac1 52/52 WRONG, fac0 48/48 WRONG. Post-fix: 52/52 + 48/48 EXACT vs engine VRAM. No regression: 100+ non-flip native parts unchanged; every flip4000 native part across the roster (sel0xdcc/dcf/dd7/ddc-4x4/de0/de6/df2/dfc) CUR-BAD->fix-ok, 0 cur-ok->FIX-BAD.';

UPSERT finding:flip4000_double_apply_carve SET
  statement='CONFIRMED + FIXED 2026-07-10. The per-record GFX2 flag 0x4000 is a DRAW-TIME texU mirror ONLY (loc_8c0346c4 neg-r8 texture-U flip; facing XOR 0x4000), NEVER a storage re-store — per re_kb/24 (per_side_storage_col_reverses) storage is facing-INDEPENDENT. The bodytex=local native-chunk carve (body_decoder.mjs ensureBodyTextures) applied 0x4000 TWICE: once correctly as render_frame_quad_mirror (the texU flip), and again WRONGLY as a storage-column reversal col=(dfl&2)?(pCols-1-cc):cc feeding twTileYFirst(col,...). For flip4000 native parts this swapped the tile columns [2,3,0,1] -> tiles land mirrored/wrong-spot. VISIBLE on Storm Lightning-Strike flying pose (sel0x35d 64x64 flip4000); the geometry gate (_tx_detect, positions only) was BLIND to it because quad positions were engine-clean — only the per-tile CONTENT/orientation was wrong. FIX: on the native (m=32 twiddle-chunk) path use the RAW storage column (ncol = dcx % pCols; no 0x4000 reversal); the reversed col stays for the LINEAR (sub-32 satellite) path (untouched — TEXFIX2 reversal there is unvalidated, re_kb/24 says likely spurious too but not gated). DEPLOYED browser body_decoder.mjs ?v=scene10. C++ twins maplecast_mirror.cpp gstaDecodeBodies + texel_gate.cpp source-only (need native rebuild). SEPARATE pre-existing gap (NOT this fix): sid0x61 sel0x316 128x256 4x8 flip4000=n multi-instance = 32/64 WRONG before AND after (distinct non-flip 4x8/multi-instance carve gap, OPEN).',
  status='confirmed', confidence='high', date='2026-07-10';

RELATE finding:flip4000_double_apply_carve->cites->source:storm_native_gate;

UPSERT finding:multiinstance_4x8_carve_gap SET
  statement='OPEN (2026-07-10, surfaced by _storm_native_gate). sid0x61 sel0x316 128x256 (4x8, flip4000=n, MULTI-INSTANCE) decodes 32/64 tiles WRONG identically before AND after the flip4000 fix — a DISTINCT native-chunk carve gap for non-flip 4x8/multi-instance parts (2+ satellite nodes drawing the same (gfx1,sel) collapse the rank grid / the twTileYFirst chunk key needs the per-instance disambiguation). Unrelated to the flip4000 double-apply. Needs its own capture + gate.',
  status='open', confidence='medium', date='2026-07-10';

RELATE finding:multiinstance_4x8_carve_gap->cites->source:storm_native_gate;

-- 2026-07-10 — the LINEAR twin, found by the WHOLE-CATALOG gate (192032 parts / 59 chars).
UPSERT source:catalog_carve_gate SET kind='measurement',
  ref='tools/render-replica-poc/_zz_catalog_carve_gate.mjs — walks the full GFX2 sprite dispatch of all 59 chars, drives the REAL production ensureBodyTextures per (sel,flip), byte-gates each tile vs whole-part Y-first detwiddle',
  note='COMPREHENSIVE catalog scan (supersedes _zz_roster_carve_gate which had no GFX2/flip context + skipped 2x2/2xN/Nx2/strip). Baseline: 2618 BAD parts / 7664 BAD tiles — 100% flip4000=1 on HORIZONTAL (Nx1) LINEAR parts (2x1/4x1/8x1/16x1 @ m=8/16/32); 0 non-flip, 0 native, 0 vertical. Storm 8-way Lightning Strike other-directions = sel0x35e(64x32 strip)+0x35f/0x360(32x8 sub32) all column-reversed. Post-fix: 0 BAD / 192032 parts. sel0x316 4x8 = CLEAN single-instance (the 32/64 WRONG is multi-instance runtime, NOT static — stays open).';

UPSERT finding:flip4000_double_apply_carve SET
  statement='CONFIRMED + FIXED 2026-07-10 (native AND linear). The per-record 0x4000 is a DRAW-TIME texU mirror ONLY (re_kb/24 loc_8c0346c4), never a storage re-store. The carve applied it TWICE (once as render_frame_quad_mirror, once as a storage-column reversal col=(dfl&2)?(pCols-1-cc):cc). scene10 fixed the NATIVE (m=32 twiddle-chunk) path via ncol=dcx%pCols. The whole-catalog gate (_zz_catalog_carve_gate.mjs, 192032 parts / 59 chars) then proved the LINEAR desc-keyed branch had the SAME bug on horizontal flip4000 parts (2618 bad parts / 7664 bad tiles, 100% flip4000=1 horizontal-linear). LINEAR FIX (scene11): col = cc (remove the reversal; non-flip and vertical pCols=1 are byte-identical -> zero regression). Full-catalog gate post-fix = 0 BAD / 192032. Storm Lightning-Strike ALL directions now clean (native sel0x35d + linear sel0x35e/0x35f/0x360). Deployed body_decoder ?v=scene11; C++ twins (maplecast_mirror.cpp gstaDecodeBodies + texel_gate.cpp) col=cc source-only (native rebuild pending for the engine-mirror-VRAM cross-check of a horizontal-linear flip part).',
  status='confirmed', confidence='high', date='2026-07-10';

RELATE finding:flip4000_double_apply_carve->cites->source:catalog_carve_gate;
