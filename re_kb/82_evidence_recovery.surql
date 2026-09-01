-- ==========================================================================
-- 82: evidence recovery -- cite the PCs these findings already named
--
-- The health audit listed 58 `confirmed` findings that could not show
-- reproduction- or code-grade evidence. For many of them the evidence was
-- never missing -- it was sitting in the finding's own statement as a
-- marvelous2 PC, and nobody ever recorded the `cites` edge. A routine id IS
-- its PC, so that edge is code-grade and satisfies the promotion rule in 77.
--
-- This file is RECOVERY, not promotion. Every PC below was verified to be
-- DEFINED in ../_marv_re/build/*.asm (anchored label match) before its row
-- was written. PCs a finding names that are NOT in the disassembly are
-- listed at the bottom as comments and were deliberately NOT created --
-- inventing them is exactly the failure 79 and 81 had to repair.
--
-- Findings still lacking any qualifying evidence after this file are
-- handled in 83_status_triage.surql, which needs human judgment.
--
-- Idempotent. Apply: tools/re_kb/rekb.sh @tools/re_kb/82_evidence_recovery.surql
-- ==========================================================================
USE NS re DB kb;

-- ---- routine rows the graph was missing ----------------------------------
UPSERT routine:loc_8c027d2c SET label='loc_8c027d2c', pc='0x8C027D2C', bank='bank02',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank02.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
UPSERT routine:loc_8c0337bc SET label='loc_8c0337bc', pc='0x8C0337BC', bank='bank03',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank03.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
UPSERT routine:loc_8c033ba8 SET label='loc_8c033ba8', pc='0x8C033BA8', bank='bank03',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank03.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
UPSERT routine:loc_8c034606 SET label='loc_8c034606', pc='0x8C034606', bank='bank03',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank03.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
UPSERT routine:loc_8c03460c SET label='loc_8c03460c', pc='0x8C03460C', bank='bank03',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank03.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
UPSERT routine:loc_8c03460e SET label='loc_8c03460e', pc='0x8C03460E', bank='bank03',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank03.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
UPSERT routine:loc_8c03478e SET label='loc_8c03478e', pc='0x8C03478E', bank='bank03',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank03.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
UPSERT routine:loc_8c0347bc SET label='loc_8c0347bc', pc='0x8C0347BC', bank='bank03',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank03.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
UPSERT routine:loc_8c034864 SET label='loc_8c034864', pc='0x8C034864', bank='bank03',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank03.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
UPSERT routine:loc_8c035000 SET label='loc_8c035000', pc='0x8C035000', bank='bank03',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank03.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
UPSERT routine:loc_8c035162 SET label='loc_8c035162', pc='0x8C035162', bank='bank03',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank03.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
UPSERT routine:loc_8c100968 SET label='loc_8c100968', pc='0x8C100968', bank='bank10',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank10.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
UPSERT routine:loc_8c1235b0 SET label='loc_8c1235b0', pc='0x8C1235B0', bank='bank12',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank12.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
UPSERT routine:loc_8c1235e0 SET label='loc_8c1235e0', pc='0x8C1235E0', bank='bank12',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank12.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
UPSERT routine:loc_8c1246da SET label='loc_8c1246da', pc='0x8C1246DA', bank='bank12',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank12.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
UPSERT routine:loc_8c1248ea SET label='loc_8c1248ea', pc='0x8C1248EA', bank='bank12',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank12.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
UPSERT routine:loc_8c124a82 SET label='loc_8c124a82', pc='0x8C124A82', bank='bank12',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank12.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
UPSERT routine:loc_8c129728 SET label='loc_8c129728', pc='0x8C129728', bank='bank12',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank12.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';
UPSERT routine:loc_8c15ffb0 SET label='loc_8c15ffb0', pc='0x8C15FFB0', bank='bank15',
  note='Row created 2026-09-01 by evidence recovery: findings cited this PC in prose without a cites edge, and no routine row existed. Label verified DEFINED in ../_marv_re/build/bank15.asm. No summary/role yet -- read the disassembly before relying on this beyond the citation.';

-- ---- the cites themselves ------------------------------------------------
RELATE finding:effect_poly_structure->cites->routine:loc_8c027d2c;
RELATE finding:effect_poly_structure->cites->routine:loc_8c129cc0;
RELATE finding:emitter_audit_2026_06_10->cites->routine:loc_8c035162;
RELATE finding:flip4000_double_apply_carve->cites->routine:loc_8c0346c4;
RELATE finding:gsta_draw_layer_per_slot->cites->routine:loc_8c0308c2;
RELATE finding:gsta_hud_bar_magenta_correct->cites->routine:loc_8c15ffb0;
RELATE finding:gsta_wire_ext_completeness_2026_06_11->cites->routine:loc_8c0308c2;
RELATE finding:gsta_wire_ext_completeness_2026_06_11->cites->routine:loc_8c0344d4;
RELATE finding:gsta_wire_ext_completeness_2026_06_11->cites->routine:loc_8c034606;
RELATE finding:gsta_wire_ext_completeness_2026_06_11->cites->routine:loc_8c0347bc;
RELATE finding:gsta_wire_ext_completeness_2026_06_11->cites->routine:loc_8c0348c8;
RELATE finding:gsta_wire_ext_completeness_2026_06_11->cites->routine:loc_8c034bea;
RELATE finding:gsta_wire_ext_completeness_2026_06_11->cites->routine:loc_8c034dee;
RELATE finding:gsta_wire_ext_completeness_2026_06_11->cites->routine:loc_8c035000;
RELATE finding:hitspark_class_resolved->cites->routine:loc_8c100968;
RELATE finding:hud_portraits_real_vs_procedural->cites->routine:loc_8c161fec;
RELATE finding:overlays_are_reconstructable_zero_bw->cites->routine:loc_8c15ffb0;
RELATE finding:render_replica_sh4_little_endian->cites->routine:loc_8c03093c;
RELATE finding:render_replica_ta_emit->cites->routine:loc_8c0344d4;
RELATE finding:render_replica_ta_emit->cites->routine:loc_8c1216c0;
RELATE finding:render_replica_ta_emit->cites->routine:loc_8c1246da;
RELATE finding:render_replica_ta_emit->cites->routine:loc_8c1248ea;
RELATE finding:sprite_id_bit15_dispatch->cites->routine:loc_8c0344d4;
RELATE finding:sprite_id_bit15_dispatch->cites->routine:loc_8c0348c8;
RELATE finding:sprite_id_bit15_dispatch->cites->routine:loc_8c034bea;
RELATE finding:sprite_id_bit15_dispatch->cites->routine:loc_8c0d97ee;
RELATE finding:storm_shipped_descriptor_tear->cites->routine:loc_8c0337bc;
RELATE finding:storm_tilecount_count_is_scale_invariant->cites->routine:loc_8c033b0a;
RELATE finding:storm_tilecount_count_is_scale_invariant->cites->routine:loc_8c0344d4;
RELATE finding:storm_tilecount_count_is_scale_invariant->cites->routine:loc_8c03460c;
RELATE finding:storm_tilecount_count_is_scale_invariant->cites->routine:loc_8c03460e;
RELATE finding:submit_rectab_alloc_index->cites->routine:loc_8c034864;
RELATE finding:submit_tcw_resident->cites->routine:loc_8c124a82;
RELATE finding:tile_descriptor_oracle_recipe->cites->routine:loc_8c034548;
RELATE finding:tile_facing_effect->cites->routine:loc_8c0344d4;
RELATE finding:tile_facing_effect->cites->routine:loc_8c034548;
RELATE finding:tile_facing_effect->cites->routine:loc_8c0346c4;
RELATE finding:tile_facing_effect->cites->routine:loc_8c0347bc;
RELATE finding:tile_grid_is_per_pose_static->cites->routine:loc_8c03478e;
RELATE finding:tile_grid_is_per_pose_static->cites->routine:loc_8c129728;
RELATE finding:tr_effect_capture_fix_spec->cites->routine:loc_8c030452;
RELATE finding:tr_effect_capture_fix_spec->cites->routine:loc_8c1235b0;
RELATE finding:tr_effect_capture_fix_spec->cites->routine:loc_8c1235e0;
RELATE finding:tr_effect_capture_fix_spec->cites->routine:loc_8c129cc0;
RELATE finding:wide_part_colpair_order->cites->routine:loc_8c033ba8;

-- ---- named but NOT in the disassembly -- NOT created ----------------------
--   finding:submit_rectab_alloc_index                    names loc_8c034744
