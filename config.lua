Config = {}

Config.MenuCommand = 'weathermenu'
Config.MenuKey = 'F7'

Config.UseAcePermissions = true
Config.AcePermission = 'weather.control'

Config.UseDiscordRoles = true
Config.BadgerResourceName = 'Badger_Discord_API'
Config.DiscordRoleIds = {
    '000000000000000000',
    '111111111111111111'
}

Config.WeatherTypes = {
    { id = 'CLEAR', label = 'Clear', description = 'Clear sky' },
    { id = 'EXTRASUNNY', label = 'Extra Sunny', description = 'Very sunny' },
    { id = 'CLOUDS', label = 'Clouds', description = 'Cloudy' },
    { id = 'OVERCAST', label = 'Overcast', description = 'Overcast' },
    { id = 'RAIN', label = 'Rain', description = 'Rain' },
    { id = 'THUNDER', label = 'Thunder', description = 'Storm' },
    { id = 'CLEARING', label = 'Clearing', description = 'Clearing up' },
    { id = 'SMOG', label = 'Smog', description = 'Pollution' },
    { id = 'FOGGY', label = 'Foggy', description = 'Fog' },
    { id = 'SNOW', label = 'Snow', description = 'Light snow' },
    { id = 'BLIZZARD', label = 'Blizzard', description = 'Snow storm' },
    { id = 'XMAS', label = 'Christmas', description = 'Christmas snow' }
}

Config.DefaultWeather = 'CLEAR'
Config.DefaultHour = 12
Config.DefaultMinute = 0

Config.LogLimit = 200

-- Weather control
Config.TransitionDuration = 15.0
Config.WeatherBlacklist = {
    'HALLOWEEN'
}

Config.WeatherCycle = {
    Enabled = true,
    IntervalMinutes = 30,
    ForecastMinutes = 5,
    Probabilities = {
        CLEAR = 20,
        EXTRASUNNY = 15,
        CLOUDS = 15,
        OVERCAST = 10,
        RAIN = 10,
        THUNDER = 5,
        CLEARING = 5,
        SMOG = 5,
        FOGGY = 5,
        SNOW = 5,
        BLIZZARD = 2,
        XMAS = 3
    }
}

-- Time control
Config.Time = {
    AutoProgression = true,
    SyncIntervalSeconds = 10
}

-- Voting system
Config.Voting = {
    Enabled = true,
    DurationSeconds = 90,
    MinimumVotes = 1
}

-- Scheduler
Config.Scheduler = {
    Enabled = true,
    StorageFile = 'data/schedules.json'
}

-- Temperature system
Config.Temperature = {
    Enabled = true,
    BaseByWeather = {
        CLEAR = 22,
        EXTRASUNNY = 28,
        CLOUDS = 20,
        OVERCAST = 18,
        RAIN = 16,
        THUNDER = 15,
        CLEARING = 19,
        SMOG = 21,
        FOGGY = 14,
        SNOW = 0,
        BLIZZARD = -5,
        XMAS = -2
    },
    AltitudeStep = 100.0,
    AltitudeModifier = -1.0,
    VehicleProtection = 0.6,
    SwimmingPenalty = -4.0,
    FireWarmthBonus = 5.0,
    RunningWarmthBonus = 2.0,
    TransitionSpeed = 0.05,
    ClothingWarmth = {
        [11] = 1.5, -- torso
        [4] = 1.0,  -- legs
        [6] = 0.5   -- shoes
    }
}
