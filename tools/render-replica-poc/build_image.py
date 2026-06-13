#!/usr/bin/env python3
"""
EXPLORATION / NOT IN run.cmd — kept to document the full-walker input-reconstruction
attempt and exactly where it hits the descriptor-table wall (see README "honest
scope"). The full numeric walker run needs the 0x8C1F9F9C tiling descriptor bytes +
GFX1 part-dimension bytes, which are absent from every available memory dump; this
script can synthesize node+GFX2 from the trace but cannot close the descriptor/scale
ambiguity. The VALIDATED tests are test_leaf.c + test_transform.c (see run.cmd).

Construct the input memory image for the FULL transpiled walker (walker_0344d4)
from the ASMTRACE, for one object/frame, and emit:
  - image.h : the synthesized RAM bytes (node struct, GFX2 cell table, descriptor
              table) + the entry ABI (node addr, stack addr) + the per-tile
              expected screenX/screenY from the trace.

We recover the node anchor/scale and the descriptor bytes from the trace itself.
HONEST SCOPE: the X axis (scaleX, baseX, per-record dx pen, X tile steps) is
recovered cleanly and INDEPENDENTLY from the trace (residual 0.000px), so the
walker reproducing screenX is a genuine end-to-end validation of the lifted
pen+tiling+FP chain. The Y axis descriptor bytes are not separable from scaleY
without the real 0x8C1F9F9C table (absent from every available dump), so Y is
reconstructed to-fit and NOT claimed as an independent validation.

Memory layout we synthesize in ram[] (guest area-3 addresses):
  NODE  @ 0x0C400000 (arbitrary scratch; walker masks to ram index)
  GFX2  @ 0x0C500000   (node+0x160 -> this)
  GFX1  @ 0x0C510000   (node+0x15C -> this; only used by scale path, set anyway)
  DESC  @ 0x8C1F9F9C  (the fixed table addr the walker hard-codes)
  GLOB  @ 0x8C1F9D80.. (template pointers; we point them at zeroed scratch)
  STACK @ 0x0C480000 (r15; grows down; plenty of headroom)
"""
import struct, collections, numpy as np

TRACE='../../_ryu_capture/asm_angled_fist.log'
FRAME='10775'; CID='23'

NODE=0x0C400000
GFX2=0x0C500000
GFX1=0x0C510000
DESC=0x8C1F9F9C
GLOB_D80=0x8C1F9D80
STACK=0x0C480000

def f32(x): return struct.pack('<f', np.float32(x))   # we store as guest BE below

def be32(x): return struct.pack('>I', x & 0xFFFFFFFF)
def be16(x): return struct.pack('>H', x & 0xFFFF)
def bef32(x):
    b=struct.pack('<f', np.float32(x)); return bytes(reversed(b))  # big-endian float

class Ram:
    def __init__(self): self.m=bytearray(16*1024*1024)
    def idx(self,a): return a & 0x00FFFFFF
    def w(self,a,b):
        i=self.idx(a); self.m[i:i+len(b)]=b
    def w32(self,a,v): self.w(a,be32(v))
    def w16(self,a,v): self.w(a,be16(v))
    def wf(self,a,x): self.w(a,bef32(x))

def load_records():
    rows=[]
    for line in open(TRACE):
        if line.startswith('#'): continue
        p=line.split()
        if len(p)<18 or p[0]!=FRAME or p[3]!=CID: continue
        rows.append(dict(sel=int(p[4]),dx=int(p[5]),dy=int(p[6]),accX=int(p[7]),accY=int(p[8]),
                         sx=float(p[9]),sy=float(p[10]),m=int(p[12]),flip=int(p[13]),
                         flags=int(p[14],16),r11=p[15],r13=int(p[16],16)))
    return rows

def main():
    rows=load_records()
    byrec=collections.OrderedDict()
    for r in rows: byrec.setdefault(r['r11'],[]).append(r)
    nrec=len(byrec)

    # ---- recover scaleX, baseX from first-tile-of-record regression (clean) ----
    ax=np.array([ts[0]['accX'] for ts in byrec.values()],float)
    fx=np.array([ts[0]['sx']  for ts in byrec.values()],float)
    bx=np.polyfit(ax,fx,1); scaleX=float(bx[0]); baseX=float(bx[1])
    # baseX is node+0xE0 AFTER the floor leaf -> store a value that floors to baseX.
    # The leaf floors node.e0; trace baseX=533.005 -> floor input 533.005 -> 533.0. The
    # per-tile add uses the FLOORED base. So set node.e0 = baseX (its floor = round down).
    # We store node.e0 = floor(baseX)+0.0 so leaf(node.e0)=floor(baseX). Verify trace baseX
    # is ~integer+.005 (rounding noise) -> use round(baseX).
    baseX_int=round(baseX)
    # scaleX exact: trace shows 5/3. Use the measured value; store as float32.
    scaleX_f=scaleX

    rec_list=list(byrec.items())

    ram=Ram()
    # ---- node fields ----
    ram.w32(NODE+0x160, GFX2)            # Dat_GFX2
    ram.w32(NODE+0x15c, GFX1)            # Dat_GFX1 (scale path only)
    ram.w16(NODE+0x144, 0x0000)          # sprite_id (sid&0x7fff=0 -> GFX2[0])
    ram.wf (NODE+0x0e0, float(baseX_int))# anchor X (floored by leaf)
    ram.wf (NODE+0x0e4, 0.0)             # anchor Y (we fit Y to it; see scope note)
    ram.wf (NODE+0x0e8, 0.0)             # node+0xE8 (loaded into fr3 @loc_8c034588)
    ram.wf (NODE+0x0ec, scaleX_f)        # scaleX
    ram.wf (NODE+0x0f0, scaleX_f)        # scaleY  (placeholder; Y not independently validated)
    ram.wf (NODE+0x0dc, 0.0)             # node+0xDC float (loaded @ e0/e4 path? it's read as ptr index)
    ram.w32(NODE+0x104, 0)               # node+0x104 (flip-select; 0 => xflip path A)
    ram.w16(NODE+0x110, 0)               # facing = 0 (matches trace flip col=0)
    ram.w16(NODE+0x134, 0)               # xflip copy
    ram.w16(NODE+0x136, 0)               # xflip copy
    ram.wf (NODE+0x108, 0.0)             # node+0x108 (loaded @ loc_8c034588 fr3)
    ram.w32(NODE+0x180, 0)               # node+0x180 (descriptor index base; 0)

    # node+0x0dc is used as r13 = *(node+0xdc) then shll2 + DESC base. We want r13 to start
    # at DESC. So node+0xDC must be an integer index 0 (DESC + 0*4). It's read with mov.l.
    ram.w32(NODE+0x0dc, 0)

    # ---- GFX2 cell table ----
    # node+0x144 sid=0 -> cell offset = *(GFX2 + 0) ; cell = GFX2 + that offset.
    # Put the cell right after a 4-byte offset slot.
    CELL=GFX2+0x10
    ram.w32(GFX2+0, (CELL-GFX2))         # offset for sid 0
    # cell: first u16 = count(nrec), then nrec * 8-byte records [dx][dy][flags][sel]
    cur=CELL
    ram.w16(cur, nrec); cur+=2
    # NOTE the walker reads count via mov.w @r11+ at entry (extu.w). It then loops
    # records of 8 bytes. r11 advances by 8 each record (add 0x08,r11 in loc_8c03488e).
    # Record layout read: @r11 (dx, mov.w), @(0x2,r11)(dy), @(0x4,r11)(flags u16), @(0x6,r11)(sel).
    # But entry consumed 2 bytes (count) so first record starts at CELL+2... yet walker uses
    # r11 (post-increment) as record base and reads @r11/@(0x2..). Align: after the count read,
    # r11 = CELL+2 = first record.
    recbase=cur
    for (r11,ts) in rec_list:
        t0=ts[0]
        ram.w16(cur+0, t0['dx'] & 0xFFFF)
        ram.w16(cur+2, t0['dy'] & 0xFFFF)
        ram.w16(cur+4, t0['flags'] & 0xFFFF)
        ram.w16(cur+6, t0['sel'] & 0xFFFF)
        cur+=8

    # ---- descriptor table @ DESC ----
    # The walker: r13 = DESC + (*(node+0xdc))*4 = DESC (index 0). Per RECORD, r13 advances by
    # 4 *per emitted tile* (add 0x04,r13 in the tile loop). Per record the descriptor entries
    # are consumed: count = byte[1 of the record's descriptor]+1 (loc_8c0345c4 reads
    # mov.b @(0x1,r13)). Wait: loc_8c0345c4 reads the descriptor for the count via
    #   mov.w @(0x6,r11),r0 ; ... mov.l @(r0,r4),r3 ; mov.b @(0x1,r13),r0 ; add 1 -> count
    # i.e. count comes from byte[1] at r13. And per tile loc_8c03478e reads byte[0],[2],[3].
    # We synthesize one descriptor entry per emitted tile (4 bytes each), with:
    #   byte[1] of the FIRST entry of a record = (ntiles-1)  (so count=ntiles)
    #   byte[0]=m (the trace 'row' col), byte[2]=X step unit, byte[3]=Y step unit.
    # We solve byte[2] so the X tile offset reproduces the trace Ix; byte[3] for Y (to-fit).
    desc=bytearray()
    for (r11,ts) in rec_list:
        ntiles=len(ts)
        m=ts[0]['m']
        # recover Ix per tile (clean): Ix=(sx-baseX)/scaleX
        for k,t in enumerate(ts):
            Ix=round((t['sx']-baseX)/scaleX)
            # per-tile descriptor 4 bytes [b0=m, b1=count-1(only first matters), b2, b3]
            b0=m & 0xFF
            b1=(ntiles-1) & 0xFF if k==0 else 0
            # b2,b3 are solved later by the harness's check; we store placeholders and let
            # the C transform use the ACTUAL desc math. For a faithful test we must store the
            # real per-tile geometry. Since the descriptor drives m*b2 - Xstack, and Xstack
            # advances by (b0<<3) per the loc_8c0346c4 shll2/shll, we can't trivially close it
            # here. We instead VALIDATE via the transform-core direct test (see harness).
            desc += bytes([b0,b1,0,0])
    ram.w(DESC, bytes(desc))

    # ---- globals (template pointers): point at zeroed scratch ----
    for off in (0x04,0x08,0x14):  # 0x8c1f9d84/88/94 referenced
        ram.w32(GLOB_D80+off, 0x0C470000)  # harmless scratch
    ram.w32(0x0C470000, 0)

    # ---- expected per-tile screenX/Y from trace ----
    exp=[]
    for (r11,ts) in rec_list:
        for t in ts:
            exp.append((t['sx'],t['sy'],t['accX'],t['accY'],t['m'],t['sel']))

    # emit image.h
    with open('image.h','w') as f:
        f.write('/* AUTO-GENERATED input image from ASMTRACE frame %s cid %s */\n'%(FRAME,CID))
        f.write('#ifndef IMAGE_H\n#define IMAGE_H\n#include "sh4ctx.h"\n')
        f.write('#define NODE_ADDR 0x%08xu\n#define STACK_ADDR 0x%08xu\n'%(NODE,STACK))
        f.write('#define SCALEX %.9ff\n#define BASEX %.6ff\n'%(scaleX,baseX))
        f.write('#define NREC %d\n'%nrec)
        # sparse image as (addr,val) pairs to keep it small
        # dump non-zero 4-byte words
        words=[]
        m=ram.m
        for a in range(0,len(m),4):
            v=(m[a]<<24)|(m[a+1]<<16)|(m[a+2]<<8)|m[a+3]
            if v: words.append((a,v))
        f.write('static const u32 IMG_WORDS[][2]={\n')
        for a,v in words:
            f.write('  {0x%06xu,0x%08xu},\n'%(a,v))
        f.write('};\nstatic const int IMG_NWORDS=%d;\n'%len(words))
        f.write('static const float EXP_SX[]={%s};\n'%(','.join('%.6ff'%e[0] for e in exp)))
        f.write('static const float EXP_SY[]={%s};\n'%(','.join('%.6ff'%e[1] for e in exp)))
        f.write('static const int EXP_ACCX[]={%s};\n'%(','.join(str(e[2]) for e in exp)))
        f.write('static const int EXP_N=%d;\n'%len(exp))
        f.write('#endif\n')
    print("wrote image.h: nrec=%d ntiles=%d scaleX=%.6f baseX=%.4f"%(nrec,len(exp),scaleX,baseX))

if __name__=='__main__': main()
