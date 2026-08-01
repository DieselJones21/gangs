Bridge = Bridge or {}

local frameworkName
local QBCore
local ESX

local function detectFramework()
    if Config.Framework ~= 'auto' then
        return Config.Framework
    end
    if GetResourceState('qbx_core') == 'started' then return 'qbx_core' end
    if GetResourceState('qb-core') == 'started' then return 'qb-core' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'qb-core'
end

CreateThread(function()
    frameworkName = detectFramework()
    if frameworkName == 'qb-core' or frameworkName == 'qbx_core' then
        QBCore = exports['qb-core']:GetCoreObject()
    elseif frameworkName == 'esx' then
        ESX = exports['es_extended']:getSharedObject()
    end
end)

function Bridge.GetFramework()
    return frameworkName or detectFramework()
end

function Bridge.Notify(message, nType)
    nType = nType or 'inform'
    if GetResourceState('ox_lib') == 'started' then
        lib.notify({
            title = 'Gangs',
            description = message,
            type = nType == 'error' and 'error' or (nType == 'success' and 'success' or 'inform'),
        })
        return
    end
    if Bridge.GetFramework() == 'esx' then
        ESX.ShowNotification(message)
    elseif QBCore then
        QBCore.Functions.Notify(message, nType)
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(message)
        EndTextCommandThefeedPostTicker(false, false)
    end
end

function Bridge.HasTarget()
    if Config.PreferOxTarget and GetResourceState('ox_target') == 'started' then
        return 'ox_target'
    end
    if GetResourceState('qb-target') == 'started' then
        return 'qb-target'
    end
    if GetResourceState('ox_target') == 'started' then
        return 'ox_target'
    end
    return nil
end

function Bridge.AddBoxZone(id, coords, size, rotation, options)
    local target = Bridge.HasTarget()
    if not target then return end

    if target == 'ox_target' then
        exports.ox_target:addBoxZone({
            name = id,
            coords = coords,
            size = size or vec3(1.5, 1.5, 2.0),
            rotation = rotation or 0.0,
            debug = Config.Debug,
            options = options,
        })
        return
    end

    local qbOptions = {}
    for _, opt in ipairs(options or {}) do
        qbOptions[#qbOptions + 1] = {
            type = 'client',
            event = opt.event,
            icon = opt.icon,
            label = opt.label,
            action = opt.onSelect,
            canInteract = opt.canInteract,
        }
    end

    exports['qb-target']:AddBoxZone(id, coords, size and size.x or 1.5, size and size.y or 1.5, {
        name = id,
        heading = rotation or 0.0,
        debugPoly = Config.Debug,
        minZ = coords.z - 1.0,
        maxZ = coords.z + 1.0,
    }, {
        options = qbOptions,
        distance = 2.0,
    })
end

function Bridge.RemoveZone(id)
    local target = Bridge.HasTarget()
    if not target then return end
    if target == 'ox_target' then
        pcall(function() exports.ox_target:removeZone(id) end)
    else
        pcall(function() exports['qb-target']:RemoveZone(id) end)
    end
end

RegisterNetEvent('gangs:client:openQBStash', function(data)
    if GetResourceState(Config.QBInventoryResourceName or 'qb-inventory') ~= 'started' then
        Bridge.Notify('qb-inventory is not running', 'error')
        return
    end
    TriggerServerEvent('inventory:server:OpenInventory', 'stash', data.id, {
        maxweight = data.maxweight,
        slots = data.slots,
    })
    TriggerEvent('inventory:client:SetCurrentStash', data.id)
end)
