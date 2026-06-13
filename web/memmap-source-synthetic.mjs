// memmap-source-synthetic.mjs — a fake per-frame dirty-page source so the M1 radar runs with NO
// emulator. Emits {frameNum, dirty:[pageIdx]} via onFrame(cb); call advance() once per frame.
// The REAL source (the mirror wire / Oracle tail) implements the same onFrame interface and swaps in.
// Churn is shaped to look like a live match: globals + char structs hot every frame, object pool
// flickering, periodic decode-scratch bursts (asset decode), plus random scatter.

const RAM_BASE = 0x0C000000, PAGE = 4096, NUM_PAGES = 4096;
const pof = (a) => ((a - RAM_BASE) / PAGE) | 0;

// deterministic LCG so stepping is reproducible (no Math.random)
const rnd = (s) => ((s * 1103515245 + 12345) >>> 0);

export class SyntheticSource {
  constructor() { this.frame = 0; this._cb = () => {}; }
  onFrame(cb) { this._cb = cb; }

  advance() {
    const f = ++this.frame;
    const dirty = new Set();

    // always changing: globals (timers) + the frame counter
    dirty.add(pof(0x0C289000));
    dirty.add(pof(0x0C3496B0));

    // char structs — positions/anim tick most frames
    dirty.add(pof(0x0C268340));
    dirty.add(pof(0x0C268340) + 1);
    dirty.add(pof(0x0C2699D0));

    // object pool — projectile/effect churn ~35% of frames, 1–3 pages
    if (rnd(f) % 100 < 35) {
      const base = pof(0x0C26AA54), span = 12, n = 1 + ((f >>> 1) % 3);
      for (let i = 0; i < n; i++) dirty.add(base + ((f * 7 + i * 13) % span));
    }

    // decode-scratch burst every ~150 frames (asset decode into 0x0CE60000)
    if (f % 150 < 6) {
      const base = pof(0x0CE60000);
      for (let i = 0; i < 8; i++) dirty.add(base + ((f * 3 + i) % 24));
    }

    // random scatter (stack / misc), 2–5 pages
    const ns = 2 + (f % 4);
    let s = f;
    for (let i = 0; i < ns; i++) { s = rnd(s + i); dirty.add(s % NUM_PAGES); }

    this._cb({ frameNum: f, dirty: [...dirty] });
  }
}
