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

CBK_MDT.RegisterAction('search_vehicles', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'view')
    if not allowed then
        return false, reason
    end

    local query = str(payload and payload.query or '', 40)
    if query == '' then
        return true, {}
    end

    local like = ('%%%s%%'):format(query)
    local rows = MySQL.query.await([[
        SELECT v.plate, v.owner_identifier, c.full_name AS owner_name, v.model_name, v.vehicle_class, v.color,
               v.stolen, v.flags, v.notes, v.updated_at
        FROM mdt_vehicles v
        LEFT JOIN mdt_citizens c ON c.identifier = v.owner_identifier
        WHERE v.plate LIKE ? OR v.owner_identifier LIKE ? OR c.full_name LIKE ?
        ORDER BY v.updated_at DESC
        LIMIT ?
    ]], { like, like, like, Config.MaxSearchResults })

    for _, row in ipairs(rows) do
        row.flags = row.flags and (json.decode(row.flags) or {}) or {}
    end

    return true, rows
end)

CBK_MDT.RegisterAction('upsert_vehicle', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'vehicle_writer')
    if not allowed then
        return false, reason
    end

    local plate = string.upper(str(payload and payload.plate or '', 12))
    local ownerIdentifier = str(payload and payload.owner_identifier or '', 80)
    local modelName = str(payload and payload.model_name or '', 80)
    local vehicleClass = str(payload and payload.vehicle_class or '', 40)
    local color = str(payload and payload.color or '', 30)

    if plate == '' then
        return false, 'Plate is required'
    end

    local before = MySQL.single.await('SELECT plate, owner_identifier, model_name, vehicle_class, color FROM mdt_vehicles WHERE plate = ?', { plate })

    MySQL.insert.await([[
        INSERT INTO mdt_vehicles (plate, owner_identifier, model_name, vehicle_class, color, stolen, flags, notes, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, 0, JSON_ARRAY(), '', ?, ?)
        ON DUPLICATE KEY UPDATE
            owner_identifier = VALUES(owner_identifier),
            model_name = VALUES(model_name),
            vehicle_class = VALUES(vehicle_class),
            color = VALUES(color),
            updated_at = VALUES(updated_at)
    ]], {
        plate,
        ownerIdentifier,
        modelName,
        vehicleClass,
        color,
        now(),
        now()
    })

    CBK_MDT.RecordOfficerActivity(source, 'vehicle_upserted', ('Upserted vehicle %s'):format(plate))
    CBK_MDT.LogAudit(source, 'vehicle', plate, 'vehicle_upserted', before or {}, {
        plate = plate,
        owner_identifier = ownerIdentifier,
        model_name = modelName,
        vehicle_class = vehicleClass,
        color = color
    })
    return true, { success = true }
end)

CBK_MDT.RegisterAction('set_vehicle_stolen', function(source, payload)
    local allowed, reason = CBK_MDT.RequirePermission(source, 'vehicle_supervisor')
    if not allowed then
        return false, reason
    end

    local plate = string.upper(str(payload and payload.plate or '', 12))
    local stolen = payload and payload.stolen == true
    local notes = str(payload and payload.notes or '', 1500)

    if plate == '' then
        return false, 'Invalid plate'
    end

    local before = MySQL.single.await('SELECT plate, stolen, notes FROM mdt_vehicles WHERE plate = ?', { plate })

    local updated = MySQL.update.await('UPDATE mdt_vehicles SET stolen = ?, notes = ?, updated_at = ? WHERE plate = ?', {
        stolen and 1 or 0,
        notes,
        now(),
        plate
    })

    if updated < 1 then
        return false, 'Vehicle not found'
    end

    CBK_MDT.RecordOfficerActivity(source, 'vehicle_stolen_flag', ('Vehicle %s stolen flag set: %s'):format(plate, tostring(stolen)))
    CBK_MDT.LogAudit(source, 'vehicle', plate, 'vehicle_stolen_flag', before or {}, {
        plate = plate,
        stolen = stolen and 1 or 0,
        notes = notes
    })
    return true, { success = true }
end)