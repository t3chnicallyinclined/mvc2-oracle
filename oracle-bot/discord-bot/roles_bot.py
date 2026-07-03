#!/usr/bin/env python3
"""
NOBD console/platform role picker — a self-owned, customizable in-channel dropdown.

Posts a persistent message in #roles (as the NOBD bot) with two dropdowns — Retro consoles and
Modern platforms. Selecting **toggles** the role (pick to add, pick again to remove; untouched
options are left alone). Persistent view, so it survives restarts. Must be running to handle new
selections (roles already granted persist regardless).

Env:
    DISCORD_BOT_TOKEN     the NOBD bot's token (needs Manage Roles; its role must sit ABOVE the
                          console/platform roles in Server Settings → Roles)
    DISCORD_GUILD_ID      the guild
    ROLES_CHANNEL_ID      (optional) where to post; defaults to #roles

Customize the RETRO / MODERN lists + INTRO below and restart — the message updates in place.

    pip install discord.py
    python roles_bot.py
"""
import os
import json
from pathlib import Path

import discord

TOKEN = os.environ["DISCORD_BOT_TOKEN"]
GUILD_ID = int(os.environ["DISCORD_GUILD_ID"])
ROLES_CH = int(os.environ.get("ROLES_CHANNEL_ID", "1519424083215909014"))
STATE = Path(__file__).with_name("roles_msg.json")

# --- customize here: (menu label, EXACT role name) ---
RETRO = [
    ("NES / Famicom", "NES"), ("SNES / Super Famicom", "SNES"), ("Nintendo 64", "N64"),
    ("GameCube", "GameCube"), ("Sega Saturn", "Saturn"), ("Dreamcast", "Dreamcast"),
    ("PC Engine / TG-16", "PC Engine"), ("PlayStation 1", "PS1"), ("PlayStation 2", "PS2"),
    ("PlayStation 3", "PS3"), ("Original Xbox", "OG Xbox"),
]
MODERN = [
    ("PlayStation 5", "PS5"), ("PlayStation 4", "PS4"), ("Nintendo Switch", "Switch"),
    ("Xbox Series X|S", "Xbox Series"), ("PC", "PC"),
]
INTRO = (
    "# \U0001F3AE Pick your consoles & platforms\n"
    "Tell us what you've got — it helps us line up **NOBD Zero** testing (retro **native** support + "
    "modern **USB** compatibility) and find people to play with.\n\n"
    "Use the menus below. Picking a console **adds** its role; pick it again to **remove** it. "
    "Choose as many as you like, and re-open anytime to change."
)


def toggle_select(options, custom_id, placeholder):
    class Toggle(discord.ui.Select):
        def __init__(self):
            opts = [discord.SelectOption(label=lbl, value=role) for lbl, role in options]
            super().__init__(placeholder=placeholder, min_values=1, max_values=len(opts),
                             options=opts, custom_id=custom_id)

        async def callback(self, interaction: discord.Interaction):
            guild, member = interaction.guild, interaction.user
            added, removed, failed = [], [], []
            for name in self.values:
                role = discord.utils.get(guild.roles, name=name)
                if role is None:
                    continue
                try:
                    if role in member.roles:
                        await member.remove_roles(role, reason="console picker"); removed.append(name)
                    else:
                        await member.add_roles(role, reason="console picker"); added.append(name)
                except discord.Forbidden:
                    failed.append(name)
            parts = []
            if added:
                parts.append("added **" + "**, **".join(added) + "**")
            if removed:
                parts.append("removed **" + "**, **".join(removed) + "**")
            msg = "\U0001F3AE " + " · ".join(parts) if parts else "No change."
            if failed:
                msg += (f"\n⚠️ couldn't set {', '.join(failed)} — my role must sit ABOVE those "
                        "roles (Server Settings → Roles).")
            await interaction.response.send_message(msg, ephemeral=True)

    return Toggle()


class RolesView(discord.ui.View):
    def __init__(self):
        super().__init__(timeout=None)  # persistent
        self.add_item(toggle_select(RETRO, "nobd_retro_select", "\U0001F579️ Retro consoles…"))
        self.add_item(toggle_select(MODERN, "nobd_modern_select", "\U0001F3AE Modern platforms…"))


intents = discord.Intents.default()
client = discord.Client(intents=intents)


async def ensure_message():
    ch = client.get_channel(ROLES_CH) or await client.fetch_channel(ROLES_CH)
    if STATE.exists():
        try:
            mid = json.loads(STATE.read_text())["message_id"]
            msg = await ch.fetch_message(mid)
            await msg.edit(content=INTRO, view=RolesView())  # apply menu/label changes in place
            print("updated existing dropdown:", mid, flush=True); return
        except Exception:
            pass
    m = await ch.send(INTRO, view=RolesView())
    STATE.write_text(json.dumps({"message_id": m.id}))
    print("posted dropdown:", m.id, flush=True)


@client.event
async def on_ready():
    client.add_view(RolesView())  # reattach the persistent selects across restarts
    await ensure_message()
    print(f"roles bot online as {client.user} | #roles={ROLES_CH}", flush=True)


if __name__ == "__main__":
    for var in ("DISCORD_BOT_TOKEN", "DISCORD_GUILD_ID"):
        if not os.environ.get(var):
            raise SystemExit(f"set {var} first")
    client.run(TOKEN)
