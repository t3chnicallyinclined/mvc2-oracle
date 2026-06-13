#!/usr/bin/env python3
"""oracle-tail-ws.py — tail the Oracle /dev/shm logs and serve them to the dashboard over a
WebSocket, merged by frame number. Runs on the box that runs flycast (the logs are local /dev/shm).

Phase 3 deliverable. Consolidates the parse/attribution logic currently scattered across
_oracle/*.py (oracle_live.py, oracle_layers.py, oracle_attribute.py) into one tail+parse+serve tool
(the planned tools/oracle_query.py is the offline/CLI sibling of this).

Tails:
  /dev/shm/mc_assembly.log      (ASMTRACE: frame sid slot cid sel dx dy accX accY screenX screenY pal row flip)
  /dev/shm/mc_oracle_hook.jsonl (Frame Oracle: per-frame sprite_quads + objects + blend)
  /dev/shm/mc_charq_render.jsonl(CHARQ: per-part PVR quads)
  /dev/shm/mc_probe.log         (generic probe)

Emits per-frame snapshots: {"frame": N, "asmtrace": [...], "oracle": {...}, "charq": [...]}.
"""
# TODO(phase3): implement tail -F + line parse + frame-merge + websockets serve.
if __name__ == "__main__":
    raise SystemExit("oracle-tail-ws.py is a Phase 3 stub — see docs/PLAN.md")
