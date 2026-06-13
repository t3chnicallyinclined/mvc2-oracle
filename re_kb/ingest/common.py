"""
common.py — shared helpers for the RE-KB ingestion pipeline.

  * careful_fetch()  — cache-first, rate-limited, polite-UA HTTP GET.
  * kb_apply()       — POST SurrealQL (or a .surql file) to the live KB.
  * sql_str()        — SurrealQL single-quoted string escaper.
  * paths            — canonical ingest dirs (cache/ data/ generated/).

The crawler is deliberately polite: every URL is fetched at most ONCE
(cached to disk by a slugged filename); re-runs read the cache and never
touch the network. A >=1s delay is enforced between *network* requests
only (cache hits are free).
"""
import os
import re
import sys
import time
import json
import hashlib
import urllib.parse
import urllib.request
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(HERE, "cache")
DATA_DIR = os.path.join(HERE, "data")
GEN_DIR = os.path.join(HERE, "generated")
for _d in (CACHE_DIR, DATA_DIR, GEN_DIR):
    os.makedirs(_d, exist_ok=True)

USER_AGENT = "MapleCast-RE-KB/1.0"
RATE_LIMIT_SECS = 1.0          # minimum gap between *network* requests
_last_net = [0.0]              # mutable holder for last network fetch time

# ---- KB connection ---------------------------------------------------------
KB_URL = os.environ.get("REKB_URL", "http://127.0.0.1:8001/sql")
KB_AUTH = os.environ.get("REKB_AUTH", "root:root")
KB_NS, KB_DB = "re", "kb"


def url_to_cache_path(url, subdir):
    """Deterministic, human-readable cache filename for a URL."""
    name = url.rstrip("/").split("/")[-1] or "index.html"
    name = urllib.parse.unquote(name)
    # keep it filesystem-safe and unique-enough
    safe = re.sub(r"[^A-Za-z0-9._#=-]", "_", name)
    if "#" in safe:
        safe = safe.split("#", 1)[0]
    if not safe.endswith((".html", ".htm")):
        h = hashlib.sha1(url.encode()).hexdigest()[:8]
        safe = f"{safe}_{h}.html"
    d = os.path.join(CACHE_DIR, subdir)
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, safe)


def careful_fetch(url, subdir="anotak", force=False):
    """
    Fetch `url`, caching to cache/<subdir>/. Returns (text, from_cache:bool).

    * Cache hit  -> returns instantly, NO network, NO rate-limit wait.
    * Cache miss -> sleeps to honour RATE_LIMIT_SECS, fetches with a polite
                    User-Agent, writes the cache, returns text.
    Network/HTTP errors are raised to the caller (handle gracefully there).
    """
    path = url_to_cache_path(url, subdir)
    if os.path.exists(path) and not force:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read(), True

    # rate-limit network requests only
    wait = RATE_LIMIT_SECS - (time.monotonic() - _last_net[0])
    if wait > 0:
        time.sleep(wait)

    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
    finally:
        _last_net[0] = time.monotonic()

    text = raw.decode("utf-8", errors="replace")
    with open(path, "w", encoding="utf-8", errors="replace") as f:
        f.write(text)
    return text, False


# ---- SurrealQL helpers -----------------------------------------------------
def sql_str(v):
    """Escape a Python value as a SurrealQL single-quoted string literal."""
    if v is None:
        return "NONE"
    s = str(v)
    s = s.replace("\\", "\\\\").replace("'", "\\'")
    s = s.replace("\r", " ").replace("\n", " ")
    return "'" + s + "'"


def kb_apply(sql, label=""):
    """
    POST a SurrealQL string to the live KB (USE NS/DB auto-prepended).
    Returns the parsed JSON result list. Raises on transport error.
    """
    body = f"USE NS {KB_NS} DB {KB_DB}; {sql}".encode("utf-8")
    auth = "Basic " + _b64(KB_AUTH)
    req = urllib.request.Request(
        KB_URL, data=body, method="POST",
        headers={"Accept": "application/json", "Authorization": auth,
                 "Content-Type": "text/plain"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        out = resp.read().decode("utf-8", errors="replace")
    try:
        res = json.loads(out)
    except json.JSONDecodeError:
        print(f"[kb] {label}: non-JSON reply: {out[:300]}", file=sys.stderr)
        raise
    # surface any per-statement errors
    errs = [r for r in res if isinstance(r, dict) and r.get("status") == "ERR"]
    if errs:
        for e in errs[:5]:
            print(f"[kb] {label}: ERR {str(e.get('result'))[:200]}", file=sys.stderr)
    return res


def kb_apply_file(path, label=""):
    """Apply a .surql file (it carries its own USE line) verbatim."""
    with open(path, "rb") as f:
        body = f.read()
    auth = "Basic " + _b64(KB_AUTH)
    req = urllib.request.Request(
        KB_URL, data=body, method="POST",
        headers={"Accept": "application/json", "Authorization": auth,
                 "Content-Type": "text/plain"},
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        out = resp.read().decode("utf-8", errors="replace")
    res = json.loads(out)
    errs = [r for r in res if isinstance(r, dict) and r.get("status") == "ERR"]
    if errs:
        for e in errs[:5]:
            print(f"[kb] {label}: ERR {str(e.get('result'))[:200]}", file=sys.stderr)
    return res


def _b64(s):
    import base64
    return base64.b64encode(s.encode()).decode()


def write_json(name, obj):
    p = os.path.join(DATA_DIR, name)
    with open(p, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2)
    return p


def read_json(name):
    p = os.path.join(DATA_DIR, name)
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)
