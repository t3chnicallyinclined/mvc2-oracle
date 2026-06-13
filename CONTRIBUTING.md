# Contributing to MvC2 Oracle

## RULE #1 — NEVER commit anything ROM-derived

MVC2 and all Dreamcast/Naomi ROMs are **copyrighted**. Committing one (or anything
extracted from one) is a DMCA event and permanently pollutes git history.

**Never commit:**
- ROMs / disc images (`*.gdi *.cdi *.chd *.iso …`) — and never copy one into the working tree "to test."
- Savestates / NVRAM / cartridge saves (`*.state *.sav *.eeprom *.nvmem*`).
- **Anything decoded from a ROM**: atlases (`PLxx.json/.png`), part rips (`PLxx_parts.*`, `PLxx_asm.json`),
  palette extracts (`_idx.png/_lut.json`), texture/audio dumps, recorded captures (`oracle_capture*.bin`).

These live in the **gitignored** `assets/` and `captures/` dirs. They are produced **locally, from your own ROM**
(see "Bring your own ROM" in the README). The repo ships the *tools and loaders*, never the assets.

Before any `git add -A`, run `git status` and eyeball it. If you're unsure whether a file is ROM-derived,
the answer is **don't commit it**.

## Platform requirements

- **x86-64 Linux (or WSL2).** The Oracle hook injects into flycast's **x64 dynarec only** — there is no
  ARM64/interpreter path. The probes write to **`/dev/shm`** (Linux). Apple Silicon / native Windows cannot
  run the live hook; use WSL2, a Linux box, or the **recorded-capture** path (no emulator needed).
- A C++ toolchain + CMake (to build flycast + the hook), Python 3, Node.js (for the dashboard + transpiler harness),
  and SurrealDB (for the `re_kb` knowledge graph).

## The cardinal RE rule

Hook handlers are **READ-ONLY** w.r.t. guest state — read `Sh4cntx.r[]` + `addrspace::read*`, append to `/dev/shm`,
never write into SH4 RAM. Injecting partial state into a live SH4 crashes the engine (the bank12 cell processor
reads a corrupt pointer → illegal instruction). If you need to *change* behavior, that's a different architecture.
