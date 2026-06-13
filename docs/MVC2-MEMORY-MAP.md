# MVC2 Dreamcast Memory Map — Per-Frame Dirty Pages

**Date:** April 4, 2026
**Source:** Live capture from mirror mode, frame 134713, during active match
**Method:** 4KB page-level diff of all Dreamcast memory (RAM 16MB + VRAM 8MB + ARAM 2MB + PVR 32KB)

---

## SUMMARY

Only **42 pages (168 KB)** change per frame out of **26 MB** total Dreamcast memory = **0.6% of total memory changes per frame.**

| Region | Dirty Pages | Size | Purpose |
|--------|-------------|------|---------|
| RAM | 38 | 152 KB | Game logic, character state, engine |
| ARAM | 3 | 12 KB | Sound/audio buffer |
| PVR | 1 | 4 KB | Hardware registers (palette, fog) |
| VRAM | 0* | 0 KB | *Textures (changes during animations) |
| **Total** | **42** | **168 KB** | |

*VRAM pages change during character animation transitions (~7 pages when sprites update)

---

## RAM DIRTY PAGES — DECODED

### System/Engine Area (0x8C000000 - 0x8C1FF000)

| Page | DC Address Range | Size | Contents |
|------|-----------------|------|----------|
| 15 | 0x8C00F000-0x8C00FFFF | 4 KB | **System tick/scheduler** — low-level engine timing |
| 363 | 0x8C16B000-0x8C16BFFF | 4 KB | Unknown — possibly sound command buffer |
| 406 | 0x8C196000-0x8C196FFF | 4 KB | Unknown — engine internal state |
| 420-421 | 0x8C1A4000-0x8C1A5FFF | 8 KB | Unknown — contiguous, likely a buffer |
| 459-460 | 0x8C1CB000-0x8C1CCFFF | 8 KB | Unknown — contiguous pair |
| 474 | 0x8C1DA000-0x8C1DAFFF | 4 KB | Unknown |
| 478 | 0x8C1DE000-0x8C1DEFFF | 4 KB | Unknown |
| 484-488 | 0x8C1E4000-0x8C1E8FFF | 20 KB | **Large contiguous block** — likely DMA buffer or display list staging |
| 504-506 | 0x8C1F8000-0x8C1FAFFF | 12 KB | **Camera + rendering state area** |

**Page 505 (0x8C1F9000)** contains:
- `0x8C1F9CD8` — camera_x (float)
- `0x8C1F9CDC` — camera_y (float)
- `0x8C1F9D80` — stage_anim_timer (u8, monotonic counter)

### Character + Game State Area (0x8C200000 - 0x8C2FF000)

| Page | DC Address Range | Size | Contents |
|------|-----------------|------|----------|
| 533 | 0x8C215000-0x8C215FFF | 4 KB | Unknown — pre-character area |
| 590 | 0x8C24E000-0x8C24EFFF | 4 KB | Unknown — pre-character area |
| 616 | 0x8C268000-0x8C268FFF | 4 KB | **CHARACTER STRUCTS (P1C1 + P2C1 + part of P1C2)** |
| 618-619 | 0x8C26A000-0x8C26BFFF | 8 KB | **Post-character area** — projectile/particle pool |
| 624-625 | 0x8C270000-0x8C271FFF | 8 KB | Unknown — post-character data |
| 649 | 0x8C289000-0x8C289FFF | 4 KB | **GLOBAL GAME STATE** |
| 731 | 0x8C2DB000-0x8C2DBFFF | 4 KB | Unknown |

**Page 616 (0x8C268000)** contains ALL character structs:
- `0x8C268250` — fight_engine_tick (counter)
- `0x8C268340` — P1C1 struct base (stride 0x5A4)
- `0x8C2688E4` — P2C1 struct base
- `0x8C268E88` — P1C2 struct base

Per character struct (+offset from base):
```
+0x000  active (u8)           +0x001  character_id (u8)
+0x034  pos_x (float)         +0x038  pos_y (float)
+0x05C  vel_x (float)         +0x060  vel_y (float)
+0x0E0  screen_x (float)      +0x0E4  screen_y (float)
+0x110  facing (u8)           +0x142  anim_timer (u16)
+0x144  sprite_id (u16)       +0x1D0  animation_state (u16)
+0x420  health (u8)           +0x424  red_health (u8)
+0x1E9  special_move (u8)     +0x4C9  assist_type (u8)
+0x502  sub_anim_phase (u8)   +0x52D  palette (u8)
+0x00C  char_link_ptr (u32)   — linked list pointer
+0x168  anim_pointer (u32)    — animation table in DC RAM
```

#### Object Pool struct (pages 618-625, 0x8C26A000-0x8C278000) — RE 2026-06-05

The "projectile/particle pool" holds each character's **satellite objects** — capes,
effect overlays, projectiles, afterimages — as separate render objects. A character
on screen = its body (char-struct `+0x144` sprite) **plus** N of these objects. Find
them by scanning `0x8C26A600`–`0x8C278000` for a u32 equal to one of the 6 char-struct
bases (the **owner pointer**); ~60 slots, most inactive (`sprite_id == 0`).

Per object (offsets from `O` = the address holding the owner pointer):
```
O+0x000  owner char base ptr   — which character_id owns it (→ which sprite set)
O-0x008  gfx/assembly ptr       — game-internal render ptr (NOT a sprite_id)
O+0x0C8  screen_x (float)        — spawned objects (projectiles) update this live;
O+0x0CC  screen_y (float)          attached parts (capes) can lag/stall here
O+0x12C  sprite_id (u16 low)     — indexes the OWNER's sprite set; animates frame-to-frame
```
Used by `maplecast_gamestate::readObjects()` → "OBJS" wire packet → the state-only
sprite client draws each object's sprite at its position. Per-character
`sprite_id → cape/effect/projectile` mappings + true sprite anchors are rip-derived
and live in the operator RE catalog (`re-catalog/`), not here.

> **marvelous2 confirms & corrects this pool** (RE 2026-06-05, disasm-verified):
> `work.asm` labels `0x8C26AC24` "Extra Sprite Render memory slot * 1d0", but the pool
> **initializer** (`bank04.asm:11725-11756`, `loc_8c044dce`) proves: **base `0x8C26AA54`,
> stride `0x1D0` (464 B), 256 nodes** — `0x8C26AC24` is node **#1**, not the array start.
> Allocator = free-list pop `loc_8c044f12` (`bank04.asm:11793`); category byte written at
> **record+0x3**. ⚠️ **Owner player-ptr is at record+0x80** (and copy +0x84), NOT at record
> start — our empirical `O+0x000=owner` scan anchored on the +0x80 field, so re-verify the
> within-record offsets (screen +0xC8/+0xCC, sprite_id +0x12C) against the **absolute** base
> `0x8C26AA54 + slot*0x1D0` before trusting them. **Draw order = position in the doubly-linked
> active list (next +0x8 / prev +0xC); there is NO z scalar** — infer layer from category+0x3
> + sprite_id range. Per-frame update-fn ptr at record+0x10. All projectiles/capes/effects/
> super-overlays come from this one pool (category-distinguished); assist *characters* are real
> char slots, but their projectiles use the pool.

---

## CROSS-REFERENCE & MERGE — marvelous2 SH4 disassembly

**Source:** [github.com/mountainmanjed/marvelous2](https://github.com/mountainmanjed/marvelous2) — a full
SH4 disassembly of MVC2 NTSC-U Dreamcast. Its `memory/pl_mem.asm` and `memory/work.asm`
are *labeled* symbol files whose addresses match every value we reverse-engineered
empirically (`player_start 0x8C268340`, the 6 slot bases, `sprite_id 0x144`,
`screen 0xE0/0xE4`, `health 0x420`, the `Dat_*` pointers, the object pool). They confirm
our map and add the fields below. ⚠️ This is disassembled copyrighted code — read for
*facts*, reimplement clean-room; **never** vendor it or its `build/` (it reassembles to the
ROM). Labels are **strong cross-reference** until confirmed against our own live capture
(✅ = we already verified independently).

### Additional per-character struct fields (base `0x8C268340`, stride `0x5A4`)

Fields beyond the core block above (the core block is all ✅-verified by us):
```
+0x025 pl_palid_match (u8)   ; COLOR SELECTED IN MATCH — live skin/tint (re-catalog uses this)
+0x040 char_pal_effect (u16) ; super-glow / hit-flash palette effect  ← palette-recolor work
+0x050 x/y/z_sprite_scale    ; f32 ×3 — per-char sprite scale (see scale note below)
+0x110 xflip_copy_2 (u8)     ; what we read as "facing" — a COPY; authoritative xflip = 0x1D2
+0x14A anim_flags (u8)       ; 0x20=no cancel/super/assist  0x40=recovery  0x80=opp prox-block
+0x154 current_cell_data ptr +0x158 anim_id/anim_group (u8)
+0x15C Dat_GFX1 ✅  +0x160 Dat_GFX2  +0x164 Dat_Pal ✅  +0x168 animations ✅
+0x16C hitbox_pattern_table  +0x170 hitbox_data ✅  +0x174 attack_data  +0x178 Sprite_Extras ✅(EXTRAS)
+0x17C Dat_FilePointer       +0x184 FAC_ptr
+0x1D0 "controls what move to play" ✅(animation_state)  +0x1D2 xflip  +0x1D3 walk-dir(0fwd/1back/FF idle)
+0x1E8 chain_strength  +0x1E9 sp_move_id ✅(special_move)
+0x1F9 stance (0=stand 1=crouch 2=jump 3=otg)  ← shadow/crop-height fix for the bake
+0x200 Buff_Speed  +0x201 Flight_Flag  +0x202 HyperArmor  +0x205 Buff_Damage  +0x206 Buff_Defense
+0x20C EnemyPointer ptr  +0x525 is_cpu  +0x52D pal_id ✅  +0x540..543 wins/lose/draw/handicap (A&B only)
```
⚠️ Reconcile: we read **facing @0x110** (a copy); the real flip is **0x1D2**. And we map
**palette @0x25** (re-catalog) vs **0x52D** (`pal_id`) — marvelous2 shows *both* exist
(`0x25`=match color choice, `0x52D`=pal_id); keep `0x25` as the live-tint source.

### DAT files & codec buffers (the open pixel-codec trail)

On-disc `PLxx_DAT` is loaded to a fixed RAM window; the GFX codec decompresses into a
scratch buffer. **To crack the still-open sprite codec, trace the routine that reads a
`PLxx_DAT` window and writes `Texture_Decompress_Buffer`.**
```
pl_A_datfile 0x0C420000(P1C1) pl_C 0x0C570000(P1C2) pl_E 0x0C6C0000(P1C3)
pl_B_datfile 0x0C810000(P2C1) pl_D 0x0C960000(P2C2) pl_F 0x0CAB0000(P2C3)   (+_FACfile sibling +0x148000)
S_PLxx char-program code @ 0x0CE30000..0x0CE58000   Texture_Decompress_Buffer 0x0CE60000 ← codec OUTPUT
DM00 Poly 0x0CE80000   Stage Poly 0x0CEA0000   Effect Poly 0x0CED0000
```

### Sprite scale constants (vs the sprite-client 1.75× lock)

Sprite client locks constant `1.75×` (commit `b26dc86f9`). marvelous2 exposes:
```
CpsXScale 0x3FD55555 = 1.66666…   CpsYScale 0x40092492 = 2.14285…   (work.asm)
per-char x/y/z_sprite_scale @ +0x50/+0x54/+0x58 (pl_mem.asm)
```
The non-square X/Y suggests an **anisotropic** rip→screen transform, not one 1.75 — test it.

### Globals — corrections & additions

| Address | marvelous2 label | vs our map |
|---|---|---|
| `0x8C16BC2C` | **RngVal** (RNG state) | new — determinism-relevant |
| `0x8C2895F0` | **Battle State** | new |
| `0x8C289620/621` | Frameskip Timer / **Counter** | ⚠️ we call `0x289621` `match_sub_state` — RECONCILE |
| `0x8C289630` | Timer | ✅ |
| `0x8C26A95C` | `STG_ID` | ⚠️ vs our `stage_id 0x8C289638` — two refs, verify live one |
| `0x8C268270/278/28C/291` | Char/Color Unlocks, Game mode, Stage Unlocks | new |
| `0x8C28C474` | `Charsel_Input` | new |
| `0x8C26823C / 240` | GameGlobalPointer / Start | new |

**Stage IDs (`STG_ID`):** `0 AirShip 1 Desert 2 Factory 3 Carnival 4 Swamp 5 BlueCave
6 Clock 7 IceRiver 8 Abyss 9 AltAirShip A AltDesert B Training C AltCarnival D PinkSwamp
E LavaCave F WinterClock 10 RiverRaft`.

**Char IDs (hex, authoritative):** `00 Ryu … 17 Cable … 23 Dan … 2A Storm … 2C Magneto
… 34 Sentinel … 3A Servbot` (file = `PL{id:02X}_DAT`; full table in `pl_mem.asm`). Confirms
**Cable=0x17, Dan=0x23**.

**SPL move-dispatch:** per-slot jump tables `0x8C289BD8 + slot*0x80`; entry index = move
category (`Normal1/2, FwrdDsh, BackDsh, FgIntro, MtchWin, SpecPRG, DlyHypC, TmHypMn/As,
Assists, AlphCnt`). Per-char `S_PLxx.asm` (raw SH4) implements these — future source for
move→effect (RenderExtra) correlation.

---

**Page 649 (0x8C289000)** contains:
- `0x8C289621` — match_sub_state
- `0x8C289624` — in_match flag
- `0x8C28962B` — round_counter
- `0x8C289630` — game timer
- `0x8C289638` — stage_id
- `0x8C289646` — p1_meter_fill (u16)
- `0x8C289648` — p2_meter_fill (u16)
- `0x8C28964A` — p1_meter_level (u8)
- `0x8C28964B` — p2_meter_level (u8)
- `0x8C289670` — p1_combo (u16)
- `0x8C289672` — p2_combo (u16)

### Engine/Buffer Area (0x8C300000 - 0x8C3FF000)

| Page | DC Address Range | Size | Contents |
|------|-----------------|------|----------|
| 813-814 | 0x8C32D000-0x8C32EFFF | 8 KB | Unknown — contiguous pair |
| 822-823 | 0x8C336000-0x8C337FFF | 8 KB | Unknown — contiguous pair |
| 825-826 | 0x8C339000-0x8C33AFFF | 8 KB | Unknown — contiguous pair |
| 835-836 | 0x8C343000-0x8C344FFF | 8 KB | Unknown — contiguous pair |
| 838-839 | 0x8C346000-0x8C347FFF | 8 KB | Unknown — contiguous pair |
| 841 | 0x8C349000-0x8C349FFF | 4 KB | **Frame counter area** |

**Page 841 (0x8C349000)** contains:
- `0x8C3496B0` — frame_counter (u32)

Note: Pages 813-839 form a pattern of contiguous pairs in the 0x8C32D000-0x8C347FFF range (108 KB). This is likely the **TA command staging buffer** or **display list work area** where the game builds GPU commands before submitting to the Tile Accelerator.

### Far RAM (0x8CF00000+)

| Page | DC Address Range | Size | Contents |
|------|-----------------|------|----------|
| 3858 | 0x8CF12000-0x8CF12FFF | 4 KB | Unknown — near end of 16MB RAM. Possibly stack or heap. |

---

## ARAM DIRTY PAGES (Sound RAM)

| Page | Offset | Size | Contents |
|------|--------|------|----------|
| 0 | 0x000000-0x000FFF | 4 KB | AICA DSP registers/command buffer |
| 11 | 0x00B000-0x00BFFF | 4 KB | Sound sample playback position |
| 14 | 0x00E000-0x00EFFF | 4 KB | Sound sample playback position |

---

## PVR DIRTY PAGES (Hardware Registers)

| Page | Offset | Size | Contents |
|------|--------|------|----------|
| 0 | 0x000000-0x000FFF | 4 KB | **ALL PVR registers** including palette RAM, fog table, display control, TA state |

Key registers in this page:
- `PAL_RAM_CTRL` — palette format selector (1555/565/4444/8888)
- `PALETTE_RAM[1024]` — 1024 × u32 color palette entries
- `FOG_TABLE[256]` — fog density lookup table
- `FOG_COL_VERT`, `FOG_COL_RAM`, `FOG_DENSITY` — fog color/density
- `ISP_FEED_CFG` — controls translucent polygon sort mode
- `TA_GLOB_TILE_CLIP` — tile clipping region
- `FB_W_SOF1` — framebuffer write address
- `SCALER_CTL` — display scaling

---

## VRAM DIRTY PAGES (Video RAM)

VRAM changes primarily during:
- **Character animation transitions** — new sprite frames uploaded (~7 pages, 28 KB)
- **Scene transitions** — loading new character/stage textures (100+ pages)
- **Effects** — hit sparks, super move effects

During steady gameplay (characters idle or repeating animations): **0 VRAM pages change.**

---

## WHAT NEVER CHANGES

| Region | Size | Contents |
|--------|------|----------|
| RAM pages 0-14 | 60 KB | System bootstrap, BIOS handlers |
| RAM pages 16-362 | 1.4 MB | Game code (ROM loaded to RAM) — **STATIC** |
| RAM pages 364-405 | 168 KB | Game data tables — **MOSTLY STATIC** |
| RAM pages 407-419 | 52 KB | Static game data |
| RAM pages 489-503 | 60 KB | Static rendering data |
| RAM pages 507-532 | 104 KB | Static data |
| RAM pages 534-589 | 224 KB | Static data |
| RAM pages 617 | 4 KB | P2C2, P1C3, P2C3 char structs (idle = no change) |
| RAM pages 620-623 | 16 KB | Static post-character data |
| RAM pages 626-648 | 92 KB | Static game engine data |
| RAM pages 650-730 | 324 KB | Static data |
| RAM pages 732-812 | 324 KB | Static data |
| RAM pages 842-3857 | 12.1 MB | **HUGE STATIC BLOCK** — ROM data, textures, lookup tables |
| VRAM (during steady gameplay) | 8 MB | Texture data — changes only on animation transitions |
| ARAM pages 1-10, 12-13, 15+ | 1.9 MB | Sound samples — loaded once, played repeatedly |

**~24.5 MB out of 26 MB is STATIC during gameplay.**

---

## IMPLICATIONS FOR STREAMING

### Ultra-Light Replay Client
A client that stores the initial 26 MB snapshot + records only the 42 dirty pages per frame:
- **168 KB/frame × 60 fps = 9.8 MB/s** raw
- **Compressed: ~3-4 MB/s** (memory diffs compress well)
- **10-minute match: ~2 GB raw, ~600 MB compressed** — stored, replayable, rewindable

### The 253-Byte Game State vs Full Brain
- 253 bytes captures the KNOWN game state (health, position, animation)
- Full brain captures EVERYTHING including unknown state
- The unknown ~35 pages outside our known addresses are likely:
  - TA command staging (pages 813-839)
  - DMA buffers (pages 484-488)
  - Engine internal state (pages 406, 420-421, 459-460)

### Do We Need the ROM?
The ROM data lives in RAM pages 16-362 (~1.4 MB) and the large static block at pages 842+ (~12 MB). This data is loaded ONCE at boot from the GDI/CHD file. A client that has:
1. The initial save state (contains all loaded ROM data)
2. Per-frame diffs

**Does NOT need the ROM file.** The save state IS the loaded ROM + game state. This is important for legal/distribution reasons — the save state contains the running game state, not the copyrighted ROM format.

### Minimum Viable Stream
If we only stream the pages that contain KNOWN game state:
- Page 505 (camera): 4 KB
- Page 616 (characters): 4 KB  
- Page 649 (global state): 4 KB
- **12 KB/frame = 720 KB/s** for complete game state including unknown fields

The 253-byte format is a SUBSET of page 616 + 649 + 505.

---

## LIVE GAME STATE — HOW THE MEMORY MAP IS USED

The memory map above isn't just documentation — it drives the live match overlay in the browser client.

### Server-Side Read
`maplecast_gamestate::readGameState()` reads the RAM addresses documented above (character structs from page 616, global state from page 649) every frame on the server. The extracted game state is serialized to JSON and broadcast over WebSocket as a status message every 1 second.

### Win Detection
Win condition is checked by monitoring health values across all 3 characters on each side. When all 3 characters on one side reach 0 HP, that side has lost. The server includes this in the status broadcast, and the client records the result.

### Character ID Mapping
Character IDs from `+0x001 character_id (u8)` in the character struct are mapped to human-readable names via the `MVC2_CHARS` array defined in `index.html`. This covers the full 56-character MVC2 roster.

### Client-Side Leaderboard
The browser client tracks wins and losses in `localStorage`. Each time the server broadcasts a win event, the client increments the appropriate counter. The leaderboard persists across page reloads.

### Live Match Stats Display
The browser overlay displays real-time match data pulled directly from the addresses in this document:
- **Timer** — from `game_timer` at `0x8C289630`
- **Teams** — character IDs resolved to names for both P1 and P2 (all 3 slots)
- **HP per character** — `health` at `+0x420` for each of the 6 character structs
- **Combo count** — `p1_combo` / `p2_combo` from `0x8C289670` / `0x8C289672`
- **Meter level** — `p1_meter_level` / `p2_meter_level` from `0x8C28964A` / `0x8C28964B`

This is the 253-byte game state made visible. Every address in the overlay traces back to a specific offset documented in the character struct and global state tables above.

---

## ADDRESS SOURCES

All addresses verified from 6+ sources:
1. flycast-dojo-training mode tools
2. lord-yoshi MVC2 trainer
3. libretro .cht cheat files
4. Codebreaker/Action Replay codes
5. MAME NAOMI cheat database
6. SRK (Shoryuken) community research
7. **MapleCast RAM autopsy** (maplecast_rend_diff.cpp) — scanned 20KB across 10 regions, found 98 correlated addresses

## TOOLS BUILT

- `maplecast_rend_diff.cpp` — RAM autopsy engine, diffs game state vs rend_context
- `maplecast_mirror.cpp` — full brain streaming, page-level diffs
- `maplecast_gamestate.cpp` — 253-byte game state read/write/serialize
- `maplecast_scanner.cpp` — brute force animation state scanner
- `maplecast_visual_cache.cpp` — TA display list + texture recorder
