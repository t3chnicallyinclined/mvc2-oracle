#!/usr/bin/env python3
"""Stand up Discord <-> GitHub integration across the NOBD repos.
Idempotent. Never prints webhook URLs/tokens. Reads DISCORD_BOT_TOKEN/GUILD from env."""
import os, sys, json, base64, subprocess, urllib.request, urllib.error

DISCORD_API = "https://discord.com/api/v10"
GH_API = "https://api.github.com"
TOKEN = os.environ["DISCORD_BOT_TOKEN"]
GUILD = os.environ["DISCORD_GUILD_ID"]
GH_TOKEN = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True).stdout.strip()

REPOS = [
    "t3chnicallyinclined/GP2040-CE-NOBD",
    "t3chnicallyinclined/finger-gap-tester",
    "t3chnicallyinclined/nobd-desktop",
    "t3chnicallyinclined/mvc2-skin-studio",
    "t3chnicallyinclined/maplecast-flycast",
]
FIRMWARE_REPO = "t3chnicallyinclined/GP2040-CE-NOBD"
FEED_EVENTS = ["release", "pull_request", "issues"]

WORKFLOW = r"""name: Discord release announce
on:
  release:
    types: [published]
permissions:
  contents: read
jobs:
  announce:
    runs-on: ubuntu-latest
    steps:
      - name: Post release to Discord
        env:
          ANNOUNCE_WEBHOOK: ${{ secrets.DISCORD_RELEASE_WEBHOOK_ANNOUNCE }}
          FIRMWARE_WEBHOOK: ${{ secrets.DISCORD_RELEASE_WEBHOOK_FIRMWARE }}
          REPO: ${{ github.repository }}
          TAG: ${{ github.event.release.tag_name }}
          RELEASE_NAME: ${{ github.event.release.name }}
          RELEASE_URL: ${{ github.event.release.html_url }}
          RELEASE_BODY: ${{ github.event.release.body }}
        run: |
          set -euo pipefail
          name="${RELEASE_NAME:-$TAG}"
          repo_short="${REPO##*/}"
          body="$(printf '%s' "${RELEASE_BODY:-}" | head -c 1200)"
          content="$(printf '🔧 **New release — %s**  ·  _%s_\n\n%s\n\n→ <%s>' "$name" "$repo_short" "$body" "$RELEASE_URL")"
          payload="$(jq -n --arg c "$content" '{content: $c}')"
          post() {
            wh="$1"; label="$2"
            if [ -z "$wh" ]; then echo "skip $label (no webhook configured)"; return 0; fi
            code="$(curl -sS -o /tmp/dresp -w '%{http_code}' -H 'Content-Type: application/json' -d "$payload" "$wh")"
            echo "$label -> HTTP $code"
            case "$code" in 2*) ;; *) echo "  body: $(cat /tmp/dresp)"; exit 1 ;; esac
          }
          post "$ANNOUNCE_WEBHOOK" "#announcements"
          post "$FIRMWARE_WEBHOOK" "#firmware"
"""


def dapi(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(DISCORD_API + path, data=data, method=method)
    req.add_header("Authorization", f"Bot {TOKEN}")
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "NOBDOps (https://nobd.net, 1.0)")
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        print(f"  ! Discord {method} {path} -> {e.code} {e.read().decode()[:200]}")
        sys.exit(1)


def gapi(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(GH_API + path, data=data, method=method)
    req.add_header("Authorization", f"Bearer {GH_TOKEN}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "NOBDOps")
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return {"_error": e.code, "_body": e.read().decode()[:300]}


# --- 1. resolve channels ---
chans = dapi("GET", f"/guilds/{GUILD}/channels")
by_name = {c["name"].lower(): c for c in chans if c["type"] in (0, 5)}


def ch_id(n):
    c = by_name.get(n)
    if not c:
        print(f"  ! channel #{n} not found"); sys.exit(1)
    return c["id"]


# --- 2. create/reuse Discord webhooks ---
def ensure_webhook(channel_name, wh_name):
    cid = ch_id(channel_name)
    for w in dapi("GET", f"/channels/{cid}/webhooks"):
        if w.get("name") == wh_name and w.get("token"):
            return f"https://discord.com/api/webhooks/{w['id']}/{w['token']}", w["id"], "reused"
    w = dapi("POST", f"/channels/{cid}/webhooks", {"name": wh_name})
    return f"https://discord.com/api/webhooks/{w['id']}/{w['token']}", w["id"], "created"


print("== Discord webhooks ==")
feed_url, feed_id, st = ensure_webhook("github", "GitHub Feed")
print(f"[discord] #github        {feed_id} ({st})")
ann_url, ann_id, st = ensure_webhook("announcements", "Release Announce")
print(f"[discord] #announcements {ann_id} ({st})")
fw_url, fw_id, st = ensure_webhook("firmware", "Release Announce")
print(f"[discord] #firmware      {fw_id} ({st})")


# --- 3. GitHub secrets ---
def set_secret(repo, name, value):
    p = subprocess.run(["gh", "secret", "set", name, "--repo", repo],
                       input=value, text=True, capture_output=True)
    return "ok" if p.returncode == 0 else f"ERR {p.stderr.strip()[:140]}"


print("\n== GitHub secrets ==")
for repo in REPOS:
    print(f"[secret] {repo:45} ANNOUNCE: {set_secret(repo, 'DISCORD_RELEASE_WEBHOOK_ANNOUNCE', ann_url)}")
print(f"[secret] {FIRMWARE_REPO:45} FIRMWARE: {set_secret(FIRMWARE_REPO, 'DISCORD_RELEASE_WEBHOOK_FIRMWARE', fw_url)}")


# --- 4. GitHub repo webhooks -> Discord /github feed ---
print("\n== #github activity feed (repo webhooks) ==")
for repo in REPOS:
    hooks = gapi("GET", f"/repos/{repo}/hooks")
    if isinstance(hooks, dict) and hooks.get("_error"):
        print(f"[feed] {repo:45} list ERR {hooks['_error']} {hooks.get('_body','')[:100]}")
        continue
    if any("discord.com/api/webhooks" in h.get("config", {}).get("url", "") for h in hooks):
        print(f"[feed] {repo:45} already linked (skip)")
        continue
    r = gapi("POST", f"/repos/{repo}/hooks", {
        "name": "web", "active": True, "events": FEED_EVENTS,
        "config": {"url": feed_url + "/github", "content_type": "json"},
    })
    print(f"[feed] {repo:45} " + (f"ERR {r['_error']} {r.get('_body','')[:120]}" if r.get("_error") else f"linked (hook {r.get('id')})"))


# --- 5. release-announce workflow file in each repo ---
print("\n== release auto-announce workflow ==")
path = ".github/workflows/discord-release-announce.yml"
for repo in REPOS:
    cur = gapi("GET", f"/repos/{repo}/contents/{path}")
    body = {"message": "ci: Discord release auto-announce",
            "content": base64.b64encode(WORKFLOW.encode()).decode()}
    if isinstance(cur, dict) and cur.get("sha"):
        if base64.b64decode(cur.get("content", "")).decode(errors="ignore") == WORKFLOW:
            print(f"[workflow] {repo:45} up-to-date (skip)")
            continue
        body["sha"] = cur["sha"]
    r = gapi("PUT", f"/repos/{repo}/contents/{path}", body)
    print(f"[workflow] {repo:45} " + (f"ERR {r['_error']} {r.get('_body','')[:140]}" if r.get("_error") else "committed"))

print("\n== done ==")
