# GSTA ↔ Memory ↔ Atlas Mapping — Verification Handoff

> **Goal:** make the state-only sprite client *complete and correct* by verifying that every
> GSTA/OBJS wire field maps to the right MVC2 memory address and the right atlas lookup.
> **Status (2026-06-05):** the map is ~90% verified; **one live capture** resolves the last
> three ambiguities, after which all remaining changes are safe mechanical edits.
> **Branch:** `feat/rom-asset-probe`.
>
> Read first: [MARVELOUS2-RE-HANDOFF.md](MARVELOUS2-RE-HANDOFF.md) (the disassembly findings
> this builds on), [MVC2-MEMORY-MAP.md](MVC2-MEMORY-MAP.md) (the merged ground-truth map),
> [re-catalog/00-README.md](../re-catalog/00-README.md) (object pool).

---

## 0. TL;DR for the next agent

1. The authoritative field map is in §1. Three fields are flagged ⚠️.
2. A capture probe is already built (§2) — `MAPLECAST_PTRDUMP=1`, read-only, prod-safe.
3. Run the capture (§3). It answers all three ⚠️ in one pass.
4. Apply the edits the capture dictates (§4 decision tree) — each is 1–30 lines.
5. Then the bigger build-out + spinoff ideas in §6 are unblocked.

---

## 1. The authoritative per-character GSTA map (38-byte block)

Server reads in `readGameState()` ([core/network/maplecast_gamestate.cpp:238](../core/network/maplecast_gamestate.cpp#L238))
with offsets from `OFF_*` constants (`gamestate.cpp:29-57`). Client parses in `onGSTA()`
([web/webgpu/sprite-client.mjs:189](../web/webgpu/sprite-client.mjs#L189)).

| wire off | client field | mem offset | marvelous2 label | drives | status |
|---|---|---|---|---|---|
| +0 | active | `0x000` | `active` | cull | ✅ |
| +1 | char_id | `0x001` | `charid0` | **atlas** `PL{cid:02X}` | ✅ |
| +2 | facing | **`0x110`** | `xflip_copy_2` (a COPY) | sprite flip | ⚠️ authoritative `xflip` = **`0x1D2`** |
| +3 | health | `0x420` | `health` | HUD | ✅ |
| +4 | red_health | `0x424` | `health2` | HUD | ✅ |
| +5 | special_move_id | `0x1E9` | `sp_move_id` | — | ✅ |
| +6 | assist_type | `0x4C9` | `assist_type` | — | ✅ |
| +7 | palette | **`0x52D`** | `pal_id` | (not applied) | ⚠️ live tint is **`0x25`** (`pl_palid_match`) |
| +8/+12 | pos_x/y | `0x34/0x38` | world pos | zoom | ✅ |
| +16/+20 | screen_x/y | `0xE0/0xE4` | screenspace | **draw pos** | ✅ |
| +24/+28 | vel_x/y | `0x5C/0x60` | velocity | prediction | ✅ |
| +32 | sprite_id | `0x144` | `sprite_id` | **atlas key** | ✅ |
| +34 | anim_state | `0x1D0` | move selector | — | ✅ |
| +36 | anim_timer | `0x142` | `frame_count` | — | ✅ |

**Atlas resolution chain (correct):** `char_id → loadChar()` fetches `PL{cid:02X}.{json,png}`
([sprite-client.mjs:149](../web/webgpu/sprite-client.mjs#L149)); `sprite_id → c.sprites[sid] =
{sx,sy,sw,sh,dx,dy,facing}`; drawn at `screen_x+dx, screen_y+dy`, flipped if `facing != sp.facing`.

**OBJS (pool) per-object — 7 bytes:** `cid(1) sprite_id(2 LE) x(i16) y(i16)`, parsed at
[sprite-client.mjs:115](../web/webgpu/sprite-client.mjs#L115); produced by `readObjects()`
([gamestate.cpp:213](../core/network/maplecast_gamestate.cpp#L213)). **Anchoring is the
unresolved item** (§2/§4).

---

## 2. The capture probe (already in the tree)

`MAPLECAST_PTRDUMP=1` → `ptrDump()` in [gamestate.cpp:92](../core/network/maplecast_gamestate.cpp#L92).
Read-only, env-gated, never runs in prod. Two relevant blocks were upgraded on 2026-06-05:

- **`[PTRDUMP] FACING` line** (per active char): logs `fac@0x110` vs `xflip@0x1D2` vs
  `walk@0x1D3` and `paleffect@0x40`. Resolves the facing-source + palette questions.
- **`[POOLV] anchor resolver`** ([gamestate.cpp:183](../core/network/maplecast_gamestate.cpp#L183)):
  for each owner-pointer object it prints **both** hypotheses —
  - **H1** (current code): `a` = record base → `sid@a+0x12C`, `scr@a+0xC8/0xCC`
  - **H2** (disasm): record base = `a−0x80` → `sid@(a−0x80)+0x12C`, `scr@…+0xC8/0xCC`
  - plus `ownerCopies@{…}` = every nearby offset where the owner value repeats.

---

## 3. The capture procedure (operator-driven — needs a live match)

```bash
# build the headless binary, then launch with the probe on:
MAPLECAST_PTRDUMP=1 ./build-headless/flycast    # your normal headless invocation
# In a match (Storm PL2A is ideal — known cape sids 731-763): walk left+right,
# TURN AROUND a few times, throw one special, then idle ~2s. Capture stdout.
```

Collect: the `[POOLV]` lines and the `[PTRDUMP] FACING` lines. (Per project norm, don't assume
someone is mid-match — coordinate before capturing.)

**What to look for:**
- **Pool anchor:** which of H1/H2 shows a `sid` in **731–763** (Storm cape) at a plausible
  `scr` near her position? That hypothesis is the true record layout.
- **Facing:** does `fac@0x110` ever differ from `xflip@0x1D2` across a turn-around? If yes,
  `0x110` is a lagging copy — wrong wire source.
- **Palette:** which of `color@0x25` / `palId@0x52D` / `paleffect@0x40` changes on skin
  select / hit-flash / super — that's the live-tint source to ship.

---

## 4. Decision tree — edits the capture dictates

**A. Pool anchoring**
- *If H1 wins* (sid 731–763 at `a+0x12C`): our `readObjects()` is already correct. Update
  [MVC2-MEMORY-MAP.md](MVC2-MEMORY-MAP.md) + [re-catalog/00-README.md](../re-catalog/00-README.md)
  to note the disasm's "owner@+0x80" is a *second copy*; our scan finds the record-start owner.
- *If H2 wins* (sid 731–763 at `(a−0x80)+0x12C`): rewrite `readObjects()` to set
  `rb = a − 0x80` and read `sid@rb+0x12C`, `scr@rb+0xC8/0xCC`, `category@rb+0x3`, `xflip@rb+0x130`,
  `owner@rb+0x80`. Re-seed the scan deterministically at `0x8C26AA54 + slot*0x1D0` (256 slots)
  rather than brute-scanning `0x8C26A600..0x8C278000`.

**B. Facing** — if `0x110 != 0x1D2` on turns: change `OFF_FACING` (`gamestate.cpp:37`) from
`0x110` to `0x1D2`. **No wire change** (still wire +2). Visual-verify a corner cross-up.

**C. Palette / live tint** — to render skins/super-glow on the sprite client: ship `0x25`
(`pl_palid_match`) and optionally `0x40` (`char_pal_effect`); apply via the `pal128` palette
technique the client already loads ([sprite-client.mjs:160](../web/webgpu/sprite-client.mjs#L160)).
This is a wire addition → see §5 (touches all 4 parsers).

---

## 5. Follow-on wiring (after the map is locked)

In priority order (from [MARVELOUS2-RE-HANDOFF.md §5](MARVELOUS2-RE-HANDOFF.md)):
1. **Pool reader** per §4-A + OBJS wire 7→9 bytes (add `category`, `xflip`); client layers by
   category (cape behind body, lightning/super in front) and blends additive for effect
   categories.
2. **Anisotropic scale** — replace constant `1.75` (`sprite-client.mjs:39`) with
   `CpsX=1.6667 / CpsY=2.1428` (separate `Sx/Sy`); no wire change, web-only.
3. **GSTA enrichment** — append `stance@0x1F9`, `Flight_Flag@0x201`, `anim_flags@0x14A`,
   `render_extra@0x151`, plus palette `0x25`/`0x40`. Append as a **trailing block** so the
   38-byte stride stays stable; bump `WIRE_SIZE` ([gamestate.h:80](../core/network/maplecast_gamestate.h#L80))
   and **update all four parsers together** (CLAUDE.md): `gamestate.cpp` serialize/deserialize,
   `sprite-client.mjs onGSTA`, `wasm_bridge.cpp`, `maplecast_wasm_bridge.cpp`.

**Constraints:** items 1–2 are read-only/client → no determinism risk. Item 3's wire bump is the
only "all parsers together" landmine. Run `MAPLECAST_DUMP_TA=1` once at phase end. Deploy via
`deploy-headless.sh` / `deploy-web.sh` only (backups); prod box `149.28.44.118`.

---

## 6. Other ideas this unlocks (reasoning included)

The disassembly + pool + codec + keyframe findings open more than the sprite client. Ranked by
value/effort:

**Quick spinoffs (days):**
- **Live hitbox / frame-data overlay from state.** We now have `hitbox_data@0x170`,
  `hitbox_pattern_table@0x16C`, `attack_data@0x174`, and the keyframe `HitboxGroup@+0x12`. The
  hitbox rip PNGs already exist (`hitbox_sprite/PL{hex}DAT/{sprite}-{hbgroup}.png`). Render boxes
  keyed on the live keyframe → a training/competitive tool, and it feeds
  [MATCH-DATA-PLATFORM.md](MATCH-DATA-PLATFORM.md). *Why now:* the keyframe→hitbox link is
  disasm-confirmed (`bank03.asm:11616`).
- **Full skin/tint on the state client.** `pl_palid_match@0x25` + `char_pal_effect@0x40` + the
  PVR bank formula ([SKIN-SYSTEM.md](SKIN-SYSTEM.md)) + the 5,202 community palettes → recolor
  the rip sprites client-side. *Why now:* palette source is being resolved in this same capture.
- **Predictive effect rendering (latency hiding).** `RenderExtra@0x151` + `EffectTrigger` (bit
  0x80 of the keyframe) tell the client an effect is *about to* spawn before the pool object
  appears. The client can pre-spawn the overlay → hides a frame of latency on supers/projectiles.

**Medium (1–2 weeks):**
- **Mechanize the per-char effect catalog for all 56 chars.** Today we hand-scrape anotak HTML
  for effect sprite_id ranges (Storm 731–763, etc.). Instead, parse each `PLxx_DAT` keyframe
  stream (now that the 20-byte layout is confirmed) and/or the `S_PLxx.asm` programs to
  auto-generate `re-catalog/PLxx-*.md` for the whole roster. *Why:* turns a per-character manual
  effort into a one-shot batch; the re-catalog becomes complete instead of Storm-only.
- **Symbol importer / drift guard.** A tiny tool that parses marvelous2's `#symbol` lines
  (`pl_mem.asm`/`work.asm`) into our `OFF_*` constants (or a shared JSON the C++ and JS both
  read). *Why:* keeps our reader in lockstep with the ground-truth disassembly and prevents the
  offset drift that caused the facing/palette bugs in the first place.

**Big bets (multi-cycle, high ceiling):**
- **Zero-copyrighted-assets atlas from the user's ROM.** Port the cracked LZSS codec
  (`bank03.asm:12740`) to a clean-room `web/webgpu/pldat-codec.mjs`, decode each character's
  sprites from the operator's own `PLxx_DAT`, feed `bake.mjs`. *Why:* the legal endgame — ship
  the ~15 KB/s state + zero pixels. Validate against the community rip oracle.
- **The killer end-to-end fidelity number.** Once pool + skins + effects render from state, run
  the P5 diff: state-client render vs the byte-perfect TA mirror, per-frame pixel match %. *Why:*
  proves (or bounds) the ~800× bandwidth claim with data, and tells us if a hybrid (strip
  characters server-side) is worth it ([ROM-ASSET-CLIENT-PLAN.md §1](ROM-ASSET-CLIENT-PLAN.md)).
- **Rollback / determinism leverage.** `RngVal@0x8C16BC2C` is now labeled. Feeding RNG state into
  the prediction client improves accuracy and is a prerequisite for any real rollback
  ([ROLLBACK-PREDICTION.md](ROLLBACK-PREDICTION.md)). *Why:* the one global we never had.
- **Contribute back → complete RE.** Our globals map + pool layout + RenderExtra table + skin
  system are net-new to marvelous2 (their README TODO is "Figure out memory / Label the code").
  A `memory/globals.asm` + `effects.md` PR makes their disassembly a near-complete gameplay RE
  and earns us their code-level ground truth in return. *Caveat:* addresses/semantics only, never
  our prod internals. (Full plan in [MARVELOUS2-RE-HANDOFF.md §6](MARVELOUS2-RE-HANDOFF.md).)

---

## 7. Open risk to respect
The pool anchoring is the *only* place our empirical reads and the disassembly conflict. **Do not
ship the `readObjects()` rewrite until the §3 capture confirms H1 vs H2.** Everything else in §1
is verified or disasm-grounded. The facing/palette edits are also gated on the same capture —
one match settles all three.
