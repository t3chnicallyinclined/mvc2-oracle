USE NS re DB kb;

-- ============================================================================
-- 2026-07-10 — the GFX2 cell-record flags-u16 FLIP AXES were SWAPPED in our
-- model. Corrected from disasm (register-traced in BOTH body walkers) +
-- decisive 8-way orthogonal-authoring proof. Implemented in render_frame.
-- ============================================================================

UPSERT source:record_flag_axes_disasm SET kind='marvelous2',
  ref='bank03.asm loc_8c0344d4 (0x4000 test loc_8c0346fc @10477, 0x8000 test loc_8c034704 @10503; neg r5(Y) @10647 control 0x20, neg r4(X) @10639 control 0x10; r4->X r5->Y bound at loc_8c0347c8 fr12=(r10+r4)*scaleX@0xEC / fr13=(@0x14+r5)*scaleY@0xF0); loc_8c0348c8 scale walker confirms (0x4000 mirrors Y-ratio slot 0x30, 0x8000 mirrors X-ratio slot 0x2C); gen_walker.c neg r4 L675 / neg r5 L687',
  note='Two independent body walkers register-trace the same result. Decisive corroboration: Storm sel0x35d/0x35e author 0x8000, 0x4000, AND 0xC000 across the 8-way Lightning-Strike (PL2A_gfx2.bin); if both bits were horizontal 0xC000 would be a no-op — since 0x8000 composes with facing (the L/R axis facing already provides), 0x4000 MUST be the vertical (up/down) axis.';

UPSERT finding:record_flag_axes_corrected SET
  statement='CONFIRMED (disasm, 2 walkers) + IMPLEMENTED 2026-07-10. GFX2 cell-record flags-u16 (r11+0x4): bit 0x8000 = HORIZONTAL flip (X-position reflect + texU mirror; control 0x10, neg r4; composes with facing -> texU = facing XOR 0x8000). bit 0x4000 = VERTICAL flip (Y-position reflect + texV mirror; control 0x20, neg r5; NO facing XOR -> texV = 0x4000 alone). Orthogonal; 0xC000 = 180 point reflection. Pure DRAW-TIME (storage is verbatim, re_kb/24 & re_kb/71 col=cc UNTOUCHED). SWAPPED vs the prior model (rip_gfx2_assembly.py 13-14, finding:emitter_render_model 08:87, render_frame.c:204-206/608 all had 0x4000=X). This RESOLVES re_kb/24 emitter_flip_unvalidated (its 1.46% "pal-16" residual = the 0x4000 vertical parts XORd into U instead of V) and finding:emitter_flip_unvalidated. render_frame.c positions ALREADY encode both axes (gen_walker neg r4/r5); the bug was only the UV mirror: it applied texU keyed on 0x4000 (wrong) and no texV. FIX (implemented, NOT yet live-confirmed): submit_1244b0 reads both bits; q->mirror = facing ^ (flags&0x8000); q->mirror_v = (flags&0x4000); wasm_entry_frame swaps vTop<->vBot on mirror_v (analog of the texU u-swap); new render_frame_quad_mirror_v export. Deployed render_frame.wasm ?v=flipfix1. OFFLINE GATES GREEN (_zz_flip_axis_gate): texU mir==facing^0x8000 0-mismatch, texV mir_v==0x4000 0-mismatch, geometry byte-identical, carve 0-bad, anim-flag audit closed (32 parts gain H mirror, 14 get texV not texU). PENDING: live pixel A/B bodytex vs legacy (the definitive engine confirmation) — sel0x35d/rocket-projectile were not in the sampled capture frames. C++ twins (maplecast_mirror gstaDecodeBodies uses draw-mirror? verify) not yet touched. LOW BITS 0x10/0x20/0x40/0x80 = HITBOX selector (loc_8c0341b4 char+0x170), NON-render (product value = hitbox viewer, see GAME-DATA-COMPLETENESS-LEDGER).',
  status='confirmed', confidence='high', date='2026-07-10';

RELATE finding:record_flag_axes_corrected->cites->source:record_flag_axes_disasm;

-- close the open item this resolves
UPSERT finding:emitter_flip_unvalidated SET status='resolved', confidence='high', date='2026-07-10',
  statement='RESOLVED 2026-07-10 by finding:record_flag_axes_corrected: the 0x4000/0x8000 axes were SWAPPED (0x8000=H/texU, 0x4000=V/texV); facing composes with 0x8000. The prior unvalidated model had 0x4000=X. See re_kb/72.';
RELATE finding:emitter_flip_unvalidated->cites->source:record_flag_axes_disasm;
