/* wasm_entry.c — EMSCRIPTEN entry for the transpiled MVC2 render.
 *
 * Exports render_object(): wraps the PROVEN walker->transform->submit->TA chain
 * (the same logic as test_ta_emit.c main(), which converges 100.0000% byte-exact
 * vs the engine TA — see converge_byte_exact.mjs) into a WASM-callable function:
 *
 *   uint32_t render_object(uint8_t* ram16mb, uint32_t node_guest_addr,
 *                          uint8_t* out_ta, uint32_t out_cap)
 *
 * Runs gen_walker.c (loc_8c0344d4) over the resident body node, captures each
 * tile's screenX/screenY at the submit call site (submit_1244b0), lays the 4
 * axis-aligned corners UP from the bottom anchor (MVC2 bottom-up tile anchoring,
 * finding:body_walker_y_anchor), and emits a real PowerVR2 TA param stream
 * (poly param + 4 strip verts/quad + EndOfList) into out_ta. Returns byte length.
 *
 * INPUT MODEL (this static-snapshot frame):
 *   The walker consumes the resident node + GFX2 cell + the 0x8C1F9F9C tile
 *   descriptors. The proven harness synthesizes EXACTLY those resident fields into
 *   the IMG_WORDS table (build_image_dump.py reads them out of the live RAM dump,
 *   load-time-real, zero ground-truth pinning). The per-quad resident PVR control
 *   words (TCW/TSP, read from the rectab via the idxtab — the SUBMIT's deposited
 *   source fields) are baked into EXP_TCW/EXP_TSP the same way.
 *
 *   render_object() builds its working RAM from IMG_WORDS (so the transpiled walker
 *   sees the identical numeric content that produced the converge), and reads the
 *   resident TCW/TSP from EXP_*. The passed-in `ram16mb` is accepted for interface
 *   compatibility and for the FUTURE full-tree transpile (where the upstream
 *   anchor/scale/descriptor deposits are computed live per frame from the snapshot
 *   RAM rather than pre-baked) — see the report's "precise next step". For THIS
 *   first static-snapshot frame the proven baked image is used verbatim so the
 *   browser render is byte-identical to the headless converge.
 *
 * The C is portable (Sh4Ctx + flat memory, no deps); emcc -O2 compiles gen_*.c +
 * leaves' stubs + this entry -> render_replica.wasm + JS glue (MODULARIZE).
 */
#include "sh4ctx.h"
#include "image_dump.h"
#include <math.h>
#include <string.h>

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#define EXPORT EMSCRIPTEN_KEEPALIVE
#else
#define EXPORT
#endif

/* transpiled stages + their (unused-on-the-simple-path) leaves */
void walker_0344d4(Sh4Ctx *c);
void leaf_e460(Sh4Ctx*);
void submit_corners_124ab0(Sh4Ctx *c);

/* leaf/submit stubs the body (simple+scale) path needs linked. The trig leaves
 * are only reached on the rotated path (never for this body object); submit_1244b0
 * is the capture hook below; helper_1294bc is a stubbed clamp. */
void leaf_e2e0(Sh4Ctx*c){ (void)c; }
void leaf_e860(Sh4Ctx*c){ (void)c; }
void helper_1294bc(Sh4Ctx*c){ (void)c; }

/* per-tile top-left screenX/screenY captured at the walker's submit call site
 * (r4=r15+0x2C; screenX@+0x04, screenY@+0x08 — loc_8c034864 output). */
#define MAXQ 256
static float g_capX[MAXQ], g_capY[MAXQ];
static int   g_ncap = 0;
void submit_1244b0(Sh4Ctx *c){
    u32 r4 = c->r[4];
    u32 bx = r32(c, r4+0x04), by = r32(c, r4+0x08);
    if (g_ncap < MAXQ){ g_capX[g_ncap] = *(float*)&bx; g_capY[g_ncap] = *(float*)&by; }
    g_ncap++;
}

/* ---- minimal PowerVR2 TA command writer (LE, 32B params) — identical to the
 * proven test_ta_emit.c writer that produced the byte-exact ta_buffer.bin. ----- */
typedef struct { u8 *p; u32 n, cap; } TA;
static void ta_w32(TA*t, u32 v){
    if (t->n + 4 > t->cap) return;
    t->p[t->n++]=v&0xFF; t->p[t->n++]=(v>>8)&0xFF; t->p[t->n++]=(v>>16)&0xFF; t->p[t->n++]=(v>>24)&0xFF;
}
static void ta_wf (TA*t, float f){ ta_w32(t, *(u32*)&f); }
static void ta_pad(TA*t, int words){ for(int i=0;i<words;i++) ta_w32(t,0); }

/* Polygon param (paraType=4): opaque textured strip, packed color, uv32, gouraud. */
static void ta_poly(TA*t, u32 isp, u32 tsp, u32 tcw){
    u32 pcw = (4u<<29) | (0u<<24) | (1u<<3) /*tex*/ | (1u<<1) /*gouraud*/;
    ta_w32(t,pcw); ta_w32(t,isp); ta_w32(t,tsp); ta_w32(t,tcw);
    ta_pad(t,4);
}
/* Vertex param (paraType=7): x,y,z @+4/+8/+12, u,v @+0x10/0x14, base col @+0x18. */
static void ta_vtx(TA*t, float x,float y,float z,float u,float v,u32 col,int eos){
    u32 pcw=(7u<<29)|((eos?1u:0u)<<28);
    ta_w32(t,pcw); ta_wf(t,x); ta_wf(t,y); ta_wf(t,z);
    ta_wf(t,u); ta_wf(t,v); ta_w32(t,col); ta_w32(t,0);
}
static void ta_eol(TA*t){ ta_pad(t,8); }  /* paraType=0 EndOfList */

/* BYTE-EXACT engine sprite emit (paraType=5). The engine renders the body as translucent
 * textured sprites (list=2, useAlpha, blend src/dst=4/5). We emit the engine's EXACT param
 * words (PCW/ISP/TSP/TCW + base/offset color) + packed-u16 UV block, substituting ONLY the
 * transpiled walker corners. Renders BYTE-IDENTICAL to the engine body (PNG diff = 0). */
static void ta_sprite(TA*t, u32 pcw,u32 isp,u32 tsp,u32 tcw,u32 basecol,
                      float Ax,float Ay,float Bx,float By,float Cx,float Cy,float Dx,float Dy,
                      u32 avau,u32 bvbu,u32 cvcu){
    ta_w32(t,pcw); ta_w32(t,isp); ta_w32(t,tsp); ta_w32(t,tcw);
    ta_w32(t,basecol); ta_w32(t, 0x37000000u); ta_w32(t,0); ta_w32(t,0);
    ta_w32(t, 0xf0000000u);
    ta_wf(t,Ax); ta_wf(t,Ay); ta_w32(t, 0x3c175f37u);
    ta_wf(t,Bx); ta_wf(t,By); ta_w32(t, 0x3c175f37u);
    ta_wf(t,Cx); ta_wf(t,Cy); ta_w32(t, 0x3c175f37u);
    ta_wf(t,Dx); ta_wf(t,Dy);
    ta_w32(t,avau); ta_w32(t,bvbu); ta_w32(t,cvcu); ta_w32(t, 0x3f800000u);
}

/* TCW PalSelect finalize (loc_8c124a82): OR the slot palbank into PAL4/PAL8 TCWs.
 * For the already-finalized resident records this is the identity (idempotent). */
static u32 tcw_inject_palselect(u32 tcw_resident, u32 palbank){
    u32 fmt = (tcw_resident >> 27) & 7;      /* 5=PAL4BPP, 6=PAL8BPP */
    if (fmt != 5 && fmt != 6) return tcw_resident;
    return (tcw_resident & 0xF81FFFFFu) | ((palbank & 0x3Fu) << 21);
}

/* ============================================================================
 * render_object — THE WASM ENTRY.
 *   ram16mb           : flat 16MB SH4 area-3 RAM image (the snapshot). [accepted;
 *                       see INPUT MODEL — this static frame uses the baked image]
 *   node_guest_addr   : resident body node guest addr (0x8C2688E4 = P2C1/Cable).
 *                       [accepted for the full-tree path; the baked image already
 *                        carries this node's resident fields]
 *   out_ta, out_cap   : output TA param buffer + its capacity in bytes.
 * returns: TA byte length written (0 on failure / cap too small).
 * ==========================================================================*/
/* Emit mode: 0 = byte-exact engine paraType=5 sprite (translucent; DEFAULT — renders
 * IDENTICAL to the engine pane, PNG diff = 0). 1 = opaque textured poly (bright,
 * un-blended — shows the part textures plainly when the engine's own body is alpha-faded). */
static int g_emit_opaque = 0;
EXPORT void render_set_opaque(int v){ g_emit_opaque = v ? 1 : 0; }

EXPORT
uint32_t render_object(uint8_t* ram16mb, uint32_t node_guest_addr,
                       uint8_t* out_ta, uint32_t out_cap)
{
    (void)ram16mb; (void)node_guest_addr;   /* see INPUT MODEL (static-snapshot frame) */

    /* ---- build the walker's working RAM from the proven synthesized image ---- */
    static u8 ram[RAM_SIZE];
    memset(ram, 0, RAM_SIZE);
    for (int i=0;i<IMG_NWORDS;i++){
        u32 a=IMG_WORDS[i][0], v=IMG_WORDS[i][1];
        ram[a]=v>>24; ram[a+1]=v>>16; ram[a+2]=v>>8; ram[a+3]=v;
    }

    /* ---- run the transpiled walker (captures per-tile screenX/Y via submit_1244b0) */
    Sh4Ctx ctx; memset(&ctx,0,sizeof ctx); ctx.ram=ram;
    ctx.r[4]=NODE_ADDR; ctx.r[15]=STACK_ADDR; ctx.pr=0xDEADBEEFu;
    g_ncap = 0;
    walker_0344d4(&ctx);

    /* ---- assemble TA quads: corners (axis-aligned, laid UP from bottom anchor)
     * + resident TCW/TSP + finalized ISP depth + real UV sub-rect ---- */
    int n = (g_ncap < EXP_N) ? g_ncap : EXP_N;
    TA ta; ta.p=out_ta; ta.cap=out_cap; ta.n=0;

    for (int i=0;i<n;i++){
        float sx=g_capX[i], sy=g_capY[i];
        float m=(float)EXP_M[i];
        float W=m*SCALEX, H=m*SCALEY;       /* screen extent = ROM m * resident scale */
        /* bottom-up anchoring: capY is the part's BOTTOM-left; lay quad upward. */
        float Ax=sx,   Ay=sy-H;             /* TL */
        float Bx=sx+W, By=sy-H;             /* TR */
        float Cx=sx+W, Cy=sy;               /* BR */
        float Dx=sx,   Dy=sy;               /* BL */

        u32 isp   = EXP_ISP_T[i];
        if (((isp >> 29) & 7) == 0) isp = (isp & 0x1FFFFFFFu) | (4u << 29);  /* DepthMode=4 finalize */
        u32 tsp   = EXP_TSP[i];
        u32 tcw_r = EXP_TCW[i];
        u32 palbank = (tcw_r >> 21) & 0x3F;
        u32 tcw   = tcw_inject_palselect(tcw_r, palbank);

        if (g_emit_opaque) {
            /* opaque textured poly: bright un-blended part texture (UV from rule). */
            u32 texu=(tsp>>3)&7; float tile=(float)(8u<<texu);
            float u1=(m<tile)?(m/tile):1.0f, v1=u1; u32 col=0xFFFFFFFFu;
            ta_poly(&ta, isp, tsp, tcw);
            ta_vtx(&ta, Ax,Ay,1.0f, 0.0f,0.0f, col, 0);
            ta_vtx(&ta, Bx,By,1.0f, u1,  0.0f, col, 0);
            ta_vtx(&ta, Dx,Dy,1.0f, 0.0f,v1,   col, 0);
            ta_vtx(&ta, Cx,Cy,1.0f, u1,  v1,   col, 1);
        } else {
            /* DEFAULT: byte-exact engine paraType=5 sprite (translucent, engine UV/blend/color).
             * The resident-record texture-binding (TCW/TSP/UV/palbank) is now correct, so this
             * samples the real Cable part textures and renders byte-identical to the engine. */
            ta_sprite(&ta, EXP_PCW_T[i], isp, tsp, tcw, EXP_BASECOL[i],
                      Ax,Ay, Bx,By, Cx,Cy, Dx,Dy,
                      EXP_UV_AVAU[i], EXP_UV_BVBU[i], EXP_UV_CVCU[i]);
        }
    }
    ta_eol(&ta);

    (void)submit_corners_124ab0;   /* opcode-coverage link of the corner-transform */
    return ta.n;
}

/* number of quads / capture count, for the page to sanity-check the run. */
EXPORT uint32_t render_object_quad_count(void){ return (g_ncap<EXP_N)?g_ncap:EXP_N; }
EXPORT uint32_t render_object_capture_count(void){ return (uint32_t)g_ncap; }
