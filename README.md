# gangs

Original FiveM territory / organization resource with Core Gangs–style gameplay:

- Organizations with roles & permissions
- Capturable zones (house, generation, processing, sales, continental)
- Zone wars with live scoring
- Bounties, criminal stats, titles, leaderboards
- Zone storages, NPC guards, continental shop
- Freecam PolyZone editor for admins (`/zoneeditor`) — fly into the sky and click ground points
- Rebel Roleplay Criminal Tablet NUI (`F11` / `/criminal`) with black/red/blue theme, city zone map, dual leaderboards, and admin tools
- Org logos (image URL) shown on war walls
- In-zone war HUD with gang names + colored score bars (no timer)
- Checkerboard war walls tinted to the leading org color

This is **not** a copy of C8RE Core Gangs code. It is an original implementation inspired by the same feature set.

## Dependencies

- `oxmysql`
- `ox_lib`
- `ox_target` or `qb-target`
- Framework: QBCore, QBox, or ESX (`Config.Framework = 'auto'`)
- Inventory: `ox_inventory` or `qb-inventory` (`Config.Inventory = 'auto'`)

## Install

1. Place this resource in your server as `resources/[local]/gangs` (folder name must match the resource name).
2. Import `sql/gangs.sql` into your database.
3. Add the currency item (default `bitcoin`) to your inventory/items list.
4. Ensure start order in `server.cfg`:

```cfg
ensure oxmysql
ensure ox_lib
ensure ox_target
ensure qb-core   # or qbx_core / es_extended
ensure ox_inventory
ensure gangs
```

5. Configure `config.lua` (framework, inventory, war windows, zone templates, etc.).
6. Restart the server, then create zones in-game with `/zoneeditor` (admin).

### Zone editor (freecam PolyZone)

Admins: `/zoneeditor`

1. Freecam starts above you — fly with **WASD**, look with mouse
2. **Space/Q** up, **Ctrl/C** down, **Shift** faster, **Scroll** speed
3. **Left click / E** places a ground poly point under the crosshair
4. Place **3+** points, then **Enter** to save the PolyZone
5. **Backspace** undo, **X / Esc** cancel

## Player commands

| Command | Description |
| --- | --- |
| `/criminal` or `F11` | Open Rebel Roleplay Criminal Tablet |
| `/gangaccept` | Accept organization invite |

## Admin commands

Admins also get an **Admin** tab in the Criminal Tablet for org setup/delete, zone ownership, stopping wars, and cooldown management.

| Command | Description |
| --- | --- |
| `/zoneeditor` | Freecam PolyZone editor (fly in sky, click points) |
| `/criminal zone` | Print current zone key |
| `/criminal setzone <key> <org>` | Assign zone ownership |
| `/criminal resetzone <key>` | Clear zone ownership |
| `/criminal startwar <key>` | Force-start a war |
| `/criminal stopwar <key>` | Cancel an active war (no ownership change) |
| `/criminal deletezone <key>` | Delete a zone |
| `/criminal givecurrency [id] [amount]` | Give currency item |

## Zone types

- **generation** — deposits configured items into zone storage on a timer
- **processing** — converts storage items using recipes
- **sales** — sells storage items into the owning org bank + street rep
- **house** — capturable stash territory
- **continental** — non-capturable safe/shop area; kills can auto-bounty the killer

## Exports (server)

```lua
exports['gangs']:getPlayerOrganization(source)
exports['gangs']:isPlayerInOrganization(source, orgName)
exports['gangs']:createOrganization(source, label, colorHex)
exports['gangs']:getOrganizationZone(zoneKey)
exports['gangs']:setZoneToOrg(zoneKey, orgName)
exports['gangs']:isWarInProgress(zoneKey)
exports['gangs']:getLeaderboard(10)
exports['gangs']:getOrgLeaderboard(10)
exports['gangs']:getZones()
```

## Exports (client)

```lua
exports['gangs']:inWarZone()
exports['gangs']:isPlayerOrganizationZone(zoneKey)
```

## Integration hooks

Edit `server/integration.lua` for:

- `onWarEnd(winnerInfo, loserInfo)`
- `callDispatch(x, y, zoneId, source)`
- `checkPoliceAmount()`
- `ClearPlayerInventory(source, identifier)`

## qb-inventory note

If you use qb-inventory / forks and need stash item injection for generation/processing/sales, expose stash helpers similar to common community patterns (`AddItemIntoStash`, `RemoveItemIntoStash`, `GetItemCountInStash`). With `ox_inventory`, no extra glue is required.

## Suggested currency item (QBCore)

```lua
bitcoin = {
    name = 'bitcoin',
    label = 'Bitcoin',
    weight = 0,
    type = 'item',
    image = 'bitcoin.png',
    unique = false,
    useable = false,
    description = 'Criminal network currency'
}
```
