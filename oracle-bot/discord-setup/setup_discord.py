#!/usr/bin/env python3
"""
NOBD Discord server setup — idempotent, stdlib-only.

Creates roles, categories, channels (topics + read-only overwrites), sets the
server name + description, and posts/pins the welcome/rules/why-nobd copy.

Bootstrap (browser, one time):
  1. Create the server in the Discord client.
  2. https://discord.com/developers/applications -> New Application -> Bot -> copy token.
  3. Invite the bot with Administrator (or Manage Roles/Channels/Server + Send Messages):
     https://discord.com/oauth2/authorize?client_id=<APP_ID>&scope=bot&permissions=8
  4. (Optional, for the discovery description) enable Community in Server Settings.
  5. Developer Mode on -> right-click server -> Copy Server ID.

Run:
  export DISCORD_BOT_TOKEN='...'        # never commit this
  export DISCORD_GUILD_ID='...'
  python3 setup_discord.py              # dry run: prints the plan
  python3 setup_discord.py --apply      # actually create
"""
import os, sys, json, time, urllib.request, urllib.error

API = "https://discord.com/api/v10"
TOKEN = os.environ.get("DISCORD_BOT_TOKEN", "")
GUILD = os.environ.get("DISCORD_GUILD_ID", "")
APPLY = "--apply" in sys.argv

# Discord permission bits
SEND_MESSAGES = 1 << 11  # 2048

SERVER_NAME = "NOBD"
SERVER_DESCRIPTION = ("Execution is back. Open-source firmware that lands your inputs "
                      "intact — built for MvC2, retro & the FGC.")

# --- Roles (created top-to-bottom; @everyone stays at the bottom) ---
ROLES = [
    {"name": "Team",               "color": 0x9B59B6, "hoist": True,  "mentionable": True},
    {"name": "Mod",                "color": 0x3498DB, "hoist": True,  "mentionable": True},
    {"name": "Dev / Contributor",  "color": 0x2ECC71, "hoist": True,  "mentionable": True},
    {"name": "Early Access",       "color": 0xF1C40F, "hoist": True,  "mentionable": True},
    {"name": "Verified",           "color": 0x95A5A6, "hoist": False, "mentionable": False},
    {"name": "Firmware User",      "color": 0xE67E22, "hoist": False, "mentionable": True},
    {"name": "Retro",              "color": 0xE74C3C, "hoist": False, "mentionable": True},
    {"name": "Bots",               "color": 0x607D8B, "hoist": False, "mentionable": False},
]

# type: 0=text, 2=voice. (Announcement/forum need Community; kept as read-only text for robustness.)
STRUCTURE = [
    ("START HERE", [
        {"name": "welcome",         "ro": True,  "topic": "Start here. NOBD keeps your inputs honest and your intent intact."},
        {"name": "rules",           "ro": True,  "topic": "Be cool. Read before posting."},
        {"name": "why-nobd",        "ro": True,  "topic": "What NOBD is, in plain terms — and the code that proves it."},
        {"name": "announcements",   "ro": True,  "topic": "Project updates. (Convert to an Announcement channel after enabling Community.)"},
        {"name": "roles",           "ro": True,  "topic": "Grab your roles."},
    ]),
    ("NOBD", [
        {"name": "general",         "topic": "Open chat about NOBD."},
        {"name": "execution-clips", "topic": "Clips of NOBD working — landing what you couldn't before. (NOBD software, not the board.)"},
        {"name": "support",         "topic": "Setup help & troubleshooting."},
        {"name": "firmware",        "topic": "Firmware: flashing, settings, sync window, releases."},
        {"name": "feedback",        "topic": "Feature requests & honest feedback."},
    ]),
    ("PLAY · nobd.net (in dev)", [
        {"name": "matchmaking",     "topic": "Find games on nobd.net (under active development).", "slowmode": 5},
        {"name": "mvc2",            "topic": "Marvel vs Capcom 2 talk, tech, sets."},
        {"name": "netplay-help",    "topic": "Online play setup & issues."},
    ]),
    ("HARDWARE", [
        {"name": "nobd-zero",       "topic": "NOBD Zero — the hardware. In development; build in the open."},
        {"name": "early-access",    "ro": True, "topic": "Waitlist info & founding-tester updates. No payment — just first in line."},
        {"name": "builds",          "topic": "Your sticks, your builds, your mods."},
    ]),
    ("DEV · OPEN SOURCE", [
        {"name": "dev",             "topic": "Contributing to the firmware & tooling."},
        {"name": "github",          "topic": "GitHub activity feed."},
        {"name": "re-and-tech",     "topic": "Reverse engineering & input-timing deep dives. Receipts welcome."},
    ]),
    ("COMMUNITY", [
        {"name": "off-topic",       "topic": "Everything else."},
        {"name": "showcase",        "topic": "Cool stuff from the community."},
    ]),
    ("VOICE", [
        {"name": "General",         "voice": True},
        {"name": "Training Lab",    "voice": True},
    ]),
]

# Messages posted (once) into freshly-created channels, then pinned.
MESSAGES = {
    "welcome": (
        "# Welcome to NOBD\n"
        "**You did the input. The game just didn't see it.**\n\n"
        "Older fighting games read your controller **once per frame** and look at what's held at that "
        "exact instant. Press two buttons a hair apart and that read can land *between* them — the game "
        "catches one, not both, and your dash turns into a jab. That's not your execution. It's a "
        "timing gap between your hands and the game.\n\n"
        "**NOBD closes that gap.** It makes sure your presses reach the game **together**, on the frame "
        "it actually reads — so what you did is what it gets. Nothing invented, nothing automated, no "
        "macros: it just stops a frame-timing glitch from eating inputs you really pressed. Built for "
        "no-leniency games like **Marvel vs Capcom 2**.\n\n"
        "It's all open — one function you can read. This is where we build it in the open: the "
        "firmware, online play on **nobd.net** *(under active development)*, and **NOBD Zero**, the "
        "hardware *(in development)*.\n\n"
        "Players, retro heads, builders, and skeptics all welcome — read the code and tell us where "
        "we're wrong.\n\n"
        "➡️ Start in **#why-nobd**, check **#rules**, grab your **#roles**.\n\n"
        "*Execution is back.*"
    ),
    "rules": (
        "# Rules\n"
        "1. **Be respectful.** The FGC is family, not an audience. No harassment, bigotry, or gatekeeping.\n"
        "2. **Stay on-topic per channel.** Read a channel's topic before posting.\n"
        "3. **No spam, no NFTs/crypto shilling, no self-promo without permission.**\n"
        "4. **Disagree with the tech? Bring receipts.** Point at the code or the data — that's the whole point.\n"
        "5. **No piracy / ROM links.** Talk about the games freely; don't share copyrighted files.\n"
        "6. **Mods have final say.** Issues? DM a **@Mod**.\n"
    ),
    "why-nobd": (
        "# Why NOBD\n"
        "A controller has one job: deliver what you meant to do, intact.\n\n"
        "Games read your controller **once per frame** and take a snapshot of what's held right then "
        "(this is verified — it's how the emulator and the game's own code work). Your two fingers "
        "land a few milliseconds apart, so if the snapshot falls between them, the game sees one "
        "button, not both — and games like MvC2 give you **no leniency**: both buttons have to be in "
        "the same frame to count together.\n\n"
        "**NOBD groups your near-simultaneous presses into one report** so they land on the same "
        "frame. It changes *when* a real press reports, never *which* buttons — it automates nothing, "
        "and it holds you to a **tighter** window than the game ever did. It's a fix, not an aid.\n\n"
        "NOBD is a fork of the excellent open-source **GP2040-CE** (OpenStickCommunity, MIT). We added "
        "the sync window and took it a different direction — native Dreamcast and online play. "
        "Standing on their shoulders.\n\n"
        "Don't take our word for it:\n"
        "• Read the one function on GitHub.\n"
        "• Measure your own finger gap with the Finger Gap Tester.\n\n"
        "*(Links pinned/added by the team.)*"
    ),
    "announcements": (
        "**NOBD is live and open-source today. NOBD Zero — the hardware — is in development.**\n"
        "Build-in-public from here. Watch this channel."
    ),
    "early-access": (
        "**NOBD Zero — reserve your spot.**\n"
        "The hardware is in active development (no board to buy yet). Join the waitlist for first "
        "units + a founding-tester role. **No payment now — just first in line.** Link coming soon."
    ),
}


def api(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Authorization", f"Bot {TOKEN}")
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "NOBDSetup (https://nobd.net, 1.0)")
    while True:
        try:
            with urllib.request.urlopen(req) as r:
                raw = r.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            payload = e.read().decode()
            if e.code == 429:
                try: retry = json.loads(payload).get("retry_after", 1)
                except Exception: retry = 1
                time.sleep(float(retry) + 0.2); continue
            sys.exit(f"  ! {method} {path} -> {e.code} {payload}")


def main():
    if not TOKEN or not GUILD:
        sys.exit("Set DISCORD_BOT_TOKEN and DISCORD_GUILD_ID env vars first.")
    mode = "APPLY" if APPLY else "DRY-RUN (pass --apply to execute)"
    print(f"== NOBD Discord setup [{mode}] guild={GUILD} ==")

    existing_roles = {r["name"]: r for r in api("GET", f"/guilds/{GUILD}/roles")}
    channels = api("GET", f"/guilds/{GUILD}/channels")
    existing_ch = {(c["name"].lower(), c["type"]) for c in channels}
    cat_id = {c["name"]: c["id"] for c in channels if c["type"] == 4}

    # Server name + description
    print(f"[guild] name -> {SERVER_NAME!r}; description -> {SERVER_DESCRIPTION!r}")
    if APPLY:
        api("PATCH", f"/guilds/{GUILD}", {"name": SERVER_NAME})
        try:
            api("PATCH", f"/guilds/{GUILD}", {"description": SERVER_DESCRIPTION})
        except SystemExit:
            print("  (description needs Community enabled — set it manually for now)")

    # Roles
    for role in ROLES:
        if role["name"] in existing_roles:
            print(f"[role] exists: {role['name']}"); continue
        print(f"[role] create: {role['name']}")
        if APPLY:
            api("POST", f"/guilds/{GUILD}/roles", {
                "name": role["name"], "color": role["color"],
                "hoist": role["hoist"], "mentionable": role["mentionable"],
            })

    # Categories + channels
    created_text = {}  # name -> id, for message posting
    for cat_name, chans in STRUCTURE:
        if cat_name in cat_id:
            print(f"[cat] exists: {cat_name}"); parent = cat_id[cat_name]
        else:
            print(f"[cat] create: {cat_name}")
            parent = None
            if APPLY:
                parent = api("POST", f"/guilds/{GUILD}/channels", {"type": 4, "name": cat_name})["id"]
                cat_id[cat_name] = parent
        for ch in chans:
            ctype = 2 if ch.get("voice") else 0
            if (ch["name"].lower(), ctype) in existing_ch:
                print(f"   [ch] exists: {ch['name']}"); continue
            print(f"   [ch] create: {ch['name']}" + (" (read-only)" if ch.get("ro") else ""))
            if not APPLY:
                continue
            body = {"type": ctype, "name": ch["name"], "parent_id": parent}
            if ch.get("topic"):    body["topic"] = ch["topic"]
            if ch.get("slowmode"): body["rate_limit_per_user"] = ch["slowmode"]
            if ch.get("ro"):
                body["permission_overwrites"] = [
                    {"id": GUILD, "type": 0, "deny": str(SEND_MESSAGES), "allow": "0"}
                ]
            new = api("POST", f"/guilds/{GUILD}/channels", body)
            if ctype == 0:
                created_text[ch["name"]] = new["id"]

    # Post + pin starter messages into newly-created text channels
    for name, content in MESSAGES.items():
        cid = created_text.get(name)
        if not cid:
            continue
        print(f"[msg] post + pin in #{name}")
        if APPLY:
            msg = api("POST", f"/channels/{cid}/messages", {"content": content})
            api("PUT", f"/channels/{cid}/pins/{msg['id']}")

    print("== done. ==" + ("" if APPLY else "  (dry run — re-run with --apply)"))


if __name__ == "__main__":
    main()
