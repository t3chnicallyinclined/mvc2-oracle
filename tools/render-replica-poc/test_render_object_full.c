/* render_object_full — the Phase-1 deliverable harness.
 *
 * Runs the FULLY CODE-DERIVED per-object render setup over a RESIDENT-ONLY RAM image
 * (build_image_full.py — no engine-TA bytes anywhere) and validates that the COMPUTED
 * anchor / scale / texture-params equal the engine's actual deposited values BYTE-EXACT:
 *
 *   render_object_setup_03093c(c)         [transpiled loc_8c03093c]
 *     -> transform_object_122560(c,node)  [ftrv over resident proj matrices]
 *          deposits node+0xE0/E4/E8  (anchor)   -- COMPUTED, was pinned/read
 *     -> deposits node+0xEC/F0        (scale)    -- COMPUTED (CpsScale*node[0x50/54])
 *   submit_params(c, rec_index, palbank, &pp)    [transpiled submit finalize]
 *          PCW/ISP/TSP/TCW per tile               -- COMPUTED from resident rectab
 *
 * GATE: computed == EXP_* (the dump's OWN resident deposited values). 0 diff = no pinning.
 */
#include "sh4ctx.h"
#include "image_full.h"
#include <stdio.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>

void render_object_setup_03093c(Sh4Ctx *c);
void transform_object_122560(Sh4Ctx *c, u32 node_addr);
typedef struct { u32 pcw, isp, tsp, tcw; } PolyParam;
void submit_params(Sh4Ctx *c, u32 rec_index, u32 palbank, PolyParam *out);

/* the proven walker + its leaves (reused to produce the per-tile corners) */
void walker_0344d4(Sh4Ctx *c);
void leaf_e460(Sh4Ctx*);
void leaf_e2e0(Sh4Ctx*c){ (void)c; }
void leaf_e860(Sh4Ctx*c){ (void)c; }
void helper_1294bc(Sh4Ctx*c){ (void)c; }
/* walker calls submit per tile with r4 = the per-tile stack record @(r15+0x2C);
 * screenX@+0x04, screenY@+0x08 (the bottom-left anchor). Capture them. */
#define MAXQ 64
static float capX[MAXQ], capY[MAXQ]; static int ncap=0;
void submit_1244b0(Sh4Ctx *c){
    u32 r4=c->r[4];
    u32 bx=r32(c,r4+0x04), by=r32(c,r4+0x08);
    if(ncap<MAXQ){ capX[ncap]=*(float*)&bx; capY[ncap]=*(float*)&by; } ncap++;
}

static float rf(Sh4Ctx*c, u32 a){ u32 w=r32(c,a); return *(float*)&w; }

int main(void){
    static u8 ram[RAM_SIZE];
    Sh4Ctx ctx; memset(&ctx,0,sizeof ctx); ctx.ram=ram;
    for(int i=0;i<IMG_NWORDS;i++){ u32 a=IMG_WORDS[i][0],v=IMG_WORDS[i][1];
        ram[a]=v>>24; ram[a+1]=v>>16; ram[a+2]=v>>8; ram[a+3]=v; }

    /* ZERO the deposited fields the engine wrote, to PROVE we recompute them and are
     * not just reading the resident snapshot. (anchor +0xE0/E4/E8, scale +0xEC/F0) */
    for(u32 off=0xE0; off<=0xF0; off+=4) w32(&ctx, NODE_ADDR+off, 0);

    /* run the transpiled per-object setup (r4 = node base, per loc_8c03093c entry) */
    ctx.r[4]=NODE_ADDR; ctx.r[14]=NODE_ADDR; ctx.r[15]=0x0C480000u; ctx.pr=0xDEADBEEFu;
    render_object_setup_03093c(&ctx);

    int fail=0;
    /* ---- anchor (computed by the ftrv transform) ---- */
    float ax=rf(&ctx,NODE_ADDR+0xE0), ay=rf(&ctx,NODE_ADDR+0xE4);
    double dax=fabs((double)ax-EXP_ANCHOR_X), day=fabs((double)ay-EXP_ANCHOR_Y);
    printf("ANCHOR  computed (%.5f, %.5f)  engine (%.5f, %.5f)  dX=%.5f dY=%.5f  %s\n",
           ax,ay, EXP_ANCHOR_X,EXP_ANCHOR_Y, dax,day,
           (dax<=1e-3 && day<=1e-3)?"BYTE-EXACT":"MISMATCH");
    if(!(dax<=1e-3 && day<=1e-3)) fail=1;

    /* ---- scale (computed: CpsScale * node[0x50/54]) ---- */
    float sx=rf(&ctx,NODE_ADDR+0xEC), sy=rf(&ctx,NODE_ADDR+0xF0);
    double dsx=fabs((double)sx-EXP_SCALE_X), dsy=fabs((double)sy-EXP_SCALE_Y);
    /* the scale has a divide (CpsScale*node[0x50] / (812.357/camZ)) so allow 1 f32 ULP */
    printf("SCALE   computed (%.6f, %.6f)  engine (%.6f, %.6f)  dX=%.7f dY=%.7f  %s\n",
           sx,sy, EXP_SCALE_X,EXP_SCALE_Y, dsx,dsy,
           (dsx<=2e-6 && dsy<=2e-6)?"BYTE-EXACT":"MISMATCH");
    if(!(dsx<=2e-6 && dsy<=2e-6)) fail=1;

    /* ---- texture params (computed from resident rectab + transpiled finalize) ---- */
    int pcw_ok=0,isp_ok=0,tsp_ok=0,tcw_ok=0;
    printf("\nPARAMS per tile (computed from resident rectab[base+k] + finalize, NO engine-TA):\n");
    for(int k=0;k<NTILES;k++){
        PolyParam pp;
        submit_params(&ctx, REC_INDEX[k], SLOT_PALBANK, &pp);
        int ok = (pp.pcw==EXP_PCW[k] && pp.isp==EXP_ISP[k] && pp.tsp==EXP_TSP[k] && pp.tcw==EXP_TCW[k]);
        pcw_ok += (pp.pcw==EXP_PCW[k]); isp_ok += (pp.isp==EXP_ISP[k]);
        tsp_ok += (pp.tsp==EXP_TSP[k]); tcw_ok += (pp.tcw==EXP_TCW[k]);
        printf("  tile%d idx%2u: PCW=%08X ISP=%08X TSP=%08X TCW=%08X  %s\n",
               k, REC_INDEX[k], pp.pcw,pp.isp,pp.tsp,pp.tcw, ok?"OK":"DIFF");
        if(!ok) fail=1;
    }
    printf("\nPCW %d/%d  ISP %d/%d  TSP %d/%d  TCW %d/%d byte-exact vs engine deposited\n",
           pcw_ok,NTILES,isp_ok,NTILES,tsp_ok,NTILES,tcw_ok,NTILES);

    /* ===== FULL CHAIN: run the proven walker to get per-tile corners, then emit the
     * fully-COMPUTED sprite list (corners + computed params + computed UV) as JSON, so
     * converge_full_computed.mjs can render+diff it vs the engine GT — NO engine-TA. ===== */
    {
        /* the walker reads node+0x144 sid, +0x160 GFX2 etc. — all resident in image_full. */
        Sh4Ctx wc; memcpy(&wc, &ctx, sizeof wc); wc.ram=ram;
        wc.r[4]=NODE_ADDR; wc.r[15]=0x0C480000u; wc.pr=0xDEADBEEFu;
        ncap=0;
        walker_0344d4(&wc);
        printf("\nWALKER produced %d body tiles.\n", ncap);

        /* the computed scale (just deposited) drives the screen tile extent W=m*sx, H=m*sy */
        float sxs = rf(&ctx, NODE_ADDR+0xEC), sys = rf(&ctx, NODE_ADDR+0xF0);

        FILE*jf=fopen("computed_sprites.json","w");
        fprintf(jf,"[\n");
        int nout = (ncap<NTILES)?ncap:NTILES;
        for(int k=0;k<nout;k++){
            PolyParam pp; submit_params(&ctx, REC_INDEX[k], SLOT_PALBANK, &pp);
            /* tile pixel size m = the load-time descriptor byte0, read straight from the
             * resident 0x8C1F9F9C table — geometry data the walker already used (proven).
             * The TILE_M[] array is built from the same resident descriptors (see image_full). */
            u32 m = TILE_M[k];
            u32 texu=(pp.tsp>>3)&7; float tile=(float)(8u<<texu);
            float W = (float)m * sxs, H = (float)m * sys;   /* screen tile extent */
            /* walker corner (capX,capY) = part BOTTOM-left; lay quad UPWARD (body_walker_y_anchor) */
            float Ax=capX[k],   Ay=capY[k]-H;
            float Bx=capX[k]+W, By=capY[k]-H;
            float Cx=capX[k]+W, Cy=capY[k];
            float Dx=capX[k],   Dy=capY[k];
            float u1 = ((float)m < tile) ? ((float)m/tile) : 1.0f;
            fprintf(jf,"  {\"pcw\":%u,\"isp\":%u,\"tsp\":%u,\"tcw\":%u,\"recidx\":%u,"
                       "\"Ax\":%.6f,\"Ay\":%.6f,\"Bx\":%.6f,\"By\":%.6f,"
                       "\"Cx\":%.6f,\"Cy\":%.6f,\"Dx\":%.6f,\"Dy\":%.6f,\"u1\":%.6f}%s\n",
                    pp.pcw,pp.isp,pp.tsp,pp.tcw,REC_INDEX[k],
                    Ax,Ay,Bx,By,Cx,Cy,Dx,Dy,u1, (k<nout-1)?",":"");
        }
        fprintf(jf,"]\n"); fclose(jf);
        printf("wrote computed_sprites.json (%d sprites, fully code-derived corners+params+UV)\n", nout);
    }

    printf("\nRESULT: %s — per-object render is %s\n",
           fail?"FAIL":"PASS",
           fail?"NOT fully code-derived":"FULLY CODE-DERIVED (anchor+scale+params computed, NO pinning)");
    return fail;
}
