USE NS re DB kb;

-- 2026-06-29 — HUD bars-don't-deplete diagnosis on _live_hud + the row-group fix.
UPSERT source:hud_nodeplete_diag SET kind='measurement',
  ref='tools/render-replica-poc/_live_hud.{gsta.mcrr,mirror.zcst} (964f combo, slot1/P2C1 hp 144->5); _hud_diag/_hud_diag2/_hud_diag3/_replay_reshape/_verify_rowgroup.mjs (offline replay of the C++ gstaBuildHudTA reshape on the same wire); maplecast_mirror.cpp gstaBuildHudTA.',
  note='3-hypothesis triage: (1) health-read REFUTED, (2) signature MATCHES, (3) twin-overdraw CONFIRMED + fixed.';

UPSERT finding:hud_reshape_twin_overdraw_fix SET
  statement='ROOT CAUSE = (3) twin-overdraw, FIXED. The native HUD bars did not deplete despite a correct reshape. Triaged offline on _live_hud (the reshape consumes the same wire HUDQ + _gstaRam, so it reproduces the native client exactly): (1) HEALTH READ = FINE — read8(0x2688E4+0x420) (P2C1, the active opponent point char, actives=110000) drops 144->140->120->...->6->5 across the combo; the char page-616 IS in the shipped dyn regions (0x268340 len 0x21d8). hpFrac varies 1.0->0.04 correctly. (2) SIGNATURE = MATCHES — 8-10 HUDQ quads/frame match (tcw==0x80000, w~152, h~8, cy 78/98); the reshape math is correct (offline: at p2hp=79 it shrinks one quad to w83, at p2hp=6 to w6). (3) THE BUG: each visible bar is drawn as TWO 0x80000 quads at ~the same cy (pcw 0x...1f body + 0x...2d highlight, cy differs <0.2px). The old slotForCand ranked cands by sorted-cy index, so the two same-cy quads got DIFFERENT row indices -> one mapped to slot1 (active, hpF=0.55, SHRANK) but its twin mapped to slot3 (reserve, hpF=1.0, stayed FULL-WIDTH) and OVERDREW the shrunk one -> bar never visibly depleted. FIX: cluster cands into VISUAL ROWS (cy within 6px) and map each ROW (not each quad index) to a slot, so BOTH same-row quads get the active char hpFrac and shrink together. VALIDATED offline on _live_hud: at p2hp 79/47/6 BOTH row0 P2 quads now shrink to w83/50/6 (matching p2hp/144*152), row1 reserve stays full. Build/flycast.exe relinked NINJA_EXIT=0 (fresh PE 22:00). NEEDS USER LIVE RE-VERIFY. NOTE: the 0x80000 quad IS the visible HP fill (h=8 team-color bar body); 0x9be00 are h=1-2 frame/highlight lines (correctly left alone). Meter still HUDQ-verbatim (staged). re_kb/55.',
  status='implemented', confidence='high', date='2026-06-29';

RELATE finding:hud_reshape_twin_overdraw_fix->cites->source:hud_nodeplete_diag;
RELATE finding:hud_reshape_twin_overdraw_fix->about->finding:hud_native_client_port_scoped;
