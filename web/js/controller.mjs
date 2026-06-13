// controller.mjs — direct-join gamepad input for the Oracle live page. Opens a control WS, joins a
// player slot, and streams the 4-byte input packet. Mirrors the proven webgpu-test flow (ensureControlWs
// + {type:'join'} + gamepad.mjs's exact button map) but self-contained — no matchmaking/queue deps.
// LOCAL instances: pass a local control URL (e.g. ws://localhost:PORT/play).
//
// Packet (4B over the control WS): [LT, RT, btn_hi, btn_lo]. btn is active-LOW (0xFFFF = nothing held).

const HEARTBEAT_MS = 5000;
const SID = 'oracle-' + (crypto.randomUUID ? crypto.randomUUID().slice(0, 12) : Math.random().toString(36).slice(2, 14));

export class Controller {
  constructor({ onStatus } = {}) {
    this.ws = null; this.slot = -1; this.raf = null;
    this.onStatus = onStatus || (() => {});
    this._last = [0xFF, 0xFF, 0xFF, 0xFF]; this._lastMs = 0;
  }

  // prod relay terminates the control WS at /play; in dev (served from :8000) default to prod relay.
  defaultUrl() {
    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const isProd = location.port === '' || location.port === '80' || location.port === '443';
    return isProd ? `${proto}//${location.hostname}/play` : 'wss://nobd.net/play';
  }

  connect(url) {
    return new Promise((res, rej) => {
      try { this.ws = new WebSocket(url); } catch (e) { return rej(e); }
      this.ws.binaryType = 'arraybuffer';
      const to = setTimeout(() => rej(new Error('control WS timeout')), 6000);
      this.ws.onopen = () => { clearTimeout(to); this.onStatus('control connected', 'ok'); res(this.ws); };
      this.ws.onclose = () => { this.slot = -1; this.stop(); this.onStatus('control closed', 'err'); };
      this.ws.onerror = () => { clearTimeout(to); this.onStatus('control error', 'err'); rej(new Error('control WS error')); };
    });
  }

  async join(slot, url, name) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) await this.connect(url || this.defaultUrl());
    const gp = navigator.getGamepads?.()[0];
    this.ws.send(JSON.stringify({
      type: 'join', id: SID, name: name || 'Oracle-' + SID.slice(7, 13),
      device: gp ? gp.id.substring(0, 30) : 'Browser', slot, latch_policy: 'latency',
    }));
    this.slot = slot; this.start();
    this.onStatus(`joined P${slot + 1} — press buttons`, 'ok');
  }

  leave() {
    try { if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify({ type: 'leave' })); } catch {}
    this.slot = -1; this.stop(); this.onStatus('left game', '');
  }

  // read the most-recently-active pad, build the packet (exact mapping from gamepad.mjs), send on change/heartbeat
  poll() {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN || this.slot < 0) return;
    const pads = navigator.getGamepads(); let gp = null, t = -1;
    for (const p of pads) if (p && p.timestamp > t) { t = p.timestamp; gp = p; }
    if (!gp) return;
    const B = gp.buttons, A = gp.axes || [];
    let btn = 0xFFFF;
    if (B[0]?.pressed) btn &= ~0x0004;                 // A  = LK
    if (B[1]?.pressed) btn &= ~0x0002;                 // B  = HK
    if (B[2]?.pressed) btn &= ~0x0400;                 // X  = LP
    if (B[3]?.pressed) btn &= ~0x0200;                 // Y  = HP
    if (B[9]?.pressed) btn &= ~0x0008;                 // Start
    if (B[12]?.pressed || A[1] < -0.5) btn &= ~0x0010; // Up
    if (B[13]?.pressed || A[1] > 0.5)  btn &= ~0x0020; // Down
    if (B[14]?.pressed || A[0] < -0.5) btn &= ~0x0040; // Left
    if (B[15]?.pressed || A[0] > 0.5)  btn &= ~0x0080; // Right
    let lt = Math.floor((B[6]?.value || 0) * 255), rt = Math.floor((B[7]?.value || 0) * 255);
    if (B[5]?.pressed) lt = 255;                       // RB → A1
    if (B[4]?.pressed) rt = 255;                       // LB → A2
    const pkt = [lt, rt, (btn >> 8) & 0xFF, btn & 0xFF];
    const now = performance.now();
    if (!pkt.some((v, i) => v !== this._last[i]) && now - this._lastMs < HEARTBEAT_MS) return;
    this._last = pkt; this._lastMs = now;
    if (this.ws.bufferedAmount < 8192) this.ws.send(new Uint8Array(pkt));
  }

  start() { if (this.raf) return; const tick = () => { this.poll(); this.raf = requestAnimationFrame(tick); }; this.raf = requestAnimationFrame(tick); }
  stop() { if (this.raf) { cancelAnimationFrame(this.raf); this.raf = null; } }

  // live pad-detect for the UI
  padId() { const p = navigator.getGamepads?.(); for (const g of (p || [])) if (g) return g.id; return null; }
}
