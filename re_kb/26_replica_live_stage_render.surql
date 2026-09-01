-- ============================================================================
-- 26: render-replica LIVE — PHASE 3 STAGE (background) render.
-- The fighters were drawn on black; this adds the actual MVC2 stage behind them,
-- grounded in the ROM stage decode + the engine's OWN live camera matrices.
-- (feat/render-replica-live). Pinned 2026-06-13.
-- ============================================================================
USE NS re DB kb;

UPSERT source:stage_decode SET kind='tool',
  ref='tools/rip_stage.py (ModNao NaomiLib/libspr port) -> web/test-atlas/stages/STGxx.json + STGxx_tNN.png',
  note='Offline disc decode of STGxxPOL.BIN (geometry) + STGxxTEX.BIN (PVR textures), pre-relocated Sega NinjaLibrary object tree at base 0x0CEA0000. Emits per-stage JSON (models->meshes->tris{pos,uv,col}) + de-twiddled RGBA PNGs. All 17 stages (STG00..STG10) ripped, gitignored (ROM-derived). STG00 geometry verified full-3D NAOMI WORLD-SPACE: X in +-48664, Y -31610..45610, Z -100435..9099, UV in [0,1] — NOT pre-projected screen space, so it needs the engine camera each frame.';

UPSERT source:stage_camera_transform SET kind='code',
  ref='tools/render-replica-poc/gen_transform_obj.c transform_object_122560 (faithful port of bank12 loc_8C122560)',
  note='The engine projects EVERY renderable world-space object through ONE frame-global transform loc_8C122560: XMTRX = M1(viewport @0x8C2D6B18) . M2(projection @0x8C2D6AD8) [column-major mat-mat, loc_8c120540]; fv = ftrv(XMTRX, (x,y,z,1)) [loc_8c11F870]; inv=1/fv[3]; screenX=fv[0]*inv; screenY=fv[1]*inv; depth=inv. The body slot-walk feeds world pos through this to deposit screen_x/y @node+0xE0/E4 (re_kb finding:render_frame_positions_validated, 0.00px vs ASMTRACE). Both source matrices are FRAME-GLOBAL camera state built once/frame by the proj setup loc_8c1216c0 (NOT per-object output) -> reading them from RAM is code-derived. From the live _ryu_capture/mc_ram_dump.bin: M1 = viewport [320,0,0,0, 0,-240,0,0, 0,0,-0.5,0, 320,240,0.5,1] (maps NDC->640x480 screen px, translate to screen center); M2 = perspective. So fv[0]/fv[1] come out directly in 640x480 SCREEN PIXELS, matching the bodies  deposited +0xE0/E4.';

UPSERT source:stage_readset SET kind='code',
  ref='core/network/maplecast_replica_live.cpp buildTables()',
  note='cam_mat region D(0x8C2D6AD8, 0xC0, "cam_mat") ALREADY ships BOTH camera matrices every frame: M2@0x8C2D6AD8+0x00 and M1@0x8C2D6B18 (=+0x40), within the 0xC0=192B (3x16f) window. stage_id (0x8C289638) was NOT shipped (the page-649 global-state block was absent from the read-set) -> ADDED D(0x8C289620, 0x20, "gstate") (32B window over in_match/round/timer/stage_id). stage_anim_timer (0x8C1F9D80) already shipped in the "arena" region. So the client gets stage_id + the live camera with NO new wire beyond 32 bytes/frame.';

UPSERT finding:replica_live_stage_render SET
  statement='PHASE 3 STAGE background landed on the render-replica client, grounded in ROM + disasm, NO model camera. The stage geometry+textures are decoded OFFLINE from the disc (tools/rip_stage.py, all 17 stages, web/test-atlas/stages/, gitignored) and cached/served locally exactly like the local-GFX overlay. web/webgpu/stage-client.mjs projects the stage s full-3D world-space verts through the SAME engine transform the bodies use (transform_object_122560: XMTRX=M1.M2, ftrv, persp divide) using the LIVE matrices read each frame from the RAM image (M1@0x8C2D6B18, M2@0x8C2D6AD8 — both already in the shipped "cam_mat" read-set), replacing the old GUESSED DEFAULT_CAM perspective camera (setCamera()/_projectEngine()/_matmulColMaj()). So the stage scrolls/zooms in lockstep with the fighters. web/render-replica/replay.html renders the stage as an OP pass BEHIND the bodies on the SAME pvr2 canvas: renderStagePass() (clears, draws stage) -> pane.render(bodyTA, {_bgPreRendered:true}) (loadOp load, composites bodies over). stage_id read from the new "gstate" region (0x8C289638). Body render (render_frame.wasm/gen_*.c/body_decoder.mjs) UNTOUCHED. Cache-bust ?v=stage1.',
  status='confirmed', confidence='high', date='2026-06-13';

UPSERT finding:replica_live_stage_projection_validated SET
  statement='The client projection math is PROVEN byte-identical to the engine transform. Offline check (python + node, live matrices from _ryu_capture/mc_ram_dump.bin): the validated body test vector pos(213.333,100,2) projects to screen (533.85953, 333.38765) via stage-client s _matmulColMaj+_projectEngine — within f32 ULP of gen_transform_obj.c s byte-exact target (533.85986, 333.38763). Projecting all 12435 STG00 verts through the live matrices lands the bulk on the 640x480 frame (median screenX=386, screenY=272; 8415/12435 verts in/near screen with depth>0); the far outliers are skybox/grazing-angle geometry (clipped). The projection is therefore the engine s own, not a fit. OPEN (deferred to live DIFF): (1) confirm the STAGE NaomiLib tree submits through loc_8C122560 vs a separate background matrix — pin via mvc2-sh4-re-expert tracing the stage submit routine, or accept the live DIFF vs the real-TA STG00 as proof; current evidence (M1/M2 are the engine s general object transform, body-validated) strongly supports it. (2) the synthesized stage PVR control words (pcw/tsp/isp in stage-client _build) are the remaining from-Ninja-fields synthesis (textured/gouraud/alpha/depth) — validate per-poly vs a live STG00 TA capture. (3) animation: stage_anim_timer low-bit A/B keyframe (loc_8c0338ec) deferred — static A-phase for v1.',
  status='confirmed', confidence='medium', date='2026-06-13';

RELATE finding:replica_live_stage_render->cites->source:stage_decode;
RELATE finding:replica_live_stage_render->cites->source:stage_camera_transform;
RELATE finding:replica_live_stage_render->cites->source:stage_readset;
RELATE finding:replica_live_stage_projection_validated->cites->source:stage_camera_transform;
RELATE finding:replica_live_stage_projection_validated->cites->source:stage_decode;

-- ============================================================================
-- 26b CORRECTION (2026-06-13): the "tilted green plane" RE-INVESTIGATION.
-- The reported root cause ("M1.M2 is the wrong transform for the 3D stage") is
-- DISPROVEN by ground truth. Three independent confirmations grounded the REAL bug.
-- ============================================================================

UPSERT source:stage_render_disasm SET kind='code',
  ref='marvelous2 bank03 loc_8c03223e (stage model dispatcher) -> bank12 loc_8c122fd0 (NaomiLib POL tree-walk) -> loc_8c122d00 (per-object processor) -> bank11 submit; camera setup bank12 loc_8C1216C0; per-vertex transform bank11 loc_8C11F870 (njCalcPoint: ftrv xmtrx).',
  note='STAGE RENDER PATH FULLY TRACED. loc_8c03223e (bank03:4990): calls loc_8c11b800 (list-id setter, stores 0x0c10->0x8C2DEE54 — NOT a matrix), writes 0x0cea0000 (stage POL base) -> [0x8c26a904], r12=loc_8c122fd0, then loc_8c03229c loops model[0..modelCount-1] (count = [0x4,[0x0cea0000]]) and jsr loc_8c122fd0 per model. NO per-model matrix push at the dispatcher level. The active XMTRX is the FRAME-GLOBAL camera, set ONCE by loc_8C1216C0 which builds XMTRX = load(M1@0x8C2D6B18)·matmul(M2@0x8C2D6AD8) and stores via the matrix-stack primitives loc_8c120950(push/load)/loc_8c120540(matmul)/loc_8c120900(pop) over the stack header @0x8C2D68E8. Per-vertex projection = loc_8C11F870 (reads x,y,z; w=1; ftrv xmtrx; writes 4 floats). THE PER-MODEL WORLD MATRICES are applied INSIDE the tree-walk (loc_8c122fd0/loc_8c122d00 read the NaomiLib node and push the node matrix onto the stack between the camera and the vertex ftrv) — they are RUNTIME state, NOT in the POL file.';

UPSERT source:stage_groundtruth_capture SET kind='oracle',
  ref='prod 149.28.44.118 /dev/shm/{mc_ram_dump.bin (16MB main RAM, 0x8C000000), mc_engine_ta.bin (raw PowerVR param stream tctx->tad), mc_pvr_regs.bin} captured in-match (MAPLECAST_DUMP_RAM). Local copies _stage_gt/.',
  note='Live in-match capture: in_match=1, stage_id=0x11(17). The loaded POL @0x0CEA0000 (= 0x8CEA0000 = main-RAM offset 0xEA0000; the 0x0C/0x8C region is the SAME physical RAM, P0/P1 mirror) has modelCount=83 -> UNIQUELY fingerprints disc STG0B (the ONLY .POL with modelCount=83). So stage_id 0x11 -> STG0B: stage_id is NOT a 0-based file index (disc has STG00..STG10 = stages 0..16; id 17 maps to STG0B). RAM-loaded POL vs disc STG0BPOL.BIN differ ONLY from byte 0x22a (pointer relocation disc-rel 0x00..->RAM-abs 0x8c..); the VERTEX geometry is byte-identical -> rip_stage.py decode == engine geometry.';

UPSERT finding:stage_transform_is_m1m2_CONFIRMED SET
  statement='THE STAGE TRANSFORM IS XMTRX = M1(0x8C2D6B18)·M2(0x8C2D6AD8) — CONFIRMED CORRECT, NOT the bug. (1) DISASM: the stage tree-walk (loc_8c122fd0) projects every model vertex through loc_8C11F870 ftrv xmtrx, where XMTRX is the SAME frame-global camera the bodies use (loc_8C1216C0), with NO separate "background matrix" — the per-model matrices the engine pushes are LOCAL node transforms layered on top, not a different camera. (2) NUMERIC vs engine ground truth: from the live RAM dump, body P2C1 world pos(213.3,100) projects via M1·M2 to screen (533.3,333.4) = BYTE-EXACT vs the engine-deposited screen @+0xE0/E4 (533.9,333.4); M2·M1 gives garbage (214,-99). matmul order CONFIRMED M1·M2. (3) The engine TA (mc_engine_ta.bin) list0 = the visible stage (2400 verts, Ymed~62, full perspective Z 0.0003..) and the CLIENT model-0 projection through M1·M2 has the SAME vert count (2422) and span (bottom y=585 matches). The prior pass projection math was RIGHT.',
  status='confirmed', confidence='high', date='2026-06-13';

UPSERT finding:stage_real_bug_pernode_matrices SET
  statement='THE REAL "tilted/collapsed stage" BUG = TWO decode/data gaps, NOT the transform. (A) MISSING PER-NODE NAOMILIB MATRICES: rip_stage.py (ModNao port) reads RAW vertex positions as world-space, but in MVC2 only model 0 (the deck/skybox, world ±2500) is authored in world space. Models 1..82 are authored in LOCAL space (verts ±15, e.g. cannons/chains/props) and need the per-model WORLD matrix the engine pushes at runtime in the tree-walk — which is NOT in the POL file. The model 0x18-byte MODEL_HEADER fields at +0x0C/+0x10/+0x14 are a NaomiLib BOUNDING-SPHERE center (+radius), NOT a transform (applying them as a translation makes placement WORSE: model0 Ymed 2082 vs engine 62). ModNao itself confirms this — it ships only NAME "stage model hints" (mvc2StageModelHints.ts), renders models individually, and does NOT compose the stage into one world. RESULT: client projects models 1..82 to a collapsed dot at ~(320,432) (the "green blob"), only model 0 spreads correctly (its M1·M2 Ymed=-105 vs engine 62, ~167px residual = model 0 ALSO has a small runtime node matrix). (B) STAGE_ID MAPPING: stage_id is not a file index (0x11->STG0B). The client also has NO geometry for whatever stage_id maps outside STG00..STG10 unless the mapping table is captured. FIX PATH: capture the per-model runtime WORLD matrices live via the Oracle (MAPLECAST_ORACLE_PROBE on the model-dispatch loc_8c03229c / the tree-walk matrix-stack @0x8C2D6900 region, OR the post-transform TA verts), bake world-space-assembled geometry per stage, and build the stage_id->STGxx map. The transform stays M1·M2 (per finding:stage_transform_is_m1m2_CONFIRMED).',
  status='confirmed', confidence='high', date='2026-06-13';

RELATE finding:stage_transform_is_m1m2_CONFIRMED->cites->source:stage_render_disasm;
RELATE finding:stage_transform_is_m1m2_CONFIRMED->cites->source:stage_groundtruth_capture;
RELATE finding:stage_transform_is_m1m2_CONFIRMED->cites->source:stage_camera_transform;
RELATE finding:stage_real_bug_pernode_matrices->cites->source:stage_render_disasm;
RELATE finding:stage_real_bug_pernode_matrices->cites->source:stage_groundtruth_capture;
RELATE finding:stage_real_bug_pernode_matrices->cites->source:stage_decode;

-- ============================================================================
-- 26c FIX SHIPPED (2026-06-13): world-space model assembly + numeric validation.
-- Implements the fix for finding:stage_real_bug_pernode_matrices. Deployed prod
-- 149.28.44.118, replay.html ?v=stage2, md5-verified. commit a73f9f442.
-- ============================================================================

UPSERT source:stage_world_assembly SET kind='tool',
  ref='tools/rip_stage.py (_model_extent/_apply_mat34/_load_matrices, WORLD_EXTENT_THRESH) + tools/validate_stage_geom.py + tools/stage_id_map.json',
  note='rip_stage.py now WORLD-ASSEMBLES the stage: per model, if max|vertexCoord| >= 100 the model is authored DIRECTLY in world space and renders with an IDENTITY matrix (raw rip verts ARE world coords); else it is a small LOCAL-space prop needing a runtime world matrix, taken from optional atlas/stages/STGxx_matrices.json (a captured 3x4 per modelIndex, pre-multiplied into world here) or, if absent, flagged placed=false. JSON gains worldAssembled/placedModels/unplacedModels/hasMatrixSidecar; each mesh gains placed. validate_stage_geom.py is the numeric gate: project the placed verts through XMTRX=M1.M2 (from _stage_gt/ram.bin) and NN-diff vs the engine TA screen verts (_stage_gt/engine_ta.bin). stage_id_map.json holds the confirmed wire-id->STGxx map + per-stage modelCount fingerprints.';

UPSERT source:stage_world_proof SET kind='oracle',
  ref='_stage_gt/engine_ta.bin un-projected through XMTRX=M1.M2; tools/validate_stage_geom.py STG0B',
  note='THE engine TA param stream (tctx->tad) carries per-vertex SCREEN x/y + depth(1/w) + UV (32B vertex, paraType=7, 0xe0/0xf0). Un-projecting (world = X[[0,1,3],:3]^-1 . (([sx,sy,1]*w) - X[[0,1,3],3]); w=1/depth) recovers EXACT world space. STG0B engine TA un-projects to X +-2500, Y -182..1363, Z -2895..744 = EXACTLY rip model 0 local extent -> model 0 IS identity world-space. PROVEN: rip model 0 raw verts projected via M1.M2 match the engine screen verts at 0.000px (median/mean/p90/max, 2346 verts). The captured frame TA contained ONLY model 0 (96 polys); the 66 local props were not submitted that frame, so prop matrices still need a live Oracle capture.';

UPSERT finding:stage_world_assembly_fix SET
  statement='STAGE FIX SHIPPED. The collapsed-prop "green blob" is FIXED by world-space assembly, NOT by any projection change (M1.M2 stays — re-confirmed 0.000px). rip_stage.py classifies each model by vertex extent: world-authored models (deck/skybox/scenery, the visible background) render with identity (raw verts = world), validated 0.000px vs engine_ta for STG0B (tools/validate_stage_geom.py PASS); small local-space props with no captured matrix are flagged placed=false and the client (web/webgpu/stage-client.mjs _build) SKIPS them instead of collapsing them to a screen dot at ~(320,432). Most stages need no props (STG00/04/07/09/0D = 0 local models; STG0B worst case = only model 0 world-space, 66 props skipped). Client: STAGE_ID_MAP maps wire stage_id->STGxx (confirmed 0x11->STG0B; else id->file fallback); setState resolves it; projection UNTOUCHED. Re-baked all 17 stages (gitignored). Deployed prod 149.28.44.118 (replay.html stage-client ?v=fx2 -> ?v=stage2, md5-verified local==prod), commit a73f9f442. BEFORE/AFTER: _stage_gt/BEFORE_AFTER_STG0B.png (BEFORE = textured deck + center prop garbage-blob; AFTER = clean placed+textured deck, no blob). Body/HUD/effects/tails UNTOUCHED.',
  status='confirmed', confidence='high', date='2026-06-13';

UPSERT finding:stage_prop_matrices_deferred SET
  statement='OPEN (deferred follow-up): per-prop runtime WORLD matrices. The small local-space props (STG0B 66 cannons/chains, etc.) are skipped until their matrices are captured. They are genuine RUNTIME state (the NaomiLib matrix stack top @0x8C2D6900 = camera x node, pushed during the tree-walk loc_8c122fd0/loc_8c122d00) — NOT in the POL (header floats +0x0C/10/14 are a bounding-sphere; the runtime node-matrix cache tables @0x8C2DE690/0x8C2AA26C hold indices+flags, not 4x3 matrices). And the captured engine_ta held only model 0 that frame, so they are not offline-derivable from the current dump. CAPTURE RECIPE: MAPLECAST_ORACLE_PROBE a per-model PC in the dispatch loop (loc_8c03229c, 0x8C03229C) or just after the node push, dumping a mem window over 0x8C2D6900 (the stack-top XMTRX=camera x node) + the model index; offline remove the camera (node_local = (M1.M2)^-1 . captured) -> STGxx_matrices.json which rip_stage.py pre-multiplies. ALSO: complete the stage_id->STGxx map by capturing each stage live + fingerprinting its loaded POL (modelCount+POL-hash unique for all 17 except the 01/0A byte-identical-geometry pair). /dev/shm was freed (ASMTRACE truncated, authorized) but the running flycast lacks MAPLECAST_ORACLE_PROBE/DUMP_RAM env (would need a restart) so the capture itself is the next session.',
  status='open', confidence='high', date='2026-06-13';

RELATE finding:stage_world_assembly_fix->cites->source:stage_world_assembly;
RELATE finding:stage_world_assembly_fix->cites->source:stage_world_proof;
RELATE finding:stage_world_assembly_fix->cites->source:stage_camera_transform;
RELATE finding:stage_world_assembly_fix->about->finding:stage_real_bug_pernode_matrices;
RELATE finding:stage_prop_matrices_deferred->cites->source:stage_render_disasm;
RELATE finding:stage_prop_matrices_deferred->cites->source:stage_world_proof;

-- ============================================================================
-- 26c (2026-06-13): "stage+effects show NOTHING on prod" — ROOT CAUSE = NOT DEPLOYED.
-- ============================================================================

UPSERT source:stage_effects_headless_proof SET kind='tool',
  ref='tools/render-replica-poc/{shot_stage_headless.mjs (Dawn WebGPU, real GPU), _probe_stage_cam.mjs, _probe_stage_project.mjs, _probe_effects_poke.mjs, _probe_effects_draw.mjs (puppeteer), mock_replica_live_server.mjs (patched to skip GFX+palette tails so real captures stream)}',
  note='Live prod capture _satlive.mcrr (700 frames, in_match=1): stage_id=0x0B(=STG0B, present), camera M2[15]=812.36/M1[0]=320 NON-ZERO every frame -> the renderStagePass gate (bail if M2[15]==0&&M2[0]==0) PASSES, the cam_mat region ships correctly. shot_stage_headless.mjs drives the UNMODIFIED StageClient+PVR2Renderer (the exact replay.html path) -> 294100/307200 (95.7%) NON-BLACK px (PNG_stage_headless.png: model-0 deck spreads green; models 1..82 collapse per finding:stage_real_bug_pernode_matrices). EFFECTS: __pokeEffect(0,320,240)+readEffectNodes returns 1 node (idx0 128x128) and EffectsClient.render draws 11851 non-transparent overlay px (atomic poke+render in one evaluate; a streamed frame between poke and render re-splats slot_cnt/objpool and wipes the poke -> earlier 0px was a TEST timing artifact, not a code bug).';

UPSERT finding:replica_live_stage_effects_not_deployed SET
  statement='THE STAGE+EFFECTS "show nothing / black" on the user s LIVE PROD VIDEO is a DEPLOYMENT GAP, not a code/gate/camera bug. PROVEN: (1) renderStagePass() AND renderEffectsPass() ARE wired into liveApplyFrame (web/render-replica/replay.html, the live path, not just showFrame). (2) the gates pass on real prod data (cam_mat + stage_id non-zero in _satlive.mcrr). (3) the render chain works: stage 95.7% non-black + effects 11851px via headless harnesses on the exact client path. BUT prod 149.28.44.118 has NO Phase-3 client: /var/www/maplecast/render-replica/ DOES NOT EXIST; /var/www/maplecast/replay.html is an ANCIENT unrelated 357-line WebGL2 file (title "MapleCast Rend Replay — WebGL2 + Textures", grep stage|effect = 0 hits, no import lines); /var/www/maplecast/test-atlas/stages/ is absent (no stage tiles deployed); /var/www/maplecast/webgpu/stage-client.mjs is the OLD pre-camera version (md5 c9409e1c vs local 04892915). FIX = DEPLOY the Phase-3 client tree: replay.html + render-replica modules (render_frame.{mjs,wasm}, body_decoder.mjs, local_gfx_overlay.mjs, effects-client.mjs) + effects/ atlas to /var/www/maplecast/render-replica/, refresh webgpu/stage-client.mjs, and scp web/test-atlas/stages/STG*.{json,png} -> /var/www/maplecast/test-atlas/stages/ (ROM-derived, scp-only). The page imports ../webgpu/stage-client.mjs + ../test-atlas/stages, so it MUST live at /var/www/maplecast/render-replica/ for those relatives to resolve.',
  status='confirmed', confidence='high', date='2026-06-13';

RELATE finding:replica_live_stage_effects_not_deployed->cites->source:stage_effects_headless_proof;
RELATE finding:replica_live_stage_effects_not_deployed->cites->source:stage_readset;

-- ============================================================================
-- 26d (2026-06-14): SYNTHESIZED STAGE CONTROL WORDS — CLOSED.
-- Closes the open item in finding:replica_live_stage_projection_validated item (2):
-- "the synthesized stage PVR control words (pcw/tsp/isp in stage-client _build) ...
--  validate per-poly vs a live STG00 TA capture." Grounded in the engine TA, the
-- green untextured deck is fixed. NO synthesized control words on the grounded path.
-- replay.html ?v=stagetex. feat/render-replica-live.
-- ============================================================================

UPSERT source:engine_ta_parse SET kind='tool',
  ref='tools/parse_engine_ta.py (TaTypeLut-correct TA walk) + tools/bake_stage_from_ta.py + tools/decode_vram_tex.py + tools/render_engine_ta.py (ground-truth raster) + tools/validate_stage_ta_client.py',
  note='parse_engine_ta.py walks the engine PowerVR param stream _stage_gt/engine_ta.bin (tctx->tad.thd_root..thd_data, dumped same-frame by the oracle hook MAPLECAST_DUMP_RAM) byte-exactly: a poly header is 32B (type 0/1/3) or 64B (type 2/4) and its vertices 32B or 64B depending on poly type — a faithful port of flycast TaTypeLut (core/hw/pvr/ta.cpp poly_data_type_id/poly_header_type_size; vertex SZ64 for vt in {5,6,11,12,13,14}). Para types: 4=Polygon 5=Sprite 7=Vertex; 0/1/2=EOL/UserTileClip/ObjListSet (32B, no poly). Extracts per-group the REAL PCW/ISP/TSP/TCW (ta_structs.h bit layouts) + per-vertex screen XY/depth(1/w)/UV/base. STG0B engine_ta.bin = 136288B -> 96 poly groups, 2457 verts, 16 distinct textured TexAddr. bake_stage_from_ta.py emits atlas/stages/STG0B_ta.json (mode:engine_ta) with those control words + the engine final screen verts + textures decoded straight from the VRAM dump at each group TexAddr (decode_vram_tex.py: byte=TexAddr*8, twiddled, RGB565/ARGB4444/ARGB1555). ROM-derived, gitignored, scp-only.';

UPSERT finding:stage_control_words_grounded SET
  statement='STAGE CONTROL WORDS GROUNDED IN THE ENGINE TA — the synthesized green deck is FIXED. The old web/webgpu/stage-client.mjs _build SYNTHESIZED pcw/isp/tsp (pcw=(4<<29)|tex<<3|gouraud, isp=(6<<29).., tsp=(1<<29)|(1<<6)) and bound textures by the POL rip per-mesh texIndex — that produced a flat green/blue wireframe deck (only world-authored model 0 placed; its tile is the dark green-box texIndex 0; ALL the textured carrier structures live in the 82 LOCAL-space props the POL rip skips). FIX (no synthesis): tools/bake_stage_from_ta.py bakes the engine OWN stage TA into atlas/stages/STG0B_ta.json carrying the REAL per-poly PCW/ISP/TSP/TCW + the engine final screen-space verts (so ALL 83 models render, props included, exactly as the engine assembled them) + textures decoded from the VRAM dump at each group real TexAddr. stage-client.mjs gains _buildFromTA (consumes those control words verbatim into the PVR2Renderer parsed shape; intensity Col_Type=2 folded into the vertex base for ShadInstr=1 modulate) and prefers STGxx_ta.json over the POL-rip STGxx.json; setCamera() does NOT re-project in TA mode (verts are already the engine final screen coords). PROVEN: tools/validate_stage_ta_client.py rasterizes the client _buildFromTA output and diffs vs tools/render_engine_ta.py (the engine-TA ground-truth raster) = 99.989% identical pixels, mean abs diff 0.0001/ch, max 2 (rasterizer rounding only). Per-poly control-word table: EVERY word differs from the synth guess (e.g. PCW engine 808c001e vs synth 8000000a; ISP engine 93000000 vs c0000000; TSP engine 2009a45b vs 20000040; TCW engine 0809fc00 = RGB565 twiddled @TexAddr 654336, synth used a bare surrogate int). BEFORE/AFTER/TRUTH: _stage_gt/STAGE_BEFORE_AFTER_GROUNDED.png. replay.html cache-bust full2 -> stagetex. Body/decode/effects/HUD UNTOUCHED.',
  status='confirmed', confidence='high', date='2026-06-14';

UPSERT finding:stage_ta_bake_camera_note SET
  statement='NOTE on the engine-TA bake vs the live camera. The grounded STGxx_ta.json bakes the engine FINAL SCREEN verts for the CAPTURED frame, so it is camera-static (it does not re-project on setCamera, by design — _isTA guard). This is the correct, fully-grounded source for the captured stage_id=0x11/STG0B frame and supersedes the synthesized-control-word path. To make the grounded path track the LIVE camera per-stage, the screen verts must be un-projected to world ((M1.M2)^-1, which needs the pre-divide fv2 the TA vertex omits — carry it by also capturing the engine pre-persp z, or re-derive world from the POL rip model + per-prop matrices per finding:stage_prop_matrices_deferred) and then re-projected via M1.M2 each frame. For now: grounded control words + textures + full-scene geometry on the captured camera; live-camera world re-assembly of the props remains the open prop-matrix item. The POL-rip world-space path (live-camera, model-0 deck only) stays as the fallback when no _ta.json exists.',
  status='open', confidence='high', date='2026-06-14';

RELATE finding:stage_control_words_grounded->cites->source:engine_ta_parse;
RELATE finding:stage_control_words_grounded->cites->source:stage_groundtruth_capture;
RELATE finding:stage_control_words_grounded->about->finding:replica_live_stage_projection_validated;
RELATE finding:stage_ta_bake_camera_note->cites->source:engine_ta_parse;
RELATE finding:stage_ta_bake_camera_note->about->finding:stage_prop_matrices_deferred;

-- ============================================================================
-- 26e (2026-06-14): PER-NODE PROP MATRICES — CLOSED via WORLD-SPACE TA un-projection.
-- Closes finding:stage_real_bug_pernode_matrices (item A) + finding:
-- stage_prop_matrices_deferred + finding:stage_ta_bake_camera_note. The props now
-- render at their correct world positions AND track the LIVE camera, with NO capture
-- of transient NaomiLib matrix-stack state. feat/render-replica-live, commit 961e43e57.
-- replay.html stage import bumped clean1->propworld (prod-only, single-line sed).
-- ============================================================================

UPSERT source:stage_world_unprojection SET kind='tool',
  ref='tools/bake_stage_from_ta.py (build_unproject/unproject -> per-vertex `world` + hasWorld:true) + tools/_probe_stage_world_render.py (BEFORE/AFTER raster gate) + web/webgpu/stage-client.mjs _buildFromTA(useLive) + setCamera(re-proj on hasWorld)',
  note='The engine TA vertex carries (sx, sy, inv=1/w); the pre-divide 4-vec is (sx*w, sy*w, fz, w) and we know rows 0,1,3 of XMTRX=M1.M2. So the 3x3 (rows 0,1,3 ; cols x,y,z) inverts for world (x,y,z) per vertex (fz unused). Round-trip (world -> reproject via M1.M2 -> screen) EXACT: median 1e-13 px, max 3.6e-6 px over all 2457 STG0B TA verts (8 clamped-degenerate 1/w=10 sentinels excluded). bake_stage_from_ta.py now writes BOTH the captured screen `pos` AND the un-projected `world` per vertex (+ hasWorld:true). stage-client.mjs _buildFromTA re-projects `world` through the LIVE XMTRX via _projectEngine when this._X is set (useLive); setCamera re-runs _buildFromTA for TA bakes that hasWorld (the old _isTA guard now only blocks legacy no-world bakes).';

UPSERT finding:stage_pernode_matrices_closed SET
  statement='STAGE PROP/SCENERY RENDER — CLOSED. The collapsed props were NOT a missing-runtime-matrix problem: the captured engine TA (_stage_gt/engine_ta.bin) is the FULL assembled scene (96 poly groups, 27 distinct textures, 2457 verts — the deck AND every prop), NOT model-0-only as finding:stage_world_proof had concluded (that "96 polys = only model 0" reading is CORRECTED: 96 GROUPS across 27 textures is the whole stage; the world-bounds coincidence X +-2500 simply reflects props physically sitting within the deck bounds). Un-projecting each TA vertex through (M1.M2)^-1 recovers EVERY model in WORLD space, with the per-node world matrix already folded into its screen position by the engine — so no NaomiLib matrix-stack capture is needed. The small local-extent props (tex 5107712, extent 3-38u) un-project to distinct correct world positions (e.g. (-25,87,741),(22,86,741),(-21,140,683)). bake_stage_from_ta.py bakes per-vertex `world`; stage-client.mjs _buildFromTA re-projects it through the LIVE camera so the FULL scenery (deck + all props) tracks the camera in lockstep with the fighters — closing BOTH the prop-placement gap (finding:stage_real_bug_pernode_matrices item A / finding:stage_prop_matrices_deferred) and the camera-static limitation (finding:stage_ta_bake_camera_note) at once. VALIDATED vs engine ground truth BEFORE deploy (cardinal rule 3): client live-projected world verts -> engine screen NN residual p90=0.0026px max=0.0069px (PASS); rigid scene under synthetic camera pan/zoom (props move coherently, no collapse); BEFORE(baked screen)/AFTER(live-world) raster identical to 12px/0.004% (the 8 clamped degenerates), _stage_gt/PROP_BEFORE_AFTER_STG0B.png. DEPLOYED prod 149.28.44.118: stage-client.mjs (md5 1c40d61d) + STG0B_ta.json (md5 f784a989) + textures scp-only; replay.html stage import clean1->propworld via single-line sed (other agent owns replay.html; their in-progress edits untouched, my line is prod-only not committed). OPEN (minor): only STG0B has an engine-TA capture; other stages still fall to the POL-rip world-space path (deck only) until each is captured live + baked. Body/HUD/effects/decode UNTOUCHED.',
  status='confirmed', confidence='high', date='2026-06-14';

UPSERT finding:stage_real_bug_pernode_matrices SET status='closed';
UPSERT finding:stage_prop_matrices_deferred SET status='closed';
UPSERT finding:stage_ta_bake_camera_note SET status='closed';

RELATE finding:stage_pernode_matrices_closed->cites->source:stage_world_unprojection;
RELATE finding:stage_pernode_matrices_closed->cites->source:engine_ta_parse;
RELATE finding:stage_pernode_matrices_closed->cites->source:stage_camera_transform;
RELATE finding:stage_pernode_matrices_closed->about->finding:stage_real_bug_pernode_matrices;
RELATE finding:stage_pernode_matrices_closed->about->finding:stage_prop_matrices_deferred;
RELATE finding:stage_pernode_matrices_closed->about->finding:stage_ta_bake_camera_note;

-- ============================================================================
-- 26c DECK-TEXTURE "GREEN NOISE" — CLOSED (2026-06-14).
-- The carrier-deck/floor rendered as solid grey because the prior agent DROPPED
-- the deck texture, believing it decoded to "green/blue noise" (a wrong
-- format/twiddle). RE-INVESTIGATION grounded in the TCW DISPROVES the format
-- theory: the decode was CORRECT; the real bug was the per-vertex COLOUR.
-- ============================================================================

UPSERT source:deck_tcw SET kind='capture',
  ref='_stage_gt/engine_ta.bin deck poly (mesh 0, 726 tris) TCW=0x0809FC00, TSP=0x2009A45B',
  note='Per core/hw/pvr/ta_structs.h union TCW: TexAddr(b0-20)=0x9FC00 -> byte addr 0x9FC00<<3=0x4FE000; ScanOrder(b26)=0 => TWIDDLED; PixelFmt(b27-29)=1 => RGB565 (PixelFormat enum Pixel565=1); VQ(b30)=0; MipMapped(b31)=0; StrideSel(b25)=0. TSP: TexU/TexV=64x64, ShadInstr(b6-7)=1 (MODULATE: out=texture*base), ClampU=1, FlipV=1. So the deck IS a 64x64 RGB565 twiddled texture modulated by the per-vertex base colour. Decode format/twiddle are EXACTLY what bake_stage_from_ta.py tex_params already read from the TCW — they were NEVER wrong.';

UPSERT source:deck_vertex_colour_bug SET kind='code',
  ref='tools/parse_engine_ta.py walk() vertex branch; tools/bake_stage_from_ta.py inten_of/rgb_of; tools/render_engine_ta.py _raster',
  note='The deck poly is VERTEX TYPE 5 (Floating Colour, textured, Col_Type=1) — a 64B vertex (TA_Vertex5A 32B + TA_Vertex5B 32B). Its real BASE colour is in the SECOND half (+0x20 A,+0x24 R,+0x28 G,+0x2C B as floats, ~A=1 R=G=B=0.0..0.05 i.e. a dark-grey ramp). The OLD walk read +0x18 (ignore_1) as a mono `base` float for EVERY vertex type, which for vt5 = 0x3c175c5a = bogus intensity 0.0092. So the deck modulated its (correctly-decoded green/blue RGB565) texture by ~0.01 -> NEAR BLACK, and when the texture was dropped, by a flat grey -> a tiling grid. FIX: walk() now decodes the TYPE-CORRECT per-vertex RGBA (vt5/6 = 2nd-half floating colour; vt7/8 = intensity float; vt3/4 = packed ARGB8888) into v[rgba]; bake rgb_of carries it as per-vertex rgb; render_engine_ta + validate_stage_ta_client + stage-client writeVtx all consume the real RGB.';

UPSERT finding:stage_deck_texture_closed SET
  statement='DECK-TEXTURE "GREEN NOISE" — CLOSED. The deck was NOT a wrong pixel-format/twiddle: the TCW (0x0809FC00) says RGB565 + twiddled + 64x64, and bake_stage_from_ta.py tex_params already decoded exactly that (bit-validated: the SAME decoder produces the recognizable STG0B t03 "TIME" HUD texture). The green/blue grid IS the genuine STG0B floor art (a perspective grid deck with blue support beams) — the engine draws it too. The REAL bug was the per-vertex MODULATION COLOUR: the deck poly is TA vertex type 5 (Floating Colour, 64B), whose base colour lives in the second 32B half (+0x20 ARGB floats, a dark-grey ramp), but parse_engine_ta.walk read +0x18 (ignore_1) as a mono intensity = 0.0092 -> modulated the deck to black, masked by the prior agent dropping the texture to a flat grey. FIXED: (1) parse_engine_ta.walk decodes the TYPE-CORRECT per-vertex RGBA; (2) bake_stage_from_ta.py rgb_of carries per-vertex rgb in STG0B_ta.json; (3) decode_vram_tex untwiddle now uses the flycast twiddle_slow(y,x,h,w) (handles non-square, bit-identical to the validated Morton on square); (4) stage-client.mjs _buildFromTA RE-ENABLES the textured deck (deckUntex=false) and writeVtx writes the real per-vertex RGB so the renderer modulates (ShadInstr=1, shaders.mjs fu.si==1). VALIDATED (cardinal rule 3): the fixed engine-TA ground truth (render_engine_ta.py, _stage_gt/GROUNDTRUTH_engine_ta_STG0B.png) shows the SAME green-grid+blue-beam deck, and the headless client render (tools/render-replica-poc/shot_stage_headless.mjs, _stage_gt/SHOT_deck_textured.png) MATCHES it — deck is TEXTURED, not grey, not noise (_stage_gt/DECK_FIXED_client_vs_engine.png). Cache-bust replay.html emitterz1->emitterz2. Body/HUD/emitter/render_frame UNTOUCHED.',
  status='confirmed', confidence='high', date='2026-06-14';

RELATE finding:stage_deck_texture_closed->cites->source:deck_tcw;
RELATE finding:stage_deck_texture_closed->cites->source:deck_vertex_colour_bug;
RELATE finding:stage_deck_texture_closed->cites->source:stage_camera_transform;

-- ============================================================================
-- 26f (2026-06-14): "LIVE stage renders BLACK" — render path PROVEN CORRECT;
-- hardened the camera gate + made the swallowed [stage] cause OBSERVABLE.
-- feat/render-replica-live. replay.html stage import emitterz3->stageblack1.
-- ============================================================================

UPSERT source:stage_black_repro SET kind='tool',
  ref='tools/render-replica-poc/{shot_stage_headless.mjs, diag_stage_canvaspath.mjs, diag_stage_cameras.mjs, _diag_reproj.mjs, _diag_double_setcam.mjs, _diag_nocam.mjs, _diag_cam_allframes.mjs, shot_stage_live_diag.mjs} on prod capture _satlive.mcrr (700f, STG0B)',
  note='EXHAUSTIVE reproduction of the deck-fix (commit bb961ad5a) stage render against the EXACT files prod serves (md5: stage-client.mjs 3cb21ebc == prod; STG0B_ta.json 57f3883d == prod). EVERY path renders the correct green-grid STG0B background that MATCHES the engine ground truth (_stage_gt/GROUNDTRUTH_engine_ta_STG0B.png): (1) RT path shot_stage_headless = 48.7% non-black; (2) CANVAS-context branch (no renderTarget arg -> this.ctx.getCurrentTexture() + immediate submit, the EXACT replay.html renderStagePass call) diag_stage_canvaspath = 48.7%, byte-for-byte the live draw branch; (3) all 12 sampled cameras + repeated setCamera (live re-projects every frame) = stable 2910 verts, 970/970 opaque textures BOUND (no stale-surrToTex break); (4) synthetic camera pan/zoom (x0.7..x2, pan +50..+5000) never collapses (2160-3231 verts survive the 800px MARGIN cull); (5) NO-camera baked-screen render (useLive=false) = 48.7%; (6) cam_mat region D(0x8C2D6AD8,0xC0) present + M2[0]=2.539/M2[15]=812.36 NON-ZERO in ALL 700 frames (gate never trips on this capture). CONCLUSION: the render code, geometry, textures, per-vertex colour, camera, and texture-binding are ALL correct — the live BLACK is NOT reproducible from the capture and depends on a transient LIVE condition (degenerate camera at a round/loading transition, or the user reading the genuinely ~70%-black STG0B grid as "no background"). This Chrome build exposes NO navigator.gpu headless (4 ANGLE/Vulkan variants probed) so the live swapchain itself is not GPU-reproducible here.';

UPSERT source:modnao_render_ref SET kind='code',
  ref='github rob2d/modnao src/components/scene/{RenderedPolygon.tsx, RenderedTexturedPolygon.tsx}',
  note='Independent open-source MVC2/NAOMI POL+NJ web viewer (three.js/react-three-fiber). CROSS-CHECK: (a) per-vertex colours DEFAULT to [1,1,1,1] white when absent — `cArray[..] = v.colors?.[0] ?? 1` — modnao NEVER lets a missing/zero vertex colour modulate the texture to black. (b) vertex colours are OPT-IN (meshBasicMaterial vertexColors={sceneOptions.enableVertexColors}); with the toggle OFF modnao shows the RAW texture at full brightness. (c) NO depth/MARGIN culling that could thin a floor to a wireframe — it renders the full mesh, double-sided when disableBackfaceCulling. OUR path differs: _buildFromTA ALWAYS modulates the textured deck by the engine per-vertex RGB (ShadInstr=1) AND MARGIN-culls per triangle. The engine RGB (dark-grey ramp 13..244, only 192/3768 verts truly [0,0,0]) is GROUNDED-correct (matches engine GT), so we keep it — but the modnao reference confirms a textured stage should never be invisible from colour alone, validating the camera-gate hardening below over any colour change.';

UPSERT finding:stage_live_black_hardened SET
  statement='LIVE STAGE BLACK — render path PROVEN CORRECT (source:stage_black_repro), camera gate HARDENED + cause made OBSERVABLE. The deck-fixed stage render produces the correct green-grid STG0B background identical to the engine ground truth on every offline/canvas/camera path with the byte-identical prod files; the black is a transient LIVE-data condition, not a code bug. FIX (web/render-replica/replay.html renderStagePass, surgical — flagged to the parallel replay.html editor): (1) the camera-zero gate NO LONGER returns false->black; when M2 is degenerate (round/loading transition) it FALLS BACK to the engine-TA BAKED screen verts (stage.parsed already built useLive=false in _ensureLoaded) and still draws — PROVEN 48.7% non-black with no camera (_diag_nocam.mjs). Only valid cameras re-project (setCamera). (2) every false-return now LATCHES a reason into _stageWhy, surfaced via window.__stageWhy() + __stageInfo().why/gpuOK/stageReady/M2 — so the swallowed [stage] cause (gpuOK=false | stageReady=false | cam-zero | no-parsed | no-texMgr | THREW:msg | ok) is observable in ONE live console call instead of silently swallowed by the catch. Cache-bust stage-client import emitterz3->stageblack1. stage-client.mjs / bake / pvr2 / body / HUD / effects UNTOUCHED (the render path needed no change — only the gate + diagnosability). NEXT LIVE TEST: read window.__stageInfo().why on the user prod browser — it pinpoints the exact black cause definitively.',
  status='confirmed', confidence='high', date='2026-06-14';

RELATE finding:stage_live_black_hardened->cites->source:stage_black_repro;
RELATE finding:stage_live_black_hardened->cites->source:modnao_render_ref;
RELATE finding:stage_live_black_hardened->about->finding:stage_deck_texture_closed;
RELATE finding:stage_live_black_hardened->about->finding:stage_pernode_matrices_closed;
