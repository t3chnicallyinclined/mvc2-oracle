# MvC2 Oracle

A standalone toolkit + live dashboard for **reverse-engineering Marvel vs Capcom 2** on the
Sega Naomi / Dreamcast (SH4). It bundles the Oracle hook (a READ-ONLY JIT probe into flycast),
the RE knowledge graph, the decode/rip tools, and a frame-by-frame visual RE dashboard.

> **You bring your own ROM.** Nothing ROM-derived ships in this repo. Point the setup at your own
> legally-owned MVC2 image and it pulls everything it needs — decoded sprites, parts, palettes,
> the assembly recipe — into your local (gitignored) `assets/`. See **Bring your own ROM** below.

---

## What's in here

| Dir | What |
|-----|------|
| `extern/flycast/` | flycast emulator — **git submodule**, pinned to the MapleCast fork (x64). |
| `hook/` | The Oracle hook (`maplecast_oracle_hook.*`) — tracked here, applied into the submodule. |
| `patch/` | The two dynarec injection edits (`rec_x64.cpp`, `decoder.cpp`) as a patch set. |
| `scripts/` | `apply-hook.sh`, `build-headless.sh`, `setup-from-rom.sh`, `capture.sh`, `oracle-tail-ws.py`. |
| `re_kb/` | The RE knowledge graph (SurrealDB seeds + `rekb.sh` + the cached anotak corpus). |
| `tools/` | The decode/rip/validate tools + the SH4→C transpiler harness (`render-replica-poc/`). |
| `web/` | The **dashboard** (`dashboard.html` + `panels/`) and the reused renderers (`webgpu/`). |
| `docs/` | The RE knowledge (memory map, GFX notes, Frame-Oracle spec, `re-catalog/`). |
| `assets/`, `captures/` | **gitignored** — your locally-decoded ROM assets and recorded captures. |

---

## The Oracle hook + the probe family

The hook is a compile-time block-entry `GenCall` injected into flycast's x64 dynarec. It is
**READ-ONLY** (reads `Sh4cntx.r[]` + guest RAM, appends to `/dev/shm`), determinism-safe, and
**default OFF** — flycast stays byte-stock unless you set a probe env var. The probes:

| Probe | Env var | Hooks | Output | What it gives you |
|-------|---------|-------|--------|-------------------|
| **ASMTRACE** | `MAPLECAST_ASMTRACE` | PC `0x8C034864` (per-part convergence in the body walker `loc_8c0344d4`) | `/dev/shm/mc_assembly.log` — one line/part: `frame sid slot cid sel dx dy accX accY screenX screenY pal row flip` | **THE per-part sprite-assembly GROUND TRUTH** — the engine's own cumulative pen + final screen X/Y. The thing the geometry gate validates against. |
| BODYCAP | `MAPLECAST_BODYCAP` | same PC `0x8C034864` | `PLxx_part_*.ppm` | decoded body-part **pixels**, keyed by the +6 render selector |
| CHARQ | `MAPLECAST_CHARQ_RENDER` | `0x8C1248CC` + `0x8C034864` | `mc_charq_render.jsonl` | the per-part **PVR sprite quad** (screen corners + UV) live |
| Frame Oracle | `MAPLECAST_FRAME_ORACLE_HOOK` | `0x8C03093C`/`0x8C030AF8` | `mc_oracle_hook.jsonl` | per-frame per-object screen anchors + objects + blend |
| Generic probe | `MAPLECAST_ORACLE_PROBE` | up to 16 PCs, **live-reloadable** | `mc_probe.log` | config-driven register/RAM reads with **no rebuild** |

ASMTRACE is the headline. It confirmed the emitter render model; it's the per-part truth the
dashboard's DIFF overlay and `tools/validate_emitter_geom.py` measure against.

---

## Quickstart

### Path A — no emulator (see something in 60 seconds)
The dashboard runs against a **recorded capture** (a `.bin` carrying TA frames + GSTA/OBJS/WATCH +
an ASMTRACE slice). A capture is ROM-derived (gitignored), so it's hand-delivered, not committed.
```bash
cd web && python3 -m http.server
# open http://localhost:8000/dashboard.html  → it auto-loads captures/oracle_capture.bin
# pause / step / scrub frames; DIFF overlay, struct inspector, WATCH diff, ASMTRACE pen overlay
```

### Path A2 — Real sprites, fast (fetch decoded atlases from prod)
The full roster was baked offline-from-disc and lives on prod. Pull the decoded atlases (READ-ONLY,
gitignored, never committed) and the dashboard renders real animated sprites — no local decode:
```bash
./scripts/fetch-prod-atlases.sh            # 6 demo chars (or: all / PLxx …)
# open web/dashboard.html → click a character → pick a group/sub-anim → ▶ plays REAL frames
```

### Path B — Bring your own ROM (the full setup)
You supply a legally-owned MVC2 image; the setup decodes everything from it locally.
```bash
# 1. Point at YOUR rom — it MUST live OUTSIDE this repo (never copied in).
export MVC2_ROM=/opt/mvc2/mvc2.gdi

# 2. One-shot setup: build flycast+hook, run the decode probes against YOUR rom,
#    pack the decoded sprites/parts/palettes into ./assets (gitignored), seed re_kb,
#    and produce a recorded capture for the dashboard.
./scripts/setup-from-rom.sh

# 3. Capture loop (the RE hello-world): the per-part assembly ground truth
./scripts/capture.sh "$MVC2_ROM" asmtrace
tail -f /dev/shm/mc_assembly.log
```

`setup-from-rom.sh` refuses to run if `$MVC2_ROM` points inside the repo, and writes only into the
gitignored `assets/` and `captures/`. Nothing ROM-derived is ever staged for commit.

---

## The five-source RE workflow

When answering any RE question, consult cheapest/already-known first, runtime-confirmation last:
**(a)** `re_kb` graph + docs → **(b)** in-repo decoded data → **(c)** anotak data semantics →
**(d)** the marvelous2 disassembly (authoritative on layout) → **(e)** the live Oracle/ASMTRACE
(the runtime ground-truth tiebreaker). See `docs/PLAN.md` and `docs/` for the full knowledge base.

## Platform
x86-64 Linux or WSL2 (the hook is x64-dynarec-only; probes write to `/dev/shm`). See `CONTRIBUTING.md`.
