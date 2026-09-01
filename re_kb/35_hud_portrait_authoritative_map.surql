-- ============================================================================
-- 35: HUD portrait char_id->cell map made AUTHORITATIVE (ROM-grounded) — CLOSES
--     finding:hud_portrait_decode (was OPEN: visually-guessed CELL_CHAR, wrong
--     portraits incl. Sentinel showing another char's face).
-- Sources: marvelous2 bank16/bank13/bank0f + DM01POL portrait-model UVs + live Oracle.
-- ============================================================================
USE NS re DB kb;

-- ---- the three cross-consistent ROM tables that pin every portrait cell --------
UPSERT routine:loc_8c161fec SET label='loc_8c161fec', pc='0x8C161FEC', bank='bank16',
  role='Dreamcast Character Select ID Table (grid->char_id)',
  note='8x8 grid of bytes, INDEXED table[col*8 + row] = char_id (0xff = empty/stage). '
     || 'Index math is exact from the read site bank0f loc_8C0F4774: `shll2 r0; shll r0; '
     || 'add tablebase,r0; mov.b @(r0,r2),r0` => r0=col*8, then +row. So the table is '
     || 'COLUMN-MAJOR. Bytes (col0 rows0..7 ; col1 ; ...): '
     || 'col0=ff,20,1c,38,07,2d,36,ff col1=ff,23,02,15,06,39,2e,ff '
     || 'col2=27,1f,00,14,16,08,2f,2b col3=21,1e,01,13,17,09,28,35 '
     || 'col4=25,37,04,12,0b,0c,29,31 col5=26,03,22,10,0f,0e,2c,32 '
     || 'col6=ff,24,05,11,0a,0d,33,ff col7=ff,3a,1d,1b,30,2a,34,ff. '
     || 'Comment: "Used to translate the DM01POL.BIN file which has portraits". '
     || 'There is also a Naomi variant loc_8c161fac (different byte layout; this is the '
     || 'DC build so loc_8c161fec is authoritative).';
UPSERT routine:loc_8c13b7d4 SET label='loc_8c13b7d4', pc='0x8C13B7D4', bank='bank13',
  role='Character Select Grid Placement (char_id->[row,col])',
  note='char_id-indexed table, 2 bytes/char_id = [ROW, COL] (byte0=row, byte1=col), '
     || 'char_id 0x00..0x3a. EXACT INVERSE of loc_8c161fec: verified table[col*8+row]==cid '
     || 'for all 53 grid chars (0 mismatches). Confirms the screen-grid coord of every char.';
UPSERT routine:loc_8c0f4774 SET label='loc_8c0f4774', pc='0x8C0F4774', bank='bank0f',
  role='char-select id-highlight: grid(col,row)->char_id via loc_8c161fec',
  note='Reads cursor col@0x8C28C416 / row@0x8C28C414, computes loc_8c161fec[col*8+row]. '
     || 'The canonical read site that fixes the ID-table indexing as column-major.';
UPSERT routine:loc_8c0f4334 SET label='loc_8c0f4334', pc='0x8C0F4334', bank='bank0f',
  role='portrait draw: reads PORTRAIT-OBJECT +0x20 (model index)',
  note='`mov 0x20,r0; mov.b @(r0,r14),r5; extu.b r5,r5; add 0x0A,r5` => NaomiLib portrait '
     || 'model = (obj+0x20)+0x0A. r14 here is the PORTRAIT OBJECT, NOT the gameplay char '
     || 'struct. ORACLE-CONFIRMED the gameplay char struct +0x20 is NOT the portrait model '
     || 'index (reads 0x00/0x03 across slots, not 0..55) — so char+0x20 is NOT the cell key.';

-- ---- the texture-sheet cell ORDER (DM01POL portrait-model UVs, ground truth) ----
UPSERT source:dm01_portrait_model_uvs CONTENT {
  name: "DM01POL portrait-model UVs",
  kind: "disc_geometry",
  note: "DM01POL models 0x0A..0x41 (the 56 portrait NaomiLib 2-tri models) each sample "
     || "ONE 64x64 cell of texture #11. Decoded UV rects (rip_stage NaomiLib decoder) give "
     || "the cell each model occupies: column-major-block bottom-up — model k(0..55): "
     || "block=k//32; idx=k%32; col=block*4+(idx%4); row=7-(idx//4). Left 4 cols rows7->0 = "
     || "k0..31; right 4 cols rows7->2 = k32..55; models 90..96 sample the top-right "
     || "rows0..1 cols4..7 filler. This is the sheet PACKING ground truth."
};

-- ---- CLOSE the finding -----------------------------------------------------------
UPSERT finding:hud_portrait_decode CONTENT {
  name: "hud_portrait_decode",
  status: "confirmed",
  confidence: "high",
  summary: "HUD char portraits decoded OFFLINE from DM01POL/DM01TEX texture #11 (512x512 "
     || "RGB565 TWIDDLED, 8x8 of 64x64 cells; faces stored 90deg-rotated, CCW to upright; "
     || "decode = rip_stage morton-twiddle+RGB565). The char_id->cell map is now AUTHORITATIVE "
     || "from the ROM (was a visually-guessed CELL_CHAR that mis-mapped ~50/56 chars incl. the "
     || "user-reported Sentinel-wrong-face bug). Rule: cell(row,col) holds char C iff "
     || "loc_8c161fec[col*8+row]==C, cross-confirmed by loc_8c13b7d4 (exact inverse) and the "
     || "DM01POL portrait-model UV cell order. PIXEL-VALIDATED for all 47 emitted chars incl. "
     || "live Storm 0x2a / Cable 0x17 / Sentinel 0x34 (each its correct face).",
  routines: "bank16 loc_8c161fec (grid->char_id, table[col*8+row]); bank13 loc_8c13b7d4 "
     || "(char_id->[row,col], inverse); bank0f loc_8c0f4774 (read site fixing col-major); "
     || "bank0f loc_8c0f4334 (portrait draw, model=(obj+0x20)+0x0A — char+0x20 is NOT the "
     || "gameplay-struct field, Oracle-confirmed).",
  resolved: "STAGE plates occupy sheet cells rows4..7 cols0..1 (pixel-confirmed STAGE1..7 + '?' "
     || "random); the top-right rows0..1 cols4..7 are FILLER (duplicate faces of already-mapped "
     || "chars). The DC table maps 9 chars onto stage/filler slots with NO unique sheet face: "
     || "0x06 Cyclops, 0x07 Wolverine, 0x25 Dhalsim, 0x26 Bison, 0x2d Shuma, 0x36 Thanos, "
     || "0x37 Jin, 0x39 BoneWolverine, 0x3a Servbot -> HUD monogram fallback (graceful, never a "
     || "WRONG face). Recovered UNIQUE filler faces: Morrigan 0x03 (r1,c5), Cammy 0x24 (r1,c6), "
     || "War Machine 0x2e (r0,c6). Total 47 real faces + 9 monogram.",
  open: "Optional: recover the 9 monogram chars by reading the PORTRAIT-OBJECT +0x20 model "
     || "index (loc_8c0f4334) live in an all-char char-select capture, then model->cell via the "
     || "DM01POL UV order. Not required for correctness (monogram is never wrong).",
  tool: "tools/rip_portraits.py (CELL_CHAR now built by _build_cell_char() from DC_ID_TABLE = "
     || "loc_8c161fec verbatim) -> web/render-replica/hud/portraits/portraits.{png,json}; "
     || "consumed by hud-client.mjs load()/_plate(). Deployed prod 149.28.44.118 "
     || "/var/www/maplecast/render-replica/hud/portraits/ (png md5 6788cba11e1ee11d852df21b72afde19). "
     || "Cache-bust ?v=emitterz3 (hud-client.mjs + replay.html).",
  char_id_numbering: "ROM internal char_id (== HUD NAMES[] and live char+0x001)."
};
RELATE finding:hud_portrait_decode->cites->source:dm01_portraits;
RELATE finding:hud_portrait_decode->cites->source:dm01_portrait_model_uvs;
RELATE finding:hud_portrait_decode->about->routine:loc_8c161fec;
RELATE finding:hud_portrait_decode->about->routine:loc_8c13b7d4;
RELATE finding:hud_portrait_decode->about->routine:loc_8c0f4774;
RELATE finding:hud_portrait_decode->about->routine:loc_8c0f4334;
