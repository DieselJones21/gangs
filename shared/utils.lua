Gangs = Gangs or {}

function Gangs.Locale(key, ...)
    local lang = Config.Locale or 'en'
    local dict = Locales[lang] or Locales.en or {}
    local str = dict[key] or key
    if select('#', ...) > 0 then
        return str:format(...)
    end
    return str
end

function Gangs.Debug(...)
    if Config.Debug then
        print('[gangs]', ...)
    end
end

function Gangs.Decode(jsonStr, fallback)
    if type(jsonStr) == 'table' then return jsonStr end
    if not jsonStr or jsonStr == '' then return fallback end
    local ok, data = pcall(json.decode, jsonStr)
    if ok and data ~= nil then return data end
    return fallback
end

function Gangs.Encode(value)
    return json.encode(value or {})
end

function Gangs.DeepCopy(tbl)
    if type(tbl) ~= 'table' then return tbl end
    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = Gangs.DeepCopy(v)
    end
    return copy
end

function Gangs.HasPermission(permissions, key)
    if type(permissions) ~= 'table' then return false end
    return permissions[key] == true
end

function Gangs.RewardAmount(value)
    if type(value) == 'table' then
        local min = tonumber(value[1]) or 0
        local max = tonumber(value[2]) or min
        if max < min then max = min end
        return math.random(min, max)
    end
    return tonumber(value) or 0
end

function Gangs.IsWarTimeAllowed()
    local windows = Config.TimeWhenWarCanStart
    if not windows or #windows == 0 then return true end

    local hour = tonumber(os.date('%H'))
    local minute = tonumber(os.date('%M'))
    local now = hour * 60 + minute

    for _, window in ipairs(windows) do
        local beginH = window.beginWar.h or 0
        local beginM = window.beginWar.m or 0
        local endH = window.endWar.h or 24
        local endM = window.endWar.m or 0
        local startMin = beginH * 60 + beginM
        local endMin = endH * 60 + endM

        if endMin <= startMin then
            -- wraps midnight
            if now >= startMin or now < endMin then
                return true
            end
        elseif now >= startMin and now < endMin then
            return true
        end
    end

    return false
end

function Gangs.PolygonCenter(points)
    local x, y = 0.0, 0.0
    local n = #points
    if n == 0 then return 0.0, 0.0 end
    for i = 1, n do
        local p = points[i]
        x = x + (p.x or p[1])
        y = y + (p.y or p[2])
    end
    return x / n, y / n
end

function Gangs.PointInPolygon(x, y, points)
    local inside = false
    local j = #points
    for i = 1, #points do
        local xi = points[i].x or points[i][1]
        local yi = points[i].y or points[i][2]
        local xj = points[j].x or points[j][1]
        local yj = points[j].y or points[j][2]
        local intersect = ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / ((yj - yi) + 0.0) + xi)
        if intersect then inside = not inside end
        j = i
    end
    return inside
end

function Gangs.NormalizePoints(points)
    local out = {}
    for i, p in ipairs(points or {}) do
        if type(p) == 'vector2' or type(p) == 'vector3' then
            out[i] = { x = p.x + 0.0, y = p.y + 0.0 }
        elseif type(p) == 'table' then
            out[i] = { x = (p.x or p[1]) + 0.0, y = (p.y or p[2]) + 0.0 }
        end
    end
    return out
end
