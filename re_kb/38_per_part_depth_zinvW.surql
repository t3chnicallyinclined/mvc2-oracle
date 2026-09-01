-- ============================================================================
-- finding:per_part_depth_zinvW
-- Per-part draw ordering WITHIN one sprite_id is by PVR depth (Z = 1/W), NOT
-- by submission order. W increases +0.001 per part submitted; with the sprite
-- list's Greater/GEqual depth test, FIRST-submitted part = largest Z = FRONT,
-- LAST-submitted part = smallest Z = BEHIND. (Inverse of painter "last-on-top".)
-- This is the Storm-cape-in-front root cause.
-- ============================================================================

-- ---- sources ----------------------------------------------------------------
USE NS re DB kb;

UPSERT source:bank03_walker_w_increment SET
  kind = 'disasm', bank = 'bank03',
  pc = '0x8C034864',
  label = 'loc_8c034864',
  note = 'Per-part: r15+0x38 (quad W) += 0.001 (lit 0x3a83126f @loc_8c034940) BEFORE submit jsr; then counter r15+0x2C += 1. This is the ASMTRACE hook PC.',
  file = 'C:/Users/trist/projects/_marv_re/build/bank03.asm:10739-10760';

UPSERT source:bank03_walker_w_init SET
  kind = 'disasm', bank = 'bank03',
  pc = '0x8C034588',
  label = 'loc_8c034588',
  note = 'Per-sprite init (before part loop): r15+0x38 (W) = node[+0xE8] (per-OBJECT W from transform_object loc_8c122560); fr15=1.0. loc_8c034610=#data 0x00e8.',
  file = 'C:/Users/trist/projects/_marv_re/build/bank03.asm:10316-10346';

UPSERT source:bank12_submit_zinvw SET
  kind = 'disasm', bank = 'bank12',
  pc = '0x8C1244B0',
  label = 'loc_8C1244B0',
  note = 'Submit/finalize. r4=r13=walker r15+0x2C frame-local quad. fr13 = 1.0 / quad[+0x0C](=walker r15+0x38=W). Writes SAME fr13 to all 3 vertex Z slots: @(0x0C,r14),@(0x18,r14),@(0x24,r14). Flags read from quad[+0x34]. @r13 (counter) vs [0x8C2DAD40] = TA list capacity gate.',
  file = 'C:/Users/trist/projects/_marv_re/build/bank12.asm:9794-10400';

UPSERT source:flycast_zfunction SET
  kind = 'code', repo = 'maplecast-flycast',
  note = 'isp.DepthMode: 4=Greater, 6=GreaterOrEqual. PVR sprite list depth test passes LARGER 1/W => larger Z draws in FRONT.',
  file = 'core/rend/dx9/d3d_renderer.cpp:61-71; core/rend/gles/gldraw.cpp Zfunction[]';

-- ---- finding ----------------------------------------------------------------
UPSERT finding:per_part_depth_zinvW SET
  title = 'Per-part intra-sprite ordering is PVR depth Z=1/W, first-submitted=front',
  status = 'CONFIRMED',
  confidence = 0.95,
  summary = 'Within one sprite_id, parts do NOT layer by submission order. The body walker loc_8c0344d4 keeps a running W in frame-local quad slot r15+0x38, initialized per-sprite to node[+0xE8] (the per-object W) and incremented by exactly +0.001 (float 0x3a83126f) per part at loc_8c034864 BEFORE each submit jsr to loc_8c1244b0. The submit computes Z = 1.0/W (fdiv fr3,fr13 with fr3=quad[+0x0C], fr13 preset 1.0) and writes that SAME Z to all three vertices of the part (@0x0C/0x18/0x24 of the output vertex). Because W strictly increases in submission order, Z=1/W strictly DECREASES in submission order. The MVC2 sprite list uses a Greater/GreaterOrEqual depth test, so the part with the LARGEST Z wins the depth test = drawn in FRONT. Therefore the FIRST part submitted is FRONTMOST and the LAST part submitted is REARMOST -- the exact inverse of a naive painter (last-on-top) renderer.',
  implication = 'Storm jump (sid 0x77=119) renders cape-in-front in both the editor and the sprite-client because both paint parts in submission order (last drawn on top). The engine submits the cape LATE, which under Z=1/W puts it BEHIND. Fix: render parts of one sprite in REVERSE submission order, OR assign each part an explicit depth and sort. Per-part depth_index = part submission index i (0-based); equivalent Z = 1/(node_W + 0.001*(i+1)). For pure intra-sprite ordering only the rank matters: draw order = reverse of submission (i descending), i.e. submission index 0 painted LAST/on-top.',
  compute_rule = 'For part i (0-based submission index within the sprite, == the row order in ASMTRACE/our exporter): W_i = node[+0xE8] + 0.001*(i+1); Z_i = 1/W_i. Smaller i => larger Z => front. Renderer with z-buffer + Greater test: feed Z_i. Painter renderer with no z-buffer: sort parts by i DESCENDING (draw highest i first, i=0 last) so i=0 ends on top.',
  caveats = 'node[+0xE8] (per-object W) is constant across all parts of one sprite, so it cancels for INTRA-sprite ordering -- only the +0.001*(i+1) bias distinguishes parts; submission index i alone is sufficient to sort within a sprite. The cross-OBJECT z (different chars/projectiles) still uses node[+0xE8] which differs per object. GreaterOrEqual vs Greater is not load-bearing here since every part has a strictly distinct W.',
  open_items = 'Live ASMTRACE on prod (149.28.44.118 /dev/shm/mc_assembly.log) currently lacks a Storm jump (sid 119) sample to visually re-confirm cape submission rank; add a W/Z column to the ASMTRACE line (read quad[+0x0C] / or i) to log depth directly. The +0.001 increment magnitude vs node_W scale should be checked does-not-overflow the 1/W precision for very long part lists (>~hundreds), but MVC2 sprites are <=~64 parts so safe.';

-- ---- edges ------------------------------------------------------------------
RELATE finding:per_part_depth_zinvW->cites->source:bank03_walker_w_increment;
RELATE finding:per_part_depth_zinvW->cites->source:bank03_walker_w_init;
RELATE finding:per_part_depth_zinvW->cites->source:bank12_submit_zinvw;
RELATE finding:per_part_depth_zinvW->cites->source:flycast_zfunction;

-- relate to the master emitter model: this RESOLVES the intra-sprite ordering
-- question left implicit by finding:emitter_render_model (which captured pen/
-- geometry but treated parts as pure submission-order paint).
RELATE finding:per_part_depth_zinvW->about->finding:emitter_render_model;
