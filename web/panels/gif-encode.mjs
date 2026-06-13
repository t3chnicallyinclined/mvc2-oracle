// gif-encode.mjs — minimal animated GIF89a encoder, no deps. Built for sprite animations:
// palette from the frames (index 0 = transparent), per-frame delay, loops forever, disposal=restore-bg
// so transparency works frame-to-frame. frames = [Uint8ClampedArray RGBA, all w*h]; delaysCs = centiseconds.

function buildPalette(frames) {
  const map = new Map();                 // (r<<16|g<<8|b) -> palette index
  const pal = [[0, 0, 0]];               // index 0 reserved = transparent
  for (const f of frames) for (let i = 0; i < f.length; i += 4) {
    if (f[i + 3] < 128) continue;
    const key = (f[i] << 16) | (f[i + 1] << 8) | f[i + 2];
    if (!map.has(key) && pal.length < 256) { map.set(key, pal.length); pal.push([f[i], f[i + 1], f[i + 2]]); }
  }
  const nearest = (r, g, b) => {         // fallback if >255 colors
    let best = 1, bd = 1e9;
    for (let i = 1; i < pal.length; i++) { const p = pal[i], d = (p[0]-r)**2+(p[1]-g)**2+(p[2]-b)**2; if (d < bd) { bd = d; best = i; } }
    return best;
  };
  return { pal, idx: (r, g, b, a) => a < 128 ? 0 : (map.get((r << 16) | (g << 8) | b) ?? nearest(r, g, b)) };
}

// LZW-min compress an index array -> byte array (GIF variable-width codes, LSB-first)
function lzw(indices, minCode) {
  const clear = 1 << minCode, eoi = clear + 1;
  let dict, next, size, cur = 0, bits = 0; const out = [];
  const reset = () => { dict = new Map(); for (let i = 0; i < clear; i++) dict.set(String.fromCharCode(i), i); next = eoi + 1; size = minCode + 1; };
  const emit = (code) => { cur |= code << bits; bits += size; while (bits >= 8) { out.push(cur & 255); cur >>= 8; bits -= 8; } };
  reset(); emit(clear);
  let w = '';
  for (const k of indices) {
    const c = String.fromCharCode(k), wc = w + c;
    if (dict.has(wc)) { w = wc; continue; }
    emit(dict.get(w)); dict.set(wc, next++);
    if (next - 1 === (1 << size) && size < 12) size++;
    if (next === 4096) { emit(clear); reset(); }
    w = c;
  }
  emit(dict.get(w)); emit(eoi);
  if (bits > 0) out.push(cur & 255);
  return out;
}

function subBlocks(bytes) {              // split LZW stream into <=255-byte sub-blocks, 0x00 terminator
  const out = [];
  for (let i = 0; i < bytes.length; i += 255) { const c = Math.min(255, bytes.length - i); out.push(c, ...bytes.slice(i, i + c)); }
  out.push(0);
  return out;
}

export function encodeGIF(frames, w, h, delaysCs) {
  const { pal, idx } = buildPalette(frames);
  let gctBits = 1; while ((1 << (gctBits + 1)) < pal.length) gctBits++;   // GCT size field (0..7)
  const gctLen = 1 << (gctBits + 1);
  const minCode = Math.max(2, gctBits + 1);
  const b = [];
  const u16 = (n) => b.push(n & 255, (n >> 8) & 255);
  const str = (s) => { for (const ch of s) b.push(ch.charCodeAt(0)); };
  str('GIF89a'); u16(w); u16(h);
  b.push(0xF0 | gctBits, 0, 0);                                   // packed (GCT=1, depth), bg=0, aspect=0
  for (let i = 0; i < gctLen; i++) { const p = pal[i] || [0, 0, 0]; b.push(p[0], p[1], p[2]); }
  b.push(0x21, 0xFF, 0x0B); str('NETSCAPE2.0'); b.push(0x03, 0x01, 0, 0, 0);  // loop forever

  frames.forEach((f, fi) => {
    const d = delaysCs[fi] || 8;
    b.push(0x21, 0xF9, 0x04, 0x09); u16(d); b.push(0, 0);          // GCE: disposal=2|transparent, delay, tIdx=0
    b.push(0x2C); u16(0); u16(0); u16(w); u16(h); b.push(0);       // image descriptor (no LCT)
    const indices = new Uint8Array(w * h);
    for (let p = 0; p < w * h; p++) { const o = p * 4; indices[p] = idx(f[o], f[o + 1], f[o + 2], f[o + 3]); }
    b.push(minCode);
    for (const x of subBlocks(lzw(indices, minCode))) b.push(x);
  });
  b.push(0x3B);                                                    // trailer
  return new Uint8Array(b);
}
