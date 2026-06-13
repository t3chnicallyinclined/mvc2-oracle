#include "sh4ctx.h"
void transform_object_122560(Sh4Ctx*, u32 node_addr);

/* AUTO-GENERATED from bank03.asm loc_8c03093c (do not edit) */
/* Entry: r4 = node base. Deposits +0xE0/E4/E8 (transform), +0xEC/F0 (scale),
   +0x104/110/130/134/136 from the char struct. NO engine-TA / no pinning. */
void render_object_setup_03093c(Sh4Ctx *c){
loc_8c03093c:; /* bb */
    /* mov.l r14,@-r15 */
    c->r[15]-=4; w32(c, c->r[15], c->r[14]);
    /* sts.l pr,@-r15 */
    c->r[15]-=4; w32(c, c->r[15], c->pr);
    /* add 0xF4,r15 */
    c->r[15] += (u32)(s32)(-12);
    /* mov.w @(loc_8c030aa4,PC),r0 */
    c->r[0] = 0x12cu; /* pool loc_8c030aa4 */
    /* mov r4,r14 */
    c->r[14] = c->r[4];
    /* mov.b @(r0,r14),r3 */
    c->r[3] = r8s(c, (c->r[14] + c->r[0]));
    /* tst r3,r3 */
    c->sr_t = ((c->r[3] & c->r[3])==0);
    if(!c->sr_t) goto loc_8c030950;
    /* nop */
    ;
    goto loc_8c030a9c;
loc_8c030950:; /* bb */
    /* mov.l @(loc_8c030abc,PC),r3 */
    c->r[3] = 0x1ea00000u; /* leafptr bank02.loc_8c02e1a4 */
    /* nop */
    ;
    if(c->r[3]==0x1ea00000u){ /* loc_8c02e1a4 setup (stub) */ } else if(c->r[3]==0x1ea00001u){ /* loc_8c1216c0 proj-matrix setup, frame-global (stub; matrices read resident) */ } else if(c->r[3]==0x1ea00002u){ transform_object_122560(c, c->r[14]); /* per-object world->screen, deposits +0xE0/E4/E8 */ } else if(c->r[3]==0x1ea00003u){ /* loc_8c034bea global-accum helper (stub) */ } else { /* unresolved jsr */ }
    /* mova @(loc_8c030ac0,PC),r0 */
    c->r[0] = 0xF0000000u; c->_pool = 0x43f00000u; /* mova loc_8c030ac0 */
    /* mov.l @(loc_8c030ac8,PC),r3 */
    c->r[3] = 0x1ea00001u; /* leafptr bank12.loc_8c1216c0 */
    /* fmov @r0,fr5 */
    { u32 _b=c->_pool; c->fr[5] = *(float*)&_b; }
    /* mova @(loc_8c030ac4,PC),r0 */
    c->r[0] = 0xF0000000u; c->_pool = 0x44200000u; /* mova loc_8c030ac4 */
    /* fmov @r0,fr4 */
    { u32 _b=c->_pool; c->fr[4] = *(float*)&_b; }
    if(c->r[3]==0x1ea00000u){ /* loc_8c02e1a4 setup (stub) */ } else if(c->r[3]==0x1ea00001u){ /* loc_8c1216c0 proj-matrix setup, frame-global (stub; matrices read resident) */ } else if(c->r[3]==0x1ea00002u){ transform_object_122560(c, c->r[14]); /* per-object world->screen, deposits +0xE0/E4/E8 */ } else if(c->r[3]==0x1ea00003u){ /* loc_8c034bea global-accum helper (stub) */ } else { /* unresolved jsr */ }
    /* mov 0x3C,r0 */
    c->r[0] = (u32)(s32)(60);
    /* mov.l @(loc_8c030acc,PC),r3 */
    c->r[3] = 0x1ea00002u; /* leafptr bank12.loc_8c122560 */
    /* fmov @(r0,r14),fr6 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[6] = *(float*)&_w; }
    /* mov 0x38,r0 */
    c->r[0] = (u32)(s32)(56);
    /* fmov @(r0,r14),fr5 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[5] = *(float*)&_w; }
    /* mov r15,r6 */
    c->r[6] = c->r[15];
    /* mov r15,r5 */
    c->r[5] = c->r[15];
    /* mov 0x34,r0 */
    c->r[0] = (u32)(s32)(52);
    /* add 0x08,r6 */
    c->r[6] += (u32)(s32)(8);
    /* mov r15,r4 */
    c->r[4] = c->r[15];
    /* add 0x04,r5 */
    c->r[5] += (u32)(s32)(4);
    /* fmov @(r0,r14),fr4 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[4] = *(float*)&_w; }
    if(c->r[3]==0x1ea00000u){ /* loc_8c02e1a4 setup (stub) */ } else if(c->r[3]==0x1ea00001u){ /* loc_8c1216c0 proj-matrix setup, frame-global (stub; matrices read resident) */ } else if(c->r[3]==0x1ea00002u){ transform_object_122560(c, c->r[14]); /* per-object world->screen, deposits +0xE0/E4/E8 */ } else if(c->r[3]==0x1ea00003u){ /* loc_8c034bea global-accum helper (stub) */ } else { /* unresolved jsr */ }
    /* mov.w @(loc_8c030aa6,PC),r0 */
    c->r[0] = 0xe0u; /* pool loc_8c030aa6 */
    /* fmov @r15,fr3 */
    { u32 _w=r32(c,c->r[15]); c->fr[3] = *(float*)&_w; }
    /* mov.l @(loc_8c030ad0,PC),r4 */
    c->r[4] = 0x8c26a518u; /* pool loc_8c030ad0 */
    /* fmov fr3,@(r0,r14) */
    { float _f=c->fr[3]; w32(c,(c->r[14] + c->r[0]), *(u32*)&_f); }
    /* mov 0x04,r0 */
    c->r[0] = (u32)(s32)(4);
    /* fmov @(r0,r15),fr3 */
    { u32 _w=r32(c,(c->r[15] + c->r[0])); c->fr[3] = *(float*)&_w; }
    /* mov.w @(loc_8c030aa8,PC),r0 */
    c->r[0] = 0xe4u; /* pool loc_8c030aa8 */
    /* fmov fr3,@(r0,r14) */
    { float _f=c->fr[3]; w32(c,(c->r[14] + c->r[0]), *(u32*)&_f); }
    /* mov 0x24,r0 */
    c->r[0] = (u32)(s32)(36);
    /* mov.b @(r0,r14),r3 */
    c->r[3] = r8s(c, (c->r[14] + c->r[0]));
    /* mov.l @(loc_8c030ad4,PC),r0 */
    c->r[0] = 0x8c26a974u; /* pool loc_8c030ad4 */
    /* shll2 r3 */
    c->r[3] <<= 2;
    /* fmov @(r0,r3),fr3 */
    { u32 _w=r32(c,(c->r[3] + c->r[0])); c->fr[3] = *(float*)&_w; }
    /* mova @(loc_8c030ad8,PC),r0 */
    c->r[0] = 0xF0000000u; c->_pool = 0x3dcccccdu; /* mova loc_8c030ad8 */
    /* fmov @r0,fr0 */
    { u32 _b=c->_pool; c->fr[0] = *(float*)&_b; }
    /* mov 0x20,r0 */
    c->r[0] = (u32)(s32)(32);
    /* fmov @(r0,r4),fr2 */
    { u32 _w=r32(c,(c->r[4] + c->r[0])); c->fr[2] = *(float*)&_w; }
    /* mov.w @(loc_8c030aaa,PC),r0 */
    c->r[0] = 0xe8u; /* pool loc_8c030aaa */
    /* fmac fr0,fr2,fr3 */
    c->fr[3] = fmaf(c->fr[0], c->fr[2], c->fr[3]);
    /* fmov fr3,@(r0,r14) */
    { float _f=c->fr[3]; w32(c,(c->r[14] + c->r[0]), *(u32*)&_f); }
    /* mova @(loc_8c030adc,PC),r0 */
    c->r[0] = 0xF0000000u; c->_pool = 0x3fd55555u; /* mova loc_8c030adc */
    /* fmov @r0,fr3 */
    { u32 _b=c->_pool; c->fr[3] = *(float*)&_b; }
    /* mov 0x50,r0 */
    c->r[0] = (u32)(s32)(80);
    /* fmov @(r0,r14),fr2 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[2] = *(float*)&_w; }
    /* mov.w @(loc_8c030aac,PC),r0 */
    c->r[0] = 0xecu; /* pool loc_8c030aac */
    /* fmul fr3,fr2 */
    c->fr[2] = c->fr[2] * c->fr[3];
    /* fmov fr2,@(r0,r14) */
    { float _f=c->fr[2]; w32(c,(c->r[14] + c->r[0]), *(u32*)&_f); }
    /* mova @(loc_8c030ae0,PC),r0 */
    c->r[0] = 0xF0000000u; c->_pool = 0x40092492u; /* mova loc_8c030ae0 */
    /* fmov @r0,fr2 */
    { u32 _b=c->_pool; c->fr[2] = *(float*)&_b; }
    /* mov 0x54,r0 */
    c->r[0] = (u32)(s32)(84);
    /* fmov @(r0,r14),fr1 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[1] = *(float*)&_w; }
    /* fmul fr2,fr1 */
    c->fr[1] = c->fr[1] * c->fr[2];
    /* mov.w @(loc_8c030aae,PC),r0 */
    c->r[0] = 0xf0u; /* pool loc_8c030aae */
    /* fmov fr1,@(r0,r14) */
    { float _f=c->fr[1]; w32(c,(c->r[14] + c->r[0]), *(u32*)&_f); }
    /* mov 0x48,r0 */
    c->r[0] = (u32)(s32)(72);
    /* mov.l @(r0,r14),r3 */
    c->r[3] = r32(c, (c->r[14] + c->r[0]));
    /* mov.w @(loc_8c030ab0,PC),r0 */
    c->r[0] = 0x104u; /* pool loc_8c030ab0 */
    /* mov.l r3,@(r0,r14) */
    w32(c, (c->r[14] + c->r[0]), c->r[3]);
    /* add 0x2C,r0 */
    c->r[0] += (u32)(s32)(44);
    /* mov.w @(r0,r14),r2 */
    c->r[2] = r16s(c, (c->r[14] + c->r[0]));
    /* add 0xE0,r0 */
    c->r[0] += (u32)(s32)(-32);
    /* mov 0x00,r3 */
    c->r[3] = (u32)(s32)(0);
    /* mov.l r2,@(r0,r14) */
    w32(c, (c->r[14] + c->r[0]), c->r[2]);
    /* add 0xFC,r0 */
    c->r[0] += (u32)(s32)(-4);
    /* mov.l r3,@(r0,r14) */
    w32(c, (c->r[14] + c->r[0]), c->r[3]);
    /* mov 0x4C,r0 */
    c->r[0] = (u32)(s32)(76);
    /* mov.w @(r0,r14),r2 */
    c->r[2] = r16s(c, (c->r[14] + c->r[0]));
    /* mov.w @(loc_8c030ab2,PC),r0 */
    c->r[0] = 0x134u; /* pool loc_8c030ab2 */
    /* mov.w r2,@(r0,r14) */
    w16(c, (c->r[14] + c->r[0]), c->r[2]);
    /* mov 0x4E,r0 */
    c->r[0] = (u32)(s32)(78);
    /* mov.w @(r0,r14),r3 */
    c->r[3] = r16s(c, (c->r[14] + c->r[0]));
    /* mov.w @(loc_8c030ab4,PC),r0 */
    c->r[0] = 0x136u; /* pool loc_8c030ab4 */
    /* mov.w r3,@(r0,r14) */
    w16(c, (c->r[14] + c->r[0]), c->r[3]);
    /* mova @(loc_8c030ae4,PC),r0 */
    c->r[0] = 0xF0000000u; c->_pool = 0x444b16deu; /* mova loc_8c030ae4 */
    /* fmov @r0,fr1 */
    { u32 _b=c->_pool; c->fr[1] = *(float*)&_b; }
    /* mov 0x20,r0 */
    c->r[0] = (u32)(s32)(32);
    /* fmov @(r0,r4),fr4 */
    { u32 _w=r32(c,(c->r[4] + c->r[0])); c->fr[4] = *(float*)&_w; }
    /* mov.w @(loc_8c030aac,PC),r0 */
    c->r[0] = 0xecu; /* pool loc_8c030aac */
    /* fdiv fr1,fr4 */
    c->fr[4] = c->fr[4] / c->fr[1];
    /* fmov @(r0,r14),fr3 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[3] = *(float*)&_w; }
    /* fdiv fr4,fr3 */
    c->fr[3] = c->fr[3] / c->fr[4];
    /* fmov fr3,@(r0,r14) */
    { float _f=c->fr[3]; w32(c,(c->r[14] + c->r[0]), *(u32*)&_f); }
    /* add 0x04,r0 */
    c->r[0] += (u32)(s32)(4);
    /* fmov @(r0,r14),fr0 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[0] = *(float*)&_w; }
    /* fdiv fr4,fr0 */
    c->fr[0] = c->fr[0] / c->fr[4];
    /* fmov fr0,@(r0,r14) */
    { float _f=c->fr[0]; w32(c,(c->r[14] + c->r[0]), *(u32*)&_f); }
    /* add 0x5D,r0 */
    c->r[0] += (u32)(s32)(93);
    /* mov.b @(r0,r14),r3 */
    c->r[3] = r8s(c, (c->r[14] + c->r[0]));
    /* tst r3,r3 */
    c->sr_t = ((c->r[3] & c->r[3])==0);
    if(c->sr_t) goto loc_8c030a74;
    /* mov.w @(loc_8c030ab6,PC),r0 */
    c->r[0] = 0x14du; /* pool loc_8c030ab6 */
    /* mov.b @(r0,r14),r4 */
    c->r[4] = r8s(c, (c->r[14] + c->r[0]));
    /* add 0x1B,r0 */
    c->r[0] += (u32)(s32)(27);
    /* mov.l @(r0,r14),r3 */
    c->r[3] = r32(c, (c->r[14] + c->r[0]));
    /* mova @(loc_8c030ae8,PC),r0 */
    c->r[0] = 0xF0000000u; c->_pool = 0x447a0000u; /* mova loc_8c030ae8 */
    /* extu.b r4,r4 */
    c->r[4] = c->r[4] & 0xFFu;
    /* fmov @r0,fr4 */
    { u32 _b=c->_pool; c->fr[4] = *(float*)&_b; }
    /* shll2 r4 */
    c->r[4] <<= 2;
    /* mov.w @(loc_8c030aac,PC),r0 */
    c->r[0] = 0xecu; /* pool loc_8c030aac */
    /* shll2 r4 */
    c->r[4] <<= 2;
    /* add r3,r4 */
    c->r[4] += c->r[3];
    /* fmov @(r0,r14),fr0 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[0] = *(float*)&_w; }
    /* mov.w @r4,r3 */
    c->r[3] = r16s(c, c->r[4]);
    /* extu.w r3,r3 */
    c->r[3] = c->r[3] & 0xFFFFu;
    /* lds r3,fpul */
    c->fpul = c->r[3];
    /* float fpul,fr3 */
    c->fr[3] = (float)(s32)c->fpul;
    /* fdiv fr4,fr3 */
    c->fr[3] = c->fr[3] / c->fr[4];
    /* fmul fr3,fr0 */
    c->fr[0] = c->fr[0] * c->fr[3];
    /* fmov fr0,@(r0,r14) */
    { float _f=c->fr[0]; w32(c,(c->r[14] + c->r[0]), *(u32*)&_f); }
    /* add 0x04,r0 */
    c->r[0] += (u32)(s32)(4);
    /* mov r0,r2 */
    c->r[2] = c->r[0];
    /* mov.w @(0x2,r4),r0 */
    c->r[0] = r16s(c, (c->r[4] + 0x2u));
    /* add r14,r2 */
    c->r[2] += c->r[14];
    /* extu.w r0,r3 */
    c->r[3] = c->r[0] & 0xFFFFu;
    /* fmov @r2,fr0 */
    { u32 _w=r32(c,c->r[2]); c->fr[0] = *(float*)&_w; }
    /* lds r3,fpul */
    c->fpul = c->r[3];
    /* mov.w @(loc_8c030ab0,PC),r3 */
    c->r[3] = 0x104u; /* pool loc_8c030ab0 */
    /* float fpul,fr3 */
    c->fr[3] = (float)(s32)c->fpul;
    /* fdiv fr4,fr3 */
    c->fr[3] = c->fr[3] / c->fr[4];
    /* fmul fr3,fr0 */
    c->fr[0] = c->fr[0] * c->fr[3];
    /* fmov fr0,@r2 */
    { float _f=c->fr[0]; w32(c,c->r[2], *(u32*)&_f); }
    /* mov.w @(0x4,r4),r0 */
    c->r[0] = r16s(c, (c->r[4] + 0x4u));
    /* add r14,r3 */
    c->r[3] += c->r[14];
    /* mov.w @(loc_8c030ab0,PC),r1 */
    c->r[1] = 0x104u; /* pool loc_8c030ab0 */
    /* mov.w @r3,r3 */
    c->r[3] = r16s(c, c->r[3]);
    /* add r14,r1 */
    c->r[1] += c->r[14];
    /* mov.w @(loc_8c030ab2,PC),r2 */
    c->r[2] = 0x134u; /* pool loc_8c030ab2 */
    /* add r3,r0 */
    c->r[0] += c->r[3];
    /* mov.w @(loc_8c030ab8,PC),r3 */
    c->r[3] = 0x110u; /* pool loc_8c030ab8 */
    /* extu.w r0,r0 */
    c->r[0] = c->r[0] & 0xFFFFu;
    /* mov.l r0,@r1 */
    w32(c, c->r[1], c->r[0]);
    /* add r14,r2 */
    c->r[2] += c->r[14];
    /* mov.w @(0x6,r4),r0 */
    c->r[0] = r16s(c, (c->r[4] + 0x6u));
    /* add r14,r3 */
    c->r[3] += c->r[14];
    /* mov.w @(loc_8c030ab4,PC),r1 */
    c->r[1] = 0x136u; /* pool loc_8c030ab4 */
    /* mov.w r0,@r2 */
    w16(c, c->r[2], c->r[0]);
    /* mov.w @(0x8,r4),r0 */
    c->r[0] = r16s(c, (c->r[4] + 0x8u));
    /* add r14,r1 */
    c->r[1] += c->r[14];
    /* mov.w r0,@r1 */
    w16(c, c->r[1], c->r[0]);
    /* mov.w @(0xA,r4),r0 */
    c->r[0] = r16s(c, (c->r[4] + 0xau));
    /* mov.l @r3,r2 */
    c->r[2] = r32(c, c->r[3]);
    /* extu.w r0,r0 */
    c->r[0] = c->r[0] & 0xFFFFu;
    /* xor r0,r2 */
    c->r[2] ^= c->r[0];
    /* mov.l r2,@r3 */
    w32(c, c->r[3], c->r[2]);
loc_8c030a74:; /* bb */
    /* mov.l @(loc_8c030aec,PC),r3 */
    c->r[3] = 0x1ea00003u; /* leafptr loc_8c034bea */
    /* mov r14,r4 */
    c->r[4] = c->r[14];
    if(c->r[3]==0x1ea00000u){ /* loc_8c02e1a4 setup (stub) */ } else if(c->r[3]==0x1ea00001u){ /* loc_8c1216c0 proj-matrix setup, frame-global (stub; matrices read resident) */ } else if(c->r[3]==0x1ea00002u){ transform_object_122560(c, c->r[14]); /* per-object world->screen, deposits +0xE0/E4/E8 */ } else if(c->r[3]==0x1ea00003u){ /* loc_8c034bea global-accum helper (stub) */ } else { /* unresolved jsr */ }
    /* mov.l @(loc_8c030af0,PC),r3 */
    c->r[3] = 0x8c26823cu; /* pool loc_8c030af0 */
    /* mov r0,r4 */
    c->r[4] = c->r[0];
    /* lds r4,fpul */
    c->fpul = c->r[4];
    /* mov 0x24,r0 */
    c->r[0] = (u32)(s32)(36);
    /* mov.l @r3,r2 */
    c->r[2] = r32(c, c->r[3]);
    /* mov.l @(0x24,r2),r1 */
    c->r[1] = r32(c, (c->r[2] + 0x24u));
    /* float fpul,fr3 */
    c->fr[3] = (float)(s32)c->fpul;
    /* add r4,r1 */
    c->r[1] += c->r[4];
    /* mov.l r1,@(0x24,r2) */
    w32(c, (c->r[2] + 0x24u), c->r[1]);
    /* mov.b @(r0,r14),r2 */
    c->r[2] = r8s(c, (c->r[14] + c->r[0]));
    /* mova @(loc_8c030af4,PC),r0 */
    c->r[0] = 0xF0000000u; c->_pool = 0x3a83126fu; /* mova loc_8c030af4 */
    /* fmov @r0,fr0 */
    { u32 _b=c->_pool; c->fr[0] = *(float*)&_b; }
    /* mov.l @(loc_8c030ad4,PC),r0 */
    c->r[0] = 0x8c26a974u; /* pool loc_8c030ad4 */
    /* shll2 r2 */
    c->r[2] <<= 2;
    /* fmov @(r0,r2),fr2 */
    { u32 _w=r32(c,(c->r[2] + c->r[0])); c->fr[2] = *(float*)&_w; }
    /* fmac fr0,fr3,fr2 */
    c->fr[2] = fmaf(c->fr[0], c->fr[3], c->fr[2]);
    /* fmov fr2,@(r0,r2) */
    { float _f=c->fr[2]; w32(c,(c->r[2] + c->r[0]), *(u32*)&_f); }
loc_8c030a9c:; /* bb */
    /* add 0x0C,r15 */
    c->r[15] += (u32)(s32)(12);
    /* lds.l @r15+,pr */
    c->pr = r32(c, c->r[15]); c->r[15]+=4;
    /* mov.l @r15+,r14 */
    { u32 _a=c->r[15]; c->r[15]+=4; c->r[14] = r32(c,_a); }
    return;
}
