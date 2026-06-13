/* Leaf implementations for the full walker compile/link test.
 *   leaf_e460    : TRANSPILED (in gen_leaf.c) — declared here only if not linked.
 *   leaf_e2e0    : cos  (sin(pi/2 - x))   — scale/rotation path; STUB (returns fr4)
 *   leaf_e860    : sin                    — scale/rotation path; STUB (returns fr4)
 *   submit_1244b0: bank12 vertex submit   — STUB: records the emitted quad's
 *                  screenX/screenY (read from the caller's stack frame @0x30/0x34)
 *                  so the harness can diff. We don't model the PVR vertex write.
 * The trig leaves are only reached on the NON-simple (scaled/rotated) path; the
 * body object we test takes the simple path, so they are never called here.
 */
#include "sh4ctx.h"
#include <stdio.h>

/* recorded submit outputs */
#define MAXQ 4096
float g_subX[MAXQ], g_subY[MAXQ];
int   g_nsub=0;

void leaf_e2e0(Sh4Ctx *c){ c->fr[0]=c->fr[4]; }  /* STUB (scale path, unused here) */
void leaf_e860(Sh4Ctx *c){ c->fr[0]=c->fr[4]; }  /* STUB (scale path, unused here) */

void submit_1244b0(Sh4Ctx *c){
    /* bank12 loc_8c1244b0: the vertex builder. r4 = &record (r15+0x2C per the
     * caller). The screenX/screenY for this part live at the caller frame
     * @(0x30,r15)/@(0x34,r15). The walker passes r4=r15+0x2C to submit; the
     * actual screen coords were written to the caller's @0x30/@0x34. For the PoC
     * we record them from r4-relative known layout: the submit reads a vertex
     * struct; screenX/screenY are at r4+0x04/r4+0x08 in that struct (the
     * @0x30/@0x34 of the caller == r4-ish). We record from the caller-visible
     * slots via r15: the harness sets nothing here — instead the harness reads
     * @0x30/@0x34 AFTER the walker returns for single-part frames. This stub just
     * counts invocations to prove the dispatch fires. */
    (void)c;
    if(g_nsub<MAXQ){ g_subX[g_nsub]=0; g_subY[g_nsub]=0; }
    g_nsub++;
}
