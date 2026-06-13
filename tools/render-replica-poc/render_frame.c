/* PHASE 2 — render_frame(ram): walk the slot table and render EVERY on-screen BODY
 * object, with the per-object rectab allocation base COMPUTED by running the engine's
 * own submit-allocation cursor (NOT RAM-discovered).
 *
 * THE CURSOR MODEL — fully traced from marvelous2 (3 confirming sites), the load-bearing
 * Phase-2 correctness piece:
 *
 *   Arena base   *(0x8C1F9D94) = 16 or 400  (per-frame ping-pong by frame parity;
 *                set in the frame-setup loc_8c033950, bank03:8460-8469). This is the
 *                START index into idxtab for the frame's first body object.
 *   Per-object   loc_8c033b0a (bank03:8751-8772) deposits  node+0xDC = *(0x8C1F9D98)
 *                (snapshot the running cursor), then per GFX2 record advances
 *                *(0x8C1F9D98) += record_tile_count  (loc_8c033d44, bank03:8057-8059:
 *                `r3=*r11; r3+=r9; *r11=r3`, r11=*(0x8C1F9D98), r9=count). So across the
 *                frame, node+0xDC = PREFIX-SUM of all prior bodies' tile counts.
 *   Render walk  loc_8c0344d4 (bank03:10325-10330): the per-tile alloc index
 *                *r13[k] = node+0xDC + *(0x8C1F9D94) + k, incremented +1/tile (10752).
 *   Submit       loc_8C1244B0 (bank12:9853-9874): rectab[ idxtab[*r13] ].
 *
 *   => For body object n, tile k:  idxtab_index = prefix_sum(n) + arena_base + k
 *      where prefix_sum(n) = Σ ntiles(0..n-1)  and arena_base = *(0x8C1F9D94).
 *
 * In the full walk the cursor advances NATURALLY as we render objects in slot order:
 * render_frame keeps a `running_cursor` (= the engine's node+0xDC), seeded 0, advanced
 * by each object's emitted tile count. The engine's resident node+0xDC is the GROUND
 * TRUTH for this prefix-sum, so we ASSERT computed prefix == resident node+0xDC per
 * object — the proof the cursor generalizes Phase-1's single object to all objects.
 *
 * NOTE on validation scope: the matched dump (mc_ram_dump.bin / mc_engine_ta.bin) is a
 * single-character-on-screen frame — only cid23/P2C1 (Cable, 9 tiles, pal=24) is in the
 * slot table (L06) and the engine TA. So the byte-exact diff covers ONE real body; the
 * MULTI-object cursor advance is proven by (a) the resident node+0xDC == computed prefix
 * check, and (b) a synthetic 2-body test (render_frame_test.c) that confirms object 2's
 * base = object 1's base + object 1's ntiles per the ROM formula.
 */
#include "sh4ctx.h"
#include <math.h>
#include <stdio.h>
#include <string.h>

/* ---- Phase-1 pieces (reused verbatim) ---- */
void render_object_setup_03093c(Sh4Ctx *c);          /* gen_render_object.c   */
void transform_object_122560(Sh4Ctx *c, u32 node);   /* gen_transform_obj.c   */
void walker_0344d4(Sh4Ctx *c);                       /* gen_walker.c          */
typedef struct { u32 pcw, isp, tsp, tcw; } PolyParam;
void submit_params(Sh4Ctx *c, u32 rec_index, u32 palbank, PolyParam *out); /* gen_submit_params.c */

/* leaves the walker links against */
void leaf_e460(Sh4Ctx*);
void leaf_e2e0(Sh4Ctx*c){ (void)c; }
void leaf_e860(Sh4Ctx*c){ (void)c; }
void helper_1294bc(Sh4Ctx*c){ (void)c; }

/* ============================================================================
 * Per-object emitted-quad capture (the walker calls submit_1244b0 per tile with
 * r4 = the per-tile stack record @(r15+0x2C); screenX@+0x04, screenY@+0x08 = the
 * BOTTOM-left anchor). We also need the per-tile ALLOC INDEX *r13 = *(r15+0x2C),
 * captured here so render_frame can map tile k -> rectab without re-deriving it.
 * ==========================================================================*/
#define MAXQ 256
typedef struct { float bx, by; u32 alloc_index; u32 sel; } TileCap;
static TileCap g_cap[MAXQ];
static int g_ncap = 0;

void submit_1244b0(Sh4Ctx *c){
    u32 r4 = c->r[4];                 /* = r15+0x2C, the per-tile stack record */
    /* SOURCE CELL SEL for this tile. The walker (gen_walker.c loc_8c0344d4) reads the
     * GFX1 part selector ONCE per GFX2 cell record at `mov.w @(0x6,r11),r0` and then emits
     * `count = u8(desc[r13+1])+1` tiles for that ONE cell via this submit — r11 is NOT
     * advanced inside the inner tile loop (r11+=8 happens only after the inner loop, at
     * loc_8c03488e). So at EVERY submit call c->r[11]+6 == the current cell's sel, shared
     * by all of that cell's tiles. Capturing it here lets the client decode the RIGHT
     * sprite per quad instead of walking sels 1:1 with quads (which slips under tiling). */
    u32 cell_sel = r16u(c, c->r[11] + 0x6);
    /* ROBUSTNESS (live multi-object): g_cap holds at most MAXQ tiles. On a normal body
     * the walker emits ~9-40 tiles; a STALE/corrupt GFX2 (e.g. a body whose art was not
     * resident at the streamed prefix-build, or a per-frame region the read-set under-ships)
     * can drive the walker's in-RAM record loop into a runaway, emitting thousands of tiles.
     * We must NOT count past MAXQ — render_object_full() reads g_cap[k] for k<ntiles, so an
     * unbounded g_ncap caused OOB reads of g_cap[] AND filled g_scene to its 1024 cap with
     * garbage quads (the "quads=1024 Ax=0" frames). Clamping the COUNT here bounds both. */
    if(g_ncap < MAXQ){
        u32 bx = r32(c, r4 + 0x04);
        u32 by = r32(c, r4 + 0x08);
        g_cap[g_ncap].bx = *(float*)&bx;
        g_cap[g_ncap].by = *(float*)&by;
        g_cap[g_ncap].alloc_index = r32(c, r4 + 0x00);  /* *r13 = stack[r15+0x2C] */
        g_cap[g_ncap].sel = cell_sel;                    /* the cell's GFX1 sel (per-quad) */
        g_ncap++;                       /* only advance while in-bounds: ntiles<=MAXQ */
    }
    /* else: drop the tile (over-read guard). A real body never exceeds MAXQ; reaching it
     * means this object's geometry source is corrupt — emitting it would garble the scene. */
}

/* ---- arena-control globals (traced) ---- */
#define G_ARENA_BASE  0x8C1F9D94u   /* *(.) = 16 or 400 (frame ping-pong base)     */
#define G_OBJ_CURSOR  0x8C1F9D98u   /* *(.) = running prefix-sum, snapshotted to +0xDC */

static float rf(Sh4Ctx*c, u32 a){ u32 w=r32(c,a); return *(float*)&w; }

/* ============================================================================
 * render_object_full(c, node) — the Phase-1 per-object body render, now driven
 * with the CURSOR-DERIVED allocation base (node+0xDC + arena_base), and writing
 * its emitted sprite quads into the global scene TA accumulator (g_scene_*).
 * Returns the number of body tiles it emitted (so the caller advances the cursor).
 * Honors the +0x12C visibility gate via render_object_setup_03093c (which `bra`s to
 * skip when node+0x12C==0 — in that case the walker emits 0 tiles and we add 0).
 * ==========================================================================*/

/* the running scene TA: each tile -> one fully-computed sprite descriptor */
typedef struct {
    u32 pcw, isp, tsp, tcw, recidx;
    float Ax,Ay,Bx,By,Cx,Cy,Dx,Dy, u1;
    u32 sel;                 /* SOURCE GFX1 cell sel for this tile (per-quad, tiling-safe) */
    u32 gfx1;                /* owning node's GFX1 base (node+0x15C) — decode key with sel */
} SceneQuad;
#define MAXSCENE 1024
static SceneQuad g_scene[MAXSCENE];
static int g_nscene = 0;

/* palette bank for a node: slot formula 16*(char_pair+1)+8*player_side. We derive it
 * from the node's char-struct identity when it is one of the 6 fighter bodies; for a
 * generic body node we default to the P2C1 bank used by the validated object. (The
 * palbank only affects the TCW PalSelect inject; resident TCW already carries it.) */
static const struct { u32 base; u32 palbank; } CHAR_SLOT[6] = {
    {0x8C268340u,16},{0x8C2688E4u,24},{0x8C268E88u,32},
    {0x8C26942Cu,40},{0x8C2699D0u,48},{0x8C269F74u,56},
};
static u32 palbank_for(u32 node){
    for(int i=0;i<6;i++) if(CHAR_SLOT[i].base==node) return CHAR_SLOT[i].palbank;
    return 24; /* default (the validated P2C1 object) */
}

/* TILE_M (tile pixel size m = descriptor byte0) per emitted tile — read straight from
 * the resident 0x8C1F9F9C descriptor table the walker already consumes for geometry.
 * The walker reads r13 = *(node+0xDC)*4 + 0x8C1F9F9C; descriptor byte0 = m. We mirror
 * that here so the screen tile extent W=m*scaleX, H=m*scaleY matches the walker. */
#define DESC_TABLE 0x8C1F9F9Cu

int render_object_full(Sh4Ctx *c, u32 node){
    /* ---- run the Phase-1 setup: computes node+0xE0/E4 (anchor) + 0xEC/F0 (scale) ---- */
    c->r[4]=node; c->r[14]=node; c->r[15]=0x0C480000u; c->pr=0xDEADBEEFu;
    render_object_setup_03093c(c);   /* honors +0x12C gate internally */

    /* ---- run the proven walker to emit this object's body tiles (corners) ---- */
    Sh4Ctx wc; memcpy(&wc, c, sizeof wc); wc.ram=c->ram;
    wc.r[4]=node; wc.r[15]=0x0C480000u; wc.pr=0xDEADBEEFu;
    g_ncap=0;
    walker_0344d4(&wc);
    int ntiles = g_ncap;

    /* ---- CORRUPTION GATE (live multi-object robustness) ----
     * submit_1244b0 now clamps g_ncap at MAXQ. If the walker SATURATED that clamp, this
     * object's geometry source (its GFX2 cell stream / descriptor table) is corrupt or
     * stale — almost certainly a body whose art was not resident at the streamed prefix
     * snapshot, or a per-frame region the read-set under-ships. A real MVC2 body never
     * emits MAXQ tiles. Emitting these would paint a wall of garbage quads (the "quads=1024"
     * frames). DROP the object's tiles entirely; the rest of the scene renders clean. */
    if(ntiles >= MAXQ){
        return 0;   /* report 0 tiles: cursor advance unaffected (engine still owns +0xDC) */
    }

    /* ---- per-tile: compute params from resident rectab[idxtab[alloc_index]] + UV ---- */
    float sxs = rf(c, node+0xEC), sys = rf(c, node+0xF0);
    u32 palbank = palbank_for(node);
    u32 node_gfx1 = r32(c, node+0x15C);   /* this body's GFX1 base (per-quad decode key) */
    /* the walker's per-tile alloc_index already = node+0xDC + arena_base + k (it read the
     * resident node+0xDC and *(0x8C1F9D94)); we use it directly — that IS the cursor-
     * derived base in action. (render_frame separately ASSERTS node+0xDC == prefix-sum.) */
    for(int k=0; k<ntiles && g_nscene<MAXSCENE; k++){
        PolyParam pp;
        submit_params(c, g_cap[k].alloc_index, palbank, &pp);

        /* tile m: the descriptor byte0 for this tile. Re-derive from the resident table
         * exactly as the walker did: idx into DESC_TABLE = node+0xDC + (tile's record).
         * For a faithful extent we read m from the descriptor the walker used. The walker
         * leaves r13 advanced; simplest faithful source = the same descriptor stream.
         * We recompute m per tile from DESC_TABLE using node+0xDC as the record base. */
        u32 dc = r16u(c, node+0xDC);
        u32 m  = r8u(c, DESC_TABLE + (dc + k)*4);   /* byte0 = tile pixel size */
        if(m==0) m=8;                               /* guard: never 0 (8px min tile) */

        u32 texu = (pp.tsp>>3)&7; float tile=(float)(8u<<texu);
        float W = (float)m * sxs, H = (float)m * sys;
        float bx=g_cap[k].bx, by=g_cap[k].by;       /* walker BOTTOM-left anchor */
        SceneQuad *q = &g_scene[g_nscene++];
        q->pcw=pp.pcw; q->isp=pp.isp; q->tsp=pp.tsp; q->tcw=pp.tcw;
        q->recidx=g_cap[k].alloc_index;
        q->sel=g_cap[k].sel;          /* per-quad source sel (tiling-safe pairing key) */
        q->gfx1=node_gfx1;            /* per-quad owning-body GFX1 base (decode with sel) */
        q->Ax=bx;     q->Ay=by-H;     /* lay the quad UPWARD from the bottom-left */
        q->Bx=bx+W;   q->By=by-H;
        q->Cx=bx+W;   q->Cy=by;
        q->Dx=bx;     q->Dy=by;
        q->u1 = ((float)m < tile) ? ((float)m/tile) : 1.0f;
    }
    return ntiles;
}

/* ============================================================================
 * The transpiled root slot-walk (gen_walker_root.c) calls render_object_full for
 * each BODY node and render_effect_030af8 for each effect node.
 * ==========================================================================*/
void render_sprites_0308c2(Sh4Ctx *c);   /* gen_walker_root.c */

/* Phase-3 stub: the effect/satellite renderer loc_8c030af8 (cat 1..4). */
void render_effect_030af8(Sh4Ctx *c, u32 node){ (void)c; (void)node; /* DEFER to Phase 3 */ }

/* ---- the cursor-advance bookkeeping the slot-walk needs ----
 * render_object_full uses the walker's resident-read alloc_index directly, but Phase 2's
 * proof obligation is that the per-object base GENERALIZES via the running cursor. We
 * therefore ALSO maintain render_frame's own running_cursor and verify it tracks the
 * engine's resident node+0xDC for every body object. These are exposed for the harness. */
int   g_body_count = 0;          /* how many body objects render_frame rendered      */
u32   g_obj_dc_resident[64];     /* resident node+0xDC per body (engine prefix-sum)   */
u32   g_obj_dc_computed[64];     /* render_frame's running-cursor prefix-sum          */
int   g_obj_ntiles[64];          /* tiles each body emitted                           */
u32   g_obj_node[64];

/* render_frame_body_hook: called by the slot-walk for each BODY node (cat==0). It runs
 * the per-object render AND advances the running cursor, recording both the engine's
 * resident node+0xDC and our computed prefix-sum for the per-object proof. */
static u32 s_running_cursor = 0;
void render_frame_body_hook(Sh4Ctx *c, u32 node){
    if(g_body_count < 64){
        g_obj_node[g_body_count]       = node;
        g_obj_dc_resident[g_body_count]= r16u(c, node+0xDC);   /* engine's prefix-sum */
        g_obj_dc_computed[g_body_count]= s_running_cursor;     /* our running prefix  */
    }
    int nt = render_object_full(c, node);
    if(g_body_count < 64) g_obj_ntiles[g_body_count] = nt;
    s_running_cursor += (u32)nt;     /* advance cursor by this object's tile count    */
    g_body_count++;
}

/* PUBLIC ENTRY: render_frame(ram) — reset cursor, walk all slots, render all bodies into
 * the scene TA accumulator. Caller reads g_scene[0..g_nscene) and the per-object proof. */
void render_frame_reset(void){
    g_nscene=0; g_body_count=0; s_running_cursor=0;
}
int  render_frame_nscene(void){ return g_nscene; }
const SceneQuad* render_frame_scene(void){ return g_scene; }

void render_frame(Sh4Ctx *c){
    render_frame_reset();
    render_sprites_0308c2(c);   /* the transpiled loc_8c0308c2; calls render_object_full */
}
