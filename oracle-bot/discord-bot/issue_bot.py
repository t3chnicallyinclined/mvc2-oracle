#!/usr/bin/env python3
"""Standalone slash-command bot for /bug and /feature -> GitHub issues.

Runs on its own gateway connection (separate from the Oracle Q&A bot) so issue
filing doesn't depend on the Oracle's Anthropic/token setup. Uses the same
dev_commands.py. Intended to run as the NOBD Setup (admin) bot.

Env:
    DISCORD_BOT_TOKEN   the bot's token (setup bot)
    DEV_GUILD_ID        guild id for instant command registration
    GITHUB_ISSUE_TOKEN  token with Issues:write (falls back to GITHUB_TOKEN)
"""
import os
import sys
import discord
from discord import app_commands
import dev_commands

intents = discord.Intents.default()
client = discord.Client(intents=intents)
tree = app_commands.CommandTree(client)
dev_commands.setup_dev_commands(tree)


@client.event
async def on_ready():
    try:
        gid = os.environ.get("DEV_GUILD_ID")
        if gid:
            g = discord.Object(id=int(gid))
            tree.copy_global_to(guild=g)
            synced = await tree.sync(guild=g)
        else:
            synced = await tree.sync()
        print(f"issue bot online as {client.user} | synced: {[c.name for c in synced]}", flush=True)
    except Exception as e:
        print(f"issue bot online as {client.user} | SLASH SYNC FAILED: {e}", flush=True)


def main():
    if not os.environ.get("DISCORD_BOT_TOKEN"):
        sys.exit("Set DISCORD_BOT_TOKEN first.")
    client.run(os.environ["DISCORD_BOT_TOKEN"])


if __name__ == "__main__":
    main()
