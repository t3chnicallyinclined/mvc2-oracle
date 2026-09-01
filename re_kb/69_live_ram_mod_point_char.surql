USE NS re DB kb;

-- ============================================================================
-- 2026-07-10 — LIVE RAM MOD-LAYER PoC (instant char swap): write path PROVEN,
-- point-char master state is CONTENT-DERIVED (not the +0x000 active byte).
-- ============================================================================

UPSERT source:ctrl_ws_charswap_poc SET kind='measurement',
  ref='tools/render-replica-poc/_ctrl_charswap.mjs + _ctrl_flip_active.mjs via control WS 7211 ram_read/ram_write (ssh tunnel), live prod match 2026-07-10',
  note='Sequence: (1) P1<->P2 world-pos swap (+0x34/+0x38) — STUCK, physics continued from poked values. (2) Full P1C1<->P1C2 struct content swap (0x5A4B, slot positions preserved) — engine ACCEPTED: within frames it re-derived point=Storm FROM THE NEW SLOT (drove C2, auto-parked C1 at x=1386.7 bench spot). (3) Active-byte flip + teleport — engine REVERTED both within ~3s (re-asserts active every frame). (4) Re-swap restored everything; engine pulled the point char from the parked position back into the arena itself. ZERO crashes throughout; savestate_load is DISABLED on prod (Overlord A.2) so content re-swap = the restore path.';

UPSERT finding:point_char_master_content_derived SET
  statement='CONFIRMED 2026-07-10. The MVC2 point-character master state is derived from CHAR-STRUCT CONTENT, not from slot address or the +0x000 active byte: after a full C1<->C2 content swap the engine re-pointed "point" at the slot now HOLDING the original point character (drove it, benched the other); directly flipping the +0x000 active bytes is reverted within frames (active is a per-frame DERIVED output). Implication for the mod layer: an instant point swap needs the in-struct TEAM-POSITION field (unmapped — the byte the active-writer routine reads to decide point) swapped between two structs; the engine will then execute the swap itself, cleanly (parking, camera, HUD). Live ram_write of positions and whole structs is SAFE (engine normalizes within frames; slot ADDRESSES are the stable identity, in-struct GFX/DAT pointers travel with content). NEXT: marvelous2 — find the writer of char+0x000 and the field it reads (mvc2-sh4-re-expert job); also fixes: satellites anchor to slot addresses (cosmetic 1-2 frame mismatch on swap).',
  status='confirmed', confidence='high', date='2026-07-10';

RELATE finding:point_char_master_content_derived->cites->source:ctrl_ws_charswap_poc;
