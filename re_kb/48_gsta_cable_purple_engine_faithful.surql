-- ============================================================================
-- 48: native GSTA client — "PURPLE CABLE" is engine-faithful, NOT a bug.
-- The recurring "Cable's palette is wrong (purple, not blue/grey)" report,
-- root-caused end-to-end against the engine arbiter (real TA + PALETTE_RAM +
-- engine pixel render). CONFIRMED-BY-MEASUREMENT 2026-06-19, feat/render-replica-live.
-- ============================================================================
USE NS re DB kb;

UPSERT source:gsta_char_identify SET kind='measurement',
  ref='GSTA prefix ram16 region (0x8C000000) char structs; build/flycast.exe GSTA mode',
  note='slot-0 in-match: P1C1=Storm char_id 0x2A (right, facing0, palette0, body bank16); P2C1=Cable char_id 0x17 (left, facing1, palette index 1 @ +0x52D, body bank24). char_id @ +0x001, palette @ +0x52D, facing @ +0x110, screen @ +0xE0/E4. The purple left-side char w/ yellow boots is P2C1 Cable. IDENTIFY by char_id, never by the on-screen color.';

UPSERT source:gsta_engine_ta_banks SET kind='measurement',
  ref='mirror client MAPLECAST_DUMP_TA (port 7200), 806 engine TA frames; tools/gsta_ta_diff.py parse',
  note='Engine real TA Sprite(ParaType5) TCW PalSelect=(tcw>>21)&0x3F. Cable PAL4 body sprites = bank 24 (never 25). Full engine bank set across all frames = {16,17,18,24,25}, IDENTICAL to the GSTA client set (16/17/18 for Storm gfx1 c420040; 24/25 for Cable gfx1 c810040). Bank 18 = Storm lightning-aura sub-palette (1484 frames); bank 25 = Cable hat/alt parts (1183). No bank-selection divergence engine-vs-GSTA.';

UPSERT source:gsta_engine_palette_ram SET kind='measurement',
  ref='engine pvr_regs shipped in GSTA prefix; PALETTE_RAM @ pvr off 0x1000 (1024 ARGB4444), PAL_RAM_CTRL 0x108=2',
  note='bank24 = PURPLE/yellow (entry1 fc7d=rgb204,119,221; entry7 fff1=yellow boots; entries11-14 greys). bank25 = BLUE (entries2-8 fbff/f8ef/f5cf/f4af/f38f/f15f/f03d = blue gradient = Cable standard military). This Cable selected palette index 1 -> bank 24 -> purple. Both bank 24 AND bank 25 are correctly populated + shipped; this is NOT the re_kb/25 palette gap (no stale/missing bank).';

UPSERT source:gsta_engine_pixel_truth SET kind='measurement',
  ref='tools/render-replica-poc/render_ta.mjs --mirror (flycast pvr2 path = DIFF truth canvas)',
  note='Rendered the engine real TA + engine VRAM + engine palette -> the engine draws PURPLE Cable with yellow boots, pixel-matching the GSTA client. Costume-color histograms (Cable greys 128/160/224 + peach 224,192,128; Storm white/grey 224/192/160 + skin 160,96,64) match engine-vs-GSTA across the 12-frame shot spread (390..600).';

UPSERT finding:gsta_cable_purple_engine_faithful SET
  statement='The native GSTA client rendering P2C1 Cable PURPLE (purple costume, yellow boots, white hair) is ENGINE-FAITHFUL, not a defect. Measured: (1) engine real TA selects body bank 24 for Cable across all 806 frames; (2) engine PVR PALETTE_RAM bank 24 IS purple/yellow (palette index 1 alt skin) while bank 25 is Cable s blue standard palette; (3) the engine s own pixel render (flycast pvr2) draws purple Cable, matching the GSTA client. render_frame finalize_body (gen_submit_params.c) PRESERVES the resident rectab TCW PalSelect verbatim (override only when resident_pal==0), so the GSTA bank == the engine bank by construction. DO NOT "fix" the Cable palette toward blue/grey — it would diverge FROM the engine. Lesson: a palette that looks wrong to a human can be exactly the engine s render (alt/team-color skin); arbiter = engine TCW bank + PALETTE_RAM contents + engine pixel render, never intuition about canonical colors.',
  status='confirmed', confidence='high', date='2026-06-19';

UPSERT finding:gsta_storm_no_body_divergence SET
  statement='Storm (gfx1 c420040) GSTA-vs-engine: blend (4,5), ListType 2, texfmt 5 IDENTICAL; pal-bank set {16,17,18} IDENTICAL (bank 18 = engine-authored lightning-aura sub-palette, 1484 engine frames). Carve: GSTA-decoded VRAM body band == engine VRAM BYTE-EXACT (0.00% diff) on the frame-aligned pair (the 38% on non-aligned frames is pose drift, the engine re-decoding a different pose into the same VRAM addrs, NOT a carve defect). The "Storm better but not perfect" report shows no measurable per-part render-model bug in bank/carve/facing/blend; the cape garble was already closed by the m-pitch (90533abc4) + non-square Y-first twiddle (1ee855655/c2a89e5db) carve fixes. Any residual is pose-coverage/animation-timing, not render model.',
  status='confirmed', confidence='high', date='2026-06-19';

RELATE finding:gsta_cable_purple_engine_faithful->cites->source:gsta_char_identify;
RELATE finding:gsta_cable_purple_engine_faithful->cites->source:gsta_engine_ta_banks;
RELATE finding:gsta_cable_purple_engine_faithful->cites->source:gsta_engine_palette_ram;
RELATE finding:gsta_cable_purple_engine_faithful->cites->source:gsta_engine_pixel_truth;
RELATE finding:gsta_storm_no_body_divergence->cites->source:gsta_engine_ta_banks;
