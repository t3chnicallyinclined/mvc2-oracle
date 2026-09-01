-- ============================================================================
-- 32: Slot-table = draw list; active/point-char selection DIAGNOSIS (Sentinel
--     "wrong portrait / scrambled body" lead). Live ground truth from the
--     render-replica recordings (_sentinel_scramble / _scramble_actual / _satlive .mcrr).
--     Pinned 2026-06-14.
-- ============================================================================
USE NS re DB kb;

UPSERT source:render_sprites_0308c2 SET kind='disasm',
  ref='_marv_re/build/bank03.asm loc_8c0308c2 (Render_sprites), lines 1200-1277',
  note='THE engine draw list = the slot table, NOT an active-flag walk of the 6 char structs. loc_8c0308c2 loads r13=0x8C2895E0 (16 per-layer signed-byte counts), r10/r12=0x8C287DE0 (16 ptr rows, stride 0x180), loops layers x counts, reads each node ptr from the ptr array, gates on node+0x3 (cat byte: tst r0,r0 -> bf body loc_8c03093c else effect loc_8c030af8). It renders EXACTLY the nodes enqueued in the slot table. A benched tag partner is simply NOT enqueued -> never drawn. The body render-main loc_8c03093c then gates on node+0x12C (unk_012c) for per-node visibility. EnemyPointer @ char+0x20C (pl_mem.asm:228) = "pointer to opponent currently-active character plmem struct" = the engine authoritative per-side point-char pointer.';

UPSERT finding:slot_table_is_drawlist_not_active SET
  statement='CONFIRMED (bank03 loc_8c0308c2 + live recordings): the engine renders ONLY the char-base nodes present in the slot table 0x8C2895E0/0x8C287DE0; it does NOT iterate the 6 char structs gating on active@+0x000. In a TAG match exactly the 2 active point chars are enqueued (one per side). Live proof (_sentinel_scramble.mcrr fr325313, _scramble_actual.mcrr, _satlive.mcrr fr196491): slot table always holds EXACTLY 2 char-base nodes, both cat=0 bodies = the two active point chars; benched partners absent. The client render-replica body loop (sprite-client.mjs:1974 buildEmitterDrawList) gates bodies on sl.active and the HUD picks the point char via _pointSlot first-active-of-side ([0,2,4]/[1,3,5]) -- BOTH consistent with the engine. So benched partners are NOT rendered by the client either.',
  status='confirmed', confidence='high', date='2026-06-14';

UPSERT finding:sentinel_scramble_slot_data_clean SET
  statement='REFUTES the "benched War Machine overlapping Sentinel" + "wrong-char from slot/pointer mis-read" hypotheses at the DATA level. Live char-struct dump from 3 render-replica recordings of the reported scramble: the per-slot active/char_id is CORRECT and unambiguous in every frame. _sentinel_scramble.mcrr (90 fr) + _scramble_actual.mcrr (120 fr): P1C1=Sentinel(0x34) active=1, P2C1=Cable(0x17) active=1, P1C2=Storm(0x2A) active=0, P2C2/P1C3/P2C3 active=0 (stale cid 0x17). _satlive.mcrr (700 fr): a DIFFERENT lineup where Sentinel is the active point char in slot P1C2 (idx2, P1C1=Colossus 0x32 benched, active=0); _pointSlot([0,2,4]) correctly skips idx0 and returns idx2=Sentinel; slot table renders node 0x8C268E88(P1C2) correctly. KEY CORRECTION: the reported third char is STORM (0x2A), NOT War Machine (0x2E) -- the team is Sentinel/Cable/Storm; War Machine (0x2E) is not in any captured frame. The deployed portraits.png (md5 ce1476877f17eb55dfcd136d799b9699 == local) maps each char_id to the correct face (Sentinel rect 384,320 = the metallic Sentinel head; War Machine rect 64,320 = the yellow armored figure; Storm rect 320,256 = Storm), verified pixel-by-pixel. So with the captured RAM, _pointSlot returns the correct cid AND the portrait atlas yields the correct pixels. CONCLUSION: the slot/active/point-char/portrait-map plumbing is NOT the bug -- it is correct end to end. Any residual "wrong portrait" is either (a) a CELL_CHAR grid mis-id in tools/rip_portraits.py for a SPECIFIC neighbor cell (the map is visually-verified, not from a static table -- see finding:hud_portrait_decode open item), or (b) the portrait pixel-DECODE itself (texture-decode agent domain), NOT a memory/slot/pointer divergence.',
  status='confirmed', confidence='high', date='2026-06-14';

RELATE finding:slot_table_is_drawlist_not_active->cites->source:render_sprites_0308c2;
RELATE finding:sentinel_scramble_slot_data_clean->cites->source:render_sprites_0308c2;
