# MVC2 Community Spreadsheet — Extracted RE Data

Source: `https://docs.google.com/spreadsheets/d/1xVxjAX3pEEPsR0tJcVAt9mCWLnzE_MVI6rIXgEIueHI/`
Fetched 2026-06-05 via CSV export. Sheet is **publicly accessible** (no auth needed).
8 tabs total; `Notes` tab is empty.

## CRITICAL: address prefix is PS2, not Dreamcast

Every address in this sheet uses the **PCSX2 / PS2** convention `0x2C......`. Our
runtime is **Dreamcast** (`0x8C......`). The good news: the **low 24 bits / struct
offsets are identical**. The char base in the sheet is `2C268340`; ours is
`8C268340`. Same `0x5A4` stride, same slot order. So every offset in this sheet
maps 1:1 onto our Dreamcast layout — just swap the high byte `2C`→`8C`.

To convert any sheet address to ours: replace leading `2C` with `8C`.
(A few non-char addresses use other high bytes, e.g. `2C1F...`, `2C34...`, `2C13...`,
`2C21...`, `2CD6...` — those are PS2-specific RAM regions and may NOT map cleanly;
only the `2C26....` char/object region and `2C289...` global region are trustworthy.)

---

## Tab gid map

| Tab | gid | Content |
|-----|-----|---------|
| PlayerMemoryAddresses | 1424163345 | Full per-character struct field map (the big one) |
| SpecificCharacterAddresses | 1789703471 | Per-character flight timers |
| Player1And2Addresses | 1908856133 | Per-player (combo/meter/input) addresses |
| SystemMemoryAddresses | 496547644 | Global game state, camera, frame/timer |
| CharacterInfo | 458303732 | char_id → name, assists, special-move inputs, SpecialID lists |
| StagesInfo | 555679403 | stage_id → name |
| InputsInfo | 701575653 | input bitmask values |
| Notes | 465078481 | (empty) |

---

## Tab: PlayerMemoryAddresses — the character struct (offsets from char base)

This is the authoritative per-slot struct map. Base = `0x..268340`, stride `0x5A4`,
slot order P1C1, P2C1, P1C2, P2C2, P1C3, P2C3 — **identical to ours**. All offsets
below are relative to a slot base.

### Render-critical fields (what the sprite client reads)

| offset | field | sheet description |
|--------|-------|-------------------|
| +0x000 | Is_Active (u8) | 0 not active / 1 active (tagged in & assist) |
| +0x001 | ID_2 (u8) char_id | full 0..58 enum (see below) |
| +0x002 | PlayerID (u8) | |
| +0x004 | Animation_Lock (u8) | 0 intro taunt / 1 default / 2 freezes sprite |
| +0x025 | **Color (u8)** | main palette index (0 LP,1 LK,2 HP,3 HK,4 A1,5 A2). "changes when hit" |
| +0x034 | X_Position_Arena (f32) | world X, −1250..1250 |
| +0x038 | Y_Position_Arena (f32) | world Y, 0..900 (camera stops tracking at 900) |
| +0x050 | Sprite_Scale_X (u8) | default 1 |
| +0x054 | Sprite_Scale_Y (u8) | default 1 |
| +0x058 | Sprite_Scale_Z (u8) | default 1 |
| +0x05C | X_Velocity (f32) | |
| +0x060 | Y_Velocity (f32) | |
| +0x0E0 | **X_Position_Screen (f32)** | screen X, 0..640 |
| +0x0E4 | **Y_Position_Screen (f32)** | screen Y, 0..480 |
| +0x0EC | Hitbox_Scale_X (u8) | default 1.666666985 |
| +0x0F0 | Hitbox_Scale_Y (u8) | default 2.142857552 |
| +0x110 | Facing_Right (u8) | 0 left / 1 right |
| +0x12C | Unknown_0x012C (u8) | "seems to be always 1" — **see object-pool note below** |
| +0x130 | Facing_Right_1 (u16) | duplicate facing |
| +0x140 | Anim_AnimationFlag_0x00 (u8) | range [0x140,0x154) copied from animation data |
| +0x142 | Anim_KeyFrame_FrameCount (u8) | (our anim_timer region) |
| +0x144 | **Animation_Value (u16)** | "Displays which sprite number is being shown on-screen. Can be increased from 0 for sprite rips." = our **sprite_id** |
| +0x154 | Anim_CurrentAnimPTR (ptr) | |
| +0x158 | Anim_AnimID (u8) | |
| +0x159 | Anim_GroupID / Is_Prox_Block (u8) | State Tracker 1 (26-state enum, see below) |
| +0x15C | **DAT_GFX00_PTR** (ptr) | matches our GFX00_PTR |
| +0x160 | DAT_GFX01_PTR (ptr) | |
| +0x164 | **DAT_PaletteData_PTR** (ptr) | matches our PAL_PTR |
| +0x168 | **DAT_AnimationData_PTR** (ptr) | matches our ANIM_POINTER |
| +0x16C | DAT_HitboxPatternTable_PTR (ptr) | |
| +0x170 | **DAT_HitboxData_PTR** (ptr) | matches our HITBOX_PTR |
| +0x174 | DAT_AttackData_PTR (ptr) | |
| +0x178 | **SpriteExtras_PTR** (ptr) | matches our EXTRAS_PTR (part-assembly list) |
| +0x17C | DAT_FilePTR (ptr) | |
| +0x184 | FAC_FilePTR (ptr) | |
| +0x1D0 | Knockdown_State (u8) | State Tracker 2 (34-state enum) — our animation_state |
| +0x420 | Health_Big (u8) | non-recoverable, 0..144 |
| +0x424 | Health_Small (u8) | recoverable, 0..144 |
| +0x428 | CharacterProgrammingTable_PTR (ptr) | |
| +0x52C | CharacterID_2 (u8) | char_id copy, out-of-match logic |
| +0x52D | PaletteID_2 (u8) | **palette copy** — out-of-match logic |

### Gameplay / state fields (useful for effects + prediction)

| offset | field | notes |
|--------|-------|-------|
| +0x005 | Stun_Check | 0 none/1 throwing/2 being thrown/3 being hit |
| +0x006 | Action_Flags | 0 default/1 startup/2 active/3 recovery |
| +0x01C | Animation_Timer_Main (u16) | super/dash durations; mashing-affected |
| +0x022 | Normal_Held_Direction | |
| +0x068 | X_Gravity (f32) | per-char unique |
| +0x06C | Trip_Checker / Y_Gravity | (shared offset, two interpretations) |
| +0x14A | Proxblock | proximity-block flags |
| +0x1A0 | Hitstop2 | hitstop after hit connects |
| +0x1A1 | Attack_Number | current attack memory ID (per-char) |
| +0x1A3 | Assist_Counter / Special_Strength | 0 light/1 heavy+A1/2 A2 |
| +0x1A4 | CharacterSlot_0 | 0..5 = P1A,P2A,P1B,P2B,P1C,P2C |
| +0x1D2 | Facing_Right_2 | another facing dup |
| +0x1D3 | Walking | 0 fwd/1 back/255 standing |
| +0x1D6 | Unfly | unfly meter tracker |
| +0x1E1 | Dizzy | undizzy stun (RNG, 0..80) |
| +0x1E9 | Special_Attack_ID | special/super ID in decimal |
| +0x1ED | Attack_Immune | 0 hurt/1 invuln/2 snapped |
| +0x1F4 | Assist_Onscreen | 0 on-screen / 1 off-screen |
| +0x1F9 | Airborne | 0 stand/1 crouch/2 air |
| +0x201 | Flight_Flag | 0 not flying / 1 flying |
| +0x202 | Hyper_Armor | 0 off / 128 on |
| +0x203 | Idle_Hover | hovering during idle (Magneto/Storm) |
| +0x20C | PointEnemy_PLMEM_PTR | ptr to opponent point char struct |
| +0x255 | THC_State | assist/THC sub-state (0x00..0x09 enum) |
| +0x298 | X_Position_From_Enemy (f32) | |
| +0x2A0 | Snapback_Timer (u32) | |
| +0x32E | Damage (u8) | damage from current attack |
| +0x364..0x3CC | Button Sequence Buffer | input-buffer region (per-char varies) |
| +0x3F2 | Super_Armor | 0 off / 1 on |
| +0x411 | Is_Point | 0 point / 1 assist-1 / 2 assist-2 |
| +0x41C | Floor_Height (f32) | |
| +0x426 | Healing_Timer (u16) | red-health regen, 1 pip / 51 frames |
| +0x48C | Y_Position_From_Enemy (f32) | |
| +0x4C9 | Assist_Value | 0 alpha / 1 beta / 2 gamma |
| +0x525 | CPU | 0 off / 1 CPU |
| +0x55C | CharacterSlot_1 | 0..5 slot id (dup of 0x1A4) |

### char_id enum (0..58) — from ID_2 field

```
0 Ryu        12 SpiderMan   24 AbyssA      36 Cammy      48 OmegaRed
1 Zangief     13 Hulk        25 AbyssB      37 Dhalsim    49 Spiral
2 Guile       14 Venom       26 AbyssC      38 MBison     50 Colossus
3 Morrigan    15 DoctorDoom  27 ChunLi      39 Ken        51 IronMan
4 Anakaris    16 TronBonne   28 Megaman     40 Gambit     52 Sentinel
5 StriderHiryu 17 Jill       29 Roll        41 Juggernaut 53 Blackheart
6 Cyclops     18 Hayato      30 Akuma       42 Storm      54 Thanos
7 Wolverine   19 RubyHeart   31 BBHood      43 Sabretooth 55 Jin
8 Psylocke    20 Sonson      32 Felicia     44 Magneto    56 CaptainCommando
9 Iceman      21 Amingo      33 Charlie     45 ShumaGorath 57 WolverineB
10 Rogue      22 Marrow      34 Sakura      46 WarMachine  58 Servbot
11 CaptainAmerica 23 Cable   35 Dan         47 SilverSamurai
```

### Color/palette enum (Color @ 0x25)
`0 LP · 1 LK · 2 HP · 3 HK · 4 A1 · 5 A2`

---

## Tab: SpecificCharacterAddresses — flight timers

Per-character flight (214KK) timers. These are **char-struct offsets** (region
`0x2685xx`-ish, i.e. ~ +0x2A4..+0x2B4 from base) except Megaman which is a separate
global region.

| Char | offset-from-base (P1A) | shared with |
|------|------|------|
| Dhalsim | +0x2AC | |
| IronMan / WarMachine | +0x2A8 | each other |
| Magneto | +0x2AA | |
| Sentinel | +0x2A4 | |
| Bison / Doom | +0x2AE | each other |
| Storm | +0x2B4 | |
| Megaman | `0x..40D386` (Beat Plane) | global, PS2 region — NOT char-struct |

(Offsets computed as sheet-addr minus `2C2685E0`-relative base. Use cautiously;
the flight timer lives near +0x2A0 Snapback_Timer.)

---

## Tab: Player1And2Addresses — per-player globals

These mix two regions: the `0x..289xxx` global state region (matches our page-649
map) and a couple back-references into char structs.

| field | P1 addr | P2 addr | offset/region |
|-------|---------|---------|--------|
| Assist_Flag | 2C289632 | 2C289633 | global 0x289632/3 (0 default/2 A1/4 A2) |
| Attacks_Done (u16) | 2C28966C | 2C28966E | global |
| Attacks_Successful (u16) | 2C289670 | 2C289672 | global |
| Combo_Meter_Value (u16) | 2C268B50 | 2C2685AC | **char-struct** offset +0x26C / +0x26C (combo names: 3 "Yes"…100+ "Marvelous") |
| Dead_Counter | 2C269DE1 | 2C26A385 | char-struct +0x411 (= Is_Point slot) — 0=3 alive…2=1 alive |
| Hitbox_Count | 2C287DDE | 2C287DDF | region 0x287Dxx (hitbox display) |
| Input_DEC (u16) | 2C2681DC | 2C2681F0 | region 0x2681xx — live input bitmask (see InputsInfo) |
| Max_Combo (u16) | 2C2685AA | 2C268B4E | char-struct |
| Meter_Big | 2C28964A | 2C28964B | global — meter whole number 0..5 |
| Meter_Small (u16) | 2C28966C | 2C28966E | global |
| Pause_ID | 2C212CA2 | 2C212CA3 | PS2 region (won't map) |
| Wins_Value | 2C28968C | 2C28968D | global |

NOTE: P1/P2 combo addresses look **swapped** in the sheet (P1=…268B50 which is the
P1C2 slot region, P2=…2685AC which is P1A region). Treat with suspicion; verify live.

---

## Tab: SystemMemoryAddresses — global game state

Region `0x..289xxx` (our page-649) and camera region `0x..26A5xx`.

### Confirms / extends our global map

| field | sheet addr | our known? |
|-------|-----------|-----------|
| A_2D_Game_Timer (match timer big) | 2C289630 | ✅ = our `0x8C289630 game timer` |
| Frame_Skip_Counter | 2C289621 | ✅ = our `0x8C289621 match_sub_state` (NOTE: sheet labels it "frame skip counter" / "displays frame values 1-4" — **contradicts** our "match_sub_state" label; investigate) |
| Frame_Skip_Rate | 2C289620 | new — 0 off..6 turbo2 |
| Frame_Skip_Toggle | 2C289622 | new |
| Frame_Skip_Cycle_Value (u16) | 2C289600 | new — frames since match start incl. skipped |
| Match_Tracker | 2C2895F0 | new — **match-state machine** (0 loading/2 intro/3 walk/4 mid-match/5 KO/6 win/9 finish). Very useful for sprite client scene gating. |
| Match_Start_Throw_Timer (u16) | 2C289602 | new |
| First_Attack_Indicator | 2C2895F2 | new |
| Timer_Secondary (match small) | 2C289631 | new |
| Total_Frames (u32) | 2C3496B0 | ✅ = our `0x8C3496B0 frame_counter` |
| Frame_Counter | 2C1F9D80 | PS2 region — different from above; won't map to DC |
| Is_Paused | 2C1C9166 | PS2 region |
| Stage_Selector | 2C26A95C | char-region — stage id, 0..16 (in-game order) |
| Abyss_Stage_Change | 2C26A8C8 | char-region |

### Camera block (region 0x..26A5xx) — NEW, potentially valuable for zoom

| field | sheet addr | default |
|-------|-----------|---------|
| Camera_X_Position | 2C26A56C | 0 |
| Camera_Y_Position | 2C26A570 | 95 |
| Camera_Z_Position | 2C26A52C | 812.357 (zoom) |
| Camera_Z_Sprite_Scale | 2C26A538 | 812.357 |
| Camera_X_Rotation | 2C26A524 | 0 |
| Camera_Y_Rotation | 2C26A528 | 95 |
| Camera_X_Left_Max | 2C26A5B0 | −1280 |
| Camera_X_Right_Max | 2C26A5B4 | 1280 |
| Camera_Field_of_View | 2C26A584 | 43 |
| Camera_Lock | 2C26A51F | 0 reset/1 default/2 custom |
| Camera_Z_Mirror_1 | 2C2D6B14 | 812.357 (PS2 region, may not map) |
| Camera_Z_Mirror_2 | 2C1F9CE0 | 812.357 (PS2 region) |

These camera addresses (`0x8C26A52C`-ish on DC) could let the sprite client compute
**dynamic zoom** from `Camera_Z_Position` / `Camera_Z_Sprite_Scale` — our notes
record zoom is currently hard-coded const 1.75×. Worth probing live.

---

## Tab: CharacterInfo — char_id → moves, assists, SpecialIDs

For each char_id (0..58): dev/pub name, name aliases, A/B/Y assist types, assist
inputs, THC inputs, alpha-counter inputs, and SpecialID input lists. Most chars
have empty SpecialID columns; **Psylocke (8), Storm (42), Magneto (44)** have full
SpecialID_0..20 lists for both "0" and "1" variants (LP/HP). Example:

- Storm SpecialID_0 = `QCF+HK`, _3 = `QCB+KK`, _4 = `LK+HP(FinalHit)`, _5 = `QCB+PP`,
  _10 = `QCF+A` (assist), _11 = `j.QCB+LP`; "1" variant swaps to HP/A1 forms.

This is gameplay/labeling data — not directly render-mapping, but useful for naming
effects/projectiles and for the panel UI. Assist types per char (Anti-Air,
Projectile, Expansion, Ground, Throw, Dash, Capture, Launcher, Heal, Variety,
Enhance, Balance) are catalogued for all 59 entries (Abyss A/B/C = "Empty").

---

## Tab: StagesInfo — stage_id → name (in-game order)

```
0 Boat1(Day_Boat)      6 Clock2(Summer_Clock)  12 Carnival2(Dark_Carnival)
1 Desert1(Sunset)      7 Raft2(Snow_Raft)      13 Bridge2(Pink_Bridge)
2 Factory              8 Abyss                 14 Cave1(Red_Cave)
3 Carnival1(Day)       9 Boat2(Night_Boat)     15 Clock1(Snow_Clock)
4 Bridge1(Brown)      10 Desert2(Day_Desert)   16 Raft1(Day_Raft)
5 Cave2(Blue_Cave)    11 Training              17 Random
```
NOTE: this ordering is the **stage-selector** order and differs from our
`stage_id @ 0x8C289638` raw value — confirm which index our wire ships.

---

## Tab: InputsInfo — input bitmask

Matches `Input_DEC` from Player1And2Addresses. Bit values (decimal):

```
0x0400 1024 Right     0x0200 512 LP    0x0080 128 A1
0x0800 2048 Left      0x0040  64 LK    0x0010  16 A2
0x1000 4096 Down      0x0100 256 HP    0x8000 32768 START
0x2000 8192 Up        0x0020  32 HK
```

---

## CROSS-CHECK vs our object-pool RE (re-catalog/00-README.md)

### CONFIRMS (independent second source agrees with us)

1. **Char base + stride + slot order** — sheet base `2C268340`, stride `0x5A4`, order
   P1C1,P2C1,P1C2,P2C2,P1C3,P2C3. Exactly ours (modulo `2C`→`8C`). Strong validation.
2. **sprite_id @ +0x144** — sheet: `Animation_Value`, "displays which sprite number is
   being shown on-screen … can be increased from 0 for sprite rips." Verbatim confirms
   our body-sprite read and even mentions sprite rips.
3. **screen_x @ +0xE0, screen_y @ +0xE4** — sheet: `X/Y_Position_Screen`, ranges 0..640 /
   0..480. Confirms our char-struct screen coords (and their 640×480 range).
4. **palette/Color @ +0x25** — confirms our `+0x025 Color/palette index`.
5. **All assembly pointers** — sheet names GFX00_PTR@0x15C, PaletteData_PTR@0x164,
   AnimationData_PTR@0x168, HitboxData_PTR@0x170, SpriteExtras_PTR@0x178 — exactly our
   GFX00/PAL/ANIM/HITBOX/EXTRAS pointer offsets. Full confirmation of the pointer-follow set.
6. **facing @ +0x110, anim_state @ +0x1D0** — confirmed (Facing_Right, Knockdown_State).

### EXTENDS (new data we can use)

- **`SpriteExtras_PTR` @ +0x178** is explicitly the part-assembly list (matches our
  EXTRAS_PTR hypothesis) — and there's a second `DAT_GFX01_PTR @ +0x160` we hadn't
  catalogued (a second graphics pointer; may be the second part-layer).
- **`Sprite_Scale_X/Y/Z` @ +0x50/0x54/0x58** and **Hitbox_Scale_X/Y @ +0xEC/0xF0**
  (defaults 1.666.. / 2.142..) — per-character sprite scaling we can apply instead of a
  global const. Directly relevant to our hard-coded size=1.75× note.
- **Camera_Z_Position / Camera_Z_Sprite_Scale @ ~0x8C26A52C/0x8C26A538** (default 812.357)
  — a path to real **dynamic zoom** vs our const. Probe these live.
- **Match_Tracker @ 0x8C2895F0** — clean scene state machine (loading/intro/mid/KO/win)
  for gating the sprite client.
- **`Color` enum** (0 LP … 5 A2) explains the 6 palette variants per char.
- **PaletteID_2 @ +0x52D** — note: this is the OUT-OF-MATCH palette copy. Our CLAUDE.md
  lists `palette @ 0x52D`; the sheet says the LIVE palette is `Color @ 0x25` and 0x52D is
  a secondary copy "for out-of-match logic." **Our pointer-follow memory already flagged
  this (palette is 0x25 not 0x52D) — the sheet confirms that correction.**

### CONTRADICTS / FLAGS — needs live verification

1. **`+0x12C` meaning differs between struct and pool.**
   - In the **char struct**, sheet calls +0x12C `Unknown_0x012C`, "seems to be always 1."
   - In our **object pool**, sprite_id is at `O+0x12C` (relative to the owner-pointer word).
   These are DIFFERENT structures — pool objects are not char structs — so there's no real
   conflict, but the coincidence is a trap. Our pool's `O+0x12C` is NOT the char struct's
   +0x12C. The sheet has **no object-pool map at all** (it only documents the 6 player
   structs + globals), so it neither confirms nor denies our pool layout. Our object-pool
   discovery (owner-ptr scan, O+0xC8 screen_x, O+0xCC screen_y, O+0x12C sprite_id) remains
   **unique to our RE** and unvalidated by this source.

2. **`0x..289621` label conflict.** Our CLAUDE.md: `match_sub_state`. Sheet:
   `Frame_Skip_Counter` ("displays frame values 1-4, 4=skipped"). Both could be true if the
   byte is reused, but worth a live check — if it's actually the frame-skip counter, our
   "match_sub_state" naming is wrong. (Sheet's real match-state is `Match_Tracker @ 0x..2895F0`.)

3. **P1/P2 combo addresses look swapped** in Player1And2Addresses (P1 points into the P1C2
   region, P2 into the P1A region). Likely a sheet typo; verify before trusting.

4. **Stage ordering** — sheet's stage list is selector-order; our `stage_id @ 0x8C289638`
   may use a different raw index. Cross-check the value we ship.

### BOTTOM LINE for the sprite client

The sheet is an excellent **independent confirmation** of the player-struct half of our RE
(sprite_id, screen_x/y, palette, all assembly pointers, base/stride) and hands us several
**new render levers** (per-char sprite scale, camera-Z zoom, match-state gating, second
GFX pointer). It does **not** document the multi-object pool — our core 2026-06-05 discovery
(rendering capes/effects/projectiles from pooled objects via owner-ptr scan) is still
ours alone and still needs the live verifications listed in 00-README.md.
