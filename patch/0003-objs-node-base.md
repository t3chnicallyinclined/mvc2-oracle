# patch/0003 — OBJS node_base: per-object RAM address on the wire

Adds each on-screen object's pool-node RAM base to the OBJS wire so the dashboard can show its address
(`[N, 0x1D0]`) and click it into the pool-node inspector. The node ptr is already in hand inside
`readAllDrawn` — this just stores + ships it. Additive (appends a u32 → 18-byte stride; the client
stride-detects, so old/new servers both work).

## Apply (core/network/)

**1. `maplecast_gamestate.h` — add to the DrawnObj struct (near `owner_slot`, ~line 130):**
```cpp
    uint32_t node_base;   // pool-node RAM base (0x8C26AA54 + i*0x1D0) — for the RE inspector
```

**2. `maplecast_gamestate.cpp` — populate it in every reader where the node base is known:**
- `readAllDrawn` (~line 414, the slot-table walk): after `out[n]...`, add `out[n].node_base = node;`
- `readObjectsWalk` (~line 334, var `node`): `out[n].node_base = node;`
- legacy reader (~line 611, anchor `a`): `out[n].node_base = a - 0x18;` (node base = scan anchor − 0x18)

**3. `maplecast_mirror.cpp` — append it to the OBJS record (the 14-byte writer, ~line 2373):**
```cpp
//   was 14B: cid(1)+sid(2)+type(1)+x(2)+y(2)+flags(1)+hotdx(1)+hotdy(1)+effkey(2)+blend(1)
//   now 18B: + node_base(u32 LE)
uint8_t obuf[4 + 1 + 255 * 18];        // bump 14 -> 18
// ... inside the per-object loop, AFTER writing blend at obuf[oo++]:
uint32_t nb = objs[i].node_base;
obuf[oo++] = nb & 0xFF; obuf[oo++] = (nb >> 8) & 0xFF; obuf[oo++] = (nb >> 16) & 0xFF; obuf[oo++] = (nb >> 24) & 0xFF;
```
(and adjust the per-object byte count / `oo` stride accounting from 14 to 18).

## Client + dashboard
`web/webgpu/sprite-client.mjs` `onOBJS` already detects the 18-byte stride and sets `ob.node_base`
(this repo). `web/live-scene.html` shows `@0x<node_base>` per object and clicks it into the pool-node
field view. With the same `MAPLECAST_MEMSNAP`-style read you can also stream each live node's bytes for
exact per-object values; for now the inspector shows the static pool-node layout at the real address.

## Build + run
Apply to the flycast source, `./scripts/build-headless.sh`, run normally (no env flag — it's always on once
patched; old clients ignore the extra bytes via stride detection). Also add `owner_base` the same way if you
want projectile→owner colour-linking (see `IDEAS-LINKED-VIEW.md`).
