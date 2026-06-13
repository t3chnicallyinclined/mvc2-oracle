# Frame Oracle — Implementation Spec (2026-06-08)

A headless-flycast instrument that captures, per frame per drawn object, its `sprite_id` + state + the **exact TA quads it emits** + the **source address** of its texture/assembly. Drives: understanding how the game draws each frame, finding our render misses, and completing anotak/marvelous2. All offsets/PCs CONFIRMED from `marvelous2/build/bank03.asm` + the maplecast source unless marked INFERRED.

## Key decision: MVP needs NO SH4 PC-hook
- `serverPublish()` (`maplecast_mirror.cpp:1746`, called from `Renderer_if.cpp:197` **before** `renderer->Process`) already receives the **completed whole-frame TA list**. By then the SH4 draw walk (`loc_8c0308c2`→`loc_8c03093c`→`loc_8c033e90`) is over — no live registers to read.
- So attribute **after `ta_parse`**, by **position-correlation**: group parsed polys to objects (from `readAllDrawn()`) by screen bbox vs object `screen_xy`. This is literally `MAPLECAST_TADBG`/`MAPLECAST_TAEFF` **generalized** (the `bdist<1600` correlator + the bbox/UV de-index loop at `maplecast_mirror.cpp:2486-2496`). **Runs on the live dynarec server, zero determinism risk.**
- A true PC-hook (`0x8C03093C` object-begin r4 + `0x8C033E90` 16-byte quad: r8=texptr, r12=palptr cursor-segmentation) is the EXACT version — but PC breakpoints under the production dynarec are a perf/determinism risk, so run that **offline on a `.mcrec` replay under the interpreter** ONLY if overlap ambiguity (super flash over body) makes the MVP's nearest-object assignment wrong. Measure the ambiguity rate first (TADBG `NO-MATCH` output already hints it).

## Draw chain + node fields (CONFIRMED)
- `0x8C0308C2 loc_8c0308c2` Render_sprites — slot walk: count `0x8C2895E0`, ptrs `0x8C287DE0`, stride `0x180`; node→r4; category @+0x3.
- `0x8C03093C loc_8c03093c` Render Main Sprite — node=r4→r14; cull @+0x12C; writes screen_x@+0xE0/screen_y@+0xE4; scale @+0x50/54.
- `0x8C033E90 loc_8c033e90` quad emitter — 16-byte quads: `w@+0,h@+2,attr@+4,texptr(r8)@+8,palptr(r12)@+C`; EXTRAS records 8B from `extras+0x18` (`readHotspot` already does this).
- Read per object: sprite_id@+0x144, screen@+0xE0/E4, scale@+0x50/54/58, flip@+0x1D2(copy +0x130), category@+0x3, Dat_GFX1@+0x15C, Dat_GFX2@+0x160, Dat_Pal@+0x164, Sprite_Extras@+0x178, Dat_FilePointer@+0x17C, FAC@+0x184.

## Source-address trace (the missing-sprite / ROM answer)
- TA poly → VRAM tex addr: `addr=(pp.tcw.full & 0x1FFFFF)<<3` (`maplecast_mirror.cpp:2506`); `fmt=(tcw>>27)&7`; dims from tsp; hash `mcfx::texHash(addr,fmt,tw,th,vq)` (line 2507).
- Region classify by `Dat_GFX1 & 0x0FFFFFFF` (pattern at gamestate.cpp:342-343): `0x0CED0000–0x0CEE0000`=**EFFECTS_BANK**, `0x0CE60000`=**DECOMP_BUF** (LZSS staging), else **CHAR_GFX**.
- Provenance: `Dat_FilePointer@+0x17C` + `FAC@+0x184` + owner cid → which PLxx file; EXTRAS part_idx → the GFX1 offset-table blob.
- `atlas_hit` = is this `sprite_id` in our `atlas/chars/PLxx.json`? (computed by the differ offline; server just emits sprite_id+source.)

## Output (`/dev/shm/mc_oracle.jsonl`, gated `MAPLECAST_FRAME_ORACLE`)
```json
{"frame":N,"in_match":1,"objects":[{"slot":0,"owner_cid":42,"category":5,"sprite_id":735,
 "screen_xy":[318,224],"scale":[1.75,1.75],"flip":0,"node_addr":"0x..",
 "quads":[{"x":300,"y":180,"w":36,"h":44,"u":[..],"v":[..],"texId":"hash","tcw":"0x..","blend":[1,1]}],
 "tex_src":{"vram_addr":"0x..","region":"EFFECTS_BANK|DECOMP_BUF|CHAR_GFX","gfx1_ptr":"0x..","pal_ptr":"0x..","part_idx":3},
 "asm_src":{"extras_ptr":"0x..","file_ptr":"0x..","fac_ptr":"0x..","hotspot_dx":-18,"hotspot_dy":-44}}]}
```
Client dumps the **same shape** (what *we* drew). Differ aligns by `(frame, sprite_id/slot)` → **MISSING** (truth, not ours; `atlas_hit:false` = worklist), **ANCHOR/SCALE** (px delta), **EXTRA**.

## Integration points
| Step | File / function | What |
|---|---|---|
| Server oracle | `maplecast_mirror.cpp serverPublish()` ~line 2405, gated `MAPLECAST_FRAME_ORACLE` | generalize TADBG: per object (from `readAllDrawn()`) group polys by nearest screen_xy, emit §output. Reuse bbox/UV loop 2486-2496. |
| Object+source read | `maplecast_gamestate.cpp readAllDrawn()`:370 + `readHotspot()`:126 | add pal@+0x164, file@+0x17C, fac@+0x184, scale, flip, GFX1-region classify (line 342). |
| Client draw dump | `web/webgpu/sprite-client.mjs` (+ pvr2-renderer for effects) | emit identical `{frame,objects:[{..,quads}]}` of what we drew. |
| Differ | `tools/frame_oracle_diff.py` (new) | align, print MISSING/ANCHOR/EXTRA + overlay. |
| EXACT (later, optional) | interpreter build, replay `.mcrec` | PC-hook 0x8C03093C + 0x8C033E90 cursor-segmentation → ground-truth attribution. |

## Live-probe unknowns
1. Position-correlation ambiguity rate under overlap (measure via TADBG NO-MATCH).
2. (Only if EXACT needed) dynarec-vs-interpreter breakpoint cost on this tree; display-buffer cursor r14 stability.
