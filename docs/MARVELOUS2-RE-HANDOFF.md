# marvelous2 RE — Findings & Handoff

> **Status: research complete, build-out pending (2026-06-05).** Branch `feat/rom-asset-probe`.
> A community SH4 disassembly of MVC2 was analyzed by four expert agents. It **cracked the
> sprite pixel codec** and **fully mapped the effect/projectile object pool** — two of the
> three open keystones for the ROM-asset / sprite client. This doc is the pick-up point:
> read it, then act on §5 (integration) or §6 (contribute-back).
>
> Companion docs: [ROM-ASSET-CLIENT.md](ROM-ASSET-CLIENT.md) · [ROM-ASSET-CLIENT-PLAN.md](ROM-ASSET-CLIENT-PLAN.md) ·
> [MVC2-MEMORY-MAP.md](MVC2-MEMORY-MAP.md) (the marvelous2 facts are merged into its
> "CROSS-REFERENCE & MERGE" section) · [re-catalog/00-README.md](../re-catalog/00-README.md).

---

## 1. What marvelous2 is

[github.com/mountainmanjed/marvelous2](https://github.com/mountainmanjed/marvelous2) — a **full
SH4 disassembly of Marvel vs Capcom 2, NTSC-U Dreamcast** ("marvelous2" = Marvel…2). Confirmed
ours by an exact memory-map match (`player_start 0x8C268340`, 6 slots, `sprite_id 0x144`,
`screen 0xE0/0xE4`, `health 0x420`, all `Dat_*` pointers).

- **Cloned locally** at `/home/tris/projects/maplecast-flycast/marvelous2/` — **gitignored**
  (`marvelous2/` is in `.gitignore`; its `build/` reassembles to the ROM). Reference only.
- **Structure:** `memory/pl_mem.asm` + `memory/work.asm` = the only *labeled* files (437 lines);
  `char_prg/code/S_PL00..S_PL3A.asm` = per-character SH4 programs; `build/bank01..1c.asm` = the
  full ROM disassembled (~981k lines, **~141k auto `loc_*` names, only 82 semantic labels**).
- **⚠️ Legal:** disassembled copyrighted code. **Read for facts, reimplement clean-room, never
  vendor it or its `build/`, never commit decoded game assets.** (Same rule as ROMs in CLAUDE.md.)

---

## 2. KEYSTONE FINDING — the sprite pixel codec is cracked

The `PLxx_DAT` GFX pixel codec (the #1 open item, prerequisite for decoding sprites from the
**user's own ROM** → ship zero copyrighted assets) was **never** a bespoke 4bpp RLE. It is a
**flag-bit LZSS over 16-bit little-endian words**.

- **Decoder:** `loc_8c03552a` at [marvelous2/build/bank03.asm:12740](../marvelous2/build/bank03.asm)
  (~60 SH4 instructions). Calling convention: **`r4` = compressed src ptr, `r5` = output dest
  ptr**, no length arg (self-terminating).
- **Data flow:** `PLxx_DAT` loaded to RAM (`pl_A_datfile 0x0C420000`, …) → staged into GFX work
  buffer `0x0CC00000` → `loc_8c03552a` decompresses → texture-upload staging
  `Texture_Decompress_Buffer 0x0CE60000`.
- **Algorithm (clean-room description):** the stream is a sequence of u16 LE words.
  1. **Flag refill:** when the 16-bit flag counter is exhausted, read one control word.
  2. **Per flag bit:**
     - **clear → literal:** copy one u16 verbatim, dest += 2.
     - **set → token word:** top 5 bits = length/count code (if 0 ⇒ real count in a *following*
       word — extended length); low 11 bits (`& 0x7FF`) = operand:
       - operand == 0 → **zero/transparent word-fill** of the zero value for `count` words.
       - operand != 0 → **back-reference**: `offset = operand << 1` (word units); `src = dest −
         offset`; copy `count` words forward from already-decoded output (LZ window copy).
     - termination when both fields resolve to 0.
  So: flag-bit LZSS with literals, transparent fills, and output-window back-refs. The "4bpp-ness"
  is in the *decoded* word stream (indexed texels), **not** in the compression layer.
- **Effort to port:** LOW (~40 lines JS/C). **Only unknowns:** copy-length off-by-one
  (`count` vs `count+1/+2`) and the offset shift direction — both **brute-forceable in an hour**
  against our oracle.
- **Oracle:** the community indexed rips `PLxxDAT/<sprite_id>.png` (palette-indexed) are the
  decoded ground truth. Decode a part from a real `PLxx_DAT`, diff pixel-for-pixel.
- **Call sites / loader for tracing:** `bank03.asm:5069` (`loc_8c0322c0` wrapper),
  `bank03.asm:5221-5227` (`loc_8c0323b2` file-load path), GD-ROM loader `bank02.asm:19030+`.

**This supersedes** the "still OPEN / 1ST_READ.BIN 0x8C017A16 / Capstone" plan in
ROM-ASSET-CLIENT-PLAN §3a and the old memory note.

---

## 3. KEYSTONE FINDING — the effect/projectile object pool is fully mapped

The pool that holds capes, lightning, projectiles, super-overlays (everything that isn't one of
the 6 character bodies). We had mapped it empirically; the disassembly corrects and completes it.

- **Pool array:** **base `0x8C26AA54`, stride `0x1D0` (464 B), 256 nodes.** Initializer
  `loc_8c044dce` [bank04.asm:11725-11756](../marvelous2/build/bank04.asm). ⚠️ `work.asm`'s
  labeled `0x8C26AC24` is **node #1**, not the start.
- **Allocator:** free-list pop `loc_8c044f12` (`bank04.asm:11793`). Per-category free-list heads
  at `0x8C287A5C + cat*4`; per-category init vtable at `0x8C14DFEC + cat*4`.
- **Within-record layout (from record start = `0x8C26AA54 + slot*0x1D0`):**

  | offset | field | note |
  |---|---|---|
  | +0x03 | **category/type byte** | 0x07 effect, 0x05, 0x04… — set from allocator arg |
  | +0x04 | object sub-state/phase | switch var in the update fn |
  | +0x08 / +0x0C | **next / prev** list ptrs | the active doubly-linked list |
  | +0x10 | **per-frame update-fn ptr** | vtable; called by the pool tick |
  | +0x34 / +0x38 | world x / y (f32) | copied from owner @0x34 (stops tracking once detached) |
  | +0x80 / +0x84 | **OWNER player-struct ptr** (+copy) | → which of 6 chars → atlas + palette bank |
  | +0xC8 / +0xCC | **screen_x / screen_y** (f32) | |
  | +0x12C | **sprite_id (lo16)** | indexes the OWNER's atlas |
  | +0x130 | xflip / orientation | |

- **⚠️ Anchor correction:** our empirical scan keyed on the owner value and treated that field's
  address as `O`, so **`O` = record+0x80** and our prior offsets are shifted +0x80 from the true
  record base. **Must re-verify** (see §7).
- **Draw order — RESOLVED:** **no numeric z field exists.** Order = position in the active
  linked list (head-insert vs tail-insert primitives `loc_8c044fa2` / `loc_8c044fe0`). For the
  client, infer layer from `category@+0x3` + sprite_id range (cape behind body, lightning/super
  in front).
- **Projectiles — RESOLVED:** **same pool**, category-distinguished. A detached projectile keeps
  `owner@+0x80` but its `+0x34` world pos diverges from the owner. Re-scan by base+stride to find
  in-flight projectiles the old proximity scan missed. (**Assist *characters*** are real
  char-struct slots dispatched via the SPL jump table `0x8C289BD8 + slot*0x80`, NOT pool objects;
  their projectiles still use the pool.)
- **Spawn template:** every effect spawner (350+ sites across bank0e/0f/10/11) does the same:
  `jsr loc_8c044f12` → write update-fn@+0x10, sprite_id@+0x12C, owner@+0x80, copy world pos@+0x34
  from owner. Canonical example `bank11.asm:1` (`loc_8c1101b0`), `bank10.asm:2900`.

---

## 4. SUPPORTING FINDING — keyframe layout & RenderExtra confirmed

The anim tick `loc_8c034dee` ([bank03.asm:11567](../marvelous2/build/bank03.asm)) advances
`current_cell_data@+0x154` by **`0x14` = 20 bytes per keyframe** and copies 20 bytes into
**player+0x140**. This hard-confirms our anotak 20-byte keyframe decode:

- `Duration` @kf+0x02 → player+0x142 (anim_timer)
- `sprite_id` @kf+0x04 → player+0x144
- `RenderExtra` @kf+0x11 → **player+0x151** (live-readable!)
- `HitboxGroup` @kf+0x12 → player+0x152 (also builds hitbox ptr @0x16C)
- `EffectTrigger` = **bit 0x80 of kf+0**

`animations@+0x168` = keyframe-table base; loader `loc_8c034e8c` (`bank03.asm:11669`) indexes it
by group/anim. RenderExtra→effect dispatch goes through `loc_8c035162` (`bank03.asm:12114`); the
RenderExtra→spawner mapping is data-table-driven (values 12/13/39/64 etc. select effect timelines
in the PLDAT — matches our empirical per-char catalog, which stays the source for the numbers).

---

## 5. How to use it — prioritized integration plan

Read-only RAM reads + client rendering → **no byte-perfect-determinism exposure** for items 0–3 &
5 (only the GSTA *write* path would matter, untouched). Item 4 is the one "update all four
parsers together" wire bump (CLAUDE.md). Deploy via `deploy-headless.sh` / `deploy-web.sh` only
(backups); prod box is `149.28.44.118` (per memory), verify before deploy.

| # | Change | Files / functions | Effort | Risk |
|---|---|---|---|---|
| **0** | **Re-verify pool anchor** (gates #3) — ptrdump at `0x8C26AA54 + slot*0x1D0`, read owner@+0x80; confirm screen/sprite at +0xC8/+0x12C from absolute base | `MAPLECAST_PTRDUMP` probe | live cap | none |
| **1** | **Facing fix:** read `xflip @0x1D2`, not `0x110` (a copy). Likely root-cause of mirror asymmetry. No wire change | `gamestate.cpp` (`OFF_FACING`), `sprite-client.mjs` | XS | low |
| **2** | **Anisotropic scale:** replace constant `1.75×` with `CpsX=1.6667 / CpsY=2.1428` (`Sx/Sy`); add per-char `sprite_scale@0x50` only if specific chars look wrong | `sprite-client.mjs` (`spriteScale`, `render`, `buildDrawList`) | S | low, web-only |
| **3** | **Pool reader re-anchor:** rewrite `readObjects()` to seed `0x8C26AA54 + slot*0x1D0`, read owner@+0x80, category@+0x3, sprite@+0x12C, screen@+0xC8/+0xCC, xflip@+0x130. OBJS wire: 7→9 bytes/obj (+category +xflip). Client: category→layer ordering + additive-vs-alpha blend | `gamestate.{cpp,h}` `readObjects`/`ObjectState`; `mirror.cpp:1843` (OBJS emit, fix `48*7`→`48*9`); `sprite-client.mjs` `onOBJS`/`buildDrawList`; `sprite-gpu.mjs` blend split | M | low |
| **4** | **GSTA enrich:** add `stance@0x1F9`, `Flight_Flag@0x201`, `anim_flags@0x14A`, `render_extra@0x151`. Append as a trailing block (keeps 38-byte stride stable). Bumps `WIRE_SIZE` → **touches all 4 parsers** | `gamestate.{cpp,h}`; `sprite-client.mjs` `onGSTA`; `wasm_bridge.cpp`; `maplecast_wasm_bridge.cpp` | M | med (wire) |
| **5** | **Clean-room LZSS decoder** (the codec) → new `web/webgpu/pldat-codec.mjs` feeding `bake.mjs` as a build-time atlas generator. Output is ROM-derived → **never committed**. Replaces the community rip as atlas source | new `web/webgpu/pldat-codec.mjs` + `bake.mjs` | M + brute-force | low to system |

**Suggested order:** 0 (next time at the box) → 1 → 2 (both no-risk, no capture) → 3 → 4; 5 in
parallel as an offline track. Verify with the existing `MAPLECAST_TADBG=1` renderer-oracle
(logs per-object nearest-TA `z`/`blend`) and the `MAPLECAST_DUMP_TA=1` determinism rig once at
phase end.

---

## 6. Can we contribute back? Yes — mutually

marvelous2 is ~100% disassembled but ~0.06% semantically labeled; their README TODO is literally
"Figure out memory / Label the code." Their gaps = our strengths (live 60Hz behavioral RE).

**Net-new we can give them (they have nothing equivalent):**
- A **globals memory map**: camera `0x8C1F9CD8/CDC`, `frame_counter 0x8C3496B0`, `in_match
  0x8C289624`, `round_counter 0x8C28962B`, meter fill/level `0x8C289646/648/64A/64B`, combo
  `0x8C289670/672`.
- The **object-pool record layout** (they have a one-line comment).
- The **RenderExtra→effect table** + 20-byte keyframe encoding.
- The **palette/skin system** (PVR bank formula `16×(char_pair+1)+8×side`, ARGB4444) — absent.
- **Relabels for their explicit unknowns:** `health2 "might be red health??"` → red_health;
  `unk_01d0 "seems to control move"` → animation_state; `GameGlobalStart ;???` neighbor →
  engine_tick `0x8C268250`; etc.

**What they give us:** the actual code behind every behavior we inferred — the SPL char programs,
the codec implementation, `RngVal 0x8C16BC2C` (rollback-relevant), and ~30 struct fields we don't
read (buffs, immunity timers, DHC/assist state).

**Verdict:** a fully-labeled reassemble-to-ROM RE is a multi-year community effort, but a
**complete RE of the gameplay-relevant surface** (state + rendering + effects + skins) is
achievable now by merging the two.

**Contribution format (low-friction first):** a `memory/globals.asm` PR (addresses + one-line
semantics) → relabel notes for their uncertain fields → an `effects.md` data doc (RenderExtra
table + pool layout + keyframe encoding). **Constraints:** contribute addresses/semantics/behavior
ONLY — never MapleCast prod internals (topology, ports, relay/hub, SurrealDB). Credit the public
spreadsheet/trainer provenance to keep the clean-room boundary clean.

**Reconcile-jointly items (don't assert over them):** they call `0x8C289621` "Frameskip Counter",
we call it `match_sub_state`; `STG_ID 0x8C26A95C` vs our `stage_id 0x8C289638` (two refs).

---

## 7. Open verification (do before shipping #3)

The one thing the experts flagged as needing a live capture, not blind trust: **the pool
anchoring tension.** Our empirical offsets are internally consistent but measured from the
owner field (+0x80); the disasm gives them from the absolute record base. Re-run the ptrdump
anchored at `0x8C26AA54 + slot*0x1D0`, read `owner@+0x80`, and confirm whether `screen@+0xC8` /
`sprite_id@+0x12C` hold from the absolute base or are themselves +0x80-shifted. **Do not ship the
`readObjects()` rewrite until this one capture confirms it.** (Per memory: don't run live captures
assuming the user is mid-match — confirm presence first.)

---

## 8. Where the facts live now
- **Merged into docs:** [MVC2-MEMORY-MAP.md](MVC2-MEMORY-MAP.md) "CROSS-REFERENCE & MERGE" section
  (full struct, pool base/stride correction, codec buffers, scale constants, globals, char IDs);
  [re-catalog/00-README.md](../re-catalog/00-README.md) (struct table + corrected pool note +
  resolved open verifications).
- **Memories:** `reference-marvelous2-disasm` (the repo + key facts), `reference-pldat-sprite-format`
  (codec now marked CRACKED).
- **Source citations:** all `marvelous2/build/bankNN.asm:line` references above are into the local
  clone; re-grep there to extend any trace.
