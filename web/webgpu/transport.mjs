// transport.mjs — Adaptive transport: WebTransport (QUIC/UDP) → WebSocket (TCP) fallback
// Provides unified API regardless of underlying transport.
// WebTransport: unreliable datagrams for delta frames, reliable stream for SYNC
// WebSocket: TCP fallback for browsers without WebTransport support

const WT_TIMEOUT = 3000; // ms to wait for WebTransport before falling back

export class AdaptiveTransport {
    constructor(opts = {}) {
        this.wsUrl = opts.wsUrl || null;       // wss://host/ws
        this.wtUrl = opts.wtUrl || null;       // https://host/webtransport
        this.onframe = opts.onframe || null;   // (Uint8Array) => void
        this.onopen = opts.onopen || null;
        this.onclose = opts.onclose || null;
        this.onstatus = opts.onstatus || null; // (string) => void — status updates

        this._ws = null;
        this._wt = null;
        this._wtReader = null;
        this._type = 'none';  // 'webtransport' | 'websocket' | 'none'
        this._closed = false;
        this._bytesIn = 0;
        this._framesIn = 0;
        this._connectTime = 0;

        // Stats
        this.stats = {
            type: 'none',
            bytesIn: 0,
            framesIn: 0,
            reconnects: 0,
        };
    }

    get type() { return this._type; }
    get connected() { return this._type !== 'none'; }

    async connect() {
        this._closed = false;
        this._connectTime = performance.now();

        // Try WebTransport first if available and URL provided
        if (this.wtUrl && typeof WebTransport !== 'undefined') {
            this._status('Trying WebTransport...');
            try {
                const ok = await this._tryWebTransport();
                if (ok) return;
            } catch (e) {
                this._status('WebTransport failed: ' + e.message);
            }
        }

        // Fall back to WebSocket
        if (this.wsUrl) {
            this._status('Connecting via WebSocket (TCP)...');
            this._connectWebSocket();
        }
    }

    async _tryWebTransport() {
        return new Promise(async (resolve) => {
            const timeout = setTimeout(() => {
                this._status('WebTransport timeout');
                resolve(false);
            }, WT_TIMEOUT);

            try {
                const wt = new WebTransport(this.wtUrl);
                await wt.ready;
                clearTimeout(timeout);

                this._wt = wt;
                this._type = 'webtransport';
                this.stats.type = 'webtransport (QUIC/UDP)';
                this._status('WebTransport connected!');

                // Read unreliable datagrams (delta frames)
                this._readDatagrams(wt);

                // Read reliable stream (SYNC packets)
                this._readStreams(wt);

                wt.closed.then(() => {
                    if (this._type === 'webtransport') {
                        this._type = 'none';
                        this.stats.type = 'none';
                        if (this.onclose) this.onclose();
                        if (!this._closed) this._reconnect();
                    }
                });

                if (this.onopen) this.onopen();
                resolve(true);
            } catch (e) {
                clearTimeout(timeout);
                resolve(false);
            }
        });
    }

    async _readDatagrams(wt) {
        try {
            const reader = wt.datagrams.readable.getReader();
            this._wtReader = reader;
            while (true) {
                const { value, done } = await reader.read();
                if (done) break;
                this._bytesIn += value.byteLength;
                this._framesIn++;
                this.stats.bytesIn = this._bytesIn;
                this.stats.framesIn = this._framesIn;
                if (this.onframe) this.onframe(new Uint8Array(value));
            }
        } catch (e) {
            // Transport closed
        }
    }

    async _readStreams(wt) {
        try {
            const reader = wt.incomingUnidirectionalStreams.getReader();
            while (true) {
                const { value: stream, done } = await reader.read();
                if (done) break;
                // Read entire stream (SYNC packet)
                const chunks = [];
                const sr = stream.getReader();
                while (true) {
                    const { value: chunk, done: sd } = await sr.read();
                    if (sd) break;
                    chunks.push(chunk);
                }
                // Concatenate and deliver
                const totalLen = chunks.reduce((s, c) => s + c.byteLength, 0);
                const data = new Uint8Array(totalLen);
                let off = 0;
                for (const c of chunks) { data.set(new Uint8Array(c), off); off += c.byteLength; }
                this._bytesIn += totalLen;
                this._framesIn++;
                this.stats.bytesIn = this._bytesIn;
                this.stats.framesIn = this._framesIn;
                if (this.onframe) this.onframe(data);
            }
        } catch (e) {
            // Transport closed
        }
    }

    _connectWebSocket() {
        const ws = new WebSocket(this.wsUrl);
        ws.binaryType = 'arraybuffer';
        this._ws = ws;

        ws.onopen = () => {
            this._type = 'websocket';
            this.stats.type = 'websocket (TCP)';
            this._status('WebSocket connected');
            if (this.onopen) this.onopen();
        };

        ws.onclose = () => {
            if (this._type === 'websocket') {
                this._type = 'none';
                this.stats.type = 'none';
                if (this.onclose) this.onclose();
                if (!this._closed) this._reconnect();
            }
        };

        ws.onerror = () => {};

        ws.onmessage = (e) => {
            if (typeof e.data === 'string') return; // Skip JSON control messages
            const data = new Uint8Array(e.data);
            this._bytesIn += data.byteLength;
            this._framesIn++;
            this.stats.bytesIn = this._bytesIn;
            this.stats.framesIn = this._framesIn;
            if (this.onframe) this.onframe(data);
        };
    }

    _reconnect() {
        this.stats.reconnects++;
        this._status('Reconnecting in 2s...');
        setTimeout(() => {
            if (!this._closed) this.connect();
        }, 2000);
    }

    send(data) {
        if (this._type === 'webtransport' && this._wt) {
            const writer = this._wt.datagrams.writable.getWriter();
            writer.write(data);
            writer.releaseLock();
        } else if (this._type === 'websocket' && this._ws && this._ws.readyState === WebSocket.OPEN) {
            this._ws.send(data);
        }
    }

    // Send gamepad input via QUIC datagram (lowest latency path)
    // Format: [0x49 'I'][slot][LT][RT][BTN_hi][BTN_lo] = 6 bytes
    // Falls back to controlWs TCP if WebTransport not available
    sendInput(slot, lt, rt, btnHi, btnLo) {
        if (this._type === 'webtransport' && this._wt) {
            const buf = new Uint8Array([0x49, slot, lt, rt, btnHi, btnLo]);
            try {
                const writer = this._wt.datagrams.writable.getWriter();
                writer.write(buf);
                writer.releaseLock();
                return true; // sent via QUIC
            } catch (e) {}
        }
        return false; // caller should fall back to controlWs
    }

    close() {
        this._closed = true;
        this._type = 'none';
        if (this._wt) { try { this._wt.close(); } catch(e) {} this._wt = null; }
        if (this._ws) { try { this._ws.close(); } catch(e) {} this._ws = null; }
    }

    _status(msg) {
        if (this.onstatus) this.onstatus(msg);
    }
}
