USE NS re DB kb;

-- ============================================================================
-- 2026-07-10 — render_frame (?bodysrc=wasm) vs sprite machine (?bodysrc=sprite):
-- full path diff + root cause of 3 live symptoms. VERDICT: invest in render_frame.
-- (mvc2-sprite-render-expert, code-traced.)
-- ============================================================================

UPSERT source:render_path_diff_trace SET kind='expert_trace',
  ref='webgpu-test.html SPRB.build/_bodyApplyFrame/_bodyMerge; sprite-client.mjs onGSTA(sid_xform)/buildEmitterDrawList/_emitEffectQuad/loadFxAtlas; render_frame.c render_object_full_ex/walker_0348c8/find_effect_block_start; maplecast_mirror.cpp taStripStage; extract_gfx1_atlas.py; HANDOFF-CHARFLIP-2026-07-09 §2/§4',
  note='Both modes share the ZCS2 wire; they differ only in who supplies the server-stripped {0x82,0x83,0x88,0x89} character quads. wasm: render_frame slot-walk, _bodyApplyFrame FILTERS output to exactly the strip set (symmetric -> no double). sprite: SPRB.build emitter (assemblyMode=true), NO block filter.';

UPSERT finding:render_path_verdict SET
  statement='CONFIRMED 2026-07-10. render_frame (?bodysrc=wasm) is the drawer to invest in; the sprite machine (?bodysrc=sprite) has 3 structural defects each requiring re-implementing render_frame capability. SYMPTOM ROOT CAUSES: (1) Storm Lightning MISSING in sprite mode — SPRB.build skips FX (charId===0xFE0), the effect texture band block 0x89 is stripped off the wire by taStripStage, AND bit15 scale-walker dispatch (sl.sid_xform) is set in onGSTA but never read (no walker_0348c8 geometry: GFX1-logical dims, Y-down anchor, sin/cos 180deg, per-axis UV span). render_frame routes (_sel&0x8000)->walker_0348c8 and draws it. (2) sprite GARBLE = swapped flip axes baked in: extract_gfx1_atlas.py (2026-06-11, predates re_kb/71) + buildEmitterDrawList use OLD axes (0x4000=X,0x8000=Y); corrected model 0x8000=H/texU facing-composed, 0x4000=V/texV (re_kb/71-72). Every part gets wrong mirror. + base-palette-only + flat single z (SPRB.z=0.00923). This is NOT the twTileYFirst/COLUMN-PAIR tile class (that is render_frame rebuild_tile_grid; the offline rip decodes each part as one whole detwiddled sprite, immune). (3) Sentinel LP rocket (sid 0x131, 19 parts) DOUBLE-DRAW is SPRITE-PATH-ONLY: SPRB.build has no {82,83,88,89} filter so kept-wire satellites draw twice (wire correct + emitter ~20px off, _bodyMerge appends leftover body polys). wasm path does NOT double (symmetric strip/filter by construction; render_frame emits no para4) — its rocket bug is a SINGLE misplaced part (177/1359 frames divergent emit order). wasm advantages: draws bit15 supers, corrected flip+carve, per-part z=1/(W+0.001k), double-draw-guarded, geometry-byte-exact at pairing S-1.',
  status='confirmed', confidence='high', date='2026-07-10';

RELATE finding:render_path_verdict->cites->source:render_path_diff_trace;

-- The tiny-wire goal is met by shrinking render_frame's wire, not switching drawers.
UPSERT finding:render_frame_wire_shrink_plan SET
  statement='render_frame stays the drawer; get the tiny wire by (a) v2 dirty-diff the /replica-live dynamic regions (measured ~150 changed B/frame -> ~370 B gzip BYTE-EXACT reconstruction over 9600 frames, re_kb/73) and (b) MERGE the /replica-live state onto the main ZCS2 socket under one vframe -> kills the two-socket body(V)/wire(V-1) pairing drift = the Storm forward/back garble + down-flicker (webgpu-test.html _bodyMerge ring, widened 16->120 in 5f66d5641). Open wasm geometry bug to also fix: Sentinel rocket single misplaced part (emit-order divergence).',
  status='planned', confidence='high', date='2026-07-10';

RELATE finding:render_frame_wire_shrink_plan->cites->finding:render_path_verdict;
RELATE finding:render_frame_wire_shrink_plan->cites->finding:state_wire_entropy;
