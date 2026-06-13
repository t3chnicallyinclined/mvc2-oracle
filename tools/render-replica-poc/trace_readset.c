/* trace_readset.c — run ONE render_frame() over the verbatim dump with the read-trace
 * header, coalesce the recorded reads into [start,end) regions, classify each region
 * STATIC | DYNAMIC | SCRATCH, and print the read-set table + the DYNAMIC bytes/frame.
 *
 * This is the WIRE SPEC derivation: the dynamic-classified regions are EXACTLY what must
 * ship per frame for an off-SH4 render_frame to reproduce the engine TA. Build with the
 * trace header forced in front of every TU (see build at bottom).
 *
 * The dump is the matched single-Cable-on-screen frame (_ryu_capture/mc_ram_dump.bin),
 * the same one Phase 2 proved render_frame -> engine TA byte-exact on. So the read-set
 * here is the COMPLETE set render_frame touches; partitioning it static|dynamic IS the
 * proof of completeness (every read lands in exactly one bucket).
 */
#include "sh4ctx_trace.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* trace storage (declared extern in the header) */
McRead mc_trace[MC_TRACE_MAX];
u32    mc_trace_n = 0;
int    mc_trace_on = 0;

void render_frame(Sh4Ctx *c);

/* ---- the dump ---- */
#define DUMP "C:\\Users\\trist\\projects\\maplecast-flycast\\_ryu_capture\\mc_ram_dump.bin"

/* PoC scratch band: r15 stack base in render_object_full / walker (= 0x0C480000). The
 * walker pushes 124 bytes below it then frames up; setup pushes a few words below 0x0C480000.
 * We tag everything in [0x0C480000-0x200, 0x0C480000+0x200) as SCRATCH. */
#define SCRATCH_LO 0x0047FE00u
#define SCRATCH_HI 0x00480200u

/* ---- classification ---- */
typedef enum { ST_STATIC, ST_DYNAMIC, ST_SCRATCH } Kind;

/* The CLASSIFICATION TABLE — reasoned from the transpile + disasm (cited in the report).
 * Any read that falls in a known band is classified by that band; reads outside all known
 * bands are flagged UNCLASSIFIED (a bug in the partition). The classifier matches by guest
 * idx (a & 0xFFFFFF) against [lo,hi). Order = first match wins; SCRATCH checked first. */
static u32 G(u32 a){ return a & 0x00FFFFFFu; }

typedef struct { u32 lo, hi; Kind kind; const char* what; } Band;

/* All bands (the static classification table + the runtime-resolved idxtab/rectab/GFX bands)
 * are appended by init_bands() so the G() normalization + runtime pointers compose cleanly. */
#define MAXDYN 128
static Band DYN[MAXDYN]; static int NDYN=0;
static void add_band(u32 lo,u32 hi,Kind k,const char*w){ if(NDYN<MAXDYN){DYN[NDYN].lo=G(lo);DYN[NDYN].hi=G(hi);DYN[NDYN].kind=k;DYN[NDYN].what=w;NDYN++;} }

/* The CLASSIFICATION TABLE — reasoned from the transpile + disasm (cited in the report). */
static void init_static_bands(void){
  /* --- PoC scratch (caller re-inits each frame; neither static nor dynamic) --- */
  add_band(0x0C47FE00,0x0C480200, ST_SCRATCH, "PoC r15 stack scratch");
  /* --- DYNAMIC: engine rewrites these every frame --- */
  add_band(0x8C2895E0,0x8C2895F0, ST_DYNAMIC, "slot-table count array (16 layers)");
  add_band(0x8C287DE0,0x8C287DE0+16*0x180, ST_DYNAMIC, "slot-table ptr arrays (16*0x180)");
  add_band(0x8C268340,0x8C268340+6*0x5A4, ST_DYNAMIC, "char structs P1C1..P2C3 (6*0x5A4)");
  add_band(0x8C1F9D80,0x8C1F9DA0, ST_DYNAMIC, "arena-control globals 0x9D80..9DA0 (cursor/base/scratch ptrs)");
  add_band(0x8C1F9F9C,0x8C1FA19C, ST_DYNAMIC, "per-frame tile-descriptor scratch table (0x8C1F9F9C, rolling)");
  add_band(0x8C2D6AD8,0x8C2D6B98, ST_DYNAMIC, "camera matrices M2/M1 (proj/viewport) + 0x6B58");
  add_band(0x8C26A510,0x8C26A550, ST_DYNAMIC, "camera-Z scale block (0x8C26A518 base, camZ @+0x20)");
  add_band(0x8C26823C,0x8C268240, ST_DYNAMIC, "GameGlobalPointer (work.asm:1) -- global-accum base ptr");
  add_band(0x8C26A974,0x8C26AA74, ST_DYNAMIC, "per-char render-param table (0x8C26a974, indexed by +0x24/+0x36)");
  add_band(0x8C2DAD30,0x8C2DAD70, ST_DYNAMIC, "rectab/idxtab pointer pair (0x8C2DAD3C idx, 0x8C2DAD4C rec)");
  add_band(0x8C2AA4C0,0x8C2AA4D0, ST_DYNAMIC, "global render-mode word (0x8C2AA4C4, TSP filter source)");
}

/* dump accessors for pointer resolution */
static u8* g_dump;
static u32 du32(u32 g){ u32 o=G(g); return (u32)g_dump[o]|((u32)g_dump[o+1]<<8)|((u32)g_dump[o+2]<<16)|((u32)g_dump[o+3]<<24); }
static u8  du8 (u32 g){ return g_dump[G(g)]; }

static int is_ram(u32 g){ return (((g>>24)&0x7F)==0x0C) && g!=0; }

static void resolve_pointer_bands(void){
    /* GameGlobalPointer target (DYNAMIC) — *(0x8C26823C) is a struct whose +0x24 dword is a
     * running global accumulator the render path reads-modifies-writes (loc_8c034bea path,
     * bank03:1518-1530). Cover a small window around the dereferenced base. */
    u32 ggp = du32(0x8C26823C);
    if(is_ram(ggp)) add_band(ggp, ggp+0x40, ST_DYNAMIC, "global-accum struct *(0x8C26823C) (+0x24 running accumulator, RMW per object)");

    /* idxtab + rectab (DYNAMIC — per-frame allocation tables). They are ADJACENT in this
     * dump (idxtab=0x8C24B65C, rectab=0x8C24D7DC, gap ~0x2180). Size each to cover the
     * frame's allocation: idxtab indexes by allocation-cursor (arena_base + Σtiles), rectab
     * by idxtab[...]. We size idxtab to the cursor span and rectab to the record span; the
     * touched extent stays inside, and any multi-char frame stays inside the 0x2000/0x8000
     * caps the engine builds. Bands are non-overlapping (idxtab capped before rectab). */
    u32 idxtab = du32(0x8C2DAD3C), rectab = du32(0x8C2DAD4C);
    if(is_ram(idxtab) && is_ram(rectab)){
        u32 idx_end = (rectab>idxtab && rectab-idxtab<0x4000)? rectab : idxtab+0x2000;
        add_band(idxtab, idx_end, ST_DYNAMIC, "idxtab (per-frame alloc-index table @*0x8C2DAD3C; u16/alloc-slot)");
        add_band(rectab, rectab+0x8000, ST_DYNAMIC, "rectab (per-frame PVR poly-param records @*0x8C2DAD4C; 0x20/record)");
    } else {
        if(is_ram(idxtab)) add_band(idxtab, idxtab+0x2000, ST_DYNAMIC, "idxtab (per-frame alloc-index table @*0x8C2DAD3C)");
        if(is_ram(rectab)) add_band(rectab, rectab+0x8000, ST_DYNAMIC, "rectab (per-frame PVR poly-param records @*0x8C2DAD4C)");
    }

    /* GFX1/GFX2 per active body (STATIC — load-time character art tables). Walk slot table. */
    u32 CB=0x8C2895E0, PB=0x8C287DE0;
    for(int L=0;L<16;L++){
        u32 cnt=du8(CB+L); if(cnt==0||cnt>0x60) continue;
        u32 base=PB+L*0x180;
        for(u32 i=0;i<cnt;i++){
            u32 node=du32(base+i*4); if(!is_ram(node)) continue;
            if(du8(node+0x3)!=0) continue;            /* body only */
            u32 GFX2=du32(node+0x160), GFX1=du32(node+0x15C);
            if(is_ram(GFX2)) add_band(GFX2 & ~0xFFFu, (GFX2 & ~0xFFFu)+0x20000, ST_STATIC, "GFX2 cell-record table (node+0x160, load-time char art)");
            if(is_ram(GFX1)) add_band(GFX1 & ~0xFFFu, (GFX1 & ~0xFFFu)+0x20000, ST_STATIC, "GFX1 tile-dim/header table (node+0x15C, load-time char art)");
        }
    }
}

/* classify one guest idx: returns the matching band or NULL */
static Band* classify(u32 gi){
    for(int b=0;b<NDYN;b++) if(gi>=DYN[b].lo && gi<DYN[b].hi) return &DYN[b];
    return NULL;
}

/* ---- coalesce raw reads into [start,end) touched-regions ---- */
typedef struct { u32 lo, hi; } Span;
static int cmp_span(const void*a,const void*b){ const Span*x=a,*y=b; return (x->lo<y->lo)?-1:(x->lo>y->lo)?1:0; }

int main(void){
    /* load dump verbatim */
    FILE* f=fopen(DUMP,"rb"); if(!f){ fprintf(stderr,"cannot open %s\n",DUMP); return 1; }
    static u8 ram[RAM_SIZE];
    size_t n=fread(ram,1,RAM_SIZE,f); fclose(f);
    fprintf(stderr,"loaded %zu bytes of dump\n",n);
    g_dump=ram;
    fprintf(stderr,"idxtab ptr *(0x8C2DAD3C) = 0x%08X\n", du32(0x8C2DAD3C));
    fprintf(stderr,"rectab ptr *(0x8C2DAD4C) = 0x%08X\n", du32(0x8C2DAD4C));
    fprintf(stderr,"GameGlobalPointer *(0x8C26823C) = 0x%08X\n", du32(0x8C26823C));
    init_static_bands();
    resolve_pointer_bands();

    /* set up the ctx exactly like wasm_entry_frame.c */
    static Sh4Ctx c; memset(&c,0,sizeof c); c.ram=ram;

    /* run ONE render_frame with tracing on */
    mc_trace_n=0; mc_trace_on=1;
    render_frame(&c);
    mc_trace_on=0;
    fprintf(stderr,"recorded %u read events\n",mc_trace_n);

    /* coalesce: build per-byte spans then merge. We expand each read to [addr,addr+size). */
    Span* sp=malloc(sizeof(Span)*mc_trace_n);
    for(u32 i=0;i<mc_trace_n;i++){ sp[i].lo=mc_trace[i].addr; sp[i].hi=mc_trace[i].addr+mc_trace[i].size; }
    qsort(sp,mc_trace_n,sizeof(Span),cmp_span);
    /* merge adjacent/overlapping (gap<=16 merges, so we report tight regions but don't fragment) */
    #define GAP 16u
    Span* merged=malloc(sizeof(Span)*mc_trace_n); int nm=0;
    for(u32 i=0;i<mc_trace_n;i++){
        if(nm && sp[i].lo<=merged[nm-1].hi+GAP){ if(sp[i].hi>merged[nm-1].hi) merged[nm-1].hi=sp[i].hi; }
        else { merged[nm++]=sp[i]; }
    }

    /* classify each merged region. A region may span only one band (we read fine-grained),
     * but to be safe we classify by sampling every byte's band and split on band change. */
    printf("# ===== RENDER_FRAME READ-SET (one frame, matched dump) =====\n");
    printf("# guest_addr   len     kind      what\n");
    u32 sum_dyn=0, sum_static=0, sum_scratch=0, sum_unclass=0;
    for(int m=0;m<nm;m++){
        u32 a=merged[m].lo;
        while(a<merged[m].hi){
            Band* bb=classify(a);
            u32 end = merged[m].hi;
            /* extend run while same band */
            u32 b=a;
            for(; b<merged[m].hi; b++){ Band* cb=classify(b); if(cb!=bb) { end=b; break; } }
            if(b==merged[m].hi) end=merged[m].hi;
            u32 len=end-a;
            const char* kname = bb? (bb->kind==ST_DYNAMIC?"DYNAMIC":bb->kind==ST_STATIC?"STATIC":"SCRATCH") : "UNCLASS";
            printf("0x%08X  %6u  %-8s  %s\n", 0x8C000000u|a, len, kname, bb?bb->what:"*** UNCLASSIFIED (partition bug) ***");
            if(!bb) sum_unclass+=len;
            else if(bb->kind==ST_DYNAMIC) sum_dyn+=len;
            else if(bb->kind==ST_STATIC) sum_static+=len;
            else sum_scratch+=len;
            a=end;
        }
    }
    printf("\n# ===== TOTALS (distinct bytes touched) =====\n");
    printf("# DYNAMIC  bytes/frame : %u\n", sum_dyn);
    printf("# STATIC   bytes (once): %u\n", sum_static);
    printf("# SCRATCH  bytes       : %u\n", sum_scratch);
    printf("# UNCLASS  bytes       : %u   (MUST be 0)\n", sum_unclass);
    free(sp); free(merged);
    return sum_unclass? 2 : 0;
}
