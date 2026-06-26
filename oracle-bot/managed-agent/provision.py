#!/usr/bin/env python3
"""
Provision the MvC2 Oracle as a Managed Agent (control plane — run ONCE).

Creates:
  1. a cloud environment
  2. a memory store `mvc2-re-kb`, seeded with the re_kb/*.surql findings + the key docs
  3. the Oracle agent (model + persona + built-in toolset, web tools off)

Writes the resulting IDs to oracle_ids.json. run_session.py reads that to start sessions.
Re-running is safe-ish: existing-by-name resources are reused, existing memory files are skipped.

    pip install anthropic
    set ANTHROPIC_API_KEY=...        (must be a FUNDED key for this workspace)
    python provision.py
"""
import os
import sys
import json
from pathlib import Path

try:
    import anthropic
except ImportError:
    sys.exit("pip install anthropic")

HERE = Path(__file__).resolve().parent
REKB_DIR = Path(os.environ.get("REKB_DIR", r"C:/Users/trist/projects/mvc2-oracle/re_kb"))
DOCS_DIR = Path(os.environ.get("ORACLE_DOCS", r"C:/Users/trist/projects/mvc2-oracle/docs"))
MODEL = os.environ.get("ORACLE_MODEL", "claude-opus-4-8")
STORE_NAME = "mvc2-re-kb"            # MUST match the /mnt/memory/<name> path in the persona
CONTEXT_DOCS = ["MVC2-MEMORY-MAP.md", "MVC2-FRAMEDATA-FIELDS.md", "ASSEMBLY-DRIVEN-DESIGN.md",
                "PART-ASSEMBLY-PLAN.md", "PER-OBJECT-QUAD-SPEC.md", "MARVELOUS2-GFX-NOTES.md",
                "MVC2-WIRE-GAP-ANALYSIS.md", "FRAME-ORACLE-SPEC.md", "MARVELOUS2-RE-HANDOFF.md",
                "GSTA-MAPPING-HANDOFF.md"]
# Public-safe RE/render docs that live only in the maplecast-flycast tree (curated — infra docs EXCLUDED).
MAPLECAST_DOCS_DIR = Path(os.environ.get("MAPLECAST_DOCS", r"C:/Users/trist/projects/maplecast-flycast/docs"))
MAPLECAST_DOCS = ["MVC2-RECONSTRUCTION-SPEC.md", "MVC2-RIPPER-DESIGN.md", "SKIN-SYSTEM.md",
                  "BAKE-HARNESS-PLAN.md", "WEBGPU-RENDERER.md"]
# Clean NOBD context (FGC fairness precedent). Most nobd-research is RESEARCH-RAW (retired claims) — the
# bot's NOBD spine is the curated knowledge/nobd-knowledge.md, NOT the raw research.
NOBD_RESEARCH = Path(os.environ.get("NOBD_RESEARCH", r"C:/Users/trist/projects/nobd-research"))
NOBD_EXTRA = ["02-domain-research/input-history-and-fairness.md"]
RENDER_EXPERT = Path(os.environ.get("RENDER_EXPERT",
    r"C:/Users/trist/projects/maplecast-flycast/.claude/agents/mvc2-sprite-render-expert.md"))
NOBD_KNOWLEDGE = HERE.parent / "knowledge" / "nobd-knowledge.md"
NOBD_DESKTOP = HERE.parent / "knowledge" / "nobd-desktop.md"
NOBD_FIRMWARE = HERE.parent / "knowledge" / "nobd-firmware.md"
NOBD_ZERO = HERE.parent / "knowledge" / "nobd-zero.md"
IDS_FILE = HERE / "oracle_ids.json"


def memory_files():
    """(path, content) pairs to seed into the memory store. Each well under the 100 KB cap."""
    out = []
    for seed in sorted(REKB_DIR.glob("*.surql")):
        out.append((f"/re_kb/{seed.name}", seed.read_text(encoding="utf-8", errors="replace")))
    for name in CONTEXT_DOCS:
        p = DOCS_DIR / name
        if p.exists():
            out.append((f"/docs/{name}", p.read_text(encoding="utf-8", errors="replace")))
    for name in MAPLECAST_DOCS:
        p = MAPLECAST_DOCS_DIR / name
        if p.exists():
            out.append((f"/docs/{name}", p.read_text(encoding="utf-8", errors="replace")))
    for rel in NOBD_EXTRA:
        p = NOBD_RESEARCH / rel
        if p.exists():
            out.append((f"/nobd/{Path(rel).name}", p.read_text(encoding="utf-8", errors="replace")))
    if RENDER_EXPERT.exists():
        out.append(("/knowledge/render-expert.md",
                    RENDER_EXPERT.read_text(encoding="utf-8", errors="replace")))
    if NOBD_KNOWLEDGE.exists():
        out.append(("/nobd/nobd-knowledge.md",
                    NOBD_KNOWLEDGE.read_text(encoding="utf-8", errors="replace")))
    if NOBD_DESKTOP.exists():
        out.append(("/nobd/nobd-desktop.md",
                    NOBD_DESKTOP.read_text(encoding="utf-8", errors="replace")))
    if NOBD_FIRMWARE.exists():
        out.append(("/nobd/nobd-firmware.md",
                    NOBD_FIRMWARE.read_text(encoding="utf-8", errors="replace")))
    if NOBD_ZERO.exists():
        out.append(("/nobd/nobd-zero.md",
                    NOBD_ZERO.read_text(encoding="utf-8", errors="replace")))
    return out


def main():
    if not os.environ.get("ANTHROPIC_API_KEY"):
        sys.exit("Set ANTHROPIC_API_KEY (funded) first.")
    c = anthropic.Anthropic()
    if not hasattr(c, "beta") or not hasattr(c.beta, "agents"):
        sys.exit("This anthropic SDK build lacks Managed Agents (client.beta.agents). Upgrade: "
                 "pip install -U anthropic")

    # 1. environment (reuse by name)
    env = next((e for e in c.beta.environments.list() if e.name == "mvc2-oracle-env"), None)
    if env is None:
        env = c.beta.environments.create(
            name="mvc2-oracle-env",
            config={"type": "cloud", "networking": {"type": "unrestricted"}},
        )
        print("created environment", env.id)
    else:
        print("reusing environment", env.id)

    # 2. memory store + seed
    store = next((s for s in c.beta.memory_stores.list() if s.name == STORE_NAME), None)
    if store is None:
        store = c.beta.memory_stores.create(
            name=STORE_NAME,
            description="MvC2 re_kb findings (routines, fields, provenance) + memory map + "
                        "frame-data field tables. The Oracle's grounded knowledge base.",
        )
        print("created memory store", store.id)
    else:
        print("reusing memory store", store.id)
    existing = {}
    for m in c.beta.memory_stores.memories.list(store.id):
        if getattr(m, "type", "memory") == "memory":
            existing[m.path] = m.id
    created = updated = 0
    for path, content in memory_files():
        if path in existing:
            c.beta.memory_stores.memories.update(existing[path], memory_store_id=store.id, content=content)
            updated += 1
        else:
            c.beta.memory_stores.memories.create(store.id, path=path, content=content)
            created += 1
    print(f"memory: {created} created, {updated} updated")

    # 3. agent — create once, then UPDATE in place (bumps version) on re-provision
    persona = (HERE / "system_prompt_cma.md").read_text(encoding="utf-8", errors="replace")
    tools = [{
        "type": "agent_toolset_20260401",
        "default_config": {"enabled": True},
        "configs": [
            {"name": "web_search", "enabled": False},
            {"name": "web_fetch", "enabled": False},
        ],
    }]
    existing = next((a for a in c.beta.agents.list() if a.name == "MvC2 Oracle"), None)
    if existing:
        agent = c.beta.agents.update(existing.id, version=existing.version,
                                     system=persona, model=MODEL, tools=tools)
        print("updated agent", agent.id, "-> version", agent.version)
    else:
        agent = c.beta.agents.create(name="MvC2 Oracle", model=MODEL, system=persona, tools=tools)
        print("created agent", agent.id, "version", agent.version)

    IDS_FILE.write_text(json.dumps({
        "agent_id": agent.id,
        "agent_version": agent.version,
        "environment_id": env.id,
        "memory_store_id": store.id,
        "memory_store_name": STORE_NAME,
    }, indent=2))
    print("wrote", IDS_FILE)


if __name__ == "__main__":
    main()
