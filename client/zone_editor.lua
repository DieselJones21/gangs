local editing = false
local points = {}
local props = {}

local function clearEditorProps()
    for _, obj in ipairs(props) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    props = {}
end

local function addPointMarker(coords)
    local obj = CreateObject(`prop_mp_cone_02`, coords.x, coords.y, coords.z - 1.0, false, false, false)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    props[#props + 1] = obj
end

local function stopEditor()
    editing = false
    points = {}
    clearEditorProps()
    Bridge.Notify('Zone editor closed', 'inform')
end

local function finishZone()
    if #points < 3 then
        Bridge.Notify('Need at least 3 points', 'error')
        return
    end

    local templates = {}
    for key, template in pairs(Config.ZoneTypeTemplates or {}) do
        templates[#templates + 1] = { value = key, label = template.Title or key }
    end
    table.sort(templates, function(a, b) return a.label < b.label end)

    local input = lib.inputDialog('Create Zone', {
        { type = 'input', label = 'Zone Key', required = true, placeholder = 'grove_house' },
        { type = 'input', label = 'Title', required = true, placeholder = 'Grove Street' },
        {
            type = 'select',
            label = 'Template',
            options = (function()
                local opts = { { value = 'none', label = 'Custom / House' } }
                for _, t in ipairs(templates) do opts[#opts + 1] = t end
                return opts
            end)(),
            default = 'none',
        },
        {
            type = 'select',
            label = 'Type (if custom)',
            options = {
                { value = 'house', label = 'House' },
                { value = 'generation', label = 'Generation' },
                { value = 'processing', label = 'Processing' },
                { value = 'sales', label = 'Sales' },
                { value = 'continental', label = 'Continental' },
            },
            default = 'house',
        },
    })

    if not input then return end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local flat = {}
    local minZ, maxZ = coords.z - 2.0, coords.z + 15.0
    for i, p in ipairs(points) do
        flat[i] = { x = p.x, y = p.y }
        if p.z < minZ then minZ = p.z - 1.0 end
        if p.z > maxZ - 10.0 then maxZ = p.z + 10.0 end
    end

    local result = lib.callback.await('gangs:adminCreateZone', false, {
        key = input[1],
        title = input[2],
        template = input[3] ~= 'none' and input[3] or nil,
        type = input[4],
        points = flat,
        minZ = minZ,
        maxZ = maxZ,
        centerZ = coords.z,
    })

    if result and result.success then
        Bridge.Notify('Zone created', 'success')
        stopEditor()
    else
        Bridge.Notify(result and result.error or 'Failed to create zone', 'error')
    end
end

RegisterNetEvent('gangs:client:openZoneEditor', function()
    if editing then
        stopEditor()
        return
    end

    editing = true
    points = {}
    clearEditorProps()
    Bridge.Notify('Zone editor: E add point | ENTER create | BACKSPACE undo | X cancel', 'inform')

    CreateThread(function()
        while editing do
            Wait(0)
            DisableControlAction(0, 24, true)

            for i = 1, #points do
                local a = points[i]
                local b = points[i + 1] or points[1]
                DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, 0, 200, 255, 200)
                DrawMarker(28, a.x, a.y, a.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.25, 0.25, 0.25, 0, 180, 255, 180, false, false, 2, false, nil, nil, false)
            end

            if IsControlJustPressed(0, 38) then -- E
                local coords = GetEntityCoords(PlayerPedId())
                points[#points + 1] = coords
                addPointMarker(coords)
                Bridge.Notify(('Point %s added'):format(#points), 'inform')
            elseif IsControlJustPressed(0, 191) then -- ENTER
                finishZone()
            elseif IsControlJustPressed(0, 194) then -- BACKSPACE
                if #points > 0 then
                    points[#points] = nil
                    local obj = props[#props]
                    if obj and DoesEntityExist(obj) then DeleteEntity(obj) end
                    props[#props] = nil
                end
            elseif IsControlJustPressed(0, 73) then -- X
                stopEditor()
            end
        end
    end)
end)
