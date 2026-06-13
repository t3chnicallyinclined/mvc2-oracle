/* live_probe.c — run render_frame over a LIVE 16MB RAM dump (live_ram.bin) and print
 * the per-object cursor proof + tile counts. Reveals: (a) does each body's computed
 * running-cursor prefix == the engine resident node+0xDC (multi-object cursor proof on
 * REAL live data), and (b) does any body emit a runaway tile count (over-read source). */
#include "sh4ctx.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
void render_frame(Sh4Ctx *c);
int  render_frame_nscene(void);
extern int  g_body_count;
extern u32  g_obj_dc_resident[64];
extern u32  g_obj_dc_computed[64];
extern int  g_obj_ntiles[64];
extern u32  g_obj_node[64];
static u8 ram[RAM_SIZE];
int main(int argc,char**argv){
    const char* path = argc>1?argv[1]:"live_ram.bin";
    FILE*f=fopen(path,"rb"); if(!f){fprintf(stderr,"open %s fail\n",path);return 1;}
    size_t n=fread(ram,1,RAM_SIZE,f); fclose(f);
    fprintf(stderr,"loaded %zu bytes from %s\n",n,path);
    Sh4Ctx c; memset(&c,0,sizeof c); c.ram=ram;
    render_frame(&c);
    int q=render_frame_nscene();
    printf("bodies=%d total_quads=%d\n",g_body_count,q);
    u32 run=0;
    for(int b=0;b<g_body_count;b++){
        u32 res=g_obj_dc_resident[b],comp=g_obj_dc_computed[b];
        printf("  body%d node=%08X ntiles=%d computed_prefix=%u resident+0xDC=%u %s%s\n",
               b,g_obj_node[b],g_obj_ntiles[b],comp,res,
               res==comp?"CURSOR-OK":"CURSOR-MISMATCH",
               g_obj_ntiles[b]>200?"  <<< RUNAWAY TILES":"");
        if(comp!=run) printf("    NOTE computed_prefix %u != running-sum %u\n",comp,run);
        run+=(u32)g_obj_ntiles[b];
    }
    return 0;
}
