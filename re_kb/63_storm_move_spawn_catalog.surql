-- ============================================================================
-- 63_storm_move_spawn_catalog.surql
-- 2026-07-05 — STORM (PL2A, char_id 0x2A) MOVE -> SPAWN-CLASS CATALOG, static
-- (S_PL2A.asm + banks 04/05/09/0e/10) cross-VALIDATED against the _live4 action
-- capture (objpool node births keyed by the +0x10 callback pointer).
-- Also RESOLVES finding:typhoon_hitspark_class_open: visible hitsparks are
-- 3D-machine (lists 7/8) objects, NOT sprite-machine quads.
-- Apply, then 07_dedup_edges.surql.
-- ============================================================================
USE NS re DB kb;

-- ---------------------------------------------------------------------------
-- Mechanism: how char move programs spawn objects
-- ---------------------------------------------------------------------------
UPSERT finding:spl_spawn_mechanism SET date='2026-07-05', confidence='high', status='confirmed',
  contribution_candidate=true,
  note='HOW S_PLxx MOVE PROGRAMS SPAWN OBJECTS (Storm/S_PL2A traced end-to-end). The SPL overlay NEVER
calls the allocator loc_8c044f12/f26 directly (no #symbol import). Instead: (1) each character has
PER-CHARACTER SPAWN WRAPPER routines compiled into banks 06-0e (Storm: bank09 loc_8c09b988/bba4/beec/
c1f4/c484 = specials/supers projectile+satellite spawners, bank0e loc_8c0e3098/3258/344c/3584 = ambient/
attached satellite spawners; each wrapper hardcodes the +0x26 type word (char_id<<8|type: Storm 0x2A00..
0x2A04) and installs its own per-frame callback at node+0x10 which dispatches via a bank15 state table
indexed by node+0x04). (2) The SPL imports these wrappers by #symbol and calls them from the move handler.
(3) SPL handler table: BEG_ce30000 copies a 28-entry pointer table (PTR_ce327a4, end of S_PL2A) to
*(char+0x428); entries = per-state-class handlers; idx8 (LAB_ce310cc, 0x0CE310CC) is the master
special/super handler containing every per-move block (anim loads via loc_8c034e8c(r5=group,r6=anim)
identify the move; spawn calls sit inside the same block). (4) ATTACHED satellites (cape, idle ambient)
are NOT SPL-spawned: bank04 loc_8c04f478 (bank04:37293) switches on char+0x01 (character_id) and
tail-calls the per-char attach spawners (case 0x2A=Storm -> bank0e.loc_8c0e3258 then loc_8c0e344c; cases
exist for char_ids 0x00,0x03,0x04,0x06,0x0A,0x0B,0x0C,0x10,0x14,0x15,0x18,0x19,0x1C,0x1E,0x1F,0x27,0x2A,
0x2C,0x38 = the chars with attached objects). (5) Allocator register contract re-CONFIRMED from
bank04.asm:11793-11869: alloc(r4=arg,r5=LIST,r6=ctor-idx), node+0x03=r5, ctor table @pool loc_8c045020
called ctor(r4=arg,r5=node,r6=list). NOTE +0x12C (live gate) is NOT set by the bank09 wrappers at alloc
time - it is set later by the node state machine, so capture-side "births" = first-VISIBLE frame.
IDENT: node+0x10 callback uniquely identifies the spawning wrapper in any RAM capture - the key that
joins static disasm to live captures.';

-- ---------------------------------------------------------------------------
-- Storm spawn wrappers (routines)
-- ---------------------------------------------------------------------------
UPSERT routine:loc_8c04f478 SET bank='bank04', line=37293,
  note='Per-character ATTACHED-OBJECT spawner. Switch on char+0x01 (character_id). Storm case 0x2A @
loc_8c04f59e (bank04:37474): jsr bank0e.loc_8c0e3258 (recurring overlay satellite) then tail-jmp
bank0e.loc_8c0e344c (cape pair). Jump-pool bank04:37506-37551 lists every per-char attach spawner
(banks 0b/0c/0d/0e/06).';

UPSERT routine:loc_8c09bba4 SET bank='bank09', line=27743,
  note='STORM TYPHOON/WHIRLWIND projectile spawner. TWO allocs (list=1,ctor=0) loop r14=1..0 ->
node+0x20=1/0. cb node+0x10 = loc_8c09bc5a (bank09:27846, state table indexed node+0x04). +0x26=0x2A01.
Called from S_PL2A idx8 handler @0x0CE31DEC (line 4679). LIVE (_live4): 18 births = 9 casts x 2 nodes,
life ~66f, sels 0x3c6-0x3ca (966-970 tornado ring art, NON-bit15 body-walker) + 0x8000-0x8005 (bit15
scale-walker effect parts). One cast = one art node + one bit15 node.';

UPSERT routine:loc_8c09beec SET bank='bank09', line=28243,
  note='STORM LIGHTNING STORM bolt spawner (INFERRED name, strong: matches _gate_bit15 window). Loop
count r13 up to r10 (COUNT-PARAMETERIZED, not fixed); alloc (list=1,ctor=0) per bolt; node pos copied
from owner +0x34/+0x38; node+0x07=r12 flag, +0x20=index, +0x26=0x2A02; cb = loc_8c09bf9a (bank09:28339,
state table 0x8C156064). Sibling single-spawner loc_8C09BF52 (bank09:28298) same family. Called from
S_PL2A idx8 @0x0CE31444 (line 3217), re-called per frame during the super. LIVE: 420 births in super
windows (f927-956, f1635-1675...), life ~4.6f, sels 0x8006-0x801d (bit15, masked 6-29) = the _gate_bit15
"up to 35 concurrent cat1 layer-0" population.';

UPSERT routine:loc_8c09c1f4 SET bank='bank09', line=28693,
  note='STORM HAIL STORM chunk spawner (INFERRED name, strong: 8-column+chunk-rain structure). ONE alloc
(list=1,ctor=0) per call, called per-frame during super active. +0x26=0x2A03; cb = loc_8c09c236
(bank09:28733). Called from S_PL2A idx8 @0x0CE31BFC (line 4387). LIVE: 128 births in windows starting
f729 (hp drain f735-769), lives 4-63f, sels 0x8028-0x8041 (bit15, masked 40-65 = hail chunk art in the
effect sheet).';

UPSERT routine:loc_8c09b988 SET bank='bank09', line=27419,
  note='STORM HAIL STORM 8-column spawner (INFERRED name, strong). ONE call loops r14=7..0 -> EIGHT
allocs (list=1,ctor=0); node+0x21=7..0 column index, +0x26=0x2A00, node+0x01=owner char_id; cb =
loc_8c09b9dc (bank09:27468, dispatch bank15 0x8c155f24). Called from S_PL2A idx8 @0x0CE31242 (line 2908).
LIVE: 8 births v21=0..7 become visible staggered f650-f731 (visibility = +0x12C set by state machine,
not at alloc), life 20-57f, sels 0x43b-0x447 (1083-1095 = PL2A g21 anim22/26 art = hail stream columns,
NON-bit15).';

UPSERT routine:loc_8c09c484 SET bank='bank09', line=29069,
  note='Storm spawn wrapper, 1x alloc (list=1,ctor=0). Called from S_PL2A idx8 @0x0CE32080 (line 5067),
block adjacent to g20 cast-pose + g21a24/a25 loads. NOT OBSERVED in _live4 (0 births) - the remaining
special (Double Typhoon candidate / unperformed move). OPEN: needs a capture performing every special.';

UPSERT routine:loc_8c0e344c SET bank='bank0e', line=7726,
  note='STORM CAPE pair spawner. TWO back-to-back allocs (list=4,ctor=0); node+0x20=0/1 (front/back);
+0x26=0x2A03; cb both = loc_8c0e34a2 (bank0e:7776, dispatch bank15 0x8C15EBFC by node+0x04). Reached via
char-id switch loc_8c04f478, NOT via SPL. LIVE: 74 births = 37 pair-spawns across match, layers 5/6,
sels 0x2db-0x351 (731-849 cape art, NON-bit15), owner sids 66-110 (idle/walk/jump poses) - the pair
re-spawns as body state changes.';

UPSERT routine:loc_8c0e3098 SET bank='bank0e', line=7150,
  note='STORM IDLE-LIGHTNING ambient spawner. 1x alloc (list=3,ctor=0); node+0x20 = caller r5 variant
(SPL passes 0=ground idle from idx0 handler @0x0CE306C2 line 1147; 1=air variant from idx4 handler
@0x0CE30CA4 line 2073); +0x26=0x2A01; cb = loc_8c0e30da. LIVE: 17 births, sels 0x352-0x384 (850-900
idle lightning streaks, NON-bit15).';

UPSERT routine:loc_8c0e3258 SET bank='bank0e', line=7420,
  note='STORM recurring EFFECT-OVERLAY satellite spawner (1x list=3 ctor=0; +0x26=0x2A02; cb =
loc_8c0e328a, dispatch 0x8C15EB94-family). Installed by char-id switch loc_8c04f478 case 0x2A; the
node re-spawns periodically and its anim tracks the owner state. LIVE: 31 births whole-match; sels
0x39f-0x43a (927-1082 = g27 overlay art incl tornado rings 960-975, casting overlays 1029/1033/1079).
Line number approximate (label loc_8C0E3258; alloc a few insns below).';

UPSERT routine:loc_8c0e3584 SET bank='bank0e', line=8020,
  note='STORM LIGHTNING-ATTACK dash-flash spawner. 1x alloc (list=3,ctor=0) @0x8c0e369e; +0x26=0x2A04;
cb = loc_8c0e36de. Called from S_PL2A idx8 Lightning-Attack block (g22 directional poses 490-507)
@ line 3515 with r5=0x16,r6=dir+1 args. LIVE: 23 births, life ~1.3f (per-dash flashes), sels
0x410-0x417 (1040-1047 flash art, NON-bit15).';

UPSERT routine:loc_8c05115a SET bank='bank05', line=2585,
  note='GENERIC "cast 3D effect at char position" helper (shared, not Storm-specific): packs char
pos (+0x34,+0x41C,+0x3C) on stack, r5 = word char+0x130 (effect TYPE field), calls
bank10.loc_8c103ba4. Storm S_PL2A calls it at SEVEN sites across special/super blocks (lines 2758,
3011,3380,3948,4135,4514,4803). EVERY call yields FIVE list-7 3D-machine nodes (see loc_8c103ba4).';

UPSERT routine:loc_8c103ba4 SET bank='bank10', line=8706,
  note='3D effect cluster spawner: bsr FIVE sub-spawners loc_8C103BD0/103C62/103D10/103D78/103DE0,
EACH alloc(r4=0, r5=7 LIST 7, r6=1); each sets node+0x12C=1 explicitly, cb (first = 0x8C103E68, others
0x8c103eb4/0x8c103f46/0x8c103f90/0x8c10400a), runs cell processor 0x8C1294C8, staggers node+0x38 +=10.0f,
node+0xCC=0x405 (3D-draw flag bits), node+0x74=1.0f scale, node+0x130 = TYPE word (from char+0x130);
type!=0 adds 0x8000 to node+0x44 (angle). LIVE: 8 casts x 5 cbs observed (t130=1). THIS WHOLE CLASS
RENDERS NOTHING CLIENT-SIDE (3D machine, bank11 draw).';

-- ---------------------------------------------------------------------------
-- The master catalog finding
-- ---------------------------------------------------------------------------
UPSERT finding:storm_move_spawn_catalog SET date='2026-07-05', confidence='high', status='confirmed',
  contribution_candidate=true,
  note='STORM (PL2A) MOVE -> SPAWN-CLASS CATALOG (static S_PL2A + banks, live-validated _live4 births).
RENDER CLASSES: [S1]=sprite list1 cat1, [S3/S4]=sprite list3/4 cat3/4 (all slot-table; bit15 sel =
scale-walker, else body-walker; GFX from owner-inherited pointers / effect sheet), [3D]=lists 5-13
NaomiLib machine (NOT IMPLEMENTED client-side).
| move | SPL site (S_PL2A) | wrapper | spawns | class | sels (live) |
| Typhoon/Whirlwind | idx8 @0x0CE31DEC L4679 | bank09.loc_8c09bba4 | 2 (art+fx) | S1 | 966-970 body-walker + 0x8000-05 bit15 |
| Lightning Storm | idx8 @0x0CE31444 L3217 (per-frame) | bank09.loc_8c09beec | N/call | S1 | 0x8006-0x801d bit15 |
| Hail Storm columns | idx8 @0x0CE31242 L2908 (once) | bank09.loc_8c09b988 | 8 | S1 | 1083-1095 body-walker |
| Hail Storm chunks | idx8 @0x0CE31BFC L4387 (per-frame) | bank09.loc_8c09c1f4 | 1/call | S1 | 0x8028-0x8041 bit15 |
| Lightning Attack flash | idx8 L3515 (g22 block) | bank0e.loc_8c0e3584 | 1/dash | S3 | 1040-1047, life~1f |
| unperformed special (Double Typhoon?) | idx8 @0x0CE32080 L5067 | bank09.loc_8c09c484 | 1 | S1 | unobserved |
| cape (always) | char-id switch loc_8c04f478 (NOT SPL) | bank0e.loc_8c0e344c | 2 (front/back) | S4 | 731-849 |
| idle lightning | idx0 L1147 / idx4 L2073 | bank0e.loc_8c0e3098 | 1 | S3 | 850-900 |
| state overlay (rings/cast art) | char-id switch + state | bank0e.loc_8c0e3258 | 1 recurring | S3 | 927-1082 |
| cast 3D flash (7 sites: every special+super) | L2758,3011,3380,3948,4135,4514,4803 | loc_8c05115a -> bank10.loc_8c103ba4 | 5/call | 3D list7 | POL models, invisible client-side |
| throw effects | idx9 L5407/5429, idx11 L5628/5640 | bank0e.loc_8c0e2f28 (S3) + bank10.loc_8c103660-chain (3D) | 1+N | S3+3D | cb 0x8c104e14 seen live (12x cat7 t130=1) |
SUPER-NAME CAVEAT (INFERRED, strong): window w/ 8 columns+chunk-rain = Hail Storm; bolt window
(0x8006-0x801d) = Lightning Storm per prior _gate_bit15 labeling; swap would not change any class.
RENDER-SIDE CORRESPONDENCE (coordinator-measured, reconciled): lstorm bit15 band renders w/ pal rows
17/18, hail bit15 band w/ pal19 - consistent with the two distinct bit15 sel bands here (6-29 vs 40-65).
TYPHOON CAT RECONCILIATION (measured, per-frame active-node scan f1100-1520): the tornado art 966-970 is
DISPLAYED by the TWO CAT1 nodes (cb 0x8c09bc5a, w26=0x2a01, layers 7 and 0) - list-1 exactly as the
disasm alloc (bank09:27757 mov 0x01,r5); no cat3 node ever shows 960-975 in the window. An external
"typhoon=cat3 non-bit15" measurement matches only the AIR-cast overlay (f517: cat3 cb=0x8c0e328a sel
0x39f/927+, owner in air-special pose g7 368-379, spawned by the loc_8c0e3258 overlay satellite) - both
exist; the ground projectile pair is cat1.
FLIGHT: no objpool spawn found; flight aura (sprites 238/239, RenderExtra=64 per re-catalog) rides the
RenderExtra body-overlay path, NOT the allocator - OPEN, separate mechanism.
GATE CONSEQUENCE: Storm needs (a) bit15 scale-walker for 3 sel bands (6-29, 40-65, 0-5) [known-open
under-emission], (b) body-walker satellites for 966-970/1083-1095/731-849/850-900/927-1082/1040-1047
[class fixed], (c) 3D-machine for the 5-node list-7 cast flash at EVERY special/super + hitsparks
[class NOT IMPLEMENTED - renders nothing].';

-- ---------------------------------------------------------------------------
-- Hitspark class RESOLVED (closes the re_kb/61 OPEN)
-- ---------------------------------------------------------------------------
UPSERT finding:hitspark_class_resolved SET date='2026-07-05', confidence='high', status='confirmed',
  contribution_candidate=true,
  note='VISIBLE HITSPARKS ARE 3D-MACHINE OBJECTS (lists 7/8), NOT sprite-machine quads. LIVE PROOF
(_live4, 2401 frames, 112 hp-drop frames, birth tracking keyed on node+0x10 callback): EVERY hp-drop
coincides (+/-3f) with a birth cluster of: 1x cat8 cb=0x8c0fe148 (life ~25f, 200/200 births near-hit)
+ 4x cat8 cb=0x8c0ff108/0x8c0ff18e/0x8c0ff252/0x8c0ff2cc (staggered lives 4.0/4.8/5.7/6.5f = expanding
ring layers, 104/104 each near-hit) + victim-anchored cat7 nodes (cb 0x8c10406c 40/40 near-hit,
owner=the HIT character struct). ZERO cat1-4 birth signatures correlate with generic hits (the cat1
bit15 bursts near super hits ARE the supers own projectiles, not spark visuals). STATIC CORROBORATION:
bank10 (hit resolution) allocator census = 72x list5, 51x list7, 11x list8, 4x list6, 3x list9,
ZERO lists 1-4; bank10 loc_8c100968 (list7,ctor1) is one of ~51 sibling per-effect-type wrappers.
DISTINCTION from the victim HIT-FLASH: the white/colored flash ON the hit character body is NOT a
spawned object at all - it is the victim BODY-WALK re-rendered with a flash palette row (measured
pal row 25; field char+0x12E per finding on wire gaps), which the existing body-walker path already
carries. So hit visuals = (a) victim body-flash pal25 [sprite machine, works today], (b) impact
spark/starburst + rings [3D lists 7/8 cluster above, RENDERS NOTHING client-side], (c) the attacking
projectile itself [cat1 etc, per storm catalog].
CONSEQUENCE: no sprite-side fix can ever show the impact sparks; client needs the 3D-list walk (matrix
from node+0x34..+0x50 per node+0xCC flags, POL from Effect Poly 0x0CED0000) + the 0x98-byte list-head
block 0x8C287A54..0x8C287AEC on the wire (per finding:typhoon_hitspark_class_open discriminator plan).';

UPSERT finding:typhoon_hitspark_class_open SET status='resolved',
  note_resolution='2026-07-05: RESOLVED by _live4 birth analysis + bank10 census. Typhoon/Hailstorm/
Lightning-Storm projectiles = sprite-machine cat1 (wire already ships them; sels catalogued in
finding:storm_move_spawn_catalog). Hitsparks = 3D-machine lists 7/8 (finding:hitspark_class_resolved).
Both halves of the original either/or were true for different objects.';

-- ---------------------------------------------------------------------------
-- Source: the live measurement
-- ---------------------------------------------------------------------------
UPSERT source:live4_birth_analysis SET kind='measurement',
  ref='scratchpad _live4.gsta.mcrr (2401 frames, Storm vs Cable w/ supers+hits) + _stormspawn.mjs',
  note='Objpool node-birth tracker: birth = +0x12C 0->nonzero; per birth captured cat(+0x03),
callback(+0x10), owner(+0x18), variant(+0x20/+0x21), type word(+0x26), layer(+0x24), sel(+0x144)
over lifetime, node+0x130, owner sid(+0x144) and P1/P2 health. 2135 births grouped by (cat,cb,+0x26)
signature; every Storm signature matched 1:1 to a statically-read spawn wrapper via the callback
address found in that wrapper pool (loc_8c09bc5a@27869, loc_8c09bf9a@28359, loc_8c09c236@28753,
loc_8c09b9dc@27492, loc_8c0e34a2@7895, etc).';

UPSERT source:s_pl2a_static SET kind='disasm',
  ref='C:/Users/trist/projects/_marv_re/char_prg/code/S_PL2A.asm + build/bank04.asm bank05.asm bank09.asm bank0e.asm bank10.asm',
  note='Handler table PTR_ce327a4 (S_PL2A:6169, 28 entries -> *(char+0x428), installed by BEG_ce30000);
idx8=LAB_ce310cc master special/super handler. Spawn/anim call sites resolved incl NUMERIC-displacement
PC-relative pool loads (mov.l @(0xNN,PC),rn) via per-line address computation - label-only matching
misses most bank09/0e/10 sites.';

-- ---------------------------------------------------------------------------
-- Edges
-- ---------------------------------------------------------------------------
RELATE finding:storm_move_spawn_catalog->cites->source:live4_birth_analysis SET kind='cites';
RELATE finding:storm_move_spawn_catalog->cites->source:s_pl2a_static SET kind='cites';
RELATE finding:storm_move_spawn_catalog->about->character:pl2a SET kind='about';
RELATE finding:storm_move_spawn_catalog->about->finding:objpool_list_system_complete SET kind='about';
RELATE finding:hitspark_class_resolved->cites->source:live4_birth_analysis SET kind='cites';
RELATE finding:hitspark_class_resolved->about->finding:objpool_list_system_complete SET kind='about';
RELATE finding:hitspark_class_resolved->about->finding:typhoon_hitspark_class_open SET kind='about';
RELATE finding:spl_spawn_mechanism->cites->source:s_pl2a_static SET kind='cites';
RELATE finding:spl_spawn_mechanism->about->finding:objpool_list_system_complete SET kind='about';
RELATE finding:storm_move_spawn_catalog->cites->routine:loc_8c09bba4 SET kind='cites';
RELATE finding:storm_move_spawn_catalog->cites->routine:loc_8c09beec SET kind='cites';
RELATE finding:storm_move_spawn_catalog->cites->routine:loc_8c09c1f4 SET kind='cites';
RELATE finding:storm_move_spawn_catalog->cites->routine:loc_8c09b988 SET kind='cites';
RELATE finding:storm_move_spawn_catalog->cites->routine:loc_8c0e344c SET kind='cites';
RELATE finding:storm_move_spawn_catalog->cites->routine:loc_8c05115a SET kind='cites';
RELATE finding:storm_move_spawn_catalog->cites->routine:loc_8c103ba4 SET kind='cites';
RELATE finding:storm_move_spawn_catalog->cites->routine:loc_8c04f478 SET kind='cites';
