local function orgDisplay(name)
    if not name or not Gangs.Orgs[name] then
        return {
            name = name,
            label = name or 'Unowned',
            color = '#3B82F6',
            logo = nil,
        }
    end
    local org = Gangs.Orgs[name]
    return {
        name = org.name,
        label = org.label,
        color = org.color or '#EF4444',
        logo = org.logo,
    }
end

function Gangs.GetClientWars()
    local payload = {}
    for key, war in pairs(Gangs.Wars) do
        local zone = Gangs.Zones[key]
        local attacker = orgDisplay(war.attacker)
        local defender = orgDisplay(war.defender)
        local leading = attacker
        if (war.defenderScore or 0) > (war.attackerScore or 0) then
            leading = defender
        end
        payload[key] = {
            zoneKey = key,
            zoneId = zone and zone.id or nil,
            zoneTitle = zone and zone.title or key,
            attacker = attacker.name,
            attackerLabel = attacker.label,
            attackerColor = attacker.color,
            attackerLogo = attacker.logo,
            defender = defender.name,
            defenderLabel = defender.label,
            defenderColor = defender.color,
            defenderLogo = defender.logo,
            leadingColor = leading.color,
            leadingLogo = leading.logo,
            leadingLabel = leading.label,
            attackerScore = war.attackerScore,
            defenderScore = war.defenderScore,
            startedAt = war.startedAt,
            endsAt = war.endsAt,
            duration = war.duration,
            points = zone and zone.points or {},
            minZ = zone and zone.min_z or nil,
            maxZ = zone and zone.max_z or nil,
            center = zone and {
                x = zone.center_x,
                y = zone.center_y,
                z = zone.center_z,
            } or nil,
        }
    end
    return payload
end

local function countActiveOrgWars(orgName)
    local count = 0
    for _, war in pairs(Gangs.Wars) do
        if war.attacker == orgName or war.defender == orgName then
            count += 1
        end
    end
    return count
end

function Gangs.CanStartWar(source, zoneKey)
    local member = Gangs.GetMember(source)
    if not member then return false, Gangs.Locale('not_in_org') end

    local org = Gangs.GetOrgById(member.org_id)
    if not org then return false, Gangs.Locale('not_in_org') end

    if Config.OnlyOwnerCanStartWar and org.owner ~= member.identifier then
        return false, Gangs.Locale('no_permission')
    end
    if not Gangs.MemberHasPermission(member, 'canStartWar') then
        return false, Gangs.Locale('no_permission')
    end

    local zone = Gangs.Zones[zoneKey]
    if not zone then return false, 'Invalid zone' end
    if zone.type == 'continental' then return false, 'Cannot war continental zones' end
    if zone.type == 'house' and not Config.HouseZoneCapture then
        return false, 'House zones cannot be captured'
    end
    if zone.owner_org == org.name then
        return false, Gangs.Locale('war_own_zone')
    end
    if Gangs.Wars[zoneKey] then
        return false, Gangs.Locale('war_already')
    end

    local now = os.time()
    if (zone.cooldown_until or 0) > now then
        return false, Gangs.Locale('war_cooldown_zone')
    end
    if (Gangs.OrgCooldowns[org.name] or 0) > now then
        return false, Gangs.Locale('war_cooldown_org')
    end
    if not Gangs.IsWarTimeAllowed() then
        return false, Gangs.Locale('war_not_allowed_time')
    end

    local online = Gangs.CountOnlineOrgMembers(org.name)
    if online < (Config.OrganizationMembersRequiredOnlineToAttackZone or 1) then
        return false, Gangs.Locale('war_need_members')
    end
    if online < (Config.CriminalOnlineRequiredToStartWar or 1) then
        return false, Gangs.Locale('war_need_members')
    end

    if Config.MaximumOrganizationWars and Config.MaximumOrganizationWars > 0 then
        if countActiveOrgWars(org.name) >= Config.MaximumOrganizationWars then
            return false, 'Your organization is already in a war'
        end
    end

    local price = tonumber(Config.PriceToStartWar) or 0
    if price > 0 and Bridge.GetItemCount(source, Config.CurrencyName) < price then
        return false, Gangs.Locale('war_need_currency')
    end

    return true, org, zone, price
end

function Gangs.StartWar(source, zoneKey, force)
    local ok, orgOrErr, zone, price
    if force and Bridge.IsAdmin(source) then
        zone = Gangs.Zones[zoneKey]
        if not zone then return false, 'Invalid zone' end
        local member = Gangs.GetMember(source)
        orgOrErr = member and Gangs.GetOrgById(member.org_id)
        if not orgOrErr then return false, Gangs.Locale('not_in_org') end
        price = 0
        ok = true
    else
        ok, orgOrErr, zone, price = Gangs.CanStartWar(source, zoneKey)
        if not ok then return false, orgOrErr end
    end

    local org = orgOrErr
    if price and price > 0 then
        Bridge.RemoveItem(source, Config.CurrencyName, price)
    end

    local defenderAdvantage = Config.OwnedZoneAdvantage or 0
    if zone.owner_org then
        defenderAdvantage = defenderAdvantage + math.floor((zone.street_rep or 0) / 2)
    end

    local duration = math.floor((Config.BaseZoneWarTime or 10) * 60)
    local now = os.time()
    local war = {
        zoneKey = zoneKey,
        attacker = org.name,
        defender = zone.owner_org,
        attackerScore = 0,
        defenderScore = zone.owner_org and defenderAdvantage or 0,
        startedAt = now,
        duration = duration,
        endsAt = now + duration,
        players = {},
    }

    Gangs.Wars[zoneKey] = war
    TriggerClientEvent('gangs:client:syncWars', -1, Gangs.GetClientWars())
    TriggerClientEvent('gangs:client:syncZones', -1, Gangs.GetClientZones())

    Bridge.Notify(source, Gangs.Locale('war_started', zone.title), 'success')
    if zone.owner_org then
        Gangs.BroadcastOrg(zone.owner_org, 'gangs:client:notify', Gangs.Locale('war_started', zone.title), 'error')
    end
    Gangs.BroadcastOrg(org.name, 'gangs:client:notify', Gangs.Locale('war_started', zone.title), 'inform')

    return true, war
end

local function giveWarRewards(source)
    local award = tonumber(Config.CurrencyAward) or 0
    if award > 0 then
        Bridge.AddItem(source, Config.CurrencyName, award)
    end
    for item, value in pairs(Config.WarRewards or {}) do
        local amount = Gangs.RewardAmount(value)
        if amount > 0 then
            Bridge.AddItem(source, item, amount)
        end
    end
end

function Gangs.EndWar(zoneKey)
    local war = Gangs.Wars[zoneKey]
    local zone = Gangs.Zones[zoneKey]
    if not war or not zone then return end

    -- Highest points wins the zone. Ties keep current owner (defender), or attacker if unowned.
    local atk = war.attackerScore or 0
    local def = war.defenderScore or 0
    local winner
    if atk > def then
        winner = war.attacker
    elseif def > atk and war.defender then
        winner = war.defender
    else
        winner = war.defender or war.attacker
    end

    MySQL.insert.await([[
        INSERT INTO gangs_war_history (zone_key, attacker, defender, winner, attacker_score, defender_score)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], {
        zoneKey,
        war.attacker,
        war.defender,
        winner,
        war.attackerScore,
        war.defenderScore,
    })

    if winner then
        Gangs.SetZoneOwner(zoneKey, winner)
    end

    local now = os.time()
    zone.cooldown_until = now + ((Config.ZoneCooldown or 10) * 60)
    Gangs.SaveZone(zone)
    Gangs.OrgCooldowns[war.attacker] = now + ((Config.OrganizationCooldown or 5) * 60)
    if war.defender then
        Gangs.OrgCooldowns[war.defender] = now + ((Config.OrganizationCooldown or 5) * 60)
    end

    for identifier, contrib in pairs(war.players or {}) do
        local src = Gangs.GetSourceByIdentifier(identifier)
        local member = Gangs.Members[identifier]
        local orgName = member and Gangs.GetOrgById(member.org_id) and Gangs.GetOrgById(member.org_id).name
        if orgName == winner then
            if src then giveWarRewards(src) end
            Gangs.AddStat(identifier, 'wars_won', 1, src)
        end
        contrib = contrib -- silence unused in some lints
    end

    Gangs.Wars[zoneKey] = nil
    TriggerClientEvent('gangs:client:syncWars', -1, Gangs.GetClientWars())
    TriggerClientEvent('gangs:client:syncZones', -1, Gangs.GetClientZones())

    local message = Gangs.Locale('war_ended', zone.title, winner)
    if war.attacker then Gangs.BroadcastOrg(war.attacker, 'gangs:client:notify', message, 'inform') end
    if war.defender then Gangs.BroadcastOrg(war.defender, 'gangs:client:notify', message, 'inform') end

    if type(onWarEnd) == 'function' then
        onWarEnd(
            { organization = winner, score = winner == war.attacker and war.attackerScore or war.defenderScore, playersInvolved = war.players },
            { [war.attacker == winner and (war.defender or 'none') or war.attacker] = {
                organization = war.attacker == winner and war.defender or war.attacker,
                score = war.attacker == winner and war.defenderScore or war.attackerScore,
                playersInvolved = war.players,
            } }
        )
    end
end

function Gangs.StartWarTicker()
    CreateThread(function()
        while true do
            Wait(1000)
            local now = os.time()
            for zoneKey, war in pairs(Gangs.Wars) do
                local zone = Gangs.Zones[zoneKey]
                if not zone then
                    Gangs.Wars[zoneKey] = nil
                else
                    local attackerPresent = {}
                    local defenderPresent = {}

                    for _, src in ipairs(Bridge.GetPlayers()) do
                        local ped = GetPlayerPed(src)
                        if ped ~= 0 then
                            local coords = GetEntityCoords(ped)
                            if Gangs.PointInPolygon(coords.x, coords.y, zone.points) then
                                if (not zone.min_z or coords.z >= zone.min_z) and (not zone.max_z or coords.z <= zone.max_z) then
                                    local identifier = Bridge.GetIdentifier(src)
                                    local member = identifier and Gangs.Members[identifier]
                                    local org = member and Gangs.GetOrgById(member.org_id)
                                    if org then
                                        war.players[identifier] = (war.players[identifier] or 0) + (Config.WarScoreIncrease or 5)
                                        if org.name == war.attacker then
                                            attackerPresent[src] = true
                                        elseif war.defender and org.name == war.defender then
                                            defenderPresent[src] = true
                                        end
                                    end
                                end
                            end
                        end
                    end

                    local atkCount, defCount = 0, 0
                    for _ in pairs(attackerPresent) do atkCount += 1 end
                    for _ in pairs(defenderPresent) do defCount += 1 end

                    war.attackerScore += atkCount * (Config.WarScoreIncrease or 5)
                    war.defenderScore += defCount * (Config.WarScoreIncrease or 5)

                    if now >= war.endsAt then
                        Gangs.EndWar(zoneKey)
                    end
                end
            end

            -- Sync score snapshots once per second; clients patch HUD in-place (no flicker)
            if next(Gangs.Wars) then
                TriggerClientEvent('gangs:client:syncWars', -1, Gangs.GetClientWars())
            end
        end
    end)
end

lib.callback.register('gangs:startWar', function(source, zoneKey)
    local ok, err = Gangs.StartWar(source, zoneKey, false)
    return { success = ok, error = not ok and err or nil, data = ok and Gangs.BuildPlayerPayload(source) or nil }
end)
