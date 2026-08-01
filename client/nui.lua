local function respond(cb, payload)
    cb(payload or { success = false, error = 'Unknown error' })
end

local function awaitCallback(name, ...)
    local args = { ... }
    local ok, result = pcall(function()
        return lib.callback.await(name, false, table.unpack(args))
    end)
    if not ok then
        print(('[gangs] callback %s failed: %s'):format(name, tostring(result)))
        return { success = false, error = 'Server request failed' }
    end
    return result
end

-- Run NUI work off the callback tick so focus/fetch never deadlocks if a server call yields.
local function nuiAsync(cb, fn)
    CreateThread(function()
        local ok, result = pcall(fn)
        if not ok then
            print(('[gangs] NUI handler error: %s'):format(tostring(result)))
            respond(cb, { success = false, error = 'UI request failed' })
            return
        end
        respond(cb, result)
    end)
end

RegisterNUICallback('close', function(_, cb)
    Gangs.MenuOpen = false
    SetNuiFocus(false, false)
    respond(cb, { ok = true })
end)

RegisterNUICallback('createOrg', function(data, cb)
    nuiAsync(cb, function()
        return awaitCallback('gangs:createOrganization', data and data.label, data and data.color)
            or { success = false, error = 'Failed to create organization' }
    end)
end)

RegisterNUICallback('leaveOrg', function(_, cb)
    nuiAsync(cb, function()
        return awaitCallback('gangs:leaveOrganization') or { success = false, error = 'Failed to leave' }
    end)
end)

RegisterNUICallback('invite', function(data, cb)
    nuiAsync(cb, function()
        return awaitCallback('gangs:inviteNearby', data and data.targetId)
            or { success = false, error = 'Invite failed' }
    end)
end)

RegisterNUICallback('kick', function(data, cb)
    nuiAsync(cb, function()
        return awaitCallback('gangs:kickMember', data and data.identifier)
            or { success = false, error = 'Kick failed' }
    end)
end)

RegisterNUICallback('setRole', function(data, cb)
    nuiAsync(cb, function()
        return awaitCallback('gangs:setMemberRole', data and data.identifier, data and data.roleId)
            or { success = false, error = 'Role update failed' }
    end)
end)

RegisterNUICallback('startWar', function(data, cb)
    nuiAsync(cb, function()
        return awaitCallback('gangs:startWar', data and data.zoneKey)
            or { success = false, error = 'Could not start war' }
    end)
end)

RegisterNUICallback('placeBounty', function(data, cb)
    nuiAsync(cb, function()
        return awaitCallback('gangs:placeBounty', data and data.targetId, data and data.amount, data and data.reason)
            or { success = false, error = 'Could not place bounty' }
    end)
end)

RegisterNUICallback('upgradeProtection', function(data, cb)
    nuiAsync(cb, function()
        return awaitCallback('gangs:upgradeProtection', data and data.zoneKey)
            or { success = false, error = 'Upgrade failed' }
    end)
end)

RegisterNUICallback('upgradeNPCs', function(data, cb)
    nuiAsync(cb, function()
        return awaitCallback('gangs:upgradeNPCs', data and data.zoneKey)
            or { success = false, error = 'Upgrade failed' }
    end)
end)

RegisterNUICallback('withdrawBank', function(data, cb)
    nuiAsync(cb, function()
        return awaitCallback('gangs:withdrawOrgBank', data and data.amount)
            or { success = false, error = 'Withdraw failed' }
    end)
end)

RegisterNUICallback('refresh', function(_, cb)
    nuiAsync(cb, function()
        local data = awaitCallback('gangs:getMenuData')
        if data and not data.error then
            SendNUIMessage({ action = 'update', data = data })
        end
        return data or { error = 'Failed to refresh' }
    end)
end)

RegisterNUICallback('getNearbyPlayers', function(_, cb)
    local myId = PlayerId()
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local list = {}
    for _, player in ipairs(GetActivePlayers()) do
        if player ~= myId then
            local ped = GetPlayerPed(player)
            if #(GetEntityCoords(ped) - myCoords) < 5.0 then
                list[#list + 1] = {
                    id = GetPlayerServerId(player),
                    name = GetPlayerName(player),
                }
            end
        end
    end
    respond(cb, list)
end)
