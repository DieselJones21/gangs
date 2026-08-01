function Gangs.PlaceBounty(source, targetSource, amount, reason)
    local member = Gangs.GetMember(source)
    local identifier = Bridge.GetIdentifier(source)
    if not identifier then return false, 'invalid_player' end

    if member and not Gangs.MemberHasPermission(member, 'canPlaceBounty') then
        return false, Gangs.Locale('no_permission')
    end

    local targetIdentifier = Bridge.GetIdentifier(targetSource)
    if not targetIdentifier then return false, Gangs.Locale('invalid_target') end
    if targetIdentifier == identifier then return false, 'Cannot bounty yourself' end

    amount = math.floor(tonumber(amount) or 0)
    if amount < (Config.MinimalBounty or 200) then
        return false, Gangs.Locale('bounty_min', Config.MinimalBounty)
    end

    if Bridge.GetItemCount(source, Config.CurrencyName) < amount then
        return false, Gangs.Locale('org_need_funds', amount, Config.CurrencyLabel)
    end

    Bridge.RemoveItem(source, Config.CurrencyName, amount)

    local org = member and Gangs.GetOrgById(member.org_id)
    local id = MySQL.insert.await([[
        INSERT INTO gangs_bounties
        (target_identifier, target_name, placer_identifier, placer_name, org_name, amount, reason, active)
        VALUES (?, ?, ?, ?, ?, ?, ?, 1)
    ]], {
        targetIdentifier,
        Bridge.GetCharName(targetSource),
        identifier,
        Bridge.GetCharName(source),
        org and org.name or nil,
        amount,
        reason and tostring(reason):sub(1, 255) or nil,
    })

    local bounty = {
        id = id,
        target_identifier = targetIdentifier,
        target_name = Bridge.GetCharName(targetSource),
        placer_identifier = identifier,
        placer_name = Bridge.GetCharName(source),
        org_name = org and org.name or nil,
        amount = amount,
        reason = reason,
        active = 1,
    }
    Gangs.Bounties[#Gangs.Bounties + 1] = bounty

    Bridge.Notify(source, Gangs.Locale('bounty_placed', amount, bounty.target_name), 'success')
    Bridge.Notify(targetSource, ('A bounty of %s was placed on you!'):format(amount), 'error')
    return true, bounty
end

function Gangs.PlaceBountyOnIdentifier(targetIdentifier, targetName, amount, reason, placerName)
    amount = math.floor(tonumber(amount) or 0)
    local id = MySQL.insert.await([[
        INSERT INTO gangs_bounties
        (target_identifier, target_name, placer_identifier, placer_name, org_name, amount, reason, active)
        VALUES (?, ?, ?, ?, ?, ?, ?, 1)
    ]], {
        targetIdentifier,
        targetName or 'Unknown',
        'system',
        placerName or 'Continental',
        nil,
        amount,
        reason,
    })

    local bounty = {
        id = id,
        target_identifier = targetIdentifier,
        target_name = targetName or 'Unknown',
        placer_identifier = 'system',
        placer_name = placerName or 'Continental',
        amount = amount,
        reason = reason,
        active = 1,
    }
    Gangs.Bounties[#Gangs.Bounties + 1] = bounty
    return bounty
end

function Gangs.ClaimBountiesForKill(killerSource, victimSource)
    local killerId = Bridge.GetIdentifier(killerSource)
    local victimId = Bridge.GetIdentifier(victimSource)
    if not killerId or not victimId or killerId == victimId then return end

    local claimed = 0
    for _, bounty in ipairs(Gangs.Bounties) do
        if bounty.active == 1 and bounty.target_identifier == victimId then
            bounty.active = 0
            bounty.claimed_by = killerId
            MySQL.update.await(
                'UPDATE gangs_bounties SET active = 0, claimed_by = ? WHERE id = ?',
                { killerId, bounty.id }
            )
            Bridge.AddItem(killerSource, Config.CurrencyName, bounty.amount)
            claimed += bounty.amount
            Bridge.Notify(
                killerSource,
                Gangs.Locale('bounty_claimed', bounty.amount, bounty.target_name),
                'success'
            )
            Gangs.AddStat(killerId, 'bounties', 1, killerSource)

            if Config.IsBountyStatWipe then
                Gangs.ResetStats(victimId)
            end
            if Config.IsBountyInventoryWipe then
                -- inventory wipe intentionally left to server owners via integration hook
                if type(ClearPlayerInventory) == 'function' then
                    ClearPlayerInventory(victimSource, victimId)
                end
            end
        end
    end

    -- rebuild active list
    local active = {}
    for _, bounty in ipairs(Gangs.Bounties) do
        if bounty.active == 1 then
            active[#active + 1] = bounty
        end
    end
    Gangs.Bounties = active
    return claimed
end

lib.callback.register('gangs:placeBounty', function(source, targetId, amount, reason)
    local ok, err = Gangs.PlaceBounty(source, tonumber(targetId), amount, reason)
    return { success = ok, error = not ok and err or nil, data = ok and Gangs.BuildPlayerPayload(source) or nil }
end)

RegisterNetEvent('gangs:server:playerKilled', function(victimServerId, isHeadshot)
    local killer = source
    local victim = tonumber(victimServerId)
    if not victim or victim <= 0 then return end

    local killerId = Bridge.GetIdentifier(killer)
    if killerId then
        Gangs.AddStat(killerId, 'kills', 1, killer)
        if isHeadshot then
            Gangs.AddStat(killerId, 'headshots', 1, killer)
        end
    end

    Gangs.ClaimBountiesForKill(killer, victim)

    -- continental kill bounty
    if Config.KillInContinentalZoneSetBounty then
        local ped = GetPlayerPed(killer)
        if ped ~= 0 then
            local coords = GetEntityCoords(ped)
            local zone = Gangs.FindZoneAtCoords(coords.x, coords.y, coords.z)
            if zone and zone.type == 'continental' then
                local victimId = Bridge.GetIdentifier(victim)
                -- bounty on killer
                Gangs.PlaceBountyOnIdentifier(
                    killerId,
                    Bridge.GetCharName(killer),
                    Config.BountyPriceSetOnContinentalKill or 200,
                    'Continental kill',
                    'Continental'
                )
                Bridge.Notify(killer, Gangs.Locale('continental_kill'), 'error')
                victimId = victimId
            end
        end
    end
end)
