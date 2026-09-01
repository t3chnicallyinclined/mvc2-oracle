-- ============================================================================
-- 60_storm_tilecount_authoritative.surql
-- 2026-07-03 — AUTHORITATIVE render-time tile-COUNT model, traced end-to-end in
-- marvelous2 build/bank03.asm (descriptor builder loc_8c033b0a; per-frame reset
-- loc_8c0337bc; body walker seed loc_8c0344d4) + bank12.asm (div helpers
-- loc_8C129128 signed / loc_8C1291DC unsigned). Explains why the Storm (PL34)
-- shipped descriptor (0x8C1F9F9C) OVER-counts one frame and UNDER-counts another
-- vs the engine's ~49-53. Apply, then 07_dedup_edges.surql.
-- ============================================================================
USE NS re DB kb;

UPSERT finding:storm_tilecount_authoritative SET date='2026-07-03', confidence='high', status='confirmed',
  contribution_candidate=true,
  note='AUTHORITATIVE ENGINE TILE-COUNT for a body (bank03.asm). The per-frame tile-descriptor table
0x8C1F9F9C is BSS scratch, RESET every render pass by loc_8c0337bc (bank03:8232): it writes descriptor
write-ptr *0x8C1FAB9C := 0x8C1F9F9C (loc_8c0338c0/c4), global tile index *0x8C1F9D98 := 0 (loc_8c0338bc),
arena_base *0x8C1F9D94 := 0x190=400 (loc_8c0338b8), *0x8C1F9D90 := 0x10, then jsr loc_8c129728
(r4=0x0CE60000,r6=0xC00). The per-object BUILDER loc_8c033b0a (bank03:8720; called per-object per-frame
from bank04 loc_8c044014 / 0x8c04b... ) fills it. Gate: bit15 of u16(node+0x144) must be CLEAR
(loc_8c033b30 tst 0x8000; bt=proceed) — Storm sid 0x42/0x44/0x46 is bit15-clear, so she uses THIS builder +
the min-rule walker loc_8c0344d4 (REFUTES scale-walker hypothesis). Builder sets node+0xDC := current global
index *0x8C1F9D98 (loc_8c033b40 mov.l r3,@(0xDC,r14)), then loops the GFX2 cell records:
  cellbase = GFX2 + *(u32)(GFX2 + (sid&0x7FFF)*4)   [GFX2=node+0x160; the SELF-MODIFYING dispatch head]
  nrec     = u16 @cellbase
  per record: sel = u16 @(rec+6); part = GFX1 + *(u32)(GFX1 + sel*4)   [GFX1=node+0x15C]
              W = u8(part+2)*8 ; H = u8(part+3)*8        (loc_8c033be0: mov.b @r4+ x2, shll2;shll => *8)
              tileSide = min-dim bucket {8px->stride32, 16px->stride128, 32px->stride512}  (=side^2/2 bytes)
              partBytes = W*H/2                          (muls.w W,H; shar => 4bpp)
              tiles r9  = partBytes / strideBytes  via loc_8C1291DC (unsigned div, bank12:21464)
                        = W*H / side^2 = LONG/SHORT.     (loc_8C129128 signed div used only odd-dim branch)
  writes r9 descriptor entries of 4 bytes each: byte0=tileSide(m), byte1=(0xFF+r9)&0xFF = r9-1 (count-base),
  byte2=Xstep, byte3=Ystep (loc_8c033ce0..loc_8c033d44); advances *0x8C1FAB9C +=4/tile and *0x8C1F9D98
  +=r9/record. HARD CAP: if global_index + r9 > 0x180 (384) it bails (loc_8c033ca8 cmp/gt 0x180 -> ret 0xFF).
  The WALKER loc_8c0344d4 (bank03:10247) re-reads r13 = 0x8C1F9F9C + u16(node+0xDC)<<2 (loc_8c034600=0xDC,
  loc_8c034618=0x8C1F9F9C CONFIRMED) and per record count = u8(desc[r13+1])+1 = (r9-1)+1 = r9.
=> ENGINE_TILE_COUNT(body) = SUM over LIVE GFX2 records of ( max(W,H)/min(W,H) ), min(W,H) in {8,16,32}px,
   capped so the running frame-global index <= 384. For Storm this sums to ~49-53.';

UPSERT finding:storm_tilecount_count_is_scale_invariant SET date='2026-07-03', confidence='high', status='confirmed',
  note='REFUTED: "CPS ratio / size modifier changes the tile COUNT." The builder loc_8c033b0a reads ONLY
node+0x04(self), +0x144(sid), +0x160(GFX2), +0x15C(GFX1), +0x12D/+0x12E(a VRAM-address mode flag+field, NOT
geometry), +0xDC. It NEVER reads node+0x50/+0x54 (CPS scale factors) nor +0xEC/+0xF0 (CpsXScale*scale). W and
H come PURELY from GFX1 part header bytes [+2]/[+3] *8. Scale (node+0xEC/+0xF0) is read ONLY in the WALKER
loc_8c0344d4 (loc_8c03460c=0xEC/loc_8c03460e=0xF0) where step*scale sizes/positions each tile (re_kb/08,/22).
So CPS/size affects tile POSITION+SIZE, NOT tile COUNT or m. The count is a pure function of the LIVE GFX1
part dims + the LIVE GFX2 record list.';

UPSERT finding:storm_16x16_parts_reconcile SET date='2026-07-03', confidence='high', status='confirmed',
  note='RECONCILES MEASURED FACT 2 (Storm RAM GFX1 parts have header [2,2,2,2]=>16x16 whereas disc PL34 rip
=128x16/64x64/32x64; Cable/PL17 does not). Because tiles = LONG/SHORT (finding:storm_tilecount_authoritative),
the count is INVARIANT to how a wide part is stored: one 128x16 record => 128/16 = 8 tiles; equivalently eight
16x16 records => 1 tile each = 8 tiles. Storm renders the SAME total whether her live GFX1 holds wide parts +
few GFX2 records, OR pre-decomposed 16x16 parts + proportionally MORE GFX2 records. So Storm being 16x16 in
RAM is NOT lost geometry and NOT a count bug; it only shifts the count from the W/H term into the record COUNT
term. CONSEQUENCE: any offline count derived from the DISC part dims (render_frame GFX1-derived) is only
correct if it also reads the LIVE (self-modified) GFX2 record list at the SAME vframe — the two must be
coherent. INFERRED (would confirm with an ASMTRACE/BODYCAP frame on Storm): whether the RAM 16x16 layout is a
genuine DAT property or a GFX1 self-modify; either way the count model is unchanged.';

UPSERT finding:storm_shipped_descriptor_tear SET date='2026-07-03', confidence='high', status='confirmed',
  note='RECONCILES MEASURED FACT 1 (shipped descriptor 0x8C1F9F9C sums 24 on f96 but engine renders 49;
sums 67 on f918 but engine 53 — OVER one frame, UNDER another). The engine count needs THREE mutually-coherent
LIVE sources, each captured NON-ATOMICALLY by the wire and each reflecting a DIFFERENT engine pass:
 (1) the GFX2 dispatch head GFX2[(sid&0x7FFF)*4] — SELF-MODIFIES per animation sub-frame (re_kb/32: Storm
     0x1b04<->0x1b44, +/-8 records); the wire ships GFX2 static-once (frozen) => wrong nrec/record set.
 (2) the per-frame descriptor scratch 0x8C1F9F9C — reset+rebuilt from index 0 EVERY render pass (loc_8c0337bc)
     and SHARED across all objects; a serverPublish snapshot reflects the LATER HUD-pass rebuild, not the
     char pass (replica_live.cpp already snapshots it at CHARACTER-pass STARTRENDER for this reason).
 (3) node+0xDC — the per-object BASE index into that scratch; the differ MUST start Storm at HER +0xDC (e.g.
     25), not body0 s +0xDC=0. Reading the wrong window returns the OTHER body count: replica_live.cpp:941
     records the coherent char-pass dump = "24/24 + 49/49 both bodies byte-exact" — i.e. 24 is body0 and 49 is
     Storm. f96=24 is body0 s window mis-attributed to Storm (UNDER) OR the frozen-lighter GFX2 pose; f918=67
     is a heavier/torn descriptor or a heavier-frozen GFX2 pose (OVER). The self-modify swings both ways per
     sub-frame, so the frozen shipped value lands sometimes lighter (f96) sometimes heavier (f918) than the
     coherent current frame => the tear has NO fixed sign. CONCLUSION: the coherent ~49-53 is NOT reconstructible
     from the torn wire snapshot; it requires (a) the LIVE self-modified GFX2 head shipped fresh per frame
     (re_kb/32 fix generalized to EVERY Storm frame, not just 122244), (b) the descriptor snapshotted at
     char-pass STARTRENDER (replica_live.cpp doSnapshotTiledesc/snapshotCharPassTiledesc, already present but
     verify it is EFFECTIVE on the _cape_live capture — MAPLECAST_TILEDESC_CHARSNAP), and (c) render_frame
     indexing Storm s descriptor at HER u16(node+0xDC), not body0 s. BEST FIX = have render_frame RECOMPUTE the
     count via finding:storm_tilecount_authoritative from the LIVE GFX1 headers + LIVE (fresh) GFX2 records +
     sprite_id — all resident fields — removing the torn-scratch dependency entirely.';

RELATE finding:storm_tilecount_authoritative->cites->routine:loc_8c0344d4 SET kind='cites';
RELATE finding:storm_tilecount_authoritative->about->finding:descriptor_table_runtime_built SET kind='about';
RELATE finding:storm_tilecount_count_is_scale_invariant->about->finding:storm_tilecount_authoritative SET kind='about';
RELATE finding:storm_16x16_parts_reconcile->about->finding:storm_tilecount_authoritative SET kind='about';
RELATE finding:storm_shipped_descriptor_tear->about->finding:storm_tilecount_authoritative SET kind='about';
RELATE finding:storm_shipped_descriptor_tear->cites->finding:replica_storm_scramble_is_static_gfx2_self_modify_plus_torn_capture SET kind='cites';
