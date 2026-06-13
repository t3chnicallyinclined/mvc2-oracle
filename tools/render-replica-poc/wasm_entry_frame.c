/* wasm_entry_frame.c — PHASE 2 EMSCRIPTEN entry: render the WHOLE FRAME (all on-screen
 * BODY objects) from a flat 16MB SH4 RAM image.
 *
 *   uint32_t render_frame_ta(uint8_t* ram16mb, uint8_t* out_ta, uint32_t out_cap)
 *
 * Runs the transpiled root slot-walk (render_sprites_0308c2 = loc_8c0308c2) over the
 * caller's ram16mb: it enumerates every BODY node in the slot table (count@0x8C2895E0,
 * ptrs@0x8C287DE0, cat@+0x3==0), renders each via render_object_full (Phase-1 chain:
 * setup->transform->scale->walker->submit, with the cursor-derived rectab base), and
 * accumulates every body tile into one full-scene PVR2 sprite TA written to out_ta.
 *
 * Unlike wasm_entry.c (single object from a baked image), THIS consumes the real passed-in
 * RAM — so it scales to N bodies with no baked descriptors. The per-object allocation base
 * advances via the running cursor (= the engine's node+0xDC prefix-sum), validated
 * byte-exact in render_frame_test.exe (params 9/9, corners 0.00px, 100% pixel match).
 *
 * Build: see build_wasm_frame.sh (emcc gen_walker_root.c render_frame.c gen_render_object.c
 * gen_transform_obj.c gen_submit_params.c gen_walker.c gen_leaf.c wasm_entry_frame.c).
 */
#include "sh4ctx.h"
#include <string.h>

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#define EXPORT EMSCRIPTEN_KEEPALIVE
#else
#define EXPORT
#endif

void render_frame(Sh4Ctx *c);
typedef struct {
    u32 pcw, isp, tsp, tcw, recidx;
    float Ax,Ay,Bx,By,Cx,Cy,Dx,Dy, u1;
    u32 sel;                 /* SOURCE GFX1 cell sel for this tile (per-quad, tiling-safe) */
    u32 gfx1;                /* owning node's GFX1 base (node+0x15C) — decode key with sel */
} SceneQuad;
int  render_frame_nscene(void);
const SceneQuad* render_frame_scene(void);
extern int g_body_count;

/* ---- PVR2 paraType=5 sprite writer (LE) — same byte format the project's
 * converge_full_computed.mjs / converge_frame.mjs feed ta-parser.mjs. ---- */
static u16 h16(float f){ u32 u; memcpy(&u,&f,4); return (u>>16)&0xFFFF; }

EXPORT
uint32_t render_frame_ta(uint8_t* ram16mb, uint8_t* out_ta, uint32_t out_cap){
    static Sh4Ctx c;
    memset(&c,0,sizeof c);
    c.ram = ram16mb;                 /* the caller's real 16MB area-3 RAM image */

    render_frame(&c);                /* slot-walk -> all bodies into the scene accumulator */

    int n = render_frame_nscene();
    const SceneQuad* S = render_frame_scene();

    u32 o = 0;
    for(int k=0;k<n;k++){
        if(o + 96 > out_cap) break;
        const SceneQuad* q=&S[k];
        u8* p = out_ta + o; memset(p,0,96);
        #define W32(off,v) do{ u32 _v=(v); p[off]=_v; p[off+1]=_v>>8; p[off+2]=_v>>16; p[off+3]=_v>>24; }while(0)
        #define WF(off,f)  do{ float _f=(f); u32 _u; memcpy(&_u,&_f,4); W32(off,_u); }while(0)
        W32(0,q->pcw); W32(4,q->isp); W32(8,q->tsp); W32(12,q->tcw);
        /* Sprite BASE COLOR (TA_Sprite global param +16, "sprite_base_color"). MUST be
         * opaque white: MVC2 body sprites use shadInstr=MODULATE (TSP bits6-7=3) so the
         * shader does c = faceColor * texColor. A zero base color (the memset default)
         * zeroes every fragment -> c.a<0.004 -> discard -> NOTHING DRAWS. 0xFFFFFFFF is the
         * modulate identity (the engine's own sprite base color for these tiles). */
        W32(16,0xFFFFFFFFu);                         /* sprite base color (opaque white) */
        W32(32,0xE0000000u);                         /* sprite vtx PCW */
        WF(36,q->Ax); WF(40,q->Ay); WF(44,1.0f);
        WF(48,q->Bx); WF(52,q->By); WF(56,1.0f);
        WF(60,q->Cx);
        WF(64,q->Cy); WF(68,1.0f);
        WF(72,q->Dx); WF(76,q->Dy);
        { float U=q->u1, V=q->u1;
          u16 v0=h16(V),u0=h16(0.0f),v1=h16(V),u1=h16(U),v2=h16(0.0f),u2=h16(U);
          p[84]=v0;p[85]=v0>>8; p[86]=u0;p[87]=u0>>8;
          p[88]=v1;p[89]=v1>>8; p[90]=u1;p[91]=u1>>8;
          p[92]=v2;p[93]=v2>>8; p[94]=u2;p[95]=u2>>8; }
        #undef W32
        #undef WF
        o += 96;
    }
    if(o + 32 <= out_cap){ memset(out_ta+o,0,32); o+=32; } /* EndOfList */
    return o;
}

EXPORT uint32_t render_frame_body_count(void){ return (uint32_t)g_body_count; }
EXPORT uint32_t render_frame_quad_count(void){ return (uint32_t)render_frame_nscene(); }

/* PER-QUAD SOURCE SEL (tiling-safe texture pairing). The body walker expands ONE GFX2 cell
 * record into N tiles (N = desc tile count), all sharing the cell's GFX1 sel. The emitted TA
 * therefore has MORE quads than cell records, so the client must NOT pair quad[i]<->sel[i] 1:1
 * (that slips after the first tiled cell -> right colors, wrong quad = the scramble). This
 * fills out_sels[k] = the GFX1 sel the walker actually used for TA quad k (k in render order,
 * == ensureBodyTextures' qcur). The client decodes THAT sel's sprite to quad k's TCW. The sels
 * are u16 in MVC2's namespace; we write them as u16 LE. Returns the number written. */
EXPORT uint32_t render_frame_quad_sels(uint16_t* out_sels, uint32_t cap){
    int n = render_frame_nscene();
    const SceneQuad* S = render_frame_scene();
    uint32_t w = 0;
    for(int k=0;k<n && w<cap;k++,w++) out_sels[w] = (uint16_t)S[k].sel;
    return w;
}

/* PER-QUAD OWNING-BODY GFX1 BASE. So the client decodes each quad's sel against the RIGHT
 * character's GFX1 (no slot-attribution / run-length re-derivation needed — fully tiling-proof:
 * a tiled cell's N tiles carry the SAME (sel,gfx1), so they decode the same sprite to N TCWs).
 * out_gfx1[k] = the GFX1 base (a P1/P0 RAM pointer) the walker's body node used for TA quad k. */
EXPORT uint32_t render_frame_quad_gfx1s(uint32_t* out_gfx1, uint32_t cap){
    int n = render_frame_nscene();
    const SceneQuad* S = render_frame_scene();
    uint32_t w = 0;
    for(int k=0;k<n && w<cap;k++,w++) out_gfx1[w] = S[k].gfx1;
    return w;
}
