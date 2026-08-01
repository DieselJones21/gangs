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

function Gangs.IsPlayerDown(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return true end
    if IsEntityDead(ped) then return true end

    local health = GetEntityHealth(ped) or 0
    -- GTA player peds are typically dead at <= 101
    if health <= 101 then return true end

    local ok, state = pcall(function()
        return Player(src).state
    end)
    if ok and state then
        if state.isDead or state.dead or state.Laststand or state.laststand or state.inLaststand then
            return true
        end
    end

    return false
end

local function ensureWarScores(war)
    war.scores = war.scores or {}
    if war.attacker and war.scores[war.attacker] == nil then
        war.scores[war.attacker] = war.attackerScore or 0
    end
    if war.defender and war.scores[war.defender] == nil then
        war.scores[war.defender] = war.defenderScore or 0
    end
end

local function syncLegacyScores(war)
    war.attackerScore = (war.attacker and war.scores[war.attacker]) or 0
    war.defenderScore = (war.defender and war.scores[war.defender]) or 0
end

local function buildWarTeams(war, limit)
    ensureWarScores(war)
    limit = tonumber(limit) or (Config.WarHudMaxTeams or 4)
    local rows = {}
    for orgName, score in pairs(war.scores) do
        local info = orgDisplay(orgName)
        rows[#rows + 1] = {
            name = info.name,
            label = info.label,
            color = info.color,
            logo = info.logo,
            score = tonumber(score) or 0,
            isAttacker = orgName == war.attacker,
            isDefender = war.defender ~= nil and orgName == war.defender,
        }
    end

    -- Always surface attacker/defender even at 0 so the HUD has a baseline
    local function ensureNamed(orgName, isAttacker, isDefender)
        if not orgName then return end
        for _, row in ipairs(rows) do
            if row.name == orgName then return end
        end
        local info = orgDisplay(orgName)
        rows[#rows + 1] = {
            name = info.name,
            label = info.label,
            color = info.color,
            logo = info.logo,
            score = 0,
            isAttacker = isAttacker,
            isDefender = isDefender,
        }
    end
    ensureNamed(war.attacker, true, false)
    ensureNamed(war.defender, false, true)

    table.sort(rows, function(a, b)
        if (a.score or 0) == (b.score or 0) then
            if a.isDefender ~= b.isDefender then return a.isDefender end
            if a.isAttacker ~= b.isAttacker then return a.isAttacker end
            return (a.label or '') < (b.label or '')
        end
        return (a.score or 0) > (b.score or 0)
    end)

    local out = {}
    for i = 1, math.min(limit, #rows) do
        out[#out + 1] = rows[i]
    end
    return out, rows
end

function Gangs.GetClientWars()
    local payload = {}
    for key, war in pairs(Gangs.Wars) do
        local zone = Gangs.Zones[key]
        ensureWarScores(war)
        syncLegacyScores(war)

        local teams = buildWarTeams(war, Config.WarHudMaxTeams or 4)
        local leading = teams[1] or orgDisplay(war.attacker)
        local now = os.time()
        local duration = war.duration or math.floor((Config.BaseZoneWarTime or 10) * 60)
        local endsAt = war.endsAt or (now + duration)

        -- Keep attacker/defender slots as the top two teams for older HUD paths
        local primary = teams[1] or orgDisplay(war.attacker)
        local secondary = teams[2] or orgDisplay(war.defender)

        payload[key] = {
            zoneKey = key,
            zoneId = zone and zone.id or nil,
            zoneTitle = zone and zone.title or key,
            attacker = war.attacker,
            attackerLabel = orgDisplay(war.attacker).label,
            attackerColor = orgDisplay(war.attacker).color,
            attackerLogo = orgDisplay(war.attacker).logo,
            defender = war.defender,
            defenderLabel = war.defender and orgDisplay(war.defender).label or 'Unowned',
            defenderColor = war.defender and orgDisplay(war.defender).color or '#3B82F6',
            defenderLogo = war.defender and orgDisplay(war.defender).logo or nil,
            leadingColor = leading.color,
            leadingLogo = leading.logo,
            leadingLabel = leading.label,
            attackerScore = war.attackerScore,
            defenderScore = war.defenderScore,
            -- Display scores use ranked teams (supports 3+ org contests)
            primaryLabel = primary.label,
            primaryColor = primary.color,
            primaryLogo = primary.logo,
            primaryScore = primary.score,
            secondaryLabel = secondary.label,
            secondaryColor = secondary.color,
            secondaryLogo = secondary.logo,
            secondaryScore = secondary.score or 0,
            teams = teams,
            startedAt = war.startedAt or (endsAt - duration),
            endsAt = endsAt,
            duration = duration,
            remaining = math.max(0, endsAt - now),
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
        if war.attacker == orgName or war.defender == orgName or (war.scores and war.scores[orgName] ~= nil) then
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
    local scores = {
        [org.name] = 0,
    }
    if zone.owner_org then
        scores[zone.owner_org] = defenderAdvantage
    end

    local war = {
        zoneKey = zoneKey,
        attacker = org.name,
        defender = zone.owner_org,
        attackerScore = 0,
        defenderScore = zone.owner_org and defenderAdvantage or 0,
        scores = scores,
        startedAt = now,
        duration = duration,
        endsAt = now + duration,
        players = {},
        notifiedContestants = {
            [org.name] = true,
        },
    }
    if zone.owner_org then
        war.notifiedContestants[zone.owner_org] = true
    end

    Gangs.Wars[zoneKey] = war
    TriggerClientEvent('gangs:client:syncWars', -1, Gangs.GetClientWars())
    TriggerClientEvent('gangs:client:syncZones', -1, Gangs.GetClientZones())

    Bridge.Notify(source, Gangs.Locale('war_started', zone.title), 'success')
    if zone.owner_org then
        Gangs.BroadcastOrg(zone.owner_org, 'gangs:client:notify', Gangs.Locale('war_started', zone.title), 'error')
    end
    Gangs.BroadcastOrg(org.name, 'gangs:client:notify', Gangs.Locale('war_started', zone.title), 'inform')
    if Config.AllowThirdPartyContest then
        TriggerClientEvent('gangs:client:notify', -1, Gangs.Locale('war_open_contest', zone.title), 'inform')
    end

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

--- Cancel an active war without changing ownership, rewards, or cooldowns.
function Gangs.CancelWar(zoneKey)
    local war = Gangs.Wars[zoneKey]
    local zone = Gangs.Zones[zoneKey]
    if not war then return false, 'No active war on that zone' end

    Gangs.Wars[zoneKey] = nil
    TriggerClientEvent('gangs:client:syncWars', -1, Gangs.GetClientWars())
    TriggerClientEvent('gangs:client:syncZones', -1, Gangs.GetClientZones())

    local title = zone and zone.title or zoneKey
    local message = Gangs.Locale('war_cancelled', title)
    ensureWarScores(war)
    for orgName in pairs(war.scores) do
        Gangs.BroadcastOrg(orgName, 'gangs:client:notify', message, 'inform')
    end
    return true
end

function Gangs.AdminSetOrgCooldown(orgName, minutes)
    orgName = tostring(orgName or '')
    if not Gangs.Orgs[orgName] then return false, 'Organization not found' end
    minutes = tonumber(minutes) or 0
    if minutes <= 0 then
        Gangs.OrgCooldowns[orgName] = nil
    else
        Gangs.OrgCooldowns[orgName] = os.time() + math.floor(minutes * 60)
    end
    return true
end

function Gangs.AdminClearAllOrgCooldowns()
    Gangs.OrgCooldowns = {}
    return true
end

local function pickWarWinner(war, zone)
    ensureWarScores(war)
    local _, ranked = buildWarTeams(war, 99)
    if #ranked == 0 then
        return war.defender or war.attacker or zone.owner_org
    end

    local top = ranked[1]
    local topScore = top.score or 0
    local tied = {}
    for _, row in ipairs(ranked) do
        if (row.score or 0) == topScore then
            tied[#tied + 1] = row
        end
    end

    if #tied == 1 then
        return tied[1].name
    end

    -- Ties: prefer current defender, then attacker, else keep zone owner
    for _, row in ipairs(tied) do
        if war.defender and row.name == war.defender then
            return row.name
        end
    end
    for _, row in ipairs(tied) do
        if row.name == war.attacker then
            return row.name
        end
    end
    return zone.owner_org or tied[1].name
end

function Gangs.EndWar(zoneKey)
    local war = Gangs.Wars[zoneKey]
    local zone = Gangs.Zones[zoneKey]
    if not war or not zone then return end

    ensureWarScores(war)
    syncLegacyScores(war)
    local winner = pickWarWinner(war, zone)

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

    for orgName in pairs(war.scores) do
        Gangs.OrgCooldowns[orgName] = now + ((Config.OrganizationCooldown or 5) * 60)
    end

    for identifier, contrib in pairs(war.players or {}) do
        local src = Gangs.GetSourceByIdentifier(identifier)
        local member = Gangs.Members[identifier]
        local memberOrg = member and Gangs.GetOrgById(member.org_id)
        local orgName = memberOrg and memberOrg.name
        if orgName == winner then
            if src then giveWarRewards(src) end
            Gangs.AddStat(identifier, 'wars_won', 1, src)
        end
        contrib = contrib
    end

    Gangs.Wars[zoneKey] = nil
    TriggerClientEvent('gangs:client:syncWars', -1, Gangs.GetClientWars())
    TriggerClientEvent('gangs:client:syncZones', -1, Gangs.GetClientZones())

    local winnerLabel = winner and orgDisplay(winner).label or 'None'
    local message = Gangs.Locale('war_ended', zone.title, winnerLabel)
    for orgName in pairs(war.scores) do
        Gangs.BroadcastOrg(orgName, 'gangs:client:notify', message, 'inform')
    end

    if type(onWarEnd) == 'function' then
        local losers = {}
        for orgName, score in pairs(war.scores) do
            if orgName ~= winner then
                losers[orgName] = {
                    organization = orgName,
                    score = score,
                    playersInvolved = war.players,
                }
            end
        end
        onWarEnd(
            {
                organization = winner,
                score = winner and war.scores[winner] or 0,
                playersInvolved = war.players,
            },
            losers
        )
    end
end

function Gangs.StartWarTicker()
    CreateThread(function()
        while true do
            Wait(1000)
            local now = os.time()
            GlobalState.gangsUnix = now
            local increase = tonumber(Config.WarScoreIncrease) or 20
            local deathPenalty = tonumber(Config.WarScoreDeathPenalty) or 20
            local floor = tonumber(Config.WarScoreFloor) or 0
            local allowContest = Config.AllowThirdPartyContest ~= false

            for zoneKey, war in pairs(Gangs.Wars) do
                local zone = Gangs.Zones[zoneKey]
                if not zone then
                    Gangs.Wars[zoneKey] = nil
                else
                    ensureWarScores(war)
                    war.notifiedContestants = war.notifiedContestants or {}

                    local aliveByOrg = {}
                    local deadByOrg = {}

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
                                        local isSide = org.name == war.attacker or (war.defender and org.name == war.defender)
                                        if isSide or allowContest then
                                            if war.scores[org.name] == nil then
                                                war.scores[org.name] = 0
                                            end

                                            if not war.notifiedContestants[org.name] then
                                                war.notifiedContestants[org.name] = true
                                                Gangs.BroadcastOrg(org.name, 'gangs:client:notify', Gangs.Locale('war_joined_contest', zone.title), 'inform')
                                            end

                                            local down = Gangs.IsPlayerDown(src)
                                            if down then
                                                deadByOrg[org.name] = (deadByOrg[org.name] or 0) + 1
                                            else
                                                aliveByOrg[org.name] = (aliveByOrg[org.name] or 0) + 1
                                                war.players[identifier] = (war.players[identifier] or 0) + increase
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end

                    for orgName, _ in pairs(war.scores) do
                        local alive = aliveByOrg[orgName] or 0
                        local dead = deadByOrg[orgName] or 0
                        local delta = (alive * increase) - (dead * deathPenalty)
                        war.scores[orgName] = math.max(floor, (war.scores[orgName] or 0) + delta)
                    end

                    syncLegacyScores(war)

                    if now >= war.endsAt then
                        Gangs.EndWar(zoneKey)
                    end
                end
            end

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
