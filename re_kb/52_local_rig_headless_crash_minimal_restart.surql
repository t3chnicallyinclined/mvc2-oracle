USE NS re DB kb;

-- ============================================================================
-- 2026-06-29 — Local render-replica headless CRASH root-cause + the STABLE
-- minimal-instrumentation restart recipe. Picks up after a crash during a
-- combo+Lightning-Storm super as a 2nd client connected.
-- ============================================================================

UPSERT source:headless_crash_22880 SET kind='crash_dump+log',
  ref='C:/Users/trist/AppData/Local/CrashDumps/flycast.exe.22880.dmp (28MB minidump); cap_headless.err (512KB launch/crash stderr); build-headless-win/flycast.exe Jun-29 18:13 (commits 8342a574d/0593e49ea)',
  note='Minidump parsed offline (no cdb/windbg installed) via _parse_minidump.mjs / _md_modules.mjs (MINIDUMP_EXCEPTION_STREAM + MODULE_LIST). Crashed build == the current stable build (same binary, same module offset map).';

-- CRASH ROOT CAUSE (CONFIRMED from the dump + corroborated by minimal-build stability).
UPSERT finding:headless_crash_instrumentation_av SET
  statement='CONFIRMED. The local headless (PID 22880) crash during a combo+Lightning-Storm super as a 2nd replica-live client connected was a HOST-SIDE ACCESS_VIOLATION (0xC0000005, READ) at flycast.exe image base+0x19fc7e (faultPC 0x7ff637ecfc7e, target read 0x238c8393020 = a heap-range pointer), faulting thread tid=65248, EXCEPTION_NONCONTINUABLE. This is NOT the SH4 guest illegal-instruction class (expEvn=0x180 / corrupt engine-owned-pointer cluster) — it is a wild/stale-pointer READ in flycast OWN x64 code, a capture/render-path data race. The launch log (cap_headless.err) shows the run was armed with MAPLECAST_FRAME_ORACLE_HOOK (spamming "[ORACLE-HOOK] FAILED to open /dev/shm/mc_oracle_hook.jsonl" EVERY FRAME — a Linux /dev/shm path the MSVC binary cannot open on Windows) STACKED with CHARPASS/ORACLE-PASS (MAPLECAST_CHARQ), VERIFY_DC, HUD_TA, DUMP_RAM; the last lines before death = "[REPLICA-LIVE] client connected (2 total)" mid-super. The over-accumulated instrumentation threads (oracle-hook capture, CHARQ ta_parse, HUD_TA ta_parse) racing the render/capture state at the 2nd-client-connect + super-spawn was the destabilizer. DROPPING the oracle-hook + CHARQ + VERIFY_DC (env-unset, NO rebuild — every diagnostic is getenv-gated in maplecast_oracle_hook.cpp) yields a binary that SURVIVES the same stress: see finding:headless_minimal_stable.',
  status='confirmed', confidence='high', date='2026-06-29';

-- THE STABLE MINIMAL-RESTART RECIPE (CONFIRMED 60fps + 2-client + dump survival).
UPSERT finding:headless_minimal_stable SET
  statement='CONFIRMED STABLE 2026-06-29. The local render-replica headless restarts STABLE with MINIMAL instrumentation = ONLY MAPLECAST_HUD_TA (HUD/meter A/B) + MAPLECAST_DUMP_RAM_TRIGGER (re-armable 1-frame RAM dump). LAUNCH (direct from Bash, NOT via cmd /c batch which returns without exec): cwd=build-headless-win; env MAPLECAST_HEADLESS=1 MAPLECAST_MIRROR_SERVER=1 MAPLECAST_REPLICA_LIVE=1 MAPLECAST_HEADLESS_AUTOLOAD=1 MAPLECAST_HUD_TA=1 MAPLECAST_DUMP_RAM_TRIGGER=<win-path> MAPLECAST_DUMP_RAM_PATH=<win-path>; UNSET MAPLECAST_FRAME_ORACLE_HOOK/_PROBE/_DECODE, MAPLECAST_CHARQ/_RENDER/_EMIT, MAPLECAST_ASMTRACE, MAPLECAST_BODYCAP, MAPLECAST_VERIFY_DC, MAPLECAST_ORACLE_PROBE, MAPLECAST_DUMP_RAM(one-shot), MAPLECAST_BYPASS_AUDIO_PACING(=120fps double-speed), MAPLECAST_QDIAG; ROM = native Windows backslash path. autoloads slot-0 base savestate; serves 7200 (mirror real-TA) + 7212 (replica GSTA). VALIDATED: (1) 7212 streams 60.0-60.2 fps measured by a RAW WS frame-counter (_frmx_counter.mjs — the wire is ZCST-wrapped zstd: msg#1=7MB prefix, msg#2..=~38-40KB per-frame FRMx, liveness=message cadence NOT the log tail which falsely halts at "about to call InitAudio()"); (2) SURVIVES sustained 20s streaming + a 2ND CLIENT connecting mid-stream (the crash trigger) — both clients 60.0fps concurrent, PID stays alive; (3) the DUMP_RAM trigger fires + the process survives. The same binary that crashed is stable here -> the instrumentation was the cause.',
  status='confirmed', confidence='high', date='2026-06-29';

-- DUMP_RAM_TRIGGER mechanism (for the issue-1b single-frame RAM dump).
UPSERT finding:headless_dump_ram_trigger_mechanism SET
  statement='CONFIRMED. MAPLECAST_DUMP_RAM_TRIGGER=<file> (maplecast_oracle_hook.cpp:3520-3559) = re-armable one-frame dump: each in-match STARTRENDER, if the trigger file EXISTS and in_match(0x8C289624)!=0, the hook reads+REMOVES the file (re-arms for next pose) and dumps that exact frame. MAIN RAM (16MB mem_b) -> MAPLECAST_DUMP_RAM_PATH (default /dev/shm/mc_ram_dump.bin). ON WINDOWS: the MSVC binary CANNOT open /dev/shm paths (fopen null) — BOTH the trigger path AND MAPLECAST_DUMP_RAM_PATH MUST be native Windows paths (verified end-to-end: trigger consumed, 16MB written, vframe logged, process survived). CAVEAT: the COMPANION dumps (VRAM mc_vram_dump.bin, PVR mc_pvr_regs.bin, engine-TA mc_engine_ta.bin) are HARDCODED to /dev/shm/* (NOT env-overridable, maplecast_oracle_hook.cpp:3545/3548/3558) -> they SILENTLY FAIL on Windows. If a byte-exact render_frame-vs-engine A/B (needing VRAM+PVR+TA at the same frame) is required on Windows, that one block needs a getenv override + rebuild. For a plain RAM-only dump (issue-1b), the main path works as-is. To arm: write/touch the trigger file (a normal NTFS path via the C runtime works; MSYS touch on /dev/shm gives Permission denied).',
  status='confirmed', confidence='high', date='2026-06-29';

RELATE finding:headless_crash_instrumentation_av->cites->source:headless_crash_22880;
RELATE finding:headless_minimal_stable->cites->source:headless_crash_22880;
RELATE finding:headless_minimal_stable->about->finding:headless_crash_instrumentation_av;
RELATE finding:headless_dump_ram_trigger_mechanism->about->finding:headless_minimal_stable;
