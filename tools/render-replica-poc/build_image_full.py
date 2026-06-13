#!/usr/bin/env python3
"""Build the render_object_full input image from RESIDENT RAM ONLY (no engine-TA).

This is the un-pinned successor to build_image_dump.py. It copies the LIVE char
struct + GFX2/GFX1 + the descriptor table + the rectab/idxtab + the frame-global
projection matrices straight out of mc_ram_dump.bin, at their REAL guest addresses,
into a flat big-endian image. render_object_full() then COMPUTES:

  anchor  node+0xE0/E4  : transform_object_122560 (ftrv over the resident matrices)
  scale   node+0xEC/F0  : render_object_setup_03093c (CpsScale * node[0x50/54])
  params  PCW/ISP/TSP/TCW : submit_params (resident rectab[base+k] + finalize)

NOTHING is read from mc_engine_ta.bin. The only value the harness still SUPPLIES is
the per-frame allocation base_index (the transient submit record cursor) — which we
DISCOVER from the resident rectab (the unique contiguous pal-bank/fmt run of the
object's tile count), so even that is RAM-derived for this object. We still emit the
engine-truth EXP_* (anchor/scale/params) for the byte-exact DIFF — read from the dump's
own resident node fields + rectab (the values the engine actually deposited), NOT pins.

Memory model: big-endian image to match sh4ctx.h. We keep the guest addresses IDENTICAL
to the dump so the transpiled code's hard-coded pool addresses (0x8C2DAD3c, 0x8C2D6AD8,
0x8C1F9F9C, ...) resolve correctly.
"""
import struct, collections, math

DUMP  = r"C:\Users\trist\projects\maplecast-flycast\_ryu_capture\mc_ram_dump.bin"
TRACE = r"C:\Users\trist\projects\maplecast-flycast\_ryu_capture\asm_angled_fist.log"
FRAME = "10766"; CID = "23"
NODE_LIVE = 0x8C2688E4          # cid23 (P2C1) node base in the dump
SLOT_PALBANK = 24               # P2C1: 16*(0+1) + 8*1 = 24  (CLAUDE.md formula)

dump = open(DUMP, "rb").read()
def doff(g): return g & 0x00FFFFFF
def u32(g): return struct.unpack_from("<I", dump, doff(g))[0]
def u16(g): return struct.unpack_from("<H", dump, doff(g))[0]
def s16(g): return struct.unpack_from("<h", dump, doff(g))[0]
def f32(g): return struct.unpack_from("<f", dump, doff(g))[0]

def be32(x): return struct.pack(">I", x & 0xFFFFFFFF)
def bef32(x): return bytes(reversed(struct.pack("<f", x)))

class Ram:
    def __init__(self): self.m = bytearray(16*1024*1024)
    def w(self,a,b): i=a&0xFFFFFF; self.m[i:i+len(b)]=b
    # VERBATIM LE copy from the dump (guest is little-endian; sh4ctx.h accessors are LE).
    # No byteswap -> byte/half/word reads are all correct (fixes the sub-word byte bug).
    def copy_be_words(self, guest, nbytes):
        a=doff(guest)
        self.w(guest, dump[a:a+nbytes])

def discover_base_index(ntiles, palbank):
    """Find the unique contiguous run of >=ntiles rectab entries with this palbank+fmt5.
    Returns the start index (the engine's per-frame allocation base). RAM-derived."""
    RECTAB=u32(0x8C2DAD4C)
    runs=[]; i=0
    while i<4096:
        tcw=struct.unpack_from("<I",dump,doff(RECTAB+i*0x20+0xC))[0]
        if ((tcw>>27)&7)==5 and ((tcw>>21)&0x3F)==palbank:
            j=i
            while j<4096:
                t=struct.unpack_from("<I",dump,doff(RECTAB+j*0x20+0xC))[0]
                if ((t>>27)&7)==5 and ((t>>21)&0x3F)==palbank: j+=1
                else: break
            if (j-i)>=ntiles: runs.append((i,j-i))
            i=j
        else: i+=1
    return runs

def load_trace_records():
    rows=[]
    for line in open(TRACE):
        if line.startswith('#'): continue
        p=line.split()
        if len(p)<18 or p[0]!=FRAME or p[3]!=CID: continue
        rows.append(dict(sel=int(p[4]),dx=int(p[5]),dy=int(p[6]),
                         sx=float(p[9]),sy=float(p[10]),
                         flags=int(p[14],16),r11=p[15],r13=int(p[16],16)))
    return rows

def main():
    rows=load_trace_records()
    byrec=collections.OrderedDict()
    for r in rows: byrec.setdefault(r['r11'],[]).append(r)
    rec_list=list(byrec.items())
    ntiles=sum(len(ts) for _,ts in rec_list)

    ram=Ram()
    # 1) the LIVE char/object struct (verbatim, BE). 0x5A4 bytes is the stride.
    ram.copy_be_words(NODE_LIVE, 0x5A4)
    # 2) GFX2 + GFX1 (the static part tables). Copy a generous span around each (the
    #    sid=212 cell lives ~0x5B5C into GFX2; GFX1 part headers span further). 0x20000.
    GFX2=u32(NODE_LIVE+0x160); GFX1=u32(NODE_LIVE+0x15c)
    ram.copy_be_words(GFX2 & ~0xFFF, 0x20000)
    ram.copy_be_words(GFX1 & ~0xFFF, 0x20000)
    # 3) the rolling descriptor table 0x8C1F9F9C (load-time-resident idx 0..8 here) +
    #    the template globals 0x8c1f9d84/88/94 the walker path-selects on. 0x8C1F9F9C is
    #    at +0x21C from 0x8C1F9D80, so copy a wide span (0x400).
    ram.copy_be_words(0x8C1F9D80, 0x400)
    # 4) the texture-param tables: the pointers + the rectab/idxtab they point to.
    ram.copy_be_words(0x8C2DAD30, 0x40)               # the pointer block (idxtab/rectab/bounds)
    IDXTAB=u32(0x8C2DAD3C); RECTAB=u32(0x8C2DAD4C)
    ram.copy_be_words(IDXTAB & ~0xFFF, 0x4000)        # idxtab
    ram.copy_be_words(RECTAB & ~0xFFF, 0x10000)       # rectab (entries up to ~2k)
    # 5) the frame-global projection matrices (the camera; transform reads these)
    ram.copy_be_words(0x8C2D6AD8, 0x40)               # MAT_PROJ
    ram.copy_be_words(0x8C2D6B18, 0x40)               # MAT_VIEWPORT
    ram.copy_be_words(0x8C2D6B58, 0x40)               # (other resident matrices, harmless)
    # 6) the camera-Z scale-adjust global (loc_8c03093c reads *(0x8c26a518+0x20) =
    #    0x8c26a538 = camZ; final scale = (CpsScale*node[0x50]) / (812.357/camZ)).
    ram.copy_be_words(0x8C26A510, 0x40)
    # 7) the render-mode global the submit TSP finalize reads (loc_8C124718 -> *0x8C2AA4C4)
    ram.copy_be_words(0x8C2AA4C0, 0x10)

    # ---- discover the per-frame allocation base (RAM-derived, no engine-TA) ----
    runs=discover_base_index(ntiles, SLOT_PALBANK)
    if len(runs)!=1:
        print(f"WARNING: base_index discovery ambiguous: {runs}")
        base_index=9
    else:
        base_index=runs[0][0]
    print(f"discovered base allocation index = {base_index}  (run {runs})")
    # idxtab index that yields rectab[base_index+k]: find idxtab entry -> base_index
    # (the walker writes *r13 = that idxtab index). For the diff we map tile k ->
    # rec_index = (idxtab index pointing to rectab[base_index+k]).
    idx_for_rectab={}
    for ii in range(4096):
        idx_for_rectab.setdefault(u16(IDXTAB+ii*2), ii)
    rec_indices=[idx_for_rectab[base_index+k] for k in range(ntiles)]

    # ---- per-tile descriptor m (geometry the walker uses; resident @0x8C1F9F9C) ----
    # tile k belongs to record r; m = descriptor byte0 at the record's r13 index.
    DESC=0x8C1F9F9C
    tile_m=[]
    for (_,ts) in rec_list:
        r13_0=ts[0]['r13']; idx0=(r13_0-DESC)//4
        m=dump[doff(DESC)+idx0*4]            # descriptor byte0 = tile pixel size
        for _t in ts: tile_m.append(m)

    # ---- engine-truth EXP values (read from the dump's OWN resident fields) ----
    EX=f32(NODE_LIVE+0xE0); EY=f32(NODE_LIVE+0xE4)
    ESX=f32(NODE_LIVE+0xEC); ESY=f32(NODE_LIVE+0xF0)
    # resident rectab[base+k] -> the byte-exact params (after finalize) the diff checks
    def finalize(pcw,isp,tsp,tcw,pal):
        pcw=(pcw&0xF8FCFFFF)|0x02000000
        isp=(isp&0x1FFFFFFF)|(4<<29)
        tcw=(tcw&0xF81FFFFF)|((pal&0x3F)<<21)
        return pcw,isp,tsp,tcw
    EXP=[]
    for k in range(ntiles):
        b=RECTAB+(base_index+k)*0x20
        pcw,isp,tsp,tcw=finalize(u32(b),u32(b+4),u32(b+8),u32(b+0xC),SLOT_PALBANK)
        EXP.append((pcw,isp,tsp,tcw))

    # write the image header
    NODE=NODE_LIVE
    with open("image_full.h","w") as f:
        f.write("/* AUTO-GENERATED resident-only image (no engine-TA) — frame %s cid %s */\n"%(FRAME,CID))
        f.write('#ifndef IMAGE_FULL_H\n#define IMAGE_FULL_H\n#include "sh4ctx.h"\n')
        f.write("#define NODE_ADDR 0x%08xu\n"%NODE)
        f.write("#define SLOT_PALBANK %du\n"%SLOT_PALBANK)
        f.write("#define NTILES %d\n"%ntiles)
        f.write("#define BASE_INDEX %d\n"%base_index)
        m=ram.m; words=[]
        for a in range(0,len(m),4):
            v=(m[a]<<24)|(m[a+1]<<16)|(m[a+2]<<8)|m[a+3]
            if v: words.append((a,v))
        f.write("static const u32 IMG_WORDS[][2]={\n")
        for a,v in words: f.write("  {0x%06xu,0x%08xu},\n"%(a,v))
        f.write("};\nstatic const int IMG_NWORDS=%d;\n"%len(words))
        f.write("static const unsigned REC_INDEX[]={%s};\n"%(",".join(str(x) for x in rec_indices)))
        f.write("static const unsigned TILE_M[]={%s};\n"%(",".join(str(x) for x in tile_m)))
        # engine-truth (the dump's own deposited values) for the byte-exact diff
        f.write("static const float EXP_ANCHOR_X=%.8ff;\n"%EX)
        f.write("static const float EXP_ANCHOR_Y=%.8ff;\n"%EY)
        f.write("static const float EXP_SCALE_X=%.8ff;\n"%ESX)
        f.write("static const float EXP_SCALE_Y=%.8ff;\n"%ESY)
        f.write("static const unsigned EXP_PCW[]={%s};\n"%(",".join("0x%08xu"%e[0] for e in EXP)))
        f.write("static const unsigned EXP_ISP[]={%s};\n"%(",".join("0x%08xu"%e[1] for e in EXP)))
        f.write("static const unsigned EXP_TSP[]={%s};\n"%(",".join("0x%08xu"%e[2] for e in EXP)))
        f.write("static const unsigned EXP_TCW[]={%s};\n"%(",".join("0x%08xu"%e[3] for e in EXP)))
        f.write("#endif\n")
    print(f"wrote image_full.h: {len(words)} nonzero words, ntiles={ntiles}")
    print(f"  resident node+0xE0={EX:.5f} +0xE4={EY:.5f}  scale +0xEC={ESX:.6f} +0xF0={ESY:.6f}")
    print(f"  rec_indices={rec_indices}")

if __name__=="__main__": main()
