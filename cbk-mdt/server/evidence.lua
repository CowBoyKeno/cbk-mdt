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

CBK_MDT.RegisterAction('add_evidence', function(source, payload)
    local allowed, reason = CBK_MDT.RequireOfficer(source)
    if not allowed then
        return false, reason
    end

    payload = payload or {}
    local reportId = tonumber(payload.report_id)
    local evidenceType = str(payload.evidence_type or 'general', 40)
    local description = str(payload.description or '', 2000)
    local imageUrl = str(payload.image_url or '', 350)
    local metadata = payload.metadata

    if not reportId or reportId < 1 then
        return false, 'Invalid report id'
    end

    if metadata ~= nil and type(metadata) ~= 'table' then
        metadata = nil
    end

    local reportExists = MySQL.single.await('SELECT id FROM mdt_reports WHERE id = ?', { reportId })
    if not reportExists then
        return false, 'Report does not exist'
    end

    local officerIdentifier, officerName = CBK_MDT.EnsureOfficer(source)

    local evidenceId = MySQL.insert.await([[
        INSERT INTO mdt_evidence (
            report_id, evidence_type, description, image_url, metadata,
            added_by_identifier, added_by_name, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        reportId,
        evidenceType,
        description,
        imageUrl,
        metadata and json.encode(metadata) or json.encode({}),
        officerIdentifier,
        officerName,
        now(),
        now()
    })

    CBK_MDT.AppendOfficerActivity(officerIdentifier, 'evidence_added', ('Added evidence #%s to report #%s'):format(tostring(evidenceId), tostring(reportId)))
    return true, { id = evidenceId }
end)

CBK_MDT.RegisterAction('list_evidence', function(source, payload)
    local allowed, reason = CBK_MDT.RequireOfficer(source)
    if not allowed then
        return false, reason
    end

    payload = payload or {}
    local reportId = tonumber(payload.report_id)

    local sql = 'SELECT * FROM mdt_evidence'
    local params = {}

    if reportId and reportId > 0 then
        sql = sql .. ' WHERE report_id = ?'
        params[#params + 1] = reportId
    end

    sql = sql .. ' ORDER BY id DESC LIMIT ?'
    params[#params + 1] = Config.MaxSearchResults

    local rows = MySQL.query.await(sql, params)
    for _, row in ipairs(rows) do
        row.metadata = row.metadata and (json.decode(row.metadata) or {}) or {}
    end

    return true, rows
end)