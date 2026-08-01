local function refreshAndSend()
    local data = lib.callback.await('gangs:getMenuData', false)
    if data and not data.error then
        SendNUIMessage({ action = 'update', data = data })
    end
    return data
end

RegisterNUICallback('close', function(_, cb)
    Gangs.MenuOpen = false
    SetNuiFocus(false, false)
    cb({ ok = true })
end)

RegisterNUICallback('createOrg', function(data, cb)
    local result = lib.callback.await('gangs:createOrganization', false, data.label, data.color)
    cb(result or { success = false, error = 'Failed' })
end)

RegisterNUICallback('leaveOrg', function(_, cb)
    local result = lib.callback.await('gangs:leaveOrganization', false)
    cb(result or { success = false })
end)

RegisterNUICallback('invite', function(data, cb)
    local result = lib.callback.await('gangs:inviteNearby', false, data.targetId)
    cb(result or { success = false })
end)

RegisterNUICallback('kick', function(data, cb)
    local result = lib.callback.await('gangs:kickMember', false, data.identifier)
    cb(result or { success = false })
end)

RegisterNUICallback('setRole', function(data, cb)
    local result = lib.callback.await('gangs:setMemberRole', false, data.identifier, data.roleId)
    cb(result or { success = false })
end)

RegisterNUICallback('startWar', function(data, cb)
    local result = lib.callback.await('gangs:startWar', false, data.zoneKey)
    cb(result or { success = false })
end)

RegisterNUICallback('placeBounty', function(data, cb)
    local result = lib.callback.await('gangs:placeBounty', false, data.targetId, data.amount, data.reason)
    cb(result or { success = false })
end)

RegisterNUICallback('upgradeProtection', function(data, cb)
    local result = lib.callback.await('gangs:upgradeProtection', false, data.zoneKey)
    cb(result or { success = false })
end)

RegisterNUICallback('upgradeNPCs', function(data, cb)
    local result = lib.callback.await('gangs:upgradeNPCs', false, data.zoneKey)
    cb(result or { success = false })
end)

RegisterNUICallback('withdrawBank', function(data, cb)
    local result = lib.callback.await('gangs:withdrawOrgBank', false, data.amount)
    cb(result or { success = false })
end)

RegisterNUICallback('refresh', function(_, cb)
    local data = refreshAndSend()
    cb(data or { error = 'Failed to refresh' })
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
    cb(list)
end)
