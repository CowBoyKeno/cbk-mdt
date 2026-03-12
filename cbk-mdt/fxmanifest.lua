fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'cbk-mdt'
author 'CowBoyKeno'
description 'Production-ready police MDT for FiveM with framework adapters and oxmysql storage'
version '1.1.0'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/app.css',
    'web/app.js'
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/framework.lua'
}

client_scripts {
    'client/ui.lua',
    'client/client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/server.lua',
    'server/citizens.lua',
    'server/vehicles.lua',
    'server/reports.lua',
    'server/warrants.lua',
    'server/bolos.lua',
    'server/evidence.lua',
    'server/radar.lua'
}

dependencies {
    'oxmysql'
}