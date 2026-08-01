exports('getPlayerOrganization', function(source)
    local member = Gangs.GetMember(source)
    if not member then return nil end
    local org = Gangs.GetOrgById(member.org_id)
    if not org then return nil end
    return {
        name = org.name,
        label = org.label,
        color = org.color,
        roleId = member.role_id,
    }
end)

exports('isPlayerInOrganization', function(source, orgName)
    local member = Gangs.GetMember(source)
    if not member then return false end
    local org = Gangs.GetOrgById(member.org_id)
    return org and org.name == orgName or false
end)

exports('createOrganization', function(playerSource, orgName, colorHex)
    return Gangs.CreateOrganization(playerSource, orgName, colorHex)
end)

exports('getOrganizationZone', function(zoneId)
    return Gangs.GetZone(zoneId)
end)

exports('isPlayerOrganizationZone', function(source, zoneId)
    local zone = Gangs.GetZone(zoneId)
    if not zone or not zone.owner_org then return false end
    local member = Gangs.GetMember(source)
    if not member then return false end
    local org = Gangs.GetOrgById(member.org_id)
    return org and org.name == zone.owner_org or false
end)

exports('setZoneToOrg', function(zoneId, orgName)
    return Gangs.SetZoneOwner(zoneId, orgName)
end)

exports('isWarInProgress', function(zoneId)
    return Gangs.Wars[zoneId] ~= nil
end)

exports('startWar', function(zoneId, adminSource)
    return Gangs.StartWar(adminSource or 0, zoneId, true)
end)

exports('getLeaderboard', function(limit)
    return Gangs.GetLeaderboard(limit)
end)

exports('getOrgLeaderboard', function(limit)
    return Gangs.GetOrgLeaderboard(limit)
end)

exports('addStat', function(identifier, field, amount, source)
    return Gangs.AddStat(identifier, field, amount, source)
end)

exports('getZones', function()
    return Gangs.GetClientZones()
end)
