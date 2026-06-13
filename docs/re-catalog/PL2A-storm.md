# PL2A — Storm (char_id 42 = 0x2A) — reference character map

The fully-mapped character. Use this layout to infer the same for others.
Rip atlas: `PL2ADAT/{sprite_id}.png` (in `/tmp/mvc2_indexed.zip`, sprite_ids 0–1173).
Conf: ✅ confirmed · 🟡 strong · ❓ TBD

---

## Storm is assembled from these live objects (idle capture, 2026-06-05)

She is NOT one sprite. On screen at idle she is **body + 2 cape objects + 2
lightning objects**, each a pool object with `sprite_id@+0x12C` and
`screen pos@+0xC8/+0xCC` (see `00-README.md` for the struct).

| object role | sprite_id range (+0x12C) | position behavior | conf | notes |
|---|---|---|---|---|
| **BODY** | `0x144` value: idle 66–73, walk ~150s | char screen_x/y | ✅ | already rendered via char-struct `0x144`. Body sprite has **NO cape**. |
| **CAPE** (×2 objects) | **731–735** and **757–763** | tracks body, bobs (+0xCC Δ25 on walk) | ✅ | the flowing cape — dark grey/gold shapes. Two layers (front/back?). This is why the sprite client showed no cape. |
| **LIGHTNING (idle ambient)** (×2) | **850–864** and **869–892** | anchored ~(107,433) near her, steady | ✅ | small white/purple lightning streaks around her at idle. |

→ To render Storm completely: draw body (0x144) PLUS every Storm-owned pool
object with `sprite_id != 0`, each at `(+0xC8, +0xCC)`, additively for the
effect ones (cape is normal-alpha; lightning is additive).

---

## Storm sprite-id ranges (from anotak `PL2A_DAT_animgroup{N}` + rip)

### Body / animation (rendered as the body sprite, 0x144)
| what | sprite_ids | conf |
|---|---|---|
| idle | 66–73 | ✅ |
| walk | ~150–155 | 🟡 |
| crouch | 212–215 | 🟡 |
| air specials (g7) | 368–379 | 🟡 |
| punch strings (g11) | 421–489 | 🟡 |
| super body poses (g21) | 485–489, 519–547 | 🟡 |

### Effects / overlays (separate objects — the layer we were missing)
| effect | sprite_ids | trigger (state) | conf |
|---|---|---|---|
| **cape** | 731–763 | always (attached) | ✅ |
| **idle lightning** | 850–892 | idle/ambient | ✅ |
| **Lightning Attack** (qcf+P) | 257, 251 | special; RenderExtra=39 | 🟡 |
| **Lightning Storm** super | 519–547 (body) + g27 overlays | super; RenderExtra=12 | 🟡 |
| **Hailstorm** super | 551, 552 | super; RenderExtra=13 | 🟡 |
| **Typhoon / tornado** | g27 ~960–975 (cyclone/ring art) | special | 🟡 |
| **flight aura** | 238, 239 | flight; RenderExtra=64 | 🟡 |
| **group 27 "overlays"** block | ~925–1000+ | various effect timelines | 🟡 |

Group 27 = the dedicated effect-sprite group (lightning arcs, bolts, sparks,
tornado/cyclone rings — all blue/purple/white electric art, verified visually).

### anotak keyframe encoding (per move)
- 20-byte keyframe: `Sprite@+4`, `EffectTrigger@+1`, `RenderExtra@+17`, `HitboxGroup@+18`, `Duration@+2`.
- Storm encodes effects in **RenderExtra** (12=Lightning Storm, 13=Hailstorm, 39=Lightning Attack, 64=flight). Live-readable via `ANIM_POINTER@0x168` indexed by `anim_state@0x1D0`+`anim_timer@0x142`.
- The anotak "raw data" column = on-disc DAT script byte offset (stride 8 for g27, 20 for g21). **Not a texture/RAM locator — ignore it.** The `Sprite` (sprite_id) column is the atlas key.

---

## Inference rules for OTHER characters (the payoff)
Once this is wired for Storm, expect the same shape per char `PL{hex}`:
1. Body = char-struct `0x144`. Body sprite is often **part-only** (cape/coat/hair separate).
2. Attached parts (cape, coat, hair, weapon) = separate pool objects, sprite_ids in a high block, tracking the body.
3. Effects/projectiles = pool objects, sprite_ids in the char's effect block (Storm 850–1000+; per-char varies — scrape anotak `PL{hex}_DAT_animgroup27`).
4. ALL render from `PL{hex}DAT/{sprite_id}.png` at the object's `(+0xC8,+0xCC)`.
5. Per-char effect sprite_ids + RenderExtra codes: scrape `zachd.com/mvc2/data/anotak/PL{hex}_DAT_animgroup{N}.html`.

Known so far (from prior scrapes): Magneto EM Disruptor 802–814; Colossus effect overlays 305–329 & 436–450.
