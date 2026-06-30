#!/usr/bin/env python3
"""
NOBD Discord — post release announcements to EXISTING channels.

Companion to setup_discord.py (which only posts into freshly-created channels).
This looks up channels by name in the guild and posts the messages in
ANNOUNCEMENTS. Dry-run by default; pass --apply to actually post.

Run:
  export DISCORD_BOT_TOKEN='...'        # never commit this
  export DISCORD_GUILD_ID='...'
  python3 announce.py                   # dry run: prints what it would post
  python3 announce.py --apply           # actually post
"""
import os, sys, json, time, urllib.request, urllib.error

API = "https://discord.com/api/v10"
TOKEN = os.environ.get("DISCORD_BOT_TOKEN", "")
GUILD = os.environ.get("DISCORD_GUILD_ID", "")
APPLY = "--apply" in sys.argv

REL = "https://github.com/t3chnicallyinclined/GP2040-CE-NOBD/releases/tag/v0.7.12-nobd-22"

# Per-channel posts. Discord hard-caps a message at 2000 chars.
# <url> angle-brackets suppress link embeds so the post stays clean.
# pin=True pins the message after posting (release notes live where they belong).
ANNOUNCEMENTS = [
    {"channel": "announcements", "pin": True, "content":
        "## 🔧 Firmware release — GP2040-CE NOBD v0.7.12-nobd-22\n\n"
        "NOBD is now a **live, switchable** feature — flip it on/off without opening the web UI.\n\n"
        "**✨ Toggle NOBD live, two ways**\n"
        "• **Hotkey** — assign “NOBD On/Off Toggle” in *Settings → Hotkey Settings* to any button "
        "combo. Global, persists across reboot.\n"
        "• **Per-profile pin** — assign it to a pin under *GPIO Pin Mapping*; a tap latches it on/off, "
        "and it can differ per profile.\n\n"
        "**📟 OLED indicator** — the status bar shows NOBD state in every mode: `N+5` when on (with "
        "your sync window in ms) or `N-` when off.\n\n"
        "**🎮 Dreamcast** — NOBD is no longer forced off in DC mode; turn it on if you want it. Native "
        "Dreamcast play (no adapter) keeps working as before.\n\n"
        "**🐛 Fix** — boards *not* using Dreamcast could be blocked from saving Input Settings by a "
        "pin-validation bug. Fixed — Dreamcast is fully optional again.\n\n"
        "**🆕 New build** — added a **Haute42 COSMOX** firmware, alongside RP2040 Advanced Breakout "
        "Board, Pico, and PicoW.\n\n"
        f"Download + full notes → <{REL}>"
    },
    {"channel": "firmware", "pin": True, "content":
        "**v0.7.12-nobd-22 — live NOBD toggle (hotkey + per-profile pin), OLED indicator, DC fix**\n\n"
        "• **Toggle hotkey** — “NOBD On/Off Toggle” in Hotkey Settings flips the sync window on/off "
        "instantly (read fresh every loop), saved to flash like SOCD / 4-Way.\n"
        "• **Per-profile toggle pin** — same action on the GPIO Pin Mapping page. Rising-edge latch; "
        "because pin maps are per-profile you can bind it per layout.\n"
        "• **OLED** — status bar shows `N+<ms>` (on, with the current window) or `N-` (off), in every "
        "input mode including Dreamcast.\n"
        "• **Dreamcast** — NOBD now applies to the Maple output if you enable it (was forced off).\n"
        "• **Fix** — Dreamcast pin validation blocked saving Input Settings on boards not using DC; "
        "now optional again.\n"
        "• **New board** — Haute42 COSMOX added to the build set.\n\n"
        f"→ <{REL}>\n\n"
        "Flash: hold **BOOTSEL**, plug in, drag the matching `.uf2` onto the `RPI-RP2` drive."
    },
    {"channel": "support", "pin": False, "content":
        "**How to toggle NOBD on the new firmware (v0.7.12-nobd-22)**\n\n"
        "Two ways to switch NOBD on/off without the web UI — set either one up once in the configurator:\n"
        "• **Button combo:** *Settings → Hotkey Settings* → pick a free row → choose **“NOBD On/Off "
        "Toggle”** → set your combo. Tap it anytime to flip NOBD.\n"
        "• **Dedicated button:** *GPIO Pin Mapping* → set a pin’s action to **“NOBD On/Off Toggle.”** "
        "This one is per-profile, so it can differ between layouts.\n\n"
        "Got an OLED? The top bar shows **`N+5`** (on, with the window in ms) or **`N-`** (off) so you "
        "always know the current state.\n\n"
        f"Download: <{REL}>\n\n"
        "Questions? Ask right here."
    },
    {"channel": "dev", "pin": False, "content":
        "**Firmware v0.7.12-nobd-22 — the open-source bits**\n\n"
        "NOBD is now toggleable at runtime, wired the standard GP2040-CE way:\n"
        "• New `HOTKEY_NOBD_TOGGLE` hotkey action **and** a `NOBD_TOGGLE` `GpioAction` (per-profile "
        "pin), both routed through one `toggleNobd()` helper — single source of truth. It flips "
        "`nobdSyncDelay` live (the main loop reads it fresh each iteration) and persists to flash.\n"
        "• The OLED status bar reports state (`N+<ms>` / `N-`) from the same field.\n"
        "• DC mode now honors the sync window (runs `syncGpioGetAll()` when enabled) instead of "
        "forcing raw passthrough — `debouncedGpio` already feeds the Maple lookup table.\n"
        "• Fix: web validation capped the Dreamcast pins at 29, rejecting the `255` “disabled” "
        "sentinel and blocking Input Settings saves on boards not using DC.\n\n"
        f"Code + notes → <{REL}>\n"
        "PRs / eyes welcome."
    },
    {"channel": "general", "pin": False, "content":
        "🔧 New firmware — **GP2040-CE NOBD v0.7.12-nobd-22**: you can now toggle NOBD on/off **live** "
        "with a hotkey or a button, see its state on the OLED (`N+5` / `N-`), and use it in Dreamcast "
        "mode too. Plus a fix so non-Dreamcast boards can save Input Settings again, and a new Haute42 "
        "COSMOX build.\n\n"
        "Details + downloads in #announcements."
    },
]


def api(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Authorization", f"Bot {TOKEN}")
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "NOBDAnnounce (https://nobd.net, 1.0)")
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
    mode = "APPLY" if APPLY else "DRY-RUN (pass --apply to post)"
    print(f"== NOBD Discord announce [{mode}] guild={GUILD} ==")

    channels = api("GET", f"/guilds/{GUILD}/channels")
    by_name = {c["name"].lower(): c for c in channels if c["type"] in (0, 5)}  # text/announcement

    for item in ANNOUNCEMENTS:
        name, content, pin = item["channel"], item["content"], item.get("pin", False)
        ch = by_name.get(name.lower())
        if not ch:
            print(f"  ! #{name}: channel not found — skipping")
            continue
        if len(content) > 2000:
            print(f"  ! #{name}: message is {len(content)} chars (>2000) — trim before posting")
            continue
        pin_note = "  [will pin]" if pin else ""
        print(f"\n--- #{name} ({len(content)} chars){pin_note} ---\n{content}\n")
        if APPLY:
            msg = api("POST", f"/channels/{ch['id']}/messages", {"content": content})
            print(f"  ✓ posted to #{name}")
            if pin:
                api("PUT", f"/channels/{ch['id']}/pins/{msg['id']}")
                print(f"  📌 pinned in #{name}")

    print("\n== done ==" + ("" if APPLY else "  (dry run — re-run with --apply)"))


if __name__ == "__main__":
    main()
