#!/usr/bin/env python3
"""Generate the per-tile transform core loc_8c0347c8 .. loc_8c034864 (SIMPLE path)
as an isolated C function transform_core(c). This is the FP+integer arithmetic that
turns (integer tile index, scale, anchor) into the final screenX/screenY. We test
it directly against the ASMTRACE per-tile screenX/screenY.

ABI for the isolated test (set by the harness before calling):
  r14         = node base (guest addr) -> we read scale node+0xEC/0xF0, that's it on
                the simple path. Anchor base @(0x0C,r15)/@(0x10,r15) preloaded.
  r10         = accX (pen) as the X integer source (s16)
  r8,r9       = flag masks 0x20,0x10 ; @(0x60,r15) PVR flags (0 => no mirror)
  r13         = descriptor ptr ; @(0x24,r15) Xstack, @(0x14,r15) Yacc preloaded
  @(0x0C,r15) = baseX float, @(0x10,r15) = baseY float
  @(0x54,r15) = 0 (simple path)
On return: @(0x30,r15)=screenX float, @(0x34,r15)=screenY float (read by harness).
"""
from lift import parse_asm, extract_block, slurp_function
from codegen import Emitter, R, FR

BANK03=r"C:\Users\trist\projects\_marv_re\build\bank03.asm"

def build():
    text=slurp_function(BANK03,None)
    # loc_8c0347c8 (10649) .. the simple-path store + bra (up to 10683), plus the
    # 10854..10878 pool block for any pool refs (loc_8c034810/812).
    blk="\n".join([extract_block(text,10649,10683), extract_block(text,10685,10698)])
    insns,data=parse_asm(blk)
    em=Emitter(data,{})
    body=[]
    i=0;n=len(insns)
    BR={'bra','bf','bt','bf.s','bt.s','bf/s','bt/s','jsr','rts'}
    while i<n:
        ins=insns[i]
        if ins.label: body.append(f"{ins.label}:; /* bb */")
        m=ins.mnem
        if m in BR:
            delayed=m not in ('bf','bt')
            ds=insns[i+1] if (delayed and i+1<n) else None
            if ds is not None: _one(em,ds,body)
            if m=='bra':
                # simple path ends with `bra loc_8c034864` -> just return
                body.append("    return;")
            elif m=='bf.s' or m=='bf/s': body.append(f"    if(!c->sr_t) goto {ins.args[0].lower()};")
            elif m=='bt.s' or m=='bt/s': body.append(f"    if(c->sr_t) goto {ins.args[0].lower()};")
            elif m=='bf': body.append(f"    if(!c->sr_t) goto {ins.args[0].lower()};")
            elif m=='bt': body.append(f"    if(c->sr_t) goto {ins.args[0].lower()};")
            else: body.append("    return;")
            i+= 2 if (delayed and ds is not None) else 1
            continue
        _one(em,ins,body)
        i+=1
    # The block falls into loc_8c03481c (scale path) if @0x54 != 0; we cut the test
    # to the simple path: if we ever reach loc_8c03481c, bail (shouldn't on simple path).
    with open("gen_transform.c","w") as f:
        f.write('#include "sh4ctx.h"\n\n')
        f.write("/* AUTO-GENERATED transform core (simple path) loc_8c0347c8..loc_8c034864 */\n")
        f.write("void transform_core(Sh4Ctx *c){\n")
        f.write("\n".join(body))
        f.write("\nloc_8c03481c:; return; /* scale-path not exercised in simple-path test */\n}\n")
    print("wrote gen_transform.c")

def _one(em,ins,body):
    saved=em.lines; em.lines=[]
    em.emit_insn(ins)
    body.extend("    "+l.strip() for l in em.lines)
    em.lines=saved

if __name__=='__main__': build()
