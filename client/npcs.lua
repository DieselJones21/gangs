local guards = {} -- [zoneKey] = { ped, ... }

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(10)
    end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

local function clearGuards(zoneKey)
    if not guards[zoneKey] then return end
    for _, ped in ipairs(guards[zoneKey]) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end
    guards[zoneKey] = nil
end

local function spawnGuards(zoneKey, zone)
    clearGuards(zoneKey)
    local count = tonumber(zone.npcCount) or 0
    if count <= 0 or not zone.owner then return end

    local models = zone.data.NPCModels or Config.NPCModels
    local weapons = zone.data.NPCWeapons or Config.NPCWeapons
    local center = zone.center
    if not center then return end

    guards[zoneKey] = {}
    for i = 1, count do
        local model = models[((i - 1) % #models) + 1]
        local hash = loadModel(model)
        if hash then
            local angle = (i / count) * math.pi * 2
            local x = center.x + math.cos(angle) * 4.0
            local y = center.y + math.sin(angle) * 4.0
            local z = center.z
            local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 5.0, false)
            if found then z = groundZ end

            local ped = CreatePed(4, hash, x, y, z, angle * 57.2958, false, true)
            SetEntityAsMissionEntity(ped, true, true)
            SetPedArmour(ped, 50)
            SetPedAsEnemy(ped, false)
            SetBlockingOfNonTemporaryEvents(ped, true)
            GiveWeaponToPed(ped, joaat(weapons[((i - 1) % #weapons) + 1]), 200, false, true)
            SetPedCombatAttributes(ped, 46, true)
            SetPedCombatAbility(ped, 2)
            TaskGuardCurrentPosition(ped, 8.0, 8.0, true)
            guards[zoneKey][#guards[zoneKey] + 1] = ped
            SetModelAsNoLongerNeeded(hash)
        end
    end
end

RegisterNetEvent('gangs:client:zonesUpdated', function()
    for key, zone in pairs(Gangs.Zones) do
        local myCoords = GetEntityCoords(PlayerPedId())
        local center = zone.center
        if center and #(myCoords - vec3(center.x, center.y, center.z)) < 120.0 then
            spawnGuards(key, zone)
        else
            clearGuards(key)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(2000)
        local myPed = PlayerPedId()
        local myCoords = GetEntityCoords(myPed)

        for key, zone in pairs(Gangs.Zones) do
            local center = zone.center
            if center then
                local dist = #(myCoords - vec3(center.x, center.y, center.z))
                if dist < 120.0 then
                    if not guards[key] or #guards[key] == 0 then
                        spawnGuards(key, zone)
                    end
                elseif dist > 160.0 then
                    clearGuards(key)
                end
            end

            local war = Gangs.Wars[key]
            local shouldAttack = war ~= nil or not Config.NPCAttackOnlyWhenWar
            if guards[key] and shouldAttack and zone.owner then
                -- Attack players who are not owners during war
                for _, ped in ipairs(guards[key]) do
                    if DoesEntityExist(ped) then
                        local target = myPed
                        -- naive: if local player is in zone and not owner color side, fight
                        if Gangs.InsideZone == key and war then
                            TaskCombatPed(ped, target, 0, 16)
                        end
                    end
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for key in pairs(guards) do
        clearGuards(key)
    end
end)
