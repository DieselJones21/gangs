local function sanitizeName(name)
    name = tostring(name or ''):lower():gsub('%s+', '_'):gsub('[^%w_]', '')
    return name:sub(1, 32)
end

local function createDefaultRoles(orgId)
    local roleIds = {}
    for _, def in ipairs(Config.DefaultRoles) do
        local id = MySQL.insert.await(
            'INSERT INTO gangs_roles (org_id, name, grade, permissions) VALUES (?, ?, ?, ?)',
            { orgId, def.name, def.grade or 0, Gangs.Encode(def.permissions or {}) }
        )
        roleIds[#roleIds + 1] = {
            id = id,
            name = def.name,
            grade = def.grade or 0,
            permissions = Gangs.DeepCopy(def.permissions or {}),
            org_id = orgId,
        }
    end
    return roleIds
end

function Gangs.CreateOrganization(source, label, color)
    local identifier = Bridge.GetIdentifier(source)
    if not identifier then return false, 'invalid_player' end
    if Gangs.Members[identifier] then
        return false, Gangs.Locale('already_in_org')
    end
    if not Config.CanCreateOrganizations then
        return false, Gangs.Locale('org_create_disabled')
    end

    label = tostring(label or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if label == '' or #label < 2 then
        return false, 'Invalid organization name'
    end

    local name = sanitizeName(label)
    if name == '' then return false, 'Invalid organization name' end
    if Gangs.Orgs[name] then
        return false, Gangs.Locale('org_exists')
    end

    local price = tonumber(Config.OrganizationCreationPrice) or 0
    if price > 0 then
        local have = Bridge.GetItemCount(source, Config.CurrencyName)
        if have < price then
            return false, Gangs.Locale('org_need_funds', price, Config.CurrencyLabel)
        end
        Bridge.RemoveItem(source, Config.CurrencyName, price)
    end

    color = color or '#DE2A21'
    local orgId = MySQL.insert.await(
        'INSERT INTO gangs_organizations (name, label, color, owner) VALUES (?, ?, ?, ?)',
        { name, label, color, identifier }
    )

    local roles = createDefaultRoles(orgId)
    local leaderRole = roles[1]

    local org = {
        id = orgId,
        name = name,
        label = label,
        color = color,
        owner = identifier,
        power = 0,
        bank = 0,
        roles = {},
        members = {},
    }
    for _, role in ipairs(roles) do
        org.roles[role.id] = role
    end

    local member = {
        id = MySQL.insert.await(
            'INSERT INTO gangs_members (org_id, identifier, citizenid, name, role_id) VALUES (?, ?, ?, ?, ?)',
            { orgId, identifier, identifier, Bridge.GetCharName(source), leaderRole.id }
        ),
        org_id = orgId,
        identifier = identifier,
        citizenid = identifier,
        name = Bridge.GetCharName(source),
        role_id = leaderRole.id,
        org_name = name,
    }

    org.members[identifier] = member
    Gangs.Orgs[name] = org
    Gangs.Members[identifier] = member
    Gangs.EnsureStats(source)

    Bridge.Notify(source, Gangs.Locale('org_created', label), 'success')
    return true, org
end

function Gangs.InviteMember(source, targetSource)
    local member = Gangs.GetMember(source)
    if not member then return false, Gangs.Locale('not_in_org') end
    if not Gangs.MemberHasPermission(member, 'canInvite') then
        return false, Gangs.Locale('no_permission')
    end

    local org = Gangs.GetOrgById(member.org_id)
    if not org then return false, Gangs.Locale('not_in_org') end

    local targetIdentifier = Bridge.GetIdentifier(targetSource)
    if not targetIdentifier then return false, Gangs.Locale('invalid_target') end
    if Gangs.Members[targetIdentifier] then
        return false, Gangs.Locale('already_in_org')
    end

    if Config.MaximumOrganizationMembers then
        local count = 0
        for _ in pairs(org.members) do count += 1 end
        if count >= Config.MaximumOrganizationMembers then
            return false, 'Organization is full'
        end
    end

    Gangs.PendingInvites[targetIdentifier] = org.name
    Bridge.Notify(source, Gangs.Locale('invited', Bridge.GetCharName(targetSource), org.label), 'success')
    Bridge.Notify(targetSource, Gangs.Locale('invite_received', org.label), 'inform')
    return true
end

function Gangs.AcceptInvite(source)
    local identifier = Bridge.GetIdentifier(source)
    if not identifier then return false end
    if Gangs.Members[identifier] then
        return false, Gangs.Locale('already_in_org')
    end

    local orgName = Gangs.PendingInvites[identifier]
    if not orgName then return false, 'No pending invite' end
    local org = Gangs.GetOrg(orgName)
    if not org then
        Gangs.PendingInvites[identifier] = nil
        return false, 'Organization no longer exists'
    end

    local memberRole
    for _, role in pairs(org.roles) do
        if not memberRole or (role.grade or 0) < (memberRole.grade or 0) then
            memberRole = role
        end
    end
    if not memberRole then return false, 'No roles configured' end

    local rowId = MySQL.insert.await(
        'INSERT INTO gangs_members (org_id, identifier, citizenid, name, role_id) VALUES (?, ?, ?, ?, ?)',
        { org.id, identifier, identifier, Bridge.GetCharName(source), memberRole.id }
    )

    local member = {
        id = rowId,
        org_id = org.id,
        identifier = identifier,
        citizenid = identifier,
        name = Bridge.GetCharName(source),
        role_id = memberRole.id,
        org_name = org.name,
    }
    org.members[identifier] = member
    Gangs.Members[identifier] = member
    Gangs.PendingInvites[identifier] = nil
    Gangs.EnsureStats(source)

    Bridge.Notify(source, Gangs.Locale('joined_org', org.label), 'success')
    return true
end

local function findLowestRole(org)
    local lowest
    for _, role in pairs(org.roles) do
        if not lowest or (role.grade or 0) < (lowest.grade or 0) then
            lowest = role
        end
    end
    return lowest
end

local function findHighestRole(org)
    local highest
    for _, role in pairs(org.roles) do
        if not highest or (role.grade or 0) > (highest.grade or 0) then
            highest = role
        end
    end
    return highest
end

function Gangs.LeaveOrganization(source)
    local member, identifier = Gangs.GetMember(source)
    if not member then return false, Gangs.Locale('not_in_org') end
    local org = Gangs.GetOrgById(member.org_id)
    if not org then return false, Gangs.Locale('not_in_org') end

    local wasOwner = org.owner == identifier
    MySQL.query.await('DELETE FROM gangs_members WHERE id = ?', { member.id })
    org.members[identifier] = nil
    Gangs.Members[identifier] = nil

    local remaining = 0
    local successor
    for id, m in pairs(org.members) do
        remaining += 1
        if not successor then successor = m end
        local role = org.roles[m.role_id]
        local succRole = successor and org.roles[successor.role_id]
        if role and succRole and (role.grade or 0) > (succRole.grade or 0) then
            successor = m
        end
    end

    if remaining == 0 and Config.RemoveOrganizationWhenEmpty then
        MySQL.query.await('DELETE FROM gangs_organizations WHERE id = ?', { org.id })
        Gangs.Orgs[org.name] = nil
        for _, zone in pairs(Gangs.Zones) do
            if zone.owner_org == org.name then
                zone.owner_org = nil
                Gangs.SaveZone(zone)
            end
        end
        TriggerClientEvent('gangs:client:syncZones', -1, Gangs.GetClientZones())
    elseif wasOwner and Config.TransferOwnershipWhenOwnerLeaves and successor then
        org.owner = successor.identifier
        local top = findHighestRole(org)
        if top then
            successor.role_id = top.id
            MySQL.update.await('UPDATE gangs_members SET role_id = ? WHERE id = ?', { top.id, successor.id })
        end
        MySQL.update.await('UPDATE gangs_organizations SET owner = ? WHERE id = ?', { org.owner, org.id })
    end

    Bridge.Notify(source, Gangs.Locale('left_org'), 'inform')
    return true
end

function Gangs.KickMember(source, targetIdentifier)
    local member = Gangs.GetMember(source)
    if not member then return false, Gangs.Locale('not_in_org') end
    if not Gangs.MemberHasPermission(member, 'canKick') then
        return false, Gangs.Locale('no_permission')
    end

    local org = Gangs.GetOrgById(member.org_id)
    local target = org and org.members[targetIdentifier]
    if not org or not target then return false, Gangs.Locale('invalid_target') end
    if org.owner == targetIdentifier then
        return false, 'Cannot kick the owner'
    end

    MySQL.query.await('DELETE FROM gangs_members WHERE id = ?', { target.id })
    org.members[targetIdentifier] = nil
    Gangs.Members[targetIdentifier] = nil

    local targetSrc = Gangs.GetSourceByIdentifier(targetIdentifier)
    if targetSrc then
        Bridge.Notify(targetSrc, Gangs.Locale('left_org'), 'error')
    end
    Bridge.Notify(source, Gangs.Locale('kicked', target.name), 'success')
    return true
end

function Gangs.SetMemberRole(source, targetIdentifier, roleId)
    local member = Gangs.GetMember(source)
    if not member then return false, Gangs.Locale('not_in_org') end
    if not Gangs.MemberHasPermission(member, 'canPromote') then
        return false, Gangs.Locale('no_permission')
    end

    local org = Gangs.GetOrgById(member.org_id)
    local target = org and org.members[targetIdentifier]
    local role = org and org.roles[roleId]
    if not org or not target or not role then
        return false, Gangs.Locale('invalid_target')
    end

    target.role_id = roleId
    MySQL.update.await('UPDATE gangs_members SET role_id = ? WHERE id = ?', { roleId, target.id })
    Bridge.Notify(source, Gangs.Locale('role_updated'), 'success')
    return true
end

lib.callback.register('gangs:createOrganization', function(source, label, color)
    local ok, result = Gangs.CreateOrganization(source, label, color)
    if not ok then return { success = false, error = result } end
    return { success = true, data = Gangs.BuildPlayerPayload(source) }
end)

lib.callback.register('gangs:inviteNearby', function(source, targetId)
    local ok, err = Gangs.InviteMember(source, tonumber(targetId))
    return { success = ok, error = err, data = ok and Gangs.BuildPlayerPayload(source) or nil }
end)

lib.callback.register('gangs:leaveOrganization', function(source)
    local ok, err = Gangs.LeaveOrganization(source)
    return { success = ok, error = err, data = ok and Gangs.BuildPlayerPayload(source) or nil }
end)

lib.callback.register('gangs:kickMember', function(source, targetIdentifier)
    local ok, err = Gangs.KickMember(source, targetIdentifier)
    return { success = ok, error = err, data = ok and Gangs.BuildPlayerPayload(source) or nil }
end)

lib.callback.register('gangs:setMemberRole', function(source, targetIdentifier, roleId)
    local ok, err = Gangs.SetMemberRole(source, targetIdentifier, tonumber(roleId))
    return { success = ok, error = err, data = ok and Gangs.BuildPlayerPayload(source) or nil }
end)

RegisterCommand('gangaccept', function(source)
    if source == 0 then return end
    local ok, err = Gangs.AcceptInvite(source)
    if not ok and err then Bridge.Notify(source, err, 'error') end
end, false)

-- Auto-create from QB gang on join
AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = player.PlayerData and player.PlayerData.source or source
    local gang = Bridge.GetGangName(src)
    if not gang or gang == 'none' then return end
    local color = Config.AutoCreateQBGang[gang]
    if not color then return end
    local identifier = Bridge.GetIdentifier(src)
    if not identifier or Gangs.Members[identifier] then return end

    if not Gangs.Orgs[gang] then
        local previousPrice = Config.OrganizationCreationPrice
        Config.OrganizationCreationPrice = 0
        Gangs.CreateOrganization(src, gang:gsub('^%l', string.upper), color)
        Config.OrganizationCreationPrice = previousPrice
    else
        -- join existing mapped gang as member if empty invite path
        local org = Gangs.Orgs[gang]
        local role = findLowestRole(org)
        if not role then return end
        local rowId = MySQL.insert.await(
            'INSERT INTO gangs_members (org_id, identifier, citizenid, name, role_id) VALUES (?, ?, ?, ?, ?)',
            { org.id, identifier, identifier, Bridge.GetCharName(src), role.id }
        )
        local member = {
            id = rowId,
            org_id = org.id,
            identifier = identifier,
            citizenid = identifier,
            name = Bridge.GetCharName(src),
            role_id = role.id,
            org_name = org.name,
        }
        org.members[identifier] = member
        Gangs.Members[identifier] = member
    end
end)
