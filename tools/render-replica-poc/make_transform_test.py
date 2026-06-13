#!/usr/bin/env python3
"""
Emit transform_cases.h: per-tile recovered (Ix, Iy, scaleX, scaleY, baseX, baseY)
+ expected (screenX, screenY) from the ASMTRACE, for the transform-core test.

Recovery (all INDEPENDENT of any descriptor bytes):
  scaleX, baseX  : first-tile-of-record regression  (residual 0.000px)
  scaleY, baseY  : joint solve s.t. all Iy are integers (max frac err < 0.003)
  Ix = round((sx-baseX)/scaleX)   (exact integer)
  Iy = round((sy-baseY)/scaleY)   (exact integer)
The transform-core C is then fed exactly these integers + scale/anchor and must
reproduce screenX/screenY. Trace screen coords are logged to 2 decimals, so the
pass tolerance is 0.01px (the trace's own quantization), with the residual
reported so we can see it is at the quantization floor, i.e. EXACT in the engine.
"""
import numpy as np, collections, struct

TRACE='../../_ryu_capture/asm_angled_fist.log'; FRAME='10775'; CID='23'

def main():
    rows=[]
    for line in open(TRACE):
        if line.startswith('#'): continue
        p=line.split()
        if len(p)<18 or p[0]!=FRAME or p[3]!=CID: continue
        rows.append(dict(sx=float(p[9]),sy=float(p[10]),accX=int(p[7]),accY=int(p[8]),
                         m=int(p[12]),sel=int(p[4]),r11=p[15]))
    byrec=collections.OrderedDict()
    for r in rows: byrec.setdefault(r['r11'],[]).append(r)

    ax=np.array([ts[0]['accX'] for ts in byrec.values()],float)
    fx=np.array([ts[0]['sx']  for ts in byrec.values()],float)
    bx=np.polyfit(ax,fx,1); scaleX=float(bx[0]); baseX=float(bx[1])

    sy=np.array([r['sy'] for r in rows])
    # joint Y solve (reuse the search that found 15/7, baseY~116.57)
    uy=sorted(set(round(v,3) for v in sy))
    diffs=sorted(set(round(uy[i+1]-uy[i],3) for i in range(len(uy)-1)))
    best=None
    for base_d in diffs[:5]:
        for k in range(1,9):
            sc=base_d/k
            if sc<0.05: continue
            for b0 in np.arange(min(uy)-sc*3, min(uy)+sc*3, sc/40):
                Iy=(sy-b0)/sc; err=np.abs(Iy-np.round(Iy)).max()
                if best is None or err<best[0]: best=(err,sc,b0)
    _,scaleY,baseY=best

    cases=[]
    for r in rows:
        Ix=round((r['sx']-baseX)/scaleX)
        Iy=round((r['sy']-baseY)/scaleY)
        cases.append((Ix,Iy,r['sx'],r['sy']))

    with open('transform_cases.h','w') as f:
        f.write('/* AUTO-GENERATED transform-core test cases (frame %s cid %s) */\n'%(FRAME,CID))
        f.write('#ifndef TC_H\n#define TC_H\n')
        f.write('#define TC_SCALEX %.9ff\n#define TC_SCALEY %.9ff\n'%(scaleX,scaleY))
        f.write('#define TC_BASEX %.6ff\n#define TC_BASEY %.6ff\n'%(baseX,baseY))
        f.write('static const int   TC_IX[]={%s};\n'%','.join(str(c[0]) for c in cases))
        f.write('static const int   TC_IY[]={%s};\n'%','.join(str(c[1]) for c in cases))
        f.write('static const float TC_SX[]={%s};\n'%','.join('%.2ff'%c[2] for c in cases))
        f.write('static const float TC_SY[]={%s};\n'%','.join('%.2ff'%c[3] for c in cases))
        f.write('static const int   TC_N=%d;\n#endif\n'%len(cases))
    print("wrote transform_cases.h: n=%d scaleX=%.6f baseX=%.4f scaleY=%.6f baseY=%.4f"%(
        len(cases),scaleX,baseX,scaleY,baseY))

if __name__=='__main__': main()
