-- ============================================================================
-- MapleCast RE Knowledge Graph — schema + seed slice
-- SurrealDB local instance: http://127.0.0.1:8001  ns=re  db=kb
-- Apply:  curl -s -X POST http://127.0.0.1:8001/sql -u root:root \
--           -H "Accept: application/json" --data-binary @tools/re_kb/schema_seed.surql
-- Idempotent (DEFINE ... IF NOT EXISTS + UPSERT). Safe to re-run.
-- ============================================================================
USE NS re DB kb;

-- ---- node tables -----------------------------------------------------------
DEFINE TABLE IF NOT EXISTS routine    SCHEMALESS COMMENT 'marvelous2 SH4 routine; id=loc label; fields: pc, bank, role, summary';
DEFINE TABLE IF NOT EXISTS field      SCHEMALESS COMMENT 'struct/semantic field; id=name; fields: offset, owner, type, note';
DEFINE TABLE IF NOT EXISTS address    SCHEMALESS COMMENT 'memory location; fields: addr, kind(ram_abs/struct_offset/pc/region), note';
DEFINE TABLE IF NOT EXISTS buffer     SCHEMALESS COMMENT 'memory region/buffer; fields: addr, name, purpose, lifetime';
DEFINE TABLE IF NOT EXISTS dataformat SCHEMALESS COMMENT 'anotak data structure; fields: size, layout, source_url';
DEFINE TABLE IF NOT EXISTS finding    SCHEMALESS COMMENT 'RE fact; fields: statement, status(confirmed/inferred/open), confidence, date';
DEFINE TABLE IF NOT EXISTS source     SCHEMALESS COMMENT 'provenance; fields: kind(marvelous2/anotak/oracle/memory/doc), ref, note';

-- ---- edge tables (created via RELATE) --------------------------------------
DEFINE TABLE IF NOT EXISTS reads    SCHEMALESS COMMENT 'routine -> field/address/buffer';
DEFINE TABLE IF NOT EXISTS writes   SCHEMALESS COMMENT 'routine -> field/address/buffer';
DEFINE TABLE IF NOT EXISTS calls    SCHEMALESS COMMENT 'routine -> routine';
DEFINE TABLE IF NOT EXISTS lives_at SCHEMALESS COMMENT 'field -> address';
DEFINE TABLE IF NOT EXISTS maps_to  SCHEMALESS COMMENT 'field/buffer -> dataformat';
DEFINE TABLE IF NOT EXISTS about    SCHEMALESS COMMENT 'finding -> any entity';
DEFINE TABLE IF NOT EXISTS cites    SCHEMALESS COMMENT 'finding/entity -> source';

-- ---- seed: the part-decode/storage mechanism (the locked finding) ----------
UPSERT field:sprite_id SET name='sprite_id', offset='+0x144', owner='char_struct', type='u16', note='stable per-char render key (masked & 0x7FFF); THE renderer input';
UPSERT field:dat_gfx1  SET name='Dat_GFX1',  offset='+0x15C', owner='char_struct', type='ptr', note='per-char GFX1 part-table base; hdr=GFX1+*(GFX1+sel*4)';
UPSERT field:dat_gfx2  SET name='Dat_GFX2',  offset='+0x160', owner='char_struct', type='ptr', note='per-char GFX2 cell table; cell index==sprite_id';
UPSERT field:dat_pal   SET name='Dat_Pal',   offset='+0x164', owner='char_struct', type='ptr', note='per-char palette (ARGB4444)';

UPSERT routine:loc_8c0344d4 SET label='loc_8c0344d4', pc='0x8C0344D4', bank='bank03', role='per-frame BODY render', summary='reads sprite_id+GFX1; cumulative pen; emits PVR sprite-para to bank12 submit; calls NO decoder; body sels 252-1532; sel=read_u16(r11+6); X-mirror FLAGS&0x4000, Y-mirror FLAGS&0x8000';
UPSERT routine:loc_8c033e90 SET label='loc_8c033e90', pc='0x8C033E90', bank='bank03', role='GFX1 load-burst packer', summary='packs EFFECT/UI sheet sels 0-251 ONLY into 0x0CE60000 at match load; quad@r14 {w<<3,h<<3,attr,texptr,palptr=0}; sel=read_u16(r13+6)';
UPSERT routine:loc_8c0322c0 SET label='loc_8c0322c0', pc='0x8C0322C0', bank='bank03', role='DM00 on-demand decoder', summary='sel->entry(=dir+sel*0x10, +8=compressed src)->LZSS decode on demand';
UPSERT routine:loc_8c1244b0 SET label='loc_8c1244b0', pc='0x8C1244B0', bank='bank12', role='PVR sprite-para submit', summary='builds dest sprite-para (4 corners+UV); CHARQ_EMIT-paired at 0x8C1248CC; UV-corner flip from FLAGS&0x30';

UPSERT buffer:ce60000  SET addr='0x0CE60000', name='Texture_Decompress_Buffer', purpose='transient LZSS scratch AND GFX1 load-burst atlas (dual use = the conflation trap)', lifetime='transient, overwritten per decode call';
UPSERT buffer:dm00pool SET addr='*(0x0CE80008)', name='DM00 directory/pool', purpose='compressed-source dir, on-demand decode, ~25-entry shared COMPACTING working set; count@*(0x0CE80004)', lifetime='compacts as poses cycle';

UPSERT source:marv_bank03 SET kind='marvelous2', ref='bank03.asm: loc_8c0344d4(10218), loc_8c033e90(9258), loc_8c0322c0(5069), loc_8c0322d4(5082) compactor, work.asm:36-39', note='local _marv_re checkout';
UPSERT source:anotak_pl00 SET kind='anotak', ref='https://zachd.com/mvc2/data/anotak/PL00_DAT_atk.html', note='Ryu 26 animation groups -> cells -> sprite_ids (the coverage map; data only, no pixels)';

UPSERT finding:part_decode_mechanism SET statement='Body part pixels (sels 252-1532, ~1281, what the emitter needs) are ON-DEMAND-decoded per-pose into transient VRAM with a MOVING TCW (CHARQ: one sel -> many TCWs). There is NO bulk-resident store of all 1533 part pixels. The GFX1 load-burst (loc_8c033e90 @0x8C033EC0) covers ONLY the effect/UI sheet sels 0-251. Full pixel coverage therefore requires the poses to appear on screen (play-capture: BODYCAP @0x8C034864 sel-keyed, or CHARQ per-frame). Static GFX2 rip gives geometry/assembly only; offline LZSS decode is a dead end.', status='confirmed', confidence='high', date='2026-06-10';

-- ---- edges -----------------------------------------------------------------
RELATE routine:loc_8c0344d4->reads->field:sprite_id;
RELATE routine:loc_8c0344d4->reads->field:dat_gfx1;
RELATE routine:loc_8c1244b0->writes->buffer:ce60000;
RELATE routine:loc_8c033e90->writes->buffer:ce60000;
RELATE routine:loc_8c0322c0->writes->buffer:dm00pool;
RELATE routine:loc_8c0344d4->calls->routine:loc_8c1244b0;
RELATE finding:part_decode_mechanism->about->routine:loc_8c0344d4;
RELATE finding:part_decode_mechanism->about->routine:loc_8c033e90;
RELATE finding:part_decode_mechanism->about->buffer:ce60000;
RELATE finding:part_decode_mechanism->about->buffer:dm00pool;
RELATE finding:part_decode_mechanism->cites->source:marv_bank03;
