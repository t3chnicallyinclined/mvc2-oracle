// struct-panel.mjs — FIELD-RESOLUTION view of the 6 character structs (0x5A4 each), the granularity
// the linked view needs (page heat can't separate sub-page structs). Each struct is a 38x38 byte grid;
// per-frame changed offsets flare in the slot's identity color ("owned + changed"). The engine-owned
// pointer cluster (+0x154..+0x184) rewrites every frame, so it's drawn striped/demoted as noise.
// Driven by any source emitting { slots: [ { changed: [[off,len],...] } ] }.

export const STRIDE = 0x5A4;                       // 1444 bytes per char struct
export const GW = 38;                              // grid width (38*38 = 1444)
export const SLOT_BASES = [0x8C268340, 0x8C2688E4, 0x8C268E88, 0x8C26942C, 0x8C2699D0, 0x8C269F74];
export const SLOT_NAMES = ['P1C1', 'P2C1', 'P1C2', 'P2C2', 'P1C3', 'P2C3'];
export const SLOT_COLORS = [
  [ 80, 180, 255],  // P1C1 blue
  [255,  90,  90],  // P2C1 red
  [ 90, 220, 140],  // P1C2 green
  [255, 170,  60],  // P2C2 orange
  [200, 120, 255],  // P1C3 purple
  [255, 225,  80],  // P2C3 yellow
];
export const ENGINE = [0x154, 0x184];              // engine-owned pointer cluster — frame-noise

// known fields within the 0x5A4 struct (for hover labels)
const FIELDS = [
  [0x000,1,'active'],[0x001,1,'char_id'],[0x025,1,'palette'],[0x034,4,'pos_x'],[0x038,4,'pos_y'],
  [0x050,4,'scale_x'],[0x054,4,'scale_y'],[0x0E0,4,'screen_x'],[0x0E4,4,'screen_y'],[0x110,1,'facing'],
  [0x142,2,'anim_timer'],[0x144,2,'sprite_id'],[0x14A,2,'anim_flags'],[0x151,1,'RenderExtra'],
  [0x154,0x30,'engine ptr cluster'],[0x1D0,2,'anim_state'],[0x1D2,1,'xflip'],[0x420,1,'health'],[0x424,1,'red_health'],
];
export function fieldAt(off){ for (const [o,l,n] of FIELDS) if (off>=o && off<o+l) return n; return null; }
const inEngine = (off) => off >= ENGINE[0] && off < ENGINE[1];

export class StructPanel {
  constructor(canvas, { cell = 5, gap = 26, labelH = 18, pad = 10, cols = 3 } = {}) {
    this.canvas = canvas; this.ctx = canvas.getContext('2d');
    this.cell = cell; this.gap = gap; this.labelH = labelH; this.pad = pad; this.cols = cols;
    this.structW = GW * cell;
    this.heat = new Float32Array(6 * STRIDE);
    this.count = new Uint32Array(6 * STRIDE);
    this.decayRate = 0.85;
    this.selected = -1;
    this._origins = this._layout();
    this.render();
  }
  _layout() {
    const o = [], { structW, gap, labelH, pad, cols } = this;
    for (let s = 0; s < 6; s++) {
      const c = s % cols, r = (s / cols) | 0;
      o[s] = { x: pad + c * (structW + gap), y: pad + r * (structW + labelH + gap) + labelH };
    }
    return o;
  }
  setSource(src) { src.onFrame((f) => this.step(f)); }
  setSelected(slot) { this.selected = slot; this.render(); }
  reset() { this.heat.fill(0); this.count.fill(0); this.render(); }

  step(frame) {
    const h = this.heat, d = this.decayRate;
    for (let i = 0; i < h.length; i++) h[i] *= d;
    (frame.slots || []).forEach((sl, s) => {
      for (const [off, len] of (sl.changed || [])) {
        for (let b = off; b < off + len && b < STRIDE; b++) { h[s*STRIDE + b] = 1; this.count[s*STRIDE + b]++; }
      }
    });
    this.render();
  }

  render() {
    const { ctx, cell, structW, labelH } = this;
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    for (let s = 0; s < 6; s++) {
      const org = this._origins[s], full = SLOT_COLORS[s];
      const dim = [full[0]*0.22|0, full[1]*0.22|0, full[2]*0.22|0];
      // label
      ctx.fillStyle = `rgb(${full[0]},${full[1]},${full[2]})`;
      ctx.font = '11px ui-monospace,monospace';
      ctx.fillText(`${SLOT_NAMES[s]}  0x${SLOT_BASES[s].toString(16).toUpperCase()}`, org.x, org.y - 5);
      // bytes
      for (let off = 0; off < STRIDE; off++) {
        const k = this.heat[s*STRIDE + off];
        let r, g, b;
        if (inEngine(off)) {                 // demoted striped noise
          const base = 64 + (off & 1 ? 14 : 0);
          r = base + (150-base)*k*0.4; g = base + (150-base)*k*0.4; b = base+8 + (165-base)*k*0.4;
        } else {
          r = dim[0] + (full[0]-dim[0])*k; g = dim[1] + (full[1]-dim[1])*k; b = dim[2] + (full[2]-dim[2])*k;
          r += (255-r)*k*0.3; g += (255-g)*k*0.3; b += (255-b)*k*0.3;   // whiten at peak
        }
        ctx.fillStyle = `rgb(${r|0},${g|0},${b|0})`;
        ctx.fillRect(org.x + (off % GW)*cell, org.y + ((off / GW)|0)*cell, cell, cell);
      }
      // selection outline
      if (this.selected === s) {
        ctx.strokeStyle = `rgb(${full[0]},${full[1]},${full[2]})`; ctx.lineWidth = 2;
        ctx.strokeRect(org.x-2, org.y-2, GW*cell+4, Math.ceil(STRIDE/GW)*cell+4);
      }
    }
  }

  locate(clientX, clientY) {
    const rect = this.canvas.getBoundingClientRect();
    const px = (clientX-rect.left) * (this.canvas.width/rect.width);
    const py = (clientY-rect.top) * (this.canvas.height/rect.height);
    const { cell, structW } = this, gh = Math.ceil(STRIDE/GW)*cell;
    for (let s = 0; s < 6; s++) {
      const o = this._origins[s];
      if (px>=o.x && px<o.x+structW && py>=o.y && py<o.y+gh) {
        const off = (((py-o.y)/cell)|0)*GW + (((px-o.x)/cell)|0);
        if (off >= 0 && off < STRIDE) return { slot: s, off };
      }
    }
    return null;
  }
  info(slot, off) {
    return {
      slot, slotName: SLOT_NAMES[slot], addr: SLOT_BASES[slot] + off, off,
      field: fieldAt(off) || (inEngine(off) ? 'engine ptr cluster' : 'unlabeled'),
      heat: this.heat[slot*STRIDE + off], writes: this.count[slot*STRIDE + off],
      engine: inEngine(off),
    };
  }
}
