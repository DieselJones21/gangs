local function ensureAdmin(source)
    if source == 0 then return true end
    if Bridge.IsAdmin(source) then return true end
    Bridge.Notify(source, Gangs.Locale('no_permission'), 'error')
    return false
end

local function adminResult(source, ok, err)
    if ok then
        return { success = true, data = Gangs.BuildPlayerPayload(source) }
    end
    return { success = false, error = err or Gangs.Locale('no_permission') }
end

RegisterCommand('zoneeditor', function(source)
    if source == 0 then return end
    if not ensureAdmin(source) then return end
    TriggerClientEvent('gangs:client:openZoneEditor', source)
end, false)

RegisterCommand('criminal', function(source, args)
    if source == 0 then
        print('Use in-game.')
        return
    end

    local sub = args[1] and args[1]:lower() or nil
    if not sub then
        TriggerClientEvent('gangs:client:openMenu', source)
        return
    end

    if sub == 'zone' then
        local ped = GetPlayerPed(source)
        local coords = GetEntityCoords(ped)
        local zone, key = Gangs.FindZoneAtCoords(coords.x, coords.y, coords.z)
        if not zone then
            Bridge.Notify(source, Gangs.Locale('no_zone'), 'error')
            print(('[gangs] player %s is not in a zone'):format(source))
            return
        end
        Bridge.Notify(source, Gangs.Locale('current_zone', zone.title, key), 'inform')
        print(('[gangs] zone=%s title=%s'):format(key, zone.title))
        return
    end

    if not ensureAdmin(source) then return end

    if sub == 'setzone' then
        local zoneKey = args[2]
        local orgName = args[3]
        if not zoneKey or not orgName then
            Bridge.Notify(source, 'Usage: /criminal setzone <zoneKey> <orgName>', 'error')
            return
        end
        if Gangs.SetZoneOwner(zoneKey, orgName) then
            Bridge.Notify(source, Gangs.Locale('zone_set'), 'success')
        else
            Bridge.Notify(source, 'Failed to set zone owner', 'error')
        end
    elseif sub == 'resetzone' then
        local zoneKey = args[2]
        if not zoneKey then
            Bridge.Notify(source, 'Usage: /criminal resetzone <zoneKey>', 'error')
            return
        end
        if Gangs.SetZoneOwner(zoneKey, nil) then
            Bridge.Notify(source, Gangs.Locale('zone_set'), 'success')
        else
            Bridge.Notify(source, 'Failed to reset zone', 'error')
        end
    elseif sub == 'startwar' then
        local zoneKey = args[2]
        if not zoneKey then
            Bridge.Notify(source, 'Usage: /criminal startwar <zoneKey>', 'error')
            return
        end
        local ok, err = Gangs.StartWar(source, zoneKey, true)
        if not ok then Bridge.Notify(source, err or 'Failed', 'error') end
    elseif sub == 'stopwar' then
        local zoneKey = args[2]
        if not zoneKey then
            Bridge.Notify(source, 'Usage: /criminal stopwar <zoneKey>', 'error')
            return
        end
        local ok, err = Gangs.CancelWar(zoneKey)
        if ok then
            Bridge.Notify(source, Gangs.Locale('war_cancelled', zoneKey), 'success')
        else
            Bridge.Notify(source, err or 'Failed', 'error')
        end
    elseif sub == 'createzone' then
        TriggerClientEvent('gangs:client:openZoneEditor', source)
    elseif sub == 'deletezone' then
        local zoneKey = args[2]
        if not zoneKey then
            Bridge.Notify(source, 'Usage: /criminal deletezone <zoneKey>', 'error')
            return
        end
        if Gangs.DeleteZone(zoneKey) then
            Bridge.Notify(source, Gangs.Locale('zone_deleted'), 'success')
        else
            Bridge.Notify(source, 'Zone not found', 'error')
        end
    elseif sub == 'givecurrency' then
        local target = tonumber(args[2]) or source
        local amount = tonumber(args[3]) or 100
        Bridge.AddItem(target, Config.CurrencyName, amount)
        Bridge.Notify(source, ('Gave %s %s'):format(amount, Config.CurrencyLabel), 'success')
    else
        Bridge.Notify(source, 'Unknown subcommand', 'error')
    end
end, false)

lib.callback.register('gangs:adminCreateZone', function(source, payload)
    if not Bridge.IsAdmin(source) then
        return { success = false, error = Gangs.Locale('no_permission') }
    end

    local key = tostring(payload.key or ''):lower():gsub('%s+', '_'):gsub('[^%w_]', '')
    if key == '' then return { success = false, error = 'Invalid key' } end

    local template = payload.template and Config.ZoneTypeTemplates[payload.template] or nil
    local data = {
        title = payload.title or (template and template.Title) or key,
        type = payload.type or (template and template.Type) or 'house',
        points = payload.points,
        min_z = payload.minZ,
        max_z = payload.maxZ,
        center_z = payload.centerZ,
        Storages = payload.storages or {},
        GenerationItems = template and template.GenerationItems or payload.GenerationItems,
        ProcessingItems = template and template.ProcessingItems or payload.ProcessingItems,
        SalesItems = template and template.SalesItems or payload.SalesItems,
        Shop = template and template.Shop or payload.Shop,
        Time = template and template.Time or payload.Time or 60000,
    }

    local ok, result = Gangs.CreateZone(key, data)
    if not ok then return { success = false, error = result } end
    Bridge.Notify(source, Gangs.Locale('zone_created', key), 'success')
    return { success = true, zone = { key = key, title = result.title, type = result.type } }
end)

lib.callback.register('gangs:adminCreateOrg', function(source, label, color, ownerSource)
    if not Bridge.IsAdmin(source) then
        return { success = false, error = Gangs.Locale('no_permission') }
    end
    local ok, result = Gangs.AdminCreateOrganization(source, label, color, ownerSource)
    return adminResult(source, ok, result)
end)

lib.callback.register('gangs:adminDeleteOrg', function(source, orgName)
    if not Bridge.IsAdmin(source) then
        return { success = false, error = Gangs.Locale('no_permission') }
    end
    local ok, err = Gangs.AdminDeleteOrganization(orgName)
    if ok then
        Bridge.Notify(source, Gangs.Locale('admin_org_removed', orgName), 'success')
    end
    return adminResult(source, ok, err)
end)

lib.callback.register('gangs:adminStopWar', function(source, zoneKey)
    if not Bridge.IsAdmin(source) then
        return { success = false, error = Gangs.Locale('no_permission') }
    end
    local ok, err = Gangs.CancelWar(zoneKey)
    if ok then
        Bridge.Notify(source, Gangs.Locale('war_cancelled', zoneKey), 'success')
    end
    return adminResult(source, ok, err)
end)

lib.callback.register('gangs:adminSetZoneOwner', function(source, zoneKey, orgName)
    if not Bridge.IsAdmin(source) then
        return { success = false, error = Gangs.Locale('no_permission') }
    end
    if orgName == '' or orgName == false or orgName == 'none' then
        orgName = nil
    end
    local ok = Gangs.SetZoneOwner(zoneKey, orgName)
    if ok then
        Bridge.Notify(source, Gangs.Locale('zone_set'), 'success')
    end
    return adminResult(source, ok, ok and nil or 'Failed to set zone owner')
end)

lib.callback.register('gangs:adminDeleteZone', function(source, zoneKey)
    if not Bridge.IsAdmin(source) then
        return { success = false, error = Gangs.Locale('no_permission') }
    end
    local ok = Gangs.DeleteZone(zoneKey)
    if ok then
        Bridge.Notify(source, Gangs.Locale('zone_deleted'), 'success')
    end
    return adminResult(source, ok, ok and nil or 'Zone not found')
end)

lib.callback.register('gangs:adminSetZoneCooldown', function(source, zoneKey, minutes)
    if not Bridge.IsAdmin(source) then
        return { success = false, error = Gangs.Locale('no_permission') }
    end
    local ok, err = Gangs.AdminSetZoneCooldown(zoneKey, minutes)
    if ok then
        Bridge.Notify(source, Gangs.Locale('admin_cooldown_updated'), 'success')
    end
    return adminResult(source, ok, err)
end)

lib.callback.register('gangs:adminSetOrgCooldown', function(source, orgName, minutes)
    if not Bridge.IsAdmin(source) then
        return { success = false, error = Gangs.Locale('no_permission') }
    end
    local ok, err = Gangs.AdminSetOrgCooldown(orgName, minutes)
    if ok then
        Bridge.Notify(source, Gangs.Locale('admin_cooldown_updated'), 'success')
    end
    return adminResult(source, ok, err)
end)

lib.callback.register('gangs:adminClearAllCooldowns', function(source)
    if not Bridge.IsAdmin(source) then
        return { success = false, error = Gangs.Locale('no_permission') }
    end
    Gangs.AdminClearAllZoneCooldowns()
    Gangs.AdminClearAllOrgCooldowns()
    Bridge.Notify(source, Gangs.Locale('admin_cooldowns_cleared'), 'success')
    return adminResult(source, true)
end)
