# MVC2 Frame-Data Fields — anotak ↔ marvelous2 Cross-Reference

**The authoritative map** linking every anotak attack field and every anotak animation field
to its byte offset, the `marvelous2` SH4 routine that reads/writes it, its gameplay meaning, and
(where the disassembly settles it) the identity of each anotak `unkNN`.

Three layers are cross-referenced for every row:

1. **anotak** — the per-character DAT dumps (value dictionaries). Index pages:
   - Attack fields: <https://zachd.com/mvc2/data/anotak/possible.html>
   - Animation fields: <https://zachd.com/mvc2/data/anotak/possible_anim.html>
   - Crawled into this repo: `refs/anotak/fields/attack/*.json`, `refs/anotak/fields/anim/*.json`,
     `refs/anotak/attacks/PLxx.json`.
2. **marvelous2** — hand-labelled SH4 disassembly (mountainmanjed). Every `loc_8cXXXXXX:` label name
   **is** the SH4 PC. Raw files:
   - <https://raw.githubusercontent.com/mountainmanjed/marvelous2/master/memory/pl_mem.asm>
   - <https://raw.githubusercontent.com/mountainmanjed/marvelous2/master/memory/work.asm>
   - <https://raw.githubusercontent.com/mountainmanjed/marvelous2/master/build/bank03.asm>
   - <https://raw.githubusercontent.com/mountainmanjed/marvelous2/master/build/bank04.asm>
   - <https://raw.githubusercontent.com/mountainmanjed/marvelous2/master/build/bank05.asm>
   (Fetched copies live in `refs/marvelous2/`.)
3. **in-repo decoded data** — `atlas/chars/PLxx.json/.png` (sprite_id → quad), the wire fields we
   already ship (`sprite_id`, `screen_x/y`, `facing`, `palette`).

Legend for the "unk-resolved?" column: **CONFIRMED** = identified from the disassembly read site;
**inferred** = offset/meaning derived from the anchor layout + anotak dictionary, not yet pinned to
a read instruction; **still unknown** = neither the disassembly examined here nor anotak names it.

---

## 1. Per-character struct anchors (from `pl_mem.asm`)

| player offset | symbol | width | relevance |
|---|---|---|---|
| `+0x0142` | `frame_count` / `anim_timer` | u16 | **= cell Duration** (engine-decremented countdown) |
| `+0x0144` | `sprite_id` | u16 | **= cell Sprite** — the atlas key the renderer consumes |
| `+0x0148`–`+0x014c` | (copied cell bytes) | — | `0x140 + cell_offset` after the per-frame 20-byte copy |
| `+0x014a` | `anim_flags` | u8 | **= cell ProximityBlock** (see §3) |
| `+0x014c` | (effect-trigger byte) | u8 | **= cell EffectTrigger** → spawns effect (see §3) |
| `+0x0154` | `current_cell_data` | ptr | base of the 20-byte animation cell walk |
| `+0x0158` | `anim_id`/`anim_group` | u8 | group 0x00–0x1B |
| `+0x0168` | `animations` | ptr | base of per-char anim/cell table |
| `+0x016c` | `hitbox_pattern_table` | ptr | indexed by cell HitboxGroup |
| `+0x0170` | `hitbox_data` | ptr | resolved hitbox geometry |
| `+0x0174` | `attack_data` | ptr | **base of the attack record table** (stride 0x1C) |
| `+0x01a1` | `attack_data_index` | u8 | which attack record to activate |
| `+0x01bc` | (active attack-record ptr) | ptr | `attack_data + index×0x1C`, cached on hit (see §2) |
| `+0x01c0` | `hitbox_group_index` | u8 | written from cell HitboxGroup×16 + pattern table |
| `+0x0420` | `health` | u16 | Damage is subtracted from here |
| `+0x01e1` | `undizzy` / reset timer | u8 | dizzy accumulator (cell/attack Undizzy feeds it) |

---

## 2. Attack record — base, stride, and pointer computation (CONFIRMED)

The attack record is **0x1C (28) bytes**. On a connecting hit, `marvelous2` computes the active
record pointer in **`loc_8c059384` (bank05, ~line 23702)**:

```
mov  0x1C,r3                ; record stride = 28 bytes      <-- confirms 0x1C
mov.w @(...=0x0174),r2      ; r2 = attack_data offset
and  0x7F,r0               ; r0 = attack index (masked 0x7F)
mul.l r3,r0                ; index × 0x1C
mov.l @r2,r2               ; r2 = attack_data base (player+0x174 dereferenced)
add  r2,r0                ; r0 = &record  =  attack_data + index×0x1C
mov.l r0,@r1              ; cache to player+0x1bc
```

Thereafter the hit pipeline reads individual fields off the cached pointer at **player+0x1bc**
(20+ read sites in bank05). Every field offset below is relative to this record base.

### Attack-field table

| Field | Offset | marvelous2 read site (bank:loc) | Meaning | unk-resolved? |
|---|---|---|---|---|
| **Damage** | `0x00` | bank05 `loc_8c056454` (~16282/16296): `mov.b @r13` → fed to `Damage_Calc`, result `sub`ed from `health` (player+0x420). Also bank05 `loc_8c057718` (~19281) block/chip path. | Hit damage (pre-scaling). anotak values 1–200; the disasm compares to `0x0D` as a high/low branch. | n/a (named) |
| **HitReaction** | `0x01` | bank05 `loc_8c0586a2` (~21756): `mov.b @(0x1,r4); tst 0x40`. | Victim reaction class / flags. **bit 0x40 = AirAttackHitstun** (matches anotak `AirAttackHitstun=0x40`); low values are enumerated states (`RegularHitstun=0x00`, `FlipReset=0x01`, `QuickBackKD=0x02`, `SweepKD=0x04`, …). | n/a (named) |
| **BlockFlags** | `0x02` | bank05 `loc_8c056920` (~16024): `mov.b @(0x2,r13); tst 0x08`; `and 0x0F` for block dir. bank05 `loc_8c056f2e` (~18012): `tst 0x20/0x40/0x10` chip bits. bank05 `loc_8c057718` (~19296): `tst 0xB0`. | Block requirements + chip behaviour. **0x02 BlockHigh, 0x04 BlockLow, 0x08 Unblockable, 0x10 ChipDamageA, 0x20 ChipDamageB(no meter), 0x40 throw-related, 0x80 ChipDamageC** (all per anotak, bits exercised in disasm). | n/a (named) |
| **HitstunOrPushback??** | `0x03` | bank05 `loc_8c056454` (~16265): `mov.b @(0x3,r13)` → player+0x231. bank05 `loc_8c056b6e` (~17431): `mov 0x03; and 0x70` selects KD reaction (0x20→state 0x0E, 0x10→state 0x0B). | Hitstun/pushback magnitude; **high nibble (0x70) also encodes a knockdown sub-class.** | n/a (named) |
| **DamageType** | `0x04` | not pinned in the routines examined; anotak enumerates it (`Normal`, …) on `PLxx_DAT_atk`. | Damage category (Normal / projectile / throw-class). | inferred (offset from anchor layout) |
| **Undizzy** | `0x05` | not pinned to a single read here; the dizzy accumulator lives at player+0x1e1 (`loc_8c05666c`/`loc_8c059914` dizzy path). | Dizzy/stun build-up contributed by this hit. anotak values 1,2,4,6,8,10,12. | inferred |
| **unk06** | `0x06` | not read in examined hit routines. | anotak: clustered 0x0A/0x10/0x14/0x18/0x1E — looks like a **frame/time count** (pushback or stun duration). | **still unknown** (likely a duration; not yet pinned) |
| **Hitstop** | `0x07` | not pinned to a read here; hit-freeze is applied in the bank03 hit-pause path. | Hit-stop / freeze frames on contact. anotak strongly peaks at 10 (0x0A). | inferred |
| **KDDuration** | `0x08` | bank05 `loc_8c056b6e` (~17397): `mov.b @(0x8,r4)` → player+0x22e; bank05 `loc_8c0566ae` (~16613): `mov.b @(0x8,r13)`; bank05 `loc_8c0578c0` (~19526): `mov.b @(0x8,r13)` reused for spark placement. | Knockdown duration / juggle reaction timer. | n/a (named) — read CONFIRMED |
| **JuggleX** | `0x09` | bank05 `loc_8c056b6e` (~17412): `mov.b @(0x9,r4)` → player+0x22f; bank05 `loc_8c0566c8` (~16628): `mov.b @(0x9,r13)`. | Horizontal juggle / launch component. | n/a (named) — read CONFIRMED |
| **JuggleY** | (see note) | — | Vertical juggle/launch component. **Conflict:** anotak lists JuggleY as a distinct column, but offsets 0x08/0x09 are taken by KDDuration/JuggleX and 0x0a by `unkFlags0a`. Either JuggleY shares the 0x08/0x09 reaction pair (anotak split one record byte into X/Y views) or its true offset differs from the naive list order. **Surfaced, not resolved.** | conflict — see note |
| **unkFlags0a** | `0x0a` | not read in examined routines. | anotak: high-bit flags (0x40/0x60/0x70/0x80/0x90/0xC0). A second flag byte (proration / hit-property bits). | **still unknown** (flag byte) |
| **Hitspark** | `0x0b` | bank05 `loc_8c0578c0` (~19520): `mov.b @(0xB,r13); cmp/pz` → effect type → `bank0f.loc_8c0fd966` (effect spawn into the shared **Effect Poly** buffer `0x0CED0000`, see `work.asm`). | Hitspark / impact-effect **type** (`Light=0`, `Medium=1`, `Heavy=2`, `Special=3`, `Laser*`, `Slash*`). Ties into the effects-atlas work. | n/a (named) — read CONFIRMED |
| **unk0c** | `0x0c` | not read in examined routines. | anotak: dominated by 4/8/12 (0x04/0x08/0x0C). Looks like a small **strength/level enum** (light/med/heavy ≈ 4/8/12). | **still unknown** (probable strength enum) |
| **ImpactSound** | `0x0d` | sound is dispatched in the hit-effect path alongside Hitspark (`loc_8c0578c0` region → `bank04.loc_8c04223a`). | Impact SFX id (anotak `ImpactSound`). | inferred (offset from layout) |
| **unk0e** | `0x0e` | bank05 `loc_8c056f2e` (~18016): `mov.b @(0xE,r14); and 0x3F` used as the **chip-damage magnitude** when BlockFlags chip bits are set. | **CHIP DAMAGE value (6-bit, masked 0x3F)** applied on block. | **CONFIRMED = chip-damage amount** |
| **unk0f** | `0x0f` | not read in examined routines. | anotak: 20/40/50/60/90/100 — looks like a **meter/percent value** (build or scaling). | **still unknown** (probable meter/scale) |
| **unk10** | `0x10` | not read in examined routines. | anotak: very wide spread (0x06–0xFF) — looks like an **index/id** (sub-table or sound/effect variant). | **still unknown** (wide id) |
| **unk11** | `0x11` | not read in examined routines. | anotak: wide spread — pairs with unk10 (a second id byte). | **still unknown** (wide id) |
| **flags** | `0x12` | bank05 `loc_8c056454` (~16342): `mov 0x12; mov.b @(r0,r13); tst 0x20` (CantKill). bank05 `loc_8c0578c0` (~19545): `tst 0x40` (Launcher). | Attack-property flags. **0x04 NoYBoost, 0x08 IgnoresDamageScaling, 0x10 NoComboCount, 0x20 CantKill, 0x40 Launcher, 0x80 FlyingScreenTrigger** (anotak; 0x20 & 0x40 exercised in disasm). | n/a (named) — read CONFIRMED |
| **unk13** | `0x13` | not read in examined routines. | anotak: **always 1** for every entry → a constant/terminator or "record valid" marker. | inferred = constant `0x01` marker |
| **unk14** | `0x14` | bank05 `loc_8c056b6e` (~17419): `mov 0x14; mov.b @(r0,r4)` — if nonzero forces reaction state `0x12` (a special capture/OTG reaction). | **A reaction-override flag** (rarely set: anotak shows only values 1 & 16). | **CONFIRMED = reaction-override (forces state 0x12)** |
| **unk15** | `0x15` | not read in examined routines. | anotak: small ints 1–0x37 — possibly a secondary timer/index. | **still unknown** |
| **InvincibilityTime** | `0x16` | not pinned to a read here; anotak names it. | I-frames granted by this attack (anotak `InvincibilityTime`, sparse: 1,2,3,8,10,12,32). | inferred |
| **unk17** | `0x17` | not read in examined routines. | anotak: 0x10–0x3C, sparse — a small **duration**. | **still unknown** |
| **unk18** | `0x18` | not read in examined routines. | anotak: 2–0x14, sparse — small **duration/count**. | **still unknown** |
| **unk19** | `0x19` | not read in examined routines. | anotak: 1–8, common — a small **enum/level**. | **still unknown** |
| **unk1a** | `0x1a` | — | anotak table **empty** (all zero across all chars). | likely **padding** (last meaningful byte of the 0x1C record region is ≤0x19) |
| **unk1b** | `0x1b` | — | anotak table **empty**. | likely **padding** |
| **unk1c** | `0x1c` | — | anotak table **empty**; `0x1c` is the first byte of the *next* record (stride is 0x1C). | **out of record** — confirms the 28-byte stride |

**Note on JuggleY / the 0x08–0x0a region.** The disassembly unambiguously reads `record+0x08` and
`record+0x09` as the knockdown/juggle reaction pair (`loc_8c056b6e`, `loc_8c0566ae/8c0566c8`) and
`record+0x0a` is never read as a juggle value. anotak's column *order* (…KDDuration, JuggleX,
JuggleY, unkFlags0a…) therefore does **not** map 1:1 onto consecutive bytes here; treat the
disassembly offsets (KDDuration=0x08, JuggleX=0x09) as authoritative and JuggleY as either a derived
view of the same reaction pair or a mislabelled column. Do not assume JuggleY=0x0a.

---

## 3. Animation cell — base, stride, and the per-frame walk (CONFIRMED)

The animation **cell is 0x14 (20) bytes**. `current_cell_data` (player+0x154) points at the current
cell; the engine copies the whole 20-byte cell to **player+0x140** each keyframe, so
**`player[0x140 + N] == cell[N]`**. Two routines drive it (both bank03):

- **`loc_8c034dee` — anim tick** (~line 11567). Decrements the Duration countdown at player+0x142;
  when it underflows it advances `current_cell_data += 0x14` (`loc_8c034e02`), re-checks the Ender
  bit, copies the new 20 bytes via `bank12.loc_8c1294c8` (r0=0x14), then re-derives HitboxGroup and
  the effect trigger.
- **`loc_8c034e8c` — load animation** (~line 11669). R4=player, R5=group, R6=anim id →
  `current_cell_data = animations(0x168) + group/anim offset`; same copy + HitboxGroup + effect logic.

Read sites proven inside these routines (data-label addresses are in the `loc_8c034e70…` /
`loc_8c034f3a…` literal pools):

- player+0x142 (`#data 0x0142`) — Duration countdown.
- player+0x154 (`#data 0x0154`) — cell pointer, `add 0x14` advance.
- player+0x143 — Ender: `add 0xEF` (→0x143), `and 0x80` end-of-anim bit.
- player+0x140 (`#data 0x0140`) — 20-byte copy destination, `mov 0x14` length.
- `mov.w @(0x12,r1)` — **HitboxGroup at cell+0x12**, `shll2 shll2` (×16), `add` hitbox_pattern_table
  (player+0x16c), store to player+0x1c0 (`hitbox_group_index`).
- player+0x14c (`#data 0x014c`) — effect trigger: if nonzero `jsr/jmp bank04.loc_8c042014`.

### Animation-field table

| Field | Offset | marvelous2 read site (bank:loc) | Meaning | unk-resolved? |
|---|---|---|---|---|
| **AnimFlags** | `0x00` | copied to player+0x140 by `loc_8c034dee`; flag byte. | Per-cell flags. **0x80 ContinuesThroughHitstop** (anotak); 0x01/0x02/0x04/0x08/0x10/0x20/0x40 are per-char flags. Distinct from the `anim_flags` byte at cell+0x0a. | n/a (named) |
| **EffectTrigger** | `0x01` (anotak list) / **effective trigger = cell+0x0c** | the *engine* effect dispatch reads **player+0x14c = cell+0x0c** in `bank04.loc_8c042014` (`#data 0x014c`, ~line 4520). | Per-cell effect spawn. **Conflict:** anotak labels cell+0x01 "EffectTrigger" and cell+0x0c "SoundFX", but the disassembly proves the byte that actually drives the effect spawner is **cell+0x0c** (value <0x40 → effect class A via `loc_8c041f5c`; ≥0x40, +0x80 ≤0x50 → class B via `loc_8c04223a`). Treat **cell+0x0c** as the real effect/hitspark trigger; cell+0x01 is a separate (still-unread) trigger byte. | partial — trigger byte CONFIRMED at 0x0c |
| **Duration** | `0x02` | `loc_8c034dee` (~11568): loaded into the player+0x142 countdown; `add 0xFF` decrement. | Frames this cell is shown (the `anim_timer`). Value 0xFF = special/hold. | n/a (named) — CONFIRMED |
| **Ender** | `0x03` | `loc_8c034dee` (~11584): `and 0x80` on player+0x143. | End-of-animation marker. **0x80 = last cell** (anotak: 14 642 entries are 0x80). | n/a (named) — CONFIRMED |
| **Sprite** | `0x04` (u16, 0x04–0x05) | `loc_8c034dee`: copied to player+0x144 = `sprite_id`. | **The atlas key** — drives `atlas/chars/PLxx.json` lookup. u16 (occupies 0x04–0x05, which is why there is no `unk05`). | n/a (named) — CONFIRMED, and this is the field the renderer consumes |
| **unk06** | `0x06` | copied to player+0x146; not separately read in tick. | anotak: **only value 0xFF** across all chars → constant / high byte of the 0x04 sprite word, or an unused/sentinel byte. | inferred = constant `0xFF` (likely pads the sprite field) |
| **unk07** | `0x07` | copied to player+0x147. | anotak: **only value 0xFF** → same as unk06 (constant/pad). | inferred = constant `0xFF` (pad) |
| **AirborneLaunchAngle** | `0x08` | copied to player+0x148; consumed by the airborne-motion path. | Launch/airborne **angle**. anotak: dominated by 0x80 (neutral), with 0x90/0xA0/0xB0/0xC0 etc. | n/a (named) |
| **AirborneLaunchSpeed** | `0x09` | copied to player+0x149. | Launch/airborne **speed**. anotak: dominated by 0x20. | n/a (named) |
| **ProximityBlock** | `0x0a` | **= player+0x14a `anim_flags`** (`pl_mem.asm` line 115: "inherits from 0x10 of animation structs"; read across the block/cancel logic). | **Block/cancel-window flags.** Per `pl_mem.asm`: **0x80 = opponent can proximity-block, 0x40 = recovery frames, 0x20 = can't special/super-cancel or call assist.** anotak's "ProximityBlock" column is exactly this byte. | n/a (named) — **identity CONFIRMED (= `anim_flags` @0x14a)** |
| **unk0b** | `0x0b` | copied to player+0x14b. | anotak: wide value spread — a small **id/param** (per-cell). | **still unknown** |
| **SoundFX** | `0x0c` (anotak) / **= effect-trigger byte** | reached as player+0x14c by `bank04.loc_8c042014` (see EffectTrigger row). | anotak calls cell+0x0c "SoundFX", but the disassembly shows this byte drives the **effect/hitspark spawner** (which also emits the associated sound). So cell+0x0c is the combined **effect-trigger** (and its SFX). | CONFIRMED offset; **anotak label "SoundFX" is really the effect trigger** |
| **unk0d** | `0x0d` | copied to player+0x14d. | anotak: small ints 1–0x14 — a **count/sub-index**. | **still unknown** |
| **unk0e** | `0x0e` | copied to player+0x14e. | anotak: only 0x40 / 0x80 (2–3 chars) → a rare flag bit. | **still unknown** (rare flag) |
| **unk0f** | `0x0f` | copied to player+0x14f. | anotak: small ints; one char uses 0x06/0x08 heavily → a per-char param. | **still unknown** |
| **unk10** | `0x10` | copied to player+0x150. | anotak: very wide spread → an **id/param**. NB: not the same as the cell+0x0a "0x10 inherits" comment (that comment refers to anim-struct offset 0x10, i.e. this byte, feeding `anim_flags`). | **still unknown** — but **note `pl_mem.asm` ties cell-struct +0x10 to `anim_flags`**; reconcile against the +0x0a finding before trusting either label |
| **RenderExtra** | `0x11` | copied to player+0x151; consumed by the sprite-assembly/EXTRAS path. | Selects extra render layers / OAM-extras behaviour (ties into `Sprite_Extras` player+0x178 and the `loc_8c033e90` quad emitter). anotak: 1/2/3… enumerated. | n/a (named) |
| **HitboxGroup** | `0x12` (u16) | `loc_8c034dee` (~11616): `mov.w @(0x12,r1)`, ×16, + hitbox_pattern_table (0x16c) → player+0x1c0. | **Selects the hitbox pattern** for this cell. Drives hitbox_data (player+0x170). | n/a (named) — CONFIRMED |
| **unk14** | `0x14` | `0x14` is the first byte of the *next* cell (stride 0x14). | anotak table **empty** → confirms the 20-byte cell stride; not a real field. | **out of cell** — confirms 0x14 stride |

**Reconciliation note (cell+0x0a vs cell+0x10).** `pl_mem.asm` (line 110, 115) says `anim_flags`
(player+0x14a) "inherits from 0x10 of animation structs." Taken literally that would put the
proximity/cancel flags at cell+0x10, not cell+0x0a. But player+0x14a = player+0x140 + 0x0a, i.e. the
copy lands the *cell+0x0a* byte at +0x14a. The "0x10" in the comment most likely refers to a byte at
offset 0x10 **within a differently-based anim struct** (the load-anim source layout) rather than the
20-byte runtime cell. The runtime fact — **player+0x14a is the proximity/cancel flag byte and it
equals cell+0x0a after the copy** — is what the renderer/predictor should rely on. Flagged here so a
future pass can confirm which source byte the build pipeline maps to 0x14a.

---

## 4. Ties to the live pipeline

| live field | source | path |
|---|---|---|
| `sprite_id` (player+0x144) | cell **Sprite** @0x04 | `loc_8c034dee` copy → atlas key consumed by `atlas/chars/PLxx.json` |
| `anim_timer` (player+0x142) | cell **Duration** @0x02 | `loc_8c034dee` countdown |
| hitbox geometry (player+0x170) | cell **HitboxGroup** @0x12 | `loc_8c034dee` → ×16 + pattern table (0x16c) → 0x1c0 |
| on-hit effect / hitspark | attack **Hitspark** @0x0b + cell **EffectTrigger** @0x0c | `loc_8c0578c0` → `bank0f.loc_8c0fd966`; `bank04.loc_8c042014` → shared **Effect Poly** buffer `0x0CED0000` (`work.asm`) |
| chip damage on block | attack **unk0e** @0x0e (masked 0x3F) | `loc_8c056f2e` |
| Damage → health | attack **Damage** @0x00 → player+0x420 | `loc_8c056454` (`Damage_Calc` then `sub`) |
| block/cancel windows | cell **ProximityBlock** @0x0a = `anim_flags` (player+0x14a) | per `pl_mem.asm` flag semantics |

---

## 5. Open items (candidates for the next RE pass)

- **JuggleY** attack offset — resolve the 0x08/0x09/0x0a conflict (§2 note).
- **EffectTrigger vs SoundFX** anim labels — confirm whether cell+0x01 is a second trigger or the
  SFX id, given cell+0x0c is the proven effect spawner (§3).
- **anim cell+0x0a vs cell+0x10** for `anim_flags` — confirm the build-pipeline source byte (§3 note).
- Pin read sites for attack **DamageType (0x04)**, **Undizzy (0x05)**, **Hitstop (0x07)**,
  **ImpactSound (0x0d)**, **InvincibilityTime (0x16)** — named by anotak, offsets inferred, read
  instructions not yet located in the banks examined (03/04/05). Hitstop/Undizzy likely resolve in
  the bank03 hit-pause / bank05 dizzy (`loc_8c059914`) paths.
- Attack `unk06, unkFlags0a, unk0c, unk0f, unk10, unk11, unk15, unk17, unk18, unk19` remain
  unidentified; the value-distribution hints in §2 narrow each to a category (duration / flag /
  id / strength enum) but none is pinned to a read.
