local editing = false
local cam = nil
local points = {}
local props = {}
local speed = 1.0
local startCoords = nil
local startHeading = 0.0
local dialogOpen = false
local refreshHelp

local CONTROLS = {
    moveFwd = 32,      -- W
    moveBack = 33,     -- S
    moveLeft = 34,     -- A
    moveRight = 35,    -- D
    moveUp = 22,       -- SPACE
    moveUpAlt = 44,    -- Q
    moveDown = 36,     -- LEFT CTRL
    moveDownAlt = 26,  -- C
    faster = 21,       -- LEFT SHIFT
    addPoint = 24,     -- LEFT CLICK
    addPointAlt = 38,  -- E
    finish = 191,      -- ENTER
    undo = 194,        -- BACKSPACE
    cancel = 200,      -- ESC
    cancelAlt = 73,    -- X
    speedUp = 14,      -- scroll up
    speedDown = 15,    -- scroll down
}

local function rotationToDirection(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function clearEditorProps()
    for _, obj in ipairs(props) do
        if DoesEntityExist(obj) then
            DeleteEntity(obj)
        end
    end
    props = {}
end

local function addPointMarker(coords)
    local model = `prop_mp_cone_02`
    RequestModel(model)
    local timeout = GetGameTimer() + 2000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do
        Wait(0)
    end
    if not HasModelLoaded(model) then return end

    local obj = CreateObject(model, coords.x, coords.y, coords.z + 0.1, false, false, false)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, false, false)
    props[#props + 1] = obj
    SetModelAsNoLongerNeeded(model)
end

local function destroyCam()
    if cam and DoesCamExist(cam) then
        RenderScriptCams(false, true, 400, true, true)
        DestroyCam(cam, false)
    end
    cam = nil
end

local function restorePlayer()
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    SetEntityAlpha(ped, 255, false)
    if startCoords then
        SetEntityCoordsNoOffset(ped, startCoords.x, startCoords.y, startCoords.z, false, false, false)
        SetEntityHeading(ped, startHeading)
    end
end

local function stopEditor(silent)
    editing = false
    points = {}
    clearEditorProps()
    destroyCam()
    restorePlayer()
    lib.hideTextUI()
    if not silent then
        Bridge.Notify('Zone editor closed', 'inform')
    end
end

local function raycastFromCam(distance)
    distance = distance or 1200.0
    if not cam or not DoesCamExist(cam) then return nil end

    local camCoord = GetCamCoord(cam)
    local camRot = GetCamRot(cam, 2)
    local dir = rotationToDirection(camRot)
    local dest = camCoord + (dir * distance)

    local handle = StartShapeTestRay(
        camCoord.x, camCoord.y, camCoord.z,
        dest.x, dest.y, dest.z,
        -1,
        PlayerPedId(),
        0
    )
    local _, hit, endCoords = GetShapeTestResult(handle)
    if hit == 1 and endCoords then
        return endCoords
    end

    -- Fallback: project onto a flat plane near start height if looking into sky/void
    local planeZ = startCoords and startCoords.z or camCoord.z - 50.0
    if math.abs(dir.z) > 0.001 then
        local t = (planeZ - camCoord.z) / dir.z
        if t > 0 then
            return vector3(camCoord.x + dir.x * t, camCoord.y + dir.y * t, planeZ)
        end
    end
    return nil
end

local function drawEditorPoly()
    local hit = raycastFromCam()
    if hit then
        DrawMarker(
            28,
            hit.x, hit.y, hit.z + 0.15,
            0.0, 0.0, 0.0,
            0.0, 0.0, 0.0,
            0.35, 0.35, 0.35,
            37, 99, 235, 200,
            false, false, 2, false, nil, nil, false
        )
        DrawLine(hit.x, hit.y, hit.z, hit.x, hit.y, hit.z + 25.0, 225, 29, 46, 180)
    end

    if #points == 0 then return end

    for i = 1, #points do
        local a = points[i]
        local b = points[i + 1] or (#points >= 3 and points[1] or nil)
        DrawMarker(28, a.x, a.y, a.z + 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.28, 0.28, 0.28, 225, 29, 46, 200, false, false, 2, false, nil, nil, false)
        DrawLine(a.x, a.y, a.z, a.x, a.y, a.z + 20.0, 37, 99, 235, 160)

        if b then
            DrawLine(a.x, a.y, a.z + 0.2, b.x, b.y, b.z + 0.2, 225, 29, 46, 220)
            DrawLine(a.x, a.y, a.z + 12.0, b.x, b.y, b.z + 12.0, 37, 99, 235, 160)
            -- translucent wall preview
            DrawPoly(a.x, a.y, a.z, b.x, b.y, b.z, b.x, b.y, b.z + 12.0, 37, 99, 235, 45)
            DrawPoly(a.x, a.y, a.z, b.x, b.y, b.z + 12.0, a.x, a.y, a.z + 12.0, 37, 99, 235, 45)
            DrawPoly(a.x, a.y, a.z, b.x, b.y, b.z + 12.0, b.x, b.y, b.z, 225, 29, 46, 35)
            DrawPoly(a.x, a.y, a.z, a.x, a.y, a.z + 12.0, b.x, b.y, b.z + 12.0, 225, 29, 46, 35)
        end
    end

    -- live rubber-band to cursor hit
    if hit and #points > 0 then
        local last = points[#points]
        DrawLine(last.x, last.y, last.z + 0.2, hit.x, hit.y, hit.z + 0.2, 255, 255, 255, 180)
        if #points >= 2 then
            local first = points[1]
            DrawLine(hit.x, hit.y, hit.z + 0.2, first.x, first.y, first.z + 0.2, 255, 255, 255, 100)
        end
    end
end

local function finishZone()
    if #points < 3 then
        Bridge.Notify('Need at least 3 poly points', 'error')
        return
    end

    local templates = {}
    for key, template in pairs(Config.ZoneTypeTemplates or {}) do
        templates[#templates + 1] = { value = key, label = template.Title or key }
    end
    table.sort(templates, function(a, b) return a.label < b.label end)

    dialogOpen = true
    lib.hideTextUI()
    local input = lib.inputDialog('Create PolyZone', {
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
        {
            type = 'number',
            label = 'Min Z offset below ground',
            default = 2,
            min = 0,
            max = 50,
        },
        {
            type = 'number',
            label = 'Max Z height above ground',
            default = 40,
            min = 5,
            max = 200,
        },
    })
    dialogOpen = false
    if editing then refreshHelp() end

    if not input then return end

    local flat = {}
    local minGround = points[1].z
    local maxGround = points[1].z
    local cx, cy, cz = 0.0, 0.0, 0.0
    for i, p in ipairs(points) do
        flat[i] = { x = p.x + 0.0, y = p.y + 0.0 }
        if p.z < minGround then minGround = p.z end
        if p.z > maxGround then maxGround = p.z end
        cx = cx + p.x
        cy = cy + p.y
        cz = cz + p.z
    end
    cx = cx / #points
    cy = cy / #points
    cz = cz / #points

    local minOffset = tonumber(input[5]) or 2.0
    local maxHeight = tonumber(input[6]) or 40.0

    local result = lib.callback.await('gangs:adminCreateZone', false, {
        key = input[1],
        title = input[2],
        template = input[3] ~= 'none' and input[3] or nil,
        type = input[4],
        points = flat,
        minZ = minGround - minOffset,
        maxZ = maxGround + maxHeight,
        centerZ = cz,
    })

    if result and result.success then
        Bridge.Notify(('PolyZone created: %s'):format(input[1]), 'success')
        stopEditor(true)
    else
        Bridge.Notify(result and result.error or 'Failed to create zone', 'error')
    end
end

local function startFreecam()
    local ped = PlayerPedId()
    startCoords = GetEntityCoords(ped)
    startHeading = GetEntityHeading(ped)

    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityAlpha(ped, 0, false)

    local spawn = startCoords + vector3(0.0, 0.0, Config.ZoneEditorStartHeight or 45.0)
    cam = CreateCamWithParams(
        'DEFAULT_SCRIPTED_CAMERA',
        spawn.x, spawn.y, spawn.z,
        -45.0, 0.0, startHeading,
        75.0,
        false,
        2
    )
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 500, true, true)
end

local function updateFreecam()
    if not cam or not DoesCamExist(cam) then return end

    DisableAllControlActions(0)
    EnableControlAction(0, 1, true)  -- look LR
    EnableControlAction(0, 2, true)  -- look UD
    EnableControlAction(0, CONTROLS.speedUp, true)
    EnableControlAction(0, CONTROLS.speedDown, true)

    local lookX = GetDisabledControlNormal(0, 1)
    local lookY = GetDisabledControlNormal(0, 2)
    local rot = GetCamRot(cam, 2)
    local newX = math.max(-89.0, math.min(89.0, rot.x - lookY * 6.0))
    local newZ = rot.z - lookX * 6.0
    SetCamRot(cam, newX, 0.0, newZ, 2)

    if IsDisabledControlPressed(0, CONTROLS.faster) then
        speed = math.min(8.0, speed + 0.02)
    end

    if IsDisabledControlJustPressed(0, CONTROLS.speedUp) or IsControlJustPressed(0, CONTROLS.speedUp) then
        speed = math.min(10.0, speed + 0.25)
        refreshHelp()
    elseif IsDisabledControlJustPressed(0, CONTROLS.speedDown) or IsControlJustPressed(0, CONTROLS.speedDown) then
        speed = math.max(0.15, speed - 0.25)
        refreshHelp()
    end

    local moveSpeed = (Config.ZoneEditorBaseSpeed or 0.6) * speed
    local camCoord = GetCamCoord(cam)
    local camRot = GetCamRot(cam, 2)
    local forward = rotationToDirection(camRot)
    local right = vector3(forward.y, -forward.x, 0.0)

    local nextPos = camCoord
    if IsDisabledControlPressed(0, CONTROLS.moveFwd) then
        nextPos = nextPos + (forward * moveSpeed)
    end
    if IsDisabledControlPressed(0, CONTROLS.moveBack) then
        nextPos = nextPos - (forward * moveSpeed)
    end
    if IsDisabledControlPressed(0, CONTROLS.moveLeft) then
        nextPos = nextPos - (right * moveSpeed)
    end
    if IsDisabledControlPressed(0, CONTROLS.moveRight) then
        nextPos = nextPos + (right * moveSpeed)
    end
    if IsDisabledControlPressed(0, CONTROLS.moveUp) or IsDisabledControlPressed(0, CONTROLS.moveUpAlt) then
        nextPos = nextPos + vector3(0.0, 0.0, moveSpeed)
    end
    if IsDisabledControlPressed(0, CONTROLS.moveDown) or IsDisabledControlPressed(0, CONTROLS.moveDownAlt) then
        nextPos = nextPos - vector3(0.0, 0.0, moveSpeed)
    end

    SetCamCoord(cam, nextPos.x, nextPos.y, nextPos.z)

    -- Keep ped near camera so streaming stays active
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, nextPos.x, nextPos.y, nextPos.z - 2.0, false, false, false)
end

refreshHelp = function()
    lib.showTextUI(([[
**PolyZone Editor (Freecam)**  
WASD move · Mouse look · Space/Q up · Ctrl/C down  
Shift faster · Scroll speed (%.1fx)  
LMB / E add ground point · Backspace undo  
Enter save zone · X / Esc cancel  
Points: **%s**
]]):format(speed, #points), {
        position = 'left-center',
        icon = 'draw-polygon',
    })
end

RegisterNetEvent('gangs:client:openZoneEditor', function()
    if editing then
        stopEditor()
        return
    end

    editing = true
    points = {}
    speed = 1.0
    clearEditorProps()
    startFreecam()
    refreshHelp()
    Bridge.Notify('Freecam PolyZone editor active — fly up and click to place points', 'inform')

    CreateThread(function()
        while editing do
            Wait(0)
            if dialogOpen then
                drawEditorPoly()
            else
                updateFreecam()
                drawEditorPoly()

                local addPressed = IsDisabledControlJustPressed(0, CONTROLS.addPoint)
                    or IsDisabledControlJustPressed(0, CONTROLS.addPointAlt)
                if addPressed then
                    local hit = raycastFromCam()
                    if hit then
                        local found, groundZ = GetGroundZFor_3dCoord(hit.x, hit.y, hit.z + 50.0, false)
                        local coords = vector3(hit.x, hit.y, found and groundZ or hit.z)
                        points[#points + 1] = coords
                        addPointMarker(coords)
                        refreshHelp()
                        Bridge.Notify(('Poly point %s added'):format(#points), 'inform')
                    else
                        Bridge.Notify('Aim at the ground to place a point', 'error')
                    end
                elseif IsDisabledControlJustPressed(0, CONTROLS.finish) then
                    finishZone()
                elseif IsDisabledControlJustPressed(0, CONTROLS.undo) then
                    if #points > 0 then
                        points[#points] = nil
                        local obj = props[#props]
                        if obj and DoesEntityExist(obj) then DeleteEntity(obj) end
                        props[#props] = nil
                        refreshHelp()
                    end
                elseif IsDisabledControlJustPressed(0, CONTROLS.cancel)
                    or IsDisabledControlJustPressed(0, CONTROLS.cancelAlt) then
                    stopEditor()
                end
            end
        end
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if editing then
        stopEditor(true)
    end
end)
