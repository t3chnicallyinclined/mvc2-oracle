-- ============================================================================
-- 65_tr_effect_capture_dropfix.surql
-- 2026-07-07 — WHY Storm's electric/hit TR effects are DROPPED by the P3D
-- capture, SETTLED BY MEASUREMENT (live MAPLECAST_P3D_CLASSHIST on headless +
-- static Effect-Poly scan). ROOT CAUSE: the emit-slot table is indexed by the
-- PCW ListType; TR effects ride slot2/class 0xAC (deferred), which the default
-- MAPLECAST_P3D_CLS={0x10} filter rejects. NOT a missing flush PC, NOT the
-- per-pass rewind. Apply, then 07_dedup_edges.surql.
-- ============================================================================
USE NS re DB kb;

UPSERT finding:p3d_emit_slot_is_listtype SET date='2026-07-07', confidence='high', status='confirmed',
  contribution_candidate=true,
  note='THE 3D drawer bank12.loc_8c129cc0 selects its SQ emit slot by the PCW LISTTYPE. Extraction
(bank12:23318-23337): slot_idx = (param_word0 >> 24) & 7 = the PCW ListType field (bits[26:24]); table
r10 = **(0x8C2AA508) = 0x8C32D328; entry = table[slot_idx]; SH4 SQ class byte = entry>>24; QACR set from
it. LIVE table (both _live4 static + live headless): [0]=0x100207E0 [1]=0xACF00040 [2]=0xACF126C0
[3]=0xACFA0040 [4]=0xACFB0040. => ListType 0 (OPAQUE, pcw 0x80xxxxxx / 0x808c002c) -> slot0 ->
class 0x10 = TA-DIRECT FIFO (0xE0-prefixed SQ to the TA); ListType 2 (TRANSLUCENT, pcw 0x828c002c) ->
slot2 -> class 0xAC = DEFERRED P2 command buffer 0x0CF126C0 (drained/sorted later); ListType 4
(PUNCH-THROUGH, pcw 0x848xxxxx) -> slot4 -> class 0xAC (0x0CFB0040). The OP-vs-TR pcw the sprite-render
expert measured (0x808c002c HUD vs 0x828c002c effect) differ ONLY in bit25 = the ListType bit, and THAT
BIT ALONE routes them to slot0(cls0x10) vs slot2(cls0xAC). This is the standard DC 5-list PVR arch, not
MVC2-specific.';

UPSERT finding:tr_effect_capture_drop_rootcause SET date='2026-07-07', confidence='high', status='confirmed',
  contribution_candidate=true,
  note='ROOT CAUSE of "Storm electric/hit effects missing" in the P3D capture, SETTLED BY LIVE
MEASUREMENT (headless, MAPLECAST_POLY3D=1 MAPLECAST_P3D_CLASSHIST=1 MAPLECAST_P3D_CLS=all, autoload
slot0, masher-driven hits). MEASURED at hit frames: the impact/electric TR tcws ride slot2 (class 0xAC):
0x4808EE00 (impact ring) @ vf=48303-07 s2=2/frame; 0x50091E00 @ vf=48378+ s2=3/frame; also 0x4808EB00,
0x48090000, 0x40097500, and 0x08080000 (additive flash quad, bursts to s2=20 at hit). Idle TR set on
slot2: 0x5008F700/0x0809BE00/0x1009CE00. Slot census: s0(cls0x10)=835, s2(cls0xAC)=65 idle -> ~90 hit.
The DEFAULT capture filter accepts class 0x10 ONLY (maplecast_oracle_hook.cpp:2723) => it FILTERS OUT
100% of slot2/cls0xAC => every TR effect is dropped. This is the coordinator suspected-reason (2), the
CLASS FILTER, CONFIRMED. The suspected-reason (1) PER-PASS REWIND is RULED OUT: every sampled vframe
(incl. hits) reported passes=1 (s_p3dPassesFrame=0) -> OP-HUD (slot0) and TR-effects (slot2) are built
in the SAME render pass before ONE STARTRENDER; the single-pass rewind retains BOTH. No missing flush PC
either: the classhist tallied these exact TR tcws AT the hooked param PC 0x8C129FE6 (kind-0 fires read
SQ w3), proving TR params DO cross the existing hook. CROSS-CHECK static (Effect Poly scan, _trslot.mjs):
model 0x0CEEB838 pcw=0x828c002c(LT2)->slot2->0xACF126C0 cls0xAC tcw=0x50097200; across all 241 effect
models every LT2 param -> slot2/cls0xAC and every LT0 -> slot0/cls0x10.';

UPSERT finding:tr_effect_capture_fix_spec SET date='2026-07-07', confidence='high', status='confirmed',
  note='CAPTURE-FIX SPEC (read-only RE handoff to flycast-internals; do NOT need to touch the drawer or
add a PC): (1) WIDEN the accepted slot-class set from {0x10} to {0x10, 0xAC}. Immediate no-rebuild
validation: env MAPLECAST_P3D_CLS=10,ac (the existing knob, maplecast_oracle_hook.cpp:2722-2735) makes
the TR effects flow; bake that as the new DEFAULT (or accept slots {0,2,4} equivalently - slot2=TR,
slot4=PT both cls0xAC; slot4 also carries 0x4808ee00 per the static scan). (2) NO NEW FLUSH PC: TR
params already cross the armed PC 0x8C129FE6; PC_P3D_TAB is complete for TR. (3) NO keep-pass-pair
needed for MVC2 in-match: measured passes=1 (OP+TR one build pass); the current per-pass rewind keeps
both. Leave the pass-pair idea shelved unless a multi-STARTRENDER scene is ever measured (monitor
s_p3dPassesFrame>0). (4) FLOOD GUARD: in the measured stage slot2 is small (65-90); the heavy list is
slot0 (835). A PRIOR note observed a heavy-TR stage flooding slot2 (stage geometry lists 0xB/0xD share
the SAME drawer loc_8c129cc0 via wrapper loc_8c1235b0, vs effects via loc_8c1235e0). If a stage re-floods
slot2 after widening, discriminate at the WALKER not the flush: the stage caller (list 0xB/0xD) and the
effect callers (lists 1-9) are distinct entries in loc_8c030452 dispatch - set a "current list-class"
flag the capture can read, keeping slot2 only for effect lists. Existing MC_P3D_MAX_LINES cap +
per-pass rewind bound overflow meanwhile. SYMMETRY: pairs with the injection-side TR-list split
(flycast-internals) - the OP-prefix wedge fix\'s translucent analog - to actually render the effects.';

UPSERT source:p3d_classhist_hit_capture SET kind='measurement',
  ref='headless build-headless-win/flycast.exe, MAPLECAST_POLY3D=1 MAPLECAST_P3D_CLASSHIST=1 MAPLECAST_P3D_CLS=all, autoload slot0 + _masher_fixed.mjs 12s; scratchpad/p3dcls.log (6404 [P3D-CLS] frames) + _trslot.mjs static Effect-Poly scan on _live4',
  note='Live [P3D] first SQ flush: kind=0 slot=2 cls=0xAC r6=0xE0F12600 r5=0xACF12620 (slot2 class byte
0xAC confirmed from r5>>24). Per-frame [P3D-CLS] at hit windows shows impact tcws 0x4808EE00/0x50091E00/
0x4808EB00/0x48090000 on s2; passes=1 every sampled frame. Static _trslot.mjs: ListType->slot->class map
+ impact model 0x0CEEB838 pcw 0x828c002c LT2 slot2 cls0xAC.';

RELATE finding:tr_effect_capture_drop_rootcause->cites->source:p3d_classhist_hit_capture SET kind='cites';
RELATE finding:tr_effect_capture_drop_rootcause->about->finding:p3d_emit_slot_is_listtype SET kind='about';
RELATE finding:tr_effect_capture_drop_rootcause->about->finding:3d_draw_emit_map SET kind='about';
RELATE finding:tr_effect_capture_fix_spec->about->finding:tr_effect_capture_drop_rootcause SET kind='about';
RELATE finding:p3d_emit_slot_is_listtype->cites->source:p3d_classhist_hit_capture SET kind='cites';
RELATE finding:p3d_emit_slot_is_listtype->cites->routine:loc_8c129cc0 SET kind='cites';
RELATE finding:tr_effect_capture_fix_spec->about->finding:hitspark_class_resolved SET kind='about';
