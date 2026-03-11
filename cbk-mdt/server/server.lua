CBK_MDT = CBK_MDT or {}
CBK_MDT.Actions = CBK_MDT.Actions or {}

local RESOURCE = Config.ResourceName or 'cbk-mdt'
local Security = Config.Security or {}
local Permissions = Config.Permissions or {}

local requestState = {}
local actionState = {}
local inFlightRequests = {}
local abuseState = {}
local activityCooldownState = {}

local function now()
    return os.date('%Y-%m-%d %H:%M:%S')
end

local function deepCopy(tbl)
    if type(tbl) ~= 'table' then
        return tbl
    end

    local out = {}
    for k, v in pairs(tbl) do
        out[k] = deepCopy(v)
    end
    return out
end

local function payloadShapeOk(value, depth, stats)
    depth = depth or 0
    stats = stats or { keys = 0 }

    local maxDepth = tonumber(Security.maxPayloadDepth) or 5
    local maxKeys = tonumber(Security.maxPayloadKeys) or 120
    local maxString = tonumber(Security.maxPayloadStringLength) or 4000

    if type(value) == 'string' then
        return #value <= maxString
    end

    if type(value) ~= 'table' then
        return true
    end

    if depth >= maxDepth then
        return false
    end

    for k, v in pairs(value) do
        stats.keys = stats.keys + 1
        if stats.keys > maxKeys then
            return false
        end

        if type(k) == 'string' and #k > 120 then
            return false
        end

        if not payloadShapeOk(v, depth + 1, stats) then
            return false
        end
    end

    return true
end

local function roleHasPermission(role, permission)
    local matrix = Permissions.matrix or {}
    local rolePerms = matrix[role] or {}
    if rolePerms[permission] == true then
        return true
    end

    return false
end

local function getOfficerRole(source)
    local aceAdmin = Permissions.aceAdmin
    if type(aceAdmin) == 'string' and aceAdmin ~= '' and IsPlayerAceAllowed(source, aceAdmin) then
        return 'mdt_admin', math.huge
    end

    local _, grade = Framework.GetJob(source)
    grade = tonumber(grade) or 0

    local thresholds = Permissions.gradeThresholds or {}
    local role = 'viewer'

    if grade >= (tonumber(thresholds.officer) or 1) then
        role = 'officer'
    end
    if grade >= (tonumber(thresholds.supervisor) or 4) then
        role = 'supervisor'
    end
    if grade >= (tonumber(thresholds.command) or 7) then
        role = 'command'
    end
    if grade >= (tonumber(thresholds.mdt_admin) or 10) then
        role = 'mdt_admin'
    end

    return role, grade
end

local function getActionCooldown(action)
    local map = Security.actionCooldownMs or {}
    local value = tonumber(map[action])
    if value and value > 0 then
        return value
    end
    return 250
end

local function addStrike(source, reason)
    local nowTick = GetGameTimer()
    local record = abuseState[source] or { strikes = 0, blockedUntil = 0 }
    local strikesBeforeBlock = tonumber(Security.abuseStrikesBeforeBlock) or 8
    local blockMs = tonumber(Security.abuseBlockMs) or 30000

    record.strikes = record.strikes + 1
    if record.strikes >= strikesBeforeBlock then
        record.blockedUntil = nowTick + blockMs
        record.strikes = 0
        print(('[%s] Temporary block for src %s after abuse (%s)'):format(RESOURCE, tostring(source), reason or 'unknown'))
    end

    abuseState[source] = record
end

local function checkRequestWindow(source)
    local nowTick = GetGameTimer()
    local windowMs = tonumber(Security.requestWindowMs) or 10000
    local maxPerWindow = tonumber(Security.maxRequestsPerWindow) or 50

    local record = requestState[source] or { windowStart = nowTick, count = 0 }
    if nowTick - record.windowStart > windowMs then
        record.windowStart = nowTick
        record.count = 0
    end

    record.count = record.count + 1
    requestState[source] = record

    if record.count > maxPerWindow then
        addStrike(source, 'request_window')
        return false
    end

    return true
end

local function checkActionCooldown(source, action)
    local nowTick = GetGameTimer()
    local key = ('%s:%s'):format(source, action)
    local lastTick = actionState[key] or 0
    local cooldown = getActionCooldown(action)

    if nowTick - lastTick < cooldown then
        addStrike(source, ('cooldown:%s'):format(action))
        return false
    end

    actionState[key] = nowTick
    return true
end

local function canProcessRequest(source)
    local nowTick = GetGameTimer()
    local blockInfo = abuseState[source]
    if blockInfo and blockInfo.blockedUntil and nowTick < blockInfo.blockedUntil then
        return false, 'Rate limit active'
    end

    if not checkRequestWindow(source) then
        return false, 'Too many requests'
    end

    local current = inFlightRequests[source] or 0
    local maxInFlight = tonumber(Security.maxInFlightRequests) or 3
    if current >= maxInFlight then
        addStrike(source, 'in_flight')
        return false, 'Too many concurrent requests'
    end

    inFlightRequests[source] = current + 1
    return true
end

local function finishRequest(source)
    local current = inFlightRequests[source] or 0
    if current <= 1 then
        inFlightRequests[source] = nil
        return
    end

    inFlightRequests[source] = current - 1
end

local function sanitizeString(value, maxLen)
    if type(value) ~= 'string' then
        return ''
    end
    local trimmed = value:gsub('[%z\1-\8\11\12\14-\31]', '')
    if maxLen and #trimmed > maxLen then
        trimmed = trimmed:sub(1, maxLen)
    end
    return trimmed
end

local function buildRequestContext(source)
    return {
        identifier = Framework.GetIdentifier(source),
        department = Framework.GetDepartment(source),
        onDuty = Framework.IsOnDuty(source)
    }
end

local function isRequestContextFresh(source, ctx)
    if not Framework.IsSourceValid(source) then
        return false, 'Session expired'
    end

    if not Security.requireStableSession then
        return true
    end

    local identifier = Framework.GetIdentifier(source)
    if identifier ~= ctx.identifier then
        return false, 'Session identity changed'
    end

    local department = Framework.GetDepartment(source)
    if department ~= ctx.department then
        return false, 'Department changed'
    end

    if Security.requireOnDuty ~= false and not Framework.IsOnDuty(source) then
        return false, 'Must be on duty'
    end

    return true
end

function CBK_MDT.IsOfficerAllowed(source)
    if not Framework.IsSourceValid(source) then
        return false
    end

    return Framework.IsAllowed(source)
end

function CBK_MDT.GetOfficerRole(source)
    return getOfficerRole(source)
end

function CBK_MDT.HasPermission(source, permission)
    if not CBK_MDT.IsOfficerAllowed(source) then
        return false
    end

    local role = getOfficerRole(source)
    return roleHasPermission(role, permission)
end

function CBK_MDT.EnsureOfficer(source)
    local identifier = Framework.GetIdentifier(source)
    local name = sanitizeString(Framework.GetPlayerName(source), 80)
    local jobName, grade = Framework.GetJob(source)

    MySQL.insert.await([[
        INSERT INTO mdt_officers (identifier, full_name, callsign, rank_label, notes, activity_log, created_at, updated_at)
        VALUES (?, ?, ?, ?, '', JSON_ARRAY(), ?, ?)
        ON DUPLICATE KEY UPDATE
            full_name = VALUES(full_name),
            rank_label = VALUES(rank_label),
            updated_at = VALUES(updated_at)
    ]], {
        identifier,
        name,
        sanitizeString(jobName, 40),
        tostring(grade or 0),
        now(),
        now()
    })

    return identifier, name, jobName, grade
end

function CBK_MDT.AppendOfficerActivity(identifier, action, details)
    local existing = MySQL.single.await('SELECT activity_log FROM mdt_officers WHERE identifier = ?', { identifier })
    local log = {}

    if existing and existing.activity_log then
        local decoded = json.decode(existing.activity_log)
        if type(decoded) == 'table' then
            log = decoded
        end
    end

    log[#log + 1] = {
        action = sanitizeString(action or 'unknown', 80),
        details = sanitizeString(details or '', 400),
        timestamp = now()
    }

    while #log > 200 do
        table.remove(log, 1)
    end

    MySQL.update.await('UPDATE mdt_officers SET activity_log = ?, updated_at = ? WHERE identifier = ?', {
        json.encode(log),
        now(),
        identifier
    })
end

function CBK_MDT.RecordOfficerActivity(source, action, details)
    if not CBK_MDT.IsOfficerAllowed(source) then
        return false
    end

    local cooldownMs = tonumber(Security.activityCooldownMs) or 3000
    local tick = GetGameTimer()
    local last = activityCooldownState[source] or 0
    if tick - last < cooldownMs then
        return false
    end

    local identifier = Framework.GetIdentifier(source)
    activityCooldownState[source] = tick
    CBK_MDT.AppendOfficerActivity(identifier, action, details)
    return true
end

function CBK_MDT.LogAudit(source, entityType, entityKey, action, oldValue, newValue)
    if not CBK_MDT.IsOfficerAllowed(source) then
        return false
    end

    local actorIdentifier = Framework.GetIdentifier(source)
    local actorName = sanitizeString(Framework.GetPlayerName(source), 120)
    local oldJson = type(oldValue) == 'table' and json.encode(oldValue) or json.encode({})
    local newJson = type(newValue) == 'table' and json.encode(newValue) or json.encode({})

    MySQL.insert.await([[
        INSERT INTO mdt_audit_log (
            entity_type, entity_key, action, actor_identifier, actor_name, old_value, new_value, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        sanitizeString(entityType or 'unknown', 40),
        sanitizeString(entityKey or 'unknown', 120),
        sanitizeString(action or 'unknown', 60),
        actorIdentifier,
        actorName,
        oldJson,
        newJson,
        now()
    })

    return true
end

function CBK_MDT.CalculateChargeTotals(charges)
    local chargeMap = CBK_MDT.GetChargesMap()
    local totalFine = 0
    local totalJail = 0
    local normalized = {}

    if type(charges) ~= 'table' then
        return totalFine, totalJail, normalized
    end

    for _, entry in ipairs(charges) do
        if type(entry) == 'table' then
            local code = sanitizeString(entry.code or '', 20)
            local count = math.max(1, math.min(tonumber(entry.count) or 1, 25))
            local template = chargeMap[code]

            if template then
                local fine = (template.fine or 0) * count
                local jail = (template.jail or 0) * count

                totalFine = totalFine + fine
                totalJail = totalJail + jail

                normalized[#normalized + 1] = {
                    code = template.code,
                    label = template.label,
                    category = template.category,
                    fine = template.fine,
                    jail = template.jail,
                    count = count
                }
            end
        end
    end

    return totalFine, totalJail, normalized
end

function CBK_MDT.GetChargesMap()
    local rows = MySQL.query.await('SELECT code, label, category, fine, jail_time FROM mdt_charges WHERE active = 1', {})
    local map = {}

    for _, row in ipairs(rows) do
        map[row.code] = {
            code = row.code,
            label = row.label,
            category = row.category,
            fine = tonumber(row.fine) or 0,
            jail = tonumber(row.jail_time) or 0
        }
    end

    return map
end

function CBK_MDT.RegisterAction(name, handler)
    CBK_MDT.Actions[name] = handler
end

function CBK_MDT.RequireOfficer(source)
    if not CBK_MDT.IsOfficerAllowed(source) then
        return false, 'Not authorized'
    end

    return true
end

function CBK_MDT.RequirePermission(source, permission)
    if not Framework.IsSourceValid(source) then
        return false, 'Session expired'
    end

    if not CBK_MDT.IsOfficerAllowed(source) then
        return false, 'Not authorized'
    end

    if Security.requireOnDuty ~= false and not Framework.IsOnDuty(source) then
        return false, 'Must be on duty'
    end

    if type(permission) ~= 'string' or permission == '' then
        return true
    end

    if not CBK_MDT.HasPermission(source, permission) then
        return false, 'Insufficient MDT permissions'
    end

    return true
end

function CBK_MDT.GetDashboard(source)
    local officerIdentifier = Framework.GetIdentifier(source)
    local officer = MySQL.single.await('SELECT full_name, callsign, rank_label, notes, activity_log, updated_at FROM mdt_officers WHERE identifier = ?', { officerIdentifier })
    local openWarrants = MySQL.single.await('SELECT COUNT(*) AS count FROM mdt_warrants WHERE status = ?', { 'active' })
    local activeBolos = MySQL.single.await('SELECT COUNT(*) AS count FROM mdt_bolos WHERE status = ?', { 'active' })
    local recentReports = MySQL.query.await([[
        SELECT id, report_type, title, officer_name, total_fines, total_jail_time, created_at
        FROM mdt_reports
        ORDER BY id DESC
        LIMIT ?
    ]], { Config.MaxRecentReports })

    local myReports = MySQL.query.await([[
        SELECT id, report_type, title, created_at
        FROM mdt_reports
        WHERE officer_identifier = ?
        ORDER BY id DESC
        LIMIT 10
    ]], { officerIdentifier })

    local activity = {}
    if officer and officer.activity_log then
        activity = json.decode(officer.activity_log) or {}
    end

    return {
        stats = {
            openWarrants = openWarrants and openWarrants.count or 0,
            activeBolos = activeBolos and activeBolos.count or 0,
            reportsToday = tonumber((MySQL.single.await('SELECT COUNT(*) AS count FROM mdt_reports WHERE DATE(created_at) = CURDATE()', {}) or {}).count) or 0
        },
        recentReports = recentReports,
        myReports = myReports,
        officer = {
            identifier = officerIdentifier,
            full_name = officer and officer.full_name or Framework.GetPlayerName(source),
            callsign = officer and officer.callsign or '',
            rank_label = officer and officer.rank_label or '',
            notes = officer and officer.notes or '',
            activity_log = activity,
            updated_at = officer and officer.updated_at or now()
        }
    }
end

local function seedCharges()
    local existing = MySQL.single.await('SELECT COUNT(*) AS count FROM mdt_charges', {})
    if existing and tonumber(existing.count) and tonumber(existing.count) > 0 then
        return
    end

    for _, charge in ipairs(Config.Charges) do
        MySQL.insert.await([[
            INSERT INTO mdt_charges (code, label, category, fine, jail_time, active, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, 1, ?, ?)
        ]], {
            sanitizeString(charge.code, 20),
            sanitizeString(charge.label, 120),
            sanitizeString(charge.category, 80),
            tonumber(charge.fine) or 0,
            tonumber(charge.jail) or 0,
            now(),
            now()
        })
    end
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do
        Wait(250)
    end

    seedCharges()
    print('[cbk-mdt] Server initialized.')
end)

CBK_MDT.RegisterAction('get_dashboard', function(source)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'view')
    if not allowed then
        return false, reason
    end

    CBK_MDT.EnsureOfficer(source)
    return true, CBK_MDT.GetDashboard(source)
end)

CBK_MDT.RegisterAction('list_charges', function(source)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'view')
    if not allowed then
        return false, reason
    end

    local rows = MySQL.query.await('SELECT code, label, category, fine, jail_time FROM mdt_charges WHERE active = 1 ORDER BY category, label', {})
    return true, rows
end)

CBK_MDT.RegisterAction('get_officer_profile', function(source)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'view')
    if not allowed then
        return false, reason
    end

    local identifier = Framework.GetIdentifier(source)
    CBK_MDT.EnsureOfficer(source)

    local profile = MySQL.single.await('SELECT identifier, full_name, callsign, rank_label, notes, activity_log, created_at, updated_at FROM mdt_officers WHERE identifier = ?', { identifier })
    local reports = MySQL.query.await('SELECT id, report_type, title, created_at FROM mdt_reports WHERE officer_identifier = ? ORDER BY id DESC LIMIT 100', { identifier })

    if profile and profile.activity_log then
        profile.activity_log = json.decode(profile.activity_log) or {}
    end

    return true, {
        profile = profile,
        reports = reports
    }
end)

CBK_MDT.RegisterAction('update_officer_notes', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'officer_tools')
    if not allowed then
        return false, reason
    end

    local identifier = Framework.GetIdentifier(source)
    local notes = sanitizeString(payload and payload.notes or '', 2500)
    local before = MySQL.single.await('SELECT identifier, notes FROM mdt_officers WHERE identifier = ?', { identifier })

    MySQL.update.await('UPDATE mdt_officers SET notes = ?, updated_at = ? WHERE identifier = ?', {
        notes,
        now(),
        identifier
    })

    CBK_MDT.RecordOfficerActivity(source, 'officer_notes_updated', 'Officer notes updated in MDT.')
    CBK_MDT.LogAudit(source, 'officer', identifier, 'officer_notes_updated', before or {}, {
        identifier = identifier,
        notes = notes
    })
    return true, { success = true }
end)

CBK_MDT.RegisterAction('panic_alert', function(source)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'view')
    if not allowed then
        return false, reason
    end

    local officerIdentifier, officerName = CBK_MDT.EnsureOfficer(source)
    local ped = GetPlayerPed(source)
    if not ped or ped <= 0 then
        return false, 'Unable to locate officer'
    end

    local coords = GetEntityCoords(ped)
    if not coords then
        return false, 'Unable to resolve position'
    end

    local payload = {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        source = source,
        officerIdentifier = officerIdentifier,
        officerName = officerName,
        durationMs = 60000,
        soundDurationMs = 10000
    }

    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        if target and CBK_MDT.IsOfficerAllowed(target) and Framework.IsOnDuty(target) then
            TriggerClientEvent('cbk_mdt:client:panicAlert', target, payload)
        end
    end

    CBK_MDT.RecordOfficerActivity(source, 'panic_alert', 'Triggered MDT panic alert')
    return true, { success = true }
end)

RegisterNetEvent('cbk_mdt:server:request', function(requestId, action, payload)
    local source = source

    if not Framework.IsSourceValid(source) then
        return
    end

    if type(requestId) ~= 'string' or #requestId > 64 then
        return
    end

    if type(action) ~= 'string' or #action > 64 then
        TriggerClientEvent('cbk_mdt:client:response', source, requestId, false, 'Invalid action')
        return
    end

    if type(payload) ~= 'table' then
        payload = {}
    end

    if not payloadShapeOk(payload) then
        addStrike(source, 'payload_shape')
        TriggerClientEvent('cbk_mdt:client:response', source, requestId, false, 'Payload rejected')
        return
    end

    local ctx = buildRequestContext(source)
    if Security.requireOnDuty ~= false and not ctx.onDuty then
        TriggerClientEvent('cbk_mdt:client:response', source, requestId, false, 'Must be on duty')
        return
    end

    local allowed, reason = canProcessRequest(source)
    if not allowed then
        TriggerClientEvent('cbk_mdt:client:response', source, requestId, false, reason or 'Rate limited')
        return
    end

    if not checkActionCooldown(source, action) then
        finishRequest(source)
        TriggerClientEvent('cbk_mdt:client:response', source, requestId, false, 'Action cooling down')
        return
    end

    local handler = CBK_MDT.Actions[action]
    if not handler then
        finishRequest(source)
        TriggerClientEvent('cbk_mdt:client:response', source, requestId, false, 'Unknown action')
        return
    end

    local ok, success, result = pcall(function()
        return handler(source, deepCopy(payload))
    end)

    finishRequest(source)

    if not ok then
        print(('[cbk-mdt] Action error (%s): %s'):format(action, success))
        TriggerClientEvent('cbk_mdt:client:response', source, requestId, false, 'Server error')
        return
    end

    local fresh, reasonFresh = isRequestContextFresh(source, ctx)
    if not fresh then
        TriggerClientEvent('cbk_mdt:client:response', source, requestId, false, reasonFresh or 'Session changed')
        return
    end

    TriggerClientEvent('cbk_mdt:client:response', source, requestId, success, result)
end)

AddEventHandler('playerDropped', function()
    local source = source
    requestState[source] = nil
    abuseState[source] = nil
    inFlightRequests[source] = nil
    activityCooldownState[source] = nil
end)
