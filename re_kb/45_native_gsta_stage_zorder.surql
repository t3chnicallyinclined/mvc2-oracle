-- ============================================================================
-- 45 (2026-06-15): NATIVE GSTA CLIENT — STAGE render + engine Z-ORDER lists.
-- The native GSTA client (MAPLECAST_GSTA_CLIENT, build/flycast.exe) rendered the
-- stage BLACK and forced ALL quads into one Translucent list. This lands the stage
-- as an OPAQUE pass behind the bodies, honoring the engine's real per-object list
-- structure. feat/render-replica-live, commit ed11835b2.
-- ============================================================================
USE NS re DB kb;

UPSERT source:gsta_zorder_disasm SET kind='code',
  ref='tools/render-replica-poc/gen_submit_params.c finalize_body (loc_8c1246b0) + atlas/stages/STG0B_ta.json (engine-TA bake) + core/hw/pvr/ta.cpp ta_handle_cmd FSM + ta_structs.h PCW ListType/ParaType',
  note='Z-ORDER GROUND TRUTH. (1) BODIES are genuinely TRANSLUCENT (ListType=2): finalize_body (bank12 loc_8c1246b0/loc_8C124720) sets PCW |= 0x02000000 = bit25 = ListType 2. So the existing all-TR body emit was CORRECT, not a bug. (2) STAGE is genuinely OPAQUE (ListType=0, ParaType=4 Polygon): the STG0B engine-TA bake = all 72 meshes PCW high byte 0x80 -> ParaType=(>>29)&7=4, ListType=(>>24)&7=0. (3) flycast ta_handle_cmd FSM reads pcw.ListType on the first poly/sprite of a list (if ta_fsm_cl==7) and an End_Of_List (32 zero bytes, ParaType=0) resets ta_fsm_cl=7. So emitting [stage OP polygons][EOL][body TR sprites] makes flycast accumulate OP then TR; the renderer draws OP->PT->TR -> stage BEHIND bodies. VERIFIED live: parsed verts=3139 op=930 pt=0 tr=87 (was op=0, all tr).';

UPSERT source:gsta_stage_impl SET kind='code',
  ref='core/network/gsta_stage.cpp / gsta_stage.h (gstaStageEnsureLoaded/gstaStageEmitTA), wired into maplecast_mirror.cpp gstaApplyFrame; gstaEmitSpriteTA renamed gstaEmitSpriteTA_append',
  note='Faithful C++ port of web/webgpu/stage-client.mjs _buildFromTA. Loads atlas/stages/STGxx_ta.json (engine-TA grounded bake: real PCW/ISP/TSP/TCW + per-vertex screen pos / un-projected world / uv / rgb). stage_id read from _gstaRam[0x289638] (gstate region); camera M2@0x8C2D6AD8 + M1@0x8C2D6B18 read from _gstaRam (cam_mat region, both ship every frame). XMTRX=M1.M2 col-major (matmulColMaj == _matmulColMaj); world-authored meshes (minZ<-500 OR |worldX|>1000) re-project through the LIVE camera (projectEngine = transform_object_122560 ftrv+persp-divide), local props use the engine baked screen pos (re_kb 26 per-mesh gate); MARGIN=800 culls the un-placeable degenerate prop tris. STAGE TEXTURES are already resident in the seeded vram[] at each mesh TCW (the GSTA prefix ships full 8MB engine VRAM) -> NO PNG decode needed natively, the bake TCW points straight at VRAM. Emitted as ParaType=4 Polygon + 3x TA_Vertex3 (packed-colour, UV32; PCW obj_ctrl forced to 0x08 Texture-only so the FSM selects vertex type 3); per-vertex RGB carried as ARGB8888 BaseCol (ShadInstr=1 modulate).';

UPSERT finding:native_gsta_stage_zorder SET
  statement='NATIVE GSTA CLIENT now renders the STAGE behind the bodies with the engine list structure honored (was: stage BLACK + all quads forced into one TR list). Z-order: bodies stay TR (CONFIRMED ListType 2 from finalize_body PCW|0x02000000), the stage emits as an OPAQUE polygon-TA pass (CONFIRMED ListType 0 from the STG0B engine-TA bake) closed with an End_Of_List before the TR body sprites, so flycast draws OP->PT->TR and the stage lands behind. Stage = gsta_stage.cpp, a faithful port of stage-client.mjs _buildFromTA: loads STGxx_ta.json, re-projects world-authored meshes through the live wire camera (XMTRX=M1.M2), renders local props at the baked screen pos, textures from the seeded VRAM at each TCW. A/B vs engine ground truth (STG0B, GROUNDTRUTH_engine_ta_STG0B.png): on-screen stage verts engine 1893 vs GSTA 1881 (99.4%), screen-span Y both 455 (stage bottom edge exact), op=930 OP polys parsed. The pre-deck-fix floor-to-white intensity override was DISPROVEN (washed the dark grid to bright green, hid the blue floor) and removed in favour of the bake per-vertex RGB (re_kb finding:stage_deck_texture_closed). Body/HUD/effects/decode UNTOUCHED. commit ed11835b2.',
  status='confirmed', confidence='high', date='2026-06-15';

UPSERT finding:native_gsta_stage_open_gaps SET
  statement='OPEN gaps on the native GSTA stage (minor, flagged): (1) LOWER BLUE-FLOOR DECK STRIPES render darker than the engine — the deck bottom-row per-vertex RGB is ~0 so the texture modulates near-black, while the engine ground truth shows lit blue floor stripes. Likely the same deck lower-row shading detail noted in re_kb 26; needs a per-vertex-colour vs engine-TA recheck on mesh0 bottom rows. (2) ~12 MARGIN-culled prop tris (engine 1893 vs GSTA 1881 on-screen verts) = the re_kb finding:stage_prop_matrices/26 deferred un-placeable props. (3) STAGE_ID COVERAGE: only STG0B has an engine-TA bake (atlas/stages/STG0B_ta.json), so only stage_id->STG0B renders; other live stage_ids load nothing (logged, stage stays unrendered) until each stage is captured live (MAPLECAST_DUMP_RAM) + baked (tools/bake_stage_from_ta.py) + added to the stage_id map. NO WIRE GAP: stage_id + camera M1/M2 are already on the wire (gstate + cam_mat); the only missing data is the per-stage OFFLINE bake, not a runtime field.',
  status='open', confidence='high', date='2026-06-15';

RELATE finding:native_gsta_stage_zorder->cites->source:gsta_zorder_disasm;
RELATE finding:native_gsta_stage_zorder->cites->source:gsta_stage_impl;
RELATE finding:native_gsta_stage_zorder->about->finding:replica_live_stage_black_fix;
RELATE finding:native_gsta_stage_zorder->about->finding:stage_deck_texture_closed;
RELATE finding:native_gsta_stage_open_gaps->about->finding:native_gsta_stage_zorder;
RELATE finding:native_gsta_stage_open_gaps->about->finding:stage_prop_matrices_deferred;
