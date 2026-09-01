-- ============================================================================
-- 83: status triage -- THE FILE THAT NEEDS A HUMAN
--
-- 77 gave the graph a status vocabulary and a promotion rule. 79/81/82 repaired
-- everything that could be repaired MECHANICALLY (a missing source row, a
-- dangling cite, a PC named in prose but never cited). What is left is the part
-- that cannot be automated, because it is a judgement about whether we actually
-- know something.
--
-- SECTIONS 1 AND 2 ARE READY TO APPLY. They are mechanical or verified.
-- SECTIONS 3 AND 4 ARE COMMENTED OUT. They need your ruling first.
--
--   tools/re_kb/rekb.sh @tools/re_kb/83_status_triage.surql
--
-- ============================================================================
--
-- FIRST, A CORRECTION TO THE HANDOVER.
--
-- HANDOVER-EPISTEMICS.md says: "44 findings whose TEXT records a dead end, but
-- whose STATUS does not -- so no query can find them, and the next session
-- re-walks them." That number came from a loose regex (it fires on the word
-- "failed" anywhere in a long note) and the conclusion drawn from it is WRONG.
--
-- Re-measured today with a strict pattern (explicit disproof/abandonment only),
-- 19 findings match. Reading all 19: SEVENTEEN are correctly `confirmed`. They
-- are positive results whose text happens to REFUTE a competing hypothesis --
--
--   hud_prior_detwiddle_claim_refuted   "THIS IS REFUTED. It was an INFERENCE
--                                        about CLIENT code the prior run never read"
--   storm_tilecount_count_is_scale_invariant
--                                       'REFUTED: "CPS ratio changes the tile COUNT"'
--   native_gsta_stage_zorder            "the floor-to-white override was DISPROVEN"
--
-- -- and demoting them to `ruled_out` would DELETE real confirmed knowledge.
--
-- The actual gap is the opposite one: the REFUTED HYPOTHESIS never gets a row
-- of its own. The refutation lives as a sentence inside the winner, so
-- `SELECT * FROM finding WHERE status='ruled_out'` still returns almost
-- nothing, and the next session can still re-walk the losing idea. Section 3
-- proposes those rows.
--
-- Two of the 19 ARE mis-statused. Both are in section 3.
--
-- Recording this because the wrong number is the kind of thing that gets
-- copied forward: it was in the handover, it sounded precise, and acting on it
-- would have damaged the graph.
-- ============================================================================
USE NS re DB kb;

-- ============================================================================
-- SECTION 1 -- STATUS VOCABULARY (ready to apply)
-- ============================================================================
-- 77 declares six statuses: open, inferred, confirmed, ruled_out, superseded,
-- resolved. Sixteen rows carry something else. Mapping rules, applied
-- uniformly so they can be checked:
--
--   CONFIRMED / RESOLVED   -> case fix, nothing else changes
--   fixed / closed         -> `resolved` (a question that got closed), EXCEPT
--                             where the row's own text says it is still open
--   implemented            -> `confirmed` where the row states a mechanism and
--                             already cites qualifying evidence; `inferred`
--                             where the row says "pending verify" IN ITS OWN TEXT
--   implemented_pending_live_verify,
--   proposed / planned     -> `inferred`. A proposal is a reasoned claim that
--                             is not yet grounded -- exactly what `inferred`
--                             means. It is NOT `open` (that is for a question,
--                             not a proposed answer).

-- -- case only ---------------------------------------------------------------
UPDATE finding:per_part_depth_zinvW              SET status = 'confirmed';
UPDATE finding:emitter_roster_deploy_2026_06_10  SET status = 'resolved';

-- -- a closed question -------------------------------------------------------
-- 43_carve_wide_square_twiddle_fix flipped this to the non-vocabulary 'fixed'.
UPDATE finding:carve_wide_square_twiddle_open    SET status = 'resolved';
UPDATE finding:stage_ta_bake_camera_note         SET status = 'resolved';

-- -- says "pending verify" in its own text -> not yet grounded ---------------
UPDATE finding:dump_companions_windows_pathable  SET status = 'inferred',
  triage_note = '2026-09-01: was status=implemented. Its own text says "relink pending PID-62532 exe lock" -- compiled is not verified. Promote via kb.confirm() once the relinked binary is exercised.';
UPDATE finding:hud_native_client_port_scoped     SET status = 'inferred',
  triage_note = '2026-09-01: was status=implemented. Its own text says "pending USER live verify".';
UPDATE finding:hud_reconstruct_from_state_browser SET status = 'inferred',
  triage_note = '2026-09-01: was status=implemented. Its own text says "pending live verify".';
UPDATE finding:hud_para5_expansion_capture_fix   SET status = 'inferred',
  triage_note = '2026-09-01: was status=implemented_pending_live_verify -- the status name itself said it was not confirmed.';

-- -- states a mechanism and already cites qualifying evidence ----------------
-- Checked, not assumed. replica_storm_scramble_fix cites two code-grade
-- sources; stage_real_bug_pernode_matrices cites a reproduction plus code.
UPDATE finding:replica_storm_scramble_fix        SET status = 'confirmed';
UPDATE finding:stage_real_bug_pernode_matrices   SET status = 'confirmed';

-- hud_reshape_twin_overdraw_fix was going to go here too -- it reads like a
-- settled root cause ("ROOT CAUSE = (3) twin-overdraw, FIXED"). It does not
-- qualify: its only citation is source:hud_nodeplete_diag, kind='measurement',
-- and its text names no PC and no file. So it lands as `inferred`, which is
-- the rule working rather than the rule being inconvenient.
--
-- It is a strong SECTION 4 PILE A candidate: the diagnosis was run offline on
-- _live_hud, which "consumes the same wire HUDQ + _gstaRam, so it reproduces
-- the native client exactly" -- that is a reproduction if the source is
-- re-kinded. Decide it there and promote via kb.confirm(), not here.
UPDATE finding:hud_reshape_twin_overdraw_fix     SET status = 'inferred',
  triage_note = '2026-09-01: was status=implemented. Reads as a settled root cause but cites only source:hud_nodeplete_diag (kind=measurement) and names no PC or file. Promote via kb.confirm() if that source is re-kinded to validation (section 4, pile A).';

-- -- proposals: reasoned, not yet grounded -----------------------------------
UPDATE finding:render_frame_wire_shrink_plan     SET status = 'inferred';
UPDATE finding:replica_live_palette_fix          SET status = 'inferred';
UPDATE finding:replica_live_readset_fix_priority SET status = 'inferred';
UPDATE finding:replica_live_static_gfx_fix       SET status = 'inferred';

-- -- its own first word is OPEN ----------------------------------------------
UPDATE finding:stage_prop_matrices_deferred      SET status = 'open',
  triage_note = '2026-09-01: was status=closed while its own statement begins "OPEN (deferred follow-up)". Keeping a deferred question loud is the point of `open`.';

-- ============================================================================
-- SECTION 2 -- EVIDENCE RECOVERY, OUR OWN SOURCE (ready to apply)
-- ============================================================================
-- 82 recovered the findings that named a marvelous2 PC. These name a file in
-- THIS repo instead. 77's ladder counts "flycast source" as code-grade -- the
-- mechanism is visible in source -- so a repo file:symbol is code-grade
-- evidence for a claim ABOUT OUR OWN CODE. (It would NOT be evidence for a
-- claim about MVC2; see the note at the end of this section.)
--
-- Every file below was confirmed to exist, and every symbol was located, on
-- 2026-09-01 before its row was written. Where a finding quoted a line number
-- that has since drifted, the SYMBOL is cited instead of the line -- e.g.
-- headless_dump_ram_trigger_mechanism says "maplecast_oracle_hook.cpp:3520-3559"
-- and the block is now at :4507.

UPSERT source:src_gsta_stage_cpp SET kind='client_source', strength='code',
  title='core/network/gsta_stage.cpp -- native GSTA stage loader + TA emitter',
  ref='core/network/gsta_stage.cpp (gstaStageEnsureLoaded @145, gstaStageEmitTA)',
  note='Row created 2026-09-01. File verified present.';

UPSERT source:src_maplecast_oracle_hook_cpp SET kind='client_source', strength='code',
  title='core/network/maplecast_oracle_hook.cpp -- the READ-ONLY dynarec probe family',
  ref='core/network/maplecast_oracle_hook.cpp (MAPLECAST_DUMP_RAM_TRIGGER block @~4507)',
  note='Row created 2026-09-01. The citing finding says :3520-3559; the block has since moved to :4507. Cite the symbol, not the line.';

UPSERT source:src_stage_client_mjs SET kind='client_source', strength='code',
  title='web/webgpu/stage-client.mjs -- the engine-TA grounded stage path',
  ref='web/webgpu/stage-client.mjs (_buildFromTA @153/211)',
  note='Row created 2026-09-01. File verified present.';

UPSERT source:src_pvr2_renderer_mjs SET kind='client_source', strength='code',
  title='web/webgpu/pvr2-renderer.mjs -- the TA-truth rasterizer (gold standard)',
  ref='web/webgpu/pvr2-renderer.mjs (per-poly ISP.DepthMode handling)',
  note='Row created 2026-09-01. File verified present.';

UPSERT source:src_maplecast_mirror_cpp SET kind='client_source', strength='code',
  title='core/network/maplecast_mirror.cpp -- GSTA client render path + sprite TA emit',
  ref='core/network/maplecast_mirror.cpp (gstaEmitSpriteTA_append @5427)',
  note='Row created 2026-09-01. File verified present.';

UPSERT source:src_shot_hud_mjs SET kind='transpile_validation', strength='reproduction',
  title='tools/render-replica-poc/shot_hud.mjs -- puppeteer WebGPU HUD shot, 7 element checks',
  ref='tools/render-replica-poc/shot_hud.mjs',
  note='Row created 2026-09-01. A scripted headless render with pass/fail assertions is a reproduction, not a metric: re-run it and it passes or it does not.';

UPSERT source:src_hud_geom_check_cjs SET kind='transpile_validation', strength='reproduction',
  title='tools/render-replica-poc/_hud_geom_check.cjs -- HUD geometry harness against the REAL renderHudPass()',
  ref='tools/render-replica-poc/_hud_geom_check.cjs',
  note='Row created 2026-09-01. Extracts the shipped functions verbatim and runs them, so it tests the real code path rather than a restatement of it.';

UPSERT source:src_bake_stage_from_ta_py SET kind='client_source', strength='code',
  title='tools/bake_stage_from_ta.py -- the stage bake (the HUD-contamination site)',
  ref='tools/bake_stage_from_ta.py',
  note='Row created 2026-09-01. File verified present.';

RELATE finding:gsta_stage_path_from_binary->cites->source:src_gsta_stage_cpp;
RELATE finding:gsta_stage_floor_cull_fix->cites->source:src_gsta_stage_cpp;
RELATE finding:headless_dump_ram_trigger_mechanism->cites->source:src_maplecast_oracle_hook_cpp;
RELATE finding:replica_live_stage_black_fix->cites->source:src_stage_client_mjs;
RELATE finding:replica_live_stage_black_rootcause->cites->source:src_stage_client_mjs;
RELATE finding:submit_isp_depthmode->cites->source:src_pvr2_renderer_mjs;
RELATE finding:gsta_body_blend_uv_confirmed->cites->source:src_maplecast_mirror_cpp;
RELATE finding:replica_live_hud_garble_fix_validated->cites->source:src_shot_hud_mjs;
RELATE finding:replica_live_hud_angled_validated->cites->source:src_hud_geom_check_cjs;
RELATE finding:stage_bake_hud_contamination->cites->source:src_bake_stage_from_ta_py;

-- A STRUCTURAL POINT WORTH DECIDING SEPARATELY:
-- this graph mixes two kinds of claim under one table -- facts about MVC2
-- ("char+0x144 is the cell selector") and facts about OUR implementation
-- ("gstaStageEnsureLoaded now resolves from the exe directory"). They need
-- different evidence and age differently: the first is permanent, the second
-- is only true until someone edits the file. A `subject` field ('mvc2' vs
-- 'maplecast') would let the health metric grade them separately. NOT done
-- here -- it is a schema change and should be its own decision.

-- ============================================================================
-- SECTION 3 -- THE REFUTED HYPOTHESES (needs your ruling -- COMMENTED OUT)
-- ============================================================================
-- Each of these is a losing idea that a confirmed finding explicitly refutes,
-- with no row of its own. Giving each one a `ruled_out` row is what makes
-- `dead_ends()` actually answer "what has already been eliminated here?".
--
-- Uncomment what you agree with. The slugs are new; the refuting finding is
-- named in each `evidence` field so the claim stays traceable.
--
-- UPSERT finding:ruled_rgb565_not_detwiddled SET status='ruled_out',
--   statement='HYPOTHESIS (2026-06): the client does not detwiddle RGB565, so the FONT texture decodes wrong.',
--   tried='Inferred from client code that was never actually read.',
--   evidence='REFUTED by finding:hud_prior_detwiddle_claim_refuted -- texture-manager.mjs _decode applies the Morton/PVR detwiddle for RGB565.',
--   date='2026-06-14';
-- RELATE finding:hud_prior_detwiddle_claim_refuted->supersedes->finding:ruled_rgb565_not_detwiddled;
--
-- UPSERT finding:ruled_hud_name_vram_zeroed SET status='ruled_out',
--   statement='HYPOTHESIS: the big per-character HUD name letters are missing because their VRAM prefix block is ZEROED (the twin of the meter-segment gap).',
--   tried='Assumed by analogy with finding:hud_meter_segments_vram_gap.',
--   evidence='REFUTED by finding:hud_name_garble_is_paratype5_sprite on a fresh live capture -- the letters ARE present as 62 fmt=5 PAL4 quads.',
--   date='2026-06-14';
-- RELATE finding:hud_name_garble_is_paratype5_sprite->supersedes->finding:ruled_hud_name_vram_zeroed;
--
-- UPSERT finding:ruled_sprite_needs_native_render SET status='ruled_out',
--   statement='HYPOTHESIS: correct HUD sprite UV mapping requires a native sprite render that 2 triangles cannot reproduce.',
--   tried='Assumed from the ParaType-5 sprite parameter shape.',
--   evidence='REFUTED by finding:hud_sprite_2tri_coercion_is_faithful -- flycast has no per-pixel single-plane stage; the plane equation is a one-time corner solve, after which the quad IS 2 triangles.',
--   date='2026-06-15';
-- RELATE finding:hud_sprite_2tri_coercion_is_faithful->supersedes->finding:ruled_sprite_needs_native_render;
--
-- UPSERT finding:ruled_per_tile_mxm_twiddle SET status='ruled_out',
--   statement='HYPOTHESIS: GFX1 parts are stored per-tile as m x m twiddled blocks, so the carve must re-twiddle per tile.',
--   tried='Proposed as the fix for the render-replica scramble.',
--   evidence='REFUTED by finding:render_replica_scramble_fix -- the engine stores each GFX1 part ONCE, CONTIGUOUS, decodeA output verbatim and byte-exact.',
--   date='2026-06-12';
-- RELATE finding:render_replica_scramble_fix->supersedes->finding:ruled_per_tile_mxm_twiddle;
--
-- UPSERT finding:ruled_scale_walker_hypothesis SET status='ruled_out',
--   statement='HYPOTHESIS: the CPS ratio / size modifier changes the TILE COUNT, so Storm uses a separate scale-walker.',
--   tried='Inferred from Storm 16x16 part records disagreeing with the disc rip.',
--   evidence='REFUTED by finding:storm_tilecount_count_is_scale_invariant and finding:storm_tilecount_authoritative -- the builder loc_8c033b0a reads only node+0x04/+0x144/+0x160, and tiles are LONG/SHORT so the count is storage-invariant.',
--   date='2026-07-03';
-- RELATE finding:storm_tilecount_count_is_scale_invariant->supersedes->finding:ruled_scale_walker_hypothesis;
--
-- UPSERT finding:ruled_floor_white_intensity_override SET status='ruled_out',
--   statement='FIX ATTEMPT: override the stage floor intensity to white to recover the dark deck.',
--   tried='Applied to the native GSTA stage before the deck fix.',
--   evidence='DISPROVEN by finding:native_gsta_stage_zorder -- it washed the dark grid to bright green and HID the blue floor. Removed in favour of the bake per-vertex RGB. The real cause was margin culling (finding:gsta_stage_floor_cull_fix).',
--   date='2026-06-19';
--
-- UPSERT finding:ruled_benched_char_overlap SET status='ruled_out',
--   statement='HYPOTHESIS: the Sentinel scramble is a benched War Machine overlapping Sentinel, or a wrong-char slot/pointer mis-read.',
--   tried='Inferred from the visual scramble.',
--   evidence='REFUTED at the DATA level by finding:sentinel_scramble_slot_data_clean -- the live char slots are clean.',
--   date='2026-06-12';
-- RELATE finding:sentinel_scramble_slot_data_clean->supersedes->finding:ruled_benched_char_overlap;
--
-- UPSERT finding:ruled_p3d_per_pass_rewind SET status='ruled_out',
--   statement='HYPOTHESIS: Storm electric/hit effects are missing from the P3D capture because of a PER-PASS REWIND.',
--   tried='One of two suspected reasons for the capture drop.',
--   evidence='RULED OUT by finding:tr_effect_capture_drop_rootcause -- every sampled vframe including hits reported passes=1. The real cause was the CLASS FILTER.',
--   date='2026-07-07';
--
-- ---- the two that ARE mis-statused ----------------------------------------
--
-- (a) state_injection_deadend is `confirmed`, and that is right -- we DID
--     confirm the injection is the trigger. But the APPROACH it killed has no
--     record, so "has anyone tried injecting state into the live SH4?" is not
--     answerable by query. That is what the attempt subgraph in 77 is for:
--
-- UPSERT approach:live_sh4_state_injection SET name='live_sh4_state_injection',
--   how='Inject per-frame GSTA state directly into the running SH4 (guest RAM writes into engine-owned pointers).';
-- RELATE approach:live_sh4_state_injection->tried_on->finding:state_injection_deadend
--   SET outcome='ineffective', date='2026-05',
--       note='Always crashes: corrupt engine-owned pointers, epc in 0x8C00xxxx non-code, pr in bank12. Capture timing / loadstate / ROM-presence were each ruled out -- the injection ITSELF is the trigger. The robust architecture is the asset-driven renderer with the SH4 OFF.';
--
-- (b) part_decode_mechanism's note still says "offline LZSS decode is a dead
--     end". That was true when written and is now FALSE: finding:offline_gfx1_lzss_feasible
--     (status=resolved) reports the 752KB runaway was a DECODER BUG (wrong
--     literal/backref polarity, off-by-one copy count) and that all 1533 PL00
--     sels now decode cleanly, validated bit-exact against 6 live-captured
--     tiles. Two live claims, opposite conclusions, no edge between them --
--     exactly the contradiction kb.contradictions() is meant to surface.
--
-- RELATE finding:offline_gfx1_lzss_feasible->corrects->finding:part_decode_mechanism;
-- UPDATE finding:part_decode_mechanism SET
--   triage_note = '2026-09-01: the note claims "offline LZSS decode is a dead end". SUPERSEDED by finding:offline_gfx1_lzss_feasible -- it is feasible; the runaway was a decoder bug. The REST of this finding (on-demand per-pose decode into transient VRAM, moving TCW, no bulk-resident store, load-burst covers only sels 0-251) still stands.';

-- ============================================================================
-- SECTION 4 -- THE REMAINING UNBACKED `confirmed` (needs your ruling)
-- ============================================================================
-- After 82 and section 2, 37 -> ~27 `confirmed` findings still cannot show
-- reproduction- or code-grade evidence. They split into two piles, and the
-- difference matters more than the count.
--
-- PILE A -- THE SOURCE IS MIS-KINDED, NOT WEAK.
-- These cite a source recorded as kind='measurement' or 'tool' that is really
-- a deterministic A/B differ with a pass/fail. 77 ranks a "deterministic differ
-- pass" as `reproduction`. Re-kinding them to 'validation' is defensible AND is
-- the single highest-leverage change left -- but it silently re-grades every
-- finding that cites them, so it is YOUR call, not mine:
--
--   source:gsta_engine_pixel_truth     engine's own pixel render vs the client
--   source:gsta_engine_palette_ram     engine PVR PALETTE_RAM read
--   source:gsta_engine_ta_banks        engine real-TA bank selection over 806/1484 frames
--   source:gsta_carve_audit_2026_06_15 engine-vs-reconstruction VRAM byte diff (0.00%)
--   source:engine_ta_parse             engine TA parse
--   source:state_wire_churn_measure    9600-frame byte-identical reconstruction (0 mismatches)
--   source:census_stage_hud_twins      bake-vs-frame mesh census
--   source:p3d_classhist_hit_capture   live headless class histogram at hit frames
--   source:live4_nj_globals            live RAM read of NJ globals
--   source:ctrl_ws_charswap_poc        live char-swap experiment through the control WS
--   source:hud_nodeplete_diag          offline HUD reshape A/B on _live_hud (see section 1)
--
-- UPDATE source SET kind='validation', strength='reproduction' WHERE id IN [
--   source:gsta_engine_pixel_truth, source:gsta_engine_palette_ram,
--   source:gsta_engine_ta_banks, source:gsta_carve_audit_2026_06_15,
--   source:engine_ta_parse, source:state_wire_churn_measure,
--   source:census_stage_hud_twins, source:p3d_classhist_hit_capture,
--   source:live4_nj_globals, source:ctrl_ws_charswap_poc,
--   source:hud_nodeplete_diag ];
--
-- MY RECOMMENDATION: yes for all eleven. Each names a comparison against the
-- ENGINE and reports a concrete pass/fail or a byte-level identity. A
-- 0.00%-diff VRAM comparison is not "a number that improved" -- it is the
-- thing reproducing.
--
-- PILE B -- GENUINELY NOT CONFIRMED. My recommendation is to demote these to
-- `inferred`, because their own text says the mechanism is not settled:
--
-- UPDATE finding:gsta_motion_blocks_residual_bands SET status='inferred',
--   triage_note='2026-09-01: its own text says "cull extension NOT shipped -- drift blocks exact validation". A band-multiset over-emit count is a symptom measurement, not a mechanism.';
-- UPDATE finding:overlay_passthrough_feasibility SET status='inferred',
--   triage_note='2026-09-01: a feasibility estimate ("heavier than expected -> needs delta"), not a demonstrated result.';
-- UPDATE finding:render_path_reconstruct_vs_passthrough SET status='inferred',
--   triage_note='2026-09-01: states a param-type SPLIT as measured, but the conclusion drawn from it (what to build) is a plan.';
--
-- AND THE ONE THAT SHOULD BE AN ATTEMPT, NOT A FINDING:
-- emitter_tile_scale_charq_calibrated is a CALIBRATION -- constants tuned until
-- the output matched CHARQ. That is the textbook `masks_only`: right output,
-- mechanism not derived. It should be recorded as an attempt with that outcome
-- rather than sitting in the graph as a confirmed fact about the game.
--
-- UPSERT approach:emitter_scale_charq_calibration SET name='emitter_scale_charq_calibration',
--   how='Tune the offline-atlas part-extent + flip scale constants (CPS/2) until the emitter output matches CHARQ ground truth.';
-- RELATE approach:emitter_scale_charq_calibration->tried_on->finding:emitter_tile_scale_charq_calibrated
--   SET outcome='masks_only', date='2026-06-10',
--       note='Produces the right geometry, but the scale is FITTED to CHARQ rather than derived from the engine. Ship it; do not treat the constant as a fact about MVC2 until the routine that sets it is read.';
