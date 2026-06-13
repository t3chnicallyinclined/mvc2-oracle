-- ============================================================================
-- 04: buffers/regions, globals, dataformats, object-pool struct
-- Sources: work.asm, CLAUDE.md, re-catalog, anotak.
-- ============================================================================
USE NS re DB kb;

-- ---- buffers / regions (refine seeded + add) -------------------------------
UPSERT buffer:ce60000  SET addr='0x0CE60000', name='Texture_Decompress_Buffer',
  purpose='transient LZSS scratch AND the GFX1 load-burst atlas (dual use = the conflation trap). Whatever is decoded here is overwritten by the next decode -- NOT a persistent atlas.',
  lifetime='transient, overwritten per decode call', note='work.asm:36. The load burst (loc_8c033e90) packs effect/UI sels 0-251 here once at match load.';
UPSERT buffer:dm00pool SET addr='*(0x0CE80008)', name='DM00 directory/pool',
  purpose='compressed-source directory (entry stride 0x10, +8=compressed src ptr); on-demand LZSS decode for body part pixels; ~25-entry shared COMPACTING working set; live count @ *(0x0CE80004).',
  lifetime='compacts as poses cycle (moving TCW)', note='Pipeline 2 of the three that touch 0x0CE60000. The ONLY source of body sel pixels.';
UPSERT buffer:effect_poly SET addr='0x0CED0000', name='Effect Poly',
  purpose='shared hitspark/effects geometry+pixels; effects resolve by GFX pointer (owner+0x15C) not sprite_id.',
  lifetime='resident effects bank', note='reference_mvc2_effects_bank: route by effect-type to an effects atlas.';
UPSERT buffer:char_prg_overlay SET addr='0x0CE30000', name='char-programming overlay region',
  purpose='where the per-character SPL programs (S_PLxx) load as CODE (A@0xCE30000..F@0xCE58000).',
  lifetime='loaded per active character', note='pl_mem: ptr_to_char_programming_A..F. CODE not data.';

UPSERT region:vram_decode_window SET name='part-decode VRAM window', lo='0x0CDD0000', hi='0x0CE00000',
  note='VRAM window where on-demand-decoded part pixels transiently live before eviction by the compactor.';
UPSERT region:char_struct_page SET name='char-struct page (616)', lo='0x8C268000', hi='0x8C26AFFF',
  note='page 616. char structs (0x8C268340+) + object pool (0x8C26AA54+) + camera block (~0x8C26A52C).';
UPSERT region:global_page SET name='global-state page (649)', lo='0x8C289000', hi='0x8C289FFF',
  note='page 649. in_match, slot table 0x8C2895E0, Match_Tracker 0x8C2895F0, timers, stage_id.';

RELATE buffer:dm00pool->part_of->region:vram_decode_window;

-- ---- globals (work.asm / CLAUDE.md) ----------------------------------------
UPSERT global:in_match SET name='in_match', addr='0x8C289624', type='u8', note='in-match flag (CLAUDE.md). gates scene.';
UPSERT global:match_sub_state SET name='match_sub_state', addr='0x8C289621', type='u8', note='match sub-state (CLAUDE.md). NOTE: spreadsheet calls true match-state machine Match_Tracker @0x8C2895F0.';
UPSERT global:match_tracker SET name='Match_Tracker', addr='0x8C2895F0', type='u8', note='match-state machine: 0 loading / 2 intro / 3 walk / 4 mid-match / 5 KO / 6 win / 9 finish (spreadsheet). Best scene-gating signal for the sprite client.';
UPSERT global:round_counter SET name='round_counter', addr='0x8C28962B', type='u8', note='round counter (CLAUDE.md).';
UPSERT global:game_timer SET name='game_timer', addr='0x8C289630', type='u16', note='match countdown timer (CLAUDE.md).';
UPSERT global:stage_id SET name='stage_id', addr='0x8C289638', type='u8', note='current stage id (CLAUDE.md). drives client-side stage/background render.';
UPSERT global:p1_meter_fill SET name='p1_meter_fill', addr='0x8C289646', type='u16', note='P1 super-meter fill (CLAUDE.md).';
UPSERT global:p1_combo SET name='p1_combo', addr='0x8C289670', type='u16', note='P1 combo counter (CLAUDE.md).';
UPSERT global:frame_counter SET name='frame_counter', addr='0x8C3496B0', type='u32', note='global frame counter (CLAUDE.md). used for .mcrec alignment.';
UPSERT global:slot_table_count SET name='slot_table_count', addr='0x8C2895E0', type='array', note='on-screen render slot table (count array), stride 0x180. THE draw list: enumerate every on-screen object incl owner-less global supers.';
UPSERT global:slot_table_ptrs SET name='slot_table_ptrs', addr='0x8C287DE0', type='array', note='inner x4 pointer array for the slot table; loc_8c0308c2 walks it.';
UPSERT global:camera_z SET name='Camera_Z_Position', addr='0x8C26A52C', type='f32', note='camera Z / zoom (default 812.357). path to dynamic zoom vs the const 1.75x lock. Camera_Z_Sprite_Scale @0x8C26A538.';

RELATE global:in_match->lives_at->global:in_match;
RELATE global:slot_table_count->part_of->region:global_page;
RELATE global:camera_z->part_of->region:char_struct_page;

-- ---- object-pool struct (re-catalog/00-README) -----------------------------
UPSERT struct:object_pool_node SET name='object_pool_node', base='0x8C26AA54', stride='0x1D0', count=256,
  note='Satellite object pool: capes / projectiles / effects / supers. Every character on screen = body + cape(s) + effect/projectile objects, each with its own sprite_id + screen pos. Initialized by loc_8c044dce; allocated via free-list pop loc_8c044f12 (node+0x3=category -> per-category constructor). Draw order = doubly-linked active-list (next@+0x8/prev@+0xC), no z scalar; infer layer from category@+0x3 + sprite_id range.';
UPSERT field:obj_category SET name='obj_category', offset='+0x003', owner='object_pool_node', type='u8', class='object', note='object category/type; selects the per-category constructor; layer hint.';
UPSERT field:obj_next SET name='obj_next', offset='+0x008', owner='object_pool_node', type='ptr', class='object', note='doubly-linked active-list next.';
UPSERT field:obj_prev SET name='obj_prev', offset='+0x00C', owner='object_pool_node', type='ptr', class='object', note='doubly-linked active-list prev.';
UPSERT field:obj_update_fn SET name='obj_update_fn', offset='+0x010', owner='object_pool_node', type='ptr', class='object', note='per-frame update function ptr.';
UPSERT field:obj_world_x SET name='obj_world_x', offset='+0x034', owner='object_pool_node', type='f32', class='object', note='object world X (diverges from owner for in-flight projectiles).';
UPSERT field:obj_world_y SET name='obj_world_y', offset='+0x038', owner='object_pool_node', type='f32', class='object', note='object world Y.';
UPSERT field:obj_owner SET name='obj_owner', offset='+0x080', owner='object_pool_node', type='ptr', class='object', note='OWNER player-struct ptr (copy @+0x84); tells which char_id -> which rip atlas/palette bank.';
UPSERT field:obj_screen_x SET name='obj_screen_x', offset='+0x0E0', owner='object_pool_node', type='f32', class='object', note='RESOLVED screen X: loc_8c03093c writes the world->screen transform here. THE submitted x (NOT +0xC8). readAllDrawn/readObjectsWalk read this.';
UPSERT field:obj_screen_y SET name='obj_screen_y', offset='+0x0E4', owner='object_pool_node', type='f32', class='object', note='RESOLVED screen Y (NOT +0xCC).';
UPSERT field:obj_cull SET name='obj_cull', offset='+0x12C', owner='object_pool_node', type='u8', class='object', note='cull/enable byte (skip render if !=0 per loc_8c030aa4). NOT a sprite_id. The old owner-anchored scan mistook +0x12C for sprite_id.';
UPSERT field:obj_sprite_id SET name='obj_sprite_id', offset='+0x144', owner='object_pool_node', type='u16', class='object', note='object sprite_id (char-struct convention; what readAllDrawn reads). NOTE conflict: old scan read sid @+0x12C (wrong).';

RELATE struct:object_pool_node->has_field->field:obj_category;
RELATE struct:object_pool_node->has_field->field:obj_next;
RELATE struct:object_pool_node->has_field->field:obj_prev;
RELATE struct:object_pool_node->has_field->field:obj_update_fn;
RELATE struct:object_pool_node->has_field->field:obj_world_x;
RELATE struct:object_pool_node->has_field->field:obj_world_y;
RELATE struct:object_pool_node->has_field->field:obj_owner;
RELATE struct:object_pool_node->has_field->field:obj_screen_x;
RELATE struct:object_pool_node->has_field->field:obj_screen_y;
RELATE struct:object_pool_node->has_field->field:obj_cull;
RELATE struct:object_pool_node->has_field->field:obj_sprite_id;
RELATE struct:object_pool_node->part_of->region:char_struct_page;

-- ---- data formats (anotak + engine) ----------------------------------------
UPSERT dataformat:anim_cell SET name='animation_cell', size='0x14 (20 bytes)',
  layout='AnimFlags@+0(0x80=EffectTrigger bit), EffectTrigger@+1, Duration@+2(->player+0x142), Ender@+3(0x80=end), Sprite@+4(->player+0x144), unk06, unk07, AirborneLaunchAngle, AirborneLaunchSpeed, ProximityBlock, unk0b, SoundFX, unk0d..unk10, RenderExtra@+0x11(->player+0x151), HitboxGroup@+0x12(->0x152), unk14',
  note='anotak animation cell. Contiguous list, Ender byte terminates. Advanced 20 B/keyframe by loc_8c034dee. Groups numbered 0x00-0x1B.',
  source_url='https://zachd.com/mvc2/data/anotak/possible_anim.html';
UPSERT dataformat:extras_oam SET name='extras_oam_record', size='8 bytes',
  layout='[dx:s16][dy:s16][part_idx/tile:u16][attr:u16]; attr 0x00FF = frame terminator',
  note='EXTRAS/OAM sprite-assembly record (Sprite_Extras@+0x178). Distinct stride from the 20-byte cell -- do not conflate.',
  source_url='https://zachd.com/mvc2/data/anotak/index.html';
UPSERT dataformat:gfx2_cell SET name='gfx2_cell_record', size='8 bytes',
  layout='[dx:s16][dy:s16][FLAGS:u16 (X-mirror 0x4000 / Y-mirror 0x8000)][sel:u16]; cell prefixed by u16 record count; cell=GFX2+*(u32)(GFX2+(sid&0x7FFF)*4); cumulative running pen',
  note='The live per-frame body cell record read by loc_8c0344d4. cell index == sprite_id. tools/rip_gfx2_assembly.py read_cells() enumerates all of them statically (n=(first u32 of GFX2)>>2).',
  source_url='https://zachd.com/mvc2/data/anotak/PL2C_DAT_animgroup0.html';
UPSERT dataformat:attack_data SET name='attack_data_record',
  layout='per-move attack fields (damage, hitstun, blockstun, etc.) -- see anotak per-field index',
  note='attack_data@+0x174. Field semantics per anotak possible.html.',
  source_url='https://zachd.com/mvc2/data/anotak/possible.html';
UPSERT dataformat:palette SET name='palette', size='32 bytes (16 colors)',
  layout='ARGB4444 little-endian, 16 colors, index 0 = transparent',
  note='Dat_Pal@+0x164. PVR bank = 16*(char_pair+1) + 8*player_side.',
  source_url='https://zachd.com/mvc2/data/anotak/index.html';

RELATE field:current_cell_data->maps_to->dataformat:anim_cell;
RELATE field:sprite_extras->maps_to->dataformat:extras_oam;
RELATE field:dat_gfx2->maps_to->dataformat:gfx2_cell;
RELATE field:attack_data->maps_to->dataformat:attack_data;
RELATE field:dat_pal->maps_to->dataformat:palette;
