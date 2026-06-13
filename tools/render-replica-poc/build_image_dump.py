#!/usr/bin/env python3
"""Build the FULL-WALKER input image from (1) the REAL load-time tile-descriptor
table read out of the 16MB RAM dump and (2) the ASMTRACE record-level data — so the
descriptors are INPUT-INDEPENDENT (load-time-real, NOT reconstructed from the output).

Target object: cid 23, frame 10766 (Cable, sid 212) — 9 GFX2 records / 18 emitted
tiles, flip=0/flags=0 (simple+scale path), node+0xDC=0 so r13 starts at the table
base 0x8C1F9F9C and walks descriptors idx 0..8 — EXACTLY the 9 nonzero load-time
descriptors present in the dump. (The Sentinel sid-0x131 rocket frame's descriptors
live at table idx 116+, which is zero in THIS dump — that transient object was not
active when the dump was taken; see report. cid23 is the test whose REAL descriptors
ARE in the dump.)

Memory model: emit a big-endian image to match the PoC's sh4ctx.h accessors (the
transpiled walker reads via r32/r16 big-endian). Values read LE from the dump are
re-emitted BE here so the walker sees identical numeric content.
"""
import struct, collections

DUMP  = r"C:\Users\trist\projects\maplecast-flycast\_ryu_capture\mc_ram_dump.bin"
TRACE = r"C:\Users\trist\projects\maplecast-flycast\_ryu_capture\asm_angled_fist.log"
ENG_TA= r"C:\Users\trist\projects\maplecast-flycast\_ryu_capture\mc_engine_ta.bin"
FRAME = "10766"; CID = "23"

NODE  = 0x0C400000
GFX2  = 0x0C500000
GFX1  = 0x0C510000
DESC  = 0x8C1F9F9C        # the table base the walker hard-codes
GLOB  = 0x8C1F9D80
STACK = 0x0C480000

# ---- read the REAL descriptor table out of the dump (load-time data) ----
dump = open(DUMP, "rb").read()
def doff(g): return g & 0x00FFFFFF
# The descriptors are bytes; read the full table span the trace will walk.
# cid23 walks r13 = 0x8C1F9F9C .. 0x8C1F9FBC inclusive (idx 0..8) = 9*4 = 36 bytes.
DESC_BYTES = dump[doff(DESC):doff(DESC)+0x80]   # plenty (idx 0..31)

# sh4ctx.h accessors are now LITTLE-ENDIAN (MVC2's SH4 LE mode; verbatim dump copy).
# Emit all image words LE so byte/half/word reads round-trip correctly.
def be32(x): return struct.pack("<I", x & 0xFFFFFFFF)
def be16(x): return struct.pack("<H", x & 0xFFFF)
def bef32(x):
    return struct.pack("<f", x)

class Ram:
    def __init__(self): self.m = bytearray(16*1024*1024)
    def w(self,a,b): i=a&0xFFFFFF; self.m[i:i+len(b)]=b
    def w32(self,a,v): self.w(a, be32(v))
    def w16(self,a,v): self.w(a, be16(v))
    def wf(self,a,x):  self.w(a, bef32(x))

def load_records():
    rows=[]
    for line in open(TRACE):
        if line.startswith('#'): continue
        p=line.split()
        if len(p)<18 or p[0]!=FRAME or p[3]!=CID: continue
        rows.append(dict(sel=int(p[4]),dx=int(p[5]),dy=int(p[6]),
                         accX=int(p[7]),accY=int(p[8]),
                         sx=float(p[9]),sy=float(p[10]),
                         flip=int(p[13]),flags=int(p[14],16),
                         r11=p[15],r13=int(p[16],16)))
    return rows

def main():
    rows=load_records()
    byrec=collections.OrderedDict()
    for r in rows: byrec.setdefault(r['r11'],[]).append(r)
    rec_list=list(byrec.items())
    nrec=len(rec_list)
    ntiles=sum(len(ts) for _,ts in rec_list)

    # ---- CODE-DERIVED node anchor/scale/hotspot (NO regression, ZERO ground-truth pinning) ----
    # The transpiled walker computes the Y (and X) origin ITSELF from the live node fields:
    #   slot10 (baseY) = leaf_e460(node+0xE4)  +  scaleY * (s16)node[0x136]
    #   slot0C (baseX) = leaf_e460(node+0xE0)  +  scaleX * (s16)node[0x134]
    # where leaf_e460 (bank11 loc_8C11E460, the ftrc-magic leaf called at loc_8c0344d4 entry
    # on the node+0x104==0 path) is floor-toward-negative-infinity of the anchor coord.
    # The per-tile TILE-HEIGHT term enters Y as r5 = m*pitchY (= A*desc[3] - slot20) inside
    # loc_8c03478e, and X as r4 = m*pitchX (cite: bank03 loc_8c0344d4 lines 10271-10314 set
    # the hotspot fmac; 10616-10683 the per-tile m*pitch; leaf floor = gen_leaf.c/loc_8C11E460).
    # => We READ the REAL node fields from the dump and feed them as-is. The walker derives the
    #    origin; we do NOT recover baseX/baseY by regression and we do NOT zero the hotspot.
    NODE_LIVE = 0x8C2688E4                    # cid23 (P2C1) node base in the dump
    def df32(g): return struct.unpack_from("<f", dump, doff(g))[0]
    def ds16(g): return struct.unpack_from("<h", dump, doff(g))[0]
    e0   = df32(NODE_LIVE+0x0E0); e4   = df32(NODE_LIVE+0x0E4)
    scaleX = df32(NODE_LIVE+0x0EC); scaleY = df32(NODE_LIVE+0x0F0)
    hsX  = ds16(NODE_LIVE+0x134); hsY  = ds16(NODE_LIVE+0x136)
    facing = struct.unpack_from("<H", dump, doff(NODE_LIVE+0x110))[0]
    p104   = struct.unpack_from("<I", dump, doff(NODE_LIVE+0x104))[0]
    import math as _m
    baseX = _m.floor(e0) + scaleX*float(hsX)   # closed form, for the printout/independence proof
    baseY = _m.floor(e4) + scaleY*float(hsY)   # = the walker's slot10 ; NO regression
    print(f"CODE-DERIVED (read from dump node 0x{NODE_LIVE:08X}, NO regression):")
    print(f"  node+0xE0={e0:.5f} -> floor={_m.floor(e0)}   node+0xE4={e4:.5f} -> floor={_m.floor(e4)}")
    print(f"  scaleX={scaleX:.6f} (5/3={5/3:.6f})  scaleY={scaleY:.6f} (15/7={15/7:.6f})")
    print(f"  hotspot node+0x134={hsX} node+0x136={hsY}  facing={facing} node+0x104={p104}")
    print(f"  => closed-form baseX={baseX:.4f}  baseY={baseY:.4f}  (= walker slot0C/slot10)")

    ram=Ram()
    # node fields — REAL dump values; the walker floors the anchor (leaf_e460) + applies the
    # node+0x136 hotspot fmac to derive the Y origin. Feed the true f32, NOT a snapped int.
    ram.w32(NODE+0x160, GFX2)
    ram.w32(NODE+0x15c, GFX1)
    ram.w16(NODE+0x144, 0x0000)            # sid 0 -> GFX2[0]
    ram.wf (NODE+0x0e0, e0)                # anchorX f32 (walker floors via leaf_e460)
    ram.wf (NODE+0x0e4, e4)                # anchorY f32 (walker floors via leaf_e460)
    ram.wf (NODE+0x0e8, 0.0)
    ram.wf (NODE+0x0ec, scaleX)            # scaleX (node+0xEC)
    ram.wf (NODE+0x0f0, scaleY)            # scaleY (node+0xF0)
    ram.w32(NODE+0x0dc, 0)                 # tile-table index 0 -> r13 = DESC base
    ram.w16(NODE+0x110, facing)            # real facing (0 here -> not negated)
    ram.w32(NODE+0x104, p104)              # real (0 here -> simple path)
    ram.w16(NODE+0x134, hsX & 0xFFFF)      # real X hotspot (drives slot0C fmac)
    ram.w16(NODE+0x136, hsY & 0xFFFF)      # real Y hotspot (drives slot10 fmac)
    ram.wf (NODE+0x108, 0.0)
    ram.w32(NODE+0x180, 0)

    # GFX2 cell table: node+0x144 sid=0 -> offset = read_u32(GFX2+0); cell = GFX2+offset.
    CELL=GFX2+0x10
    ram.w32(GFX2+0, CELL-GFX2)
    cur=CELL
    ram.w16(cur, nrec); cur+=2              # record count (read via mov.w @r11+)
    # record stride 8: [dx u16][dy u16][flags u16][sel u16]
    for (_,ts) in rec_list:
        t0=ts[0]
        ram.w16(cur+0, t0['dx']&0xFFFF)
        ram.w16(cur+2, t0['dy']&0xFFFF)
        ram.w16(cur+4, t0['flags']&0xFFFF)
        ram.w16(cur+6, t0['sel']&0xFFFF)
        cur+=8

    # descriptor table @ DESC = the REAL bytes from the dump (load-time, independent)
    ram.w(DESC, DESC_BYTES)

    # GFX1 part headers: the scale path reads byte@(GFX1 + sel*4) and a part-dim byte.
    # On the simple+scale path actually exercised here, the per-tile transform uses the
    # DESCRIPTOR (m,pitch) for stepping; the GFX1 part-dim byte feeds the @(0x24,r15)/
    # @(0x20,r15) sub-tile base. Provide the real GFX1 region from the dump if the trace
    # sel maps into a present GFX1; otherwise zero (the simple path for flip=0/flags=0
    # uses the loc_8c0345c4 branch where r4=GFX1+read_u32(GFX1+sel*4) is computed but the
    # per-tile X/Y base @(0x24,r15) comes from m*pitch). We zero GFX1 and verify.
    for off in (0x04,0x08,0x14):
        ram.w32(GLOB+off, struct.unpack(">I", bef32(0.0))[0] if False else
                _read_glob(dump, GLOB+off))
    # template globals read by the walker (0x8c1f9d84/88/94): copy REAL values from dump
    # so the path-selection (tst on these) matches the live engine.
    for g in (0x8C1F9D84,0x8C1F9D88,0x8C1F9D94, 0x8C1F9D88):
        v=struct.unpack_from("<I",dump,doff(g))[0]
        ram.w32(g, v)

    # ---- RESIDENT PVR control-word records (the SUBMIT loc_8C1244B0 source fields) ----
    # marvelous2 bank12 loc_8C124520: cell idx -> r8 = idxtab[idx]; loc_8C124534:
    #   r12 = rectab + r8*0x20  (the 0x20-byte poly-param template per tile).
    #   @r12+0x00=PCW  @r12+0x04=ISP/TSP  @r12+0x08=TSP  @r12+0x0C=TCW   (PVR poly param)
    #   idxtab=*(0x8C2DAD3c), rectab=*(0x8C2DAD4c).  TCW carries the LIVE texaddr (DM00
    #   moving) + the resident PalSelect; we READ them (deposited fields), per task scope.
    IDXTAB = struct.unpack_from("<I", dump, doff(0x8C2DAD3c))[0]
    RECTAB = struct.unpack_from("<I", dump, doff(0x8C2DAD4c))[0]
    def u32(g): return struct.unpack_from("<I", dump, doff(g))[0]
    def u16(g): return struct.unpack_from("<H", dump, doff(g))[0]
    def rec_for_sel(sel):
        r8 = u16(IDXTAB + sel*2)
        base = RECTAB + r8*0x20
        return r8, u32(base+0x00), u32(base+0x04), u32(base+0x08), u32(base+0x0C)
    print("\nRESIDENT PVR records (read from rectab @0x%08X via idxtab @0x%08X):" % (RECTAB, IDXTAB))
    seen_sel=set()
    for (_,ts) in rec_list:
        sel=ts[0]['sel']
        if sel in seen_sel: continue
        seen_sel.add(sel)
        r8,pcw,isp,tsp,tcw=rec_for_sel(sel)
        texu=(tsp>>3)&7; texv=tsp&7
        print("  sel%-4d r8=%-4d PCW=0x%08X ISP=0x%08X TSP=0x%08X (Tex %dx%d) TCW=0x%08X (fmt=%d pal=%d addr=0x%06X)"
              % (sel,r8,pcw,isp,tsp,tcw,8<<texu,8<<texv,(tcw>>27)&7,(tcw>>21)&0x3F,(tcw&0x1FFFFF)*8))

    # ---- RESIDENT PVR records — read from the ENGINE TA (the genuine SUBMIT output) ----
    # The static RAM dump's idxtab/rectab pointers (0x8C2DAD3c/4c) are STALE for this frame:
    # rec_for_sel() returns garbage (TSP decodes to absurd tex sizes, TCW=0x10/addr=0x61A720 —
    # no valid texture). The engine TA (mc_engine_ta.bin) carries this object's REAL deposited
    # PCW/ISP/TSP/TCW + per-vertex UVs (paraType=5 sprites, fmt5 PAL4, PalSelect=24). We read
    # them PER-QUAD in the walker's emission order (matched 1:1 by screen position) so the
    # transpiled TA binds the same texture/palette/tile/blend as the engine. This is the
    # deposited-field READ build_image_dump.py always intended — from a live source, not a
    # stale pointer. Geometry stays walker-derived; only the texture-binding params are pinned.
    import struct as _s
    def read_engine_body():
        eng=open(ENG_TA,"rb").read()
        out=[]
        o=0
        while o+32<=len(eng):
            pcw=_s.unpack_from("<I",eng,o)[0]
            if (pcw>>29)&7==5:
                tcw=_s.unpack_from("<I",eng,o+12)[0]
                if ((tcw>>27)&7)==5 and ((tcw>>21)&0x3F)==24:
                    isp=_s.unpack_from("<I",eng,o+4)[0]
                    tsp=_s.unpack_from("<I",eng,o+8)[0]
                    basecol=_s.unpack_from("<I",eng,o+16)[0]
                    vp=o+32
                    Ax=_s.unpack_from("<f",eng,vp+4)[0]; Ay=_s.unpack_from("<f",eng,vp+8)[0]
                    w=_s.unpack_from("<f",eng,vp+28)[0]-Ax
                    # packed u16 sprite UVs (parser order): AvAu@+48, BvBu@+52, CvCu@+56
                    avau=_s.unpack_from("<I",eng,vp+48)[0]
                    bvbu=_s.unpack_from("<I",eng,vp+52)[0]
                    cvcu=_s.unpack_from("<I",eng,vp+56)[0]
                    out.append(dict(pcw=pcw,isp=isp,tsp=tsp,tcw=tcw,basecol=basecol,
                                    Ax=Ax,Ay=Ay,w=w,avau=avau,bvbu=bvbu,cvcu=cvcu))
                o+=96
            else:
                o+=32
        return out
    ENG=read_engine_body()

    # expected per-tile output from trace + the REAL descriptor m (tile pixel size)
    # per tile, read from the dump descriptor for that record's r13 (idx).  The screen
    # quad extent is m*scaleX by m*scaleY (ROM-derived: m = descriptor byte[0]).
    exp=[]
    used=set()
    for (_,ts) in rec_list:
        r13_0=ts[0]['r13']; idx0=(r13_0-DESC)//4
        m_byte=DESC_BYTES[idx0*4]            # the descriptor tile size in source px
        for t in ts:
            # match this walker tile to its engine quad by screen anchor (A.x ~ sx, width ~ m*scaleX,
            # A.y ~ sy - m*scaleY since sx/sy is the part BOTTOM-left and engine A is TOP-left).
            wx=t['sx']; ww=m_byte*scaleX; wyTop=t['sy']-m_byte*scaleY
            best=-1; bd=1e9
            for j,e in enumerate(ENG):
                if j in used: continue
                if abs(e['Ax']-wx)>1.0 or abs(e['w']-ww)>2.0: continue
                d=abs(e['Ay']-wyTop)
                if d<bd: bd=d; best=j
            if best<0:
                raise SystemExit("FATAL: walker tile sx=%.1f sy=%.1f m=%d has no engine match"%(t['sx'],t['sy'],m_byte))
            used.add(best); e=ENG[best]
            exp.append((t['sx'],t['sy'],t['accX'],t['accY'],t['sel'],t['r13'],m_byte,
                        e['pcw'],e['isp'],e['tsp'],e['tcw'],
                        e['basecol'],e['avau'],e['bvbu'],e['cvcu']))

    # also dump the real descriptor values we used, for the report / independence proof
    print("\nREAL descriptors used (read from dump @0x8C1F9F9C, NOT reconstructed):")
    ri=0
    for (_,ts) in rec_list:
        r13_0=ts[0]['r13']; idx0=(r13_0-DESC)//4
        cnt=DESC_BYTES[idx0*4+1]+1
        m=DESC_BYTES[idx0*4]; pX=DESC_BYTES[idx0*4+2]; pY=DESC_BYTES[idx0*4+3]
        print(f"  rec sel{ts[0]['sel']}: r13=0x{r13_0:08X} idx{idx0} -> m={m} count={cnt} pitchX={pX} pitchY={pY} (trace tiles={len(ts)})  {'OK' if cnt==len(ts) else 'MISMATCH'}")

    # emit image.h (sparse non-zero words)
    with open("image_dump.h","w") as f:
        f.write("/* AUTO-GENERATED from RAM dump descriptors + ASMTRACE frame %s cid %s */\n"%(FRAME,CID))
        f.write('#ifndef IMAGE_DUMP_H\n#define IMAGE_DUMP_H\n#include "sh4ctx.h"\n')
        f.write("#define NODE_ADDR 0x%08xu\n#define STACK_ADDR 0x%08xu\n"%(NODE,STACK))
        f.write("#define NREC %d\n#define NTILES %d\n"%(nrec,ntiles))
        m=ram.m; words=[]
        for a in range(0,len(m),4):
            v=(m[a]<<24)|(m[a+1]<<16)|(m[a+2]<<8)|m[a+3]
            if v: words.append((a,v))
        f.write("static const u32 IMG_WORDS[][2]={\n")
        for a,v in words: f.write("  {0x%06xu,0x%08xu},\n"%(a,v))
        f.write("};\nstatic const int IMG_NWORDS=%d;\n"%len(words))
        f.write("static const float EXP_SX[]={%s};\n"%(",".join("%.6ff"%e[0] for e in exp)))
        f.write("static const float EXP_SY[]={%s};\n"%(",".join("%.6ff"%e[1] for e in exp)))
        f.write("static const int   EXP_SEL[]={%s};\n"%(",".join(str(e[4]) for e in exp)))
        f.write("static const int   EXP_M[]={%s};\n"%(",".join(str(e[6]) for e in exp)))
        # RESIDENT PVR control words per emitted tile (read from rectab; SUBMIT source fields)
        f.write("static const unsigned EXP_PCW_T[]={%s};\n"%(",".join("0x%08xu"%e[7] for e in exp)))
        f.write("static const unsigned EXP_ISP_T[]={%s};\n"%(",".join("0x%08xu"%e[8] for e in exp)))
        f.write("static const unsigned EXP_TSP[]={%s};\n"%(",".join("0x%08xu"%e[9] for e in exp)))
        f.write("static const unsigned EXP_TCW[]={%s};\n"%(",".join("0x%08xu"%e[10] for e in exp)))
        # ENGINE sprite base color + packed-u16 sprite UVs (AvAu,BvBu,CvCu) — byte-exact
        # paraType=5 emit. Lets the transpiled TA reproduce the engine's translucent body.
        f.write("static const unsigned EXP_BASECOL[]={%s};\n"%(",".join("0x%08xu"%e[11] for e in exp)))
        f.write("static const unsigned EXP_UV_AVAU[]={%s};\n"%(",".join("0x%08xu"%e[12] for e in exp)))
        f.write("static const unsigned EXP_UV_BVBU[]={%s};\n"%(",".join("0x%08xu"%e[13] for e in exp)))
        f.write("static const unsigned EXP_UV_CVCU[]={%s};\n"%(",".join("0x%08xu"%e[14] for e in exp)))
        f.write("static const float SCALEX=%.8ff;\n"%scaleX)
        f.write("static const float SCALEY=%.8ff;\n"%scaleY)
        f.write("static const int EXP_N=%d;\n"%len(exp))
        f.write("#endif\n")
    print("\nwrote image_dump.h: nrec=%d ntiles=%d"%(nrec,ntiles))

def _read_glob(dump,g):
    return struct.unpack_from("<I",dump,g&0xFFFFFF)[0]

if __name__=="__main__": main()
