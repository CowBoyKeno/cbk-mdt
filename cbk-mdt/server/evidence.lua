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

local function normalizeMetadata(value, evidenceType, depth, stats)
    local limits = Config.Evidence or {}
    local maxDepth = tonumber(limits.maxMetadataDepth) or 3
    local maxKeys = tonumber(limits.maxMetadataKeys) or 30
    local maxString = tonumber(limits.maxMetadataStringLength) or 200
    local allowedMap = limits.allowedMetadata or {}
    local whitelist = allowedMap[evidenceType] or allowedMap.general or {}

    if type(value) ~= 'table' then
        return {}
    end

    depth = depth or 0
    stats = stats or { keys = 0 }
    if depth >= maxDepth then
        return {}
    end

    local out = {}
    for key, item in pairs(value) do
        if type(key) == 'string' and whitelist[key] == true then
            stats.keys = stats.keys + 1
            if stats.keys <= maxKeys then
                if type(item) == 'string' then
                    out[key] = str(item, maxString)
                elseif type(item) == 'number' then
                    out[key] = tonumber(item) or 0
                elseif type(item) == 'boolean' then
                    out[key] = item
                elseif type(item) == 'table' then
                    out[key] = normalizeMetadata(item, evidenceType, depth + 1, stats)
                end
            end
        end
    end

    return out
end

CBK_MDT.RegisterAction('add_evidence', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'evidence_writer')
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
        metadata = {}
    end

    metadata = normalizeMetadata(metadata or {}, evidenceType)

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
        json.encode(metadata),
        officerIdentifier,
        officerName,
        now(),
        now()
    })

    CBK_MDT.RecordOfficerActivity(source, 'evidence_added', ('Added evidence #%s to report #%s'):format(tostring(evidenceId), tostring(reportId)))
    CBK_MDT.LogAudit(source, 'evidence', tostring(evidenceId), 'evidence_added', {}, {
        id = evidenceId,
        report_id = reportId,
        evidence_type = evidenceType,
        image_url = imageUrl
    })
    return true, { id = evidenceId }
end)

CBK_MDT.RegisterAction('list_evidence', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'view')
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