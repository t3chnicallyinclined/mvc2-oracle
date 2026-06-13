#include "sh4ctx.h"
/* Per-body hook: runs render_object_full AND advances the submit-allocation cursor +
 * records the per-object prefix-sum proof. Defined in render_frame.c. */
void render_frame_body_hook(Sh4Ctx *c, u32 node);
/* Phase-3: the effect/satellite renderer loc_8c030af8 (cat 1..4). Stub for now. */
void render_effect_030af8(Sh4Ctx *c, u32 node);

/* AUTO-GENERATED (faithful hand-port) from bank03.asm loc_8c0308c2 "Render_sprites".
 * Entry: walks the on-screen slot table; per body node -> render_object_full. */
void render_sprites_0308c2(Sh4Ctx *c){
    /* [1208] r4 = 0x8C2895E0 (count array)   [1213] r12 = 0x8C287DE0 (ptr arrays) */
    const u32 COUNT_BASE = 0x8C2895E0u;
    const u32 PTR_BASE   = 0x8C287DE0u;
    const u32 LAYER_STRIDE = 0x180u;          /* [1211] mov.w loc_8c030924 = 0x0180 */
    u32 r8  = COUNT_BASE + 0x10u;             /* [1214] count-array END (16 layers)  */
    u32 r12 = PTR_BASE;                       /* [1213] current layer ptr-array base */
    u32 r13 = COUNT_BASE;                     /* [1215] count cursor                 */

    /* [1217] loc_8c0308e0: per-layer loop */
    for(;;){
        u32 r10 = r12;                        /* [1220] this layer's ptr-array base  */
        u32 r14 = 0;                          /* [1218] r14 = r11 = 0 (object index) */
        /* [1242] loc_8c030902: count gate (cmp/ge r3,r14; bf body) */
        for(;;){
            s32 count = r8s(c, r13);          /* [1243] mov.b @r13,r3 (sign-ext) */
            /* ROBUSTNESS (live read-set): the slot-table count is shipped per frame. A
             * negative byte already terminates (faithful: cmp/ge), but a CORRUPT large
             * positive count (stale 'slot_cnt' bytes, or a transition frame) would iterate
             * dozens of garbage ptr-array slots — each a junk "node" whose +0x3 byte and
             * +0x160 GFX2 are random => runaway tiles => the "quads=1024" over-read. MVC2
             * never packs >0x60 objects into one layer; bound the walk to that (same gate
             * the server's buildTables() uses: `cnt==0 || cnt>0x60` => skip). */
            if(!((s32)r14 < count)) break;    /* [1244-1245] cmp/ge; bf -> render */
            if(count > 0x60) break;           /* corrupt layer count: stop this layer */
            /* [1222] loc_8c0308e6: render object r14 */
            u32 r0   = r14 << 2;              /* [1225] shll2 */
            u32 node = r32(c, r10 + r0);      /* [1226] r4 = *(r0,r10) = layer_ptrs[r14] */
            /* node must be an area-3 RAM pointer (((g>>24)&0x7F)==0x0C, non-null); a junk
             * slot entry that isn't would index garbage for cat/GFX. Skip it defensively. */
            if(node == 0 || (((node >> 24) & 0x7Fu) != 0x0Cu)){ r14++; continue; }
            s32 cat  = r8s(c, node + 0x3);    /* [1227] mov.b @(0x3,r4) category byte */
            if(cat == 0){                     /* [1228-1230] tst;bf -> cat==0 = BODY */
                render_frame_body_hook(c, node); /* bsr loc_8c03093c (Render Main Sprite) */
            } else {                          /* [1236] cat!=0 = EFFECT */
                render_effect_030af8(c, node);/* bsr loc_8c030af8 (Phase-3 stub) */
            }
            r14++;                            /* [1240] loc_8c030900: add 0x01,r14 */
        }
        r13 += 1;                             /* [1246] next layer count */
        r12 += LAYER_STRIDE;                  /* [1249] next layer ptr array (delay slot) */
        if(!(r13 < r8)) break;                /* [1247-1248] cmp/hs r8,r13; bf.s loop */
    }
    /* [1251] loc_8c030910: epilogue (register restore) — no state to restore here */
}
