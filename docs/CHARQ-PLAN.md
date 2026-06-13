# CHARQ — Per-Frame Character Quad-List + VRAM-Cache Render (Implementation Plan)

Pixel-perfect character rendering by shipping the game's OWN parsed quads (not reconstruction). **CHARQ = STAF + a 16-byte-per-object segmentation header, with the poly set filtered to the Oracle-attributed character/satellite quads.** Validated foundation: real TCW + mirrored VRAM → `texture-manager.getTexture` → clean sprites in all 4 formats (PAL4/565/4444/4444+VQ).

CHARQ is also the **extraction harness for the Phase-2 offline emitter** — its captured {quads + texId + screen_xy + sprite_id + cid + ownerSlot} per object is the bake input. Keep verts UNQUANTIZED in a bake-capture mode so they seed the offline atlas.

## Wire record — `CHRQ` magic (STAF superset, rides ZCST)
```
'CHRQ'(4) frameNum(4) pvr_snapshot[16](64)
vertCount(u32)@72  polyCount(u32)@76  objCount(u32)@80
── vertex region: vertCount × 28 B  (IDENTICAL to STAF) ──
    x,y,z(f32) u,v(f32) col(4 RGBA) spc(4 RGBA)
── object region: objCount × 16 B  (NET-NEW) ──
    sprite_id(2)  cid(1)  flags(1: b0 isSat, b1 hasOwner, b2 facing/xflip)
    screen_x(2 i16)  screen_y(2 i16)   // node+0xE0/E4 own-origin anchor
    firstPoly(2)  polyCnt(2)  ownerSlot(1)  scaleQ(1: node+0x50 ×64)  pad(2)
── poly region: polyCount × 33 B  (IDENTICAL to STAF) ──
    firstVert(u32) vertCount(u32) texId(8) tcw(4) tsp(4) pcw(4) isp(4) listType(1)
```
- Verts stay **f32** (STAF's pixel-perfect property — client hands PVR2Renderer the byte-identical ta-parser shape). u16 quantization is a later bandwidth pass, measured on the differ.
- Textures ship via existing `TX64` (pre-decoded RGBA, content-addressed `texHash64`); client resolves via the `makeStafTexMgr` surrogate shim. NO VRAM-on-wire for textures. The VRAM-decode path (`texture-manager.getTexture`) is only the fallback for formats `decodeTexAny` rejects.
- Per-frame: ~6 objects, ~18–40 char/sat polys (drops all stage/BG/HUD) → well under STAF's ~140 KB/s.

## Build order (each step testable before the next)
1. **Oracle attribution fix + schema** (`maplecast_oracle_hook.cpp`) — FOUNDATION, both wire + offline depend on it.
   - 3b body-attribution fix: re-read `screen_xy` from node (node+0xE0/E4) in `attributeScreenQuads`/`frameFlush` (entry-time value lags); widen `ATTR_RADIUS`/use bbox-overlap so tall body quads attribute. Verify `attributed ≈ screenQuads` for body frames in the flush log.
   - 3a schema: add `isp` to the `ScreenQuad` struct (capture `pp.isp.full`); add `tsp/pcw/isp` to the JSONL screen_quads emit (for the offline harness).
   - Add a per-frame accessor: kept-sprite-quad ordinal → obj index + `s_objs[]` identity (sprite_id, cid, sx, sy, isSat, ownerSlot, ownerCid). Declared in `maplecast_oracle_hook.h`.
   - **Verify:** `/dev/shm/mc_oracle_hook.jsonl` body frames have populated screen_quads with tsp/pcw/isp; unassigned bucket ≈ 0.
2. **Server `CHRQ` emit** (`maplecast_mirror.cpp`) — model on the STAF block (~lines 2894-3196), gated `MAPLECAST_CHARQ`, in-match only (`0x8C289624`). Consume the Oracle accessor; filter polys to the Oracle's `isSprite` set; emit the object header + STAF vert/poly regions. REUSE `texHash64`/`decodeTexAny` (1698-1745), `_stafSent`/`_stafRgba`/`_compressor`/`TX64`. Add `MAPLECAST_CHARQ_DBG` → `/dev/shm/mc_charq.log` + reuse `MAPLECAST_STAFMEASURE`.
   - **Verify (no client):** dump shows ~6 objects/frame, sane sprite_ids, contiguous poly runs, total polys ≈ Oracle attributed sprite-quads, KB/s < STAF.
3. **Relay pass-through** (`relay/src/protocol.rs`) — add `CHRQ_MAGIC` + `is_charq` mirroring `is_staf` (46-53): forward verbatim, NEVER `apply_dirty_pages` (offset 76/80 are counts, not page data), add to the render-keep-list for state-mode clients. Relay does NOT parse CHARQ contents.
4. **Client `onCHARQ`** (`sprite-client.mjs`) — `isCHRQ`/`onCHARQ` modeled on `onSTAF` (282-363); factor the shared strip-parse `_parseStripFrame`; parse the 16-B object region into `_charqObjs[]`; set `_stafParsed`/`_charqParsed` so `renderStaf` draws it unchanged. `TX64` intake unchanged. In `webgpu-test.html`: peek inner magic `CHRQ` (like STAF at ~1509) → `onCHARQ`; add a CHARQ checkbox; drive `renderStaf(_charqParsed)`; bump `?v=` on the sprite-client.mjs import.
5. **DIFF v7 validation** — Ryu match with `MAPLECAST_CHARQ=1`, tick CHARQ + DIFF (tint). Pixel-perfect = body+satellites all YELLOW (TA-truth green coincides with CHARQ red). Sweep idle/walk/fireball(sat)/super(owner-less). Green-only = attribution miss (step 1); red-only = mis-place.

## Parsers that change
- `maplecast_mirror.cpp` (C++ producer) — the `CHRQ` emit block. **YES.**
- `relay/src/protocol.rs` (Rust) — pass-through + never-apply-dirty + render-keep. **YES (minimal).**
- `web/webgpu/sprite-client.mjs` + `webgpu-test.html` (JS client) — `onCHARQ` + route + checkbox. **YES.**
- `packages/renderer/src/wasm_bridge.cpp`, `core/network/maplecast_wasm_bridge.cpp` — **NO** (those are the MIRROR-TA wire; CHARQ is a parallel channel like STAF, per STRIPPED-TA-DESIGN §6).
- `web/webgpu/pvr2-renderer.mjs`, `texture-manager.mjs` — **NO** (renders `_stafParsed` unchanged; texture-manager only on the VRAM-decode fallback).

## Risks
- Determinism: CHARQ re-parses `ta_parse(ctx,...)` read-only (no guest writes), like STAF/Oracle. Run `MAPLECAST_DUMP_TA` rig end-of-phase.
- Prod-bound server: emit is gated/additive (off by default) — cannot regress the live mirror. Deploy via `deploy-headless.sh`, never raw scp.
- In-match gating: reuse `0x8C289624` (off-match floods attract-demo textures — the HUDF bug).
- Attribution quality (step 1) is the real risk — mis-attributed fast-motion body quads still DRAW correctly (TA position) but mis-key the offline bake. The differ surfaces it.

## Phase-2 offline-emitter harness notes
- Object region's `screen_x/y` (own-origin) → each quad's vert minus screen_xy = own-origin dx/dy (the bake anchor + own-origin draw rule). Satellites attribute to THEIR node's screen_xy (fixes the bake-foot-vs-own-origin conflict).
- Content-addressed `texId` dedups parts across frames for free; `TX64` pixels are the live-decoded clean-part source (replaces the dead offline-LZSS path).
- Keep an unquantized `MAPLECAST_CHARQ_BAKE` capture mode for offline fidelity even when the live wire later quantizes.

Foundation validation: `_ryu_capture/val_*.png` (TCW+VRAM→clean, all 4 formats). DIFF surface: webgpu-test.html DIFF v7 (PVR2Renderer TA-truth vs reconstruction).
