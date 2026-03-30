# Rocket League 6Mans-Style Discord Bot

This bot now supports both:
- **6Mans queue + matchmaking workflow**, and
- **Rocket League account rank -> Discord role sync** (via Ballchasing replay API).

## What this bot does

### 1) 6Mans queue system
- `/queue_panel` posts Join/Leave buttons.
- Queue pops automatically at configured size (default 6).
- Teams are auto-generated (Blue vs Orange).
- `/report` records match winner.
- `/leaderboard` shows internal 6Mans MMR.

### 2) Rocket League rank role sync (advanced)
- Players link their RL account with `/link_rl_account`.
- Admin sets Ballchasing API token with `/set_ballchasing_token`.
- Admin maps RL rank buckets to Discord roles with `/set_rank_role`.
- `/sync_rank` fetches the linked account's latest detected ranked replay rank and updates Discord role.

This gives you the “your real RL rank = server role” flow.

---

## Important note about “exactly like official 6Mans bot”
Rocket League does not provide a simple public official endpoint for direct rank lookup in this project. This implementation uses **Ballchasing replay data** as a practical rank source. If a linked account has no recent ranked replays uploaded, rank sync will fail until replays are available.

---

## Setup

### 1) Discord bot setup
1. Create an app + bot in Discord Developer Portal.
2. Enable scopes: `bot`, `applications.commands`.
3. Permissions: Send Messages, Use Application Commands, Manage Roles, Read Message History, Embed Links.
4. Ensure bot role is **above** rank roles in server role hierarchy.

### 2) Install
```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 3) Configure token
```bash
cp config.example.json config.json
```
Set `discord_token` in `config.json`.

### 4) Run
```bash
python bot.py
```

---

## Command reference

### Admin commands
- `/setup queue_channel:<channel> results_channel:<channel>`
- `/set_queue_size size:<4-12>`
- `/queue_panel`
- `/set_ballchasing_token token:<api_token>`
- `/set_rank_role rank_bucket:<rank> role:<discord_role>`
- `/show_rank_map`

### Player commands
- `/link_rl_account platform:<epic|steam|ps4|xbox> platform_id:<id>`
- `/my_link`
- `/sync_rank`
- `/report winner:<blue|orange>`
- `/leaderboard`

---

## Rank buckets you can map
- bronze
- silver
- gold
- platinum
- diamond
- champion
- grand champion
- supersonic legend

---

## Download this project

### Option A: Git clone (recommended)
```bash
git clone <your-repo-url>
cd Custom-HeadTag-Script-FiveM
```

### Option B: GitHub ZIP download
1. Open your repository page on GitHub.
2. Click **Code**.
3. Click **Download ZIP**.
4. Extract, then run setup steps above.
