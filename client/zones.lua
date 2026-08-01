local storageZones = {}
local shopZones = {}
local zoneBlips = {}

local function clearTargets()
    for id in pairs(storageZones) do
        Bridge.RemoveZone(id)
    end
    for id in pairs(shopZones) do
        Bridge.RemoveZone(id)
    end
    storageZones = {}
    shopZones = {}
end

local function clearBlips()
    for _, blip in pairs(zoneBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    zoneBlips = {}
end

local function hexToRgb(hex)
    hex = hex:gsub('#', '')
    if #hex < 6 then return 150, 150, 150 end
    return tonumber(hex:sub(1, 2), 16) or 150,
        tonumber(hex:sub(3, 4), 16) or 150,
        tonumber(hex:sub(5, 6), 16) or 150
end

local function setupZoneInteractions()
    clearTargets()
    clearBlips()

    for key, zone in pairs(Gangs.Zones) do
        local center = zone.center
        if center then
            local blip = AddBlipForCoord(center.x + 0.0, center.y + 0.0, center.z + 0.0)
            SetBlipSprite(blip, zone.type == 'continental' and 439 or 84)
            SetBlipScale(blip, 0.7)
            SetBlipAsShortRange(blip, true)
            local r, g, b = hexToRgb(zone.color or '#888888')
            SetBlipColour(blip, 1)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(zone.title or key)
            EndTextCommandSetBlipName(blip)
            zoneBlips[key] = blip
            r, g, b = r, g, b
        end

        for stashId, storage in pairs(zone.data and zone.data.Storages or {}) do
            local coords = storage.Coords
            if coords then
                local id = ('gangs_storage_%s_%s'):format(key, stashId)
                local c = type(coords) == 'vector3' and coords or vec3(coords.x, coords.y, coords.z)
                Bridge.AddBoxZone(id, c, vec3(1.6, 1.6, 2.0), storage.Rotation or 0.0, {
                    {
                        name = id,
                        icon = 'fa-solid fa-box',
                        label = 'Open Zone Storage',
                        onSelect = function()
                            local result = lib.callback.await('gangs:openStorage', false, key, stashId)
                            if result and not result.success then
                                Bridge.Notify(result.error or 'Cannot open storage', 'error')
                            end
                        end,
                    },
                })
                storageZones[id] = true
            end
        end

        if zone.type == 'continental' then
            for model, npc in pairs(zone.data and zone.data.ShopNPCs or {}) do
                local coords = npc.Coords
                if coords then
                    local id = ('gangs_shop_%s_%s'):format(key, model)
                    local c = type(coords) == 'vector3' and coords or vec3(coords.x, coords.y, coords.z)
                    Bridge.AddBoxZone(id, c, vec3(1.8, 1.8, 2.0), npc.Rotation or 0.0, {
                        {
                            name = id,
                            icon = 'fa-solid fa-shop',
                            label = 'Continental Shop',
                            onSelect = function()
                                TriggerEvent('gangs:client:openContinentalShop', key, zone)
                            end,
                        },
                    })
                    shopZones[id] = true
                end
            end
        end
    end
end

RegisterNetEvent('gangs:client:zonesUpdated', setupZoneInteractions)

CreateThread(function()
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local found
        for key, zone in pairs(Gangs.Zones) do
            if Gangs.PointInPolygon(coords.x, coords.y, zone.points or {}) then
                if (not zone.minZ or coords.z >= zone.minZ) and (not zone.maxZ or coords.z <= zone.maxZ) then
                    found = key
                    break
                end
            end
        end

        if found ~= Gangs.InsideZone then
            Gangs.InsideZone = found
            if found and Gangs.Zones[found] then
                local z = Gangs.Zones[found]
                local owner = z.owner or 'Unowned'
                Bridge.Notify(('%s [%s] — %s'):format(z.title, z.type, owner), 'inform')
            end
            SendNUIMessage({
                action = 'zoneChanged',
                zone = found and {
                    key = found,
                    title = Gangs.Zones[found].title,
                    owner = Gangs.Zones[found].owner,
                    type = Gangs.Zones[found].type,
                } or nil,
            })
        end
    end
end)

-- Draw zone outlines when nearby / in war
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)

        for key, zone in pairs(Gangs.Zones) do
            local center = zone.center
            if center then
                local dist = #(coords - vec3(center.x, center.y, center.z))
                local inWar = Gangs.Wars[key] ~= nil
                if dist < (inWar and Config.DistanceToDisplayWall or 80.0) then
                    sleep = 0
                    local points = zone.points or {}
                    local r, g, b = hexToRgb(zone.color or '#888888')
                    if inWar then r, g, b = 220, 40, 40 end
                    for i = 1, #points do
                        local a = points[i]
                        local c = points[i + 1] or points[1]
                        local z1 = zone.minZ or (center.z - 1.0)
                        local z2 = zone.maxZ or (center.z + 8.0)
                        DrawLine(a.x, a.y, z1, c.x, c.y, z1, r, g, b, inWar and 200 or 120)
                        DrawLine(a.x, a.y, z2, c.x, c.y, z2, r, g, b, inWar and 200 or 80)
                        DrawLine(a.x, a.y, z1, a.x, a.y, z2, r, g, b, inWar and 160 or 60)
                        if inWar and Config.DisplayWarWall then
                            DrawPoly(a.x, a.y, z1, c.x, c.y, z1, c.x, c.y, z2, r, g, b, 40)
                            DrawPoly(a.x, a.y, z1, c.x, c.y, z2, a.x, a.y, z2, r, g, b, 40)
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

RegisterNetEvent('gangs:client:openContinentalShop', function(zoneKey, zone)
    local shop = zone.data and zone.data.Shop or {}
    local options = {}
    for category, items in pairs(shop) do
        for itemName, price in pairs(items) do
            options[#options + 1] = {
                title = ('%s (%s)'):format(itemName, category),
                description = ('Price: %s %s'):format(price, Config.CurrencyLabel),
                onSelect = function()
                    local result = lib.callback.await('gangs:buyContinentalItem', false, zoneKey, category, itemName)
                    if result and result.success then
                        Bridge.Notify('Purchased ' .. itemName, 'success')
                    else
                        Bridge.Notify(result and result.error or 'Purchase failed', 'error')
                    end
                end,
            }
        end
    end

    if #options == 0 then
        Bridge.Notify('Shop is empty', 'error')
        return
    end

    lib.registerContext({
        id = 'gangs_continental_shop',
        title = zone.title or 'Continental',
        options = options,
    })
    lib.showContext('gangs_continental_shop')
end)

exports('isPlayerOrganizationZone', function(zoneId)
    local zone = Gangs.Zones[zoneId]
    return zone ~= nil and zone.owner ~= nil
end)

exports('inWarZone', function()
    return Gangs.InsideZone and Gangs.Wars[Gangs.InsideZone] ~= nil
end)
