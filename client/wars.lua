CreateThread(function()
    while true do
        local sleep = 1000
        local wars = Gangs.Wars or {}
        if next(wars) then
            sleep = 0
            local y = 0.02
            for _, war in pairs(wars) do
                local remaining = math.max(0, (war.endsAt or 0) - os.time())
                local mins = math.floor(remaining / 60)
                local secs = remaining % 60
                local text = ('WAR %s | %s %d vs %s %d | %02d:%02d'):format(
                    war.zoneTitle or war.zoneKey,
                    war.attacker or '?',
                    war.attackerScore or 0,
                    war.defender or 'Unowned',
                    war.defenderScore or 0,
                    mins,
                    secs
                )
                SetTextFont(4)
                SetTextScale(0.35, 0.35)
                SetTextColour(255, 80, 80, 220)
                SetTextOutline()
                SetTextEntry('STRING')
                AddTextComponentString(text)
                DrawText(0.015, y)
                y = y + 0.025
            end
        end
        Wait(sleep)
    end
end)
