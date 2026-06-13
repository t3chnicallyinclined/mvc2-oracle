#include "sh4ctx.h"
void helper_1294bc(Sh4Ctx*);

/* AUTO-GENERATED from bank12.asm loc_8C124AB0 (submit corner-transform) */
void submit_corners_124ab0(Sh4Ctx *c){
loc_8c124ab0:; /* bb */
    /* fmov.s fr14,@-r15 */
    c->r[15]-=4; { float _f=c->fr[14]; w32(c,c->r[15], *(u32*)&_f); }
    /* sts.l pr,@-r15 */
    c->r[15]-=4; w32(c, c->r[15], c->pr);
    /* add 0xDC,r15 */
    c->r[15] += (u32)(s32)(-36);
    /* fmov fr5,fr9 */
    c->fr[9] = c->fr[5];
    /* fmul fr7,fr5 */
    c->fr[5] = c->fr[5] * c->fr[7];
    /* fmov fr4,fr8 */
    c->fr[8] = c->fr[4];
    /* fmul fr6,fr4 */
    c->fr[4] = c->fr[4] * c->fr[6];
    /* fmul fr7,fr8 */
    c->fr[8] = c->fr[8] * c->fr[7];
    /* mov r15,r1 */
    c->r[1] = c->r[15];
    /* fmul fr6,fr9 */
    c->fr[9] = c->fr[9] * c->fr[6];
    /* mov.l @(loc_8C124BE8,pc),r2 */
    c->r[2] = 0x1ea00000u; /* leafptr bank13.loc_8C13F548 */
    /* mov r15,r7 */
    c->r[7] = c->r[15];
    /* mov.l @(loc_8C124BEC,pc),r3 */
    c->r[3] = 0x1ea00001u; /* leafptr bank12.loc_8c1294BC */
    /* add 0x04,r7 */
    c->r[7] += (u32)(s32)(4);
    /* add 0x04,r1 */
    c->r[1] += (u32)(s32)(4);
    /* mov 0x20,r0 */
    c->r[0] = (u32)(s32)(32);
    helper_1294bc(c); /* loc_8C1294Bc clamp (stub) */
    /* mov.l @(0x34,r4),r0 */
    c->r[0] = r32(c, (c->r[4] + 0x34u));
    /* tst 0x0F,r0 */
    c->sr_t = ((c->r[0] & 0xfu)==0);
    if(!c->sr_t) goto loc_8c124ae0;
    /* fldi1 fr10 */
    c->fr[10] = 1.0f;
    /* fmov fr10,fr6 */
    c->fr[6] = c->fr[10];
    /* fmov fr10,fr7 */
    c->fr[7] = c->fr[10];
    goto loc_8c124af8;
loc_8c124ae0:; /* bb */
    /* mov.l r0,@r15 */
    w32(c, c->r[15], c->r[0]);
    /* and 0x03,r0 */
    c->r[0] &= 0x3u;
    /* lds r0,fpul */
    c->fpul = c->r[0];
    /* mov.l @r15,r0 */
    c->r[0] = r32(c, c->r[15]);
    /* shar r0 */
    c->sr_t = (c->r[0] & 1u); c->r[0] = (u32)((s32)c->r[0] >> 1);
    /* float fpul,fr3 */
    c->fr[3] = (float)(s32)c->fpul;
    /* shar r0 */
    c->sr_t = (c->r[0] & 1u); c->r[0] = (u32)((s32)c->r[0] >> 1);
    /* and 0x03,r0 */
    c->r[0] &= 0x3u;
    /* lds r0,fpul */
    c->fpul = c->r[0];
    /* fmov fr3,fr6 */
    c->fr[6] = c->fr[3];
    /* float fpul,fr3 */
    c->fr[3] = (float)(s32)c->fpul;
    /* fmov fr3,fr7 */
    c->fr[7] = c->fr[3];
loc_8c124af8:; /* bb */
    /* mov 0x04,r1 */
    c->r[1] = (u32)(s32)(4);
loc_8c124afa:; /* bb */
    /* fmov.s @r7+,fr11 */
    { u32 _a=c->r[7]; c->r[7]+=4; u32 _w=r32(c,_a); c->fr[11] = *(float*)&_w; }
    /* mov 0x04,r0 */
    c->r[0] = (u32)(s32)(4);
    /* fldi0 fr3 */
    c->fr[3] = 0.0f;
    /* fsub fr6,fr11 */
    c->fr[11] = c->fr[11] - c->fr[6];
    /* fmov.s @r7+,fr10 */
    { u32 _a=c->r[7]; c->r[7]+=4; u32 _w=r32(c,_a); c->fr[10] = *(float*)&_w; }
    /* fmov.s @(r0,r4),fr1 */
    { u32 _w=r32(c,(c->r[4] + c->r[0])); c->fr[1] = *(float*)&_w; }
    /* mov 0x08,r0 */
    c->r[0] = (u32)(s32)(8);
    /* fsub fr7,fr10 */
    c->fr[10] = c->fr[10] - c->fr[7];
    /* fcmp/eq fr3,fr11 */
    c->sr_t = (c->fr[11] == c->fr[3]);
    /* fmov.s @(r0,r4),fr14 */
    { u32 _w=r32(c,(c->r[4] + c->r[0])); c->fr[14] = *(float*)&_w; }
    if(c->sr_t) goto loc_8c124b1c;
    /* fmov fr4,fr2 */
    c->fr[2] = c->fr[4];
    /* fmul fr11,fr2 */
    c->fr[2] = c->fr[2] * c->fr[11];
    /* fmov fr11,fr0 */
    c->fr[0] = c->fr[11];
    /* fmac fr0,fr8,fr1 */
    c->fr[1] = fmaf(c->fr[0], c->fr[8], c->fr[1]);
    /* fneg fr2 */
    c->fr[2] = -c->fr[2];
    /* fadd fr2,fr14 */
    c->fr[14] = c->fr[14] + c->fr[2];
loc_8c124b1c:; /* bb */
    /* fldi0 fr3 */
    c->fr[3] = 0.0f;
    /* fcmp/eq fr3,fr10 */
    c->sr_t = (c->fr[10] == c->fr[3]);
    if(c->sr_t) goto loc_8c124b28;
    /* fmov fr10,fr0 */
    c->fr[0] = c->fr[10];
    /* fmac fr0,fr5,fr14 */
    c->fr[14] = fmaf(c->fr[0], c->fr[5], c->fr[14]);
    /* fmac fr0,fr9,fr1 */
    c->fr[1] = fmaf(c->fr[0], c->fr[9], c->fr[1]);
loc_8c124b28:; /* bb */
    /* add 0xFF,r1 */
    c->r[1] += (u32)(s32)(-1);
    /* fmov.s fr1,@r5 */
    { float _f=c->fr[1]; w32(c,c->r[5], *(u32*)&_f); }
    /* fmov.s fr14,@r6 */
    { float _f=c->fr[14]; w32(c,c->r[6], *(u32*)&_f); }
    /* tst r1,r1 */
    c->sr_t = ((c->r[1] & c->r[1])==0);
    /* add 0x04,r6 */
    c->r[6] += (u32)(s32)(4);
    /* add 0x04,r5 */
    c->r[5] += (u32)(s32)(4);
    if(!c->sr_t) goto loc_8c124afa;
    /* add 0x24,r15 */
    c->r[15] += (u32)(s32)(36);
    /* lds.l @r15+,pr */
    c->pr = r32(c, c->r[15]); c->r[15]+=4;
    /* fmov.s @r15+,fr14 */
    { u32 _a=c->r[15]; c->r[15]+=4; u32 _w=r32(c,_a); c->fr[14] = *(float*)&_w; }
    return;
}
