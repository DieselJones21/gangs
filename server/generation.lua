local lastTick = {}

local function firstStorageId(zone)
    for stashId in pairs(zone.data.Storages or {}) do
        return stashId, zone.data.Storages[stashId]
    end
end

local function processGeneration(zone)
    if zone.type ~= 'generation' then return end
    if not zone.owner_org and not Config.EnableGenerationWhenUnowned then return end
    local stashId, storage = firstStorageId(zone)
    if not stashId then return end

    for _, item in ipairs(zone.data.GenerationItems or {}) do
        Bridge.AddStashItem(
            stashId,
            item.itemName,
            item.itemAmount or 1,
            storage.slots or storage.slot or 50,
            storage.maxWeight or 2500000
        )
    end
end

local function processProcessing(zone)
    if zone.type ~= 'processing' then return end
    if not zone.owner_org and not Config.EnableProcessingWhenUnowned then return end
    local stashId, storage = firstStorageId(zone)
    if not stashId then return end

    for _, recipe in ipairs(zone.data.ProcessingItems or {}) do
        local have = Bridge.GetStashItemCount(stashId, recipe.ProcessingFromItem)
        local need = recipe.ProcessingFromItemAmount or 1
        if have >= need then
            if Bridge.RemoveStashItem(stashId, recipe.ProcessingFromItem, need, storage.slots or storage.slot, storage.maxWeight) then
                Bridge.AddStashItem(
                    stashId,
                    recipe.ProcessingToItem,
                    recipe.ProcessingToItemAmount or 1,
                    storage.slots or storage.slot or 50,
                    storage.maxWeight or 2500000
                )
            end
        end
    end
end

local function processSales(zone)
    if zone.type ~= 'sales' then return end
    if not zone.owner_org and not Config.EnableSellingWhenUnowned then return end
    local stashId, storage = firstStorageId(zone)
    if not stashId then return end

    local earned = 0
    for _, sale in ipairs(zone.data.SalesItems or {}) do
        local amount = sale.SaleAmount or 1
        local have = Bridge.GetStashItemCount(stashId, sale.SaleItem)
        if have >= amount then
            if Bridge.RemoveStashItem(stashId, sale.SaleItem, amount, storage.slots or storage.slot, storage.maxWeight) then
                earned += sale.SalePriceForAmount or 0
            end
        end
    end

    if earned > 0 and zone.owner_org and Gangs.Orgs[zone.owner_org] then
        local org = Gangs.Orgs[zone.owner_org]
        org.bank = (org.bank or 0) + earned
        MySQL.update.await('UPDATE gangs_organizations SET bank = ? WHERE id = ?', { org.bank, org.id })
        zone.street_rep = math.min(100, (zone.street_rep or 0) + 1)
        Gangs.SaveZone(zone)
    end
end

function Gangs.StartZoneWorkers()
    CreateThread(function()
        while true do
            Wait(5000)
            local now = GetGameTimer()
            for key, zone in pairs(Gangs.Zones) do
                local interval = tonumber(zone.data.Time) or 60000
                if interval < 5000 then interval = 5000 end
                local last = lastTick[key] or 0
                if now - last >= interval then
                    lastTick[key] = now
                    if zone.type == 'generation' then
                        processGeneration(zone)
                    elseif zone.type == 'processing' then
                        processProcessing(zone)
                    elseif zone.type == 'sales' then
                        processSales(zone)
                    end
                end
            end
        end
    end)
end

lib.callback.register('gangs:withdrawOrgBank', function(source, amount)
    local member = Gangs.GetMember(source)
    if not member then return { success = false, error = Gangs.Locale('not_in_org') } end
    if not Gangs.MemberHasPermission(member, 'canManageBank') then
        return { success = false, error = Gangs.Locale('no_permission') }
    end

    local org = Gangs.GetOrgById(member.org_id)
    amount = math.floor(tonumber(amount) or 0)
    if not org or amount <= 0 or (org.bank or 0) < amount then
        return { success = false, error = 'Invalid amount' }
    end

    org.bank = org.bank - amount
    MySQL.update.await('UPDATE gangs_organizations SET bank = ? WHERE id = ?', { org.bank, org.id })
    Bridge.AddItem(source, Config.CurrencyName, amount)
    return { success = true, data = Gangs.BuildPlayerPayload(source) }
end)
