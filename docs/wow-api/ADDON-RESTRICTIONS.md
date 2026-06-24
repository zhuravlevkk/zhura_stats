# Addon Restrictions (build 12.0.7.68275)

Generated from `RestrictedActionsConstantsDocumentation.lua` and selected entries in `RestrictedActionsDocumentation.lua`.

Use this to interpret `ADDON_RESTRICTION_STATE_CHANGED`, `GetAddOnRestrictionState`, and `IsAddOnRestrictionActive`.

## `AddOnRestrictionState`

- **`Inactive`** = `0` -- State used when an addon restriction is not being enforced.
- **`Activating`** = `1` -- State used during the dispatch of ADDON_RESTRICTION_STATE_CHANGED to infer that a restriction is about to become active, but won't be enforced until event dispatch has completed.
- **`Active`** = `2` -- State used when an addon restriction is presently being enforced.

## `AddOnRestrictionType`

- **`Combat`** = `0` -- The player is actively affecting combat.
- **`Encounter`** = `1` -- The player is actively participating in an instance encounter.
- **`ChallengeMode`** = `2` -- The player is in an active and incomplete challenge mode or mythic keystone dungeon.
- **`PvPMatch`** = `3` -- The player is in an active and incomplete PvP match.
- **`Map`** = `4` -- The player is on a map that applies addon restrictions.
- **`Chat`** = `5` -- The player is in a state where addon chat communications are restricted.

## Key APIs and events

### `AddonRestrictionStateChanged` / `ADDON_RESTRICTION_STATE_CHANGED` (Event)

Fired when the state of an addon restriction type is changing. This event is sequenced such that it will always be fired before a restriction becomes active, or after it is deactivated.

- **Payload:** `type`: AddOnRestrictionType, `state`: AddOnRestrictionState

### `GetAddOnRestrictionState` (Function)

Returns the current state of an addon restriction type.

- **Arguments:** `type`: AddOnRestrictionType
- **Returns:** `state`: AddOnRestrictionState
- **SecretArguments:** `AllowedWhenUntainted`

### `IsAddOnRestrictionActive` (Function)

Returns true if an addon restriction type is in an active state. Will always return false during dispatch of ADDON_RESTRICTION_STATE_CHANGED.

- **Arguments:** `type`: AddOnRestrictionType
- **Returns:** `active`: bool
- **SecretArguments:** `AllowedWhenUntainted`

