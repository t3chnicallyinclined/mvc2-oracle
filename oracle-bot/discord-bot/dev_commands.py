"""Slash commands for the NOBD Discord: /bug and /feature -> GitHub issues.

Lets non-technical members file bugs / feature requests without touching GitHub.
Attach in bot.py with `setup_dev_commands(tree)`. Needs a GitHub token with
issues:write on the target repos (GITHUB_ISSUE_TOKEN; falls back to GITHUB_TOKEN).

The bot must be invited with the `applications.commands` scope for slash commands
to register. Set DEV_GUILD_ID=<guild id> for instant (guild-scoped) registration.
"""
import os
import aiohttp
import discord
from discord import app_commands

# Discord-facing project name -> GitHub repo (owner/name)
PROJECTS = {
    "GP2040 NOBD firmware": "t3chnicallyinclined/GP2040-CE-NOBD",
    "NOBD Desktop":         "t3chnicallyinclined/nobd-desktop",
    "Finger Gap Tester":    "t3chnicallyinclined/finger-gap-tester",
    "MvC2 Skin Studio":     "t3chnicallyinclined/mvc2-skin-studio",
    "MapleCast / Flycast":  "t3chnicallyinclined/maplecast-flycast",
}
DEFAULT_PROJECT = "GP2040 NOBD firmware"
_CHOICES = [app_commands.Choice(name=k, value=k) for k in PROJECTS]

# Pre-filled skeletons so reports come in structured. The user edits these in-form.
BUG_TEMPLATE = (
    "What happened:\n\n"
    "What I expected:\n\n"
    "Steps to reproduce:\n1. \n2. \n\n"
    "Setup (board / firmware version / game / console): "
)
FEATURE_TEMPLATE = (
    "What I'd like:\n\n"
    "Why — the problem it solves:\n\n"
    "How I'd use it: "
)


def _gh_token() -> str:
    return os.environ.get("GITHUB_ISSUE_TOKEN") or os.environ.get("GITHUB_TOKEN", "")


async def _create_issue(repo: str, title: str, body: str, label: str):
    token = _gh_token()
    if not token:
        return None, "no GitHub token configured (set GITHUB_ISSUE_TOKEN)"
    headers = {"Authorization": f"Bearer {token}",
               "Accept": "application/vnd.github+json",
               "User-Agent": "NOBD-DevBot"}
    # "bug"/"enhancement" are GitHub's built-in labels (exist in every repo).
    payload = {"title": title, "body": body, "labels": [label]}
    async with aiohttp.ClientSession() as s:
        async with s.post(f"https://api.github.com/repos/{repo}/issues",
                          json=payload, headers=headers) as r:
            data = await r.json()
            if r.status == 201:
                return data.get("html_url"), None
            return None, f"GitHub {r.status}: {data.get('message', 'error')}"


class IssueModal(discord.ui.Modal):
    def __init__(self, kind: str, repo: str, project_label: str):
        self.kind = kind  # "bug" | "feature"
        self.repo = repo
        self.project_label = project_label
        verb = "Report a bug" if kind == "bug" else "Request a feature"
        super().__init__(title=f"{verb} · {project_label}"[:45])
        self.title_in = discord.ui.TextInput(
            label="Title", max_length=120, placeholder="Short summary")
        self.body_in = discord.ui.TextInput(
            label="Details (template pre-filled)",
            style=discord.TextStyle.paragraph, max_length=1800,
            required=(kind == "bug"),
            default=(BUG_TEMPLATE if kind == "bug" else FEATURE_TEMPLATE))
        self.add_item(self.title_in)
        self.add_item(self.body_in)

    async def on_submit(self, interaction: discord.Interaction):
        await interaction.response.defer(ephemeral=True, thinking=True)
        u = interaction.user
        label = "bug" if self.kind == "bug" else "enhancement"
        prefix = "🐛" if self.kind == "bug" else "✨"
        where = f" from #{interaction.channel.name}" if interaction.channel else ""
        body = (f"{self.body_in.value or '_(no details provided)_'}\n\n"
                f"---\n_Submitted by **{u}** (`{u.id}`) via Discord{where}._")
        url, err = await _create_issue(self.repo, f"{prefix} {self.title_in.value}", body, label)
        if not url:
            await interaction.followup.send(
                f"⚠️ Couldn't create the issue — {err}\nPing a **@Mod** and we'll sort it.",
                ephemeral=True)
            return

        # Open a public thread for the issue (no message in the channel body, so the channel
        # stays clean) — gives the team/community a place to discuss. Falls back to an
        # ephemeral-only confirm if the bot can't create threads in this channel.
        thread = None
        try:
            thread = await interaction.channel.create_thread(
                name=f"{prefix} {self.title_in.value}"[:100],
                type=discord.ChannelType.public_thread,
                auto_archive_duration=1440)
            await thread.send(
                f"{prefix} **{self.title_in.value}**  ·  filed by {u.mention}\n"
                f"_{self.project_label}_ · `{label}`\n\n"
                f"{self.body_in.value or '_(no details)_'}\n\n→ {url}")
        except Exception:
            thread = None

        if thread:
            await interaction.followup.send(
                f"✅ Filed — tracking it in {thread.mention}\n{url}", ephemeral=True)
        else:
            await interaction.followup.send(f"✅ Filed it — thanks!\n{url}", ephemeral=True)


def setup_dev_commands(tree: app_commands.CommandTree):
    @tree.command(name="bug", description="Report a bug — files a GitHub issue for the devs")
    @app_commands.describe(project="Which project? (defaults to GP2040 NOBD firmware)")
    @app_commands.choices(project=_CHOICES)
    async def bug(interaction: discord.Interaction,
                  project: app_commands.Choice[str] = None):
        proj = project.value if project else DEFAULT_PROJECT
        await interaction.response.send_modal(IssueModal("bug", PROJECTS[proj], proj))

    @tree.command(name="feature", description="Request a feature — files a GitHub issue for the devs")
    @app_commands.describe(project="Which project? (defaults to GP2040 NOBD firmware)")
    @app_commands.choices(project=_CHOICES)
    async def feature(interaction: discord.Interaction,
                      project: app_commands.Choice[str] = None):
        proj = project.value if project else DEFAULT_PROJECT
        await interaction.response.send_modal(IssueModal("feature", PROJECTS[proj], proj))
