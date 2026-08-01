function Gangs.GetClientZones()
    local payload = {}
    for key, zone in pairs(Gangs.Zones) do
        payload[key] = {
            key = key,
            title = zone.title,
            type = zone.type,
            owner = zone.owner_org,
            color = (zone.owner_org and Gangs.Orgs[zone.owner_org] and Gangs.Orgs[zone.owner_org].color) or '#888888',
            points = zone.points,
            minZ = zone.min_z,
            maxZ = zone.max_z,
            center = { x = zone.center_x, y = zone.center_y, z = zone.center_z },
            protection = zone.protection,
            npcCount = zone.npc_count,
            data = {
                Storages = zone.data.Storages or {},
                Shop = zone.data.Shop,
                ShopNPCs = zone.data.ShopNPCs,
                NPCModels = zone.data.NPCModels or Config.NPCModels,
                NPCWeapons = zone.data.NPCWeapons or Config.NPCWeapons,
            },
            inWar = Gangs.Wars[key] ~= nil,
        }
    end
    return payload
end

function Gangs.RegisterZoneStorages(zone)
    for stashId, storage in pairs(zone.data.Storages or {}) do
        Bridge.RegisterStash(
            stashId,
            ('%s Storage'):format(zone.title),
            storage.slots or storage.slot or 50,
            storage.maxWeight or 2500000
        )
    end
end

function Gangs.FindZoneAtCoords(x, y, z)
    for key, zone in pairs(Gangs.Zones) do
        if Gangs.PointInPolygon(x, y, zone.points) then
            if zone.min_z and z < zone.min_z then goto continue end
            if zone.max_z and z > zone.max_z then goto continue end
            return zone, key
        end
        ::continue::
    end
end

function Gangs.GetZone(zoneKey)
    return Gangs.Zones[zoneKey]
end

function Gangs.SetZoneOwner(zoneKey, orgName)
    local zone = Gangs.Zones[zoneKey]
    if not zone then return false end
    if orgName and not Gangs.Orgs[orgName] then return false end

    local old = zone.owner_org
    zone.owner_org = orgName
    Gangs.SaveZone(zone)

    if old and Gangs.Orgs[old] then
        Gangs.Orgs[old].power = math.max(0, (Gangs.Orgs[old].power or 0) - 1)
        MySQL.update.await('UPDATE gangs_organizations SET power = ? WHERE id = ?', { Gangs.Orgs[old].power, Gangs.Orgs[old].id })
    end
    if orgName and Gangs.Orgs[orgName] then
        Gangs.Orgs[orgName].power = (Gangs.Orgs[orgName].power or 0) + 1
        MySQL.update.await('UPDATE gangs_organizations SET power = ? WHERE id = ?', { Gangs.Orgs[orgName].power, Gangs.Orgs[orgName].id })
    end

    TriggerClientEvent('gangs:client:syncZones', -1, Gangs.GetClientZones())
    return true
end

function Gangs.CreateZone(zoneKey, data)
    if Gangs.Zones[zoneKey] then return false, 'Zone already exists' end
    local points = Gangs.NormalizePoints(data.points or data.Points or {})
    if #points < 3 then return false, 'Need at least 3 points' end

    local cx, cy = Gangs.PolygonCenter(points)
    local zoneData = data.data or {
        Storages = data.Storages or {},
        GenerationItems = data.GenerationItems,
        ProcessingItems = data.ProcessingItems,
        SalesItems = data.SalesItems,
        Shop = data.Shop,
        ShopNPCs = data.ShopNPCs,
        Time = data.Time or 60000,
    }

    local id = MySQL.insert.await([[
        INSERT INTO gangs_zones
        (zone_key, title, type, owner_org, points, center_x, center_y, center_z, min_z, max_z, protection, npc_count, street_rep, data)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        zoneKey,
        data.title or data.Title or zoneKey,
        data.type or data.Type or 'house',
        data.owner_org,
        Gangs.Encode(points),
        data.center_x or cx,
        data.center_y or cy,
        data.center_z or data.CenterZ or 30.0,
        data.min_z or data.MinZ,
        data.max_z or data.MaxZ,
        data.protection or Config.DefaultProtectionValue,
        data.npc_count or Config.DefaultNPCValue,
        0,
        Gangs.Encode(zoneData),
    })

    local zone = {
        id = id,
        zone_key = zoneKey,
        title = data.title or data.Title or zoneKey,
        type = data.type or data.Type or 'house',
        owner_org = data.owner_org,
        points = points,
        center_x = data.center_x or cx,
        center_y = data.center_y or cy,
        center_z = data.center_z or data.CenterZ or 30.0,
        min_z = data.min_z or data.MinZ,
        max_z = data.max_z or data.MaxZ,
        protection = data.protection or Config.DefaultProtectionValue,
        npc_count = data.npc_count or Config.DefaultNPCValue,
        street_rep = 0,
        data = zoneData,
        cooldown_until = 0,
    }

    Gangs.Zones[zoneKey] = zone
    Gangs.RegisterZoneStorages(zone)
    TriggerClientEvent('gangs:client:syncZones', -1, Gangs.GetClientZones())
    return true, zone
end

function Gangs.DeleteZone(zoneKey)
    local zone = Gangs.Zones[zoneKey]
    if not zone then return false end
    MySQL.query.await('DELETE FROM gangs_zones WHERE zone_key = ?', { zoneKey })
    Gangs.Zones[zoneKey] = nil
    Gangs.Wars[zoneKey] = nil
    TriggerClientEvent('gangs:client:syncZones', -1, Gangs.GetClientZones())
    TriggerClientEvent('gangs:client:syncWars', -1, Gangs.GetClientWars())
    return true
end

function Gangs.AdminSetZoneCooldown(zoneKey, minutes)
    local zone = Gangs.Zones[zoneKey]
    if not zone then return false, 'Zone not found' end
    minutes = tonumber(minutes) or 0
    if minutes <= 0 then
        zone.cooldown_until = 0
    else
        zone.cooldown_until = os.time() + math.floor(minutes * 60)
    end
    Gangs.SaveZone(zone)
    TriggerClientEvent('gangs:client:syncZones', -1, Gangs.GetClientZones())
    return true
end

function Gangs.AdminClearAllZoneCooldowns()
    for _, zone in pairs(Gangs.Zones) do
        if (zone.cooldown_until or 0) > 0 then
            zone.cooldown_until = 0
            Gangs.SaveZone(zone)
        end
    end
    TriggerClientEvent('gangs:client:syncZones', -1, Gangs.GetClientZones())
    return true
end

function Gangs.UpgradeProtection(source, zoneKey)
    local member = Gangs.GetMember(source)
    if not member then return false, Gangs.Locale('not_in_org') end
    if not Gangs.MemberHasPermission(member, 'canManageZones') then
        return false, Gangs.Locale('no_permission')
    end

    local org = Gangs.GetOrgById(member.org_id)
    local zone = Gangs.Zones[zoneKey]
    if not org or not zone or zone.owner_org ~= org.name then
        return false, 'You do not own this zone'
    end
    if (zone.protection or 0) >= Config.MaxProtectionLevel then
        return false, 'Max protection reached'
    end

    local nextLevel = (zone.protection or 0) + 1
    local price = nextLevel * (Config.ProtectionValuePrice or 100)
    if Bridge.GetItemCount(source, Config.CurrencyName) < price then
        return false, Gangs.Locale('org_need_funds', price, Config.CurrencyLabel)
    end

    Bridge.RemoveItem(source, Config.CurrencyName, price)
    zone.protection = nextLevel
    Gangs.SaveZone(zone)
    Bridge.Notify(source, Gangs.Locale('zone_upgraded', nextLevel), 'success')
    TriggerClientEvent('gangs:client:syncZones', -1, Gangs.GetClientZones())
    return true
end

function Gangs.UpgradeNPCs(source, zoneKey)
    local member = Gangs.GetMember(source)
    if not member then return false, Gangs.Locale('not_in_org') end
    if not Gangs.MemberHasPermission(member, 'canManageZones') then
        return false, Gangs.Locale('no_permission')
    end

    local org = Gangs.GetOrgById(member.org_id)
    local zone = Gangs.Zones[zoneKey]
    if not org or not zone or zone.owner_org ~= org.name then
        return false, 'You do not own this zone'
    end
    if (zone.npc_count or 0) >= Config.MaxNPCValue then
        return false, 'Max NPC count reached'
    end

    local nextLevel = (zone.npc_count or 0) + 1
    local price = nextLevel * (Config.NPCValuePrice or 100)
    if Bridge.GetItemCount(source, Config.CurrencyName) < price then
        return false, Gangs.Locale('org_need_funds', price, Config.CurrencyLabel)
    end

    Bridge.RemoveItem(source, Config.CurrencyName, price)
    zone.npc_count = nextLevel
    Gangs.SaveZone(zone)
    Bridge.Notify(source, Gangs.Locale('zone_npc_upgraded', nextLevel), 'success')
    TriggerClientEvent('gangs:client:syncZones', -1, Gangs.GetClientZones())
    return true
end

lib.callback.register('gangs:openStorage', function(source, zoneKey, stashId)
    local zone = Gangs.Zones[zoneKey]
    if not zone then return { success = false, error = 'Invalid zone' } end
    local storage = zone.data.Storages and zone.data.Storages[stashId]
    if not storage then return { success = false, error = 'Invalid storage' } end

    if storage.OnlyOwnerCanAccessStorage then
        local member = Gangs.GetMember(source)
        local org = member and Gangs.GetOrgById(member.org_id)
        if not org or org.name ~= zone.owner_org then
            return { success = false, error = Gangs.Locale('storage_owner_only') }
        end
        if not Gangs.MemberHasPermission(member, 'canAccessStorage') then
            return { success = false, error = Gangs.Locale('no_permission') }
        end
    end

    Bridge.OpenStash(
        source,
        stashId,
        ('%s Storage'):format(zone.title),
        storage.slots or storage.slot or 50,
        storage.maxWeight or 2500000
    )
    return { success = true }
end)

lib.callback.register('gangs:buyContinentalItem', function(source, zoneKey, category, itemName)
    local zone = Gangs.Zones[zoneKey]
    if not zone or zone.type ~= 'continental' then
        return { success = false, error = 'Invalid continental zone' }
    end

    local shop = zone.data.Shop or {}
    local catalog = shop[category]
    if not catalog or not catalog[itemName] then
        return { success = false, error = 'Item not available' }
    end

    local price = tonumber(catalog[itemName]) or 0
    if Bridge.GetItemCount(source, Config.CurrencyName) < price then
        return { success = false, error = Gangs.Locale('org_need_funds', price, Config.CurrencyLabel) }
    end

    if not Bridge.RemoveItem(source, Config.CurrencyName, price) then
        return { success = false, error = 'Could not remove currency' }
    end
    Bridge.AddItem(source, itemName, 1)
    return { success = true, data = Gangs.BuildPlayerPayload(source) }
end)

lib.callback.register('gangs:upgradeProtection', function(source, zoneKey)
    local ok, err = Gangs.UpgradeProtection(source, zoneKey)
    return { success = ok, error = err, data = ok and Gangs.BuildPlayerPayload(source) or nil }
end)

lib.callback.register('gangs:upgradeNPCs', function(source, zoneKey)
    local ok, err = Gangs.UpgradeNPCs(source, zoneKey)
    return { success = ok, error = err, data = ok and Gangs.BuildPlayerPayload(source) or nil }
end)

lib.callback.register('gangs:getCurrentZone', function(source)
    local ped = GetPlayerPed(source)
    if ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    local zone, key = Gangs.FindZoneAtCoords(coords.x, coords.y, coords.z)
    if not zone then return nil end
    return {
        key = key,
        title = zone.title,
        type = zone.type,
        owner = zone.owner_org,
    }
end)
