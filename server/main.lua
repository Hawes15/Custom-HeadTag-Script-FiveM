local logs = {}
local schedules = {}
local voteState = nil

local weatherState = {
    weather = Config.DefaultWeather,
    hour = Config.DefaultHour,
    minute = Config.DefaultMinute,
    freezeTime = false,
    freezeWeather = false,
    rain = 0,
    fog = 0,
    wind = 0,
    tempOverride = nil
}

local function addLog(sourceId, action, detail)
    local name = sourceId and GetPlayerName(sourceId) or 'System'
    local entry = {
        time = os.date('%H:%M:%S'),
        actor = name,
        action = action,
        detail = detail
    }

    table.insert(logs, 1, entry)
    if #logs > Config.LogLimit then
        logs[#logs] = nil
    end

    TriggerClientEvent('hawes-weather:receiveLogs', -1, logs)
end

local function hasAcePermission(sourceId)
    if not Config.UseAcePermissions then
        return false
    end

    return IsPlayerAceAllowed(sourceId, Config.AcePermission)
end

local function hasDiscordRole(sourceId)
    if not Config.UseDiscordRoles then
        return false
    end

    local resourceName = Config.BadgerResourceName or 'Badger_Discord_API'
    if GetResourceState(resourceName) ~= 'started' then
        return false
    end

    local ok, roles = pcall(function()
        return exports[resourceName]:GetDiscordRoles(sourceId)
    end)

    if not ok or type(roles) ~= 'table' then
        return false
    end

    for _, roleId in ipairs(Config.DiscordRoleIds) do
        for _, userRole in ipairs(roles) do
            if tostring(userRole) == tostring(roleId) then
                return true
            end
        end
    end

    return false
end

local function hasAccess(sourceId)
    if hasAcePermission(sourceId) then
        return true
    end

    if hasDiscordRole(sourceId) then
        return true
    end

    return false
end

local function broadcastState()
    TriggerClientEvent('hawes-weather:applyWeather', -1, weatherState.weather, weatherState.freezeWeather, Config.TransitionDuration)
    TriggerClientEvent('hawes-weather:applyTime', -1, weatherState.hour, weatherState.minute, weatherState.freezeTime)
    TriggerClientEvent('hawes-weather:applyEnvironment', -1, weatherState.rain, weatherState.fog, weatherState.wind)
end

local function sendStateTo(sourceId)
    TriggerClientEvent('hawes-weather:receiveState', sourceId, weatherState, logs, schedules, voteState)
end

local function isWeatherAllowed(weatherId)
    if not Config.WeatherBlacklist then
        return true
    end
    for _, blocked in ipairs(Config.WeatherBlacklist) do
        if blocked == weatherId then
            return false
        end
    end
    return true
end

local function getWeatherPool()
    local pool = {}
    for _, weather in ipairs(Config.WeatherTypes) do
        if isWeatherAllowed(weather.id) then
            table.insert(pool, weather.id)
        end
    end
    return pool
end

local function chooseRandomWeather()
    local pool = getWeatherPool()
    local totalWeight = 0
    for _, weatherId in ipairs(pool) do
        totalWeight = totalWeight + (Config.WeatherCycle.Probabilities[weatherId] or 1)
    end

    local pick = math.random() * totalWeight
    local running = 0
    for _, weatherId in ipairs(pool) do
        running = running + (Config.WeatherCycle.Probabilities[weatherId] or 1)
        if pick <= running then
            return weatherId
        end
    end

    return pool[1] or Config.DefaultWeather
end

local function ensureStoragePath()
    if not Config.Scheduler or not Config.Scheduler.StorageFile then
        return
    end

    local dir = Config.Scheduler.StorageFile:match('(.+)/[^/]+$')
    if dir then
        if type(CreateDirectory) == 'function' then
            CreateDirectory(dir)
        else
            os.execute(('mkdir -p %s'):format(dir))
        end
    end
end

local function loadSchedules()
    if not Config.Scheduler.Enabled then
        return
    end

    ensureStoragePath()
    local content = LoadResourceFile(GetCurrentResourceName(), Config.Scheduler.StorageFile)
    if content then
        local ok, decoded = pcall(json.decode, content)
        if ok and type(decoded) == 'table' then
            schedules = decoded
        end
    end
end

local function saveSchedules()
    if not Config.Scheduler.Enabled then
        return
    end

    ensureStoragePath()
    SaveResourceFile(GetCurrentResourceName(), Config.Scheduler.StorageFile, json.encode(schedules, { indent = true }), -1)
end

local function applySchedule(schedule)
    weatherState.weather = schedule.weather
    weatherState.rain = schedule.rain or weatherState.rain
    weatherState.fog = schedule.fog or weatherState.fog
    weatherState.wind = schedule.wind or weatherState.wind
    weatherState.tempOverride = schedule.temp
    weatherState.hour = schedule.hour
    weatherState.minute = schedule.minute
    broadcastState()
    addLog(nil, 'Schedule', ('Applied schedule %s (%s)'):format(schedule.id, schedule.weather))
end

local function startVote(reason)
    if voteState then
        return
    end

    local options = getWeatherPool()
    if #options == 0 then
        return
    end

    voteState = {
        active = true,
        endsAt = os.time() + Config.Voting.DurationSeconds,
        options = options,
        votes = {},
        reason = reason or 'Auto Cycle'
    }

    TriggerClientEvent('hawes-weather:voteStarted', -1, voteState)
    addLog(nil, 'Voting', 'Weather vote started')
end

local function finishVote()
    if not voteState then
        return
    end

    local tally = {}
    local totalVotes = 0

    for _, weatherId in pairs(voteState.votes) do
        tally[weatherId] = (tally[weatherId] or 0) + 1
        totalVotes = totalVotes + 1
    end

    if totalVotes < Config.Voting.MinimumVotes then
        addLog(nil, 'Voting', 'Vote skipped (not enough votes)')
        voteState = nil
        TriggerClientEvent('hawes-weather:voteEnded', -1, nil)
        return
    end

    local winningWeather
    local winningVotes = -1
    for weatherId, count in pairs(tally) do
        if count > winningVotes then
            winningWeather = weatherId
            winningVotes = count
        end
    end

    if winningWeather then
        weatherState.weather = winningWeather
        broadcastState()
        addLog(nil, 'Voting', ('Winning weather %s with %d votes'):format(winningWeather, winningVotes))
    end

    voteState = nil
    TriggerClientEvent('hawes-weather:voteEnded', -1, winningWeather)
end

RegisterNetEvent('hawes-weather:requestState', function()
    sendStateTo(source)
end)

RegisterNetEvent('hawes-weather:setWeather', function(weatherId)
    local sourceId = source
    if not hasAccess(sourceId) then
        return
    end

    if not isWeatherAllowed(weatherId) then
        return
    end

    weatherState.weather = weatherId
    broadcastState()
    addLog(sourceId, 'Weather', ('Changed weather to %s'):format(weatherId))
end)

RegisterNetEvent('hawes-weather:setTime', function(hour, minute)
    local sourceId = source
    if not hasAccess(sourceId) then
        return
    end

    weatherState.hour = math.max(0, math.min(23, tonumber(hour) or weatherState.hour))
    weatherState.minute = math.max(0, math.min(59, tonumber(minute) or weatherState.minute))
    broadcastState()
    addLog(sourceId, 'Time', ('Changed time to %02d:%02d'):format(weatherState.hour, weatherState.minute))
end)

RegisterNetEvent('hawes-weather:toggleFreezeTime', function()
    local sourceId = source
    if not hasAccess(sourceId) then
        return
    end

    weatherState.freezeTime = not weatherState.freezeTime
    broadcastState()
    addLog(sourceId, 'Time Freeze', weatherState.freezeTime and 'Enabled time freeze' or 'Disabled time freeze')
end)

RegisterNetEvent('hawes-weather:toggleFreezeWeather', function()
    local sourceId = source
    if not hasAccess(sourceId) then
        return
    end

    weatherState.freezeWeather = not weatherState.freezeWeather
    broadcastState()
    addLog(sourceId, 'Weather Freeze', weatherState.freezeWeather and 'Enabled weather freeze' or 'Disabled weather freeze')
end)

RegisterNetEvent('hawes-weather:requestOpenMenu', function()
    local sourceId = source
    if not hasAccess(sourceId) then
        TriggerClientEvent('chat:addMessage', sourceId, {
            color = { 255, 80, 80 },
            args = { 'Weather', 'You do not have permission to open the menu.' }
        })
        return
    end

    TriggerClientEvent('hawes-weather:openMenu', sourceId)
end)

RegisterNetEvent('hawes-weather:addSchedule', function(schedule)
    local sourceId = source
    if not hasAccess(sourceId) or not Config.Scheduler.Enabled then
        return
    end

    schedule.id = schedule.id or tostring(os.time() .. math.random(100, 999))
    table.insert(schedules, schedule)
    saveSchedules()
    addLog(sourceId, 'Schedule', ('Added schedule %s (%s)'):format(schedule.id, schedule.weather))
    TriggerClientEvent('hawes-weather:receiveSchedules', -1, schedules)
end)

RegisterNetEvent('hawes-weather:deleteSchedule', function(scheduleId)
    local sourceId = source
    if not hasAccess(sourceId) or not Config.Scheduler.Enabled then
        return
    end

    for index, entry in ipairs(schedules) do
        if entry.id == scheduleId then
            table.remove(schedules, index)
            break
        end
    end

    saveSchedules()
    addLog(sourceId, 'Schedule', ('Deleted schedule %s'):format(scheduleId))
    TriggerClientEvent('hawes-weather:receiveSchedules', -1, schedules)
end)

RegisterNetEvent('hawes-weather:startVote', function(reason)
    local sourceId = source
    if not hasAccess(sourceId) or not Config.Voting.Enabled then
        return
    end

    startVote(reason or 'Manual Vote')
end)

RegisterNetEvent('hawes-weather:castVote', function(weatherId)
    if not Config.Voting.Enabled or not voteState then
        return
    end

    local sourceId = source
    if not isWeatherAllowed(weatherId) then
        return
    end

    voteState.votes[tostring(sourceId)] = weatherId
    TriggerClientEvent('hawes-weather:voteUpdate', -1, voteState)
end)

RegisterCommand('voteweather', function(sourceId, args)
    if sourceId == 0 or not Config.Voting.Enabled then
        return
    end

    local weatherId = args[1]
    if not weatherId or not voteState then
        TriggerClientEvent('chat:addMessage', sourceId, {
            color = { 255, 255, 120 },
            args = { 'Weather', 'No active vote right now.' }
        })
        return
    end

    TriggerEvent('hawes-weather:castVote', weatherId)
end)

RegisterNetEvent('hawes-weather:playerReady', function()
    sendStateTo(source)
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    loadSchedules()
    broadcastState()
    addLog(nil, 'System', 'Weather control started')
end)

CreateThread(function()
    while true do
        Wait(Config.Time.SyncIntervalSeconds * 1000)
        if Config.Time.AutoProgression and not weatherState.freezeTime then
            weatherState.minute = weatherState.minute + 1
            if weatherState.minute >= 60 then
                weatherState.minute = 0
                weatherState.hour = (weatherState.hour + 1) % 24
            end
            broadcastState()
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)

        if Config.Voting.Enabled and voteState and os.time() >= voteState.endsAt then
            finishVote()
        end
    end
end)

CreateThread(function()
    while true do
        Wait(60000)
        if not Config.Scheduler.Enabled then
            goto continue
        end

        local now = os.date('*t')
        for index, entry in ipairs(schedules) do
            if entry.hour == now.hour and entry.minute == now.min then
                applySchedule(entry)
                if not entry.recurring then
                    table.remove(schedules, index)
                end
            end
        end
        saveSchedules()
        ::continue::
    end
end)

CreateThread(function()
    if not Config.WeatherCycle.Enabled then
        return
    end

    while true do
        Wait(Config.WeatherCycle.IntervalMinutes * 60000)
        if weatherState.freezeWeather then
            goto continue
        end

        if Config.Voting.Enabled then
            TriggerClientEvent('hawes-weather:forecast', -1, Config.WeatherCycle.ForecastMinutes)
            Wait(Config.WeatherCycle.ForecastMinutes * 60000)
            startVote('Auto Cycle')
            Wait(Config.Voting.DurationSeconds * 1000)
            if voteState then
                finishVote()
            end
        else
            weatherState.weather = chooseRandomWeather()
            broadcastState()
            addLog(nil, 'Auto Cycle', ('Auto cycled weather to %s'):format(weatherState.weather))
        end
        ::continue::
    end
end)

exports('GetWeatherState', function()
    return weatherState
end)

exports('SetWeather', function(weatherId)
    if not isWeatherAllowed(weatherId) then
        return false
    end
    weatherState.weather = weatherId
    broadcastState()
    return true
end)

exports('SetTime', function(hour, minute)
    weatherState.hour = math.max(0, math.min(23, tonumber(hour) or weatherState.hour))
    weatherState.minute = math.max(0, math.min(59, tonumber(minute) or weatherState.minute))
    broadcastState()
    return true
end)

exports('StartVote', function(reason)
    if not Config.Voting.Enabled then
        return false
    end
    startVote(reason)
    return true
end)
