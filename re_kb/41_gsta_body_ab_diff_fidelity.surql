-- 41_gsta_body_ab_diff_fidelity.surql
-- MEASURED body-fidelity A/B diff: GSTA-emitted TA vs the real mirror-client TA (:7200),
-- slot-0 in-match deterministic. Tool: tools/gsta_ta_diff.py (per-sprite param parser).
-- All numbers CONFIRMED-BY-MEASUREMENT (2026-06-15), not disasm/doc inference.

-- ---------------------------------------------------------------------------
-- SOURCE: the A/B TA diff harness
-- ---------------------------------------------------------------------------
USE NS re DB kb;

UPSERT source:gsta_ta_ab_diff CONTENT {
  kind: "tool",
  name: "tools/gsta_ta_diff.py + MAPLECAST_DUMP_GSTA_TA_DIR / MAPLECAST_DUMP_TA_DIR",
  what: "Dumps the GSTA reconstruction-client emitted TA (per vframe) and the real "
      + "mirror-client received TA (per frameNum) to keyed dirs; parser extracts every "
      + "ParaType=5 sprite (PCW/ISP/TSP/TCW/corners/UV) and aligns by body-corner overlap.",
  testbed: "headless slot-0 in-match (deterministic) on :7200(real)/:7212(gsta). Align by "
        + "best A-corner overlap -> constant frameNum<->vframe offset; census matches each "
        + "GSTA body tile (pal in {16,17,18,24,25}) to its nearest real tile."
};

-- ---------------------------------------------------------------------------
-- FINDING 1: Cable-blue = static even-bank palette override (NOT snapshot timing)
-- ---------------------------------------------------------------------------
UPSERT finding:gsta_palette_bank_preserve CONTENT {
  status: "confirmed",
  confidence: "high",
  summary: "The static formula 16*(char_pair+1)+8*player_side yields only EVEN base banks "
         + "{16,24,...}; the engine allocates palette banks DYNAMICALLY (loc_8c124bd8) and "
         + "uses ODD sibling banks (17,25). gen_submit_params.c finalize_body was overriding "
         + "the wire's resident TCW PalSelect with the static even bank, dropping odd-bank "
         + "skins (Cable) to the wrong even sibling => all-blue. FIX: preserve the resident "
         + "rectab TCW PalSelect; only inject when resident pal is empty.",
  measured: "A/B per-sprite aligned diff: palette-bank mismatch 0.00% over 41,163 / 12,682 "
         + "body tiles (two runs). REAL and GSTA both emit {16,17,18,24,25} incl odd siblings. "
         + "Pre-fix static override emitted only even {16,24}.",
  disproved: "The 'palette snapshot-timing gap' doc guess -- the diff showed the cause was the "
          + "static even-bank override, not timing. DIFF beat the doc.",
  fix_site: "tools/render-replica-poc/gen_submit_params.c finalize_body() PalSelect preserve",
  commit: "f2e81a82f"
};

-- ---------------------------------------------------------------------------
-- FINDING 2: blend + V-orientation are byte-exact (advisories CONFIRMED)
-- ---------------------------------------------------------------------------
UPSERT finding:gsta_body_blend_uv_confirmed CONTENT {
  status: "confirmed",
  confidence: "high",
  summary: "Body per-sprite blend and V-orientation match the real engine TA byte-for-byte.",
  measured: "Over ~620K-670K body/HUD sprites: blend(src/dst)=(4,5) 100% both sides, "
         + "ListType=2 (translucent) 100% both, texfmt=5 (PAL4) 100% both, top TSP word "
         + "0x949004D2 identical. Aligned per-sprite: TSP mismatch 0.00%, V-orientation "
         + "mismatch 0.03% (essentially zero). U/V ranges [0,1] both sides.",
  note: "The forced translucent/MODULATE in gstaEmitSpriteTA and the finalize_body TSP "
      + "reproduce the real per-sprite blend exactly -- no per-sprite wire TSP needed."
};

-- ---------------------------------------------------------------------------
-- FINDING 3: texU mirror = facing XOR per-part 0x4000 (flip4000-alone DISPROVEN)
-- ---------------------------------------------------------------------------
UPSERT finding:gsta_texu_mirror_facing_xor CONTENT {
  status: "confirmed",
  confidence: "high",
  summary: "The per-tile texU mirror bit = body_facing(node+0x110) XOR the per-part 0x4000 "
         + "X-mirror flag (GFX2 cell record flags @ r11+0x4). The engine folds facing into "
         + "BOTH the screen-X span direction AND the texel-U direction (lockstep).",
  measured: "A/B census: facing-XOR formula -> U mismatch 1.46% (599/41163); flip4000-ALONE "
         + "-> U mismatch 35.04% (4551/12989). flip4000-alone un-mirrors every facing==1 tile.",
  disproved: "flip4000-alone, which the loc_8c0347bc disasm (`tst r8 -> neg r5`) suggested. "
          + "The DIFF overruled the disasm reading.",
  open_residual: "1.47% U mismatch remains, concentrated in pal-16 / one body / facing==1, a "
              + "pure U swap (630/652 are exact swaps). Localized per-pose effect, NOT the gross "
              + "facing rule. Minor; supersedes/refines re_kb emitter_flip_unvalidated.",
  commit: "7819056df"
};

-- ---------------------------------------------------------------------------
-- FINDING 4: native carve == validated web re-tile reference (NOT a fragmentation bug)
-- ---------------------------------------------------------------------------
UPSERT finding:gsta_native_carve_matches_web CONTENT {
  status: "confirmed",
  confidence: "high",
  summary: "gstaDecodeBodies (maplecast_mirror.cpp) per-tile re-tile carve is byte-identical to "
         + "the occupancy-validated web body_decoder.mjs ensureBodyTextures: same detwiddlePal4, "
         + "same ox=col*32/oy=row*32 32x32 clamp+zero-pad, same retwiddle32, same TCW addressing, "
         + "same (col,row) from render_frame_quad_colrow. The fixed-32 step is the VALIDATED "
         + "per-tile model (web finding:per_tile_retile_decode), not the superseded variable m=W/cols.",
  measured: "Aligned A/B: V-orient 0.03%, palette 0.00%, TSP 0.00% -- no tile-coverage/carve "
         + "fragmentation detected. The only body diff is the 1.46% texU mirror residual (Finding 3).",
  note: "Task-4 'fragmentation/scatter' hypothesis (variable carve) was already superseded; the "
      + "carve was not the cause."
};

UPSERT edge:about_41a CONTENT { in: finding:gsta_palette_bank_preserve, out: source:gsta_ta_ab_diff };
UPSERT edge:about_41b CONTENT { in: finding:gsta_body_blend_uv_confirmed, out: source:gsta_ta_ab_diff };
UPSERT edge:about_41c CONTENT { in: finding:gsta_texu_mirror_facing_xor, out: source:gsta_ta_ab_diff };
UPSERT edge:about_41d CONTENT { in: finding:gsta_native_carve_matches_web, out: source:gsta_ta_ab_diff };
