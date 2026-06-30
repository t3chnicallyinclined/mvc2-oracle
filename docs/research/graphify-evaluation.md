# Graphify Evaluation — mvc2-oracle

**Date:** 2026-06-27  **Status:** Research / paused
**Tool:** [safishamsi/graphify](https://github.com/safishamsi/graphify) (MIT, by Safi Shamsi)

> One of 5 per-repo notes from the same research session. Siblings (same filename,
> `docs/research/graphify-evaluation.md`) live in: **GP2040-CE, maplecast-flycast,
> nobd-desktop, mvc2-skin-studio**. "Shared verdict" is identical across all five.

---

## What graphify is (1-paragraph)

CLI that turns folders of **code + docs + PDFs + data** into a queryable knowledge graph.
**AST tier** (tree-sitter, local, free) for code structure; **semantic tier** (LLM, your
API key, costs tokens) for doc/concept edges. Outputs `graph.json` (committable),
`graph.html`, `GRAPH_REPORT.md`, and an **MCP server**
(`python -m graphify.serve graph.json`). Edges tagged `EXTRACTED`/`INFERRED`/`AMBIGUOUS`.
Install: `uv tool install graphifyy` then `graphify install`.

---

## This repo's assessment

**This repo IS the reason the shared verdict says "do not duplicate `re_kb`."** Its
`re_kb/` is a 16-file SurrealQL knowledge graph (~400 nodes, ~800 edges): char_struct +
60 fields, render/anim routines (bank03/04/05 PCs), object-pool nodes, full 59-char
roster, findings with `cites` edges to marvelous2 / anotak / live Oracle and
`CONFIRMED`/`INFERRED` status. **Knowledge here is *already* a graph** — it just lacks an
LLM query layer + web UI (currently `rekb.sh` CLI only).

**Therefore graphify is the wrong tool for the RE facts** — its inferred edges would be
lower-confidence than these curated, source-cited facts. Do not point it at `re_kb`,
`extern/`, or the disasm to "learn the memory map."

**Narrow places graphify could help (docs/onboarding only):**
- 45 markdown docs (MVC2-MEMORY-MAP.md, MVC2-FRAMEDATA-FIELDS.md, FRAME-ORACLE-SPEC.md,
  re-catalog/, ASSEMBLY-DRIVEN-DESIGN.md, GFX-NOTES, PLAN.md) — semantic-tier target for
  faster contributor onboarding.
- Cross-repo shared-vocabulary view with mvc2-skin-studio / mvc2-skin-processor /
  maplecast-flycast (GFX1/GFX2, twiddle/LZSS, palette banks, PLxx IDs).

**Better long-term play than graphify:** give `re_kb` itself the missing query
layer/MCP. graphify's *MCP-serve* idea is the inspiration; the *graph* already exists and
shouldn't be rebuilt. If anything, **export `re_kb` as a source** into a docs-only
graphify graph — never the reverse.

**Scope:** exclude `extern/flycast/` (vendored), `re_kb/ingest/cache/` (100+MB staging),
node_modules, captures.

---

## Shared verdict (identical across all 5 repos)

| Constellation | Repos | Existing graph? | Verdict |
|---|---|---|---|
| **NOBD input-timing** | GP2040-CE, nobd-desktop, nobd-research, nobd-website, maplecast input-latch | **None** | **Strongest, cleanest win** |
| **MVC2 reverse-engineering** | **mvc2-oracle**, maplecast-flycast, mvc2-skin-studio, mvc2-skin-processor | **Yes — SurrealDB `re_kb`** | **Complement only — do NOT duplicate `re_kb`** |

**Risks:** yet-another-store risk is highest *here* (re_kb is the crown jewel — protect
it); scale blast radius (exclude extern/ + ingest cache); AST code-graph value modest.

**Overall:** the NOBD constellation is where graphify earns adoption. Here, prefer
investing in a query/MCP layer **on top of `re_kb`** over a parallel graphify graph.

---

## Where we left off / next steps

1. Pilot on **nobd-desktop** first.
2. GP2040-CE docs only.
3. Cross-repo **NOBD** graph + MCP ← unique-value artifact.
4. MVC2 docs-only, scoped. For this repo specifically, evaluate giving **`re_kb` an
   MCP/query layer directly** as the higher-ROI alternative to a graphify copy.
5. Decide MCP-first after steps 1–2.

**Nothing installed/run yet.** Prereqs: `uv` + Python 3.10+.
