# Memory Map — data sources

The radar (`web/panels/memmap-panel.mjs`) is source-agnostic. A source implements:

```js
source.onFrame(cb)   // cb({ frameNum, dirty: [pageIdx, ...] })
source.advance()     // emit one frame; returns false at end (capture sources)
```

So synthetic, recorded, and live feeds are all interchangeable.

## Sources

| Source | File | Data | Status |
|--------|------|------|--------|
| **Synthetic** | `web/memmap-source-synthetic.mjs` | fake match-shaped churn | ✅ works now, no emulator |
| **Capture** | `web/memmap-source-capture.mjs` | a recorded dirty-page JSON (real or synthetic), scrubbable | ✅ works now |
| **Live (mirror)** | (Phase 1/2) | prod VRAM dirty pages over the mirror WS | needs the wire parser |
| **Live (M2 main-RAM)** | (Phase 2) | `MAPLECAST_MEMMAP` RamWatcher feed | needs the server flag |

## Getting REAL data from prod (what's actually grabbable)

1. **VRAM dirty — LIVE, free, today.** The mirror stream (relay `:7201` → nginx `/ws`, public) already
   ships region-1 (VRAM) dirty pages every frame. A WS client + the ZCST/delta-frame parser (port
   `transport.mjs` + the frame parse) records them. *Caveat:* VRAM = texture activity, not the
   RE-interesting main RAM.
2. **Main RAM via snapshot-diff — real, coarse, ZERO server change.** The state-sync port (`:7102`,
   public) ships full `dc_serialize` blobs. Pull two, locate the main-RAM (`mem_b`) region in the blob,
   `memcmp` client-side → real main-RAM dirty pages at the state-sync cadence (not per-frame, but real).
3. **Main RAM per-frame — M2.** Deploy the `RamWatcher`-backed `MAPLECAST_MEMMAP` flag (env-gated,
   READ-ONLY) so a server emits per-frame main-RAM dirty pages directly. The richest feed; needs the
   backend add (see `WORKSTREAM-MEMORY-MAP.md` M2).

## Recording a capture

```bash
# synthetic (works now) — produces a replayable file to test the capture source / scrub
node tools/record-memmap.mjs synthetic 600 > captures/sample.json
# then: open web/memmap.html → Source → capture file → pick captures/sample.json
```
`mirror` and `statesync` modes are stubbed in `tools/record-memmap.mjs` pending the parsers above.
Real captures are ROM-derived → **gitignored** (`captures/`); only hand-deliver them.
