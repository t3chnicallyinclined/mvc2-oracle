-- ============================================================================
-- 57: HUD TRANSPILE SCOPE MAP (Phase 1). The full in-match HUD render call tree
-- mapped from marvelous2 bank0f/03/04/12/15/16, for the DECISION to transpile the
-- HUD render (like render_frame does bodies) instead of shipping HUDQ TA quads.
-- READ-ONLY mapping; no transpiler written yet. feat/render-replica-live.
-- Pinned 2026-07-01.
-- ============================================================================
USE NS re DB kb;

UPSERT routine:loc_8c03012c SET label='loc_8c03012c', pc='0x8C03012C', bank='bank03',
  role='in-match HUD/overlay frame dispatcher (the HUD root caller)',
  note='Per-frame in-match overlay driver (function-pointer table entry bank03 loc_8c03de4c). '
     || 'Zeroes 4 anim counters 0x8C289BD0/BD2/BD4/BD6, then jsr in sequence: loc_8c0f0408, '
     || 'loc_8c0f048e (THE life/portrait/name/tag HUD), loc_8c0f1410, loc_8c0f1698, loc_8c0f236c. '
     || 'loc_8c03015c is the companion that ADVANCES those 4 counters (meter breathing wave phase).';

UPSERT routine:loc_8c0f048e SET label='loc_8c0f048e', pc='0x8C0F048E', bank='bank0f',
  role='in-match HUD root: 6 char-panels + 2-side life bars',
  note='Loops i=0..5 calling loc_8c0f04c4(i) [per-slot char panel: portrait+name+winstars+meter '
     || 'sub-calls], then loops side=0..1 calling loc_8c0f06ec(side,0/1) [the two life bars]. '
     || 'Cited by bank03 dispatch table loc_8c0301a4.';

UPSERT routine:loc_8c0f04c4 SET label='loc_8c0f04c4', pc='0x8C0F04C4', bank='bank0f',
  role='per-slot HUD char panel builder (portrait/name/winstars container)',
  note='r4=slot(0..5). Allocs a poly record via bank04 loc_8c044f12(list=0x0B), reads the slot '
     || 'char struct (base 0x8C268340 + slot*0x5A4; also a portrait table via GGP 0x8C26823c), '
     || 'zeroes a 6-word winstar accumulator, then bsr loc_8c0f05f4 (portrait) + loc_8c0f0824 + '
     || 'loc_8c0f08b0 + bra loc_8c0f0a1a. Char panel emits into the cell processor bank12 '
     || 'loc_8c1294c8 (record+0x34).';

UPSERT routine:loc_8c0f06ec SET label='loc_8c0f06ec', pc='0x8C0F06EC', bank='bank0f',
  role='LIFE BAR poly builder (per side; the angled team-tinted health bar + chip)',
  note='r4=side, r5=0/1 (bar sub-part). Allocs poly via loc_8c044f12(0x0B). Indexes the team '
     || 'colour table bank15 loc_8c15FFB0 by side/active-point ((side?0x48:0x3F)>>? -> slot*4 words '
     || 'of 2-stop gouraud). Reads char base 0x8C268340. tst r14 (side) selects P1(0x3F)/P2(0x48) '
     || 'colour row. Emits via bank12 loc_8c1294c8. TCW/vertex-template from resident data blocks '
     || '(loc_8C0F06D8 char base, loc_8C0F06E0 team-colour ptr).';

UPSERT routine:loc_8c0f05f4 SET label='loc_8c0f05f4', pc='0x8C0F05F4', bank='bank0f',
  role='HUD PORTRAIT poly builder (in-match mugshot)',
  note='Allocs poly via loc_8c044f12(0x0B). Reads char id from panel (+0x2) and a portrait-object '
     || 'table 0x8C28C720; sets record scale (+0x50) and colour, emits via bank12 loc_8c1294c8 '
     || '(record+0x34) + loc_8c1294bc. The portrait TEXTURE is a RESIDENT VRAM sprite (decoded at '
     || 'match load; TCW ~0x0809DE00/E000 per live HUDQ capture source:hudq_live_capture_2026_06_14) '
     || '-- the routine only writes screen corners/UV/TCW referencing already-resident VRAM. NO '
     || 'FAC.BIN decode on the live path (FAC decode is offline-extraction only).';

UPSERT routine:loc_8c0f0824 SET label='loc_8c0f0824', pc='0x8C0F0824', bank='bank0f',
  role='HUD name-plate / panel-decoration poly builder',
  note='Allocs poly loc_8c044f12(0x0B); reads char base 0x8C268340; two float consts '
     || '0x46AAAA00/0x472AAA00 (position scale) + list-type 0x00010C11; emits via bank12 '
     || 'loc_8c1294c8 (record r13+0x34) and loc_8c1294bc. FONT glyph family (TCW 0x0809BE00 '
     || 'RGB565-twiddled, resident VRAM 0x4DF000; set-site source:hud_font_tcw_setter).';

UPSERT routine:loc_8c0f08b0 SET label='loc_8c0f08b0', pc='0x8C0F08B0', bank='bank0f',
  role='HUD panel sub-element poly builder (win-star / tag-bar decoration)',
  note='Allocs poly loc_8c044f12(0x0B); reads GGP-derived pointer (+0x10 deref) and a scale/anim '
     || 'value; sets record scale fields (+0x50/+0x54/+0x58 = 1.0) and emits via bank12 '
     || 'loc_8c1294c8. Part of the loc_8c0f04c4 panel chain.';

UPSERT routine:loc_8c0f0a1a SET label='loc_8c0f0a1a', pc='0x8C0F0A1A', bank='bank0f',
  role='HUD panel final poly builder (tail of the char-panel chain)',
  note='bra-tail of loc_8c0f04c4. Allocs poly loc_8c044f12(0x0B); side-selects colour '
     || '((side?0x6B:0x6A)*4 words) from a resident block; zeroes two float fields (+0x34/+0x38); '
     || 'emits via bank12 loc_8c1294c8.';

UPSERT routine:loc_8c0f0fdc SET label='loc_8c0f0fdc', pc='0x8C0F0FDC', bank='bank0f',
  role='SUPER/HYPER METER poly builder (multi-level segmented gauge)',
  note='r4=meter panel base. Reads meter_level (0x8C28964A P1 / +1 P2, via panel+0x20 index) and '
     || 'a per-panel level-state (+0x21/+0x22). For the active level: divides meter_fill (u16 '
     || '0x8C289646 P1 / 0x8C289648 P2) by METER_MAX = loc_8C0F113C = 0x43100000 = 144.0f, storing '
     || 'the fill fraction to record+0x50. Uses the breathing WAVE fn bank11 loc_8c11E860 (sin/cos '
     || 'poly approx) on counter 0x8C289BD2/BD4 to animate segment brightness (consts loc_8C0F1134 '
     || '=8.0f, loc_8c0f1148=0.5f). Indexes meter colour/uv table bank16 loc_8c160220 by level. '
     || 'Emits via bank12 loc_8c1294bc. Level 5 (max) special-cased (loc_8c0f1094).';

UPSERT routine:loc_8c044f12 SET label='loc_8c044f12', pc='0x8C044F12', bank='bank04',
  role='TA poly-record ALLOCATOR (called by every HUD sub-builder, r5=list 0x0B r6=1)',
  note='Reads global poly budget 0x8C287AE8 (rts 0 if <=0), pops a free record from a pool head '
     || '(loc_8c045010 deref, next=@+0x8), decrements budget + per-list counters, sets record+0x3 '
     || '=listid, and jsr\'s a per-list-type init via table loc_8c045020[listtype]. RETURNS the '
     || 'record ptr in r0. THIS IS THE ENGINE-OWNED TA SCRATCH ALLOCATOR: a transpile must either '
     || 'replicate the free-list pop (needs the pool state 0x8C26A90c-area + 0x8C287AE8 in-wire) OR '
     || '(preferred) allocate its OWN output record array client-side, since the transpile emits '
     || 'to OUR TA list, not the engine\'s.';

UPSERT routine:loc_8c1294c8 SET label='loc_8c1294c8', pc='0x8C1294C8', bank='bank12',
  role='cell processor = record->TA-list Duff-device struct COPIER (HUD poly emitter)',
  note='Jump-table (loc_8c12951c, 18 entries) Duff-device that block-copies the built poly record '
     || '(r2) into the live TA poly list (r1) word-by-word. loc_8c1294bc is the sibling variant. '
     || 'This is the CANONICAL crash site (corrupt count -> jmp into non-code) and is the point '
     || 'where the HUD record becomes an actual PVR TA vertex/poly. A transpile REPLACES this with '
     || 'a direct emit into OUR client TA builder (buildHudTA), so the engine TA list + its pool '
     || 'state need NOT be reproduced -- only the record CONTENTS (corners/UV/col/pcw/isp/tsp/tcw).';

UPSERT source:hud_team_colour_table SET kind='code',
  ref='marvelous2 bank15 loc_8c15FFB0 (+ loc_8c15FF98 zero / loc_8c15FFA4 white)',
  note='THE PER-TEAM LIFE-BAR/METER GOURAUD COLOUR TABLE (ARGB8888, 12 words = 6 stops x2, '
     || 'inner->outer). CONFIRMED bytes: C1 magenta 0xFFFF40FF -> yellow 0xFFFFFF00; C2 green '
     || '0xFF00FF00 -> yellow 0xFFFFFF00; C3 cyan 0xFF00C0FF -> yellow 0xFFFFFF00. loc_8c15FF98 '
     || '= all-zero (alpha-0 stop), loc_8c15FFA4 = 0x3F800000 x3 (white 1.0 intensity). The life '
     || 'bar is a white/solid texel poly MODULATED by these per-team vertex colours (matches the '
     || 'live HUDQ captured cols, finding:hud_bar_tint_confirmed).';

UPSERT source:hud_meter_colour_uv_table SET kind='code',
  ref='marvelous2 bank16 loc_8c160220 (+ bar geom templates loc_8c1601C0/loc_8c1602C0)',
  note='The super-meter per-LEVEL colour/uv table (floats), indexed by meter_level in '
     || 'loc_8c0f0fdc. bank16 loc_8c1601C0.. are RESIDENT xyz/colour/uv vertex-template #data '
     || 'blocks (NOT code) that the HUD builders read to lay out bar/portrait/meter quads. So the '
     || 'HUD geometry templates are ROM-constant + in-code-space (no wire needed).';

UPSERT finding:hud_transpile_scope_map SET
  statement='PHASE 1 HUD TRANSPILE MAP COMPLETE (marvelous2-grounded). The in-match HUD render is a '
     || 'compact, LARGELY FLOAT-LIGHT bank0f subtree rooted at loc_8c0f048e (called every frame from '
     || 'the bank03 overlay dispatcher loc_8c03012c). CALL TREE: loc_8c0f048e -> {6x loc_8c0f04c4 '
     || '(char panel) -> loc_8c0f05f4 (PORTRAIT) + loc_8c0f0824 (name plate) + loc_8c0f08b0 (winstar/'
     || 'tag deco) + loc_8c0f0a1a (panel tail)} + {2x loc_8c0f06ec (LIFE BAR)}; the SUPER METER is '
     || 'loc_8c0f0fdc (a sibling overlay routine in the same bank03 dispatch chain, meter_fill/144 + '
     || 'meter_level, breathing-wave bank11 loc_8c11E860). Every builder: (1) allocs a poly record via '
     || 'bank04 loc_8c044f12(list 0x0B), (2) reads engine STATE + resident ROM colour/geom tables '
     || '(bank15 loc_8c15FFB0 team gouraud, bank16 loc_8c160xxx vertex templates), (3) copies the '
     || 'record into the TA list via the bank12 cell processor loc_8c1294c8/bc. '
     || 'STATE READ = ALL ALREADY IN THE SHIPPED _gstaRam READ-SET (finding:replica_live_hud + '
     || 'maplecast_replica_live.cpp buildTables): per-char health+0x420/red+0x424/active+0x000/'
     || 'char_id+0x001 (char_str region), globals meter_fill 0x289646/8 + meter_level 0x28964A/B + '
     || 'timer/round/in_match (gstate region), num_wins char+0x540 (char_str). '
     || 'TWO fields NOT yet in-wire, both TRIVIAL: (a) meter breathing-wave counters 0x8C289BD0..BD6 '
     || '(4 u16, cosmetic segment shimmer -- add a 8B window OR reproduce the counter client-side '
     || 'since loc_8c03015c just += constants/frame); (b) the TA pool/budget state (0x8C287AE8, '
     || '0x8C26A90c-area) which the transpile SKIPS entirely by emitting to OUR client TA builder '
     || 'instead of the engine free-list. '
     || 'PORTRAITS: CONFIRMED the in-match portrait (loc_8c0f05f4) emits a quad referencing a '
     || 'RESIDENT VRAM portrait sprite (TCW ~0x0809DE00/E000, decoded at match-load, already in the '
     || 'shipped static 8MB VRAM prefix) -- NO FAC.BIN decode on the live path. '
     || 'TRANSPILE SCOPE: ~8 leaf builders + 1 allocator + the meter, all bank0f, mostly integer/'
     || 'byte record-fill with a handful of float ops (fill fraction /144, scale set, meter wave). '
     || 'NO ftrv/matrix (unlike the body transform gen_transform_obj.c). Est. a few hundred SH4 '
     || 'instructions total across the subtree. PLAN: gen_hud_lifebar.c (loc_8c0f06ec + team table), '
     || 'gen_hud_meter.c (loc_8c0f0fdc + wave fn loc_8c11E860), gen_hud_panel.c (loc_8c0f04c4 + '
     || 'loc_8c0f05f4/0824/08b0/0a1a), driver gen_hud_frame.c (loc_8c0f048e loop). Each emits '
     || 'HudQuad records into an OUR-side array; the bank12 cell-copy + bank04 alloc are REPLACED by '
     || 'a client record allocator, not transpiled. '
     || 'RISK: (1) the record->TA field offsets (+0x10 isp/tsp base, +0x18 tcw, +0x1C/1E uv, +0x34 '
     || 'corners) must be mapped from the cell-processor copy layout to the 96B HudQuad -- same '
     || 'mapping the HUDQ collectHudQuads already proved, so it is cross-checkable against a live '
     || 'HUDQ capture (the transpile output must byte-match the HUDQ tail for the same frame -- that '
     || 'IS the acceptance gate, cardinal rule 3). (2) win-star/tag-bar/name-plate exact glyph runs '
     || 'may be multi-quad strips (finding:replica_live_hud_real_ta_open_multistrip) -- tier-2. '
     || 'RECOMMENDATION: phase it -- P2a life bars + meter (highest value, single quads, pure '
     || 'state) first, validate byte-exact vs a live HUDQ capture; P2b portraits (resident VRAM '
     || 'quad); P2c name plates/winstars (multi-glyph). The HUDQ capture stays as the GROUND-TRUTH '
     || 'ORACLE the transpile is diffed against (not shipped), exactly as CHARQ grounds render_frame.',
  status='confirmed', confidence='high', date='2026-07-01';

RELATE finding:hud_transpile_scope_map->about->routine:loc_8c0f048e;
RELATE finding:hud_transpile_scope_map->about->routine:loc_8c0f04c4;
RELATE finding:hud_transpile_scope_map->about->routine:loc_8c0f06ec;
RELATE finding:hud_transpile_scope_map->about->routine:loc_8c0f05f4;
RELATE finding:hud_transpile_scope_map->about->routine:loc_8c0f0fdc;
RELATE finding:hud_transpile_scope_map->about->routine:loc_8c044f12;
RELATE finding:hud_transpile_scope_map->about->routine:loc_8c1294c8;
RELATE finding:hud_transpile_scope_map->cites->source:hud_team_colour_table;
RELATE finding:hud_transpile_scope_map->cites->source:hud_meter_colour_uv_table;
RELATE finding:hud_transpile_scope_map->cites->source:hud_field_addresses;
RELATE finding:hud_transpile_scope_map->cites->source:hud_render_routine_rom;
RELATE finding:hud_transpile_scope_map->cites->source:hudq_live_capture_2026_06_14;
