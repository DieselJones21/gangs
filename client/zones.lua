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
    hex = tostring(hex or ''):gsub('#', '')
    if #hex < 6 then return 150, 150, 150 end
    return tonumber(hex:sub(1, 2), 16) or 150,
        tonumber(hex:sub(3, 4), 16) or 150,
        tonumber(hex:sub(5, 6), 16) or 150
end

local function wallColor(name)
    local c = Config.WarWallColors and Config.WarWallColors[name]
    if not c then
        if name == 'red' then return 210, 24, 42 end
        if name == 'blue' then return 28, 92, 220 end
        return 8, 8, 10
    end
    return c[1] or 8, c[2] or 8, c[3] or 10
end

local function drawTexturedQuad(ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz, r, g, b, a)
    -- two triangles: A-B-C and A-C-D
    DrawPoly(ax, ay, az, bx, by, bz, cx, cy, cz, r, g, b, a)
    DrawPoly(ax, ay, az, cx, cy, cz, dx, dy, dz, r, g, b, a)
    -- reverse winding so both sides are visible
    DrawPoly(ax, ay, az, cx, cy, cz, bx, by, bz, r, g, b, a)
    DrawPoly(ax, ay, az, dx, dy, dz, cx, cy, cz, r, g, b, a)
end

local function drawStripedWall(ax, ay, az1, az2, bx, by, bz1, bz2)
    local dx = bx - ax
    local dy = by - ay
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.05 then return end

    local stripe = Config.WarWallStripeWidth or 1.35
    -- Keep segment counts bounded for FPS while preserving the hazard look
    local steps = math.max(3, math.min(28, math.ceil(length / stripe)))
    local heightSteps = math.max(6, math.min(18, math.ceil(math.abs(az2 - az1) / (stripe * 0.85))))

    local redR, redG, redB = wallColor('red')
    local blueR, blueG, blueB = wallColor('blue')
    local blackR, blackG, blackB = wallColor('black')

    for i = 0, steps - 1 do
        local t0 = i / steps
        local t1 = (i + 1) / steps
        local x0 = ax + dx * t0
        local y0 = ay + dy * t0
        local x1 = ax + dx * t1
        local y1 = ay + dy * t1

        for j = 0, heightSteps - 1 do
            local v0 = j / heightSteps
            local v1 = (j + 1) / heightSteps
            local z0 = az1 + (az2 - az1) * v0
            local z1 = az1 + (az2 - az1) * v1

            -- Diagonal hazard bands across the wall face
            local band = math.floor((i + j) / 1)
            local tone = band % 3
            local r, g, b, a
            if tone == 0 then
                r, g, b, a = redR, redG, redB, 145
            elseif tone == 1 then
                r, g, b, a = blackR, blackG, blackB, 170
            else
                r, g, b, a = blueR, blueG, blueB, 140
            end

            drawTexturedQuad(
                x0, y0, z0,
                x1, y1, z0,
                x1, y1, z1,
                x0, y0, z1,
                r, g, b, a
            )
        end
    end

    -- Bright edge lines for silhouette
    DrawLine(ax, ay, az1, bx, by, bz1, redR, redG, redB, 220)
    DrawLine(ax, ay, az2, bx, by, bz2, blueR, blueG, blueB, 200)
    DrawLine(ax, ay, az1, ax, ay, az2, 255, 255, 255, 70)
    DrawLine(bx, by, bz1, bx, by, bz2, 255, 255, 255, 70)
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
            SetBlipColour(blip, 1)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(zone.title or key)
            EndTextCommandSetBlipName(blip)
            zoneBlips[key] = blip
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

-- Zone outlines + striped war walls
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local wallHeight = Config.WarWallHeight or 18.0

        for key, zone in pairs(Gangs.Zones) do
            local center = zone.center
            if center then
                local dist = #(coords - vec3(center.x, center.y, center.z))
                local inWar = Gangs.Wars[key] ~= nil
                local drawDist = inWar and (Config.DistanceToDisplayWall or 260.0) or 80.0

                if dist < drawDist then
                    sleep = 0
                    local points = zone.points or {}
                    local z1 = zone.minZ or (center.z - 1.0)
                    local z2 = inWar and (z1 + wallHeight) or (zone.maxZ or (center.z + 8.0))

                    if inWar and Config.DisplayWarWall then
                        for i = 1, #points do
                            local a = points[i]
                            local b = points[i + 1] or points[1]
                            drawStripedWall(a.x, a.y, z1, z2, b.x, b.y, z1, z2)
                        end
                    else
                        local r, g, b = hexToRgb(zone.color or '#3B82F6')
                        for i = 1, #points do
                            local a = points[i]
                            local c = points[i + 1] or points[1]
                            DrawLine(a.x, a.y, z1, c.x, c.y, z1, r, g, b, 120)
                            DrawLine(a.x, a.y, z2, c.x, c.y, z2, r, g, b, 80)
                            DrawLine(a.x, a.y, z1, a.x, a.y, z2, r, g, b, 60)
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
