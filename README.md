# CBK POLICE MDT #

Production-ready FiveM Police MDT resource with oxmysql persistence, secure server-authoritative actions, multi-framework adapters, and modern NUI.

Last updated: 03-11-2026
Current version: 1.1.0

# Additional Credits #

Special shout out to **WolfKnight98**, the original creator of **wk_wars2x / Wraith ARS 2X**.

Original repository: [https://github.com/WolfKnight98/wk_wars2x](https://github.com/WolfKnight98/wk_wars2x)

This project exists because of the time, care, and quality put into the original release.
Thank you for building and sharing such an outstanding radar system with the FiveM community.

## CHANGELOG

- 03-11-2026 (CowBoyKeno) - v1.1.0
  - Switched ALPR page to live-feed mode with dedicated Front/Rear slots.
  - Added MDT close-to-unlock behavior for matching radar antenna.
  - Added radar ingest hardening: strict source checks and expiring token auth.
  - Updated Wraith integration to direct server ingest (`radarHit`/`radarUnlock`) with token handshake.

## Features

- Citizen search, profile view, criminal history, and notes
- Vehicle plate lookup, owner lookup, and stolen flagging
- Incident and arrest report creation with charge auto-calculation
- Warrant management (create, list, update status)
- BOLO management (create, list, update status)
- Evidence attachments with image URLs and report association
- Live ALPR feed integration with wk_wars2x (front/rear antenna aware)
- Officer profile, officer reports, and officer activity log
- Draggable and resizable dark-theme NUI with responsive layout

## Dependencies

- oxmysql (required)
- ox_lib (required)
- One framework (optional but recommended): QBCore, Qbox, ESX, ND_Core, or OX_Core
- wk_wars2x radar (optional) (only use the version that comes with the latest release of cbk-mdt)

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
- `mdt_vehicles`
- `mdt_audit_log` (immutable mutation audit trail)

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

Radar/ALPR integration is optional and controlled in `cbk-mdt/shared/config.lua`:

```lua
Config.Radar = {
    enabled = true,
    provider = 'wk_wars2x',
    captureScope = 'all',
    strictSourceVehicleCheck = true,
    requireToken = true,
    tokenTtlSeconds = 180,
    debug = false
}
```

### CowBoyKeno Integration Notes

- ALPR page now renders fixed antenna slots (Front on top, Rear on bottom).
- ALPR list is live-feed only (in-memory), not DB-backed for the ALPR page.
- Closing a Front/Rear ALPR lock from MDT also unlocks the same radar antenna in Wraith.
- Radar lock automatically syncs and locks the matching plate-reader side.

### Event Flow

- Wraith client emits directly to MDT server:
  - `cbk_mdt:server:radarHit`
  - `cbk_mdt:server:radarUnlock`
- MDT server issues auth tokens to clients:
  - `cbk_mdt:server:requestRadarToken`
  - `cbk_mdt:client:setRadarToken`
- MDT close action can force local antenna unlock:
  - `cbk_mdt:client:forceRadarUnlockAntenna`

### Security Hardening

- Server validates source state for radar ingest/unlock (`strictSourceVehicleCheck = true`).
- Radar ingest/unlock requires a server-issued expiring token (`requireToken = true`).
- `dismiss_radar_log` only forces antenna unlock for the same officer that created the ALPR lock.

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
- Session freshness checks for source validity, identity, and department continuity
- Optional on-duty enforcement on secured actions
- No trust in client-side calculations (charges recalculated server-side)
- Query limits via configurable max search values
- Radar/ALPR ingest includes source rate limiting and server-side validation
