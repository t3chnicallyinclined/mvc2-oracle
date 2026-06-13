# Option C PoC — lift MVC2's body walker SH4 → C, diff vs ground truth

Proof-of-concept for `docs/RENDER-REPLICA-PLAN.md` §8 "SMALLEST FIRST MILESTONE":
demonstrate the **lift-to-C transpiler** path by mechanically translating MVC2's
real per-frame body-render SH4 code to native C, running it, and diffing its output
against engine ground truth. This de-risks the whole "reproduce the render block
mechanically" thesis (Option C in the plan) — the FP/integer SH4 semantics, the
flat-RAM memory model, and the lifter — cheaply, as a **native C diff**, no wasm,
no Phase-0, no browser.

## Result — GO

| Validation | What it proves | Result |
|---|---|---|
| **Leaf `loc_8C11E460`** (bank11, 24 insns) | lifter + FP semantics on a self-contained function (zero input ambiguity) | **21/21 bit-exact** vs an independent `floorf` reference |
| **Transform core `loc_8c0347c8..loc_8c034864`** (the per-tile FP+integer screen math, simple path) | the lifted `float`/`fmul`/`fadd`/`exts.w` chain reproduces the engine's per-part `screenX/screenY` | **18/18 bit-exact** (X and Y) vs reference float; **within the ASMTRACE's own 0.01px logging quantization** vs the real engine output |
| **Full walker `loc_8c0344d4`** (bank03, 464 insns / 20 BBs — BOTH the simple and the scaled/rotated path, full record+tile loops, all 4 leaf dispatch sites) | the lifter produces a structurally correct, self-contained C unit for the entire function | **compiles, links, runs, terminates with a balanced stack (r15 delta = 0), leaf dispatch fires** |
| **Full walker NUMERIC `loc_8c0344d4`** (the COMPLETE pen + REAL tiling + transform, end-to-end, with INPUT-INDEPENDENT descriptors) | the entire walker reproduces every emitted tile's `screenX/screenY` when fed the REAL load-time tile-descriptor table read out of a live prod RAM dump (`_ryu_capture/mc_ram_dump.bin` @`0x8C1F9F9C`) | **9/9 tiles 0.00px-relative** (maxdX=0.0034px, maxdY=0.0043px — both under the trace's 0.01px logging ULP); negative control (descriptors zeroed) collapses to 4 wrong tiles → proves non-circular |

**Bottom line:** straight C `float` arithmetic is **bit-exact** for this render
routine's `+ − ×` chain; the single opcode that needed special-casing is `fmac`
(→ `fmaf`, fused single-rounding — 5 sites). The transpiler approach is **PROVEN**
for the body path.

## Run it

```
tools\render-replica-poc\run.cmd        REM Windows + MSVC (vcvars64 auto-invoked)
```
Outputs the three validations above. Requires Python 3 + numpy and MSVC (cl.exe).

## How it works (the pipeline)

```
SH4 disasm (marvelous2 bank03/bank11)
   │  lift.py        parse labels/insns/#data pools (the lifter front-end)
   │  codegen.py     per-opcode C emitter — semantics harvested from flycast's
   │                 determinism-validated interpreter (core/hw/sh4/interpr/*.cpp)
   ▼  gen_*.py       emit C: each SH4 fn -> one C fn over Sh4Ctx + flat ram[16MB];
                     each BB -> a C label/goto; SH4 delay slots emitted BEFORE the
                     branch effect; jsr -> resolved leaf dispatch.
gen_leaf.c / gen_walker.c / gen_transform.c   (AUTO-GENERATED — do not edit)
   │  sh4ctx.h       Sh4Ctx{r,fr,xf,fpscr,fpul,pr,macl,sr_t,gbr} + big-endian
   │                 area-3 RAM accessors (translate(a)=a&0x00FFFFFF)
   ▼  test_*.c       build the input image + run + diff
```

### Files
- `lift.py` — disasm parser (labels, operands incl `@(disp,Rn)` / `@(R0,Rn)` /
  `@Rn+` / `@-Rn` / PC-pool, paren-aware arg split).
- `codegen.py` — the per-mnemonic C emitter (~45 opcodes). Notable bit-exact choices:
  `fmac→fmaf` (FUSED, single rounding — matches flycast `sh4_fpu.cpp:559`),
  `ftrc→(u32)(s32)f` with the `0x7fffff80` overflow clamp (`sh4_fpu.cpp:522`),
  `mov #imm`/`add #imm` 8-bit **sign extension** (load-bearing — e.g. `add 0xE4,r0`
  is `+(-28)` and is how the walker computes `node+0x144` from `node+0x160`),
  `mov.w/mov.b` sign-extending loads, `muls.w` 16×16→32.
- `emit_func.py` — generic function-level control-flow emitter (delay-slot ordering).
- `gen_leaf.py` / `gen_walker.py` / `gen_transform.py` — drive the lifter over the
  three target ranges; resolve `jsr @rN` to the named leaves via pool-word tags.
- `sh4ctx.h` — runtime context + flat-RAM (area-3 only; no MMIO/MMU/virtmem, per the
  Option-C scope note "tree touches only area-3 RAM+VRAM").
- `test_leaf.c` / `test_transform.c` / `test_walker_compile.c` — harnesses.
- `make_transform_test.py` / `build_image.py` — recover inputs from the ASMTRACE.
- `leaves.c` — the scaled-path trig leaves (stubbed; unused on the simple path) +
  the bank12 submit stub.

## Ground truth & input reconstruction (honest scope)

Ground truth = `_ryu_capture/asm_angled_fist.log` — the ASMTRACE, which logs the
body walker's per-part output **at PC `0x8C034864`** (= `loc_8c034864`, the point
right after the simple-path transform writes `screenX@(0x30,r15)`/`screenY@(0x34,r15)`).
Columns: `frame sid slot cid sel dx dy accX accY screenX screenY pal row flip flags
r11 r13 node`. We use object **cid 23** (node `0c2688e4` = P2C1), **frame 10775**,
which renders 18 body tiles across 5 GFX2 records (one record tiles 2×4).

**What is independently recovered from the trace (no circularity):**
- Pen accumulation `accX -= dx`, `accY -= dy` per record — confirmed directly against
  the logged `accX/accY` and the disasm (`sub r5,r10` / the `@(0x14,r15)` accumulate).
- `scaleX = 1.666875 (≈5/3)`, `baseX = 533.00` — recovered by regressing the
  first-tile-of-record `screenX` on `accX`, **residual 0.000px** (clean).
- `scaleY = 2.142857 (=15/7)`, `baseY = 116.57` — recovered by the joint solve that
  forces every `Iy = (screenY−baseY)/scaleY` to an integer (max frac err 0.0027 =
  trace rounding).
- Per-tile integer indices `Ix = round((screenX−baseX)/scaleX)`,
  `Iy = round((screenY−baseY)/scaleY)` — exact integers.

The **transform-core test** feeds these recovered integers + scale/anchor into the
transpiled C and checks it reproduces `screenX/screenY`. Both the **bit-exact-vs-
reference-float** check (18/18, quantization-free) and the **vs-real-engine** check
(at/under the trace's 0.01px logging ULP) pass — so the lifted FP chain *is* the
engine's arithmetic.

**FULL NUMERIC WALKER — CLOSED 2026-06-12 (`test_walker_dump.c` + `build_image_dump.py`).**
The earlier gap — a **full numeric** run driving pen→tiling→transform end-to-end from
raw bytes — needed the **tiling descriptor table `0x8C1F9F9C`** the per-tile code reads
(`loc_8c0344d4` entry: `r13 = *(node+0xDC)*4 + 0x8C1F9F9C`; per tile `loc_8c03478e`
reads `m=byte[0]`, `pitchX=byte[2]`, `pitchY=byte[3]`, count `=byte[1]+1` from `r13`).
We now HAVE it: **`_ryu_capture/mc_ram_dump.bin`** is a 16MB main-RAM image from live
prod whose `0x8C1F9F9C` table holds 9 REAL load-time descriptors (idx 0..8).

Test object = **cid 23, frame 10766** (the ASMTRACE's only frame whose descriptors fall
entirely in the dump-resident idx 0..8 — `node+0xDC=0`, `r13` walks `0x8C1F9F9C..0x8C1F9FBC`):
9 GFX2 records' record-level data (`dx/dy/flags/sel`) come from the trace, the **tile
descriptors (count/pitch) are read straight out of the dump** (load-time-real, NOT
reconstructed), and anchor/scale are recovered from the trace (`scaleX=5/3`, `baseX=533`,
`scaleY=15/7`, `baseY=floor(node+0xE4)=333`). Running the transpiled `walker_0344d4` over
this image reproduces all **9 emitted tiles at 0.00px-relative** (maxdX 0.0034px / maxdY
0.0043px, both under the trace's 0.01px ULP).

**Non-circularity is proven two ways:** (1) `build_image_dump.py` prints the real
descriptor bytes and confirms each record's `count` (from descriptor `byte[1]+1`) equals
the trace's tile count BEFORE the diff runs; (2) the harness's `zerodesc` negative control
wipes the table → the walker collapses to 4 wrong tiles, so the pass genuinely depends on
the dump's load-time descriptors.

**Scope note for the OTHER objects:** every *other* trace frame (incl. the Sentinel
sid-0x131 rocket, 19 parts) uses `r13` at table idx ≥ 36, which is ZERO in this particular
dump — `0x8C1F9F9C` is a **rolling per-frame scratch table** the engine refills per object
via `node+0xDC`, and only the first object's descriptors (idx 0..8) survived at the base in
this static snapshot. So the rocket frame can't be diffed against THIS dump (its transient
descriptors aren't present); cid23 frame 10766 is the test whose REAL descriptors ARE in the
dump, and it closes the full-walker thesis: **pen + REAL tiling + FP transform reproduced
end-to-end through mechanically-transpiled C with fully independent input.**

## STAGE 2 — walker → submit-corners → NATIVE PVR TA QUADS (CLOSED 2026-06-12)

`run.cmd` step **[6/6]** (`test_ta_emit.c` + `gen_submit.py`) extends the proven walker
into the game's **native TA command stream** — the artifact the WebGPU renderer consumes.

**The chain, and the key architectural reconciliation (5-source):**
```
(1) WALKER  loc_8c0344d4   -> per-tile top-left screenX/screenY   [PROVEN 9/9 @0.00px]
(2) TRANSFORM loc_8c1216c0 -> RESIDENT: its world->screen result is already a node field
(3) SUBMIT  loc_8C1244B0 -> loc_8C124AB0 -> 4 screen corners -> TA polygon quads
```

- **The world→screen matrix transform (`loc_8c1216c0`, bank12, the ftrv/fsca tree) runs
  ONCE PER OBJECT upstream and deposits its result into `node+0xE0/E4` (screen anchor)
  and `node+0xEC/F0` (per-axis scale).** CONFIRMED by reading the RAM dump directly:
  `node+0xE0 = 533.86`, `node+0xEC = 1.66667 (=5/3)`, `node+0xF0 = 2.142857 (=15/7)` —
  these are **byte-exact** the `baseX=533 / scaleX=5/3 / scaleY=15/7` the PoC previously
  recovered by regression. So the 9,850-insn ftrv matrix tree need **not** be re-run to
  reproduce a resident object's quads; its product is a node field the walker reads
  (`@(0xEC,r14)`/`@(0xF0,r14)`, bank03 loc_8c0347c8). (Cross-checked vs KB
  `finding:render_calltree_scope` which places the ftrv transform in bank12
  loc_8c1216c0/loc_8c1219b0. Transpiling that tree is still required for objects whose
  `node+0xE0/E4` is NOT resident in a dump — see "Honest scope" below.)

- **The body submit path is AXIS-ALIGNED.** `loc_8C1244B0` calls `loc_8C124AB0` (transpiled
  to `gen_submit.c`) which builds 4 corners as `out = anchor + R(angle).(scale·unit_offset)`.
  For the body, the billboard angle is 0 ⇒ `R = I` ⇒ `corner = (sx,sy)..(sx+m·scaleX, sy+m·scaleY)`.
  CONFIRMED axis-aligned directly from `_ryu_capture/probe_body_uv.json` (every CHARQ quad has
  `A.y==B.y` and `B.x==C.x`). The tile pixel size `m` is the **ROM descriptor byte[0]** read
  from the dump (m=32 for sel1264, m=8 for sel1267) — not hard-coded.

**RESULT — `test_ta_emit.exe`:** walker→corners→TA emits a real PVR TA stream for cid23
frame 10766 → **9 quads, corner extent ROM-exact (maxerr=0.0000)**; written to `ta_buffer.bin`
(1472 bytes / 46 TA params) and **round-tripped through the real `web/webgpu/ta-parser.mjs`**
(`verify_ta.mjs`): decodes to **9 opaque textured polys / 36 vertices**, corners byte-exact
(TL 463.00/228.00 .. BR 516.33/296.57). Within-record tiling is exact (tile 2's top-left ==
tile 0's right edge).

### New opcodes added to `codegen.py` (the matrix/submit core the §8 plan flagged)
- **`ftrv XMTRX,FVn`** — 4×4 (XF bank) × FV, column-major (`out_i = Σ_k xf[i+4k]·v_k`), single
  rounding. Models the **XF bank** (`xf[16]`) separate from `fr[16]`.
- **`frchg`** — swap FR↔XF banks + toggle `FPSCR.FR` (bit 21). **`fschg`** — toggle `FPSCR.SZ`
  (bit 20, single/pair fmov size). Both modeled as explicit state on `Sh4Ctx`.
- **`fsca FPUL,DRn`** — sin/cos from the 16-bit angle: `ang = (fpul&0xFFFF)·2π/65536`,
  `fr[n]=sin`, `fr[n+1]=cos` (flycast `sh4_fpu.cpp`).
- **`shad`/`shar`/`shll16`/`shll8`/`shlr16`/`shlr8`/`shlr2`/`shlr`** — the PVR control-word
  (tcw/tsp/pcw) bit-assembly the submit does. `shad` = dynamic L/arith-R; `shar` sets T=bit0.
- **`xor`/`not`/`cmp/hs`/`cmp/hi`/`pref`** + sign-extended **`cmp/eq #imm`** — submit integer glue.
- **`fcnvsd/fcnvds`** modeled identity (single-precision scope, 1 isolated site per §8).

**FP/bank subtlety:** the matrix transform uses `frchg` to make the constructed projection
matrix the **secondary (XF) bank** that `ftrv` then multiplies — so `ftrv` reads `xf[]`, and
any `fmov` between the banks must respect the current `FPSCR.FR`. The PoC models FR/SZ as
toggled state; the body path itself never flips them (axis-aligned, single precision), so the
walker+corner chain needs no bank routing — but the opcodes are in place for the full tree.

### The emitted TA buffer format (for the render harness — `ta_buffer.bin`)
A standard little-endian **PowerVR2 TA command stream** of 32-byte parameters (exactly what
`ta-parser.mjs` / `pvr2-renderer.mjs` already parse). Per body tile, one textured-polygon quad:
```
Polygon param  (paraType=4): [PCW u32][ISP u32][TSP u32][TCW u32][16 bytes pad]
   PCW = 0x80000000 | tex(1<<3) | gouraud(1<<1)   (opaque list, packed color, uv32)
Vertex param   (paraType=7) x4, strip order TL,TR,BL,BR (last has EndOfStrip bit 28):
   [PCW u32][x f32][y f32][z f32][u f32][v f32][baseColor u32][0]
...one EndOfList param (paraType=0, all-zero 32B) terminates the stream.
```
- `x,y` = final screen pixels (the walker's transformed corners). `z=1.0`.

### STAGE 3 — REAL TCW + UV (CLOSED 2026-06-12) — the placeholder seam is GONE

The earlier placeholder (`tcw = 0x2A000000 | sel`, `u,v` unit) is **replaced by the engine's
actual control words**, traced from the disasm and read from the resident fields. Each emitted
quad now carries its OWN real TCW/TSP + real UV sub-rect, **bit-exact vs the engine**.

**WHERE TCW/TSP/UV COME FROM (traced from marvelous2 bank12, not assumed):**
- The body submit is `loc_8C1244B0` (bank12). At `loc_8C124520`: `idx = *r13` (cell-record
  index, r13 = the source cell pointer = the submit's arg r4); `r8 = idxtab[idx]` where
  `idxtab = *(0x8C2DAD3c)`. At `loc_8C124534`: **`r12 = rectab + r8*0x20`** where
  `rectab = *(0x8C2DAD4c)`. **`r12` is a resident 0x20-byte PVR poly-param TEMPLATE per tile:**
  `@r12+0x00 = PCW`, `+0x04 = ISP/TSP word0`, `+0x08 = TSP`, **`+0x0C = TCW`** (canonical PVR
  poly-param layout — cross-checked vs flycast `core/hw/pvr/ta_structs.h` `TA_PolyParam0`).
- So **TCW/TSP/ISP/PCW are NOT computed inline in the submit — they are DEPOSITED fields** the
  submit reads from `rectab[idxtab[sel]]` and copies into the output record (the copies at
  bank12 `loc_8c124856`: `@(0x08,r12)→@(0x08,r14)` TSP, `@(0x10,r12)→@(0x10,r14)` etc). The TCW
  carries the **live DM00 texaddr** (low 21 bits, moves as the part is re-decoded into VRAM —
  matches the KB "moving TCW" finding) + the **PixelFmt** (bits 27..29; =5 PAL4BPP for the body)
  + the **PalSelect** (bits 21..26).
- **The ONE thing the submit COMPUTES on top of the resident TCW is the PalSelect injection**,
  in the finalize routine `loc_8C124910` at **`loc_8c124a82`**:
  `TCW = (TCW & 0xF81FFFFF) | (palbank << 21)` (`shad #21,r12; and 0xF81FFFFF,r2; or; store
  @(0x0C,r14)`). Transpiled literally in `test_ta_emit.c::tcw_inject_palselect`. For records
  already finalized in the dump (PalSelect baked, e.g. pal=28) it is the **identity** (verified
  idempotent 9/9), so reading the resident field is bit-exact.
- **TSP** decodes the tile size: `TexU = (TSP>>3)&7`, `tile = 8<<TexU` (=16 for `0x4C9`, =8 for
  `0x4C0`), `ShadInstr = (TSP>>6)&3` (=3). **UV** = each body tile-quad samples one texture tile;
  for a tile-filling part `u,v = [0,1]`, for a sub-tile part (`m < tile`) `u,v = [0, m/tile]`
  (=`[0,0.5]` for sel1266, m=8, tile=16). This UV rule is the body specialization of the engine's
  sub-rect format `u:[u0,u1],v:[v0,v1]` observed in `oracle_post_blend.jsonl` (`tex_wh=[tile,tile]`,
  `u/v=[0, used/tile]`). `m` = the load-time tile descriptor byte[0] (already used for geometry).

**TRANSPILED vs READ-FROM-FIELD (per task scope):**
- **READ from the RAM dump** (deposited fields): PCW, ISP, TSP, TCW from `rectab[idxtab[sel]]`
  — baked into `image_dump.h` as `EXP_PCW_T/EXP_ISP_T/EXP_TSP/EXP_TCW` by `build_image_dump.py`
  (which reads `idxtab=*(0x8C2DAD3c)`, `rectab=*(0x8C2DAD4c)` out of `mc_ram_dump.bin`).
- **TRANSPILED** (computed): the PalSelect OR (`loc_8c124a82`) and the per-quad UV from TSP+m.

**BIT-EXACT VALIDATION RESULT (`test_ta_emit.exe`, cid23 frame 10766, 9 quads):**
```
TCW-BITEXACT:  9/9 quads' emitted TCW == engine resident TCW (rectab+0x0C)
TSP-BITEXACT:  9/9 quads' emitted TSP == engine resident TSP (rectab+0x08)
PALSEL-INJECT: 9/9 idempotent on finalized TCW (loc_8c124a82 transpiled)
```
Round-tripped through the real `web/webgpu/ta-parser.mjs` (`verify_ta.mjs`): **9 opaque polys /
36 verts; TCW + TSP 9/9 bit-exact after parse; real UV sub-rects `[0,1]`/`[0,0.5]`.** The
texture-binding seam is **CLOSED** — the TA carries the engine's exact TCW (VRAM texel addr +
fmt + pal) and UV; `render_ta.mjs` can now sample the real VRAM tile per quad.

**TEST OBJECT / VRAM ALIGNMENT (for the converge step):** cid23 = P2C1, frame 10766, Cable body,
sels {1264,1265,1266,1267}, all PixelFmt=5 (PAL4BPP), PalSelect=28. The converge VRAM frame must
contain these texel addresses (= `(TCW&0x1FFFFF)<<3`):
`sel1264→0x61A720 · sel1267→0x61A7A0 · sel1265→0x61A800 · sel1266→0x61A880`. Palette bank 28
(PVR PAL_RAM entries 28*16=448..463) must be present in `mc_pvr_regs.bin`.

## Opcode notes (FP-exactness — the plan's flagged risk)

- **`fmac` → `std::fmaf`** is the ONE opcode requiring special handling: flycast uses
  `std::fma` (single rounding); a naive `fr0*frm + frn` rounds twice and would diverge.
  5 sites in the walker. **This is the only place straight C float ops are not the
  literal translation.**
- All other FP (`fadd/fsub/fmul/fdiv/fabs/fneg/float/ftrc/fcmp/fldi0/fldi1`) lift to
  the obvious C `float` op and are **bit-exact** here. Compiled `/fp:precise` (no
  contraction, ordered eval). No FPSCR rounding-mode juggling was needed for this
  subtree (RM=0, single precision throughout — consistent with the §8 scope analysis).
- Integer subtleties that mattered: 8-bit immediate **sign extension** on `mov #imm`/
  `add #imm`; sign-extending `mov.w`/`mov.b` loads; `exts.w` before the `float`;
  `muls.w` as 16×16→32. All handled by the emitter; the leaf and transform results
  confirm them.

## Generalization

The lifter is a **reusable generator over the disasm** (operand parser + per-mnemonic
table + delay-slot-aware control-flow emitter), not a hand-port. Extending to the full
114-function / ~9,850-insn render tree (§8) means: add the remaining opcodes
(`ftrv`/`frchg`/`fsca`/`fschg` — the matrix/trig core), wire the 2 enumerable ROM jump
tables + the 1 RAM vtable as `switch`es, and transpile the trig leaves
(`loc_8c11e2e0`/`loc_8c11e860`, present in bank11 — sin/cos via the 2π/π-2 constants)
and the bank12 submit. No general indirect-jump resolver is required (§8 confirmed
~96% statically resolved).

---

# Render harness — `render_ta.mjs` (Phase 4 back-half: TA → PIXELS, headless)

The transpiler above is the **front half** (SH4 render code → emitted TA quads). This
is the **back half** (`docs/RENDER-REPLICA-PLAN.md` §Phase 4): run the project's
gold-standard rasterizer **headless, on a file**, so the transpiled TA can be pixel-tested
offline and diffed vs ground truth.

```
TA buffer  +  VRAM (8MB)  +  pvr_regs (32KB)  +  pvrSnapshot (16×u32)
   └─► ta-parser.mjs    (TAParser.parse [+ fillBGP])     [REUSED VERBATIM]
   └─► pvr2-renderer.mjs (PVR2Renderer.renderFrame, GOLD STANDARD CONFIG) [VERBATIM]
   └─► offscreen WebGPU render target → readback → PNG
```

It is the **same pipeline the live cockpit** (`web/webgpu-test.html`) runs (FrameDecoder →
TextureManager → TAParser → PVR2Renderer.renderFrame), just driven headless from a file
instead of a WebSocket + `<canvas>`. **`ta-parser.mjs`, `pvr2-renderer.mjs`,
`texture-manager.mjs`, `frame-decoder.mjs` are imported UNCHANGED** — zero edits to the
render modules (the harness reaches `renderFrame`'s existing offscreen `renderTarget`
path and calls `PVR2Renderer._init()` directly to skip the canvas-only `init()`).

## Headless WebGPU backend

**`webgpu` npm package (Dawn N-API bindings)** — picked over Deno (not installed on the
box) and headless-Chrome/puppeteer (heavier, flakier readback). It exposes a real
WebGPU on the GPU with no canvas/swap-chain. `webgpu-headless.mjs` installs its `globals`
(`GPUBufferUsage`/`GPUTextureUsage`/`GPUShaderStage`/`GPUColorWrite` + all `GPU*` classes)
onto `globalThis` and provides `navigator.gpu`, so the unchanged modules resolve their
WebGPU symbols. Verified on an RTX 3090 (Dawn → Vulkan); the WGSL in `shaders.mjs`
compiles and runs unmodified.

```
npm install                    # webgpu (Dawn) + pngjs
node render_ta.mjs --self-test --out selftest.png         # proves WebGPU+readback+PNG
node render_ta.mjs --mirror <file.zcst> --out frame.png   # render a captured live frame
node render_ta.mjs --ta ta.bin --vram vram.bin --pvr pvr.bin --out f.png   # the triple
node diff_png.mjs a.png b.png --out diff.png [--tol N]     # pixel diff + heatmap
```

## INPUT INTERFACE — what the converge step plugs in

Two equivalent ways to feed the harness; **the raw triple is the converge contract.**

### (A) The raw triple — what the transpiler + a prod dump produce
| Flag | File | Size | Meaning | Consumed by |
|---|---|---|---|---|
| `--ta`   | TA command stream | var | the game's native PVR2 TA buffer. **`MAPLECAST_DUMP_TA=1`** server already writes this exact format to `<dir>/frame_NNNNNN.bin` (`maplecast_mirror.cpp:1954`). The transpiled `submit` emits the *same* byte format. | `TAParser.parse(buf, buf.length)` |
| `--vram` | VRAM image | **8 MiB** | the part-pixel textures the TA samples by `tcw`. **`MAPLECAST_DUMP_RAM` server hook writes `/dev/shm/mc_vram_dump.bin`** (`maplecast_oracle_hook.cpp:3168`) — byte-for-byte this file. | `texMgr.getTexture(tsp,tcw,vram)` + `fillBGP` |
| `--pvr`  | PVR register block | **32 KiB** (`pvr_RegSize=0x8000`) | palette RAM @ `+0x1000`, `PAL_RAM_CTRL` @ `+0x108`, `ISP_BACKGND_*` for `fillBGP`. **Same hook writes `/dev/shm/mc_pvr_regs.bin`** (`:3171`). | `texMgr.updatePalette` + `fillBGP` |
| `--snap` | pvrSnapshot | 64 B = 16×u32 LE | only `snap[0]` is read (`_ndcMat`: framebuffer tile dims `tx=g&0x3F, ty=(g>>16)&0x3F`). **Optional** — omitted ⇒ synthesized for `--width × --height` (640×480 default), which is correct for MVC2's FB. | `renderFrame`'s NDC matrix |

The three server dumps (`mc_vram_dump.bin`, `mc_pvr_regs.bin`, plus a `MAPLECAST_DUMP_TA`
frame OR a transpiler-emitted TA) drop straight in with **no transform** — the dump sizes
already match the harness's expected sizes.

### (B) A captured ZCST mirror stream — easiest, self-contained
`--mirror <file.zcst>` replays a captured live stream through `FrameDecoder`
(reused verbatim — the same decoder the cockpit runs), which yields exactly the
renderFrame inputs (TA + VRAM + pvr_regs + pvrSnapshot + dirty-page list). Capture with:

```
node capture_mirror.mjs --url wss://nobd.net/ws --out frame.zcst --frames 400
```

Container framing: `[u32 LE len][message]…` per WS message (one ZCST envelope each).
A `SYNC`/`FSYN` seeds full VRAM+PVR; a TA **keyframe** (`deltaPayloadSize==taSize`)
establishes `prevTA`; subsequent **deltas** patch it. `--frame N` selects which decoded
frame to render (default: last). The in-match prod stream also carries an `MCSV` savestate
blob (full `dc_serialize`, nested `ZCST`); the harness skips it (FrameDecoder only consumes
SYNC/FSYN for VRAM) — VRAM comes from the SYNC, or supply `--vram` from the dump.

## Validation — DONE, end-to-end, against a real known-good frame

| Test | Result |
|---|---|
| **`--self-test`** (synthetic gouraud quad) | renders the expected R/G/B/Y-corner quad; proves Dawn WebGPU + WGSL compile + offscreen render-target + texture readback + PNG write all work headless. |
| **`--mirror live.zcst`** — a **captured live prod frame** (SYNC + TA keyframe + deltas off `wss://nobd.net/ws`) | renders the **MVC2 character-select screen pixel-correctly** (rotating portrait globe, neon grid, side art) — textures sampled from the SYNC's VRAM, palette from pvr_regs, translucency + `fillBGP` background all correct. This is the gold-standard rasterizer producing the actual game screen **headless**, identical in pipeline to the cockpit. |
| **Determinism** (`diff_png.mjs` same frame ×2) | **100.0000% match, max Δ=0** — byte-identical render run-to-run. |

So: **the known-TA → correct-pixels claim is proven** with a live frame, not just a
synthetic one. The harness is a clean, reusable, deterministic loop ready for the
transpiled TA: emit a TA buffer, pass `--ta` (+ the `mc_vram_dump.bin` / `mc_pvr_regs.bin`),
render, and `diff_png.mjs` against the cockpit screenshot or the `MAPLECAST_DUMP_TA`
frame rendered through this same harness.

### Files (render harness)
- `render_ta.mjs` — the harness (args, FrameDecoder/`--mirror` path, raw-triple path,
  self-test, offscreen render target + readback + PNG).
- `webgpu-headless.mjs` — Dawn bootstrap (installs GPU globals + `navigator.gpu`).
- `capture_mirror.mjs` — capture a live ZCST stream to a replayable `.zcst` file.
- `diff_png.mjs` — PNG-vs-PNG pixel diff (match %, max/mean Δ, heatmap, CI exit code).
- `package.json` — deps: `webgpu` (Dawn), `pngjs`.

### If a render module ever needs touching (flag it)
None were touched. The only non-obvious coupling: `PVR2Renderer._pipe` builds pipelines
for `this.fmt`, so the harness sets `R.fmt='rgba8unorm'` (the offscreen color format) and
calls `_init()` directly. If a future change makes `renderFrame` assume a live canvas
(`this.ctx`) on the `renderTarget` path, the harness would need a stub — currently it does
not, because the `renderTarget` branch never touches `this.ctx`.
