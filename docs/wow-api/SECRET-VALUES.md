# Secret Values -- conditionally-secret API (build 12.1.0.69465)

Functions whose return value becomes a **Secret** under the given condition. In tainted addon code you must call `issecretvalue(v)` before any comparison, arithmetic, or table-index on the result -- otherwise the game raises a Lua error.

Predicate descriptions come from `SecretPredicatesDocumentation.lua`. See also `ADDON-RESTRICTIONS.md` for restriction types such as Challenge Mode (Mythic+).

Total: 300 entries across 23 conditions.

## `SecretInActivePvPMatch` (2)

> Guarded APIs and events produce secret values when PvP match addon restrictions are in effect.

- `GetScoreInfo` -- PvpInfo (`SecretArguments`: AllowedWhenUntainted)
- `GetScoreInfoByPlayerGuid` -- PvpInfo (`SecretArguments`: AllowedWhenUntainted)

## `SecretInChatMessagingLockdown` (98)

> Guarded APIs and events produce secret values when encounter, challenge mode, or PvP match addon restrictions are in effect, and when the player is on a communication-restricted map such as a dungeon or raid.

- `EventGetInvite` -- Calendar (`SecretArguments`: AllowedWhenUntainted)
- `EventGetInviteResponseTime` -- Calendar (`SecretArguments`: AllowedWhenUntainted)
- `GetClubCalendarEvents` -- Calendar (`SecretArguments`: AllowedWhenUntainted)
- `GetDayEvent` -- Calendar (`SecretArguments`: AllowedWhenUntainted)
- `ChatMsgAfk` -- ChatInfo
- `ChatMsgBn` -- ChatInfo
- `ChatMsgBnInlineToastAlert` -- ChatInfo
- `ChatMsgBnInlineToastBroadcast` -- ChatInfo
- `ChatMsgBnInlineToastBroadcastInform` -- ChatInfo
- `ChatMsgBnInlineToastConversation` -- ChatInfo
- `ChatMsgBnWhisper` -- ChatInfo
- `ChatMsgBnWhisperInform` -- ChatInfo
- `ChatMsgBnWhisperPlayerOffline` -- ChatInfo
- `ChatMsgChannel` -- ChatInfo
- `ChatMsgChannelJoin` -- ChatInfo
- `ChatMsgChannelLeave` -- ChatInfo
- `ChatMsgChannelList` -- ChatInfo
- `ChatMsgChannelNotice` -- ChatInfo
- `ChatMsgChannelNoticeUser` -- ChatInfo
- `ChatMsgCommunitiesChannel` -- ChatInfo
- `ChatMsgDnd` -- ChatInfo
- `ChatMsgEmote` -- ChatInfo
- `ChatMsgGuild` -- ChatInfo
- `ChatMsgIgnored` -- ChatInfo
- `ChatMsgInstanceChat` -- ChatInfo
- `ChatMsgInstanceChatLeader` -- ChatInfo
- `ChatMsgMonsterEmote` -- ChatInfo
- `ChatMsgMonsterParty` -- ChatInfo
- `ChatMsgMonsterSay` -- ChatInfo
- `ChatMsgMonsterWhisper` -- ChatInfo
- `ChatMsgMonsterYell` -- ChatInfo
- `ChatMsgOfficer` -- ChatInfo
- `ChatMsgOpening` -- ChatInfo
- `ChatMsgParty` -- ChatInfo
- `ChatMsgPartyLeader` -- ChatInfo
- `ChatMsgPing` -- ChatInfo
- `ChatMsgRaid` -- ChatInfo
- `ChatMsgRaidBossEmote` -- ChatInfo
- `ChatMsgRaidBossWhisper` -- ChatInfo
- `ChatMsgRaidLeader` -- ChatInfo
- `ChatMsgRaidWarning` -- ChatInfo
- `ChatMsgSay` -- ChatInfo
- `ChatMsgSkill` -- ChatInfo
- `ChatMsgSystem` -- ChatInfo
- `ChatMsgTargeticons` -- ChatInfo
- `ChatMsgTextEmote` -- ChatInfo
- `ChatMsgTradeskills` -- ChatInfo
- `ChatMsgVoiceText` -- ChatInfo
- `ChatMsgWhisper` -- ChatInfo
- `ChatMsgWhisperInform` -- ChatInfo
- `ChatMsgYell` -- ChatInfo
- `GetChatLineSenderGUID` -- ChatInfo (`SecretArguments`: AllowedWhenUntainted)
- `GetChatLineSenderName` -- ChatInfo (`SecretArguments`: AllowedWhenUntainted)
- `GetChatLineText` -- ChatInfo (`SecretArguments`: AllowedWhenUntainted)
- `GetClubInfo` -- Club (`SecretArguments`: AllowedWhenUntainted)
- `GetClubMembers` -- Club (`SecretArguments`: AllowedWhenUntainted)
- `GetInfoFromLastCommunityChatLine` -- Club
- `GetMemberInfo` -- Club (`SecretArguments`: AllowedWhenUntainted)
- `GetMessageInfo` -- Club (`SecretArguments`: AllowedWhenUntainted)
- `GetMessageRanges` -- Club (`SecretArguments`: AllowedWhenUntainted)
- `GetMessagesBefore` -- Club (`SecretArguments`: AllowedWhenUntainted)
- `GetMessagesInRange` -- Club (`SecretArguments`: AllowedWhenUntainted)
- `GetStreamInfo` -- Club (`SecretArguments`: AllowedWhenUntainted)
- `GetStreams` -- Club (`SecretArguments`: AllowedWhenUntainted)
- `GetSubscribedClubs` -- Club
- `IsBeginningOfStream` -- Club (`SecretArguments`: AllowedWhenUntainted)
- `RequestMoreMessagesBefore` -- Club (`SecretArguments`: AllowedWhenUntainted)
- `GuildMotd` -- GuildInfo
- `GetActiveEntryInfo` -- LFGListInfo
- `GetApplicantInfo` -- LFGListInfo (`SecretArguments`: AllowedWhenUntainted)
- `GetSearchResultInfo` -- LFGListInfo (`SecretArguments`: AllowedWhenUntainted)
- `GetSearchResultLeaderInfo` -- LFGListInfo (`SecretArguments`: AllowedWhenUntainted)
- `GetSearchResultPlayerInfo` -- LFGListInfo (`SecretArguments`: AllowedWhenUntainted)
- `ReadyCheck` -- PartyInfo
- `UnitIsAFK` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitIsDND` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `GetChannel` -- VoiceChat (`SecretArguments`: AllowedWhenUntainted)
- `GetChannelForChannelType` -- VoiceChat (`SecretArguments`: AllowedWhenUntainted)
- `GetChannelForCommunityStream` -- VoiceChat (`SecretArguments`: AllowedWhenUntainted)
- `GetMemberGUID` -- VoiceChat (`SecretArguments`: AllowedWhenUntainted)
- `GetMemberID` -- VoiceChat (`SecretArguments`: AllowedWhenUntainted)
- `GetMemberInfo` -- VoiceChat (`SecretArguments`: AllowedWhenUntainted)
- `GetMemberName` -- VoiceChat (`SecretArguments`: AllowedWhenUntainted)
- `IsMemberMutedForAll` -- VoiceChat (`SecretArguments`: AllowedWhenUntainted)
- `IsMemberSilenced` -- VoiceChat (`SecretArguments`: AllowedWhenUntainted)
- `VoiceChatChannelDisplayNameChanged` -- VoiceChat
- `VoiceChatChannelMemberActiveStateChanged` -- VoiceChat
- `VoiceChatChannelMemberAdded` -- VoiceChat
- `VoiceChatChannelMemberEnergyChanged` -- VoiceChat
- `VoiceChatChannelMemberGuidUpdated` -- VoiceChat
- `VoiceChatChannelMemberMuteForAllChanged` -- VoiceChat
- `VoiceChatChannelMemberRemoved` -- VoiceChat
- `VoiceChatChannelMemberSilencedChanged` -- VoiceChat
- `VoiceChatChannelMemberSpeakingStateChanged` -- VoiceChat
- `VoiceChatChannelMemberSttMessage` -- VoiceChat
- `VoiceChatChannelMemberVolumeChanged` -- VoiceChat
- `CancelPlayerCountdown` -- WorldStateInfo
- `StartPlayerCountdown` -- WorldStateInfo

## `SecretWhenAnchoringSecret` (23)

> Guarded APIs and events produce secret values when an object has secret anchoring information.

- `CalculateScreenAreaFromCharacterSpan` -- SimpleFontString (`SecretArguments`: AllowedWhenUntainted)
- `FindCharacterIndexAtCoordinate` -- SimpleFontString (`SecretArguments`: AllowedWhenUntainted)
- `GetNumLines` -- SimpleFontString
- `GetStringHeight` -- SimpleFontString
- `GetStringWidth` -- SimpleFontString
- `GetUnboundedStringWidth` -- SimpleFontString
- `GetUnboundedStringWidthForText` -- SimpleFontString (`SecretArguments`: AllowedWhenUntainted)
- `GetWrappedWidth` -- SimpleFontString
- `IsTruncated` -- SimpleFontString
- `GetBottom` -- SimpleScriptRegion
- `GetCenter` -- SimpleScriptRegion
- `GetHeight` -- SimpleScriptRegion (`SecretArguments`: AllowedWhenUntainted)
- `GetLeft` -- SimpleScriptRegion
- `GetRect` -- SimpleScriptRegion
- `GetRight` -- SimpleScriptRegion
- `GetScaledRect` -- SimpleScriptRegion
- `GetSize` -- SimpleScriptRegion (`SecretArguments`: AllowedWhenUntainted)
- `GetTop` -- SimpleScriptRegion
- `GetWidth` -- SimpleScriptRegion (`SecretArguments`: AllowedWhenUntainted)
- `Intersects` -- SimpleScriptRegion (`SecretArguments`: AllowedWhenUntainted)
- `IsMouseOver` -- SimpleScriptRegion (`SecretArguments`: AllowedWhenUntainted)
- `GetPoint` -- SimpleScriptRegionResizing (`SecretArguments`: AllowedWhenUntainted)
- `GetPointByName` -- SimpleScriptRegionResizing (`SecretArguments`: AllowedWhenUntainted)

## `SecretWhenAurasRestricted` (1)

> Guarded APIs and events produce secret values when combat, encounter, challenge mode, or PvP match addon restrictions are in effect.

- `UnitAura` -- UnitAura

## `SecretWhenCooldownsRestricted` (15)

> Guarded APIs and events produce secret values when combat, encounter, challenge mode, or PvP match addon restrictions are in effect. Individual spells may be flagged as never or always secret, which takes priority over restrictions.

- `GetActionCharges` -- ActionBarFrame (`SecretArguments`: AllowedWhenUntainted)
- `GetActionCooldown` -- ActionBarFrame (`SecretArguments`: AllowedWhenUntainted)
- `GetActionDisplayCount` -- ActionBarFrame (`SecretArguments`: AllowedWhenUntainted)
- `GetActionLossOfControlCooldownInfo` -- ActionBarFrame (`SecretArguments`: AllowedWhenUntainted)
- `GetActionUseCount` -- ActionBarFrame (`SecretArguments`: AllowedWhenUntainted)
- `GetLastCategoryCooldownSource` -- Spell (`SecretArguments`: AllowedWhenTainted)
- `GetSpellCastCount` -- Spell (`SecretArguments`: AllowedWhenTainted)
- `GetSpellCharges` -- Spell (`SecretArguments`: AllowedWhenTainted)
- `GetSpellCooldown` -- Spell (`SecretArguments`: AllowedWhenTainted)
- `GetSpellDisplayCount` -- Spell (`SecretArguments`: AllowedWhenUntainted)
- `GetSpellLossOfControlCooldownInfo` -- Spell (`SecretArguments`: AllowedWhenTainted)
- `GetSpellBookItemCastCount` -- SpellBook (`SecretArguments`: AllowedWhenUntainted)
- `GetSpellBookItemCharges` -- SpellBook (`SecretArguments`: AllowedWhenUntainted)
- `GetSpellBookItemCooldown` -- SpellBook (`SecretArguments`: AllowedWhenUntainted)
- `GetSpellBookItemLossOfControlCooldownInfo` -- SpellBook (`SecretArguments`: AllowedWhenUntainted)

## `SecretWhenCurveSecret` (8)

- `EvaluateElapsedDuration` -- LuaDurationObject (`SecretArguments`: AllowedWhenUntainted)
- `EvaluateElapsedPercent` -- LuaDurationObject (`SecretArguments`: AllowedWhenUntainted)
- `EvaluateRemainingDuration` -- LuaDurationObject (`SecretArguments`: AllowedWhenUntainted)
- `EvaluateRemainingPercent` -- LuaDurationObject (`SecretArguments`: AllowedWhenUntainted)
- `EvaluateTotalDuration` -- LuaDurationObject (`SecretArguments`: AllowedWhenUntainted)
- `UnitHealthPercent` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitPowerPercent` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `GetAuraDispelTypeColor` -- UnitAura (`SecretArguments`: AllowedWhenUntainted)

## `SecretWhenEncounterEvent` (3)

- `EncounterTimelineEventAdded` -- EncounterTimeline
- `GetEventColor` -- EncounterTimeline (`SecretArguments`: NotAllowed)
- `GetEventInfo` -- EncounterTimeline (`SecretArguments`: NotAllowed)

## `SecretWhenInCombat` (4)

> Guarded APIs and events produce secret values when combat addon restrictions are in effect.

- `GetCombatSessionFromID` -- DamageMeter (`SecretArguments`: AllowedWhenUntainted)
- `GetCombatSessionFromType` -- DamageMeter (`SecretArguments`: AllowedWhenUntainted)
- `GetCombatSessionSourceFromID` -- DamageMeter (`SecretArguments`: AllowedWhenUntainted)
- `GetCombatSessionSourceFromType` -- DamageMeter (`SecretArguments`: AllowedWhenUntainted)

## `SecretWhenLossOfControlInfoRestricted` (3)

> Guarded APIs and events produce secret values if the subject unit is not the active player, unless they are an active spectator or commentator of a PvP match.

- `GetActiveLossOfControlDataByUnit` -- LossOfControl (`SecretArguments`: AllowedWhenUntainted)
- `GetArenaCrowdControlInfo` -- PvpInfo (`SecretArguments`: AllowedWhenUntainted)
- `ArenaCrowdControlSpellUpdate` -- Unit

## `SecretWhenNumericFormatterSecret` (3)

- `FormatElapsedDuration` -- LuaDurationObject (`SecretArguments`: AllowedWhenUntainted)
- `FormatRemainingDuration` -- LuaDurationObject (`SecretArguments`: AllowedWhenUntainted)
- `FormatTotalDuration` -- LuaDurationObject (`SecretArguments`: AllowedWhenUntainted)

## `SecretWhenTotemSlotSecret` (2)

> Guarded APIs and events produce secret values when combat, encounter, challenge mode, or PvP match addon restrictions are in effect. Individual totem spell auras may be flagged as never or always secret, which takes priority over restrictions.

- `GetTotemInfo` -- Totem (`SecretArguments`: AllowedWhenUntainted)
- `GetTotemTimeLeft` -- Totem (`SecretArguments`: AllowedWhenUntainted)

## `SecretWhenUnitAuraRestricted` (20)

> Guarded APIs and events produce secret values when combat, encounter, challenge mode, or PvP match addon restrictions are in effect. Individual spells may be flagged as never or always secret, which takes priority over restrictions.

- `GetSpellMaxCumulativeAuraApplications` -- Spell (`SecretArguments`: AllowedWhenTainted)
- `GetUnitAura` -- TooltipInfo (`SecretArguments`: AllowedWhenUntainted)
- `GetUnitAuraByAuraInstanceID` -- TooltipInfo (`SecretArguments`: AllowedWhenUntainted)
- `GetUnitBuff` -- TooltipInfo (`SecretArguments`: AllowedWhenUntainted)
- `GetUnitBuffByAuraInstanceID` -- TooltipInfo (`SecretArguments`: AllowedWhenUntainted)
- `GetUnitDebuff` -- TooltipInfo (`SecretArguments`: AllowedWhenUntainted)
- `GetUnitDebuffByAuraInstanceID` -- TooltipInfo (`SecretArguments`: AllowedWhenUntainted)
- `DoesAuraHaveExpirationTime` -- UnitAura (`SecretArguments`: AllowedWhenUntainted)
- `GetAuraApplicationDisplayCount` -- UnitAura (`SecretArguments`: AllowedWhenUntainted)
- `GetAuraBaseDuration` -- UnitAura (`SecretArguments`: AllowedWhenTainted)
- `GetAuraDataByAuraInstanceID` -- UnitAura (`SecretArguments`: AllowedWhenUntainted)
- `GetAuraDataByIndex` -- UnitAura (`SecretArguments`: AllowedWhenUntainted)
- `GetAuraDataBySlot` -- UnitAura (`SecretArguments`: AllowedWhenUntainted)
- `GetAuraDataBySpellName` -- UnitAura (`SecretArguments`: AllowedWhenUntainted)
- `GetAuraDispelTypeColor` -- UnitAura (`SecretArguments`: AllowedWhenUntainted)
- `GetBuffDataByIndex` -- UnitAura (`SecretArguments`: AllowedWhenUntainted)
- `GetDebuffDataByIndex` -- UnitAura (`SecretArguments`: AllowedWhenUntainted)
- `GetPlayerAuraBySpellID` -- UnitAura (`SecretArguments`: AllowedWhenTainted)
- `GetRefreshExtendedDuration` -- UnitAura (`SecretArguments`: AllowedWhenTainted)
- `GetUnitAuraBySpellID` -- UnitAura (`SecretArguments`: AllowedWhenTainted)

## `SecretWhenUnitComparisonRestricted` (1)

> Guarded APIs and events produce secret values based upon supplied unit tokens. Comparisons involving compound unit tokens (eg. 'boss1target') are always secret. This restriction only applies when the player is on an addon-restricted map.

- `UnitIsUnit` -- Unit (`SecretArguments`: AllowedWhenUntainted)

## `SecretWhenUnitHealthMaxRestricted` (1)

> Guarded APIs and events produce secret values when the unit isn't player-controlled.

- `UnitHealthMax` -- Unit (`SecretArguments`: AllowedWhenUntainted)

## `SecretWhenUnitIdentityRestricted` (32)

> Guarded APIs and events produce secret values when the unit isn't player-controlled or in the party/raid. For compound tokens (eg. 'boss1target'), results are secret if any unit in the chain fails this.

- `GetUnitCriteriaProgressValues` -- ScenarioInfo (`SecretArguments`: AllowedWhenUntainted)
- `GetInspectSpecialization` -- SpecializationInfo (`SecretArguments`: AllowedWhenUntainted)
- `PartyKill` -- Unit
- `PlayerSoftInteractChanged` -- Unit
- `UnitClass` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitClassBase` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitCreatureFamily` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitCreatureID` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitCreatureType` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitDied` -- Unit
- `UnitFullName` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitGUID` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitGroupRolesAssigned` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitGroupRolesAssignedEnum` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitHonorLevel` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitInRaid` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitIsGroupAssistant` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitIsGroupLeader` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitIsOwnerOrControllerOfUnit` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitIsPVP` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitIsRaidOfficer` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitLeadsAnyGroup` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitNameFromGUID` -- Unit (`SecretArguments`: AllowedWhenTainted)
- `UnitNameUnmodified` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitOwnerGUID` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitPVPName` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitPhaseReason` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitRace` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitSex` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitSexBase` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitTokenFromGUID` -- Unit (`SecretArguments`: AllowedWhenTainted)
- `UnitGetAvailableRoles` -- UnitRole (`SecretArguments`: AllowedWhenUntainted)

## `SecretWhenUnitNameIdentityRestricted` (1)

> Guarded APIs and events produce secret values under regular unit identity secrecy rules, except in PvP when the queried unit is a player.

- `UnitName` -- Unit (`SecretArguments`: AllowedWhenTainted)

## `SecretWhenUnitPossessionRestricted` (2)

> Guarded APIs and events produce secret values based on aura secrecy, except for unit tokens under the player's direct control.

- `UnitIsCharmed` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitIsPossessed` -- Unit (`SecretArguments`: AllowedWhenUntainted)

## `SecretWhenUnitPowerMaxRestricted` (1)

> Guarded APIs and events produce secret values when the unit isn't player-controlled. Individual power types may be flagged as never or always secret, which takes priority.

- `UnitPowerMax` -- Unit (`SecretArguments`: AllowedWhenUntainted)

## `SecretWhenUnitPowerRestricted` (7)

> Guarded APIs and events produce secret values for power types not explicitly flagged as being never secret, unless the subject unit does not have a power of this type.

- `GetComboPoints` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `GetUnitChargedPowerPoints` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitPartialPower` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitPower` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitPowerMissing` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitPowerPercent` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitPowerPointCharge` -- Unit

## `SecretWhenUnitSpellCastRestricted` (21)

> Guarded APIs and events produce secret values if the unit being queried for cast information is not the player or their pet. Individual spells may be flagged as never or always secret, which takes priority.

- `GetUnitEmpowerHoldAtMaxTime` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `GetUnitEmpowerMinHoldTime` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `GetUnitEmpowerStageDuration` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitCastingInfo` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitChannelInfo` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitSpellcastChannelStart` -- Unit
- `UnitSpellcastChannelStop` -- Unit
- `UnitSpellcastChannelUpdate` -- Unit
- `UnitSpellcastDelayed` -- Unit
- `UnitSpellcastEmpowerStart` -- Unit
- `UnitSpellcastEmpowerStop` -- Unit
- `UnitSpellcastEmpowerUpdate` -- Unit
- `UnitSpellcastFailed` -- Unit
- `UnitSpellcastFailedQuiet` -- Unit
- `UnitSpellcastInterrupted` -- Unit
- `UnitSpellcastReticleClear` -- Unit
- `UnitSpellcastReticleTarget` -- Unit
- `UnitSpellcastSent` -- Unit
- `UnitSpellcastStart` -- Unit
- `UnitSpellcastStop` -- Unit
- `UnitSpellcastSucceeded` -- Unit

## `SecretWhenUnitStatsRestricted` (50)

> Guarded APIs and events produce secret values when access to unit stats would generally produce secret values.

> **Related:** `SecretWhenUnitAuraRestricted`: Guarded APIs and events produce secret values when combat, encounter, challenge mode, or PvP match addon restrictions are in effect. Individual spells may be flagged as never or always secret, which takes priority over restrictions.

- `GetAttackPowerForStat` -- PlayerScript (`SecretArguments`: AllowedWhenUntainted)
- `GetAvoidance` -- PlayerScript
- `GetBlockChance` -- PlayerScript
- `GetCombatRating` -- PlayerScript (`SecretArguments`: AllowedWhenUntainted)
- `GetCombatRatingBonus` -- PlayerScript (`SecretArguments`: AllowedWhenUntainted)
- `GetCritChance` -- PlayerScript
- `GetDodgeChance` -- PlayerScript
- `GetDodgeChanceFromAttribute` -- PlayerScript
- `GetExpertise` -- PlayerScript
- `GetExpertisePercent` -- PlayerScript
- `GetHaste` -- PlayerScript
- `GetHitModifier` -- PlayerScript
- `GetLifesteal` -- PlayerScript
- `GetManaRegen` -- PlayerScript
- `GetMastery` -- PlayerScript
- `GetMasteryEffect` -- PlayerScript
- `GetMeleeHaste` -- PlayerScript
- `GetModResilienceDamageReduction` -- PlayerScript
- `GetOverrideAPBySpellPower` -- PlayerScript
- `GetOverrideSpellPowerByAP` -- PlayerScript
- `GetParryChance` -- PlayerScript
- `GetParryChanceFromAttribute` -- PlayerScript
- `GetPetMeleeHaste` -- PlayerScript
- `GetPetSpellBonusDamage` -- PlayerScript
- `GetPowerRegen` -- PlayerScript
- `GetPowerRegenForPowerType` -- PlayerScript (`SecretArguments`: AllowedWhenUntainted)
- `GetPvpPowerDamage` -- PlayerScript
- `GetPvpPowerHealing` -- PlayerScript
- `GetRangedCritChance` -- PlayerScript
- `GetRangedHaste` -- PlayerScript
- `GetShieldBlock` -- PlayerScript
- `GetSpeed` -- PlayerScript
- `GetSpellBonusDamage` -- PlayerScript (`SecretArguments`: AllowedWhenUntainted)
- `GetSpellBonusHealing` -- PlayerScript
- `GetSpellCritChance` -- PlayerScript
- `GetSpellHitModifier` -- PlayerScript
- `GetSpellPenetration` -- PlayerScript
- `GetSturdiness` -- PlayerScript
- `GetVersatilityBonus` -- PlayerScript (`SecretArguments`: AllowedWhenUntainted)
- `PlayerEffectiveAttackPower` -- PlayerScript
- `GetUnitSpeed` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitArmor` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitAttackPower` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitAttackSpeed` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitDamage` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitRangedAttackPower` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitRangedDamage` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitSpellHaste` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitStat` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitWeaponAttackPower` -- Unit (`SecretArguments`: AllowedWhenUntainted)

## `SecretWhenUnitThreatStateRestricted` (2)

> Guarded APIs and events produce secret values based upon supplied unit tokens. Queries where only one unit token is specified, or where one unit token is the player, their pet, or an ally while the other is a nameplate, boss, target, etc., are generally not secret.

- `UnitThreatLeadSituation` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitThreatSituation` -- Unit (`SecretArguments`: AllowedWhenUntainted)

## `SecretWhenUnitThreatValuesRestricted` (2)

> Guarded APIs and events produce secret values based upon supplied unit tokens. Queries where only one unit token is specified, or where one unit token is the player, their pet, or an ally while the other is a non-boss or nameplate target, are generally not secret.

- `UnitDetailedThreatSituation` -- Unit (`SecretArguments`: AllowedWhenUntainted)
- `UnitThreatPercentageOfLead` -- Unit (`SecretArguments`: AllowedWhenUntainted)

