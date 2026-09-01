-- 62_tcw_palsel_patch_pipeline.surql
-- CONFIRMED (marvelous2 static disasm, 2026-07-05): where the per-tile TCW at
-- descriptor entry +0x0C is composed, and where PalSelect (bits 21-26) is patched.
-- Motivated by the MEASURED BTCW stale-palsel bug (capture at PC 0x8C1248CC reads
-- current ADDR bits but m-2 owner's palsel on VRAM-arena slot churn).
--
-- Descriptor entry arena: ptr @0x8C2DAD4C, 32-byte entries
--   +0x00 PCW  +0x04 ISP  +0x08 TSP  +0x0C TCW  +0x10 color
--   +0x14 u16 is-paletted flag  +0x16 u16 palette-id (0xFFFF = none)
-- slot->entry-index word table: ptr @0x8C2DAD3C (0xFF = unassigned)
-- entry-index allocator bitmask: ptr @0x8C2DAD44 (bank12 loc_8c124cb0)
-- texture record arena: ptr @0x8C2DE690, 0x3C-stride
--   +0x08/+0x18 TCW flag words  +0x1C VRAM arena byte addr  +0x2C per-frame use count
--   +0x30 TSP size bits  +0x34 record TCW
-- slot-record table: ptr @0x8C2AA26C, 8-byte [(+0x00 use ctr/flag)(+0x04 record idx)]
-- slot namespace base offset: @0x8C2DEE54 (setter bank11 loc_8C11B800; zeroed by
--   bank12 loc_8C122CF0). Registration/palette-change ADD it to the slot; the
--   SUBMIT (loc_8C1244B0) does NOT (0x8C124522 mov.l @r13,r8 uses object +0x00 raw).
-- palette residency table: ptr @0x8C32B438, 8-byte per palette-id
--   [+0x00 u16 resident PVR bank][+0x04 u16 refcount][+0x06 u16 palid backref]
--   max palette count word @0x8C32B424; mode flag @0x8C16BBEC (0 = residency mode,
--   nonzero = caller array holds raw banks); enable flag @0x8C2D6CEC.
--
-- ENTRY TCW (+0x0C) WRITER SET (complete, per grep of bank11/bank12):
--   0x8C124C56 clear-to-0 during entry rebuild            (bank12 loc_8c124c40)
--   0x8C11BB90 install record TCW: entry+0x0C = rec+0x34  (bank11 loc_8C11BB70)
--              -- rec+0x34 composed at bank11 loc_8C11BBD0:
--                 ((rec+0x18|rec+0x08) & 0xFF800000) | (rec+0x1C >> 3)
--                 store 0x8C11BC0A. Mask 0xFF800000 HARD-ZEROES palsel bits 21-22;
--                 => install DESTROYS palsel; it must be re-patched afterward.
--   PALSEL PATCHES: tcw = (tcw & 0xF81FFFFF) | (bank << 21)   [shad 0x15]
--   0x8C124030 registration, residency path   (bank12 loc_8c124022; entry in r13,
--              bank in r12 from residency table: reuse read 0x8C123F72 / new-alloc
--              store 0x8C123FFC; palid written to entry+0x16 at 0x8C123F58,
--              default 0xFFFF at 0x8C123F12)
--   0x8C12405A registration, direct-bank path (bank12 loc_8c12404c)
--   0x8C124A8E palette-CHANGE, residency path (bank12 loc_8c124a82; entry in r14)
--   0x8C124978 palette-CHANGE, direct path    (bank12 loc_8C12495E; entry in r14)
--              -- change API = bank12 loc_8C124910; called by GAME layer:
--                 bank03 pool loc_8c033e1c (#data bank12.loc_8c124910), routine
--                 reads char+0x52C palette byte (pool 0x052C at loc_8c033e16)
--   0x8C1241A8 REFRESH pass (bank12 loc_8c124140/loc_8c124170): extracts the
--              entry's OLD palsel (0x8C12418E load, 0x8C124190 and 0x07E00000),
--              re-installs fresh-addr TCW via jsr loc_8C11BB70 (0x8C124196),
--              then ORs the OLD palsel back (0x8C1241A6) and stores (0x8C1241A8).
--              => THE stale-carry producer: addr CURRENT + palsel CARRIED.
--
-- SUBMIT (bank12 loc_8C1244B0) NEVER writes entry+0x0C. It reads it ONCE at
-- 0x8C124864 (mov.l @(0x0C,r12),r3) and copies verbatim to the store-queue TA
-- block at 0x8C124866 (mov.l r3,@(0x0C,r14)), flushed by pref 0x8C12487A -- all
-- BEFORE the BTCW capture PC 0x8C1248CC (2nd pref). No register holds palbank at
-- 0x8C1248CC on either walker arm (0x8C034864 body / 0x8C034BA4 scale); r12=entry
-- (computed 0x8C124536..0x8C124544, callee-saved, valid on both arms).
-- => The engine SHIPS the same stale word to the TA on churn frames; no capture
--    reordering inside the submit can fix it.
--
-- OPEN: the m-2 (same-parity) signature. Refresh-carry explains "addr current,
-- palsel old"; the 2-frame parity is INFERRED to be @0x8C2DEE54 alternating the
-- slot namespace (double-buffered draw build). Discriminating probe: log
-- @0x8C2DEE54 + fire counts of the six writer PCs across a super-peak window.

USE NS re DB kb;

UPSERT routine:loc_8c1244b0 SET
    name = "pvr_sprite_submit",
    bank = "bank12",
    pc = "0x8C1244B0",
    summary = "Shared sprite submit. Reads descriptor entry TCW @+0x0C ONCE at 0x8C124864, copies verbatim to TA SQ at 0x8C124866 (pref 0x8C12487A). NEVER writes entry TCW. BTCW capture PC 0x8C1248CC = 2nd pref; word already final for the frame.",
    updated_at = time::now();

UPSERT routine:loc_8c11bb70 SET
    name = "descriptor_tcw_install",
    bank = "bank11",
    pc = "0x8C11BB70",
    summary = "entry+0x0C = texrecord+0x34 (store 0x8C11BB90); entry+0x08 |= rec+0x30 size bits. Record TCW (composed loc_8C11BBD0, store 0x8C11BC0A) = ((rec+0x18|rec+0x08)&0xFF800000)|(rec+0x1C>>3): palsel bits 21-22 hard-zeroed -> install DESTROYS palsel; must be re-patched.",
    updated_at = time::now();

UPSERT routine:loc_8c123e00 SET
    name = "draw_slot_full_registration",
    bank = "bank12",
    pc = "0x8C123E00",
    summary = "Per-slot full registration (game wrapper loc_8c1240a0, called from bank03). Uploads texture on first-use/frame, rebuilds entry (loc_8c124c40), resolves palette residency (table @@0x8C32B438, palid->bank), patches palsel CURRENT: store 0x8C124030 (residency) / 0x8C12405A (direct-bank). entry+0x16 = palid (0x8C123F58).",
    updated_at = time::now();

UPSERT routine:loc_8c124140 SET
    name = "draw_slot_refresh",
    bank = "bank12",
    pc = "0x8C124140",
    summary = "Fast refresh: extracts entry's OLD palsel (0x8C124190 and 0x07E00000), reinstalls fresh-addr TCW from record (jsr loc_8C11BB70 @0x8C124196), ORs OLD palsel back (0x8C1241A6), store 0x8C1241A8. THE stale-palsel carrier: addr current + palsel from entry's previous contents.",
    updated_at = time::now();

UPSERT routine:loc_8c124910 SET
    name = "draw_slot_change_palette",
    bank = "bank12",
    pc = "0x8C124910",
    summary = "Palette-change API on an existing entry (slot + @0x8C2DEE54). Residency path patch store 0x8C124A8E; direct-bank path store 0x8C124978 (returns old bank (tcw>>21)&0x3F). Called from bank03 (pool loc_8c033e1c) using char+0x52C palette byte.",
    updated_at = time::now();

UPSERT finding:tcw_palsel_patch_pipeline SET
    status = "confirmed",
    confidence = 0.9,
    summary = "TCW palsel (bits 21-26) is patched OUTSIDE the submit: writer set {0x8C124030, 0x8C12405A, 0x8C124A8E, 0x8C124978 = CURRENT-bank patches; 0x8C1241A8 = refresh OLD-palsel carry; 0x8C11BB90 = addr install that destroys palsel}. Submit loc_8C1244B0 copies entry+0x0C verbatim to the TA (0x8C124864/66) before capture PC 0x8C1248CC; no register holds palbank there; the engine ships the stale word itself on churn frames. BTCW fix = hook the four CURRENT-patch stores (entry addr r13/r13/r14/r14, composed word r2/r2/r2/r4) into a per-frame entry->palsel map consulted at 0x8C1248CC. OPEN: m-2 parity mechanism (suspect @0x8C2DEE54 slot-namespace flip, setter loc_8C11B800).",
    updated_at = time::now();

RELATE finding:tcw_palsel_patch_pipeline->about->routine:loc_8c1244b0;
RELATE finding:tcw_palsel_patch_pipeline->about->routine:loc_8c11bb70;
RELATE finding:tcw_palsel_patch_pipeline->about->routine:loc_8c123e00;
RELATE finding:tcw_palsel_patch_pipeline->about->routine:loc_8c124140;
RELATE finding:tcw_palsel_patch_pipeline->about->routine:loc_8c124910;
