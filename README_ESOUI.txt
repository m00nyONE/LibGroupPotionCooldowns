[size="5"][b]LibGroupPotionCooldowns[/b][/size]

[b]LibGroupPotionCooldowns[/b] is a lightweight library for ESO add-ons that enables group-wide tracking and broadcasting of potion cooldowns. It allows you to monitor the cooldown status of all group members and react accordingly via a simple API.

[i]Dependencies: [url=https://www.esoui.com/downloads/info1337-LibGroupBroadcast.html]LibGroupBroadcast[/url][/i]

[size="4"][b]Features[/b][/size]

[list]
[*]Tracks potion cooldowns for all group members
[*]Uses [b]LibGroupBroadcast[/b] to send/receive updates
[*]Provides event-based and query-based APIs
[*]Supports add-on registration for safe usage
[/list]

[size="4"][b]Usage[/b][/size]

Include this in your [b]AddOn.txt[/b]:

[highlight=lua]
## DependsOn: LibGroupPotionCooldowns
[/highlight]

Make sure the following libraries are installed:

[list]
[*][b]LibGroupBroadcast[/b]
[*][b]LibDebugLogger[/b] (optional for debug output)
[/list]

[size="4"][b]API Overview[/b][/size]

[b] Registering Your Add-on[/b]

[highlight=lua]
local LGPC = LibGroupPotionCooldowns
local potionStats = LGPC.RegisterAddon("MyAddonName")
[/highlight]

Returns a `_PotionStatsObject` to access cooldown data and register callbacks.

[b]Querying Group Cooldowns[/b]

[highlight=lua]
-- Iterate all group members
for unitTag, data in potionStats:Iterate() do
    d(string.format("%s cooldown: %s", data.name, data.potionData.isOnCooldown))
end

-- Check specific unit
local data = potionStats:GetUnitPotionData("group1")
if data then
    d("Remaining cooldown: " .. potionStats:GetUnitRemainingCooldownMS("group1"))
end
[/highlight]

[b]Listening for Cooldown Updates[/b]

[highlight=lua]
local function onCooldownUpdateReceived(unitTag, data)
    d("Cooldown changed for " .. unitTag .. ": " .. data.isOnCooldown)
end

potionStats:RegisterForEvent(LGPC.EVENT_GROUP_COOLDOWN_UPDATE, onCooldownUpdateReceived)
potionStats:RegisterForEvent(LGPC.EVENT_PLAYER_COOLDOWN_UPDATE, onCooldownUpdateReceived)
[/highlight]

To unregister:

[highlight=lua]
potionStats:UnregisterForEvent(LGPC.EVENT_GROUP_COOLDOWN_UPDATE, onCooldownUpdateReceived)
[/highlight]

[size="4"][b]Events[/b][/size]

[b]Available Events:[/b]

[list]
[*][b]EVENT_PLAYER_COOLDOWN_UPDATE[/b] Fired when your own cooldown changes
[*][b]EVENT_GROUP_COOLDOWN_UPDATE[/b] Fired when any group member's cooldown changes
[/list]

Each callback receives:

[list]
[*][b]string[/b] unitTag
[*][b]table[/b] potionData
[/list]

[size="4"][b]Data Format[/b][/size]

Each potion data table includes:

[highlight=lua]
{
    lastUpdated = 123456789, -- game time in ms of the last update
    isOnCooldown = true, --
    cooldownDurationMS = 45000, -- overall cooldown in ms
    hasCooldownUntil = 123459999, -- game time when the unit will have no cooldown anymore
}
[/highlight]

[size="4"][b]Example Use Case[/b][/size]

Show a warning icon when a healer's potion is on cooldown:

[highlight=lua]
potionStats:RegisterForEvent(LGPC.EVENT_GROUP_COOLDOWN_UPDATE, function(tag, data)
    if data.isOnCooldown then
        WarningIcon:SetHidden(false)
    else
        WarningIcon:SetHidden(true)
    end
end)
[/highlight]

[size="4"][b]Notes[/b][/size]

[list]
[*]Potion cooldowns are detected via [b]EVENT_INVENTORY_ITEM_USED[/b]
[*]Updates are broadcast via [b]LibGroupBroadcast[/b]
[*]The library tries to calculate the time when the message should arrive by counting in the cooldown of the Broadcast API.
[*]Cooldown messages are throttled and synchronized to reduce spam
[/list]

[size="4"][b] Feedback & Contribution[/b][/size]

For issues or feature requests, feel free to submit them on [url=https://github.com/m00nyONE/LibGroupPotionCooldowns]GitHub[/url].