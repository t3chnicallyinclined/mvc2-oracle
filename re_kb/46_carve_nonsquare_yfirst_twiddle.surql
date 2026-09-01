-- finding:carve_nonsquare_yfirst_twiddle
-- CONFIRMED-BY-MEASUREMENT 2026-06-15 (byte-exact vs engine VRAM, flycast twop).
-- CORRECTS finding:carve_nonsquare_linear_fix (re_kb/44).
--
-- The W>32 AND H>32 multi-32x32-tile body parts (m==32, cols>1, rows>1) are stored in VRAM as
-- ONE full-WxH PVR-twiddle blob; tile (col,row)'s 32x32 chunk lives at the TILE-GRID twiddle index.
--   - SQUARE grid (Tw==Th, e.g. sel124 128x128 4x4): X-FIRST tile twiddle (gstaTwTile). [re_kb/43]
--   - NON-SQUARE grid (Tw!=Th, e.g. Storm cape sel267/285/273 64x128 = 2x4): Y-FIRST tile twiddle
--     (gstaTwTileYFirst) — flycast's REAL _twiddleSlow interleave (y-bit before x-bit for the
--     short dimension). re_kb/44's "non-square -> LINEAR slice" was WRONG: linear (and x-first)
--     scatter the off-diagonal tiles -> the POSE-DEPENDENT Storm-cape grey-block garble.
--
-- Root-caused by: dump the engine VRAM 512B chunk at each tile's TCW (mirror client :7200 /
-- headless) and the offline decodeA chunk; compare the carved 32x32 tile read through flycast's
-- twop. Y-first reproduces sel267/285/273 byte-exact; x-first/linear do not.
-- Fix in BOTH gstaDecodeBodies (core/network/maplecast_mirror.cpp) + body_decoder.mjs (lockstep).
-- Verified live multi-frame (stage off): frames 120/240/360/480 all clean (360 was the garbled pose).
-- META: re_kb/44 "screenshot-confirmed" on one pose and missed this — single-frame signoff fails on
-- pose-dependent carve bugs; verify >=12 poses + diff vs the engine's own twop, never a hand ref.
USE NS re DB kb;

UPSERT finding:carve_nonsquare_yfirst_twiddle SET
  status = "confirmed",
  area = "gsta-carve",
  corrects = "finding:carve_nonsquare_linear_fix",
  summary = "W>32 H>32 NON-square multi-tile parts (Tw!=Th) use Y-FIRST tile twiddle, not linear; "
          + "fixes pose-dependent Storm-cape grey blocks. SQUARE parts stay x-first (re_kb/43).";
