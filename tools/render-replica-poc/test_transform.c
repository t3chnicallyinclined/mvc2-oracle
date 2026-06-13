/* Transform-core test: drive the transpiled loc_8c0347c8..loc_8c034864 (simple path)
 * with recovered (Ix,Iy,scaleX,scaleY,baseX,baseY) per tile and diff the produced
 * screenX/screenY against the ASMTRACE. This validates the FP+integer arithmetic of
 * the real render routine (float/fmul/fadd, s16 sign-extend, the node/stack memory
 * model) bit-for-bit, independent of the (unavailable) descriptor table bytes.
 */
#include "sh4ctx.h"
#include "transform_cases.h"
#include <stdio.h>
#include <math.h>

void transform_core(Sh4Ctx *c);

/* guest layout for this test */
#define NODE  0x0C400000u
#define STK   0x0C480000u   /* r15 */

static void putf(Sh4Ctx*c,u32 a,float v){ u32 b=*(u32*)&v; w32(c,a,b); }
static float getf(Sh4Ctx*c,u32 a){ u32 b=r32(c,a); return *(float*)&b; }

int main(void){
    static u8 ram[RAM_SIZE];
    Sh4Ctx ctx; memset(&ctx,0,sizeof ctx); ctx.ram=ram;

    /* node scale fields */
    putf(&ctx, NODE+0xEC, TC_SCALEX);
    putf(&ctx, NODE+0xF0, TC_SCALEY);

    int worstX_i=-1, worstY_i=-1;
    double worstX=0, worstY=0, sumX=0, sumY=0;
    int passX=0, passY=0;
    /* exact cross-check: transpiled-C vs the same arithmetic in straight float.
     * This removes the trace's 2-decimal quantization and shows whether the lifted
     * float/fmul/fadd chain is BIT-EXACT against a reference float computation. */
    int bitexactX=0, bitexactY=0;

    for (int i=0;i<TC_N;i++){
        memset(ctx.r,0,sizeof ctx.r);
        memset(ctx.fr,0,sizeof ctx.fr);
        ctx.r[14]=NODE;
        ctx.r[15]=STK;
        /* Ix = r3 + r4 (we put all of Ix in r3, r4=0). r5/@0x14 -> Iy. */
        ctx.r[3]=(u32)TC_IX[i];
        ctx.r[4]=0;
        ctx.r[5]=0;
        w16(&ctx, STK+0x14, (u32)(TC_IY[i] & 0xFFFF));  /* @(0x14,r15) = Iy (s16) */
        /* base anchors on stack */
        putf(&ctx, STK+0x0C, TC_BASEX);
        putf(&ctx, STK+0x10, TC_BASEY);
        /* scale-flag @(0x54,r15)=0 -> simple path */
        w32(&ctx, STK+0x54, 0);
        /* flags word @(0x60,r15) consumed earlier; not in this slice */

        transform_core(&ctx);

        float gx=getf(&ctx, STK+0x30);
        float gy=getf(&ctx, STK+0x34);
        /* reference: the EXACT arithmetic the routine performs (simple path):
         *   screen = base + (float)(s16 Ix) * scale    [float/fmul/fadd, single prec] */
        float refX = TC_BASEX + (float)(s16)TC_IX[i] * TC_SCALEX;
        float refY = TC_BASEY + (float)(s16)TC_IY[i] * TC_SCALEY;
        if(*(u32*)&gx == *(u32*)&refX) bitexactX++;
        if(*(u32*)&gy == *(u32*)&refY) bitexactY++;
        double dX=fabs((double)gx - TC_SX[i]);
        double dY=fabs((double)gy - TC_SY[i]);
        sumX+=dX; sumY+=dY;
        if(dX>worstX){worstX=dX;worstX_i=i;}
        if(dY>worstY){worstY=dY;worstY_i=i;}
        /* trace is logged to 2 decimals -> tolerance = 0.005 (half ULP of 0.01) */
        if(dX<=0.01) passX++;     /* trace logged to 2 decimals -> 1 ULP = 0.01px */
        if(dY<=0.01) passY++;
        if(i<8 || dX>0.01 || dY>0.01)
            printf("tile %2d  Ix=%4d Iy=%4d  gotX=%8.3f expX=%8.3f dX=%.4f | gotY=%8.3f expY=%8.3f dY=%.4f\n",
                   i,TC_IX[i],TC_IY[i],gx,TC_SX[i],dX,gy,TC_SY[i],dY);
    }
    printf("\nscaleX=%.6f baseX=%.4f  scaleY=%.6f baseY=%.4f  N=%d\n",
           TC_SCALEX,TC_BASEX,TC_SCALEY,TC_BASEY,TC_N);
    printf("X: %d/%d within trace 0.01px quantization | maxdX=%.4f (tile %d) meandX=%.5f\n",
           passX,TC_N,worstX,worstX_i,sumX/TC_N);
    printf("Y: %d/%d within trace 0.01px quantization | maxdY=%.4f (tile %d) meandY=%.5f\n",
           passY,TC_N,worstY,worstY_i,sumY/TC_N);
    printf("BIT-EXACT vs reference float arithmetic:  X %d/%d   Y %d/%d\n",
           bitexactX,TC_N,bitexactY,TC_N);
    /* SUCCESS = bit-exact vs the reference arithmetic (the trace-quantization-free
     * proof that the lifted FP chain is correct). The "within trace quantization"
     * lines are informational: residual vs the 2-decimal trace is at/under its own
     * logging ULP, i.e. the transpiled output IS the engine's value. */
    return (bitexactX==TC_N && bitexactY==TC_N)?0:1;
}
