USE NS re DB kb;

-- ============================================================================
-- REVISED 2026-06-29 (v3) — finding 49's "effect SKIP is sufficient" conclusion
-- is WRONG, AND the first revision's "stale effect-VRAM slot" theory is ALSO wrong.
-- A live Lightning Storm super was captured (_live_fx3) and MEASURED. The garble
-- (~6-8 tiled copies of Storm's body + fists, over the HUD) is NOT an Effect-Poly
-- decode/VRAM problem at all: the effect-node scanner found ZERO Effect-Poly bank
-- (0x0CED0000) nodes across the entire super. The TRUE root cause is the slot-walk
-- effect nodes OVER-TILING because node+0xDC / tiledesc are STALE during the super
-- freeze. See finding:gsta_super_effect_overtile (the authoritative root cause).
-- ============================================================================

UPSERT source:gsta_effect_decode_model_measured SET kind='measurement',
  ref='marvelous2 bank12 loc_8C1244B0 + gen_submit_params.c read_template (decode MODEL only)',
  note='Effect-Poly DECODE MODEL stays CONFIRMED but is NOT the active bug: per-part submit reads the TCW from the resident rectab template; the Effect-Poly bank is an absolute-pointer directory; effects are never per-frame LZSS-decoded. IRRELEVANT to _live_fx3 — there are NO Effect-Poly nodes in the Lightning Storm super.';

UPSERT finding:gsta_effect_decode_skip_proven SET
  statement='SUPERSEDED 2026-06-29 by measurement on _live_fx3 (live Lightning Storm). The 2026-06-21 "effect SKIP sufficient" conclusion AND the 2026-06-29-v1 "stale effect-VRAM slot" theory are BOTH disproven: the effect-node scanner (_find_efx_nodes.mjs / _fx3_slotwalk_dump.mjs) found ZERO Effect-Poly bank (0x0CED0000) nodes across the whole super. The visible garble is the SLOT-WALK effect nodes (cat 1..4, Storm gfx1=c420040, bit15-set sels) OVER-TILING in the GSTA render_frame reconstruction. ROOT CAUSE + fix tracked in finding:gsta_super_effect_overtile. The Effect-Poly SKIP guard in gstaDecodeBodies is harmless (no effect-poly node hits it here) and is left in place. Branch feat/render-replica-live.',
  status='superseded', confidence='high', date='2026-06-29';

RELATE finding:gsta_effect_decode_skip_proven->cites->source:gsta_effect_decode_model_measured;
RELATE finding:gsta_effect_decode_skip_proven->about->finding:gsta_super_effect_overtile;
