// sprite-preview.mjs — click-to-decode REPLAY MVP (Canvas2D, per the sprite-render expert's Spec 2).
// Given {cid, sprite_id} (+ optional captured sprite_id history) render the object's sprite from the
// atlas (PLxx.{json,png}) and replay its animation. Canvas2D is the smallest viable path: a single
// ctx.drawImage(atlas, sp.x,sp.y,sp.w,sp.h -> centered) — byte-faithful for baked-RGB atlases, no WebGPU
// device, no SpriteClient. Degrades gracefully when no atlas is present (shows the decoded id + a box).

const HEX2 = (n) => n.toString(16).toUpperCase().padStart(2, '0');

export class SpritePreview {
  constructor(canvas, { atlasBase = './test-atlas/chars', scale = 1 } = {}) {
    this.canvas = canvas; this.ctx = canvas.getContext('2d');
    this.atlasBase = atlasBase;
    this.scale = scale;       // 1 = native game-rendered size (1:1 atlas pixels)
    this.chars = {};          // cid -> { img, sprites, name, screenW, screenH } | { missing:true }
    this._timer = null; this._held = null;
  }

  // lazy-load PL{HEX}.{json,png}; resolves to a char record or {missing:true} (graceful)
  async loadChar(cid) {
    if (this.chars[cid]) return this.chars[cid];
    try {
      const base = `${this.atlasBase}/PL${HEX2(cid)}`;
      const json = await (await fetch(`${base}.json`)).json();
      const img = await createImageBitmap(await (await fetch(`${base}.png`)).blob());
      this.chars[cid] = { img, sprites: json.sprites, name: json.name, screenW: json.screenW || 640, screenH: json.screenH || 480 };
    } catch { this.chars[cid] = { missing: true }; }
    return this.chars[cid];
  }

  // render one pose. Centers the sprite (synthetic screen_x = screenW/2 - sp.dx -> gx = screenW/2),
  // mirroring buildDrawList's own dx/dy/wG/hG math (no hand-rolled geometry).
  async show(cid, sid, info) {
    const c = await this.loadChar(cid);
    const { ctx, canvas } = this, S = this.scale || 1;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = '#000'; ctx.fillRect(0, 0, canvas.width, canvas.height);
    const sp = c.missing ? null : c.sprites[String(sid)];
    // object origin = bottom-center; draw at NATIVE game pixels (1:1), anchored by own-origin dx/dy
    const draw = (s, a = 1) => {
      const gx = canvas.width / 2, gy = canvas.height - 24;
      ctx.globalAlpha = a; ctx.imageSmoothingEnabled = false;
      ctx.drawImage(c.img, s.x, s.y, s.w, s.h,
        Math.round(gx + s.dx * S), Math.round(gy + s.dy * S), s.w * S, s.h * S);
      ctx.globalAlpha = 1;
    };
    if (sp) { draw(sp); this._held = sp; }
    else if (this._held && !c.missing) { draw(this._held, 0.4); }
    else {
      // graceful no-atlas: a placeholder box + the decoded identity (still useful)
      ctx.strokeStyle = '#3a3f4b'; ctx.setLineDash([4, 4]);
      ctx.strokeRect(canvas.width/2 - 30, canvas.height/2 - 45, 60, 90); ctx.setLineDash([]);
      ctx.fillStyle = '#7f8593'; ctx.font = '11px ui-monospace,monospace'; ctx.textAlign = 'center';
      ctx.fillText('no atlas', canvas.width/2, canvas.height/2 - 56);
      ctx.textAlign = 'left';
    }
    // caption
    ctx.fillStyle = '#d7dae2'; ctx.font = '11px ui-monospace,monospace';
    const nm = info?.charName || (c.name) || `PL${HEX2(cid)}`;
    ctx.fillText(`${nm}  sid=0x${(sid & 0x7fff).toString(16).toUpperCase()}${sp ? '' : sp === null && !c.missing ? '  (held)' : ''}`, 6, canvas.height - 8);
    return !!sp;
  }

  // replay a captured sprite_id history at `fps`; sparse poses hold the previous frame
  replay(cid, history, info, fps = 30) {
    this.stop();
    let i = 0;
    const tick = () => { const sid = history[i % history.length] & 0x7fff; this.show(cid, sid, info); i++; };
    tick();
    this._timer = setInterval(tick, 1000 / fps);
  }

  // CANONICAL mode: play an animation's cell list, each cell held for `duration` game frames.
  // cells = [{sprite_id, duration, ender}]; 0xFFFF = blank (hold). speed scales playback (1 = 60fps).
  playAnim(cid, cells, info, speed = 1) {
    this.stop();
    if (!cells || !cells.length) return;
    let ci = 0, held = 0;
    const tick = () => {
      const cell = cells[ci % cells.length];
      if (held === 0 && cell.sprite_id !== 0xFFFF) this.show(cid, cell.sprite_id & 0x7fff, info);
      if (++held >= Math.max(1, cell.duration)) { held = 0; ci++; }
    };
    tick();
    this._timer = setInterval(tick, (1000 / 60) / speed);   // one game frame per tick
  }
  stop() { if (this._timer) { clearInterval(this._timer); this._timer = null; } }

  // Capture an animation's cells into frames for export. Tight bbox over all cells, transparent bg,
  // native size; 0xFFFF holds the previous frame. -> { frames:[RGBA bytes], w, h, delaysCs:[centisec] }
  async captureAnim(cid, cells) {
    const c = await this.loadChar(cid);
    if (c.missing) return null;
    const S = this.scale || 1;
    const real = cells.filter((k) => k.sprite_id !== 0xFFFF).map((k) => c.sprites[String(k.sprite_id & 0x7fff)]).filter(Boolean);
    if (!real.length) return null;
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const s of real) { minX = Math.min(minX, s.dx); minY = Math.min(minY, s.dy); maxX = Math.max(maxX, s.dx + s.w); maxY = Math.max(maxY, s.dy + s.h); }
    const w = Math.max(1, Math.ceil((maxX - minX) * S)), h = Math.max(1, Math.ceil((maxY - minY) * S));
    const oc = (typeof OffscreenCanvas !== 'undefined') ? new OffscreenCanvas(w, h) : Object.assign(document.createElement('canvas'), { width: w, height: h });
    const ox = oc.getContext('2d'); ox.imageSmoothingEnabled = false;
    const frames = [], delaysCs = []; let last = null;
    for (const cell of cells) {
      const cs = Math.max(1, Math.round(cell.duration * 100 / 60));
      if (cell.sprite_id === 0xFFFF) { if (last) { frames.push(last); delaysCs.push(cs); } continue; }
      const s = c.sprites[String(cell.sprite_id & 0x7fff)]; if (!s) continue;
      ox.clearRect(0, 0, w, h);
      ox.drawImage(c.img, s.x, s.y, s.w, s.h, Math.round((s.dx - minX) * S), Math.round((s.dy - minY) * S), s.w * S, s.h * S);
      last = ox.getImageData(0, 0, w, h).data;
      frames.push(last); delaysCs.push(cs);
    }
    return frames.length ? { frames, w, h, delaysCs } : null;
  }
}
