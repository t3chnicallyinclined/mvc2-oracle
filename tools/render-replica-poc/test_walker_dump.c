/* FULL-WALKER NUMERIC test — drive the transpiled loc_8c0344d4 end-to-end over an
 * input image whose tile DESCRIPTORS are the REAL load-time bytes read from the live
 * prod RAM dump (_ryu_capture/mc_ram_dump.bin @0x8C1F9F9C), and whose GFX2 records +
 * node anchor/scale come from the ASMTRACE (cid23 frame 10766). Diff the per-tile
 * screenX/screenY the walker emits vs the engine's logged screenX/screenY.
 *
 * This closes the full-walker milestone: pen accumulation + REAL tiling (count/pitch
 * from the dump's descriptor table) + the FP transform, run through mechanically-
 * transpiled C, reproduced numerically with INPUT-INDEPENDENT descriptors.
 *
 * Submit capture: the walker calls submit with r4 = r15+0x2C; the per-tile screenX is
 * at @(0x30,r15) == r4+0x04 and screenY at @(0x34,r15) == r4+0x08 (see bank03
 * loc_8c03478e..loc_8c034864). We capture those two floats per submit invocation.
 */
#include "sh4ctx.h"
#include "image_dump.h"
#include <stdio.h>
#include <math.h>
#include <stdlib.h>

void walker_0344d4(Sh4Ctx *c);
void leaf_e460(Sh4Ctx*);              /* transpiled floorf snap (gen_leaf.c) */
void leaf_e2e0(Sh4Ctx*c){ (void)c; }  /* scale-path trig (unused: flip=0/flags=0) */
void leaf_e860(Sh4Ctx*c){ (void)c; }

#define MAXQ 256
static float capX[MAXQ], capY[MAXQ];
static int   ncap=0;
static Sh4Ctx *g_ctx;

/* override submit to capture screenX/Y from the caller frame (r4 = r15+0x2C) */
void submit_1244b0(Sh4Ctx *c){
    u32 r4=c->r[4];           /* r4 = r15+0x2C (caller frame ptr passed to submit) */
    u32 bx=r32(c, r4+0x04);   /* @(0x30,r15) screenX */
    u32 by=r32(c, r4+0x08);   /* @(0x34,r15) screenY */
    if(ncap<MAXQ){ capX[ncap]=*(float*)&bx; capY[ncap]=*(float*)&by; }
    if(getenv("DBG")){
        u32 r15=r4-0x2C;
        fprintf(stderr,"  submit %d: r4=%08x r15=%08x  X=%.2f Y=%.2f | ",ncap,r4,r15,*(float*)&bx,*(float*)&by);
        for(u32 o=0x0C;o<=0x3C;o+=4){ u32 w=r32(c,r15+o); fprintf(stderr," [%02x]=%.2f",o,*(float*)&w);}
        fprintf(stderr,"\n");
    }
    ncap++;
}

int main(int argc, char**argv){
    static u8 ram[RAM_SIZE];
    Sh4Ctx ctx; memset(&ctx,0,sizeof ctx); ctx.ram=ram; g_ctx=&ctx;

    /* load the sparse image (big-endian words) */
    for(int i=0;i<IMG_NWORDS;i++){
        u32 a=IMG_WORDS[i][0], v=IMG_WORDS[i][1];
        ram[a]=v>>24; ram[a+1]=v>>16; ram[a+2]=v>>8; ram[a+3]=v;
    }
    /* NEGATIVE CONTROL: pass "zerodesc" to wipe the descriptor table -> the walker
     * must then NOT reproduce the 9 tiles, proving the pass depends on the REAL
     * dump descriptors (non-circular). */
    int zerodesc = (argc>1 && !strcmp(argv[1],"zerodesc"));
    if(zerodesc){ for(u32 a=0x1F9F9Cu; a<0x1FA000u; a++) ram[a]=0; }

    ctx.r[4]=NODE_ADDR;       /* entry ABI: R4 = node */
    ctx.r[15]=STACK_ADDR;     /* stack */
    ctx.pr=0xDEADBEEFu;       /* sentinel (rts -> C return) */

    walker_0344d4(&ctx);

    long stkdelta=(long)ctx.r[15]-(long)STACK_ADDR;
    printf("walker terminated. r15 delta=%ld (expect 0) tiles emitted=%d (expect %d)\n",
           stkdelta, ncap, EXP_N);

    /* per-tile diff vs the engine's logged screenX/screenY */
    int npass=0; double maxdx=0, maxdy=0;
    printf("\n  tile  sel    transpiled-C (X,Y)        engine-trace (X,Y)        dX      dY\n");
    int n = (ncap<EXP_N)?ncap:EXP_N;
    for(int i=0;i<n;i++){
        double dx=fabs((double)capX[i]-EXP_SX[i]);
        double dy=fabs((double)capY[i]-EXP_SY[i]);
        if(dx>maxdx)maxdx=dx; if(dy>maxdy)maxdy=dy;
        int ok = (dx<=0.01 && dy<=0.01);   /* trace logs to 0.01px; 0.00 relative */
        if(ok)npass++;
        printf("   %2d  %4d   (%8.2f,%8.2f)   (%8.2f,%8.2f)   %6.3f  %6.3f  %s\n",
               i, EXP_SEL[i], capX[i],capY[i], EXP_SX[i],EXP_SY[i], dx,dy, ok?"OK":"** ");
    }
    printf("\nFULL-WALKER NUMERIC: %d/%d tiles within 0.01px (maxdX=%.4f maxdY=%.4f)\n",
           npass, n, maxdx, maxdy);
    printf("RESULT: %s\n", (npass==EXP_N && ncap==EXP_N && stkdelta==0)?
           "PASS 0.00px-relative (full walker reproduces tiling from REAL dump descriptors)":
           "FAIL");
    return (npass==EXP_N && ncap==EXP_N)?0:1;
}
