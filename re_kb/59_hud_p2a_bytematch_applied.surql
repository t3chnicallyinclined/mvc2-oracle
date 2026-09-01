USE NS re DB kb;
UPSERT finding:hud_p2a_portrait_dropfilter_fix SET
  statement='NATIVE-PATH "missing portrait" ROOT CAUSE = a WRONG drop-filter band in gsta_stage.cpp, '
    || 'NOT a monogram/FAC-decode/VRAM gap. The stage-mesh loop DROPS baked dynamic HUD fills so the '
    || 'procedural synth can redraw them from live state; isLifeFill=(band==0x080000) is correct, but '
    || 'isMeterFill was band 0x9de00..0x9e900 -- which is the baked PORTRAIT band (0x9de00..0x9e600 = 6 '
    || 'char portraits, tcw 0809deXX) + level/exp icons (0x9e700..0x9e900), NOT the meter fill. The '
    || 'REAL meter fill is at 0x080000 (white texel tcw 0x08080000, same as the life fill) -- CONFIRMED '
    || 'by the STG0B_ta.json band histogram (band 0x080000 x12 = 6 life + 6 meter; bands 0x9deXX x1 each '
    || '= portraits). So the filter was silently dropping all baked portraits -> the native GSTA HUD '
    || 'showed no portrait (fallback). FIX (gsta_stage.cpp): isMeterFill now == (band==0x080000), same '
    || 'as isLifeFill; the 0x9deXX portrait band is KEPT. The baked portrait mesh is BYTE-EXACT vs the '
    || 'HUDQ oracle (pcw 0x808c002c tsp 0x2009a452 tcw 0x0809deXX, resident VRAM 0x4efXXX ~97% nonzero '
    || 'in the shipped prefix) -- so keeping it IS the correct byte-match; NO new portrait quad emit and '
    || 'NO char_id->cell indexing is needed (the residency at the per-slot VRAM addr IS the char binding, '
    || 'loaded at match-load). CONFIRMED _hud_cap/vram_prefix.bin + atlas/stages/STG0B_ta.json.',
  status='confirmed', confidence='high', date='2026-07-02';

UPSERT finding:hud_p2a_bytematch_applied SET
  statement='P2a VALUE-ACCURACY PASS APPLIED + BYTE-GATED (client build flycast.exe, MAPLECAST_CLIENT_ONLY, '
    || 'core/network/gsta_stage.cpp). THREE color deltas fixed so the bars/meter-fill byte-match the live '
    || 'HUDQ oracle (_hud_cap/hudq_inventory.txt): (1) ALPHA -- the gouraud fill now uses the engine ARGB '
    || 'words directly (A=0xFE), not mkARGB (which forced 0xFF). (2) EXACT loc_8c15FFB0 stops via the '
    || 'engine intensity map channel c->trunc(c*254/255): C1 inner 0xfefe3ffe / C2 0xfe00fe00 / C3 '
    || '0xfe00bffe, outer warm-yellow 0xfefefe00 (new consts TEAM_HP_ARGB[3]/GRAD_WARM_ARGB, replacing '
    || 'the RGB TEAM_HP/GRAD_WARM that lost the LSB). (3) RED CHIP now its OWN Type-6 strip via new '
    || 'emitChip6 (pcw 0x808c002d, tsp 0x20080440 -- NOTE distinct from the fill 0x20880440, bit '
    || '0x00800000 clear -- tcw 0x08080000, flat col 0xfffe0000 A=0xFF), not emitQuad+mkARGB. The meter '
    || 'FILL now routes through emitStrip6 (same white-texel gouraud strip as the life bar, FLAT no skew) '
    || 'with the exact stops. ALSO fixed the portrait drop-filter (finding:hud_p2a_portrait_dropfilter_fix) '
    || 'so the byte-exact baked portraits render. BYTE-GATE (numeric per-quad, reproducing emitStrip6/'
    || 'emitChip6 for the oracle frame state vs hudq_inventory.txt): P1 life fill [q2] PASS, P1 chip [q4] '
    || 'PASS, P2 life fill [q8] PASS, meter fill [q14 cyan] PASS, portrait [q3 baked] PASS -- all on '
    || 'pcw/tsp/tcw/corners(<=1.5px)/col-set. Client flycast.exe clean-rebuilt (ninja: gsta_stage.cpp.obj '
    || '+ link, no errors). Headless PID 62532 (build-headless-win/, does NOT compile gsta_stage.cpp) '
    || 'untouched. NO gen_hud_*.c added (the big HUD-routine transpile stays OFF -- loc_8c0f06ec is '
    || 'coordinate-less, per finding:hud_p2a_bars_already_byteexact). OUT-OF-SCOPE (other agent): HUD '
    || 'name letters + fmt=5 PAL4 meter-segment art (VRAM dirty-page wire fix); the synthetic meter '
    || 'highlight-sheen emitQuad is a pre-existing embellishment left under its gate (not an oracle quad).',
  status='confirmed', confidence='high', date='2026-07-02';

RELATE finding:hud_p2a_bytematch_applied->cites->source:hudq_bar_meter_bytetarget;
RELATE finding:hud_p2a_bytematch_applied->cites->source:hud_team_colour_table;
RELATE finding:hud_p2a_bytematch_applied->about->finding:hud_p2a_bars_already_byteexact;
RELATE finding:hud_p2a_bytematch_applied->about->finding:hud_p2a_portrait_dropfilter_fix;
RELATE finding:hud_p2a_portrait_dropfilter_fix->cites->source:hudq_bar_meter_bytetarget;
