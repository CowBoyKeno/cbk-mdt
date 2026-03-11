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

RegisterKeyMapping(Config.Command, 'Open Police MDT', 'keyboard', 'F6')

RegisterNetEvent('cbk_mdt:client:panicAlert', function(data)
    if type(data) ~= 'table' then
        return
    end

    local x = tonumber(data.x)
    local y = tonumber(data.y)
    local z = tonumber(data.z)
    if not x or not y or not z then
        return
    end

    local durationMs = math.max(1000, tonumber(data.durationMs) or 60000)
    local soundDurationMs = math.max(1000, tonumber(data.soundDurationMs) or 10000)
    local officerName = tostring(data.officerName or ('Officer %s'):format(tostring(data.source or '?')))

    CBK_MDT_Client.Notify(('PANIC: %s requested immediate backup!'):format(officerName), 'error')

    local blip = AddBlipForCoord(x, y, z)
    SetBlipSprite(blip, 161)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 1.2)
    SetBlipColour(blip, 1)
    SetBlipAsShortRange(blip, false)
    SetBlipHighDetail(blip, true)
    SetBlipFlashes(blip, true)
    SetBlipFlashInterval(blip, 250)
    SetBlipFlashTimer(blip, durationMs)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(('PANIC | %s'):format(officerName))
    EndTextCommandSetBlipName(blip)

    CreateThread(function()
        local endAt = GetGameTimer() + soundDurationMs
        while GetGameTimer() < endAt do
            PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
            Wait(900)
        end
    end)

    SetTimeout(durationMs, function()
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end)
end)