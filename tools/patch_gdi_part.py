#!/usr/bin/env python3
"""Patch one GFX1 part inside a character DAT, in place, in a COPY of the GDI.

Usage:
  patch_gdi_part.py                      # default: PL2C (Magneto) part 484 -> white
  patch_gdi_part.py PL17 47 0xFF         # Cable part 47 -> idx15 (both nibbles)

MVP: solid-fill a part with a palette index (twiddle-invariant) so the edit is
visible from the disc on a real emulator / Dreamcast. Keeps the DAT the same SIZE
(re-encoded blob padded to the original slot length), so no ISO9660 / GDI rebuild
is needed — we overwrite only the changed sectors' user data. Multiple chars can
be patched into the same image (track copy is reused if already present).

Leaves Mode-1 EDC/ECC stale (fine for flycast; regenerate for burned hardware).
NEVER writes the source ROM — always operates on a fresh copy.
"""
import os, sys, struct, shutil
sys.path.insert(0, os.path.dirname(__file__))
from gfx1_lzss import decodeA, encodeA

SRC_DIR = r"C:\roms\mvc2_us"
DST_DIR = r"C:\roms\mvc2_us_patched"
TRACK   = "track03.bin"
RAW     = 2352
BASE    = 45000           # track03 start LBA (from .gdi)


def _user(path, abs_lba):
    with open(path, "rb") as f:
        f.seek((abs_lba - BASE) * RAW + 16)
        return f.read(2048)


def find_dat(path, charname):
    """Resolve <charname>_DAT.BIN -> (lba, size) from the ISO9660 root dir."""
    pvd = _user(path, BASE + 16)
    rl = struct.unpack_from("<I", pvd, 156 + 2)[0]
    rn = struct.unpack_from("<I", pvd, 156 + 10)[0]
    d = b"".join(_user(path, rl + i) for i in range((rn + 2047) // 2048))
    off = 0
    target = (charname.upper() + "_DAT")
    while off < rn:
        L = d[off]
        if L == 0:
            off = ((off // 2048) + 1) * 2048
            if off >= rn:
                break
            continue
        e = struct.unpack_from("<I", d, off + 2)[0]
        ln = struct.unpack_from("<I", d, off + 10)[0]
        nl = d[off + 32]
        nm = d[off + 33:off + 33 + nl].decode('ascii', 'replace')
        if nm.upper().startswith(target):
            return e, ln
        off += L
    raise SystemExit("DAT not found for %s" % charname)


def desector(path, lba, size):
    out = bytearray()
    for i in range((size + 2047) // 2048):
        out += _user(path, lba + i)
    return bytes(out[:size])


def main():
    charname = sys.argv[1] if len(sys.argv) > 1 else "PL2C"
    sel      = int(sys.argv[2]) if len(sys.argv) > 2 else 484
    fill     = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x22   # both nibbles = idx

    dat_lba, dat_size = find_dat(os.path.join(SRC_DIR, TRACK), charname)
    print("%s_DAT.BIN @ LBA %d, %d bytes" % (charname, dat_lba, dat_size))

    # clone tracks + gdi (skip files already copied at the right size)
    os.makedirs(DST_DIR, exist_ok=True)
    for name in os.listdir(SRC_DIR):
        s = os.path.join(SRC_DIR, name); dd = os.path.join(DST_DIR, name)
        if not os.path.exists(dd) or os.path.getsize(dd) != os.path.getsize(s):
            print("copy", name, "..."); shutil.copy2(s, dd)
    dst_track = os.path.join(DST_DIR, TRACK)

    dat = desector(os.path.join(SRC_DIR, TRACK), dat_lba, dat_size)
    gfx1 = struct.unpack_from("<I", dat, 0)[0]
    o0 = struct.unpack_from("<I", dat, gfx1 + sel * 4)[0]
    o1 = struct.unpack_from("<I", dat, gfx1 + (sel + 1) * 4)[0]
    hdr = dat[gfx1 + o0:gfx1 + o0 + 4]; sw, sh = hdr[2], hdr[3]
    dest_len = (sw * 8) * (sh * 8) // 2
    blob_off = gfx1 + o0 + 4
    blob_len = (gfx1 + o1) - blob_off

    edit = bytes([fill]) * dest_len
    enc = encodeA(edit)
    if len(enc) > blob_len:
        raise SystemExit("patched blob %d > slot %d (needs offset-table rebuild)" % (len(enc), blob_len))
    assert decodeA(enc, dest_len) == edit
    padded = enc + b"\x00" * (blob_len - len(enc))
    print("part %d: %dx%d dest_len=%d slot=%dB re-enc=%dB fill=%#04x (fits)" %
          (sel, sw * 8, sh * 8, dest_len, blob_len, len(enc), fill))

    # overwrite blob bytes in the COPY, sector-aware (handles span)
    with open(dst_track, "r+b") as f:
        for k, byte in enumerate(padded):
            sec = (blob_off + k) // 2048; within = (blob_off + k) % 2048
            f.seek((dat_lba - BASE + sec) * RAW + 16 + within)
            f.write(bytes([byte]))

    # verify from the patched copy
    dat2 = desector(dst_track, dat_lba, dat_size)
    o0 = struct.unpack_from("<I", dat2, gfx1 + sel * 4)[0]
    o1 = struct.unpack_from("<I", dat2, gfx1 + (sel + 1) * 4)[0]
    px = decodeA(dat2[gfx1 + o0 + 4:gfx1 + o1], dest_len)
    print("VERIFY: %s part %d decodes all-%#04x: %s (size unchanged: %s)" %
          (charname, sel, fill, px == edit, len(dat2) == dat_size))
    gdi = [n for n in os.listdir(DST_DIR) if n.lower().endswith(".gdi")]
    print("Load in flycast: %s" % os.path.join(DST_DIR, gdi[0] if gdi else "<.gdi>"))


if __name__ == "__main__":
    main()
