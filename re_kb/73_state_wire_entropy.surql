USE NS re DB kb;

-- ============================================================================
-- 2026-07-10 — THE STATE WIRE IS 99.9% WASTE. Measured, byte-exact-proven.
-- Reshapes the whole stream-consolidation + low-latency plan.
-- ============================================================================

UPSERT source:state_wire_churn_measure SET kind='measurement',
  ref='scratchpad/churn.mjs + delta_proof.mjs over tools/render-replica-poc/{fwdback,rocket,torture,band4}.mcrr (9600 frames total)',
  note='Parsed the .mcrr dynamic-region blobs and diffed consecutive frames. The /replica-live state wire ships the WHOLE dynamic-region span every frame (214172 B, or ~300412 B incl the 7 efxtmpl arenas during a super), zstd-1 -> ~0.37 Mbps measured. The ACTUAL frame-to-frame CHANGE is ~120-200 bytes/frame (0.1% of raw) across ALL captures incl under load (rocket projectile, torture supers, busy band). Per-region: objpool 39.5% of raw but changes ~50B across 4.8 scattered pages; efxtmpl 28.6% raw but 0 change when no super; rectab 21.8% raw but ~13B change. cam_mat/camZ/idxtab/rmode: literally 0 change over thousands of frames.';

UPSERT finding:state_wire_entropy SET
  statement='CONFIRMED (measured 2026-07-10, 9600 frames). MVC2 per-frame render STATE entropy = ~150 changed bytes/frame (0.1% of the 214KB whole-region ship). A changed-BYTE-RUN delta vs the previous frame (gap-merge<8B) reconstructs BYTE-IDENTICAL (0 mismatches / 9600 frames) at ~350-390 B/frame gzip (worst single frame 4518B during a rocket spawn) = ~0.17-0.19 Mbps, ~HALF the current whole-region zstd wire AND collapses server compress (memcmp+zstd 600B vs zstd 214KB/frame). CRITICAL COROLLARY: page-granularity delta (the render wires 4KB dirty-page model) is WRONG for this data — the ~150 changed bytes scatter across ~12 pages -> 49KB/frame, 300x worse than byte-run. The whole objpool(118KB)/efxtmpl(86KB)/rectab(64KB) region-SIZE debate is MOOT once delta-coded: you only ship what changed, so inactive pool nodes + idle effect templates cost 0. IMPLICATION FOR CONSOLIDATION: the entire state stream folds into the ZCS2 render packet for ~370 B/frame -> the two-socket merge (one vframe, fixes the body(V)/wire(V-1) pairing-drift garble = fwd/back + down-flicker) has NO bandwidth cost. IMPLICATION FOR LATENCY: the true information content of a live MVC2 frame is ~150 bytes; the wire can approach that (state-only + client-side reconstruction), the users everything-in-cache/tiny-wire thesis.',
  status='confirmed', confidence='high', date='2026-07-10';

RELATE finding:state_wire_entropy->cites->source:state_wire_churn_measure;
