local STAT_FIELDS = {
    'kills', 'headshots', 'captured', 'bounties', 'wars_won',
    'robberies', 'npcs_killed', 'plants_picked', 'drugs_used', 'drugs_sold',
}

function Gangs.EnsureStats(source)
    local identifier = Bridge.GetIdentifier(source)
    if not identifier then return nil end
    if Gangs.Stats[identifier] then
        Gangs.Stats[identifier].name = Bridge.GetCharName(source)
        return Gangs.Stats[identifier]
    end

    MySQL.insert.await(
        'INSERT INTO gangs_stats (identifier, citizenid, name) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name)',
        { identifier, identifier, Bridge.GetCharName(source) }
    )

    Gangs.Stats[identifier] = {
        identifier = identifier,
        citizenid = identifier,
        name = Bridge.GetCharName(source),
        kills = 0,
        headshots = 0,
        captured = 0,
        bounties = 0,
        wars_won = 0,
        robberies = 0,
        npcs_killed = 0,
        plants_picked = 0,
        drugs_used = 0,
        drugs_sold = 0,
        title_tier = 1,
    }
    return Gangs.Stats[identifier]
end

function Gangs.GetTitleForStats(stats)
    if not stats then
        return Config.CriminalTitles[1]
    end

    local best = Config.CriminalTitles[1]
    local bestTier = 1
    for tier, title in pairs(Config.CriminalTitles) do
        local ok = true
        for stat, need in pairs(title.Require or {}) do
            if (stats[stat] or 0) < need then
                ok = false
                break
            end
        end
        if ok and tier >= bestTier then
            best = title
            bestTier = tier
        end
    end
    return best
end

function Gangs.AddStat(identifier, field, amount, source)
    if not identifier or not field then return end
    amount = tonumber(amount) or 1
    local stats = Gangs.Stats[identifier]
    if not stats and source then
        stats = Gangs.EnsureStats(source)
    end
    if not stats then return end

    local valid = false
    for _, name in ipairs(STAT_FIELDS) do
        if name == field then valid = true break end
    end
    if not valid then return end

    stats[field] = (stats[field] or 0) + amount
    local title = Gangs.GetTitleForStats(stats)
    local tier = 1
    for t, data in pairs(Config.CriminalTitles) do
        if data.Title == title.Title then tier = t break end
    end
    stats.title_tier = tier

    MySQL.update.await(
        ('UPDATE gangs_stats SET `%s` = ?, title_tier = ?, name = ? WHERE identifier = ?'):format(field),
        { stats[field], stats.title_tier, stats.name, identifier }
    )
end

function Gangs.ResetStats(identifier)
    local stats = Gangs.Stats[identifier]
    if not stats then return end
    for _, field in ipairs(STAT_FIELDS) do
        stats[field] = 0
    end
    stats.title_tier = 1
    MySQL.update.await([[
        UPDATE gangs_stats SET
            kills=0, headshots=0, captured=0, bounties=0, wars_won=0,
            robberies=0, npcs_killed=0, plants_picked=0, drugs_used=0, drugs_sold=0, title_tier=1
        WHERE identifier = ?
    ]], { identifier })
end

function Gangs.GetLeaderboard(limit)
    limit = tonumber(limit) or 10
    local rows = {}
    for _, stats in pairs(Gangs.Stats) do
        rows[#rows + 1] = stats
    end
    table.sort(rows, function(a, b)
        if (a.wars_won or 0) == (b.wars_won or 0) then
            return (a.kills or 0) > (b.kills or 0)
        end
        return (a.wars_won or 0) > (b.wars_won or 0)
    end)

    local out = {}
    for i = 1, math.min(limit, #rows) do
        local s = rows[i]
        out[#out + 1] = {
            name = s.name,
            kills = s.kills,
            warsWon = s.wars_won,
            bounties = s.bounties,
            title = Gangs.GetTitleForStats(s).Title,
        }
    end
    return out
end

function Gangs.GetOrgLeaderboard(limit)
    limit = tonumber(limit) or 10
    local rows = {}
    for name, org in pairs(Gangs.Orgs) do
        local members = 0
        for _ in pairs(org.members or {}) do members += 1 end
        local zones = 0
        for _, zone in pairs(Gangs.Zones or {}) do
            if zone.owner_org == name then zones += 1 end
        end
        rows[#rows + 1] = {
            name = org.name,
            label = org.label,
            power = org.power or 0,
            bank = org.bank or 0,
            members = members,
            zones = zones,
            color = org.color or '#64748b',
        }
    end
    table.sort(rows, function(a, b)
        if (a.power or 0) == (b.power or 0) then
            if (a.zones or 0) == (b.zones or 0) then
                return (a.bank or 0) > (b.bank or 0)
            end
            return (a.zones or 0) > (b.zones or 0)
        end
        return (a.power or 0) > (b.power or 0)
    end)
    local out = {}
    for i = 1, math.min(limit, #rows) do
        out[#out + 1] = rows[i]
    end
    return out
end

