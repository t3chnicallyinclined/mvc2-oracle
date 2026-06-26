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

FGT = "https://github.com/t3chnicallyinclined/finger-gap-tester/releases/tag/v0.2.0"
NBD = "https://github.com/t3chnicallyinclined/nobd-desktop/releases/tag/v0.3.0"

# Per-channel posts. Discord hard-caps a message at 2000 chars.
# <url> angle-brackets suppress link embeds so the post stays clean.
# pin=True pins the message after posting (release notes live where they belong).
ANNOUNCEMENTS = [
    {"channel": "announcements", "pin": True, "content":
        "## 🛠️ New releases — Finger Gap Tester v0.2.0 & NOBD Desktop v0.3.0\n\n"
        "Two big updates to the desktop tools today.\n\n"
        "**🎯 Finger Gap Tester v0.2.0** — now a controller *input-conditioning detector*, "
        "not just a gap meter:\n"
        "• Tells you **live** whether a controller is **grouping presses** (a sync window) or "
        "passing your raw finger timing through — **“GROUPING OFF — natural finger timing”** "
        "vs **“GROUPING DETECTED”**.\n"
        "• The verdict re-decides over a sliding window of your last N inputs, so you can toggle "
        "firmware mid-session and watch it flip.\n"
        "• **60fps split simulation:** every dash shows `60fps: SPLIT` or `same frame` — whether a "
        "60fps game would actually have dropped the input.\n"
        f"→ <{FGT}>\n\n"
        "**🕹️ NOBD Desktop v0.3.0** — the same detector + 60fps sim, now in the Finger Gap Tester "
        "tab (per-controller), plus clearer notes on what the in-game sync does.\n"
        f"→ <{NBD}>\n\n"
        "Download, run, plug in your stick — no install. *Execution is back.*"
    },
    {"channel": "firmware", "pin": True, "content":
        "**Finger Gap Tester v0.2.0 / NOBD Desktop v0.3.0 — detect grouping + 60fps split sim**\n\n"
        "You can now use the Finger Gap Tester to *verify* whether a board/firmware is grouping "
        "inputs. How it decides, from 3 signatures:\n"
        "• **Same-frame rate** — how often two presses land in one USB report (humans can’t, so "
        "high = grouped)\n"
        "• **Dead zone** — the empty “missing middle” a sync window carves out (its width ≈ the window)\n"
        "• **Singles + fixed-combo** — whether single buttons still register on their own\n\n"
        "**Live & honest:** the verdict runs over your last N inputs (slider 6–40) so it flips when "
        "you toggle NOBD; the 60fps sim uses a *free-running* clock, so it reflects real random poll "
        "alignment — not a synced best case.\n\n"
        "Wording is neutral — “grouping detected,” no macro implication. Note: NOBD Desktop’s tester "
        "reads your controller directly, so it shows the *controller’s* behavior, not the in-game DLL sync.\n\n"
        f"• Finger Gap Tester: <{FGT}>\n"
        f"• NOBD Desktop: <{NBD}>"
    },
    {"channel": "support", "pin": False, "content":
        "**New tools + how to read them — Finger Gap Tester v0.2.0 / NOBD Desktop v0.3.0**\n\n"
        "Plug in your stick, mash two buttons “together” ~10 times, and the app tells you:\n"
        "• **GROUPING OFF — natural finger timing** = your controller passes raw timing (stock).\n"
        "• **GROUPING DETECTED** = something’s grouping your presses onto one frame (a sync window).\n"
        "• Each dash shows **`60fps: SPLIT`** (a 60fps game would’ve dropped it) or **`same frame`** (good).\n\n"
        "The verdict updates **live** over your last N inputs — flip your firmware on/off and watch it "
        "change. Use the **Decision window** slider to make it react faster/slower. No install — download "
        "and run.\n\n"
        f"• Finger Gap Tester: <{FGT}>\n"
        f"• NOBD Desktop: <{NBD}>\n\n"
        "Stuck? Ask right here."
    },
    {"channel": "dev", "pin": False, "content":
        "**Tooling update — grouping detector + 60fps sim (open source)**\n\n"
        "Finger Gap Tester v0.2.0 / NOBD Desktop v0.3.0 turn the gap tester into an input-conditioning "
        "detector. The bits worth a look if you poke at input timing:\n"
        "• **3-signature classifier:** same-frame rate, the **dead zone** (the empty band a sync window "
        "leaves between same-frame and your first real gap — width ≈ the window), and singles + "
        "fixed-combo to tell a window from an always-on macro.\n"
        "• **Sliding-window verdict** so it re-decides live instead of accumulating forever.\n"
        "• **Free-running 60fps poll sim** (fixed epoch, never reset on input) → honest random-phase "
        "split rate, cross-checked against the analytical gap/16.67ms.\n"
        "• Backend reads XInput directly at ~2 kHz gated on dwPacketNumber (gilrs only sampled ~125 Hz "
        "and merged sub-8ms gaps).\n\n"
        "Both Rust, open source — eyes/PRs welcome:\n"
        f"• <{FGT}>\n"
        f"• <{NBD}>"
    },
    {"channel": "general", "pin": False, "content":
        "🛠️ Dropped two tool updates — the **Finger Gap Tester** can now tell you straight up whether a "
        "controller is **grouping your inputs** (a sync window) or not, and simulate whether a **60fps "
        "game would’ve dropped your dash**. Toggle your firmware and watch the verdict flip live.\n\n"
        "Details + downloads in #announcements. *Execution is back.*"
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
