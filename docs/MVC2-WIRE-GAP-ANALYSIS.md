# MVC2 Wire Gap Analysis

Off-SH4 asset-driven renderer: what the GSTA + OBJS wire currently ships, what
on-screen-relevant state it does NOT ship, and the exact field(s) behind the
white/electric on-body hit-flash.

All struct offsets are from `marvelous2/memory/pl_mem.asm`; code citations are
`bank:line` against `marvelous2/build/bankNN.asm`. Char struct base P1C1 =
`0x8C268340`, stride `0x5A4`. CONFIRMED = pinned to a disasm read site or doc
line; INFERRED = reasoned from anotak/value patterns without a pinned read.

---

## 1. Full field inventory by layer

### Layer A — GSTA per-character struct (base 0x8C268340, stride 0x5A4)

| Field | Offset | Type | Source | Drives visual | On wire |
|-------|--------|------|--------|---------------|---------|
| active | +0x000 | u8 | pl_mem:58 | char drawn at all | yes (GSTA@0) |
| character_id | +0x001 | u8 | pl_mem:59 | selects PLxx atlas | yes (GSTA@1) |
| unnamed_state | +0x005 | u8 | pl_mem:61 | none confirmed | no |
| Special_Move_State | +0x006 | u8 | pl_mem:62 | gates move/anim | partial* |
| mash_timer/counter | +0x01c/+0x01e | s16 | pl_mem:65,67 | indirect (move) | no |
| airdash_direction | +0x022 | u8 | pl_mem:70 | indirect | no |
| **pl_palid_match** | **+0x025** | u8 | pl_mem:73 | **active palette bank / flash base** | partial** |
| pos_x / pos_y | +0x034/+0x038 | f32 | pl_mem:76,77 | world pos | yes (GSTA@8/@12) |
| **char_pal_effect** | **+0x040** | u16 | pl_mem:79 | super/EX glow ONLY (dead on normal hits) | yes (PALF) |
| x/y/z sprite scale | +0x050/+0x054/+0x058 | f32 | pl_mem:81-83 | sprite size (vs 1.75x lock) | no |
| x/y velocity | +0x05c/+0x060 | f32 | pl_mem:85,86 | motion / interp | yes (GSTA@24/@28)*** |
| screen_x / screen_y | +0x0e0/+0x0e4 | f32 | pl_mem:96,97 (written by loc_8c03093c) | on-screen draw pos | yes (GSTA@16/@20) |
| xflip (copies) | +0x110/+0x130 | u8 | pl_mem:99,105 | facing flip (stale copies) | yes (facing@2) |
| unk_012c | +0x012c | u8 | pl_mem:103 | render/visibility? (1 always) | no |
| **palette-effect selector** | **+0x012e** | u8/u16 | bank03:12262 (loc_8c035250 `#data 0x012e`) | **live body palette-effect (flash/glow/tint)** | no |
| frame_count / anim_timer | +0x0142 | u16 | pl_mem:117 | anim timing | yes (anim_timer@36) |
| sprite_id | +0x0144 | u16 | pl_mem:118 | THE atlas key (body sprite) | yes (sprite_id@32) |
| anim_flags (=cell ProximityBlock) | +0x014a | u8 | pl_mem:115 | cancel windows (no pixels) | no |
| **RenderExtra** | **+0x0151** | u8 | bank03:11567 (copied by loc_8c034dee) | **additive overlay/aura/super layer** | no |
| current_cell_data | +0x0154 | ptr | pl_mem:120 | ENGINE-OWNED (never ship) | no |
| anim_id / anim_group | +0x0158 | u8 | pl_mem:122,123 | indirect (anim table) | no |
| Dat_GFX1/2, Dat_Pal, anims, hitbox/attack/extras ptrs | +0x015c..+0x0184 | ptr | pl_mem:126-136 | ENGINE-OWNED (never ship; crash source) | no |
| xflip (authoritative) | +0x01d2 | u8 | pl_mem:147 | facing flip (source of truth) | yes (facing@2) |
| unk_01d0 / animation_state | +0x01d0 | u8/u16 (disputed) | pl_mem:145 | indexes anim table | yes (anim_state@34) |
| walk-dir | +0x01d3 | u8 | pl_mem:149 | fwd/back walk gait | no |
| attack_data_index | +0x01a1 | u8 | pl_mem:138 | selects attack/hitspark record | no |
| per-char paleffect index | +0x01a4 | u8 | bank03:12266 (loc_8c035254 `#data 0x01a4`) | per-char palette-effect variant line | no |
| stance | +0x01f9 | u8 | pl_mem:191 | stand/crouch/jump/otg posture | no |
| superjump_state | +0x01fc | u8 | pl_mem:196 | indirect (camera/anim) | no |
| corner_touching | +0x01fd | u8 | pl_mem:201 | indirect (pushback) | no |
| Buff_Speed | +0x0200 | u8 | pl_mem:213 | indirect (aura) | no |
| Flight_Flag | +0x0201 | u8 | pl_mem:214 | flight aura/stance (Storm/Magneto) | no |
| Buff_HyperArmor | +0x0202 | u8 | pl_mem:215 | armor body glow (palette path) | no |
| Buff_Unk_03 | +0x0203 | u8 | pl_mem:217 | Magneto idle-float variant | no |
| landing_screen_shake | +0x0207 | u8 | pl_mem:222 | camera shake (not sprite) | no |
| EnemyPointer | +0x020c | ptr | pl_mem:229 | none (host ptr; never ship) | no |
| BlockFlags copy | +0x0230 | u8 | bank05:16414 (loc_8c056454) | block/hit-spark select (not body) | no |
| Hitstun/pushback (KD subclass) | +0x0231 | u8 | bank05:16261 (loc_8c056454) | hitstun dur / KD class (motion) | no |
| unk06 stun-duration | +0x0232 | u8 | bank05:16420 (loc_8c056454) | reaction timing | no |
| HitReaction state | +0x0233 | u8 | bank05:16482 (loc_8c056454) | selects hurt anim (→sprite_id) | no |
| Hitstop (u16) | +0x022c | u16 | bank05:16424 (loc_8c056454) | hit-pause freeze | no |
| KDDuration | +0x022e | u8 | bank05:17397 (loc_8c056b6e) | KD timer + spark placement | no |
| JuggleX | +0x022f | u8 | bank05:17412 (loc_8c056b6e) | launch vel (→pos/vel) | no |
| air_hitstun / airthrow_protect | +0x0239/+0x023a | u8 | pl_mem:239,244 | reaction state | no |
| health | +0x0420 | s16 | pl_mem:283 | health bar (HUD) | yes (health@3) |
| health2 (red) | +0x0424 | s16 | pl_mem:285 | red-health bar (HUD) | yes (red_health@4) |
| assist_type | +0x04c9 | u8 | pl_mem:289 | which assist | yes (assist_type@6) |
| is_cpu | +0x0525 | u8 | pl_mem:294 | none | no |
| pal_id (duplicate) | +0x052d | u8 | pl_mem:298 | secondary palette id | no |

\* Baseline ships `special_move_id@5`. pl_mem puts Special_Move_State at 0x06 and
sp_move_id at 0x1e9 — RE-VERIFY which byte the wire reads.
\** Baseline ships `palette_id@7`. The palette field the effect path reads is
`pl_palid_match`@0x25, NOT the duplicate pal_id@0x52d — confirm the wire maps to 0x25.
\*** pl_mem puts velocity at 0x5c/0x60; confirm the wire reads those, not 0x68.

### Layer B — Attack record (base player+0x1bc, stride 0x1C = 28 bytes)

Pointer cached at player+0x1bc; computed in bank05 loc_8c059384 (~23702:
`mov 0x1C,r3 ... mul.l ... add attack_data(0x174)`). This is ATTACKER-side data;
its *effects* land in the victim reaction block (Layer A 0x230-0x233 / 0x22c-0x22f).

| Field | Offset | Source | Effect | Writes victim |
|-------|--------|--------|--------|----------------|
| Damage | +0x00 | bank05:16282 (loc_8c056490) | health drop | victim+0x420 |
| HitReaction | +0x01 | bank05:21756 (loc_8c0586a2) | hurt anim class | victim+0x233 |
| BlockFlags | +0x02 | bank05:16024 (loc_8c056920) | block/chip, spark select | victim+0x230 |
| Hitstun/KD | +0x03 | bank05:16265 (loc_8c056454) | hitstun dur / KD class | victim+0x231 |
| DamageType | +0x04 | bank05:16522 (loc_8c056628) | dizzy build-up ONLY (NOT flash) | victim+0x1e1 (accum) |
| Undizzy | +0x05 | folded in loc_8c056628 | dizzy/stun build | victim+0x1e1 |
| Hitstop | +0x07 | bank03 hit-pause path | contact freeze | victim+0x22c |
| KDDuration | +0x08 | bank05:17397/19526 | KD timer + spark placement | victim+0x22e |
| JuggleX | +0x09 | bank05:17412 (loc_8c056b6e) | horiz launch | victim+0x22f |
| JuggleY/flags | +0x0a | DISPUTED (no pinned read) | vertical launch? flags? | — (open RE) |
| Hitspark | +0x0b | bank05:19520 (loc_8c0578c0) → bank0f:loc_8c0fd966 | spawns spark effect object | Effect Poly 0x0CED0000 |
| chip-dmg | +0x0e | bank05:18016 (loc_8c056f2e) | chip damage | victim+0x420 |
| flags | +0x12 | bank05:16342/19545 | Launcher(0x40)/FlyingScreen(0x80) → extra VFX | spawns effect |

### Layer C — Animation cell (20 bytes / 0x14; copied whole to player+0x140 by loc_8c034dee, bank03:11567)

`player[0x140+N] == cell[N]`, so every cell byte is live-readable each frame.

| Field | Cell off | → char off | Source | Drives visual | On wire |
|-------|----------|-----------|--------|---------------|---------|
| AnimFlags | +0x00 | +0x140 | anotak | hitstop anim advance (0x80) | no (redundant) |
| EffectTrigger (anotak) | +0x01 | +0x141 | anotak | category byte (real spawner is +0x0c) | no |
| Duration | +0x02 | +0x142 | bank03:11568 | anim timing | yes (anim_timer@36) |
| Ender | +0x03 | +0x143 | bank03:11584 (and 0x80) | loop/stop boundary | no |
| Sprite | +0x04 (u16) | +0x144 | bank03 loc_8c034dee | THE atlas key | yes (sprite_id@32) |
| unk06/07 | +0x06/07 | +0x146/47 | anotak (const 0xFF) | pad | no |
| AirborneLaunchAngle | +0x08 | +0x148 | anotak | trajectory (→screen pos) | no |
| AirborneLaunchSpeed | +0x09 | +0x149 | anotak | trajectory | no |
| ProximityBlock (=anim_flags) | +0x0a | +0x14a | pl_mem:115 | cancel windows (no pixels) | no |
| unk0b | +0x0b | +0x14b | — | unknown | no |
| **effect-trigger (effective)** | **+0x0c** | **+0x14c** | bank04:4520 (loc_8c042014 `#data 0x014c`) | **spawns effect/hitspark object** | no |
| unk0d/0e/0f | +0x0d-0f | +0x14d-4f | — | unknown | no |
| unk10 | +0x10 | +0x150 | — | unknown (label reconcile flag) | no |
| **RenderExtra** | **+0x11** | **+0x151** | re-catalog:117 | **additive overlay / super layer** | no |
| HitboxGroup | +0x12 (u16) | +0x1c0 | bank03:11616 | hitboxes (invisible) | no |

### Layer D — OBJS effect/object pool (base 0x8C26AA54, stride 0x1D0, 256 nodes; loc_8c044dce bank04:11725)

Pool objects carry their own render data — the real source of capes, projectiles,
hitsparks, and additive flash overlays. Per-object: sprite_id@+0x12C,
screen_x/y@+0xC8/+0xCC, owner@+0x80, category@+0x3. Wire OBJS currently ships
`cid, sprite_id(+0x8000 flip), type(slot-table layer), x, y, [blend]` — i.e. the
per-object analog of char+0x0151. The slot/draw-list enumeration lives at
0x8C2895E0 (stride 0x180) / inner ×4 at 0x8C287DE0.

---

## 2. What GSTA + OBJS currently ship

**GSTA per-char (38 bytes):**
`active@0, char_id@1, facing@2, health@3, red_health@4, special_move_id@5,
assist_type@6, palette_id@7, pos_x@8, pos_y@12, screen_x@16, screen_y@20,
vel_x@24, vel_y@28, sprite_id@32, animation_state@34, anim_timer@36`.

**PALF packet:** ships `char+0x40` (char_pal_effect) — EMPIRICALLY 0 on normal hits.

**OBJS per-object (8-9 bytes):**
`cid, sprite_id(+0x8000 flip = node+0x130), type(slot-table layer), x, y, [blend]`.

This covers: which character, which body sprite, where on screen, facing, health
bars, and the per-object effect sprites in the pool. It does NOT cover: the body
palette-effect (flash/glow), additive overlay layers, sprite scale, posture, or
flight/buff state.

---

## 3. Prioritized GAP list (drives visuals/state, NOT shipped)

Ordered by visual impact.

1. **char+0x0151 RenderExtra (u8)** — selects the additive effect/aura/super-overlay
   layer (Storm: 12=Lightning Storm, 13=Hailstorm, 39=Lightning Attack, 64=flight
   aura — PL2A-storm.md:44-48). Live-readable; copied by anim tick loc_8c034dee
   (bank03:11567). The body sprite alone cannot show these.
2. **char+0x012e palette-effect selector (u8/u16)** — THE live body palette-effect
   selector read by the palette-effect renderer bank03 loc_8c035162 (loc_8c035250
   `#data 0x012e`, bank03:12262). Drives super-glow, hit-flash whiteout, Iceman-style
   body tint via palette-line swap (loc_8c03544c "used for palette effects",
   bank03:12588). This is the field char+0x40 was supposed to be.
3. **char+0x0025 pl_palid_match (u8)** — the active palette bank index AND the base
   that flash effects offset from (loc_8c035000 "happens on hit" reads 0x25 then adds
   the +0x300 hurt-palette offset to Dat_Pal@0x164; bank03:11891). Confirm the wire's
   `palette_id@7` maps to 0x25, not the duplicate 0x52d.
4. **char+0x01f9 stance (u8)** — 00 stand / 01 crouch / 02 jump / 03 otg. Fixes the
   "2 unstable crouch crops" (re-catalog:60). Cheap, render-relevant.
5. **char+0x050 x_sprite_scale (f32, + 0x054 y)** — per-char sprite scale vs the
   client's constant 1.75x lock (Sentinel/Hulk size, big-hit zoom, projectile scale).
6. **char+0x0201 Flight_Flag (u8)** — flight stance/aura toggle (Storm flight aura
   paired with RenderExtra=64; Magneto idle float, re-catalog:62).
7. **char+0x0202 Buff_HyperArmor (u8)** — armored-super body glow via the palette
   path (bank03 has a "HyperArmor Offset" literal near loc_8c03537e); pairs with 0x12e.
8. **char+0x01a4 per-char paleffect index (u8)** — secondary flash input; indexes a
   per-char palette-effect line (bank03:12266). Mostly constant; ship only if 0x12e
   alone is insufficient.
9. **char+0x01d3 walk-dir (u8)** — fwd(0)/back(1)/not-walking(0xFF); disambiguates
   walk gait. Cheap.
10. **char+0x0203 Buff_Unk_03 (u8)** — Magneto idle-float anim variant. Minor.
11. **OBJS effect-pool enumeration** — ship pool objects (sprite_id@+0x12C,
    screen@+0xC8/0xCC, owner@+0x80, category@+0x3) rendered additively. This is the
    authoritative source of the spark/flash overlay objects; RenderExtra is only the
    per-char hint.

**Explicitly NOT worth shipping** (effect already captured downstream, or host
pointers): attacker DamageType@record+0x04 (only perturbs dizzy; does NOT drive the
flash); the engine-owned pointer cluster 0x154-0x184 (crash source); HitboxGroup
(invisible); reaction-state bytes 0x230-0x233 (these select the hurt anim, already
captured via sprite_id — ship only for a hit-state HUD).

---

## 4. THE ELECTRIC HIT-FLASH VERDICT

**The white/electric on-body hit-flash has NO single dedicated flash boolean.** It
is produced by a palette-RAM swap plus (for electric/super) an additive overlay.
Reconciled with the live capture (`char+0x40 = 0`, `char+0x231 = 19→51`,
`char+0x233 = 0→1`):

### What the live bytes ARE (and are not)
- **char+0x40 = 0 (char_pal_effect / PALF)** — NOT the normal-hit flash. pl_mem:79
  names it, re-catalog:41 calls it "super-glow / hit-flash palette effect", but the
  live body-palette renderer (bank03 loc_8c035162) reads **char+0x012e**, never 0x40.
  0x40 is the SUPER/EX glow mode (byte 0x40 = mode 0x00-0x0A passed as r5 to
  loc_8c035162; byte 0x41 = per-frame countdown, decremented in bank04 loc_8c046bc4,
  bank04:16202, gated by Special_Move_State@0x06). It is empirically 0 on normal hits
  → that is why the normal-hit flash never appears with only PALF shipped.
- **char+0x231 = 19→51** — the hitstun→recovery magnitude (attack record+0x03 written
  by bank05 loc_8c056454, bank05:16261). Reaction STATE, not the flash.
- **char+0x233 = 0→1** — the HitReaction class (attack record+0x01 & 0x1F, written by
  loc_8c056454, bank05:16482). Selects WHICH hurt anim plays (→ sprite_id). Not the flash.

### What the engine actually reads to flash the body
**Primary (the normal-hit white flash) — a palette-line swap:**
- bank03 **loc_8c035000** ("happens on hit", bank03:11891) reads **char+0x25**
  (`pl_palid_match`, the displayed palette-bank index; `mov 0x25,r0; mov.b @(r0,r4),r5`)
  and, in its branches, adds the **+0x300 "Palette Offset"** (loc_8c035076 = 0x0300) to
  **Dat_Pal** (char+0x164) — selecting the alternate hurt/flash palette bank instead of
  the normal one. When 0x25 flips to the hurt index during hitstop, the body re-palettes
  to Dat_Pal+0x300 = whiteout.
- The render-time resolver bank03 **loc_8c035162** (bank03:12114) dispatches on a MODE
  in r5 (cases 0x00..0x0A, bank03:12142-12194): 0x00 = no tint, nonzero = the
  glow/tint variants (plain white vs electric blue-white). It reads its selector from
  **char+0x012e** (loc_8c035250 `#data 0x012e`, bank03:12262) and the per-char index at
  **char+0x01a4** (bank03:12266), then rewrites palette memory via **loc_8c03544c**
  ("used for palette effects", bank03:12588; reads char+0x30 palette-line + char+0x164
  Dat_Pal). Iceman's deliberate body tint (S_PL09.asm:705 loc_ce3041C) proves this
  mechanism: read palette-id char+0x25 + a per-effect "Pal_Effect_Var", overwrite the
  palette line.

**Secondary (the electric crackle / aura) — an additive overlay object:**
- The per-cell **RenderExtra** byte (cell+0x11 → **char+0x0151**, copied by anim tick
  loc_8c034dee, bank03:11567) selects the additive render layer. The crackle is an
  additive object in the shared Effect Poly buffer 0x0CED0000, spawned by the cell
  effect-trigger (cell+0x0c → char+0x14c, drives bank04 loc_8c042014, bank04:4520) and
  by the attack record Hitspark@+0x0b (bank05 loc_8c0578c0 → bank0f loc_8c0fd966).

### Verdict — fields to ship to reproduce the flash
1. **char+0x012e** (u8/u16) — the live body palette-effect selector. THE field char+0x40
   was supposed to be. Drives normal-hit whiteout + electric tint + super glow.
2. **char+0x0025** (u8, `pl_palid_match`) — the bank index the +0x300 hurt-palette swap
   offsets from. Without it the client can't pick the flash palette line.
3. **char+0x0151** (u8, RenderExtra) — the additive electric/aura overlay layer.
4. **char+0x01a4** (u8) — per-char palette-effect variant index (secondary; mostly const).
5. KEEP **char+0x40/0x41** (PALF) — still correct for SUPER/EX electric glow, just not
   for normal hits.

**Do NOT** ship attacker DamageType@record+0x04 expecting it to drive the flash — it
only perturbs the dizzy accumulator (loc_8c056628 → PRNG loc_8c03319e → table
loc_8c14f27a → victim+0x1e1). Confirmed negative.

---

## 5. LIVE-PROBE WATCH-LIST

Watch these char-struct bytes in real time (per slot; P1C1 base 0x8C268340, stride
0x5A4) across a clean normal hit, an electric/special hit, and a super, to confirm
each candidate before wiring it.

| Watch | Offset | Expect on normal hit | Expect on electric/super | Confirms |
|-------|--------|----------------------|--------------------------|----------|
| **palette-effect selector** | **+0x012e** | flips nonzero during hitstop | distinct nonzero (tint variant) | bank03 loc_8c035162 selector — PRIME flash field |
| **pl_palid_match** | **+0x025** | flips to hurt index during flash | hurt/tint index | bank03 loc_8c035000 +0x300 swap base |
| **RenderExtra** | **+0x0151** | low/none | nonzero (electric=39, aura=64, etc.) | bank03 loc_8c034dee additive overlay |
| per-char paleffect idx | +0x01a4 | ~1 const | may vary | bank03:12266 secondary index |
| char_pal_effect mode | +0x040 | 0 (confirmed) | nonzero on super/EX | PALF — rules IN supers, OUT normal hits |
| char_pal_effect timer | +0x041 | 0 | counts down during glow | bank04 loc_8c046bc4 |
| unk_012c | +0x012c | 1 const | 1 | adjacent to 0x12e cluster (context) |
| Special_Move_State | +0x006 | 0 | nonzero in super | gates the 0x40/0x41 glow path |
| Dat_Pal ptr | +0x164 | engine ptr | engine ptr | READ-ONLY witness (+0x300 = flash bank) — never ship |
| hitstun magnitude | +0x0231 | 19→51 | varies | reaction state (already characterized) |
| HitReaction class | +0x0233 | 0→1 | varies | reaction state (selects hurt anim) |
| Flight_Flag | +0x0201 | 0 | 1 when flying | flight aura gate (pairs w/ 0x151=64) |
| Buff_HyperArmor | +0x0202 | 0 | 1 on armored super | armor glow via palette path |
| x_sprite_scale | +0x050 | per-char const | may zoom on big hits | scale-lock fix |
| stance | +0x01f9 | 0/1/2 by posture | — | crouch-crop fix |

**Probe protocol:** sample 0x012e, 0x025, 0x0151, 0x01a4, 0x040, 0x041 together on
the exact frame HP drops (gate on the already-characterized 0x231 19→51 / 0x233 0→1
edge). The candidate that flips nonzero on a clean normal hit while 0x040 stays 0 is
the normal-hit flash driver — expected to be **0x012e** (with 0x025 supplying the
swap base).

---

### Cross-references
- `marvelous2/memory/pl_mem.asm` (struct offsets), `build/bank03.asm`
  (loc_8c035000 @11891, loc_8c035162 @12114, loc_8c03544c @12588, loc_8c034dee @11567),
  `build/bank04.asm` (loc_8c042014 @4468, loc_8c046bc4 @16195),
  `build/bank05.asm` (loc_8c056454 @16249, loc_8c056b6e @17381, loc_8c0578c0 @19520).
- `docs/MVC2-FRAMEDATA-FIELDS.md`, `re-catalog/00-README.md`, `re-catalog/PL2A-storm.md`,
  `char_prg/code/S_PL09.asm:705` (Iceman tint), `core/network/maplecast_gamestate.cpp`
  (PALF serializer ~375-414).
