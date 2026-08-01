Gangs = Gangs or {}
Gangs.Zones = {}
Gangs.Wars = {}
Gangs.InsideZone = nil
Gangs.MenuOpen = false

RegisterNetEvent('gangs:client:notify', function(message, nType)
    Bridge.Notify(message, nType)
end)

RegisterNetEvent('gangs:client:syncZones', function(zones)
    Gangs.Zones = zones or {}
    TriggerEvent('gangs:client:zonesUpdated')
end)

RegisterNetEvent('gangs:client:syncWars', function(wars)
    Gangs.Wars = wars or {}
    TriggerEvent('gangs:client:warsUpdated')
end)

CreateThread(function()
    Wait(1500)
    TriggerServerEvent('gangs:server:requestSync')
end)

local function openMenu()
    local data = lib.callback.await('gangs:getMenuData', false)
    if not data then return end
    if data.error then
        Bridge.Notify(data.error, 'error')
        return
    end
    Gangs.MenuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })
end

RegisterNetEvent('gangs:client:openMenu', openMenu)

RegisterCommand(Config.OpenCommand or 'criminal', function()
    openMenu()
end, false)

RegisterKeyMapping(Config.OpenCommand or 'criminal', 'Open Rebel Roleplay Criminal Tablet', 'keyboard', Config.OpenKey or 'F11')

-- Death / kill reporting for bounties + stats
CreateThread(function()
    local wasDead = false
    while true do
        Wait(500)
        local ped = PlayerPedId()
        local dead = IsEntityDead(ped) or IsPedFatallyInjured(ped)
        if dead and not wasDead then
            local killer = GetPedSourceOfDeath(ped)
            if killer and IsEntityAPed(killer) and IsPedAPlayer(killer) then
                local killerPlayer = NetworkGetPlayerIndexFromPed(killer)
                if killerPlayer and killerPlayer ~= -1 then
                    local killerServerId = GetPlayerServerId(killerPlayer)
                    local bone = GetPedLastDamageBone(ped)
                    local headshot = bone == 31086 -- SKEL_Head
                    -- victim informs server; killer validation done server-side via event from victim is weak
                    -- instead, we let the killer client detect victim death nearby below
                    killerServerId = killerServerId
                    headshot = headshot
                end
            end
        end
        wasDead = dead
    end
end)

-- Killer-side detection
local reported = {}
CreateThread(function()
    while true do
        Wait(1000)
        local myPed = PlayerPedId()
        if IsEntityDead(myPed) then goto continue end

        for _, playerId in ipairs(GetActivePlayers()) do
            local ped = GetPlayerPed(playerId)
            if ped ~= myPed and DoesEntityExist(ped) and IsEntityDead(ped) then
                local sid = GetPlayerServerId(playerId)
                if not reported[sid] then
                    local killer = GetPedSourceOfDeath(ped)
                    if killer == myPed then
                        local bone = GetPedLastDamageBone(ped)
                        local headshot = bone == 31086
                        reported[sid] = true
                        TriggerServerEvent('gangs:server:playerKilled', sid, headshot)
                    end
                end
            end
        end

        -- cleanup reports for revived players
        for sid in pairs(reported) do
            local found = false
            for _, playerId in ipairs(GetActivePlayers()) do
                if GetPlayerServerId(playerId) == sid then
                    local ped = GetPlayerPed(playerId)
                    if IsEntityDead(ped) then found = true end
                    break
                end
            end
            if not found then reported[sid] = nil end
        end

        ::continue::
    end
end)
