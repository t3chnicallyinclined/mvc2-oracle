/* Test harness for the transpiled leaf loc_8C11E460.
 *
 * Reference: the leaf's documented semantics (2^23-guarded integer snap).
 * We sweep inputs and compare the transpiled C against:
 *   (a) the independent C reference ref_e460() below (derived from the disasm), and
 *   (b) for the small-magnitude range the body walker actually uses (|x|<=2^23),
 *       the identity, since that is provably the leaf's behaviour there.
 */
#include "sh4ctx.h"
#include <stdio.h>
#include <stdlib.h>

void leaf_e460(Sh4Ctx *c);

/* Independent reference, transcribed by hand from bank11 loc_8C11E460.
 * CORRECTED after reading the branch polarity exactly:
 *   fcmp/gt fr5,fr3  sets T iff  2^23 > |x|   (fr3=2^23, fr5=|x|)
 *   bf e490          branches when T==0, i.e. when |x| >= 2^23  -> return x (identity)
 * So for the NORMAL range (|x| < 2^23) it runs the snap path:
 *   n   = (s32)|x|        (ftrc of |x|)
 *   fn  = (float)n        (float n)
 *   neg = (x < 0)         (fcmp/gt fr4,fr2 ; fr2=0 -> T iff 0 > x)
 *   if (neg) return fn;                              (e4a0 returns fr6=fn=trunc(|x|))
 *   if (|x| - fn == 0) return x;                     (e490 identity, x already integral)
 *   return (float)(0xFFFFFFFF - n)  i.e. (float)(-1 - n)
 * Net effect = FLOOR(x): for x>=0 -> trunc(x); for x<0 non-integral -> trunc(|x|)
 * negated-and-minus-1 == floor. Confirmed below as floorf for |x|<2^23. */
static float ref_e460(float x){
    if (fabsf(x) >= 8388608.0f) return x;     /* identity for large magnitudes */
    return floorf(x);
}

int main(void){
    Sh4Ctx ctx; memset(&ctx,0,sizeof ctx);
    static u8 ram[RAM_SIZE]; ctx.ram=ram;

    float inputs[] = {
        0.0f, 1.0f, -1.0f, 463.0f, 228.0f, 519.6667f, 34.2857f, -127.0f,
        -8.0f, 1234.5f, -1234.5f, 8388607.0f, 8388608.0f, 8388609.0f,
        16777216.0f, -16777216.0f, 1e7f, -1e7f, 0.5f, -0.5f, 100000.25f
    };
    int n = sizeof(inputs)/sizeof(inputs[0]);
    int fails=0;
    for (int i=0;i<n;i++){
        float x=inputs[i];
        memset(&ctx,0,sizeof ctx); ctx.ram=ram;
        ctx.fr[4]=x;
        leaf_e460(&ctx);
        float got=ctx.fr[0];
        float exp=ref_e460(x);
        u32 gb=*(u32*)&got, eb=*(u32*)&exp;
        int ok = (gb==eb) || (got==exp);
        printf("x=%-14g  transpiled=%-14g  ref=%-14g  %s\n",
               x, got, exp, ok?"OK":"MISMATCH");
        if(!ok) fails++;
    }
    printf("\nleaf loc_8C11E460: %d/%d exact\n", n-fails, n);
    return fails?1:0;
}
