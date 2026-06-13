# patch/0002 — MEMD: live per-byte memory feed (local headless)

Adds a gated, READ-ONLY side packet that ships the RE char-struct region's raw bytes each frame, so the
dashboard's memory map shows **exact per-byte heat** (client-side diff). Local-only — bandwidth (~0.5 MB/s)
is a non-issue on a local headless server. No JIT hook needed: `serverPublish()` runs once per frame and
`mem_b[]` is main RAM directly.

## Apply
Add this block in `core/network/maplecast_mirror.cpp`, inside `serverPublish()`, **right after the WTCH
probe broadcast** (after `if (wN > 0) maplecast_ws::broadcastBinary(wbuf, wN);`, ~line 2337, still inside
the per-frame `if (++_gsCounter >= 1) { … }`):

```cpp
            // MEMD — live per-byte snapshot of the RE char-struct region (gated MAPLECAST_MEMSNAP).
            // Local RE feed: ships raw mem_b bytes each frame; the dashboard diffs client-side for the
            // per-byte memory radar. READ-ONLY (reads mem_b, broadcasts). ~0.5 MB/s @ 60Hz (local only).
            static const bool _memsnapOn = getenv("MAPLECAST_MEMSNAP") != nullptr;
            if (_memsnapOn) {
                // 6 interleaved char structs: phys 0x0C268340 .. 0x0C26A518 = 0x21D8 bytes
                static const uint32_t MS_BASE = 0x0C268340, MS_LEN = 0x21D8;
                static uint32_t _msFrame = 0; ++_msFrame;
                static uint8_t msBuf[18 + MS_LEN];
                uint8_t* p = msBuf;
                p[0]='M'; p[1]='E'; p[2]='M'; p[3]='D'; p += 4;
                memcpy(p, &_msFrame, 4); p += 4;
                uint16_t nR = 1;       memcpy(p, &nR, 2);   p += 2;
                uint32_t base = MS_BASE, len = MS_LEN;
                memcpy(p, &base, 4); p += 4; memcpy(p, &len, 4); p += 4;
                memcpy(p, &mem_b[MS_BASE & 0x00FFFFFF], MS_LEN); p += MS_LEN;
                maplecast_ws::broadcastBinary(msBuf, (uint32_t)(p - msBuf));
            }
```

Packet wire format: `'MEMD'(4) + frame(u32 LE) + nRanges(u16 LE) + [ base(u32) + len(u32) + bytes[len] ] × nRanges`.
To add more ranges (globals page, object pool) bump `nR` and append more `{base,len,bytes}` blocks; the
client parses generically.

## Build + run (local headless, x64 Linux / WSL)
```bash
./scripts/build-headless.sh                       # builds the fork submodule WITH this patch applied
MAPLECAST_MEMSNAP=1 ./extern/flycast/build/headless/flycast /path/to/mvc2.gdi   # +existing GSTA/OBJS
# point the dashboard's Memory Map at it:  web/live-memory.html?ws=ws://localhost:7200
```
(`7200` = the flycast mirror WS; the relay/nginx path also works. MEMD rides the same WS as GSTA/OBJS.)

## Why no dirty-page diff
The mirror's dirty-page diff is for bandwidth-limited remote browsers and skips main RAM. Locally we just
read the bytes we care about each frame — exact, per-byte, field-granular, and the client diff gives the
heat for free. See `docs/WORKSTREAM-MEMORY-MAP.md`.
