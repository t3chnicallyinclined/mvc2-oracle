-- ============================================================================
-- 31 (2026-06-14): LIVE STAGE RENDERS BLACK — ROOT CAUSE + FIX.
-- The user's live render-replica match (stage_id=0x0B / STG0B) rendered BLACK.
-- Extends/corrects finding:stage_pernode_matrices_closed (26e): its cross-frame
-- camera assumption was wrong — re-projecting local-space prop `world` through a
-- DIFFERENT-frame live camera explodes the props off-screen, and the deck's decoded
-- intensity was ~0 so the modulate killed it. feat/render-replica-live.
-- ============================================================================
USE NS re DB kb;

UPSERT source:stage_black_diagnosis SET kind='tool',
  ref='tools/render-replica-poc/{livecap.mjs, shot_stage_headless.mjs, shot_stage_curlive.mjs} + Dawn WebGPU headless raster on the EXACT replay.html StageClient+PVR2Renderer path',
  note='LIVE capture from wss://nobd.net/replica-live (livecap.mjs, now ships the gstate@0x8C289620:96 dyn region incl stage_id): current match stage_id=0x0B(11) STG0B, P1cid=0x2A Storm vs P2cid=0x17 Cable (the older _satlive.mcrr was Colossus 0x32 vs Cable, same stage 0x0B). Camera M1@0x8C2D6B18=[320,0,0,320; 0,-240,0,240; 0,0,-.5,.5; 0,0,0,1], M2@0x8C2D6AD8 valid non-degenerate (M2[15]=812.36) -> renderStagePass camera gate PASSES. shot_stage_headless on STG0B reported 26.8% "non-black" BUT a brightness histogram showed MAX CHANNEL = 2/255, mean 0.39, ZERO px > 32: the stage drew but was catastrophically dark = the user-visible BLACK. After the fix: max 255, mean 96.1, 171296 visible px (56%) = the real STG0B neon-grid stage (blue floor + green/blue backdrop), validated against the CURRENT live capture (_curlive.mcrr).';

UPSERT finding:replica_live_stage_black_rootcause SET
  statement='THE LIVE STAGE WAS BLACK FROM TWO DISTINCT BUGS in stage-client.mjs _buildFromTA (the engine-TA grounded path), NOT a deploy gap, gate, or missing asset (STG0B_ta.json md5 was deployed + correct, code md5 prod==local). (1) CROSS-FRAME RE-PROJECTION EXPLOSION: finding:stage_pernode_matrices_closed (26e) re-projects EVERY mesh`s un-projected `world` through the LIVE XMTRX. But only the 3 large STRUCTURAL meshes (deck/floor/backdrop, world extent +-2491, Z down to -2895) are authored in TRUE world space; the 69 small props carry LOCAL-space coords in `world` (extent +-70, shallow +Z ~620-741). 26e validated only the ROUND-TRIP (bake-camera == reproject-camera = exact). The LIVE stream camera is a DIFFERENT frame`s matrices, so re-projecting the props` local coords through it flings them to X=-16,000,000 / Y=-6,800,000 off-screen: only ~480/3768 verts (12.7%) survived -> a few faint deck triangles = effectively black. (2) DECK INTENSITY ~0: the engine-TA bake decoded the 3 world-authored meshes` Col_Type=1 packed-color intensity as ~0.01 (uniform, all 2178 deck verts), while the props decoded to 0.93. With ShadInstr=1 (modulate, c.rgb*tex.rgb) the bright deck texture (meanRGB 77-122) x 0.01 base = near-black. So even the deck triangles that DID project on-screen were invisible.',
  status='confirmed', confidence='high', date='2026-06-14';

UPSERT finding:replica_live_stage_black_fix SET
  statement='STAGE BLACK FIXED (never-black, full-scene). Two surgical changes in web/webgpu/stage-client.mjs _buildFromTA, both grounded in the STG0B world geometry: (A) PER-MESH RE-PROJECTION GATE: re-project (track live camera) ONLY world-authored meshes; render local props at the engine`s OWN baked SCREEN `pos` verbatim (camera-static but correctly placed by the engine that frame). Discriminator _meshIsWorldAuthored(m): minZ < -500 OR max|worldX| > 1000 (cleanly separates the 3 deck-class meshes from the 69 props: deck Z -2895..812 / Xext 2491 vs props Z +619..741 / Xext <=70; cached per-mesh in m._wa). (B) INTENSITY FLOOR: for textured world-authored meshes floor the base colour to 1.0 (iv=max(floor,v.i)) so the modulate passes the real deck texture through (decal-like) instead of x0.01; props keep their real per-vertex shading. RESULT vs the CURRENT live capture (_curlive.mcrr, STG0B, Storm vs Cable): max channel 2->255, mean 0.39->96.1, visible px (>32) 0->171296 = the real neon-grid STG0B (blue floor + green/blue grid + HUD). NO regression to the proven deck camera-tracking (deck still re-projects). The POL-rip path (_build, non-TA stages) UNTOUCHED. Deployed prod 149.28.44.118: stage-client.mjs (local md5 059e0c65 == prod, backup taken) + replay.html stage import propworld->stagefix1 via single-line sed (prod) + local Edit (other agent owns the rest of replay.html). STG0B_ta.json + textures already on prod (unchanged). Body/HUD/effects/decode UNTOUCHED.',
  status='confirmed', confidence='high', date='2026-06-14';

UPSERT finding:replica_live_stage_other_stages_open SET
  statement='OPEN: only STG0B has an engine-TA bake (STG0B_ta.json), so only stage_id->STG0B renders the full grounded scene. Any OTHER live stage_id falls to the POL-rip STGxx.json world-space path (deck/world-authored models only, synthesized control words — finding:stage_world_assembly_fix), which renders the deck but no props and with synth blend. To make every stage render its full grounded scene: capture each stage`s engine TA live (MAPLECAST_DUMP_RAM in-match on prod, per stage_id) + bake with tools/bake_stage_from_ta.py, and complete STAGE_ID_MAP (stage-client.mjs; only 0x11->STG0B confirmed, else id->file fallback — note the live wire id for STG0B is 0x0B which the fallback maps to file 0x0B == STG0B coincidentally, so STG0B works under BOTH the explicit 0x11 entry and the 0x0B fallback). The per-mesh gate + intensity floor in finding:replica_live_stage_black_fix apply to every future _ta.json bake automatically.',
  status='open', confidence='high', date='2026-06-14';

UPSERT finding:stage_pernode_matrices_closed SET status='open',
  note_correction='REOPENED by finding:replica_live_stage_black_rootcause: the 26e round-trip validation (bake-camera==reproject-camera) did NOT test the LIVE cross-frame camera, under which the local-space props explode off-screen. The fix is to NOT re-project the props (render their baked screen pos) — finding:replica_live_stage_black_fix.';

RELATE finding:replica_live_stage_black_rootcause->cites->source:stage_black_diagnosis;
RELATE finding:replica_live_stage_black_rootcause->cites->source:engine_ta_parse;
RELATE finding:replica_live_stage_black_rootcause->about->finding:stage_pernode_matrices_closed;
RELATE finding:replica_live_stage_black_fix->cites->source:stage_black_diagnosis;
RELATE finding:replica_live_stage_black_fix->about->finding:replica_live_stage_black_rootcause;
RELATE finding:replica_live_stage_black_fix->about->finding:stage_pernode_matrices_closed;
RELATE finding:replica_live_stage_other_stages_open->about->finding:replica_live_stage_black_fix;
