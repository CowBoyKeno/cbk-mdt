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

Config.Security = {
    maxPayloadDepth = 5,
    maxPayloadKeys = 120,
    maxPayloadStringLength = 4000,
    maxInFlightRequests = 3,
    requestWindowMs = 10000,
    maxRequestsPerWindow = 50,
    abuseBlockMs = 30000,
    abuseStrikesBeforeBlock = 8,
    actionCooldownMs = {
        get_dashboard = 2000,
        list_charges = 500,
        get_officer_profile = 1200,
        update_officer_notes = 3000,
        search_citizens = 500,
        get_citizen_profile = 600,
        save_citizen_notes = 2000,
        create_or_update_citizen = 2500,
        search_vehicles = 500,
        upsert_vehicle = 2500,
        set_vehicle_stolen = 2500,
        create_report = 3000,
        search_reports = 500,
        get_report = 600,
        create_warrant = 3500,
        update_warrant_status = 2500,
        create_bolo = 3500,
        update_bolo_status = 2500,
        add_evidence = 3000,
        list_evidence = 500,
        list_warrants = 500,
        list_bolos = 500,
        list_radar_logs = 200,
        panic_alert = 15000
    },
    activityCooldownMs = 3000,
    requireOnDuty = true,
    requireStableSession = true,
    radarCooldownMs = 1000,
    radarMaxSpeed = 260,
    radarBatchSize = 25,
    radarFlushMs = 1500
}

Config.Permissions = {
    aceAdmin = 'cbk.mdt.admin',
    gradeThresholds = {
        officer = 1,
        supervisor = 4,
        command = 7,
        mdt_admin = 10
    },
    matrix = {
        viewer = {
            view = true
        },
        officer = {
            view = true,
            officer_tools = true,
            report_writer = true,
            evidence_writer = true,
            warrant_writer = true,
            bolo_writer = true,
            citizen_writer = true,
            vehicle_writer = true
        },
        supervisor = {
            view = true,
            officer_tools = true,
            report_writer = true,
            evidence_writer = true,
            warrant_writer = true,
            warrant_supervisor = true,
            bolo_writer = true,
            bolo_supervisor = true,
            citizen_writer = true,
            citizen_supervisor = true,
            vehicle_writer = true,
            vehicle_supervisor = true
        },
        command = {
            view = true,
            officer_tools = true,
            report_writer = true,
            evidence_writer = true,
            warrant_writer = true,
            warrant_supervisor = true,
            bolo_writer = true,
            bolo_supervisor = true,
            citizen_writer = true,
            citizen_supervisor = true,
            vehicle_writer = true,
            vehicle_supervisor = true,
            mdt_admin = true
        },
        mdt_admin = {
            view = true,
            officer_tools = true,
            report_writer = true,
            evidence_writer = true,
            warrant_writer = true,
            warrant_supervisor = true,
            bolo_writer = true,
            bolo_supervisor = true,
            citizen_writer = true,
            citizen_supervisor = true,
            vehicle_writer = true,
            vehicle_supervisor = true,
            mdt_admin = true
        }
    }
}

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
    provider = 'wk_wars2x',
    -- all: log NPC + player plates.
    -- players: only enforce owner-plate DB checks for non-wk sources; wk_wars2x ALPR/radar hits bypass ownership checks.
    captureScope = 'all',
    -- Harden incoming radar events by requiring a valid player->vehicle state for the source.
    strictSourceVehicleCheck = true,
    -- Require a server-issued token for radar ingest/unlock events from clients.
    requireToken = true,
    -- Lifetime (seconds) for radar auth tokens issued to clients.
    tokenTtlSeconds = 180,
    -- Prints radar ingest/drop reasons to server console for troubleshooting.
    debug = false
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
    maxChargesPerReport = 30,
    maxCitizenNameLength = 120,
    maxVehicleModelLength = 80
}

Config.Evidence = {
    maxMetadataDepth = 3,
    maxMetadataKeys = 30,
    maxMetadataStringLength = 200,
    allowedMetadata = {
        photo = { camera = true, timestamp = true, location = true },
        casing = { caliber = true, serial = true },
        fingerprint = { match_score = true, source = true },
        dna = { match_score = true, lab = true },
        general = { note = true }
    }
}