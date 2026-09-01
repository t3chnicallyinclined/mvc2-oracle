-- ============================================================================
-- 22: render-replica LIVE — the SATELLITE OBJECT-POOL read-set gap is CLOSED on
-- the server; the residual missing satellite is now a CLIENT effect-path stub.
-- Confirmed 2026-06-13 from prod ASMTRACE (149.28.44.118 /dev/shm/mc_assembly.log)
-- + a live replica-live capture (/tmp/poolcap.mcrr vframe 17887). NOT guessed.
-- Apply: tools/re_kb/rekb.sh @tools/re_kb/22_replica_live_objpool_readset.surql
-- ============================================================================
USE NS re DB kb;

UPSERT source:objpool_initconsts SET kind='marvelous2',
  ref='bank04.asm:11601-11756 loc_8c044dce pool init',
  note='Satellite object pool init. base const loc_8c044ec8=0x8C26AA54; stride const loc_8c044ea4=0x1D0; span const loc_8c044ed8=0x1D000 -> 256 nodes (0x1D000/0x1D0=256). Allocator loc_8c044f12 sets node+0x3=category. Pool span = [0x8C26AA54, 0x8C287A54).';

UPSERT source:prod_asmtrace_poolnodes SET kind='live_capture',
  ref='prod 149.28.44.118 /dev/shm/mc_assembly.log col18=node (r14)',
  note='Live ASMTRACE proves the slot-walk renders out-of-char-struct nodes. frame 708746 nodes 0x8C26AFC4/0x8C26B194/0x8C275684 = pool idx 3/4/58; frame 17887 node 0x8C271E54 = pool idx 64 (70 parts, sid 0x29A, owner cid 0x17 Cable). ALL land exactly on 0x8C26AA54 + N*0x1D0, N in [0,256).';

-- ---- CONFIRMED: server read-set gap (the missing/misplaced sprites) -> CLOSED ----
UPSERT finding:replica_live_objpool_readset SET
  statement='The render-replica LIVE dyn read-set shipped only the 6 fighter char structs (0x8C268340 6*0x5A4). But the slot-walk loc_8c0308c2 renders EVERY on-screen node: cat==0 -> render_object_full loc_8c03093c (body), cat 1..4 -> loc_8c030af8 (effect/satellite), and loc_8c030af8 reads the SAME node fields (+0x24 palid, +0x34/0x38/0x3C world pos, +0x50/0x54 scale, writes +0xE0/E4 anchor + +0xEC/F0 scale) and emits a body-like sprite through the SAME body walker loc_8c0344d4 (PC 0x8C034864). Satellite/projectile/cape/drone objects live in the SATELLITE OBJECT POOL [0x8C26AA54, 0x8C287A54) = 256 * 0x1D0 (cited source:objpool_initconsts). Their +0xE0..+0xF0 anchor/scale were NOT shipped -> render_frame read STALE -> the user-visible missing/misplaced sprites when an assist/projectile/super fires. FIX (CONFIRMED deployed): add one dyn region D(0x8C26AA54, 0x1D000, "objpool") to maplecast_replica_live.cpp buildTables() (the whole pool; render_object_full reads scattered fields +0x24..+0x184 so a per-node window is fragile, and the GFX those nodes reference already lives in the once-shipped 16MB static RAM image + the per-frame on-change GFX slot-walk, so NO GFX-side server change is needed). VALIDATED on live capture /tmp/poolcap.mcrr vframe 17887: pool node 0x8C271E54 now shipped via the objpool region with NON-stale +0xE0 anchorX=533.86 (matches engine ASMTRACE screenX 530..534 for that node), maxDX=maxDY=0.000px. Binary 3aecf73b719c4ecb95545418aae6bc57 deployed surgically to prod /usr/local/bin/flycast (backup flycast.bak-20260613-183748 = prior 2068f134); MAPLECAST_REPLICA_LIVE=1 still gated, port 7212 listening, dyn table now 15 regions incl objpool@8c26aa54:118784. Branch feat/render-replica-live commit 1f54b8706.',
  status='confirmed', confidence='high', date='2026-06-13';

-- ---- NEW open item: the satellite still does not RENDER client-side (effect stub) ----
UPSERT finding:replica_live_effect_path_stub SET
  statement='AFTER the server read-set fix, the cat 1..4 satellite STILL does not render in render_frame because the CLIENT transpiled root walker (tools/render-replica-poc/gen_walker_root.c) dispatches cat!=0 nodes to render_effect_030af8 which is a Phase-3 STUB (no-op, "DEFER to Phase 3"). Proof: /tmp/poolcap.mcrr vframe 17887 slot-walk = L5 node 0x8C268340 cat=0 (Sentinel body), L6 node 0x8C2688E4 cat=0 (Cable body), L7 node 0x8C271E54 cat=4 (Cable drone/satellite); render_frame emits 60 quads (2 bodies) and SKIPS the 70-part cat=4 node. ROOT CAUSE has SHIFTED from server (data now present, validated 0.00px) to client (the effect path is unimplemented). FIX (sprite-render side, mvc2-sprite-render-expert): in gen_walker_root.c route cat in [1,5) satellites that carry a body sprite through render_object_full (loc_8c030af8 reads the same +0x24/+0x34/+0x38/+0x3C/+0x50 fields and emits a body via loc_8c0344d4, bank03.asm:1526 loc_8c030af8 gate cmp/pl & cmp/ge 0x5). The data the client needs (node anchor/scale/GFX) is now fully shipped; only the dispatch is missing.',
  status='open', confidence='high', date='2026-06-13';

RELATE finding:replica_live_objpool_readset->cites->source:objpool_initconsts;
RELATE finding:replica_live_objpool_readset->cites->source:prod_asmtrace_poolnodes;
RELATE finding:replica_live_objpool_readset->about->struct:object_pool_node;
RELATE finding:replica_live_effect_path_stub->cites->source:prod_asmtrace_poolnodes;
RELATE finding:replica_live_effect_path_stub->about->struct:object_pool_node;
