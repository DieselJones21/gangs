--[[
  DROP THIS FILE INTO: core_gangs/server/getPlayerCurrency_fix.lua

  Then add this line at the BOTTOM of core_gangs/fxmanifest.lua server_scripts:
    'server/getPlayerCurrency_fix.lua',

  Restart: ensure core_gangs

  Why: newer/decompiled core_gangs uses getCurrencyAmount(), but the UI callback
  still calls getPlayerCurrency() — that global is missing and crashes /criminal.
]]

local function resolveAmount(playerOrSource)
    if type(getCurrencyAmount) == 'function' then
        local ok, amount = pcall(getCurrencyAmount, playerOrSource)
        if ok then
            return tonumber(amount) or 0
        end
    end

    -- Fallback for Qbox + ox_inventory if getCurrencyAmount is unavailable
    local src = playerOrSource
    if type(playerOrSource) == 'table' then
        src = playerOrSource.source
            or (playerOrSource.PlayerData and playerOrSource.PlayerData.source)
            or playerOrSource
    end

    local item = (Config and Config.CurrencyName) or 'bitcoin'
    local ok, count = pcall(function()
        return exports.ox_inventory:GetItemCount(src, item)
    end)
    return (ok and tonumber(count)) or 0
end

_G.getPlayerCurrency = function(playerOrSource)
    return resolveAmount(playerOrSource)
end

-- Keep common aliases in sync if missing
if type(_G.addPlayerCurrency) ~= 'function' and type(addCurrency) == 'function' then
    _G.addPlayerCurrency = addCurrency
end
if type(_G.removePlayerCurrency) ~= 'function' and type(removeCurrency) == 'function' then
    _G.removePlayerCurrency = removeCurrency
end
if type(_G.givePlayerCurrency) ~= 'function' and type(addCurrency) == 'function' then
    _G.givePlayerCurrency = addCurrency
end
if type(_G.takePlayerCurrency) ~= 'function' and type(removeCurrency) == 'function' then
    _G.takePlayerCurrency = removeCurrency
end

print('^2[core_gangs]^7 getPlayerCurrency fix loaded')
