USE NS re DB kb;

UPSERT source:uvtcw_diff_122244 SET kind='capture_analysis',
  ref='tools/render-replica-poc/_uv_tcw_diff.mjs _probe.log _uvdiff.mcrr 122244',
  note='ENGINE-vs-render_frame per-part decode diff. CABLE(cid23, node 0x8c2688e4): 29/29 parts FIRST-DIV=OK/TCW (clean). STORM(cid42, node 0x8c268e88): all 51 parts FIRST-DIV=SEL. Engine body sels 229-251 + satellite sels 2912-3028; client emits sels 3170-3235 (sids 0x36a/0x37b cat-3 nodes) instead. NOT a decode bug (Cable proves decode correct).';

UPSERT finding:replica_storm_scramble_is_static_gfx2_self_modify_plus_torn_capture SET
  statement='ROOT CAUSE of the Storm (cid42/PL2A) scramble at frame 122244, pinned byte-exact (NOT the texture decode; decode is correct for Cable). TWO coincident anomalies, BOTH confined to exactly vframe 122244 and traced to a TORN/COMPOSITE capture, not a render_frame math bug:
(1) GFX2 SELF-MODIFY: the engine self-modifies the GFX2 cell-record dispatch entry GFX2[sid*4] in place per animation sub-frame. For the body sprite_id 0x42 the disc/default value GFX2[0x42*4]=0x1b04 (firstSel 234); at vframe 122244 ONLY, the engine had transiently written 0x1b44 (=0x1b04+0x40, 8 records deeper, firstSel 229). The render-replica server (core/network/maplecast_replica_live.cpp buildPrefixLocked) ships GFX2 STATIC-ONCE in the cached prefix, frozen at 0x1b04, and never re-ships it (the on-change gfxSig sparse-64 fold provably never samples region byte 0x788 = trueBase-rel 0x108, since 0x788 % 64 = 8; and the per-body GFX is only collected in collectFreshGfx by base+content-sig, which misses a single-u32 dispatch-table mutation). So render_frame walked the frozen 0x1b04 -> wrong pose. CONFIRMED: patching GFX2[0x42*4] 0x1b04->0x1b44 in the mcrr RAM image makes the body walker r11 match the engine (0xc65a1c4) byte-exact; the satellite dispatch entries (sid 0x2dd=0xfdf2, 0x2fb=0x10286) MATCHED the engine with delta 0 (only the body s self-modified entry was stale).
(2) CAT-3 ONE-FRAME CULL: render_frame (gen_walker_root.c, faithful loc_8c0308c2) dispatches ALL 5 in-count L5 slot entries; at 122244 the engine TRANSIENTLY culled the two cat=3 nodes 0x8c27d904(sid 0x36a) + 0x8c27c344(sid 0x37b) — they render on EVERY neighbouring frame 122245-122255 but NOT 122244 (a one-frame blink). Their node fields (+0x12C=0x20ff01, +0x130, active=0, etc.) are IDENTICAL to the rendered cat=4 sats; the only diff is cat (3 vs 4). The cull is a transient global/phase gate not in the shipped per-frame read-set. The differ aligns engine body sels against these cat-3 client sels by gfx1-order -> the 3170-range SEL mismatch.
BOTH anomalies occur at the SINGLE frame 122244. The shipped RAM image for 122244 is a COMPOSITE: static-once GFX2 (0x1b04, captured at prefix-build, pre-mutation) + dynamic-122244 char/slot state — internally inconsistent with the engine s 122244 render. The Cable body has no self-modified dispatch entry that frame, so it is clean. Disc PL2A GFX2[0x42*4]=0x1b04 (byte-identical to the shipped region, 0 diffs) -> applyLocalGfx (web/render-replica/local_gfx_overlay.mjs, called per-frame in replay.html liveApplyFrame) would REVERT the engine s runtime 0x1b44 back to disc 0x1b04 -> it CANNOT fix this and actively makes 122244 worse. This is NOT the never-resident static-gap of finding:replica_live_static_gfx_gap; it is RUNTIME SELF-MODIFICATION of an already-resident GFX2 region.',
  status='confirmed', confidence='high', date='2026-06-14';

UPSERT finding:replica_storm_scramble_fix SET
  statement='FIX (server core/network/maplecast_replica_live.cpp): GFX2 must be shipped FRESH per frame for active bodies (or at least its dispatch table head), because the engine SELF-MODIFIES GFX2[sid*4] per animation sub-frame; static-once shipping freezes a stale pose. Two-part: (A) ship the GFX2 region for every active BODY node as an ON-CHANGE dynamic tail using a signature that DENSELY covers the dispatch table (the head n*4 bytes, n~=1174 => ~4.7KB), not the sparse-64 gfxSig that misses single-u32 mutations; cheapest correct form = include the whole GFX2 region (~64-150KB) in the per-frame dynamic read-set for active bodies, or fold the dispatch table densely and re-ship the small head on change. GFX1 (pixels) does NOT self-modify -> keep static-once. (B) client: applyLocalGfx must NOT overlay the disc GFX2 dispatch table over a freshly-shipped one (disc holds the default 0x1b04, reverting the engine mutation). Either drop the GFX2 overlay entirely once the server ships fresh GFX2, or restrict the disc overlay to GFX1 only. SECONDARY (cat-3 one-frame cull): not a steady-state bug (cat-3 renders on all neighbouring frames); it is a torn-capture artifact at the single frame 122244 + a transient engine category gate not in the read-set. To eliminate residual per-frame skew, capture the GFX2/static state atomically WITH the dynamic state of the same vframe (the prefix is currently built once at an earlier frame). VALIDATE: re-capture a fresh frame with the GFX2-fresh server, then node tools/render-replica-poc/_uv_tcw_diff.mjs -> Storm parts FIRST-DIV SEL->OK like Cable.',
  status='proposed', confidence='high', date='2026-06-14';

RELATE finding:replica_storm_scramble_is_static_gfx2_self_modify_plus_torn_capture->cites->source:uvtcw_diff_122244;
RELATE finding:replica_storm_scramble_is_static_gfx2_self_modify_plus_torn_capture->cites->source:replica_live_cpp;
RELATE finding:replica_storm_scramble_is_static_gfx2_self_modify_plus_torn_capture->cites->source:gen_walker_c;
RELATE finding:replica_storm_scramble_fix->cites->source:replica_live_cpp;

-- ===========================================================================
-- FIX IMPLEMENTED + DEPLOYED 2026-06-14 (branch feat/render-replica-live)
-- ===========================================================================
UPSERT finding:replica_storm_scramble_fix SET
  status='implemented', confidence='high', date='2026-06-14',
  implementation='SERVER core/network/maplecast_replica_live.cpp: gfxSig() gained an isGfx2 path that
DENSELY folds the WHOLE GFX2 dispatch-table HEAD (front n*4 bytes, entry[0]==n*4, n~1174 => ~4.7KB) so
EVERY u32 dispatch entry contributes to the on-change signature. The old sparse-64 fold (rd32 every 64B)
provably never sampled region byte 0x788 (=trueBase+0x108, 1928=64*30.125, falls between samples) so a
single-u32 self-modify of GFX2[(sid&0x7FFF)*4] never flipped the sig -> GFX2 stayed frozen at disc 0x1b04.
Now any per-sub-frame dispatch self-modify flips the sig -> collectFreshGfx re-ships the small GFX2 region
as a dynamic on-change tail (gfxSig(pbase,plen,isG2[k])). GFX1 (LZSS pixels) does NOT self-modify -> keeps
the cheap sparse-64 fold, static-once. CAPTURE ATOMICITY: on first prefix build, _gfxShipped.clear() so the
SAME-vframe captureFrame re-ships GFX2 fresh, making the dispatch table internally consistent with the
dynamic char/slot state of that vframe (kills the torn-capture / one-frame artifact).
CLIENT web/render-replica/local_gfx_overlay.mjs: applyLocalGfx now overlays GFX1 PIXELS ONLY (node+0x15C);
the disc GFX2 overlay (node+0x160, ram.set(ent.gfx2,o2)) is REMOVED — it reverted the engine runtime
self-modified dispatch entry (Storm sid 0x42: disc 0x1b04 vs engine-live 0x1b44) back to the disc default
and actively made 122244 worse. The walker now reads the server fresh GFX2. replay.html overlay import
cache-busted ?v=rf3 -> ?v=gfx1only.
DEPLOY: dev box 65.109.77.178 build (MAPLECAST_HEADLESS=ON, Release) -> prod 149.28.44.118
/usr/local/bin/flycast md5 ad968c65c8d1775ce71b0efbeb32893d (prev 826dc5997f40f192339231d4532d5d7a, backup
/usr/local/bin/flycast.bak-20260614-200209); MAPLECAST_REPLICA_LIVE=1 gate preserved in
/etc/maplecast/headless.env. Client overlay md5 bc7e3967d59143b261c6b8421983e7f9.
VALIDATION PENDING: parent captures a fresh live frame (Oracle probe @0x8C1248CC -> /dev/shm/mc_probe.log)
+ fresh .mcrr, then node tools/render-replica-poc/_uv_tcw_diff.mjs <probe.log> <mcrr> <vf> -> Storm parts
must go SEL-garbage -> FIRST-DIV=OK (sels 229-250) like Cable.
OPEN (separate item, NOT in this fix): cat-3 one-frame transient cull at 122244 (gen_walker_root.c
loc_8c0308c2 dispatches all in-count L5 entries; engine transiently culled cat=3 nodes 0x8c27d904/0x8c27c344
at that single frame). A transient global/phase category gate not in the per-frame read-set; the
same-vframe atomic capture above should reduce the skew but does not by itself reproduce the engine cull.';

RELATE finding:replica_storm_scramble_fix->cites->source:gen_walker_c;
