// frame-decoder.mjs — ZCST decompress, SYNC/FSYN handling, delta frame apply
// Mirrors wasm_bridge.cpp exactly including all 5 documented bugs.

import { decompress } from './fzstd.mjs';

const VRAM_SIZE = 8 * 1024 * 1024;
const PVR_REG_SIZE = 32 * 1024;
const PAGE_SIZE = 4096;
const MAGIC_ZCST = 0x5453435A;
const MAGIC_SYNC = 0x434E5953;
const MAGIC_FSYN = 0x4E595346;
const MAGIC_SAVE = 0x45564153;

export class FrameDecoder {
    constructor() {
        this.vram = new Uint8Array(VRAM_SIZE);
        this.pvrRegs = new Uint8Array(PVR_REG_SIZE);
        this.prevTA = new Uint8Array(0);
        this.prevTASize = 0;
        this.hasPrevTA = false;
        this.frameNum = 0;
        this.stats = { syncs: 0, keyframes: 0, deltas: 0, dropped: 0 };
        // VCACHE (content-addressed VRAM, env MAPLECAST_VCACHE): persistent
        // hash->page cache. Keyed by the u64 content hash as a "lo:hi" hex string
        // (avoids BigInt churn). A reference page (hasData==0) is filled from here.
        // Cleared on every SYNC/FSYN — a SYNC replaces the entire VRAM, so any
        // cached page identity from the prior scene is invalid.
        this._vcache = new Map();
        this._vcacheMissLogged = false;
    }

    _decompress(data) {
        const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
        if (data.length >= 8 && view.getUint32(0, true) === MAGIC_ZCST) {
            return decompress(data.subarray(8));
        }
        return data;
    }

    applySync(rawData) {
        const data = this._decompress(new Uint8Array(rawData));
        const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
        if (data.length < 8) return false;
        const magic = view.getUint32(0, true);

        if (magic === MAGIC_FSYN) {
            let off = 4;
            const recordCount = view.getUint16(off + 2, true); off += 4;
            for (let r = 0; r < recordCount && off + 8 <= data.length; r++) {
                const tag = String.fromCharCode(data[off], data[off+1], data[off+2], data[off+3]); off += 4;
                const recSize = view.getUint32(off, true); off += 4;
                if (off + recSize > data.length) break;
                if (tag === 'VRAM') this.vram.set(data.subarray(off, off + Math.min(recSize, VRAM_SIZE)));
                else if (tag === 'PREG') this.pvrRegs.set(data.subarray(off, off + Math.min(recSize, PVR_REG_SIZE)));
                off += recSize;
            }
            this.prevTA = new Uint8Array(0); this.prevTASize = 0; this.hasPrevTA = false;
            if (this._vcache) this._vcache.clear();   // full VRAM replace -> cached page identities invalid
            this.stats.syncs++;
            return true;
        }
        if (magic === MAGIC_SAVE) return true;
        if (magic !== MAGIC_SYNC) return false;

        let off = 4;
        const vramSize = Math.min(view.getUint32(off, true), VRAM_SIZE); off += 4;
        this.vram.set(data.subarray(off, off + vramSize)); off += vramSize;
        const pvrSize = Math.min(view.getUint32(off, true), PVR_REG_SIZE); off += 4;
        this.pvrRegs.set(data.subarray(off, off + pvrSize));
        this.prevTA = new Uint8Array(0); this.prevTASize = 0; this.hasPrevTA = false;
        if (this._vcache) this._vcache.clear();   // full VRAM replace -> cached page identities invalid
        this.stats.syncs++;
        return true;
    }

    applyFrame(rawData) {
        const data = this._decompress(new Uint8Array(rawData));
        const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
        if (data.length < 80) return null;

        const maybeMagic = view.getUint32(0, true);
        // Non-TA frames ride the same broadcast: GSTA (game state) and EFCT (isolated
        // effect quads). Each page dispatches these itself; reaching here they'd
        // misparse as a delta frame and throw. Bail cleanly so EVERY client (incl.
        // king.html via renderer-bridge) is safe. LE u32: 'GSTA'=0x41545347, 'EFCT'=0x54434645
        if (maybeMagic === 0x41545347 || maybeMagic === 0x54434645 || maybeMagic === 0x52545854 || maybeMagic === 0x534A424F) return null; // GSTA/EFCT/TXTR/OBJS
        // CHRQ (per-part PVR sprite quads) and STAF (stripped-TA quad list) ride the SAME
        // mirror stream as TA deltas. If one reaches here (e.g. the caller's magic-peek
        // diversion was bypassed), reading its header as a delta frame yields a bogus
        // multi-GB taSize -> `new Uint8Array(taSize)` throws RangeError and stalls the
        // stream. Bail cleanly instead. LE u32: 'CHRQ'=0x51524843, 'STAF'=0x46415453.
        if (maybeMagic === 0x51524843 || maybeMagic === 0x46415453) return null; // CHRQ/STAF
        if (maybeMagic === MAGIC_SYNC || maybeMagic === MAGIC_FSYN || maybeMagic === MAGIC_SAVE) {
            this.applySync(rawData);
            // A SYNC replaces the ENTIRE VRAM, but carries no dirty-page list — so any
            // texture decoded earlier (from pre-SYNC / partial VRAM, e.g. the stage
            // background) is now stale and would never refresh. Signal the caller to
            // invalidate the texture cache ONCE (the proper fix for the missing
            // background, instead of texForceInvalidate re-decoding every frame).
            this.syncPending = true;
            return null;
        }

        let off = 0;
        const frameSize = view.getUint32(off, true); off += 4;
        const frameNum = view.getUint32(off, true); off += 4;
        this.frameNum = frameNum;

        const pvrSnapshot = new Uint32Array(16);
        for (let i = 0; i < 16; i++) { pvrSnapshot[i] = view.getUint32(off, true); off += 4; }

        const taSize = view.getUint32(off, true); off += 4;
        const deltaPayloadSize = view.getUint32(off, true); off += 4;
        let skipRender = false;

        if (deltaPayloadSize === taSize) {
            if (this.prevTA.length < taSize) { const n = new Uint8Array(taSize); n.set(this.prevTA); this.prevTA = n; }
            this.prevTA.set(data.subarray(off, off + taSize));
            this.prevTASize = taSize; this.hasPrevTA = true;
            off += taSize; this.stats.keyframes++;
        } else if (!this.hasPrevTA) {
            off += deltaPayloadSize; skipRender = true; this.stats.dropped++;
        } else {
            if (this.prevTA.length < taSize) { const n = new Uint8Array(taSize); n.set(this.prevTA); this.prevTA = n; }
            this.prevTASize = taSize;
            const deltaEnd = off + deltaPayloadSize;
            while (off + 4 <= deltaEnd) {
                const doff = view.getUint32(off, true); off += 4;
                if (doff === 0xFFFFFFFF) break;
                const runLen = view.getUint16(off, true); off += 2;
                if (doff + runLen <= taSize && off + runLen <= deltaEnd) this.prevTA.set(data.subarray(off, off + runLen), doff);
                off += runLen;
            }
            off = deltaEnd - deltaPayloadSize + deltaPayloadSize;  // ensure we're past delta
            this.stats.deltas++;
        }

        off += 4; // skip checksum

        let dirtyPages = view.getUint32(off, true); off += 4;
        let vramDirty = false, pvrDirty = false;
        const dirtyPageList = [];

        // VCACHE branch (env MAPLECAST_VCACHE): the count slot is the sentinel
        // 0xFFFFFFFF, followed by the real count, and each page carries a u64
        // content hash + a hasData flag. hasData==1 => 4096 bytes follow (apply +
        // cache by hash); hasData==0 => reference, fill from this._vcache[hash].
        // The result is byte-identical to a standard delta frame, so everything
        // downstream (texture-manager invalidation via dirtyPageList, pvr2-renderer)
        // is untouched. See maplecast_mirror.cpp:2045-2102, sentinel :1595.
        if (dirtyPages === 0xFFFFFFFF) {
            dirtyPages = view.getUint32(off, true); off += 4;
            for (let d = 0; d < dirtyPages; d++) {
                const regionId = data[off]; off += 1;
                const pageIdx = view.getUint32(off, true); off += 4;
                const hLo = view.getUint32(off, true), hHi = view.getUint32(off + 4, true); off += 8;
                const hasData = data[off]; off += 1;
                const key = hLo.toString(16) + ':' + hHi.toString(16);
                let pageBytes;
                if (hasData) {
                    pageBytes = data.subarray(off, off + PAGE_SIZE); off += PAGE_SIZE;
                    this._vcache.set(key, pageBytes.slice());   // copy: data buffer is reused
                } else {
                    pageBytes = this._vcache.get(key);          // reference: fill from cache
                    if (!pageBytes) {                            // miss (shouldn't happen post-SYNC)
                        if (!this._vcacheMissLogged) { console.warn('[VCACHE] cache miss for ref page', key, '- skipping'); this._vcacheMissLogged = true; }
                        continue;
                    }
                }
                const pageOff = pageIdx * PAGE_SIZE;
                if (regionId === 1 && pageOff + PAGE_SIZE <= VRAM_SIZE) {
                    this.vram.set(pageBytes, pageOff);
                    vramDirty = true;
                    dirtyPageList.push(pageIdx);
                } else if (regionId === 3 && pageOff + PAGE_SIZE <= PVR_REG_SIZE) {
                    this.pvrRegs.set(pageBytes, pageOff);
                    pvrDirty = true;
                }
            }
        } else {
            for (let d = 0; d < dirtyPages; d++) {
                const regionId = data[off]; off += 1;
                const pageIdx = view.getUint32(off, true); off += 4;
                const pageOff = pageIdx * PAGE_SIZE;
                if (regionId === 1 && pageOff + PAGE_SIZE <= VRAM_SIZE) {
                    this.vram.set(data.subarray(off, off + PAGE_SIZE), pageOff);
                    vramDirty = true;
                    dirtyPageList.push(pageIdx);
                } else if (regionId === 3 && pageOff + PAGE_SIZE <= PVR_REG_SIZE) {
                    this.pvrRegs.set(data.subarray(off, off + PAGE_SIZE), pageOff);
                    pvrDirty = true;
                }
                off += PAGE_SIZE;
            }
        }

        if (skipRender) return null;
        return { frameNum, pvrSnapshot, taBuffer: this.prevTA.subarray(0, this.prevTASize), taSize: this.prevTASize, vramDirty, pvrDirty, dirtyPageList };
    }
}
