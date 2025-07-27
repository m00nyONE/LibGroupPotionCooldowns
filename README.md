# LibGroupPotionCooldowns

**LibGroupPotionCooldowns** is a lightweight library for ESO add-ons that enables group-wide tracking and broadcasting of potion cooldowns. It allows you to monitor the cooldown status of all group members and react accordingly via a simple API.

Dependencies: [LibGroupBroadcast](https://www.esoui.com/downloads/fileinfo.php?id=1337)

## 🚀 Features

* Tracks potion cooldowns for all group members
* Uses `LibGroupBroadcast` to send/receive updates
* Provides event-based and query-based APIs
* Supports add-on registration for safe usage

---

## 📦 Installation

Include this library in your `AddOn.txt` manifest:

```
## DependsOn: LibGroupPotionCooldowns
```

Ensure the following dependencies are also present:

* `LibGroupBroadcast`
* `LibDebugLogger` (optional for debug output)

---

## 🧪 API Overview

### 🔹 Registering Your Add-on

Before using the library, register your add-on:

```lua
local LGPC = LibGroupPotionCooldowns
local potionStats = LGPC.RegisterAddon("MyAddonName")
```

This returns an instance of `_PotionStatsObject`, which you use for querying data or registering callbacks.

Using callbacks is the preferred way of interacting with the Library because it saves a lot of resources.

---

### 🔹 Querying Group Cooldowns

```lua
-- Iterate all group members
for unitTag, data in potionStats:Iterate() do
    d(string.format("%s cooldown: %s", data.name, data.potionData.isOnCooldown))
end

-- Check specific unit
local data = potionStats:GetUnitPotionData("group1")
if data then
    d("Remaining cooldown: " .. potionStats:GetUnitRemainingCooldownMS("group1"))
end
```

---

### 🔹 Listening for Cooldown Updates

You can register for cooldown events:

```lua
local function onCooldownUpdateReceived(unitTag, data)
    d("Cooldown changed for " .. unitTag .. ": " .. data.isOnCooldown)
end

potionStats:RegisterForEvent(LGPC.EVENT_GROUP_COOLDOWN_UPDATE, onCooldownUpdateReceived)
potionStats:RegisterForEvent(LGPC.EVENT_PLAYER_COOLDOWN_UPDATE, onCooldownUpdateReceived)
```

To unregister:

```lua
potionStats:UnregisterForEvent(LGPC.EVENT_GROUP_COOLDOWN_UPDATE, onCooldownUpdateReceived)
```

---

## 🧰 Events

| Event Name                     | Description                                                      |
| ------------------------------ |------------------------------------------------------------------|
| `EVENT_PLAYER_COOLDOWN_UPDATE` | Fired when your own cooldown changes                             |
| `EVENT_GROUP_COOLDOWN_UPDATE`  | Fired when any group member's cooldown changes (except yourself) |

Each event passes two parameters:

* `unitTag` (`string`)
* `potionData` (`table`)

---

## 📖 Data Format

Each unit's potion data includes:

```lua
{
    lastUpdated = 123456789, -- game time in ms of the last update
    isOnCooldown = true, -- 
    cooldownDurationMS = 45000, -- overall cooldown in ms
    hasCooldownUntil = 123459999, -- game time when the unit will have no cooldown anymore
}
```

---

## ✅ Example Use Case

Show a warning icon when someone's potion is on cooldown:

```lua
potionStats:RegisterForEvent(LGPC.EVENT_GROUP_COOLDOWN_UPDATE, function(tag, data)
    if data.isOnCooldown then
        WarningIcon:SetHidden(false)
    else 
        WarningIcon:SetHidden(true)
    end
end)
```

---

## ⚠️ Notes

* Potion cooldown detection is based on `EVENT_INVENTORY_ITEM_USED` and shared via `LibGroupBroadcast`.
* The library tries to calculate the time when the message should arrive by counting in the cooldown of the Broadcast API.
* Cooldown updates are throttled and synchronized to avoid spamming.

---

## 💬 Feedback & Contribution

Feel free to open issues or submit PRs. For questions, contact the author in-game or via GitHub.
