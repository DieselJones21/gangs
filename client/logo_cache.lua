Gangs = Gangs or {}
Gangs.LogoCache = Gangs.LogoCache or {}

local function safeId(url)
    return tostring(joaat(url))
end

local function encodeURIComponent(str)
    str = tostring(str or '')
    return (str:gsub('([^%w%-_%.%~])', function(c)
        return ('%%%02X'):format(string.byte(c))
    end))
end

function Gangs.EnsureLogoTexture(url)
    if type(url) ~= 'string' or url == '' then return nil end
    local cached = Gangs.LogoCache[url]
    if cached and cached.ready then
        return cached.dict, cached.name
    end
    if cached and cached.loading then
        return nil
    end

    local id = safeId(url)
    local dict = ('gangs_logo_%s'):format(id)
    local name = 'img'
    local size = 256

    -- Transparent NUI frame so logos aren't stuck on a white square
    local duiUrl = ('https://cfx-nui-%s/web/logo.html?img=%s'):format(
        GetCurrentResourceName(),
        encodeURIComponent(url)
    )

    Gangs.LogoCache[url] = { loading = true, dict = dict, name = name }
    local dui = CreateDui(duiUrl, size, size)
    if not dui then
        Gangs.LogoCache[url] = nil
        return nil
    end

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

    -- Give the DUI a moment to paint before first draw looks blank
    return dict, name
end

local function drawCircleBacking(cx, cy, cz, tx, ty, nx, ny, radius, r, g, b, a)
    local segments = 16
    for i = 0, segments - 1 do
        local a0 = (i / segments) * math.pi * 2
        local a1 = ((i + 1) / segments) * math.pi * 2
        local x0 = cx + (tx * math.cos(a0) + nx * 0.02) * radius
        local y0 = cy + (ty * math.cos(a0) + ny * 0.02) * radius
        local z0 = cz + math.sin(a0) * radius
        local x1 = cx + (tx * math.cos(a1) + nx * 0.02) * radius
        local y1 = cy + (ty * math.cos(a1) + ny * 0.02) * radius
        local z1 = cz + math.sin(a1) * radius
        DrawPoly(cx + nx * 0.02, cy + ny * 0.02, cz, x0, y0, z0, x1, y1, z1, r, g, b, a)
        DrawPoly(cx + nx * 0.02, cy + ny * 0.02, cz, x1, y1, z1, x0, y0, z0, r, g, b, a)
    end
end

function Gangs.DrawLogoOnWall(url, ax, ay, az, bx, by, bz, size, tintHex)
    local cached = Gangs.LogoCache[url]
    local dict, name = Gangs.EnsureLogoTexture(url)
    if not dict then return end
    -- wait briefly after create so texture isn't empty/white flash
    if cached and cached.created and (GetGameTimer() - cached.created) < 250 then
        return
    end

    size = size or Config.WarWallLogoSize or 2.6
    local mx = (ax + bx) * 0.5
    local my = (ay + by) * 0.5
    local mz = (az + bz) * 0.5

    local dx = bx - ax
    local dy = by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.2 then return end

    local tx, ty = dx / len, dy / len
    local nx, ny = -ty, tx
    local half = size * 0.5
    local inset = 0.12

    local cx = mx + nx * inset
    local cy = my + ny * inset

    local x1 = cx - tx * half
    local y1 = cy - ty * half
    local x2 = cx + tx * half
    local y2 = cy + ty * half
    local z1 = mz - half
    local z2 = mz + half

    -- Dark circular plate behind logo so white image backgrounds are less harsh
    local br, bg, bb = 10, 12, 16
    if tintHex then
        local hex = tostring(tintHex):gsub('#', '')
        if #hex >= 6 then
            br = math.floor((tonumber(hex:sub(1, 2), 16) or 10) * 0.2)
            bg = math.floor((tonumber(hex:sub(3, 4), 16) or 12) * 0.2)
            bb = math.floor((tonumber(hex:sub(5, 6), 16) or 16) * 0.2)
        end
    end
    drawCircleBacking(cx, cy, mz, tx, ty, nx, ny, half * 1.08, br, bg, bb, 180)

    local r, g, b, a = 255, 255, 255, 235
    DrawSpritePoly(x1, y1, z2, x2, y2, z2, x2, y2, z1, r, g, b, a, dict, name, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0)
    DrawSpritePoly(x1, y1, z2, x2, y2, z1, x1, y1, z1, r, g, b, a, dict, name, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0)
    DrawSpritePoly(x2, y2, z2, x1, y1, z2, x1, y1, z1, r, g, b, a, dict, name, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0)
    DrawSpritePoly(x2, y2, z2, x1, y1, z1, x2, y2, z1, r, g, b, a, dict, name, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, entry in pairs(Gangs.LogoCache) do
        if entry.dui then
            DestroyDui(entry.dui)
        end
    end
    Gangs.LogoCache = {}
end)
