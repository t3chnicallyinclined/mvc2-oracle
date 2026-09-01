-- ============================================================================
-- 61_objpool_list_system_live2_dissolved.surql
-- 2026-07-05 — (1) The COMPLETE MVC2 object-list system (bank04) traced end-to-end:
-- objpool alloc/free, 14 render lists, slot-table clear/register frame order,
-- registrar cat<=4 gate; (2) ALL ELEVEN callers of the sprite submit loc_8C1244B0
-- (why BTCW misses text/counter quads by design); (3) the _live2 "typhoon/hitspark
-- contradiction" DISSOLVED by measurement: the pair contains NO supers at all.
-- Apply, then 07_dedup_edges.surql.
-- ============================================================================
USE NS re DB kb;

UPSERT finding:objpool_list_system_complete SET date='2026-07-05', confidence='high', status='confirmed',
  contribution_candidate=true,
  note='COMPLETE OBJECT/LIST SYSTEM (marvelous2 bank04.asm). POOL INIT loc_8c044dce (bank04:11601):
objpool base 0x8C26AA54, 0x100 nodes x 0x1D0 (end 0x8C287A54=base+0x1D000... free-list head stored at
0x8C287A54, arena end ptr 0x8C287A58=base+0x1CE30); FOURTEEN render-list heads 0x8C287A5C[0..13] (u32 x14),
tails 0x8C287A94[0..13], per-list counts 0x8C287ACC (u16 x14), free count 0x8C287AE8 (init 0xF6=246),
total 0x8C287AEA (0x100). ALLOC loc_8c044f12/loc_8c044f26(r4=arg,r5=LIST,r6=ctor-idx): pops free node,
sets node+0x03 = r5 (THE cat BYTE == the list index), links via +0x08 prev/+0x0C next, jsr
bank14.loc_8c14dfec[r6*4](r4,node,r5). FREE loc_8c0450c0: clears node+0x12C FIRST (so +0x12C!=0 == live).
Node has per-frame update callback at +0x10 (walked by loc_8c044ef0 per list). FRAME ORDER (in-match tick
loc_8c03e888 bank03:34926, loc_8c03e8de+): update -> loc_8c045208 CLEARS the 16 slot-table count bytes
0x8C2895E0 -> loc_8c043f60 registers the 6 CHAR STRUCTS (walks 0x8C268340 stride 0x5A4; per active char
jsr loc_8c044014 geometry-prep chain [-> loc_8c033b0a] + registrar) -> loc_8c04508e(3),(4),(1),(2)
registers objpool lists 3,4,1,2 (per live node: bank03.loc_8c033b0a then loc_8c04515e) -> loc_8c030858
RENDER. REGISTRAR loc_8c04515e (bank04:12166): REFUSES cat>4 (mov 4,r3; cmp/gt r3,r0 -> skip), gate
node+0x12C!=0 (offset word loc_8c04521e=0x012C), layer = node+0x24 -> slot ptr array 0x8C287DE0 +
layer*0x180 + cnt*4, count byte 0x8C2895E0+layer capped 0x60, insertion-sorted by node+0x31. THEREFORE the
slot table ONLY EVER holds cats 0-4 (0=char struct, 1-4=sprite-class objpool satellites/effects).
Lists 5..13 NEVER enter the slot table: they render in the SECOND (3D/NaomiLib) machine passes called from
loc_8c030858/loc_8c030886: lists 5,6 loc_8c030d12/loc_8c030d24; 7,8 loc_8c030d36; 9 loc_8c030d56; 0xB
loc_8c030dcc (+ conditional extra walk loc_8c030d68 of head 0x8c287a8c=list 0xC calling
bank0f.loc_8c0f215e); 0xC/0xD walks loc_8c0307ae/loc_8c0307d2 (bank01.loc_8c01836c / bank02.loc_8c02861e
per node). Per-node 3D draw loc_8c0301f6 (bank03:129): builds matrix from node+0x34/38/3C pos +
+0x40/44/48 angle ptrs + +0x50 scale per node+0xCC FLAG BITS (0x4000,0x01,0x100,0x80,0x08,0x04,0x02,0x10),
then draws bank11.loc_8c11fa80(node+0x88 EMBEDDED struct) and/or bank11.loc_8c1201e0(ptr @node+0xC8 =
NaomiLib-style display list). Stage set pieces measured LIVE (_live2 objpool): 37x cat11 + 2x cat12 +
2x cat6 persistent nodes (cat6 pair tracks the two chars = shadows/companions). Named arenas (work.asm:36-39):
0x0CE60000 Texture_Decompress_Buffer / 0x0CE80000 DM00 Poly / 0x0CEA0000 Stage Poly / 0x0CED0000 Effect
Poly (NaomiLib POL model data for effects; loaded by bank02 loader loc_8c027d2c-family; per-stage object
spawner loc_8c032be0 bank03:6485 switches on STG_ID). bank10 loc_8c100968 (bank10:1270) spawns a
hit-related object onto LIST 7 (allocator r5=7, r6=1, callback loc_8c100868 at node+0x10) = proof some
hit/impact effects use the 3D-list machine, invisible to the slot table AND to the BTCW arm PCs.
GOTCHA for measurement scripts: objpool satellite nodes carry +0x00==0 (only CHAR STRUCTS have +0x00
active=1) — NEVER filter slot entries by u8(node+0)!=0; the live gate is +0x12C.';

UPSERT finding:submit_1244b0_all_callers SET date='2026-07-05', confidence='high', status='confirmed',
  note='ALL ELEVEN direct callers of the sprite submit bank12.loc_8C1244B0 (grep #data across banks):
(1) bank03 body walker loc_8c0344d4 call site at loc_8c034864 (= BTCW/ASMTRACE arm PC 0x8C034864);
(2) bank03 scale walker loc_8c0348c8 call site at loc_8c034ba4 (= arm PC 0x8C034BA4);
(3) bank03 loc_8c03069e-area render-pass variant (pool loc_8c030758);
(4) bank03 loc_8c0312d6 (the list-0xC pass entered via loc_8c03082a with r4=r5=0xC);
(5) bank03 loc_8c031470 (special-mode render taken when *(GGP)+0x2E==1, see loc_8c0308aa);
(6) bank03 loc_8c0319f4; (7) bank03 loc_8c033fdc; (8) bank03 loc_8c03408e (load-time/packer-adjacent);
(9) bank02 loc_8c02a7ce STRING/GLYPH renderer (walks a byte string mov.b @r8+, glyph lookup loc_8c02a400,
one submit per char via call site loc_8c02a79e) — announcer/floating text;
(10) bank02 loc_8c02aa14 (second text variant); (11) bank02 loc_8c02d214 COMBO-COUNTER drawer (display
state struct 0x8C1F97A8: value u16@+4, shown u16@+6, slide timer; glyph draw loc_8c02d508) + siblings
loc_8c02d574/loc_8c02d8ac in the same pool family. CONSEQUENCE: quads from callers 3-11 pass the shared
tile-arena allocator + submit (their TCWs are sequential per-frame arena slots exactly like body tiles,
0x200-byte slots, double-buffered VRAM 0x41xxxx even / 0x44xxxx odd frames) but NEVER pass the two arm
PCs, so BTCW misses them BY DESIGN. To capture them, arm the submit itself (PC 0x8C1248CC fires for every
caller) and attribute by caller PR, or arm each caller.';

UPSERT source:live2_pair_idle_proven SET kind='measurement',
  ref='scratchpad _live2.gsta.mcrr + _live2.mirror.zcst; _catscan.mjs/_slotraw.mjs/_actionscan.mjs/_xcorr.mjs/_xcheck.mjs; render_ta.mjs --frame 213/206 PNG',
  note='THE _live2 "typhoon/hitspark contradiction" IS DISSOLVED — the capture pair contains NO supers,
NO projectiles, NO hits. PROOF: (a) alignment is EXACT: gsta frame F pairs with mirror msg F-358
(idle-bob cross-correlation corr=0.997 sharp peak; per-frame mirror body-top minY == gsta P1 screenY
- 249.0 px CONSTANT point-by-point); (b) across ALL 1802 gsta frames: both chars at x=282/517 constant,
sels strictly idle ranges, P1/P2 health 144/144 NEVER changes, objpool active census constant
(37 cat11 + 2 cat12 + 2 cat6 stage nodes + 1-3 Storm cape satellites cat3/cat4 sel 0x2db-0x37c);
(c) rendering the LARGEST mirror "burst" frame (msg#213, 122 sprites) shows Storm+Cable standing IDLE in
training stage — the sprite-count spikes (92->132, 437 of 1764 frames) are Storm\'s flowing-cape idle
animation varying the per-frame tile count, all quads are body-arena tiles of the same <=6 slot nodes.
The two prior "measured facts" were artifacts: "slot table EXACTLY 2 nodes" came from _hitscan.mjs
filtering u8(node+0)==0 (objpool satellites legitimately carry +0x00==0; real census = 4-6 nodes incl
cape sats, matching BTCW max 6); "engine draws effect quads" was the cape tile-count variance misread as
effect bursts. BTCW "zero effect tiles" is CORRECT for this window (nothing bit15 ever spawned). The
user\'s live symptoms (projectile wrong texture / missing hitsparks) are from gameplay OUTSIDE this
capture window and need a FRESH paired capture taken while the moves are actually performed.';

UPSERT finding:typhoon_hitspark_class_open SET date='2026-07-05', confidence='medium', status='open',
  note='OPEN: which class Typhoon/Hailstorm/Lightning-Attack projectiles and HITSPARKS are. STRONG
INFERENCE (architecture, finding:objpool_list_system_complete): sprite-class effects all spawn via the
one allocator into lists 1-4 and register into the slot table — exactly like the CONFIRMED Lightning
Storm bolts (_gate_bit15: up to 35 layer-0 cat=1 nodes, bit15 sels 0x8006-0x801d, g1=0xc420040) and the
cat=1 sel 0x44x non-bit15 beam segments; so Typhoon/Hailstorm/hitsparks are EXPECTED to be cat 1-4
objpool slot nodes already carried by the GSTA wire (hitsparks resolving parts via THEIR OWN node+0x15C
GFX pointer possibly into the shared effects bank / Effect Poly 0x0CED0000 assets). CAVEAT: bank10
loc_8c100968 proves at least one hit-effect object spawns onto LIST 7 (3D machine, draws via bank11
loc_8c11fa80/loc_8c1201e0, never in slot table, never passes 0x8C1248CC-with-arm). DISCRIMINATOR (one
capture): fresh paired capture WHILE casting typhoon/hailstorm + landing hits; scan objpool for
transient +0x12C nodes by cat (use _catscan.mjs, NOT the buggy +0x00 filter). If new cat1-4 nodes appear
-> slot class, wire already ships them, fix is client texture resolution. If only list>=5 nodes appear ->
3D class: client needs a 3D-list walk (matrix from node+0x34..+0x50 per +0xCC flags; POL data from Effect
Poly 0x0CED0000 static) and the wire should add the 0x98-byte list-head block 0x8C287A54..0x8C287AEC
(heads/tails/counts; NOT currently in any dynamic region — only stale static ram16; node ORDER/linkage
+0x08/+0x0C already rides the shipped objpool). Optional live probe: ASMTRACE the submit PC 0x8C1248CC
capturing PR to attribute every quad to its caller, or arm bank11.loc_8c11fa80 entry (r4=node+0x88).';

RELATE finding:objpool_list_system_complete->cites->routine:loc_8c04515e SET kind='cites';
RELATE finding:objpool_list_system_complete->cites->routine:loc_8c0308c2 SET kind='cites';
RELATE finding:submit_1244b0_all_callers->cites->routine:loc_8c0344d4 SET kind='cites';
RELATE finding:submit_1244b0_all_callers->cites->routine:loc_8c0348c8 SET kind='cites';
RELATE finding:typhoon_hitspark_class_open->cites->source:live2_pair_idle_proven SET kind='cites';
RELATE finding:typhoon_hitspark_class_open->about->finding:objpool_list_system_complete SET kind='about';
RELATE finding:submit_1244b0_all_callers->about->finding:objpool_list_system_complete SET kind='about';
