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

RegisterNetEvent('wk_wars2x:radarHit', function(plate, speed, location)
    submitRadarHit({
        plate = plate,
        speed = speed,
        location = location,
        radar_source = 'wk_wars2x'
    })
end)

RegisterNetEvent('wk:radar:hit', function(data)
    if type(data) ~= 'table' then
        return
    end
    data.radar_source = 'wk_wars2x'
    submitRadarHit(data)
end)

RegisterNetEvent('cbk_mdt:client:radarHit', function(data)
    submitRadarHit(data)
end)