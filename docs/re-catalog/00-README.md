# MVC2 Object-Pool RE Catalog

Living reference for the MapleCast ROM-asset client. Goal: render the FULL game
(characters + capes + effects + projectiles) on the state-only sprite client by
reading MVC2 RAM, not by scraping the TA video. Map ONE character (Storm)
exhaustively, then infer the same layout for the rest.

**Confidence legend:** ✅ confirmed by live capture · 🟡 strong hypothesis · ❓ unknown/TBD

---

## The core discovery (2026-06-05)

**Every character is assembled from MULTIPLE objects in a pool, not one sprite.**
Storm on screen = body object + cape object(s) + lightning object(s) + (when
active) tornado / projectile / super objects. Each object carries its own
`sprite_id` and screen position. We had been rendering ONLY the body (`0x144`),
which is why the sprite client showed no cape, no tornado, no effects.

The fix is one clean mechanism: **read every active pool object → draw its rip
sprite at its position.** No TA texture scraping. Projectiles, supers, assists,
capes — all fall out of the same read.

---

## Character struct (per slot) — already known/used

6 slots, base `0x8C268340`, stride `0x5A4`. Order P1C1,P2C1,P1C2,P2C2,P1C3,P2C3.

Offset names cross-checked against the **marvelous2** SH4 disassembly
(`memory/pl_mem.asm`, [github.com/mountainmanjed/marvelous2](https://github.com/mountainmanjed/marvelous2)).
⚠️ disassembled copyrighted code — facts only, reimplement clean-room, never vendor.

| offset | field | notes (marvelous2 label) |
|--------|-------|-------|
| +0x000 | active (u8) | `active` |
| +0x001 | character_id (u8) | `charid0` |
| +0x025 | Color/palette index (u8) | `pl_palid_match` = COLOR SELECTED IN MATCH (live skin/tint). `pal_id` also @ +0x52D |
| +0x034 | pos_x (f32) | `x_pos` (world) |
| +0x038 | pos_y (f32) | `y_pos` (world) |
| +0x040 | char_pal_effect (u16) | super-glow / hit-flash palette effect |
| +0x050 | x/y/z_sprite_scale (f32×3) | per-char sprite scale @ +0x50/54/58 — vs the constant 1.75× lock |
| +0x0E0 | screen_x (f32) | `x_pos_screenspace` (0–640) |
| +0x0E4 | screen_y (f32) | `y_pos_screenspace` (0–480) |
| +0x110 | facing (u8) | `xflip_copy_2` — a COPY; authoritative `xflip` = +0x1D2 |
| +0x142 | anim_timer (u16) | `frame_count` |
| +0x144 | **sprite_id (u16)** | `sprite_id` — BODY sprite; indexes rip atlas |
| +0x14A | anim_flags (u8) | 0x20=no cancel/super/assist · 0x40=recovery · 0x80=opp prox-block |
| +0x154 | current_cell_data (ptr) | `current_cell_data` |
| +0x158 | anim_id / anim_group (u8) | `anim_id`=`anim_group` |
| +0x15C | GFX00_PTR | `Dat_GFX1` (decoded part pixels); +0x160 `Dat_GFX2` |
| +0x164 | PAL_PTR | `Dat_Pal` (live ARGB4444 palette) |
| +0x168 | ANIM_POINTER | `animations` (keyframe table; RenderExtra lives here) |
| +0x16C | hitbox_pattern_table (ptr) | `hitbox_pattern_table` |
| +0x170 | HITBOX_PTR | `hitbox_data`; +0x174 `attack_data` |
| +0x178 | EXTRAS_PTR | `Sprite_Extras`; +0x17C `Dat_FilePointer`, +0x184 `FAC_ptr` |
| +0x1D0 | animation_state (u16) | `unk_01d0` "controls what move to play" |
| +0x1D2 | xflip (u8) | authoritative facing; +0x1D3 walk-dir (0 fwd / 1 back / 0xFF idle) |
| +0x1E9 | sp_move_id (u8) | `sp_move_id` (special move) |
| +0x1F9 | stance (u8) | 0=stand 1=crouch 2=jump 3=otg — explains the 2 unstable crouch crops |
| +0x201 | Flight_Flag (u8) | drives Storm flight aura (RenderExtra=64) + Magneto idle float |
| +0x420 | health (u8) | `health` (int16) |

GSTA wire already ships: active, char_id, facing, health, palette, pos_x/y,
screen_x/y, vel_x/y, sprite_id, anim_state, anim_timer (per-char 38B block).
Candidate additions from the merge: `stance` (0x1F9), `Flight_Flag` (0x201),
`anim_flags` (0x14A), sprite scale (0x50) — cheap and render-relevant.

---

## Object pool — the NEW map

Pool region ≈ `0x8C26A000` – `0x8C278000`. Objects found by scanning for a u32
that equals one of the 6 char-struct bases (the **owner pointer**). ~60 object
slots; most are inactive (`sprite_id == 0`). Probe: `MAPLECAST_PTRDUMP=1` →
`/dev/shm/mc_obj.log` (per-frame dump of owner-0x10 .. owner+0x140).

> **marvelous2 names AND corrects this pool** (disasm-verified, 2026-06-05). The pool
> initializer `loc_8c044dce` (`marvelous2/build/bank04.asm:11601-11756`, consts
> `loc_8c044ea4=0x1d0`, `loc_8c044ea2=0x0100`, `loc_8c044ec8=0x8c26aa54`,
> `loc_8c044ed8=0x0001d000`=256×0x1d0) gives the real shape: **base `0x8C26AA54`,
> stride `0x1D0` (464 B), 256 nodes** — `work.asm`'s `0x8C26AC24` is node **#1**, not
> the start. Allocator = free-list pop `loc_8c044f12` (sets `node+0x3`=category, then
> jsr's a per-category constructor `loc_8c045020[cat]`). Disasm record layout:
> `category@+0x3 · next@+0x8 · prev@+0xC · update-fn-ptr@+0x10 · world x/y@+0x34/+0x38 ·
> OWNER player-ptr@+0x80 (copy +0x84) · cull/gfx field@+0xC8 · sprite_id(lo16)@+0x12C ·
> xflip@+0x130`. **Draw order RESOLVED: linked-list order (next/prev), no z field** —
> infer layer from `category@+0x3` + sprite_id range. (`STG_ID 0x8C26A95C`, Abyss flag
> `0x8C26A8C8` sit just below the pool.)
>
> ### ✅ RESOLVED 2026-06-08 — screen pos is **+0xE0/+0xE4**, NOT +0xC8/+0xCC (the renderer is the authority)
> The "+0xC8 vs +0xE0" screen-offset conflict is **closed, CONFIRMED-FROM-DISASM**. Trace
> of the two render walkers that turn these nodes into on-screen sprites:
> - **`loc_8c0308c2` Render_sprites** (`bank03.asm:1200`) walks the slot table
>   (count array `0x8C2895E0`, ptr array `0x8C287DE0`, row stride 0x180). Per entry it
>   loads the node ptr into r4, reads the **category byte @node+0x3** (`mov.b @(0x3,r4)`),
>   and `bsr loc_8c03093c` (Render Main Sprite) for it.
> - **`loc_8c03093c` Render Main Sprite** (`bank03.asm:1281`): r14=node base. First reads
>   the **cull byte @node+0x12C** (`loc_8c030aa4=0x012c`; if nonzero → skip/return). Then
>   reads world pos @+0x34/+0x38/+0x3C, runs the world→screen transform
>   (`bank12.loc_8c1216c0`), and **writes the result to screen_x@node+0xE0 and
>   screen_y@node+0xE4** (`loc_8c030aa6=0x00e0`, `loc_8c030aa8=0x00e4`, lines 1316-1323).
>   facing is read from +0x110 (`loc_8c030ab8`), xflip copies at +0x130/+0x134/+0x136.
> - The **slot-table INSERT** `loc_8c04515e` (`bank04.asm:12166`) confirms the record shape:
>   it gates on **byte @r4+0x12C** (`loc_8c04521e=0x012c`; must be nonzero to register) and
>   indexes the layer count by **byte @r4+0x24**, then stores the record ptr into `0x8C287DE0`.
>
> **Verdict (b):** the slot-table / render path operates on **char-struct-shaped records**
> where `+0x12C` is a **one-byte cull/enable flag** (NOT a u16 sprite_id) and the screen
> position the renderer actually submits is **+0xE0/+0xE4**. `readAllDrawn` and
> `readObjectsWalk` in `core/network/maplecast_gamestate.cpp` read screen at +0xE0/+0xE4 —
> **CORRECT**, matching the disasm.
>
> The earlier **"pool node screen = +0xC8/+0xCC, sprite_id = +0x12C"** map came from the
> **owner-anchored empirical scan** (`readObjects`, anchored at `O` = the +0x80 owner word)
> and is **not** what the renderer submits. At +0xC8 the *other* render walker
> `loc_8c0301ce`/`loc_8c0301f6` (head-list `0x8C287A5C`, chained via +0xC) **dereferences
> the value as a POINTER** (`loc_8c03021e=0x00c8`; `tst; bt`), i.e. +0xC8 holds a gfx/assembly
> pointer or a pre-transform/copy coordinate — a float-looking value the walk-test mistook
> for screen_x. **The transform output the GPU receives is +0xE0/+0xE4.** Treat +0xC8/+0xCC
> as a copy/secondary field; do not submit it.
>
> ### Code state + the fix (`core/network/maplecast_gamestate.cpp`)
> Three object readers exist; `readObjects()` dispatches on env:
> - **`readObjects` (DEFAULT, live in prod)** — pool scan anchored at the owner-ptr word `a`;
>   reads **screen @a+0xC8/+0xCC** and **sid @a+0x12C** (line 512, 496). ❌ **WRONG offsets**
>   per the disasm — this is the live source of projectile/object drift.
> - **`readObjectsWalk` (MAPLECAST_OBJS_WALK)** — head-list walk `0x8C287A5C`, chained via
>   node+0xC; reads **screen @node+0xE0/0xE4**, **sid @node+0x144** (line 294, 283). ✅ correct.
> - **`readAllDrawn` (MAPLECAST_OBJS_SLOTTABLE)** — slot-table walk `0x8C2895E0`/`0x8C287DE0`;
>   reads **screen @node+0xE0/0xE4**, **sid @node+0x144**, cull @node+0x12C (line 359, 357). ✅ correct.
>
> **The fix is NOT a one-line offset swap inside `readObjects`** — its whole anchoring (`a` =
> owner word, not record base) is wrong, so +0xC8/+0x12C are skewed fields. The disasm-correct
> readers already exist. **One-line fix: make production use the walk reader** (e.g. default
> `readObjects` to `return readObjectsWalk(...)`, or set `MAPLECAST_OBJS_WALK=1`). `readObjectsWalk`
> walks the exact head-lists the engine renders (`loc_8c0301ce`) in z-order, no ghost frames.
> Prefer it over the slot-table reader unless you need the owner-less global supers (those need
> `readAllDrawn`).

Offsets are relative to the **owner-pointer word** (call it `O` = the address
holding the char base):

| offset | field | conf | notes |
|--------|-------|------|-------|
| O+0x000 | owner char base ptr | ✅ | the scan key; tells you which char owns it (→ which rip atlas) |
| O−0x008 | gfx/assembly ptr | ✅ | game's internal render ptr (0x8C0E/0x8C10). NOT a sprite_id; ignore. |
| O+0x00C | type id `0x2a03xxxx` | 🟡 | object type/category |
| O+0x01C | f32 (~−310 seen) | ❓ | velocity or relative offset? |
| O+0x020 | f32 (~−21 seen) | ❓ | |
| O+0x0C8 | ~~screen_x~~ pre-transform/copy or gfx ptr | ⚠️SUPERSEDED | float-looking; the head-list walker `loc_8c0301f6` deref's +0xC8 as a POINTER. **NOT the submitted screen pos** — the renderer submits +0xE0 (see RESOLVED note above). |
| O+0x0CC | ~~screen_y~~ copy/secondary | ⚠️SUPERSEDED | as above; renderer writes screen_y to +0xE4. |
| **node+0xE0** | **screen_x (f32)** | ✅disasm | `loc_8c03093c` writes the world→screen transform here (`loc_8c030aa6=0x00e0`). THE submitted x. (abs node base, not owner-anchored.) |
| **node+0xE4** | **screen_y (f32)** | ✅disasm | `loc_8c03093c` writes transform here (`loc_8c030aa8=0x00e4`). THE submitted y. |
| node+0x12C | **cull/enable byte (u8)** | ✅disasm | render gate `loc_8c030aa4=0x012c` (skip if !=0) + slot-insert gate `loc_8c04521e`. NOT a sprite_id. |
| node+0x144 | **sprite_id (u16)** | 🟡 | char-struct convention (pl_mem.asm sprite_id@+0x144); slot records share it — what `readAllDrawn` reads. |

**To render an object:** owner char_id → which `PL{hex}` atlas; `sprite_id@+0x12C`
→ which sprite; `(screen_x@+0xC8, screen_y@+0xCC)` → where; draw additively for
effects (see docs/WEBGPU-RENDERER analysis: characters first, effects last,
blend `one/one`, transparency implicit because additive treats black as no-op).

### Open verifications
- ✅ **screen pos = +0xE0/+0xE4** (RESOLVED 2026-06-08, disasm `loc_8c03093c` writes the transform output there; slot/render path is the authority). The 2026-06-05 walk-test "+0xC8 = screen_x" was the owner-anchored scan reading a pre-transform/copy field; **superseded** — do NOT submit +0xC8/+0xCC.
- ✅ **Detached projectiles = SAME pool** (disasm: every spawner across bank0e/0f/10/11 calls the one allocator `loc_8c044f12`, category-distinguished). In-flight projectiles keep owner@+0x80 but their +0x34 world pos diverges from the owner — the old scan missed them if it keyed on owner-proximity; the base+stride scan finds them.
- ✅ **Draw order = doubly-linked active-list order (next@+0x8/prev@+0xC), no z scalar.** Engine has head-insert vs tail-insert spawn primitives. Client: infer layer from category@+0x3 + sprite_id range (cape behind body, lightning/super in front).
- 🟡 **Body double-draw:** keep rendering body from char-struct 0x144; skip the pool's body-category record to avoid double-draw (re-verify by category byte).
- ✅ **Keyframe = 20 bytes, CONFIRMED** by anim tick `loc_8c034dee` (`bank03.asm:11567`): `current_cell_data@+0x154` advances 0x14/keyframe; 20 B copied to player+0x140. So `Duration@kf+2→0x142`, `sprite_id@kf+4→0x144`, `RenderExtra@kf+0x11→player+0x151`, `HitboxGroup@kf+0x12→0x152`, `EffectTrigger = bit 0x80 of kf+0`. **RenderExtra is live-readable at player+0x151.**

---

## Memory-map grounding (docs/MVC2-MEMORY-MAP.md)
Cross-checked against the committed dirty-page memory map:
- **Object pool** = per-frame dirty pages **618-625** (`0x8C26A000`-`0x8C271FFF`+); the doc
  labels 618-619 "projectile/particle pool", 624-625 "post-character data". Our scan
  `0x8C26A600`-`0x8C278000` spans them. The object-struct internals above are now merged INTO that doc.
- **Char structs**: page 616 (`0x8C268000`). **Global state**: page 649 (`0x8C289000`). Offsets match.
- **TA command staging / display-list work area**: pages **813-839** (`0x8C32D000`-`0x8C347FFF`) —
  where the game BUILDS the GPU draw list each frame. The natural RE target for the
  **renderer-oracle** (exact per-sprite position / draw-order / blend the game submits).
- **VRAM**: 0 pages change during steady gameplay; ~7 on animation transitions.

## Sprite anchors (true per-sprite offsets)
Our tight-cropped rip atlas lost each sprite's anchor (we used generic `-w/2,-h`). The archive
`MvC2_SpriteFolders_Patched.7z` (operator-local, repo root) has the SAME sprites
(`{Name}_{0000..}` == same index as `PL{hex}DAT/{sid}`) on a fixed **800x800 canvas** where the
sprite's position ENCODES its anchor. Origin = idle-body bottom-center (~400,400); anchor for a
sprite = its (palette index != 0) bbox relative to that origin. Applied to Storm (PL2A) 2026-06-05 —
fixes cape/part placement; body anchor unchanged (validates the origin). **TODO: batch the roster**
(needs the .7z folder-name → PL{hex} map; the anotak scrape can supply it).

## The render gotcha (sprite-gpu.mjs)
The WebGPU sprite renderer **groups CONSECUTIVE same-cid sprites** and **drops anything past
`maxGroups=8` / `maxInst=64`**. So the draw list MUST be sorted by cid (each character's body +
its objects = one contiguous group). Scattering mixed-cid objects to the front (e.g. via unshift)
floods the group cap and silently drops character bodies. Objects get `z=-1` (behind body) + the
owner's slot (for the palette bank); sort key = `(charId, z)`.

## Per-character files
- `PL2A-storm.md` — Storm (the reference mapping)
- (add others as mapped: PL2C-magneto, PL17-cable, …)
