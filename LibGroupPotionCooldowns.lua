--- general initialization
local lib = {
    name = "LibGroupPotionCooldowns",
    version = "dev",
}
local lib_debug = false
local lib_name = lib.name
local lib_version = lib.version
_G[lib_name] = lib

local LGB = LibGroupBroadcast
local EM = EVENT_MANAGER
local LocalEM = ZO_CallbackObject:New()
local localPlayer = "player"

local _LGBHandler = {}
local _LGBProtocols = {}
local _registeredAddons = {}

--- logging setup
local mainLogger
local subLoggers = {}
local LOG_LEVEL_ERROR = "E"
local LOG_LEVEL_WARNING ="W"
local LOG_LEVEL_INFO = "I"
local LOG_LEVEL_DEBUG = "D"
local LOG_LEVEL_VERBOSE = "V"

local MESSAGE_ID_COOLDOWN = 26

local EVENT_PLAYER_COOLDOWN_UPDATE = "EVENT_PLAYER_COOLDOWN_UPDATE"
local EVENT_GROUP_COOLDOWN_UPDATE = "EVENT_GROUP_COOLDOWN_UPDATE"

lib.EVENT_PLAYER_COOLDOWN_UPDATE = EVENT_PLAYER_COOLDOWN_UPDATE
lib.EVENT_GROUP_COOLDOWN_UPDATE = EVENT_GROUP_COOLDOWN_UPDATE

--- often used variables
local PLAYER_CHARACTER_NAME = GetUnitName(localPlayer)
local PLAYER_DISPLAY_NAME = GetUnitDisplayName(localPlayer)

if LibDebugLogger then
    mainLogger = LibDebugLogger.Create(lib_name)

    LOG_LEVEL_ERROR = LibDebugLogger.LOG_LEVEL_ERROR
    LOG_LEVEL_WARNING = LibDebugLogger.LOG_LEVEL_WARNING
    LOG_LEVEL_INFO = LibDebugLogger.LOG_LEVEL_INFO
    LOG_LEVEL_DEBUG = LibDebugLogger.LOG_LEVEL_DEBUG
    LOG_LEVEL_VERBOSE = LibDebugLogger.LOG_LEVEL_VERBOSE

    subLoggers["broadcast"] = mainLogger:Create("broadcast")
    subLoggers["encoding"] = mainLogger:Create("encoding")
    subLoggers["events"] = mainLogger:Create("events")
    subLoggers["debug"] = mainLogger:Create("debug")
end

--- utility functions
local function Log(category, level, ...)
    if not mainLogger then return end
    if category == "debug" and not lib_debug then return end

    local logger = subLoggers[category] or mainLogger
    if type(logger.Log)=="function" then logger:Log(level, ...) end
end

--- Main Library
local groupStats = {
    [PLAYER_CHARACTER_NAME] = {
        tag = localPlayer,
        name = PLAYER_CHARACTER_NAME,
        displayName = PLAYER_DISPLAY_NAME,
        isPlayer = true,
        isOnline = true,

        potionData = {
            lastUpdated = 0,
            isOnCooldown = false,
            cooldownDurationMS = 45.0,
            hasCooldownUntil = GetGameTimeMilliseconds(),
        },
    }
}

local _PotionStatsObject = {}
_PotionStatsObject.__index = _PotionStatsObject

-- Constructor for the _CombatStatsObject
-- @return (table): A new instance of _PotionStatsObject
function _PotionStatsObject:New()
    local obj = setmetatable({}, _PotionStatsObject)
    return obj
end
-- Returns key, value of groupStats
-- @return (string, table): key value pairs of groupStats
function _PotionStatsObject:Iterate()
    local key, value
    return function()
        key, value = next(groupStats, key)
        if not key then
            return nil
        end

        local stats = groupStats[key]
        return stats.tag, {
            tag = stats.tag,
            name = stats.name,
            displayName = stats.displayName,
            isPlayer = stats.isPlayer,

            potionData = stats.potionData,
        }
    end
end
-- metatable version of _PotionStatsObject:Iterate()
function _PotionStatsObject:__pairs()
    return self:Iterate()
end
-- Returns the number of group members in "groupStats"
-- @return (number): the number of units in the group
function _PotionStatsObject:GetGroupSize()
    return #groupStats
end
-- metatable version of _PotionStatsObject:GetGroupSize()
function _PotionStatsObject:__len()
    return self:GetGroupSize()
end
-- Retrieves a copy of the current group statistics
-- @return (table): A table containing group statistics (cloned from the internal state)
function _PotionStatsObject:GetGroupStats()
    local result = {}
    for tag, stats in self:Iterate() do
        result[tag] = stats
    end

    return result
end
-- Retrieves statistics for a specific unit in the group
-- @param unitTag (string): The unitTag of the group member (e.g., "group1")
-- @return (table or nil): A table containing the unit's statistics, or nil if the unit is not found
function _PotionStatsObject:GetUnitPotionData(unitTag)
    local characterName = GetUnitName(unitTag)
    local unit = groupStats[characterName]
    if not unit then
        Log("debug", LOG_LEVEL_DEBUG, "unit does not exist in groupStats")
        return nil
    end
    local result = {
        tag = unitTag,
        name = unit.name,
        displayName = unit.displayName,
        isPlayer = unit.isPlayer,

        potionData = unit.potionData,
    }

    return result
end
function _PotionStatsObject:GetUnitRemainingCooldownMS(unitTag)
    local characterName = GetUnitName(unitTag)
    local unit = groupStats[characterName]
    if not unit then
        Log("debug", LOG_LEVEL_DEBUG, "unit does not exist in groupStats")
        return nil
    end
    local t = GetGameTimeMilliseconds()
    local result = zo_max(0, t - unit.hasCooldownUntil)
    return result
end
function _PotionStatsObject:IsUnitOnCooldown(unitTag)
    local characterName = GetUnitName(unitTag)
    local unit = groupStats[characterName]
    if not unit then
        Log("debug", LOG_LEVEL_DEBUG, "unit does not exist in groupStats")
        return nil
    end
    return unit.potionData.isOnCooldown
end

-- Registers a callback function for a specified event
-- @param eventName (string): The name of the event to register for
-- @param callback (function): The function to be called when the event is triggered
function _PotionStatsObject:RegisterForEvent(eventName, callback)
    assert(type(callback) == "function", "callback must be a function")
    assert(type(eventName) == "string", "eventName must be a string")

    LocalEM:RegisterCallback(eventName, callback)
    Log("events", LOG_LEVEL_DEBUG, "callback for %s registered", eventName)
end
-- Unregisters a callback function for a specified event
-- @param eventName (string): The name of the event to unregister from
-- @param callback (function): The callback function to unregister
function _PotionStatsObject:UnregisterForEvent(eventName, callback)
    assert(type(callback) == "function", "callback must be a function")
    assert(type(eventName) == "string", "eventName must be a string")

    Log("events", LOG_LEVEL_DEBUG, "callback for %s unregistered", eventName)
    LocalEM:UnregisterCallback(eventName, callback)
end

--- group change tracking
local function OnGroupChange()
    local _existingGroupCharacters = {} -- create empty table to create a list of all groupmembers after the change
    local _groupSize = GetGroupSize()

    for i = 1, _groupSize do
        local tag = GetGroupUnitTagByIndex(i)

        if IsUnitPlayer(tag) then

            local isPlayer = AreUnitsEqual(tag, localPlayer)
            local characterName = GetUnitName(tag)
            _existingGroupCharacters[characterName] = true

            if not isPlayer then
                groupStats[characterName] = groupStats[characterName] or {
                    name = characterName,
                    displayName = GetUnitDisplayName(tag),
                    isPlayer = isPlayer,
                    isOnline = IsUnitOnline(tag),

                    potionData = {
                        lastUpdated = 0,
                        isOnCooldown = false,
                        cooldownDurationMS = 45000,
                        hasCooldownUntil = GetGameTimeMilliseconds(),
                    },
                }

            end
            groupStats[characterName].tag = tag
            --groupStats[characterName].isOnline = IsUnitOnline(tag)
        end
    end

    for characterName, _ in pairs(groupStats) do
        if characterName ~= PLAYER_CHARACTER_NAME then
            if not _existingGroupCharacters[characterName] then
                groupStats[characterName] = nil
            end
        end
    end
end

local function OnGroupChangeDelayed()
    zo_callLater(OnGroupChange, 250) -- wait 250ms to avoid any race conditions
end

local function unregisterGroupEvents()
    EM:UnregisterForEvent(lib_name, EVENT_GROUP_MEMBER_JOINED)
    EM:UnregisterForEvent(lib_name, EVENT_GROUP_MEMBER_LEFT)
    --EM:UnregisterForEvent(lib_name, EVENT_GROUP_UPDATE)
    EM:UnregisterForEvent(lib_name, EVENT_GROUP_MEMBER_CONNECTED_STATUS)
    Log("events", LOG_LEVEL_DEBUG, "group events unregistered")
end
local function registerGroupEvents()
    EM:RegisterForEvent(lib_name, EVENT_GROUP_MEMBER_JOINED, OnGroupChangeDelayed)
    EM:RegisterForEvent(lib_name, EVENT_GROUP_MEMBER_LEFT, OnGroupChangeDelayed)
    --EM:RegisterForEvent(lib_name, EVENT_GROUP_UPDATE, OnGroupChangeDelayed)
    EM:RegisterForEvent(lib_name, EVENT_GROUP_MEMBER_CONNECTED_STATUS, OnGroupChangeDelayed)
    Log("events", LOG_LEVEL_DEBUG, "group events registered")
end

local function onInventoryItemUsed(_, sound)
    if sound ~= ITEM_SOUND_CATEGORY_POTION then return end

    EM:RegisterForUpdate(lib_name .. "onDrink", 10, function(...)
        local slotIndex = GetCurrentQuickslot()
        local remain, duration, global, _ = GetSlotCooldownInfo(slotIndex, HOTBAR_CATEGORY_QUICKSLOT_WHEEL)
        if not global then
            EM:UnregisterForUpdate(lib_name .. "onDrink")
            local data = {
                remain = remain / 1000,
                duration = duration / 1000,
                minDelay = GetGroupAddOnDataBroadcastCooldownRemainingMS(),
            }
            _LGBProtocols[MESSAGE_ID_COOLDOWN]:Send(data)
        end
    end)
end

local function onMessageCooldownUpdateReceived(tag, data)
    local charName = GetUnitName(tag)
    if not charName then d("can not get charName") return end
    if not groupStats[charName] then d("OnGroupChange") OnGroupChange() end
    if not groupStats[charName] then d("still no groupStats entry") return end

    groupStats[charName].tag = tag

    local t = GetGameTimeMilliseconds()
    local totalCooldown = (data.remain * 1000) + data.minDelay

    local potionData = groupStats[charName].potionData
    potionData.lastUpdated = t
    potionData.isOnCooldown = true
    potionData.cooldownDurationMS = data.duration * 1000
    potionData.hasCooldownUntil = t + totalCooldown

    local eventName = EVENT_GROUP_COOLDOWN_UPDATE
    if AreUnitsEqual(localPlayer, tag) then
        eventName = EVENT_PLAYER_COOLDOWN_UPDATE
    end

    LocalEM:FireCallbacks(eventName, tag, potionData)
    zo_callLater(function()
        groupStats[charName].potionData.isOnCooldown = false
        LocalEM:FireCallbacks(eventName, tag, groupStats[charName].potionData)
    end, totalCooldown)
end

function lib.RegisterAddon(addonName)
    if not addonName then
        Log("main", LOG_LEVEL_ERROR, "addonName must be provided")
        return nil
    end

    if _registeredAddons[addonName] then
        Log("debug", LOG_LEVEL_ERROR, "Addon %s tried to register multiple times", addonName)
        return nil
    end

    _registeredAddons[addonName] = true

    Log("debug", LOG_LEVEL_INFO, "Addon " .. addonName .. " registered.")
    return _PotionStatsObject:New()
end

local function onPlayerActivated()
    -- set the player character name again to ensure that after swapping a character it gets updated
    PLAYER_CHARACTER_NAME = GetUnitName(localPlayer)

    -- trigger group update
    OnGroupChangeDelayed()
    -- register group update events
    unregisterGroupEvents()
    registerGroupEvents()

    EM:RegisterForEvent(lib_name .. "onDrink", EVENT_INVENTORY_ITEM_USED, onInventoryItemUsed)
    EM:AddFilterForEvent(lib_name .. "onDrink", EVENT_INVENTORY_ITEM_USED, REGISTER_FILTER_UNIT_TAG, localPlayer)
end

local function declareLGBProtocols()
    local CreateNumericField = LGB.CreateNumericField

    local protocolOptions = {
        isRelevantInCombat = true
    }
    local handler = LGB:RegisterHandler("LibGroupPotionCooldowns")
    handler:SetDisplayName("Group Potion Cooldowns")
    handler:SetDescription("Shares potion cooldowns with group members.")

    local protocolCooldown = handler:DeclareProtocol(MESSAGE_ID_COOLDOWN, "Cooldown")
    protocolCooldown:AddField(CreateNumericField("remain", {
        minValue = 0,
        maxValue = 50,
        defaultValue = 0,
        precision = 0.1,
        trimValues = true,
    }))
    protocolCooldown:AddField(CreateNumericField("duration", {
        minValue = 0,
        maxValue = 50,
        defaultValue = 45.0,
        precision = 0.1,
        trimValues = true,
    }))
    protocolCooldown:AddField(CreateNumericField("minDelay", {
        minValue = 0,
        maxValue = 2000,
        defaultValue = 0,
        trimValues = true,
    }))
    protocolCooldown:OnData(onMessageCooldownUpdateReceived)
    protocolCooldown:Finalize(protocolOptions)

    _LGBHandler = handler
    _LGBProtocols[MESSAGE_ID_COOLDOWN] = protocolCooldown
end


--- register the addon
EM:RegisterForEvent(lib_name, EVENT_ADD_ON_LOADED, function(_, name)
    if name ~= lib_name then return end
    EM:UnregisterForEvent(lib_name, EVENT_ADD_ON_LOADED)

    --LGB = LibGroupBroadcast:SetupMockInstance()
    --LGB_MOCK = LGB
    declareLGBProtocols()

    -- register onPlayerActivated callback
    EM:UnregisterForEvent(lib_name, EVENT_PLAYER_ACTIVATED)
    EM:RegisterForEvent(lib_name, EVENT_PLAYER_ACTIVATED, onPlayerActivated)
    Log("main", LOG_LEVEL_DEBUG, "Library initialized")
end)

local function lgpc_version()
    d(lib_version)
end

local function lgpc_test()
    lib_debug = true
    lib.groupStats = groupStats
    local instance = lib.RegisterAddon("LibGroupPotionCooldownsTest")
    if not instance then
        Log("debug", LOG_LEVEL_ERROR, "registration of LibGroupPotionCooldownsTest failed")
        return
    end

    local function logEvent(eventName)
        LocalEM:RegisterCallback(eventName, function(unitTag, data)
            Log("event", LOG_LEVEL_INFO, eventName, unitTag, data )
        end)
    end

    logEvent(EVENT_PLAYER_COOLDOWN_UPDATE)
    logEvent(EVENT_GROUP_COOLDOWN_UPDATE)
end

local function slashCommands(str)
    if str == "version" then lgpc_version()
    elseif str == "test" then lgpc_test() end
end

SLASH_COMMANDS["/LibGroupPotionCooldowns"] = slashCommands
SLASH_COMMANDS["/lgpc"] = slashCommands