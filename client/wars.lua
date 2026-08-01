local lastHudSignature = nil
local stickyWarZone = nil
local stickyLostAt = 0

local function getHudWarKeys()
    local onlyInside = Config.WarHudOnlyInsideZone ~= false
    local inside = Gangs.InsideZone

    if inside and Gangs.Wars and Gangs.Wars[inside] then
        stickyWarZone = inside
        stickyLostAt = 0
    elseif stickyWarZone then
        if stickyLostAt == 0 then
            stickyLostAt = GetGameTimer()
        elseif (GetGameTimer() - stickyLostAt) > 1500 then
            stickyWarZone = nil
            stickyLostAt = 0
        end
    end

    local focus = stickyWarZone or inside
    local list = {}

    for key, war in pairs(Gangs.Wars or {}) do
        if war.attackerLogo then Gangs.EnsureLogoTexture(war.attackerLogo) end
        if war.defenderLogo then Gangs.EnsureLogoTexture(war.defenderLogo) end
        if war.leadingLogo then Gangs.EnsureLogoTexture(war.leadingLogo) end

        if (not onlyInside) or (focus and focus == key) then
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
                attackerScore = war.attackerScore or 0,
                defenderScore = war.defenderScore or 0,
                startedAt = war.startedAt,
                endsAt = war.endsAt,
                duration = war.duration or math.floor((Config.BaseZoneWarTime or 10) * 60),
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
        parts[#parts + 1] = table.concat({
            tostring(w.zoneKey),
            tostring(w.attackerLabel),
            tostring(w.defenderLabel),
            tostring(w.attackerColor),
            tostring(w.defenderColor),
            tostring(w.attackerLogo),
            tostring(w.defenderLogo),
            tostring(w.attackerScore),
            tostring(w.defenderScore),
            tostring(w.endsAt),
        }, '|')
    end
    return table.concat(parts, ';')
end

local function pushWarHud(force)
    local list = getHudWarKeys()
    local signature = signatureFor(list)
    if not force and signature == lastHudSignature then
        return
    end
    lastHudSignature = signature

    SendNUIMessage({
        action = 'warHud',
        wars = list,
        serverTime = os.time(),
    })
end

AddEventHandler('gangs:client:warsUpdated', function()
    pushWarHud(true)
end)

CreateThread(function()
    while true do
        if Gangs.Wars and next(Gangs.Wars) then
            pushWarHud(false)
            Wait(500)
        else
            if lastHudSignature ~= '' then
                lastHudSignature = ''
                stickyWarZone = nil
                stickyLostAt = 0
                SendNUIMessage({ action = 'warHud', wars = {}, serverTime = os.time() })
            end
            Wait(1000)
        end
    end
end)
