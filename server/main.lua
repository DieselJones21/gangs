Gangs = Gangs or {}
Gangs.Orgs = {} -- [name] = org
Gangs.Members = {} -- [identifier] = member
Gangs.Zones = {} -- [zone_key] = zone
Gangs.Wars = {} -- [zone_key] = war
Gangs.Bounties = {} -- list
Gangs.Stats = {} -- [identifier] = stats
Gangs.PendingInvites = {} -- [identifier] = orgName
Gangs.OrgCooldowns = {} -- [orgName] = unix

local RESOURCE = GetCurrentResourceName()

local function loadOrganizations()
    local orgs = MySQL.query.await('SELECT * FROM gangs_organizations') or {}
    local roles = MySQL.query.await('SELECT * FROM gangs_roles') or {}
    local members = MySQL.query.await('SELECT * FROM gangs_members') or {}

    Gangs.Orgs = {}
    Gangs.Members = {}

    for _, org in ipairs(orgs) do
        org.roles = {}
        org.members = {}
        Gangs.Orgs[org.name] = org
    end

    for _, role in ipairs(roles) do
        local org = nil
        for _, o in pairs(Gangs.Orgs) do
            if o.id == role.org_id then
                org = o
                break
            end
        end
        if org then
            role.permissions = Gangs.Decode(role.permissions, {})
            org.roles[role.id] = role
        end
    end

    for _, member in ipairs(members) do
        local org = nil
        for _, o in pairs(Gangs.Orgs) do
            if o.id == member.org_id then
                org = o
                break
            end
        end
        if org then
            org.members[member.identifier] = member
            member.org_name = org.name
            Gangs.Members[member.identifier] = member
        end
    end
end

local function seedZonesFromConfig()
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM gangs_zones') or 0
    if count > 0 then return end

    for key, zone in pairs(Config.Zones or {}) do
        local points = Gangs.NormalizePoints(zone.Points or {})
        local cx, cy = Gangs.PolygonCenter(points)
        local data = {
            Storages = zone.Storages or {},
            GenerationItems = zone.GenerationItems,
            ProcessingItems = zone.ProcessingItems,
            SalesItems = zone.SalesItems,
            Shop = zone.Shop,
            ShopNPCs = zone.ShopNPCs,
            NPCModels = zone.NPCModels,
            NPCWeapons = zone.NPCWeapons,
            Time = zone.Time or 60000,
            Template = zone.Template,
        }

        MySQL.insert.await([[
            INSERT INTO gangs_zones
            (zone_key, title, type, owner_org, points, center_x, center_y, center_z, min_z, max_z, protection, npc_count, street_rep, data)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            key,
            zone.Title or key,
            zone.Type or 'house',
            zone.Owner or nil,
            Gangs.Encode(points),
            cx,
            cy,
            zone.CenterZ or 30.0,
            zone.MinZ,
            zone.MaxZ,
            zone.Protection or Config.DefaultProtectionValue,
            zone.NPCCount or Config.DefaultNPCValue,
            0,
            Gangs.Encode(data),
        })
    end
end

local function loadZones()
    seedZonesFromConfig()
    local rows = MySQL.query.await('SELECT * FROM gangs_zones') or {}
    Gangs.Zones = {}
    for _, row in ipairs(rows) do
        row.points = Gangs.NormalizePoints(Gangs.Decode(row.points, {}))
        row.data = Gangs.Decode(row.data, {})
        Gangs.Zones[row.zone_key] = row
        Gangs.RegisterZoneStorages(row)
    end
end

local function loadBounties()
    Gangs.Bounties = MySQL.query.await('SELECT * FROM gangs_bounties WHERE active = 1') or {}
end

local function loadStats()
    local rows = MySQL.query.await('SELECT * FROM gangs_stats') or {}
    Gangs.Stats = {}
    for _, row in ipairs(rows) do
        Gangs.Stats[row.identifier] = row
    end
end

function Gangs.SaveZone(zone)
    MySQL.update.await([[
        UPDATE gangs_zones
        SET title = ?, type = ?, owner_org = ?, points = ?, center_x = ?, center_y = ?, center_z = ?,
            min_z = ?, max_z = ?, protection = ?, npc_count = ?, street_rep = ?, data = ?, cooldown_until = ?
        WHERE zone_key = ?
    ]], {
        zone.title,
        zone.type,
        zone.owner_org,
        Gangs.Encode(zone.points),
        zone.center_x,
        zone.center_y,
        zone.center_z,
        zone.min_z,
        zone.max_z,
        zone.protection,
        zone.npc_count,
        zone.street_rep,
        Gangs.Encode(zone.data),
        zone.cooldown_until or 0,
        zone.zone_key,
    })
end

function Gangs.GetMember(source)
    local identifier = Bridge.GetIdentifier(source)
    if not identifier then return nil end
    return Gangs.Members[identifier], identifier
end

function Gangs.GetOrg(name)
    return name and Gangs.Orgs[name] or nil
end

function Gangs.GetOrgById(id)
    for _, org in pairs(Gangs.Orgs) do
        if org.id == id then return org end
    end
end

function Gangs.GetMemberRole(member)
    if not member then return nil end
    local org = Gangs.GetOrgById(member.org_id)
    if not org then return nil end
    return org.roles[member.role_id]
end

function Gangs.MemberHasPermission(member, permission)
    local role = Gangs.GetMemberRole(member)
    if not role then return false end
    return Gangs.HasPermission(role.permissions, permission)
end

function Gangs.CountOnlineOrgMembers(orgName)
    local org = Gangs.GetOrg(orgName)
    if not org then return 0 end
    local count = 0
    for _, src in ipairs(Bridge.GetPlayers()) do
        local identifier = Bridge.GetIdentifier(src)
        if identifier and org.members[identifier] then
            count += 1
        end
    end
    return count
end

function Gangs.GetSourceByIdentifier(identifier)
    for _, src in ipairs(Bridge.GetPlayers()) do
        if Bridge.GetIdentifier(src) == identifier then
            return src
        end
    end
end

function Gangs.BroadcastOrg(orgName, eventName, ...)
    local org = Gangs.GetOrg(orgName)
    if not org then return end
    for identifier in pairs(org.members) do
        local src = Gangs.GetSourceByIdentifier(identifier)
        if src then
            TriggerClientEvent(eventName, src, ...)
        end
    end
end

function Gangs.CanUseMenu(source)
    local job = Bridge.GetJobName(source)
    if job and Config.BlacklistedJobs[job] then
        return false, Gangs.Locale('blacklisted_job')
    end
    return true
end

function Gangs.BuildPlayerPayload(source)
    local member, identifier = Gangs.GetMember(source)
    local org = member and Gangs.GetOrgById(member.org_id) or nil
    local role = member and Gangs.GetMemberRole(member) or nil
    local stats = identifier and (Gangs.Stats[identifier] or Gangs.EnsureStats(source)) or nil

    local orgPayload = nil
    if org then
        local members = {}
        for _, m in pairs(org.members) do
            local r = org.roles[m.role_id]
            members[#members + 1] = {
                identifier = m.identifier,
                name = m.name,
                roleId = m.role_id,
                roleName = r and r.name or 'Unknown',
                online = Gangs.GetSourceByIdentifier(m.identifier) ~= nil,
            }
        end
        local roles = {}
        for _, r in pairs(org.roles) do
            roles[#roles + 1] = {
                id = r.id,
                name = r.name,
                grade = r.grade,
                permissions = r.permissions,
            }
        end
        table.sort(roles, function(a, b) return (a.grade or 0) > (b.grade or 0) end)

        orgPayload = {
            id = org.id,
            name = org.name,
            label = org.label,
            color = org.color,
            logo = org.logo,
            owner = org.owner,
            power = org.power,
            bank = org.bank,
            members = members,
            roles = roles,
        }
    end

    local zones = {}
    for key, zone in pairs(Gangs.Zones) do
        local ownerOrg = zone.owner_org and Gangs.Orgs[zone.owner_org] or nil
        zones[#zones + 1] = {
            key = key,
            title = zone.title,
            type = zone.type,
            owner = zone.owner_org,
            ownerLabel = ownerOrg and ownerOrg.label or zone.owner_org or 'Unowned',
            ownerColor = ownerOrg and ownerOrg.color or '#64748b',
            protection = zone.protection,
            npcCount = zone.npc_count,
            streetRep = zone.street_rep,
            center = { x = zone.center_x, y = zone.center_y, z = zone.center_z },
            points = zone.points,
            inWar = Gangs.Wars[key] ~= nil,
            cooldownUntil = zone.cooldown_until or 0,
        }
    end


    local wars = {}
    local clientWars = Gangs.GetClientWars()
    for key, war in pairs(clientWars) do
        wars[#wars + 1] = {
            zoneKey = key,
            zoneId = war.zoneId,
            zoneTitle = war.zoneTitle,
            attacker = war.attacker,
            defender = war.defender,
            attackerLabel = war.attackerLabel,
            defenderLabel = war.defenderLabel,
            attackerColor = war.attackerColor,
            defenderColor = war.defenderColor,
            attackerLogo = war.attackerLogo,
            defenderLogo = war.defenderLogo,
            attackerScore = war.attackerScore,
            defenderScore = war.defenderScore,
            teams = war.teams,
            startedAt = war.startedAt,
            endsAt = war.endsAt,
            duration = war.duration,
            remaining = war.remaining,
        }
    end


    local bounties = {}
    for _, bounty in ipairs(Gangs.Bounties) do
        if bounty.active == 1 or bounty.active == true then
            bounties[#bounties + 1] = {
                id = bounty.id,
                targetName = bounty.target_name,
                placerName = bounty.placer_name,
                amount = bounty.amount,
                reason = bounty.reason,
                orgName = bounty.org_name,
            }
        end
    end

    local leaderboard = Gangs.GetLeaderboard(10)
    local orgLeaderboard = Gangs.GetOrgLeaderboard(10)
    local isAdmin = Bridge.IsAdmin(source)
    local now = os.time()

    local adminPayload = nil
    if isAdmin then
        local orgs = {}
        for name, org in pairs(Gangs.Orgs) do
            local memberCount = 0
            for _ in pairs(org.members or {}) do memberCount += 1 end
            orgs[#orgs + 1] = {
                name = name,
                label = org.label,
                color = org.color,
                power = org.power or 0,
                bank = org.bank or 0,
                memberCount = memberCount,
                owner = org.owner,
                cooldownUntil = Gangs.OrgCooldowns[name] or 0,
            }
        end
        table.sort(orgs, function(a, b) return (a.label or a.name) < (b.label or b.name) end)

        adminPayload = {
            orgs = orgs,
            serverTime = now,
            defaultZoneCooldown = Config.ZoneCooldown or 10,
            defaultOrgCooldown = Config.OrganizationCooldown or 5,
        }
    end

    return {
        player = {
            source = source,
            identifier = identifier,
            name = Bridge.GetCharName(source),
            currency = Bridge.GetItemCount(source, Config.CurrencyName),
            permissions = role and role.permissions or {},
            roleName = role and role.name or nil,
            title = Gangs.GetTitleForStats(stats),
            stats = stats,
            isAdmin = isAdmin,
        },
        organization = orgPayload,
        zones = zones,
        wars = wars,
        bounties = bounties,
        leaderboard = leaderboard,
        orgLeaderboard = orgLeaderboard,
        admin = adminPayload,
        config = {
            canCreate = Config.CanCreateOrganizations,
            createPrice = Config.OrganizationCreationPrice,
            currencyLabel = Config.CurrencyLabel,
            minimalBounty = Config.MinimalBounty,
            maxProtection = Config.MaxProtectionLevel,
            protectionPrice = Config.ProtectionValuePrice,
            maxNpc = Config.MaxNPCValue,
            npcPrice = Config.NPCValuePrice,
            warPrice = Config.PriceToStartWar,
        },
    }
end

local function ensureSchema()
    pcall(function()
        MySQL.query.await('ALTER TABLE gangs_organizations ADD COLUMN logo VARCHAR(512) DEFAULT NULL')
    end)
end

AddEventHandler('onResourceStart', function(res)
    if res ~= RESOURCE then return end
    Wait(500)
    ensureSchema()
    loadOrganizations()
    loadZones()
    loadBounties()
    loadStats()
    TriggerClientEvent('gangs:client:syncZones', -1, Gangs.GetClientZones())
    TriggerClientEvent('gangs:client:syncWars', -1, Gangs.GetClientWars())
    Gangs.StartZoneWorkers()
    Gangs.StartWarTicker()
    print(('[^2gangs^7] Loaded %s orgs, %s zones'):format(
        tostring((function()
            local n = 0
            for _ in pairs(Gangs.Orgs) do n += 1 end
            return n
        end)()),
        tostring((function()
            local n = 0
            for _ in pairs(Gangs.Zones) do n += 1 end
            return n
        end)())
    ))
end)

AddEventHandler('playerDropped', function()
    local src = source
    local identifier = Bridge.GetIdentifier(src)
    if identifier then
        Gangs.PendingInvites[identifier] = nil
    end
end)

lib.callback.register('gangs:getMenuData', function(source)
    local ok, reason = Gangs.CanUseMenu(source)
    if not ok then
        return { error = reason }
    end
    return Gangs.BuildPlayerPayload(source)
end)

RegisterNetEvent('gangs:server:requestSync', function()
    local src = source
    TriggerClientEvent('gangs:client:syncZones', src, Gangs.GetClientZones())
    TriggerClientEvent('gangs:client:syncWars', src, Gangs.GetClientWars())
end)
