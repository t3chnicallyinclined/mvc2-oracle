#include "sh4ctx.h"

/* AUTO-GENERATED transform core (simple path) loc_8c0347c8..loc_8c034864 */
void transform_core(Sh4Ctx *c){
loc_8c0347c8:; /* bb */
    /* exts.w r4,r4 */
    c->r[4] = (u32)(s32)(s16)c->r[4];
    /* mov.w @(loc_8c034810,PC),r0 */
    c->r[0] = 0xecu; /* pool loc_8c034810 */
    /* add r4,r3 */
    c->r[3] += c->r[4];
    /* lds r3,fpul */
    c->fpul = c->r[3];
    /* exts.w r5,r5 */
    c->r[5] = (u32)(s32)(s16)c->r[5];
    /* fmov @(r0,r14),fr2 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[2] = *(float*)&_w; }
    /* mov.w @(0x14,r15),r0 */
    c->r[0] = r16s(c, (c->r[15] + 0x14u));
    /* float fpul,fr3 */
    c->fr[3] = (float)(s32)c->fpul;
    /* add r5,r0 */
    c->r[0] += c->r[5];
    /* lds r0,fpul */
    c->fpul = c->r[0];
    /* mov.w @(loc_8c034812,PC),r0 */
    c->r[0] = 0xf0u; /* pool loc_8c034812 */
    /* fmov fr3,fr12 */
    c->fr[12] = c->fr[3];
    /* float fpul,fr3 */
    c->fr[3] = (float)(s32)c->fpul;
    /* fmul fr2,fr12 */
    c->fr[12] = c->fr[12] * c->fr[2];
    /* fmov @(r0,r14),fr2 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[2] = *(float*)&_w; }
    /* mov 0x54,r0 */
    c->r[0] = (u32)(s32)(84);
    /* mov.l @(r0,r15),r3 */
    c->r[3] = r32(c, (c->r[15] + c->r[0]));
    /* fmov fr3,fr13 */
    c->fr[13] = c->fr[3];
    /* fmul fr2,fr13 */
    c->fr[13] = c->fr[13] * c->fr[2];
    /* mov r3,r2 */
    c->r[2] = c->r[3];
    /* tst r2,r2 */
    c->sr_t = ((c->r[2] & c->r[2])==0);
    /* mov.l r3,@r15 */
    w32(c, c->r[15], c->r[3]);
    if(!c->sr_t) goto loc_8c03481c;
    /* mov 0x0C,r0 */
    c->r[0] = (u32)(s32)(12);
    /* fmov @(r0,r15),fr3 */
    { u32 _w=r32(c,(c->r[15] + c->r[0])); c->fr[3] = *(float*)&_w; }
    /* mov 0x30,r0 */
    c->r[0] = (u32)(s32)(48);
    /* fadd fr12,fr3 */
    c->fr[3] = c->fr[3] + c->fr[12];
    /* fmov fr3,@(r0,r15) */
    { float _f=c->fr[3]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov 0x10,r0 */
    c->r[0] = (u32)(s32)(16);
    /* fmov @(r0,r15),fr3 */
    { u32 _w=r32(c,(c->r[15] + c->r[0])); c->fr[3] = *(float*)&_w; }
    /* mov 0x34,r0 */
    c->r[0] = (u32)(s32)(52);
    /* fadd fr13,fr3 */
    c->fr[3] = c->fr[3] + c->fr[13];
    /* fmov fr3,@(r0,r15) */
    { float _f=c->fr[3]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    return;
loc_8c03481c:; return; /* scale-path not exercised in simple-path test */
}
