USE NS re DB kb;

-- ============================================================================
-- 2026-07-09 — re_kb/51 FULLY CLOSED: the engine tile order for wide parts is
-- COLUMN-PAIR MAJOR; rebuild_tile_grid's row-band-major scan 2x2-block-swapped
-- 4x4+ parts (Sentinel) = the flashing block holes / "swapped diagonally".
-- ============================================================================

UPSERT source:band4_desc_order SET kind='measurement',
  ref='band4.mcrr (2400 frames, vf 310394..312793) + asm_band4.txt (frame-exact ASMTRACE) + _tx_desc_order.mjs shipped-vs-rebuild desc diff; _tx_detect gate',
  note='_tx_detect found 9600 CONFIRMED 2-part transpositions, all on node 0c268e88 (P1C2 Sentinel), tiles 20<->24/21<->25/22<->26/23<->27 within one sel (124/112) — 2x2 tile blocks swapped diagonally (64 internal px in X and Y), persistent every frame. _tx_desc_order on the SHIPPED tiledesc (vf310394, sel 124, 128x128 = 4 cols x 4 rows): engine order = c0r4 c0r3 c1r4 c1r3 | c0r2 c0r1 c1r2 c1r1 | c2r4 c2r3 c3r4 c3r3 | c2r2 c2r1 c3r2 c3r1 (column-pair macro-column through ALL row-bands, then next pair); rebuild order was row-band-major (all 4 cols per band). Identical when cols<=2 OR rows<=2 (all normal chars clean) — diverges only on 4x4+ parts.';

UPSERT finding:wide_part_colpair_order SET
  statement='CONFIRMED + FIXED 2026-07-09. The engine desc builder (loc_8c033ba8..ce0) emits wide-part tiles COLUMN-PAIR MAJOR: [col-pair][2-row band][col-in-pair][row-in-band] — a 2-column macro-column walks all row-bands before the next pair. rebuild_tile_grid (render_frame.c) used row-band-major ([band][all cols][row]) which matches for cols<=2 or rows<=2 but 2x2-block-swaps 4x4+ parts: Sentinel 128x128 sel-124 tiles 4..7 got the desc entries the engine assigns tiles 8..11 -> two 2x2 blocks of his body drawn at each other\'s positions + matching holes = the user-visible flashing black blocks and the ORIGINAL re_kb/51 "two cleanly-rendered parts, swapped diagonally puts them right". FIX: rebuild loop reordered to column-pair major; _tx_desc_order MATCH=YES vs shipped desc on the 4x4. GATES: band4 9600 transpositions -> 0 (4800/4800 node-frames clean @6px); band2 regression 5664/5664 clean. Deployed render_frame.wasm ?v=widecarve1. re_kb/51 now closed BOTH halves (blank-slot compaction re_kb/66 + this order bug); re_kb/21/46 storage-order hypotheses resolved to this mechanism.',
  status='confirmed', confidence='high', date='2026-07-09';

RELATE finding:wide_part_colpair_order->cites->source:band4_desc_order;

UPSERT finding:gsta_body_part_transposition SET
  statement='RESOLVED 2026-07-09 — BOTH mechanisms found and fixed. (1) sel==0xFF blank-record desc-slot compaction (re_kb/66): burst misplacements after blank records. (2) wide-part COLUMN-PAIR-MAJOR tile order (re_kb/68): persistent 2x2-block diagonal swaps on 4x4+ parts (Sentinel) — the literal "swapped diagonally puts them right" report. Gates: band2 5664/5664 + band4 4800/4800 node-frames clean vs frame-exact ASMTRACE; 0 transpositions, 0 over/under-emission.',
  status='resolved', confidence='high', date='2026-07-09';

RELATE finding:gsta_body_part_transposition->cites->source:band4_desc_order;
