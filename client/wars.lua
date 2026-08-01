local function pushWarHud()
    local list = {}
    for key, war in pairs(Gangs.Wars or {}) do
        list[#list + 1] = {
            zoneKey = key,
            zoneId = war.zoneId,
            zoneTitle = war.zoneTitle or key,
            attackerLabel = war.attackerLabel or war.attacker or 'Attacker',
            defenderLabel = war.defenderLabel or war.defender or 'Unowned',
            attackerColor = war.attackerColor or '#EF4444',
            defenderColor = war.defenderColor or '#3B82F6',
            attackerScore = war.attackerScore or 0,
            defenderScore = war.defenderScore or 0,
            startedAt = war.startedAt,
            endsAt = war.endsAt,
            duration = war.duration or math.floor((Config.BaseZoneWarTime or 10) * 60),
        }
    end

    table.sort(list, function(a, b)
        return tostring(a.zoneKey) < tostring(b.zoneKey)
    end)

    SendNUIMessage({
        action = 'warHud',
        wars = list,
        serverTime = os.time(),
    })
end

AddEventHandler('gangs:client:warsUpdated', pushWarHud)

-- Keep the timer ring smooth even between server sync ticks
CreateThread(function()
    while true do
        if Gangs.Wars and next(Gangs.Wars) then
            pushWarHud()
            Wait(250)
        else
            SendNUIMessage({ action = 'warHud', wars = {}, serverTime = os.time() })
            Wait(1000)
        end
    end
end)
