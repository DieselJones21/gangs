local lastHudSignature = nil

local function buildWarHudList()
    local list = {}
    local onlyInside = Config.WarHudOnlyInsideZone == true
    local inside = Gangs.InsideZone

    for key, war in pairs(Gangs.Wars or {}) do
        if war.attackerLogo then pcall(Gangs.EnsureLogoTexture, war.attackerLogo) end
        if war.defenderLogo then pcall(Gangs.EnsureLogoTexture, war.defenderLogo) end
        if war.leadingLogo then pcall(Gangs.EnsureLogoTexture, war.leadingLogo) end

        local include = true
        if onlyInside and inside then
            include = (inside == key)
        end

        if include then
            local duration = tonumber(war.duration) or math.floor((Config.BaseZoneWarTime or 10) * 60)
            local remaining = tonumber(war.remaining)
            if remaining == nil and war.endsAt and GlobalState and GlobalState.gangsUnix then
                remaining = math.max(0, tonumber(war.endsAt) - tonumber(GlobalState.gangsUnix))
            end
            remaining = math.max(0, math.floor(tonumber(remaining) or duration))

            list[#list + 1] = {
                zoneKey = key,
                zoneId = war.zoneId,
                zoneTitle = war.zoneTitle or key,
                attackerLabel = war.attackerLabel or war.attacker or 'Attacker',
                defenderLabel = war.defenderLabel or war.defender or 'Unowned',
                attackerColor = war.attackerColor or '#EF4444',
                defenderColor = war.defenderColor or '#3B82F6',
                attackerLogo = war.attackerLogo or '',
                defenderLogo = war.defenderLogo or '',
                attackerScore = tonumber(war.attackerScore) or 0,
                defenderScore = tonumber(war.defenderScore) or 0,
                duration = duration,
                remaining = remaining,
            }
        end
    end

    table.sort(list, function(a, b)
        return tostring(a.zoneKey) < tostring(b.zoneKey)
    end)

    return list
end

local function signatureFor(list)
    local parts = {}
    for i = 1, #list do
        local w = list[i]
        parts[i] = ('%s:%s:%s:%s'):format(
            tostring(w.zoneKey),
            tostring(w.attackerScore),
            tostring(w.defenderScore),
            tostring(w.remaining)
        )
    end
    return table.concat(parts, ';')
end

local function pushWarHud(force)
    local ok, err = pcall(function()
        local list = buildWarHudList()
        local signature = signatureFor(list)
        if not force and signature == lastHudSignature then
            return
        end
        lastHudSignature = signature

        SendNUIMessage({
            action = 'warHud',
            wars = list,
            insideZone = Gangs.InsideZone,
        })
    end)

    if not ok then
        print(('[gangs] pushWarHud failed: %s'):format(tostring(err)))
    end
end

AddEventHandler('gangs:client:warsUpdated', function()
    pushWarHud(true)
end)

CreateThread(function()
    while true do
        if Gangs.Wars and next(Gangs.Wars) then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local found
            for key, zone in pairs(Gangs.Zones or {}) do
                if Gangs.Wars[key] and Gangs.PointInPolygon(coords.x, coords.y, zone.points or {}) then
                    found = key
                    break
                end
            end
            if found ~= Gangs.InsideZone then
                Gangs.InsideZone = found
            end
            pushWarHud(false)
            Wait(500)
        else
            if lastHudSignature ~= nil and lastHudSignature ~= '' then
                lastHudSignature = ''
                SendNUIMessage({ action = 'warHud', wars = {} })
            end
            Wait(1000)
        end
    end
end)
