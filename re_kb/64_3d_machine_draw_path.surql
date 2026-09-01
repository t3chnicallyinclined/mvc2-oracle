-- ============================================================================
-- 64_3d_machine_draw_path.surql
-- 2026-07-06 — The SECOND (3D/NaomiLib) render machine's draw path RE'd to
-- transpile-prep depth: matrix build -> per-node draw -> THE one model drawer
-- (loc_8c129cc0) -> SQ/TA emission. Arm PCs for a BTCW-style hook, the
-- outside-node global read set (wire audit), texture binding (TCW embedded in
-- POL model data), Effect Poly 0x0CED0000 structure (static post-load).
-- CORRECTS re_kb/61: loc_8c11fa80 = STORE XMTRX, loc_8c1201e0 = LOAD XMTRX,
-- model ptr = node+0x84 (NOT +0xC8; +0xC8 = optional matrix ptr).
-- Apply, then 07_dedup_edges.surql.
-- ============================================================================
USE NS re DB kb;

-- ---------------------------------------------------------------------------
-- Corrected roles of the bank11 pair
-- ---------------------------------------------------------------------------
UPSERT routine:loc_8c11fa80 SET bank='bank11', line=38245,
  note='CORRECTION vs finding:objpool_list_system_complete: NOT a draw. STORE XMTRX -> r4 buffer
(frchg; fmov fr15..fr0 @-r4 from r4+0x40 down; r4==0 -> default from ctx *(0x8C2D68E8+0x8)). Used by
loc_8c0301f6 to save the composed node matrix INTO node+0x88 (node+0x88..0xC7 = embedded 4x4 matrix,
0x40 bytes, ends exactly at +0xC8).';

UPSERT routine:loc_8c1201e0 SET bank='bank11', line=39380,
  note='CORRECTION: NOT a display-list draw. LOAD XMTRX <- r4 (16 floats) via bra bank12.loc_8c120220
(bank12:1, frchg+16 fmov loads); r4==0 -> default from ctx *(0x8C2D68E8+0x8). The per-node draw calls it
with r4=node+0x88 (the composed matrix). node+0xC8 = OPTIONAL matrix POINTER consumed by the matrix
builder (loc_8c0301f6 bank03:141-147: if *(node+0xC8)!=0 load it as the base), not a POL pointer.';

-- ---------------------------------------------------------------------------
-- Matrix build + walk + per-node draw (bank03)
-- ---------------------------------------------------------------------------
UPSERT routine:loc_8c0301f6 SET bank='bank03', line=129,
  note='3D-node MATRIX BUILDER (r4=node, r5=list). njPushMatrix loc_8c120950(0); base = *(node+0xC8)
matrix if set (load via loc_8c1201e0) else loc_8c121100(); +0xCC&0x4000 -> apply embedded node+0x88
(loc_8c120540); global 0x8c212c14==1 && +0xCC&0x10000 && list==0xB && +0xC8==0 -> scale(1,0.93,1)
loc_8c120fc0 (0x3f6e147b const, bank03:253); +0xCC&0x01 -> TRANSLATE node+0x34/38/3C (loc_8c1210e0);
LISTS 7/8/9 PRE-SCALE POSITION BY 0.1 (const 0x3dcccccd bank03:426, copy via bank12.loc_8c1294c8 r0=0xC
= the Duff copier); +0xCC&0x100 -> BILLBOARD-YAW to camera: atan (bank11.loc_8c11e170) of
(cam.x-node.x, cam.z-node.z) read from CAM STRUCT 0x8c26a518 +0x18/+0x20 -> RotY loc_8c120cd0;
+0xCC&0x80 -> billboard-pitch (cam +0x1C y) -> RotX loc_8c120b20; +0xCC&0x08 RotZ loc_8c120d90(*(+0x48));
&0x04 RotY(*(+0x44)); &0x02 RotX(*(+0x40)); &0x10 scale-vec loc_8c120ff0(node+0x50); STORE matrix
loc_8c11fa80(node+0x88); loc_8c120900(1)=njPopMatrix. So node+0x88 holds the FULL composed matrix
(base incl view/projection) for the drawer.';

UPSERT routine:loc_8c030410 SET bank='bank03', line=447,
  note='3D LIST WALKER (r4=list idx). head = *(0x8c287a5c + idx*4); walk +0x0C next. Per node gate:
u8(node+0x12C)!=0 AND *(node+0x84)!=0 (pool words bank03:582-584: 0x012C, 0x0084 -> NODE+0x84 = THE
MODEL/POL POINTER). Optional per-node callback *(node+0x28) (loc_8c0305ce). Then loc_8c030452(node,list).
Render-pass order (loc_8c0305d8 bank03:733 + loc_8c030658): passes draw lists 0x0B, 5, 7, 1, ... with
bank02 pass-setup calls between (loc_8c02e334/loc_8c02e1a4/loc_8c02e246) - NOTE list 1 also passes the
3D walker (only nodes with +0x84 set draw here; sprite cat1 nodes have +0x84=0).';

UPSERT routine:loc_8c030452 SET bank='bank03', line=491,
  note='PER-NODE 3D DRAW. njPush loc_8c120950(0); LOAD node matrix loc_8c1201e0(node+0x88); +0xCC&0x10
-> loc_8c0301b4(node+0x50)+loc_8c122710(fr4) uniform-scale fixup; loc_8c030550(node) = SET COLOR:
gate +0xCC&0x400, if +0xCC&0x800 multiply node+0x78/7C/80 (RGB floats) by global light 0x8c26a89c
+0xC/10/14, call bank12.loc_8c123780(r,g,b); DRAW DISPATCH on +0xCC: &0x2000 -> loc_8c123370(0x80) +
bank12.loc_8c123410(*(node+0x84)); &0x8000 -> bank13.loc_8c132640(model); &0x20 -> lists 0xB/0xD
bank12.loc_8c123610(fr4=node+0x74 alpha, model) else loc_8c123650(same); DEFAULT -> lists 0xB/0xD
loc_8c1235b0(model) else loc_8c1235e0(model). Hit effects (+0xCC=0x405, list 7) take DEFAULT non-B/D =
loc_8c1235e0. Tail bank12.loc_8c120900(1) pop. The B/D (stage) wrapper loc_8c1235b0 additionally
composes matrix 0x8C2D6BC0 via loc_8c1205e0 (bank12:7658-7660).';

-- ---------------------------------------------------------------------------
-- THE model drawer + emit map (the capture-hook PCs)
-- ---------------------------------------------------------------------------
UPSERT routine:loc_8c129cc0 SET bank='bank12', line=23192,
  note='THE single POL MODEL DRAWER for BOTH model types. Reached via runtime-patched dispatch table
0x8C123C60 (+0x18 type0 = +0x1C type1 = 0x8c129cc0, +0x20 = loc_8c120900 pop; LIVE-READ from _live4 RAM
- ROM holds zeros, patched at init). Entry fr4=alpha (loc_8c129cc0 sets 1.0; alt entry loc_8c129cc2
keeps caller fr4 = node+0x74), r4=model (add 0x18 skips header), r5=0x8C2DEE20 param block. Per strip:
loads [word0 -> r8 | masks][float cull-center][word2 -> r1 | mask][float cull-radius]; screen-cull via
ftrv of strip center PC 0x8c129dbc + fcmp (loc_8c129e88 block); EMIT-SLOT select: (r8>>19)&7 indexes
table r10=**(0x8C2AA508); QACR0/QACR1 (0xFF000038/3C) programmed from entry>>24 at PC ~0x8c129dda-e2
(bank12:23338-23346, only when slot changes, cached in r11); SQ virtual cursor r6 = 0xE0000000 |
(entry & 0x03FFFFFF); entry advanced +0x40/parcel and stored back (mov.l r5,@(r0,r10) PC 0x8c12a370-area
+ 0x8c129e7c-area). Vertices: fmov @r4+ -> ftrv xmtrx -> perspective divide -> SQ parcel -> pref.';

UPSERT finding:3d_draw_emit_map SET date='2026-07-06', confidence='high', status='confirmed',
  contribution_candidate=true,
  note='ARM PCs for a BTCW-style capture hook on the 3D machine (all inside bank12.loc_8c129cc0; the
analog of sprite-path 0x8C1248CC). GLOBAL-PARAM: write PC 0x8c129e0e (mov.l r8,@r6; r8=composed param
word0, r6=SQ cursor), flush prefs PC 0x8c129e66 (line1: [r8][0][0][0]) and PC 0x8c129e78 (line2: 8
face-color floats DR0-DR6, intensity-scaled by fr11/light). VERTEX LOOPS (unrolled, double-buffered
fv4/fv8): ftrv PCs 0x8c12a0d8/0x8c12a108/0x8c12a146 (loop A), 0x8c12a1f8/0x8c12a244/0x8c12a296 (loop B),
0x8c12a356 (loop C); 1/w divides fdiv fr4,fr7 @0x8c12a0dc/0x8c12a202/0x8c12a36c and fdiv fr8,fr11
@0x8c12a11c/0x8c12a25c; vertex SQ flush prefs @r6: 0x8c129fe6/0x8c129fec/0x8c12a114/0x8c12a150/
0x8c12a1cc/0x8c12a24c/0x8c12a29e/0x8c12a320 (pref @r4/@r14 = data prefetch, NOT submits). REGISTERS at
arm: r6=SQ target (0xE0000000-based), r8/r1=param words, r5=slot-table entry (target addr), r11=slot
idx<<2, r10=slot table, fv4/fv8=post-transform vertex, fr7/fr11=w. EMIT-SLOT TABLE (LIVE _live4):
*(0x8C2AA508)=0x8C32D328 -> 8 entries [0x100207e0, 0xACF00040, 0xACF126C0, 0xACFA0040, 0xACFB0040,
0,0,0]: slot0 = TA POLYGON FIFO (QACR=0x10, DIRECT submission - the mirror sees these as TR ParaType-4
textured polys); slots1-4 = DEFERRED TA-format command buffers in P2 RAM 0x0CF00040/0x0CF126C0/
0x0CFA0040/0x0CFB0040 (QACR=0xAC -> SQ writes RAM; replayed by a later pass - buffer-drain routine not
yet traced, OPEN). Strip word0 bits[21:19] choose live-vs-deferred per strip. RECONCILE with mirror:
calm-state 3-5-vert strips = ambient POL strip lengths; 4-vert constant-z quads at hits = billboarded
quad models (+0xCC=0x405: translate(pos*0.1 for list7)+RotY only -> constant z after transform).';

-- ---------------------------------------------------------------------------
-- Outside-node read set (what must be on the wire)
-- ---------------------------------------------------------------------------
UPSERT finding:3d_outside_node_readset SET date='2026-07-06', confidence='high', status='confirmed',
  note='EVERY outside-node global the 3D walk+draw reads (NONE named in marvelous2 work.asm; live
values from _live4 static RAM): (1) list heads 0x8C287A5C[0..13] (+tails/counts, already catalogued
re_kb/61); (2) nj context 0x8C2D68E8: +0x0 stack depth words, +0x8 matrix-stack cursor (stack areas
0x8C2D6920/0x8C2D69E0 per ctx +0x1C/+0x28); (3) PROJECTION+VIEWPORT matrix 0x8C2D6BC0 (copy at
0x8C2D6C00): LIVE [0,320,0,0][0,0,-320,0][-1,-320,-240,1][0,0,0,0] - screen half-extents 320/240 baked
in; composed per-frame by the camera setup (composer routine OPEN); (4) CAMERA struct 0x8C26A518:
+0xC/+0x10/+0x14 and +0x18/+0x1C/+0x20 = cam pos (LIVE 231.2, 95.0, 812.4) - billboard reads +0x18/1C/20;
(5) light color 0x8C26A89C +0xC/10/14 (LIVE 1,1,1); (6) light/param block 0x8C2DEE20 (LIVE 0, 195.21,
390.42, -0.1, 0, 1, 1, 1) + 0x8C2DEE8C/0x8C2DEEA0; (7) scale global 0x8C32B448 (LIVE 1.0f, the fdiv
divisor at 0x8c129cd0); (8) consts 0x8C2D6B98/9C (LIVE 452.548, 400.001); (9) mode 0x8C212C14 (LIVE 1;
gates the 0.93 x-scale for list 0xB); (10) emit-slot table ptr 0x8C2AA508 -> 0x8C32D328[8] + mode word
0x8C2AA4C4 (LIVE 0x68); (11) Effect-Poly directory ptr 0x8C26A908 (LIVE 0x0CED0000); (12) bank16 ROM
const vecs 0x8C16BD88-94/0x8C16BE18-BE60 (static, in-binary). Items 2-10 are RAM the wire must carry
(or the client must recompute); 12 is code-resident; 11+region are static assets.';

-- ---------------------------------------------------------------------------
-- Texture binding + Effect Poly structure
-- ---------------------------------------------------------------------------
UPSERT finding:3d_texture_binding SET date='2026-07-06', confidence='high', status='confirmed',
  note='TEXTURE BINDING: the TSP/TCW words are EMBEDDED IN THE POL MODEL DATA itself - the hit-effect
model at 0x0CEEB838 (Effect Poly slot +0x2A4, the loc_8C103BD0 spawn) contains literal TCW 0x50097200
at model+0x24 (LIVE read) - exactly the mirror-observed pt4 TCW class (0x5008f700-family; 0x40095400 =
another model). The drawer ORs strip words with runtime masks (pool globals incl an XOR selector r9)
but the texture ADDRESS comes from the model. No fixed per-object table, no per-frame texel upload:
the draw path writes ONLY to SQ (TA FIFO / deferred RAM buffers) - textures are RESIDENT VRAM uploaded
at load. For the client: resolving these textures = decode the VRAM at the TCW address once (prefix/
static), same as stage textures.';

UPSERT finding:effect_poly_structure SET date='2026-07-06', confidence='high', status='confirmed',
  note='EFFECT POLY 0x0CED0000 (arena named in work.asm:36-39, loaded once by the bank02 loader family
loc_8c027d2c at match load): DIRECTORY header [+0x0 u32 ptr-to-first-model = 0x0CED0010][+0x4 u32 model
count = 0xF1 = 241 (LIVE)] followed by intra-region model POINTERS (+0x8, +0xC, +0x10...; per-effect
slots - the char/hit spawn wrappers read *(dir + slot) into node+0x84, e.g. slot +0x2A4 -> 0x0CEEB838).
MODEL: [+0x0 u32 type 0|1 (both dispatch to loc_8c129cc0)][+0x4 u32 flags (bit1 SET -> wrapper skips
the light-setup call, bank12:7677)][+0x8 0][+0xC 3 floats bounds][+0x18.. strip records]. STRIP record
head: [u32 word0: PCW-source flags + emit-slot bits21:19][f32 cull center][u32 word2: TSP-source]
[f32 cull radius] + embedded TSP/TCW words + inline vertex arrays (pos xyz + uv + color; 3-5 verts
typical). ALL pointers intra-region; the drawer only READS model bytes (every access fmov/mov.l @r4+)
=> the WHOLE 0x0CED0000 region is STATIC POST-LOAD - "resident" for the wire means: ship/seed once per
match (or read from the client-side disc image), never per frame.';

-- ---------------------------------------------------------------------------
-- Sources + edges
-- ---------------------------------------------------------------------------
UPSERT source:bank12_drawer_disasm SET kind='disasm',
  ref='_marv_re/build/bank03.asm:129-807, bank11.asm:38245/39380, bank12.asm:1-120,1080-1134,7642-7756,8415-8614,23100-24200',
  note='Full static trace: matrix builder, walker, per-node draw, wrapper chain, model drawer emit
loops. Numeric-displacement pool resolution per-line addresses (spawn_catalog2.py Asm class).';

UPSERT source:live4_nj_globals SET kind='measurement',
  ref='scratchpad _njptrs.mjs + _njtab.mjs on _live4.gsta.mcrr static RAM',
  note='Live reads: dispatch table 0x8C123C60 (+0x18/+0x1C=0x8c129cc0, +0x20=0x8c120900), emit-slot
table *(0x8C2AA508)=0x8C32D328 [0x100207e0, 4x 0xACFxxxxx deferred, 0,0,0], projection matrix
0x8C2D6BC0 values, cam pos 0x8C26A518, light 0x8C26A89C/0x8C2DEE20, Effect-Poly dir (241 models),
hit-effect model 0x0CEEB838 header incl embedded TCW 0x50097200.';

RELATE finding:3d_draw_emit_map->cites->source:bank12_drawer_disasm SET kind='cites';
RELATE finding:3d_draw_emit_map->cites->source:live4_nj_globals SET kind='cites';
RELATE finding:3d_draw_emit_map->cites->routine:loc_8c129cc0 SET kind='cites';
RELATE finding:3d_outside_node_readset->cites->source:live4_nj_globals SET kind='cites';
RELATE finding:3d_outside_node_readset->cites->source:bank12_drawer_disasm SET kind='cites';
RELATE finding:3d_texture_binding->cites->source:live4_nj_globals SET kind='cites';
RELATE finding:effect_poly_structure->cites->source:live4_nj_globals SET kind='cites';
RELATE finding:effect_poly_structure->about->finding:objpool_list_system_complete SET kind='about';
RELATE finding:3d_draw_emit_map->about->finding:hitspark_class_resolved SET kind='about';
RELATE finding:3d_draw_emit_map->about->finding:objpool_list_system_complete SET kind='about';
RELATE routine:loc_8c030452->cites->source:bank12_drawer_disasm SET kind='cites';
RELATE routine:loc_8c0301f6->cites->source:bank12_drawer_disasm SET kind='cites';
