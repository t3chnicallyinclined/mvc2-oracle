// sprite-client.mjs — the ROM-asset client proof (Option 6).
//
// Renders MVC2 characters from the ~253-byte GSTA game state ALONE, with NO TA
// stream: preload a sprite atlas once (baked by bake.mjs -> bake_atlas.{png,json}),
// then for each active character draw sprite[char_id][sprite_id] at the reported
// screen position. This is the client that, if it matches the byte-perfect TA
// mirror, proves the ~800x bandwidth model.
//
// Input is the same GSTA broadcast the bake harness consumes:
//   'GSTA'(4) + serialized GameState (wire layout = gamestate.cpp serialize()):
//   25-byte global header, then 6 * 57-byte character blocks (stride bumped 38->49
//   by the GSTA enrich: +38 scaleX(f32) +42 scaleY(f32) +46 pal12d +47 pal12e
//   +48 overlay1a4; then 49->57 by the GSTA wire ext: +49 draw_layer +50 render_extra
//   +51 facing_1d2 +52 pal_color_25 +53 hyper_armor +54 flight_flag +55 stance +56 _pad).
//   We read the two point characters (render slots 0,1) — active, char_id, facing,
//   palette, screen_x/y, sprite_id, plus the enrich + wire-ext fields. draw_layer
//   drives the emitter z-order; the rest are parsed-but-unused for now.
//
// Canvas2D on purpose: fastest path to a visible side-by-side test, fully
// decoupled from the WebGPU TA renderer. A WebGPU port comes later for the
// pixel-exact diff (plan Phase 2).
//
// KNOWN GAPS (first pass, see ROM-ASSET-CLIENT-PLAN.md):
//   - Palette: the baked crop carries a fixed palette; live skin swaps (the PVR
//     palette-bank system) are NOT reapplied here yet. Wrong colors on skinned
//     chars is expected until palette-from-state lands.
//   - Mirror anchor: flipping uses the character's screen_x as the mirror axis,
//     which is approximate for sprites whose alpha bbox is asymmetric about the
//     origin. Good enough to prove placement; refine in P1.5.
//   - Only the 2 point characters are drawn (assists/projectiles/effects are
//     separate object systems not in the 6 tracked slots).

const GSTA_MAGIC = [71, 83, 84, 65]; // 'G','S','T','A'

// Per-char dynamic-zoom guard (char+0x50/0x54). Same band the emitter path uses
// (sprite-client.mjs:926): out-of-band / zero / garbage -> 1.0 (no zoom), so a char
// WITHOUT the step-1 scale field renders byte-identical to the pre-field build.
const _sane = (v) => (v > 0.05 && v < 16) ? v : 1.0;

// Reserved pseudo-char id for the shared EFFECTS atlas in the whole-sprite path.
// Effect satellite objects (OBJS flags bit0 / node+0x15c, Effect Poly 0x0CED0000)
// resolve their sprite from this atlas instead of the owner's PL{cid}. Registered
// into this.chars[FX_CID] so the GPU's existing per-cid atlas/grouping picks it up
// with no HTML change. 0xFE0 is far outside the 0..0x39 real char_id range.
const FX_CID = 0xFE0;

export class SpriteClient {
  constructor() {
    // Per-character atlases, lazy-loaded by char_id as characters appear in the
    // state. chars[char_id] = { img:ImageBitmap, sprites:{sid:{...}}, name }.
    this.chars = {};
    this._loading = {};       // char_id -> Promise (de-dupe concurrent fetches)
    this.charBase = null;     // URL base for per-char atlases, e.g. './test-atlas/chars'
    this.screenW = 640; this.screenH = 480;
    this.spriteScale = 1.0;   // constant size factor — 1.0: baked offsets are already screen-space
    this._zoom = 1;           // derived camera zoom — INFO ONLY (shown, not applied)
    this._lastFc = null;      // last game frame_counter (for frame-timed velocity)
    this.inMatch = 0;
    // All 6 character slots (P1C1,P2C1,P1C2,P2C2,P1C3,P2C3). The on-screen POINT
    // can be any of a side's 3 — and a called assist is a bench char briefly
    // active — so we read all 6 and render every active one.
    this.slot = Array.from({ length: 6 }, () => this._blank());
    this._lastNote = 'no atlas loaded';
    // State-stream (GSTA) bandwidth — the whole point of Option 6. Rolling 1s window.
    this._bwBytes = 0; this._bwFrames = 0; this._bwT0 = 0;
    this._bwRate = 0; this._bwHz = 0; this._lastSize = 0;
    this.sparks = [];          // active hit-sparks {x,y,t0,type}
    this.sparksOn = true;
    this.effects = [];         // server-isolated TA effect quads {hash,cx,cy,w,h} (EFCT packet)
    this.objects = [];         // pool satellite objects {cid,sid,x,y} (OBJS packet) — cape/effects/projectiles
    this.objectsOn = true;
    this._objBridge = false;   // flicker-bridge: re-draw last frame's missing objects (lingers removed objs 1 frame) — OFF by default
    // STEP-1 WIRE fx flags (whole-sprite path). APPROXIMATE — baked sprites are RGB,
    // so these are TINT approximations, NOT the exact hurt/overlay palette-bank swap.
    // Default ON; subtle. Toggle window._spriteclient.hitFlashOn/overlayOn = false.
    this.hitFlashOn = true;    // char+0x12d/0x12e nonzero -> white/red flash tint on the body
    this.overlayOn  = false;   // OFF: char+0x1a4 is nonzero for NORMAL render classes (it washed every body blue); re-enable only with the exact overlay-bank swap, not a blanket tint
    this._fxCache = new Map(); // texture hash -> canvas (decoded from TXTR packets)
    this._lastEfctN = 0;
    this.effectsOn = true;

    // ===== STAF (stripped-TA frame) render path =====
    // Pixel-exact: the server ships the full textured-quad list every frame
    // (STAF) + each unique texture ONCE (TX64), content-addressed by a 64-bit id.
    // We cache tex_id -> canvas and draw each quad's axis-aligned dest rect with
    // its UV sub-rect + PVR blend. No atlas, no VRAM, no ta_parse — see
    // docs/STRIPPED-TA-DESIGN.md. tex_id is a JS string ("hi:lo") so the 64-bit
    // value survives Map keys without precision loss.
    this.stafQuads = [];       // per-tri descriptors {key,blend,shadInstr,ignoreTexA,textured,punch,voff}
    this._stafV = null;        // Float32Array: 8 floats/vert [x,y,u,v,r,g,b,a], 3 verts/tri
    this._stafVCount = 0;
    this._stafTex = new Map(); // tex_id(string) -> {w,h,rgba} decoded texture (from TX64)
    this.stafFrame = 0;
    this.stafOn = true;
    this._stafQuadN = 0; this._stafTexN = 0;

    // ===== CHARQ (CHRQ per-part PVR sprite-quad character render) =====
    // _charqParsed is the PVR2Renderer input contract (same shape as _stafParsed),
    // built in onCHARQ from the Oracle-read per-part screen quads. Textures resolve
    // from LIVE VRAM via the global TextureManager (real tcw/tsp/pcw) — no surrogate.
    this.charqFrame = 0;
    this.charqOn = false;
    this._charqFrame = null;   // {frameNum, objs:[{cid,sprite_id,node,quads:[...]}]}
    this._charqParsed = null;  // {vertexData,vertexCount,opaque,punchThrough,translucent}
    this._charqQuadN = 0;

    // ===== Assembly-driven render path (parallel to whole-sprite) =====
    // When true, buildAssemblyDrawList() is the GPU source instead of buildDrawList().
    // Each object's sprite_id resolves to an assembly (a list of part placements);
    // we draw each part rect from the per-char part atlas at its (dx,dy) offset.
    // See docs/ASSEMBLY-DRIVEN-DESIGN.md §2.3.
    this.assemblyMode = false;
    // asm[cid] = { img:ImageBitmap, parts:{idx:{x,y,w,h}}, asm:{sid:[{part,dx,dy,flip,z}]},
    //              palette:[...], pal128:[[r,g,b]...], screenW, screenH, name }
    this.asmChars = {};
    this._asmLoading = {};     // cid -> Promise (de-dupe)
    // Negative cache: char_ids whose emitter-atlas fetch already 404'd (or otherwise
    // failed). loadAsmChar attempts ONCE per char; on failure the cid lands here and
    // every subsequent frame skips the fetch silently. Without this a genuinely-missing
    // char's parts.png/asm.json 404 re-fires every frame (the ?t=Date.now() bust defeats
    // the HTTP cache) -> a 404 storm that stalls the main render. resetAsmMissing()
    // clears it after a deploy so newly-shipped atlases get a fresh attempt.
    this._asmMissing = new Set();
    // sel -> {tcw,tsp,pcw} resolver for the ON-THE-FLY live-VRAM emitter
    // (buildEmitterLiveCharq). THE OPEN PIECE: maps a static GFX1 selector to the VRAM
    // tile the engine loaded it to. Null by default — the live path is gated OFF until
    // this is populated from an Oracle probe (0x8C0345C4: rmem r11:8 + resulting TCW)
    // or the contiguous GFX1 load layout. A heuristic stub an operator can wire up:
    //   this._selToTcw = SpriteClient.heuristicSelToTcw(vramBase /*per-char GFX base*/);
    // It encodes the CHARQ-confirmed shape (PAL4 fmt5, 32x32 tiles, stride 0x200, pal
    // bank = player slot) but the per-char vramBase + exact sel ordering are UNKNOWN,
    // so it WILL mis-resolve until the probe confirms them. Do NOT ship it on by default.
    this._selToTcw = null;
    // CpsX/CpsY game scale (work.asm, Preppy RE) — part dx/dy/w/h are in game px;
    // screen_x/y is already in 640x480 screen space. These factors convert game px
    // to screen px: CpsXScale=0x3FD55555=5/3, CpsYScale=0x40092492=15/7.
    this.asmScaleX = 5/3;   // 1.6667 — CpsXScale from work.asm
    this.asmScaleY = 15/7;  // 2.1429 — CpsYScale from work.asm
    this._asmNote = 'assembly: no atlas';
    this._asmMiss = 0; this._asmDrawn = 0;
  }
  _blank() {
    return { active:0, char_id:0, sprite_id:-1, screen_x:0, screen_y:0, facing:0, palette:0,
             health:0, red_health:0, _ph:-1, _maxhp:144,   // health + red(trailing) + prev-health (hits) + max seen (bar full)
             // prediction: previous screen pos + timestamps -> observed screen velocity
             px:0, py:0, t:0, pt:0, vx:0, vy:0,
             // GSTA wire extension (parsed in onGSTA; draw_layer drives z-order, the rest
             // are parsed-but-unused for now — future overlay/facing/palette work).
             draw_layer:0xFF, render_extra:0, facing_1d2:0, pal_color_25:0,
             hyper_armor:0, flight_flag:0, stance:0 };
  }

  static isGSTA(d) {
    return d.length >= 4 && d[0]===GSTA_MAGIC[0] && d[1]===GSTA_MAGIC[1]
        && d[2]===GSTA_MAGIC[2] && d[3]===GSTA_MAGIC[3];
  }

  // 'EFCT'(4) + count(1) + count*[id(1) cx(i16) cy(i16) w(i16) h(i16)] — the
  // server-isolated TA effect quads (screen space). Routed away from the TA
  // decoder by the page (same as GSTA) so applyFrame never sees it.
  static isEFCT(d) {
    return d.length >= 5 && d[0]===69 && d[1]===70 && d[2]===67 && d[3]===84; // 'E','F','C','T'
  }
  onEFCT(d) {
    const n = d[4];
    const dv = new DataView(d.buffer, d.byteOffset, d.byteLength);
    const fx = [];
    let o = 5;
    for (let i = 0; i < n && o + 20 <= d.length; i++) {
      fx.push({
        hash: dv.getUint32(o, true),
        cx: dv.getInt16(o + 4, true), cy: dv.getInt16(o + 6, true),
        w:  dv.getInt16(o + 8, true), h:  dv.getInt16(o + 10, true),
        // UV sub-rect of the shared EFKYTEX page (u16 normalized) — which frame to draw.
        u0: dv.getUint16(o + 12, true) / 65535, v0: dv.getUint16(o + 14, true) / 65535,
        u1: dv.getUint16(o + 16, true) / 65535, v1: dv.getUint16(o + 18, true) / 65535,
      });
      o += 20;
    }
    this.effects = fx;
    this._lastEfctN = n;
  }

  // 'HUDQ'(4) + count(1) + count*[hash(4) cx,cy,w,h(i16) u0,v0,u1,v1(u16)] — the SAME
  // 20B record as EFCT, but these are the HUD's textured quads (health bars / timer /
  // hit-counter / super meters) captured from the top+bottom screen strips. Drawn with
  // REGULAR alpha blend (not additive) — the real game HUD, not a synthesized one.
  static isHUDQ(d) { return d.length >= 5 && d[0]===72 && d[1]===85 && d[2]===68 && d[3]===81; } // 'H','U','D','Q'
  onHUDQ(d) {
    const n = d[4];
    const dv = new DataView(d.buffer, d.byteOffset, d.byteLength);
    const q = []; let o = 5;
    for (let i = 0; i < n && o + 20 <= d.length; i++) {
      q.push({ hash: dv.getUint32(o, true),
        cx: dv.getInt16(o+4,true), cy: dv.getInt16(o+6,true), w: dv.getInt16(o+8,true), h: dv.getInt16(o+10,true),
        u0: dv.getUint16(o+12,true)/65535, v0: dv.getUint16(o+14,true)/65535,
        u1: dv.getUint16(o+16,true)/65535, v1: dv.getUint16(o+18,true)/65535 });
      o += 20;
    }
    this.hudQuads = q;
    this._lastHudN = n;
  }

  // 'PALF'(4) + 6×u16 paleffect (char+0x40). Nonzero = that slot's body is hit-
  // flashing (engine swaps it to the hurt palette bank). We tint the body.
  static isPALF(d) { return d.length >= 16 && d[0]===80 && d[1]===65 && d[2]===76 && d[3]===70; } // 'P','A','L','F'
  onPALF(d) {
    const dv = new DataView(d.buffer, d.byteOffset, d.byteLength);
    for (let s = 0; s < 6 && 4 + s * 2 + 1 < d.length; s++)
      this.slot[s].paleffect = dv.getUint16(4 + s * 2, true);
  }

  // 'WTCH'(4) base(u16) len(u16) then 6 x [active(1) char_id(1) bytes(len)] — the
  // LIVE BIT-PROBE. We diff vs the previous frame and keep recently-changed bytes
  // so the overlay shows which RAM field moved when (correlate to an on-screen
  // visual). watchText() formats the recent changes.
  static isWATCH(d) { return d.length >= 8 && d[0]===87 && d[1]===84 && d[2]===67 && d[3]===72; } // 'W','T','C','H'
  onWATCH(d) {
    const dv = new DataView(d.buffer, d.byteOffset, d.byteLength);
    const base = dv.getUint16(4, true), len = dv.getUint16(6, true);
    this._wBase = base; this._wLen = len;
    if (!this._wPrev) this._wPrev = [];
    if (!this._wChg)  this._wChg = new Map();   // "slot:off" -> {slot,cid,off,val,prev,t}
    const now = (this._wFrame = (this._wFrame || 0) + 1);
    let o = 8;
    for (let s = 0; s < 6; s++) {
      const active = d[o], cid = d[o+1]; o += 2;
      const cur = d.subarray(o, o + len); o += len;
      if (active) {
        const prev = this._wPrev[s];
        if (prev && prev.length === len) {
          for (let b = 0; b < len; b++) if (cur[b] !== prev[b])
            this._wChg.set(s + ':' + b, { slot:s, cid, off: base + b, val: cur[b], prev: prev[b], t: now });
        }
        this._wPrev[s] = cur.slice();
      } else this._wPrev[s] = null;
    }
    for (const [k, v] of this._wChg) if (now - v.t > 90) this._wChg.delete(k);   // prune >~1.5s old
  }
  watchText() {
    const po = (this._probeOff != null ? this._probeOff : 0x1a0);
    const poff = po - (this._wBase || 0);
    // current value of the PROBED field per active slot (this drives the flash)
    let vals = [];
    for (let s = 0; s < 6; s++) { const v = this._wPrev && this._wPrev[s]; if (v && poff >= 0 && poff < v.length && this.slot[s] && this.slot[s].active) vals.push(`s${s}=${v[poff]}`); }
    const head = `>> FLASH FIELD = +0x${po.toString(16)}  [ / ] to step  (flashes when nonzero)\n   ${vals.join(' ') || '(no active slots)'}\n`;
    if (!this._wChg || !this._wChg.size) return head + `WATCH +0x${(this._wBase||0).toString(16)} ${(this._wLen||0)}B — no recent changes`;
    const arr = [...this._wChg.values()].sort((a,b) => b.t - a.t).slice(0, 24);
    return head + `recent changes:\n` +
      arr.map(c => `s${c.slot}(c${c.cid}) +0x${c.off.toString(16)}: ${c.prev}->${c.val}`).join('\n');
  }

  // 'TXTR'(4) + hash(4) + w(2) + h(2) + zstd(RGBA). The page decompresses and
  // calls onTXTR with the raw RGBA; we cache hash -> canvas for additive draw.
  static isTXTR(d) {
    return d.length >= 12 && d[0]===84 && d[1]===88 && d[2]===84 && d[3]===82; // 'T','X','T','R'
  }
  onTXTR(hash, w, h, rgba) {
    if (!rgba || rgba.length < w * h * 4 || w <= 0 || h <= 0) return;
    let cv = this._fxCache.get(hash);
    if (!cv) { cv = document.createElement('canvas'); cv.width = w; cv.height = h; }
    const ctx = cv.getContext('2d');
    const id = new ImageData(new Uint8ClampedArray(rgba.subarray(0, w * h * 4)), w, h);
    ctx.putImageData(id, 0, 0);
    this._fxCache.set(hash, cv);
  }

  // ===== STAF channel ========================================================
  // 64-bit tex_id -> string key (so it can index a Map without float precision loss).
  static texKey(lo, hi) { return (hi >>> 0).toString(16).padStart(8, '0') + ':' + (lo >>> 0).toString(16).padStart(8, '0'); }

  // 'TX64'(4) texId(8) w(2) h(2) rawSize(4) zstd(RGBA). Caller decompresses the
  // RGBA (offset 20) and passes it in — same shape as onTXTR but 64-bit keyed.
  static isTX64(d) {
    return d.length >= 20 && d[0]===84 && d[1]===88 && d[2]===54 && d[3]===52; // 'T','X','6','4'
  }
  // Cache the decoded RGBA (+dims) by 64-bit key. The GL renderer (StafGL) uploads
  // it to a GPUtexture lazily on first use and tracks uploaded keys itself; we just
  // hold the bytes so a re-decode is never needed. (rgba is copied — the source
  // decompress buffer is reused by the next packet.)
  onTX64(key, w, h, rgba) {
    if (!rgba || rgba.length < w * h * 4 || w <= 0 || h <= 0) return;
    this._stafTex.set(key, { w, h, rgba: new Uint8Array(rgba.subarray(0, w * h * 4)) });
    this._stafTexN = this._stafTex.size;
  }

  // === STAF wire (DE-INDEXED STRIP) — post-zstd (ZCST stripped by the caller) ====
  // 'STAF'(4) frameNum(4) pvr_snapshot[16](64) vertCount(u32)@72 polyCount(u32)@76
  //   vertCount × vertex (28 B): x,y,z(f32) u,v(f32) col(4 = R,G,B,A) spc(4 = R,G,B,A)
  //   polyCount × poly  (33 B): firstVert(u32) vertCount(u32) texId(8)
  //                             tcw(4) tsp(4) pcw(4) isp(4) listType(1)
  // x,y,z and u,v are the TA's OWN projected coords (640x480 screen space, real
  // 1/w depth). firstVert/vertCount span a CONSECUTIVE run in the vertex buffer =
  // a degenerate-linked triangle STRIP — IDENTICAL in shape to ta-parser.mjs's
  // output (PolyParam.first/count over the strip vertex buffer). PVR2Renderer's
  // _buildIndexBuffer does the winding-correct strip->triangle-list conversion
  // (and the GPU drops the zero-area link triangles), so the STAF path feeds
  // PVR2Renderer the EXACT same way as the working out-of-match TA video. tcw 0 =
  // untextured (use per-vertex col). The server already content-cached each texture
  // once (TX64); the client overrides tcw with a per-frame surrogate for the texMgr
  // shim to resolve the cached RGBA without a VRAM decode.
  static isSTAF(d) {
    return d.length >= 10 && d[0]===83 && d[1]===84 && d[2]===65 && d[3]===70; // 'S','T','A','F'
  }
  // Parse STAF into the PVR2Renderer input contract (web/webgpu/pvr2-renderer.mjs):
  //   _stafParsed = { vertexData, vertexCount, opaque[], punchThrough[], translucent[] }
  // vertexData is the SAME 28-byte/vertex layout TAParser produces:
  //   x,y,z(f32) col(u8x4 RGBA) spc(u8x4 RGBA) u,v(f32).  Each STAF poly becomes a
  //   PolyParam { first, count, tsp, tcw, pcw, isp, tileclip } whose first/count are
  //   consecutive vertex indices (a strip); _buildIndexBuffer turns count into
  //   (count-2) triangles with alternating winding. tcw is OVERRIDDEN with a
  //   per-frame texture SURROGATE (1:1 with the 64-bit texId the server hashed from
  //   the raw tcw) so the STAF texMgr shim resolves the cached GPUTexture by tcw
  //   without a VRAM decode; pcw paraType is forced to 4 so PVR2Renderer treats it
  //   as a poly while keeping the real textured/gouraud/offset bits.
  onSTAF(d) {
    const dv = new DataView(d.buffer, d.byteOffset, d.byteLength);
    this.stafFrame = dv.getUint32(4, true);
    // pvr_snapshot[16] u32 at offset 8 — PVR2Renderer._ndcMat reads [0] for the
    // render screen size (w=(tx+1)*32, h=(ty+1)*32). Carry it so the overlay scales
    // to the real 640x480 (not the 32x32 default of an all-zero snapshot).
    if (!this._stafSnap) this._stafSnap = new Uint32Array(16);
    for (let i = 0; i < 16; i++) this._stafSnap[i] = dv.getUint32(8 + i * 4, true);
    const vertCount = dv.getUint32(72, true);
    const polyCount = dv.getUint32(76, true);
    const VSTRIDE = 28, PSTRIDE = 33;
    let o = 80;
    // Bound vertCount/polyCount against the actual buffer length (defensive).
    const vBytes = vertCount * VSTRIDE;
    const nVerts = Math.min(vertCount, ((d.length - 80) / VSTRIDE) | 0);
    // 28-byte/vertex interleaved buffer (matches TAParser/PVR2Renderer VBL stride 28).
    if (!this._stafVB || this._stafVB.byteLength < nVerts * 28) {
      this._stafVB = new ArrayBuffer(Math.max(nVerts * 28, 1 << 16));
      this._stafVBf = new Float32Array(this._stafVB);
      this._stafVBu = new Uint8Array(this._stafVB);
    }
    const f32 = this._stafVBf, u8 = this._stafVBu;
    // Copy/repack the vertex region: wire (x,y,z,u,v,col,spc) -> VBL (x,y,z,col,spc,u,v).
    for (let i = 0; i < nVerts; i++) {
      const x = dv.getFloat32(o, true);
      const y = dv.getFloat32(o + 4, true);
      const z = dv.getFloat32(o + 8, true);
      const u = dv.getFloat32(o + 12, true);
      const v = dv.getFloat32(o + 16, true);
      const cr = d[o + 20], cg = d[o + 21], cb = d[o + 22], ca = d[o + 23];
      const sr = d[o + 24], sg = d[o + 25], sb = d[o + 26], sa = d[o + 27];
      o += VSTRIDE;
      const fi = i * 7, bi = i * 28;
      f32[fi] = x; f32[fi + 1] = y; f32[fi + 2] = z;
      u8[bi + 12] = cr; u8[bi + 13] = cg; u8[bi + 14] = cb; u8[bi + 15] = ca;  // col RGBA
      u8[bi + 16] = sr; u8[bi + 17] = sg; u8[bi + 18] = sb; u8[bi + 19] = sa;  // spc (offset) RGBA
      f32[fi + 5] = u; f32[fi + 6] = v;
    }
    // Poly records begin after the FULL declared vertex region (the server appends
    // poly records after all verts), so seek by vertCount, not the clamped nVerts.
    let po = 80 + vBytes;
    const maxPoly = Math.min(polyCount, ((d.length - po) / PSTRIDE) | 0);
    const op = [], pt = [], tr = [];
    // Per-frame texId -> surrogate int (1:1). Surrogate 0 reserved for "no texture".
    if (!this._stafSurr) this._stafSurr = new Map();
    const surrMap = this._stafSurr; surrMap.clear();
    this._stafSurrTex = this._stafSurrTex || [];      // surrogate -> texKey string
    let surrNext = 1;
    for (let i = 0; i < maxPoly; i++) {
      const first = dv.getUint32(po, true); po += 4;
      const count = dv.getUint32(po, true); po += 4;
      const texLo = dv.getUint32(po, true); po += 4;   // texId low 32
      const texHi = dv.getUint32(po, true); po += 4;   // texId high 32
      const tcwRaw = dv.getUint32(po, true); po += 4;  // (kept for reference)
      const tsp = dv.getUint32(po, true); po += 4;
      const pcwRaw = dv.getUint32(po, true); po += 4;
      const isp = dv.getUint32(po, true); po += 4;
      const lt = d[po++];                              // listType: 0=op 1=pt 2=tr
      if (count < 3 || first + count > nVerts) continue;
      const textured = ((pcwRaw >> 3) & 1) !== 0 && (texLo !== 0 || texHi !== 0);
      // Resolve a texture surrogate (1:1 with the 64-bit texId). The poly's texId
      // matches the TX64 cache key exactly (onTX64 stores by texKey(lo,hi)), so the
      // texMgr shim resolves surrogate -> texKey -> cached decoded RGBA with no VRAM.
      let surr = 0;
      if (textured) {
        const key = SpriteClient.texKey(texLo, texHi);
        surr = surrMap.get(key);
        if (surr === undefined) { surr = surrNext++; surrMap.set(key, surr); this._stafSurrTex[surr] = key; }
      }
      // pcw: keep real textured/gouraud/offset bits but force paraType=4 (poly).
      const pcw = (4 << 29) | (pcwRaw & 0x1FFFFFFF);
      // tcw OVERRIDDEN with the surrogate (the STAF texMgr shim keys on it).
      const pp = { first, count, tsp, tcw: surr, pcw, isp, tileclip: 0 };
      (lt === 1 ? pt : lt === 2 ? tr : op).push(pp);
    }
    this._stafParsed = {
      vertexData: u8.subarray(0, nVerts * 28),
      vertexCount: nVerts,
      opaque: op, punchThrough: pt, translucent: tr,
    };
    this._stafQuadN = op.length + pt.length + tr.length;
  }

  stafStatsText() {
    return `STAF: frame=${this.stafFrame} tris=${this._stafQuadN} texCache=${this._stafTexN}`;
  }

  // ===== CHARQ channel (CHRQ — per-part PVR sprite-quad character render) =====
  // The Oracle-read character data (project_charq_breakthrough): each character
  // part is a PVR SPRITE QUAD — 4 screen corners + per-corner UV + the real
  // tcw/tsp/pcw — so it feeds web/webgpu/pvr2-renderer.mjs (TA-truth rasterizer)
  // natively, with ZERO raster guessing. Unlike STAF (which ships textures via
  // the TX64 surrogate channel), CHARQ references textures ALREADY in live VRAM
  // (the mirror dirty-page channel maintains D.vram + the palette), so the real
  // tcw resolves through texMgr.getTexture(tsp,tcw,vram) — the SAME decode the TA
  // path and the offline composite used. This is also the Phase-2 offline-GSTA
  // emitter target: only the quad SOURCE changes, the render path stays identical.
  //
  // Wire (post-ZCST-decompress; caller strips the ZCST envelope):
  //   'CHRQ'(4) frameNum(u32) objCount(u32)
  //   per object:  cid(u8) flags(u8) sprite_id(u16) node(u32) quadCount(u16) pad(u16)
  //     per quad (68 B): Ax,Ay,Bx,By,Cx,Cy,Dx,Dy : 8×f32 (screen corners, px)
  //                      AU,AV,BU,BV,CU,CV         : 6×f32 (UVs; D derived by
  //                        parallelogram closure DU=AU+CU-BU, DV=AV+CV-BV)
  //                      tcw,tsp,pcw               : 3×u32  (real PVR sprite paras)
  static isCHARQ(d) {
    return d.length >= 12 && d[0]===67 && d[1]===72 && d[2]===82 && d[3]===81; // 'C','H','R','Q'
  }
  // Parse CHRQ into BOTH a structured frame (for labels / inspection) and the
  // PVR2Renderer input contract (_charqParsed = {vertexData,vertexCount,opaque[],
  // punchThrough[],translucent[]}). Each quad becomes a 4-vertex triangle STRIP
  // in order A,B,D,C — _buildIndexBuffer turns that into the two parallelogram
  // triangles (A,B,D)+(B,C,D), winding-correct. The PVR2Renderer VBL stride is 28:
  //   x,y,z(f32) col(u8x4 RGBA) spc(u8x4 RGBA) u,v(f32).
  // tcw/tsp/pcw are passed THROUGH unchanged (real PVR paras): the renderer's
  // op/pt/tr classification, blend (tsp bits), and texture decode (texMgr) all use
  // them directly. listType is derived from the PVR blend (additive => translucent,
  // else opaque) since the wire ships the raw paras, not a pre-sorted list index.
  onCHARQ(d) {
    const dv = new DataView(d.buffer, d.byteOffset, d.byteLength);
    this.charqFrame = dv.getUint32(4, true);
    const objCount = dv.getUint32(8, true);
    let o = 12;
    const objs = [];
    // First pass: count quads so the vertex buffer can be sized exactly.
    let totalQuads = 0;
    const objHdrs = [];
    for (let i = 0; i < objCount && o + 12 <= d.length; i++) {
      const cid = d[o], flags = d[o + 1];
      const sprite_id = dv.getUint16(o + 2, true);
      const node = dv.getUint32(o + 4, true);
      const quadCount = dv.getUint16(o + 8, true);
      o += 12;
      const qStart = o;
      const nq = Math.min(quadCount, ((d.length - o) / 68) | 0);
      objHdrs.push({ cid, flags, sprite_id, node, quadCount: nq, qStart });
      o += nq * 68;
      totalQuads += nq;
    }
    // 4 verts per quad. PVR2Renderer VBL = 28 bytes/vertex.
    const nVerts = totalQuads * 4;
    if (!this._charqVB || this._charqVB.byteLength < nVerts * 28) {
      this._charqVB = new ArrayBuffer(Math.max(nVerts * 28, 1 << 16));
      this._charqVBf = new Float32Array(this._charqVB);
      this._charqVBu = new Uint8Array(this._charqVB);
    }
    const f32 = this._charqVBf, u8 = this._charqVBu;
    const op = [], pt = [], tr = [];
    let vi = 0; // vertex index cursor
    // DEGENERATE-QUAD GUARD (2026-06-10): a few quads arrive with a wild corner
    // (a bad/garbage corner read on the server side, or a leaked non-body submit),
    // producing big spanning "garbage triangles" across the canvas. _buildIndexBuffer
    // is per-poly correct (no strip bridging — each quad is its own count=4 run
    // anchored at pp.first), so the artifacts are these wild quads, not stitching.
    // Filter any quad whose bbox span exceeds QSPAN_MAX px or whose corners fall far
    // outside the 640x480 frame. Tunable via window._charqQSpan / _charqMargin.
    const QSPAN_MAX = (typeof window !== 'undefined' && window._charqQSpan) || 384;
    const MARGIN    = (typeof window !== 'undefined' && window._charqMargin) || 512;
    let qDropped = 0, qKept = 0;
    for (const h of objHdrs) {
      let q = h.qStart;
      const objQuads = [];
      for (let k = 0; k < h.quadCount; k++) {
        const Ax = dv.getFloat32(q, true),     Ay = dv.getFloat32(q + 4, true);
        const Bx = dv.getFloat32(q + 8, true), By = dv.getFloat32(q + 12, true);
        const Cx = dv.getFloat32(q + 16, true),Cy = dv.getFloat32(q + 20, true);
        const Dx = dv.getFloat32(q + 24, true),Dy = dv.getFloat32(q + 28, true);
        const AU = dv.getFloat32(q + 32, true),AV = dv.getFloat32(q + 36, true);
        const BU = dv.getFloat32(q + 40, true),BV = dv.getFloat32(q + 44, true);
        const CU = dv.getFloat32(q + 48, true),CV = dv.getFloat32(q + 52, true);
        const tcw = dv.getUint32(q + 56, true);
        const tsp = dv.getUint32(q + 60, true);
        const pcw = dv.getUint32(q + 64, true);
        q += 68;
        // Degenerate guard: bbox span + off-frame test over all 4 corners.
        const minX = Math.min(Ax, Bx, Cx, Dx), maxX = Math.max(Ax, Bx, Cx, Dx);
        const minY = Math.min(Ay, By, Cy, Dy), maxY = Math.max(Ay, By, Cy, Dy);
        const bad =
          !(Number.isFinite(minX) && Number.isFinite(minY) &&
            Number.isFinite(maxX) && Number.isFinite(maxY)) ||
          (maxX - minX) > QSPAN_MAX || (maxY - minY) > QSPAN_MAX ||
          maxX < -MARGIN || minX > 640 + MARGIN ||
          maxY < -MARGIN || minY > 480 + MARGIN;
        if (bad) {
          qDropped++;
          if (typeof window !== 'undefined' && window._charqDbg && qDropped <= 8) {
            console.warn(`[onCHARQ] DROP degenerate quad cid=${h.cid} sid=${h.sprite_id} ` +
              `span=${(maxX-minX).toFixed(0)}x${(maxY-minY).toFixed(0)} ` +
              `A(${Ax.toFixed(0)},${Ay.toFixed(0)}) B(${Bx.toFixed(0)},${By.toFixed(0)}) ` +
              `C(${Cx.toFixed(0)},${Cy.toFixed(0)}) D(${Dx.toFixed(0)},${Dy.toFixed(0)})`);
          }
          continue;
        }
        qKept++;
        // D's UV by parallelogram closure (matches the wire's corner derivation).
        const DU = AU + CU - BU, DV = AV + CV - BV;
        // Emit the 4 verts in STRIP order A,B,D,C so _buildIndexBuffer yields the
        // two parallelogram triangles (A,B,D)+(B,C,D), winding-correct. White
        // vertex colour (texture-modulate; shadInstr from tsp decides replace/mod).
        const first = vi;
        const put = (x, y, u, v) => {
          const fi = vi * 7, bi = vi * 28;
          f32[fi] = x; f32[fi + 1] = y; f32[fi + 2] = 0.5; // z mid (sprite para, no real depth)
          u8[bi + 12] = 255; u8[bi + 13] = 255; u8[bi + 14] = 255; u8[bi + 15] = 255; // col
          u8[bi + 16] = 0; u8[bi + 17] = 0; u8[bi + 18] = 0; u8[bi + 19] = 0;         // spc (offset)
          f32[fi + 5] = u; f32[fi + 6] = v;
          vi++;
        };
        put(Ax, Ay, AU, AV);
        put(Bx, By, BU, BV);
        put(Dx, Dy, DU, DV);
        put(Cx, Cy, CU, CV);
        const pp = { first, count: 4, tsp, tcw, pcw, isp: 0, tileclip: 0 };
        // Classify by PVR blend: additive (src=ONE/SrcA & dst=ONE) => translucent
        // (drawn in the blended pass); everything else as punch-through so the
        // character draws with alpha-test (index-0 transparent) like the TA path.
        const sb = (tsp >> 29) & 7, db = (tsp >> 26) & 7;
        if (db === 1 && (sb === 1 || sb === 4)) tr.push(pp);
        else pt.push(pp);
        objQuads.push({ corners: [Ax, Ay, Bx, By, Cx, Cy, Dx, Dy], uv: [AU, AV, BU, BV, CU, CV], tcw, tsp, pcw });
      }
      objs.push({ cid: h.cid, flags: h.flags, sprite_id: h.sprite_id, node: h.node, quads: objQuads });
    }
    // vi is the count of verts ACTUALLY emitted (dropped quads never advance it),
    // so size the parsed buffer to vi — not nVerts (the pre-drop upper bound).
    const emittedVerts = vi;
    this._charqFrame = { frameNum: this.charqFrame, objs };
    this._charqParsed = {
      vertexData: u8.subarray(0, emittedVerts * 28),
      vertexCount: emittedVerts,
      opaque: op, punchThrough: pt, translucent: tr,
    };
    this._charqQuadN = qKept;
    this._charqQuadDropped = qDropped;
    // Throttled diagnostic: confirm onCHARQ fires + parses non-empty geometry.
    // Enable with window._charqDbg=1 in the console.
    if (typeof window !== 'undefined' && window._charqDbg) {
      if (!this._charqDbgN) this._charqDbgN = 0;
      if ((this._charqDbgN++ % 60) === 0) {
        console.log(`[onCHARQ] frame=${this.charqFrame} objs=${objCount} quads=${qKept}/${totalQuads} (dropped ${qDropped}) verts=${emittedVerts} op=${op.length} pt=${pt.length} tr=${tr.length} bytes=${d.length}`);
      }
    }
  }

  charqStatsText() {
    const n = this._charqFrame ? this._charqFrame.objs.length : 0;
    return `CHARQ: frame=${this.charqFrame||0} objs=${n} quads=${this._charqQuadN||0}`;
  }

  // 'OBJS'(4) + count(1) + N×[cid(1), sprite_id(2 LE), type(1), x(i16 LE), y(i16 LE),
  //   flags(1), hot_dx(s8), hot_dy(s8), effect_key(u16 LE)] = 13B each
  //   (auto-detected; 11B/9B/8B legacy).
  //
  // flags bit0 = is_effect (route to the effects atlas, not PL{cid}).
  // hot_dx/hot_dy (PATH A) = the object's TRUE assembly hotspot (min dx,dy over the
  // node+0x178 extras records) — the satellite's own origin, which the body-relative
  // baked sp.dx does not match. effect_key = low 16 bits of the GFX base (node+0x15c),
  // a stable per-effect content key (parsed-but-unused for now). Stride is auto-detected
  // from the packet length so the client consumes whichever the server ships (old
  // 8B/9B/11B servers -> trailing fields default to 0/baked).
  static isOBJS(d) {
    return d.length >= 5 && d[0]===79 && d[1]===66 && d[2]===74 && d[3]===83; // 'O','B','J','S'
  }
  onOBJS(d) {
    const n = d[4]; const dv = new DataView(d.buffer, d.byteOffset, d.byteLength);
    // Detect per-object stride: 11B (flags + hot_dx + hot_dy), 9B (flags only), or
    // legacy 8B. The flags byte (GSTA enrich step 1): bit0 = is_effect (route to the
    // effects atlas, not PL{cid}); bits1-7 reserved. hot_dx/hot_dy (PATH A) = the
    // object's TRUE assembly hotspot (min dx,dy over node+0x178 extras), 2×int8; the
    // object draw anchors satellites here instead of the baked body-relative sp.dx
    // (0,0 => no extras, keep the baked anchor). Old servers omit the trailing bytes.
    const body = d.length - 5;
    const stride = (n > 0 && body === n * 14) ? 14   // GSTA wire ext: +blend u8
                 : (n > 0 && body === n * 13) ? 13   // GSTA wire ext: +effect_key u16
                 : (n > 0 && body === n * 11) ? 11
                 : (n > 0 && body === n * 9)  ? 9
                 : 8;
    const hasFlags = stride >= 9;
    const hasHot   = stride >= 11;
    const hasKey   = stride >= 13;
    const hasBlend = stride === 14;
    const objs = []; let o = 5;
    for (let i = 0; i < n && o + stride <= d.length; i++) {
      const raw = dv.getUint16(o+1, true);   // sprite_id with 0x8000 hflip bit
      const ob = { cid: d[o], sid: raw & 0x7fff, type: d[o+3],
                   xflip: (raw & 0x8000) ? 1 : 0,   // object's OWN flip (node+0x130) — NOT owner facing
                   x: dv.getInt16(o+4, true), y: dv.getInt16(o+6, true),
                   isEffect: 0, hotDx: 0, hotDy: 0, hasHot: false, effect_key: 0,
                   listType: null, blend: null };
      if (hasFlags) {
        const f = d[o+8];
        ob.flags = f;
        ob.isEffect = (f & 0x01) ? 1 : 0;     // node+0x15c in Effect Poly 0x0CED0000
      }
      if (hasHot) {
        ob.hotDx = dv.getInt8(o+9);
        ob.hotDy = dv.getInt8(o+10);
        ob.hasHot = !(ob.hotDx === 0 && ob.hotDy === 0);  // 0,0 => server found no extras
      }
      // GSTA wire ext: low 16 bits of the GFX base (node+0x15c) — stable per-effect content
      // key. PARSED-BUT-UNUSED for now (future effect routing/dedup).
      if (hasKey) ob.effect_key = dv.getUint16(o+11, true);
      // GSTA wire ext (G2): per-object PVR blend / list-type, RAM-derived server-side
      // (computeObjectBlend): 0=PT/opaque, 1=alpha, 2=additive (effects render additively;
      // ref reference_mvc2_effects_bank + per-category dispatch loc_8c0301f6). The
      // downstream draw list (buildAssemblyDrawList / drawEffects) already keys additive
      // off o.blend in the PVR (src<<4)|dst NIBBLE convention where dst==ONE(1) => additive
      // ('lighter'). So MAP the list-type code -> that nibble so additive effects actually
      // blend through the existing pool-draw path: 2->0x11 (src=ONE,dst=ONE additive),
      // 1->0x45 (normal alpha), 0->0x00 (opaque). Keep the raw code in ob.listType too.
      if (hasBlend) {
        ob.listType = d[o+13];
        ob.blend = (ob.listType === 2) ? 0x11 : (ob.listType === 1) ? 0x45 : 0x00;
      }
      objs.push(ob);
      o += stride;
    }
    this._objsPrev = this.objects || [];   // keep last frame for the flicker bridge
    this.objects = objs;
  }

  // Point the client at a server dir of per-character atlases
  // (PL{cid:02X}.{json,png}). Characters are then fetched on demand as they
  // appear in the streamed state — only what's picked gets downloaded.
  setCharBase(base) { this.charBase = base; this.loadFxAtlas(); this.loadHudAtlas(); }

  // Load the ripped HUD atlas (hud/hud_atlas.{png,json}) — FONT.BIN digits + the
  // white bar swatch. Served beside chars (e.g. <base>/../hud/hud_atlas), the same
  // convention loadFxAtlas uses for effects. Built by tools/rip_hud_atlas.py.
  async loadHudAtlas() {
    if (this._hud || this._hudLoading || !this.charBase) return;
    this._hudLoading = true;
    const base = this.charBase.replace(/\/chars\/?$/, '/hud') + '/hud_atlas';
    const bust = '?t=' + Date.now();
    try {
      const json = await (await fetch(base + '.json' + bust)).json();
      const blob = await (await fetch(base + '.png' + bust)).blob();
      this._hudImg = await createImageBitmap(blob);
      this._hud = json;
      console.log('[sprite-client] loaded hud_atlas:', Object.keys(json.rects || {}).length, 'rects');
    } catch (e) { console.warn('[sprite-client] hud_atlas load failed', e); }
    finally { this._hudLoading = false; }
  }

  // Load the isolated-effect atlas (fx_atlas.{png,json}) — the 5 universal effect
  // textures the server's EFCT isolation references by id (additive overlays).
  async loadFxAtlas() {
    if (this._fx || this._fxLoading || !this.charBase) return;
    this._fxLoading = true;
    const base = this.charBase.replace(/\/chars\/?$/, '/effects') + '/fx_atlas';
    const bust = '?t=' + Date.now();
    try {
      const json = await (await fetch(base + '.json' + bust)).json();
      const blob = await (await fetch(base + '.png' + bust)).blob();
      this._fxImg = await createImageBitmap(blob);
      this._fx = json;
      // WHOLE-SPRITE effect routing: expose the fx atlas as a pseudo-char so
      // buildDrawList()'s effect objects (ob.isEffect) resolve sprites from it and
      // the GPU registers/binds its texture via the same per-cid path. Only when the
      // atlas carries a sprite-keyed `sprites` map (the whole-sprite bake format);
      // an assembly-only fx atlas (parts/asm) stays on the emitter path's _fxAsmChar.
      if (json.sprites) {
        this.chars[FX_CID] = { img: this._fxImg, sprites: json.sprites,
                               name: json.name || 'effects', pal128: json.pal128 };
      }
      console.log('[sprite-client] loaded fx_atlas:',
        (json.effects || []).length, 'effects,', Object.keys(json.sprites || {}).length, 'sprites');
    } catch (e) { console.warn('[sprite-client] fx_atlas load failed', e); }
    finally { this._fxLoading = false; }
  }

  // Lazy-load ONE character's atlas: <charBase>/PL{cid:02X}.{json,png}.
  loadChar(cid) {
    if (this.chars[cid] || this._loading[cid] || !this.charBase) return this._loading[cid];
    const hex = (cid & 0xff).toString(16).padStart(2, '0').toUpperCase();
    const base = `${this.charBase}/PL${hex}`;
    const bust = '?t=' + Date.now();   // re-fetch fresh after an atlas rebuild
    const p = (async () => {
      try {
        const json = await (await fetch(base + '.json' + bust)).json();
        const blob = await (await fetch(base + '.png' + bust)).blob();
        const img = await createImageBitmap(blob);
        this.screenW = json.screenW || this.screenW; this.screenH = json.screenH || this.screenH;
        this.chars[cid] = { img, sprites: json.sprites, name: json.name || ('char' + cid), pal128: json.pal128 };
        // EXACT palette-LUT atlas (optional, out-of-band): PL{hex}_idx.png + _lut.json
        // (tools/rgb_to_indexed.py). Best-effort — absence keeps the RGB path.
        try {
          const [lutR, idxR] = await Promise.all([
            fetch(base + '_lut.json' + bust), fetch(base + '_idx.png' + bust) ]);
          if (lutR.ok && idxR.ok) {
            const lut = await lutR.json();
            const idxImg = await createImageBitmap(await idxR.blob());
            this.chars[cid].idxImg = idxImg; this.chars[cid].lut = lut;
            console.log('[sprite-client] loaded EXACT palette LUT for char', cid,
              'banks', lut.bankList, idxImg.width + 'x' + idxImg.height);
          }
        } catch (_e) { /* no indexed atlas for this char — RGB path */ }
        console.log('[sprite-client] loaded char', cid, json.name, Object.keys(json.sprites).length, 'sprites');
      } catch (e) {
        this.chars[cid] = { img: null, sprites: {}, name: 'char' + cid, err: String(e) };
        console.error('[sprite-client] char', cid, 'load failed', e);
      } finally { delete this._loading[cid]; }
    })();
    this._loading[cid] = p; return p;
  }

  // Lazy-load ONE character's PART atlas + assembly table for the assembly path:
  //   <charBase>/PL{hex}_parts.png  — packed part rectangles
  //   <charBase>/PL{hex}_parts.json — { <part_idx>: {x,y,w,h} }  (rect in the atlas)
  //   <charBase>/PL{hex}_asm.json   — { sprite_id: [{part, dx, dy, flip, z?}], ... }
  // The two JSONs are kept separate exactly as the sibling baker emits them. We
  // also accept an optional palette/pal128 in the asm JSON (reuse the palette path).
  // Clear the negative cache so a freshly-deployed atlas gets re-attempted without a
  // page reload. Call from the console after scp'ing new PLxx_*.{png,json}.
  resetAsmMissing(cid) {
    if (cid == null) this._asmMissing.clear();
    else this._asmMissing.delete(cid & 0xff);
  }

  loadAsmChar(cid) {
    // Already loaded, in-flight, no charBase yet, or a prior attempt already 404'd:
    // do nothing. The _asmMissing guard is what stops the per-frame 404 retry-storm —
    // a genuinely-missing char is fetched ONCE, then skipped silently thereafter.
    if (this.asmChars[cid] || this._asmLoading[cid] || !this.charBase
        || this._asmMissing.has(cid & 0xff)) return this._asmLoading[cid];
    const hex = (cid & 0xff).toString(16).padStart(2, '0').toUpperCase();
    const base = `${this.charBase}/PL${hex}`;
    const bust = '?t=' + Date.now();
    const p = (async () => {
      try {
        const [partsJson, asmRaw, blob] = await Promise.all([
          fetch(base + '_parts.json' + bust).then(r => { if (!r.ok) throw new Error('parts.json ' + r.status); return r.json(); }),
          fetch(base + '_asm.json'   + bust).then(r => { if (!r.ok) throw new Error('asm.json '   + r.status); return r.json(); }),
          fetch(base + '_parts.png'  + bust).then(r => { if (!r.ok) throw new Error('parts.png '  + r.status); return r.blob(); }),
        ]);
        const img = await createImageBitmap(blob);
        // asm JSON may be the flat { sid:[...] } map, or wrapped { assemblies:{...}, parts:{...}, palette, pal128, screenW, screenH }.
        const asm   = asmRaw.assemblies || asmRaw.asm || asmRaw;
        const parts = asmRaw.parts || partsJson.parts || partsJson;
        if (asmRaw.screenW) this.screenW = asmRaw.screenW;
        if (asmRaw.screenH) this.screenH = asmRaw.screenH;
        this.asmChars[cid] = {
          img, parts, asm,
          palette: asmRaw.palette || partsJson.palette || null,
          pal128:  asmRaw.pal128  || partsJson.pal128  || null,
          // screenSpace: parts are baked at native SCREEN-pixel resolution and their
          // dx/dy are game-px offsets from the anchor (bake_emitter_uv.mjs tight bake).
          // The emitter must blit them 1:1 — NO CPS (cpsX/cpsY) re-multiply.
          screenSpace: !!asmRaw.screenSpace,
          // selKeyed: the LEAN emitter atlas — FULL static GFX2 assembly (all poses)
          // keyed by +6 selector; parts placed at owner+pen·CPS+(ax,ay), blit native.
          // Lights up the sel-keyed branch in buildEmitterDrawList (live animating pose).
          selKeyed: !!asmRaw.selKeyed,
          name: asmRaw.name || ('char' + cid),
        };
        console.log('[sprite-client] loaded ASM char', cid, this.asmChars[cid].name,
          Object.keys(parts).length, 'parts,', Object.keys(asm).length, 'assemblies');
      } catch (e) {
        // Missing emitter atlas (e.g. PL09 Iceman has no _parts.png — only PL00/Ryu is
        // baked). Cache the failure as a SKIP marker so (a) this fetch never re-fires —
        // loadAsmChar early-returns once asmChars[cid] is set — and (b) emitAssembly sees
        // !c.img and quietly returns for THAT char, never aborting the whole draw pass.
        // One warn per char (not per frame); not console.error (this is expected, not a bug).
        this.asmChars[cid] = { img: null, parts: {}, asm: {}, name: 'char' + cid, err: String(e), missing: true };
        // Negative-cache the char so loadAsmChar never re-fetches it (stops the per-frame
        // 404 storm). resetAsmMissing(cid) re-arms it after a deploy.
        this._asmMissing.add(cid & 0xff);
        console.warn('[sprite-client] no emitter atlas for char', cid,
          '(' + String(e) + ') — skipping its parts render; other chars unaffected');
      } finally { delete this._asmLoading[cid]; }
    })();
    this._asmLoading[cid] = p; return p;
  }

  // Combined-atlas load (file-picker / single-URL fallback): one JSON
  // {chars:{cid:{sprites}}} + one shared PNG. Populates the same per-char map.
  async loadAtlas(atlasJson, pngBlob) {
    const img = await createImageBitmap(pngBlob);
    this.screenW = atlasJson.screenW || 640; this.screenH = atlasJson.screenH || 480;
    for (const cid in (atlasJson.chars || {})) {
      const c = atlasJson.chars[cid];
      this.chars[cid] = { img, sprites: c.sprites, name: c.name || ('char' + cid) };
    }
    this._lastNote = '';
  }
  async loadAtlasFromUrl(base) {
    const bust = '?t=' + Date.now();
    const json = await (await fetch(base + '.json' + bust)).json();
    const blob = await (await fetch(base + '.png' + bust)).blob();
    await this.loadAtlas(json, blob);
    return Object.keys(json.chars || {}).length;
  }

  onGSTA(d) {
    // --- state-stream bandwidth (rolling 1s window) ---
    const _now = (typeof performance !== 'undefined') ? performance.now() : 0;
    if (!this._bwT0) this._bwT0 = _now;
    this._bwBytes += d.byteLength; this._bwFrames++; this._lastSize = d.byteLength;
    const _dt = _now - this._bwT0;
    if (_dt >= 1000) {
      this._bwRate = this._bwBytes / (_dt / 1000);   // bytes/sec
      this._bwHz   = this._bwFrames / (_dt / 1000);
      this._bwBytes = 0; this._bwFrames = 0; this._bwT0 = _now;
    }
    const dv = new DataView(d.buffer, d.byteOffset, d.byteLength);
    const B = 4;                       // payload starts after 'GSTA'
    this.inMatch = dv.getUint8(B + 0);
    // Global HUD values — already in the state, so the HUD renders from data alone.
    this.hud = {
      timer:   dv.getUint8(B + 1),
      p1lvl:   dv.getUint8(B + 3),  p2lvl:   dv.getUint8(B + 4),
      p1combo: dv.getUint16(B + 5, true), p2combo: dv.getUint16(B + 7, true),
      p1fill:  dv.getUint16(B + 9, true), p2fill:  dv.getUint16(B + 11, true),
    };
    this._maxfill = Math.max(this._maxfill || 1, this.hud.p1fill, this.hud.p2fill);
    const now = (typeof performance !== 'undefined') ? performance.now() : 0;
    // Velocity is timed on the GAME frame delta, NOT the jittery network arrival
    // gap — so a late/early packet doesn't wobble the extrapolation speed.
    const fc = dv.getUint32(B + 21, true);
    const dfr = (this._lastFc != null) ? (fc - this._lastFc) : 0; this._lastFc = fc;
    const frameDt = (dfr >= 1 && dfr <= 8) ? dfr * 16.667 : 0;   // ms of game time since last state
    for (let s = 0; s < 6; s++) {
      const ci = B + 25 + s * 57;      // 25-byte global header + 57*slot (GSTA wire ext: 49->57)
      const sl = this.slot[s];
      const nx = dv.getFloat32(ci + 16, true), ny = dv.getFloat32(ci + 20, true);
      if (sl.active && frameDt > 0) {
        const ivx = (nx - sl.screen_x) / frameDt, ivy = (ny - sl.screen_y) / frameDt;
        sl.vx = sl.vx * 0.4 + ivx * 0.6;   // EMA-smoothed px/ms (kills velocity noise)
        sl.vy = sl.vy * 0.4 + ivy * 0.6;
      } else if (!sl.active) { sl.vx = 0; sl.vy = 0; }
      sl.t = now;
      sl.active   = dv.getUint8(ci + 0);
      sl.char_id  = dv.getUint8(ci + 1);
      sl.facing   = dv.getUint8(ci + 2);
      sl.palette  = dv.getUint8(ci + 7);
      sl.pos_x    = dv.getFloat32(ci + 8,  true);   // arena/world X — for the zoom
      sl.screen_x = nx;
      sl.screen_y = ny;
      const _rawSid = dv.getUint16(ci + 32, true);
      sl.sprite_id = _rawSid & 0x7fff;          // engine indexes GFX2[sid & 0x7FFF] (loc_8c0344d4); strip bit15
      sl.sid_xform = (_rawSid & 0x8000) ? 1 : 0; // bit15 = alt world-transform variant (loc_8c0348c8), not facing
      // Hit-spark: a health drop = a hit landed -> spawn a spark on the defender's
      // upper body. (Guard against round-reset jumps and the first frame.)
      const hp = dv.getUint8(ci + 3);
      const hitNow = (this.inMatch && sl.active && sl._ph >= 0 && hp < sl._ph && (sl._ph - hp) <= 60);
      // Hit-flash: a health drop = a hit landed. The on-body flash has no clean RAM
      // field (live data: 0x12e/0x40 flat; the per-hit changes are undocumented), so
      // we drive it off the health drop already on the wire — flash the victim's body
      // for ~60ms on each hit. (Electric vs white would need the attacker's DamageType.)
      if (hitNow) sl._flashUntil = now + 60;
      if (this.sparksOn && hitNow) {
        const jx = (Math.random()*22 - 11), jy = (Math.random()*16 - 8);
        this.sparks.push({ x: nx + jx, y: ny - 55 + jy, t0: now, type: (sl._ph - hp) >= 14 ? 2 : 0 });
        if (this.sparks.length > 24) this.sparks.shift();
      }
      sl._ph = sl.active ? hp : -1;
      sl.health = hp;
      sl.red_health = dv.getUint8(ci + 4);    // trailing/chip layer (GSTA char +4)
      // GSTA enrich (step 1) — made AVAILABLE here; buildAssemblyDrawList consumes
      // them in step 2. scaleX/Y = per-char/super dynamic zoom (char+0x50/0x54);
      // pal12d/pal12e = per-part palette row + live hit-flash (char+0x12d/0x12e);
      // overlay1a4 = super/aura overlay class (char+0x1a4).
      sl.scaleX     = dv.getFloat32(ci + 38, true);
      sl.scaleY     = dv.getFloat32(ci + 42, true);
      sl.pal12d     = dv.getUint8(ci + 46);
      sl.pal12e     = dv.getUint8(ci + 47);
      sl.overlay1a4 = dv.getUint8(ci + 48);
      // GSTA wire extension (+49..+56). draw_layer drives the emitter z-order (below);
      // the rest are PARSED-BUT-UNUSED for now (future overlay/facing/palette work).
      sl.draw_layer   = dv.getUint8(ci + 49);   // slot-table layer (0xFF = not drawn); z-order
      sl.render_extra = dv.getUint8(ci + 50);   // char+0x151 RenderExtra (super/aura) — unused
      // A2 nuance (audit finding:gsta_wire_ext_completeness): the RENDER-authoritative
      // facing is char+0x110 (= sl.facing @wire+2), the field the body walker loc_8c0344d4
      // gates on (literal 0x0110 @loc_8c034606) and which the ROM setter loc_8c0d97ee writes
      // (facing=1 => faces right). The body draw flips on sl.facing — do NOT switch it to
      // 0x1d2 (geometry is 0.00px-validated against that field). char+0x1d2 (below) is the
      // COPY; use it ONLY to pre-empt 1-frame turn-around lag (it can lead 0x110 by a frame),
      // never as the render gate.
      sl.facing_1d2   = dv.getUint8(ci + 51);   // char+0x1d2 xflip copy — turn-lag hint only, NOT the render gate
      sl.pal_color_25 = dv.getUint8(ci + 52);   // char+0x025 live palette idx — unused (see report)
      sl.hyper_armor  = dv.getUint8(ci + 53);   // char+0x202 Buff_HyperArmor — unused
      sl.flight_flag  = dv.getUint8(ci + 54);   // char+0x201 Flight_Flag — unused
      sl.stance       = dv.getUint8(ci + 55);   // char+0x1f9 stance — unused
      // ci + 56 = _pad (reserved)
      if (sl.active && hp > sl._maxhp) sl._maxhp = hp;   // round-start full = bar max
    }
    // Exact size from state: camera zoom = |Δscreen_x / Δpos_x| between two
    // active characters (camera offset cancels). Tracks MVC2's live zoom.
    let a = -1, b = -1;
    for (let s = 0; s < 6; s++) if (this.slot[s].active) { if (a < 0) a = s; else { b = s; break; } }
    if (a >= 0 && b >= 0) {
      const dp = this.slot[a].pos_x - this.slot[b].pos_x;
      if (Math.abs(dp) > 5) {
        const z = Math.abs((this.slot[a].screen_x - this.slot[b].screen_x) / dp);
        if (z > 0.1 && z < 10) this._zoom = z;
      }
    }
    // ATLAS PRELOAD — BUG 1 FIX (tag-in blank) 2026-06-11. Previously we only kicked the
    // atlas load for ACTIVE slots, so when a bench partner TAGGED IN its slot went active
    // with a char_id whose atlas was never fetched → the async load gap drew nothing for a
    // few frames → the character vanished ("client closes temporarily"). MVC2 populates all
    // six character structs (P1C1..P2C3) with their char_id at match start (the bench/assist
    // chars are loaded), and the GSTA block carries char_id for every slot regardless of
    // `active`. So while IN MATCH we eagerly preload EVERY slot's char atlas — the incoming
    // partner's atlas is already resident before it goes active → zero tag-in gap. Out of
    // match we keep the active-only load (inactive char_id is stale/garbage between matches).
    // The emitter body flicker-bridge (buildEmitterDrawList _heldEmit) is the second-line
    // defense for any residual gap (a brand-new char_id seen mid-match before its fetch lands).
    for (let s = 0; s < 6; s++) {
      const sl = this.slot[s];
      const want = this.inMatch ? (sl.char_id != null) : sl.active;
      if (!want) continue;
      if (this.assemblyMode) this.loadAsmChar(sl.char_id); else this.loadChar(sl.char_id);
    }
  }

  // Draw the current state into a 2D context. Returns a small status object.
  render(ctx) {
    const W = ctx.canvas.width, H = ctx.canvas.height;
    ctx.clearRect(0, 0, W, H);
    this._now0 = (typeof performance !== 'undefined') ? performance.now() : 0;
    const sx = W / (this.screenW || 640);
    const sy = H / (this.screenH || 480);
    let drawn = 0, missing = 0, loading = 0, missKeys = [];

    if (!this._held) this._held = new Array(6).fill(null);   // last drawn sprite per slot
    for (let s = 0; s < 6; s++) {
      const sl = this.slot[s];
      if (!sl.active) { this._held[s] = null; continue; }
      const c = this.chars[sl.char_id];
      if (!c) { loading++; continue; }            // this char's atlas still downloading
      if (!c.img) continue;                        // load failed for this char
      let sp = c.sprites[sl.sprite_id];
      if (sp) {
        this._held[s] = { char_id: sl.char_id, sp };
      } else {
        // Sparse atlas: this sprite_id wasn't in the rip. Hold the last known
        // pose for this character (same char_id) instead of blanking → no blink.
        missing++;
        if (missKeys.length < 3) missKeys.push(`${sl.char_id}/0x${(sl.sprite_id&0xffff).toString(16)}`);
        const h = this._held[s];
        if (h && h.char_id === sl.char_id) sp = h.sp; else continue;
      }

      // Render-time extrapolation: advance position by the observed screen
      // velocity over the time since the last state, clamped to ~2 frames so a
      // direction change can't overshoot. Hides network jitter / inter-state gap.
      let exx = sl.screen_x, eyy = sl.screen_y;
      if (this.predict !== false) {
        const dt = Math.min(this._now0 - sl.t, 33);     // ms since last state, cap 33ms
        if (dt > 0) { exx += sl.vx * dt; eyy += sl.vy * dt; }
      }

      // Destination in game space (sprite size × constant scale).
      const S = this.spriteScale || 1;
      const gx = exx + sp.dx*S, gy = eyy + sp.dy*S;
      const dx = gx * sx, dy = gy * sy, dw = sp.wG * S * sx, dh = sp.hG * S * sy;
      const flip = (sl.facing !== sp.facing);

      ctx.save();
      if (flip) {
        // Mirror horizontally about the character's (extrapolated) screen_x.
        const axis = exx * sx;
        ctx.translate(axis, 0); ctx.scale(-1, 1); ctx.translate(-axis, 0);
      }
      ctx.drawImage(c.img, sp.x, sp.y, sp.w, sp.h, dx, dy, dw, dh);
      ctx.restore();
      drawn++;
    }
    this._lastNote = loading ? `loading ${loading} char atlas…`
                   : missing ? `holding (uncaptured) ${missing}: ${missKeys.join(' ')}`
                   : 'all visible poses captured';
    return { drawn, missing, note:this._lastNote };
  }

  // Canvas2D assembly render (A/B fallback when WebGPU is off). Consumes the same
  // draw list as the GPU path; maps the optional fx blend byte to a canvas
  // compositing op (additive for glows). No palette recolor here (GPU path only).
  renderAssembly(ctx) {
    const W = ctx.canvas.width, H = ctx.canvas.height;
    ctx.clearRect(0, 0, W, H);
    const list = this.buildAssemblyDrawList(W, H);
    for (const it of list) {
      const c = this.asmChars[it.charId];
      if (!c || !c.img) continue;
      ctx.save();
      // Additive when the fx blend byte requests dst=ONE (1) — glows/energy.
      if (it.blend != null && (it.blend & 0xf) === 1) ctx.globalCompositeOperation = 'lighter';
      if (it.flip) { ctx.translate(it.dx + it.dw, it.dy); ctx.scale(-1, 1); }
      else         { ctx.translate(it.dx, it.dy); }
      ctx.drawImage(c.img, it.sx, it.sy, it.sw, it.sh, 0, 0, it.dw, it.dh);
      ctx.restore();
    }
    return { drawn: this._asmDrawn, missing: this._asmMiss, note: this._asmNote };
  }

  // Apply the STEP-1 body fx (hit-flash + super/aura overlay) to a body draw item.
  // APPROXIMATE: the baked sprites are RGB, so we add an additive `tint` (rgb 0..1
  // the GPU adds to the body's color, see sprite-gpu.mjs `tint`) — NOT the exact
  // hurt/overlay palette-bank swap the engine does (loc_8c035162). Subtle by design.
  //   - hit-flash: char+0x12d/0x12e (sl.pal12d/pal12e). +0x12e is the live
  //     palette-effect word; +0x12d the per-part select. We can't pick the exact
  //     hurt bank from a baked RGB crop, so we flash a white-ish boost on any hit
  //     edge. We ALSO honor the existing health-drop flash window (sl._flashUntil).
  //   - overlay: char+0x1a4 (sl.overlay1a4) = RenderExtra class; nonzero -> an
  //     additive aura tint (cool/blue for a generic super glow). Coarse: the class
  //     -> exact overlay-palette table (bank03) isn't reproduced from baked sprites.
  _applyBodyFx(item, sl) {
    let tr = 0, tg = 0, tb = 0;
    if (this.hitFlashOn) {
      const now = this._now0 || ((typeof performance !== 'undefined') ? performance.now() : 0);
      // ONLY the validated health-drop edge. pal12d/pal12e are nonzero during NORMAL
      // play (they're palette-effect selectors, not hit booleans — RE notes confirm
      // +0x12e probes flat on hits), so keying off them washed every body white every
      // frame. The real generic hit trigger is the hp-drop window (sl._flashUntil).
      const flashing = (sl._flashUntil && now < sl._flashUntil);
      if (flashing) { tr += 0.35; tg += 0.30; tb += 0.30; }   // near-white additive flash
    }
    if (this.overlayOn && sl.overlay1a4 && sl.overlay1a4 !== 0) {
      tr += 0.05; tg += 0.10; tb += 0.22;                     // cool/blue super-aura tint
    }
    if (tr || tg || tb) item.tint = [tr, tg, tb];
  }

  // GPU path: emit [{charId, sx,sy,sw,sh (atlas px), dx,dy,dw,dh (canvas px), flip}]
  // for the active characters — same extrapolation + held-pose logic as render().
  buildDrawList(canvasW, canvasH) {
    const scaleX = canvasW / (this.screenW || 640), scaleY = canvasH / (this.screenH || 480);
    const now = (typeof performance !== 'undefined') ? performance.now() : 0;
    this._now0 = now;   // for _applyBodyFx's flash-window check
    if (!this._held) this._held = new Array(6).fill(null);
    const out = []; let loading = 0, missing = 0, missKeys = [];
    for (let s = 0; s < 6; s++) {
      const sl = this.slot[s];
      if (!sl.active) { this._held[s] = null; continue; }
      const c = this.chars[sl.char_id];
      if (!c) { loading++; continue; }
      if (!c.img) continue;
      let sp = c.sprites[sl.sprite_id];
      if (sp) this._held[s] = { char_id: sl.char_id, sp };
      else { missing++; if (missKeys.length<3) missKeys.push(`${sl.char_id}/0x${(sl.sprite_id&0xffff).toString(16)}`);
             const h = this._held[s]; if (h && h.char_id === sl.char_id) sp = h.sp; else continue; }
      let exx = sl.screen_x, eyy = sl.screen_y;
      if (this.predict !== false) { const dt = Math.min(now - sl.t, 33); if (dt > 0) { exx += sl.vx*dt; eyy += sl.vy*dt; } }
      // Anisotropic CPS scale (CpsXScale=5/3, CpsYScale=15/7 — work.asm:44-45):
      // rip sprites are CPS-native px, MVC2 stretches Y MORE than X. Apply SX to
      // every X (anchor offset + width), SY to every Y (offset + height). This is
      // the fixed game scale — NOT the derived "sliding" camera zoom (_zoom, info-only).
      // STEP-1 WIRE (exact): compose the fixed CPS scale with the per-char dynamic
      // zoom char+0x50/0x54 (sl.scaleX/scaleY). sane() guards garbage/zero so a char
      // WITHOUT the field (scaleX≈1) is byte-identical to the pre-field behavior.
      const SX = (this.asmScaleX || 1) * _sane(sl.scaleX), SY = (this.asmScaleY || 1) * _sane(sl.scaleY);
      const cfl = (sl.facing !== sp.facing);
      const cdx = cfl ? -(sp.dx + sp.wG) : sp.dx;   // mirror the (asymmetric) anchor when flipped
      // STEP-1 WIRE (approx, flagged): hit-flash (char+0x12d/0x12e) -> body TINT, and
      // super/aura overlay (char+0x1a4) -> additive aura. Baked sprites are RGB so
      // these are tint approximations, NOT the exact hurt/overlay palette-bank swap.
      const item = { charId: sl.char_id, slot: s, z: 8, sx: sp.x, sy: sp.y, sw: sp.w, sh: sp.h,
        dx: (exx+cdx*SX)*scaleX, dy: (eyy+sp.dy*SY)*scaleY, dw: sp.wG*SX*scaleX, dh: sp.hG*SY*scaleY,
        flip: cfl };
      this._applyBodyFx(item, sl);
      out.push(item);
    }
    // FLICKER-TRANSPARENCY BRIDGE: MVC2 draws some semi-transparent effects/
    // projectiles on ALTERNATING frames to fake alpha. Rendered literally they
    // blink. Bridge it: also draw last frame's objects that have NO match this
    // frame (same cid+sid within ~40px) — so an every-other-frame object renders
    // continuously. Objects still present this frame are skipped here (no trail
    // on things that move every frame). Truly-gone objects drop after one frame.
    let drawObjs = this.objects || [];
    // Flicker-bridge OFF by default: it re-draws last frame's missing objects to mask
    // blink, but lingers REMOVED objects one extra frame (the "stuck sprites"). Toggle
    // window._spriteclient._objBridge=true if real blink returns.
    if (this.objectsOn !== false && this._objBridge && this._objsPrev && this._objsPrev.length) {
      const held = [];
      for (const p of this._objsPrev) {
        let matched = false;
        for (const o of drawObjs) {
          if (o.cid === p.cid && o.sid === p.sid && Math.abs(o.x - p.x) < 40 && Math.abs(o.y - p.y) < 40) { matched = true; break; }
        }
        if (!matched) held.push(p);
      }
      if (held.length) drawObjs = drawObjs.concat(held);
    }
    // Satellite + global objects from the slot table (cape, projectiles, hail,
    // lightning, supers). The slot table gives each its OWN authoritative screen
    // pos and render layer, so we draw exactly there — no owner-relative guess.
    if (this.objectsOn !== false) for (const o of drawObjs) {
      // Skip sentinel/placeholder object ids (0x7fff & 0xffff are empty-slot
      // markers, 0 is an inactive node) BEFORE the atlas lookup — otherwise they
      // flood the effects-miss tally with bogus PLxx/0x7fff entries.
      if (o.sid === 0x7fff || o.sid === 0xffff || o.sid === 0) continue;
      // EFFECT ROUTING (OBJS flags bit0 = is_effect, node+0x15c in Effect Poly
      // 0x0CED0000): resolve the sprite from the shared EFFECTS atlas (this.chars
      // [FX_CID], populated by loadFxAtlas when it carries a `sprites` map), NOT the
      // owner's PL{cid}. Non-effect objects (cape/projectile body) stay on the char
      // atlas. The fx atlas is registered as a pseudo-char so the GPU binds its own
      // texture/group; if it isn't loaded yet the effect object just waits (no draw).
      const atlasCid = o.isEffect ? FX_CID : o.cid;
      const c = this.chars[atlasCid];
      if (!c) { if (!o.isEffect) this.loadChar(o.cid); continue; }   // fx atlas loads via loadFxAtlas()
      if (!c.img) continue;
      const sp = c.sprites[o.sid];
      if (!sp) {
        // DIAGNOSTIC: this object's sprite_id isn't in the resolved atlas. For a
        // non-effect object it's a SHARED effect sprite (hitspark/etc.) not yet
        // routed/baked; tally it — the set is the exact effects-atlas extraction
        // list. (Effect-routed misses are also tallied, prefixed FX.)
        const tag = o.isEffect ? 'FX' : `PL${o.cid.toString(16).padStart(2,'0').toUpperCase()}`;
        const k = `${tag}/0x${(o.sid&0xffff).toString(16)}`;
        this._objMiss = this._objMiss || new Map();
        this._objMiss.set(k, (this._objMiss.get(k) || 0) + 1);
        continue;
      }
      // AUTHORITATIVE position: the object's own slot-table screen pos (node+0xE0/E4
      // -> o.x/o.y). The old far>130 heuristic flip-flopped between this and the
      // owner's pos as the object crossed the threshold — that was the 'jumpy/skip'
      // look. Drawing at the true pos is both correct and stable.
      const px = o.x, py = o.y;
      if (px < -64 || px > 704 || py < -64 || py > 544) continue;
      // Owner slot: the active char that owns this object (drives palette group + the
      // per-char dynamic zoom that satellites inherit).
      let oslot = 0, osl = null;
      for (let s = 0; s < 6; s++) if (this.slot[s].active && this.slot[s].char_id === o.cid) { oslot = s; osl = this.slot[s]; break; }
      // STEP-1 WIRE (exact): anisotropic CPS scale composed with the OWNER's dynamic
      // zoom char+0x50/0x54 — so a growing/shrinking super's projectiles/effects
      // scale WITH the caster. Owner without the field (scaleX≈1) = unchanged.
      const SX = (this.asmScaleX || 1) * _sane(osl ? osl.scaleX : 1);
      const SY = (this.asmScaleY || 1) * _sane(osl ? osl.scaleY : 1);
      // Orientation: use the object's OWN flip (node+0x130, shipped in the 0x8000
      // bit) — NOT the owner's facing. The old cid-matched-owner-facing guess locked
      // P2's cape onto P1's facing (mirror/slot-order), so the P2 cape faced the
      // wrong way and looked "stuck". XOR the sprite's baked facing.
      const fl = (!!o.xflip) !== (!!sp.facing);
      // PATH A — TRUE ANCHOR. When the server shipped the object's own assembly
      // hotspot (node+0x178 min dx,dy), use it INSTEAD of the baked body-relative
      // sp.dx/sp.dy: satellites (projectiles/capes/effects) have their OWN origin,
      // so the body-relative bake drifts. _objCfg stays a residual user nudge.
      // hasHot=false (server found no extras, or an old server) => baked anchor.
      // OBJECT ANCHOR — DATA-DRIVEN OWN-ORIGIN (default 'own'). NO per-char guessing,
      // NO proximity heuristic. The proven model (marvelous2 loc_8c030af8 + Frame
      // Oracle 2026-06-08): a satellite places its parts at its OWN node origin, not the
      // owner's body foot:  satellite_screen_quad = node(+0xE0/E4) + intrinsic_part_off.
      //   * node(+0xE0/E4) = the satellite's OWN authoritative screen pos. The Oracle
      //     confirmed loc_8c030af8 (the EFFECT/SATELLITE render path the slot-table walk
      //     dispatches for category!=0) writes screen_x/y to +0xE0/+0xE4 exactly like the
      //     body's loc_8c03093c. readAllDrawn ships it as o.x/o.y (prod runs
      //     MAPLECAST_OBJS_SLOTTABLE so the OBJS wire reads +0xE0). So `px,py` above IS
      //     each satellite's own origin — no owner-relative reconstruction needed.
      //   * intrinsic_part_off = the rip atlas's baked sp.dx/sp.dy. For the offline ROM
      //     rip (atlas/chars/PLxx.json) these are OWN-ORIGIN-relative: dx = -wG/2 (the
      //     sprite's own horizontal center — verified PL2C dev 0.0px, PL2A 0.5px), dy =
      //     the sprite's own top. IDENTICAL in nature for body, cape AND projectile, so
      //     one rule places all of them — Storm's cape on her body AND Magneto's cape/
      //     projectile, from the SAME data, with no cid branch.
      // Why NOT the old defaults:
      //   - PATH A (node+0x178 EXTRAS hotspot / offline EXTRAS table): DEGENERATE — the
      //     satellite sid isn't in the body's ANIMATION keyframe table (capes are spawned
      //     objects), and where sids resolve the min(dx,dy) is a CONSTANT body-extent per
      //     char. Rejected (?v=54, server hotDx/hotDy ignored).
      //   - 'auto' proximity: a heuristic (attached→baked, free→center) — exactly what
      //     this task removes. The own-origin rule supersedes it: a cape near the body
      //     and a projectile across the screen BOTH have a correct o.x/o.y, so both use
      //     the same baked own-origin offset. No threshold to flip-flop on.
      // window._objAnchor still forces a manual override for A/B:
      //   'own' (default = baked at own origin) | 'center' | 'bottom' | 'baked' (alias of
      //   'own') | 'hot' (PATH A, only if the server shipped a non-degenerate hotspot).
      const _am = (typeof window !== 'undefined' && window._objAnchor) || 'own';
      let anchorX, anchorY;
      if (_am === 'hot' && o.hasHot) { anchorX = o.hotDx; anchorY = o.hotDy; }
      else if (_am === 'center') { anchorX = -sp.wG / 2; anchorY = -sp.hG / 2; }
      else if (_am === 'bottom') { anchorX = -sp.wG / 2; anchorY = -sp.hG; }
      else { anchorX = sp.dx; anchorY = sp.dy; }   // 'own'/'baked' (default): intrinsic own-origin offset
      // DIAG (gated): window._objDiag=true logs each distinct object's anchor data once.
      if (typeof window !== 'undefined' && window._objDiag) { const _k = `${o.cid}:${(o.sid&0xffff).toString(16)}`; (this._od = this._od || new Set());
        if (!this._od.has(_k)) { this._od.add(_k);
          console.log(`[OBJDIAG] PL${o.cid.toString(16).padStart(2,'0').toUpperCase()} sid=0x${(o.sid&0xffff).toString(16)} hasHot=${!!o.hasHot} hot=(${o.hotDx},${o.hotDy}) baked=(${sp.dx|0},${sp.dy|0}) scr=(${o.x|0},${o.y|0}) wh=(${sp.w}x${sp.h}) z=${o.type}`); } }
      const dxv = fl ? -(anchorX + sp.wG) : anchorX;   // mirror the anchor when flipped
      // z = the REAL render layer (o.type now carries the slot-table layer 0..15).
      // Bodies sit at the mid baseline (z=8), so low-layer satellites (capes) fall
      // behind their owner and high-layer ones (effects/supers) draw in front.
      const z = o.type;
      // SATELLITE FINE-CALIBRATION (window._objCfg = {dx, dy, scale}). The body and
      // the object use the IDENTICAL formula (base + anchor*SX) and the SAME screen
      // field (+0xE0/E4 — prod runs MAPLECAST_OBJS_SLOTTABLE so readAllDrawn reads
      // +0xE0 like the body). The residual object drift is a convention difference
      // between the body's foot-origin anchor (baked: dx = cropLeft - body.screen_x)
      // and an object node's own +0xE0 transform origin for the SAME sprite_id.
      // It's a small systematic offset/scale, so expose it as a user-dialed tunable
      // (mirrors how the body CPS scale was calibrated) instead of guessing a swap.
      // Defaults {dx:0,dy:0,scale:1} => byte-identical to the pre-tunable draw.
      const oc = (typeof window !== 'undefined' && window._objCfg) || null;
      const ocSc = oc ? (oc.scale || 1) : 1;
      const ocDx = oc ? (oc.dx || 0) : 0;
      const ocDy = oc ? (oc.dy || 0) : 0;
      const oSX = SX * ocSc, oSY = SY * ocSc;
      const item = { charId: atlasCid, slot: oslot, z, sx: sp.x, sy: sp.y, sw: sp.w, sh: sp.h,
        dx: (px + dxv*oSX + ocDx)*scaleX, dy: (py + anchorY*oSY + ocDy)*scaleY,
        dw: sp.wG*oSX*scaleX, dh: sp.hG*oSY*scaleY,
        flip: fl };
      // Effect objects draw additive (glow), matching the sparks/EFCT passes — and
      // any per-object blend nibble the server shipped still wins.
      if (o.isEffect) item.blend = (o.blend != null) ? o.blend : 0x01;
      else if (o.blend != null) item.blend = o.blend;
      out.push(item);
    }
    // The renderer groups CONSECUTIVE same-cid sprites and drops chars past maxGroups(8).
    // Sort by cid so each character's body+objects form ONE group, objects (z=-1) behind
    // bodies (z=0). (unshift broke this by scattering mixed-cid objects to the front.)
    out.sort((a, b) => (a.charId - b.charId) || ((a.z || 0) - (b.z || 0)));
    // Periodically dump the shared-effect miss tally to the console — this is the
    // exact list of effect sprite_ids to put in the effects atlas. (window._objMiss
    // also holds it live for inspection.)
    if ((this._dlc = (this._dlc || 0) + 1) % 180 === 0 && this._objMiss && this._objMiss.size) {
      // Keep accumulating the tally every frame, but rate-limit the console output
      // to once per ~5s so the rAF stack trace doesn't flood the console.
      const now = (typeof performance !== 'undefined' ? performance.now() : Date.now());
      if (!this._lastEffMissLog || (now - this._lastEffMissLog) >= 5000) {
        this._lastEffMissLog = now;
        const top = [...this._objMiss.entries()].sort((a,b)=>b[1]-a[1]).slice(0,40);
        console.warn('[effects-miss] sprite_ids not in any per-char atlas (cid/sid x frames):',
          top.map(([k,v])=>`${k}×${v}`).join('  '));
      }
      if (typeof window !== 'undefined') window._objMiss = this._objMiss;
    }
    const missEff = this._objMiss ? this._objMiss.size : 0;
    this._lastNote = loading ? `loading ${loading} char atlas…`
      : (missing ? `holding ${missing}: ${missKeys.join(' ')}`
      : (missEff ? `all poses ok · ${missEff} effect sids missing (see console)` : 'all visible poses captured'));
    return out;
  }

  // ===== ASSEMBLY DRAW LIST (the parallel path) =====
  // Same owners as buildDrawList (6 bodies + N pool objects), but each owner's
  // sprite_id resolves to an ASSEMBLY (a list of part placements) and we emit one
  // quad per part. Output items match buildDrawList's shape so sprite-gpu.mjs
  // consumes them unchanged — plus an optional `blend` for fx objects:
  //   { charId, slot, z, sx,sy,sw,sh (atlas px), dx,dy,dw,dh (canvas px), flip, blend? }
  // Dispatch: the faithful game-logic emitter port (loc_8c033e90) is default ON;
  // window._emitterPort === false falls back to the original hand-rolled builder for
  // A/B comparison. Both return the identical quad-list shape sprite-gpu.mjs expects.
  buildAssemblyDrawList(canvasW, canvasH) {
    const usePort = (typeof window === 'undefined') ? true : (window._emitterPort !== false);
    return usePort ? this.buildEmitterDrawList(canvasW, canvasH)
                   : this._buildAssemblyDrawListLegacy(canvasW, canvasH);
  }

  _buildAssemblyDrawListLegacy(canvasW, canvasH) {
    const scaleX = canvasW / (this.screenW || 640), scaleY = canvasH / (this.screenH || 480);
    const now = (typeof performance !== 'undefined') ? performance.now() : 0;
    const SX = this.asmScaleX || 1, SY = this.asmScaleY || 1;
    const S  = this.spriteScale || 1;
    const out = [];
    let loading = 0, missing = 0, drawn = 0, missKeys = [];

    // Emit every part of `sprite_id`'s assembly for one owner (body or pool obj).
    // owner: { cid, exx, eyy, facing, slot, zBase, blend? }
    const emitAssembly = (owner, sid) => {
      const c = this.asmChars[owner.cid];
      if (!c) { this.loadAsmChar(owner.cid); loading++; return; }
      if (!c.img) return;                          // load failed
      const recs = c.asm[sid] || c.asm[sid & 0xffff] || c.asm[String(sid)];
      if (!recs || !recs.length) {
        missing++; if (missKeys.length < 3) missKeys.push(`${owner.cid}/0x${(sid&0xffff).toString(16)}`);
        return;
      }
      for (const r of recs) {
        const part = c.parts[r.part] || c.parts[String(r.part)];
        if (!part) continue;
        // X-mirror (flags & 0x4000) XORs facing; Y-mirror (flags & 0x8000) does not.
        const flip  = (!!owner.facing) !== (!!r.flip);
        const flipY = !!r.flipy;
        // Reflect the part extent across the anchor: X -> -(dx+w), Y -> -(dy+h).
        const pdx = flip  ? -(r.dx + part.w) : r.dx;
        const pdy = flipY ? -(r.dy + part.h) : r.dy;
        const dx = (owner.exx + pdx * SX * S) * scaleX;
        const dy = (owner.eyy + pdy * SY * S) * scaleY;
        const dw = part.w * SX * S * scaleX;
        const dh = part.h * SY * S * scaleY;
        // z: owner base layer + the record's own intra-assembly z (back-to-front).
        const z = (owner.zBase || 0) * 100 + (r.z || 0);
        const item = { charId: owner.cid, slot: owner.slot, z,
          sx: part.x, sy: part.y, sw: part.w, sh: part.h,
          dx, dy, dw, dh, flip, flipY };
        if (owner.blend != null) item.blend = owner.blend;
        out.push(item);
        drawn++;
      }
    };

    // --- bodies (the 6 tracked slots) ---
    for (let s = 0; s < 6; s++) {
      const sl = this.slot[s];
      if (!sl.active) continue;
      let exx = sl.screen_x, eyy = sl.screen_y;
      if (this.predict !== false) { const dt = Math.min(now - sl.t, 33); if (dt > 0) { exx += sl.vx*dt; eyy += sl.vy*dt; } }
      // ANCHOR-FLOOR 2026-06-11: the engine places per-part PVR quads against the INTEGER-
      // truncated screen anchor (node+0xE0/E4), not the float. Flooring drives the per-part
      // residual 0.70px -> 0.00 vs flycast truth (tools/emitter_truth_gate.py: 0.001px/100%).
      exx = Math.floor(exx); eyy = Math.floor(eyy);
      emitAssembly({ cid: sl.char_id, exx, eyy, facing: sl.facing, slot: s, zBase: 0 }, sl.sprite_id);
    }

    // --- pool objects (cape / projectile / fx) — each its own assembly + blend ---
    if (this.objectsOn !== false) for (const o of (this.objects || [])) {
      // Find owner slot for the shared transform (same logic as buildDrawList).
      let osl = null;
      for (let s = 0; s < 6; s++) if (this.slot[s].active && this.slot[s].char_id === o.cid) { osl = this.slot[s]; break; }
      if (!osl) continue;
      let ox = osl.screen_x, oy = osl.screen_y;
      if (this.predict !== false) { const dt = Math.min(now - osl.t, 33); if (dt > 0) { ox += osl.vx*dt; oy += osl.vy*dt; } }
      if ((ox === 0 && oy === 0) || ox < -60 || ox > 700) continue;
      // type 3 = cape: rides the owner. Others: distance decides attached vs spawned.
      const far = (o.type !== 3) && ((Math.abs(o.x - ox) + Math.abs(o.y - oy)) > 130);
      const px = Math.floor(far ? o.x : ox), py = Math.floor(far ? o.y : oy);  // anchor-floor: match engine integer anchor
      // z layer by category: cape (3) behind body, fx/lightning (1) in front, else just behind.
      const zBase = (o.type === 1) ? 1 : (o.type === 3 ? -2 : -1);
      emitAssembly({ cid: o.cid, exx: px, eyy: py, facing: osl.facing, slot: 0,
                     zBase, blend: o.blend }, o.sid);
    }

    out.sort((a, b) => (a.charId - b.charId) || ((a.z || 0) - (b.z || 0)));
    this._asmDrawn = drawn; this._asmMiss = missing;
    this._asmNote = loading ? `assembly: loading ${loading} char atlas…`
                  : missing ? `assembly: missing ${missing} asm: ${missKeys.join(' ')} (${drawn} parts)`
                  : `assembly: ${drawn} parts drawn`;
    this._lastNote = this._asmNote;
    return out;
  }

  // ===== ON-THE-FLY ALL-POSES EMITTER (live-VRAM part pixels, NO bake) =========
  // The synthesis of the two operator insights:
  //   (1) correct per-part transforms (the 0x4000/0x8000 mirror fix above), and
  //   (2) NO pre-baked PLxx_parts.png — decode each part's tile LIVE from the VRAM
  //       the mirror already ships (window._D.vram), the SAME PAL4 decode the TA path
  //       and CHARQ use (texMgr.getTexture(tsp,tcw,vram)).
  //
  // It produces the EXACT same _charqParsed contract onCHARQ builds, so it renders
  // through web/webgpu/pvr2-renderer.mjs (TA-truth rasterizer) with ZERO raster
  // guessing — and animates the LIVE sprite_id every frame (any pose), because the
  // geometry comes from the static GFX2 cell table (cached per char) indexed by the
  // live sprite_id, not from one baked pose.
  //
  // Geometry per part (CONFIRMED): cumulative pen (dx,dy already accumulated in the
  // asm JSON) + owner screen_x/y, X-mirror = facing XOR (flags&0x4000), Y-mirror =
  // (flags&0x8000). The quad is a screen-space axis-aligned rect (4 corners) with UVs
  // 0..1 over the tile (flipped per mirror bit).
  //
  // ── THE ONE OPEN PIECE: sel → TCW (the VRAM tile address) ───────────────────────
  // The static cell record gives a GFX1 SELECTOR, not a TCW. To decode live we need
  // the VRAM address (+ PAL4 fmt + palette bank) the engine loaded that selector to.
  // The CHARQ breakthrough (project_charq_breakthrough) READ this live: each body part
  // is PAL4 fmt5, contiguous 32x32 tiles, stride 0x200, palette bank in TCW bits 25-21
  // = the player slot. But the static sel→VRAM_base is NOT yet known offline; it must
  // come from an Oracle probe at 0x8C0345C4 dumping rmem:r11:8 + the resulting TCW to
  // tie sel→TCW (per the SH4 expert), OR be derived from the contiguous GFX1 load
  // layout. Until that mapping is captured, this path CANNOT resolve real pixels and is
  // gated OFF (window._emitterLive, default false). The proven, shipping path stays
  // buildEmitterDrawList (atlas) / CHARQ (server Oracle quads). Set this._selToTcw =
  // (cid, sel, slot, part) => ({tcw,tsp,pcw}) once the mapping lands to light it up.
  // A HEURISTIC sel->TCW resolver (NOT confirmed — see _selToTcw doc). Encodes the
  // CHARQ-read tile shape: PAL4 (fmt5), contiguous 32x32 tiles, VRAM stride 0x200,
  // palette bank = player slot (TCW bits 25-21). vramBase is the per-char GFX base
  // (UNKNOWN offline — must come from the Oracle). tsp packs texU/texV = 32px tiles
  // (8<<2). Returns {tcw,tsp,pcw}. Use only to experiment until the probe lands.
  static heuristicSelToTcw(vramBase, tileStride = 0x200, fmt = 5) {
    const TEX_32 = 2;                               // 8<<2 = 32px
    const tsp = (TEX_32 << 3) | TEX_32;             // texU/texV nibbles (other bits 0 = nearest, repeat)
    return (cid, sel, slot, part) => {
      const addr = (vramBase + sel * tileStride) >>> 0;
      const tcwAddr = (addr >>> 3) & 0x1FFFFF;       // (tcw & 0x1FFFFF) << 3 == addr
      const palBank = (slot & 0x3F);                 // PAL4 palette selector = player slot
      const tcw = ((fmt & 7) << 27) | (palBank << 21) | tcwAddr;
      return { tcw: tcw >>> 0, tsp: tsp >>> 0, pcw: 0 };
    };
  }

  buildEmitterLiveCharq() {
    if (typeof window === 'undefined' || !window._emitterLive) return null;
    const now = (typeof performance !== 'undefined') ? performance.now() : 0;
    const resolver = this._selToTcw;                       // the OPEN sel->TCW mapping
    if (!resolver) { this._asmNote = 'emitter-live: no sel->TCW resolver (set this._selToTcw)'; this._lastNote = this._asmNote; return null; }

    // Collect every active body's parts into CHARQ objects (one quad per part).
    const objs = [];
    let totalQuads = 0;
    const addOwner = (cid, sx, sy, facing, slot, sid) => {
      const c = this.asmChars[cid];
      if (!c) { this.loadAsmChar(cid); return; }
      const recs = c.asm[sid] || c.asm[sid & 0xffff] || c.asm[String(sid)];
      if (!recs || !recs.length) return;
      const quads = [];
      for (const r of recs) {
        const part = c.parts[r.part] || c.parts[String(r.part)];
        if (!part) continue;
        const res = resolver(cid, r.part, slot, part);     // {tcw,tsp,pcw}
        if (!res) continue;
        const flip  = (!!facing) !== (!!r.flip);            // X-mirror XOR facing
        const flipY = !!r.flipy;                            // Y-mirror (no facing XOR)
        const w = part.w, h = part.h;
        // Screen rect: pen (already cumulative) + owner anchor; mirror reflects extent.
        const x0 = sx + (flip  ? -(r.dx + w) : r.dx);
        const y0 = sy + (flipY ? -(r.dy + h) : r.dy);
        const x1 = x0 + w, y1 = y0 + h;
        // UVs 0..1 over the tile, flipped per mirror bit (matches the shader's ux/vy).
        const u0 = flip ? 1 : 0, u1 = flip ? 0 : 1;
        const v0 = flipY ? 1 : 0, v1 = flipY ? 0 : 1;
        // CHARQ corner order A(TL) B(TR) C(BR) D(BL); UV per corner.
        quads.push({
          corners: [x0, y0, x1, y0, x1, y1, x0, y1],
          uv:      [u0, v0, u1, v0, u1, v1],               // D's UV derived by closure
          tcw: res.tcw, tsp: res.tsp, pcw: res.pcw || 0,
        });
        totalQuads++;
      }
      if (quads.length) objs.push({ cid, flags: 0, sprite_id: sid, node: 0, quads });
    };

    for (let s = 0; s < 6; s++) {
      const sl = this.slot[s];
      if (!sl.active) continue;
      let ex = sl.screen_x, ey = sl.screen_y;
      if (this.predict !== false) { const dt = Math.min(now - sl.t, 33); if (dt > 0) { ex += sl.vx*dt; ey += sl.vy*dt; } }
      addOwner(sl.char_id, ex, ey, sl.facing, s, sl.sprite_id);
    }

    // Pack into the PVR2Renderer vertex contract (28-byte verts, A,B,D,C strip order),
    // identical to onCHARQ so renderCharq() consumes it unchanged.
    const nVerts = totalQuads * 4;
    if (!this._elVB || this._elVB.byteLength < nVerts * 28) {
      this._elVB = new ArrayBuffer(Math.max(nVerts * 28, 1 << 16));
      this._elVBf = new Float32Array(this._elVB);
      this._elVBu = new Uint8Array(this._elVB);
    }
    const f32 = this._elVBf, u8 = this._elVBu;
    const op = [], pt = [], tr = [];
    let vi = 0;
    const outObjs = [];
    for (const ob of objs) {
      const oq = [];
      for (const q of ob.quads) {
        const [Ax, Ay, Bx, By, Cx, Cy, Dx, Dy] = q.corners;
        const [AU, AV, BU, BV, CU, CV] = q.uv;
        const DU = AU + CU - BU, DV = AV + CV - BV;
        const first = vi;
        const put = (x, y, u, v) => {
          const fi = vi * 7, bi = vi * 28;
          f32[fi] = x; f32[fi+1] = y; f32[fi+2] = 0.5;
          u8[bi+12] = 255; u8[bi+13] = 255; u8[bi+14] = 255; u8[bi+15] = 255;
          u8[bi+16] = 0; u8[bi+17] = 0; u8[bi+18] = 0; u8[bi+19] = 0;
          f32[fi+5] = u; f32[fi+6] = v; vi++;
        };
        put(Ax, Ay, AU, AV); put(Bx, By, BU, BV); put(Dx, Dy, DU, DV); put(Cx, Cy, CU, CV);
        const pp = { first, count: 4, tsp: q.tsp, tcw: q.tcw, pcw: q.pcw, isp: 0, tileclip: 0 };
        const sb = (q.tsp >> 29) & 7, db = (q.tsp >> 26) & 7;
        if (db === 1 && (sb === 1 || sb === 4)) tr.push(pp); else pt.push(pp);
        oq.push(q);
      }
      outObjs.push({ cid: ob.cid, flags: 0, sprite_id: ob.sprite_id, node: 0, quads: oq });
    }
    this._charqFrame = { frameNum: this.charqFrame, objs: outObjs };
    this._charqParsed = {
      vertexData: u8.subarray(0, vi * 28), vertexCount: vi,
      opaque: op, punchThrough: pt, translucent: tr,
    };
    this._charqQuadN = totalQuads;
    this._asmNote = `emitter-live: ${totalQuads} parts (VRAM-decode, live pose)`;
    this._lastNote = this._asmNote;
    return this._charqParsed;
  }

  // ===== EMITTER PORT — faithful loc_8c033e90 (bank03.asm:9258) =====
  // Reimplements MVC2's quad emitter over the REAL per-sprite EXTRAS records.
  //
  // EXTRAS record (8 bytes, proven against PL00_DAT_EXTRAS_DATA.BIN + the disasm):
  //   [dx:s16][dy:s16][part_idx:u16][attr:u16]   terminator attr==0x00FF
  //   flip    = attr & 0x8000        (bit15)
  //   pal_row = attr & 0x00FF        (low byte, fed into the palette-row combine)
  // The atlas bakes each record as { dx, dy, part, flip, pal } (pal = attr low byte).
  //
  // Per record (loc_8c033e90):
  //   - part rect  = c.parts[part_idx]            (GFX1 offset-table lookup, offline)
  //   - quad w/h   = part.w/.h                     (= w_dim<<3 / h_dim<<3, baked)
  //   - placement  = owner screen (+0xe0/+0xe4) + (dx,dy), scaled
  //   - flip       = owner.facing XOR record flip; mirror x = -(dx+w)   (line ~812 rule)
  //   - SCALE      = global CpsX/CpsY  *  per-char sl.scaleX/scaleY (char+0x50/0x54)   [NEW]
  //   - PALETTE row= ((pal + (pal12d? pal12e<<4 : 0)) & 0x03ff) >> 4                   [NEW]
  //                  (loc_8c033e3e path A / loc_8c033e76 path B; masks 0x03ff, shad -4)
  // Output quad shape is unchanged; `palRow` is an extra field (shader wiring is a
  // follow-up — the RGB-recolor pipeline already handles the common single-row case).
  buildEmitterDrawList(canvasW, canvasH) {
    const scaleX = canvasW / (this.screenW || 640), scaleY = canvasH / (this.screenH || 480);
    const now = (typeof performance !== 'undefined') ? performance.now() : 0;
    const CPSX = this.asmScaleX || 1, CPSY = this.asmScaleY || 1;   // global CPS aspect (work.asm:44-45)
    const S    = this.spriteScale || 1;
    const out  = [];
    // LIVE TUNING (window._asmCfg, driven by the calibration panel). Defaults = no change.
    const cfg    = (typeof window !== 'undefined' && window._asmCfg) || {};
    const cpsX   = cfg.cpsX     != null ? cfg.cpsX     : CPSX;   // X scale (def ~1.667)
    const cpsY   = cfg.cpsY     != null ? cfg.cpsY     : CPSY;   // Y scale (def ~2.143)
    const offMul = cfg.offScale != null ? cfg.offScale : 1;      // multiplier on per-part dx/dy (CPS-on-offsets test)
    const sizeMul= cfg.partScale!= null ? cfg.partScale: 1;      // part w/h multiplier
    const ax     = cfg.anchorX  != null ? cfg.anchorX  : 0;      // part anchor X (0=left .5=center, in part-w units)
    const ay     = cfg.anchorY  != null ? cfg.anchorY  : 0;      // part anchor Y
    const gdx    = cfg.dx0       != null ? cfg.dx0      : 0;      // global px offset X
    const gdy    = cfg.dy0       != null ? cfg.dy0      : 0;      // global px offset Y
    // tileScale: native-px → screen factor multiplied onto CPS for the OFFLINE atlas
    // (selKeyed). DERIVED 2026-06-10 from CHARQ ground truth (KB emitter_scale_derived):
    // the offline atlas (PL00_parts.png) AND its pen are at the SAME native resolution as
    // the live PVR cells, so native→screen = FULL CPS (tileScale = 1.0). Proof: every
    // captured PVR cell renders screen_w=native·CPSX, screen_h=native·CPSY EXACTLY
    // (probe_body_uv.json: 8/16/32px cells → 13.3/26.7/53.3 × 17.1/34.3/68.6, <0.01px);
    // and the full offline sid64 assembly (native bbox 80×128) reconstructs to screen
    // 133×274 at tileScale=1.0 == the CHARQ probe's TRUE drawn body bbox 137×274 (residual
    // X 3.0%, Y 0.0%). The OLD default 0.5 halved this → the body rendered exactly 2× too
    // SMALL (the ~1.6× / ~CPS the operator saw). Exposed so the cockpit can A/B w/o redeploy.
    const tileScale = cfg.tileScale != null ? cfg.tileScale : 1.0;
    let loading = 0, missing = 0, drawn = 0, missKeys = [], skipSel = 0;

    // FACING POLARITY (2026-06-11, ROM-DERIVED — NOT eyeballed. The byte→direction
    // semantic is read from the game's facing-UPDATE setter, not toggled):
    //
    //   SETTER (where the ROM WRITES facing) — bank0d.asm loc_8c0d97ee :23266-23272:
    //     fr2 = SELF.pos_x(+0x34) ; fr3 = OPP.pos_x(+0x34) ; fcmp/gt fr2,fr3 (T = opp>self)
    //     bf.s ...; mov r5(=0),r4 ; mov 0x01,r4   →   facing = (opp.x > self.x) ? 1 : 0
    //   So facing=1 ⇔ opponent is to the RIGHT ⇔ character FACES RIGHT (P1 default);
    //      facing=0 ⇔ opponent is to the LEFT  ⇔ character FACES LEFT  (P2 default).
    //
    //   USE — render gate bank03.asm loc_8c03453a :10271-10314: `tst facing@+0x110; bf neg`:
    //     facing!=0 → loc_8c034548 `neg r10,r10` (pen seed @+0x134 NEGATED) AND `neg r8`
    //     (texture-U). facing==0 → pen seed used as-is. ONE byte gates BOTH (lockstep).
    //   CROSS-CHECK — spawn helper bank08.asm :30550-30583: facing!=0 → spawn at owner.x
    //     +offset (in front, +X=right); facing==0 → owner.x −offset. ✓ facing=1=faces-right.
    //
    //   The validated 0.00px placement (tools/validate_emitter_geom.py vs the facing=1
    //   CHARQ capture chosen_body.json/probe_body_uv.json) uses `tlx = pen − w` and was
    //   proven with bodyFace = !facing (faceInv=TRUE) → bodyFace=FALSE at facing=1 →
    //   posReflect=FALSE → `pen − w`. i.e. the engine's `neg r10` for the right-facing pen
    //   seed is ALREADY BAKED INTO the validated `pen − w` form. So the ROM-faithful sense
    //   is bodyFace = !owner.facing, driving BOTH posReflect (neg r10) and the texture-U
    //   mirror (neg r8) from the SAME bit. PRIOR BUG: the shipped client used the RAW byte
    //   (faceInv default FALSE) → at facing=1 it took the MIRROR branch, the exact OPPOSITE
    //   of the 0.00px-validated config (validator default faceInv=TRUE). That is the single
    //   inverted transform the operator kept fighting; it is corrected here by defaulting
    //   faceInv=TRUE so the default == the validator's proven config.
    //   window._emitFaceInv=false restores the raw-byte sense for A/B. r.flip (per-part
    //   0x4000) XORs on top of bodyFace (texture-U only).
    const faceInv = (typeof window === 'undefined') ? true
                  : (window._emitFaceInv !== undefined ? !!window._emitFaceInv : true);

    // Y-AXIS POLARITY (2026-06-10): the selKeyed part atlas (PL00_parts.png, the
    // Oracle live-VRAM / GFX1-detwiddle build) stores each part's PIXELS BOTTOM-UP
    // (row 0 = bottom of the part), so a part sampled with the normal top→top V reads
    // UPSIDE-DOWN. The cumulative-pen PLACEMENT is already correct (KB finding
    // cumulative_pen_geometry: baked dy is negative = builds UP from the foot-anchor,
    // bank03 loc_8c0344d4 Y-acc -= dy; verified: sid126 spans screen-Y 328..439 with
    // the foot at 433 = feet at bottom). So the body was placed right but every tile
    // rendered head-down — the WHOLE figure read inverted. Fix = invert the per-part
    // texture V ONLY (the shader's flipY attr does vy=1-c.y, sampling-only, the quad
    // does NOT move), so the upright placement keeps standing on the foot-anchor while
    // each tile flips upright. Offline-validated against PL00_parts.png: V-flip renders
    // red-headband-top / feet-bottom Ryu; un-flipped renders him head-down. This is
    // ORTHOGONAL to faceInv (X) and to tileScale/CPS (scale) — Y direction only.
    // Default ON (the corrected, upright value); window._emitFlipY=false = raw A/B.
    const emitFlipY = (typeof window === 'undefined') ? true
                    : (window._emitFlipY !== undefined ? !!window._emitFlipY : true);

    // LIVE INSTRUMENTATION (2026-06-10) — break the offline-guess loop. All default OFF,
    // so default = byte-identical to ?v=71. These are A/B knobs for the operator to tune
    // against the green TA-truth in the DIFF, in real time, no redeploy.
    //   _emitFaceFlip : WHOLESALE invert the single facing sense F — flips BOTH the position
    //                   reflection (neg r10) AND the texture-U mirror (neg r8) together, so
    //                   they can never decouple. Default false = operator-confirmed-correct
    //                   polarity (F = owner.facing). (Was position-only; that decoupling was
    //                   the left↔right part-jumping bug, fixed 2026-06-11.)
    //   _emitFaceLog  : ~1/sec per-char console readout (facingRaw, anchorX, reflected,
    //                   leadPartScreenX = the jab/lead limb's final screen X).
    //   _emitAnchorDbg: draw a 1px vertical magenta line at the owner anchorX (foot pen
    //                   origin) so the operator can see anchor-offset vs reflection.
    const faceFlip = (typeof window !== 'undefined' && !!window._emitFaceFlip);
    const faceLog  = (typeof window !== 'undefined' && !!window._emitFaceLog);
    const anchorDbg= (typeof window !== 'undefined' && !!window._emitAnchorDbg);
    // throttle the readout to ~once/sec per char (keyed by cid in _emitFaceLogT).
    this._emitFaceLogT = this._emitFaceLogT || {};

    // Per-char dynamic zoom (char+0x50/0x54), clamped to a sane band; raw field
    // semantics are step-1 wire (f32). Out-of-band => fall back to 1.0 (no zoom),
    // so a mis-scaled/garbage field can never blow a character up off-screen.
    const sane = (v) => (v > 0.05 && v < 16) ? v : 1.0;

    // Palette-row combine, ported from bank03.asm:9232-9256:
    //   path A (pal12d==0):  row = (recPal & 0x03ff) >> 4
    //   path B (pal12d!=0):  row = ((pal12e<<4) + recPal) & 0x03ff) >> 4
    const palRowOf = (recPal, pal12d, pal12e) => {
      const base = (pal12d ? ((pal12e & 0xffff) << 4) : 0) + (recPal & 0xffff);
      return (base & 0x03ff) >> 4;
    };

    // EMITTER DEBUG (window._emitDbg=1): per ~60 frames, trace the Ryu (cid 0) body —
    // its LIVE sprite_id, whether it equals the only baked pose (126 = standing), and how
    // many parts emitted. Answers "is Ryu actually hitting sprite_id 126?" at the source.
    const _eDbg = (typeof window !== 'undefined' && window._emitDbg);
    this._emitDbgN = (this._emitDbgN || 0) + 1;
    const _eTrace = _eDbg && (this._emitDbgN % 60 === 1);

    // owner: { cid, exx, eyy, facing, slot, zBase, sclX, sclY, pal12d, pal12e, blend?, fx? }
    const emitAssembly = (owner, sid) => {
      const isRyuBody = (_eTrace && !owner.fx && owner.cid === 0 && owner.slot != null && owner.zBase === 0);
      // fx objects resolve from the effects atlas, not the per-char atlas.
      const c = owner.fx ? this._fxAsmChar() : this.asmChars[owner.cid];
      if (!c) { if (!owner.fx) { this.loadAsmChar(owner.cid); loading++; } return; }
      if (!c.img) {                                        // load failed / no atlas (skip)
        if (isRyuBody) console.log(`[emit] Ryu cid0 sid=${sid&0xffff} -> NO ATLAS (c.img null) — no draw`);
        return;
      }
      const recs = c.asm[sid] || c.asm[sid & 0xffff] || c.asm[String(sid)];
      if (!recs || !recs.length) {
        if (isRyuBody) console.log(`[emit] Ryu cid0 LIVE sid=${sid&0xffff} (0x${(sid&0xffff).toString(16)}) NOT in atlas. Baked poses: [${Object.keys(c.asm).join(',')}] (126=standing is the only demo pose)`);
        missing++; if (missKeys.length < 3) missKeys.push(`${owner.cid}/0x${(sid&0xffff).toString(16)}`);
        return;
      }
      if (isRyuBody) console.log(`[emit] Ryu cid0 sid=${sid&0xffff} HIT atlas: ${recs.length} records, anchor=(${owner.exx.toFixed(0)},${owner.eyy.toFixed(0)}) facing=${owner.facing} — emitting parts`);
      // screenSpace atlas: parts already baked at screen-pixel size with game-px dx/dy,
      // so DON'T re-apply the CPS aspect (cpsX/cpsY) — only the live per-char zoom + S.
      // (Pre-CPS/logical atlases keep the cpsX/cpsY multiply.) This is what makes the
      // tight bake render edge-to-edge instead of the old 8x8-tile fragmentation.
      const ss = !!c.screenSpace;
      const sX = (ss ? 1 : cpsX) * sane(owner.sclX) * S, sY = (ss ? 1 : cpsY) * sane(owner.sclY) * S;
      // LEAN SEL-KEYED PATH (c.selKeyed): the FULL static GFX2 assembly (all 441 poses)
      // drives placement; part PIXELS come from a sel-keyed atlas (Oracle live-VRAM
      // decode, keyed by the +6 selector). A part is a multi-tile group baked to ONE
      // upright native-screen bitmap with its own anchor residual {ax,ay}:
      //   screen_top_left = owner_screen + pen·CPS + (ax, ay)         (proven offline,
      //   sub-pixel vs char_tight.png; pen = the cumulative running pen r.dx/r.dy in
      //   cell units, CPS = 5/3, 15/7).  Sels not yet in the atlas are SKIPPED (counted
      //   in skipSel) so an uncaptured pose renders its captured parts and no garbage.
      if (c.selKeyed) {
        // ONE-TIME PATH MARKER — prove the selKeyed body path (the ?v=71/72 logic) is the
        // branch actually rendering the body, not whole-sprite/CHARQ. Logs once per page load.
        if (typeof window !== 'undefined' && !window.__emitPathLogged && !owner.fx && owner.zBase === 0) {
          window.__emitPathLogged = 1;
          console.log('[emitter] selKeyed BODY path active (v72)', { cid: owner.cid, sid: sid & 0xffff,
            faceInv, faceFlip, facingRaw: owner.facing, anchorX: owner.exx });
        }
        const cpsx = sane(owner.sclX) * S, cpsy = sane(owner.sclY) * S;   // live per-char zoom
        const pcX = cpsX * cpsx, pcY = cpsY * cpsy;                       // pen scale (CPS×zoom)
        // Per-char readout state: track the lead (max-|pen-dx|) part's final screen X so the
        // operator sees WHICH side the jab lands. Reset per emitAssembly call.
        let _leadAbsDx = -1, _leadScreenX = null, _anyReflected = false;
        // FRAME DUMP (window._emitDumpReq): when set, collect this char's per-part
        // emitter quads (sel + FINAL screen rect + flip/posReflect) into a parallel
        // array, stashed to window._emitDumpResult below. Gated, read-only, no render
        // change. Lets the EMITTER DEBUG "DUMP FRAME" button export ground-truth-vs-
        // emitter geometry so facing is DERIVED from numbers, not eyeballed.
        const _dumpOn = (typeof window !== 'undefined' && window._emitDumpReq && !owner.fx && owner.zBase === 0);
        const _dumpParts = _dumpOn ? [] : null;
        for (const r of recs) {
          const part = c.parts[r.part] || c.parts[String(r.part)];
          if (!part) { skipSel++; continue; }            // sel pixels not captured yet
          // FACING — ROM-DERIVED single sense (2026-06-11). The byte→direction comes from
          // the SETTER bank0d loc_8c0d97ee :23266-23272 (facing = opp.x>self.x ? 1 : 0,
          // facing=1=faces-right) and the USE gate bank03 loc_8c03453a :10271-10314 (`tst
          // facing; bf neg` → facing!=0 negates BOTH the position pen `neg r10` @loc_8c034548
          // AND the texture-U `neg r8`). ONE byte gates BOTH, so the client derives BOTH from
          // ONE sense — they can never decouple.
          //   bodyFace = !owner.facing  (== the validator's faceInv=TRUE config that proved
          //   0.00px vs the facing=1 capture). At facing=1: bodyFace=FALSE → posReflect=FALSE
          //   → `tlx = pen − w` (the engine's neg-r10 for the right-facing pen seed is ALREADY
          //   baked into this validated form) and texture-U = r.flip only (un-mirrored). At
          //   facing=0: bodyFace=TRUE → posReflect=TRUE → mirror `2*axisX − pen` + texture-U
          //   mirror. faceFlip (_emitFaceFlip) WHOLESALE-inverts bodyFace (both transforms
          //   together). r.flip (per-part 0x4000) XORs onto the texture-U mirror only.
          const bodyFace = (faceInv ? !owner.facing : !!owner.facing) !== faceFlip;  // ROM single sense (default !facing)
          const F = bodyFace;
          const posReflect = F;                          // POSITION reflect (neg r10) — gated on F
          // TEXTURE U-mirror (neg r8) — FACING FIX 2026-06-11. The POSITION model above is a
          // CALIBRATED form: the pen baked in PL00_asm.json is facing-neutral and the validated
          // `pen − w` (facing=1) / `2A − pen` (facing=0) branch absorbs the ROM's `neg r10` into
          // the baked pen + the −w convention — so `posReflect` reads as the INVERSE of the raw
          // facing bit (faceInv default). The texture-U mirror, by contrast, is a literal pixel
          // op on the atlas, whose parts are stored in the OPPOSITE orientation to the facing=1
          // display (offline-baked Ryu faces LEFT; facing=1 must face RIGHT). So the U-mirror must
          // NOT lockstep with posReflect — it must follow the RAW ROM rule `texU = facing XOR 0x4000`.
          // With F = !facing (faceInv default), !F = facing, so `(!F) XOR r.flip` == `facing XOR 0x4000`
          // — a LITERAL port of the ROM (bank03 neg r8 @ loc_8c0344d4), restoring phase with the
          // calibrated position. The OLD `F XOR r.flip` (= !facing XOR 0x4000) was the INVERSE: it
          // left the body un-mirrored at facing=1 → Ryu faced LEFT by default AND the +dx limbs
          // (un-mirrored) reassembled on the wrong side of the −dx torso → "half the body swaps"
          // as the pose's +dx/−dx mix changed frame to frame. Decoupling fixes BOTH symptoms.
          const flip  = (!F) !== (!!r.flip);             // TEXTURE U-mirror = facing XOR 0x4000 (RAW ROM rule)
          const flipY = !!r.flipy;                       // Y-mirror geometry (no facing XOR)
          const ax0 = (part.ax || 0), ay0 = (part.ay || 0);
          // SIZE FIX (2026-06-10, CHARQ-GROUND-TRUTH calibrated): the OFFLINE atlas (the
          // GFX1-detwiddle build, PL00_asm.json _note "OFFLINE-COMPLETE") emits BOTH the
          // accumulated pen (r.dx/r.dy) AND the part pixels at the SAME 2×-cell native
          // resolution (1 pen cell-unit = 2 native px). So the whole assembly — pen offset
          // AND tile extent — shares ONE scale: native → screen = CPS/2.
          //   Proof (CHARQ chosen_body.json, scale[1,1]): a 128×128 body tile renders to
          // 106×137 screen px → (0.833, 1.071) = EXACTLY CPS/2 (1.667/2, 2.143/2), <0.3%
          // error; and the full sid64 assembly bbox at CPS/2 = 67×137 ≈ the GT ~146 tall.
          //   The OLD bug: pen used full CPS (pcX/pcY) but the tile used only the live zoom
          // (cpsx≈1) — TWO different scales. The skeleton spread 2× wider than the tiles, so
          // the body was fragmented and the solid mass looked small (the operator's ~1.75×
          // Size slider was hand-undoing the mismatch). Now pen AND tile both use tsX/tsY =
          // (CPS/2)·zoom → one consistent transform, body lands on the green TA-truth at the
          // DEFAULT Size (1.0×). NB: the per-part Y vs CHARQ uses CPSY (the cumulative pen's
          // proven aspect), so halving keeps the disasm-proven 5/3,15/7 RATIO intact.
          // NB (2026-06-11): tileScale DEFAULTS 1.0 (line ~1465) — i.e. FULL CPS, NOT the
          // CPS/2 the older block above describes. That CPS/2 era predated the full-span
          // atlas: it used the LOGICAL-crop dims and halved CPS to compensate. With the
          // 2026-06-11 full-span baker (extract_gfx1_atlas.py) part.w/h = sw*8 x sh*8 (the
          // true tile span) and tileScale=1.0 gives dW=dH=0.00px vs the live CHARQ capture
          // (tools/validate_emitter_geom.py, all 6 sels). part.w/h are read STRAIGHT from the
          // atlas — no client-side dim override — so the re-baked atlas needs no ?v= bump.
          const tsX = pcX * tileScale, tsY = pcY * tileScale;  // unified assembly scale = CPS·tileScale·zoom (tileScale=1.0 default)
          const w = part.w * tsX * sizeMul, h = part.h * tsY * sizeMul;
          // base (un-flipped) top-left in screen px — pen AND tile residual at the SAME tsX/tsY
          let tlx = owner.exx + gdx + r.dx * tsX + ax0 * tsX;
          let tly = owner.eyy + gdy + r.dy * tsY + ay0 * tsY;
          // X PLACEMENT — NUMERICALLY VALIDATED 2026-06-11 (tools/validate_emitter_geom.py
          // vs _ryu_capture/probe_body_uv.json, the live CHARQ per-part screen quads of
          // node 0x8C268340 Ryu sprite_id 68, facing=1). The disasm (loc_8c0344d4) negates
          // the pen accumulator on facing (loc_8c034548 `neg r10,r10`) and lays each tile at
          // node+0xE0 + (Xacc+tileX)·scale; with the pen negated the part's pen point becomes
          // its RIGHT edge and the tile columns run LEFTWARD. PROVEN: for facing=1 the
          // captured part RIGHT edge == exx + dx·tsX to <0.7px (= pure anchor quantization,
          // 106.7 capture vs 106.0 true; relative geometry residual = 0.00px over all 6 parts).
          // So the part extends LEFT of the pen: tlx = exx + dx·tsX − w.
          //   bodyFace=false (the validated facing-1 sense): pen point = RIGHT edge, extend left
          //     → tlx = pen − w.
          //   bodyFace=true (the OPPOSITE facing): DISASM-DERIVED & ALGEBRAICALLY PROVEN
          //     (2026-06-11, finding:emitter_flip_unvalidated → RESOLVED). loc_8c034548
          //     `neg r10,r10` negates the cumulative pen ORIGIN ONLY; the part WIDTH enters the
          //     screen-X composition via the tile span r4 (bank03 :10652 `add r4,r3`)
          //     IDENTICALLY in both branches — there is NO ±w introduced by the reflection
          //     (the texture-U mirror neg r8/neg r5 is a SEPARATE, internal-pixel flip). So the
          //     pen point mirrors across axisX and the part now extends RIGHT, its LEFT edge AT
          //     the mirrored pen:  tlx = 2·axisX − pen  (NO +w). `tlx` here IS the pen point.
          //     The exact mirror of the validated form: a part at +dx (left edge pen−w) maps to
          //     left edge 2·axisX−pen (synthetic facing=0 mirror = 0.70px dX / 0.00px dW vs the
          //     facing=1 capture mirrored across exx — tools/validate_emitter_geom.py).
          //     The OLD default `2·axisX − pen + w` injected a spurious +w = one full part-width
          //     (≈13–107 screen-px, the operator's offset). _asmCfg.reflectEdge=true keeps that
          //     old +w form ONLY as an A/B knob. axisX = the owner foot-anchor X.
          const reflEdge = (cfg.reflectEdge === true);
          const reflDx   = (cfg.reflectDx != null ? cfg.reflectDx : 0);
          const axisX = owner.exx + gdx + reflDx;
          if (!posReflect) {
            // VALIDATED facing (bodyFace=false): part extends LEFT of the pen point.
            tlx = tlx - w;
          } else {
            // OPPOSITE facing: pen point mirrors across axisX, part extends RIGHT (no ±w).
            tlx = reflEdge ? (2 * axisX - tlx + w) : (2 * axisX - tlx);
          }
          // PER-PART X-MIRROR GEOMETRY (0x4000) — BUG 2 FIX 2026-06-11. Until now the per-
          // part 0x4000 bit (r.flip) drove ONLY the texture-U mirror (the `flip` attr below);
          // it did NOT move the quad. That is WRONG: the selKeyed atlas bakes each part as ONE
          // upright bitmap, so an X-mirrored part must REFLECT its screen rect (not just its
          // pixels) — exactly as flipY (0x8000) reflects the rect below. Proof the texture-only
          // path was wrong: PL00 sid 1 lists part 4 TWICE — {dx:93,flip:0} and {dx:93,flip:1}
          // (a symmetric limb, e.g. both forearms). With the same pen and no geometry reflect,
          // both copies landed on the IDENTICAL screen rect (just opposite U) → one limb drew
          // on top of the other instead of on opposite sides. 112 PL00 parts carry flip=1; idle
          // sids 61-68 (the only ones previously validated) carry NONE, so this never showed in
          // the gate. ROM ground: bank03 loc_8c0344d4 processes 0x4000 X-mirror by the SAME
          // mechanism as 0x8000 Y-mirror; the accepted flipY precedent (next line) reflects the
          // rect across the owner anchor, so the X-mirror reflects across axisX in symmetry.
          // Reduces to the validated form when r.flip=0 (no-op) — the truth gate + idle sids
          // 62/68 stay byte-identical. window._emitPartFlipX=false restores the texture-only
          // (pre-fix) behavior for A/B against a flycast-truth capture of a flip-heavy pose.
          // ⚠ UNVALIDATED vs live truth: no flip=1 capture exists yet (the gate's sid 68 has
          // none). The texture-U sense `(!F) XOR r.flip` is the ROM-literal port; this geometry
          // mirror is its position counterpart, derived (not pixel-confirmed). See report for
          // the precise sid/pose the parent must CHARQ-capture to gate it.
          const partFlipX = (typeof window === 'undefined') ? true
                          : (window._emitPartFlipX !== undefined ? !!window._emitPartFlipX : true);
          if (partFlipX && r.flip) tlx = 2 * axisX - (tlx + w);   // mirror the rect like flipY does for Y
          if (flipY)    tly = 2 * (owner.eyy + gdy) - (tly + h);
          // READOUT: track the lead (max |pen-dx|) part — the jab/extended limb — and its
          // FINAL screen X (post-reflection), so the log shows which side the fist lands.
          // Unconditional (two comparisons/part, negligible) so the structured readout
          // global below always has jabX live for the on-screen EMITTER DEBUG table —
          // does NOT change any rendered output (read-only of tlx/w/posReflect).
          {
            const absDx = Math.abs(r.dx);
            if (absDx > _leadAbsDx) { _leadAbsDx = absDx; _leadScreenX = tlx + w / 2; }
            if (posReflect) _anyReflected = true;
          }
          const z  = (owner.zBase || 0) * 100 + (r.z || 0);
          // SHADER V-FLIP: the atlas stores parts bottom-up, so correct the texture V
          // for EVERY part (emitFlipY, default ON) XOR the per-record geometry Y-mirror
          // (flipY, the 0x8000 bit). The geometry reflection above (line ~1561) already
          // moved the quad for r.flipy; this only controls which way the texture samples.
          const flipYTex = flipY !== emitFlipY;   // V-only correction XOR per-record Y-mirror
          const item = { charId: owner.fx ? -1 : owner.cid, slot: owner.slot, z,
            sx: part.x, sy: part.y, sw: part.w, sh: part.h,
            dx: tlx * scaleX, dy: tly * scaleY, dw: w * scaleX, dh: h * scaleY,
            flip, flipY: flipYTex, palRow: 0 };
          if (owner.blend != null) item.blend = owner.blend;
          out.push(item);
          drawn++;
          // FRAME DUMP: record this part's FINAL game-space (640x480) rect — the same
          // space the TA-truth verts live in — plus sel + the two facing-derived bits.
          if (_dumpParts) _dumpParts.push({ sel: r.part, x: +tlx.toFixed(2), y: +tly.toFixed(2),
            w: +w.toFixed(2), h: +h.toFixed(2), flip, posReflect, rdx: r.dx, rdy: r.dy });
        }
        // FRAME DUMP: stash this char's collected emitter parts + its facing/anchor state.
        if (_dumpParts) {
          const dr = (window._emitDumpResult = window._emitDumpResult || { chars: [] });
          dr.chars.push({ cid: owner.cid, slot: owner.slot, sid: sid & 0xffff,
            facing: owner.facing, anchorX: +(owner.exx + gdx).toFixed(2),
            anchorY: +(owner.eyy + gdy).toFixed(2),
            faceInv, faceFlip, tileScale,
            F: (faceInv ? !owner.facing : !!owner.facing) !== faceFlip,
            leadScreenX: _leadScreenX != null ? +_leadScreenX.toFixed(2) : null,
            parts: _dumpParts });
        }
        // LIVE READOUT (window._emitFaceLog) — ~once/sec per char. Shows the LIVE facing
        // byte, the pen anchor X (owner.exx), whether the position gate fired, and the lead
        // (jab) limb's FINAL screen X. Compare leadPartScreenX vs the green TA-truth jab:
        // if the red fist is LEFT of green while green leads RIGHT, flip _emitFaceFlip.
        if (faceLog && !owner.fx && owner.zBase === 0) {
          const tkey = `${owner.cid}:${owner.slot}`;
          if ((this._emitFaceLogT[tkey] || 0) + 1000 <= now) {
            this._emitFaceLogT[tkey] = now;
            console.log('[emitFace]', { cid: owner.cid, slot: owner.slot, sid: sid & 0xffff,
              facingRaw: owner.facing, faceFlip, faceInv,
              anchorX: +(owner.exx).toFixed(1), reflected: _anyReflected,
              leadPartScreenX: _leadScreenX != null ? +_leadScreenX.toFixed(1) : null });
          }
        }
        // STRUCTURED READOUT (window._emitFaceReadout) — same values as the [emitFace]
        // console log, but written EVERY frame to a structured global so the EMITTER
        // DEBUG cockpit panel can render a live on-screen per-char table without the
        // console. No new computation: reuses owner.facing / owner.exx / the lead-part
        // tracking already done above (gated on faceLog). When faceLog is OFF we still
        // emit the cheap fields (facing/anchor/side); leadPartScreenX needs faceLog.
        if (!owner.fx && owner.zBase === 0) {
          if (typeof window !== 'undefined') {
            const ro = (window._emitFaceReadout = window._emitFaceReadout || { perChar: {} });
            const side = (_leadScreenX != null)
              ? (_leadScreenX >= (owner.exx + gdx) ? 'R' : 'L')
              : ((((faceInv ? !owner.facing : !!owner.facing) !== faceFlip)) ? 'R' : 'L');  // F-derived sense
            ro.perChar[`${owner.cid}:${owner.slot}`] = {
              cid: owner.cid, slot: owner.slot, sid: sid & 0xffff,
              facingRaw: owner.facing,
              anchorX: +(owner.exx + gdx).toFixed(1),
              jabX: _leadScreenX != null ? +_leadScreenX.toFixed(1) : null,
              reflected: _anyReflected, side, t: now };
          }
        }
        // ANCHOR LINE (window._emitAnchorDbg) — a 1px-wide magenta vertical bar at the owner
        // pen-anchor X spanning the canvas, pushed as a degenerate part-less quad the GPU
        // tints. Lets the operator SEE the anchor (vs the reflection): if red is offset from
        // green but the magenta line sits ON green's foot, the bug is the reflection, not the
        // anchor; if the line itself is off, it's the anchor (owner.exx). DEFAULT OFF.
        if (anchorDbg && !owner.fx && owner.zBase === 0) {
          const ax2 = (owner.exx + gdx) * scaleX;
          out.push({ charId: owner.cid, slot: owner.slot, z: 9999,
            sx: 0, sy: 0, sw: 1, sh: 1,
            dx: ax2 - 0.5, dy: 0, dw: 1 * scaleX, dh: canvasH,
            flip: false, flipY: false, palRow: 0, tint: [1, 0, 1], blend: 0x01 });
        }
        return;
      }
      for (const r of recs) {
        const part = c.parts[r.part] || c.parts[String(r.part)];
        if (!part) continue;
        // CONFIRMED 2026-06-10 (bank03 loc_8c0344d4): the record carries TWO mirror
        // bits — r.flip = X-mirror (flags & 0x4000), r.flipy = Y-mirror (flags &
        // 0x8000). X-mirror XORs with the owner's facing; Y-mirror does NOT.
        const flip  = (!!owner.facing) !== (!!r.flip);   // X
        const flipY = !!r.flipy;                         // Y (no facing XOR)
        // Mirror reflects the part extent across the owner anchor:
        //   X flip: dx -> -(dx + w)   Y flip: dy -> -(dy + h)
        const pdx = flip  ? -(r.dx + part.w) : r.dx;
        const pdy = flipY ? -(r.dy + part.h) : r.dy;
        const dx = (owner.exx + gdx + (pdx * offMul - part.w * ax) * sX) * scaleX;
        const dy = (owner.eyy + gdy + (pdy * offMul - part.h * ay) * sY) * scaleY;
        const dw = part.w * sX * sizeMul * scaleX;
        const dh = part.h * sY * sizeMul * scaleY;
        const z  = (owner.zBase || 0) * 100 + (r.z || 0);
        const palRow = palRowOf(r.pal || 0, owner.pal12d || 0, owner.pal12e || 0);
        const item = { charId: owner.fx ? -1 : owner.cid, slot: owner.slot, z,
          sx: part.x, sy: part.y, sw: part.w, sh: part.h,
          dx, dy, dw, dh, flip, flipY, palRow };
        if (owner.blend != null) item.blend = owner.blend;
        out.push(item);
        drawn++;
      }
    };

    // --- FORCE-STATIC DEMO (window._emitForce, default ON) ---------------------
    // The emitter only has ONE baked pose so far: Ryu (cid 0) sprite_id 126 (standing
    // idle). The live body slot rarely sits on exactly 126, so the body loop almost
    // always pose-MISSES → 0 quads → opaque black canvas (post-process.mjs:318 clears
    // to black, then blits a transparent scene). That makes the emitter look "broken"
    // even though geometry+decode are PROVEN (offline _ryu_capture/emitter_uv_zoom.png).
    //
    // This mode draws Ryu's baked assembly at a FIXED anchor EVERY frame, ignoring the
    // live sprite_id entirely — the operator sees the fragmented-but-recognizable Ryu
    // immediately (white gi, red headband, black belt), decoupled from any live pose.
    // window._emitForce=false restores the pure live path.
    // DEFAULT OFF (lean emitter): render the LIVE sprite_id every frame from the full
    // static GFX2 assembly + the sel-keyed atlas (animating pose). window._emitForce=true
    // restores the single-pose (sid 126) demo for A/B.
    const force = (typeof window === 'undefined') ? false
                : (window._emitForce !== undefined ? window._emitForce : false);
    const fc = (typeof window !== 'undefined' && window._emitForceCfg) || {};
    if (force) {
      const fcid = fc.cid != null ? fc.cid : 0;            // Ryu
      const fsid = fc.sid != null ? fc.sid : 126;          // standing idle (the one baked pose)
      // POSITION TRACKING: anchor the baked idle pose on the LIVE character so the
      // reconstructed Ryu walks/jumps with the real one. We only have ONE baked pose,
      // so the live sprite_id is IGNORED for pose selection — but the live screen_x/y
      // (+velocity extrapolation) and facing drive WHERE + which way the idle is drawn.
      //
      // Find the first active body slot whose char_id == fcid (the on-screen Ryu). If
      // none is live yet, fall back to the fixed lower-middle anchor so Ryu is ALWAYS
      // visible. The bake's part dx/dy are offsets from the captured FOOT anchor
      // (AX,AY in bake_emitter_uv.mjs); the body slot's screen_x/y is that same MVC2
      // +0xE0/+0xE4 foot point, so passing exx=live screen_x places the figure foot-on
      // the live position and the baked dx/dy register directly (no anchor subtraction).
      let live = null;
      for (let s = 0; s < 6; s++) { const sl = this.slot[s]; if (sl.active && sl.char_id === fcid) { live = sl; break; } }
      let fx, fy, ffac, fsx, fsy;
      if (live) {
        fx = live.screen_x; fy = live.screen_y;
        if (this.predict !== false) { const dt = Math.min(now - live.t, 33); if (dt > 0) { fx += live.vx*dt; fy += live.vy*dt; } }
        ffac = live.facing; fsx = sane(live.scaleX); fsy = sane(live.scaleY);
      } else {
        // fallback: no live Ryu — pin the idle at the captured foot anchor so he stays drawn.
        fx = fc.x != null ? fc.x : 106.7; fy = fc.y != null ? fc.y : 433.4;
        ffac = 0; fsx = 1; fsy = 1;
      }
      const c0 = this.asmChars[fcid];
      if (!c0) { this.loadAsmChar(fcid); }                 // kick the lazy load if not yet present
      emitAssembly({ cid: fcid, exx: fx, eyy: fy, facing: ffac, slot: 0, zBase: 0,
                     sclX: fsx, sclY: fsy, pal12d: 0, pal12e: 0 }, fsid);
      // One-line gated diagnostic (window._emitDbg=1): parts emitted + atlas state.
      if (typeof window !== 'undefined' && window._emitDbg && (this._emitDbgN % 60 === 1)) {
        const has = c0 && c0.img ? `recs=${(c0.asm[fsid]||[]).length}` : (c0 ? 'NO IMG' : 'NOT LOADED');
        console.log(`[emit-force] cid${fcid} sid${fsid} @(${fx},${fy}) drawn=${drawn} ${has}`);
      }
    }

    // --- bodies (the 6 tracked slots) ---  (skipped while force-demo is on)
    // BODY FLICKER-BRIDGE — BUG 1 FIX (tag-in blank) 2026-06-11. Mirrors buildDrawList's
    // `_held` (sprite-client.mjs:880) for the emitter. When a partner TAGS IN, that slot
    // goes active with a char_id whose ASM atlas may still be loading (loadAsmChar is async)
    // OR whose live sprite_id isn't yet in the atlas → emitAssembly returns 0 quads → the
    // character blanks for a few frames. We KEEP the last good per-slot emit and, on a gap
    // (active slot that produced nothing this frame because its atlas isn't loaded), re-push
    // the held quads RE-ANCHORED to the slot's current screen pos so the held pose tracks the
    // moving character through the gap. As soon as the atlas/pose lands the live emit takes
    // over (it produced quads, so we don't replay). Cleared when the slot goes inactive.
    // The preload above usually closes the gap entirely; this covers the residual frames.
    if (!this._heldEmit) this._heldEmit = new Array(6).fill(null);
    if (!force) for (let s = 0; s < 6; s++) {
      const sl = this.slot[s];
      if (!sl.active) { this._heldEmit[s] = null; continue; }
      let exx = sl.screen_x, eyy = sl.screen_y;
      if (this.predict !== false) { const dt = Math.min(now - sl.t, 33); if (dt > 0) { exx += sl.vx*dt; eyy += sl.vy*dt; } }
      const before = out.length;
      emitAssembly({ cid: sl.char_id, exx, eyy, facing: sl.facing, slot: s, zBase: 0,
                     sclX: sl.scaleX, sclY: sl.scaleY, pal12d: sl.pal12d, pal12e: sl.pal12e },
                   sl.sprite_id);
      if (out.length > before) {
        // Live emit succeeded — snapshot it (deep-ish copy of the items + the anchor they
        // were drawn at) so a later gap can replay it re-anchored. Only the same char_id is
        // ever replayed (cleared on inactive / char change below).
        const items = out.slice(before).map(it => ({ ...it }));
        this._heldEmit[s] = { cid: sl.char_id, exx, eyy, items };
      } else {
        // Gap: this active slot drew nothing. Replay the last good emit IFF it's the SAME
        // char (don't show the outgoing partner's pose for the incoming one) AND its atlas
        // genuinely isn't ready yet (a not-loaded atlas, the tag-in case — not a permanent
        // missing-pose, which the live path already handles by skipping). Re-anchor to the
        // current screen pos so the held figure follows the live movement.
        const h = this._heldEmit[s];
        const c = this.asmChars[sl.char_id];
        const atlasNotReady = !c || !c.img;   // still downloading (or kicked just now)
        if (h && h.cid === sl.char_id && atlasNotReady) {
          const ddx = (exx - h.exx) * scaleX, ddy = (eyy - h.eyy) * scaleY;
          for (const it of h.items) {
            out.push({ ...it, dx: it.dx + ddx, dy: it.dy + ddy });
            drawn++;
          }
        }
      }
    }

    // --- pool objects (cape / projectile / fx) ---  (skipped while force-demo is on)
    if (!force && this.objectsOn !== false) for (const o of (this.objects || [])) {
      let osl = null;
      for (let s = 0; s < 6; s++) if (this.slot[s].active && this.slot[s].char_id === o.cid) { osl = this.slot[s]; break; }
      if (!osl) continue;
      let ox = osl.screen_x, oy = osl.screen_y;
      if (this.predict !== false) { const dt = Math.min(now - osl.t, 33); if (dt > 0) { ox += osl.vx*dt; oy += osl.vy*dt; } }
      if ((ox === 0 && oy === 0) || ox < -60 || ox > 700) continue;
      const far = (o.type !== 3) && ((Math.abs(o.x - ox) + Math.abs(o.y - oy)) > 130);
      const px = far ? o.x : ox, py = far ? o.y : oy;
      const zBase = (o.type === 1) ? 1 : (o.type === 3 ? -2 : -1);
      // Effect nodes (is_effect / GFX base in Effect Poly 0x0CED0000) -> effects atlas.
      const isFx = !!o.isEffect;
      emitAssembly({ cid: o.cid, exx: px, eyy: py, facing: osl.facing, slot: 0, zBase,
                     sclX: osl.scaleX, sclY: osl.scaleY, pal12d: osl.pal12d, pal12e: osl.pal12e,
                     blend: o.blend, fx: isFx }, o.sid);
    }

    // Z-ORDER — GSTA wire ext 2026-06-11. MVC2's TRUE draw order is the slot/LAYER table
    // (the slot table IS the draw list — memory reference_mvc2_slot_table_drawlist). That
    // layer is now ON THE WIRE: each char block carries draw_layer (+49 = the slot-table
    // layer index, 0xFF = not in any layer this frame). LOWER layer = drawn FIRST = BEHIND,
    // so we sort char GROUPS by draw_layer ASCENDING, with char_id as the deterministic
    // tiebreak (the renderer groups CONSECUTIVE same-cid quads — sprite-gpu.mjs byChar Map,
    // first-appearance order — so each cid's quads MUST stay contiguous). Intra-assembly z
    // is the final key.
    //   FALLBACK: when NO active slot reports a real layer (all draw_layer==0xFF — e.g. an
    //   older server or a pre-match frame), fall back to the previous SCREEN-DEPTH heuristic
    //   (lower foot/larger screen_y = nearer = on top). window._emitZByDepth=false forces the
    //   pure char_id order (legacy). window._emitZByLayer=false forces the depth fallback.
    const useLayer = (typeof window === 'undefined') ? true
                   : (window._emitZByLayer !== undefined ? !!window._emitZByLayer : true);
    const zByDepth = (typeof window === 'undefined') ? true
                   : (window._emitZByDepth !== undefined ? !!window._emitZByDepth : true);
    // Per-cid draw_layer from the active body slots; track whether ANY real layer was seen.
    const lmap = new Map(); let anyLayer = false;
    for (let s = 0; s < 6; s++) { const sl = this.slot[s];
      if (sl.active && sl.char_id != null && sl.draw_layer !== undefined && sl.draw_layer !== 0xFF) {
        anyLayer = true;
        // Use the MIN layer per cid (earliest = furthest back) for a stable group key.
        if (!lmap.has(sl.char_id) || sl.draw_layer < lmap.get(sl.char_id)) lmap.set(sl.char_id, sl.draw_layer);
      } }
    let groupKey;
    if (useLayer && anyLayer) {
      // ASCENDING draw_layer: lower layer sorts FIRST = behind. cids with no layer (0xFF /
      // pure-effect cids) sort to the BACK of the group order (key = -1 < any real layer).
      groupKey = (cid) => lmap.has(cid) ? lmap.get(cid) : -1;
    } else if (zByDepth) {
      // FALLBACK: per-cid foot depth (larger screen_y = nearer = on top). Sort DESCENDING by
      // depth -> we negate so the comparator below stays "ascending key". A cid not on a body
      // slot -> +Infinity key so it sorts to the back (drawn first).
      const dmap = new Map();
      for (let s = 0; s < 6; s++) { const sl = this.slot[s];
        if (sl.active && sl.char_id != null) {
          const d = sl.screen_y;
          if (!dmap.has(sl.char_id) || d > dmap.get(sl.char_id)) dmap.set(sl.char_id, d);
        } }
      groupKey = (cid) => dmap.has(cid) ? -dmap.get(cid) : Infinity;  // negate: larger screen_y -> later
    } else {
      groupKey = () => 0;   // disabled -> pure char_id order (legacy)
    }
    out.sort((a, b) =>
      (groupKey(a.charId) - groupKey(b.charId))    // ascending group key: lower layer / further = first = behind
      || (a.charId - b.charId)                     // deterministic, keeps each cid contiguous
      || ((a.z || 0) - (b.z || 0)));               // intra-assembly back-to-front
    this._asmDrawn = drawn; this._asmMiss = missing; this._asmSkipSel = skipSel;
    this._asmNote = loading ? `emitter: loading ${loading} char atlas…`
                  : missing ? `emitter: missing ${missing} asm: ${missKeys.join(' ')} (${drawn} parts)`
                  : skipSel ? `emitter(lean): ${drawn} parts drawn · ${skipSel} sels uncaptured (skipped)`
                  : `emitter: ${drawn} parts (port)`;
    this._lastNote = this._asmNote;
    if (_eTrace) {
      // On-screen bound: how many emitted quads land inside the 0..canvasW/0..canvasH frame
      // (a quad emitted off-canvas draws nothing). If drawn>0 but onScreen==0, it's an anchor/scale
      // bug, not a missing-atlas bug.
      const onScreen = out.filter(q => q.dx + q.dw > 0 && q.dx < canvasW && q.dy + q.dh > 0 && q.dy < canvasH).length;
      console.log(`[emit] SUMMARY drawn=${drawn} quads (onScreen=${onScreen}/${out.length}) missing=${missing} loading=${loading} :: ${this._asmNote}`);
    }
    return out;
  }

  // The effects atlas exposed in the same {img, parts, asm} shape emitAssembly uses.
  // loadFxAtlas() populates this._fx (a sprite-keyed atlas); if it also carries an
  // assembly table we use it, else fx objects fall through as missing (logged).
  _fxAsmChar() {
    const fx = this._fx;
    if (!fx || !this._fxImg) return null;
    const asm = fx.assemblies || fx.asm;
    if (!asm) return null;          // effects atlas has no assembly table yet
    return { img: this._fxImg, parts: fx.parts || {}, asm };
  }

  // Active hit-sparks for the GPU additive pass — each grows + fades over ~280ms.
  // Returns [{x,y,size,alpha,frame}] in canvas px; prunes expired sparks.
  buildSparkList(canvasW, canvasH) {
    const scaleX = canvasW / (this.screenW || 640), scaleY = canvasH / (this.screenH || 480);
    const now = (typeof performance !== 'undefined') ? performance.now() : 0;
    const DUR = 280, BASE = 50;                    // ms lifetime, base screen px
    this.sparks = this.sparks.filter(sp => (now - sp.t0) < DUR);
    const out = [];
    for (const sp of this.sparks) {
      const age = (now - sp.t0) / DUR;             // 0..1
      const size = BASE * (0.55 + age * 0.9);      // grow
      out.push({ x: sp.x*scaleX, y: sp.y*scaleY, size: size*scaleX,
                 alpha: Math.max(0, 1 - age*age), frame: sp.frame !== undefined ? sp.frame : (sp.type|0) });
    }
    return out;
  }

  // ===== HUD from state — health/meter/combo/timer are already in the GSTA =====
  // The on-screen POINT character is whichever of a side's 3 slots is active; its
  // health/red_health drive the life bar. (slots arg = that side's 3 slot indices.)
  _pointSlot(slots) {
    for (const s of slots) { const sl = this.slot[s]; if (sl.active) return sl; }
    return null;
  }
  // Draw a horizontal slice of the ripped white bar swatch, tinted with a
  // left->right gradient (the per-team modulate of loc_8c15FFB0). This is the
  // faithful Canvas2D equivalent of MVC2's "white FONT tex modulated by the
  // per-slot vertex color" — drawImage the swatch, then multiply the team tint.
  _drawBar(ctx, x, y, w, h, frac, colA, colB, fromRight) {
    frac = Math.max(0, Math.min(1, frac));
    const fw = Math.round(w * frac);
    if (fw <= 0) return;
    const fx = fromRight ? (x + w - fw) : x;
    const r = this._hud && this._hud.rects && this._hud.rects.bar_white;
    if (r && this._hudImg) {
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(this._hudImg, r.x, r.y, r.w, r.h, fx, y, fw, h);  // stretch ripped white texel
      ctx.save();
      ctx.globalCompositeOperation = 'multiply';                      // modulate -> team tint
      const g = ctx.createLinearGradient(x, 0, x + w, 0);
      g.addColorStop(0, colA); g.addColorStop(1, colB);
      ctx.fillStyle = g; ctx.fillRect(fx, y, fw, h);
      ctx.restore();
    } else {
      // atlas not loaded yet: flat tint (still correct geometry)
      ctx.fillStyle = colB; ctx.fillRect(fx, y, fw, h);
    }
  }
  // Draw the round timer / hit counter from the ripped FONT digit glyphs.
  _drawDigits(ctx, str, x, y, dh, align) {
    if (!this._hud || !this._hudImg) return 0;
    const R = this._hud.rects;
    const d0 = R.digit_0; if (!d0) return 0;
    const scale = dh / d0.h, dw = Math.round(d0.w * scale), adv = dw + 1;
    const total = str.length * adv - 1;
    let cx = (align === 'right') ? x - total : (align === 'center' ? x - total / 2 : x);
    ctx.imageSmoothingEnabled = false;
    for (const ch of str) {
      const r = R['digit_' + ch];
      if (r) ctx.drawImage(this._hudImg, r.x, r.y, r.w, r.h, Math.round(cx), y, dw, dh);
      cx += adv;
    }
    return total;
  }
  // Draw the server-isolated TA effects additively over the scene. Each EFCT
  // descriptor is {id,cx,cy,w,h} in 640x480 screen space; id indexes fx_atlas.
  // (Drawn on the HUD overlay canvas AFTER drawHUD's clear, so call it after.)
  drawEffects(ctx) {
    if (!this.effectsOn || !this.effects.length) return;
    const W = ctx.canvas.width, H = ctx.canvas.height, sx = W / 640, sy = H / 480;
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';   // additive
    for (const e of this.effects) {
      const tex = this._fxCache.get(e.hash); if (!tex) continue;  // texture not received yet
      const dw = Math.max(2, Math.abs(e.w)) * sx, dh = Math.max(2, Math.abs(e.h)) * sy;
      // Draw only the quad's UV sub-rect of the shared EFKYTEX page (not the whole sheet).
      const tw = tex.width, th = tex.height;
      const swp = (e.u1 - e.u0) * tw, shp = (e.v1 - e.v0) * th;
      if (e.u1 != null && swp > 0.5 && shp > 0.5)
        ctx.drawImage(tex, e.u0 * tw, e.v0 * th, swp, shp, e.cx * sx - dw / 2, e.cy * sy - dh / 2, dw, dh);
      else
        ctx.drawImage(tex, e.cx * sx - dw / 2, e.cy * sy - dh / 2, dw, dh);  // fallback (no UV)
    }
    ctx.restore();
  }

  // Draw the REAL game HUD from captured textured quads (health/timer/hit-counter/
  // meters). Identical UV-sub-rect draw to drawEffects, but REGULAR alpha blend so it
  // composites like the game. Call after drawHUD so it lands over the synthesized one.
  drawHudReal(ctx) {
    if (!this.hudQuads || !this.hudQuads.length) return;
    const W = ctx.canvas.width, H = ctx.canvas.height, sx = W / 640, sy = H / 480;
    ctx.save();
    ctx.globalCompositeOperation = 'source-over';
    for (const e of this.hudQuads) {
      const tex = this._fxCache.get(e.hash); if (!tex) continue;   // texture not received yet
      const dw = Math.max(2, Math.abs(e.w)) * sx, dh = Math.max(2, Math.abs(e.h)) * sy;
      const tw = tex.width, th = tex.height;
      const swp = (e.u1 - e.u0) * tw, shp = (e.v1 - e.v0) * th;
      if (e.u1 != null && swp > 0.5 && shp > 0.5)
        ctx.drawImage(tex, e.u0 * tw, e.v0 * th, swp, shp, e.cx * sx - dw / 2, e.cy * sy - dh / 2, dw, dh);
      else
        ctx.drawImage(tex, e.cx * sx - dw / 2, e.cy * sy - dh / 2, dw, dh);
    }
    ctx.restore();
  }

  // Hit-flash: MVC2 swaps the VICTIM's body to a "hurt" palette bank (Dat_Pal+0x300,
  // white; electric -> blue-white) for the hit-reaction frames — it's ON the body,
  // not a separate sprite (per bank03:loc_8c035000). We approximate by drawing an
  // ADDITIVE tinted silhouette of each flashing body (slot.paleffect != 0, via PALF),
  // reusing the body draw-list geometry so it lands exactly on the sprite.
  drawFlash(ctx, drawList) {
    if (!drawList || !drawList.length) return;
    if (this._probeOff == null) return;   // dormant unless actively field-stepping ([ / ])
    // FIELD-STEPPER: flash a body when the PROBED RAM byte (this._probeOff, stepped
    // with [ / ] in the UI) is nonzero for that slot. Step through the on-hit fields
    // (0x1a0, 0x220…) and watch which one's flash matches the game — no hardcoding.
    const poff = ((this._probeOff != null ? this._probeOff : 0x1a0) - (this._wBase || 0)) | 0;
    const lit = (sl, s) => { if (!sl || !sl.active) return false; const v = this._wPrev && this._wPrev[s]; return !!(v && poff >= 0 && poff < v.length && v[poff] > 0); };
    let any = false;
    for (let s = 0; s < 6; s++) if (lit(this.slot[s], s)) { any = true; break; }
    if (!any) return;
    if (!this._flashTmp) this._flashTmp = document.createElement('canvas');
    const tmp = this._flashTmp, tctx = tmp.getContext('2d');
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';   // additive — brightens the body toward the flash color
    for (const it of drawList) {
      if (it.slot == null) continue;
      const sl = this.slot[it.slot];
      if (!lit(sl, it.slot)) continue;
      const c = this.chars[it.charId]; if (!c || !c.img || it.sw <= 0 || it.sh <= 0) continue;
      // Build a solid-tint silhouette of the sprite's alpha (keeps the body shape).
      tmp.width = it.sw; tmp.height = it.sh;
      tctx.globalCompositeOperation = 'source-over'; tctx.clearRect(0, 0, it.sw, it.sh);
      tctx.drawImage(c.img, it.sx, it.sy, it.sw, it.sh, 0, 0, it.sw, it.sh);
      tctx.globalCompositeOperation = 'source-in';
      tctx.fillStyle = '#cfe0ff';                // electric/white hit-flash tint
      tctx.fillRect(0, 0, it.sw, it.sh);
      ctx.globalAlpha = 0.7;
      if (it.flip) { ctx.save(); ctx.translate(it.dx + it.dw, it.dy); ctx.scale(-1, 1); ctx.drawImage(tmp, 0, 0, it.dw, it.dh); ctx.restore(); }
      else ctx.drawImage(tmp, it.dx, it.dy, it.dw, it.dh);
    }
    ctx.restore();
  }

  // Pick the per-team-slot life-bar gradient (loc_8c15FFB0): which of a side's 3
  // chars (C1/C2/C3) is the active point -> magenta/green/cyan -> yellow.
  _barCols(sideSlots) {
    const bc = (this._hud && this._hud.barColors) || {
      C1: ['#FF40FF', '#FFFF00'], C2: ['#00FF00', '#FFFF00'], C3: ['#00C0FF', '#FFFF00'] };
    for (let i = 0; i < sideSlots.length; i++) if (this.slot[sideSlots[i]].active) return bc['C' + (i + 1)];
    return bc.C1;
  }

  // MVC2 HUD, drawn PIXEL-SOURCED from the ripped FONT.BIN atlas (hud_atlas):
  //   - two life bars: white bar swatch stretched to width=HP/maxHP, tinted by the
  //     per-team gradient, with the red_health/maxHP trailing chip behind it.
  //   - super-meter bars: width = meter_fill / 144 (loc_8C0F0FDC max const 144.0).
  //   - meter-level pips (0..5).
  //   - round timer: two FONT digits (BCD-ish, game_timer 0..99).
  //   - hit counter: FONT digits + (font_sheet) — combo>1 per side.
  drawHUD(ctx) {
    const W = ctx.canvas.width, H = ctx.canvas.height;
    ctx.clearRect(0, 0, W, H);
    if (!this.inMatch) return;
    ctx.save(); ctx.scale(W / 640, H / 480);
    ctx.imageSmoothingEnabled = false;
    const hud = this.hud || {};
    const P1 = [0, 2, 4], P2 = [1, 3, 5];
    const METER_MAX = 144;                          // loc_8C0F0FDC: meter_fill / 144.0
    const c1 = this._barCols(P1), c2 = this._barCols(P2);
    const p1 = this._pointSlot(P1), p2 = this._pointSlot(P2);
    const hpFrac = (sl) => sl ? Math.max(0, Math.min(1, sl.health / (sl._maxhp || 144))) : 0;
    const redFrac = (sl) => sl ? Math.max(0, Math.min(1, sl.red_health / (sl._maxhp || 144))) : 0;

    // --- life bars (red chip behind, current HP in front), tinted ripped swatch ---
    const LB = { x1: 18, x2: 330, y: 16, w: 292, h: 14 };
    // P1 (left-anchored): red trailing layer first, then HP on top.
    this._drawBar(ctx, LB.x1, LB.y, LB.w, LB.h, redFrac(p1), '#b01010', '#601010', false);
    this._drawBar(ctx, LB.x1, LB.y, LB.w, LB.h, hpFrac(p1),  c1[0], c1[1], false);
    // P2 (right-anchored mirror).
    this._drawBar(ctx, LB.x2, LB.y, LB.w, LB.h, redFrac(p2), '#b01010', '#601010', true);
    this._drawBar(ctx, LB.x2, LB.y, LB.w, LB.h, hpFrac(p2),  c2[0], c2[1], true);

    // --- super meters (width = fill/144), team-tinted ripped swatch ---
    this._drawBar(ctx, 18,  456, 250, 9, (hud.p1fill || 0) / METER_MAX, c1[0], c1[1], false);
    this._drawBar(ctx, 372, 456, 250, 9, (hud.p2fill || 0) / METER_MAX, c2[0], c2[1], true);

    // --- meter-level pips (0..5) ---
    ctx.fillStyle = '#ffd24d';
    for (let i = 0; i < (hud.p1lvl || 0); i++) ctx.fillRect(18 + i * 12, 446, 9, 6);
    for (let i = 0; i < (hud.p2lvl || 0); i++) ctx.fillRect(613 - i * 12, 446, 9, 6);

    // --- round timer: two ripped FONT digits, centered ---
    const tstr = String(Math.max(0, Math.min(99, hud.timer | 0))).padStart(2, '0');
    if (this._hud && this._hudImg) this._drawDigits(ctx, tstr, 320, 12, 22, 'center');
    else { ctx.fillStyle = '#fff'; ctx.font = 'bold 22px monospace'; ctx.textAlign = 'center'; ctx.textBaseline = 'top'; ctx.fillText(tstr, 320, 14); }

    // --- hit counters: ripped FONT digits, combo>1 per side ---
    const drawCombo = (n, x, align) => {
      if (!(n > 1)) return;
      if (this._hud && this._hudImg) this._drawDigits(ctx, String(n), x, 38, 15, align);
      else { ctx.fillStyle = '#ffe14d'; ctx.font = 'bold 15px monospace'; ctx.textAlign = align; ctx.textBaseline = 'top'; ctx.fillText(n + ' HIT', x, 40); }
    };
    drawCombo(hud.p1combo | 0, 24, 'left');
    drawCombo(hud.p2combo | 0, 616, 'right');
    ctx.restore();
  }

  statsText() {
    const loaded = this.assemblyMode ? Object.keys(this.asmChars) : Object.keys(this.chars);
    const src = this.assemblyMode ? this.asmChars : this.chars;
    const names = loaded.map(c => src[c].name + (src[c].img?'':'!')).join(', ') || '(none yet)';
    const nm = (i) => { const c = this.chars[this.slot[i].char_id]; return c ? c.name : '…'; };
    const LAB = ['P1a','P2a','P1b','P2b','P1c','P2c'];
    const sl = (i) => { const x = this.slot[i];
      return `${LAB[i]} ${x.active?'ON ':'-- '} ${nm(i)}(${x.char_id}) sid=0x${(x.sprite_id&0xffff).toString(16).padStart(4,'0')} f${x.facing}`; };
    const kbps = this._bwRate/1024;
    const mbps = (this._bwRate*8/1e6).toFixed(3);
    if (kbps > (this._bwPeak||0)) this._bwPeak = kbps;       // track peak this session
    const vsMirror = kbps > 0.01 ? (1700/kbps).toFixed(0)+'x cheaper than mirror' : '(waiting for GSTA…)';
    const mode = this.assemblyMode ? 'ASSEMBLY (parts)' : 'WHOLE-SPRITE';
    return `SPRITE CLIENT [${mode}] — ${loaded.length} char atlas loaded\n`
         + `loaded: ${names}\n`
         + `━━━ BANDWIDTH: ${kbps.toFixed(2)} KB/s (${mbps} Mbps) ━━━\n`
         + `      peak ${(this._bwPeak||0).toFixed(2)} KB/s · ${vsMirror} (~1700 KB/s)\n`
         + `size=${(this.spriteScale||1).toFixed(2)}x  zoom(info,not applied)=${(this._zoom||1).toFixed(2)}\n`
         + `  ${this._bwHz.toFixed(0)} Hz x ${this._lastSize} B/frame\n`
         + `inMatch=${this.inMatch}\n` + [0,1,2,3,4,5].map(sl).join('\n') + '\n'
         + (this._lastNote ? `note: ${this._lastNote}` : '');
  }
}

// =============================================================================
// FX-BLEND WIRE BYTE — spec (the "merge" for pixel-exact supers/energy)
// =============================================================================
//
// The GSTA OBJS packet gains an OPTIONAL trailing flags byte per pool object. The
// client auto-detects the stride from the packet length — no version flag — so an
// old 8B server and a new 9B server both work against the same client.
//
//   OBJS packet:  'OBJS'(4) + count(1) + count × OBJ
//   OBJ (legacy): cid(1) + sprite_id(2 LE) + type(1) + x(i16 LE) + y(i16 LE)        = 8 B
//   OBJ (flags):  cid(1) + sprite_id(2 LE) + type(1) + x(i16 LE) + y(i16 LE) + flags(1) = 9 B
//
//   Stride is 9 iff (packetLen - 5) == count*9, else 8. (count*8 and count*9 can
//   only collide when count==0, which carries no objects — safe.)
//
// flags byte (GSTA enrich step 1):
//   bit0 = is_effect — the node's GFX base (node+0x15c) points into the shared
//          "Effect Poly" bank 0x0CED0000; the client routes this object to the
//          effects atlas, NOT the PL{cid} character atlas. bits1-7 reserved.
//
// (Historically this 9th byte was spec'd as a PVR blend nibble (src<<4|dst); that
// was never emitted by the server. The reference table below is retained for the
// eventual blend path, which would move to a 10th byte.)
//
// blend byte = (srcFactor << 4) | dstFactor, the PVR TSP instruction word's
// SRC_ALPHA_INSTR (bits 29-31) and DST_ALPHA_INSTR (bits 26-28), each a 3-bit
// PVR blend code packed into a nibble:
//
//   PVR code  meaning            WebGPU GPUBlendFactor   Canvas2D
//   0  ZERO                      'zero'
//   1  ONE                       'one'                   'lighter' (additive) when DST
//   2  OTHER (dst/src color)     'src'/'dst' color
//   3  INVERSE OTHER             'one-minus-…-color'
//   4  SRC ALPHA                 'src-alpha'             'source-over' (default)
//   5  INVERSE SRC ALPHA         'one-minus-src-alpha'
//   6  DST ALPHA                 'dst-alpha'
//   7  INVERSE DST ALPHA         'one-minus-dst-alpha'
//
// The common cases:
//   0x45 = src=SRC_ALPHA(4), dst=INV_SRC_ALPHA(5)  -> normal alpha (default; omit byte)
//   0x11 = src=ONE(1),       dst=ONE(1)            -> additive glow (supers/energy)
//   0x41 = src=SRC_ALPHA(4), dst=ONE(1)            -> premultiplied additive
//
// Client mapping: sprite-gpu.mjs picks the additive pipeline when dst==ONE (the
// glow case); Canvas2D uses globalCompositeOperation='lighter' for dst==ONE.
// Everything else falls back to normal alpha. Default (no byte) == 0x45.
// =============================================================================
