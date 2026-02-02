# Hawes Weather Control

High-quality weather control for FiveM with ACE permissions or Badger Discord API role checks. Includes automated cycling, scheduling, voting, and a realistic body temperature system.

## Features
- **Comprehensive weather control**: 12+ weather types, smooth transitions, weather freeze, and blacklist support.
- **Time management**: custom time setting, time freeze, and optional auto-progression.
- **Democratic weather voting**: forecast alerts, voting duration, live vote counts, and majority wins.
- **Advanced scheduling**: schedule weather changes with optional temperature/rain/fog/wind values, recurring or one-time, persisted to disk.
- **Realistic temperature system**: clothing, altitude, swimming penalties, fire warmth, and running warmup with smooth transitions.
- **Exports/API**: programmatic get/set for weather, time, and temperature.

## Requirements
- **Badger Discord API** (optional if you only use ACE perms)

## Installation
1. Drop this resource into your server resources folder.
2. Add `ensure hawes-weather-control` (or your folder name) to `server.cfg`.
3. Configure permissions, weather probabilities, and temperature tuning in `config.lua`.

## Commands
- `/weathermenu` — Opens the weather control menu for authorized users.
- `/voteweather <WEATHER>` — Cast a vote during an active weather vote.

## Permissions
### ACE
Add an ACE permission in your `server.cfg`:
```
add_ace group.admin weather.control allow
```

### Discord Roles
Add the Discord role IDs to `Config.DiscordRoleIds` in `config.lua` and make sure your Badger Discord API resource is running.

## Configuration
Edit `config.lua` for:
- Menu command, keybind, and permission setup.
- Weather probabilities, blacklist, transition duration, and cycle intervals.
- Time auto-progression and sync interval.
- Voting duration and minimum votes.
- Schedule persistence file.
- Temperature tuning and clothing warmth values.

## Exports
### Server
- `exports['hawes-weather-control']:GetWeatherState()`
- `exports['hawes-weather-control']:SetWeather(weatherId)`
- `exports['hawes-weather-control']:SetTime(hour, minute)`
- `exports['hawes-weather-control']:StartVote(reason)`

### Client
- `exports['hawes-weather-control']:GetBodyTemperature()`
