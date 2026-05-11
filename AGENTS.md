## Purpose

This document defines strict engineering rules for working on the ZhuraStats WoW addon.  
All agents must follow these rules to avoid architecture degradation.

This is a modular addon. Do NOT revert it back into a monolith.

---

## Architecture Overview

The addon is split into clear layers. Each file has a single responsibility.

### Core Layers

- **Core.lua**
  - Orchestration only
  - Event handling
  - Initialization
  - Calls into other modules
  - MUST NOT contain business logic or UI logic

- **Database.lua**
  - Single source of truth for data
  - Profile management (AceDB)
  - Migration logic
  - ONLY place allowed to access `db.profile`

- **Stats.lua**
  - Reads WoW API values
  - Handles diminishing returns (DR)
  - Handles secret values and caching
  - MUST NOT contain UI or formatting logic

- **Render.lua**
  - Responsible for drawing stats on screen
  - Uses prepared data
  - MUST NOT access db directly
  - MUST NOT implement business logic

- **Frame.lua**
  - Frame creation and positioning
  - Drag & lock behavior
  - Visual container only

- **Format.lua**
  - All formatting logic
  - Percent, DR display, suffixes, gold formatting
  - No rendering or data fetching

- **Options.lua**
  - Settings UI
  - Sliders, checkboxes, dropdowns
  - Calls API methods only

- **Popups.lua**
  - StaticPopupDialogs
  - Profile create/rename/delete dialogs

- **Locale.lua**
  - Localization system
  - String resolution

- **Defaults.lua**
  - Constants
  - Default profile values

- **StatDefinitions.lua**
  - Static metadata (labels, colors, stat config)

- **Media.lua**
  - Fonts (LibSharedMedia)
  - Font helpers

- **ZhuraStats.lua**
  - Entry point only
  - Namespace bootstrap

---

## Hard Rules (DO NOT VIOLATE)

### 1. No Direct DB Access Outside Database.lua

Forbidden everywhere else:
```lua
db.profile
GetActiveProfile()
````

Allowed only via:

```lua
Addon:GetProfile()
Addon:GetProfileValue(key)
Addon:SetProfileValue(key, value)
```

---

### 2. No Cross-File Local Function Usage

If a function is used outside its file, it MUST be exposed via:

```lua
function Addon:FunctionName() end
```

Never rely on:

* load order
* shared locals
* accidental globals

---

### 3. Strict Layer Separation

#### Core.lua

MUST NOT:

* render UI
* format values
* read stats
* access db directly

#### Render.lua

MUST:

* only render

MUST NOT:

* access db
* implement business rules
* compute DR

#### Format.lua

MUST:

* handle all formatting

MUST NOT:

* access UI
* access WoW API directly (except pure formatting helpers)

#### Frame.lua

MUST:

* manage frame only

MUST NOT:

* format data
* compute stats

---

### 4. Single Responsibility Per File

Never split one logical system across multiple files.

Bad:

```
Render.lua → half logic
Core.lua → other half
```

Good:

```
Render.lua → ALL render logic
```

---

### 5. No Duplicate Helpers

If a helper exists:

* reuse it
* do NOT copy it

Common risks:

* DeepCopy
* formatting helpers
* profile utilities

---

### 6. Centralized Formatting

All stat formatting MUST go through:

```lua
Addon:FormatStat(statKey, result)
```

Forbidden:

* inline formatting
* string.format scattered across files

---

### 7. Stable Public API

Only expose necessary methods:

```lua
Addon:GetProfile()
Addon:SetProfileValue()
Addon:RefreshStats()
Addon:EnsureStatsFrame()
Addon:ApplyFrameStyle()
Addon:BuildOptionsPanel()
Addon:FormatStat()
```

Do not expose internal helpers.

---

## Refactoring Rules

When modifying code:

1. Do NOT mix responsibilities
2. Do NOT move code unless fully relocating the system
3. Do NOT leave partial logic behind
4. Always remove old implementations after moving logic

---

## Renderer Stability Rules

The stats frame must feel anchored and predictable during live stat updates.

* `RefreshStats()` MUST NOT reset frame position or call `ApplyFrameStyle()`.
* Text alignment controls the frame anchor:
  * `LEFT` → `BOTTOMLEFT`
  * `CENTER` → `BOTTOM`
  * `RIGHT` → `BOTTOMRIGHT`
* Live stat values, reference suffixes, DR hints, or tooltip state MUST NOT cause visible frame jumping.
* Row widgets MUST be fully reset before reuse: hide, clear points, clear text/state, and reset overlays.
* Tooltip hit areas MUST be row frames or explicit overlay frames, not bare `FontString` geometry.
* Frame controls belong in the controls row below the rendered stats, not in the stat text width calculation.
* Do not disable the active priority mode button; keep it mouse-interactive and make clicking it a no-op.

---

## Code Style Guidelines

* Prefer small focused functions
* Avoid deep nesting
* Avoid hidden side effects
* Use explicit naming
* Keep logic readable over clever

---

## Testing Checklist (MANDATORY)

After ANY change:
* Deploy addon to the game folder with addons (if possible)
* `/reload` → no Lua errors
* Frame appears
* Frame can be dragged
* Lock/unlock works
* Stats update correctly
* Enter/leave combat → no break
* Options panel opens
* Profile switching works
* Localization still works

### Local Game Deploy

Deploy the addon into the retail WoW AddOns folder from the repository root:

```powershell
.\scripts\deploy-local.ps1
```

Default target:

```text
C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\ZhuraStats
```

To deploy somewhere else:

```powershell
.\scripts\deploy-local.ps1 -TargetPath "C:\path\to\World of Warcraft\_retail_\Interface\AddOns\ZhuraStats"
```

After deploy, reload the game UI with `/reload`.

### Iteration Routine (MANDATORY)

After each implementation iteration (even small patches):
* Deploy addon locally via `scripts/deploy-local.ps1`
* Regenerate review diff file from the repo root: `cmd /c "git diff > temp-review.diff"` (Windows). This preserves UTF-8 from Git; avoid `git diff | Out-File` in PowerShell, which corrupts non-ASCII strings in locale diffs. On Unix shells, `git diff > temp-review.diff` is sufficient.

---

## Anti-Patterns (STRICTLY FORBIDDEN)

* Reintroducing monolithic files
* Copy-pasting logic between modules
* Accessing db from UI or Render
* Formatting inside Render or Frame
* Business logic inside Core
* Cross-file local dependencies

---

## Goal

Keep the addon:

* modular
* predictable
* easy to extend
* safe to refactor

If unsure:
→ prefer isolation over convenience
→ prefer explicit API over shortcuts
