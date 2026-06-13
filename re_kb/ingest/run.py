#!/usr/bin/env python3
"""
run.py — orchestrate the full RE-KB ingestion pipeline. Idempotent + re-runnable.

  crawl anotak (PL00 by default) -> parse -> (LLM label) -> ingest
  parse marvelous2 symbols       -> (LLM label) -> ingest
  parse repo RE docs + memory    -> ingest          (--docs)
  catalog MVC2 Dev Files + PLDAT -> ingest          (--disc)
  dedup edges

Network fetches are cached (re-runs hit cache, never the network). KB writes are
all UPSERT/RELATE (safe to repeat); edges are deduped at the end.

Usage:
  python run.py                       # PL00 + marvelous2 (the proof run)
  python run.py --chars PL00 PL2A     # specific chars
  python run.py --all-chars           # every char discovered from the anotak index
  python run.py --marv-routines       # also enumerate + ingest loc_ routine PCs
  python run.py --docs                # also parse + ingest repo RE docs + memory
  python run.py --disc                # also catalog MVC2 Dev Files + PLDAT format
  python run.py --all-local           # marvelous2 + docs + disc (no network) + PL00
  python run.py --no-label            # force [needs-curation] notes (skip LLM)
"""
import sys
import argparse

import anotak_crawl
import marv_parse
import docs_parse
import disc_parse
import ingest
import label
import common


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--chars", nargs="*", default=["PL00"],
                    help="PLxx ids (default PL00)")
    ap.add_argument("--all-chars", action="store_true",
                    help="discover + crawl every char from the anotak index")
    ap.add_argument("--marv-routines", action="store_true",
                    help="also parse + ingest loc_ routine PCs from build/*.asm")
    ap.add_argument("--docs", action="store_true",
                    help="also parse + ingest repo RE docs + auto-memory")
    ap.add_argument("--disc", action="store_true",
                    help="also catalog + ingest MVC2 Dev Files + PLDAT format")
    ap.add_argument("--all-local", action="store_true",
                    help="marvelous2 + docs + disc (all local, no network)")
    ap.add_argument("--no-label", action="store_true",
                    help="skip the LLM-label layer")
    args = ap.parse_args(argv)

    do_docs = args.docs or args.all_local
    do_disc = args.disc or args.all_local

    do_label = (not args.no_label) and label.have_llm()
    print("=" * 60)
    print(f"RE-KB ingestion pipeline | LLM labeling: "
          f"{'ON (' + label.MODEL + ')' if do_label else 'OFF (curation flags)'}")
    print(f"KB: {common.KB_URL}  ns={common.KB_NS} db={common.KB_DB}")
    print("=" * 60)

    # ---- 1. anotak: crawl (cache-first) -------------------------------------
    if args.all_chars:
        chars = anotak_crawl.discover_chars()
        print(f"[run] discovered {len(chars)} chars from index")
    else:
        chars = [c.upper() for c in args.chars]

    print("\n--- anotak crawl ---")
    anotak_crawl.crawl_fields()          # shared field-semantics dict (cached)
    for pl in chars:
        print(f"== {pl} ==")
        anotak_crawl.crawl_char(pl)

    # ---- 2. marvelous2: parse ----------------------------------------------
    print("\n--- marvelous2 parse ---")
    marv_parse.main(["--routines"] if args.marv_routines else [])

    # ---- 2b. docs + disc: parse (all local, no network) --------------------
    if do_docs:
        print("\n--- docs parse ---")
        docs_parse.main([])
    if do_disc:
        print("\n--- disc parse ---")
        disc_parse.main([])

    # ---- 3. ingest (with optional LLM labeling) -----------------------------
    print("\n--- ingest -> KB ---")
    ingest_args = ["--anotak", *chars, "--marv"]
    if do_docs:
        ingest_args.append("--docs")
    if do_disc:
        ingest_args.append("--disc")
    if args.no_label:
        ingest_args.append("--no-label")
    ingest_args.append("--dedup")
    ingest.main(ingest_args)

    print("\n[run] pipeline complete.")


if __name__ == "__main__":
    main(sys.argv[1:])
