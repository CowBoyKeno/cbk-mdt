local function now()
    return os.date('%Y-%m-%d %H:%M:%S')
end

local function str(value, maxLen)
    if type(value) ~= 'string' then
        return ''
    end
    local cleaned = value:gsub('[%z\1-\8\11\12\14-\31]', '')
    if maxLen and #cleaned > maxLen then
        cleaned = cleaned:sub(1, maxLen)
    end
    return cleaned
end

local radarRateLimit = {}
local radarQueue = {}
local radarFlushing = false

local function canProcessRadar(source)
    local current = GetGameTimer()
    local last = radarRateLimit[source] or 0
    local cooldown = tonumber((Config.Security or {}).radarCooldownMs) or 1000
    if current - last < cooldown then
        return false
    end
    radarRateLimit[source] = current
    return true
end

local function isRadarSourceValid(source)
    local ped = GetPlayerPed(source)
    if not ped or ped <= 0 then
        return false
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    return vehicle and vehicle > 0
end

local function flushRadarQueue()
    if radarFlushing or #radarQueue == 0 then
        return
    end

    radarFlushing = true

    local batchSize = tonumber((Config.Security or {}).radarBatchSize) or 25
    local batch = {}

    while #batch < batchSize and #radarQueue > 0 do
        batch[#batch + 1] = table.remove(radarQueue)
    end

    local values = {}
    local params = {}
    for _, row in ipairs(batch) do
        values[#values + 1] = '(?, ?, ?, ?, ?, ?, ?, ?)'
        params[#params + 1] = row.plate
        params[#params + 1] = row.speed
        params[#params + 1] = row.location
        params[#params + 1] = row.radar_source
        params[#params + 1] = row.officer_identifier
        params[#params + 1] = row.officer_name
        params[#params + 1] = row.created_at
        params[#params + 1] = row.updated_at
    end

    if #values > 0 then
        local sql = [[
            INSERT INTO mdt_radar_logs (
                plate, speed, location, radar_source, officer_identifier, officer_name, created_at, updated_at
            ) VALUES
        ]] .. table.concat(values, ', ')

        local ok, err = pcall(function()
            MySQL.insert.await(sql, params)
        end)

        if not ok then
            print(('[cbk-mdt] Radar batch insert failed: %s'):format(tostring(err)))
        end
    end

    radarFlushing = false

    if #radarQueue > 0 then
        SetTimeout(50, flushRadarQueue)
    end
end

local function insertRadarLog(source, payload)
    if not Config.Radar.enabled then
        return
    end

    if not CBK_MDT.IsOfficerAllowed(source) then
        return
    end

    if not isRadarSourceValid(source) then
        return
    end

    if not canProcessRadar(source) then
        return
    end

    local plate = string.upper(str(payload.plate or '', 12))
    local speed = tonumber(payload.speed) or 0
    local maxSpeed = tonumber((Config.Security or {}).radarMaxSpeed) or 260
    speed = math.floor(math.max(0, math.min(speed, maxSpeed)))
    local officerIdentifier, officerName = CBK_MDT.EnsureOfficer(source)

    if plate == '' then
        return
    end

    radarQueue[#radarQueue + 1] = {
        plate = plate,
        speed = speed,
        location = str(payload.location or '', 120),
        radar_source = str(payload.radar_source or Config.Radar.provider or 'unknown', 40),
        officer_identifier = officerIdentifier,
        officer_name = officerName,
        created_at = now(),
        updated_at = now()
    }

    local batchSize = tonumber((Config.Security or {}).radarBatchSize) or 25
    if #radarQueue >= batchSize then
        flushRadarQueue()
    end
end

RegisterNetEvent('cbk_mdt:server:radarHit', function(payload)
    local source = source
    if type(payload) ~= 'table' then
        return
    end

    insertRadarLog(source, payload)
end)

CreateThread(function()
    local flushMs = tonumber((Config.Security or {}).radarFlushMs) or 1500
    while true do
        Wait(flushMs)
        flushRadarQueue()
    end
end)

CBK_MDT.RegisterAction('list_radar_logs', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'view')
    if not allowed then
        return false, reason
    end

    payload = payload or {}
    local plate = string.upper(str(payload.plate or '', 12))

    local sql = [[
        SELECT id, plate, speed, location, radar_source, officer_name, created_at
        FROM mdt_radar_logs
    ]]
    local params = {}

    if plate ~= '' then
        sql = sql .. ' WHERE plate LIKE ?'
        params[#params + 1] = ('%%%s%%'):format(plate)
    end

    sql = sql .. ' ORDER BY id DESC LIMIT ?'
    params[#params + 1] = Config.MaxSearchResults

    return true, MySQL.query.await(sql, params)
end)