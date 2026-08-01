local lastHudSignature = nil
local stickyInside = nil
local stickyLostAt = 0

local function resolveInsideWarZone()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local found

    for key, zone in pairs(Gangs.Zones or {}) do
        if Gangs.Wars and Gangs.Wars[key] and Gangs.PointInPolygon(coords.x, coords.y, zone.points or {}) then
            found = key
            break
        end
    end

    if found then
        stickyInside = found
        stickyLostAt = 0
        Gangs.InsideZone = found
        return found
    end

    -- Small grace so walking the edge doesn't spam hide/show
    if stickyInside then
        if stickyLostAt == 0 then
            stickyLostAt = GetGameTimer()
        elseif (GetGameTimer() - stickyLostAt) < 700 then
            return stickyInside
        end
        stickyInside = nil
        stickyLostAt = 0
    end

    if Gangs.InsideZone and Gangs.Wars and Gangs.Wars[Gangs.InsideZone] then
        Gangs.InsideZone = nil
    end
    return nil
end

local function buildWarHudList(insideKey)
    local list = {}

    for key, war in pairs(Gangs.Wars or {}) do
        if war.attackerLogo then pcall(Gangs.EnsureLogoTexture, war.attackerLogo) end
        if war.defenderLogo then pcall(Gangs.EnsureLogoTexture, war.defenderLogo) end
        if war.leadingLogo then pcall(Gangs.EnsureLogoTexture, war.leadingLogo) end

        -- Only show HUD while inside that war zone
        if insideKey and insideKey == key then
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

    return list
end

local function signatureFor(list, insideKey)
    if not list or #list == 0 then
        return ('empty:%s'):format(tostring(insideKey))
    end
    local w = list[1]
    return ('%s:%s:%s:%s:%s'):format(
        tostring(insideKey),
        tostring(w.zoneKey),
        tostring(w.attackerScore),
        tostring(w.defenderScore),
        tostring(w.remaining)
    )
end

local function pushWarHud(force)
    local ok, err = pcall(function()
        local insideKey = resolveInsideWarZone()
        local list = buildWarHudList(insideKey)
        local signature = signatureFor(list, insideKey)
        if not force and signature == lastHudSignature then
            return
        end
        lastHudSignature = signature

        SendNUIMessage({
            action = 'warHud',
            wars = list,
            insideZone = insideKey,
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
            pushWarHud(false)
            Wait(350)
        else
            if lastHudSignature ~= nil and lastHudSignature ~= '' then
                lastHudSignature = ''
                stickyInside = nil
                stickyLostAt = 0
                SendNUIMessage({ action = 'warHud', wars = {} })
            end
            Wait(1000)
        end
    end
end)
