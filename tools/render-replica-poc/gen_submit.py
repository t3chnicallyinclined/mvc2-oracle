#!/usr/bin/env python3
"""Transpile the per-part SUBMIT corner-transform helper loc_8C124AB0 (bank12) to C.

This is the routine loc_8C1244B0 (the body-part PVR quad submit) calls at bank12
line 9952 (`bsr loc_8C124AB0`) to turn the 4 corner-offset pairs into the 4 final
screen corners via a 2x2 rotation+scale around the screen anchor:

    out_corner = anchor + R(angle) . (offsetX*scaleX, offsetY*scaleY)

where R is built from fr4..fr9 = {scaleX*cos, scaleX*sin, scaleY*cos, scaleY*sin}
(submit lines 9962-9966) and the 4 offset pairs come from the unit-quad table.

For the AXIS-ALIGNED body path the rotation angle is 0 (cos=1, sin=0) so this
collapses to:  out = anchor + (offsetX*scaleX, offsetY*scaleY)  -- which is exactly
the rule the CHARQ probe_body_uv corners obey (A.y==B.y, B.x==C.x; all axis-aligned).

We transpile it to PROVE the extended codegen (fmac/shar/shad/and-imm/cmp-imm) lifts
the real submit SH4 faithfully, and to drive the corner build in test_ta_emit.c.

NOTE: loc_8C124AB0 itself calls loc_8C1294Bc (a clamp/range helper, bank12) at line
10663; on the axis-aligned body path that branch is data-dependent and we stub it
(the corner math below it is the load-bearing part). The function is transpiled up to
its rts; the one external jsr is resolved to a stub `helper_1294bc`.
"""
import re
from lift import parse_asm, extract_block, slurp_function
from codegen import Emitter, R, FR

BANK12=r"C:\Users\trist\projects\_marv_re\build\bank12.asm"
# loc_8C124AB0 .. its rts (bank12 lines 10647..10728), plus the pool block right after
RANGES=[(10647,10728),(10826,10840)]

def build():
    text=slurp_function(BANK12,None)
    blk="\n".join(extract_block(text,a,b) for (a,b) in RANGES)
    insns,data=parse_asm(blk)
    em=Emitter(data,{})
    body=[]
    BR={'bra','bsr','bf','bt','bf.s','bt.s','bf/s','bt/s','jsr','rts','jmp'}
    i=0;n=len(insns)
    while i<n:
        ins=insns[i]
        if ins.label: body.append(f"{ins.label}:; /* bb */")
        m=ins.mnem
        if m in BR:
            delayed = m not in ('bf','bt')
            ds=insns[i+1] if (delayed and i+1<n) else None
            if ds is not None: _one(em,ds,body)
            if m=='bra': body.append(f"    goto {ins.args[0].lower()};")
            elif m=='bsr':
                # bsr loc_.. : internal call. Only external jsr @rN here; bsr targets are
                # in-range labels -> treat as goto-with-return via inline (none in this fn).
                body.append(f"    goto {ins.args[0].lower()};")
            elif m=='bf': body.append(f"    if(!c->sr_t) goto {ins.args[0].lower()};")
            elif m=='bt': body.append(f"    if(c->sr_t) goto {ins.args[0].lower()};")
            elif m in ('bf.s','bf/s'): body.append(f"    if(!c->sr_t) goto {ins.args[0].lower()};")
            elif m in ('bt.s','bt/s'): body.append(f"    if(c->sr_t) goto {ins.args[0].lower()};")
            elif m=='jsr':
                # the single jsr @r3 -> loc_8C1294Bc clamp helper (stubbed)
                body.append("    helper_1294bc(c); /* loc_8C1294Bc clamp (stub) */")
            elif m=='rts': body.append("    return;")
            else: raise NotImplementedError(ins.raw)
            i += 2 if (delayed and ds is not None) else 1
            continue
        _one(em,ins,body)
        i+=1

    with open("gen_submit.c","w") as f:
        f.write('#include "sh4ctx.h"\n')
        f.write('void helper_1294bc(Sh4Ctx*);\n\n')
        f.write("/* AUTO-GENERATED from bank12.asm loc_8C124AB0 (submit corner-transform) */\n")
        f.write("void submit_corners_124ab0(Sh4Ctx *c){\n")
        f.write("\n".join(body))
        f.write("\n}\n")
    print("wrote gen_submit.c  (", len(insns), "insns )")

def _one(em,ins,body):
    saved=em.lines; em.lines=[]
    em.emit_insn(ins)
    body.extend("    "+l.strip() if not l.strip().endswith(':; /* bb */') else l for l in em.lines)
    em.lines=saved

if __name__=='__main__': build()
