-- ============================================================================
-- 19: render-replica LIVE — the GFX-TRUNCATION root cause of the residual grid.
-- The 18_static_gfx_gap fix shipped each GFX region as a FIXED 0x20000 (128KB); the
-- real GFX1 reaches ~1.1MB, so the truncation left most part-blobs STALE -> scramble.
-- Pinned 2026-06-13 from the live capture (tools/render-replica-poc/maxq_86.mcrr),
-- not guessed. Supersedes finding:replica_live_static_gfx_fix's 0x20000 sizing.
-- ============================================================================
USE NS re DB kb;

UPSERT source:maxq_mcrr SET kind='capture',
  ref='tools/render-replica-poc/maxq_86.mcrr (live render-replica prefix+frames)',
  note='Live MCRR. nStatic=3 (GFX2 0x0C8FB000, GFX1 0x0C810000, ram16 0x8C000000), nDyn=14. The GFX1/GFX2 offset tables were read at their TRUE base out of the ram16 backdrop to measure the real extents.';

UPSERT source:gfx_extent_format SET kind='format',
  ref='tools/extract_gfx1_atlas.py / tools/rip_gfx2_assembly.py read_cells()/decode_part()',
  note='GFX1 (node+0x15C) and GFX2 (node+0x160) share a header: u32-LE OFFSET TABLE at the TRUE base; entry[0]=n*4 so n=entry[0]>>2 = selector count; entry[i] = byte offset of selector i block from the TRUE base. GFX2 block = [u16 count][count*8B records] (size = 2+count*8, EXACTLY headered). GFX1 block = [lw][lh][sw][sh] + LZSS stream (compressed length NOT headered).';

UPSERT finding:replica_live_gfx_extent SET
  statement='The render-replica LIVE grid/scramble that survived the 18 static-GFX-gap fix is a GFX TRUNCATION, measured on the live wire (maxq_86.mcrr): the fix shipped each GFX1/GFX2 region as a FIXED 0x20000 (128KB), but the REAL GFX1 region reaches 0x115760 (~1.13MB). PROOF from the capture: GFX1 true base 0x0C810000 has 16 offset-table entries whose part-blob offsets spread to 0x115760; under the old 0x20000 ship only 4 of 16 blobs were resident, 12 were PAST 128KB and decoded from STALE bytes. The live scramble pose (sid 680, GFX2 cell offset 0x100CC) references 11 parts, ALL 11 at GFX1 blob offsets PAST 128KB (0x328F4..0xEAD1E) -> every part of that pose decoded from truncated/stale GFX1 = the grid. GFX2 for this char (681 cells, max offset 0x100CC ~64KB) DID fit in 128KB so its cell records (geometry) were coherent; the residual scramble was purely GFX1 (pixel) truncation. SECONDARY bug found in the capture: the GFX2 TRUE base is NOT page-aligned (0x0C8FB8C0, 0x8C0 into its page); the old code page-aligned DOWN (& ~0xFFF) before reading, which lands the offset-table read off the table head (e0=0x2E431143 = invalid) -> the extent/sig MUST be read at the TRUE base node+0x160/+0x15C, then ship page-aligned-down with a len that covers from the page base to the region end.',
  status='confirmed', confidence='high', date='2026-06-13';

UPSERT finding:replica_live_gfx_extent_fix SET
  statement='FIX (server core/network/maplecast_replica_live.cpp + client web/render-replica/replay.html, committed feat/render-replica-live). SERVER: gfxExtentFromBase(trueBase,isGfx2) reads the offset table at the TRUE base (node+0x15C/+0x160): validate e0==n*4 (n=e0>>2); maxoff = max(entry[i]); GFX2 extent = maxoff + 2 + count*8 (exact, last cell-record block); GFX1 extent = maxoff + GFX1_LAST_SLACK (0x4000 > the 0x234D worst compressed-block gap measured across the roster, since the last LZSS block length is not headered). gfxShipDescriptor() ships base = trueBase & ~0xFFF, len = page_round_up((trueBase & 0xFFF) + extent), falling back to 0x20000 only if the header does not validate (never blind-truncate to 0). Applied in BOTH buildTables (static prefix) and collectFreshGfx (on-change dynamic tail). gfxSig now folds the FULL region. WIRE FORMAT CHANGE: the GFX tail goes from nGfx x {u32 base, 0x20000 bytes} to nGfx x {u32 base, u32 len, len bytes}. Compressors bumped: prefix 28->32MB, frame 6->8MB (a resend-all connect ships every active body full GFX). CLIENT: applyGfxTail reads {base,len} then ram.set(len bytes); the file-load skip-peek walks per-region lengths. render_frame.wasm UNCHANGED (walker is correct). VALIDATION (maxq_86.mcrr): ship GFX1 base 0x0C810000 len 0x11A000 COVERS offset-max 0x115760; GFX2 base 0x0C8FB000 len 0x11000 COVERS region-end 0x1098C. All 16 GFX1 blobs + all 11 pose-680 part offsets now resident (0 truncated). PER-CONNECT BANDWIDTH: real-size GFX = ~1196KB raw/body (GFX1 0x11A000 + GFX2 0x11000); GFX1 is already-LZSS-compressed so it barely re-zstds (~811KB via zlib-L1 proxy) -> ~840KB compressed/body; a 4-body resend-all on connect ~3.3MB ONE-TIME (steady state stays nGfx=0, a 4B tail).',
  status='confirmed', confidence='high', date='2026-06-13';

RELATE finding:replica_live_gfx_extent->cites->source:maxq_mcrr;
RELATE finding:replica_live_gfx_extent->cites->source:gfx_extent_format;
RELATE finding:replica_live_gfx_extent_fix->cites->source:maxq_mcrr;
RELATE finding:replica_live_gfx_extent_fix->cites->source:replica_live_cpp;
RELATE finding:replica_live_gfx_extent_fix->supersedes->finding:replica_live_static_gfx_fix;
