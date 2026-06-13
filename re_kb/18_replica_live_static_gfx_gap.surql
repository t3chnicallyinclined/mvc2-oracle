-- ============================================================================
-- 18: render-replica LIVE — the STATIC GFX GAP root-cause of the grid divergence
-- (feat/render-replica-live). Pinned 2026-06-13 from the live captures + the
-- byte-exact transpiled walker, not guessed.
-- ============================================================================
USE NS re DB kb;

UPSERT source:replica_live_cpp SET kind='code',
  ref='core/network/maplecast_replica_live.cpp buildTables()/buildPrefixLocked()',
  note='Static prefix (16MB RAM + per-active-body GFX1@+0x15C / GFX2@+0x160) built ONCE on first armed in-match frame (_tablesBuilt + _prefixReady one-shot guards); cached _prefixZcst re-sent verbatim to every new client. GFX1/GFX2 are STATIC-once; the per-frame DYNAMIC read-set ships char structs/slot tables/idxtab/rectab/tiledesc/camera but NOT GFX1/GFX2.';

UPSERT source:gen_walker_c SET kind='code',
  ref='tools/render-replica-poc/gen_walker.c (transpile of loc_8c0344d4)',
  note='Byte-exact: r4=*(node+0x160)=GFX2; r0=*(node+0x144)&0x7FFF=sid; r11=GFX2+*(GFX2+sid*4); count=*(u16)r11. ALL body geometry (count + 8B records [dx][dy][flags][sel@+6]) comes from GFX2 at node+0x160 — the region shipped STATIC-once.';

UPSERT finding:replica_live_static_gfx_gap SET
  statement='The render-replica LIVE grid is an INPUT divergence, not a walker bug: the server ships each active body s GFX1(+0x15C)/GFX2(+0x160) art STATIC-ONCE in the cached prefix (built on the first armed in-match frame, _tablesBuilt/_prefixReady guards), while the per-frame dynamic read-set ships char structs/slot/idxtab/rectab/tiledesc/camera but NOT GFX. The transpiled walker (gen_walker.c == loc_8c0344d4) reads its ENTIRE geometry — cell count + records + sels — from GFX2 at node+0x160. If a body s art is not resident (or differs) at prefix-build time, that body s GFX2 cell records are FROZEN at the snapshot value; the walker reads stale/wrong-char records and emits a coherent-count but wrong/repeated tile set = the grid. PINNED on live.mcrr/live2.mcrr: the shipped static GFX table covers exactly ONE body (P2C1 GFX2@0xc8fb000, count=SHIPPED), while P1C3 (node 8c2699d0, GFX2@0xc789500) is NOT covered by any shipped static GFX region NOR any dynamic region (in-static-GFX=false, in-dyn=false). Both captures happened to be taken AFTER both chars  art loaded, so the frozen 16MB ram16 backdrop coincidentally held valid P1C3 records -> no grid in THESE captures (consistent with maxq_86 byte-faithful). The grid manifests only for a client connecting BEFORE a char s art is resident, where the one-body prefix freezes that char s GFX2 as zero/wrong. The client body_decoder.mjs (cellSels/decodePart) ALSO reads GFX1/GFX2 from the same seeded RAM, so stale GFX corrupts both geometry AND texture decode.',
  status='confirmed', confidence='high', date='2026-06-13';

UPSERT finding:replica_live_static_gfx_fix SET
  statement='FIX (server core/network/maplecast_replica_live.cpp): make the shipped GFX fresh per active body. Preferred option (a) ON-CHANGE DYNAMIC GFX: each frame, walk the slot table, for each body node read GFX1(+0x15C)/GFX2(+0x160) bases; if a base is not already covered by the shipped static GFX regions OR its content changed vs last shipped, emit that body s GFX1+GFX2 (0x20000 each, page-aligned) as a tagged DYNAMIC region (tag "GFXdyn") only on the frames where it changed. Client (replay.html liveApplyFrame/applyDynamic) routes a "GFXdyn" region the same as any RAM region (ram.set at addr&0xFFFFFF) — both render_frame and body_decoder then walk fresh GFX. WIRE COST: a body s GFX1+GFX2 = 256KB raw -> ~121KB zstd (GFX1 ~91KB, GFX2 ~30KB), shipped ONLY on (re)load, ~0 steady-state (GFX bases are constant across frames in capture). render_frame.wasm needs NO rebuild (render_frame.c unchanged); only the server read-set + client region routing change.',
  status='proposed', confidence='high', date='2026-06-13';

RELATE finding:replica_live_static_gfx_gap->cites->source:replica_live_cpp;
RELATE finding:replica_live_static_gfx_gap->cites->source:gen_walker_c;
RELATE finding:replica_live_static_gfx_fix->cites->source:replica_live_cpp;
