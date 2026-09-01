-- Finding: the off-SH4 render_frame (transpiled emitter) screen-X quad span direction
-- must follow the OWNING BODY FACING (node+0x110), not be hardcoded rightward.
-- Pinned 2026-06-14 via _uv_tcw_diff.mjs (engine _probe2.log vs client render_frame on _uvval.mcrr vf45597).

USE NS re DB kb;

UPSERT source:probe_uvval_45597 SET
  kind = 'oracle_capture',
  detail = 'MAPLECAST_ORACLE_PROBE paired @0x0C034864(part)+0x0C1248CC(submit); _probe2.log + wire _uvval.mcrr vf45597; Storm(cid42 node 0x8c282354) + Cable(cid23 node 0x8c2688e4)';

UPSERT finding:satellite_quad_xspan_facing SET
  status = 'confirmed',
  confidence = 'high',
  summary = 'The transpiled body emitter (render_frame.c render_object_full_ex) lays each per-part screen quad RIGHTWARD from the captured submit anchor bx (treating bx as bottom-LEFT). That is only correct when the owning body faces RIGHT (node+0x110==0). The engine bank12 cell-processor builds the quad AWAY from the anchor in the FACING direction: bx is the LEFT edge when facing==0 and the RIGHT edge when facing==1. Result: every facing==1 body part was shifted by +one tile width (~+26.7px for a half-tile / +13.3 for a quarter-tile) in X. Cable (facing=0) was correct; Storm (facing=1) was uniformly +26.7px in X.',
  evidence = 'Storm part0 (facing=1): engine submit corners A(114.0,433.0)TL B(140.67,433.0)TR C(140.67,467.29)BR D(114.0,467.29)BL; foot anchor r15+0x30 = (140.67,467.29) == engine RIGHT edge (C/D.x). Client pre-fix A.x=140.7 (=bx, treated as left). Cable part0 (facing=0): foot anchor 511.67 == engine A.x LEFT edge; client A.x=511.7 matched. Net engine quad direction = facing-driven, in lockstep with the texU mirror (re_kb routine:loc_8c0346c4) and the position pen.',
  fix = 'render_frame.c render_object_full_ex per-tile corner build (~line 237): xl = node_facing ? (bx - W) : bx ; xr = xl + W ; A/D.x=xl, B/C.x=xr. Y unchanged (by-H..by). Validated: _uv_tcw_diff.mjs Storm cid42 all parts GEOM->OK (corners byte-exact vs engine), Cable cid23 no regression.',
  residual = 'Remaining non-OK in differ are unrelated: (1) Cable rows 21-26 = engineParts=28 vs clientQuads=27 pair-join off-by-one after a 0xFF terminator record; (2) Storm rows 62-63 = a one-row Y delta (17.1px) on two sub-tile parts (Y-pen/row ordering, NOT X-anchor); (3) <<TCW>> on the high sels (3205-3230) = a 0x00E00000 texture-bank resolution diff for effect/aura sels, orthogonal to geometry.';

UPSERT routine:loc_8c1244b0_quad_xspan SET
  bank = 12,
  pc = '0x8c1244b0',
  note = 'cell-processor finalize: per-part screen quad corner build from the foot anchor (r15+0x2C+0x04). The X span direction is set by the body facing (node+0x110) — anchor is the leading edge AWAY from which the W-wide quad extends. CONFIRMED by submit corner capture @0x0C1248CC.';

RELATE finding:satellite_quad_xspan_facing -> cites -> source:probe_uvval_45597;
RELATE finding:satellite_quad_xspan_facing -> about -> routine:loc_8c1244b0_quad_xspan;
