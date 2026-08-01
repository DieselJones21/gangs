Bridge = Bridge or {}

local frameworkName
local QBCore
local ESX

local function detectFramework()
    if Config.Framework == 'qb-core' or Config.Framework == 'qbx_core' then
        return Config.Framework
    end
    if Config.Framework == 'esx' then
        return 'esx'
    end

    if GetResourceState('qbx_core') == 'started' then
        return 'qbx_core'
    end
    if GetResourceState('qb-core') == 'started' then
        return 'qb-core'
    end
    if GetResourceState('es_extended') == 'started' then
        return 'esx'
    end
    return 'qb-core'
end

CreateThread(function()
    frameworkName = detectFramework()
    if frameworkName == 'qb-core' or frameworkName == 'qbx_core' then
        local resource = Config.FrameworkResource or (frameworkName == 'qbx_core' and 'qb-core' or 'qb-core')
        if frameworkName == 'qbx_core' and GetResourceState('qbx_core') == 'started' then
            QBCore = exports['qb-core']:GetCoreObject()
        else
            QBCore = exports[resource]:GetCoreObject()
        end
    elseif frameworkName == 'esx' then
        ESX = exports['es_extended']:getSharedObject()
    end
    Gangs.Debug(('Framework bridge ready: %s'):format(frameworkName))
end)

function Bridge.GetFramework()
    return frameworkName or detectFramework()
end

function Bridge.GetPlayer(source)
    local fw = Bridge.GetFramework()
    if fw == 'esx' then
        return ESX and ESX.GetPlayerFromId(source) or nil
    end
    return QBCore and QBCore.Functions.GetPlayer(source) or nil
end

function Bridge.GetIdentifier(source)
    local player = Bridge.GetPlayer(source)
    if not player then return nil end
    local fw = Bridge.GetFramework()
    if fw == 'esx' then
        return player.identifier
    end
    return player.PlayerData.citizenid
end

function Bridge.GetCitizenId(source)
    return Bridge.GetIdentifier(source)
end

function Bridge.GetCharName(source)
    local player = Bridge.GetPlayer(source)
    if not player then return GetPlayerName(source) or ('ID %s'):format(source) end
    local fw = Bridge.GetFramework()
    if fw == 'esx' then
        return player.getName and player.getName() or GetPlayerName(source)
    end
    local info = player.PlayerData.charinfo or {}
    local first = info.firstname or ''
    local last = info.lastname or ''
    local full = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+$', '')
    if full == '' then return GetPlayerName(source) end
    return full
end

function Bridge.GetJobName(source)
    local player = Bridge.GetPlayer(source)
    if not player then return nil end
    local fw = Bridge.GetFramework()
    if fw == 'esx' then
        return player.job and player.job.name or nil
    end
    return player.PlayerData.job and player.PlayerData.job.name or nil
end

function Bridge.GetGangName(source)
    local player = Bridge.GetPlayer(source)
    if not player then return nil end
    local fw = Bridge.GetFramework()
    if fw == 'esx' then return nil end
    return player.PlayerData.gang and player.PlayerData.gang.name or nil
end

function Bridge.IsAdmin(source)
    local fw = Bridge.GetFramework()
    if fw == 'esx' then
        return IsPlayerAceAllowed(source, 'command') or IsPlayerAceAllowed(source, 'admin')
    end
    local player = Bridge.GetPlayer(source)
    if not player then return false end
    local group = player.PlayerData.group or 'user'
    if Config.AdminGroups[group] then return true end
    return IsPlayerAceAllowed(source, 'command') or QBCore.Functions.HasPermission(source, 'admin')
end

function Bridge.Notify(source, message, nType)
    nType = nType or 'inform'
    if GetResourceState('ox_lib') == 'started' then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Gangs',
            description = message,
            type = nType == 'error' and 'error' or (nType == 'success' and 'success' or 'inform'),
        })
        return
    end
    local fw = Bridge.GetFramework()
    if fw == 'esx' then
        TriggerClientEvent('esx:showNotification', source, message)
    else
        TriggerClientEvent('QBCore:Notify', source, message, nType)
    end
end

function Bridge.GetItemCount(source, item)
    local fw = Bridge.GetFramework()
    local inv = Bridge.GetInventory()
    if inv == 'ox_inventory' then
        return exports.ox_inventory:GetItemCount(source, item) or 0
    end

    local player = Bridge.GetPlayer(source)
    if not player then return 0 end
    if fw == 'esx' then
        local data = player.getInventoryItem(item)
        return data and data.count or 0
    end
    local it = player.Functions.GetItemByName(item)
    return it and (it.amount or it.count or 0) or 0
end

function Bridge.RemoveItem(source, item, amount)
    amount = amount or 1
    local inv = Bridge.GetInventory()
    if inv == 'ox_inventory' then
        return exports.ox_inventory:RemoveItem(source, item, amount)
    end

    local player = Bridge.GetPlayer(source)
    if not player then return false end
    local fw = Bridge.GetFramework()
    if fw == 'esx' then
        player.removeInventoryItem(item, amount)
        return true
    end
    return player.Functions.RemoveItem(item, amount)
end

function Bridge.AddItem(source, item, amount, metadata)
    amount = amount or 1
    local inv = Bridge.GetInventory()
    if inv == 'ox_inventory' then
        return exports.ox_inventory:AddItem(source, item, amount, metadata)
    end

    local player = Bridge.GetPlayer(source)
    if not player then return false end
    local fw = Bridge.GetFramework()
    if fw == 'esx' then
        player.addInventoryItem(item, amount)
        return true
    end
    return player.Functions.AddItem(item, amount, false, metadata)
end

function Bridge.GetInventory()
    if Config.Inventory == 'ox_inventory' or Config.Inventory == 'qb-inventory' then
        return Config.Inventory
    end
    if GetResourceState('ox_inventory') == 'started' then
        return 'ox_inventory'
    end
    return 'qb-inventory'
end

function Bridge.RegisterStash(stashId, label, slots, maxWeight)
    local inv = Bridge.GetInventory()
    if inv == 'ox_inventory' then
        exports.ox_inventory:RegisterStash(stashId, label or stashId, slots or 50, maxWeight or 2500000)
        return true
    end
    -- qb-inventory uses OpenInventory with stash data at open time
    return true
end

function Bridge.OpenStash(source, stashId, label, slots, maxWeight)
    local inv = Bridge.GetInventory()
    if inv == 'ox_inventory' then
        exports.ox_inventory:forceOpenInventory(source, 'stash', stashId)
        return true
    end

    TriggerClientEvent('gangs:client:openQBStash', source, {
        id = stashId,
        label = label or stashId,
        slots = slots or 50,
        maxweight = maxWeight or 2500000,
    })
    return true
end

function Bridge.AddStashItem(stashId, item, amount, slots, maxWeight)
    amount = amount or 1
    local inv = Bridge.GetInventory()
    if inv == 'ox_inventory' then
        return exports.ox_inventory:AddItem(stashId, item, amount)
    end

    local resource = Config.QBInventoryResourceName or 'qb-inventory'
    if GetResourceState(resource) == 'started' then
        local ok = pcall(function()
            exports[resource]:AddItemIntoStash(stashId, item, amount, nil, nil, slots, maxWeight)
        end)
        return ok
    end
    return false
end

function Bridge.RemoveStashItem(stashId, item, amount, slots, maxWeight)
    amount = amount or 1
    local inv = Bridge.GetInventory()
    if inv == 'ox_inventory' then
        return exports.ox_inventory:RemoveItem(stashId, item, amount)
    end

    local resource = Config.QBInventoryResourceName or 'qb-inventory'
    if GetResourceState(resource) == 'started' then
        local ok = pcall(function()
            exports[resource]:RemoveItemIntoStash(stashId, item, amount, nil, slots, maxWeight)
        end)
        return ok
    end
    return false
end

function Bridge.GetStashItemCount(stashId, item)
    local inv = Bridge.GetInventory()
    if inv == 'ox_inventory' then
        return exports.ox_inventory:GetItemCount(stashId, item) or 0
    end

    local resource = Config.QBInventoryResourceName or 'qb-inventory'
    if GetResourceState(resource) == 'started' then
        local ok, count = pcall(function()
            return exports[resource]:GetItemCountInStash(stashId, item)
        end)
        if ok then return count or 0 end
    end
    return 0
end

function Bridge.GetPlayers()
    local list = {}
    local fw = Bridge.GetFramework()
    if fw == 'esx' then
        local players = ESX and ESX.GetExtendedPlayers and ESX.GetExtendedPlayers() or {}
        for _, player in pairs(players) do
            list[#list + 1] = player.source or player.playerId
        end
        return list
    end

    if QBCore and QBCore.Functions.GetPlayers then
        return QBCore.Functions.GetPlayers()
    end

    for _, id in ipairs(GetPlayers()) do
        list[#list + 1] = tonumber(id)
    end
    return list
end
