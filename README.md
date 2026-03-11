# CBK MDT

Production-ready FiveM Police MDT resource with oxmysql persistence, secure server-authoritative actions, multi-framework adapters, and modern NUI.

Last updated: 03-10-2026

## Features

   - Citizen search, profile view, criminal history, and notes
   - Vehicle plate lookup, owner lookup, and stolen flagging
   - Incident and arrest report creation with charge auto-calculation
   - Warrant management (create, list, update status)
   - BOLO management (create, list, update status)
   - Evidence attachments with image URLs and report association
   - Radar logging with optional wk_wars2x integration
   - Officer profile, officer reports, and officer activity log
# - Draggable and resizable dark-theme NUI with responsive layout #



## Dependencies

- oxmysql (required)
- ox_lib (required)
- One framework (optional but recommended): QBCore, Qbox, ESX, ND_Core, or OX_Core
- wk_wars2x radar (optional)

## Installation

1. Place the `cbk-mdt` folder in your server resources.
2. Import SQL from `cbk-mdt/sql/install.sql` into your server database.
3. Ensure dependencies are started before this resource:

```cfg
ensure oxmysql
ensure ox_lib
ensure cbk-mdt
```

1. Configure framework and MDT settings in `cbk-mdt/shared/config.lua`.
1. Restart the server.

## SQL Import

Run `cbk-mdt/sql/install.sql` in your MySQL database used by oxmysql.

The schema creates all required MDT tables with timestamps:

- `mdt_citizens`
- `mdt_reports`
- `mdt_warrants`
- `mdt_bolos`
- `mdt_evidence`
- `mdt_radar_logs`
- `mdt_charges`
- `mdt_officers`

Additional helper table included:

- `mdt_vehicles`

## Framework Configuration

Edit `cbk-mdt/shared/config.lua`:

```lua
Config.Framework = 'auto' -- auto | qbcore | qbox | esx | nd_core | ox_core
Config.AllowedJobs = {
    police = true,
    sheriff = true,
    statepolice = true,
    trooper = true,
    fib = true
}
```

Framework adapter logic is in `cbk-mdt/shared/framework.lua`.

## Radar Integration (wk_wars2x)

Radar logging is optional and controlled in `cbk-mdt/shared/config.lua`:

```lua
Config.Radar = {
    enabled = true,
    provider = 'wk_wars2x'
}
```

The client listens for these events and forwards validated hits to the server:

- `wk_wars2x:radarHit`
- `wk:radar:hit`

Server storage target: `mdt_radar_logs`.

## Commands

- `/mdt` opens the MDT UI and sets NUI focus.
- Default key mapping: `F6`.

## Resource Structure

```text
cbk-mdt/
  fxmanifest.lua
  shared/config.lua
  shared/framework.lua
  client/client.lua
  client/ui.lua
  client/radar.lua
  server/server.lua
  server/citizens.lua
  server/vehicles.lua
  server/reports.lua
  server/warrants.lua
  server/bolos.lua
  server/evidence.lua
  server/radar.lua
  web/index.html
  web/app.css
  web/app.js
  sql/install.sql
  README.md
```

## Security and Performance Notes

- Server-authoritative action handling in `server/server.lua`
- Payload validation and input length control
- No trust in client-side calculations (charges recalculated server-side)
- Query limits via configurable max search values
- Radar logging includes lightweight source rate limiting




