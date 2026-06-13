#!/usr/bin/env python3
"""Generate C for the full body walker loc_8c0344d4 (bank03) + emit gen_walker.c.

The walker calls leaves via `jsr @rN`/`jsr @r3` where rN holds a code pointer
loaded from a #data pool word (a `bankNN.loc_..` ref). The lifter tags those
pointer loads with a synthetic value; this generator wires the `jsr` to a C
dispatch over those tags, calling the (separately transpiled or modelled) leaf.

Leaves referenced by loc_8c0344d4:
  bank11.loc_8c11e460  (r9)  -> floorf snap          [TRANSPILED, proven 21/21]
  bank11.loc_8c11e2e0  (r3)  -> cos (scale path)      [modelled / not on simple path]
  bank11.loc_8c11e860  (r3)  -> sin (scale path)      [modelled / not on simple path]
  bank12.loc_8c1244b0  (r3)  -> vertex submit         [STUB: records the emitted quad]
"""
import re
from lift import parse_asm, extract_block, slurp_function
from codegen import Emitter, R, FR

BANK03=r"C:\Users\trist\projects\_marv_re\build\bank03.asm"

# walker spans 10218..10683 (code) with #data pools interleaved at
# 10380-10418, 10526-10540, 10686-10698; and the tail 10739..10797.
# We feed the lifter the full contiguous range and let it pick up data labels.
# walker code is 10218..10797; its tail pool words live at 10854..10878.
# Feed code + that pool block (data-only labels are harmless to the lifter).
WALKER_RANGES=[(10218,10797),(10854,10878)]

LEAF_DISPATCH = {
    # bankref -> C call. arg in fr4, result in fr0 (SH4 fp ABI used here).
    'bank11.loc_8c11e460': 'leaf_e460(c);',
    'bank11.loc_8c11e2e0': 'leaf_e2e0(c);',
    'bank11.loc_8c11e860': 'leaf_e860(c);',
    'bank12.loc_8c1244b0': 'submit_1244b0(c);',
}

def build():
    text=slurp_function(BANK03,None)
    blk="\n".join(extract_block(text,a,b) for (a,b) in WALKER_RANGES)
    insns,data=parse_asm(blk)

    em=Emitter(data,{})
    body=[]
    # pre-register leaf tags by scanning data for bankrefs we know
    tag_for={}
    for k,v in data.items():
        if v.lower().startswith('bank'):
            tag=em.leaf_tag(v); tag_for[tag]=v
    def resolver(regarg):
        # regarg like '@r9' or '@r3' ; emit a switch over the reg's tagged value
        reg=regarg.strip('@')
        cases=[]
        for tag,bankref in tag_for.items():
            call=LEAF_DISPATCH.get(bankref, '/*unknown leaf*/;')
            cases.append(f"if(({R(reg)} & 0xFFF00000u)==0x1EA00000u && {R(reg)}==0x{tag:08x}u){{ {call} }}")
        return " else ".join(cases) + " else { /* unresolved jsr */ }"

    i=0; n=len(insns)
    BRANCHES={'bra','bsr','bf','bt','bf.s','bt.s','bf/s','bt/s','jsr','rts','jmp'}
    while i<n:
        ins=insns[i]
        if ins.label: body.append(f"{ins.label}:; /* bb */")
        m=ins.mnem
        if m in BRANCHES:
            delayed = m not in ('bf','bt')
            ds=insns[i+1] if (delayed and i+1<n) else None
            if ds is not None:
                _one(em,ds,body)
            if m=='bra': body.append(f"    goto {ins.args[0].lower()};")
            elif m=='bf': body.append(f"    if(!c->sr_t) goto {ins.args[0].lower()};")
            elif m=='bt': body.append(f"    if(c->sr_t) goto {ins.args[0].lower()};")
            elif m in ('bf.s','bf/s'): body.append(f"    if(!c->sr_t) goto {ins.args[0].lower()};")
            elif m in ('bt.s','bt/s'): body.append(f"    if(c->sr_t) goto {ins.args[0].lower()};")
            elif m=='jsr': body.append("    "+resolver(ins.args[0]))
            elif m=='rts': body.append("    return;")
            else: raise NotImplementedError(ins.raw)
            i += 2 if (delayed and ds is not None) else 1
            continue
        _one(em,ins,body)
        i+=1

    with open("gen_walker.c","w") as f:
        f.write('#include "sh4ctx.h"\n')
        f.write('void leaf_e460(Sh4Ctx*);\nvoid leaf_e2e0(Sh4Ctx*);\nvoid leaf_e860(Sh4Ctx*);\nvoid submit_1244b0(Sh4Ctx*);\n\n')
        f.write("/* AUTO-GENERATED from bank03.asm loc_8c0344d4 (do not edit) */\n")
        f.write("void walker_0344d4(Sh4Ctx *c){\n")
        f.write("\n".join(body))
        f.write("\n}\n")
    print("wrote gen_walker.c  (", len(insns), "insns,", sum(1 for ins in insns if ins.label),"bbs )")

def _one(em,ins,body):
    saved=em.lines; em.lines=[]
    em.emit_insn(ins)
    body.extend("    "+l.strip() if not l.strip().endswith(':; /* bb */') else l for l in em.lines)
    em.lines=saved

if __name__=='__main__': build()
