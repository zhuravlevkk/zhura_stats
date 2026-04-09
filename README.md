# NE Stats

NE Stats is a World of Warcraft addon that shows your primary and secondary stats in a compact, movable panel.

It is designed for players who want a lightweight stat display with profile support, per-character customization, and multilingual UI options.

## Features

- Movable stat panel with lock/unlock support
- Optional lock icon display only on hover
- Lock button tooltip with left-click and right-click actions
- Configurable stat visibility and ordering
- Optional priority for the current specialization's main stat
- Adjustable font, font size, UI scale, and background opacity
- Toggle stat names, values, and percentages
- Account-wide profiles with create, rename, and delete actions
- Addon language selector
- Localized UI for `enUS`, `deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `ukUA`, `zhCN`, and `zhTW`

## Commands

- `/zhs`
- `/zhurastats`

Open the addon settings with either command.

Additional shortcuts:

- `/zhs lock` locks the frame
- `/zhs unlock` unlocks the frame
- `/zhs reset` resets the active profile

## Installation

### Manual

1. Download the latest `.zip`
2. Extract the `ZhuraStats` folder into:

```text
World of Warcraft\_retail_\Interface\AddOns\
```

3. The final path should look like:

```text
World of Warcraft\_retail_\Interface\AddOns\ZhuraStats\ZhuraStats.toc
```

### CurseForge Pack Structure

The uploaded archive should contain a single top-level addon folder:

```text
ZhuraStats.zip
\-- ZhuraStats/
    +-- ZhuraStats.toc
    +-- ZhuraStats.lua
    +-- embeds.xml
    +-- Libs/
    \-- Locales/
```

## Configuration

In the settings panel you can:

- choose the addon language or follow the client language
- show or hide percentages
- show or hide stat names and values
- lock the frame
- show the lock icon only on hover
- always show the current specialization main stat first
- change font and font size
- change UI scale and background opacity
- reset the panel position
- reorder visible stats

## Notes

- Profiles are shared across your account
- The display is character-focused, with profile-based customization
- The addon bundles its required libraries locally

## Development

Main files:

- `ZhuraStats.lua`
- `ZhuraStats.toc`
- `Locales/`

## Releases

GitHub Actions can build a release archive automatically.

- Push a tag like `v0.1.1` to trigger a release build and attach the zip to a GitHub Release
- Or run the `Release Build` workflow manually from the Actions tab to generate an artifact without publishing a tagged release

The workflow reads the addon version from `ZhuraStats.toc` and packages the addon as a CurseForge-ready zip with a top-level `ZhuraStats/` folder.

## License

This project is licensed under the MIT License. See `LICENSE` for details.
