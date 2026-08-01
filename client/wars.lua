local function pushWarHud()
    local list = {}
    local onlyInside = Config.WarHudOnlyInsideZone ~= false
    local inside = Gangs.InsideZone

    for key, war in pairs(Gangs.Wars or {}) do
        if war.attackerLogo then Gangs.EnsureLogoTexture(war.attackerLogo) end
        if war.defenderLogo then Gangs.EnsureLogoTexture(war.defenderLogo) end
        if war.leadingLogo then Gangs.EnsureLogoTexture(war.leadingLogo) end

        if (not onlyInside) or (inside and inside == key) then
            local atk = war.attackerScore or 0
            local def = war.defenderScore or 0
            list[#list + 1] = {
                zoneKey = key,
                zoneId = war.zoneId,
                zoneTitle = war.zoneTitle or key,
                attackerLabel = war.attackerLabel or war.attacker or 'Attacker',
                defenderLabel = war.defenderLabel or war.defender or 'Unowned',
                attackerColor = war.attackerColor or '#EF4444',
                defenderColor = war.defenderColor or '#3B82F6',
                attackerLogo = war.attackerLogo,
                defenderLogo = war.defenderLogo,
                attackerScore = atk,
                defenderScore = def,
                leadingLabel = war.leadingLabel,
                leadingColor = war.leadingColor,
            }
        end
    end

    table.sort(list, function(a, b)
        return tostring(a.zoneKey) < tostring(b.zoneKey)
    end)

    SendNUIMessage({
        action = 'warHud',
        wars = list,
        insideZone = inside,
    })
end

AddEventHandler('gangs:client:warsUpdated', pushWarHud)

CreateThread(function()
    local lastInside = nil
    while true do
        local hasWars = Gangs.Wars and next(Gangs.Wars) ~= nil
        if hasWars then
            if Gangs.InsideZone ~= lastInside then
                lastInside = Gangs.InsideZone
            end
            pushWarHud()
            Wait(300)
        else
            lastInside = nil
            SendNUIMessage({ action = 'warHud', wars = {}, insideZone = nil })
            Wait(1000)
        end
    end
end)
