# NE Stats

NE Stats is a modular World of Warcraft addon that shows your stats in a compact, movable panel.

It is built for players who want a lightweight live stat display with profile support, per-character customization, and multilingual UI.

## Features

- Movable stat panel with lock/unlock behavior
- Optional lock icon shown only on hover
- Configurable stat visibility, order, and per-stat color
- Support for primary and secondary stats, plus utility stats (`Parry`, `Dodge`, `Block`, `Leech`, `Speed Rating`, `Movement Speed`, `Durability`, `Item Level`, `Gold`)
- Stat priority modes:
  - `Manual`
  - `Archon Raid`
  - `Archon Mythic+`
- Optional priority for current specialization primary stat
- Adjustable columns, max rows per column, font, font size, text alignment, scale, and background opacity
- Toggle stat labels, values, and percentages
- Profile create/rename/delete/switch actions (AceDB)
- Addon language selector with runtime localization refresh
- Localized UI for `enUS`, `deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `ukUA`, `zhCN`, `zhTW`

## Commands

- `/zhs`
- `/zhurastats`

Both commands open addon settings.

Additional shortcuts:

- `/zhs lock` - lock the frame
- `/zhs unlock` - unlock the frame
- `/zhs reset` - reset the active profile

## Installation

### Manual

1. Download the latest `.zip`
2. Extract the `ZhuraStats` folder into:

```text
World of Warcraft\_retail_\Interface\AddOns\
```

3. Final path should look like:

```text
World of Warcraft\_retail_\Interface\AddOns\ZhuraStats\ZhuraStats.toc
```

### CurseForge Package Structure

The release archive must contain a single top-level addon folder:

```text
ZhuraStats.zip
\-- ZhuraStats/
    +-- ZhuraStats.toc
    +-- ZhuraStats.lua
    +-- embeds.xml
    +-- Libs/
    +-- Media/
    \-- Locales/
```

## Configuration

In the settings panel you can:

- choose addon language or follow the game client language
- lock/unlock the frame and show lock icon only on hover
- show or hide stat labels, values, and percentages
- select stat priority mode (`Manual`, `Archon Raid`, `Archon Mythic+`)
- keep current spec primary stat at top
- split stats into multiple columns
- limit rows per column or keep auto layout
- change font, font size, and text alignment
- change frame scale and background opacity
- reset frame position
- reorder visible stats (when priority mode allows manual ordering)

## Data Sources

### `WoWLogsStatsPrio.lua`

Contains generated stat priority data used by Archon priority modes.

- Generated through the official Warcraft Logs GraphQL API locally or in CI
- Key format: `"class/spec/activity"` where `activity` is `m+` or `raid`
- Used at runtime to lock and apply stat ordering for secondary stats

Create a Warcraft Logs API client at `https://www.warcraftlogs.com/api/clients/`,
then provide its client credentials and update from the repo root:

```powershell
$env:WCL_CLIENT_ID = "<client id>"
$env:WCL_CLIENT_SECRET = "<client secret>"
node ./scripts/Get-AllStats.mjs --out-file "./WoWLogsStatsPrio.lua"
```

Optional custom thread count:

```powershell
node ./scripts/Get-AllStats.mjs --threads 3 --out-file "./WoWLogsStatsPrio.lua"
```

The GitHub Actions workflow expects repository secrets named `WCL_CLIENT_ID`
and `WCL_CLIENT_SECRET`. Credentials are used only to obtain a short-lived OAuth
token and are never written to the generated Lua file or logs.

### `ArchonPriority.lua`

Runtime mapping and resolution layer that:

- resolves player class/spec to Archon keys
- validates available stat entries
- applies mode-specific priority ordering

## Development

Core addon modules are split by responsibility:

- `Core.lua` - initialization and event orchestration
- `Database.lua` - profile data and migrations
- `Stats.lua` - stat reads and calculations
- `Render.lua` - frame text layout/rendering
- `Frame.lua` - movable frame container behavior
- `Format.lua` - centralized stat formatting
- `Options.lua` - settings UI
- `Popups.lua` - profile popup dialogs
- `Locale.lua` - localization resolution
- `Defaults.lua` - defaults/constants
- `StatDefinitions.lua` - stat metadata
- `Media.lua` - font/media helpers
- `ZhuraStats.lua` - addon entry point

## Releases

GitHub Actions can build and publish release artifacts automatically.

- After merge to `master`, updating `## Version` in `ZhuraStats.toc` triggers `Tag Release Version`
- The created tag triggers `Release Build` workflow
- `Release Build` packages a CurseForge-ready zip and publishes GitHub Release notes
- You can also push a manual tag (for example `v0.3.0`)
- Or run `Release Build` manually to produce an artifact without publishing a tagged release

The workflow always reads addon version from `ZhuraStats.toc`.

## License

This project is licensed under the MIT License. See `LICENSE` for details.
