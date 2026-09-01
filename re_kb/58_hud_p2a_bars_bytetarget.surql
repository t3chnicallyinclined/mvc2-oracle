USE NS re DB kb;
UPSERT source:hudq_bar_meter_bytetarget SET kind='oracle',
  ref='_hud_cap/hudq_inventory.txt (live HUDQ capture vframe=40080, 143 quads) + hudq_tail.bin',
  note='THE EXACT BYTE TARGET for the P2a life-bar + super-meter FILL quads (tcw=08080000 white texel). '
    || 'Each life bar / meter fill emits a MATCHED PAIR at cy 52/78/98 (P1) + mirror (P2): (a) the HP/meter '
    || 'GOURAUD fill pcw=808c001f tsp=20880440, col=[inner,outer,inner,outer] where inner=team stop / '
    || 'outer=warm-yellow, u=v=0; (b) the RED chip/drain pcw=808c002d tsp=20080440, col=[fffe0000]x4 (flat). '
    || 'CONFIRMED gouraud stops (ARGB8888): C1 inner fefe3ffe (A254 R254 G63 B254 magenta), outer fefefe00 '
    || '(A254 R254 G254 B0 yellow); super/cyan inner fe00bffe (A254 R0 G191 B254); chip fffe0000 (A255 R254 '
    || 'G0 B0). Note the engine alpha is 0xfe not 0xff on the gouraud fill, 0xff on chip. Corners are FLAT '
    || 'rects (skew 0) e.g. P1 row0 x=[270,47,270,47] y=[58,58,46,46]; P2 mirrors x=[370,593,...]. The '
    || 'segmented multi-level meter ART is a SEPARATE family (fmt=5 PAL4 pcw=a2000009 tsp=949004d2 tcw=2a489xxx '
    || 'texAddr 0x44Bxxx) = ~10 tiny notch/segment quads per meter -- NOT a white-texel bar, and the VRAM bank '
    || '0x440000-0x460000 is ZEROED in the shipped prefix (finding:hud_meter_segments_vram_gap).';

UPSERT finding:hud_p2a_bars_already_byteexact SET
  statement='P2a REDIRECT (measurement-grounded, cardinal rules 2+3): the LIFE-BAR fill does NOT need a '
    || 'transpile -- gsta_stage.cpp emitStrip6 ALREADY emits the engine-exact quad. Diffed vs the live HUDQ '
    || 'oracle (_hud_cap/hudq_inventory.txt quads [2]/[8] life, [14..34] reserve/meter): control words '
    || 'MATCH EXACTLY (pcw 0x808c001f, tsp 0x20880440, tcw 0x08080000, Type-6 4-vert gouraud strip, u=v=0). '
    || 'The current emit was a direct MEASURED PORT of _live_hud.mirror.zcst (the engine mirror TA), i.e. it '
    || 'is the engine geometry, mislabeled "hand-synth". RESIDUAL DELTAS, both value-only (state math), NOT '
    || 'structural, NOT requiring a transpile: (1) COLOR ALPHA: emit forces mkARGB alpha=0xFF; engine uses '
    || '0xFE on the gouraud fill (chip is 0xFF, matches). (2) GOURAUD STOPS: engine outer stop is always '
    || 'warm-yellow fefefe00 gated on gradientOn; inner = the loc_8c15FFB0 team stop -- our TEAM_HP magenta '
    || '(255,64,255) vs engine (254,63,254) differ by the 0xfe/0xff LSB only. (3) POSITION: emit uses '
    || 'measured STG0B rects; HUDQ shows the SAME rects to <1px. '
    || 'WHY A loc_8c0f06ec TRANSPILE WOULD NOT PASS THE GATE: re-reading loc_8c0f06ec (bank0f 0x8C0F06EC) '
    || 'instruction-by-instruction, it writes NO x/y and NO u/v -- it fills a MODEL/INSTANCE record (fields '
    || '+0x10 ctrl-ptr, +0x18 data-ptr from char*0x5a4+table, +0x20/+0x21 side/subpart bytes, +0x74 12B block) '
    || 'and hands it to bank12 loc_8c1294c8. The SCREEN corners the HUDQ oracle measures are produced by a '
    || 'DOWNSTREAM transform/projection stage (same ftrv-class stage the body path needed gen_transform_obj.c '
    || 'for), reading a resident object-local vertex template (bank16 loc_8c1601C0 family). So a faithful '
    || 'byte-exact bar = MEASURED template positions (already have) + team color from loc_8c15FFB0 + HP-fraction '
    || 'width math -- which is EXACTLY what emitStrip6/drawSide already do. The Phase-1 "float-light, no ftrv" '
    || 'note applied to the record BUILDER, NOT to the geometry the gate measures -- CORRECTED here. '
    || 'RECOMMENDED P2a: (i) fix the 3 value deltas in emitStrip6/drawSide (alpha 0xfe, exact loc_8c15FFB0 '
    || 'stops incl the always-yellow outer, chip pcw 0x808c002d as its own quad not mkARGB) to byte-match the '
    || 'HUDQ oracle; (ii) meter fill bar = same white-texel model, ALREADY in drawMeter, apply same fixes; '
    || '(iii) the fmt=5 PAL4 segmented meter ART (tcw 2a489xxx) is DEFERRED to P2b -- it needs the server VRAM '
    || 'prefix 0x440000-0x460000 shipped (currently zeroed) before any client can draw it, so it is a SERVER '
    || 'gap not a transpile. No new gen_hud_*.c file is warranted for bars; the "transpile" for P2a is a '
    || 'value-accuracy pass on the existing measured emit, gated numerically against hudq_inventory.txt.',
  status='confirmed', confidence='high', date='2026-07-01';
RELATE finding:hud_p2a_bars_already_byteexact->cites->source:hudq_bar_meter_bytetarget;
RELATE finding:hud_p2a_bars_already_byteexact->cites->source:hud_team_colour_table;
RELATE finding:hud_p2a_bars_already_byteexact->about->routine:loc_8c0f06ec;
RELATE finding:hud_p2a_bars_already_byteexact->about->finding:hud_meter_segments_vram_gap;
