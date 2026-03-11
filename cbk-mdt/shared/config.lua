Config = {}

Config.ResourceName = 'cbk-mdt'
Config.Framework = 'auto' -- auto | qbcore | qbox | esx | nd_core | ox_core
Config.Command = 'mdt'
Config.Locale = 'en'

Config.AllowedJobs = {
    police = true,
    sheriff = true,
    statepolice = true,
    trooper = true,
    fib = true
}

Config.MaxSearchResults = 50
Config.MaxRecentReports = 25

Config.NativeSync = {
    enabled = true,
    citizens = {
        qbcore = {
            search = [[
                SELECT citizenid AS identifier,
                       JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) AS firstname,
                       JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) AS lastname,
                       JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.birthdate')) AS dob,
                       JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.phone')) AS phone
                FROM players
                WHERE citizenid LIKE ?
                   OR JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) LIKE ?
                   OR JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) LIKE ?
                   OR JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.phone')) LIKE ?
                LIMIT ?
            ]],
            byIdentifier = [[
                SELECT citizenid AS identifier,
                       JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) AS firstname,
                       JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) AS lastname,
                       JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.birthdate')) AS dob,
                       JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.phone')) AS phone
                FROM players
                WHERE citizenid = ?
                LIMIT 1
            ]]
        },
        qbox = {
            search = [[
                SELECT citizenid AS identifier,
                       JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) AS firstname,
                       JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) AS lastname,
                       JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.birthdate')) AS dob,
                       JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.phone')) AS phone
                FROM players
                WHERE citizenid LIKE ?
                   OR JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) LIKE ?
                   OR JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) LIKE ?
                   OR JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.phone')) LIKE ?
                LIMIT ?
            ]],
            byIdentifier = [[
                SELECT citizenid AS identifier,
                       JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) AS firstname,
                       JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) AS lastname,
                       JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.birthdate')) AS dob,
                       JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.phone')) AS phone
                FROM players
                WHERE citizenid = ?
                LIMIT 1
            ]]
        },
        esx = {
            search = [[
                SELECT identifier,
                       firstname,
                       lastname,
                       dateofbirth AS dob,
                       phone_number AS phone
                FROM users
                WHERE identifier LIKE ?
                   OR firstname LIKE ?
                   OR lastname LIKE ?
                   OR phone_number LIKE ?
                LIMIT ?
            ]],
            byIdentifier = [[
                SELECT identifier,
                       firstname,
                       lastname,
                       dateofbirth AS dob,
                       phone_number AS phone
                FROM users
                WHERE identifier = ?
                LIMIT 1
            ]]
        }
    },
    vehicles = {
        qbcore = {
            search = [[
                SELECT plate,
                       citizenid AS owner_identifier,
                       JSON_UNQUOTE(JSON_EXTRACT(vehicle, '$.model')) AS model_name
                FROM player_vehicles
                WHERE plate LIKE ? OR citizenid LIKE ?
                LIMIT ?
            ]],
            byPlate = [[
                SELECT plate,
                       citizenid AS owner_identifier,
                       JSON_UNQUOTE(JSON_EXTRACT(vehicle, '$.model')) AS model_name
                FROM player_vehicles
                WHERE plate = ?
                LIMIT 1
            ]]
        },
        qbox = {
            search = [[
                SELECT plate,
                       citizenid AS owner_identifier,
                       JSON_UNQUOTE(JSON_EXTRACT(vehicle, '$.model')) AS model_name
                FROM player_vehicles
                WHERE plate LIKE ? OR citizenid LIKE ?
                LIMIT ?
            ]],
            byPlate = [[
                SELECT plate,
                       citizenid AS owner_identifier,
                       JSON_UNQUOTE(JSON_EXTRACT(vehicle, '$.model')) AS model_name
                FROM player_vehicles
                WHERE plate = ?
                LIMIT 1
            ]]
        },
        esx = {
            search = [[
                SELECT plate,
                       owner AS owner_identifier,
                       '' AS model_name
                FROM owned_vehicles
                WHERE plate LIKE ? OR owner LIKE ?
                LIMIT ?
            ]],
            byPlate = [[
                SELECT plate,
                       owner AS owner_identifier,
                       '' AS model_name
                FROM owned_vehicles
                WHERE plate = ?
                LIMIT 1
            ]]
        }
    }
}

Config.Radar = {
    enabled = true,
    provider = 'wk_wars2x'
}

Config.Warrant = {
    defaultExpiryHours = 72
}

Config.Charges = {
    { code = 'PC100', label = 'Speeding', category = 'Traffic', fine = 500, jail = 0 },
    { code = 'PC101', label = 'Reckless Driving', category = 'Traffic', fine = 1500, jail = 10 },
    { code = 'PC200', label = 'Evading Police', category = 'Felony', fine = 5000, jail = 40 },
    { code = 'PC201', label = 'Resisting Arrest', category = 'Misdemeanor', fine = 1800, jail = 15 },
    { code = 'PC300', label = 'Possession of Illegal Firearm', category = 'Felony', fine = 7000, jail = 45 },
    { code = 'PC301', label = 'Armed Robbery', category = 'Felony', fine = 12000, jail = 80 },
    { code = 'PC302', label = 'Attempted Murder', category = 'Felony', fine = 25000, jail = 140 }
}

Config.Report = {
    maxTitleLength = 120,
    maxSummaryLength = 1000,
    maxNarrativeLength = 5000,
    maxPeoplePerReport = 25,
    maxVehiclesPerReport = 25,
    maxEvidencePerReport = 50,
    maxChargesPerReport = 30
}