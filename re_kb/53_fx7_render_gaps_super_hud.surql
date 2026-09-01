USE NS re DB kb;

-- ============================================================================
-- 2026-06-29 — fx7 A/B (GSTA render_frame reconstruction vs 7200 MIRROR real-TA,
-- HUD_TA armed so HUDQ present). Capture: _live_fx7.gsta.mcrr (1320f) +
-- _live_fx7.mirror.zcst (1320f). Tools: _fx7_locate/_fx7_super_ab/_fx7_paramtypes/
-- _fx7_hud/_fx7_hud_fill/_fx7_band_aligned.mjs. render_frame_node.mjs (byte-exact wasm).
-- ============================================================================

UPSERT source:fx7_ab SET kind='measurement',
  ref='tools/render-replica-poc/_live_fx7.{gsta.mcrr,mirror.zcst}; render_frame_node.mjs sprite-TA reconstruction; web/webgpu/{frame-decoder,ta-parser}.mjs; reference frames scratchpad/vid3/{bigwhite,hud_t1,lightning}.png. Drift caveat: GSTA<->mirror streams index-drift (frame drops) so exact-frame per-pixel A/B is skew-limited; band/param-type multiset A/B is robust to drift.',
  note='Super windows located by GSTA quad spikes: fi~290-330, fi~470-590 (Lightning Storm), fi~1030-1070 (peak 274 @ fi1040). Camera M1/M2 (0x8C2D6B18/0x8C2D6AD8) confirmed NON-degenerate every super frame (M1=const viewport, M2 well-formed) -> NOT a stage-camera blowup.';

-- ISSUE 5 (NEW): the fullscreen SUPER-FLASH (bigwhite.png) is a PARAM-TYPE GAP, not a bad quad.
UPSERT finding:gsta_super_flash_paramtype_gap SET
  statement='CONFIRMED structural cause. The fullscreen white/black jagged super-flash (bigwhite.png) is NOT a mis-sized sprite quad and NOT a stage-camera blowup. MEASURED: render_frame reconstructs ONLY ParaType-5 sprite params (GSTA fi=1040 param hist = pt0:1 pt5:274, ALL sprite quads are the standard 53x69 body-tile size — NO giant quad). The MIRROR real-TA is dominated by ParaType-1 polygon (~1700/frame) + ParaType-7 vertex (~2900) + pt4 (~130) + pt5 (50); at the SUPER PEAK (mirror fnum 495-560,1040) the mirror DROPS to ~1600-1900 records of ONLY pt1/pt7 polygons with pt5=0 (bodies gone) — i.e. the engine REPLACES the scene with a fullscreen ParaType-1 flash/dim polygon overlay. Our GSTA wire + render_frame emit NONE of that pt1/pt7 polygon stream (render_frame only synthesizes sprite quads). So the bigwhite = the engine super-flash POLYGON our reconstruction does not carry/draw, letting the stage + over-emitted effect sprites show through wrong against an un-flashed/un-dimmed background. Camera (M1/M2) ruled NON-degenerate every super frame. FIX DIRECTION (needs design, NOT a cull): the super flash/dim is engine pt1 geometry absent from the state wire; either (a) synthesize the fullscreen flash overlay client-side keyed by a super-active flag in the read-set, or (b) detect the engine flash state and render render_frame bodies over a correct dim. Validate vs the mirror pt1 polygon extent. re_kb/50,/51 sibling.',
  status='confirmed', confidence='high', date='2026-06-29';

-- ISSUE 3: HUD health/meter STATIC = fill-not-tracking (CONFIRMED state DOES change; geometry does NOT).
UPSERT finding:gsta_hud_fill_static_confirmed SET
  statement='CONFIRMED fill-not-updating (NOT a no-state-change). The user-reported static HUD: across the combo the underlying STATE IS CHANGING in the wire — P2 health (char P2C1+0x420, RAM 0x2688E4+0x420) drops 144->140->133->120->107->96->78->55 and the meter (0x8C289646) fills 98->113->129->144 then spends to 0 then rebuilds 16->21->29->36->43 (so the user IS dealing damage; state is present in the read-set). BUT the HUDQ life-bar quad GEOMETRY does NOT track it: the P2 magenta fill quad (x[439..591] w=152.2, col=fefe3ffe) is BYTE-IDENTICAL at p2hp=140 (fi=79) and p2hp=55 (fi=396) — same x-extent, the right edge never moves; UV widths (uw) are per-quad constant too, not health-driven. So the HUDQ collector ships the full-width bar TRACK quad, fill-invariant — the depleting fill mechanism (the engine moves the bar quad right-edge / draws a clipped fill proportional to hp) is NOT captured. CAVEAT: the engine real life bars are ParaType-1/7 POLYGONS (mirror pt1~1700, pt5=50 are only the body sprites), NOT sprites — collectHudQuads (MAPLECAST_HUD_TA, maplecast_oracle_hook.cpp:3058) parses the surviving HUD pass; verify whether the depleting bar is among the pt5 quads it keeps or is a pt1 poly it skips. FIX DIRECTION: either capture the bar fill as the engine clips it (the moving right-edge quad) in the HUDQ collector, OR (browser path) drive the procedural hud-client.mjs _lifeBar from the shipped health state (which IS in the wire) instead of trusting a fill-static HUDQ quad. NOTE issue-2 magenta = correct (re_kb/51, no action).',
  status='confirmed', confidence='high', date='2026-06-29';

-- ISSUE 1a residual: blocks are SIBLING body band 0x84xxx + over-emitted effect 0x88/0x8a (CONFIRMED band, cull NOT yet extended).
UPSERT finding:gsta_motion_blocks_residual_bands SET
  statement='CONFIRMED bands (cull extension NOT shipped — drift blocks exact validation). The residual motion/super BLOCKS the 0x85xxx cull (re_kb/51) does not remove are OTHER bands: band-multiset A/B (robust to drift) shows GSTA over-emits vs the best-Jaccard mirror super frame — at fi=1040/1050 (super peak) GSTA emits +80/+96 of EFFECT band 0x88000 and +36/+44 of band 0x8a000 that the mirror has ZERO of; during heavy motion fi=480/520 GSTA emits +55/+88 of BODY band 0x84000 the mirror lacks. So the residual blocks = sibling body band 0x84xxx (motion) + over-emitted effect bands 0x88/0x8a (super) — same char-pass-transient idxtab staleness as re_kb/50 now landing on 0x84/0x88/0x8a instead of the already-culled 0x85xxx. NOT YET FIXED: exact-frame validation is drift-limited (Jaccard 0.60 at super peak; the index-aligned mirror frame is not pixel-coincident), so a blind cull extension to 0x84/0x88/0x8a risks culling LEGITIMATE bodies/effects (0x84 is a real body band the mirror uses heavily, 0x88 is a real effect band) — DO NOT ship the cull extension without a frame-exact RAM dump (DUMP_RAM trigger armed) to confirm which specific recidx/TCW are provably-wrong on a coincident frame. re_kb/50,/51 sibling; per [[feedback_data_source_decision_rules]] + re_kb/44 (no unvalidated ship).',
  status='confirmed', confidence='medium', date='2026-06-29';

RELATE finding:gsta_super_flash_paramtype_gap->cites->source:fx7_ab;
RELATE finding:gsta_hud_fill_static_confirmed->cites->source:fx7_ab;
RELATE finding:gsta_motion_blocks_residual_bands->cites->source:fx7_ab;
RELATE finding:gsta_motion_blocks_residual_bands->about->finding:gsta_super_effect_overtile;
RELATE finding:gsta_hud_fill_static_confirmed->about->finding:gsta_hud_meter_open;
