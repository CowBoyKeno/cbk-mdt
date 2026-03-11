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

CBK_MDT.RegisterAction('search_citizens', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'view')
    if not allowed then
        return false, reason
    end

    local query = str(payload and payload.query or '', 80)
    if #query < 1 then
        return true, {}
    end

    local like = ('%%%s%%'):format(query)
    local rows = MySQL.query.await([[
        SELECT identifier, full_name, date_of_birth, phone_number, licenses_status, flags, updated_at
        FROM mdt_citizens
        WHERE identifier LIKE ? OR full_name LIKE ? OR phone_number LIKE ?
        ORDER BY updated_at DESC
        LIMIT ?
    ]], { like, like, like, Config.MaxSearchResults })

    for _, row in ipairs(rows) do
        row.flags = row.flags and (json.decode(row.flags) or {}) or {}
    end

    return true, rows
end)

CBK_MDT.RegisterAction('get_citizen_profile', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'view')
    if not allowed then
        return false, reason
    end

    local identifier = str(payload and payload.identifier or '', 80)
    if identifier == '' then
        return false, 'Invalid identifier'
    end

    local citizen = MySQL.single.await([[
        SELECT id, identifier, full_name, date_of_birth, phone_number, address, licenses_status, notes, flags, created_at, updated_at
        FROM mdt_citizens
        WHERE identifier = ?
    ]], { identifier })

    if not citizen then
        return false, 'Citizen not found'
    end

    citizen.flags = citizen.flags and (json.decode(citizen.flags) or {}) or {}

    local criminalHistory = MySQL.query.await([[
        SELECT id, report_type, title, charges, total_fines, total_jail_time, officer_name, created_at
        FROM mdt_reports
        WHERE JSON_SEARCH(involved_citizens, 'one', ?, NULL, '$[*].identifier') IS NOT NULL
        ORDER BY id DESC
        LIMIT 100
    ]], { identifier })

    for _, report in ipairs(criminalHistory) do
        report.charges = report.charges and (json.decode(report.charges) or {}) or {}
    end

    return true, {
        citizen = citizen,
        criminalHistory = criminalHistory
    }
end)

CBK_MDT.RegisterAction('save_citizen_notes', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'citizen_writer')
    if not allowed then
        return false, reason
    end

    local citizenIdentifier = str(payload and payload.identifier or '', 80)
    local notes = str(payload and payload.notes or '', 6000)
    local flags = payload and payload.flags or {}

    if citizenIdentifier == '' then
        return false, 'Invalid citizen identifier'
    end

    if type(flags) ~= 'table' then
        flags = {}
    end

    local before = MySQL.single.await('SELECT identifier, notes, flags FROM mdt_citizens WHERE identifier = ?', { citizenIdentifier })

    local result = MySQL.update.await('UPDATE mdt_citizens SET notes = ?, flags = ?, updated_at = ? WHERE identifier = ?', {
        notes,
        json.encode(flags),
        now(),
        citizenIdentifier
    })

    if result < 1 then
        return false, 'Citizen not found'
    end

    CBK_MDT.RecordOfficerActivity(source, 'citizen_notes_updated', ('Updated notes for citizen %s'):format(citizenIdentifier))
    CBK_MDT.LogAudit(source, 'citizen', citizenIdentifier, 'citizen_notes_updated', before or {}, {
        identifier = citizenIdentifier,
        notes = notes,
        flags = flags
    })

    return true, { success = true }
end)

CBK_MDT.RegisterAction('create_or_update_citizen', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'citizen_supervisor')
    if not allowed then
        return false, reason
    end

    local identifier = str(payload and payload.identifier or '', 80)
    local fullName = str(payload and payload.full_name or '', 120)
    local dob = str(payload and payload.date_of_birth or '', 20)
    local phone = str(payload and payload.phone_number or '', 30)
    local address = str(payload and payload.address or '', 180)
    local licensesStatus = str(payload and payload.licenses_status or 'valid', 20)

    if identifier == '' or fullName == '' then
        return false, 'Identifier and full name are required'
    end

    local before = MySQL.single.await([[
        SELECT identifier, full_name, date_of_birth, phone_number, address, licenses_status
        FROM mdt_citizens
        WHERE identifier = ?
    ]], { identifier })

    MySQL.insert.await([[
        INSERT INTO mdt_citizens (identifier, full_name, date_of_birth, phone_number, address, licenses_status, notes, flags, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, '', JSON_ARRAY(), ?, ?)
        ON DUPLICATE KEY UPDATE
            full_name = VALUES(full_name),
            date_of_birth = VALUES(date_of_birth),
            phone_number = VALUES(phone_number),
            address = VALUES(address),
            licenses_status = VALUES(licenses_status),
            updated_at = VALUES(updated_at)
    ]], {
        identifier,
        fullName,
        dob,
        phone,
        address,
        licensesStatus,
        now(),
        now()
    })

    CBK_MDT.RecordOfficerActivity(source, 'citizen_profile_upserted', ('Upserted citizen %s'):format(identifier))
    CBK_MDT.LogAudit(source, 'citizen', identifier, 'citizen_profile_upserted', before or {}, {
        identifier = identifier,
        full_name = fullName,
        date_of_birth = dob,
        phone_number = phone,
        address = address,
        licenses_status = licensesStatus
    })
    return true, { success = true }
end)