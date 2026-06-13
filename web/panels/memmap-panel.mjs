// memmap-panel.mjs — M1 memory-map activity radar.
// Self-contained Canvas2D heat renderer with a pluggable data source. The source emits per-frame
// dirty-page sets ({frameNum, dirty:[pageIdx]}); the panel keeps a decaying heat buffer and paints
// a 64x64 page grid (4 KB/page over 16 MB main RAM). Known regions are tinted so structure shows.
// Production scale-up (WebGPU + Hilbert layout) comes later; the source interface stays the same.

export const RAM_BASE = 0x0C000000;          // main RAM (cached mirror 0x8C000000)
export const PAGE     = 4096;                // dirty-page granularity (matches the mirror wire)
export const NUM_PAGES = (16 * 1024 * 1024) / PAGE;  // 4096 pages
export const GRID     = 64;                  // 64 x 64 = 4096 cells, linear row-major

// MVP subset of the MVC2 memory map (physical 0x0C… addresses) for region tint + labels.
export const REGIONS = [
  { name: 'char structs',   start: 0x0C268000, end: 0x0C26A800, rgb: [ 0, 190, 210] },
  { name: 'object pool',    start: 0x0C26AA00, end: 0x0C276600, rgb: [ 70, 200,  90] },
  { name: 'globals',        start: 0x0C289000, end: 0x0C28A000, rgb: [210,  90, 200] },
  { name: 'engine work',    start: 0x0C349000, end: 0x0C34A000, rgb: [205,  70,  70] },
  { name: 'SPL overlay',    start: 0x0CE30000, end: 0x0CE60000, rgb: [ 90, 130, 235] },
  { name: 'decode scratch', start: 0x0CE60000, end: 0x0CE82000, rgb: [225, 145,  45] },
];
const UNKNOWN_RGB = [42, 44, 54];
const HOT_RGB     = [255, 232, 120];

export const pageAddr = (p) => RAM_BASE + p * PAGE;
export function regionOf(addr) {
  for (const r of REGIONS) if (addr >= r.start && addr < r.end) return r;
  return null;
}

export class MemMap {
  constructor(canvas, { decay = 0.90 } = {}) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.decayRate = decay;
    this.cell = Math.floor(canvas.width / GRID);
    this.heat = new Float32Array(NUM_PAGES);
    this.lastWrite = new Int32Array(NUM_PAGES).fill(-1);
    this.count = new Uint32Array(NUM_PAGES);
    this.frameNum = 0;
    this._tint = this._precomputeTints();
    this.render();
  }

  _precomputeTints() {
    const t = new Array(NUM_PAGES);
    for (let p = 0; p < NUM_PAGES; p++) {
      const c = (regionOf(pageAddr(p)) || { rgb: UNKNOWN_RGB }).rgb;
      t[p] = [(c[0] * 0.28) | 0, (c[1] * 0.28) | 0, (c[2] * 0.28) | 0]; // dim base so hot pops
    }
    return t;
  }

  setDecay(d) { this.decayRate = d; }
  setSource(src) { src.onFrame((f) => this.step(f)); }

  // Clear all state (used when swapping sources or scrubbing a capture from the start).
  reset() {
    this.heat.fill(0);
    this.lastWrite.fill(-1);
    this.count.fill(0);
    this.frameNum = 0;
    this.render();
  }

  // One frame: decay all heat, then mark dirty pages hot, then paint.
  step(frame) {
    this.frameNum = frame.frameNum;
    const h = this.heat, d = this.decayRate;
    for (let p = 0; p < NUM_PAGES; p++) h[p] *= d;
    for (const p of (frame.dirty || [])) {
      if (p >= 0 && p < NUM_PAGES) { h[p] = 1; this.lastWrite[p] = frame.frameNum; this.count[p]++; }
    }
    this.render();
  }

  render() {
    const { ctx, cell, heat, _tint } = this;
    for (let p = 0; p < NUM_PAGES; p++) {
      const x = (p % GRID) * cell, y = ((p / GRID) | 0) * cell;
      const b = _tint[p], k = heat[p];
      const r = (b[0] + (HOT_RGB[0] - b[0]) * k) | 0;
      const g = (b[1] + (HOT_RGB[1] - b[1]) * k) | 0;
      const bl = (b[2] + (HOT_RGB[2] - b[2]) * k) | 0;
      ctx.fillStyle = `rgb(${r},${g},${bl})`;
      ctx.fillRect(x, y, cell, cell);
    }
  }

  pageAt(clientX, clientY) {
    const rect = this.canvas.getBoundingClientRect();
    const cx = Math.floor((clientX - rect.left) * (this.canvas.width / rect.width) / this.cell);
    const cy = Math.floor((clientY - rect.top) * (this.canvas.height / rect.height) / this.cell);
    if (cx < 0 || cy < 0 || cx >= GRID || cy >= GRID) return -1;
    return cy * GRID + cx;
  }

  info(p) {
    if (p < 0 || p >= NUM_PAGES) return null;
    const addr = pageAddr(p);
    const r = regionOf(addr);
    return {
      page: p,
      addrStart: addr, addrEnd: addr + PAGE,
      region: r ? r.name : 'unknown',
      heat: this.heat[p],
      writeCount: this.count[p],
      lastWrite: this.lastWrite[p],
    };
  }
}
