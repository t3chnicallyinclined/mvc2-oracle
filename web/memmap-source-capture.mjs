// memmap-source-capture.mjs — replay a recorded dirty-page stream (real or synthetic) so the radar
// shows real MVC2 churn with no live connection. Same onFrame interface as the synthetic/live sources.
//
// Capture format (JSON):
//   { meta: { source, base, page, recorded }, frames: [ [pageIdx, ...], [pageIdx, ...], ... ] }
// frames[i] is the dirty-page list for frame i. Record one from prod/dev via tools/record-memmap.mjs.

export class CaptureSource {
  constructor(capture) {
    const c = capture || {};
    this.meta = c.meta || {};
    this.frames = c.frames || [];
    this.i = 0;
    this._cb = () => {};
  }
  onFrame(cb) { this._cb = cb; }
  get length() { return this.frames.length; }
  get frame() { return this.i; }
  reset() { this.i = 0; }

  // Emit the next recorded frame. Returns false at end-of-capture.
  advance() {
    if (this.i >= this.frames.length) return false;
    const dirty = this.frames[this.i++];
    this._cb({ frameNum: this.i, dirty });
    return true;
  }

  // Scrub: rebuild state up to frame n by replaying 0..n. Caller resets the panel first.
  replayTo(n) {
    this.i = 0;
    const end = Math.max(0, Math.min(n, this.frames.length));
    for (let k = 0; k < end; k++) this.advance();
  }
}
