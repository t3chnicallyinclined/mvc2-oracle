-- ============================================================================
-- 23: render-replica LIVE — the CLIENT effect-path STUB is CLOSED: cat 1..4 body-
-- sprite satellites now RENDER via the transpiled loc_8c030af8 dispatch.
-- Confirmed 2026-06-13. Derived from marvelous2 bank03.asm:1526 loc_8c030af8 (the
-- disasm, NOT a model) and validated end-to-end at 0.0000px against the already-
-- 0.00px-vs-ASMTRACE body path. Apply:
--   tools/re_kb/rekb.sh @tools/re_kb/23_replica_live_satellite_dispatch.surql
-- ============================================================================
USE NS re DB kb;

UPSERT source:loc_8c030af8_satellite_setup SET kind='marvelous2',
  ref='bank03.asm:1526-1717 loc_8c030af8 (+ tail 1769-1781), pool 1719-1766',
  note='The CAT 1..4 satellite body-sprite setup, sibling of loc_8c03093c "Render Main Sprite". Slot-walk loc_8c0308c2 routes node+0x3==0 -> loc_8c03093c, node+0x3 in [1,5) -> loc_8c030af8. FIELD-BY-FIELD vs loc_8c03093c: SAME math for +0x12C gate, the loc_8c122560 transform (fr6=+0x3C fr5=+0x38 fr4=+0x34), the +0xE0/E4 anchor write, +0xE8 depth fmac(0.1, camZ@0x8c26a538, rparam@0x8c26a974[node+0x24*4]), +0xEC=CpsXScale*node[+0x50], +0xF0=CpsYScale*node[+0x54], +0x104=node[+0x48], +0x130/+0x134/+0x136 copies, the +0xEC/F0 /=(node[+0x20]/0x444b16de), and the node+0x14D zoom gate. ONLY TWO per-cat DELTAS: (1) loc_8c030af8 SKIPS the frame-global proj-setup calls loc_8c02e1a4+loc_8c1216c0 that loc_8c03093c makes first (both STUBBED in the transpile -> identical output); (2) the ZOOM branch (node+0x14D!=0, af8 1642-1701) indexes the OWNER char struct: idx=node[+0x1a4]*0x5A4 (pair stride) -> *(0x8c2684a8+idx) -> +node[+0x24d]*16, whereas loc_8c03093c (1386-1396) uses its OWN node[+0x168] animations ptr + node[+0x14d]*16. A satellite fetches its zoom anim from its owner fighter. Same body walker loc_8c0344d4 emits the sprite (ASMTRACE PC 0x8C034864).';

UPSERT source:satellite_dispatch_validation SET kind='transpile_validation',
  ref='tools/render-replica-poc/test_satellite_equiv.c + _e2e_equiv.mjs (render_frame_node.wasm)',
  note='On a REAL engine RAM frame (livecap satcap2 vframe 61740, body node 0x8C2688E4, node+0x14D==0 = the non-zoom path a body satellite takes): render_object_setup_030af8 deposits 9/11 walker fields BIT-IDENTICAL to render_object_setup_03093c; the 2 deltas are sub-pixel FP-contraction (+0xE4 anchorY 1 ULP = 0.0003px; +0xE8 is DEPTH not screen X/Y). END-TO-END through the shared body walker (_e2e_equiv.mjs: same node rendered as cat==0 BODY vs cat==4 SATELLITE), per-quad screen anchor diff maxDX=0.0000px maxDY=0.0000px over 76 quads, satellite hook confirmed firing (sat_count=1), quad_count preserved. Since the body path is itself 0.00px vs ASMTRACE/CHARQ (finding:emitter_render_model), the satellite path is TRANSITIVELY validated to the ASMTRACE ground truth at 0.00px. Live-satellite ASMTRACE cross-check is ready via _diff_sat.mjs (prod node 0x8C271E54, 70 parts, vframe 17887) for the next frame an assist/projectile fires.';

-- ---- CLOSE the open client stub finding ----
UPSERT finding:replica_live_effect_path_stub SET
  statement='CLOSED. The CLIENT effect-path stub is implemented: a cat 1..4 BODY-SPRITE satellite (Cable drone/projectile, assist, cape, extra limb) now RENDERS in render_frame. FIX: transpiled loc_8c030af8 (bank03:1526) FAITHFULLY into gen_render_satellite.py -> gen_render_satellite.c::render_object_setup_030af8 (a sibling of gen_render_object.c::render_object_setup_03093c); added render_object_full_satellite + render_frame_satellite_hook in render_frame.c (the shared body walker/submit/cursor path, only the setup differs); rewired gen_walker_root.py so cat!=0 routes to render_frame_satellite_hook (was the no-op render_effect_030af8). Also lifted mulu.w in codegen.py (used only in af8 zoom branch). New export render_frame_sat_count. Rebuilt web/render-replica/render_frame.{wasm,mjs} (+ node target) via build_wasm_frame.sh. VALIDATED (source:satellite_dispatch_validation): satellite deposits 9/11 fields bit-identical to the body setup (deltas sub-pixel FP/depth-only), and end-to-end the same node renders at 0.0000px through the body vs satellite path -> transitively 0.00px vs ASMTRACE (the body path is the 0.00px-validated finding:emitter_render_model). PURE effects (aura/hitspark, no body GFX2) still emit 0 tiles here (real Phase-3 cell-processor effect path stays unimplemented) — only body satellites were the missing/misplaced sprites. replay.html cache-busted ?v=satellite. Branch feat/render-replica-live.',
  status='confirmed', confidence='high', date='2026-06-13';

RELATE finding:replica_live_effect_path_stub->cites->source:loc_8c030af8_satellite_setup;
RELATE finding:replica_live_effect_path_stub->cites->source:satellite_dispatch_validation;
RELATE finding:replica_live_effect_path_stub->cites->source:prod_asmtrace_poolnodes;
