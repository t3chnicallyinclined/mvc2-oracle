// anim-export.mjs — export a captured animation (from SpritePreview.captureAnim) to an animation file.
// GIF (no deps, transparent, looping), WebM (built-in MediaRecorder), or a PNG spritesheet + JSON.

import { encodeGIF } from './gif-encode.mjs';

function download(blob, name) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob); a.download = name; a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
}

// cap = { frames:[RGBA Uint8ClampedArray], w, h, delaysCs:[] }
export function exportGIF(cap, name = 'anim.gif') {
  if (!cap) return false;
  download(new Blob([encodeGIF(cap.frames, cap.w, cap.h, cap.delaysCs)], { type: 'image/gif' }), name);
  return true;
}

// horizontal PNG spritesheet + a JSON sidecar (w,h,per-frame delay) — universal, re-animatable
export function exportSheet(cap, name = 'anim') {
  if (!cap) return false;
  const n = cap.frames.length, cv = document.createElement('canvas');
  cv.width = cap.w * n; cv.height = cap.h; const cx = cv.getContext('2d');
  for (let i = 0; i < n; i++) cx.putImageData(new ImageData(new Uint8ClampedArray(cap.frames[i]), cap.w, cap.h), i * cap.w, 0);
  cv.toBlob((b) => download(b, name + '.png'), 'image/png');
  download(new Blob([JSON.stringify({ frameW: cap.w, frameH: cap.h, frames: cap.delaysCs.map((d) => ({ delayCs: d })) })], { type: 'application/json' }), name + '.json');
  return true;
}

// record a live (playing) canvas to WebM for `ms` — zero-dep, plays everywhere
export function exportWebM(canvas, ms, name = 'anim.webm') {
  if (!canvas.captureStream || typeof MediaRecorder === 'undefined') return false;
  const rec = new MediaRecorder(canvas.captureStream(30), { mimeType: 'video/webm' });
  const chunks = []; rec.ondataavailable = (e) => e.data.size && chunks.push(e.data);
  rec.onstop = () => download(new Blob(chunks, { type: 'video/webm' }), name);
  rec.start(); setTimeout(() => rec.stop(), Math.max(300, ms));
  return true;
}
