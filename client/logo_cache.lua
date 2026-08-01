Gangs = Gangs or {}
Gangs.LogoCache = Gangs.LogoCache or {}

local function safeId(url)
    return tostring(joaat(url))
end

function Gangs.EnsureLogoTexture(url)
    if type(url) ~= 'string' or url == '' then return nil end

    local cached = Gangs.LogoCache[url]
    if cached and cached.ready and cached.dict and cached.name then
        return cached.dict, cached.name
    end
    if cached and cached.loading then
        return nil
    end

    local id = safeId(url)
    local dict = ('gangs_logo_%s'):format(id)
    local name = 'logo'

    Gangs.LogoCache[url] = { loading = true, dict = dict, name = name }

    CreateThread(function()
        -- Load the image URL directly (most reliable for CreateDui)
        local dui = CreateDui(url, 512, 512)
        if not dui then
            Gangs.LogoCache[url] = nil
            return
        end

        local timeout = GetGameTimer() + 8000
        while not IsDuiAvailable(dui) and GetGameTimer() < timeout do
            Wait(50)
        end

        if not IsDuiAvailable(dui) then
            DestroyDui(dui)
            Gangs.LogoCache[url] = nil
            return
        end

        -- Extra paint time so the first frames aren't blank
        Wait(350)

        local handle = GetDuiHandle(dui)
        local txd = CreateRuntimeTxd(dict)
        CreateRuntimeTextureFromDuiHandle(txd, name, handle)

        Gangs.LogoCache[url] = {
            ready = true,
            loading = false,
            dict = dict,
            name = name,
            dui = dui,
            handle = handle,
            created = GetGameTimer(),
        }
    end)

    return nil
end

function Gangs.DrawLogoOnWall(url, ax, ay, az, bx, by, bz, size, tintHex)
    local dict, name = Gangs.EnsureLogoTexture(url)
    if not dict or not name then return end

    local cached = Gangs.LogoCache[url]
    if cached and cached.created and (GetGameTimer() - cached.created) < 100 then
        return
    end

    size = size or Config.WarWallLogoSize or 2.6
    local mx = (ax + bx) * 0.5
    local my = (ay + by) * 0.5
    local mz = (az + bz) * 0.55

    local dx = bx - ax
    local dy = by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    if len < size then return end

    local tx, ty = dx / len, dy / len
    local nx, ny = -ty, tx
    local half = size * 0.5
    local inset = 0.15

    local cx = mx + nx * inset
    local cy = my + ny * inset

    -- Dark plate behind logo (slightly larger)
    local plate = half * 1.15
    local px1, py1 = cx - tx * plate, cy - ty * plate
    local px2, py2 = cx + tx * plate, cy + ty * plate
    local pz1, pz2 = mz - plate, mz + plate
    local pr, pg, pb = 8, 8, 10
    if tintHex then
        local hex = tostring(tintHex):gsub('#', '')
        if #hex >= 6 then
            pr = math.floor((tonumber(hex:sub(1, 2), 16) or 20) * 0.15)
            pg = math.floor((tonumber(hex:sub(3, 4), 16) or 20) * 0.15)
            pb = math.floor((tonumber(hex:sub(5, 6), 16) or 20) * 0.15)
        end
    end

    DrawPoly(px1, py1, pz2, px2, py2, pz2, px2, py2, pz1, pr, pg, pb, 200)
    DrawPoly(px1, py1, pz2, px2, py2, pz1, px1, py1, pz1, pr, pg, pb, 200)
    DrawPoly(px2, py2, pz2, px1, py1, pz2, px1, py1, pz1, pr, pg, pb, 200)
    DrawPoly(px2, py2, pz2, px1, py1, pz1, px2, py2, pz1, pr, pg, pb, 200)

    local x1, y1 = cx - tx * half, cy - ty * half
    local x2, y2 = cx + tx * half, cy + ty * half
    local z1, z2 = mz - half, mz + half

    -- DrawSpritePoly UVs: (u,v,w) per vertex
    local r, g, b, a = 255, 255, 255, 255
    DrawSpritePoly(
        x1, y1, z2,
        x2, y2, z2,
        x2, y2, z1,
        r, g, b, a,
        dict, name,
        0.0, 0.0, 0.0,
        1.0, 0.0, 0.0,
        1.0, 1.0, 0.0
    )
    DrawSpritePoly(
        x1, y1, z2,
        x2, y2, z1,
        x1, y1, z1,
        r, g, b, a,
        dict, name,
        0.0, 0.0, 0.0,
        1.0, 1.0, 0.0,
        0.0, 1.0, 0.0
    )
    -- reverse side
    DrawSpritePoly(
        x2, y2, z2,
        x1, y1, z2,
        x1, y1, z1,
        r, g, b, a,
        dict, name,
        0.0, 0.0, 0.0,
        1.0, 0.0, 0.0,
        1.0, 1.0, 0.0
    )
    DrawSpritePoly(
        x2, y2, z2,
        x1, y1, z1,
        x2, y2, z1,
        r, g, b, a,
        dict, name,
        0.0, 0.0, 0.0,
        1.0, 1.0, 0.0,
        0.0, 1.0, 0.0
    )
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, entry in pairs(Gangs.LogoCache) do
        if entry.dui then
            pcall(DestroyDui, entry.dui)
        end
    end
    Gangs.LogoCache = {}
end)
