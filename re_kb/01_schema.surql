-- ============================================================================
-- MapleCast RE Knowledge Graph — 01: schema (node + edge tables)
-- SurrealDB local: http://127.0.0.1:8001  ns=re  db=kb  (root:root)
-- Apply: curl -s -X POST http://127.0.0.1:8001/sql -u root:root \
--          -H "Accept: application/json" --data-binary @tools/re_kb/01_schema.surql
-- Idempotent (DEFINE ... IF NOT EXISTS). Safe to re-run. Extends schema_seed.surql.
-- EVERY node table carries a `note` field (plain-English: what it is / does).
-- ============================================================================
USE NS re DB kb;

-- ---- node tables (existing, kept) ------------------------------------------
DEFINE TABLE IF NOT EXISTS routine    SCHEMALESS COMMENT 'marvelous2 SH4 routine; id=loc label; fields: pc, bank, role, summary/note';
DEFINE TABLE IF NOT EXISTS field      SCHEMALESS COMMENT 'struct/semantic field; id=name; fields: offset, owner, type, note';
DEFINE TABLE IF NOT EXISTS address    SCHEMALESS COMMENT 'memory location; fields: addr, kind(ram_abs/struct_offset/pc/region), note';
DEFINE TABLE IF NOT EXISTS buffer     SCHEMALESS COMMENT 'memory region/buffer; fields: addr, name, purpose/note, lifetime';
DEFINE TABLE IF NOT EXISTS dataformat SCHEMALESS COMMENT 'anotak/engine data structure; fields: size, layout, note, source_url';
DEFINE TABLE IF NOT EXISTS finding    SCHEMALESS COMMENT 'RE fact; fields: statement/note, status(confirmed/inferred/open/resolved), confidence, date';
DEFINE TABLE IF NOT EXISTS source     SCHEMALESS COMMENT 'provenance; fields: kind(marvelous2/anotak/oracle/memory/doc/recatalog), ref, note';

-- ---- node tables (NEW for the domain) --------------------------------------
DEFINE TABLE IF NOT EXISTS struct     SCHEMALESS COMMENT 'a RAM struct layout (char_struct, object_pool_node); fields: base, stride, count, note';
DEFINE TABLE IF NOT EXISTS character  SCHEMALESS COMMENT 'a roster character; id=plXX (hex char_id); fields: char_id, name, spl_file, atlas, note';
DEFINE TABLE IF NOT EXISTS slot       SCHEMALESS COMMENT 'a concrete per-player char-struct instance; id=p#c#; fields: base, player, char_pos, note';
DEFINE TABLE IF NOT EXISTS global      SCHEMALESS COMMENT 'a global game-state RAM variable; id=name; fields: addr, type, note';
DEFINE TABLE IF NOT EXISTS region      SCHEMALESS COMMENT 'a named RAM/VRAM address range; fields: lo, hi, note';
DEFINE TABLE IF NOT EXISTS animgroup  SCHEMALESS COMMENT 'a per-character animation group (0x00-0x1B); id=plXX_gNN; fields: char, group_id, note';

-- ---- edge tables (existing, kept) ------------------------------------------
DEFINE TABLE IF NOT EXISTS reads    SCHEMALESS COMMENT 'routine -> field/address/buffer/global';
DEFINE TABLE IF NOT EXISTS writes   SCHEMALESS COMMENT 'routine -> field/address/buffer/global';
DEFINE TABLE IF NOT EXISTS calls    SCHEMALESS COMMENT 'routine -> routine';
DEFINE TABLE IF NOT EXISTS lives_at SCHEMALESS COMMENT 'field/global -> address';
DEFINE TABLE IF NOT EXISTS maps_to  SCHEMALESS COMMENT 'field/buffer -> dataformat';
DEFINE TABLE IF NOT EXISTS about    SCHEMALESS COMMENT 'finding -> any entity';
DEFINE TABLE IF NOT EXISTS cites    SCHEMALESS COMMENT 'finding/entity -> source';

-- ---- edge tables (NEW) -----------------------------------------------------
DEFINE TABLE IF NOT EXISTS has_field SCHEMALESS COMMENT 'struct -> field (this field lives in this struct)';
DEFINE TABLE IF NOT EXISTS instance_of SCHEMALESS COMMENT 'slot -> struct (this slot is an instance of this struct layout)';
DEFINE TABLE IF NOT EXISTS owns     SCHEMALESS COMMENT 'character -> animgroup / slot -> character (ownership)';
DEFINE TABLE IF NOT EXISTS part_of  SCHEMALESS COMMENT 'field/buffer -> region or struct -> region (containment)';
DEFINE TABLE IF NOT EXISTS confirms SCHEMALESS COMMENT 'source -> finding/field/routine (a source confirms an entity)';
