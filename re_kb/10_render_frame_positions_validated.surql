-- 10_render_frame_positions_validated.surql
-- FINDING: the transpiled render_frame's per-part screen positions are byte-exact vs the
-- engine's OWN per-frame ASMTRACE output (PC 0x8C034864, loc_8c0344d4) for LIVE multi-object
-- frames. The "scramble" the live replica-live client showed is NOT a position bug in
-- render_frame; positions are 0.00px vs ground truth. The residual visual scatter is the
-- WIDE-PART pixel decode/carve (ensureBodyTextures + colrow), a client decode concern.
--
-- Apply: tools/re_kb/rekb.sh @tools/re_kb/10_render_frame_positions_validated.surql

-- source: the ASMTRACE column layout, cited to the handler + the prod log header.
USE NS re DB kb;

UPSERT source:asmtrace_columns_loc8c034864 CONTENT {
  kind: "live_capture",
  pc:   "0x8C034864",
  routine: "loc_8c0344d4 per-part convergence (BOTH transform paths have written final screen X/Y)",
  handler: "core/network/maplecast_oracle_hook.cpp mc_asmTraceHandler (line ~1492-1543)",
  log: "/dev/shm/mc_assembly.log",
  -- 18 columns, confirmed from the fprintf format string (line 1539) AND the live prod header:
  columns: "frame sid slot cid sel dx dy accX accY screenX screenY pal row flip flags r11 r13 node",
  screenX: "col 10 = f32 @ (r15+0x30) — engine final screen X, bottom anchor",
  screenY: "col 11 = f32 @ (r15+0x34) — engine final screen Y, bottom anchor",
  sel:     "col 5  = read_u16(r11+6) — GFX1 part selector (per-part)",
  node:    "col 18 = r14 char/render base (|0x0C000000); maps to the owning fighter",
  r13:     "col 17 = inner part cursor; walks DESC_TABLE 0x8C1F9F9C in prefix-sum order across bodies",
  note: "the prompt's example line mislabeled token count; the deployed header is authoritative: 18 cols"
};

-- finding: render_frame positions validated to 0.00px vs ASMTRACE.
UPSERT finding:render_frame_positions_validated CONTENT {
  title: "render_frame per-part screenX/Y == engine ASMTRACE (0.00px), live multi-object",
  status: "confirmed",
  confidence: 1.0,
  date: "2026-06-13",
  method: "sync wire frame (livecap.mjs wss://nobd.net/replica-live) by engine frame 0x8C3496B0; grep /dev/shm/mc_assembly.log for that frame; run render_frame.wasm on the wire RAM; per-part diff bottom-left (Ax,Cy) vs ASMTRACE (screenX,screenY)",
  harness: "tools/render-replica-poc/_diff_vs_asm.mjs (+ repro_scramble.mjs for PNG)",
  result_frames: ["591400","591410","591422","591430"],
  result: "maxDX=0.00px maxDY=0.00px BOTH fighters (cid52 Sentinel P1C1 LEFT, cid23 Cable P2C1 RIGHT), every part; render_frame quad count == asmParts every frame; sel and node owner match 1:1 in emission order; +0xDC prefix-sum correct (Sentinel cursor=0/52 tiles, Cable cursor=52)",
  implication: "the live scramble is NOT a render_frame positioning/read-set bug for the 2 FIGHTER bodies. The char-struct (0x8C268340 6*0x5A4), arena (0x8C1F9D80), tiledesc (0x8C1F9F9C 0x1800), camera, idxtab, rectab dynamic regions ARE sufficient for exact fighter geometry. Residual scatter = WIDE-PART pixel decode/carve (sel 112 4x4 grid, sel 121 8-wide) in ensureBodyTextures/colrow — a CLIENT DECODE concern, not server read-set.",
  open_risk: "read-set gap remains for BODY nodes OUTSIDE the 6 fighter char structs (projectiles/satellites/capes at object-pool nodes): render_object_full reads their node+0xDC/+0xE0/+0xEC which the dynamic table does NOT ship -> stale -> wrong geometry. Not triggered in the 2-fighter capture (counts=[..L05=1,L06=1..], 0 effects). Add those nodes' +0xDC..+0xF0 window to the dyn table when an effect/satellite body appears."
};

-- operational note: ASMTRACE log has no rotation and freezes silently on /dev/shm ENOSPC.
UPSERT finding:asmtrace_log_enospc_freeze CONTENT {
  title: "ASMTRACE /dev/shm/mc_assembly.log freezes silently when tmpfs fills",
  status: "confirmed",
  confidence: 1.0,
  date: "2026-06-13",
  detail: "log grows ~25MB/min, no rotation; at /dev/shm 100% the fprintf appends fail (last line is a partial mid-write), freezing the frame counter while the live engine + replica-live stream advance. Symptom: log frame far behind live vframe though both read 0x8C3496B0 on the same pid. Fix: rm /dev/shm/mc_assembly.log (handler fopen('a') recreates with header); periodically truncate during long captures."
};

RELATE finding:render_frame_positions_validated->cites->source:asmtrace_columns_loc8c034864 SET note="positions diffed against the 18-col live log";
