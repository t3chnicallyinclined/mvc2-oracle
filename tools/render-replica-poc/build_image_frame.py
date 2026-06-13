#!/usr/bin/env python3
"""PHASE 2 — build the render_frame input image: the WHOLE-FRAME resident RAM needed for
the slot-table walk (loc_8c0308c2) to enumerate + render every on-screen BODY object.

Unlike build_image_full.py (which copied just ONE object's struct + tables), this copies:
  - the slot table: count array 0x8C2895E0 (16 bytes) + ptr arrays 0x8C287DE0 (16*0x180)
  - ALL 6 fighter char structs (P1C1..P2C3) so any active body resolves
  - GFX2/GFX1 for each active body
  - the descriptor table 0x8C1F9F9C + arena-control globals 0x8C1F9D80..9C
  - the rectab/idxtab + the frame-global projection matrices + the render-mode globals

It also emits the engine-truth EXP_* (per-object node+0xDC prefix-sum + the body sprite
params) for the byte-exact diff, all read from the dump's OWN resident fields.

Memory model: VERBATIM little-endian copy (sh4ctx.h is LE; the dump is LE). Guest
addresses kept identical so the transpiled code's hard-coded pool addrs resolve.
"""
import struct

DUMP = r"C:\Users\trist\projects\maplecast-flycast\_ryu_capture\mc_ram_dump.bin"
dump = open(DUMP, "rb").read()
def off(g): return g & 0x00FFFFFF
def u32(g): return struct.unpack_from("<I", dump, off(g))[0]
def u16(g): return struct.unpack_from("<H", dump, off(g))[0]
def u8(g):  return dump[off(g)]
def f32(g): return struct.unpack_from("<f", dump, off(g))[0]

CHAR_BASES = [0x8C268340,0x8C2688E4,0x8C268E88,0x8C26942C,0x8C2699D0,0x8C269F74]
SLOT_PALBANK = {0x8C268340:16,0x8C2688E4:24,0x8C268E88:32,0x8C26942C:40,0x8C2699D0:48,0x8C269F74:56}

class Ram:
    def __init__(self): self.m=bytearray(16*1024*1024)
    def copy(self, guest, nbytes):
        a=off(guest); self.m[a:a+nbytes]=dump[a:a+nbytes]   # verbatim LE

def enumerate_bodies():
    """Walk the slot table exactly as loc_8c0308c2 does; return body nodes in walk order."""
    CB=0x8C2895E0; PB=0x8C287DE0
    bodies=[]
    for L in range(16):
        cnt=u8(CB+L)
        if cnt==0 or cnt>0x60: continue
        base=PB+L*0x180
        for i in range(cnt):
            node=u32(base+i*4)
            if node==0 or (node>>24)!=0x8C: continue
            cat=u8(node+0x3)
            if cat==0:                       # cat==0 => BODY
                bodies.append((L,i,node))
    return bodies

def main():
    ram=Ram()
    # 1) slot table (count + ptr arrays, all 16 layers)
    ram.copy(0x8C2895E0, 0x10)
    ram.copy(0x8C287DE0, 16*0x180)
    # 2) all 6 char structs (any may be active)
    for b in CHAR_BASES: ram.copy(b, 0x5A4)
    # 3) per active body: GFX2 + GFX1
    bodies=enumerate_bodies()
    def is_ram(g):  # area-3 (0x8C..) or its cached P0 alias (0x0C..); both -> ram[g&0xFFFFFF]
        return ((g>>24)&0x7F)==0x0C and g!=0
    for (_,_,node) in bodies:
        GFX2=u32(node+0x160); GFX1=u32(node+0x15c)
        if is_ram(GFX2): ram.copy(GFX2 & ~0xFFF, 0x20000)
        if is_ram(GFX1): ram.copy(GFX1 & ~0xFFF, 0x20000)
    # 4) descriptor table + arena-control globals + template selects
    ram.copy(0x8C1F9D80, 0x400)            # 0x8C1F9D80..9C arena ctrl + 0x8C1F9F9C is +0x21C
    # 5) texture-param tables
    ram.copy(0x8C2DAD30, 0x40)
    IDXTAB=u32(0x8C2DAD3C); RECTAB=u32(0x8C2DAD4C)
    ram.copy(IDXTAB & ~0xFFF, 0x4000)
    ram.copy(RECTAB & ~0xFFF, 0x10000)
    # 6) frame-global projection matrices (camera)
    ram.copy(0x8C2D6AD8, 0x40); ram.copy(0x8C2D6B18, 0x40); ram.copy(0x8C2D6B58, 0x40)
    # 7) camera-Z scale global + render-mode global
    ram.copy(0x8C26A510, 0x40)
    ram.copy(0x8C2AA4C0, 0x10)

    # ---- engine-truth per-body prefix-sum (node+0xDC) + arena base ----
    arena_base = u32(0x8C1F9D94)
    obj_truth=[]
    for (L,i,node) in bodies:
        dc=u16(node+0xDC); pal=SLOT_PALBANK.get(node,24)
        obj_truth.append((L,i,node,dc,pal))

    # ---- engine body sprite params from the engine TA (the byte-exact diff target) ----
    # (read here so the harness can compare; grouped by PalSelect bank == per object)
    ta=open(r"C:\Users\trist\projects\maplecast-flycast\_ryu_capture\mc_engine_ta.bin","rb").read()
    def tu32(o): return struct.unpack_from("<I",ta,o)[0]
    eng_by_pal={}
    o=0
    while o+32<=len(ta):
        w=tu32(o); pt=(w>>29)&7
        if pt==5:
            tcw=tu32(o+12)
            if ((tcw>>27)&7)==5:
                pal=(tcw>>21)&0x3F
                eng_by_pal.setdefault(pal,[]).append((tu32(o),tu32(o+4),tu32(o+8),tcw))
            o+=96
        else: o+=32

    with open("image_frame.h","w") as f:
        f.write('#ifndef IMAGE_FRAME_H\n#define IMAGE_FRAME_H\n#include "sh4ctx.h"\n')
        f.write("/* AUTO-GENERATED whole-frame resident image (no engine-TA load-bearing) */\n")
        f.write("#define ARENA_BASE %du\n"%arena_base)
        f.write("#define NBODIES %d\n"%len(obj_truth))
        # the image words
        m=ram.m; words=[]
        for a in range(0,len(m),4):
            v=(m[a]<<24)|(m[a+1]<<16)|(m[a+2]<<8)|m[a+3]
            if v: words.append((a,v))
        f.write("static const u32 IMG_WORDS[][2]={\n")
        for a,v in words: f.write("  {0x%06xu,0x%08xu},\n"%(a,v))
        f.write("};\nstatic const int IMG_NWORDS=%d;\n"%len(words))
        # per-body truth
        f.write("static const u32 BODY_NODE[]={%s};\n"%(",".join("0x%08xu"%t[2] for t in obj_truth) or "0"))
        f.write("static const u32 BODY_LAYER[]={%s};\n"%(",".join(str(t[0]) for t in obj_truth) or "0"))
        f.write("static const u32 BODY_DC_RESIDENT[]={%s};\n"%(",".join(str(t[3]) for t in obj_truth) or "0"))
        f.write("static const u32 BODY_PALBANK[]={%s};\n"%(",".join(str(t[4]) for t in obj_truth) or "0"))
        # engine body params per pal (flattened: for the diff, per body in order)
        # emit the engine sprite params for each body's palbank
        flat=[]
        counts=[]
        for t in obj_truth:
            recs=eng_by_pal.get(t[4],[])
            counts.append(len(recs)); flat += recs
        f.write("static const int ENG_NTILES[]={%s};\n"%(",".join(str(x) for x in counts) or "0"))
        f.write("static const u32 ENG_PCW[]={%s};\n"%(",".join("0x%08xu"%r[0] for r in flat) or "0"))
        f.write("static const u32 ENG_ISP[]={%s};\n"%(",".join("0x%08xu"%r[1] for r in flat) or "0"))
        f.write("static const u32 ENG_TSP[]={%s};\n"%(",".join("0x%08xu"%r[2] for r in flat) or "0"))
        f.write("static const u32 ENG_TCW[]={%s};\n"%(",".join("0x%08xu"%r[3] for r in flat) or "0"))
        f.write("#endif\n")

    print("wrote image_frame.h: %d nonzero words, %d body object(s) in slot table"%(len(words),len(obj_truth)))
    print("  arena_base=%d"%arena_base)
    for (L,i,node,dc,pal) in obj_truth:
        print("  body L%02d[%d] node=%08X  node+0xDC(resident prefix)=%d  palbank=%d  eng_tiles=%d"
              %(L,i,node,dc,pal,len(eng_by_pal.get(pal,[]))))

if __name__=="__main__": main()
