USE NS re DB kb;

-- ============================================================================
-- 2026-07-09 — the LIVE "dark band / incomplete HUD" on webgpu-test CLOSED:
-- the STG0B engine-TA stage bake contained the CAPTURED HUD (68/72 meshes),
-- prepended every frame, depth-rejecting the live HUD at its own z-planes.
-- ============================================================================

UPSERT source:census_stage_hud_twins SET kind='measurement',
  ref='webgpu-test.html render census v9 (src=stage|wire|body origin tags + z ranges), user session 2026-07-09; STG0B_ta.json mesh inventory',
  note='Census showed every src=stage opaque group z-IDENTICAL to a live-wire HUD group: stage surr3 n=348 z=[0.005169..0.01409] == wire TCW 0809be00 n=120 z=[..0.01408] (font/bars); stage surr4 n=36 == wire 08080000 n=12; stage singles == wire portraits 0809dexx-0809e9xx. STG0B_ta.json meshes 4..71 carried tcw 809be00/8080000/809dexx-809e9xx (the HUD sheets); mesh 4 vertex at screen (28.7,453.4) z=0.014085 = the hyper meter. Meshes 0-3 (tcw 809fc00/80a0000, 812 tris) are the true stage.';

UPSERT finding:stage_bake_hud_contamination SET
  statement='CONFIRMED + FIXED 2026-07-09. bake_stage_from_ta.py had no HUD exclusion: MVC2 draws the HUD in the SAME OP list as the stage, so the STG0B engine-TA bake shipped a FROZEN bake-time HUD (68/72 meshes, 434/1256 tris). The client stage-merge prepends the bake each stage-stripped frame -> the frozen HUD draws FIRST with zw=1 dm=Greater at exactly the live HUD z-planes (0.0052..0.0141) -> the live wire HUD strict-Greater FAILS against its own stale doppelganger = the "dark band"/incomplete-HUD symptom. Its depth writes (up to 0.0141) also sit above the character tiles (z~0.0092-0.0094) = cape/body interference. User workarounds explained: opSkip=800 skipped the prepended bake; blend srcAlpha masked the frozen-HUD pixels; opaque depthFunc=always bypassed the rejection. FIX: (a) STG0B_ta.json filtered to the true stage meshes (tcw 809fc00 deck/backdrop + 80a0000 BG plane; 72->4 meshes), deployed prod; (b) bake_stage_from_ta.py now drops HUD_TEX_WORDS {0x9be00, 0x80000, 0x9de00..0x9e900} at bake time. Related fixes same session: _bodyMerge renderPasses tr_count bookkeeping (Cable-vanish on wire-pass-honoring), duplicate dbg_singlePass id + singlePass default true (pass-merge) removed.',
  status='confirmed', confidence='high', date='2026-07-09';

RELATE finding:stage_bake_hud_contamination->cites->source:census_stage_hud_twins;
