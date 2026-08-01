-- Optional integration hooks. Edit freely for your server.

--- Called when a war ends.
--- winnerInfo: { organization, score, playersInvolved }
--- loserInfo: { [orgName] = { organization, score, playersInvolved } }
function onWarEnd(winnerInfo, loserInfo)
    -- Example: TriggerEvent('your_dispatch:warEnded', winnerInfo, loserInfo)
end

--- Optional inventory wipe used by bounty claims when Config.IsBountyInventoryWipe = true
function ClearPlayerInventory(source, identifier)
    -- Implement for your inventory if needed.
end

--- Optional police count gate. Return true to allow wars/actions.
function checkPoliceAmount()
    return true
end

--- Optional dispatch call when contested activity happens.
function callDispatch(x, y, zoneId, source)
    -- Example:
    -- exports['ps-dispatch']:CustomAlert({ ... })
end
