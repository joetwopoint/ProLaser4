# ProLaser4 – Community Fork Patchset (2026-03-05)

This package is your original ProLaser4 folder with a small set of stability + performance upgrades applied.

## What was changed

### Stability
- **NUI ready handshake** to prevent edge-cases where LUA/NUI messages race the JS initialization.
- JS now falls back to `GetParentResourceName()` if config hasn't arrived yet (prevents nil callback URL issues).

### Performance
- The "remove controls / reticle" loop now sleeps when the lidar weapon is not selected (less idle client work).
- SQL inserts are **batched** (fewer DB calls) when logging is enabled.

### Quality of life
- **oxmysql is now optional** at the manifest level:
  - If `cfg.logging = true`, you must have `oxmysql` installed and started before ProLaser4.
  - If `cfg.logging = false`, ProLaser4 runs without oxmysql.

## Install / Update

1) Replace your existing `ProLaser4/` folder with this one.
2) In `server.cfg`, ensure oxmysql is started before ProLaser4 **if logging is enabled**:
   ```cfg
   ensure oxmysql
   ensure ProLaser4
   ```
3) Restart your server.

## Notes

### Restart crash warning (weapon assets)
Like most custom weapon resources, restarting ProLaser4 while players have the weapon spawned can cause client instability.
If you frequently restart resources while players are online, consider splitting weapon metas/stream assets into a separate, rarely-restarted resource.

### SQL logging
If you do not use the records tablet / SQL logging, set:
```lua
cfg.logging = false
```
in `config.lua`.

## Files changed in this patchset
- `UI/html/lidar.js`
- `UI/cl_hud.lua`
- `UTIL/cl_lidar.lua`
- `UTIL/sv_lidar.lua`
- `fxmanifest.lua`
