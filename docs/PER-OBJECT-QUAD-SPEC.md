# Per-Object Quad Capture — Technical Spec (2026-06-08)

Author: mvc2-sh4-re-expert agent. Status: **RE + design, no production code**. Read-only RE only.

Goal: attribute every rendered quad to **the object that drew it by RENDER-CALL BOUNDARY**, not by 160 px screen proximity. This delivers (a) clean per-frame per-object SCREEN quads so satellite/cape anchors can be measured exactly, and (b) the foundation for step C (the Oracle-built assembly atlas → emitter).

Every structural claim cites `marvelous2/build/bankNN.asm` (label name == SH4 PC) or a flycast source file. Items I could not confirm from the disasm/source are marked **[INFERRED]** or **[UNKNOWN — test]**.

---

## 0. TL;DR of the chosen mechanism

At each object's quad-emit entry we read the game's **own RAM display-list write cursor** (`r14` in `loc_8c033d78`, the per-character/per-object quad emitter), recording `(object_node, cursor_start, quad_count)`. Post-frame in `serverPublish`, after `ta_parse`, we segment the parsed PolyParam list by per-object quad counts in submission order. Because flycast appends PolyParams in TA-submission order and the game submits the display list in the order it was built, object A's `[i,j)` PolyParams and object B's `[j,k)` are contiguous ranges — segment by counts, attribute exactly.

This **replaces** the current `attributeScreenQuads()` 160 px nearest-anchor heuristic (`maplecast_oracle_hook.cpp:493`) with count-based segmentation.

**The single most important new RE finding in this spec** (and a contradiction with the existing Oracle's recorded conclusion): `loc_8c033d78` / `loc_8c033e90` is **NOT load-time-only**. It is driven **per character, every in-match frame** by the render driver `loc_8c03dcba` → loop `loc_8c03dd6c` (6× stride `0x5A4` from `0x8C268340`). The "fires once at frame 2568" note in `maplecast_oracle_hook.cpp:50-56` is wrong, OR the prior capture hooked a path that the in-match gate/window suppressed. **This must be re-tested first (Phase 0) — the whole spec depends on it.**

---

## 1. The render pipeline (CONFIRMED from bank03.asm)

There are **two distinct per-frame walks** over the characters/objects. Conflating them was the prior error.

### 1a. The slot-table walk = POSITION pass (`loc_8c0308c2`, "Render_sprites", bank03:1200)

```
loc_8c0308c2: slot table base = 0x8C2895E0 (count), 0x8C287DE0 (ptr array), stride 0x180
  loc_8c0308e6:  r4 = node;  r0 = byte @ node+0x3 (category)
                 tst r0,r0; bf loc_8c0308fc
                   category == 0 (T=1, bf NOT taken) -> bsr loc_8c03093c  (Render Main Sprite = BODIES)
                   category != 0 (T=0, bf taken)     -> bsr loc_8c030af8  (SAT/EFFECT path)
```

> **DISCREPANCY with existing code (must fix before relying on it):** the comment in
> `maplecast_oracle_hook.cpp:71-73` says "category==0 → loc_8c03093c (bodies)" and
> "category!=0 → loc_8c030af8" — the *routine mapping is correct*, but the literal
> branch logic written there ("bf loc_8c0308fc … category != 0 → bsr loc_8c030af8 — line 1236")
> describes the branch backwards relative to the disasm. The disasm at bank03:1222-1236 is:
> `tst r0,r0` then `bf loc_8c0308fc`. `tst` sets T=1 when r0==0, and `bf` branches when T==0.
> So **category==0 → `bsr loc_8c03093c`** (fall-through), **category!=0 → `loc_8c0308fc` → `bsr loc_8c030af8`**.
> Net mapping (bodies vs satellites) is unchanged and matches the existing hook; only the
> in-code rationale string is inverted. Cosmetic, but fix it so the next reader trusts it.

- `loc_8c03093c` "Render Main Sprite" (bank03:1281): `r4=node→r14`; cull byte @+0x12C (`loc_8c030aa4=0x012c`); world pos floats @+0x34/0x38/0x3C; world→screen transform `bank12.loc_8c1216c0` + `bank12.loc_8c122560`; **writes screen_x @+0xE0 (`loc_8c030aa6=0x00e0`), screen_y @+0xE4 (`loc_8c030aa8=0x00e4`)**; scale @+0x50/0x54 × `CpsXScale/CpsYScale`; xflip copies @+0x130→+0x134; then `jsr loc_8c034bea` (r4=node) — the **anim/cell setup** (reads sprite_id @+0x144 `loc_8c034c1c=0x0144`, checks `0xFF` terminator; dispatches `loc_8c0348c8` / `loc_8c0344d4`). **`loc_8c03093c` does NOT itself emit quads** — it sets screen_xy and advances anim state.
- `loc_8c030af8` (bank03:1526) "satellite/effect": same shape — cull @+0x12C, world pos @+0x34/38/3C, transform `bank12.loc_8c122560`, **writes screen_x @+0xE0 / screen_y @+0xE4** (`loc_8c030c68=0x00e0`, `loc_8c030c6a=0x00e4`), then `jsr` into the same anim/cell family (`loc_8c030c4a`). Also does NOT emit quads itself.

So the slot-walk = **placement + animation tick** per object; both body and satellite write `screen_xy @+0xE0/+0xE4`. This is what the existing Oracle correctly hooks as `OBJ_BEGIN` (0x8C03093C) and `SAT_BEGIN` (0x8C030AF8). **Keep these hooks — they remain the authoritative per-object anchor.**

### 1b. The character-base walk = QUAD-EMIT pass (`loc_8c03dcba` → `loc_8c033d78`, bank03)

This is the crux that the prior pass missed. The per-frame render driver:

```
loc_8c03dcba (bank03:33142)  — per-frame render driver, called bsr from the in-match
                                game-mode handler at bank03:34780.
  gate: jsr bank02.loc_8c0279a4 (renderable-state gate, +0x14==0x40 check) else return
  loc_8c03dd6c (33246): loop i = 0..5  (r10=6)
     r11 = 0x05A4 (char stride);  base = 0x8C268340 (P1C1, loc_8c03de1c)
     r13 = base + i*0x5A4
     r5  = char_id byte @ r13+0x55C  (loc_8c03de10=0x055c)
     jsr loc_8c031fa0 (r4=r13)              ; pre-pass
     jsr loc_8c033d78 (r4=r13 = node, r5=i) ; THE QUAD EMITTER  (loc_8c03de14)
```

`loc_8c033d78` (bank03:9092) is the **per-frame display-list builder for one character**:

```
loc_8c033d78:
  r10 = r4 (node base)
  r4  = *(r10 + 0x180)                       ; loc_8c033e0e=0x0180  -> the per-char draw block ptr
  r14 = r4 + 0x0E20                           ; loc_8c033e14=0x0e20  -> WRITE CURSOR (display list)
  r8  = 0x0CE60000                            ; loc_8c033e28        -> texptr base (decode buffer)
  ... iterate cells (count from cell data @ +0x160 / 0x1f9d9c table) ...
  loc_8c033e90 ("reading sprite data"): for each part, emit a 16-byte quad at r14:
        mov.w r3,@r14          ; +0x0  w = (databyte<<3)
        mov.w r0,@(0x2,r14)    ; +0x2  h = (databyte<<3)
        mov.l r3,@(0x4,r14)    ; +0x4  attr
        mov.l r8,@(0x8,r14)    ; +0x8  texptr (r8, advances by blob size r9)
        mov.l r12,@(0xC,r14)   ; +0xC  palptr
        add 0x10,r14           ; cursor advances 16 bytes per quad   <-- THE PER-QUAD CURSOR
        add r9,r8              ; texptr advances by decoded blob size
        add 0x01,r11           ; r11 = running quad count
  loc_8c033f14: write 0x00FF/0x00FF sentinel quad (terminator) at r14
  loc_8c033f44 (finalize): store the per-object results into two parallel tables:
        *(u16)(0x8C26AA24 + i*2) = r11        ; loc_8c033f88 -> QUAD COUNT for object i
        *(u32)(0x8C26AA34 + i*4) = displaylist ; loc_8c033f8c -> DISPLAY-LIST PTR for object i
```

**This is the per-frame display list the earlier work saw** (r14 cursor, 16-byte quads `{w,h,attr,texptr,palptr}`). It is NOT the load-time atlas decode — same routine, but it runs **per character per frame** under `loc_8c03dcba`. The 16-byte record layout exactly matches the existing hook's documented `{w@+0,h@+2,attr@+4,texptr(r8)@+8,palptr(r12)@+C}` (bank03 9275-9284, cursor r14).

**[INFERRED] The "load-time decode" the prior agent saw is the SAME emitter** invoked once during the cell-processor jump-table dispatch `loc_8c033d78` from the *load path* (`loc_8c03e728` calls it with r5=char_id during character load, bank03:34708-34716). The emitter is reused for both load-time atlas decode AND per-frame display-list build. The previous capture window only caught the load instance because of [UNKNOWN — see Phase 0].

### 1c. The two parallel result tables (CONFIRMED addresses, consumer INFERRED)

| Table | Address | Stride | Holds |
|---|---|---|---|
| Quad count | `0x8C26AA24` | 2 (u16) | `r11` = number of quads object `i` emitted this frame |
| Display-list ptr | `0x8C26AA34` | 4 (u32) | pointer to object `i`'s 16-byte-quad list (`= *(node+0x180)+0xE20`) |

There is a sibling cluster at `0x8C26AA54` (object-pool base per `re-catalog/00-README.md`, referenced by bank04:11748). **[INFERRED]** a later routine (the TA submit / bulk-DMA, likely bank04) walks these tables and ships each object's quad list to the PVR TA FIFO. The draw routines themselves do **no** SQ / `0x10000000` writes (confirmed — no store-queue writes in `loc_8c033d78`/`loc_8c033e90`), so submission is a separate bulk pass. **The exact submit routine is [UNKNOWN — test]; it is the linchpin for the order-preservation guarantee (§3).**

---

## 2. WHERE the per-frame display list lives (the crux, resolved)

- **Per-object display-list buffer:** `*(node+0x180) + 0x0E20`, written 16 bytes/quad by cursor `r14` in `loc_8c033d78`. Distinct from the LZSS decode staging `0x0CE60000` (which holds *texels*, walked by `r8=texptr`). The earlier "~0x0C56xxxx" cursor sighting is this per-object buffer for a specific character (`*(node+0x180)` resolves into that region).
- **The cursor IS monotonic per quad** (`add 0x10,r14`) and **`r11` is the per-object quad count**, stored to `0x8C26AA24[i]` at finalize. So **a per-object delta = `r11` at finalize = `0x8C26AA24[i]`** — we don't even need to diff the cursor; the game hands us the count directly.
- **LOAD-TIME decode vs PER-FRAME build:** same routine `loc_8c033d78`, different driver. Per-frame: `loc_8c03dcba`→`loc_8c03dd6c` (6 chars). Load-time: `loc_8c03e728` (single char during load). The decode-buffer base `0x0CE60000` is the texptr source in **both** — that's why the prior agent saw "no screen coords": the *texptr* has no screen coords by design; the **screen coords come from the slot-walk's +0xE0/+0xE4**, not from this routine. The two passes are meant to be joined (anchor from 1a, parts from 1b) — which is exactly what this spec does.

---

## 3. Display-list → TA → parsed-quads: IS ORDER PRESERVED? (CONFIRMED for op/pt; CONFIRMED-with-caveat for tr)

flycast `ta_parse` builds `rend_context`:
- PolyParams are appended in **TA submission order** via `emplace_back()`/`push_back()` into `global_param_op` / `global_param_pt` / `global_param_tr` (`core/hw/pvr/ta_vtx.cpp:588, 693, 1148`). `pp.first = verts.size()` at open, `pp.count = verts.size() - first` at close (`ta_vtx.cpp:593, 689`) — verts are contiguous and sequential per PolyParam.
- **OP and PT lists are never reordered.** Only the **TR list** is sorted, and only when `pass.autosort` is true (`ta_vtx.cpp:1238-1245`).
- **Even for TR, the sort does NOT reorder the `global_param_tr` vector.** `sortTriangles`/`sortPolyParams` produce a separate **sorted index** (`sorted_idx`) for *draw order*; the `PolyParam` vector itself stays in submission order, and `pp.first/pp.count` still point at the submission-order verts. So **iterating the PolyParam vectors (as `collectScreenQuads()` already does: `collect(op); collect(pt); collect(tr)`) yields submission order for all three lists.**

**Conclusion:** if the bulk-DMA submits the per-object display lists **in object order** (object 0's quads, then object 1's, …), then the parsed PolyParam vectors are contiguous per object, and **count-segmentation works.** The remaining risk is purely: *does the submit pass preserve object order, and within an object are op/pt/tr interleaved or grouped?* — see §6 unknowns.

> **Re-examining the prior dismissal (`FRAME-ORACLE-SPEC.md:8`):** "cursor-segmentation doesn't work because at OBJ_BEGIN time flycast's TA write cursor (`ta_tad.thd_data`) hasn't advanced." **That was the WRONG cursor.** `ta_tad.thd_data` is flycast's TA-FIFO ingest pointer, which only advances during the bulk-DMA submit (after the whole draw walk). The **right** cursor is the **game's own RAM display-list write pointer `r14` in `loc_8c033d78`**, which advances per quad *as each object is processed*, and is finalized into `0x8C26AA24[i]` (count) — available the instant `loc_8c033d78` returns for object `i`. The prior agent measured the FIFO, concluded "doesn't advance," and dismissed the approach. The game's RAM cursor is the correct signal. **This spec revives count-segmentation on the correct cursor.**

---

## 4. Existing Oracle infrastructure — what stays, what changes

| Component | File / location | Verdict |
|---|---|---|
| Compile-time block-entry `GenCall` | `core/rec-x64/rec_x64.cpp:135-164` | **KEEP** — generic; new hooked PCs covered automatically |
| Forced block boundary at hooked PCs | `core/hw/sh4/dyna/decoder.cpp:975-991` | **KEEP** — generic |
| `mc_isHookedPC` PC-mask (`& 0x1FFFFFFF`, P0/P1 alias) | `maplecast_oracle_hook.cpp:286-305` | **KEEP** — add the emitter-return PC (§5) |
| `OBJ_BEGIN` 0x8C03093C / `SAT_BEGIN` 0x8C030AF8 hooks → `enrichObj` + `resolveOwner` (screen_xy/scale/sprite_id/owner) | `maplecast_oracle_hook.cpp:324-361` | **KEEP** — these remain the authoritative per-object anchor list |
| `s_objs[]` per-object record (node-keyed `findOrCreateObj`) | `maplecast_oracle_hook.cpp:163-271` | **KEEP + EXTEND** — add `qStart`, `qCount` (display-list cursor + count) |
| `QUAD_DONE` 0x8C033EC0 per-quad capture (sub-flag) | `maplecast_oracle_hook.cpp:368-409` | **REPURPOSE** — instead of (or in addition to) per-quad read, capture the **finalize** values (count `r11`, cursor base) — see §5 |
| `collectScreenQuads(rc)` — TA→screen quads (de-index op/pt/tr, sprite filter) | `maplecast_oracle_hook.cpp:419-483` | **KEEP** — still how we turn TA into screen quads; only the *attribution* changes |
| `attributeScreenQuads()` — 160 px nearest-anchor | `maplecast_oracle_hook.cpp:493-511` | **REPLACE** with count-segmentation (§5) |
| `mc_oracle_frameFlush` — ta_parse + emit jsonl | `maplecast_oracle_hook.cpp:513-668` | **KEEP shape**, swap attribution call |
| serverPublish flush wiring | `maplecast_mirror.cpp:1757-1764` | **KEEP** — already passes live `ctx`, once/frame, post-walk |
| `MAPLECAST_FRAME_ORACLE` position-correlation path | `maplecast_mirror.cpp:2465-2588` | **LEAVE** — the older heuristic instrument; independent |

What changes is small and surgical: **add a per-object quad-count capture at the emitter finalize, and replace `attributeScreenQuads` with a count-walk.**

---

## 5. What to BUILD / ADD (exact)

### 5.1 New hooked PC — the emitter finalize

Hook the **return/finalize** of `loc_8c033d78` so we read the per-object count `r11` and the cursor base **after** the object's quads are written but before the next object overwrites the shared scratch. Two options:

- **Option A (preferred — read the game's own table):** hook `0x8C033F44` (`loc_8c033f44`, the finalize block). At entry `r11` = quad count for this object, `r5/[0x28,r15]` = object index `i`, cursor base = `*(node+0x180)+0xE20`. Even simpler: at any post-finalize point, **just read `0x8C26AA24[i]` (count) and `0x8C26AA34[i]` (ptr)** for each of the 6 slots — these tables are authoritative and persist for the whole frame. **No per-PC hook needed at all for the count** if we read these two tables once per frame in `frameFlush` (after the draw walk, before ta_parse). **This is the leanest path — prefer it.**
- **Option B (per-quad, exact):** keep `QUAD_DONE` 0x8C033EC0 hooked (existing) and count per-object via `r10`=node. Higher overhead, but gives per-quad texptr/palptr if needed for step C.

**Recommendation:** use **Option A table-read** for segmentation (count per object), and keep **Option B sub-flag** OFF by default but available for step C's part-level texptr/palptr capture.

The object index `i` (0..5) in the count table maps to the 6 char bases `CHAR_BASE[]` (already in the hook). Satellites: the satellite quad emission path **[UNKNOWN — test]** — confirm whether `loc_8c030af8`'s cell walk also routes through `loc_8c033d78` with its own index, or a separate pool emitter. See §6.

### 5.2 The segmentation logic (replaces `attributeScreenQuads`)

The hard part: the **count table is in object/character order (0..5)**, but the **PolyParam list is in TA-submission order**. We must map "object i emitted N_i quads" onto contiguous PolyParam ranges. Two routes:

- **Route 1 — submission-order counts (cleanest if obtainable):** if we can capture the **submission order** of objects (the order the bulk-DMA ships them) and each object's quad count, then walk the parsed PolyParam vector summing counts: object with submission-rank 0 owns PolyParams `[0, N_0)`, rank 1 owns `[N_0, N_0+N_1)`, etc. **[UNKNOWN — test]** whether submission order == character order (0..5) or follows the slot-table category/layer order. Resolve in Phase 1.
- **Route 2 — count-bounded nearest-anchor (robust hybrid, recommended first):** keep the screen-position anchor from `OBJ_BEGIN`/`SAT_BEGIN`, but **bound each object to its known quad count** `N_i`: assign the N_i parsed quads *closest to object i's screen_xy* to object i (greedy, nearest-first, each quad used once). This fixes the two failure modes of the pure 160 px heuristic (over-grab from a neighbor, and missing far parts) because the **count is ground truth**. Degrades gracefully if submission order is ambiguous.

**Build Route 2 first** (low risk, uses data we can definitely get — counts + anchors), then upgrade to Route 1 once Phase 1 confirms submission order.

### 5.3 Decoder force-splits needed

- `0x8C033F44` (if Option A per-PC) — **[INFERRED]** likely mid-block; needs the same `decoder.cpp` force-split treatment as `0x8C033EC0`. If using the **table-read in frameFlush** (preferred Option A), **no new force-split is needed** — we read `0x8C26AA24`/`0x8C26AA34` via `addrspace::read*` in `frameFlush`, zero new hooks.
- Existing splits at `0x8C03093C`, `0x8C030AF8`, `0x8C033EC0` stay.

### 5.4 Output shape (jsonl / wire)

Extend the existing per-object record in `/dev/shm/mc_oracle_hook.jsonl` (no wire-format change — this is an offline instrument):

```json
{"frame":N,"objects":[{
  "node":"0x..","slot":0,"kind":"body|satellite","sprite_id":735,
  "owner_slot":0,"owner_cid":42,
  "screen_xy":[318,224],"scale":[1.75,1.75],"facing":0,"category":5,
  "dl_quad_count":12,                         // 0x8C26AA24[i]  (game-truth count)
  "dl_ptr":"0x..",                            // 0x8C26AA34[i]
  "seg_method":"count-bounded|submission-order",
  "screen_quads":[{"x":..,"y":..,"w":..,"h":..,"u":[..],"v":[..],"z":[..],
                   "vram_addr":"0x..","tcw":"0x..","fmt":..,"tex_wh":[..],"blend":[..]}],
  "tex_src":{"gfx1_ptr":"0x..","pal_ptr":"0x..","region":".."}
}],
"unassigned":[{...}]}
```

New fields: `dl_quad_count`, `dl_ptr`, `seg_method`. `screen_quads` now segmented by count, not 160 px radius.

### 5.5 Offline tool consumption

- `_oracle/oracle_attribute.py` — update to read `dl_quad_count` and validate `len(screen_quads) ≈ dl_quad_count` per object (the **self-check**: parsed-quad-count should match game-truth-quad-count, modulo the sprite filter dropping HUD/clears).
- Cape/satellite anchor measurement: each satellite is now its own `OBJ` with its own `screen_xy` + its own segmented `screen_quads` → measure `(quad_centroid − screen_xy)` directly = the exact anchor offset. Feed into `bake.mjs` per-object anchor.
- Step C: `dl_ptr` + `dl_quad_count` give the **exact per-object part list** (16-byte records `{w,h,attr,texptr,palptr}`) → the Oracle-built assembly atlas. Read the 16-byte records straight from `dl_ptr` (sub-flag) to enumerate every part the object drew, keyed by sprite_id.

---

## 6. RISKS / GAPS / UNKNOWNS (each with a test)

| # | Unknown | Why it matters | How to test |
|---|---|---|---|
| **R1** | **Is `loc_8c033d78` truly per-frame?** The existing hook recorded "fires once at frame 2568." | If load-time-only, the whole count approach collapses. The disasm (`loc_8c03dcba`→`loc_8c03dd6c`, 6× per frame, called from the in-match game loop bank03:34780) says **per-frame** — but the live capture said once. | **Phase 0 probe:** add a fire counter on `0x8C033D78` block entry (or read `0x8C26AA24[0..5]` each frame in frameFlush and log non-zero counts). Play an in-match frame. If counts are non-zero every frame → per-frame confirmed; the prior "once" was a capture-window/gate artifact. |
| **R2** | **Does the bulk-DMA preserve object order into the TA?** | Count-segmentation (Route 1) needs object i's quads contiguous and in a known order. | **Phase 1 probe:** capture per-object `dl_quad_count` AND `total parsed sprite-PolyParams`. If `Σ dl_quad_count ≈ N_polyparams` AND the cumulative-count boundaries line up with object screen-position clusters, order is preserved. If they sum but don't align positionally → order differs (use Route 2). |
| **R3** | **Do op/pt/tr interleave within one object, or is each object single-list?** | A character body may emit some opaque + some translucent parts; if interleaved, a single contiguous PolyParam range per object spans list boundaries. | **Phase 1:** for a known single object (1 char in training), dump which lists its quads land in. If all in one list → simple. If split → segmentation must be per-list (count split across op/pt/tr by the game's per-quad list assignment, which we'd need from the attr/tsp of each 16-byte record). |
| **R4** | **Autosort/TR reorder.** Confirmed the PolyParam *vector* stays in submission order (only `sorted_idx` reorders). | If we ever segment by `sorted_idx` instead of the PolyParam vector we'd break. | Already mitigated: `collectScreenQuads` iterates the **PolyParam vectors** (`ta_vtx.cpp` append order), not `sorted_idx`. Keep it that way. Verify by asserting segmentation uses vector index, never sorted index. |
| **R5** | **Culled objects emit 0 quads.** `loc_8c03093c` early-returns on cull byte @+0x12C; the emitter may still write a sentinel-only (count 0) entry. | A 0-count object must consume 0 PolyParam slots, else everything downstream shifts. | **Phase 1:** verify `0x8C26AA24[i]==0` for off-screen/inactive chars, and that 0-count objects own an empty PolyParam range. Route 2 (count-bounded) is immune; Route 1 must skip 0-count objects in the cumulative walk. |
| **R6** | **Satellites' emit path.** Body quads come via `loc_8c03dcba`→`loc_8c033d78` (6 char bases). **Where do satellite/pool nodes' quads get emitted?** Pool base `0x8C26AA54` (re-catalog). | Satellite quad counts may be in a different table or a pool walk, not `0x8C26AA24[0..5]`. | **Phase 1:** with a projectile/cape on screen, check whether `0x8C26AA24` has >6 entries or there's a parallel pool-quad table. Trace the pool render driver (bank04 near `loc_8c0450c0`, `0x8C26AA54`). Until resolved, satellites use Route 2 (count from a per-node read or fall back to anchor-only). |
| **R7** | **Multi-pass / `render_passes`.** flycast supports multiple TA passes per frame (`ta_vtx.cpp:1297` `render_passes`). MVC2 [INFERRED] single pass. | Multi-pass would re-segment counts per pass. | **Phase 1:** log `ctx->rend.render_passes.size()`. Expect 1 for MVC2. If >1, segment per pass. |
| **R8** | **The submit routine itself is [UNKNOWN].** We inferred a bulk-DMA reads `0x8C26AA24/AA34`. | The order/grouping guarantee (R2) lives in that routine. | **Phase 2 (only if R2 ambiguous):** trace the consumer of `0x8C26AA34` (search bank04 for reads of `0x8C26AA34`/`0x8C26AA24`; the `0x8C26AA54` ref at bank04:11748 is the pool, nearby). Confirm it walks objects 0..5 in order and DMAs each list head→tail. |

---

## 7. Phased BUILD PLAN (de-risk first)

**Phase 0 — Confirm the emitter is per-frame (gates everything).**
- Add a read of `0x8C26AA24[0..5]` (u16 counts) + `0x8C26AA34[0..5]` (ptrs) in `mc_oracle_frameFlush`, BEFORE `ta_parse`. Log per-frame: which slots have non-zero counts, and the sum.
- Play an in-match training frame. **PASS = counts non-zero every in-match frame.** If they're zero except at load, R1 fails → escalate (the per-frame driver isn't this one; re-RE the in-match render path).

**Phase 1 — Validate count-vs-TA alignment (the core de-risking probe).**
- Same frameFlush: after `ta_parse` + `collectScreenQuads`, log `Σ dl_quad_count` vs `s_nscreen` (parsed sprite quads). Also log, per object, `dl_quad_count` and the count of screen quads within 120 px of its `screen_xy`.
- **PASS = the sums track (within the sprite-filter slop) AND per-object counts roughly match the positional cluster sizes.** This confirms R2/R3/R5 empirically without writing the full segmenter.
- Capture `render_passes.size()` (R7) and whether a single char's quads span op/pt/tr (R3).

**Phase 2 — Implement Route 2 (count-bounded nearest-anchor).**
- Replace `attributeScreenQuads()`: for each object, claim its `dl_quad_count` nearest unclaimed parsed quads (greedy nearest-first). Emit `seg_method:"count-bounded"`, `dl_quad_count`, and per-object `screen_quads`.
- Validate cape/satellite anchors: each satellite now has its own segmented quads → measure exact anchor offset. **This is the immediate win.**

**Phase 3 — Upgrade to Route 1 (submission-order) IF Phase 1 showed clean ordering.**
- Capture submission order (Phase 2 sums + R8 trace if needed), walk PolyParams by cumulative count, emit `seg_method:"submission-order"`. Pure boundary segmentation, no position heuristic at all.

**Phase 4 — Step C enablement.**
- Turn on the per-quad sub-flag (Option B / `dl_ptr` 16-byte-record read) to enumerate each object's part list (`{w,h,attr,texptr,palptr}` × count) keyed by sprite_id → build the Oracle assembly atlas → emitter.

---

## 8. How this enables the two deliverables

1. **Exact cape/satellite anchor measurement (immediate win).** Today satellites borrow the body anchor or get mis-grabbed by the 160 px radius. With count-bounded segmentation, each `SAT_BEGIN` object owns exactly its `dl_quad_count` quads near its own `screen_xy` → `anchor_offset = quad_centroid − screen_xy` is measured per object, per frame, cleanly. Feed into `bake.mjs` per-object anchor (replaces the degenerate body-relative anchor).
2. **Step C — Oracle assembly atlas → emitter.** `dl_ptr` + `dl_quad_count` (and the per-quad sub-flag) give the **exact ordered part list** the game drew for each `sprite_id`: the 16-byte `{w,h,attr,texptr,palptr}` records. This is the ground-truth input to reimplement `loc_8c033e90`'s assembly client-side (the one routine `MVC2-RECONSTRUCTION-SPEC.md` says still needs porting) — now validated against the game's own per-frame output rather than the offline PLDAT guess.

---

## 9. Confirmed-vs-inferred ledger

**CONFIRMED (disasm/source cited):**
- Slot-walk dispatch + body/satellite split (bank03:1200-1236); screen_xy @+0xE0/+0xE4 written by both (bank03 loc_8c030aa6/aa8, loc_8c030c68/c6a).
- Per-frame char-base walk `loc_8c03dcba`→`loc_8c03dd6c` (6× stride 0x5A4) → `loc_8c033d78` emitter, called from the in-match loop (bank03:34780).
- Emitter cursor `r14 = *(node+0x180)+0xE20`, 16 bytes/quad `{w,h,attr,texptr,palptr}`, `add 0x10,r14`, `r11`=count, sentinel 0x00FF (bank03:9092-9301).
- Finalize stores count→`0x8C26AA24[i]`, ptr→`0x8C26AA34[i]` (bank03:9403-9409).
- flycast PolyParam append order = submission order; only TR `sorted_idx` reorders, the vectors don't (ta_vtx.cpp:588/693/1148/1238-1255).
- Existing Oracle hook/decoder/rec_x64 mechanism (cited files/lines §4).

**INFERRED (flagged):**
- The load-time decode and per-frame build are the same routine `loc_8c033d78` under different drivers (load: loc_8c03e728; frame: loc_8c03dcba).
- A bulk-DMA submit reads `0x8C26AA24/AA34` and ships per-object lists to the TA in object order.

**UNKNOWN — must test (Phase 0/1):** R1 (per-frame reality), R2 (submit order), R3 (op/pt/tr interleave), R6 (satellite emit table), R8 (submit routine identity).
