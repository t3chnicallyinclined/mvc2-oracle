#!/usr/bin/env python3
"""Verify the REAL load-time tile descriptors in the 16MB RAM dump at the
ASMTRACE r13 offsets, BEFORE running the diff — so the proof is not circular.

Dump layout: guest 0x8C000000 == dump offset 0, LITTLE-ENDIAN.
  guest addr 0x8CXXXXXX -> dump offset (0xXXXXXX & 0x00FFFFFF).

Per finding:body_walker_tiling (disasm loc_8c0344d4):
  r13 = (*(u16/u32 node+0xDC)) * 4 + 0x8C1F9F9C    [base of tile-desc table]
  per descriptor (4 bytes at r13): [m=@r13][count-1=@r13+1][pitchX=@r13+2][pitchY=@r13+3]
  count = (@r13+1) + 1 ; step per tile = (m*pitchX, m*pitchY); r13 advances +4 per tile.
"""
import struct, sys

DUMP = r"C:\Users\trist\projects\maplecast-flycast\_ryu_capture\mc_ram_dump.bin"
TBL  = 0x8C1F9F9C

def off(guest): return guest & 0x00FFFFFF

with open(DUMP, "rb") as f:
    ram = f.read()
assert len(ram) == 16*1024*1024, len(ram)

def u8(g):  return ram[off(g)]
def u16le(g): return struct.unpack_from("<H", ram, off(g))[0]
def u32le(g): return struct.unpack_from("<I", ram, off(g))[0]

print(f"=== tile-descriptor table base 0x{TBL:08X} (offset 0x{off(TBL):06X}) ===")
d0 = u32le(TBL)
b  = ram[off(TBL):off(TBL)+4]
print(f"first u32 LE = 0x{d0:08X}  bytes = [m=0x{b[0]:02X}][cnt-1=0x{b[1]:02X}][pitchX=0x{b[2]:02X}][pitchY=0x{b[3]:02X}]  -> count={b[1]+1}")

# ----------------------------------------------------------------------------------
# THE TEST OBJECT: cid 23, frame 10766 (Cable, sid 212) — the ASMTRACE's only frame
# whose tile descriptors fall entirely in the dump-resident idx 0..8 (node+0xDC=0).
# Its 4 GFX2 records' first-descriptor r13 + the trace tile count for each:
records = [
    ("sel1264", 0x8C1F9F9C, 4),   # idx0
    ("sel1267", 0x8C1F9FAC, 2),   # idx4
    ("sel1265", 0x8C1F9FB4, 1),   # idx6
    ("sel1266", 0x8C1F9FB8, 2),   # idx7
]
# ----------------------------------------------------------------------------------
# NOTE on the Sentinel sid-0x131 rocket (the prompt's 19-part object, node 0x0C27B864,
# r13=0x8C1FA16C / table idx 116+): those descriptors are ZERO in THIS dump. 0x8C1F9F9C
# is a ROLLING per-frame scratch table refilled per object via node+0xDC; only the first
# object's descriptors (idx 0..8) survived at the base in this static snapshot, so the
# rocket frame cannot be diffed against this dump. cid23 frame 10766 IS testable.
rocket_records = [
    ("sel2334", 0x8C1FA16C, 4), ("sel2383", 0x8C1FA17C, 1), ("sel2394", 0x8C1FA180, 4),
    ("sel2385", 0x8C1FA190, 1), ("sel2380", 0x8C1FA194, 4), ("sel2382", 0x8C1FA1A4, 2),
    ("sel2384", 0x8C1FA1AC, 1), ("sel2387", 0x8C1FA1B0, 1), ("sel2381", 0x8C1FA1B4, 1),
]

print("\n=== per-record real descriptors read from dump (independent of the trace's screenX/Y) ===")
all_ok = True
for name, r13, trace_count in records:
    tblidx = (r13 - TBL)//4   # this is node+0xDC for the FIRST record only; subsequent
    print(f"\n{name}: r13=0x{r13:08X}  (table index {tblidx})  trace tiles={trace_count}")
    # read `trace_count` consecutive descriptors (each 4 bytes), as the per-tile loop does
    for t in range(trace_count):
        a = r13 + 4*t
        m, cm1, px, py = ram[off(a)], ram[off(a)+1], ram[off(a)+2], ram[off(a)+3]
        cnt = cm1 + 1
        tag = ""
        if t == 0:
            cnt_match = (cnt == trace_count)
            tag = f"  count={cnt} {'== trace OK' if cnt_match else '!= trace MISMATCH'}"
            if not cnt_match: all_ok = False
        print(f"   desc[{t}] @0x{a:08X}: m=0x{m:02X}({m}) cnt-1=0x{cm1:02X} pitchX=0x{px:02X}({px}) pitchY=0x{py:02X}({py})  stepX={m*px} stepY={m*py}{tag}")

print("\n=== VERDICT ===")
print("All first-descriptor counts match the trace tile counts:", all_ok)
