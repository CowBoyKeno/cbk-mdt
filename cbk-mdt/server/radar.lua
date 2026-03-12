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
local radarLiveFeed = {}
local radarLiveFeedMax = 300
local radarLiveFeedNextId = 1
local radarActiveLocks = {}
local radarTokens = {}

local function isRadarDebugEnabled()
    return (Config.Radar or {}).debug == true
end

local function radarTrace(message)
    if isRadarDebugEnabled() then
        print(('[cbk-mdt][radar] %s'):format(tostring(message)))
    end
end

local function isWkRadarSource(sourceName)
    local name = string.lower(tostring(sourceName or ''))
    return name:find('wk_wars2x', 1, true) ~= nil or name == 'wk'
end

local function getRadarTokenTtlSeconds()
    local ttl = tonumber((Config.Radar or {}).tokenTtlSeconds) or 180
    if ttl < 30 then
        ttl = 30
    end
    return ttl
end

local function createRadarToken(source)
    local seed = ('%s:%s:%s:%s'):format(
        tostring(source),
        tostring(GetGameTimer()),
        tostring(os.time()),
        tostring(math.random(100000, 999999))
    )

    local token = seed:gsub('[^%w]', '')
    local expiresAt = os.time() + getRadarTokenTtlSeconds()
    radarTokens[source] = {
        token = token,
        expiresAt = expiresAt
    }

    return token, expiresAt
end

local function isRadarTokenRequired()
    return (Config.Radar or {}).requireToken == true
end

local function validateRadarToken(source, payload)
    if not isRadarTokenRequired() then
        return true
    end

    if type(payload) ~= 'table' then
        radarTrace(('drop: source %s invalid payload for token validation'):format(tostring(source)))
        return false
    end

    local token = str(payload.radar_token or '', 128)
    if token == '' then
        radarTrace(('drop: source %s missing radar token'):format(tostring(source)))
        return false
    end

    local state = radarTokens[source]
    if not state or token ~= tostring(state.token or '') then
        radarTrace(('drop: source %s invalid radar token'):format(tostring(source)))
        return false
    end

    if os.time() > tonumber(state.expiresAt or 0) then
        radarTrace(('drop: source %s expired radar token'):format(tostring(source)))
        return false
    end

    return true
end

local function pushRadarLiveFeed(row)
    if type(row) ~= 'table' then
        return
    end

    local rowId = radarLiveFeedNextId
    radarLiveFeedNextId = radarLiveFeedNextId + 1

    local liveRow = {
        id = rowId,
        plate = row.plate,
        speed = row.speed,
        location = row.location,
        radar_source = row.radar_source,
        antenna = row.antenna,
        officer_identifier = row.officer_identifier,
        officer_name = row.officer_name,
        created_at = row.created_at
    }

    table.insert(radarLiveFeed, 1, liveRow)

    while #radarLiveFeed > radarLiveFeedMax do
        table.remove(radarLiveFeed)
    end

    return liveRow
end

local function getRadarActiveLockKey(source, antenna)
    local antennaKey = string.lower(str(tostring(antenna or ''), 12))
    if antennaKey == '' then
        return nil
    end

    return ('%s:%s'):format(tostring(source), antennaKey)
end

local function removeRadarLiveFeedById(id)
    if not id or id <= 0 then
        return false, nil
    end

    local removed = false
    local removedRow = nil
    for i = #radarLiveFeed, 1, -1 do
        local row = radarLiveFeed[i]
        if tonumber(row.id or 0) == id then
            removedRow = row
            table.remove(radarLiveFeed, i)
            removed = true
            break
        end
    end

    if removed then
        for key, activeId in pairs(radarActiveLocks) do
            if tonumber(activeId or 0) == id then
                radarActiveLocks[key] = nil
            end
        end
    end

    return removed, removedRow
end

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
    if not Framework.IsSourceValid(source) then
        return false
    end

    if (Config.Radar or {}).strictSourceVehicleCheck ~= true then
        return true
    end

    local ped = GetPlayerPed(source)
    if not ped or ped <= 0 then
        return false
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    return vehicle and vehicle > 0
end

local function insertRadarLog(source, payload)
    if not Config.Radar.enabled then
        radarTrace('drop: radar disabled')
        return
    end

    local radarSource = str(payload.radar_source or Config.Radar.provider or 'unknown', 40)
    local wkSource = isWkRadarSource(radarSource)

    if not wkSource then
        radarTrace(('drop: non-wk ALPR source blocked (%s)'):format(tostring(radarSource)))
        return
    end

    if not validateRadarToken(source, payload) then
        return
    end

    if not isRadarSourceValid(source) then
        radarTrace(('drop: source %s failed source validity checks'):format(tostring(source)))
        return
    end

    if not canProcessRadar(source) then
        radarTrace(('drop: source %s hit radar cooldown'):format(tostring(source)))
        return
    end

    local plate = string.upper(str(payload.plate or '', 12))
    local speed = tonumber(payload.speed) or 0
    local maxSpeed = tonumber((Config.Security or {}).radarMaxSpeed) or 260
    speed = math.floor(math.max(0, math.min(speed, maxSpeed)))
    local officerIdentifier = Framework.GetIdentifier(source)
    local officerName = Framework.GetPlayerName(source)

    if plate == '' then
        radarTrace(('drop: source %s empty plate in payload'):format(tostring(source)))
        return
    end

    radarTrace(('live-feed: src=%s plate=%s speed=%s source=%s'):format(
        tostring(source),
        tostring(plate),
        tostring(speed),
        tostring(radarSource)
    ))

    local row = {
        plate = plate,
        speed = speed,
        location = str(payload.location or '', 120),
        radar_source = radarSource,
        antenna = str(payload.antenna or '', 12),
        officer_identifier = officerIdentifier,
        officer_name = officerName,
        created_at = now(),
        updated_at = now()
    }

    local activeKey = getRadarActiveLockKey(source, row.antenna)
    if activeKey and radarActiveLocks[activeKey] then
        removeRadarLiveFeedById(tonumber(radarActiveLocks[activeKey]) or 0)
    end

    local liveRow = pushRadarLiveFeed(row)
    if activeKey and liveRow and liveRow.id then
        radarActiveLocks[activeKey] = liveRow.id
    end
end

RegisterNetEvent('cbk_mdt:server:radarHit', function(payload)
    local source = source
    if type(payload) ~= 'table' then
        return
    end

    insertRadarLog(source, payload)
end)

RegisterNetEvent('wk:onPlateLocked', function(cam, plate, index, radarToken)
    local source = source

    insertRadarLog(source, {
        plate = plate,
        speed = 0,
        location = ('cam:%s idx:%s'):format(str(cam or '', 12), str(tostring(index or ''), 8)),
        radar_source = 'wk_wars2x_plate_lock',
        radar_token = radarToken
    })
end)

RegisterNetEvent('cbk_mdt:server:radarUnlock', function(payload)
    local source = source
    if type(payload) ~= 'table' then
        return
    end

    if not validateRadarToken(source, payload) then
        return
    end

    if not isRadarSourceValid(source) then
        radarTrace(('drop: source %s failed unlock source validity checks'):format(tostring(source)))
        return
    end

    local activeKey = getRadarActiveLockKey(source, payload.antenna)
    if not activeKey then
        return
    end

    local activeId = tonumber(radarActiveLocks[activeKey]) or 0
    if activeId > 0 then
        removeRadarLiveFeedById(activeId)
    end

    radarActiveLocks[activeKey] = nil
end)

RegisterNetEvent('cbk_mdt:server:requestRadarToken', function()
    local source = source
    if not Framework.IsSourceValid(source) then
        return
    end

    local token, expiresAt = createRadarToken(source)
    TriggerClientEvent('cbk_mdt:client:setRadarToken', source, token, expiresAt)
end)

CreateThread(function()
    radarTrace('ALPR live-feed mode active (no DB reads/writes for ALPR list)')
end)

CBK_MDT.RegisterAction('list_radar_logs', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'view')
    if not allowed then
        return false, reason
    end

    payload = payload or {}
    local plate = string.upper(str(payload.plate or '', 12))

    local liveRows = {}
    for _, row in ipairs(radarLiveFeed) do
        if plate == '' or string.find(string.upper(tostring(row.plate or '')), plate, 1, true) then
            liveRows[#liveRows + 1] = row
        end
        if #liveRows >= Config.MaxSearchResults then
            break
        end
    end

    return true, liveRows
end)

CBK_MDT.RegisterAction('dismiss_radar_log', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'view')
    if not allowed then
        return false, reason
    end

    payload = payload or {}
    local id = tonumber(payload.id)
    if not id or id <= 0 then
        return false, 'Invalid ALPR log id'
    end

    local removed, removedRow = removeRadarLiveFeedById(id)

    if not removed then
        return false, 'ALPR log not found'
    end

    local ownIdentifier = Framework.GetIdentifier(source)
    local antenna = string.lower(str(removedRow and removedRow.antenna or '', 12))
    if ownIdentifier ~= ''
        and removedRow
        and tostring(removedRow.officer_identifier or '') == tostring(ownIdentifier)
        and (antenna == 'front' or antenna == 'rear') then
        TriggerClientEvent('cbk_mdt:client:forceRadarUnlockAntenna', source, antenna)
    end

    return true, { success = true }
end)