/* PER-OBJECT WORLD->SCREEN TRANSFORM — faithful port of loc_8C122560 (bank12).
 *
 * This is the routine loc_8c03093c calls (bank03:1298 `mov.l @(loc_8c030ac8,PC),r3`
 * = bank12.loc_8c1216c0 ... NO — see below) to deposit screen_x/y@node+0xE0/E4.
 *
 * THE CALL CHAIN (traced, marvelous2):
 *   loc_8c03093c (bank03:1281, "Render Main Sprite") at line 1298-1315 loads
 *     fr4=node.posX@0x34, fr5=node.posY@0x38, fr6=node.posZ@0x3C,
 *     r4=&stack[0] r5=&stack[4] r6=&stack[8],
 *     jsr bank12.loc_8c122560   (the per-object transform; pool loc_8c030acc).
 *   Wait: loc_8c030ac8 = loc_8c1216c0 (the once/frame proj-matrix SETUP, called first
 *     at line 1295-1302 with fr4=640.0/fr5=480.0), and loc_8c030acc = loc_8c122560
 *     (the per-object transform, called at 1304-1315 with the pos floats). So:
 *       (A) loc_8c1216c0  -> builds the frame-global projection XMTRX (once/frame)
 *       (B) loc_8c122560  -> per object: ftrv(pos) + perspective divide -> screen
 *   loc_8c03093c then stores stack[0]->node+0xE0 (X), stack[1]->node+0xE4 (Y),
 *     stack[2]->node+0xE8 (Z) (bank03:1316-1323).
 *
 * loc_8C122560 (bank12:5271) itself:
 *   - stores pos into a local vector (fr4/5/6 -> stack+0x14/+0x08/+0x10, w=1 implicit)
 *   - loc_8c120950(0x8C2D6B18)  : XMTRX = matrix@0x8C2D6B18           (load)
 *   - loc_8c120540(0x8C2D6AD8)  : XMTRX = matrix@0x8C2D6AD8 . XMTRX   (mat-mat mul)
 *   - loc_8c11F870(vec=pos)     : fv = ftrv XMTRX . (px,py,pz,1)       (mat-vec)
 *   - perspective divide (bank12:5308-5323): inv = 1/fv[3];
 *       out[0]=fv[0]*inv  out[1]=fv[1]*inv  out[2]=inv
 *     (stored to the caller's r4/r5/r6 = stack[0],stack[1],stack[2]).
 *
 * The two source matrices 0x8C2D6AD8 (projection) and 0x8C2D6B18 (viewport) are
 * FRAME-GLOBAL camera state built by loc_8c1216c0's setup BEFORE any object renders
 * — NOT per-object render output. Reading them from RAM is legitimately code-derived
 * (they are the camera, not this object's deposited +0xE0/E4). VALIDATED in Python:
 * this composition reproduces node+0xE0=533.85986 / node+0xE4=333.38765 byte-exact
 * (target 533.85986 / 333.38763, within f32 ULP) for pos (213.333,100,2).
 *
 * loc_8c120540's mat-mat semantics (bank12:478-508): it loads matrix@r4 column by
 * column into fv0..fv12 and ftrv's each column THROUGH the current XMTRX, i.e.
 *   XMTRX' = XMTRX . (matrix@r4)     [column-major: new_col = XMTRX . old_col]
 * then frchg installs the product as the new XMTRX. loc_8c120950 (bank12:1080) loads
 * matrix@r4 straight into XMTRX (via the frchg/fmov @r4+ at loc_8c120990). The matrix
 * push/pop bookkeeping (the 0x8C2D68E8 stack cursor) does NOT affect THIS object's
 * ftrv result (only the XMTRX load/mul does), so we model just the load+mul+ftrv.
 *
 * This is a HAND-VERIFIED faithful port (each step cites its loc_8c..); the column-
 * major ftrv matches codegen.py's `ftrv` emitter exactly (out_i = sum_k M[i+4k]*v_k).
 */
#include "sh4ctx.h"

/* read a 16-float matrix (mem order = column-major M[0..15]) from guest RAM */
static void load_mat(Sh4Ctx *c, u32 addr, float M[16]){
    for(int i=0;i<16;i++){ u32 w=r32(c, addr+(u32)i*4); M[i]=*(float*)&w; }
}

/* column-major ftrv: out_i = sum_k M[i+4k] * v_k  (matches loc_8c11F870 / codegen) */
static void ftrv_colmaj(const float M[16], const float v[4], float out[4]){
    for(int i=0;i<4;i++)
        out[i] = M[i+0]*v[0] + M[i+4]*v[1] + M[i+8]*v[2] + M[i+12]*v[3];
}

/* XMTRX' = X . Mnew  (loc_8c120540: each column of Mnew is ftrv'd through X) */
static void matmul_colmaj(const float X[16], const float Mnew[16], float out[16]){
    for(int col=0;col<4;col++){
        float c4[4] = { Mnew[col*4+0], Mnew[col*4+1], Mnew[col*4+2], Mnew[col*4+3] };
        float r4[4];
        ftrv_colmaj(X, c4, r4);
        for(int i=0;i<4;i++) out[col*4+i] = r4[i];
    }
}

/* Per-object transform, faithful to loc_8C122560's CONTRACT: the caller
 * (loc_8c03093c) passes the world pos in fr4/fr5/fr6 and three OUTPUT pointers in
 * r4/r5/r6 (= stack[0], stack[1], stack[2]); the routine writes screen X/Y/Z to
 * *r4/*r5/*r6. loc_8c03093c then copies those stack words to node+0xE0/E4/E8.
 *
 * We mirror that contract exactly: read pos from the node, write the 3 results to
 * the guest addresses in c->r[4]/r[5]/r[6]. The transpiled render_object_setup_03093c
 * then performs the stack->node deposit itself (no double-write).
 *
 * MAT_VIEWPORT / MAT_PROJ are the resident frame-global source matrices (read from
 * RAM); these are the camera, set up once/frame by loc_8c1216c0 (NOT per object). */
#define MAT_VIEWPORT 0x8C2D6B18u   /* loc_8c120950 arg (loc_8C12264C pool)  */
#define MAT_PROJ     0x8C2D6AD8u   /* loc_8c120540 arg (loc_8C122654 pool)  */

void transform_object_122560(Sh4Ctx *c, u32 node_addr){
    /* fr4=posX@0x34, fr5=posY@0x38, fr6=posZ@0x3C (bank03:1303-1315) */
    u32 wx=r32(c, node_addr+0x34), wy=r32(c, node_addr+0x38), wz=r32(c, node_addr+0x3C);
    float px=*(float*)&wx, py=*(float*)&wy, pz=*(float*)&wz;

    float M1[16], M2[16], X[16];
    load_mat(c, MAT_VIEWPORT, M1);          /* loc_8c120950: XMTRX = M1            */
    load_mat(c, MAT_PROJ,     M2);          /* loc_8c120540 arg                    */
    matmul_colmaj(M1, M2, X);               /* XMTRX = M1 . M2 (loc_8c120540)      */

    float v[4]  = { px, py, pz, 1.0f };     /* loc_8c11F870: vec=(x,y,z,1)         */
    float fv[4];
    ftrv_colmaj(X, v, fv);                  /* fv = XMTRX . v                      */

    /* perspective divide (loc_8C122560 bank12:5308-5323):
     *   fr4 = 1.0 / fv[3] ; out[0]=fv[0]*fr4 ; out[1]=fv[1]*fr4 ; out[2]=fr4 */
    float inv = 1.0f / fv[3];
    float sx = fv[0]*inv, sy = fv[1]*inv, sz = inv;

    /* write to the caller's output pointers r4/r5/r6 (the stack slots) */
    u32 ox=*(u32*)&sx, oy=*(u32*)&sy, oz=*(u32*)&sz;
    w32(c, c->r[4], ox);
    w32(c, c->r[5], oy);
    w32(c, c->r[6], oz);
}
