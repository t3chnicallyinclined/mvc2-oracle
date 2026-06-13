-- ============================================================================
-- 08_emitter_render_model.surql
-- COMPLETENESS PASS (2026-06-11): consolidate the off-SH4 emitter render model.
--
-- This file makes a fresh DB rebuild include the FULL emitter subgraph:
--   * the MASTER finding emitter_render_model (end-to-end pipeline, every
--     constant/formula cited to its source),
--   * every session sub-finding re-asserted (idempotent UPSERT) so they survive
--     a rebuild (they were previously only live-UPSERTed, not seeded),
--   * the VALIDATION method (tool + finding) as the gate for geometry changes,
--   * the OPEN items (flip/opposite-facing unvalidated, roster re-bake pending),
--   * all about/cites edges connecting the subgraph.
--
-- Apply AFTER 06_findings_sources.surql, then run 07_dedup_edges.surql.
-- ============================================================================
USE NS re DB kb;

-- ---- supporting sub-routine nodes (cited inline by the geometry findings) ---
UPSERT routine:loc_8c034548 SET pc='0x8C034548', bank='bank03',
  role='pen X-accumulator negate on facing',
  note='neg r10 — negates the cumulative pen X accumulator when facing@node+0x110 != 0. The POSITION half of the facing reflection (the texture-U mirror is the separate neg r8 @ loc_8c0346c4). Reflects the pen ORIGIN only; part width enters via tileX, NOT the reflection (see emitter_reflection_axis).';
UPSERT routine:loc_8c0345c4 SET pc='0x8C0345C4', bank='bank03',
  role='per-tile lay-down loop',
  note='Tile loop inside loc_8c0344d4: lays each storage tile at node+0xE0 + (Xacc+tileX)*scale. Tile span = FULL storage dims sw*8 x sh*8 (header +2/+3). Pairs with loc_8c03478e.';
UPSERT routine:loc_8c0346c4 SET pc='0x8C0346C4', bank='bank03',
  role='texture-U mirror on facing^0x4000',
  note='neg r8 — mirrors the texture U coordinate. Driven by facing XOR the part 0x4000 flag, i.e. the SAME facing sense as the position neg r10 (loc_8c034548) — they MUST stay in lockstep (emitter_facing_rule).';

-- ---- tools (validation gate) ------------------------------------------------
UPSERT tool:validate_emitter_geom SET kind='geometry validator', path='tools/validate_emitter_geom.py',
  date='2026-06-11',
  note='THE GATE for any emitter geometry change — run it, do not eyeball. Diffs the computed per-part quads (cumulative pen + full-span tile + scale) against the live CHARQ ground truth _ryu_capture/probe_body_uv.json, per part. PL00 current status: dW=dH=0.00 on ALL sels (single + multi-tile 265/278/279), dX/dY uniform anchor quantization only => RELATIVE residual 0.00px = geometry PROVEN exact. Loads the BAKED PL00_parts.json dims (no override). Any future change to pen/scale/span/flip must re-pass this at 0.00px relative before deploy.';

-- ============================================================================
-- SESSION SUB-FINDINGS — re-asserted idempotently so a rebuild keeps them.
-- (statements verbatim from the live DB; UPSERT is update-in-place by id.)
-- ============================================================================

UPSERT finding:emitter_scale_derived SET date='2026-06-10', confidence='high', status='confirmed',
  note='Scale closed: native->screen = FULL CPS, tileScale=1.0 (NOT 0.5/CPS-half). The earlier CPS/2 calibration was superseded once the full-span baker landed.',
  statement='EMITTER native->screen scale = FULL CPS (5/3,15/7) i.e. tileScale=1.0 NOT 0.5. Per PVR cell screen_w=native*CPSX screen_h=native*CPSY EXACTLY (probe_body_uv 8/16/32px -> 13.3/26.7/53.3 x 17.1/34.3/68.6, <0.01px). Full figure: offline sid64 native 80x128 -> tileScale=1.0 screen 133x274 = CHARQ probe true 137x274 (resid X 3.0pct Y 0.0pct). tileScale=0.5 gave 67x137 = 2x too small (operators ~1.6x bug). Disasm loc_8c0344d4: final=node+0xE0/E4+(pen+tile)*scale@+0xEC/0xF0, node scale=1.0 in chosen_body. FIX tileScale 0.5->1.0.';

UPSERT finding:emitter_facing_rule SET date='2026-06-11', confidence='high', status='confirmed',
  note='Facing rule: ONE facing byte (node+0x110) gates BOTH the position reflection (neg r10) AND the texture-U mirror (neg r8); they must stay in lockstep. Client bakes facing-neutral, so bodyFace = NOT owner.facing drives both.',
  statement='loc_8c0344d4 :10271-10314 - facing@node+0x110 drives TWO transforms that MUST use the SAME sense (disasm reads ONE facing byte for both): (1) POSITION = the pen accumulator is negated (loc_8c034548 neg r10,r10 when facing!=0); (2) TEXTURE-U mirror = facing XOR the part 0x4000 (loc_8c0346c4 neg r8). LOCK (client buildEmitterDrawList v=74, 2026-06-11): the offline atlas bakes FACING-NEUTRAL (rip accumulates +dx only) and the operator-confirmed correct body sense is the INVERTED owner.facing byte, so faceInv DEFAULTS TRUE and BOTH posReflect AND the texture-U flip derive from the SAME bodyFace=NOT owner.facing - keeping neg r10 and neg r8 in lockstep. The prior bug inverted ONLY the POSITION gate (_emitFaceFlip) while flip used the raw byte, so 0x4000 parts composed against the OPPOSITE sense and popped side-to-side (the flashing the operator saw). Y analogue: 0x8000 reflects Y-position (no facing XOR), V-texture separate (emitFlipY).';

UPSERT finding:emitter_reflection_axis SET date='2026-06-11', confidence='high', status='confirmed',
  note='Reflection axis: reflect the pen ORIGIN only (tlx = 2*A - tlx), NOT the whole rect. Reflecting the rect (2*A-(tlx+w)) injected a spurious -w = one part-width offset (~50-70 game-px) that flipped sign with facing.',
  statement='EMITTER OFFSET FIX (client buildEmitterDrawList v=74, 2026-06-11). SYMPTOM: red emitter body sat ~50-70 game-px to one side of green TA-truth, and the offset FLIPPED sides when facing was corrected (h_08/h_12 left Ryu: red center ~228 vs green ~158 game-px). ROOT CAUSE: the disasm (loc_8c0344d4, GFX-NOTES 3a :170) negates the pen ACCUMULATOR (neg r10) then lays each tile at node+0xE0 + (Xacc+tileX)*scale - part width enters ONLY via tileX (0..lw), NOT the reflection; internal pixel mirror is the SEPARATE texture-U flip (neg r8). The client reflected the whole RECT (2*A - (tlx+w)), injecting a spurious extra -w = one full part-width (~53-106 screen-px) = the measured offset, which flips sign with the facing gate. FIX: reflect the pen ORIGIN only (tlx = 2*A - tlx); rect still extends rightward and flip mirrors U. Exposed _asmCfg.reflectEdge (default false=origin; true=old +w form A/B) and _asmCfg.reflectDx (game-px axis nudge for a residual non-zero hotspot seed node+0x134, baked 0). A = owner.exx (node+0xE0 foot) + gdx + reflectDx.';

UPSERT finding:emitter_y_axis_fix SET date='2026-06-10', confidence='high', status='confirmed',
  note='Y-axis: atlas stores parts BOTTOM-UP; render-time invert texture V ONLY (flipY attr, sampling), quad placement stays. emitFlipY default TRUE; XORs the per-record 0x8000 geometry Y-mirror.',
  statement='EMITTER Y-AXIS FIX (sprite-client.mjs buildEmitterDrawList selKeyed branch, v=69 md5 69b7ab32). SYMPTOM: emitter body rendered upside-down (head-down/feet-up) AND below the foot-anchor vs the upright green TA-truth. ROOT CAUSE: the selKeyed part atlas (PL00_parts.png, Oracle live-VRAM / GFX1-detwiddle build) stores each parts PIXELS BOTTOM-UP (row 0 = bottom of the part), so sampling with the normal top-to-top V reads every tile upside-down; with correctly-placed quads the whole figure read inverted. The cumulative-pen PLACEMENT was ALREADY correct per KB cumulative_pen_geometry: baked dy is negative = builds UP from the foot; bank03 loc_8c0344d4 does Y-acc -= dy. Verified offline: sid126 spans screen-Y 328..439 with the foot at 433 = feet at bottom, head at top. pvr2-renderer (the green TA path) uses the same standard top-left convention (clip.y = 1 - py/H, V = c.y) as sprite-gpu, so the sprite-gpu projection is NOT the bug. FIX: invert the per-part texture V ONLY (the shader flipY attr does vy = 1 - c.y, sampling-only, the quad does NOT move) for every selKeyed part. Added window._emitFlipY (default TRUE = upright), emitted as flipYTex = (r.flipy XOR emitFlipY) so the global V-correction XORs the per-record 0x8000 geometry Y-mirror; the geometry reflection tly = 2*eyy-(tly+h) stays driven by r.flipy alone. Orthogonal to faceInv (X) and tileScale/CPS (scale), so it does NOT regress the v=68 scale/facing calibration. Offline-validated against PL00_parts.png: V-flip renders red-headband-top / feet-bottom upright Ryu standing on the foot-anchor; un-flipped renders him head-down.';

UPSERT finding:emitter_part_flashing SET date='2026-06-11', confidence='high', status='confirmed',
  note='Part flashing/detaching: two stacked causes, both fixed. (a) position reflected on flip not facing (v71); (b) flip and position used different facing sense (v74); plus the detached-foot offset was the reflection-axis bug. Any remaining vanish = an uncaptured selector (coverage), not geometry.',
  statement='EMITTER PART FLASHING / DETACHING - two stacked causes, both now fixed. (a) PRE-v71: the X-position reflection was gated on flip=facing^r.flip, so r.flip=1 parts of mixed-flip poses (61/441 for PL00) jumped to screen-right off the body and popped in/out as the live sprite_id animated through mixed vs non-mixed poses. FIXED by reflecting POSITION on facing ALONE (v71). (b) v74 RESIDUAL: after the facing lock (faceInv default TRUE) the texture-U flip and the position reflection must use the SAME bodyFace - pre-v74 _emitFaceFlip inverted ONLY posReflect while flip kept the raw byte, so parts carrying their own 0x4000 composed against the OPPOSITE sense and jumped side-to-side. FIXED by deriving BOTH posReflect AND flip from one bodyFace=NOT owner.facing (see emitter_facing_rule). (c) The DETACHED feet in h_08 were the ~70px reflection-axis offset (emitter_reflection_axis), not a coverage gap - the foot part reflected to the wrong X. No separate selector-gap coverage item identified for PL00 idle/jab; if parts still vanish on a specific sid after v74 it is an uncaptured selector (skipSel counter), a coverage item, not a geometry bug.';

UPSERT finding:offline_gfx1_lzss_feasible SET date='2026-06-10', confidence='high', status='resolved',
  note='Offline GFX1 LZSS decode (loc_8c0354c0) is self-contained per-part, ported to Python, bit-exact vs live captures and all 1533 PL00 sels. Whole atlas extractable from the disc, no play-capture.',
  statement='RESOLVED: Offline GFX1 part-pixel extraction from the disc IS FEASIBLE. marvelous2 loc_8c0354c0 is a self-contained per-part byte LZSS (window = output buffer, NO preset dict, NO cross-part carry). Ported to Python and validated BIT-EXACT against 6 live-captured raw tiles (sels 1,13,24,34,61,127 from _ryu_capture) AND all 1533 PL00 sels decode cleanly with zero runaways. The earlier 752KB-runaway dead end was a DECODER BUG (wrong literal/backref polarity + off-by-one copy count = (byte&0x0F)+2, NOT a window-init or fundamental issue). Recipe: part_base = GFX1 + *(u32)(GFX1+sel*4); w=hdr[+2]*8 h=hdr[+3]*8; len=w*h/2; decode stream@+4 with the corrected decoder; PAL4->ARGB4444 via Dat_Pal. This extracts the whole char atlas (sel->pixels) offline from GFX_DATA_00.BIN for EVERY character, no play-capture needed.';

UPSERT finding:gfx1_part_twiddle_storage SET date='2026-06-10', confidence='high', status='resolved',
  note='GFX1 part texels are PVR-TWIDDLED. Detwiddle with flycast ConvertTwiddlePal4 over the FULL part WxH (not min-square). Implemented in extract_gfx1_atlas.py detwiddle_pal4.',
  statement='GFX1 part texels (the bit-exact decodeA output, == live 0x0CE60000) are stored PVR-TWIDDLED, NOT linear. Detwiddle = flycast texconv.cpp ConvertTwiddlePal4 over the FULL part W x H: bcx=log2(W), bcy=log2(H), twop=detw[0][bcy][x]+detw[1][bcx][y], 4x4 nibble blocks in PAL4_ORDER. The min(W,H) square-block twiddle (old rip_gfx2_assembly tile_to_indices) is WRONG for non-square parts (stripes them). Validated byte-identical vs _ryu_capture/decode_flycast.py swapXY=False (sel 1 torso decodes coherent; the path that produced char_tight Ryu). Implemented in tools/extract_gfx1_atlas.py detwiddle_pal4.';

-- ============================================================================
-- THE VALIDATION FINDING (the gate)
-- ============================================================================
UPSERT finding:emitter_geom_validation_gate SET date='2026-06-11', confidence='high', status='confirmed',
  note='The numerical gate for emitter geometry: validate_emitter_geom.py vs CHARQ probe_body_uv.json. 0.00px relative residual on PL00 = proven exact. Run it (do not eyeball) before any geometry deploy.',
  statement='EMITTER GEOMETRY VALIDATION METHOD = tools/validate_emitter_geom.py. It diffs the computed per-part quads (GFX2 cumulative pen + FULL-span tile + full-CPS scale + facing/flip) against the live CHARQ ground truth _ryu_capture/probe_body_uv.json, PER PART, loading the BAKED PL00_parts.json dims (no override). RESULT (PL00, Ryu sid 68, facing=1, 6 sels incl multi-tile 265/278/279): dW=dH=0.00 on every sel, dX/dY a uniform anchor quantization (+0.70/+0.40) only => RELATIVE residual 0.00px = geometry PROVEN exact. THIS IS THE GATE: any future change to pen / scale / span / flip / reflection MUST re-pass validate_emitter_geom.py at 0.00px relative before deploy — do not eyeball the render. Current status: PL00 geometry CLOSED at 0.00px (all sels, single + multi-tile).';

-- ============================================================================
-- THE MASTER FINDING — the COMPLETE off-SH4 emitter render model, end-to-end.
-- ============================================================================
UPSERT finding:emitter_render_model SET date='2026-06-11', confidence='high', status='confirmed',
  note='MASTER: the complete off-SH4 emitter render model end-to-end. Every constant/formula cited to loc_8c0344d4 (geometry), the GFX1 header (dims), loc_8c0354c0 (pixels), and the CHARQ/validate captures. Sub-findings: emitter_geom_validated, emitter_scale_derived, emitter_facing_rule, emitter_reflection_axis, emitter_y_axis_fix, emitter_part_flashing, offline_gfx1_lzss_feasible, gfx1_part_twiddle_storage; gated by emitter_geom_validation_gate; OPEN: emitter_flip_unvalidated, emitter_roster_rebake_pending.',
  statement='OFF-SH4 EMITTER RENDER MODEL — COMPLETE PIPELINE (master, 2026-06-11). Reproduces MVC2 body rendering with the SH4 OFF, from GSTA state + an offline disc-extracted atlas. Geometry is NUMERICALLY CLOSED at 0.00px relative (validate_emitter_geom.py vs CHARQ).
[INPUT] per node from GSTA: sprite_id (char+0x144 u16), facing (char+0x110 u8), screen anchor screen_x/y (node+0xE0/+0xE4 f32, written per-frame by loc_8c03093c), palette (Dat_Pal char+0x164).
[ASSEMBLY] GFX2 cell = GFX2 + *(u32)(GFX2 + (sprite_id & 0x7FFF)*4); first u16 = record count; then count x 8-byte records [dx s16][dy s16][FLAGS u16][sel u16] (cite: loc_8c0344d4 bank03; dataformat gfx2_cell; rip_gfx2_assembly read_cells, cell index == sprite_id).
[PEN] cumulative running pen across records: Xacc += +/-dx (negated on facing, loc_8c034548 neg r10), Yacc -= dy. (cite: loc_8c0344d4; cumulative_pen_geometry.)
[SCALE] CPS = (5/3, 15/7); tileScale = 1.0 (FULL CPS, NOT CPS/2); node scale @ +0xEC/+0xF0 = 1.0 in chosen_body. screen_w = native*CPSX, screen_h = native*CPSY exactly. (cite: emitter_scale_derived; probe_body_uv <0.01px.)
[PLACEMENT] screen = node+0xE0/E4 + (pen + tile)*scale. The part RIGHT edge sits at the pen, so tlx = exx + dx*CPSX - w (the part extends LEFT of the pen). Reflect the pen ORIGIN only on facing (tlx = 2*A - tlx), NEVER the rect (cite: emitter_reflection_axis — reflecting the rect injects a spurious -w part-width offset). A = owner foot (node+0xE0) + gdx.
[FACING] bodyFace = NOT owner.facing (atlas baked facing-neutral). The SAME bodyFace gates BOTH the position reflection (neg r10) AND the texture-U mirror (neg r8) — they MUST stay in lockstep; a mismatch is the left<->right part-jumping/flashing bug (cite: emitter_facing_rule, emitter_part_flashing).
[ATLAS PART DIMS] FULL storage tile span sw*8 x sh*8 (GFX1 header +2/+3), NOT the logical crop (+0/+1 lw/lh). Decoded texels occupy the BOTTOM-LEFT lw*8 x lh*8 window + transparent pad; parts stored bottom-up. (cite: emitter_geom_validated — full-span baker, 0.00px.)
[FLIPS] FLAGS 0x4000 = X-mirror (XORs facing/bodyFace); 0x8000 = Y-mirror (NO facing XOR). Y also corrected for bottom-up storage via emitFlipY (V-only invert, default TRUE), XORed with the per-record 0x8000. (cite: emitter_y_axis_fix, flip_bits.)
[PIXELS] offline GFX1 LZSS decode (loc_8c0354c0, self-contained per-part, bit-exact) + PVR PAL4 detwiddle (flycast ConvertTwiddlePal4 over full WxH) -> ARGB4444 via Dat_Pal. Fully from the disc, no play-capture (extract_gfx1_atlas.py). (cite: offline_gfx1_lzss_feasible, gfx1_part_twiddle_storage.)
[VALIDATION] validate_emitter_geom.py vs _ryu_capture/probe_body_uv.json = 0.00px relative on PL00 (all sels). This is the GATE for any geometry change (emitter_geom_validation_gate).
[OPEN] (1) emitter_flip_unvalidated: the 0x4000/0x8000 mirror branches + the opposite-facing reflect are coded as mirrors of the proven form but NO capture exercises them (all probe records facing=1, flip=flipy=0). (2) emitter_roster_rebake_pending: only PL00 is re-baked with the full-span baker; all other chars still carry old logical-crop dims — re-bake via extract_gfx1_atlas.py over the roster.';

-- ============================================================================
-- OPEN ITEMS — recorded explicitly as status=open findings.
-- ============================================================================
UPSERT finding:emitter_flip_unvalidated SET date='2026-06-11', confidence='medium', status='open',
  note='OPEN: the 0x4000 / 0x8000 mirror branches and the opposite-facing reflect are implemented as mirrors of the proven form, but NO capture exercises them (every probe record is facing=1, flip=0, flipy=0). Confirm via an opposite-facing + mirrored-part CHARQ capture, or a live green-DIFF.',
  statement='OPEN — EMITTER FLIP / OPPOSITE-FACING UNVALIDATED. The geometry is proven exact ONLY for the captured regime (facing=1, standing, flip=flipy=0). These branches are coded as MIRRORS of the proven form but are NOT yet exercised by any capture: (1) FLAGS 0x4000 X-mirror (XORs bodyFace); (2) FLAGS 0x8000 Y-mirror; (3) the opposite-facing reflect tlx = 2*axisX - tlx + w. All _ryu_capture/probe_body_uv.json records are facing=1/flip=0/flipy=0, so validate_emitter_geom.py cannot confirm them. CONFIRM BY: an opposite-facing + mirrored-part CHARQ capture (a pose with FLAGS&0x4000 set and/or owner.facing=0), or a live green-DIFF against TA-truth on such a pose. Until then these branches are INFERRED, not numerically proven.';

UPSERT finding:emitter_roster_rebake_pending SET date='2026-06-11', confidence='high', status='open',
  note='OPEN: only PL00 (Ryu) is re-baked with the corrected FULL-SPAN baker. Every other roster char still has the old logical-crop dims and must be re-baked via extract_gfx1_atlas.py (batch extract_roster_atlases.sh) before its geometry is correct.',
  statement='OPEN — EMITTER ROSTER RE-BAKE PENDING. The full-span baker fix (extract_gfx1_atlas.py decode_part: keep W=sw*8/H=sh*8, drop the logical-crop shrink) has only been applied to PL00 — the deployed PL00_parts.png/.json carry full-span dims and validate at 0.00px. EVERY OTHER CHARACTER still carries the OLD logical-crop dims and will mis-size multi-tile parts until re-baked. ACTION: run tools/extract_gfx1_atlas.py over the full roster (batch tools/extract_roster_atlases.sh) and re-deploy each PLxx_parts.{png,json}. No client change needed (buildEmitterDrawList reads part.w/h from the atlas, no override, no ?v= bump). Until done, only PL00 renders at correct geometry.';

-- ============================================================================
-- EDGES — about (finding -> entity) and cites (finding -> source).
-- RELATE is NOT idempotent: run 07_dedup_edges.surql after applying this file.
-- ============================================================================

-- master -> the entities it concerns
RELATE finding:emitter_render_model->about->routine:loc_8c0344d4;
RELATE finding:emitter_render_model->about->routine:loc_8c0354c0;
RELATE finding:emitter_render_model->about->dataformat:gfx2_cell;
RELATE finding:emitter_render_model->about->field:sprite_id;
RELATE finding:emitter_render_model->about->field:facing;
RELATE finding:emitter_render_model->about->field:screen_x;
RELATE finding:emitter_render_model->about->field:screen_y;
RELATE finding:emitter_render_model->about->field:dat_pal;
RELATE finding:emitter_render_model->about->field:dat_gfx1;
RELATE finding:emitter_render_model->about->field:dat_gfx2;
RELATE finding:emitter_render_model->about->tool:extract_gfx1_atlas;
RELATE finding:emitter_render_model->about->tool:validate_emitter_geom;

-- master -> sources (every constant/formula traces to one of these)
RELATE finding:emitter_render_model->cites->source:marv_bank03;
RELATE finding:emitter_render_model->cites->source:oracle_charq;
RELATE finding:emitter_render_model->cites->source:validate_emitter_geom_20260611;
RELATE finding:emitter_render_model->cites->source:lzss_offline_decode_2026_06_10;

-- sub-finding about/cites
RELATE finding:emitter_scale_derived->about->routine:loc_8c0344d4;
RELATE finding:emitter_scale_derived->cites->source:marv_bank03;
RELATE finding:emitter_scale_derived->cites->source:oracle_charq;

RELATE finding:emitter_facing_rule->about->routine:loc_8c0344d4;
RELATE finding:emitter_facing_rule->about->routine:loc_8c034548;
RELATE finding:emitter_facing_rule->about->routine:loc_8c0346c4;
RELATE finding:emitter_facing_rule->about->field:facing;
RELATE finding:emitter_facing_rule->cites->source:marv_bank03;

RELATE finding:emitter_reflection_axis->about->routine:loc_8c0344d4;
RELATE finding:emitter_reflection_axis->about->routine:loc_8c034548;
RELATE finding:emitter_reflection_axis->about->field:screen_x;
RELATE finding:emitter_reflection_axis->cites->source:marv_bank03;

RELATE finding:emitter_y_axis_fix->about->routine:loc_8c0344d4;
RELATE finding:emitter_y_axis_fix->about->field:screen_y;
RELATE finding:emitter_y_axis_fix->cites->source:marv_bank03;
RELATE finding:emitter_y_axis_fix->cites->source:oracle_charq;

RELATE finding:emitter_part_flashing->about->routine:loc_8c0344d4;
RELATE finding:emitter_part_flashing->about->field:facing;
RELATE finding:emitter_part_flashing->cites->source:marv_bank03;

RELATE finding:offline_gfx1_lzss_feasible->about->routine:loc_8c0354c0;
RELATE finding:offline_gfx1_lzss_feasible->about->tool:extract_gfx1_atlas;
RELATE finding:offline_gfx1_lzss_feasible->cites->source:lzss_offline_decode_2026_06_10;

RELATE finding:gfx1_part_twiddle_storage->about->tool:extract_gfx1_atlas;
RELATE finding:gfx1_part_twiddle_storage->cites->source:lzss_offline_decode_2026_06_10;

-- emitter_geom_validated -> add the tool + scale links (cites already seeded in 06)
RELATE finding:emitter_geom_validated->about->tool:extract_gfx1_atlas;
RELATE finding:emitter_geom_validated->about->tool:validate_emitter_geom;
RELATE finding:emitter_geom_validated->about->routine:loc_8c0345c4;
RELATE finding:emitter_geom_validated->cites->source:validate_emitter_geom_20260611;

-- validation finding
RELATE finding:emitter_geom_validation_gate->about->tool:validate_emitter_geom;
RELATE finding:emitter_geom_validation_gate->about->routine:loc_8c0344d4;
RELATE finding:emitter_geom_validation_gate->cites->source:validate_emitter_geom_20260611;
RELATE finding:emitter_geom_validation_gate->cites->source:oracle_charq;

-- open items
RELATE finding:emitter_flip_unvalidated->about->finding:emitter_render_model;
RELATE finding:emitter_flip_unvalidated->about->dataformat:gfx2_cell;
RELATE finding:emitter_flip_unvalidated->about->field:facing;
RELATE finding:emitter_flip_unvalidated->cites->source:validate_emitter_geom_20260611;
RELATE finding:emitter_flip_unvalidated->cites->source:oracle_charq;

RELATE finding:emitter_roster_rebake_pending->about->finding:emitter_render_model;
RELATE finding:emitter_roster_rebake_pending->about->tool:extract_gfx1_atlas;
RELATE finding:emitter_roster_rebake_pending->cites->source:validate_emitter_geom_20260611;

-- connect the sub-findings + validation + open items to the MASTER so the
-- whole emitter model is ONE connected subgraph (about edges, master as hub).
RELATE finding:emitter_render_model->about->finding:emitter_geom_validated;
RELATE finding:emitter_render_model->about->finding:emitter_scale_derived;
RELATE finding:emitter_render_model->about->finding:emitter_facing_rule;
RELATE finding:emitter_render_model->about->finding:emitter_reflection_axis;
RELATE finding:emitter_render_model->about->finding:emitter_y_axis_fix;
RELATE finding:emitter_render_model->about->finding:emitter_part_flashing;
RELATE finding:emitter_render_model->about->finding:offline_gfx1_lzss_feasible;
RELATE finding:emitter_render_model->about->finding:gfx1_part_twiddle_storage;
RELATE finding:emitter_render_model->about->finding:cumulative_pen_geometry;
RELATE finding:emitter_render_model->about->finding:emitter_geom_validation_gate;
RELATE finding:emitter_render_model->about->finding:emitter_flip_unvalidated;
RELATE finding:emitter_render_model->about->finding:emitter_roster_rebake_pending;
