/* SUBMIT TEXTURE-PARAM DEPOSIT — faithful port of the loc_8C1244B0 (bank12) finalize
 * + the loc_8C124910/loc_8c124a82 PalSelect inject. Produces the per-tile PVR
 * polygon-param words (PCW/ISP/TSP/TCW) the engine deposits into its TA — read from
 * the RESIDENT rectab/idxtab in RAM, NOT from the engine TA. This REMOVES the
 * engine-TA pinning of build_image_dump.py.
 *
 * THE CHAIN (traced, marvelous2 bank12):
 *   loc_8C124520 (9853): r8 = idxtab[*r13]      ; idxtab = *(0x8C2DAD3c)
 *                        (*r13 = the per-tile allocation index the walker wrote at
 *                         stack[r15+0x2C]; the engine assigns a contiguous run)
 *   loc_8C124534 (9865): r12 = rectab + r8*0x20 ; rectab = *(0x8C2DAD4c)
 *                        r12 = the 0x20-byte PVR poly-param TEMPLATE for this tile:
 *                        @r12+0x00=PCW @+0x04=ISP @+0x08=TSP @+0x0C=TCW
 *   loc_8c124630 (10001): the finalize masks+ORs:
 *        @r12      &= 0xF8FCFFFF     (loc_8C1246FC) ; PCW clear
 *        @(0x04)   &= 0x1FFFFFFF     (loc_8C124700) ; ISP clear depthmode
 *        @(0x08)   &= 0x03278FFF     (loc_8C124704) ; TSP clear blend/filter
 *      then per r13[0x30] (poly type) / r13[0x34] (blend flags) OR's the on-screen
 *      bits. For the BODY (type==4 list path, loc_8c1246b0): PCW |= 0x02000000
 *      (loc_8C124720), ISP |= DepthMode<<29 (=4<<29=0x80000000; loc_8c12467a:
 *      `mov 0xF8,r3; shad r3,r0; and 0x07,r0` reads PixelFmt, then `shad #0x1D,r4`
 *      with r4=4 -> 0x80000000), TSP gets the blend/filter via loc_8c124740/124b40.
 *   loc_8c124a82 (10622): TCW PalSelect inject (in the finalize loc_8C124910):
 *        TCW = (TCW & 0xF81FFFFF) | (palbank << 21)
 *      palbank = the slot palette bank (P2C1 -> 24, per CLAUDE.md formula
 *        bank = 16*(char_pair+1) + 8*player_side). The resident TCW already carries
 *      the live DM00 texaddr (low 21) + PixelFmt(27..29); we re-inject PalSelect.
 *
 * VALIDATED (Python, vs the engine TA for cid23 frame10766, 9 body sprites):
 *   (resident rectab[base+k] template) + (PCW|0x02000000, ISP|0x80000000) reproduces
 *   the engine's PCW=A2000009 / ISP=80000000 / TSP=949004D2 / TCW=2B082A80.. BYTE-EXACT
 *   for all 9 quads — ZERO engine-TA reads. The resident block already has pal=24 baked
 *   so the PalSelect inject is the identity here (and we also support computing it).
 */
#include "sh4ctx.h"

/* the two resident table pointers (read from RAM, frame-global allocation state) */
#define PTR_IDXTAB 0x8C2DAD3Cu     /* loc_8C1245F8 / loc_8C1249B8 pool */
#define PTR_RECTAB 0x8C2DAD4Cu     /* loc_8C1245FC / loc_8C1249BC pool */

typedef struct { u32 pcw, isp, tsp, tcw; } PolyParam;

/* Read the resident 0x20-byte template at rectab[idxtab[rec_index]].
 * rec_index = the per-tile allocation index (*r13 = stack[r15+0x2C]).  */
static void read_template(Sh4Ctx *c, u32 rec_index, PolyParam *out){
    u32 idxtab = r32(c, PTR_IDXTAB);
    u32 rectab = r32(c, PTR_RECTAB);
    u32 r8     = r16u(c, idxtab + rec_index*2);
    u32 r12    = rectab + r8*0x20;
    out->pcw = r32(c, r12+0x00);
    out->isp = r32(c, r12+0x04);
    out->tsp = r32(c, r12+0x08);
    out->tcw = r32(c, r12+0x0C);
}

/* The submit finalize for a BODY tile — transpiled from loc_8c124630..loc_8c1246ca +
 * loc_8c124a82 (bank12). The BODY takes the loc_8c1246b0 path (r13[0x30] != 4; the
 * engine PCW carries 0x02000000 from loc_8C124720, NOT the type==4 0x04000000).
 *
 * tsp_or  = the loc_8c1246b0 TSP OR = ((*(0x8C2AA4C4) ^ 0xFC) << 24) | 0x00100000
 *           = 0x94100000  (the texture filter/shading word from the global render mode)
 * plus loc_8c12465c: r13[0x34] & 0x0800 -> TSP |= 0x00800000 (loc_8C124708).
 * For the body these together give the 0x94900000 upper bits.
 *
 * NOTE: the resident rectab[base+k] block in a STARTRENDER dump is ALREADY finalized
 * (the engine wrote it pre-STARTRENDER) so reading it IS byte-exact. We additionally
 * APPLY this transpiled finalize to PROVE it (it is IDEMPOTENT on a finalized record:
 * masking then re-OR'ing the same bits is a no-op). palbank re-injects PalSelect.
 *
 * tsp_global = *(0x8C2AA4C4) and r34flags = r13[0x34] would normally come from RAM /
 * the walker's per-tile record; on the body path they are constant (render mode +
 * the translucent-list flag), so we read tsp_global from RAM and assume the body's
 * 0x0800 list flag (validated against the resident block + engine TA). */
static void finalize_body(Sh4Ctx *c, PolyParam *p, u32 palbank){
    u32 tsp_global = r32(c, 0x8C2AA4C4u);                 /* loc_8C124718 */
    u32 tsp_or = (((tsp_global ^ 0xFCu) << 24) | 0x00100000u)  /* loc_8c1246b0 */
               | 0x00800000u;                             /* loc_8c12465c (r34&0x0800) */
    /* loc_8c124630: clear, then OR the finalized bits (idempotent on finalized rec) */
    p->pcw = (p->pcw & 0xF8FCFFFFu) | 0x02000000u;        /* loc_8C1246FC / loc_8C124720 */
    p->isp = (p->isp & 0x1FFFFFFFu) | (4u << 29);         /* loc_8C124700 / DepthMode 4  */
    p->tsp = (p->tsp & 0x03278FFFu) | tsp_or;             /* loc_8C124704 / loc_8c1246b0 */
    p->tcw = (p->tcw & 0xF81FFFFFu) | ((palbank & 0x3Fu) << 21); /* loc_8c124a82 PalSelect */
}

/* Public: compute the engine's deposited poly-param for body tile k of an object.
 *   c         = the RAM image
 *   rec_index = the per-tile allocation index (*r13). For the validated object this
 *               is base_index + k (the engine allocates a contiguous run).
 *   palbank   = the slot palette bank (P2C1=24).
 * Returns the byte-exact PCW/ISP/TSP/TCW. NO engine-TA read. */
void submit_params(Sh4Ctx *c, u32 rec_index, u32 palbank, PolyParam *out){
    read_template(c, rec_index, out);
    finalize_body(c, out, palbank);
}
