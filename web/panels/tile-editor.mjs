// tile-editor.mjs — Skin Studio: palette recolor + a COMPOSITE FRAME pixel editor.
// Pick an animation, step its frames, paint on the FULLY ASSEMBLED sprite at full size,
// watch the animation play with your edits. Strokes are decomposed back to the individual
// parts (bundle orientation) and exported as skin.json for tools/bake_skin.py.
//
// Data: web/anim/PLxx.json · PLxx_asm.json (sprite_id→[{dx,dy,part,flip,flipy}]) ·
//       PLxx_edit.{png,json} (bake-faithful part atlas — tools/export_editor_bundle.py PLxx)
// Verified: bundle pixels + _asm composite to a correct right-side-up pose; painted parts
// (bundle orientation) bake byte-faithful via png_to_blob.

import * as rb from '../rom-bake.mjs?v=6';
import { RomReader } from '../rom-reader.mjs?v=6';

const HEX2 = (n) => n.toString(16).toUpperCase().padStart(2, '0');

const CHARS = [
  ['00','Ryu'],['01','Zangief'],['02','Guile'],['03','Morrigan'],['04','Anakaris'],['05','Strider'],['06','Cyclops'],['07','Wolverine (metal)'],
  ['08','Psylocke'],['09','Iceman'],['0A','Rogue'],['0B','Captain America'],['0C','Spider-Man'],['0D','Hulk'],['0E','Venom'],['0F','Dr. Doom'],
  ['10','Tron'],['11','Jill'],['12','Hayato'],['13','Ruby Heart'],['14','SonSon'],['15','Amingo'],['16','Marrow'],['17','Cable'],
  ['18','Abyss1'],['19','Abyss2'],['1A','Abyss3'],['1B','Chun-Li'],['1C','Mega Man'],['1D','Roll'],['1E','Akuma'],['1F','B.B.Hood'],
  ['20','Felicia'],['21','Charlie'],['22','Sakura'],['23','Dan'],['24','Cammy'],['25','Dhalsim'],['26','M.Bison'],['27','Ken'],
  ['28','Gambit'],['29','Juggernaut'],['2A','Storm'],['2B','Sabretooth'],['2C','Magneto'],['2D','Shuma-Gorath'],['2E','War Machine'],['2F','Silver Samurai'],
  ['30','Omega Red'],['31','Spiral'],['32','Colossus'],['33','Iron Man'],['34','Sentinel'],['35','Blackheart'],['36','Thanos'],['37','Jin'],
  ['38','Captain Commando'],['39','Wolverine (bone)'],['3A','Servbot'],
];

export class SkinStudio {
  constructor(root, { atlasBase = './test-atlas/chars', animBase = './anim' } = {}) {
    this.root = root; this.atlasBase = atlasBase; this.animBase = animBase;
    this.cid = null; this.bank = 0;
    this.orig = []; this.cur = []; this._key2idx = null;                       // palette
    this.bundle = null; this.bundleImg = null; this.bundleData = null;        // part atlas (RGBA pixels)
    this.anim = null; this.asm = null;
    this.cells = []; this.fi = 0; this.frame = null;                          // current animation + frame
    this._origPix = {}; this.painted = {};                                   // sel -> Uint8Array indices
    this.brush = 1; this.tool = 'pencil'; this._undoStack = []; this._timer = null;
    this.romReader = null; this._romHandle = null; this._romDir = null; this._romName = null; this._romCache = new Map();
    this._build();
  }

  _build() {
    this.root.innerHTML = `
      <div class="ss-row">
        <label>character <select class="ss-char"></select></label>
        <button class="ss-reset" title="revert palette">reset palette</button>
        <button class="ss-export">export skin.json</button>
        <button class="ss-bakerom" title="bake into a patched GDI (needs skin_server.py)">⬇ bake to ROM</button>
        <button class="ss-loadrom" title="pick the folder that holds your GDI (track03.bin)">📀 load ROM</button>
        <span class="ss-romsrc dim" style="font-size:11px">pick your GDI folder to start</span>
      </div>
      <div class="ss-row">
        <label>anim <select class="ss-grp"></select></label>
        <select class="ss-sub"></select>
      </div>
      <div class="ss-row ss-framenav">
        <button class="ss-prev-f" title="previous frame">◀ prev</button>
        <span class="ss-finfo">frame —</span>
        <button class="ss-next-f" title="next frame">next ▶</button>
        <button class="ss-play" title="play through the animation">▶ play</button>
        <input class="ss-fr" type="range" min="0" value="0" style="width:120px" title="scrub frames">
      </div>
      <div class="ss-hint">Pick an animation above, then use <b>◀ prev / next ▶</b> to step frame-by-frame. Paint this frame, advance, paint again. Left-click swatch to paint · <b>right-click to edit that color</b> live on the sprite.</div>
      <div class="ss-paint">
        <div class="ss-pwrap">
          <div class="ss-tools">
            <button data-t="pencil" class="on">✏ pencil</button>
            <button data-t="fill">🪣 fill</button>
            <button data-t="pick">💧 pick</button>
            <button data-t="pan">✋ pan</button>
            <button class="ss-erase-tool">✕ erase</button>
            <button class="ss-undo">↶ undo</button>
            <button class="ss-reset-frame" title="reset pixel edits for parts in this frame">↺ frame px</button>
            <button class="ss-reset-all-px" title="reset ALL painted parts">↺ all px</button>
            <span class="ss-sep"></span>
            <span class="dim" style="font-size:11px">size</span>
            <button class="ss-sz on" data-sz="1">1</button>
            <button class="ss-sz" data-sz="2">2</button>
            <button class="ss-sz" data-sz="4">4</button>
            <button class="ss-sz" data-sz="8">8</button>
            <label class="dim" style="font-size:11px">zoom <input class="ss-zoom" type="range" min="1" max="24" value="4"></label>
            <label class="dim" style="font-size:11px"><input class="ss-boxes" type="checkbox" checked> part boxes</label>
          </div>
          <div class="ss-canvas-row">
            <div class="ss-pal-side">
              <div class="dim ss-pal-label">palette · right-click to edit</div>
              <div class="ss-brush"></div>
            </div>
            <canvas class="ss-edit" width="420" height="380"></canvas>
          </div>
        </div>
      </div>
      <div class="ss-bake"></div>`;
    const $ = (s) => this.root.querySelector(s);
    this.selEl = $('.ss-char');
    this.grpEl = $('.ss-grp'); this.subEl = $('.ss-sub'); this.frEl = $('.ss-fr'); this.finfo = $('.ss-finfo');
    this.brushEl = $('.ss-brush'); this.editC = $('.ss-edit'); this.ectx = this.editC.getContext('2d'); this.ectx.imageSmoothingEnabled = false;
    this.zoomEl = $('.ss-zoom'); this.bakeEl = $('.ss-bake'); this._romSrcEl = $('.ss-romsrc');
    this.penSize = 1;

    for (const [hex, nm] of CHARS) { const o = document.createElement('option'); o.value = hex; o.textContent = `PL${hex} ${nm}`; this.selEl.append(o); }
    this.selEl.value = '17'; // default to Cable (well-tested char with full atlas)
    this.selEl.onchange = () => this.loadChar(parseInt(this.selEl.value, 16));
    $('.ss-reset').onclick = () => { this.cur = this.orig.map(c => c.slice()); this._renderBrush(); this._render(); this._renderBake(); };
    $('.ss-loadrom').onclick = () => this._loadRom();
    $('.ss-export').onclick = () => this.exportSkin();
    $('.ss-bakerom').onclick = () => this.bakeToRom();
    $('.ss-undo').onclick = () => { if (!this._undoStack?.length) return; const entry = this._undoStack.pop(); for (const { sel, pix } of entry) this.painted[sel] = pix; this._drawFrame(); this._renderBake(); };
    this.root.querySelectorAll('.ss-tools button[data-t]').forEach(b => b.onclick = () => { this.tool = b.dataset.t; this.root.querySelectorAll('.ss-tools button[data-t]').forEach(x => x.classList.toggle('on', x === b)); });
    $('.ss-erase-tool').onclick = () => { this.brush = 0; this._renderBrush(); };
    $('.ss-reset-frame').onclick = () => {
      if (!this.frame) return;
      for (const pb of this.frame.parts) { delete this.painted[pb.sel]; delete this._origPix[pb.sel]; }
      this._undoStack = []; this._drawFrame(); this._renderBake();
    };
    $('.ss-reset-all-px').onclick = () => {
      if (!Object.keys(this.painted).length) return;
      this.painted = {}; this._origPix = {}; this._undoStack = [];
      try { localStorage.removeItem(this._draftKey()); } catch {}
      this._drawFrame(); this._renderBake();
    };
    this.root.querySelectorAll('.ss-sz').forEach(b => b.onclick = () => { this.penSize = +b.dataset.sz; this.root.querySelectorAll('.ss-sz').forEach(x => x.classList.toggle('on', x === b)); });
    this.grpEl.onchange = () => this._populateSubs();
    this.subEl.onchange = () => this._selectAnim();
    $('.ss-play').onclick = (e) => this._togglePlay(e.target);
    $('.ss-prev-f').onclick = () => this._gotoFrame(this.fi - 1);
    $('.ss-next-f').onclick = () => this._gotoFrame(this.fi + 1);
    this.frEl.oninput = () => this._gotoFrame(+this.frEl.value);
    this.zoomEl.oninput = () => { this._panX = null; this._render(); };   // recenter on zoom
    $('.ss-boxes').onchange = (e) => { this._showBoxes = e.target.checked; this._render(); };
    this._hoverSel = -1; this._showBoxes = true;
    this._editEvents();
    this.cid = parseInt(this.selEl.value, 16); // set default; loadChar deferred until ROM picked
    this._populateGroups();
  }

  async loadChar(cid, { fresh = false } = {}) {
    this._stop(); this.cid = cid; this.painted = {}; this._origPix = {}; this.fi = 0;
    this._undoStack = []; this._oc = null;

    if (!this.romReader) {
      this.orig = []; this.cur = []; this.asm = null; this.bundle = null; this.bundleData = null; this.anim = null;
      this._renderBrush(); this._populateGroups(); this._renderBake();
      return;
    }

    let data = null;
    try {
      if (!this._romCache.has(cid)) this._romCache.set(cid, await this.romReader.extractChar(cid));
      data = this._romCache.get(cid);
      this.bank = data.lut.bodyBank || 0;
      this.orig = (data.lut.banks[this.bank] || []).map(c => c.slice());
      this.cur = this.orig.map(c => c.slice());
      this._key2idx = {}; this.orig.forEach((c, i) => { if (c[3] > 0) this._key2idx[`${c[0]},${c[1]},${c[2]}`] = i; });
      this.asm = data.asm.assemblies;
      this.bundle = data.bundle; this.bundleImg = data.bundleImg;
      this.bundleData = data.bundleData;
    } catch (e) {
      console.error('ROM extract failed:', e);
      this.orig = []; this.cur = []; this.asm = null; this.bundle = null; this.bundleData = null;
      if (this._romSrcEl) this._romSrcEl.textContent = `❌ ${e.message}`;
    }

    // anim comes from ROM reader; fall back to server JSON if ROM didn't produce groups
    this.anim = (data?.anim && Object.keys(data.anim.groups).length) ? data.anim : null;
    if (!this.anim) {
      const bust = '?t=' + (this._t = (this._t || 1) + 1);
      try { this.anim = await (await fetch(`${this.animBase}/PL${HEX2(cid)}.json${bust}`)).json(); } catch { this.anim = null; }
    }
    if (!fresh) this._loadDraft();
    this._renderBrush(); this._populateGroups(); this._renderBake();
  }

  // ---------- animation / frames ----------
  _populateGroups() {
    this.grpEl.innerHTML = ''; this.subEl.innerHTML = '';
    if (!this.anim) {
      // No catalog: synthesize a static default frame from the first available sprite_id
      if (this.asm && this.bundle) {
        const firstSid = Object.keys(this.asm).sort((a, b) => +a - +b)[0];
        if (firstSid !== undefined) {
          this.cells = [{ sprite_id: +firstSid }]; this.fi = 0;
          this.frEl.max = 0; this.frEl.value = 0;
          this._fitOnCenter = true; this._panX = null; this._drawFrame();
          this.finfo.textContent = `static sid 0x${(+firstSid).toString(16)} · load anim catalog for animation`;
          return;
        }
      }
      this.cells = []; this.finfo.textContent = this.bundle ? 'no anim catalog' : '📀 pick your ROM to start'; return;
    }
    for (const g of Object.keys(this.anim.groups).sort((a, b) => a - b)) { const grp = this.anim.groups[g]; const o = document.createElement('option'); o.value = g; o.textContent = `g${g} [${grp.kind || '?'}] ${grp.name}`; this.grpEl.append(o); }
    this._populateSubs();
  }
  _populateSubs() {
    this.subEl.innerHTML = ''; const grp = this.anim && this.anim.groups[this.grpEl.value]; if (!grp) return;
    grp.subanims.forEach((s, i) => { const o = document.createElement('option'); o.value = i; o.textContent = `#${i} (${s.cells.length} cells)`; this.subEl.append(o); });
    this._selectAnim();
  }
  _selectAnim() {
    const grp = this.anim && this.anim.groups[this.grpEl.value]; const sub = grp && grp.subanims[+this.subEl.value];
    this.cells = sub ? sub.cells : []; this.fi = 0; this.frEl.max = Math.max(0, this.cells.length - 1); this.frEl.value = 0;
    this._fitOnCenter = true; this._panX = null; this._drawFrame();
  }
  _gotoFrame(i) { if (!this.cells.length) return; this.fi = (i + this.cells.length) % this.cells.length; this.frEl.value = this.fi; this._drawFrame(); }
  _togglePlay(btn) { if (this._timer) { this._stop(); btn.textContent = '▶'; } else { btn.textContent = '⏸'; const tick = () => { this._gotoFrame(this.fi + 1); }; this._timer = setInterval(tick, 120); } }
  _stop() { if (this._timer) { clearInterval(this._timer); this._timer = null; const b = this.root.querySelector('.ss-play'); if (b) b.textContent = '▶'; } }

  // current pixels of a part (painted override, else decoded from the bundle once)
  _partPix(sel) {
    if (this.painted[sel]) return this.painted[sel];
    if (this._origPix[sel]) return this._origPix[sel];
    const r = this.bundle.parts[sel]; const px = new Uint8Array(r.w * r.h);
    for (let y = 0; y < r.h; y++) for (let x = 0; x < r.w; x++) {
      const p = ((r.y + y) * this.bundle.w + (r.x + x)) * 4; const a = this.bundleData[p + 3];
      px[y * r.w + x] = a === 0 ? 0 : (this._key2idx[`${this.bundleData[p]},${this.bundleData[p + 1]},${this.bundleData[p + 2]}`] ?? 0);
    }
    this._origPix[sel] = px; return px;
  }

  // composite the current frame's sprite into an index buffer + owner maps (for decompose)
  _composite() {
    const cell = this.cells[this.fi]; if (!cell || !this.asm || !this.bundle) return null;
    const sid = cell.sprite_id; if (sid == null || sid === 0xFFFF) return null;
    const recs = this.asm[String(sid & 0x7fff)] || this.asm[String(sid)]; if (!recs) return null;
    const pl = [];
    let minx = 1e9, miny = 1e9, maxx = -1e9, maxy = -1e9;
    for (const r of recs) {
      const pr = this.bundle.parts[r.part]; if (!pr) continue;
      const w = pr.w, h = pr.h, flip = !!r.flip, flipy = !!r.flipy;
      // Placement VALIDATED vs whole-sprite ground truth across PL00/17/2C/2A (mean width-dev
      // 0.1-5.2px, sign-detect over 40 sids/char): part left edge = -dx (the _asm dx convention
      // is negated vs the facing-0 atlas), NO -w. The 0x4000 flip is a PIXEL mirror only — it
      // does NOT move the quad (flipMoves=true gave 38-101px error). flipy mirrors the rect in Y.
      const pdx = -r.dx, pdy = flipy ? -(r.dy + h) : r.dy;
      pl.push({ sel: r.part, x: pdx, y: pdy, w, h, flip, flipy });
      minx = Math.min(minx, pdx); miny = Math.min(miny, pdy); maxx = Math.max(maxx, pdx + w); maxy = Math.max(maxy, pdy + h);
    }
    if (!pl.length) return null;
    const W = maxx - minx, H = maxy - miny, N = W * H;
    const out = new Uint8Array(N), ownSel = new Int32Array(N).fill(-1), ownLoc = new Int32Array(N).fill(-1), boxSel = new Int32Array(N).fill(-1), boxLoc = new Int32Array(N).fill(-1);
    for (const p of pl) {
      const pix = this._partPix(p.sel);
      for (let py = 0; py < p.h; py++) for (let px = 0; px < p.w; px++) {
        const sx = p.flip ? p.w - 1 - px : px, sy = p.flipy ? p.h - 1 - py : py;
        const loc = sy * p.w + sx, idx = pix[loc];
        const ci = (p.y - miny + py) * W + (p.x - minx + px);
        boxSel[ci] = p.sel; boxLoc[ci] = loc;
        if (idx !== 0) { out[ci] = idx; ownSel[ci] = p.sel; ownLoc[ci] = loc; }
      }
    }
    const parts = pl.map(p => ({ sel: p.sel, x: p.x - minx, y: p.y - miny, w: p.w, h: p.h }));
    return { out, W, H, ownSel, ownLoc, boxSel, boxLoc, parts };
  }

  _drawFrame() { this.frame = this._composite(); this._oc = null; this._render(); }   // recomposite + draw (frame/part change)
  _render() {                                                          // draw only (hover/zoom/palette change)
    const c = this.editC, ctx = this.ectx; ctx.clearRect(0, 0, c.width, c.height);
    const f = this.frame;
    const cell = this.cells[this.fi];
    this.finfo.textContent = this.cells.length ? `frame ${this.fi + 1}/${this.cells.length} · sid 0x${((cell?.sprite_id ?? 0) & 0x7fff).toString(16)}` + (f ? ` · ${f.W}×${f.H}` : ' · (blank)') : 'no animation';
    if (!f) { ctx.fillStyle = '#7f8593'; ctx.font = '12px monospace'; ctx.fillText('blank / no assembly for this frame', 8, 20); this._z = 0; return; }
    let z = Math.max(1, +this.zoomEl.value);
    if (this._panX == null) {
      if (this._fitOnCenter) { z = Math.max(1, Math.min(Math.floor(c.width / f.W), Math.floor(c.height / f.H))); this.zoomEl.value = z; this._fitOnCenter = false; }
      this._panX = Math.floor((c.width - f.W * z) / 2); this._panY = Math.floor((c.height - f.H * z) / 2);
    }
    this._z = z;
    this._ox = this._panX; this._oy = this._panY;
    // Fast path: fill ImageData at 1:1, then scale once with drawImage.
    // Dramatically faster than per-pixel fillRect for large/zoomed sprites.
    if (!this._oc || this._oc.width !== f.W || this._oc.height !== f.H)
      { this._oc = new OffscreenCanvas(f.W, f.H); this._ocCtx = this._oc.getContext('2d'); }
    const id = new ImageData(f.W, f.H); const d = id.data;
    for (let i = 0, N = f.W * f.H; i < N; i++) {
      const idx = f.out[i]; const col = this.cur[idx] || [0,0,0,0]; const p = i << 2;
      if (idx === 0 || col[3] === 0) { const ck = ((i % f.W + (i / f.W | 0)) & 1) ? 0x17 : 0x1d; d[p]=d[p+1]=d[p+2]=ck; d[p+3]=255; }
      else { d[p]=col[0]; d[p+1]=col[1]; d[p+2]=col[2]; d[p+3]=255; }
    }
    this._ocCtx.putImageData(id, 0, 0);
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(this._oc, 0, 0, f.W, f.H, this._ox, this._oy, f.W * z, f.H * z);
    // part outlines — every tile that makes up this frame; hovered/edited highlighted
    if (this._showBoxes !== false) {
      ctx.lineWidth = 1;
      for (const pb of f.parts) {
        const hot = pb.sel === this._hoverSel, edited = !!this.painted[pb.sel];
        ctx.strokeStyle = hot ? '#ffe878' : edited ? 'rgba(95,208,138,.8)' : 'rgba(127,176,255,.35)';
        ctx.strokeRect(this._ox + pb.x * z + 0.5, this._oy + pb.y * z + 0.5, pb.w * z - 1, pb.h * z - 1);
      }
    }
  }

  // ---------- brush / palette ----------
  _renderBrush() {
    const eb = this.root.querySelector('.ss-erase-tool'); if (eb) eb.classList.toggle('on', this.brush === 0);
    this.brushEl.innerHTML = '';
    for (let i = 0; i < 16; i++) {
      const c = this.cur[i] || [0, 0, 0, 0];
      const edited = i > 0 && JSON.stringify(c) !== JSON.stringify(this.orig[i] || [0,0,0,0]);
      const b = document.createElement('div');
      b.className = 'ss-bsw' + (i === this.brush ? ' on' : '') + (edited ? ' edited' : '');
      if (i === 0) {
        b.dataset.erase = '1';
        b.innerHTML = '<span style="position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:11px;color:#e07070;pointer-events:none">E</span>';
      } else {
        b.style.background = c[3] === 0 ? 'transparent' : `rgb(${c[0]},${c[1]},${c[2]})`;
        const lbl = document.createElement('span');
        lbl.style.cssText = 'position:absolute;bottom:1px;right:2px;font-size:8px;color:rgba(255,255,255,.55);pointer-events:none;line-height:1';
        lbl.textContent = i;
        b.appendChild(lbl);
        // hidden color input — triggered by right-click to keep left-click as brush-select
        const inp = document.createElement('input'); inp.type = 'color';
        inp.value = '#' + c.slice(0,3).map(v => v.toString(16).padStart(2,'0')).join('');
        inp.style.cssText = 'position:absolute;width:0;height:0;opacity:0;pointer-events:none;';
        inp.oninput = (e) => {
          const h = e.target.value;
          this.cur[i] = [parseInt(h.slice(1,3),16), parseInt(h.slice(3,5),16), parseInt(h.slice(5,7),16), 255];
          this._renderBrush(); this._render(); this._renderBake();
        };
        b.appendChild(inp);
        b.addEventListener('contextmenu', (e) => {
          e.preventDefault();
          this.brush = i; this._renderBrush();
          // after rebuild, click the new input at this slot
          this.brushEl.querySelectorAll('.ss-bsw')[i]?.querySelector('input[type=color]')?.click();
        });
      }
      b.title = i === 0 ? 'erase (transparent — index 0)' : `index ${i}${edited ? ' · edited' : ''} · right-click to edit color`;
      b.onclick = () => { this.brush = i; this._renderBrush(); };
      this.brushEl.appendChild(b);
    }
  }
  _xy(e) { const r = this.editC.getBoundingClientRect(); const z = this._z || 1; const x = Math.floor(((e.clientX - r.left) * (this.editC.width / r.width) - this._ox) / z); const y = Math.floor(((e.clientY - r.top) * (this.editC.height / r.height) - this._oy) / z); const f = this.frame; return (f && x >= 0 && y >= 0 && x < f.W && y < f.H) ? [x, y] : null; }
  _editEvents() {
    let down = false;
    let strokeUndo = new Map(); // before-state of each part first touched this stroke
    const MAX_UNDO = 20;
    const paintAt = (cx, cy) => {
      const f = this.frame;
      // pick: single point, no pen-size
      if (this.tool === 'pick') {
        const ci = cy * f.W + cx; let sel = f.ownSel[ci], loc = f.ownLoc[ci];
        if (sel < 0) { sel = f.boxSel[ci]; loc = f.boxLoc[ci]; }
        if (sel >= 0) { this.brush = (this.painted[sel] || this._partPix(sel))[loc]; this._renderBrush(); }
        return;
      }
      // pencil / erase: paint a sz×sz square centered on the cursor
      const sz = this.penSize || 1, half = Math.floor(sz / 2);
      for (let dy = 0; dy < sz; dy++) for (let dx = 0; dx < sz; dx++) {
        const px = cx - half + dx, py = cy - half + dy;
        if (px < 0 || py < 0 || px >= f.W || py >= f.H) continue;
        const ci = py * f.W + px;
        let sel = f.ownSel[ci], loc = f.ownLoc[ci];
        if (sel < 0) { sel = f.boxSel[ci]; loc = f.boxLoc[ci]; }
        if (sel < 0) continue;
        if (!strokeUndo.has(sel)) strokeUndo.set(sel, (this.painted[sel] || this._partPix(sel)).slice());
        if (!this.painted[sel]) this.painted[sel] = this._partPix(sel).slice();
        this.painted[sel][loc] = this.brush;
      }
    };
    const apply = (e) => {
      const p = this._xy(e); if (!p) return; const [x, y] = p; const f = this.frame; if (!f) return;
      if (this.tool === 'fill') this._fillComposite(x, y); else paintAt(x, y);
      this._drawFrame(); this._renderBake();
    };
    let panLast = null;
    this.editC.addEventListener('mousedown', (e) => {
      if (this.tool === 'pan') { panLast = [e.clientX, e.clientY]; return; }
      if (!this.frame) return;
      strokeUndo = new Map(); // fresh per-stroke before-state collection
      down = true; apply(e);
    });
    this.editC.addEventListener('mousemove', (e) => {
      if (panLast) { const r = this.editC.getBoundingClientRect(); this._panX += (e.clientX - panLast[0]) * (this.editC.width / r.width); this._panY += (e.clientY - panLast[1]) * (this.editC.height / r.height); panLast = [e.clientX, e.clientY]; this._render(); return; }
      if (down && this.tool === 'pencil') { apply(e); return; }
      const f = this.frame; if (!f) return; const p = this._xy(e); let s = -1;
      if (p) { const ci = p[1] * f.W + p[0]; s = f.ownSel[ci]; if (s < 0) s = f.boxSel[ci]; }
      if (s !== this._hoverSel) { this._hoverSel = s; this._render(); }
    });
    this.editC.addEventListener('mouseleave', () => { if (this._hoverSel !== -1) { this._hoverSel = -1; this._render(); } });
    window.addEventListener('mouseup', () => {
      if (down && strokeUndo.size > 0) {
        this._undoStack.push([...strokeUndo.entries()].map(([s, p]) => ({ sel: s, pix: p })));
        if (this._undoStack.length > MAX_UNDO) this._undoStack.shift();
        strokeUndo = new Map();
      }
      down = false; panLast = null;
    });
  }
  _fillComposite(x, y) {
    const f = this.frame; const from = f.out[y * f.W + x]; if (from === this.brush) return;
    const st = [[x, y]];
    while (st.length) {
      const [cx, cy] = st.pop(); if (cx < 0 || cy < 0 || cx >= f.W || cy >= f.H) continue;
      const ci = cy * f.W + cx; if (f.out[ci] !== from) continue;
      let sel = f.ownSel[ci], loc = f.ownLoc[ci]; if (sel < 0) { sel = f.boxSel[ci]; loc = f.boxLoc[ci]; }
      if (sel >= 0) { if (!this.painted[sel]) this.painted[sel] = this._partPix(sel).slice(); this.painted[sel][loc] = this.brush; }
      f.out[ci] = this.brush;   // mark visited
      st.push([cx + 1, cy], [cx - 1, cy], [cx, cy + 1], [cx, cy - 1]);
    }
  }

  // ---------- export ----------
  _partToDataURL(sel) {
    const px = this.painted[sel], r = this.bundle.parts[sel]; const oc = new OffscreenCanvas(r.w, r.h); const ox = oc.getContext('2d'); const id = ox.createImageData(r.w, r.h); const d = id.data;
    for (let p = 0; p < r.w * r.h; p++) { const c = this.cur[px[p]] || [0, 0, 0, 0]; if (px[p] === 0 || c[3] === 0) d[p * 4 + 3] = 0; else { d[p * 4] = c[0]; d[p * 4 + 1] = c[1]; d[p * 4 + 2] = c[2]; d[p * 4 + 3] = 255; } }
    ox.putImageData(id, 0, 0); return oc.convertToBlob({ type: 'image/png' }).then(b => new Promise(res => { const fr = new FileReader(); fr.onload = () => res(fr.result); fr.readAsDataURL(b); }));
  }
  _diffPalette() { const o = {}; this.cur.forEach((c, i) => { if (JSON.stringify(c) !== JSON.stringify(this.orig[i])) o[i] = c; }); return o; }

  // ---------- draft persistence (survives page refresh) ----------
  _draftKey() { return `mvc2-sks-PL${HEX2(this.cid)}`; }
  _saveDraft() {
    if (this.cid == null) return;
    const draft = { palette: this._diffPalette(), painted: {} };
    for (const [s, px] of Object.entries(this.painted)) draft.painted[s] = Array.from(px);
    try { localStorage.setItem(this._draftKey(), JSON.stringify(draft)); } catch {}
  }
  _loadDraft() {
    try {
      const raw = localStorage.getItem(this._draftKey()); if (!raw) return false;
      const { palette = {}, painted = {} } = JSON.parse(raw);
      for (const [i, c] of Object.entries(palette)) { const n = +i; if (n > 0 && n < this.cur.length) this.cur[n] = c; }
      for (const [s, arr] of Object.entries(painted)) this.painted[+s] = new Uint8Array(arr);
      return Object.keys(palette).length > 0 || Object.keys(painted).length > 0;
    } catch { return false; }
  }

  _renderBake() {
    const pe = Object.keys(this._diffPalette()).length, pp = Object.keys(this.painted).length;
    this.bakeEl.innerHTML = (pe || pp) ? `<b>${pe}</b> color(s), <b>${pp}</b> painted part(s). Export, then:<br><code>python tools/bake_skin.py PL${HEX2(this.cid)}_skin.json</code>` : `<span class="dim">recolor a swatch or paint the sprite for PL${HEX2(this.cid)}</span>`;
    this._saveDraft();
  }
  async _buildSkin() {
    const skin = { char: `PL${HEX2(this.cid)}` }; const pe = this._diffPalette(); if (Object.keys(pe).length) skin.palette = { [this.bank]: pe };
    const sels = Object.keys(this.painted); if (sels.length) { skin.parts_png_b64 = {}; for (const s of sels) skin.parts_png_b64[s] = await this._partToDataURL(parseInt(s)); }
    return skin;
  }
  _hasEdits() { return Object.keys(this._diffPalette()).length || Object.keys(this.painted).length; }
  async exportSkin() {
    const skin = await this._buildSkin();
    const blob = new Blob([JSON.stringify(skin)], { type: 'application/json' }); const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = `PL${HEX2(this.cid)}_skin.json`; a.click(); URL.revokeObjectURL(a.href);
  }
  // Build a Map<sel, twiddled-4bpp pixels> from the painted parts (display indices -> ROM format).
  _buildEdits() {
    const edits = new Map();
    for (const s of Object.keys(this.painted)) { const r = this.bundle.parts[s]; edits.set(+s, rb.paintedToBlobPixels(this.painted[s], r.w, r.h)); }
    const pe = this._diffPalette(); const palEdits = Object.keys(pe).length ? { [this.bank]: pe } : null;
    return { edits, palEdits };
  }
  async _loadRom() {
    // Pick the GDI FOLDER (not the file) so we can both read track03.bin and write a
    // sibling .bak backup next to it on bake — see bakeToRom / rb.ensureBackup.
    let dir;
    try { dir = await window.showDirectoryPicker({ mode: 'readwrite' }); }
    catch { return; } // cancelled
    this._romSrcEl.textContent = 'finding track03.bin…';
    try {
      const { handle, name } = await RomReader.findInDir(dir);
      this.romReader = await RomReader.fromFile(await handle.getFile());
      this._romHandle = handle; this._romDir = dir; this._romName = name;
      this._romCache = new Map();
      this._romSrcEl.textContent = `📀 ${name}`;
      await this.loadChar(this.cid, { fresh: true });
      this._warmRomCache(name);
    } catch (e) {
      this.romReader = null; this._romHandle = null; this._romDir = null; this._romName = null;
      this._romSrcEl.textContent = `❌ ${e.message}`;
    }
  }

  async _warmRomCache(romName) {
    const reader = this.romReader; // snapshot — if user loads another ROM mid-warmup, bail
    let done = 0;
    for (const [hex] of CHARS) {
      if (this.romReader !== reader) return; // stale
      const cid = parseInt(hex, 16);
      if (!this._romCache.has(cid)) {
        try { this._romCache.set(cid, await reader.extractChar(cid)); }
        catch { /* skip broken chars silently */ }
      }
      done++;
      if (done % 5 === 0 || done === CHARS.length)
        this._romSrcEl.textContent = `📀 ${romName} (${done}/${CHARS.length})`;
      await new Promise(r => setTimeout(r, 0)); // yield to UI between chars
    }
    this._romSrcEl.textContent = `📀 ${romName} ✓ all ${CHARS.length} chars`;
  }
  async bakeToRom() {
    if (!this._hasEdits()) { this.bakeEl.innerHTML = '<span class="dim">nothing edited yet</span>'; return; }
    if (location.protocol === 'file:') {
      this.bakeEl.innerHTML = `❌ Don't open this file directly. Serve it: run <code>python tools/skin_server.py</code>, then open <b>http://localhost:8000/skin-studio.html</b> and bake again.`; return;
    }
    this.bakeEl.innerHTML = 'baking…';
    // 1) Local Python server (preferred): reads your ROM, writes a clean patched COPY. No file-picking.
    try {
      const r = await fetch('./bake', { method: 'POST', body: JSON.stringify(await this._buildSkin()) });
      if (r.ok) {
        const j = await r.json();
        this.bakeEl.innerHTML = j.ok
          ? `✅ baked → <code>${j.path}</code><br><span class="dim">${j.info} · load THAT .gdi in flycast (not your original)</span>`
          : `❌ bake failed: ${j.error}`;
        return;
      }
    } catch { /* no /bake server — fall through */ }
    // 2) Browser-native (no server, Chrome/Edge over localhost): use already-held handle or pick.
    if (!rb.supportsFS()) { this.bakeEl.innerHTML = `❌ No bake server. Run <code>python tools/skin_server.py</code> and open <b>localhost:8000</b> from it (recommended), or use Chrome/Edge.`; return; }
    let handle = this._romHandle, dir = this._romDir, name = this._romName;
    if (!handle) {
      // Not loaded yet — pick the GDI folder so we can auto-backup + bake.
      try {
        dir = await window.showDirectoryPicker({ mode: 'readwrite' });
        ({ handle, name } = await RomReader.findInDir(dir));
        this._romHandle = handle; this._romDir = dir; this._romName = name;
      } catch (e) { this.bakeEl.innerHTML = e?.name === 'AbortError' ? '<span class="dim">cancelled</span>' : `❌ ${e.message}`; return; }
    }
    name = name || handle.name;
    if (!confirm(`Bake directly into "${name}"?\nThis edits track03.bin IN PLACE. A one-time pristine "${name}.bak" backup is made next to it first. Close the ROM in flycast before baking.`)) { this.bakeEl.innerHTML = '<span class="dim">cancelled</span>'; return; }
    // Auto-backup: pristine <track>.bak next to the ROM (once). If it can't be written we
    // REFUSE to bake — better to stop than to risk an unrecoverable in-place edit.
    if (dir) {
      try {
        const bk = await rb.ensureBackup(dir, name, (d, t) => { this.bakeEl.innerHTML = `backing up ${(d / 1048576) | 0}/${(t / 1048576) | 0} MB…`; });
        this.bakeEl.innerHTML = bk.created ? `backup saved (${name}.bak) — baking…` : `backup exists (${name}.bak) — baking…`;
      } catch (e) {
        this.bakeEl.innerHTML = `❌ couldn't write backup (${e.message}) — NOT baking, to avoid an unrecoverable edit. Free disk space / check folder write permission and retry.`; return;
      }
    } else {
      this.bakeEl.innerHTML = '⚠ no folder handle — baking without auto-backup (use 📀 load ROM to enable it). Baking…';
    }
    try {
      if (await handle.queryPermission({ mode: 'readwrite' }) !== 'granted' && await handle.requestPermission({ mode: 'readwrite' }) !== 'granted')
        throw new Error('write permission denied for that file');
      const { edits, palEdits } = this._buildEdits();
      const res = await rb.bakeToTrack03(handle, `PL${HEX2(this.cid)}`, edits, palEdits);
      const bakNote = dir ? ` · backup: <code>${name}.bak</code>` : '';
      this.bakeEl.innerHTML = res.verified
        ? `✅ baked + verified into <code>${name}</code> — ${res.parts} part(s)${res.grew ? `, grew ${res.grew}B` : ''}${bakNote}. Load it in flycast.`
        : `⚠ wrote but verification FAILED (${res.diff} bytes differ) — file likely open in flycast/locked. Close it and bake again${dir ? ` (restore from ${name}.bak if needed)` : ''}.`;
    } catch (e) {
      const m = (e.name === 'NotAllowedError' || /not allowed/i.test(e.message || '')) ? 'browser blocked file access (open the page over http://localhost, not file://, in Chrome/Edge) — or just use the Python server bake' : (e.message || e);
      this.bakeEl.innerHTML = `❌ ${m}`;
    }
  }
}
