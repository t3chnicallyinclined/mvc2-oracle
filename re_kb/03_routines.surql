-- ============================================================================
-- 03: Render-routine chain + anim/cell routines + edges
-- Sources: marvelous2 build/bank03.asm + bank12.asm, Frame Oracle captures.
-- ============================================================================
USE NS re DB kb;

-- ---- the render data path --------------------------------------------------
UPSERT routine:loc_8c0308c2 SET label='loc_8c0308c2', pc='0x8C0308C2', bank='bank03', role='Render_sprites (slot-table walker)',
  note='Loops the on-screen slot table 0x8C2895E0 (count array) / 0x8C287DE0 (ptr array), row stride 0x180. Per node loads ptr->r4, reads category byte @node+0x3 (layer gate), bsr loc_8c03093c (Render Main Sprite). Top of the per-frame render walk.';
UPSERT routine:loc_8c03093c SET label='loc_8c03093c', pc='0x8C03093C', bank='bank03', role='Render Main Sprite (PER-FRAME, per-object)',
  note='ORACLE-CONFIRMED per-object per-frame render (150541 fires / 22197-frame match). r4/r14=node. Reads cull byte @node+0x12C (skip if !=0), world pos @0x34/0x38/0x3C + scale @0x50/0x54, runs world->screen transform (bank12 loc_8c1216c0), and WRITES screen_x@+0xE0 / screen_y@+0xE4 (the authoritative GPU anchor / Oracle OBJ_BEGIN). reads facing @+0x110. Sets up the record; does not emit quads itself. NOTE: prod renders from P0 region 0x0C03093C (same low 28 bits).';
UPSERT routine:loc_8c0344d4 SET label='loc_8c0344d4', pc='0x8C0344D4', bank='bank03', role='per-frame BODY geometry/screen-quad emitter',
  note='THE live per-frame body placement. Reads Dat_GFX2@node+0x160; cell=GFX2+*(u32)(GFX2+(sid&0x7FFF)*4); first u16=record count; then count x 8-byte records [dx s16][dy s16][FLAGS u16 X-mirror 0x4000 / Y-mirror 0x8000][sel u16] with a CUMULATIVE running pen (X acc +/-dx by facing, Y acc -=dy). final screen = node+0xE0/E4 + (pen+tile)*scale@node+0xEC/F0. sel=read_u16(r11+6). Calls NO decoder (consumes pre-decoded VRAM). Body sels 252-1532. Use THIS (not loc_8c033e90) for live per-frame placement.';
UPSERT routine:loc_8c1216c0 SET label='loc_8c1216c0', pc='0x8C1216C0', bank='bank12', role='world->screen transform',
  note='The world->screen coordinate transform invoked by loc_8c03093c; its output is written to node+0xE0/+0xE4.';
UPSERT routine:loc_8c1294c8 SET label='loc_8c1294c8', pc='0x8C1294C8', bank='bank12', role='cell-processor dispatcher (CRASH SITE)',
  note='Duff-device block copy that jumps through the 18-entry table at loc_8c12951c using a count derived from cell data. THE canonical SH4-exception-when-blocked crash site: if current_cell_data@0x154 is stale/corrupt the count goes out of 0..18 range, table[count] is a non-pointer, jmp @r3 lands in non-code -> illegal instruction.';
UPSERT routine:loc_8c129cc2 SET label='loc_8c129cc2', pc='0x8C129CC2', bank='bank12', role='per-record quad/vertex loop',
  note='Skips an 0x18 header, record stride 0x20. The bsr at ~0x8C12A002 is a common return address (pr) seen in faults from this path.';
UPSERT routine:loc_8c034dee SET label='loc_8c034dee', pc='0x8C034DEE', bank='bank03', role='anim tick',
  note='Advances current_cell_data@+0x154 by 0x14 (20) bytes per keyframe and copies 20 bytes to player+0x140. Confirms the 20-byte cell: Duration@kf+2->0x142, sprite_id@kf+4->0x144, RenderExtra@kf+0x11->player+0x151, HitboxGroup@kf+0x12->0x152, EffectTrigger=bit0x80 of kf+0.';
UPSERT routine:loc_8c034e8c SET label='loc_8c034e8c', pc='0x8C034E8C', bank='bank03', role='load animation',
  note='R4=player base, R5=group id, R6=anim id -> computes current_cell_data from animations@+0x168. Called by the per-character SPL programs (S_PLxx) with a group-id immediate to switch moves.';
UPSERT routine:loc_8c03552a SET label='loc_8c03552a', pc='0x8C03552A', bank='bank03', role='LZSS part decoder',
  note='LZSS decompressor; GFX decode staging buffer = 0x0CE60000 (Texture_Decompress_Buffer).';
UPSERT routine:loc_8c0322c0 SET label='loc_8c0322c0', pc='0x8C0322C0', bank='bank03', role='DM00 on-demand decoder',
  note='sel -> entry (=dir@*(0x0CE80008) + sel*0x10, +8=compressed src) -> LZSS decode on demand into transient VRAM. The body parts (sels 252-1532) get their pixels from here, NOT from the load burst. Companion compactor loc_8c0322d4 (bank03:5082) shifts the +8 source ptrs reclaiming space (~25-entry shared compacting set; live count @*(0x0CE80004)). MOVING TCW: one sel -> many VRAM addrs across frames.';
UPSERT routine:loc_8c0322d4 SET label='loc_8c0322d4', pc='0x8C0322D4', bank='bank03', role='DM00 compactor',
  note='Shifts the DM00 +8 source pointers as it reclaims space; why a logical part lands at different VRAM addresses (moving TCW) across frames.';
UPSERT routine:loc_8c044dce SET label='loc_8c044dce', pc='0x8C044DCE', bank='bank04', role='object-pool initializer',
  note='Initializes the satellite object pool (capes/projectiles/effects/supers): base 0x8C26AA54, stride 0x1D0, 256 nodes (consts loc_8c044ec8=base, loc_8c044ea4=0x1d0, loc_8c044ed8=0x1d000=256*0x1d0). Allocator = free-list pop loc_8c044f12 (sets node+0x3=category, jsr per-category constructor loc_8c045020[cat]).';

-- ---- already-seeded routines kept; refine notes ----------------------------
UPSERT routine:loc_8c033e90 SET label='loc_8c033e90', pc='0x8C033E90', bank='bank03', role='GFX1 load-burst packer (LOAD-TIME, NOT per-frame)',
  note='ORACLE-CONFIRMED load-time (fires ONCE ~frame 2568 into 0x0CE60000; palptr=0, no screen coords; capture PC 0x8C033EC0). Dispatched from cell-processor jump table loc_8c033d78. Packs the EFFECT/UI sheet sels 0-251 ONLY (NOT the body). 16-byte quad@r14 {w<<3,h<<3,attr,texptr(r8),palptr(r12)}; sel=read_u16(r13+6). The display list lands in RAM (~0x0C56xxxx) then bulk-DMA to TA later -- NOT the TA FIFO. NOT the per-frame emitter (that is loc_8c0344d4).';
UPSERT routine:loc_8c1244b0 SET label='loc_8c1244b0', pc='0x8C1244B0', bank='bank12', role='PVR sprite-para submit',
  note='Builds the dest PVR sprite-para (4 screen corners + UV sub-rects). CHARQ probe reads the per-part quad at 0x8C1248CC (r14 corners, TCW @ r12+0x0C). UV-corner flip derived from FLAGS.';

-- ---- edges: reads / writes / calls -----------------------------------------
-- Render_sprites walks the slot table and dispatches Render Main Sprite
RELATE routine:loc_8c0308c2->reads->global:slot_table_count;
RELATE routine:loc_8c0308c2->reads->global:slot_table_ptrs;
RELATE routine:loc_8c0308c2->calls->routine:loc_8c03093c;

-- Render Main Sprite: reads pos/scale/facing, writes screen_x/y, calls transform
RELATE routine:loc_8c03093c->reads->field:pos_x;
RELATE routine:loc_8c03093c->reads->field:pos_y;
RELATE routine:loc_8c03093c->reads->field:x_sprite_scale;
RELATE routine:loc_8c03093c->reads->field:facing;
RELATE routine:loc_8c03093c->writes->field:screen_x;
RELATE routine:loc_8c03093c->writes->field:screen_y;
RELATE routine:loc_8c03093c->calls->routine:loc_8c1216c0;

-- Body emitter: reads sprite_id + GFX2 + scale + screen anchor; submits to bank12
RELATE routine:loc_8c0344d4->reads->field:sprite_id;
RELATE routine:loc_8c0344d4->reads->field:dat_gfx2;
RELATE routine:loc_8c0344d4->reads->field:dat_gfx1;
RELATE routine:loc_8c0344d4->reads->field:screen_x;
RELATE routine:loc_8c0344d4->reads->field:screen_y;
RELATE routine:loc_8c0344d4->reads->field:hitbox_scale_x;
RELATE routine:loc_8c0344d4->reads->field:facing;
RELATE routine:loc_8c0344d4->calls->routine:loc_8c1244b0;

-- cell processor reads current_cell_data (the crash dependency)
RELATE routine:loc_8c1294c8->reads->field:current_cell_data;

-- anim tick advances/writes the cell pointer + sprite_id + timer
RELATE routine:loc_8c034dee->reads->field:current_cell_data;
RELATE routine:loc_8c034dee->writes->field:current_cell_data;
RELATE routine:loc_8c034dee->writes->field:sprite_id;
RELATE routine:loc_8c034dee->writes->field:anim_timer;

-- load animation computes current_cell_data from animations
RELATE routine:loc_8c034e8c->reads->field:animations;
RELATE routine:loc_8c034e8c->reads->field:anim_group;
RELATE routine:loc_8c034e8c->writes->field:current_cell_data;

-- DM00 decoder writes the transient VRAM the body emitter consumes
RELATE routine:loc_8c0322c0->writes->buffer:dm00pool;
RELATE routine:loc_8c0322c0->calls->routine:loc_8c03552a;

-- pool initializer writes the object pool struct
RELATE routine:loc_8c044dce->writes->struct:object_pool_node;
