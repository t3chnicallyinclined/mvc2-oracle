// re-cockpit.mjs — the Z-layer ETL from the original RE dash, ported pure. Classifies every TA poly of
// a decoded frame (STAGE/BG · CHARACTER · EFFECT/SPK · HUD) by depth + blend, attributes foreground polys
// to the nearest on-screen GSTA object, and reports counts + the per-object #fg table + misses.
// Input: the TAParser frame `g` ({vertexData,vertexCount,opaque,punchThrough,translucent}) + the sprite
// client (for slot[]). No WebGPU — stats only. (The visual truth-vs-ours DIFF is a separate WebGPU layer.)

const VPV = 7;   // floats per vertex in TAParser output: x,y,z, u,v, ... (z at +2)

export function classify(g, client, cut = 0.0091) {
  if (!g || !g.vertexCount) return { breakdown: 'no TA frame yet — RE mode needs the TA stream (in a match)', objs: '', misses: '' };
  const vf = new Float32Array(g.vertexData.buffer, g.vertexData.byteOffset, g.vertexCount * VPV);
  const objs = [];
  for (let s = 0; s < 6; s++) { const sl = client.slot?.[s]; if (sl?.active) objs.push({ slot: s, cid: sl.char_id, sid: sl.sprite_id & 0xffff, x: sl.screen_x, y: sl.screen_y, fg: 0 }); }
  const cnt = { stage: 0, character: 0, effect: 0, hud: 0 };
  let zmin = 1e9, zmax = -1e9;
  const scan = (list) => { if (!list) return; for (const pp of list) {
    if (!pp || pp.count < 3) continue;
    const z0 = vf[pp.first * VPV + 2]; if (z0 < zmin) zmin = z0; if (z0 > zmax) zmax = z0;
    let mnX = 1e9, mxX = -1e9, mnY = 1e9, mxY = -1e9;
    for (let v = pp.first; v < pp.first + pp.count; v++) { const x = vf[v * VPV], y = vf[v * VPV + 1]; if (x < mnX) mnX = x; if (x > mxX) mxX = x; if (y < mnY) mnY = y; if (y > mxY) mxY = y; }
    const cx = (mnX + mxX) / 2, cy = (mnY + mxY) / 2, dstB = (pp.tsp >> 26) & 7;
    let cls;
    if (z0 < cut) cls = 'stage';            // z<cut => the validated floor cut = STAGE/BG
    else if (dstB === 1) cls = 'effect';    // additive blend => EFFECT / SPARK
    else cls = (cy <= 120) ? 'hud' : 'character';
    cnt[cls]++;
    if (cls === 'character' || cls === 'effect') {
      let bd = 120, bo = null;
      for (const o of objs) { const d = Math.hypot(cx - o.x, cy - o.y); if (d < bd) { bd = d; bo = o; } }
      if (bo) bo.fg++;
    }
  }};
  scan(g.opaque); scan(g.punchThrough); scan(g.translucent);
  const tot = cnt.stage + cnt.character + cnt.effect + cnt.hud || 1;
  const pct = (n) => (100 * n / tot).toFixed(0).padStart(3) + '%';
  const breakdown =
    `polys ${tot}   cut z=${cut.toFixed(5)}  (z ${zmin.toFixed(4)}..${zmax.toFixed(4)})\n` +
    `STAGE/BG   ${String(cnt.stage).padStart(4)}  ${pct(cnt.stage)}\n` +
    `CHARACTER  ${String(cnt.character).padStart(4)}  ${pct(cnt.character)}\n` +
    `EFFECT/SPK ${String(cnt.effect).padStart(4)}  ${pct(cnt.effect)}\n` +
    `HUD        ${String(cnt.hud).padStart(4)}  ${pct(cnt.hud)}`;
  let ot = 'GSTA obj  cid  sid     scr_xy     #fg\n'; const misses = [];
  for (const o of objs) {
    ot += `s${o.slot} c0x${o.cid.toString(16).padStart(2, '0')} 0x${o.sid.toString(16).padStart(4, '0')} (${(o.x || 0).toFixed(0).padStart(3)},${(o.y || 0).toFixed(0).padStart(3)}) ${String(o.fg).padStart(4)}\n`;
    if (o.fg === 0) misses.push(`c0x${o.cid.toString(16)}/0x${o.sid.toString(16)}`);
  }
  return {
    breakdown,
    objs: objs.length ? ot.trimEnd() : 'objects: none active',
    misses: misses.length ? 'MISSES (on-screen, no fg poly): ' + misses.join(', ') : 'misses: none (every GSTA obj has fg polys)',
  };
}
