#!/usr/bin/env python3
"""Transpile loc_8c03093c ("Render Main Sprite", bank03) — the per-object setup that
DEPOSITS the per-frame fields the body walker/submit consume:

  +0xE0/E4/E8  screen anchor   (from the transform loc_8c122560; we route that jsr
               to the hand-verified transform_object_122560 — see gen_transform_obj.c)
  +0xEC/F0     per-axis scale  = CpsXScale * node[0x50] , CpsYScale * node[0x54]
               (CpsXScale=0x3fd55555=5/3, CpsYScale=0x40092492=15/7 — IMMEDIATES,
               work.asm:44-45; bank03:1336-1349). FULLY CODE-DERIVED from the char
               struct — no transform, no engine read.
  +0x104       = node[0x48]            (bank03:1350-1353)
  +0x130/0x134 xflip copies            (bank03:1354-1368)
  +0x136       Y-hotspot copy          (the walker's slot10 hotspot, bank03:1365-1368)
  +0x110       facing xor (zoom path)  (bank03:1382-1439, only when node[0x5D]!=0)

This routine's OTHER calls (loc_8c02e1a4 setup, loc_8c1216c0 proj-setup, loc_8c122560
transform, loc_8c034bea, GameGlobalPointer accum, the zoom-table fmac) are routed:
  - loc_8c1216c0 (proj setup, once/frame) + loc_8c02e1a4 -> STUB here (frame-global,
    we read the resident source matrices directly in transform_object_122560).
  - loc_8c122560 (the transform) -> transform_object_122560(c, node) (deposits E0/E4/E8).
  - loc_8c034bea / GameGlobalPointer / zoom fmac -> STUB (those touch global accum /
    the zoom-scale table; node[0x5D]==0 here so the zoom branch (1382-1439) is skipped).

We transpile the WHOLE function faithfully; the jsr's are resolved to the calls above.
The scale + field deposits (the load-bearing part for the walker/submit) are real C.
"""
import re
from lift import parse_asm, extract_block, slurp_function
from codegen import Emitter, R, FR

BANK03=r"C:\Users\trist\projects\_marv_re\build\bank03.asm"
WORK_ASM=r"C:\Users\trist\projects\_marv_re\memory\work.asm"

def load_work_symbols():
    """Resolve `work.NAME` -> its 0x value from memory/work.asm (#symbol NAME 0x..)."""
    syms={}
    for line in open(WORK_ASM, errors='replace'):
        m=re.match(r'\s*#symbol\s+(\w+)\s+(0x[0-9a-fA-F]+)', line)
        if m: syms[m.group(1).lower()]=m.group(2).lower()
    return syms

def resolve_work_refs(data, syms):
    """Rewrite pool words that are `work.NAME` into their numeric 0x value so the
    codegen treats them as ordinary constants (CpsXScale=5/3, CpsYScale=15/7, etc.)."""
    for k,v in list(data.items()):
        vl=v.lower()
        if vl.startswith('work.'):
            name=vl.split('.',1)[1]
            if name in syms: data[k]=syms[name]
    return data
# loc_8c03093c .. its rts (bank03:1281..1467) + the pool block (1469..1522)
RANGES=[(1281,1467),(1469,1523)]

# jsr targets in loc_8c03093c, resolved by the pool tag the lifter assigns:
#   loc_8c030abc -> bank02.loc_8c02e1a4   (setup; stub)
#   loc_8c030ac8 -> bank12.loc_8c1216c0   (proj-matrix setup, once/frame; stub)
#   loc_8c030acc -> bank12.loc_8c122560   (per-object transform -> deposits E0/E4/E8)
#   loc_8c030aec -> loc_8c034bea          (global accum helper; stub)
#   loc_8c030af0 -> work.GameGlobalPointer (data ptr, not a call)
LEAF_DISPATCH = {
    'bank02.loc_8c02e1a4': '/* loc_8c02e1a4 setup (stub) */',
    'bank12.loc_8c1216c0': '/* loc_8c1216c0 proj-matrix setup, frame-global (stub; matrices read resident) */',
    'bank12.loc_8c122560': 'transform_object_122560(c, c->r[14]); /* per-object world->screen, deposits +0xE0/E4/E8 */',
    'loc_8c034bea':        '/* loc_8c034bea global-accum helper (stub) */',
}

def build():
    text=slurp_function(BANK03,None)
    blk="\n".join(extract_block(text,a,b) for (a,b) in RANGES)
    insns,data=parse_asm(blk)
    data=resolve_work_refs(data, load_work_symbols())

    em=Emitter(data,{})
    body=[]
    tag_for={}
    for k,v in data.items():
        if v.lower().startswith('bank') or v.lower().startswith('loc_'):
            try: tag=em.leaf_tag(v); tag_for[tag]=v
            except Exception: pass
    def resolver(regarg):
        reg=regarg.strip('@')
        cases=[]
        for tag,ref in tag_for.items():
            call=LEAF_DISPATCH.get(ref)
            if call is None: continue
            cases.append(f"if({R(reg)}==0x{tag:08x}u){{ {call} }}")
        if not cases: return "/* unresolved jsr (no known leaf) */"
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
            if ds is not None: _one(em,ds,body)
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

    with open("gen_render_object.c","w") as f:
        f.write('#include "sh4ctx.h"\n')
        f.write('void transform_object_122560(Sh4Ctx*, u32 node_addr);\n\n')
        f.write("/* AUTO-GENERATED from bank03.asm loc_8c03093c (do not edit) */\n")
        f.write("/* Entry: r4 = node base. Deposits +0xE0/E4/E8 (transform), +0xEC/F0 (scale),\n")
        f.write("   +0x104/110/130/134/136 from the char struct. NO engine-TA / no pinning. */\n")
        f.write("void render_object_setup_03093c(Sh4Ctx *c){\n")
        f.write("\n".join(body))
        f.write("\n}\n")
    print("wrote gen_render_object.c  (", len(insns), "insns,",
          sum(1 for ins in insns if ins.label),"bbs )")

def _one(em,ins,body):
    saved=em.lines; em.lines=[]
    em.emit_insn(ins)
    body.extend("    "+l.strip() if not l.strip().endswith(':; /* bb */') else l for l in em.lines)
    em.lines=saved

if __name__=='__main__': build()
