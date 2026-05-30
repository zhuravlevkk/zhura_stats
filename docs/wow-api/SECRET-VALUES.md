# Secret Values -- conditionally-secret API (build 12.0.5.67823)

Functions whose return value becomes a **Secret** under the given condition. In tainted addon code you must call `issecretvalue(v)` before any comparison, arithmetic, or table-index on the result -- otherwise the game raises a Lua error.

Total: 286 entries across 20 conditions.

## `SecretInActivePvPMatch` (2)

- `GetScoreInfo` -- PvpInfo
- `GetScoreInfoByPlayerGuid` -- PvpInfo

## `SecretInChatMessagingLockdown` (107)

- `EventGetInvite` -- Calendar
- `EventGetInviteResponseTime` -- Calendar
- `GetClubCalendarEvents` -- Calendar
- `GetDayEvent` -- Calendar
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
- `ChatMsgCombatFactionChange` -- ChatInfo
- `ChatMsgCombatHonorGain` -- ChatInfo
- `ChatMsgCombatMiscInfo` -- ChatInfo
- `ChatMsgCombatXpGain` -- ChatInfo
- `ChatMsgCommunitiesChannel` -- ChatInfo
- `ChatMsgCurrency` -- ChatInfo
- `ChatMsgDnd` -- ChatInfo
- `ChatMsgEmote` -- ChatInfo
- `ChatMsgFiltered` -- ChatInfo
- `ChatMsgGuild` -- ChatInfo
- `ChatMsgIgnored` -- ChatInfo
- `ChatMsgInstanceChat` -- ChatInfo
- `ChatMsgInstanceChatLeader` -- ChatInfo
- `ChatMsgLoot` -- ChatInfo
- `ChatMsgMoney` -- ChatInfo
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
- `ChatMsgRestricted` -- ChatInfo
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
- `GetChatLineSenderGUID` -- ChatInfo
- `GetChatLineSenderName` -- ChatInfo
- `GetChatLineText` -- ChatInfo
- `GetClubInfo` -- Club
- `GetClubMembers` -- Club
- `GetInfoFromLastCommunityChatLine` -- Club
- `GetMemberInfo` -- Club
- `GetMessageInfo` -- Club
- `GetMessageRanges` -- Club
- `GetMessagesBefore` -- Club
- `GetMessagesInRange` -- Club
- `GetStreamInfo` -- Club
- `GetStreams` -- Club
- `GetSubscribedClubs` -- Club
- `IsBeginningOfStream` -- Club
- `RequestMoreMessagesBefore` -- Club
- `GuildMotd` -- GuildInfo
- `GetActiveEntryInfo` -- LFGListInfo
- `GetApplicantInfo` -- LFGListInfo
- `GetSearchResultInfo` -- LFGListInfo
- `GetSearchResultLeaderInfo` -- LFGListInfo
- `GetSearchResultPlayerInfo` -- LFGListInfo
- `ReadyCheck` -- PartyInfo
- `UnitIsAFK` -- Unit
- `UnitIsDND` -- Unit
- `GetChannel` -- VoiceChat
- `GetChannelForChannelType` -- VoiceChat
- `GetChannelForCommunityStream` -- VoiceChat
- `GetMemberGUID` -- VoiceChat
- `GetMemberID` -- VoiceChat
- `GetMemberInfo` -- VoiceChat
- `GetMemberName` -- VoiceChat
- `IsMemberMutedForAll` -- VoiceChat
- `IsMemberSilenced` -- VoiceChat
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

- `CalculateScreenAreaFromCharacterSpan` -- SimpleFontString
- `FindCharacterIndexAtCoordinate` -- SimpleFontString
- `GetNumLines` -- SimpleFontString
- `GetStringHeight` -- SimpleFontString
- `GetStringWidth` -- SimpleFontString
- `GetUnboundedStringWidth` -- SimpleFontString
- `GetUnboundedStringWidthForText` -- SimpleFontString
- `GetWrappedWidth` -- SimpleFontString
- `IsTruncated` -- SimpleFontString
- `GetBottom` -- SimpleScriptRegion
- `GetCenter` -- SimpleScriptRegion
- `GetHeight` -- SimpleScriptRegion
- `GetLeft` -- SimpleScriptRegion
- `GetRect` -- SimpleScriptRegion
- `GetRight` -- SimpleScriptRegion
- `GetScaledRect` -- SimpleScriptRegion
- `GetSize` -- SimpleScriptRegion
- `GetTop` -- SimpleScriptRegion
- `GetWidth` -- SimpleScriptRegion
- `Intersects` -- SimpleScriptRegion
- `IsMouseOver` -- SimpleScriptRegion
- `GetPoint` -- SimpleScriptRegionResizing
- `GetPointByName` -- SimpleScriptRegionResizing

## `SecretWhenCooldownsRestricted` (14)

- `GetActionCharges` -- ActionBarFrame
- `GetActionCooldown` -- ActionBarFrame
- `GetActionDisplayCount` -- ActionBarFrame
- `GetActionLossOfControlCooldownInfo` -- ActionBarFrame
- `GetActionUseCount` -- ActionBarFrame
- `GetSpellCastCount` -- Spell
- `GetSpellCharges` -- Spell
- `GetSpellCooldown` -- Spell
- `GetSpellDisplayCount` -- Spell
- `GetSpellLossOfControlCooldownInfo` -- Spell
- `GetSpellBookItemCastCount` -- SpellBook
- `GetSpellBookItemCharges` -- SpellBook
- `GetSpellBookItemCooldown` -- SpellBook
- `GetSpellBookItemLossOfControlCooldownInfo` -- SpellBook

## `SecretWhenCurveSecret` (8)

- `EvaluateElapsedDuration` -- LuaDurationObject
- `EvaluateElapsedPercent` -- LuaDurationObject
- `EvaluateRemainingDuration` -- LuaDurationObject
- `EvaluateRemainingPercent` -- LuaDurationObject
- `EvaluateTotalDuration` -- LuaDurationObject
- `UnitHealthPercent` -- Unit
- `UnitPowerPercent` -- Unit
- `GetAuraDispelTypeColor` -- UnitAura

## `SecretWhenEncounterEvent` (2)

- `EncounterTimelineEventAdded` -- EncounterTimeline
- `GetEventInfo` -- EncounterTimeline

## `SecretWhenInCombat` (4)

- `GetCombatSessionFromID` -- DamageMeter
- `GetCombatSessionFromType` -- DamageMeter
- `GetCombatSessionSourceFromID` -- DamageMeter
- `GetCombatSessionSourceFromType` -- DamageMeter

## `SecretWhenLossOfControlInfoRestricted` (3)

- `GetActiveLossOfControlDataByUnit` -- LossOfControl
- `GetArenaCrowdControlInfo` -- PvpInfo
- `ArenaCrowdControlSpellUpdate` -- Unit

## `SecretWhenNumericFormatterSecret` (3)

- `FormatElapsedDuration` -- LuaDurationObject
- `FormatRemainingDuration` -- LuaDurationObject
- `FormatTotalDuration` -- LuaDurationObject

## `SecretWhenTotemSlotSecret` (2)

- `GetTotemInfo` -- Totem
- `GetTotemTimeLeft` -- Totem

## `SecretWhenUnitAuraRestricted` (20)

- `GetSpellMaxCumulativeAuraApplications` -- Spell
- `GetUnitAura` -- TooltipInfo
- `GetUnitAuraByAuraInstanceID` -- TooltipInfo
- `GetUnitBuff` -- TooltipInfo
- `GetUnitBuffByAuraInstanceID` -- TooltipInfo
- `GetUnitDebuff` -- TooltipInfo
- `GetUnitDebuffByAuraInstanceID` -- TooltipInfo
- `DoesAuraHaveExpirationTime` -- UnitAura
- `GetAuraApplicationDisplayCount` -- UnitAura
- `GetAuraBaseDuration` -- UnitAura
- `GetAuraDataByAuraInstanceID` -- UnitAura
- `GetAuraDataByIndex` -- UnitAura
- `GetAuraDataBySlot` -- UnitAura
- `GetAuraDataBySpellName` -- UnitAura
- `GetAuraDispelTypeColor` -- UnitAura
- `GetBuffDataByIndex` -- UnitAura
- `GetDebuffDataByIndex` -- UnitAura
- `GetPlayerAuraBySpellID` -- UnitAura
- `GetRefreshExtendedDuration` -- UnitAura
- `GetUnitAuraBySpellID` -- UnitAura

## `SecretWhenUnitComparisonRestricted` (1)

- `UnitIsUnit` -- Unit

## `SecretWhenUnitHealthMaxRestricted` (1)

- `UnitHealthMax` -- Unit

## `SecretWhenUnitIdentityRestricted` (15)

- `GetUnitCriteriaProgressValues` -- ScenarioInfo
- `PartyKill` -- Unit
- `PlayerSoftInteractChanged` -- Unit
- `UnitCreatureFamily` -- Unit
- `UnitCreatureID` -- Unit
- `UnitCreatureType` -- Unit
- `UnitDied` -- Unit
- `UnitFullName` -- Unit
- `UnitGUID` -- Unit
- `UnitName` -- Unit
- `UnitNameFromGUID` -- Unit
- `UnitNameUnmodified` -- Unit
- `UnitOwnerGUID` -- Unit
- `UnitPVPName` -- Unit
- `UnitTokenFromGUID` -- Unit

## `SecretWhenUnitPowerMaxRestricted` (1)

- `UnitPowerMax` -- Unit

## `SecretWhenUnitPowerRestricted` (7)

- `GetComboPoints` -- Unit
- `GetUnitChargedPowerPoints` -- Unit
- `UnitPartialPower` -- Unit
- `UnitPower` -- Unit
- `UnitPowerMissing` -- Unit
- `UnitPowerPercent` -- Unit
- `UnitPowerPointCharge` -- Unit

## `SecretWhenUnitSpellCastRestricted` (21)

- `GetUnitEmpowerHoldAtMaxTime` -- Unit
- `GetUnitEmpowerMinHoldTime` -- Unit
- `GetUnitEmpowerStageDuration` -- Unit
- `UnitCastingInfo` -- Unit
- `UnitChannelInfo` -- Unit
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

- `GetAttackPowerForStat` -- PlayerScript
- `GetAvoidance` -- PlayerScript
- `GetBlockChance` -- PlayerScript
- `GetCombatRating` -- PlayerScript
- `GetCombatRatingBonus` -- PlayerScript
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
- `GetPowerRegenForPowerType` -- PlayerScript
- `GetPvpPowerDamage` -- PlayerScript
- `GetPvpPowerHealing` -- PlayerScript
- `GetRangedCritChance` -- PlayerScript
- `GetRangedHaste` -- PlayerScript
- `GetShieldBlock` -- PlayerScript
- `GetSpeed` -- PlayerScript
- `GetSpellBonusDamage` -- PlayerScript
- `GetSpellBonusHealing` -- PlayerScript
- `GetSpellCritChance` -- PlayerScript
- `GetSpellHitModifier` -- PlayerScript
- `GetSpellPenetration` -- PlayerScript
- `GetSturdiness` -- PlayerScript
- `GetVersatilityBonus` -- PlayerScript
- `PlayerEffectiveAttackPower` -- PlayerScript
- `GetUnitSpeed` -- Unit
- `UnitArmor` -- Unit
- `UnitAttackPower` -- Unit
- `UnitAttackSpeed` -- Unit
- `UnitDamage` -- Unit
- `UnitRangedAttackPower` -- Unit
- `UnitRangedDamage` -- Unit
- `UnitSpellHaste` -- Unit
- `UnitStat` -- Unit
- `UnitWeaponAttackPower` -- Unit

## `SecretWhenUnitThreatStateRestricted` (2)

- `UnitThreatLeadSituation` -- Unit
- `UnitThreatSituation` -- Unit

## `SecretWhenUnitThreatValuesRestricted` (2)

- `UnitDetailedThreatSituation` -- Unit
- `UnitThreatPercentageOfLead` -- Unit

