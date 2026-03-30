import json
import random
import re
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import aiohttp
import discord
from discord import app_commands
from discord.ext import commands

CONFIG_PATH = Path("config.json")
DB_PATH = Path("sixmans.db")
BALLCHASING_API = "https://ballchasing.com/api"

RANK_BUCKETS = [
    "bronze",
    "silver",
    "gold",
    "platinum",
    "diamond",
    "champion",
    "grand champion",
    "supersonic legend",
]


def load_config() -> dict:
    if not CONFIG_PATH.exists():
        raise FileNotFoundError(
            "Missing config.json. Copy config.example.json to config.json and fill values."
        )
    return json.loads(CONFIG_PATH.read_text())


@dataclass
class GuildConfig:
    queue_size: int
    queue_channel_id: int
    results_channel_id: int


class SixMansStore:
    def __init__(self, db_path: Path):
        self.conn = sqlite3.connect(db_path)
        self.conn.row_factory = sqlite3.Row
        self._init_tables()

    def _init_tables(self):
        self.conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS guild_config (
                guild_id INTEGER PRIMARY KEY,
                queue_size INTEGER NOT NULL DEFAULT 6,
                queue_channel_id INTEGER,
                results_channel_id INTEGER
            );

            CREATE TABLE IF NOT EXISTS queue_members (
                guild_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (guild_id, user_id)
            );

            CREATE TABLE IF NOT EXISTS matches (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                guild_id INTEGER NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                team_a TEXT NOT NULL,
                team_b TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending',
                winner TEXT
            );

            CREATE TABLE IF NOT EXISTS ratings (
                guild_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                mmr INTEGER NOT NULL DEFAULT 1000,
                wins INTEGER NOT NULL DEFAULT 0,
                losses INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (guild_id, user_id)
            );

            CREATE TABLE IF NOT EXISTS provider_config (
                guild_id INTEGER NOT NULL,
                provider TEXT NOT NULL,
                token TEXT NOT NULL,
                PRIMARY KEY (guild_id, provider)
            );

            CREATE TABLE IF NOT EXISTS account_links (
                guild_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                platform TEXT NOT NULL,
                platform_id TEXT NOT NULL,
                PRIMARY KEY (guild_id, user_id)
            );

            CREATE TABLE IF NOT EXISTS rank_roles (
                guild_id INTEGER NOT NULL,
                rank_bucket TEXT NOT NULL,
                role_id INTEGER NOT NULL,
                PRIMARY KEY (guild_id, rank_bucket)
            );
            """
        )
        self.conn.commit()

    def get_guild_config(self, guild_id: int) -> GuildConfig:
        row = self.conn.execute(
            "SELECT * FROM guild_config WHERE guild_id = ?", (guild_id,)
        ).fetchone()
        if not row:
            self.conn.execute("INSERT INTO guild_config(guild_id) VALUES(?)", (guild_id,))
            self.conn.commit()
            return GuildConfig(queue_size=6, queue_channel_id=0, results_channel_id=0)
        return GuildConfig(
            queue_size=row["queue_size"],
            queue_channel_id=row["queue_channel_id"] or 0,
            results_channel_id=row["results_channel_id"] or 0,
        )

    def set_channels(self, guild_id: int, queue_channel_id: int, results_channel_id: int):
        self.conn.execute(
            """
            INSERT INTO guild_config(guild_id, queue_channel_id, results_channel_id)
            VALUES(?, ?, ?)
            ON CONFLICT(guild_id) DO UPDATE SET
                queue_channel_id=excluded.queue_channel_id,
                results_channel_id=excluded.results_channel_id
            """,
            (guild_id, queue_channel_id, results_channel_id),
        )
        self.conn.commit()

    def set_queue_size(self, guild_id: int, queue_size: int):
        self.conn.execute(
            """
            INSERT INTO guild_config(guild_id, queue_size)
            VALUES(?, ?)
            ON CONFLICT(guild_id) DO UPDATE SET
                queue_size=excluded.queue_size
            """,
            (guild_id, queue_size),
        )
        self.conn.commit()

    def enqueue(self, guild_id: int, user_id: int) -> bool:
        try:
            self.conn.execute(
                "INSERT INTO queue_members(guild_id, user_id) VALUES(?, ?)",
                (guild_id, user_id),
            )
            self.conn.commit()
            return True
        except sqlite3.IntegrityError:
            return False

    def dequeue(self, guild_id: int, user_id: int) -> bool:
        cur = self.conn.execute(
            "DELETE FROM queue_members WHERE guild_id = ? AND user_id = ?",
            (guild_id, user_id),
        )
        self.conn.commit()
        return cur.rowcount > 0

    def dequeue_many(self, guild_id: int, user_ids: List[int]):
        if not user_ids:
            return
        placeholders = ",".join("?" for _ in user_ids)
        self.conn.execute(
            f"DELETE FROM queue_members WHERE guild_id = ? AND user_id IN ({placeholders})",
            (guild_id, *user_ids),
        )
        self.conn.commit()

    def queue_members(self, guild_id: int) -> List[int]:
        rows = self.conn.execute(
            "SELECT user_id FROM queue_members WHERE guild_id = ? ORDER BY joined_at ASC",
            (guild_id,),
        ).fetchall()
        return [r["user_id"] for r in rows]

    def create_match(self, guild_id: int, team_a: List[int], team_b: List[int]) -> int:
        cur = self.conn.execute(
            "INSERT INTO matches(guild_id, team_a, team_b) VALUES(?, ?, ?)",
            (guild_id, json.dumps(team_a), json.dumps(team_b)),
        )
        self.conn.commit()
        return cur.lastrowid

    def latest_pending_match(self, guild_id: int) -> Optional[sqlite3.Row]:
        return self.conn.execute(
            "SELECT * FROM matches WHERE guild_id = ? AND status = 'pending' ORDER BY id DESC LIMIT 1",
            (guild_id,),
        ).fetchone()

    def report_match(self, match_id: int, winner: str):
        self.conn.execute(
            "UPDATE matches SET status = 'reported', winner = ? WHERE id = ?",
            (winner, match_id),
        )
        self.conn.commit()

    def ensure_rating(self, guild_id: int, user_id: int):
        self.conn.execute(
            "INSERT OR IGNORE INTO ratings(guild_id, user_id) VALUES(?, ?)",
            (guild_id, user_id),
        )
        self.conn.commit()

    def update_result(self, guild_id: int, winners: List[int], losers: List[int], delta: int = 10):
        for uid in winners:
            self.ensure_rating(guild_id, uid)
            self.conn.execute(
                "UPDATE ratings SET mmr = mmr + ?, wins = wins + 1 WHERE guild_id = ? AND user_id = ?",
                (delta, guild_id, uid),
            )
        for uid in losers:
            self.ensure_rating(guild_id, uid)
            self.conn.execute(
                "UPDATE ratings SET mmr = mmr - ?, losses = losses + 1 WHERE guild_id = ? AND user_id = ?",
                (delta, guild_id, uid),
            )
        self.conn.commit()

    def leaderboard(self, guild_id: int, limit: int = 10) -> List[sqlite3.Row]:
        return self.conn.execute(
            "SELECT * FROM ratings WHERE guild_id = ? ORDER BY mmr DESC LIMIT ?",
            (guild_id, limit),
        ).fetchall()

    def set_provider_token(self, guild_id: int, provider: str, token: str):
        self.conn.execute(
            """
            INSERT INTO provider_config(guild_id, provider, token)
            VALUES(?, ?, ?)
            ON CONFLICT(guild_id, provider) DO UPDATE SET token=excluded.token
            """,
            (guild_id, provider, token),
        )
        self.conn.commit()

    def get_provider_token(self, guild_id: int, provider: str) -> Optional[str]:
        row = self.conn.execute(
            "SELECT token FROM provider_config WHERE guild_id = ? AND provider = ?",
            (guild_id, provider),
        ).fetchone()
        return row["token"] if row else None

    def link_account(self, guild_id: int, user_id: int, platform: str, platform_id: str):
        self.conn.execute(
            """
            INSERT INTO account_links(guild_id, user_id, platform, platform_id)
            VALUES(?, ?, ?, ?)
            ON CONFLICT(guild_id, user_id)
            DO UPDATE SET platform=excluded.platform, platform_id=excluded.platform_id
            """,
            (guild_id, user_id, platform, platform_id),
        )
        self.conn.commit()

    def get_link(self, guild_id: int, user_id: int) -> Optional[sqlite3.Row]:
        return self.conn.execute(
            "SELECT platform, platform_id FROM account_links WHERE guild_id = ? AND user_id = ?",
            (guild_id, user_id),
        ).fetchone()

    def set_rank_role(self, guild_id: int, rank_bucket: str, role_id: int):
        self.conn.execute(
            """
            INSERT INTO rank_roles(guild_id, rank_bucket, role_id)
            VALUES(?, ?, ?)
            ON CONFLICT(guild_id, rank_bucket) DO UPDATE SET role_id=excluded.role_id
            """,
            (guild_id, rank_bucket, role_id),
        )
        self.conn.commit()

    def rank_roles(self, guild_id: int) -> Dict[str, int]:
        rows = self.conn.execute(
            "SELECT rank_bucket, role_id FROM rank_roles WHERE guild_id = ?", (guild_id,)
        ).fetchall()
        return {r["rank_bucket"]: r["role_id"] for r in rows}


class QueueView(discord.ui.View):
    def __init__(self, bot: "SixMansBot"):
        super().__init__(timeout=None)
        self.bot_ref = bot

    @discord.ui.button(label="Join Queue", style=discord.ButtonStyle.success, custom_id="sixmans_join")
    async def join_queue(self, interaction: discord.Interaction, _: discord.ui.Button):
        await self.bot_ref.join_queue(interaction)

    @discord.ui.button(label="Leave Queue", style=discord.ButtonStyle.danger, custom_id="sixmans_leave")
    async def leave_queue(self, interaction: discord.Interaction, _: discord.ui.Button):
        await self.bot_ref.leave_queue(interaction)


class SixMansBot(commands.Bot):
    def __init__(self, store: SixMansStore):
        intents = discord.Intents.default()
        intents.guilds = True
        intents.members = True
        super().__init__(command_prefix="!", intents=intents)
        self.store = store

    async def setup_hook(self):
        self.add_view(QueueView(self))
        await self.tree.sync()

    async def on_ready(self):
        print(f"Logged in as {self.user} ({self.user.id})")

    async def join_queue(self, interaction: discord.Interaction):
        assert interaction.guild is not None
        guild_id = interaction.guild.id
        if not self.store.enqueue(guild_id, interaction.user.id):
            await interaction.response.send_message("You're already in queue.", ephemeral=True)
            return

        queue = self.store.queue_members(guild_id)
        cfg = self.store.get_guild_config(guild_id)
        await interaction.response.send_message(
            f"Joined queue. ({len(queue)}/{cfg.queue_size})",
            ephemeral=True,
        )
        if len(queue) >= cfg.queue_size:
            await self.pop_queue(interaction.guild, cfg, queue[: cfg.queue_size])

    async def leave_queue(self, interaction: discord.Interaction):
        assert interaction.guild is not None
        if not self.store.dequeue(interaction.guild.id, interaction.user.id):
            await interaction.response.send_message("You're not currently queued.", ephemeral=True)
            return
        await interaction.response.send_message("You left the queue.", ephemeral=True)

    async def pop_queue(self, guild: discord.Guild, cfg: GuildConfig, queued_ids: List[int]):
        self.store.dequeue_many(guild.id, queued_ids)
        shuffled = queued_ids[:]
        random.shuffle(shuffled)
        half = len(shuffled) // 2
        team_a = shuffled[:half]
        team_b = shuffled[half:]

        match_id = self.store.create_match(guild.id, team_a, team_b)
        mentions_a = " ".join(f"<@{uid}>" for uid in team_a)
        mentions_b = " ".join(f"<@{uid}>" for uid in team_b)

        channel = guild.get_channel(cfg.queue_channel_id) if cfg.queue_channel_id else None
        if isinstance(channel, discord.TextChannel):
            await channel.send(
                f"🚨 Queue popped! **Match #{match_id}**\n"
                f"**Blue:** {mentions_a}\n"
                f"**Orange:** {mentions_b}\n"
                "Use `/report blue` or `/report orange` in the results channel when series is done."
            )


class RankProvider:
    @staticmethod
    def normalize_rank_bucket(raw_rank: str) -> Optional[str]:
        text = raw_rank.lower().replace("_", " ").strip()
        text = re.sub(r"\s+", " ", text)
        if "supersonic" in text:
            return "supersonic legend"
        if "grand" in text and "champ" in text:
            return "grand champion"
        for bucket in RANK_BUCKETS:
            if bucket in text:
                return bucket
        return None

    async def fetch_latest_rank(self, token: str, platform: str, platform_id: str) -> Tuple[str, str]:
        headers = {"Authorization": token}
        params = {
            "player-id": f"{platform}:{platform_id}",
            "playlist": "ranked-doubles",
            "count": 1,
            "sort-by": "replay-date",
            "sort-dir": "desc",
        }

        async with aiohttp.ClientSession() as session:
            async with session.get(f"{BALLCHASING_API}/replays", headers=headers, params=params, timeout=20) as res:
                if res.status != 200:
                    body = await res.text()
                    raise RuntimeError(f"ballchasing API error ({res.status}): {body[:120]}")
                data = await res.json()

            replay_list = data.get("list", [])
            if not replay_list:
                raise RuntimeError(
                    "No ranked 2v2 replays found for this account. Upload recent replays first."
                )

            replay_id = replay_list[0].get("id")
            async with session.get(f"{BALLCHASING_API}/replays/{replay_id}", headers=headers, timeout=20) as res:
                if res.status != 200:
                    body = await res.text()
                    raise RuntimeError(f"ballchasing replay detail error ({res.status}): {body[:120]}")
                replay = await res.json()

        raw = self._extract_rank_from_replay(replay, platform, platform_id)
        bucket = self.normalize_rank_bucket(raw)
        if not bucket:
            raise RuntimeError(f"Unable to map rank '{raw}' to configured Discord buckets")
        return raw, bucket

    def _extract_rank_from_replay(self, replay: dict, platform: str, platform_id: str) -> str:
        norm_id = platform_id.lower()
        for team_name in ("blue", "orange"):
            team = replay.get(team_name, {})
            for player in team.get("players", []):
                pid = (player.get("id", {}) or {})
                if str(pid.get("platform", "")).lower() != platform.lower():
                    continue
                if str(pid.get("id", "")).lower() != norm_id:
                    continue

                rank_block = player.get("rank") or {}
                if isinstance(rank_block, dict):
                    for key in ("name", "tier", "rank"):
                        value = rank_block.get(key)
                        if isinstance(value, str) and value.strip():
                            return value

                for key in ("rank", "tier"):
                    value = player.get(key)
                    if isinstance(value, str) and value.strip():
                        return value

        minimum_rank = replay.get("min_rank") or replay.get("max_rank")
        if minimum_rank:
            return str(minimum_rank)

        raise RuntimeError("Replay found, but no rank field could be extracted for this account")


def build_embed(title: str, description: str):
    return discord.Embed(title=title, description=description, color=discord.Color.blurple())


config = load_config()
store = SixMansStore(DB_PATH)
bot = SixMansBot(store)
rank_provider = RankProvider()


@bot.tree.command(name="setup", description="Configure queue and result channels")
@app_commands.checks.has_permissions(administrator=True)
async def setup(
    interaction: discord.Interaction,
    queue_channel: discord.TextChannel,
    results_channel: discord.TextChannel,
):
    assert interaction.guild is not None
    store.set_channels(interaction.guild.id, queue_channel.id, results_channel.id)
    embed = build_embed(
        "6Mans setup complete",
        f"Queue channel: {queue_channel.mention}\nResults channel: {results_channel.mention}",
    )
    await interaction.response.send_message(embed=embed)


@bot.tree.command(name="set_queue_size", description="Set player count needed to pop queue")
@app_commands.checks.has_permissions(administrator=True)
async def set_queue_size(interaction: discord.Interaction, size: app_commands.Range[int, 4, 12]):
    assert interaction.guild is not None
    store.set_queue_size(interaction.guild.id, size)
    await interaction.response.send_message(f"Queue size set to {size}.")


@bot.tree.command(name="queue_panel", description="Post queue join/leave buttons")
@app_commands.checks.has_permissions(administrator=True)
async def queue_panel(interaction: discord.Interaction):
    embed = build_embed(
        "Rocket League 6Mans Queue",
        "Use the buttons below to join or leave queue. When the queue fills, teams are auto-generated.",
    )
    await interaction.response.send_message(embed=embed, view=QueueView(bot))


@bot.tree.command(name="set_ballchasing_token", description="Admin: set Ballchasing API token for rank sync")
@app_commands.checks.has_permissions(administrator=True)
async def set_ballchasing_token(interaction: discord.Interaction, token: str):
    assert interaction.guild is not None
    store.set_provider_token(interaction.guild.id, "ballchasing", token)
    await interaction.response.send_message(
        "Saved Ballchasing API token for this server.", ephemeral=True
    )


@bot.tree.command(name="link_rl_account", description="Link your Rocket League account id for rank sync")
@app_commands.describe(platform="epic/steam/ps4/xbox", platform_id="Your platform account id")
async def link_rl_account(interaction: discord.Interaction, platform: str, platform_id: str):
    assert interaction.guild is not None
    store.link_account(
        interaction.guild.id,
        interaction.user.id,
        platform=platform.lower().strip(),
        platform_id=platform_id.strip(),
    )
    await interaction.response.send_message(
        f"Linked account: **{platform.lower()}:{platform_id}**", ephemeral=True
    )


@bot.tree.command(name="set_rank_role", description="Map a Rocket League rank bucket to a Discord role")
@app_commands.checks.has_permissions(administrator=True)
@app_commands.describe(rank_bucket="bronze/silver/gold/platinum/diamond/champion/grand champion/supersonic legend")
async def set_rank_role(interaction: discord.Interaction, rank_bucket: str, role: discord.Role):
    assert interaction.guild is not None
    bucket = rank_provider.normalize_rank_bucket(rank_bucket)
    if not bucket:
        await interaction.response.send_message("Invalid rank bucket.", ephemeral=True)
        return

    store.set_rank_role(interaction.guild.id, bucket, role.id)
    await interaction.response.send_message(
        f"Mapped **{bucket.title()}** -> {role.mention}",
        ephemeral=True,
    )


@bot.tree.command(name="show_rank_map", description="Show rank to role mappings")
async def show_rank_map(interaction: discord.Interaction):
    assert interaction.guild is not None
    mappings = store.rank_roles(interaction.guild.id)
    if not mappings:
        await interaction.response.send_message("No rank-role mappings configured yet.", ephemeral=True)
        return

    lines = []
    for bucket, role_id in sorted(mappings.items()):
        lines.append(f"**{bucket.title()}** -> <@&{role_id}>")
    await interaction.response.send_message(embed=build_embed("Rank Role Map", "\n".join(lines)))


@bot.tree.command(name="sync_rank", description="Sync your linked Rocket League rank to Discord role")
async def sync_rank(interaction: discord.Interaction, member: Optional[discord.Member] = None):
    assert interaction.guild is not None
    target = member or interaction.user

    link = store.get_link(interaction.guild.id, target.id)
    if not link:
        await interaction.response.send_message(
            f"{target.mention} has not linked an account. Use `/link_rl_account` first.",
            ephemeral=True,
        )
        return

    token = store.get_provider_token(interaction.guild.id, "ballchasing")
    if not token:
        await interaction.response.send_message(
            "Ballchasing token is not configured. Admin must run `/set_ballchasing_token`.",
            ephemeral=True,
        )
        return

    await interaction.response.defer(ephemeral=True)

    raw_rank, bucket = await rank_provider.fetch_latest_rank(
        token=token,
        platform=link["platform"],
        platform_id=link["platform_id"],
    )

    mappings = store.rank_roles(interaction.guild.id)
    target_role_id = mappings.get(bucket)
    if not target_role_id:
        await interaction.followup.send(
            f"Detected rank **{raw_rank}** ({bucket}), but no role is mapped for that bucket.",
            ephemeral=True,
        )
        return

    guild = interaction.guild
    all_rank_role_ids = set(mappings.values())
    remove_roles = [r for r in target.roles if r.id in all_rank_role_ids and r.id != target_role_id]
    add_role = guild.get_role(target_role_id)

    if not add_role:
        await interaction.followup.send(
            "Mapped role no longer exists in server.", ephemeral=True
        )
        return

    if remove_roles:
        await target.remove_roles(*remove_roles, reason="6Mans rank sync role update")
    if add_role not in target.roles:
        await target.add_roles(add_role, reason="6Mans rank sync role update")

    await interaction.followup.send(
        f"Synced {target.mention}: detected **{raw_rank}** -> assigned {add_role.mention}",
        ephemeral=True,
    )


@bot.tree.command(name="my_link", description="Show your currently linked Rocket League account")
async def my_link(interaction: discord.Interaction):
    assert interaction.guild is not None
    link = store.get_link(interaction.guild.id, interaction.user.id)
    if not link:
        await interaction.response.send_message("No account linked yet.", ephemeral=True)
        return
    await interaction.response.send_message(
        f"Linked: **{link['platform']}:{link['platform_id']}**", ephemeral=True
    )


@bot.tree.command(name="report", description="Report winner for latest pending match")
@app_commands.describe(winner="Team that won the match")
@app_commands.choices(
    winner=[
        app_commands.Choice(name="blue", value="blue"),
        app_commands.Choice(name="orange", value="orange"),
    ]
)
async def report(interaction: discord.Interaction, winner: app_commands.Choice[str]):
    assert interaction.guild is not None
    cfg = store.get_guild_config(interaction.guild.id)
    if cfg.results_channel_id and interaction.channel_id != cfg.results_channel_id:
        await interaction.response.send_message(
            "Use this command in the configured results channel.", ephemeral=True
        )
        return

    match = store.latest_pending_match(interaction.guild.id)
    if not match:
        await interaction.response.send_message("No pending match to report.", ephemeral=True)
        return

    team_a = json.loads(match["team_a"])
    team_b = json.loads(match["team_b"])
    winners, losers = (team_a, team_b) if winner.value == "blue" else (team_b, team_a)

    store.report_match(match["id"], winner.value)
    store.update_result(interaction.guild.id, winners, losers)
    await interaction.response.send_message(
        f"Recorded result for Match #{match['id']}: **{winner.value.title()}** won."
    )


@bot.tree.command(name="leaderboard", description="Top players by 6Mans MMR")
async def leaderboard(interaction: discord.Interaction):
    assert interaction.guild is not None
    rows = store.leaderboard(interaction.guild.id, 10)
    if not rows:
        await interaction.response.send_message("No ranked results yet.")
        return

    lines = []
    for idx, row in enumerate(rows, start=1):
        lines.append(
            f"{idx}. <@{row['user_id']}> — **{row['mmr']}** MMR ({row['wins']}-{row['losses']})"
        )
    await interaction.response.send_message(embed=build_embed("6Mans Leaderboard", "\n".join(lines)))


if __name__ == "__main__":
    bot.run(config["discord_token"])
