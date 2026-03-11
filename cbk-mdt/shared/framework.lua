Framework = {
    name = 'standalone',
    object = nil
}

local function detectFramework()
    if Config.Framework ~= 'auto' then
        return string.lower(Config.Framework)
    end

    if GetResourceState('qbx_core') == 'started' then
        return 'qbox'
    end

    if GetResourceState('cbk2') == 'started' then
        local ok = pcall(function()
            return exports['cbk2']:GetCoreObject()
        end)
        if ok then
            return 'qbox'
        end
    end

    if GetResourceState('qb-core') == 'started' then
        return 'qbcore'
    end

    if GetResourceState('es_extended') == 'started' then
        return 'esx'
    end

    if GetResourceState('ND_Core') == 'started' then
        return 'nd_core'
    end

    if GetResourceState('ox_core') == 'started' then
        return 'ox_core'
    end

    return 'standalone'
end

local function safeGetObject(resource, exportName)
    local ok, result = pcall(function()
        return exports[resource][exportName]()
    end)
    if ok then
        return result
    end
    return nil
end

function Framework.Init()
    Framework.name = detectFramework()

    if Framework.name == 'qbcore' then
        Framework.object = exports['qb-core']:GetCoreObject()
    elseif Framework.name == 'qbox' then
        Framework.object = safeGetObject('qbx_core', 'GetCoreObject')
    elseif Framework.name == 'esx' then
        local ok, obj = pcall(function()
            return exports['es_extended']:getSharedObject()
        end)
        if ok then
            Framework.object = obj
        else
            TriggerEvent('esx:getSharedObject', function(shared)
                Framework.object = shared
            end)
        end
    elseif Framework.name == 'nd_core' then
        Framework.object = safeGetObject('ND_Core', 'GetCoreObject')
    elseif Framework.name == 'ox_core' then
        Framework.object = safeGetObject('ox_core', 'GetCoreObject')
    end

    print(('[cbk-mdt] Framework initialized: %s'):format(Framework.name))
end

function Framework.GetPlayer(source)
    if Framework.name == 'qbcore' and Framework.object then
        return Framework.object.Functions.GetPlayer(source)
    end

    if Framework.name == 'qbox' then
        local ok, player = pcall(function()
            return exports.qbx_core:GetPlayer(source)
        end)
        if ok then
            return player
        end

        local okCbk2, playerCbk2 = pcall(function()
            return exports['cbk2']:GetPlayer(source)
        end)
        if okCbk2 then
            return playerCbk2
        end
    end

    if Framework.name == 'esx' and Framework.object then
        return Framework.object.GetPlayerFromId(source)
    end

    if Framework.name == 'nd_core' then
        local ok, player = pcall(function()
            return exports.ND_Core:GetPlayer(source)
        end)
        if ok then
            return player
        end
    end

    if Framework.name == 'ox_core' then
        local ok, player = pcall(function()
            return exports.ox_core:GetPlayer(source)
        end)
        if ok then
            return player
        end
    end

    return nil
end

function Framework.GetIdentifier(source)
    local player = Framework.GetPlayer(source)

    if Framework.name == 'qbcore' and player and player.PlayerData and player.PlayerData.citizenid then
        return player.PlayerData.citizenid
    end

    if Framework.name == 'qbox' and player and player.PlayerData and player.PlayerData.citizenid then
        return player.PlayerData.citizenid
    end

    if Framework.name == 'esx' and player and player.identifier then
        return player.identifier
    end

    if Framework.name == 'nd_core' and player and player.identifier then
        return player.identifier
    end

    if Framework.name == 'ox_core' and player and player.charId then
        return tostring(player.charId)
    end

    local ids = GetPlayerIdentifiers(source)
    return ids[1] or ('src:%s'):format(source)
end

function Framework.GetPlayerName(source)
    local player = Framework.GetPlayer(source)

    if Framework.name == 'qbcore' and player and player.PlayerData and player.PlayerData.charinfo then
        local charinfo = player.PlayerData.charinfo
        return (charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')
    end

    if Framework.name == 'qbox' and player and player.PlayerData and player.PlayerData.charinfo then
        local charinfo = player.PlayerData.charinfo
        return (charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')
    end

    if Framework.name == 'esx' and player then
        local fullName = (player.getName and player.getName()) or ''
        if fullName ~= '' then
            return fullName
        end
    end

    return GetPlayerName(source) or ('Officer %s'):format(source)
end

function Framework.GetJob(source)
    local player = Framework.GetPlayer(source)

    if Framework.name == 'qbcore' and player and player.PlayerData and player.PlayerData.job then
        return player.PlayerData.job.name, player.PlayerData.job.grade and player.PlayerData.job.grade.level or 0
    end

    if Framework.name == 'qbox' and player and player.PlayerData and player.PlayerData.job then
        local grade = player.PlayerData.job.grade
        local gradeLevel = type(grade) == 'table' and (grade.level or 0) or tonumber(grade) or 0
        return player.PlayerData.job.name, gradeLevel
    end

    if Framework.name == 'esx' and player and player.job then
        return player.job.name, tonumber(player.job.grade) or 0
    end

    if Framework.name == 'nd_core' and player and player.job then
        return player.job, tonumber(player.rank) or 0
    end

    if Framework.name == 'ox_core' and player and player.getGroup then
        local group, grade = player:getGroup('police')
        if group then
            return group, grade or 0
        end
    end

    return 'unknown', 0
end

function Framework.IsAllowed(source)
    local jobName = Framework.GetJob(source)
    if not jobName then
        return false
    end

    return Config.AllowedJobs[string.lower(jobName)] == true
end

function Framework.IsSourceValid(source)
    if type(source) ~= 'number' or source <= 0 then
        return false
    end

    return GetPlayerName(source) ~= nil
end

function Framework.IsOnDuty(source)
    local player = Framework.GetPlayer(source)

    if Framework.name == 'qbcore' and player and player.PlayerData and player.PlayerData.job then
        if type(player.PlayerData.job.onduty) == 'boolean' then
            return player.PlayerData.job.onduty
        end
    end

    if Framework.name == 'qbox' and player and player.PlayerData and player.PlayerData.job then
        if type(player.PlayerData.job.onduty) == 'boolean' then
            return player.PlayerData.job.onduty
        end
    end

    if Framework.name == 'esx' and player and player.job then
        if type(player.job.onDuty) == 'boolean' then
            return player.job.onDuty
        end
    end

    if Framework.name == 'nd_core' and player and type(player.onDuty) == 'boolean' then
        return player.onDuty
    end

    local state = Player(source) and Player(source).state
    if state and type(state.onduty) == 'boolean' then
        return state.onduty
    end

    return true
end

function Framework.GetDepartment(source)
    local jobName = Framework.GetJob(source)
    if type(jobName) ~= 'string' then
        return 'unknown'
    end

    return string.lower(jobName)
end

CreateThread(function()
    Framework.Init()
end)