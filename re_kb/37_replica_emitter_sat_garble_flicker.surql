-- ============================================================================
-- 37: render-replica LIVE (EMITTER body mode) — the bottom-center "effects/sparks
-- flicking on and off in random places near the feet" is the EMITTER POOL-SAT draw
-- pairing a pool node's sel against the WRONG (owner-body) atlas. Diagnosed + fixed
-- 2026-06-15. Distinct from finding 29 (that is the render_frame walker path; the LIVE
-- default is __bodyMode='emitter', sprite-client.buildEmitterDrawList, NOT render_frame).
-- Apply: tools/re_kb/rekb.sh @tools/re_kb/37_replica_emitter_sat_garble_flicker.surql
-- ============================================================================
USE NS re DB kb;

UPSERT source:emitter_sat_pairing_code SET kind='js_function',
  ref='web/webgpu/sprite-client.mjs buildEmitterDrawList (pool-objects loop) + web/render-replica/replay.html populateObjectsFromRAM / renderBodiesPass',
  note='LIVE replay default is window.__bodyMode=\'emitter\' (replay.html ~L1499) -> renderBodiesPass -> populateObjectsFromRAM walks the slot table (0x8C2895E0 count / 0x8C287DE0 ptr, stride 0x180, 16 layers) gating each node EXACTLY like the prod readAllDrawn (maplecast_gamestate.cpp:421 node+0x12C==0 SKIP; sid==0 skip; screen OOB -64..704/-64..544 skip), then pushes {cid(owner char_id),sid:node+0x144&0x7fff,type:layer,x,y,isEffect:gfxLow in 0x0CED0000,engZ:1/(node+0xE8),...}. buildEmitterDrawList then for each pool object found the owner body slot by char_id and called emitAssembly({cid:o.cid,...}, o.sid) — i.e. it drew o.sid AGAINST THE OWNER BODY ATLAS PL{cid}. That is the bug: a pool node`s sel indexes the NODE`S OWN GFX2 (node+0x160), a different cell stream than the body`s assembly table.';

UPSERT source:emitter_sat_engine_model SET kind='marvelous2',
  ref='bank03 loc_8c030af8 (satellite/effect setup, sibling of loc_8c03093c Render Main Sprite) -> loc_8c034bea (sel dispatch on node+0x144: 0xFF=terminator, &0x8000=loc_8c0348c8 scaled, else loc_8c0344d4) -> loc_8c0344d4 (the body walker, indexes GFX2 node+0x160 by sel&0x7FFF)',
  note='ENGINE TRUTH (already cited in effects-client.mjs + finding:replica_live_satellite_dispatch / 23): a pool object/effect is rendered by the IDENTICAL walker as a body, through the IDENTICAL loc_8c030af8 setup, keyed by its OWN node+0x144 sel and its OWN node+0x160 GFX2. There is NO separate effect cell processor, and the owner body`s GFX2/atlas is NOT the object`s art source. The render-replica EMITTER only HOLDS baked BODY atlases (PL{cid}_parts/_asm, keyed by the body`s GFX2 assembly cells). So an owner-atlas pairing is only valid for a sat that is part of the owner`s OWN GFX2 (an owned cape/assist pose) — NOT for a projectile/effect with a distinct or Effect-Poly (0x0CED0000) GFX2.';

UPSERT finding:replica_emitter_sat_garble_flicker SET
  statement='CONFIRMED + FIXED 2026-06-15. The user-reported bottom-center transient garble ("effects flicking on and off in random places near the feet, might be sats or sparks") in the LIVE render-replica (replay.html, wss://nobd.net/replica-live, __bodyMode=emitter) is the EMITTER POOL-SAT draw, NOT the effects pass. renderEffectsPass (EffectsClient.render) is a NO-OP (returns 0, draws nothing; pure effects are meant to render via the walker), so it cannot be the flicker — proven by the window._fxRenderMode toggle (off vs on = identical picture). ROOT CAUSE (pinned to live node data): buildEmitterDrawList drew each pool node`s sel (node+0x144) against the OWNER BODY atlas PL{cid} (emitAssembly cid:o.cid, o.sid). A pool node`s sel indexes the NODE`S OWN GFX2 (node+0x160) — for a projectile/effect that is a DIFFERENT cell stream. Whenever a transient pool sel collided with a baked body pose index, the emitter slapped a WRONG body sprite at the node`s screen foot, vanishing the next frame as the node`s sel changed -> the random-place bottom-center on/off flicker. Owner-less / cid==0 / Effect-Poly-bank (0x0CED0000, isEffect) nodes were also fed to the owner atlas (extra garble). FIX (engine-grounded, web/webgpu/sprite-client.mjs buildEmitterDrawList pool loop): (1) SKIP isEffect (Effect-Poly bank) sats — they have no baked body atlas and render via the engine walker, never the body atlas; (2) require a LIVE ACTIVE owner body of the same char_id (no global/dead node draws); (3) require the sel to ACTUALLY HIT the owner body assembly table (asmChars[cid].asm[sid]) before drawing — a non-hit is skipped (skipSel++), so a colliding sel can no longer paint a wrong pose at the foot. Net: only an actually-owned cape/assist pose draws, at its node anchor; everything else is left to the engine-faithful path. window._satRenderMode=\'off\' draws NO pool sats (isolation toggle, confirms the flicker source in the live browser); window._fxRenderMode=\'off\' skips the (no-op) effects pass. Diagnostic hook window.__satNodes() dumps each live pool node with {isEffect,ownerActive,hit,willDraw} so a flicker node is pinned to live data (flicker nodes show willDraw=false: hit=false collision or isEffect=true misroute). Deployed cache-bust: replay.html sprite-client import ?v=scene2b. Branch feat/render-replica-live.',
  status='confirmed', confidence='high', date='2026-06-15';

RELATE finding:replica_emitter_sat_garble_flicker->cites->source:emitter_sat_pairing_code;
RELATE finding:replica_emitter_sat_garble_flicker->cites->source:emitter_sat_engine_model;
RELATE finding:replica_emitter_sat_garble_flicker->cites->routine:loc_8c0344d4;
RELATE finding:replica_emitter_sat_garble_flicker->cites->routine:loc_8c030af8;
RELATE finding:replica_emitter_sat_garble_flicker->about->finding:replica_live_satellite_dispatch;
RELATE finding:replica_emitter_sat_garble_flicker->about->finding:replica_effect_overemit_sel_ff;

-- ---- OPEN sub-item: owned-cape/assist sats need their OWN GFX2 atlas for full fidelity ----
UPSERT finding:replica_emitter_sat_own_gfx2_atlas SET
  statement='OPEN (raised 2026-06-15). The fix above draws a pool sat ONLY when its sel hits the OWNER body`s baked assembly table — correct for sats that are part of the owner`s OWN GFX2 (some capes/assists), but a projectile/super/hitspark with a DISTINCT GFX2 (incl the shared Effect-Poly bank 0x0CED0000) is now SKIPPED by the emitter rather than mis-drawn. To render those faithfully in emitter mode they need their own baked assembly atlas keyed by the node`s node+0x160 GFX2 + node+0x144 sel (the walker`s real keys), OR the live page should route the emitter`s sat draw onto the engine walker (render_frame satellite hook, finding:replica_live_satellite_dispatch) the same way render_frame mode already does. Until then, emitter-mode shows bodies + owned-pose sats cleanly with NO garble; distinct-GFX2 projectiles/effects are absent rather than garbled. Validate when a matchup fires a non-owner-atlas sat on screen (use window.__satNodes() to enumerate isEffect/hit=false nodes).',
  status='open', confidence='high', date='2026-06-15';

RELATE finding:replica_emitter_sat_own_gfx2_atlas->about->finding:replica_emitter_sat_garble_flicker;
RELATE finding:replica_emitter_sat_own_gfx2_atlas->about->finding:replica_live_satellite_dispatch;
