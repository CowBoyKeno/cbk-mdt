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

local function canProcessRadar(source)
    local current = GetGameTimer()
    local last = radarRateLimit[source] or 0
    if current - last < 350 then
        return false
    end
    radarRateLimit[source] = current
    return true
end

local function insertRadarLog(source, payload)
    if not Config.Radar.enabled then
        return
    end

    if not CBK_MDT.IsOfficerAllowed(source) then
        return
    end

    if not canProcessRadar(source) then
        return
    end

    local plate = string.upper(str(payload.plate or '', 12))
    local speed = tonumber(payload.speed) or 0
    local officerIdentifier, officerName = CBK_MDT.EnsureOfficer(source)

    if plate == '' then
        return
    end

    MySQL.insert.await([[
        INSERT INTO mdt_radar_logs (
            plate, speed, location, radar_source, officer_identifier, officer_name, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        plate,
        speed,
        str(payload.location or '', 120),
        str(payload.radar_source or Config.Radar.provider or 'unknown', 40),
        officerIdentifier,
        officerName,
        now(),
        now()
    })
end

RegisterNetEvent('cbk_mdt:server:radarHit', function(payload)
    local source = source
    if type(payload) ~= 'table' then
        return
    end

    insertRadarLog(source, payload)
end)

CBK_MDT.RegisterAction('list_radar_logs', function(source, payload)
    local allowed, reason = CBK_MDT.RequireOfficer(source)
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