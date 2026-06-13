-- ============================================================================
-- 02: Per-character struct — layout, all known fields, the 6 slots
-- Sources: memory/pl_mem.asm (AUTHORITATIVE offsets), CLAUDE.md, re-catalog/.
-- ============================================================================
USE NS re DB kb;

-- ---- the struct itself -----------------------------------------------------
UPSERT struct:char_struct SET
  name='char_struct', base='0x8C268340', stride='0x5A4', pair_stride='0xB48', count=6,
  note='Per-character state struct (P1C1 base 0x8C268340, stride 0x5A4, 6 slots). Holds LOGICAL fields (server-knowable: sprite_id/pos/health/facing) AND the ENGINE-OWNED pointer cluster 0x154-0x184 recomputed every frame from PLxx_DAT. Cardinal lesson: writing logical fields while the pointer cluster is at a different frame corrupts the cell processor -> illegal-instruction crash; render off-SH4 instead.';

-- ---- LOGICAL fields (server-knowable; safe to read/write) -------------------
UPSERT field:active        SET name='active', offset='+0x000', owner='char_struct', type='u8',  class='logical', note='slot active flag (pl_mem: active).';
UPSERT field:character_id  SET name='character_id', offset='+0x001', owner='char_struct', type='u8', class='logical', note='roster char id == PLxx hex == S_PLxx index (pl_mem: charid0). 0x00 Ryu .. 0x3A Servbot.';
UPSERT field:pl_palid_match SET name='pl_palid_match', offset='+0x025', owner='char_struct', type='u8', class='logical', note='COLOR/palette index SELECTED IN MATCH (live skin/tint). pal_id also mirrored at +0x52D.';
UPSERT field:pos_x         SET name='pos_x', offset='+0x034', owner='char_struct', type='f32', class='logical', note='world/stage X (pl_mem: x_pos).';
UPSERT field:pos_y         SET name='pos_y', offset='+0x038', owner='char_struct', type='f32', class='logical', note='world/stage Y (pl_mem: y_pos). camera stops tracking ~900.';
UPSERT field:char_pal_effect SET name='char_pal_effect', offset='+0x040', owner='char_struct', type='u16', class='logical', note='super-glow / hit-flash palette effect word (pl_mem: char_pal_effect).';
UPSERT field:x_sprite_scale SET name='x_sprite_scale', offset='+0x050', owner='char_struct', type='f32', class='logical', note='per-char sprite scale X (pl_mem: x_sprite_scale). y@+0x54, z@+0x58. vs the const 1.75x lock.';
UPSERT field:y_sprite_scale SET name='y_sprite_scale', offset='+0x054', owner='char_struct', type='f32', class='logical', note='per-char sprite scale Y (pl_mem: y_sprite_scale).';
UPSERT field:z_sprite_scale SET name='z_sprite_scale', offset='+0x058', owner='char_struct', type='f32', class='logical', note='per-char sprite scale Z (pl_mem: z_sprite_scale).';
UPSERT field:screen_x      SET name='screen_x', offset='+0x0E0', owner='char_struct', type='f32', class='logical', note='post-transform screen X (0-640). Written by loc_8c03093c (world->screen). THE GPU-placement anchor. (pl_mem: x_pos_screenspace).';
UPSERT field:screen_y      SET name='screen_y', offset='+0x0E4', owner='char_struct', type='f32', class='logical', note='post-transform screen Y (0-480). Written by loc_8c03093c. (pl_mem: y_pos_screenspace).';
UPSERT field:hitbox_scale_x SET name='hitbox_scale_x', offset='+0x0EC', owner='char_struct', type='f32', class='logical', note='hitbox/render scale X used by body walker loc_8c0344d4 final screen= node+0xE0 + pen*scale@0xEC. (spreadsheet: Hitbox_Scale_X).';
UPSERT field:hitbox_scale_y SET name='hitbox_scale_y', offset='+0x0F0', owner='char_struct', type='f32', class='logical', note='hitbox/render scale Y (loc_8c0344d4 uses @0xF0).';
UPSERT field:facing        SET name='facing', offset='+0x110', owner='char_struct', type='u8', class='logical', note='facing COPY (pl_mem: xflip_copy_2). authoritative xflip = +0x1D2; copies also at +0x130/+0x134.';
UPSERT field:anim_timer    SET name='anim_timer', offset='+0x142', owner='char_struct', type='u16', class='logical', note='frame_count / per-frame countdown decremented by the engine (pl_mem: frame_count). Writing it fights the anim clock.';
-- sprite_id already seeded; refine note + class
UPSERT field:sprite_id     SET name='sprite_id', offset='+0x144', owner='char_struct', type='u16', class='logical', note='stable per-char BODY render key (masked &0x7FFF). THE renderer input; cell index into Dat_GFX2. Shipped on the GSTA wire.';
UPSERT field:anim_flags    SET name='anim_flags', offset='+0x14A', owner='char_struct', type='u8', class='logical', note='per-frame flags inherited from cell+0x10 (pl_mem: anim_flags). 0x20 no special/super/assist cancel, 0x40 recovery, 0x80 opponent can proximity-block.';
UPSERT field:health        SET name='health', offset='+0x420', owner='char_struct', type='u16', class='logical', note='current health (pl_mem: health, int16). red_health/health2 @ +0x424.';
UPSERT field:red_health    SET name='red_health', offset='+0x424', owner='char_struct', type='u16', class='logical', note='recoverable/red health (pl_mem: health2).';
UPSERT field:palette       SET name='palette', offset='+0x52D', owner='char_struct', type='u8', class='logical', note='palette/pal_id mirror (CLAUDE.md). live SELECT uses pl_palid_match @ +0x025.';
UPSERT field:stance        SET name='stance', offset='+0x1F9', owner='char_struct', type='u8', class='logical', note='0 stand / 1 crouch / 2 jump / 3 otg (pl_mem: stance).';
UPSERT field:xflip         SET name='xflip', offset='+0x1D2', owner='char_struct', type='u8', class='logical', note='authoritative facing/x-mirror (pl_mem: xflip). +0x110/+0x130 are copies.';
UPSERT field:unk_01d0      SET name='unk_01d0', offset='+0x1D0', owner='char_struct', type='u8', class='logical', note='DISPUTED width: marvelous2 unk_01d0 is a BYTE (controls which move to play); CLAUDE.md calls it animation_state u16. Trust byte unless re-confirmed. NOT on the sprite-selection critical path (sprite_id@0x144 is).';

-- ---- ENGINE-OWNED pointer cluster (0x154-0x184) — NEVER write from outside --
UPSERT field:current_cell_data SET name='current_cell_data', offset='+0x154', owner='char_struct', type='ptr', class='engine', note='ENGINE-OWNED. ptr to the current 20-byte animation cell; dereferenced every frame. Stale/corrupt value here mis-indexes the bank12 cell processor jump table -> jmp into non-code -> illegal-instruction crash (expEvn=0x180). The root cause of the state-injection dead-end.';
UPSERT field:anim_group    SET name='anim_group', offset='+0x158', owner='char_struct', type='u8', class='engine', note='ENGINE-OWNED. current animation group/anim id (pl_mem: anim_id == anim_group).';
-- dat_gfx1/2/pal already seeded; reclassify + refine
UPSERT field:dat_gfx1  SET name='Dat_GFX1', offset='+0x15C', owner='char_struct', type='ptr', class='engine', note='ENGINE-OWNED. per-char GFX1 part-table base; hdr=GFX1+*(GFX1+sel*4) is tile METADATA (not pixels). Body walker loc_8c0344d4 reads it.';
UPSERT field:dat_gfx2  SET name='Dat_GFX2', offset='+0x160', owner='char_struct', type='ptr', class='engine', note='ENGINE-OWNED. per-char GFX2 cell table. cell index==sprite_id: cell=GFX2+*(u32)(GFX2+(sid&0x7FFF)*4); first u16 = record count.';
UPSERT field:dat_pal   SET name='Dat_Pal', offset='+0x164', owner='char_struct', type='ptr', class='engine', note='ENGINE-OWNED. per-char live palette ptr (ARGB4444, 16 colors/32 bytes, idx0 transparent).';
UPSERT field:animations SET name='animations', offset='+0x168', owner='char_struct', type='ptr', class='engine', note='ENGINE-OWNED. base of the per-char anim/cell keyframe table. loc_8c034e8c computes current_cell_data from this + group/anim id. RenderExtra lives here.';
UPSERT field:hitbox_pattern_table SET name='hitbox_pattern_table', offset='+0x16C', owner='char_struct', type='ptr', class='engine', note='ENGINE-OWNED. hitbox pattern table ptr (pl_mem).';
UPSERT field:hitbox_data SET name='hitbox_data', offset='+0x170', owner='char_struct', type='ptr', class='engine', note='ENGINE-OWNED. hitbox data ptr (pl_mem).';
UPSERT field:attack_data SET name='attack_data', offset='+0x174', owner='char_struct', type='ptr', class='engine', note='ENGINE-OWNED. attack data table ptr (pl_mem). anotak DAT_atk fields.';
UPSERT field:sprite_extras SET name='Sprite_Extras', offset='+0x178', owner='char_struct', type='ptr', class='engine', note='ENGINE-OWNED. EXTRAS/OAM sprite-assembly record ptr (pl_mem). 8-byte records.';
UPSERT field:dat_filepointer SET name='Dat_FilePointer', offset='+0x17C', owner='char_struct', type='ptr', class='engine', note='ENGINE-OWNED. base file ptr for the loaded PLxx_DAT (pl_mem).';
UPSERT field:fac_ptr   SET name='FAC_ptr', offset='+0x184', owner='char_struct', type='ptr', class='engine', note='ENGINE-OWNED. FAC (face/portrait) file ptr (pl_mem).';

-- ---- has_field edges (struct -> field) -------------------------------------
RELATE struct:char_struct->has_field->field:active;
RELATE struct:char_struct->has_field->field:character_id;
RELATE struct:char_struct->has_field->field:pl_palid_match;
RELATE struct:char_struct->has_field->field:pos_x;
RELATE struct:char_struct->has_field->field:pos_y;
RELATE struct:char_struct->has_field->field:char_pal_effect;
RELATE struct:char_struct->has_field->field:x_sprite_scale;
RELATE struct:char_struct->has_field->field:y_sprite_scale;
RELATE struct:char_struct->has_field->field:z_sprite_scale;
RELATE struct:char_struct->has_field->field:screen_x;
RELATE struct:char_struct->has_field->field:screen_y;
RELATE struct:char_struct->has_field->field:hitbox_scale_x;
RELATE struct:char_struct->has_field->field:hitbox_scale_y;
RELATE struct:char_struct->has_field->field:facing;
RELATE struct:char_struct->has_field->field:anim_timer;
RELATE struct:char_struct->has_field->field:sprite_id;
RELATE struct:char_struct->has_field->field:anim_flags;
RELATE struct:char_struct->has_field->field:health;
RELATE struct:char_struct->has_field->field:red_health;
RELATE struct:char_struct->has_field->field:palette;
RELATE struct:char_struct->has_field->field:stance;
RELATE struct:char_struct->has_field->field:xflip;
RELATE struct:char_struct->has_field->field:unk_01d0;
RELATE struct:char_struct->has_field->field:current_cell_data;
RELATE struct:char_struct->has_field->field:anim_group;
RELATE struct:char_struct->has_field->field:dat_gfx1;
RELATE struct:char_struct->has_field->field:dat_gfx2;
RELATE struct:char_struct->has_field->field:dat_pal;
RELATE struct:char_struct->has_field->field:animations;
RELATE struct:char_struct->has_field->field:hitbox_pattern_table;
RELATE struct:char_struct->has_field->field:hitbox_data;
RELATE struct:char_struct->has_field->field:attack_data;
RELATE struct:char_struct->has_field->field:sprite_extras;
RELATE struct:char_struct->has_field->field:dat_filepointer;
RELATE struct:char_struct->has_field->field:fac_ptr;

-- ---- the 6 concrete slots --------------------------------------------------
UPSERT slot:p1c1 SET name='P1C1', base='0x8C268340', player=1, char_pos=1, note='Player 1, character 1. struct base. (pl_mem: player_start_charA).';
UPSERT slot:p2c1 SET name='P2C1', base='0x8C2688E4', player=2, char_pos=1, note='Player 2, character 1 (pl_mem: charB).';
UPSERT slot:p1c2 SET name='P1C2', base='0x8C268E88', player=1, char_pos=2, note='Player 1, character 2 (pl_mem: charC).';
UPSERT slot:p2c2 SET name='P2C2', base='0x8C26942C', player=2, char_pos=2, note='Player 2, character 2 (pl_mem: charD).';
UPSERT slot:p1c3 SET name='P1C3', base='0x8C2699D0', player=1, char_pos=3, note='Player 1, character 3 (pl_mem: charE).';
UPSERT slot:p2c3 SET name='P2C3', base='0x8C269F74', player=2, char_pos=3, note='Player 2, character 3 (pl_mem: charF).';

RELATE slot:p1c1->instance_of->struct:char_struct;
RELATE slot:p2c1->instance_of->struct:char_struct;
RELATE slot:p1c2->instance_of->struct:char_struct;
RELATE slot:p2c2->instance_of->struct:char_struct;
RELATE slot:p1c3->instance_of->struct:char_struct;
RELATE slot:p2c3->instance_of->struct:char_struct;
