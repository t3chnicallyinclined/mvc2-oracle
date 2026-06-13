#include "sh4ctx.h"

/* AUTO-GENERATED from bank11.asm loc_8C11E460 (do not edit) */
void leaf_e460(Sh4Ctx *c){
loc_8c11e460:; /* bb */
    /* mova @(loc_8C11E584,pc),r0 */
    c->r[0] = 0xF0000000u; c->_pool = 0x4b000000u; /* mova loc_8C11E584 */
    /* fmov fr4,fr5 */
    c->fr[5] = c->fr[4];
    /* fmov.s @r0,fr3 */
    { u32 _b=c->_pool; c->fr[3] = *(float*)&_b; }
    /* fabs fr5 */
    c->fr[5] = fabsf(c->fr[5]);
    /* fcmp/gt fr5,fr3 */
    c->sr_t = (c->fr[3] > c->fr[5]);
    if(!c->sr_t) goto loc_8c11e490;
    /* ftrc fr5,fpul */
    { float _f=c->fr[5]; if(_f!=_f) c->fpul=0x80000000u; else { c->fpul=(u32)(s32)_f; if((s32)c->fpul>0x7fffff80) c->fpul=0x7fffffffu; } }
    /* fldi0 fr2 */
    c->fr[2] = 0.0f;
    /* fcmp/gt fr4,fr2 */
    c->sr_t = (c->fr[2] > c->fr[4]);
    /* sts fpul,r4 */
    c->r[4] = c->fpul;
    /* lds r4,fpul */
    c->fpul = c->r[4];
    /* float fpul,fr3 */
    c->fr[3] = (float)(s32)c->fpul;
    /* fmov fr3,fr6 */
    c->fr[6] = c->fr[3];
    if(!c->sr_t) goto loc_8c11e4a0;
    /* fsub fr6,fr5 */
    c->fr[5] = c->fr[5] - c->fr[6];
    /* fcmp/eq fr2,fr5 */
    c->sr_t = (c->fr[5] == c->fr[2]);
    if(c->sr_t) goto loc_8c11e490;
    /* mov 0xFF,r3 */
    c->r[3] = (u32)(s32)(-1);
    /* sub r4,r3 */
    c->r[3] -= c->r[4];
    /* lds r3,fpul */
    c->fpul = c->r[3];
    /* float fpul,fr3 */
    c->fr[3] = (float)(s32)c->fpul;
    /* fmov fr3,fr0 */
    c->fr[0] = c->fr[3];
    return;
    /* nop */
    ;
loc_8c11e490:; /* bb */
    /* fmov fr4,fr0 */
    c->fr[0] = c->fr[4];
    return;
    /* nop */
    ;
    /* nop */
    ;
    /* nop */
    ;
    /* nop */
    ;
    /* nop */
    ;
    /* nop */
    ;
loc_8c11e4a0:; /* bb */
    /* fmov fr6,fr0 */
    c->fr[0] = c->fr[6];
    /* nop */
    ;
    return;
}
