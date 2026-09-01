-- ============================================================================
-- 23c: SATELLITE (PROJECTILE) DISPATCH — LIVE-VALIDATED, the OPEN cross-check from
-- 23b is now CLOSED (2026-06-14). The prior block (23b) could not diff the satellite
-- part-walk because _satlive.mcrr had NO engine-visible satellite (every cat 1..4 pool
-- node had +0x12C==0 and sat beyond the slot count). This session captured a LIVE prod
-- frame WITH 3 engine-visible cat 1..4 projectiles in the slot count (+0x12C=1) and
-- diffed render_frame's per-part emission vs the ASMTRACE ground truth to <0.005px.
-- Apply:
--   tools/re_kb/rekb.sh @tools/re_kb/23c_satellite_dispatch_live_validated.surql
-- ============================================================================
USE NS re DB kb;

UPSERT source:asmtrace_projcap_1405656 SET kind='oracle_capture',
  ref='prod /dev/shm/mc_assembly.log (PC 0x8C034864, MAPLECAST_ASMTRACE=1) + tools/render-replica-poc/_projcap.mcrr (wss://nobd.net/replica-live, 500 frames, vframe 1405656..1406155) + _asm_sync.txt (synced ASMTRACE slice, same vframe range)',
  note='Live coupled capture 2026-06-14. PROCEDURE that worked: /dev/shm was 100%% full (tmpfs 2.0G) so the ASMTRACE log was FROZEN (stale at vframe 1349378) and its frame counter no longer tracked the replica-live stream (which was at vframe 1405xxx); `cp /dev/null /dev/shm/mc_assembly.log` freed shm and the hook resumed writing fresh frames whose col-1 frame counter (0x8C3496B0) once again aligns with the livecap MCRR vframe. Captured the MCRR, then `awk "$1>=1405656 && $1<=1406156"` sliced the matching ASMTRACE. At vframe 1405656 the engine emitted parts for 5 nodes: 2 FIGHTER bodies (0c2688e4 P2C1 cid20, 0c268e88 P1C2 cid42) + 3 POOL-NODE PROJECTILES (0c26afc4 cat4 22parts, 0c26b194 cat4 7parts, 0c281874 cat3 10parts). All 3 satellites share gfx1=0xc570040 / gfx2=0xc658680 = character 42 (P1C2) GFX banks (already streamed/resident) and carry body-range sels (0x2df/0x2f6/0x376 = 735/758/886, in 252..1532) -> they decode through the body GFX2 walker, not the effect path.';

UPSERT source:livecap_mcrr_frame_layout SET kind='format_decode',
  ref='tools/render-replica-poc/livecap.mjs output + tools/render-replica-poc/_diff_proj.mjs parser',
  note='livecap MCRR per-FRMx-record layout reverse-engineered 2026-06-14 (the OLD _diff_sat.mjs parser broke on it -> "bad FRMx"): FRMx(4) vframe(4) taSize(4) dyn(sum-of-dyn-region-lens=214172) nGfx(4) [base(4) len(4) data(len)]*nGfx taData(taSize) <trailing pvr/pad blob, variable>. nGfx>0 ONLY on the first frame a given char texture streams in (the resident GFX1/GFX2 blobs); later frames carry nGfx=0 and reuse them. The trailing per-frame blob size VARIES (a mid-stream nGfx>0 frame shifts it), so the robust parser resyncs to the next FRMx magic 0x784D5246 rather than assuming a fixed trailer. dyn regions (15): slot_cn@2895e0:16 slot_pt@287de0:6144 char_st@268340:8664 objpool@26aa54:118784 arena@1f9d80:32 tiledes@1f9f9c:6144 cam_mat@2d6ad8:192 camZ@26a510:64 ggp_ptr@26823c:4 ggp_acc@268240:64 rparam@26a974:256 tab_ptr@2dad30:64 rmode@2aa4c0:16 idxtab@24b65c:8192 rectab@24d7dc:65536.';

-- ---- CLOSE the dispatch finding: the live-satellite ASMTRACE cross-check now PASSES ----
UPSERT finding:replica_live_satellite_dispatch SET
  statement='CLOSED 2026-06-14 (was OPEN since 23b). PROJECTILES (cat 1..4 satellite-pool BODY-sprites) RENDER in the live render-replica scene, validated <1px (in fact <0.005px) per-part vs the ASMTRACE ground truth. The transpiled dispatch is CORRECT AS-IS and needed NO fix: gen_walker_root.c (loc_8c0308c2) routes node+0x3==0 -> render_frame_body_hook and node+0x3 in [1,5) -> render_frame_satellite_hook (render_object_full_ex is_sat=1 = loc_8c030af8 setup + the SHARED body walker loc_8c0344d4). VALIDATION (tools/render-replica-poc/_diff_proj.mjs, source:asmtrace_projcap_1405656): 8 distinct live projectile nodes diffed across cat=3 and cat=4 and multiple frames, every one PASS — node 0c26afc4 (cat4, 22 parts) maxDX=0.003 maxDY=0.004; 0c26b194 (cat4, 7) 0.003/0.004; 0c281874 (cat3, 10) 0.003/0.004; 0c275684/0c27cc54/0c27de74/0c27a474/0c281fb4/0c2876b4 (cat3) all <0.005px. COUNT delta: render_frame reports satellites=3 at vframe 1405656, exactly the 3 engine-visible cat 1..4 pool nodes from an independent slot-walk; their 39 parts (22+7+10) are emitted as 39 of the 84 scene quads (without the dispatch they would all be dropped -> 45 fighter-only quads, satellites=0). The web AND node render_frame.wasm are byte-identical (md5 6f6292317e9f210c7800d74f7bc089d0) and the web build is ALREADY deployed on prod (/var/www/maplecast/render-replica/render_frame.wasm, same md5) under cache-bust ?v=fx1 in replay.html -> projectiles are live with NO new deploy required. NOTE: projectile PIXELS depend on body_decoder.mjs carve (fixed in parallel, out of this scope) but the satellites\' gfx1 == an on-screen fighter\'s GFX bank (resident), so the texture WILL resolve once the carve lands; this finding covers DISPATCH + GEOMETRY only.',
  status='confirmed', confidence='high', date='2026-06-14';

RELATE finding:replica_live_satellite_dispatch->cites->source:asmtrace_projcap_1405656;
RELATE finding:replica_live_satellite_dispatch->cites->source:livecap_mcrr_frame_layout;
