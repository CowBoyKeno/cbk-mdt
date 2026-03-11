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

local function cleanTable(value)
    if type(value) == 'table' then
        return value
    end
    return {}
end

local function normalizeCitizenRefs(list)
    local out = {}
    for _, entry in ipairs(cleanTable(list)) do
        if type(entry) == 'table' then
            local identifier = str(entry.identifier or '', 80)
            if identifier ~= '' then
                out[#out + 1] = {
                    identifier = identifier,
                    name = str(entry.name or entry.full_name or '', Config.Report.maxCitizenNameLength or 120)
                }
            end
        end
    end
    return out
end

local function normalizeVehicleRefs(list)
    local out = {}
    for _, entry in ipairs(cleanTable(list)) do
        if type(entry) == 'table' then
            local plate = string.upper(str(entry.plate or '', 12))
            if plate ~= '' then
                out[#out + 1] = {
                    plate = plate,
                    model = str(entry.model or entry.model_name or '', Config.Report.maxVehicleModelLength or 80)
                }
            end
        end
    end
    return out
end

local function normalizeEvidenceRefs(list)
    local out = {}
    for _, entry in ipairs(cleanTable(list)) do
        local id = type(entry) == 'table' and tonumber(entry.id) or tonumber(entry)
        if id and id > 0 then
            out[#out + 1] = { id = id }
        end
    end
    return out
end

CBK_MDT.RegisterAction('create_report', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'report_writer')
    if not allowed then
        return false, reason
    end

    payload = payload or {}
    local reportType = str(payload.report_type or 'incident', 20)
    if reportType ~= 'incident' and reportType ~= 'arrest' then
        reportType = 'incident'
    end

    local title = str(payload.title or '', Config.Report.maxTitleLength)
    local summary = str(payload.summary or '', Config.Report.maxSummaryLength)
    local narrative = str(payload.narrative or '', Config.Report.maxNarrativeLength)
    local involvedCitizens = normalizeCitizenRefs(payload.involved_citizens)
    local involvedVehicles = normalizeVehicleRefs(payload.involved_vehicles)
    local chargesInput = cleanTable(payload.charges)
    local evidenceRefs = normalizeEvidenceRefs(payload.evidence_refs)

    if title == '' then
        return false, 'Report title is required'
    end

    local totalFine, totalJail, normalizedCharges = CBK_MDT.CalculateChargeTotals(chargesInput)

    while #involvedCitizens > Config.Report.maxPeoplePerReport do
        table.remove(involvedCitizens)
    end

    while #involvedVehicles > Config.Report.maxVehiclesPerReport do
        table.remove(involvedVehicles)
    end

    while #normalizedCharges > Config.Report.maxChargesPerReport do
        table.remove(normalizedCharges)
    end

    while #evidenceRefs > Config.Report.maxEvidencePerReport do
        table.remove(evidenceRefs)
    end

    local officerIdentifier, officerName = CBK_MDT.EnsureOfficer(source)

    local reportId = MySQL.insert.await([[
        INSERT INTO mdt_reports (
            report_type, title, summary, narrative, involved_citizens, involved_vehicles,
            charges, total_fines, total_jail_time, evidence_refs, officer_identifier, officer_name,
            created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        reportType,
        title,
        summary,
        narrative,
        json.encode(involvedCitizens),
        json.encode(involvedVehicles),
        json.encode(normalizedCharges),
        totalFine,
        totalJail,
        json.encode(evidenceRefs),
        officerIdentifier,
        officerName,
        now(),
        now()
    })

    CBK_MDT.RecordOfficerActivity(source, 'report_created', ('Created %s report #%s'):format(reportType, tostring(reportId)))
    CBK_MDT.LogAudit(source, 'report', tostring(reportId), 'report_created', {}, {
        id = reportId,
        report_type = reportType,
        title = title,
        total_fines = totalFine,
        total_jail_time = totalJail
    })

    return true, {
        id = reportId,
        total_fines = totalFine,
        total_jail_time = totalJail,
        charges = normalizedCharges
    }
end)

CBK_MDT.RegisterAction('search_reports', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'view')
    if not allowed then
        return false, reason
    end

    payload = payload or {}
    local query = str(payload.query or '', 100)
    local reportType = str(payload.report_type or '', 20)

    local sql = [[
        SELECT id, report_type, title, summary, total_fines, total_jail_time, officer_name, created_at
        FROM mdt_reports
        WHERE 1 = 1
    ]]
    local params = {}

    if query ~= '' then
        sql = sql .. ' AND (title LIKE ? OR summary LIKE ? OR officer_name LIKE ?)'
        local like = ('%%%s%%'):format(query)
        params[#params + 1] = like
        params[#params + 1] = like
        params[#params + 1] = like
    end

    if reportType == 'incident' or reportType == 'arrest' then
        sql = sql .. ' AND report_type = ?'
        params[#params + 1] = reportType
    end

    sql = sql .. ' ORDER BY id DESC LIMIT ?'
    params[#params + 1] = Config.MaxSearchResults

    local rows = MySQL.query.await(sql, params)
    return true, rows
end)

CBK_MDT.RegisterAction('get_report', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'view')
    if not allowed then
        return false, reason
    end

    local id = tonumber(payload and payload.id)
    if not id or id < 1 then
        return false, 'Invalid report id'
    end

    local report = MySQL.single.await('SELECT * FROM mdt_reports WHERE id = ?', { id })
    if not report then
        return false, 'Report not found'
    end

    report.involved_citizens = report.involved_citizens and (json.decode(report.involved_citizens) or {}) or {}
    report.involved_vehicles = report.involved_vehicles and (json.decode(report.involved_vehicles) or {}) or {}
    report.charges = report.charges and (json.decode(report.charges) or {}) or {}
    report.evidence_refs = report.evidence_refs and (json.decode(report.evidence_refs) or {}) or {}

    return true, report
end)