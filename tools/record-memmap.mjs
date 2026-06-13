#!/usr/bin/env node
// record-memmap.mjs — record a dirty-page stream into a replayable capture JSON for the memory-map
// radar. The capture replays in web/memmap.html (Source → capture file).
//
//   node tools/record-memmap.mjs synthetic 600 > captures/sample.json   # fake churn (works now)
//   node tools/record-memmap.mjs mirror    wss://HOST/ws                # real VRAM dirty (Phase 1/2)
//   node tools/record-memmap.mjs statesync HOST:7102                    # real main-RAM (snapshot-diff)
//
// Capture format: { meta:{source,base,page,frames}, frames:[ [pageIdx,...], ... ] }

import { SyntheticSource } from '../web/memmap-source-synthetic.mjs';

const [, , mode = 'synthetic', arg = '600'] = process.argv;

if (mode === 'synthetic') {
  const n = parseInt(arg, 10) || 600;
  const src = new SyntheticSource();
  const frames = [];
  src.onFrame((f) => frames.push(f.dirty));
  for (let i = 0; i < n; i++) src.advance();
  process.stdout.write(JSON.stringify({
    meta: { source: 'synthetic', base: 0x0C000000, page: 4096, frames: n },
    frames,
  }));
} else if (mode === 'mirror') {
  // Real VRAM dirty pages from prod, LIVE. The mirror wire already ships region-1 dirty pages.
  // TODO(phase1/2): connect to the mirror WS (arg), parse the ZCST envelope + delta frame
  // (port transport.mjs + the frame parser), collect dirtyPage indices where regionId==1.
  console.error('mirror mode needs the ZCST/delta-frame parser (port from maplecast transport.mjs). Phase 1/2.');
  process.exit(2);
} else if (mode === 'statesync') {
  // Real MAIN-RAM dirty pages with ZERO server change: pull two full dc_serialize snapshots from
  // the state-sync port and memcmp the main-RAM region client-side (coarse cadence, but real).
  // TODO: parse the dc_serialize blob to locate the mem_b (main RAM) region, diff successive snapshots.
  console.error('statesync mode needs the dc_serialize RAM-offset parse. Real main-RAM, coarse cadence.');
  process.exit(2);
} else {
  console.error('usage: record-memmap.mjs synthetic|mirror|statesync [count|url|host:port]');
  process.exit(1);
}
