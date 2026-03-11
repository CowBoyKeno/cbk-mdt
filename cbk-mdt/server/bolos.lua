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

CBK_MDT.RegisterAction('create_bolo', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'bolo_writer')
    if not allowed then
        return false, reason
    end

    payload = payload or {}
    local boloType = str(payload.bolo_type or 'person', 20)
    local title = str(payload.title or '', 120)
    local description = str(payload.description or '', 3000)
    local targetIdentifier = str(payload.target_identifier or '', 80)
    local targetPlate = string.upper(str(payload.target_plate or '', 12))

    if boloType ~= 'person' and boloType ~= 'vehicle' and boloType ~= 'general' then
        boloType = 'general'
    end

    if title == '' then
        return false, 'Title is required'
    end

    local officerIdentifier, officerName = CBK_MDT.EnsureOfficer(source)

    local boloId = MySQL.insert.await([[
        INSERT INTO mdt_bolos (
            bolo_type, title, description, target_identifier, target_plate, status,
            created_by_identifier, created_by_name, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, 'active', ?, ?, ?, ?)
    ]], {
        boloType,
        title,
        description,
        targetIdentifier,
        targetPlate,
        officerIdentifier,
        officerName,
        now(),
        now()
    })

    CBK_MDT.RecordOfficerActivity(source, 'bolo_created', ('Created BOLO #%s'):format(tostring(boloId)))
    CBK_MDT.LogAudit(source, 'bolo', tostring(boloId), 'bolo_created', {}, {
        id = boloId,
        status = 'active',
        title = title,
        bolo_type = boloType
    })
    return true, { id = boloId }
end)

CBK_MDT.RegisterAction('list_bolos', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'view')
    if not allowed then
        return false, reason
    end

    local status = str(payload and payload.status or '', 20)
    local sql = 'SELECT * FROM mdt_bolos'
    local params = {}

    if status == 'active' or status == 'closed' or status == 'archived' then
        sql = sql .. ' WHERE status = ?'
        params[#params + 1] = status
    end

    sql = sql .. ' ORDER BY id DESC LIMIT ?'
    params[#params + 1] = Config.MaxSearchResults

    return true, MySQL.query.await(sql, params)
end)

CBK_MDT.RegisterAction('update_bolo_status', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'bolo_writer')
    if not allowed then
        return false, reason
    end

    local id = tonumber(payload and payload.id)
    local status = str(payload and payload.status or '', 20)

    if not id or id < 1 then
        return false, 'Invalid BOLO id'
    end

    if status ~= 'active' and status ~= 'closed' and status ~= 'archived' then
        return false, 'Invalid status'
    end

    local bolo = MySQL.single.await('SELECT id, status, created_by_identifier FROM mdt_bolos WHERE id = ?', { id })
    if not bolo then
        return false, 'BOLO not found'
    end

    local officerIdentifier = Framework.GetIdentifier(source)
    local isSupervisor = CBK_MDT.HasPermission(source, 'bolo_supervisor')
    if bolo.created_by_identifier ~= officerIdentifier and not isSupervisor then
        return false, 'Only creating officer or supervisor can change this BOLO'
    end

    local updated = MySQL.update.await('UPDATE mdt_bolos SET status = ?, updated_at = ? WHERE id = ?', {
        status,
        now(),
        id
    })

    if updated < 1 then
        return false, 'BOLO not found'
    end

    CBK_MDT.RecordOfficerActivity(source, 'bolo_status_updated', ('BOLO #%s status set to %s'):format(tostring(id), status))
    CBK_MDT.LogAudit(source, 'bolo', tostring(id), 'bolo_status_updated', {
        status = bolo.status
    }, {
        status = status
    })
    return true, { success = true }
end)