#include "sh4ctx.h"
void leaf_e460(Sh4Ctx*);
void leaf_e2e0(Sh4Ctx*);
void leaf_e860(Sh4Ctx*);
void submit_1244b0(Sh4Ctx*);

/* AUTO-GENERATED from bank03.asm loc_8c0344d4 (do not edit) */
void walker_0344d4(Sh4Ctx *c){
loc_8c0344d4:; /* bb */
    /* mov.l r14,@-r15 */
    c->r[15]-=4; w32(c, c->r[15], c->r[14]);
    /* mov.l r13,@-r15 */
    c->r[15]-=4; w32(c, c->r[15], c->r[13]);
    /* mov.l r12,@-r15 */
    c->r[15]-=4; w32(c, c->r[15], c->r[12]);
    /* mov.l r11,@-r15 */
    c->r[15]-=4; w32(c, c->r[15], c->r[11]);
    /* mov.l r10,@-r15 */
    c->r[15]-=4; w32(c, c->r[15], c->r[10]);
    /* mov.l r9,@-r15 */
    c->r[15]-=4; w32(c, c->r[15], c->r[9]);
    /* mov.l r8,@-r15 */
    c->r[15]-=4; w32(c, c->r[15], c->r[8]);
    /* fmov fr15,@-r15 */
    c->r[15]-=4; { float _f=c->fr[15]; w32(c,c->r[15], *(u32*)&_f); }
    /* fmov fr14,@-r15 */
    c->r[15]-=4; { float _f=c->fr[14]; w32(c,c->r[15], *(u32*)&_f); }
    /* fmov fr13,@-r15 */
    c->r[15]-=4; { float _f=c->fr[13]; w32(c,c->r[15], *(u32*)&_f); }
    /* fmov fr12,@-r15 */
    c->r[15]-=4; { float _f=c->fr[12]; w32(c,c->r[15], *(u32*)&_f); }
    /* sts.l pr,@-r15 */
    c->r[15]-=4; w32(c, c->r[15], c->pr);
    /* add 0x84,r15 */
    c->r[15] += (u32)(s32)(-124);
    /* mov.w @(loc_8c0345fc,PC),r0 */
    c->r[0] = 0x160u; /* pool loc_8c0345fc */
    /* mov r4,r14 */
    c->r[14] = c->r[4];
    /* mov.w @(loc_8c0345fe,PC),r3 */
    c->r[3] = 0x7fffu; /* pool loc_8c0345fe */
    /* mov.l @(r0,r14),r4 */
    c->r[4] = r32(c, (c->r[14] + c->r[0]));
    /* add 0xE4,r0 */
    c->r[0] += (u32)(s32)(-28);
    /* mov.l @(r0,r14),r0 */
    c->r[0] = r32(c, (c->r[14] + c->r[0]));
    /* mov.l @(loc_8c03461c,PC),r9 */
    c->r[9] = 0x1ea00000u; /* leafptr bank11.loc_8c11e460 */
    /* and r3,r0 */
    c->r[0] &= c->r[3];
    /* shll2 r0 */
    c->r[0] <<= 2;
    /* mov.l @(r0,r4),r11 */
    c->r[11] = r32(c, (c->r[4] + c->r[0]));
    /* mov.w @(loc_8c034600,PC),r0 */
    c->r[0] = 0xdcu; /* pool loc_8c034600 */
    /* add r4,r11 */
    c->r[11] += c->r[4];
    /* mov.w @r11+,r2 */
    { u32 _a=c->r[11]; c->r[11]+=2; c->r[2] = r16s(c,_a); }
    /* extu.w r2,r2 */
    c->r[2] = c->r[2] & 0xFFFFu;
    /* mov.l r2,@(0x28,r15) */
    w32(c, (c->r[15] + 0x28u), c->r[2]);
    /* mov.l @(r0,r14),r13 */
    c->r[13] = r32(c, (c->r[14] + c->r[0]));
    /* add 0x28,r0 */
    c->r[0] += (u32)(s32)(40);
    /* mov.l @(r0,r14),r3 */
    c->r[3] = r32(c, (c->r[14] + c->r[0]));
    /* mov.l @(loc_8c034618,PC),r2 */
    c->r[2] = 0x8c1f9f9cu; /* pool loc_8c034618 */
    /* shll2 r13 */
    c->r[13] <<= 2;
    /* tst r3,r3 */
    c->sr_t = ((c->r[3] & c->r[3])==0);
    /* add r2,r13 */
    c->r[13] += c->r[2];
    /* mov 0x00,r12 */
    c->r[12] = (u32)(s32)(0);
    if(!c->sr_t) goto loc_8c03453a;
    /* mov.w @(loc_8c034602,PC),r0 */
    c->r[0] = 0xe0u; /* pool loc_8c034602 */
    /* fmov @(r0,r14),fr4 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[4] = *(float*)&_w; }
    if((c->r[9] & 0xFFF00000u)==0x1EA00000u && c->r[9]==0x1ea00000u){ leaf_e460(c); } else if((c->r[9] & 0xFFF00000u)==0x1EA00000u && c->r[9]==0x1ea00001u){ leaf_e2e0(c); } else if((c->r[9] & 0xFFF00000u)==0x1EA00000u && c->r[9]==0x1ea00002u){ leaf_e860(c); } else if((c->r[9] & 0xFFF00000u)==0x1EA00000u && c->r[9]==0x1ea00003u){ submit_1244b0(c); } else { /* unresolved jsr */ }
    /* mov 0x0C,r0 */
    c->r[0] = (u32)(s32)(12);
    /* fmov fr0,@(r0,r15) */
    { float _f=c->fr[0]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov.w @(loc_8c034604,PC),r0 */
    c->r[0] = 0xe4u; /* pool loc_8c034604 */
    /* fmov @(r0,r14),fr4 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[4] = *(float*)&_w; }
    if((c->r[9] & 0xFFF00000u)==0x1EA00000u && c->r[9]==0x1ea00000u){ leaf_e460(c); } else if((c->r[9] & 0xFFF00000u)==0x1EA00000u && c->r[9]==0x1ea00001u){ leaf_e2e0(c); } else if((c->r[9] & 0xFFF00000u)==0x1EA00000u && c->r[9]==0x1ea00002u){ leaf_e860(c); } else if((c->r[9] & 0xFFF00000u)==0x1EA00000u && c->r[9]==0x1ea00003u){ submit_1244b0(c); } else { /* unresolved jsr */ }
    /* mov 0x10,r0 */
    c->r[0] = (u32)(s32)(16);
    /* mov r12,r10 */
    c->r[10] = c->r[12];
    /* fmov fr0,@(r0,r15) */
    { float _f=c->fr[0]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov r12,r0 */
    c->r[0] = c->r[12];
    /* mov.w r0,@(0x14,r15) */
    w16(c, (c->r[15] + 0x14u), c->r[0]);
    goto loc_8c034588;
loc_8c03453a:; /* bb */
    /* mov.w @(loc_8c034606,PC),r0 */
    c->r[0] = 0x110u; /* pool loc_8c034606 */
    /* mov.l @(r0,r14),r1 */
    c->r[1] = r32(c, (c->r[14] + c->r[0]));
    /* tst r1,r1 */
    c->sr_t = ((c->r[1] & c->r[1])==0);
    if(!c->sr_t) goto loc_8c034548;
    /* mov.w @(loc_8c034608,PC),r0 */
    c->r[0] = 0x134u; /* pool loc_8c034608 */
    /* mov.w @(r0,r14),r10 */
    c->r[10] = r16s(c, (c->r[14] + c->r[0]));
    goto loc_8c03454e;
loc_8c034548:; /* bb */
    /* mov.w @(loc_8c034608,PC),r0 */
    c->r[0] = 0x134u; /* pool loc_8c034608 */
    /* mov.w @(r0,r14),r10 */
    c->r[10] = r16s(c, (c->r[14] + c->r[0]));
    /* neg r10,r10 */
    c->r[10] = (u32)(0 - (s32)c->r[10]);
loc_8c03454e:; /* bb */
    /* mov.w @(loc_8c03460a,PC),r0 */
    c->r[0] = 0x136u; /* pool loc_8c03460a */
    /* mov.w @(r0,r14),r8 */
    c->r[8] = r16s(c, (c->r[14] + c->r[0]));
    /* add 0xAA,r0 */
    c->r[0] += (u32)(s32)(-86);
    /* fmov @(r0,r14),fr4 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[4] = *(float*)&_w; }
    if((c->r[9] & 0xFFF00000u)==0x1EA00000u && c->r[9]==0x1ea00000u){ leaf_e460(c); } else if((c->r[9] & 0xFFF00000u)==0x1EA00000u && c->r[9]==0x1ea00001u){ leaf_e2e0(c); } else if((c->r[9] & 0xFFF00000u)==0x1EA00000u && c->r[9]==0x1ea00002u){ leaf_e860(c); } else if((c->r[9] & 0xFFF00000u)==0x1EA00000u && c->r[9]==0x1ea00003u){ submit_1244b0(c); } else { /* unresolved jsr */ }
    /* exts.w r10,r3 */
    c->r[3] = (u32)(s32)(s16)c->r[10];
    /* mov.w @(loc_8c03460c,PC),r0 */
    c->r[0] = 0xecu; /* pool loc_8c03460c */
    /* lds r3,fpul */
    c->fpul = c->r[3];
    /* fmov fr0,fr2 */
    c->fr[2] = c->fr[0];
    /* fmov @(r0,r14),fr0 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[0] = *(float*)&_w; }
    /* mov 0x0C,r0 */
    c->r[0] = (u32)(s32)(12);
    /* float fpul,fr3 */
    c->fr[3] = (float)(s32)c->fpul;
    /* fmac fr0,fr3,fr2 */
    c->fr[2] = fmaf(c->fr[0], c->fr[3], c->fr[2]);
    /* fmov fr2,@(r0,r15) */
    { float _f=c->fr[2]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov.w @(loc_8c034604,PC),r0 */
    c->r[0] = 0xe4u; /* pool loc_8c034604 */
    /* fmov @(r0,r14),fr4 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[4] = *(float*)&_w; }
    if((c->r[9] & 0xFFF00000u)==0x1EA00000u && c->r[9]==0x1ea00000u){ leaf_e460(c); } else if((c->r[9] & 0xFFF00000u)==0x1EA00000u && c->r[9]==0x1ea00001u){ leaf_e2e0(c); } else if((c->r[9] & 0xFFF00000u)==0x1EA00000u && c->r[9]==0x1ea00002u){ leaf_e860(c); } else if((c->r[9] & 0xFFF00000u)==0x1EA00000u && c->r[9]==0x1ea00003u){ submit_1244b0(c); } else { /* unresolved jsr */ }
    /* exts.w r8,r3 */
    c->r[3] = (u32)(s32)(s16)c->r[8];
    /* mov.w @(loc_8c03460e,PC),r0 */
    c->r[0] = 0xf0u; /* pool loc_8c03460e */
    /* lds r3,fpul */
    c->fpul = c->r[3];
    /* neg r10,r10 */
    c->r[10] = (u32)(0 - (s32)c->r[10]);
    /* fmov fr0,fr2 */
    c->fr[2] = c->fr[0];
    /* fmov @(r0,r14),fr0 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[0] = *(float*)&_w; }
    /* mov 0x10,r0 */
    c->r[0] = (u32)(s32)(16);
    /* float fpul,fr3 */
    c->fr[3] = (float)(s32)c->fpul;
    /* fmac fr0,fr3,fr2 */
    c->fr[2] = fmaf(c->fr[0], c->fr[3], c->fr[2]);
    /* fmov fr2,@(r0,r15) */
    { float _f=c->fr[2]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* neg r8,r0 */
    c->r[0] = (u32)(0 - (s32)c->r[8]);
    /* mov.w r0,@(0x14,r15) */
    w16(c, (c->r[15] + 0x14u), c->r[0]);
loc_8c034588:; /* bb */
    /* mov.w @(loc_8c034610,PC),r0 */
    c->r[0] = 0xe8u; /* pool loc_8c034610 */
    /* mov 0x20,r8 */
    c->r[8] = (u32)(s32)(32);
    /* mov.l @(loc_8c034620,PC),r1 */
    c->r[1] = 0x8c1f9d94u; /* pool loc_8c034620 */
    /* mov 0x10,r9 */
    c->r[9] = (u32)(s32)(16);
    /* fmov @(r0,r14),fr3 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[3] = *(float*)&_w; }
    /* mov 0x38,r0 */
    c->r[0] = (u32)(s32)(56);
    /* fldi0 fr14 */
    c->fr[14] = 0.0f;
    /* fmov fr3,@(r0,r15) */
    { float _f=c->fr[3]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov.w @(loc_8c034600,PC),r0 */
    c->r[0] = 0xdcu; /* pool loc_8c034600 */
    /* mov.l @r1,r3 */
    c->r[3] = r32(c, c->r[1]);
    /* mov.l @(r0,r14),r2 */
    c->r[2] = r32(c, (c->r[14] + c->r[0]));
    /* mov.w @(loc_8c034612,PC),r0 */
    c->r[0] = 0x108u; /* pool loc_8c034612 */
    /* add r3,r2 */
    c->r[2] += c->r[3];
    /* mov.l r2,@(0x2C,r15) */
    w32(c, (c->r[15] + 0x2cu), c->r[2]);
    /* mov.l @(loc_8c034624,PC),r2 */
    c->r[2] = 0x8c1f9d84u; /* pool loc_8c034624 */
    /* fmov @(r0,r14),fr3 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[3] = *(float*)&_w; }
    /* mov 0x58,r0 */
    c->r[0] = (u32)(s32)(88);
    /* fmov fr3,@(r0,r15) */
    { float _f=c->fr[3]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov 0x5C,r0 */
    c->r[0] = (u32)(s32)(92);
    /* mov.l @r2,r3 */
    c->r[3] = r32(c, c->r[2]);
    /* mov.l r3,@(r0,r15) */
    w32(c, (c->r[15] + c->r[0]), c->r[3]);
    /* mov 0x64,r0 */
    c->r[0] = (u32)(s32)(100);
    /* mov 0xFF,r3 */
    c->r[3] = (u32)(s32)(-1);
    /* mov.l r3,@(r0,r15) */
    w32(c, (c->r[15] + c->r[0]), c->r[3]);
    /* mov 0x68,r0 */
    c->r[0] = (u32)(s32)(104);
    /* mov.l r12,@(r0,r15) */
    w32(c, (c->r[15] + c->r[0]), c->r[12]);
    /* mov.l r12,@(0x18,r15) */
    w32(c, (c->r[15] + 0x18u), c->r[12]);
    /* mov.l r12,@(0x1C,r15) */
    w32(c, (c->r[15] + 0x1cu), c->r[12]);
    /* fldi1 fr15 */
    c->fr[15] = 1.0f;
    goto loc_8c03489e;
loc_8c0345c4:; /* bb */
    /* mov.w @(loc_8c034614,PC),r0 */
    c->r[0] = 0x15cu; /* pool loc_8c034614 */
    /* mov.w @(loc_8c034616,PC),r1 */
    c->r[1] = 0x180u; /* pool loc_8c034616 */
    /* mov.l @(r0,r14),r4 */
    c->r[4] = r32(c, (c->r[14] + c->r[0]));
    /* mov.w @(0x6,r11),r0 */
    c->r[0] = r16s(c, (c->r[11] + 0x6u));
    /* extu.w r0,r0 */
    c->r[0] = c->r[0] & 0xFFFFu;
    /* shll2 r0 */
    c->r[0] <<= 2;
    /* mov.l @(r0,r4),r3 */
    c->r[3] = r32(c, (c->r[4] + c->r[0]));
    /* mov.b @(0x1,r13),r0 */
    c->r[0] = r8s(c, (c->r[13] + 0x1u));
    /* add r3,r4 */
    c->r[4] += c->r[3];
    /* extu.b r0,r0 */
    c->r[0] = c->r[0] & 0xFFu;
    /* add 0x01,r0 */
    c->r[0] += (u32)(s32)(1);
    /* mov.l r0,@(0x4,r15) */
    w32(c, (c->r[15] + 0x4u), c->r[0]);
    /* mova @(loc_8c034628,PC),r0 */
    c->r[0] = 0xF0000000u; c->_pool = 0x42000000u; /* mova loc_8c034628 */
    /* mov.b @r13,r3 */
    c->r[3] = r8s(c, c->r[13]);
    /* fmov @r0,fr2 */
    { u32 _b=c->_pool; c->fr[2] = *(float*)&_b; }
    /* extu.b r3,r3 */
    c->r[3] = c->r[3] & 0xFFu;
    /* mov.w @(loc_8c034600,PC),r0 */
    c->r[0] = 0xdcu; /* pool loc_8c034600 */
    /* lds r3,fpul */
    c->fpul = c->r[3];
    /* mov.l @(0x4,r15),r2 */
    c->r[2] = r32(c, (c->r[15] + 0x4u));
    /* mov.l @(r0,r14),r3 */
    c->r[3] = r32(c, (c->r[14] + c->r[0]));
    /* float fpul,fr3 */
    c->fr[3] = (float)(s32)c->fpul;
    /* add r3,r2 */
    c->r[2] += c->r[3];
    /* cmp/gt r1,r2 */
    c->sr_t = ((s32)c->r[2] > (s32)c->r[1]);
    /* fmov fr3,fr4 */
    c->fr[4] = c->fr[3];
    /* fdiv fr2,fr4 */
    c->fr[4] = c->fr[4] / c->fr[2];
    if(!c->sr_t) goto loc_8c03462c;
    /* mov 0xFF,r0 */
    c->r[0] = (u32)(s32)(-1);
    goto loc_8c0348ac;
loc_8c03462c:; /* bb */
    /* fmov fr15,fr5 */
    c->fr[5] = c->fr[15];
    /* fsub fr4,fr5 */
    c->fr[5] = c->fr[5] - c->fr[4];
    /* mov 0x44,r0 */
    c->r[0] = (u32)(s32)(68);
    /* fmov fr14,@(r0,r15) */
    { float _f=c->fr[14]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov 0x48,r0 */
    c->r[0] = (u32)(s32)(72);
    /* fmov fr5,@(r0,r15) */
    { float _f=c->fr[5]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov 0x4C,r0 */
    c->r[0] = (u32)(s32)(76);
    /* fmov fr4,@(r0,r15) */
    { float _f=c->fr[4]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov 0x50,r0 */
    c->r[0] = (u32)(s32)(80);
    /* fmov fr15,@(r0,r15) */
    { float _f=c->fr[15]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov.w @(loc_8c0346f4,PC),r0 */
    c->r[0] = 0xecu; /* pool loc_8c0346f4 */
    /* fmov @(r0,r14),fr3 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[3] = *(float*)&_w; }
    /* mov 0x3C,r0 */
    c->r[0] = (u32)(s32)(60);
    /* fmul fr4,fr3 */
    c->fr[3] = c->fr[3] * c->fr[4];
    /* fmov fr3,@(r0,r15) */
    { float _f=c->fr[3]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov.w @(loc_8c0346f6,PC),r0 */
    c->r[0] = 0xf0u; /* pool loc_8c0346f6 */
    /* fmov @(r0,r14),fr3 */
    { u32 _w=r32(c,(c->r[14] + c->r[0])); c->fr[3] = *(float*)&_w; }
    /* mov 0x40,r0 */
    c->r[0] = (u32)(s32)(64);
    /* fmul fr4,fr3 */
    c->fr[3] = c->fr[3] * c->fr[4];
    /* fmov fr3,@(r0,r15) */
    { float _f=c->fr[3]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov.w @(0x2,r11),r0 */
    c->r[0] = r16s(c, (c->r[11] + 0x2u));
    /* mov.w @r11,r5 */
    c->r[5] = r16s(c, c->r[11]);
    /* mov.w r0,@(0x8,r15) */
    w16(c, (c->r[15] + 0x8u), c->r[0]);
    /* mov 0x24,r0 */
    c->r[0] = (u32)(s32)(36);
    /* mov.w r12,@(r0,r15) */
    w16(c, (c->r[15] + c->r[0]), c->r[12]);
    /* mov 0x20,r0 */
    c->r[0] = (u32)(s32)(32);
    /* mov.w r12,@(r0,r15) */
    w16(c, (c->r[15] + c->r[0]), c->r[12]);
    /* mov.w @(0x8,r15),r0 */
    c->r[0] = r16s(c, (c->r[15] + 0x8u));
    /* mov r0,r3 */
    c->r[3] = c->r[0];
    /* mov.w @(0x14,r15),r0 */
    c->r[0] = r16s(c, (c->r[15] + 0x14u));
    /* mov r0,r6 */
    c->r[6] = c->r[0];
    /* sub r3,r6 */
    c->r[6] -= c->r[3];
    /* mov.w @(loc_8c0346f8,PC),r0 */
    c->r[0] = 0x110u; /* pool loc_8c0346f8 */
    /* mov r4,r1 */
    c->r[1] = c->r[4];
    /* mov.l @(loc_8c034700,PC),r2 */
    c->r[2] = 0x8c1f9d88u; /* pool loc_8c034700 */
    /* add 0x01,r1 */
    c->r[1] += (u32)(s32)(1);
    /* mov.l @r2,r7 */
    c->r[7] = r32(c, c->r[2]);
    /* mov.l r1,@r15 */
    w32(c, c->r[15], c->r[1]);
    /* mov.l @(r0,r14),r3 */
    c->r[3] = r32(c, (c->r[14] + c->r[0]));
    /* tst r3,r3 */
    c->sr_t = ((c->r[3] & c->r[3])==0);
    if(!c->sr_t) goto loc_8c034708;
    /* mov r6,r0 */
    c->r[0] = c->r[6];
    /* nop */
    ;
    /* mov 0x0D,r3 */
    c->r[3] = (u32)(s32)(13);
    /* mov.w r0,@(0x14,r15) */
    w16(c, (c->r[15] + 0x14u), c->r[0]);
    /* mov 0x60,r0 */
    c->r[0] = (u32)(s32)(96);
    /* mov.w @(loc_8c0346fc,PC),r2 */
    c->r[2] = 0x4000u; /* pool loc_8c0346fc */
    /* or r3,r7 */
    c->r[7] |= c->r[3];
    /* mov.l r7,@(r0,r15) */
    w32(c, (c->r[15] + c->r[0]), c->r[7]);
    /* mov.w @(loc_8c0346fa,PC),r0 */
    c->r[0] = 0x104u; /* pool loc_8c0346fa */
    /* mov.l @(r0,r14),r1 */
    c->r[1] = r32(c, (c->r[14] + c->r[0]));
    /* mov 0x54,r0 */
    c->r[0] = (u32)(s32)(84);
    /* mov.l r1,@(r0,r15) */
    w32(c, (c->r[15] + c->r[0]), c->r[1]);
    /* mov.w @(0x4,r11),r0 */
    c->r[0] = r16s(c, (c->r[11] + 0x4u));
    /* extu.w r0,r0 */
    c->r[0] = c->r[0] & 0xFFFFu;
    /* tst r2,r0 */
    c->sr_t = ((c->r[2] & c->r[0])==0);
    /* sub r5,r10 */
    c->r[10] -= c->r[5];
    if(c->sr_t) goto loc_8c0346c4;
    /* mov.l @(loc_8c034700,PC),r1 */
    c->r[1] = 0x8c1f9d88u; /* pool loc_8c034700 */
    /* mov.l @r1,r0 */
    c->r[0] = r32(c, c->r[1]);
    /* or 0x05,r0 */
    c->r[0] |= 0x5u;
    /* mov r0,r3 */
    c->r[3] = c->r[0];
    /* mov 0x60,r0 */
    c->r[0] = (u32)(s32)(96);
    /* or r8,r3 */
    c->r[3] |= c->r[8];
    /* mov.l r3,@(r0,r15) */
    w32(c, (c->r[15] + c->r[0]), c->r[3]);
    /* mov 0x48,r0 */
    c->r[0] = (u32)(s32)(72);
    /* fmov fr14,@(r0,r15) */
    { float _f=c->fr[14]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov 0x50,r0 */
    c->r[0] = (u32)(s32)(80);
    /* fmov fr4,@(r0,r15) */
    { float _f=c->fr[4]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov 0x20,r0 */
    c->r[0] = (u32)(s32)(32);
    /* mov.l @r15,r3 */
    c->r[3] = r32(c, c->r[15]);
    /* mov.b @r3,r3 */
    c->r[3] = r8s(c, c->r[3]);
    /* extu.b r3,r3 */
    c->r[3] = c->r[3] & 0xFFu;
    /* shll2 r3 */
    c->r[3] <<= 2;
    /* shll r3 */
    c->r[3] <<= 1;
    /* mov.w r3,@(r0,r15) */
    w16(c, (c->r[15] + c->r[0]), c->r[3]);
loc_8c0346c4:; /* bb */
    /* mov.w @(0x4,r11),r0 */
    c->r[0] = r16s(c, (c->r[11] + 0x4u));
    /* mov.l @(loc_8c034704,PC),r3 */
    c->r[3] = 0x8000u; /* pool loc_8c034704 */
    /* extu.w r0,r0 */
    c->r[0] = c->r[0] & 0xFFFFu;
    /* tst r3,r0 */
    c->sr_t = ((c->r[3] & c->r[0])==0);
    if(c->sr_t) goto loc_8c034782;
    /* mov 0x60,r0 */
    c->r[0] = (u32)(s32)(96);
    /* mov.l @(r0,r15),r1 */
    c->r[1] = r32(c, (c->r[15] + c->r[0]));
    /* mov 0x60,r0 */
    c->r[0] = (u32)(s32)(96);
    /* or r9,r1 */
    c->r[1] |= c->r[9];
    /* mov.l r1,@(r0,r15) */
    w32(c, (c->r[15] + c->r[0]), c->r[1]);
    /* mov 0x44,r0 */
    c->r[0] = (u32)(s32)(68);
    /* fmov fr5,@(r0,r15) */
    { float _f=c->fr[5]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov 0x4C,r0 */
    c->r[0] = (u32)(s32)(76);
    /* fmov fr15,@(r0,r15) */
    { float _f=c->fr[15]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov 0x24,r0 */
    c->r[0] = (u32)(s32)(36);
    /* mov.b @r4,r2 */
    c->r[2] = r8s(c, c->r[4]);
    /* mov.b @r13,r1 */
    c->r[1] = r8s(c, c->r[13]);
    /* extu.b r2,r2 */
    c->r[2] = c->r[2] & 0xFFu;
    /* shll2 r2 */
    c->r[2] <<= 2;
    /* extu.b r1,r1 */
    c->r[1] = c->r[1] & 0xFFu;
    /* shll r2 */
    c->r[2] <<= 1;
    /* sub r1,r2 */
    c->r[2] -= c->r[1];
    /* mov.w r2,@(r0,r15) */
    w16(c, (c->r[15] + c->r[0]), c->r[2]);
    goto loc_8c034782;
loc_8c034708:; /* bb */
    /* mov r6,r0 */
    c->r[0] = c->r[6];
    /* nop */
    ;
    /* mov 0x0F,r3 */
    c->r[3] = (u32)(s32)(15);
    /* mov.w r0,@(0x14,r15) */
    w16(c, (c->r[15] + 0x14u), c->r[0]);
    /* mov 0x60,r0 */
    c->r[0] = (u32)(s32)(96);
    /* or r3,r7 */
    c->r[7] |= c->r[3];
    /* mov.l r7,@(r0,r15) */
    w32(c, (c->r[15] + c->r[0]), c->r[7]);
    /* mov.w @(loc_8c03480c,PC),r0 */
    c->r[0] = 0x104u; /* pool loc_8c03480c */
    /* mov.l @(r0,r14),r1 */
    c->r[1] = r32(c, (c->r[14] + c->r[0]));
    /* mov 0x54,r0 */
    c->r[0] = (u32)(s32)(84);
    /* neg r1,r1 */
    c->r[1] = (u32)(0 - (s32)c->r[1]);
    /* mov.l r1,@(r0,r15) */
    w32(c, (c->r[15] + c->r[0]), c->r[1]);
    /* mov 0x24,r0 */
    c->r[0] = (u32)(s32)(36);
    /* mov.b @r4,r2 */
    c->r[2] = r8s(c, c->r[4]);
    /* mov.b @r13,r1 */
    c->r[1] = r8s(c, c->r[13]);
    /* extu.b r2,r2 */
    c->r[2] = c->r[2] & 0xFFu;
    /* shll2 r2 */
    c->r[2] <<= 2;
    /* extu.b r1,r1 */
    c->r[1] = c->r[1] & 0xFFu;
    /* shll r2 */
    c->r[2] <<= 1;
    /* sub r1,r2 */
    c->r[2] -= c->r[1];
    /* mov.w r2,@(r0,r15) */
    w16(c, (c->r[15] + c->r[0]), c->r[2]);
    /* mov.w @(0x4,r11),r0 */
    c->r[0] = r16s(c, (c->r[11] + 0x4u));
    /* mov.w @(loc_8c03480e,PC),r2 */
    c->r[2] = 0x4000u; /* pool loc_8c03480e */
    /* extu.w r0,r0 */
    c->r[0] = c->r[0] & 0xFFFFu;
    /* tst r2,r0 */
    c->sr_t = ((c->r[2] & c->r[0])==0);
    /* add r5,r10 */
    c->r[10] += c->r[5];
    if(c->sr_t) goto loc_8c034762;
    /* mov.l @(loc_8c034814,PC),r1 */
    c->r[1] = 0x8c1f9d88u; /* pool loc_8c034814 */
    /* mov.l @r1,r0 */
    c->r[0] = r32(c, c->r[1]);
    /* or 0x07,r0 */
    c->r[0] |= 0x7u;
    /* mov r0,r3 */
    c->r[3] = c->r[0];
    /* mov 0x60,r0 */
    c->r[0] = (u32)(s32)(96);
    /* or r8,r3 */
    c->r[3] |= c->r[8];
    /* mov.l r3,@(r0,r15) */
    w32(c, (c->r[15] + c->r[0]), c->r[3]);
    /* mov 0x48,r0 */
    c->r[0] = (u32)(s32)(72);
    /* fmov fr14,@(r0,r15) */
    { float _f=c->fr[14]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov 0x50,r0 */
    c->r[0] = (u32)(s32)(80);
    /* fmov fr4,@(r0,r15) */
    { float _f=c->fr[4]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov 0x20,r0 */
    c->r[0] = (u32)(s32)(32);
    /* mov.l @r15,r3 */
    c->r[3] = r32(c, c->r[15]);
    /* mov.b @r3,r3 */
    c->r[3] = r8s(c, c->r[3]);
    /* extu.b r3,r3 */
    c->r[3] = c->r[3] & 0xFFu;
    /* shll2 r3 */
    c->r[3] <<= 2;
    /* shll r3 */
    c->r[3] <<= 1;
    /* mov.w r3,@(r0,r15) */
    w16(c, (c->r[15] + c->r[0]), c->r[3]);
loc_8c034762:; /* bb */
    /* mov.w @(0x4,r11),r0 */
    c->r[0] = r16s(c, (c->r[11] + 0x4u));
    /* mov.l @(loc_8c034818,PC),r3 */
    c->r[3] = 0x8000u; /* pool loc_8c034818 */
    /* extu.w r0,r0 */
    c->r[0] = c->r[0] & 0xFFFFu;
    /* tst r3,r0 */
    c->sr_t = ((c->r[3] & c->r[0])==0);
    if(!c->sr_t) goto loc_8c034782;
    /* mov 0x60,r0 */
    c->r[0] = (u32)(s32)(96);
    /* mov.l @(r0,r15),r1 */
    c->r[1] = r32(c, (c->r[15] + c->r[0]));
    /* mov 0x60,r0 */
    c->r[0] = (u32)(s32)(96);
    /* or r9,r1 */
    c->r[1] |= c->r[9];
    /* mov.l r1,@(r0,r15) */
    w32(c, (c->r[15] + c->r[0]), c->r[1]);
    /* mov 0x44,r0 */
    c->r[0] = (u32)(s32)(68);
    /* fmov fr5,@(r0,r15) */
    { float _f=c->fr[5]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov 0x4C,r0 */
    c->r[0] = (u32)(s32)(76);
    /* fmov fr15,@(r0,r15) */
    { float _f=c->fr[15]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov 0x24,r0 */
    c->r[0] = (u32)(s32)(36);
    /* mov.w r12,@(r0,r15) */
    w16(c, (c->r[15] + c->r[0]), c->r[12]);
loc_8c034782:; /* bb */
    /* mov.l r12,@(0x8,r15) */
    w32(c, (c->r[15] + 0x8u), c->r[12]);
    /* mov.l @(0x4,r15),r3 */
    c->r[3] = r32(c, (c->r[15] + 0x4u));
    /* cmp/pl r3 */
    c->sr_t = ((s32)c->r[3] > 0);
    if(c->sr_t) goto loc_8c03478e;
    /* nop */
    ;
    goto loc_8c03488e;
loc_8c03478e:; /* bb */
    /* mov.b @r13,r5 */
    c->r[5] = r8s(c, c->r[13]);
    /* mov r15,r1 */
    c->r[1] = c->r[15];
    /* mov.b @(0x2,r13),r0 */
    c->r[0] = r8s(c, (c->r[13] + 0x2u));
    /* add 0x20,r1 */
    c->r[1] += (u32)(s32)(32);
    /* extu.b r5,r5 */
    c->r[5] = c->r[5] & 0xFFu;
    /* extu.b r0,r0 */
    c->r[0] = c->r[0] & 0xFFu;
    /* muls.w r5,r0 */
    c->macl = (u32)((s32)(s16)c->r[5] * (s32)(s16)c->r[0]);
    /* mov 0x24,r0 */
    c->r[0] = (u32)(s32)(36);
    /* mov.w @(r0,r15),r3 */
    c->r[3] = r16s(c, (c->r[15] + c->r[0]));
    /* mov.b @(0x3,r13),r0 */
    c->r[0] = r8s(c, (c->r[13] + 0x3u));
    /* sts macl,r4 */
    c->r[4] = c->macl;
    /* extu.b r0,r0 */
    c->r[0] = c->r[0] & 0xFFu;
    /* muls.w r5,r0 */
    c->macl = (u32)((s32)(s16)c->r[5] * (s32)(s16)c->r[0]);
    /* sub r3,r4 */
    c->r[4] -= c->r[3];
    /* mov.w @r1,r3 */
    c->r[3] = r16s(c, c->r[1]);
    /* sts macl,r0 */
    c->r[0] = c->macl;
    /* mov r0,r5 */
    c->r[5] = c->r[0];
    /* mov 0x60,r0 */
    c->r[0] = (u32)(s32)(96);
    /* mov.l @(r0,r15),r2 */
    c->r[2] = r32(c, (c->r[15] + c->r[0]));
    /* tst r9,r2 */
    c->sr_t = ((c->r[9] & c->r[2])==0);
    /* sub r3,r5 */
    c->r[5] -= c->r[3];
    if(c->sr_t) goto loc_8c0347bc;
    /* neg r4,r4 */
    c->r[4] = (u32)(0 - (s32)c->r[4]);
loc_8c0347bc:; /* bb */
    /* mov 0x60,r0 */
    c->r[0] = (u32)(s32)(96);
    /* mov.l @(r0,r15),r3 */
    c->r[3] = r32(c, (c->r[15] + c->r[0]));
    /* tst r8,r3 */
    c->sr_t = ((c->r[8] & c->r[3])==0);
    /* exts.w r10,r3 */
    c->r[3] = (u32)(s32)(s16)c->r[10];
    if(c->sr_t) goto loc_8c0347c8;
    /* neg r5,r5 */
    c->r[5] = (u32)(0 - (s32)c->r[5]);
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
    goto loc_8c034864;
loc_8c03481c:; /* bb */
    /* mov.l @(loc_8c034938,PC),r3 */
    c->r[3] = 0x1ea00001u; /* leafptr bank11.loc_8c11e2e0 */
    /* mov.l @r15,r4 */
    c->r[4] = r32(c, c->r[15]);
    if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00000u){ leaf_e460(c); } else if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00001u){ leaf_e2e0(c); } else if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00002u){ leaf_e860(c); } else if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00003u){ submit_1244b0(c); } else { /* unresolved jsr */ }
    /* mov 0x0C,r0 */
    c->r[0] = (u32)(s32)(12);
    /* mov.l @(loc_8c03493c,PC),r3 */
    c->r[3] = 0x1ea00002u; /* leafptr bank11.loc_8c11e860 */
    /* fmov @(r0,r15),fr3 */
    { u32 _w=r32(c,(c->r[15] + c->r[0])); c->fr[3] = *(float*)&_w; }
    /* mov 0x58,r0 */
    c->r[0] = (u32)(s32)(88);
    /* fmac fr0,fr12,fr3 */
    c->fr[3] = fmaf(c->fr[0], c->fr[12], c->fr[3]);
    /* fmov fr3,@-r15 */
    c->r[15]-=4; { float _f=c->fr[3]; w32(c,c->r[15], *(u32*)&_f); }
    /* mov.l @(r0,r15),r4 */
    c->r[4] = r32(c, (c->r[15] + c->r[0]));
    if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00000u){ leaf_e460(c); } else if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00001u){ leaf_e2e0(c); } else if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00002u){ leaf_e860(c); } else if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00003u){ submit_1244b0(c); } else { /* unresolved jsr */ }
    /* fmov @r15+,fr2 */
    { u32 _a=c->r[15]; c->r[15]+=4; u32 _w=r32(c,_a); c->fr[2] = *(float*)&_w; }
    /* mov 0x30,r0 */
    c->r[0] = (u32)(s32)(48);
    /* fmov fr0,fr3 */
    c->fr[3] = c->fr[0];
    /* fmov fr13,fr0 */
    c->fr[0] = c->fr[13];
    /* fmac fr0,fr3,fr2 */
    c->fr[2] = fmaf(c->fr[0], c->fr[3], c->fr[2]);
    /* mov.l @(loc_8c03493c,PC),r3 */
    c->r[3] = 0x1ea00002u; /* leafptr bank11.loc_8c11e860 */
    /* fmov fr2,@(r0,r15) */
    { float _f=c->fr[2]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* mov 0x54,r0 */
    c->r[0] = (u32)(s32)(84);
    /* mov.l @(r0,r15),r4 */
    c->r[4] = r32(c, (c->r[15] + c->r[0]));
    if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00000u){ leaf_e460(c); } else if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00001u){ leaf_e2e0(c); } else if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00002u){ leaf_e860(c); } else if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00003u){ submit_1244b0(c); } else { /* unresolved jsr */ }
    /* fmul fr0,fr12 */
    c->fr[12] = c->fr[12] * c->fr[0];
    /* mov 0x10,r0 */
    c->r[0] = (u32)(s32)(16);
    /* fmov @(r0,r15),fr3 */
    { u32 _w=r32(c,(c->r[15] + c->r[0])); c->fr[3] = *(float*)&_w; }
    /* mov 0x58,r0 */
    c->r[0] = (u32)(s32)(88);
    /* mov.l @(loc_8c034938,PC),r3 */
    c->r[3] = 0x1ea00001u; /* leafptr bank11.loc_8c11e2e0 */
    /* fsub fr12,fr3 */
    c->fr[3] = c->fr[3] - c->fr[12];
    /* fmov fr3,@-r15 */
    c->r[15]-=4; { float _f=c->fr[3]; w32(c,c->r[15], *(u32*)&_f); }
    /* mov.l @(r0,r15),r4 */
    c->r[4] = r32(c, (c->r[15] + c->r[0]));
    if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00000u){ leaf_e460(c); } else if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00001u){ leaf_e2e0(c); } else if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00002u){ leaf_e860(c); } else if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00003u){ submit_1244b0(c); } else { /* unresolved jsr */ }
    /* fmov @r15+,fr2 */
    { u32 _a=c->r[15]; c->r[15]+=4; u32 _w=r32(c,_a); c->fr[2] = *(float*)&_w; }
    /* mov 0x34,r0 */
    c->r[0] = (u32)(s32)(52);
    /* fmov fr0,fr3 */
    c->fr[3] = c->fr[0];
    /* fmov fr13,fr0 */
    c->fr[0] = c->fr[13];
    /* fmac fr0,fr3,fr2 */
    c->fr[2] = fmaf(c->fr[0], c->fr[3], c->fr[2]);
    /* fmov fr2,@(r0,r15) */
    { float _f=c->fr[2]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
loc_8c034864:; /* bb */
    /* mova @(loc_8c034940,PC),r0 */
    c->r[0] = 0xF0000000u; c->_pool = 0x3a83126fu; /* mova loc_8c034940 */
    /* mov.l @(loc_8c034944,PC),r3 */
    c->r[3] = 0x1ea00003u; /* leafptr bank12.loc_8c1244b0 */
    /* fmov @r0,fr3 */
    { u32 _b=c->_pool; c->fr[3] = *(float*)&_b; }
    /* mov 0x38,r0 */
    c->r[0] = (u32)(s32)(56);
    /* fmov @(r0,r15),fr2 */
    { u32 _w=r32(c,(c->r[15] + c->r[0])); c->fr[2] = *(float*)&_w; }
    /* mov 0x38,r0 */
    c->r[0] = (u32)(s32)(56);
    /* mov r15,r4 */
    c->r[4] = c->r[15];
    /* fadd fr3,fr2 */
    c->fr[2] = c->fr[2] + c->fr[3];
    /* fmov fr2,@(r0,r15) */
    { float _f=c->fr[2]; w32(c,(c->r[15] + c->r[0]), *(u32*)&_f); }
    /* add 0x2C,r4 */
    c->r[4] += (u32)(s32)(44);
    if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00000u){ leaf_e460(c); } else if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00001u){ leaf_e2e0(c); } else if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00002u){ leaf_e860(c); } else if((c->r[3] & 0xFFF00000u)==0x1EA00000u && c->r[3]==0x1ea00003u){ submit_1244b0(c); } else { /* unresolved jsr */ }
    /* mov.l @(0x2C,r15),r2 */
    c->r[2] = r32(c, (c->r[15] + 0x2cu));
    /* add 0x01,r2 */
    c->r[2] += (u32)(s32)(1);
    /* mov.l r2,@(0x2C,r15) */
    w32(c, (c->r[15] + 0x2cu), c->r[2]);
    /* mov.l @(0x8,r15),r3 */
    c->r[3] = r32(c, (c->r[15] + 0x8u));
    /* add 0x01,r3 */
    c->r[3] += (u32)(s32)(1);
    /* mov.l r3,@(0x8,r15) */
    w32(c, (c->r[15] + 0x8u), c->r[3]);
    /* mov.l @(0x4,r15),r2 */
    c->r[2] = r32(c, (c->r[15] + 0x4u));
    /* cmp/ge r2,r3 */
    c->sr_t = ((s32)c->r[3] >= (s32)c->r[2]);
    /* add 0x04,r13 */
    c->r[13] += (u32)(s32)(4);
    if(!c->sr_t) goto loc_8c03478e;
loc_8c03488e:; /* bb */
    /* mov.l @(0x1C,r15),r1 */
    c->r[1] = r32(c, (c->r[15] + 0x1cu));
    /* add 0x08,r11 */
    c->r[11] += (u32)(s32)(8);
    /* mov.l @(0x4,r15),r3 */
    c->r[3] = r32(c, (c->r[15] + 0x4u));
    /* add r3,r1 */
    c->r[1] += c->r[3];
    /* mov.l r1,@(0x1C,r15) */
    w32(c, (c->r[15] + 0x1cu), c->r[1]);
    /* mov.l @(0x18,r15),r2 */
    c->r[2] = r32(c, (c->r[15] + 0x18u));
    /* add 0x01,r2 */
    c->r[2] += (u32)(s32)(1);
    /* mov.l r2,@(0x18,r15) */
    w32(c, (c->r[15] + 0x18u), c->r[2]);
loc_8c03489e:; /* bb */
    /* mov.l @(0x28,r15),r1 */
    c->r[1] = r32(c, (c->r[15] + 0x28u));
    /* mov.l @(0x18,r15),r3 */
    c->r[3] = r32(c, (c->r[15] + 0x18u));
    /* cmp/gt r3,r1 */
    c->sr_t = ((s32)c->r[1] > (s32)c->r[3]);
    if(!c->sr_t) goto loc_8c0348aa;
    /* nop */
    ;
    goto loc_8c0345c4;
loc_8c0348aa:; /* bb */
    /* mov.l @(0x1C,r15),r0 */
    c->r[0] = r32(c, (c->r[15] + 0x1cu));
loc_8c0348ac:; /* bb */
    /* add 0x7C,r15 */
    c->r[15] += (u32)(s32)(124);
    /* lds.l @r15+,pr */
    c->pr = r32(c, c->r[15]); c->r[15]+=4;
    /* fmov @r15+,fr12 */
    { u32 _a=c->r[15]; c->r[15]+=4; u32 _w=r32(c,_a); c->fr[12] = *(float*)&_w; }
    /* fmov @r15+,fr13 */
    { u32 _a=c->r[15]; c->r[15]+=4; u32 _w=r32(c,_a); c->fr[13] = *(float*)&_w; }
    /* fmov @r15+,fr14 */
    { u32 _a=c->r[15]; c->r[15]+=4; u32 _w=r32(c,_a); c->fr[14] = *(float*)&_w; }
    /* fmov @r15+,fr15 */
    { u32 _a=c->r[15]; c->r[15]+=4; u32 _w=r32(c,_a); c->fr[15] = *(float*)&_w; }
    /* mov.l @r15+,r8 */
    { u32 _a=c->r[15]; c->r[15]+=4; c->r[8] = r32(c,_a); }
    /* mov.l @r15+,r9 */
    { u32 _a=c->r[15]; c->r[15]+=4; c->r[9] = r32(c,_a); }
    /* mov.l @r15+,r10 */
    { u32 _a=c->r[15]; c->r[15]+=4; c->r[10] = r32(c,_a); }
    /* mov.l @r15+,r11 */
    { u32 _a=c->r[15]; c->r[15]+=4; c->r[11] = r32(c,_a); }
    /* mov.l @r15+,r12 */
    { u32 _a=c->r[15]; c->r[15]+=4; c->r[12] = r32(c,_a); }
    /* mov.l @r15+,r13 */
    { u32 _a=c->r[15]; c->r[15]+=4; c->r[13] = r32(c,_a); }
    /* mov.l @r15+,r14 */
    { u32 _a=c->r[15]; c->r[15]+=4; c->r[14] = r32(c,_a); }
    return;
}
