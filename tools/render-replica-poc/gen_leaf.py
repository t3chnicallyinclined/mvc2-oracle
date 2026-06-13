#!/usr/bin/env python3
"""Generate C for the leaf loc_8C11E460 (bank11) and emit gen_leaf.c."""
import sys
from lift import parse_asm, extract_block, slurp_function
from emit_func import emit_function

BANK11=r"C:\Users\trist\projects\_marv_re\build\bank11.asm"

def main():
    text=slurp_function(BANK11,None)
    # leaf body: lines 34676..34721 (label loc_8C11E460 .. the e4a0 rts), incl its #data const
    blk=extract_block(text, 34676, 34721)
    # append the data pool const (loc_8C11E584) so pool resolution works
    const_blk=extract_block(text, 34877, 34878)
    insns,data=parse_asm(blk+"\n"+const_blk)
    # leaf calls no sub-leaf
    def noleaf(reg): raise RuntimeError("leaf has no jsr")
    cbody=emit_function(insns, data, "leaf_e460", noleaf)
    with open("gen_leaf.c","w") as f:
        f.write('#include "sh4ctx.h"\n\n')
        f.write("/* AUTO-GENERATED from bank11.asm loc_8C11E460 (do not edit) */\n")
        f.write("void leaf_e460(Sh4Ctx *c){\n")
        f.write(cbody)
        f.write("\n}\n")
    print("wrote gen_leaf.c")
    print(cbody)

if __name__=='__main__': main()
