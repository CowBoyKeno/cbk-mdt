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

CBK_MDT.RegisterAction('create_warrant', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'warrant_writer')
    if not allowed then
        return false, reason
    end

    payload = payload or {}
    local citizenIdentifier = str(payload.citizen_identifier or '', 80)
    local title = str(payload.title or '', 120)
    local reasonText = str(payload.reason or '', 2000)
    local reportId = tonumber(payload.report_id) or 0
    local expiresAt = payload.expires_at

    if citizenIdentifier == '' or title == '' then
        return false, 'Citizen identifier and title are required'
    end

    if type(expiresAt) ~= 'string' or expiresAt == '' then
        expiresAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + (Config.Warrant.defaultExpiryHours * 3600))
    end

    local officerIdentifier, officerName = CBK_MDT.EnsureOfficer(source)

    local insertId = MySQL.insert.await([[
        INSERT INTO mdt_warrants (
            citizen_identifier, title, reason, report_id, status,
            issued_by_identifier, issued_by_name, issued_at, expires_at, created_at, updated_at
        ) VALUES (?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?)
    ]], {
        citizenIdentifier,
        title,
        reasonText,
        reportId > 0 and reportId or nil,
        officerIdentifier,
        officerName,
        now(),
        expiresAt,
        now(),
        now()
    })

    CBK_MDT.RecordOfficerActivity(source, 'warrant_created', ('Created warrant #%s for %s'):format(tostring(insertId), citizenIdentifier))
    CBK_MDT.LogAudit(source, 'warrant', tostring(insertId), 'warrant_created', {}, {
        id = insertId,
        citizen_identifier = citizenIdentifier,
        status = 'active',
        title = title
    })
    return true, { id = insertId }
end)

CBK_MDT.RegisterAction('list_warrants', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'view')
    if not allowed then
        return false, reason
    end

    local status = str(payload and payload.status or '', 20)
    local sql = [[
        SELECT w.*, c.full_name AS citizen_name
        FROM mdt_warrants w
        LEFT JOIN mdt_citizens c ON c.identifier = w.citizen_identifier
    ]]
    local params = {}

    if status == 'active' or status == 'served' or status == 'recalled' or status == 'expired' then
        sql = sql .. ' WHERE w.status = ?'
        params[#params + 1] = status
    end

    sql = sql .. ' ORDER BY w.id DESC LIMIT ?'
    params[#params + 1] = Config.MaxSearchResults

    return true, MySQL.query.await(sql, params)
end)

CBK_MDT.RegisterAction('update_warrant_status', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'warrant_writer')
    if not allowed then
        return false, reason
    end

    local id = tonumber(payload and payload.id)
    local status = str(payload and payload.status or '', 20)

    if not id or id < 1 then
        return false, 'Invalid warrant id'
    end

    if status ~= 'active' and status ~= 'served' and status ~= 'recalled' and status ~= 'expired' then
        return false, 'Invalid status'
    end

    local warrant = MySQL.single.await('SELECT id, status, issued_by_identifier FROM mdt_warrants WHERE id = ?', { id })
    if not warrant then
        return false, 'Warrant not found'
    end

    local officerIdentifier = Framework.GetIdentifier(source)
    local isSupervisor = CBK_MDT.HasPermission(source, 'warrant_supervisor')
    if warrant.issued_by_identifier ~= officerIdentifier and not isSupervisor then
        return false, 'Only issuing officer or supervisor can change this warrant'
    end

    local updated = MySQL.update.await('UPDATE mdt_warrants SET status = ?, updated_at = ? WHERE id = ?', {
        status,
        now(),
        id
    })

    if updated < 1 then
        return false, 'Warrant not found'
    end

    CBK_MDT.RecordOfficerActivity(source, 'warrant_status_updated', ('Warrant #%s status set to %s'):format(tostring(id), status))
    CBK_MDT.LogAudit(source, 'warrant', tostring(id), 'warrant_status_updated', {
        status = warrant.status
    }, {
        status = status
    })
    return true, { success = true }
end)
