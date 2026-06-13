#!/usr/bin/env python3
"""
compare_naomi_dc.py — Compare PLxx character data between the Naomi arcade ROM
and the Dreamcast GD-ROM port of MVC2.

Answers: are the sprite/animation assets identical, or does Naomi have different
(higher-quality) data?

USAGE
  python3 tools/compare_naomi_dc.py \
    --dc  "C:/Users/trist/Downloads/flycast-dojo-6.53/ROMs/mvsc2.zip" \
    --naomi "C:/Users/trist/Downloads/flycast-dojo-6.53/ROMs/mvsc2.zip.naomi"

HOW IT WORKS
  DC side:
    - Opens mvsc2.zip, extracts track03.bin (the ISO9660 data track)
    - Walks the ISO9660 filesystem to find PLxx_TBL.BIN files
    - Reports name, size, SHA1 for each

  Naomi side:
    - Opens mvsc2.zip.naomi, reads the 14 mask ROM blobs (mpr-23048..mpr-23061)
    - Deinterleaves each ic*s (odd bytes) + ic* (even bytes) pair into a 16MB block
    - Concatenates 7 blocks -> 112MB flat ROM image
    - Searches for PLxx header patterns (4 ordered LE pointers as used in DC PAK format)
    - Also searches for LZSS compressed data signatures
    - Reports any hits and their sizes

  Comparison:
    - For each DC PLxx file, searches the flat Naomi ROM for exact byte match
    - Reports: IDENTICAL / SIMILAR (same size, different content) / NOT FOUND
"""
import argparse, hashlib, io, os, struct, zipfile

# ─── ISO 9660 minimal reader ──────────────────────────────────────────────────

SECTOR      = 2048
RAW_SECTOR  = 2352
RAW_HEADER  = 16   # 12-byte sync + 3-byte address + 1-byte mode

def _iso_str(b):
    return b.rstrip(b'\x00 ').decode('ascii', errors='replace')

GDI_TRACK3_LBA = 45000  # GD-ROM high-density area starts here; track03.bin offset 0 = LBA 45000

def _read_sector(data, lba, raw=False):
    # lba is an absolute disc LBA; subtract the track base to get file offset
    rel = lba - GDI_TRACK3_LBA
    if rel < 0:
        rel = lba  # fallback: treat as already relative
    if raw:
        off = rel * RAW_SECTOR + RAW_HEADER
        if off + SECTOR > len(data):
            return None
        return data[off:off + SECTOR]
    off = rel * SECTOR
    if off + SECTOR > len(data):
        return None
    return data[off:off + SECTOR]

def _parse_dir(data, lba, size):
    """Yield (name, lba, size) for all entries in a directory."""
    raw = data[lba * SECTOR : lba * SECTOR + size]
    pos = 0
    while pos < len(raw):
        rec_len = raw[pos]
        if rec_len == 0:
            # advance to next sector boundary
            pos = ((pos // SECTOR) + 1) * SECTOR
            continue
        if pos + rec_len > len(raw):
            break
        rec = raw[pos:pos + rec_len]
        flags = rec[25]
        name_len = rec[32]
        name_bytes = rec[33:33 + name_len]
        name = name_bytes.decode('ascii', errors='replace').split(';')[0]  # strip version
        file_lba  = struct.unpack_from('<I', rec, 2)[0]
        file_size = struct.unpack_from('<I', rec, 10)[0]
        is_dir = bool(flags & 0x02)
        if name not in ('', '\x00', '\x01'):
            yield name, file_lba, file_size, is_dir
        pos += rec_len

def walk_iso(iso_data, pattern=None):
    """Walk ISO9660, yield (path, lba, size) for files matching pattern (case-insensitive).
    Auto-detects raw (2352-byte) vs cooked (2048-byte) sectors."""
    # Try raw sectors first (GD-ROM track03.bin uses 2352-byte sectors)
    for raw in (True, False):
        pvd = _read_sector(iso_data, 16, raw=raw)
        if pvd and pvd[0] == 1:
            break
    else:
        raise RuntimeError("No ISO9660 PVD found (tried both raw and cooked sector modes)")

    root_lba  = struct.unpack_from('<I', pvd, 158)[0]
    root_size = struct.unpack_from('<I', pvd, 166)[0]

    def _dir_data(lba, size):
        """Reassemble directory data from (possibly raw) sectors."""
        chunks = []
        n_sectors = (size + SECTOR - 1) // SECTOR
        for i in range(n_sectors):
            s = _read_sector(iso_data, lba + i, raw=raw)
            if s:
                chunks.append(s)
        return b''.join(chunks)[:size]

    def recurse(lba, size, prefix):
        raw_dir = _dir_data(lba, size)
        for name, flba, fsize, is_dir in _parse_dir(raw_dir, 0, len(raw_dir)):
            path = prefix + name
            if is_dir:
                yield from recurse(flba, fsize, path + '/')
            else:
                if pattern is None or pattern.upper() in name.upper():
                    yield path, flba, fsize

    yield from recurse(root_lba, root_size, '')


def extract_iso_file_raw(iso_data, lba, size, raw=True):
    """Extract file content from ISO, handling raw sector mode."""
    chunks = []
    n_sectors = (size + SECTOR - 1) // SECTOR
    for i in range(n_sectors):
        s = _read_sector(iso_data, lba + i, raw=raw)
        if s:
            chunks.append(s)
    return b''.join(chunks)[:size]


# ─── Naomi ROM deinterleave ───────────────────────────────────────────────────

# mpr-23048.ic17s = odd bytes, mpr-23049.ic18 = even bytes -> 16MB combined
# mpr-23050.ic19s = odd bytes, mpr-23051.ic20 = even bytes -> next 16MB  ...etc
NAOMI_PAIRS = [
    ('mpr-23048.ic17s', 'mpr-23049.ic18'),
    ('mpr-23050.ic19s', 'mpr-23051.ic20'),
    ('mpr-23052.ic21s', 'mpr-23053.ic22'),
    ('mpr-23054.ic23s', 'mpr-23055.ic24'),
    ('mpr-23056.ic25s', 'mpr-23057.ic26'),
    ('mpr-23058.ic27s', 'mpr-23059.ic28'),
    ('mpr-23061.ic30s', 'mpr-23060.ic29'),  # last pair: ic30s=odd, ic29=even
]
# Sound ROMs (not game data)
SOUND_ROMS = {'mpr-23083.ic31', 'mpr-23084.ic32s'}
# Program ROM
PROG_ROM   = 'epr-23085a.ic11'


def deinterleave_pair(odd_bytes, even_bytes):
    """Combine two 8MB chips into one 16MB block. even@0,2,4... odd@1,3,5..."""
    assert len(odd_bytes) == len(even_bytes), "ROM pair size mismatch"
    out = bytearray(len(odd_bytes) * 2)
    out[0::2] = even_bytes
    out[1::2] = odd_bytes
    return bytes(out)


def build_naomi_flat(naomi_zip_path):
    """Deinterleave all 7 data pairs -> flat 112MB ROM image. Returns bytes."""
    with zipfile.ZipFile(naomi_zip_path) as z:
        names_in_zip = {i.filename for i in z.infolist()}
        blocks = []
        for odd_name, even_name in NAOMI_PAIRS:
            # Try exact name, then try swapped (some sets use different ic numbering)
            def _read(n):
                if n in names_in_zip:
                    return z.read(n)
                # case-insensitive fallback
                for fn in names_in_zip:
                    if fn.lower() == n.lower():
                        return z.read(fn)
                raise KeyError(f"ROM chip {n!r} not found in zip")

            odd  = _read(odd_name)
            even = _read(even_name)
            blocks.append(deinterleave_pair(odd, even))
            print(f"  deinterleaved {odd_name} + {even_name} -> {len(blocks[-1])//1024//1024} MB")
    flat = b''.join(blocks)
    print(f"  total flat image: {len(flat)//1024//1024} MB")
    return flat

# ─── PLxx header pattern scanner ─────────────────────────────────────────────

# PLxx PAK header: 4 LE u32 pointers at offsets 0,4,8,12 that must be ordered
# and within [0x40, filesize]. We scan 16-byte-aligned positions.
MIN_PTR   = 0x40
MAX_BLOCK = 2 * 1024 * 1024   # 2 MB max per character blob (generous)

def scan_plxx_headers(data, min_size=0x1000):
    """Scan flat data for PLxx PAK header patterns. Yield (offset, ptrs)."""
    end = len(data) - 16
    pos = 0
    while pos < end:
        p = struct.unpack_from('<4I', data, pos)
        if (p[0] > MIN_PTR and p[1] > p[0] and p[2] > p[1]
                and p[3] > p[2] and p[3] < MAX_BLOCK
                and (p[3] - p[0]) > min_size):
            yield pos, p
            pos += p[3]   # skip past end of this block
        else:
            pos += 16


def sha1(data):
    return hashlib.sha1(data).hexdigest()[:12]

def find_exact(haystack, needle):
    """Return first offset of needle in haystack, or -1."""
    if len(needle) > len(haystack):
        return -1
    # Check every 16-byte-aligned position for the first 64 bytes
    probe = needle[:64]
    idx = 0
    while True:
        idx = haystack.find(probe, idx)
        if idx == -1:
            return -1
        if haystack[idx:idx + len(needle)] == needle:
            return idx
        idx += 1

# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="Compare MVC2 Naomi vs DC character data")
    ap.add_argument('--dc',    required=True, help='Path to DC mvsc2.zip (contains track03.bin)')
    ap.add_argument('--naomi', required=True, help='Path to Naomi ROM zip (mvsc2.zip.naomi or similar)')
    ap.add_argument('--dump-dc',  help='Dump extracted DC PLxx files to this dir')
    ap.add_argument('--filter',   help='Only process files matching this pattern (e.g. PL00)')
    args = ap.parse_args()

    # ── DC side ──
    print("\n=== DREAMCAST ISO ===")
    print(f"  Opening {args.dc} ...")
    with zipfile.ZipFile(args.dc) as z:
        names = [i.filename for i in z.infolist()]
        track = next((n for n in names if n.lower() == 'track03.bin'), None)
        if not track:
            raise RuntimeError(f"track03.bin not found in {args.dc} (files: {names})")
        print(f"  Reading {track} ({z.getinfo(track).file_size//1024//1024} MB uncompressed) ...")
        iso_data = z.read(track)

    dc_files = {}   # name -> bytes
    print(f"  Walking ISO9660 filesystem ...")
    for path, lba, size in walk_iso(iso_data, pattern='_TBL.BIN' if not args.filter else args.filter):
        name = os.path.basename(path)
        data = extract_iso_file_raw(iso_data, lba, size)
        dc_files[name] = data
        print(f"  {path:40s}  {size:8d} B  sha1={sha1(data)}")

    if not dc_files:
        print("  (no matching files found — try without --filter)")

    if args.dump_dc:
        os.makedirs(args.dump_dc, exist_ok=True)
        for name, data in dc_files.items():
            with open(os.path.join(args.dump_dc, name), 'wb') as f:
                f.write(data)
        print(f"  Dumped {len(dc_files)} files to {args.dump_dc}")

    # ── Naomi side ──
    print(f"\n=== NAOMI ROM ===")
    print(f"  Deinterleaving mask ROM pairs from {args.naomi} ...")
    naomi_flat = build_naomi_flat(args.naomi)

    print(f"\n  Scanning for PLxx PAK header patterns ...")
    hits = list(scan_plxx_headers(naomi_flat))
    print(f"  Found {len(hits)} candidate PLxx blobs in Naomi ROM")
    for i, (off, ptrs) in enumerate(hits[:60]):
        print(f"    [{i:2d}] offset=0x{off:08X}  ptrs={[hex(p) for p in ptrs]}  approx_size={ptrs[3]} B")

    # ── Comparison ──
    if dc_files and hits:
        print(f"\n=== COMPARISON ===")
        for dc_name, dc_data in sorted(dc_files.items()):
            # Search Naomi flat for exact byte match (first 256 bytes as fingerprint)
            probe = dc_data[:256] if len(dc_data) >= 256 else dc_data
            idx = naomi_flat.find(probe)
            if idx >= 0:
                naomi_slice = naomi_flat[idx:idx + len(dc_data)]
                if naomi_slice == dc_data:
                    print(f"  {dc_name:30s}  IDENTICAL  (Naomi offset=0x{idx:08X})")
                else:
                    match_bytes = sum(a == b for a, b in zip(dc_data, naomi_slice))
                    pct = 100.0 * match_bytes / len(dc_data)
                    print(f"  {dc_name:30s}  SIMILAR    ({pct:.1f}% match, Naomi offset=0x{idx:08X})")
            else:
                print(f"  {dc_name:30s}  NOT FOUND  (dc_sha1={sha1(dc_data)} size={len(dc_data)})")

    print("\nDone.")

if __name__ == '__main__':
    main()
