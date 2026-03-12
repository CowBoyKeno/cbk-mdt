local function submitRadarHit(data)
    if not Config.Radar.enabled then
        return
    end

    if type(data) ~= 'table' then
        return
    end

    local payload = {
        plate = tostring(data.plate or ''),
        speed = tonumber(data.speed) or 0,
        location = tostring(data.location or ''),
        radar_source = tostring(data.radar_source or Config.Radar.provider or 'unknown')
    }

    if payload.plate == '' then
        return
    end

    TriggerServerEvent('cbk_mdt:server:radarHit', payload)
end

