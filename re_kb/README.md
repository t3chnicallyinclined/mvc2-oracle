# MapleCast RE Knowledge Graph (`re_kb`) — **MIRROR**

> **This directory is a MIRROR. The canonical graph lives in
> [`maplecast-flycast`](https://github.com/t3chnicallyinclined/maplecast-flycast)
> at `tools/re_kb/`.** Make changes there, then refresh this copy with
> `./scripts/sync-re-kb.sh` (`--check` reports drift without writing).
>
> It is vendored so this toolkit stays standalone — you can clone this repo
> alone and still query the RE knowledge — but it does NOT lead.
>
> It went stale silently once: on 2026-09-01 this directory held 16 of the
> canonical 89 seed files, frozen at 2026-06-13, while this README claimed to
> be "the canonical place RE findings live." Every shared file was
> byte-identical (no fork, ~69 files simply missing) and the numbering jumps
> 09 → 15 → 18, so nothing about the listing looked wrong. Run the sync check
> rather than trusting the directory.


A living, queryable index of all MVC2 / SH4 reverse-engineering knowledge —
memory addresses, character data, render routines, data formats, and findings —
with plain-English `note` fields, correctly linked, fed by the **five-source RE
workflow** (auto-memory, repo docs/`re-catalog`, anotak, marvelous2 disassembly,
live Frame Oracle) and UPSERT-updated as new findings land.

**The KB is the place RE findings live and get queried** — query it *before*
re-deriving anything, and record findings *after* any new confirmation.
Write through `kb.py` (`propose` / `confirm` / `rule_out` / `record_attempt`),
not raw SQL: `confirm()` requires a reproduction- or code-grade source, which
is what keeps the graph honest. Write to the CANONICAL copy, then re-sync here.

---

## Server

SurrealDB, local, RocksDB-backed:

```bash
surreal start --user root --pass root --bind 127.0.0.1:8001 rocksdb:re_kb_data/re_kb
```

- Endpoint: `http://127.0.0.1:8001/sql`  ·  ns=`re`  db=`kb`  ·  auth `root:root`
- Data dir `re_kb_data/` is **gitignored** (it is a rebuildable RocksDB store).
- The `*.surql` seed files in this folder ARE the committable, version-controlled
  source of truth — re-applying them rebuilds the graph.

## Helpers

```bash
# Bash
tools/re_kb/rekb.sh "SELECT name FROM character WHERE char_id='0x2C';"
echo "SELECT * FROM finding WHERE status='open';" | tools/re_kb/rekb.sh
tools/re_kb/rekb.sh @tools/re_kb/06_findings_sources.surql      # apply a file

# Windows
tools\re_kb\rekb.cmd "SELECT * FROM struct;"
tools\re_kb\rekb.cmd @tools\re_kb\02_char_struct.surql
```

Both prepend `USE NS re DB kb;` automatically. An arg beginning with `@` is passed
verbatim (file apply — those files carry their own `USE` line). Override the target
with `REKB_URL` / `REKB_AUTH`.

## Rebuild from scratch

Apply in order, then dedup edges (RELATE is **not** idempotent — see below):

```bash
for f in schema_seed 01_schema 02_char_struct 03_routines 04_memory_data \
         05_characters 06_findings_sources 08_emitter_render_model \
         09_facing_subgraph; do
  tools/re_kb/rekb.sh @tools/re_kb/$f.surql
done
tools/re_kb/rekb.sh @tools/re_kb/07_dedup_edges.surql
```

---

## The entity / edge model

### Node tables (every one has a `note` — plain-English "what it is/does")

| table | id convention | what it is |
|-------|---------------|------------|
| `routine` | `routine:loc_8cXXXXXX` | a marvelous2 SH4 routine (the label name == the PC). fields: `pc, bank, role, note` |
| `field` | `field:<name>` | a struct/semantic field. fields: `offset, owner, type, class(logical/engine/object), note` |
| `struct` | `struct:char_struct`, `struct:object_pool_node` | a RAM struct layout. fields: `base, stride, count, note` |
| `slot` | `slot:p1c1` … `slot:p2c3` | a concrete per-player char-struct instance. fields: `base, player, char_pos, note` |
| `character` | `character:plXX` (hex char_id) | a roster character. fields: `char_id, name, spl_file, atlas, note` |
| `animgroup` | `animgroup:plXX_gNN` | a per-char animation group (0x00–0x1B). fields: `char, group_id, note` |
| `global` | `global:<name>` | a global game-state RAM var. fields: `addr, type, note` |
| `buffer` | `buffer:<short>` | a memory region/buffer. fields: `addr, name, purpose, lifetime, note` |
| `region` | `region:<name>` | a named address range. fields: `lo, hi, note` |
| `dataformat` | `dataformat:<name>` | an anotak/engine record layout. fields: `size, layout, source_url, note` |
| `address` | `address:<name>` | a specific memory location. fields: `addr, kind, note` |
| `finding` | `finding:<slug>` | an RE fact. fields: `statement, status(confirmed/inferred/open/resolved), confidence, date` |
| `source` | `source:<slug>` | provenance. fields: `kind(marvelous2/anotak/oracle/memory/doc/recatalog), ref, note` |

### Edge tables (created via `RELATE in->edge->out`)

| edge | direction / meaning |
|------|---------------------|
| `reads` | routine → field/buffer/global (routine reads it) |
| `writes` | routine → field/buffer/global (routine writes it) |
| `calls` | routine → routine |
| `has_field` | struct → field |
| `instance_of` | slot → struct |
| `owns` | character → animgroup (and slot → character) |
| `lives_at` | field/global → address |
| `maps_to` | field/buffer → dataformat |
| `part_of` | field/buffer/struct → region (containment) |
| `about` | finding → any entity (what the finding concerns) |
| `cites` | finding/entity → source (provenance) |
| `confirms` | source → finding/entity |

> **EDGE GOTCHA — `RELATE` is NOT idempotent.** Re-running a seed file creates
> duplicate edge rows (you'll see the same neighbor twice in a traversal). After
> any reseed, run `07_dedup_edges.surql` (snapshots DISTINCT `(in,out)` pairs,
> wipes each edge table, RELATEs one back). Note: edges MUST be created with
> `RELATE` (it maintains the bidirectional graph refs) — a plain `CREATE` on an
> edge table stores `in`/`out` but the `->arrow->` traversal won't see it.

---

## Query patterns

```sql
-- graph traversal (the idiom): use ->edge->table.field
SELECT ->reads->field.name AS reads, ->calls->routine.label AS calls
  FROM routine:loc_8c0344d4;

-- reverse traversal: who reads/writes a field?
SELECT <-reads<-routine.label AS readers, <-writes<-routine.label AS writers
  FROM field:sprite_id;

-- filter by a derived field
SELECT offset, name, type FROM field
  WHERE owner='char_struct' AND class='engine' ORDER BY offset;

-- findings about an entity, with provenance
SELECT status, confidence, statement, ->cites->source.ref AS cited_by
  FROM finding WHERE ->about->struct CONTAINS struct:object_pool_node;

-- a struct's full field list
SELECT ->has_field->field.* FROM struct:char_struct;

-- what data format a field maps to + who reads it
SELECT name, layout, source_url, <-maps_to<-field.name AS fields
  FROM dataformat:gfx2_cell;
```

---

## The ORACLE-UPDATE recipe (how a new finding feeds the KB)

Whenever a Frame Oracle probe (or any new RE pass) confirms/changes something,
**UPSERT it into the KB by natural id** so the graph stays the single source of
truth. The recipe (all UPSERT/RELATE — safe, idempotent except RELATE):

1. **UPSERT the entity by natural id**, refining its `note`. Same id =
   update-in-place; new id = insert. Examples:
   ```sql
   UPSERT field:screen_x SET note='... (Oracle 2026-06-10: re-confirmed +0xE0 ...)';
   UPSERT routine:loc_8c03093c SET note='... per-frame, 150541 fires/22197-frame match ...';
   UPSERT buffer:dm00pool SET lifetime='compacts as poses cycle (moving TCW)';
   ```

2. **Add the Oracle source** (provenance = the probe config + the capture):
   ```sql
   UPSERT source:oracle_<slug> SET kind='oracle',
     ref='MAPLECAST_<PROBE>; capture <path/PC>; <regs read>',
     note='<one-line what the probe proved>';
   ```

3. **UPSERT or bump the finding** — set/raise `status` and `confidence`, set `date`:
   ```sql
   UPSERT finding:<slug> SET
     statement='<the reconciled fact>',
     status='confirmed',          -- inferred -> confirmed, or open -> resolved
     confidence='high', date='YYYY-MM-DD';
   ```

4. **Link it**: `about` → the entities it concerns, `cites` → every source that
   backs it (marvelous2 + anotak + the new Oracle source):
   ```sql
   RELATE finding:<slug>->about->field:screen_x;
   RELATE finding:<slug>->cites->source:oracle_<slug>;
   RELATE finding:<slug>->cites->source:marv_bank03;
   ```

5. **Dedup** after (RELATE adds rows): `tools/re_kb/rekb.sh @tools/re_kb/07_dedup_edges.surql`.

6. **Persist the SQL**: add the UPSERTs/RELATEs to the matching `NN_*.surql` file
   (or a new `08_*.surql`) and commit — the `.surql` files are the durable record;
   `re_kb_data/` is a rebuildable cache.

**Status / confidence conventions:** `confirmed` (PC+bank line, pl_mem/work
symbol, anotak URL, Oracle capture, or re-catalog entry) · `resolved` (a prior
conflict closed) · `inferred` (reasoned, not yet grounded — say what would confirm
it, usually an Oracle probe) · `open` (unresolved conflict — keep it loud).
Always `cites` the source class so a reader can tell CONFIRMED from INFERRED.

---

## Files

| file | contents |
|------|----------|
| `schema_seed.surql` | original seed (node/edge tables + the part-decode finding) |
| `01_schema.surql` | full schema: all node + edge tables (with `note` everywhere) |
| `02_char_struct.surql` | char_struct + all known fields + has_field edges + 6 slots |
| `03_routines.surql` | render-routine chain + anim/cell routines + reads/writes/calls |
| `04_memory_data.surql` | buffers, regions, globals, object_pool_node, dataformats |
| `05_characters.surql` | full 59-char roster (char_id↔name↔S_PLxx) + Ryu anim groups |
| `06_findings_sources.surql` | sources + key findings (status/confidence) + about/cites |
| `07_dedup_edges.surql` | collapse duplicate edges (run after any reseed) |
| `09_facing_subgraph.surql` | the FACING subgraph: setter `loc_8c0d97ee` (Facing_Update) --writes--> `field:facing` --reads--> render-gate (`loc_8c03453a`/`034548` neg r10, `0346c4` neg r8) + emitter + spawn cross-check; the `field_semantics_from_setter` PRINCIPLE finding (read the SET-site for a field's meaning); `contribution_candidate` tags for upstream marvelous2 |
| `08_emitter_render_model.surql` | off-SH4 emitter render model: MASTER `emitter_render_model` finding + all session sub-findings + validation gate + OPEN items, fully cross-linked |
| `rekb.sh` / `rekb.cmd` | query/apply helpers |
