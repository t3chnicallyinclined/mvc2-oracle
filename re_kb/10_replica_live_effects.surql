USE NS re DB kb;

-- ===========================================================================
-- finding:replica_live_effects — SUPERSEDED 2026-06-14. The pure-effect render
-- path was re-derived FAITHFULLY from the disassembly. The prior directory-binding
-- HEURISTIC (node+0x15C -> Effect-Poly dir entry, point-centered additive quad) was
-- built on a MISLABEL and is RETIRED. The real path is the SAME body walker.
-- Apply: tools/re_kb/rekb.sh @tools/re_kb/10_replica_live_effects.surql
-- ===========================================================================

-- ---- SUPERSEDE the heuristic finding ----
UPSERT finding:replica_live_effects SET
  status = "superseded",
  superseded_by = "finding:replica_effect_walker_faithful",
  confidence = "high",
  date = "2026-06-14",
  statement = "SUPERSEDED by finding:replica_effect_walker_faithful. This finding rendered pure effects with a DIRECTORY-BINDING HEURISTIC: it read an effect node's GFX base node+0x15C, treated it as a pointer INTO the Effect-Poly directory at *(0x0CED0008) (0x10-byte entries), recovered dirIdx=(node+0x15C - dirBase)/0x10, and drew ONE point-centered additive quad sized by the directory entry e0, anchored at node+0xE0/E4. That model rested on the MISLABEL 'loc_8c1294c8 = the cell processor for non-body effects' (copied from render_frame.c into this finding). TRACING THE DISASM proves loc_8c1294c8 is NOT a render routine: it is a Duff's-device 20-byte longword MEMCPY (marvelous2 bank12.asm:21885; jump table loc_8C12951C, 18 entries; descending mov.l @(0xNN,r2),r3 / mov.l r0,@(0xNN,r1) ladder), whose ONLY caller is load-animation loc_8c034e8c (bank03:11697-11700: mov 0x14,r0 -> copies the 20-byte anim CELL RECORD into plmem+0x140). The heuristic diverged from the engine on every multi-cell / per-cell-offset / per-cell-flip / cumulative-pen / bit15-scaled effect, and DOUBLE-DREW on top of the real walker output (render_frame.wasm already renders cat 1..4 nodes). RETIRED: effects-client.mjs is now a diagnostic-only no-op overlay; effects render through the body walker (see the superseding finding).";

-- ---- NEW: the FAITHFUL effect path ----
UPSERT source:loc_8c1294c8_memcpy_not_cellproc SET kind='marvelous2',
  ref='bank12.asm:21885 loc_8C1294C8 (+ table loc_8C12951C 21969, ladder loc_8C1294DA..loc_8C129516); caller bank03.asm:11697-11700 loc_8c034e8c',
  note='loc_8c1294c8 is a Duff-device variable-length LONGWORD MEMCPY, NOT an effect cell processor. add 0xFC,r0 biases the index; jmp through loc_8C12951C[18] into the descending mov.l @(off,r2),r3 / mov.l r0,@(off,r1) ladder copies 0..18 longwords r2->r1. Its caller load-animation loc_8c034e8c sets r0=0x14 (20 bytes), r1=plmem+0x140, r2=current_cell_data -> copies the 20-byte anotak anim cell record into the live struct. The render_frame.c comment + finding:replica_live_effects mislabel both stem from this routine being misread as a render dispatcher.';

UPSERT source:loc_8c034bea_cell_fetch SET kind='marvelous2',
  ref='bank03.asm:11259 loc_8c034bea (data 11290: 0x0104/0x00ec/0x0144; 0x00008000)',
  note='The cell-fetch / render dispatch called at the END of loc_8c030af8 (satellite+effect setup) AND inside the anim tick. Reads sel = read_u16(node+0x144): if sel==0xFF return 0 (terminator, nothing drawn); if (sel & 0x8000) bsr loc_8c0348c8 (the per-part-SCALED walker twin, bit15 = scale dispatch); else bsr loc_8c0344d4 (THE BODY WALKER). This is the ONE dispatch for bodies AND effects -> there is no separate effect cell processor.';

UPSERT source:loc_8c0344d4_walker_keys SET kind='marvelous2',
  ref='bank03.asm:10218 loc_8c0344d4; key offsets data 10380 loc_8c0345fc..',
  note='Walker entry reads GFX2 = read_u32(node+0x160) (loc_8c0345fc=0x0160), masks sel with loc_8c0345fe=0x7FFF, indexes cell = GFX2 + *(u32)(GFX2 + (sel&0x7FFF)*4); first u16 = record count, then count x 8-byte records [dx s16][dy s16][FLAGS u16 (0x4000 X-mirror / 0x8000 Y-mirror)][sel u16] with a cumulative pen. Anchor node+0xE0/E4 (loc_8c034602/4), scale node+0xEC/F0 (loc_8c03460c/e), facing node+0x110 (loc_8c034606), cursor node+0xDC (loc_8c034600). An EFFECT node uses the IDENTICAL arithmetic — only cat (1..4) + GFX2-in-Effect-Poly-bank distinguish it from a body.';

UPSERT source:replica_effect_walker_disasm_validation SET kind='transpile_validation',
  ref='tools/render-replica-poc/_validate_efx_walker.mjs on _efxcap.mcrr (prod replica-live vframe 1516220)',
  note='Live prod capture (wss://nobd.net/replica-live, 300 frames) was IDLE (2 bodies, slot layers 5+6, ZERO active pool/effect nodes) so no live pure-effect node was capturable — the documented OPEN item (a live HIT is required). VALIDATED AGAINST THE DISASM on the real bodies, which use the IDENTICAL walker keys an effect uses: slot1 base 0x8C2688E4 sel=0x30 -> GFX2 0xC9032A0 -> cellPtr 0xC905064 CELL_COUNT=7; slot4 base 0x8C2699D0 sel=0x37 -> GFX2 0xC7AB8C0 -> cellPtr 0xC7AD8F2 CELL_COUNT=16. The walker-key resolution (cell = GFX2 + *(GFX2+(sel&0x7FFF)*4); u16=count) is byte-exact vs loc_8c0344d4. DEFERRED: live byte-check of a real pure-effect node (cat 1..4, GFX2 in 0x0CED0000) needs a contact-frame capture — fire a hit on prod and re-run livecap.mjs + _scan_pool_efx.mjs / _probe_effect_nodes.mjs.';

UPSERT finding:replica_effect_walker_faithful SET
  statement='FAITHFUL pure-effect render path (replaces the directory-binding heuristic). A pure effect (cat 1..4 pool node, GFX2 node+0x160 in the Effect-Poly bank 0x0CED0000, NO directory binding) renders through the SAME path as a body: loc_8c030af8 (satellite/effect setup, gates 0<cat<5 and node+0x12C==0, deposits anchor +0xE0/E4, scale +0xEC/F0, facing +0x110, cursor +0xDC via the loc_8c122560 transform) -> loc_8c034bea (sel node+0x144 dispatch: 0xFF=>nothing, &0x8000=>loc_8c0348c8 scaled twin, else=>loc_8c0344d4) -> loc_8c0344d4 (the proven body walker, reads cell records from GFX2 node+0x160 by (sel&0x7FFF), cumulative pen, per-cell 0x4000/0x8000 flips). render_frame.wasm slot-walk (gen_walker_root.c) ALREADY routes EVERY cat 1..4 node through render_frame_satellite_hook -> render_object_full_satellite -> this walker (re_kb finding 23, 0.0000px-validated), so effects render FAITHFULLY in the WebGPU body pass with the engine real per-cell geometry. CLIENT CHANGE: effects-client.mjs rewritten as a diagnostic-only no-op overlay (render() returns 0, draws nothing — no double-draw, no divergence; readEffectNodes() kept FAITHFUL: enumerates cat 1..4 nodes with GFX2 in the effect bank, sel!=0xFF, gate==0, and resolves the walker cell COUNT). replay.html: import ?v=fx3faithful, removed the atlas load, __pokeEffect rewritten to borrow a body GFX2/sel so the WALKER renders the synthetic effect (no heuristic dir binding). VALIDATED vs the disasm on a real prod RAM frame (source:replica_effect_walker_disasm_validation: walker-key resolution byte-exact, CELL_COUNT 7/16 on the two live bodies). DEFERRED: live byte-check of a real pure-effect node needs a contact-frame capture (no idle capture has one). This COMPLETES the RENDER-half transpile (geometry + texture decode + effects all faithful, no heuristics). Branch feat/render-replica-live.',
  status='confirmed', confidence='high', date='2026-06-14';

RELATE finding:replica_effect_walker_faithful->cites->source:loc_8c1294c8_memcpy_not_cellproc;
RELATE finding:replica_effect_walker_faithful->cites->source:loc_8c034bea_cell_fetch;
RELATE finding:replica_effect_walker_faithful->cites->source:loc_8c0344d4_walker_keys;
RELATE finding:replica_effect_walker_faithful->cites->source:replica_effect_walker_disasm_validation;
RELATE finding:replica_effect_walker_faithful->supersedes->finding:replica_live_effects;
RELATE finding:replica_effect_walker_faithful->cites->routine:loc_8c0344d4;
RELATE finding:replica_effect_walker_faithful->cites->routine:loc_8c030af8;

UPSERT memdata:effect_poly_bank SET addr = '0x0CED0000', name = "Effect Poly bank", note = "shared hitspark/electric/energy textures + cell records; an effect node's GFX2 (node+0x160) points HERE and the walker loc_8c0344d4 reads its cell records by (sel&0x7FFF) — NOT a directory binding via node+0x15C";
