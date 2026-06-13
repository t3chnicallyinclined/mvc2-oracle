-- ============================================================================
-- 06: sources (provenance) + key findings with status/confidence + cites edges
-- ============================================================================
USE NS re DB kb;

-- ---- sources ---------------------------------------------------------------
UPSERT source:marv_bank03 SET kind='marvelous2', ref='bank03.asm: loc_8c0344d4(10218), loc_8c033e90(9258), loc_8c0322c0(5069), loc_8c0322d4(5082), loc_8c034dee(11567), loc_8c034e8c, loc_8c0308c2(1200), loc_8c03093c(1281); work.asm:36-39', note='local _marv_re checkout (mountainmanjed canonical).';
UPSERT source:marv_bank12 SET kind='marvelous2', ref='bank12.asm: loc_8c1294c8 (cell dispatcher), loc_8c12951c (18-entry table), loc_8c129cc2, loc_8c1216c0 (transform), loc_8c1244b0/0x8C1248CC (sprite-para submit)', note='local _marv_re checkout.';
UPSERT source:marv_bank04 SET kind='marvelous2', ref='bank04.asm:11601-11756 loc_8c044dce pool init (consts 0x8c26aa54/0x1d0/0x1d000), loc_8c044f12 allocator, loc_8c04515e slot insert', note='object-pool shape.';
UPSERT source:pl_mem SET kind='memory', ref='_marv_re/memory/pl_mem.asm', note='AUTHORITATIVE per-character struct offsets (#symbol NAME 0xNNN).';
UPSERT source:work_asm SET kind='memory', ref='_marv_re/memory/work.asm', note='global RAM map + buffer addresses.';
UPSERT source:buildspl SET kind='memory', ref='_marv_re/char_prg/buildSPL.sh', note='AUTHORITATIVE char-id -> name -> S_PLxx file manifest (#NN Name).';
UPSERT source:anotak_pl00 SET kind='anotak', ref='https://zachd.com/mvc2/data/anotak/PL00_DAT_atk.html', note='Ryu animation groups -> cells -> sprite_ids (data only, no pixels).';
UPSERT source:anotak_anim SET kind='anotak', ref='https://zachd.com/mvc2/data/anotak/possible_anim.html', note='animation-field semantics (20-byte cell).';
UPSERT source:anotak_atk SET kind='anotak', ref='https://zachd.com/mvc2/data/anotak/possible.html', note='attack-field semantics.';
UPSERT source:recatalog_objpool SET kind='recatalog', ref='re-catalog/00-README.md', note='object-pool map + the screen-offset RESOLVED note.';
UPSERT source:recatalog_storm SET kind='recatalog', ref='re-catalog/PL2A-storm.md', note='Storm = fully-mapped reference character.';
UPSERT source:recatalog_sheet SET kind='recatalog', ref='re-catalog/spreadsheet-data.md', note='community-sheet cross-check (camera block, Match_Tracker, per-char scale).';
UPSERT source:oracle_render SET kind='oracle', ref='MAPLECAST_FRAME_ORACLE_HOOK; capture /dev/shm/mc_oracle_hook.jsonl; loc_8c03093c @P0 0x0C03093C', note='Frame Oracle: 150541 fires/22197-frame match -> loc_8c03093c is per-frame per-object; writes screen @+0xE0/E4.';
UPSERT source:oracle_decode SET kind='oracle', ref='MAPLECAST_FRAME_ORACLE_DECODE; capture PC 0x8C033EC0', note='Frame Oracle: loc_8c033e90 fires ONCE ~frame 2568 (load-time), packs effect sels 0-251 into 0x0CE60000.';
UPSERT source:oracle_charq SET kind='oracle', ref='MAPLECAST_ORACLE_PROBE (CHARQ, live reload, no rebuild); bank12 0x8C1248CC r14 corners, TCW @r12+0x0C, foot-anchor 0x8C034864 r15+0x30/34', note='CHARQ: per-part PVR sprite quad live; one sel -> many TCWs (moving working set).';
UPSERT source:oracle_bodycap SET kind='oracle', ref='MAPLECAST_BODYCAP @ 0x8C034864 (r15+0x30/0x34 foot anchor)', note='sel-keyed body-part pixel capture from live play.';
UPSERT source:doc_gfxnotes SET kind='doc', ref='docs/MARVELOUS2-GFX-NOTES.md', note='GFX/part decode notes (LZSS, GFX1/2 select, facing/flip).';
UPSERT source:rip_tool SET kind='doc', ref='tools/rip_gfx2_assembly.py read_cells()', note='static GFX2 enumeration: n=(first u32 of GFX2)>>2; cell index==sprite_id.';

-- ---- findings --------------------------------------------------------------
-- (part_decode_mechanism already seeded; re-assert with full cites below)
UPSERT finding:part_decode_mechanism SET
  statement='Body part pixels (sels 252-1532, ~1281, what the emitter needs) are ON-DEMAND-decoded per-pose into transient VRAM with a MOVING TCW (one sel -> many TCWs). There is NO bulk-resident store of all 1533 part pixels. The GFX1 load-burst (loc_8c033e90 @0x8C033EC0) covers ONLY the effect/UI sheet sels 0-251. Full pixel coverage therefore requires the poses to appear on screen (play-capture: BODYCAP @0x8C034864 sel-keyed, or CHARQ per-frame). Static GFX2 rip gives geometry/assembly only; offline one-shot LZSS dump is a dead end.',
  status='confirmed', confidence='high', date='2026-06-10';

UPSERT finding:screen_anchor SET
  statement='The authoritative per-object GPU placement is screen_x/y @ node+0xE0/+0xE4, written by loc_8c03093c from the world->screen transform. NOT +0xC8/+0xCC (which the head-list walker loc_8c0301f6 dereferences as a POINTER) and NOT +0x12C (a one-byte cull flag, not a sprite_id). readObjectsWalk/readAllDrawn (read +0xE0/E4) are correct; the legacy owner-anchored readObjects (+0xC8/+0x12C) is wrong and is the source of object drift.',
  status='resolved', confidence='high', date='2026-06-08';

UPSERT finding:state_injection_deadend SET
  statement='Per-frame GSTA injection into a live SH4 is fundamentally crash-prone. Writing logical fields (sprite_id/pos/health) while the engine-owned pointer cluster 0x154-0x184 is at a different frame makes the bank12 cell processor (loc_8c1294c8) read a corrupt current_cell_data, mis-index its 18-entry jump table, and jmp into non-code -> illegal instruction (expEvn=0x180; epc in 0x8C00xxxx non-code, pr in bank12). Capture timing / loadstate / ROM-presence were ruled out -- the injection itself is the trigger. Robust architecture = asset-driven renderer with the SH4 OFF.',
  status='confirmed', confidence='high', date='2026-06-06';

UPSERT finding:flip_bits SET
  statement='Per-part X-mirror = GFX2 cell-record FLAGS & 0x4000, Y-mirror = FLAGS & 0x8000 (8-byte record [dx s16][dy s16][FLAGS u16][sel u16]). The body emitter loc_8c0344d4 applies these per record; UV-corner flip in the bank12 submit derives from FLAGS.',
  status='confirmed', confidence='high', date='2026-06-09';

UPSERT finding:cumulative_pen_geometry SET
  statement='Body sub-pixel geometry = a CUMULATIVE running pen across the cell records: X accumulates +/-dx by facing, Y accumulates -=dy; final screen = node+0xE0/E4 + (pen+tile)*scale@node+0xEC/0xF0. Disasm-proven in loc_8c0344d4 and reconciled with the live Oracle (live cell+6 sel == static GFX2-BIN cell+6).',
  status='confirmed', confidence='high', date='2026-06-09';

UPSERT finding:sel_coverage SET
  statement='Full per-character sprite_id->parts GEOMETRY coverage is statically extractable from the DAT alone (no SPL needed): tools/rip_gfx2_assembly.py read_cells() reads n=(first u32 of GFX2)>>2 and walks every cell-table entry; cell index == sprite_id. ~1533 sels total; effect/UI = 0-251, body = 252-1532. The SPL is needed only to attach named-move/reachability semantics to a sprite_id.',
  status='confirmed', confidence='high', date='2026-06-10';

UPSERT finding:objpool_unified SET
  statement='Every character on screen is assembled from MULTIPLE pool objects (body + cape(s) + lightning/projectile/super), each with its own sprite_id + screen pos. Detached projectiles are the SAME pool (every spawner across bank0e/0f/10/11 calls the one allocator loc_8c044f12, category-distinguished). Render reads every active pool object -> draws its rip sprite at its position. The cape is never in the body assembly -- it is a separate object.',
  status='confirmed', confidence='high', date='2026-06-08';

UPSERT finding:objpool_screen_open SET
  statement='OPEN nuance on the object pool: re-catalog records a RESOLVED conclusion (screen = +0xE0/+0xE4 per the renderer loc_8c03093c) but flags that the legacy empirical scan was mis-anchored by +0x80 (owner word) and read +0xC8/+0x12C. The disasm authority (+0xE0/E4 screen, +0x12C cull, +0x144 sprite_id) supersedes the empirical map; confirm any new pool reader against loc_8c03093c before trusting offsets.',
  status='open', confidence='medium', date='2026-06-10';

UPSERT finding:oracle_hooks SET
  statement='The Frame Oracle is a READ-ONLY compile-time block-entry GenCall on the prod dynarec (rec_x64.cpp BlockCompiler::compile), determinism-safe, gated OFF (MAPLECAST_FRAME_ORACLE_HOOK). PC-alias: prod renders from P0 (0x0C03093C) vs marvelous2 P1 labels (0x8C03093C); mc_isHookedPC masks pc&0x1FFFFFFF. CHARQ (MAPLECAST_ORACLE_PROBE) reloads live with NO rebuild/restart and reads the per-part PVR sprite quad. These are the runtime confirm-not-guess tiebreakers.',
  status='confirmed', confidence='high', date='2026-06-09';

-- ---- about edges (finding -> entity) ---------------------------------------
RELATE finding:part_decode_mechanism->about->routine:loc_8c0344d4;
RELATE finding:part_decode_mechanism->about->routine:loc_8c033e90;
RELATE finding:part_decode_mechanism->about->routine:loc_8c0322c0;
RELATE finding:part_decode_mechanism->about->buffer:ce60000;
RELATE finding:part_decode_mechanism->about->buffer:dm00pool;

RELATE finding:screen_anchor->about->field:screen_x;
RELATE finding:screen_anchor->about->field:screen_y;
RELATE finding:screen_anchor->about->routine:loc_8c03093c;
RELATE finding:screen_anchor->about->struct:object_pool_node;

RELATE finding:state_injection_deadend->about->field:current_cell_data;
RELATE finding:state_injection_deadend->about->routine:loc_8c1294c8;
RELATE finding:state_injection_deadend->about->struct:char_struct;

RELATE finding:flip_bits->about->dataformat:gfx2_cell;
RELATE finding:flip_bits->about->routine:loc_8c0344d4;
RELATE finding:cumulative_pen_geometry->about->routine:loc_8c0344d4;
RELATE finding:cumulative_pen_geometry->about->dataformat:gfx2_cell;

RELATE finding:sel_coverage->about->field:sprite_id;
RELATE finding:sel_coverage->about->field:dat_gfx2;
RELATE finding:sel_coverage->about->dataformat:gfx2_cell;

RELATE finding:objpool_unified->about->struct:object_pool_node;
RELATE finding:objpool_unified->about->routine:loc_8c044dce;
RELATE finding:objpool_screen_open->about->struct:object_pool_node;
RELATE finding:objpool_screen_open->about->field:obj_screen_x;

RELATE finding:oracle_hooks->about->routine:loc_8c03093c;
RELATE finding:oracle_hooks->about->routine:loc_8c033e90;

-- ---- cites edges (finding -> source) ---------------------------------------
RELATE finding:part_decode_mechanism->cites->source:marv_bank03;
RELATE finding:part_decode_mechanism->cites->source:oracle_decode;
RELATE finding:part_decode_mechanism->cites->source:oracle_charq;
RELATE finding:part_decode_mechanism->cites->source:oracle_bodycap;
RELATE finding:part_decode_mechanism->cites->source:doc_gfxnotes;

RELATE finding:screen_anchor->cites->source:marv_bank03;
RELATE finding:screen_anchor->cites->source:recatalog_objpool;
RELATE finding:screen_anchor->cites->source:oracle_render;

RELATE finding:state_injection_deadend->cites->source:marv_bank12;
RELATE finding:state_injection_deadend->cites->source:pl_mem;

RELATE finding:flip_bits->cites->source:marv_bank03;
RELATE finding:flip_bits->cites->source:anotak_anim;
RELATE finding:cumulative_pen_geometry->cites->source:marv_bank03;
RELATE finding:cumulative_pen_geometry->cites->source:oracle_charq;

RELATE finding:sel_coverage->cites->source:rip_tool;
RELATE finding:sel_coverage->cites->source:marv_bank03;

RELATE finding:objpool_unified->cites->source:recatalog_objpool;
RELATE finding:objpool_unified->cites->source:marv_bank04;
RELATE finding:objpool_screen_open->cites->source:recatalog_objpool;
RELATE finding:objpool_screen_open->cites->source:marv_bank03;

RELATE finding:oracle_hooks->cites->source:oracle_render;
RELATE finding:oracle_hooks->cites->source:oracle_charq;

-- ---- lives_at edges (field -> address record for key fields) ---------------
-- (compact: create address records + link for the render-critical fields)
UPSERT address:sprite_id_addr SET addr='char_base+0x144', kind='struct_offset', note='sprite_id absolute = slot.base + 0x144.';
RELATE field:sprite_id->lives_at->address:sprite_id_addr;
UPSERT address:screen_x_addr SET addr='char_base+0x0E0', kind='struct_offset', note='screen_x absolute = slot.base + 0x0E0.';
RELATE field:screen_x->lives_at->address:screen_x_addr;


-- ---- emitter geometry close-out (2026-06-11, full tile span) ----------------
UPSERT finding:emitter_geom_validated SET date='2026-06-11', confidence='high', status='confirmed', note='Geometry closed NUMERICALLY: the full-span baker makes the DEPLOYED atlas match the live engine to 0.00px relative on every sel (multi+single). Supersedes the 2026-06-10 logical-crop.', statement='EMITTER GEOMETRY NUMERICALLY CLOSED — FULL TILE SPAN (2026-06-11). The 8-byte GFX1 part header is [lw][lh][sw][sh] (logical vs STORAGE tile dims). DISASM-CITED RULE (bank03 loc_8c0344d4 -> tile loop loc_8c0345c4/loc_8c03478e): the part SCREEN FOOTPRINT is the FULL STORAGE tile span sw*8 x sh*8 (header +2/+3); the cumulative running pen anchors the FULL-SPAN top-left (X-acc +/-dx by facing, Y-acc -=dy; loc_8c034548 neg r10 on facing; final = node+0xE0/E4 + (pen+tile)*scale@node+0xEC/F0). PIXEL ORIGIN: decoded texels occupy the BOTTOM-LEFT lw*8 x lh*8 window + transparent pad to full span (parts bottom-up). PROOF (tools/validate_emitter_geom.py vs _ryu_capture/probe_body_uv.json, Ryu sid 68 facing=1, 6 sels, loading the BAKED PL00_parts.json dims, NO override): dW=dH=0.00 ALL sels incl multi-tile 265/278/279; dX=+0.70 dY=+0.40 uniform = pure anchor quantization => RELATIVE residual 0.00px. BAKER (tools/extract_gfx1_atlas.py decode_part): removed the logical-crop shrink; keep full-span W=sw*8/H=sh*8 verbatim. RECONCILES the 2026-06-10 limb-crop fix (right about pixels=bottom-left, wrong to shrink the rect). REGRESSION-CLEAN: 930 single-tile dims unchanged, 603 multi-tile grew to full span. CLIENT buildEmitterDrawList reads part.w/h from the atlas (no override) => NO ?v= bump. DEPLOYED scp to 149.28.44.118:/var/www/maplecast/test-atlas/chars (backup-20260611-011829), 5 md5 verified. ROSTER: re-bake all chars with the full-span baker. COVERAGE: only facing=1/standing/flip=flipy=0; X-mirror 0x4000, Y-mirror 0x8000, opposite-facing reflect remain for the live DIFF.';
RELATE finding:emitter_geom_validated->cites->source:marv_bank03;
