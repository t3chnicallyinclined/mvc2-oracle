#!/usr/bin/env python3
"""
Option C PoC — minimal SH4 -> C lifter.

Reads the marvelous2 disassembly text for a single function (a list of
`loc_8c...:` labels + SH4 mnemonics + the inline `#data` pools), and emits a C
function that operates on a `Sh4Ctx` + flat `ram[16MB]` exactly like the plan's
EXECUTOR-C path describes.

Scope: only the ~45 opcodes the two PoC target functions use. Each opcode
emitter mirrors flycast's determinism-validated interpreter semantics
(core/hw/sh4/interpr/*.cpp), specialized on the decoded operands, with NATIVE C
control flow (each BB -> a C label; SH4 delay slots emitted BEFORE the branch
effect, matching real SH4 execution order).

This is intentionally small but structured as a reusable generator (operand
parsing + a per-mnemonic table) so it generalizes to the full render tree later.

NOTE: marvelous2 already resolves PC-relative literal pool loads into named
`loc_..` data labels; this lifter consumes the SAME resolved form. `mov.w/mov.l
@(loc_X,PC),rN` becomes "load the #data word at loc_X" (a compile-time constant),
which is how we get struct offsets / pool pointers without modelling the real PC.
"""
import re, sys

# ---- a parsed instruction --------------------------------------------------
class Insn:
    __slots__=('label','mnem','args','raw','is_delay')
    def __init__(self, mnem, args, raw):
        self.mnem=mnem; self.args=args; self.raw=raw; self.label=None; self.is_delay=False
    def __repr__(self): return f"{self.label or '':>16} {self.mnem} {','.join(self.args)}"

def split_args(argstr):
    """Split SH4 operands on commas, but not inside @(...) parentheses."""
    out=[]; depth=0; cur=''
    for ch in argstr:
        if ch=='(': depth+=1; cur+=ch
        elif ch==')': depth-=1; cur+=ch
        elif ch==',' and depth==0:
            out.append(cur.strip()); cur=''
        else: cur+=ch
    if cur.strip(): out.append(cur.strip())
    return out

def parse_asm(text):
    """Parse a function body. Returns (insns[], data{label:intval}, order[])."""
    insns=[]; data={}; pending_label=None
    lines=text.splitlines()
    i=0
    cur_data_label=None
    while i < len(lines):
        ln=lines[i].rstrip('\n'); i+=1
        s=ln.strip()
        if not s or s.startswith(';'):
            continue
        # label?
        m=re.match(r'^(loc_[0-9a-fA-F]+|loc_[0-9a-zA-Z_]+):$', s)
        if m:
            pending_label=m.group(1).lower()
            cur_data_label=pending_label
            continue
        if s.startswith('#align'):
            continue
        if s.startswith('#data'):
            val=s.split(None,1)[1].strip()
            # could be hex or a bank ref like bank11.loc_..
            if cur_data_label is not None:
                data[cur_data_label]=val
                cur_data_label=None
            continue
        # strip trailing comment
        s=re.split(r'\s*;', s, 1)[0].strip()
        if not s: continue
        parts=s.split(None,1)
        mnem=parts[0]
        args=split_args(parts[1]) if len(parts)>1 else []
        ins=Insn(mnem,args,s)
        if pending_label is not None:
            ins.label=pending_label; pending_label=None
        insns.append(ins)
        cur_data_label=None
    return insns, data

def slurp_function(path, start_label):
    """Read the asm file, return the text block from start_label up to (but not
    including) the next top-level function separator (a ';====' that begins a new
    `loc_` not reachable). We just take from start_label to the function's `rts`
    epilogue region; simplest: take a generous window the caller bounds."""
    with open(path,'r',errors='replace') as f:
        return f.read()

def extract_block(text, first_line, last_line):
    lines=text.splitlines()
    return "\n".join(lines[first_line-1:last_line])

if __name__=='__main__':
    # quick self-test: dump parsed insns of a slice
    path=sys.argv[1]; a=int(sys.argv[2]); b=int(sys.argv[3])
    blk=extract_block(slurp_function(path,None), a, b)
    insns,data=parse_asm(blk)
    for ins in insns:
        print(ins)
    print("DATA:", data)
