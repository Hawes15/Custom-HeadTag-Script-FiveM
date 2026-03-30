local isMenuOpen = false
local currentWeather = Config.DefaultWeather
local freezeWeather = false
local freezeTime = false
local currentHour = Config.DefaultHour
local currentMinute = Config.DefaultMinute
local rainLevel = 0
local fogLevel = 0
local windLevel = 0
local tempOverride = nil
local schedules = {}
local voteState = nil

local temperatureState = {
    current = 20,
    target = 20
}

local function applyWeather(weatherId, freeze, transition)
    currentWeather = weatherId
    freezeWeather = freeze

    ClearWeatherTypePersist()
    SetWeatherTypeNowPersist(weatherId)
    SetWeatherTypeNow(weatherId)
    SetWeatherTypeOverTime(weatherId, transition or Config.TransitionDuration)
    if freeze then
        ClearWeatherTypePersist()
        SetWeatherTypePersist(weatherId)
    end
end

local function applyTime(hour, minute, freeze)
    currentHour = hour
    currentMinute = minute
    freezeTime = freeze

    NetworkOverrideClockTime(hour, minute, 0)
end

local function applyEnvironment(rain, fog, wind)
    rainLevel = rain or rainLevel
    fogLevel = fog or fogLevel
    windLevel = wind or windLevel

    if SetRainFxIntensity then
        SetRainFxIntensity((rainLevel or 0) / 100.0)
    end
    if SetWindSpeed then
        SetWindSpeed((windLevel or 0) / 100.0)
    end
end

local function calculateTemperature()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local base = tempOverride or Config.Temperature.BaseByWeather[currentWeather] or 20
    local altitudeDelta = math.floor(coords.z / Config.Temperature.AltitudeStep) * Config.Temperature.AltitudeModifier

    local warmth = 0
    for componentId, bonus in pairs(Config.Temperature.ClothingWarmth) do
        local drawable = GetPedDrawableVariation(ped, componentId)
        if drawable and drawable > 0 then
            warmth = warmth + bonus
        end
    end

    if IsPedInAnyVehicle(ped, false) then
        local diff = base - 22
        base = base - (diff * Config.Temperature.VehicleProtection)
    end

    if IsPedSwimming(ped) or IsPedInWater(ped) then
        base = base + Config.Temperature.SwimmingPenalty
    end

    if IsPedRunning(ped) or IsPedSprinting(ped) then
        base = base + Config.Temperature.RunningWarmthBonus
    end

    if GetNumberOfFiresInRange then
        local fires = GetNumberOfFiresInRange(coords.x, coords.y, coords.z, 5.0)
        if fires and fires > 0 then
            base = base + Config.Temperature.FireWarmthBonus
        end
    end

    temperatureState.target = base + altitudeDelta + warmth
    temperatureState.current = temperatureState.current + (temperatureState.target - temperatureState.current) * Config.Temperature.TransitionSpeed
end

RegisterNetEvent('hawes-weather:applyWeather', function(weatherId, freeze, transition)
    applyWeather(weatherId, freeze, transition)
end)

RegisterNetEvent('hawes-weather:applyTime', function(hour, minute, freeze)
    applyTime(hour, minute, freeze)
end)

RegisterNetEvent('hawes-weather:applyEnvironment', function(rain, fog, wind)
    applyEnvironment(rain, fog, wind)
end)

RegisterNetEvent('hawes-weather:receiveState', function(state, logs, scheduleList, vote)
    currentWeather = state.weather
    currentHour = state.hour
    currentMinute = state.minute
    freezeTime = state.freezeTime
    freezeWeather = state.freezeWeather
    rainLevel = state.rain or 0
    fogLevel = state.fog or 0
    windLevel = state.wind or 0
    tempOverride = state.tempOverride
    schedules = scheduleList or {}
    voteState = vote

    SendNUIMessage({
        type = 'state',
        state = {
            weather = currentWeather,
            hour = currentHour,
            minute = currentMinute,
            freezeTime = freezeTime,
            freezeWeather = freezeWeather,
            rain = rainLevel,
            fog = fogLevel,
            wind = windLevel,
            tempOverride = tempOverride,
            altitude = GetEntityCoords(PlayerPedId()).z,
            weatherTypes = Config.WeatherTypes,
            schedules = schedules,
            voteState = voteState,
            temperature = math.floor(temperatureState.current)
        },
        logs = logs or {}
    })

    applyWeather(currentWeather, freezeWeather, Config.TransitionDuration)
    applyTime(currentHour, currentMinute, freezeTime)
    applyEnvironment(rainLevel, fogLevel, windLevel)
end)

RegisterNetEvent('hawes-weather:receiveLogs', function(logs)
    SendNUIMessage({
        type = 'logs',
        logs = logs or {}
    })
end)

RegisterNetEvent('hawes-weather:receiveSchedules', function(scheduleList)
    schedules = scheduleList or {}
    SendNUIMessage({
        type = 'schedules',
        schedules = schedules
    })
end)

RegisterNetEvent('hawes-weather:voteStarted', function(vote)
    voteState = vote
    SendNUIMessage({
        type = 'vote',
        vote = vote
    })
    TriggerEvent('chat:addMessage', {
        color = { 120, 200, 255 },
        args = { 'Weather', 'Weather vote started! Use /voteweather <type>.' }
    })
end)

RegisterNetEvent('hawes-weather:voteUpdate', function(vote)
    voteState = vote
    SendNUIMessage({
        type = 'vote',
        vote = vote
    })
end)

RegisterNetEvent('hawes-weather:voteEnded', function(winning)
    voteState = nil
    SendNUIMessage({
        type = 'voteEnd',
        winning = winning
    })
end)

RegisterNetEvent('hawes-weather:forecast', function(minutes)
    TriggerEvent('chat:addMessage', {
        color = { 255, 200, 100 },
        args = { 'Weather', ('Forecast: vote starts in %d minutes.'):format(minutes) }
    })
end)

RegisterNetEvent('hawes-weather:openMenu', function()
    if isMenuOpen then
        return
    end

    isMenuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'open' })
    TriggerServerEvent('hawes-weather:requestState')
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    isMenuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'close' })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    isMenuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'close' })
end)

RegisterCommand('+hawesWeatherMenu', function()
    if not isMenuOpen then
        TriggerServerEvent('hawes-weather:requestOpenMenu')
    end
end, false)

RegisterCommand('-hawesWeatherMenu', function()
end, false)

RegisterKeyMapping('+hawesWeatherMenu', 'Open Weather Control Menu', 'keyboard', Config.MenuKey)

RegisterNUICallback('close', function(_, cb)
    isMenuOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('setWeather', function(data, cb)
    TriggerServerEvent('hawes-weather:setWeather', data.weather)
    cb('ok')
end)

RegisterNUICallback('setTime', function(data, cb)
    TriggerServerEvent('hawes-weather:setTime', data.hour, data.minute)
    cb('ok')
end)

RegisterNUICallback('toggleFreezeTime', function(_, cb)
    TriggerServerEvent('hawes-weather:toggleFreezeTime')
    cb('ok')
end)

RegisterNUICallback('toggleFreezeWeather', function(_, cb)
    TriggerServerEvent('hawes-weather:toggleFreezeWeather')
    cb('ok')
end)

RegisterNUICallback('addSchedule', function(data, cb)
    TriggerServerEvent('hawes-weather:addSchedule', data)
    cb('ok')
end)

RegisterNUICallback('deleteSchedule', function(data, cb)
    TriggerServerEvent('hawes-weather:deleteSchedule', data.id)
    cb('ok')
end)

RegisterNUICallback('startVote', function(data, cb)
    TriggerServerEvent('hawes-weather:startVote', data.reason)
    cb('ok')
end)

RegisterNUICallback('castVote', function(data, cb)
    TriggerServerEvent('hawes-weather:castVote', data.weather)
    cb('ok')
end)

RegisterNUICallback('ready', function(_, cb)
    cb('ok')
end)

CreateThread(function()
    TriggerServerEvent('hawes-weather:playerReady')
    while true do
        Wait(1000)
        if freezeTime then
            NetworkOverrideClockTime(currentHour, currentMinute, 0)
        end
        if freezeWeather then
            SetWeatherTypePersist(currentWeather)
        end
        if Config.Temperature.Enabled then
            calculateTemperature()
            SendNUIMessage({
                type = 'temperature',
                temperature = math.floor(temperatureState.current)
            })
        end
    end
end)

exports('GetBodyTemperature', function()
    return temperatureState.current, temperatureState.target
end)
