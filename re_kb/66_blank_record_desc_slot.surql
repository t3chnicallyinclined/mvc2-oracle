USE NS re DB kb;

-- ============================================================================
-- 2026-07-09 — the "dark band" residual CLOSED: sel==0xFF BLANK records consume
-- real tiledesc slots; rebuild_tile_grid's `continue` compacted the slice.
-- Ground truth: band2.mcrr (vf 724167..725439, 1273 frames) + frame-exact
-- ASMTRACE (PC 0x8C034864) via the capture_break/_tx_detect pipeline.
-- ============================================================================

UPSERT source:asmtrace_band2_blankslot SET kind='oracle',
  ref='band2.mcrr vf724219 node 0c2688e4 (P2C1 cid=0x17) + asm_band2.txt (110804 lines) + WALKDBG instrumented walker on ram_724219.bin',
  note='Frame-exact engine-vs-render_frame per-record walk diff. Engine r11 stepped 0c8fe534->544 skipping record 0c8fe53c {dx=0,dy=-88,flags=0,sel=0xFF}; r13 consumed exactly ONE desc slot (a05c->a064, slot a060=[20 00 00 01]); pen accX/accY carried the blank dx/dy (accY -128 -> -40 -> -4 solves exactly). Shipped desc table = byte-coherent with the engine walk (all count/m bytes match). Post-rebuild WALKDBG dump proved rebuild_tile_grid compacted the slice 1 slot left of the engine layout.';

UPSERT finding:blank_record_desc_slot SET
  statement='CONFIRMED + FIXED 2026-07-09. A GFX2 cell record with sel==0xFF ("blank") is allocated its FORMULA-DERIVED tiledesc slots by the engine builder (loc_8c033ba8..ce0) exactly like any record — GFX1[0xFF] resolves to a real header (P2C1 cid=0x17: sw=4 sh=4 -> W=H=32 -> m=32, cnt=1 == the shipped slot [20 00 00 01] byte-for-byte, NO special case). The walker (loc_8c0344d4) consumes those slots and accumulates the record pen dx/dy; only the DRAW is suppressed. render_frame.c rebuild_tile_grid (the racy-tiledesc fix, re_kb/22) skipped blanks with `continue` -> the rebuilt slice sat one slot LEFT of the engine layout -> the walker read each later record with its NEIGHBOR record count/m (measured: engine 230x1,256x2,260x1,258x2 -> rf 230x2,256x1,260x2,258x2) -> +1 over-emission + a 3-part strip drawn 51-180px low = the recurring "dark band" (147 node-frames in band2, bursts on P2C1). FIX: remove the continue (blank gets formula slots; submit_1244b0 sel==0xFF guard still drops the visible quad, matching the engine observable: slot consumed, pen carried, nothing drawn). GATE: _tx_detect band2 = 5664/5664 node-frames clean (tol 6px, shift 0), over-emission 147->0, transpositions 0.',
  status='confirmed', confidence='high', date='2026-07-09';

RELATE finding:blank_record_desc_slot->cites->source:asmtrace_band2_blankslot;
RELATE finding:blank_record_desc_slot->about->routine:loc_8c0344d4;

-- Update the open re_kb/51 transposition finding: the observed residual class is
-- explained by the blank-slot compaction; a literal clean 2-swap NEVER occurred in
-- a frame-exact 1273-frame gameplay capture once corner pairing is facing-aware.
UPSERT finding:gsta_body_part_transposition SET
  statement='RESOLVED 2026-07-09 (superseded by finding:blank_record_desc_slot). The "two cleanly-rendered parts placed wrong / stray dark band" residual = the sel==0xFF blank-record desc-slot compaction in rebuild_tile_grid, NOT an anchor/cursor transposition: after the blank, every record read its neighbor desc entry (count/m), producing 2-4 mis-positioned clean parts per frame in bursts. With frame-exact ASMTRACE alignment + facing-aware corner pairing (asm anchor = quad LEFT edge or RIGHT edge by facing; Y = quad max-y always), a literal 2-part swap occurred 0 times in 1273 gameplay frames (5664 node-frames). Gate clean post-fix: 5664/5664. NOTE the earlier "68px skew noise" was frame misalignment (fixed by capture_break vframe alignment) and the whole-node 13.3/26.7/53.3px offset class was the tile-width-x-scaleX corner artifact in _diff_sweep, not render error.',
  status='resolved', confidence='high', date='2026-07-09';

RELATE finding:gsta_body_part_transposition->cites->source:asmtrace_band2_blankslot;
