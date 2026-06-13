#!/usr/bin/env python3
"""
anotak_crawl.py — CAREFUL crawler for the anotak MVC2 attack/animation data.

Source: https://zachd.com/mvc2/data/anotak/   (community RE resource — be polite)

What it does, per character (PLxx):
  1. PLxx_DAT_atk.html      -> attack-data table + char-stat ("Other Data") table
                              + the list of animation-group links/names/entry-counts.
  2. PLxx_DAT_animgroupN.html-> per-group cells (anim num, sprite id, duration, flags...).
  3. (once, global) possible_anim.html + each possible_anim_<Field>.html
                              -> the animation field-semantics dictionary
                                 (field -> enumerated value meanings).

Every fetched page is CACHED to cache/anotak/ and fetched AT MOST ONCE.
Re-runs are served entirely from cache (no network). Network requests are
rate-limited to >=1s and use a polite User-Agent. Errors are caught per-page
so one bad page doesn't abort the crawl.

Output: data/anotak_PLxx.json  (one per character)
        data/anotak_fields.json (the global field-semantics dict, once)

Usage:
  python anotak_crawl.py PL00            # crawl one char
  python anotak_crawl.py PL00 PL2A ...   # several
  python anotak_crawl.py --all           # discover + crawl every char from index
  python anotak_crawl.py --fields        # (re)build the field-semantics dict only
"""
import re
import sys
import argparse

from bs4 import BeautifulSoup

import common

BASE = "https://zachd.com/mvc2/data/anotak/"


def fetch(page):
    """Fetch a page under BASE by filename; returns soup or None on error."""
    url = BASE + page
    try:
        text, cached = common.careful_fetch(url, subdir="anotak")
        tag = "cache" if cached else "NET "
        print(f"  [{tag}] {page}")
        return BeautifulSoup(text, "html.parser")
    except Exception as e:  # noqa: BLE001 — be resilient, log, continue
        print(f"  [ERR ] {page}: {e}", file=sys.stderr)
        return None


def _cells(row):
    return [c.get_text(" ", strip=True) for c in row.find_all(["td", "th"])]


def _table_to_dicts(table):
    """First row = header; following rows = dict keyed by header."""
    rows = table.find_all("tr")
    if not rows:
        return []
    header = _cells(rows[0])
    out = []
    for r in rows[1:]:
        cells = _cells(r)
        if not any(cells):
            continue
        out.append({header[i] if i < len(header) else f"col{i}": cells[i]
                    for i in range(len(cells))})
    return out


# ---- index discovery -------------------------------------------------------
def discover_chars():
    """Return ordered list of PLxx ids linked from index.html."""
    soup = fetch("index.html")
    if soup is None:
        return []
    seen, chars = set(), []
    for a in soup.find_all("a", href=True):
        m = re.match(r"(PL[0-9A-Fa-f]{2})_DAT_atk\.html", a["href"])
        if m:
            pl = m.group(1).upper()
            if pl not in seen:
                seen.add(pl)
                chars.append(pl)
    return chars


# ---- per-character atk page ------------------------------------------------
def crawl_char(pl):
    """Crawl PLxx_DAT_atk.html + its animation groups. Returns a dict."""
    pl = pl.upper()
    atk = fetch(f"{pl}_DAT_atk.html")
    if atk is None:
        return None

    rec = {"char": pl, "name": None, "attacks": [], "stats": [], "anim_groups": []}
    title = atk.title.string if atk.title else ""
    # H1 is the character name ("Ryu")
    h1 = atk.find("h1")
    rec["name"] = h1.get_text(strip=True) if h1 else (title.split(" MVC2")[0] if title else pl)

    # Section tables: under "Attack Data" and "Other Data" headings.
    # Heuristic: a table whose header row contains 'attack number' = attacks;
    # a table whose header contains 'Converted Value' = char stats.
    for t in atk.find_all("table"):
        rows = t.find_all("tr")
        if not rows:
            continue
        hdr = [c.lower() for c in _cells(rows[0])]
        if "attack number" in hdr:
            rec["attacks"] = _table_to_dicts(t)
        elif "converted value" in hdr:
            rec["stats"] = _table_to_dicts(t)

    # Animation-group links: PLxx_DAT_animgroupN.html (+ optional text name).
    groups = {}
    for a in atk.find_all("a", href=True):
        m = re.match(rf"{pl}_DAT_animgroup(\d+)\.html$", a["href"])
        if m:
            gnum = int(m.group(1))
            groups.setdefault(gnum, a.get_text(" ", strip=True))
    for gnum in sorted(groups):
        g = crawl_animgroup(pl, gnum)
        if g:
            rec["anim_groups"].append(g)

    common.write_json(f"anotak_{pl}.json", rec)
    print(f"  -> {pl}: {len(rec['attacks'])} attacks, {len(rec['stats'])} stats, "
          f"{len(rec['anim_groups'])} anim groups")
    return rec


def crawl_animgroup(pl, gnum):
    """One PLxx_DAT_animgroupN.html -> group meta + cell list."""
    soup = fetch(f"{pl}_DAT_animgroup{gnum}.html")
    if soup is None:
        return None
    g = {"group_num": gnum, "name": None, "entry_count": None, "cells": []}
    h = soup.find(["h1", "h2", "h3"])
    if h:
        txt = h.get_text(" ", strip=True)
        # e.g.  'Animation Group #0 "walking & standing stuff": 8 entries'
        mn = re.search(r'"([^"]+)"', txt)
        if mn:
            g["name"] = mn.group(1)
        mc = re.search(r"(\d+)\s+entries", txt)
        if mc:
            g["entry_count"] = int(mc.group(1))

    # Each keyframe table has a header containing 'anim num' + 'Sprite'.
    for t in soup.find_all("table"):
        rows = t.find_all("tr")
        if not rows:
            continue
        hdr = [c.lower() for c in _cells(rows[0])]
        if "anim num" in hdr or "sprite" in hdr:
            for kf in _table_to_dicts(t):
                # normalise the handful of fields we care about
                g["cells"].append({
                    "anim": kf.get("anim num", ""),
                    "sprite_id": kf.get("Sprite", ""),
                    "duration": kf.get("Duration", ""),
                    "anim_flags": kf.get("AnimFlags", ""),
                    "effect_trigger": kf.get("EffectTrigger", ""),
                    "render_extra": kf.get("RenderExtra", ""),
                    "hitbox_group": kf.get("HitboxGroup", ""),
                    "address": kf.get("address", ""),
                })
    return g


# ---- global field-semantics dictionary -------------------------------------
def crawl_fields():
    """
    Build the animation field-semantics dictionary from possible_anim.html
    and each linked possible_anim_<Field>.html (value-enum table only).
    The per-field pages also carry a huge char x entry cross-reference; we
    deliberately keep ONLY the Value/Hex/Characters/Entries summary rows.
    """
    index = fetch("possible_anim.html")
    if index is None:
        return {}
    fields = {}
    field_links = []
    for a in index.find_all("a", href=True):
        m = re.match(r"possible_anim_([A-Za-z0-9]+)\.html$", a["href"])
        if m:
            field_links.append((m.group(1), a["href"]))

    for fname, href in field_links:
        soup = fetch(href)
        if soup is None:
            fields[fname] = {"values": []}
            continue
        values = []
        for t in soup.find_all("table"):
            rows = t.find_all("tr")
            if not rows:
                continue
            hdr = [c.lower() for c in _cells(rows[0])]
            if "value" in hdr and "hex" in hdr:
                for row in _table_to_dicts(t):
                    values.append({
                        "name": row.get("Value", ""),
                        "hex": row.get("Hex", ""),
                        "characters": row.get("Characters", ""),
                        "entries": row.get("Entries", ""),
                    })
                break
        fields[fname] = {"values": values}

    common.write_json("anotak_fields.json", fields)
    print(f"  -> field-semantics: {len(fields)} fields "
          f"({sum(len(v['values']) for v in fields.values())} enumerated values)")
    return fields


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("chars", nargs="*", help="PLxx ids to crawl (e.g. PL00)")
    ap.add_argument("--all", action="store_true", help="crawl every char from index")
    ap.add_argument("--fields", action="store_true", help="(re)build field dict only")
    args = ap.parse_args(argv)

    if args.fields and not args.chars and not args.all:
        crawl_fields()
        return

    if args.all:
        chars = discover_chars()
        print(f"Discovered {len(chars)} characters from index.")
    else:
        chars = args.chars or ["PL00"]

    crawl_fields()  # cheap on re-run (cached); shared by all chars
    for pl in chars:
        print(f"== {pl} ==")
        crawl_char(pl)


if __name__ == "__main__":
    main(sys.argv[1:])
