#!/usr/bin/env python3
"""
Function-level codegen: turn a parsed Insn[] into a complete C function with
native control flow. Handles SH4's delayed branches by emitting the delay-slot
instruction's effect, then the transfer.

Branch model (flycast-accurate ordering):
  bra L / bsr L     : delay-slot executes, then goto L (bsr: set pr first)
  bf L              : if(!T) goto L         (no delay slot)
  bt L              : if(T)  goto L
  bf.s L / bt.s L   : delay-slot executes; if(cond) goto L
  bf/s, bt/s        : aliases of bf.s/bt.s
  jsr @rN           : delay-slot executes; call resolved leaf; (pr set)
  rts               : delay-slot executes; return
Fall-through between consecutive labelled blocks is implicit (C labels).
"""
import re
from codegen import Emitter, R, FR

BRANCHES = {'bra','bsr','bf','bt','bf.s','bt.s','bf/s','bt/s','jsr','rts','jmp','braf','bsrf'}

def emit_function(insns, data, fname, leaf_call_resolver):
    """leaf_call_resolver(jsr_reg_or_target) -> C statement to call the leaf."""
    em=Emitter(data, {})
    body=[]
    def out(s): body.append("    "+s)
    def outl(s): body.append(s)

    i=0
    n=len(insns)
    while i<n:
        ins=insns[i]
        if ins.label:
            outl(f"{ins.label}:; /* bb */")
        m=ins.mnem
        if m in BRANCHES:
            # collect the (single) delay-slot insn if delayed
            delayed = m in ('bra','bsr','bf.s','bt.s','bf/s','bt/s','jsr','rts','jmp','braf','bsrf')
            ds=None
            if delayed and i+1<n:
                ds=insns[i+1]
            # emit delay slot FIRST (its effect happens before transfer)
            if ds is not None:
                _emit_one(em, ds, body)
            # now the transfer
            if m=='bra':
                out(f"goto {ins.args[0].lower()};")
            elif m=='bf':
                out(f"if(!c->sr_t) goto {ins.args[0].lower()};")
            elif m=='bt':
                out(f"if(c->sr_t) goto {ins.args[0].lower()};")
            elif m in ('bf.s','bf/s'):
                out(f"if(!c->sr_t) goto {ins.args[0].lower()};")
            elif m in ('bt.s','bt/s'):
                out(f"if(c->sr_t) goto {ins.args[0].lower()};")
            elif m=='jsr':
                # jsr @rN -> resolve via the loaded pool value held in rN.
                out(leaf_call_resolver(ins.args[0]))
            elif m=='rts':
                out("return;")
            else:
                raise NotImplementedError(ins.raw)
            i += 2 if (delayed and ds is not None) else 1
            continue
        # normal insn
        _emit_one(em, ins, body)
        i+=1
    # assemble
    em.lines=[]  # codegen wrote into em.lines via emit; but we routed through body
    return "\n".join(body)

def _emit_one(em, ins, body):
    # temporarily redirect em.lines to capture this insn's C
    saved=em.lines
    em.lines=[]
    em.emit_insn(ins)
    body.extend(em.lines)
    em.lines=saved
