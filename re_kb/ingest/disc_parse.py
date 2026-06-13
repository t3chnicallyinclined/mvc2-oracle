#!/usr/bin/env python3
"""
disc_parse.py — CATALOG the MVC2 Dev Files disc + the decoded PLDAT structure
into structured JSON. This is RE METADATA ONLY — a manifest of WHAT files exist
and the FORMAT of the character data. It NEVER reads or emits a single ROM byte
(file names + sizes + the documented layout are RE facts, not copyrighted data).

Sources (relative to the repo root, configurable via --disc / --pldat):
  "MVC2 Dev Files/"        -> the 866 .BIN disc files. Grouped by filename prefix
                             into file families (ADX_=audio, ATCK=attack-data,
                             PL*=character data, STG=stage, DM=demo, 1ST_READ=exe,
                             *TEX/*POL=textures/polys, HIT*=hitboxes, LIB/YOK/...
                             =per-char libs). Emits one dataformat per family
                             (name/count/total-size/purpose — NOT the bytes).
  dasm_PLDAT/Output/       -> the DECODED PLDAT structure. The disassembler
                             (dasm_PLDAT_v005a.py) splits each PLxx_DAT.BIN into
                             GFX_DATA_00/01 (parts), PALETTE_DATA, ANIMATION_DATA,
                             EXTRAS_DATA (cells/OAM), HITBOX/ATTACK/AI. Emits a
                             dataformat per section + the top-level PLDAT header
                             pointer table (offsets 0x00..0x34), linked to the
                             existing GFX1/GFX2 fields.

Output: data/disc_catalog.json
  { sources:[...],
    families:[{prefix, count, total_bytes, sample, purpose}],
    pldat_header:[{offset, name, note}],
    pldat_sections:[{name, file_suffix, char_count, layout}] }

Usage:
  python disc_parse.py                  # catalog Dev Files + dasm_PLDAT output
  python disc_parse.py --disc PATH      # different "MVC2 Dev Files" dir
  python disc_parse.py --pldat PATH     # different dasm_PLDAT root
"""
import os
import re
import sys
import glob
import argparse

import common

REPO = os.path.abspath(os.path.join(common.HERE, "..", "..", ".."))
DEFAULT_DISC = os.path.join(REPO, "MVC2 Dev Files")
DEFAULT_PLDAT = os.path.join(REPO, "dasm_PLDAT")

# prefix -> human purpose for the known Dev-Files families. Matched longest-first.
FAMILY_PURPOSE = [
    ("1ST_READ", "main SH4 executable (the game binary)"),
    ("ADX_S", "ADX streamed stage BGM (per-stage music)"),
    ("ADX_", "ADX audio (BGM / voice / jingles)"),
    ("AICADRV", "AICA sound driver"),
    ("ATCK", "per-character attack / frame data tables"),
    ("HIT_FM", "hitbox frame-meta tables"),
    ("HIT_DT", "hitbox data tables"),
    ("HIT", "hitbox tables"),
    ("PL", "per-character data (PLDAT sprite/anim/palette + FAC/VOI/WIN/TBL/PAK)"),
    ("STG", "stage data (background / scene)"),
    ("DM", "demo / attract-mode playback data"),
    ("LIB", "shared character library data"),
    ("YOK", "per-character data table (YOK family)"),
    ("WARI", "per-character data table (WARI family)"),
    ("TAIKI", "per-character idle/standby data (TAIKI family)"),
    ("SE_", "sound effects"),
    ("SELTEX", "character-select textures"),
    ("SELVM", "character-select VMU data"),
    ("FONT", "font texture data"),
    ("ENDDCTEX", "ending textures"),
    ("EFKYTEX", "effect/key texture data"),
    ("EFKYPOL", "effect/key polygon data"),
    ("DEBUG", "debug build data"),
    ("IP", "IP.BIN disc boot header"),
]

# the PLDAT top-level header pointer table (from dasm_PLDAT_v005a.py comments).
PLDAT_HEADER = [
    ("0x00", "gfx_pointer01", "-> GFX1 part-pixel block (Dat_GFX1; decoded sprite parts)"),
    ("0x04", "gfx_pointer02", "-> GFX2 block (Dat_GFX2; secondary parts/cells)"),
    ("0x08", "palette_pointer", "-> PALETTE block (ARGB4444, 16-color rows, idx0=transparent)"),
    ("0x0C", "extras_pointer", "-> EXTRAS / sprite-assembly (OAM) table"),
    ("0x10", "separation_blank", "padding/separator"),
    ("0x14", "animations", "-> ANIMATION_DATA (per-frame durations + EXTRAS ptr table)"),
    ("0x18", "hitbox_pattern_table", "-> hitbox pattern table"),
    ("0x1C", "hitbox_data", "-> hitbox data"),
    ("0x20", "attack_data", "-> attack data"),
    ("0x24", "ai_script_00", "-> AI script 0"),
    ("0x28", "ai_script_01", "-> AI script 1"),
    ("0x2C", "ai_script_02", "-> AI script 2"),
    ("0x30", "ai_script_03", "-> AI scripts (likely)"),
    ("0x34", "ai_script_04", "-> AI script 3"),
    ("0x38", "separation_blank", "padding/separator"),
    ("0x3C", "separation_blank", "padding/separator"),
]

# decoded PLDAT section files the disassembler emits, + the known layout.
PLDAT_SECTIONS = [
    ("GFX1", "GFX_DATA_00",
     "u32 LE offset table -> variable-length 4bpp sprite PARTS (piece header "
     "[w_tiles][h_tiles][padded_w][padded_h]; transparency-aware 4bpp stream; "
     "idx0=transparent). ~1533 pieces in PL00. RLE control codec still unsolved."),
    ("GFX2", "GFX_DATA_01",
     "secondary GFX block (additional parts/cells); same offset-table + 4bpp "
     "part encoding as GFX1."),
    ("PALETTE", "PALETTE_DATA",
     "palette table: N rows x 16 colors x 2B ARGB4444 LE, idx0=transparent "
     "(PL00 = 57 palettes / 1824 B). Same banks as the PVR skin system."),
    ("ANIMATION", "ANIMATION_DATA",
     "0x000-0x3FF header w/ per-frame durations (03E8=1000); 0x400+ = u32 LE "
     "pointer table into EXTRAS (random-access frame index)."),
    ("EXTRAS", "EXTRAS_DATA",
     "sprite-assembly / OAM table: 8-byte records [x:s16][y:s16][tile:u16]"
     "[attr:u16]; attr=0x00FF = frame terminator; attr bit15=h-flip; low byte "
     "= palette row. PL00 = 31 frames, 12-147 parts each."),
    ("HITBOX", "HITBOX_DATA",
     "hitbox data + HITBOX_PATTERN_TABLE; frame-accurate collision boxes."),
    ("ATTACK", "ATTACK_DATA",
     "per-frame attack / damage / properties data."),
    ("AI_SCRIPT", "AI_SCRIPT_DATA_00..04",
     "AI behaviour scripts (5 slots per character)."),
]


def _slug(s):
    return re.sub(r"[^a-z0-9]+", "_", str(s).lower()).strip("_")[:80]


def _purpose_for(name):
    for prefix, purpose in FAMILY_PURPOSE:
        if name.startswith(prefix):
            return prefix, purpose
    return None, None


def catalog_disc(disc_dir):
    """Group the .BIN files into families. Returns [{prefix,count,bytes,...}]."""
    if not os.path.isdir(disc_dir):
        return [], 0, 0
    # case-insensitive filesystems (Windows) match *.BIN and *.bin to the same
    # files — de-dup by lowercased absolute path so we count each file once.
    _seen = {}
    for p in glob.glob(os.path.join(disc_dir, "*.BIN")) + \
            glob.glob(os.path.join(disc_dir, "*.bin")):
        _seen.setdefault(os.path.normcase(os.path.abspath(p)), p)
    bins = sorted(_seen.values())
    fam = {}          # prefix -> {count, bytes, samples}
    unknown = []
    total = 0
    for p in bins:
        name = os.path.basename(p)
        try:
            sz = os.path.getsize(p)
        except OSError:
            sz = 0
        total += sz
        prefix, purpose = _purpose_for(name)
        if prefix is None:
            unknown.append(name)
            prefix, purpose = "MISC", "uncategorised disc file"
        f = fam.setdefault(prefix, {
            "prefix": prefix, "purpose": purpose,
            "count": 0, "total_bytes": 0, "samples": []})
        f["count"] += 1
        f["total_bytes"] += sz
        if len(f["samples"]) < 4:
            f["samples"].append(f"{name} ({sz}B)")
    families = sorted(fam.values(), key=lambda x: -x["count"])
    return families, len(bins), total


def catalog_pldat(pldat_root):
    """Count decoded PLxx_DAT output dirs. Returns (char_dirs, palette_count)."""
    out = os.path.join(pldat_root, "Output")
    if not os.path.isdir(out):
        return [], 0
    dat_dirs = sorted(
        d for d in glob.glob(os.path.join(out, "PL*_DAT"))
        if os.path.isdir(d))
    char_dirs = [os.path.basename(d) for d in dat_dirs]
    pal = glob.glob(os.path.join(out, "paletteData", "*PALETTE_DATA.BIN"))
    return char_dirs, len(pal)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--disc", default=DEFAULT_DISC, help='"MVC2 Dev Files" dir')
    ap.add_argument("--pldat", default=DEFAULT_PLDAT, help="dasm_PLDAT root")
    args = ap.parse_args(argv)

    families, nbins, total_bytes = catalog_disc(args.disc)
    char_dirs, npal = catalog_pldat(args.pldat)

    sources = []
    if nbins:
        sources.append({
            "slug": "disc_mvc2_devfiles", "kind": "disc",
            "ref": "MVC2 Dev Files/",
            "note": (f"MVC2 Dreamcast disc 'Dev Files' dump — {nbins} .BIN files, "
                     f"{len(families)} families, {total_bytes // (1024*1024)} MB. "
                     "RE catalog only (file inventory, not ROM bytes)."),
        })
    if char_dirs:
        sources.append({
            "slug": "pldat_decoded", "kind": "pldat",
            "ref": "dasm_PLDAT/Output/",
            "note": (f"PLDAT decoded structure (dasm_PLDAT_v005a.py) — "
                     f"{len(char_dirs)} PLxx_DAT dirs, {npal} palette dumps. "
                     "Format catalog (GFX1/GFX2/PALETTE/ANIM/EXTRAS/HITBOX/ATTACK)."),
        })

    data = {
        "source": "disc",
        "disc_dir": args.disc,
        "pldat_root": args.pldat,
        "bin_count": nbins,
        "total_bytes": total_bytes,
        "char_dir_count": len(char_dirs),
        "palette_count": npal,
        "sources": sources,
        "families": families,
        "pldat_header": [
            {"offset": o, "name": n, "note": note} for o, n, note in PLDAT_HEADER],
        "pldat_sections": [
            {"name": nm, "file_suffix": sfx, "char_count": len(char_dirs),
             "layout": lay}
            for nm, sfx, lay in PLDAT_SECTIONS],
    }
    p = common.write_json("disc_catalog.json", data)
    print(f"disc_parse -> {p}")
    print(f"  bins={nbins} families={len(families)} "
          f"total={total_bytes // (1024*1024)}MB "
          f"pldat_dirs={len(char_dirs)} palettes={npal} "
          f"sections={len(data['pldat_sections'])}")


if __name__ == "__main__":
    main(sys.argv[1:])
