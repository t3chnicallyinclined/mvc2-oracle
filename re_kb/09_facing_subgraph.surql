-- ============================================================================
-- 09: The FACING subgraph + the SET-site-not-USE-site principle
-- Make the facing flow one connected subgraph:
--   SETTER (bank0d loc_8c0d97ee) --writes--> field:facing
--      field:facing --reads--> render-gate (loc_8c03453a/loc_8c034548 neg r10,
--                               loc_8c0346c4 neg r8) + emitter (loc_8c0344d4)
--      field:pos_x  --feeds--> the setter (fcmp/gt of opponent vs self pos_x)
-- Plus the PRINCIPLE finding: a field's MEANING comes from the SET-site.
-- Sources: marvelous2 build/bank0d.asm:23258-23280 (setter), build/bank03.asm:
--   10271-10314 (render gate), build/bank08.asm:30550-30590 (spawn cross-check).
-- ALL nodes idempotent (UPSERT). Edges via RELATE -> run 07_dedup_edges after.
-- ============================================================================
USE NS re DB kb;

-- ---- the FACING SETTER (the SET-site -- where MEANING is decided) -----------
UPSERT routine:loc_8c0d97ee SET label='Facing_Update', pc='0x8C0D97EE', bank='bank0d',
  role='FACING SETTER -- set facing toward opponent (the SET-site)',
  contribution_candidate=true,
  note='THE SET-SITE for facing@+0x110 (no pre-existing loc_ label in marvelous2 -- found by reading the instructions, a contribution candidate). bank0d ~:23266-23272: r0=0x34; fmov @(r0,r13),fr3 (opponent.pos_x); fmov @(r0,r14),fr2 (self.pos_x); fcmp/gt fr2,fr3 (self<opp i.e. opponent to the RIGHT); bf.s skips else r4=0x01; at loc_8C0D9820 writes r4 -> @(0x110,r14) (facing on self). => facing@+0x110 = (opponent.pos_x@+0x34 > self.pos_x@+0x34) ? 1 : 0. SEMANTIC (decided HERE, not at any USE-site): facing=1 <=> opponent to the RIGHT <=> character FACES RIGHT (P1 default, left side); facing=0 <=> FACES LEFT (P2 default). Set per-frame. This is the source of the byte->direction mapping that the 2026-06-11 facing bug got wrong by only reading the render USE-site.';

-- ---- the render-gate USE-site (label the previously-unlabeled nodes) --------
UPSERT routine:loc_8c03453a SET label='Render_Facing_Gate', pc='0x8C03453A', bank='bank03',
  role='render-gate facing test (USE-site: tst facing; bf neg)',
  contribution_candidate=true,
  note='USE-site of facing@+0x110 in the body render math. bank03:10271-10278: mov.l @(facing_off,PC),r0; mov.l @(r0,r14),r1; tst r1,r1; bf loc_8c034548. facing!=0 -> take the negate branch for BOTH the position pen and the texture-U. The gate READS the byte; it does NOT define its meaning (that is the SET-site loc_8c0d97ee). One byte drives both transforms in lockstep.';
UPSERT routine:loc_8c034548 SET label='Render_Pen_Reflect', pc='0x8C034548', bank='bank03',
  role='POSITION pen reflect on facing (neg r10)',
  contribution_candidate=true,
  note='bank03:10280-10283 (also second neg r10 @10306): when facing!=0, neg r10,r10 negates the pen X ORIGIN (the position reflection). Width enters via the tile span identically in both branches (NO +/-w on reflection) -> opposite facing mirrors the pen across the foot axis A, part extends RIGHT (client: tlx = 2*A - pen). Gated by loc_8c03453a on facing@+0x110.';
UPSERT routine:loc_8c0346c4 SET label='Render_TexU_Mirror', pc='0x8C0346C4', bank='bank03',
  role='TEXTURE-U mirror on facing (neg r8)',
  contribution_candidate=true,
  note='bank03:10313 neg r8,r0 then mov.w r0,@(0x14,r15): when facing!=0 (XORed with per-part 0x4000 X-mirror flag) the texture U is mirrored. Same facing@+0x110 byte as the position reflect (loc_8c034548) -> position and texture can NEVER decouple. The render USE-site for the texture half of the one-byte facing.';

-- ---- the projectile-spawn cross-check (bank08) -----------------------------
UPSERT routine:loc_8c08ca48 SET label='Projectile_Spawn_Facing', pc='0x8C08CA48', bank='bank08',
  role='projectile spawn facing cross-check (xflip@+0x1D2 -> +/-X)',
  contribution_candidate=true,
  note='bank08 ~:30550-30590: r0=0x1D2; mov.b @(r0,r5),r3; tst r3,r3; bf/s -> when xflip@+0x1D2 (per-frame copy of facing) is NONZERO, branch does fadd (owner.x + offset = spawn to the RIGHT, faces right); the zero/else branch loc_8C08CA74 does fsub (-X). Independent confirmation that facing/xflip=1 <=> +X <=> faces right, consistent with the bank0d setter semantics.';

-- ---- field semantics refined from the SET-site -----------------------------
UPSERT field:facing SET offset='+0x110', owner='char_struct', type='u8', class='logical',
  note='Facing direction byte. SEMANTIC (from the SET-site loc_8c0d97ee, NOT a USE-site): facing=1 <=> opponent to the RIGHT <=> character FACES RIGHT (P1 default, left side); facing=0 <=> FACES LEFT (P2 default). Written PER-FRAME by loc_8c0d97ee from a fcmp/gt of opponent.pos_x vs self.pos_x. Read by the render gate (loc_8c03453a -> neg r10 position reflect loc_8c034548 + neg r8 texture-U mirror loc_8c0346c4) and by the body emitter (loc_8c0344d4) -- one byte drives position AND texture in lockstep. Per-frame copies: xflip @+0x1D2 (projectile spawn cross-check loc_8c08ca48), +0x130/+0x134.';
UPSERT field:pos_x SET offset='+0x034', owner='char_struct', type='f32', class='logical',
  note='World X position (f32). FEEDS the facing setter: loc_8c0d97ee compares opponent.pos_x@+0x34 vs self.pos_x@+0x34 (fcmp/gt) to derive facing@+0x110. Also the world coordinate the render transform (loc_8c03093c) projects to screen_x@+0xE0.';

-- ---- the PRINCIPLE finding -------------------------------------------------
UPSERT finding:field_semantics_from_setter SET
  statement='PRINCIPLE: a field`s MEANING (byte->direction, polarity, units, valid range) is determined by where the ROM SETS (WRITES) it, not where it is used. READ THE SET-SITE. Worked example: the facing byte@+0x110 -> direction mapping came from the SETTER loc_8c0d97ee (bank0d, fcmp/gt opponent.pos_x vs self.pos_x => facing=1 means opponent-right => FACES RIGHT), NOT from the render USE-site loc_8c0344d4/loc_8c03453a. The 2026-06-11 facing bug burned ~8 eyeball-A/B iterations because only the render USE-site (the neg r10 / neg r8 gate) was read -- the USE-site shows the MATH (negate on a nonzero byte) but is SILENT on what the byte MEANS; only the SET-site defines the byte->direction. Corollary: if a value is deterministic in the ROM, reading the SET-site IS the answer; toggling/eyeballing is not. The deterministic-source order is (a) disasm SET-site = semantics, (b) disasm USE-site = math/gate, (c) Oracle live probe = confirm, (d) flycast`s own source.',
  status='confirmed', confidence='high', date='2026-06-11', contribution_candidate=false;

-- ---- sources ---------------------------------------------------------------
UPSERT source:marv_bank0d SET kind='marvelous2',
  ref='marvelous2 build/bank0d.asm:23258-23280 (facing setter, loc_8c0d97ee compute -> loc_8C0D9820 write @(0x110,r14))',
  note='The facing SET-site: fcmp/gt of opponent.pos_x@+0x34 (r13) vs self.pos_x@+0x34 (r14) -> facing=1 if opponent to the right, written to self+0x110. No pre-existing loc_ label here (mid-block) -- found by reading instructions.';
UPSERT source:marv_bank08 SET kind='marvelous2',
  ref='marvelous2 build/bank08.asm:30550-30590 (projectile spawn facing cross-check, xflip@+0x1D2 -> fadd/fsub +/-X)',
  note='Independent confirmation of facing polarity: xflip@+0x1D2 nonzero -> spawn at owner.x + offset (+X, faces right).';

-- ============================================================================
-- EDGES (RELATE; run 07_dedup_edges.surql after to collapse dupes)
-- ============================================================================

-- SETTER writes the field; field is fed by pos_x; readers of the field
RELATE routine:loc_8c0d97ee->writes->field:facing;
RELATE routine:loc_8c0d97ee->reads->field:pos_x;
RELATE routine:loc_8c0d97ee->reads->field:facing;            -- reads self+opp pos_x; writes facing (own readback in cmp/eq)
RELATE routine:loc_8c03453a->reads->field:facing;            -- render gate tests the byte
RELATE routine:loc_8c034548->reads->field:facing;            -- position reflect gated on facing
RELATE routine:loc_8c0346c4->reads->field:facing;            -- texture-U mirror gated on facing
RELATE routine:loc_8c08ca48->reads->field:facing;            -- spawn cross-check reads xflip copy

-- call chain: the gate dispatches into the two neg branches (same routine body)
RELATE routine:loc_8c03453a->calls->routine:loc_8c034548;
RELATE routine:loc_8c03453a->calls->routine:loc_8c0346c4;

-- the PRINCIPLE finding is ABOUT the setter, the field, and the render USE-sites
RELATE finding:field_semantics_from_setter->about->routine:loc_8c0d97ee;
RELATE finding:field_semantics_from_setter->about->field:facing;
RELATE finding:field_semantics_from_setter->about->routine:loc_8c03453a;
RELATE finding:field_semantics_from_setter->about->routine:loc_8c0344d4;
RELATE finding:field_semantics_from_setter->cites->source:marv_bank0d;
RELATE finding:field_semantics_from_setter->cites->source:marv_bank03;

-- wire the SETTER + sources into the existing emitter_facing_rule finding
RELATE finding:emitter_facing_rule->about->routine:loc_8c0d97ee;
RELATE finding:emitter_facing_rule->about->routine:loc_8c03453a;
RELATE finding:emitter_facing_rule->about->routine:loc_8c08ca48;
RELATE finding:emitter_facing_rule->about->field:pos_x;
RELATE finding:emitter_facing_rule->cites->source:marv_bank0d;
RELATE finding:emitter_facing_rule->cites->source:marv_bank08;

-- wire the SETTER + field into the emitter_render_model finding (one subgraph)
RELATE finding:emitter_render_model->about->routine:loc_8c0d97ee;
RELATE finding:emitter_render_model->about->routine:loc_8c03453a;
RELATE finding:emitter_render_model->about->field:facing;
RELATE finding:emitter_render_model->cites->source:marv_bank0d;

-- the principle finding cites the prior facing finding it generalizes
RELATE finding:field_semantics_from_setter->about->finding:emitter_facing_rule;

-- ---- contribution-candidate tags on the emitter findings -------------------
UPSERT finding:emitter_facing_rule SET contribution_candidate=true;
UPSERT finding:emitter_render_model SET contribution_candidate=true;
