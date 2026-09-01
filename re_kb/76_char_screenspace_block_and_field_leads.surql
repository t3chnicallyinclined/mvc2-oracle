USE NS re DB kb;

-- ============================================================================
-- 2026-07-18 — CHAR-STRUCT SCREENSPACE OUTPUT BLOCK (0xE0..0xF0) code-confirmed
-- from the render transform loc_8c03093c, + a clearly-labelled set of
-- change-frequency LEADS that are NOT yet code-confirmed (do not upstream).
-- Grew out of the TDW2 state-floor study (per-frame change-structure of the
-- char structs over 2104+1083 MCRR frames + 4 true full-RAM dumps).
-- ============================================================================

-- ---- SOURCES -------------------------------------------------------------
UPSERT source:td_field_verify SET kind='disasm+measurement',
  ref='_marv_re/build/bank03.asm loc_8c03093c (Render Main Sprite transform) + literal pool loc_8c030aa4..aae; cross-ref _bwlab/td_*.py over _bwlab/cap.gsta.mcrr (2104f) + _live_fx5.gsta.mcrr (1083f) + tools/render-replica-poc/_ram_f90..f93.bin (4 true 16MB dumps)',
  note='loc_8c03093c sets r14=char_base (mov r4,r14 at entry; r14 never reassigned). Its offset literal pool loc_8c030aa4..aae = {0x12c(read gate),0xe0,0xe4,0xe8,0xec,0xf0}. fmov-write mapping: 0xe0<-transformX(@r15), 0xe4<-transformY(@r15+4), 0xe8<-fmac(fr0=const, fr2=camptr+0x20 [camZ block 0x8C26A510+0x20], fr3=renderparam_table[char+0x24 byte *4]), 0xec<-const*xscale(char+0x50), 0xf0<-const2*yscale(char+0x54). All writes @(r0,r14)=char_base+offset. Cross-validated by re_kb finding:emitter_render_model (body walker reads per-node scale @node+0xEC/0xF0) and CHARQ 0.00px.';

UPSERT source:td_full_ram_churn SET kind='measurement',
  ref='_bwlab/td_fullram.py over tools/render-replica-poc/_ram_f90..f93.bin (4 consecutive true 16MB SH4 RAM dumps, 3 transitions); _bwlab/td_extract.py over the .gsta.mcrr dynamic read-set',
  note='Full-16MB churn: 99.8776% of RAM never changed over 3 transitions; per-frame raw churn 5624-14492 B (0.033-0.086%). Largest changing runs are DERIVABLE not state: 0x8CE60000 Texture_Decompress_Buffer (=fn(GFX,sprite_id)), render scratch. Effective churn inside the 300412 B shipped render read-set = 196 B/frame (footsies) .. 432 B/frame (action); true game-state regions (char_st 28-31 + objpool 46-277 + gstate 3.5 + battle 1.2 + rparam 2) dominate. CONFIRMS+extends finding:state_wire_entropy (120-200 B/frame).';

-- ---- CONFIRMED FINDING: the screenspace output block -----------------------
UPSERT finding:char_screenspace_block SET
  statement='CONFIRMED (disasm loc_8c03093c, bank03). The Render Main Sprite transform writes a FIVE-field screenspace output block into the char struct in one pass: +0xE0 screen_x, +0xE4 screen_y (both already in marvelous2/pl_mem.asm as x/y_pos_screenspace), PLUS three fields marvelous2 does NOT label: +0xE8 = screenspace depth/Z = fmac(const, camZ@[0x8C26A510+0x20], renderparam_table[char+0x24]); +0xEC = screenspace X-scale = const * x_sprite_scale(char+0x50); +0xF0 = screenspace Y-scale = const2 * y_sprite_scale(char+0x54). Offsets read from the routine\'s own literal pool loc_8c030aa4..aae ({0x12c,0xe0,0xe4,0xe8,0xec,0xf0}); every store is @(r0,r14) with r14=char_base. +0xEC/+0xF0 are the SAME per-node scale the body walker consumes in re_kb finding:emitter_render_model (scale@node+0xEC/F0), independently cross-validated at 0.00px by CHARQ. NOVEL vs marvelous2 for +0xE8/+0xEC/+0xF0 (pl_mem.asm labels only 0xE0/0xE4). Upstream-candidate.',
  status='confirmed', confidence='high', date='2026-07-18';

UPSERT field:z_pos_screenspace SET name='z_pos_screenspace', offset='0xe8', owner='char_struct', type='float', class='engine',
  note='CONFIRMED loc_8c03093c: screenspace depth/Z = fmac(const, camZ[0x8C26A510+0x20], renderparam_table[char+0x24]). NOVEL vs marvelous2/pl_mem.asm.';
RELATE struct:char_struct->has_field->field:z_pos_screenspace;
UPSERT address:cs_z_pos_screenspace SET addr='0xe8', kind='struct_offset', note='char_struct+0xe8 (z_pos_screenspace / screen depth). Writer loc_8c03093c.';
RELATE field:z_pos_screenspace->lives_at->address:cs_z_pos_screenspace;

UPSERT field:x_scale_screenspace SET name='x_scale_screenspace', offset='0xec', owner='char_struct', type='float', class='engine',
  note='CONFIRMED loc_8c03093c: const * x_sprite_scale(0x50). == body-walker per-node render scale node+0xEC (re_kb finding:emitter_render_model). NOVEL vs marvelous2.';
RELATE struct:char_struct->has_field->field:x_scale_screenspace;
UPSERT address:cs_x_scale_screenspace SET addr='0xec', kind='struct_offset', note='char_struct+0xec (screenspace x-scale). Writer loc_8c03093c.';
RELATE field:x_scale_screenspace->lives_at->address:cs_x_scale_screenspace;

UPSERT field:y_scale_screenspace SET name='y_scale_screenspace', offset='0xf0', owner='char_struct', type='float', class='engine',
  note='CONFIRMED loc_8c03093c: const2 * y_sprite_scale(0x54). == body-walker per-node render scale node+0xF0 (re_kb finding:emitter_render_model). NOVEL vs marvelous2.';
RELATE struct:char_struct->has_field->field:y_scale_screenspace;
UPSERT address:cs_y_scale_screenspace SET addr='0xf0', kind='struct_offset', note='char_struct+0xf0 (screenspace y-scale). Writer loc_8c03093c.';
RELATE field:y_scale_screenspace->lives_at->address:cs_y_scale_screenspace;

RELATE finding:char_screenspace_block->cites->source:td_field_verify;
RELATE finding:char_screenspace_block->about->field:z_pos_screenspace;
RELATE finding:char_screenspace_block->about->field:x_scale_screenspace;
RELATE finding:char_screenspace_block->about->field:y_scale_screenspace;

-- ---- INFERRED-ONLY: change-frequency LEADS, NOT code-confirmed -------------
-- These offsets change frequently in the char struct across live capture but I
-- have NOT found a store to char_base+offset with confirmed semantics. DO NOT
-- upstream. Recorded only so the leads are not re-derived from scratch.
UPSERT finding:char_field_changefreq_leads SET
  statement='INFERRED / UNCONFIRMED (change-frequency only, 2026-07-18). Char-struct byte-offsets that mutate often in live MCRR capture but whose write-site+semantics are NOT yet confirmed: +0x2D0/+0x2D4/+0x2D8 (53-67% of frames; velocity hypothesis FALSIFIED — the real velocity is the already-labelled x_velocity 0x5c / y_velocity 0x60; the only 0x2d0 literal-pool sites in bank01/bank05 dereference a DIFFERENT struct via a global ptr, not char_base, so char+0x2d0 is unproven); +0x23D/+0x23E (33-40%, near air_hitstun 0x239/airthrow 0x23a); +0x48C-0x48E (18-23%); +0x1E2 (18%, near undizzy 0x1e1); +0x32A (15%). Two derivable ARTIFACTS (not DOF): +0x0C toggles 0<->pointer by frame parity (ping-pong double-buffer ptr, change-every-frame but predictable); +0x502 cycles a small 0..35 periodic counter. Confirmed-already-known cross-checks that lit up as expected and validate the map: 0x142 anim_timer, 0x144 sprite_id, 0x154 current_cell_data (changes on the same frames as 0x144), 0x34/0x38 pos, 0xE0/0xE4 screen, 0x420 health, 0xDC render_accum, 0x298 x_opponent_distance. GATE TO PROMOTE any lead: find the mov.X store to char_base+offset (base register verified == player ptr) and read the surrounding math.',
  status='inferred', confidence='low', date='2026-07-18';
RELATE finding:char_field_changefreq_leads->cites->source:td_full_ram_churn;
