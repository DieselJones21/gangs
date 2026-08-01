Gangs = Gangs or {}
Gangs.LogoCache = Gangs.LogoCache or {}

local function safeId(url)
    return tostring(joaat(url))
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

    Gangs.LogoCache[url] = { loading = true, dict = dict, name = name }
    local dui = CreateDui(url, size, size)
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
    }
    return dict, name
end

function Gangs.DrawLogoOnWall(url, ax, ay, az, bx, by, bz, size)
    local dict, name = Gangs.EnsureLogoTexture(url)
    if not dict then return end

    size = size or Config.WarWallLogoSize or 2.8
    local mx = (ax + bx) * 0.5
    local my = (ay + by) * 0.5
    local mz = (az + bz) * 0.5

    local dx = bx - ax
    local dy = by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.2 then return end

    -- wall tangent / normal for a facing quad
    local tx, ty = dx / len, dy / len
    local nx, ny = -ty, tx
    local half = size * 0.5
    local inset = 0.08

    local cx = mx + nx * inset
    local cy = my + ny * inset

    local x1 = cx - tx * half
    local y1 = cy - ty * half
    local x2 = cx + tx * half
    local y2 = cy + ty * half
    local z1 = mz - half
    local z2 = mz + half

    local r, g, b, a = 255, 255, 255, 215
    -- front
    DrawSpritePoly(
        x1, y1, z2,
        x2, y2, z2,
        x2, y2, z1,
        r, g, b, a,
        dict, name,
        0.0, 0.0, 1.0,
        1.0, 0.0, 1.0,
        1.0, 1.0, 1.0
    )
    DrawSpritePoly(
        x1, y1, z2,
        x2, y2, z1,
        x1, y1, z1,
        r, g, b, a,
        dict, name,
        0.0, 0.0, 1.0,
        1.0, 1.0, 1.0,
        0.0, 1.0, 1.0
    )
    -- back
    DrawSpritePoly(
        x2, y2, z2,
        x1, y1, z2,
        x1, y1, z1,
        r, g, b, a,
        dict, name,
        0.0, 0.0, 1.0,
        1.0, 0.0, 1.0,
        1.0, 1.0, 1.0
    )
    DrawSpritePoly(
        x2, y2, z2,
        x1, y1, z1,
        x2, y2, z1,
        r, g, b, a,
        dict, name,
        0.0, 0.0, 1.0,
        1.0, 1.0, 1.0,
        0.0, 1.0, 1.0
    )
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
