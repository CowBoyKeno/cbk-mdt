local requestCounter = 0

local function newRequestId()
    requestCounter = requestCounter + 1
    return ('%s:%s:%s'):format(GetPlayerServerId(PlayerId()), GetGameTimer(), requestCounter)
end

local function requestServer(action, payload, timeoutMs)
    timeoutMs = timeoutMs or 12000

    local p = promise.new()
    local requestId = newRequestId()

    CBK_MDT_Client.state.pending[requestId] = p
    TriggerServerEvent('cbk_mdt:server:request', requestId, action, payload or {})

    SetTimeout(timeoutMs, function()
        if CBK_MDT_Client.state.pending[requestId] then
            CBK_MDT_Client.state.pending[requestId] = nil
            p:resolve({ ok = false, data = 'Request timed out' })
        end
    end)

    return Citizen.Await(p)
end

RegisterNetEvent('cbk_mdt:client:response', function(requestId, ok, data)
    local p = CBK_MDT_Client.state.pending[requestId]
    if not p then
        return
    end

    CBK_MDT_Client.state.pending[requestId] = nil
    p:resolve({ ok = ok == true, data = data })
end)

RegisterCommand(Config.Command, function()
    local result = requestServer('get_dashboard', {})
    if not result.ok then
        CBK_MDT_Client.Notify(result.data or 'Unable to open MDT', 'error')
        return
    end

    CBK_MDT_Client.SetOpen(true)

    SendNUIMessage({
        type = 'mdt:init',
        payload = {
            dashboard = result.data,
            config = {
                command = Config.Command,
                radarEnabled = Config.Radar.enabled,
                radarProvider = Config.Radar.provider
            }
        }
    })
end, false)

RegisterNUICallback('mdt:close', function(_, cb)
    CBK_MDT_Client.SetOpen(false)
    cb({ ok = true })
end)

RegisterNUICallback('mdt:request', function(data, cb)
    if type(data) ~= 'table' then
        cb({ ok = false, data = 'Invalid payload' })
        return
    end

    local action = data.action
    local payload = data.payload or {}

    if type(action) ~= 'string' then
        cb({ ok = false, data = 'Invalid action' })
        return
    end

    local result = requestServer(action, payload)
    cb(result)
end)

RegisterNUICallback('mdt:appendActivity', function(data, cb)
    if type(data) ~= 'table' then
        cb({ ok = false })
        return
    end

    TriggerServerEvent('cbk_mdt:server:appendActivity', tostring(data.action or 'ui_action'), tostring(data.details or ''))
    cb({ ok = true })
end)

RegisterKeyMapping(Config.Command, 'Open Police MDT', 'keyboard', 'F6')