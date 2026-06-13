# Idea: Labeled Inspector + Live Edit

Every memory location carries its **label + what-it-does** (from `re_kb`); select an object and see its
**attached fields, decoded and labeled, with live values**; and — guarded — **edit a value live**. Status:
**idea**. Read side (label + value) is safe and near-term; write side (edit) is the gated **mod layer**.

## Two sides, one inspector — and they must stay distinct
- **READ (always safe, free):** resolve an address → its `re_kb` field → name, type, class, plain-English
  note; decode the bytes to a typed value; show it live. This is pure viewing (cardinal rule 4: read-only).
- **WRITE (gated, whitelisted, separate channel):** poke a new value into a SAFE field. This crosses the
  read-only line and is the existing **mod-layer RAM_WRITE** capability — never the read-only Oracle hook.

## 1. Labeling — from the knowledge graph
The labels already exist: `re_kb` `field` nodes carry `offset, owner, type, class(logical/engine/object)`
and a plain-English `note` ("what it is / does"); `routine` nodes note who reads/writes it. So:
- **Resolve** `addr → field` (char-struct offset, pool-node offset, global) → show `{name, type, class, note,
  readers/writers}`. The struct panel's `fieldAt()` is the stub; back it with the `re_kb` export.
- **Unknown = gray = the frontier.** A click-to-label action writes a stub `field` node + `note` to `re_kb`
  (the read-side knowledge loop — distinct from editing the value). The inspector *grows* the graph.

## 2. Attached fields + live values
Select an object (or hover a struct cell) → a **field list** for that struct, each row:
`+offset · name · type · value(decoded) · note`, value updating live per frame. Type-aware decode:
`u8/s8/u16/s16/u32/f32/flags`, plus enums where known (facing 0/1, char_id→name, sprite_id→pose). Group by
class: **logical** (player-driven, the interesting ones) / **engine** (the +0x154..184 pointer cluster —
shown but flagged "do not edit") / **object**. This is the click-to-decode preview's data twin.

## 3. Live edit — the guarded mod layer
Editing a value WRITES to SH4 RAM. The project already has the safe path for this (the **control WS
RAM_WRITE** / GameGenie mod-layer idea — health/assist/pose/skin pokes, no ROM patch). Rules:
- **Route via the control WS RAM_WRITE (`:7211`), NOT the Oracle hook.** The hook is read-only and must stay so.
- **Whitelist SAFE logical fields only:** health/red_health, pos_x/y, sprite_id (pose), palette/skin,
  meter, timer, facing. **HARD-BLOCK the engine-owned pointer cluster (+0x154..+0x184)** and any pointer —
  writing those corrupts the cell processor → `expEvn=0x180` crash (the state-injection dead-end). The
  inspector renders those rows read-only with a lock icon.
- **Opt-in "poke mode"** with a confirm; type-checked input (can't write a float as a u8); echo the wire
  RAM_WRITE so it's auditable.
- Use cases: set health, teleport, force a pose/sprite_id, hot-swap skin/palette, freeze the timer —
  i.e. a **training/mod surface** built on the same inspector. (See the mod-layer notes:
  assist remaps, point-char hot-swap, infinite-tag, frame-data overlay.)

## Why it composes with everything
It's the inspector layer under the linked view + click-to-decode: **label** (re_kb) → **value** (typed
decode) → **picture** (atlas render, IDEAS-CLICK-DECODE) → **poke** (mod-layer RAM_WRITE). One selected
address gives you what it is, what it holds, what it looks like, and (safely) lets you change it.

## Dependencies / risks
- **Labels** need the `re_kb` → client label-manifest export (the same one the memory-map semantic taxonomy
  needs). Build once, reuse.
- **Live values** need a per-frame read feed of the relevant ranges (the GSTA wire already carries the
  logical char fields; the field-resolution diff carries the rest).
- **Edit** is the only line-crossing piece: gated, whitelisted to logical fields, via the control WS, never
  the hook. Default OFF; the read inspector ships first and stands alone.
- READ inspector = safe, determinism-clean. WRITE = explicitly opt-in mod surface with the engine-cluster
  hard-block.
