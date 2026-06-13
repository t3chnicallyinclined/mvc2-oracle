// sprite-preview.mjs — click-to-decode REPLAY MVP (Canvas2D, per the sprite-render expert's Spec 2).
// Given {cid, sprite_id} (+ optional captured sprite_id history) render the object's sprite from the
// atlas (PLxx.{json,png}) and replay its animation. Canvas2D is the smallest viable path: a single
// ctx.drawImage(atlas, sp.x,sp.y,sp.w,sp.h -> centered) — byte-faithful for baked-RGB atlases, no WebGPU
// device, no SpriteClient. Degrades gracefully when no atlas is present (shows the decoded id + a box).

const HEX2 = (n) => n.toString(16).toUpperCase().padStart(2, '0');

export class SpritePreview {
  constructor(canvas, { atlasBase = './test-atlas/chars' } = {}) {
    this.canvas = canvas; this.ctx = canvas.getContext('2d');
    this.atlasBase = atlasBase;
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
    const { ctx, canvas } = this;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = '#000'; ctx.fillRect(0, 0, canvas.width, canvas.height);
    const sp = c.missing ? null : c.sprites[String(sid)];
    if (sp) {
      const sx = canvas.width / c.screenW, sy = canvas.height / c.screenH, S = 1;
      const gx = canvas.width / 2, gy = canvas.height * 0.62;     // foot-ish anchor
      const dw = sp.wG * S * sx, dh = sp.hG * S * sy;
      const dx = gx + sp.dx * S * sx, dy = gy + sp.dy * S * sy;
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(c.img, sp.x, sp.y, sp.w, sp.h, dx, dy, dw, dh);
      this._held = sp;
    } else if (this._held && !c.missing) {
      const h = this._held, sx = canvas.width / c.screenW, sy = canvas.height / c.screenH;
      ctx.globalAlpha = 0.4;
      ctx.drawImage(c.img, h.x, h.y, h.w, h.h, canvas.width/2 + h.dx*sx, canvas.height*0.62 + h.dy*sy, h.wG*sx, h.hG*sy);
      ctx.globalAlpha = 1;
    } else {
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
  stop() { if (this._timer) { clearInterval(this._timer); this._timer = null; } }
}
