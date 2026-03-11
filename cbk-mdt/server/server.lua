CBK_MDT = CBK_MDT or {}
CBK_MDT.Actions = CBK_MDT.Actions or {}

local RESOURCE = Config.ResourceName or 'cbk-mdt'

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

function CBK_MDT.IsOfficerAllowed(source)
    return Framework.IsAllowed(source)
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
    local allowed, reason = CBK_MDT.RequireOfficer(source)
    if not allowed then
        return false, reason
    end

    CBK_MDT.EnsureOfficer(source)
    return true, CBK_MDT.GetDashboard(source)
end)

CBK_MDT.RegisterAction('list_charges', function(source)
    local allowed, reason = CBK_MDT.RequireOfficer(source)
    if not allowed then
        return false, reason
    end

    local rows = MySQL.query.await('SELECT code, label, category, fine, jail_time FROM mdt_charges WHERE active = 1 ORDER BY category, label', {})
    return true, rows
end)

CBK_MDT.RegisterAction('get_officer_profile', function(source)
    local allowed, reason = CBK_MDT.RequireOfficer(source)
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
    local allowed, reason = CBK_MDT.RequireOfficer(source)
    if not allowed then
        return false, reason
    end

    local identifier = Framework.GetIdentifier(source)
    local notes = sanitizeString(payload and payload.notes or '', 2500)

    MySQL.update.await('UPDATE mdt_officers SET notes = ?, updated_at = ? WHERE identifier = ?', {
        notes,
        now(),
        identifier
    })

    CBK_MDT.AppendOfficerActivity(identifier, 'officer_notes_updated', 'Officer notes updated in MDT.')
    return true, { success = true }
end)

RegisterNetEvent('cbk_mdt:server:request', function(requestId, action, payload)
    local source = source

    if type(requestId) ~= 'string' or #requestId > 64 then
        return
    end

    if type(action) ~= 'string' or #action > 64 then
        TriggerClientEvent('cbk_mdt:client:response', source, requestId, false, 'Invalid action')
        return
    end

    local handler = CBK_MDT.Actions[action]
    if not handler then
        TriggerClientEvent('cbk_mdt:client:response', source, requestId, false, 'Unknown action')
        return
    end

    local ok, success, result = pcall(function()
        return handler(source, deepCopy(payload or {}))
    end)

    if not ok then
        print(('[cbk-mdt] Action error (%s): %s'):format(action, success))
        TriggerClientEvent('cbk_mdt:client:response', source, requestId, false, 'Server error')
        return
    end

    TriggerClientEvent('cbk_mdt:client:response', source, requestId, success, result)
end)

RegisterNetEvent('cbk_mdt:server:appendActivity', function(action, details)
    local source = source
    if not CBK_MDT.IsOfficerAllowed(source) then
        return
    end

    local identifier = Framework.GetIdentifier(source)
    CBK_MDT.AppendOfficerActivity(identifier, action, details)
end)
