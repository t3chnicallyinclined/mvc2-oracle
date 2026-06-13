# re_kb/ — the MVC2 RE knowledge graph

Phase 1 copies `tools/re_kb/` from the MapleCast repo: the SurrealDB seeds (`*.surql`), the helper
(`rekb.sh`/`rekb.cmd`), the README, and the `ingest/` pipeline (incl. the cached anotak corpus).

Rebuild locally (the `re_kb_data/` store is gitignored):
```bash
surreal start --user root --pass root --bind 127.0.0.1:8001 rocksdb:re_kb_data/re_kb &
for f in schema_seed 01_schema 02_char_struct 03_routines 04_memory_data 05_characters \
         06_findings_sources 08_emitter_render_model 09_facing_subgraph; do
  ./rekb.sh @$f.surql; done
./rekb.sh @07_dedup_edges.surql   # RELATE is not idempotent — run dedup LAST
```
Query example: `./rekb.sh "SELECT pc,note FROM routine:loc_8c0344d4;"`
