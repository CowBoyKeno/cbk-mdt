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
local radarTokenFallbackTrace = {}

local function isRadarDebugEnabled()
    return (Config.Radar or {}).debug == true
end

local function setRadarDebugEnabled(state)
    Config.Radar = Config.Radar or {}
    Config.Radar.debug = state == true
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
    local radarSource = str(payload.radar_source or '', 40)
    local wkSource = isWkRadarSource(radarSource)

    -- Keep token hardening but do not black-hole wk ALPR if token sync misses.
    -- strictSourceVehicleCheck still applies and wk source is enforced elsewhere.
    local function allowWkFallback(reason)
        if wkSource then
            local nowTick = GetGameTimer()
            local lastTick = tonumber(radarTokenFallbackTrace[source] or 0)
            if nowTick - lastTick >= 5000 then
                radarTokenFallbackTrace[source] = nowTick
                radarTrace(('token fallback: source %s accepted (%s)'):format(tostring(source), tostring(reason)))
            end
            return true
        end
        return false
    end

    if token == '' then
        if wkSource then
            return allowWkFallback('missing')
        end
        radarTrace(('drop: source %s missing radar token'):format(tostring(source)))
        return allowWkFallback('missing')
    end

    local state = radarTokens[source]
    if not state or token ~= tostring(state.token or '') then
        if wkSource then
            return allowWkFallback('invalid')
        end
        radarTrace(('drop: source %s invalid radar token'):format(tostring(source)))
        return allowWkFallback('invalid')
    end

    if os.time() > tonumber(state.expiresAt or 0) then
        if wkSource then
            return allowWkFallback('expired')
        end
        radarTrace(('drop: source %s expired radar token'):format(tostring(source)))
        return allowWkFallback('expired')
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

local function canProcessRadar(source, payload)
    local current = GetGameTimer()
    local antenna = ''
    if type(payload) == 'table' then
        antenna = string.lower(str(payload.antenna or '', 12))
    end

    local key = tostring(source)
    if antenna ~= '' then
        key = ('%s:%s'):format(key, antenna)
    end

    local last = radarRateLimit[key] or 0
    local cooldown = tonumber((Config.Security or {}).radarCooldownMs) or 1000
    if current - last < cooldown then
        return false
    end
    radarRateLimit[key] = current
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
    if vehicle and vehicle > 0 then
        return true
    end

    -- Fallback to last vehicle to avoid dropping legitimate lock events during
    -- brief ped/seat state transitions.
    local lastVehicle = GetVehiclePedIsIn(ped, true)
    return lastVehicle and lastVehicle > 0
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

    if not canProcessRadar(source, payload) then
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
    local antenna = string.lower(str(cam or '', 12))

    insertRadarLog(source, {
        plate = plate,
        speed = 0,
        location = ('cam:%s idx:%s'):format(str(cam or '', 12), str(tostring(index or ''), 8)),
        radar_source = 'wk_wars2x_plate_lock',
        antenna = antenna,
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

RegisterCommand('mdtdebug', function(source, args)
    local ace = tostring((Config.Permissions or {}).aceAdmin or 'cbk.mdt.admin')
    local isConsole = source == 0

    if not isConsole and (ace == '' or not IsPlayerAceAllowed(source, ace)) then
        TriggerClientEvent('chat:addMessage', source, {
            color = { 255, 80, 80 },
            args = { '[MDT]', 'You do not have permission to use /mdtdebug.' }
        })
        return
    end

    local mode = string.lower(tostring((args and args[1]) or 'toggle'))
    local nextState = isRadarDebugEnabled()

    if mode == 'on' then
        nextState = true
    elseif mode == 'off' then
        nextState = false
    elseif mode == 'status' then
        nextState = isRadarDebugEnabled()
    else
        nextState = not isRadarDebugEnabled()
    end

    if mode ~= 'status' then
        setRadarDebugEnabled(nextState)
    end

    local statusText = isRadarDebugEnabled() and 'ON' or 'OFF'
    local usage = '/mdtdebug [on|off|status|toggle]'
    local message = ('Radar debug is %s. %s'):format(statusText, usage)

    print(('[cbk-mdt] %s'):format(message))

    if not isConsole then
        TriggerClientEvent('chat:addMessage', source, {
            color = { 80, 180, 255 },
            args = { '[MDT]', message }
        })
    end
end, true)

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