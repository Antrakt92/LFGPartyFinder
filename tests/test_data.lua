-- Run with Lua 5.1 and pass the addon directory as the first argument.
local addon = {}
local restricted = {}
function canaccessvalue(value) return value ~= restricted end
assert(loadfile((arg[1] or ".") .. "/Data.lua"))("PartyFinderForever", addon)

local maps = {
    [1420] = "Tirisfal Glades", [1426] = "Dun Morogh", [1427] = "Searing Gorge", [1428] = "Burning Steppes",
    [1416] = "Alterac Mountains", [1421] = "Silverpine Forest", [1437] = "Wetlands", [1455] = "Ironforge",
}
local instances = {
    [90] = "Gnomeregan", [189] = "Scarlet Monastery", [229] = "Blackrock Spire",
    [2959] = "City of Dalaran", [2998] = "Excavation Site: Wetlands", [3065] = "Hall of Thanes",
}
C_Map = {
    GetMapInfo = function(id) return maps[id] and { name = maps[id] } end,
    GetAreaInfo = function(id) return ({ [25] = "Blackrock Mountain", [35] = "Booty Bay" })[id] end,
}
function GetRealZoneText(id) return instances[id] end

local function zones(id, name, faction)
    return addon.ActivityZones({ mapID = id, fullName = name }, faction)
end
local horde = zones(90, "Gnomeregan", "Horde")
assert(horde.Gnomeregan == 1 and horde["Dun Morogh"] == 2 and horde["Booty Bay"] == 3)
assert(zones(90, "Gnomeregan", "Alliance")["Booty Bay"] == nil)
local spire = zones(229, "Lower Blackrock Spire")
assert(spire["Lower Blackrock Spire"] == 1 and spire["Blackrock Spire"] == 1)
assert(spire["Blackrock Mountain"] == 2 and spire["Searing Gorge"] == 2 and spire["Burning Steppes"] == 2)
assert(zones(2959, "City of Dalaran")["Alterac Mountains"] == 2)
assert(zones(2998, "Excavation Site: Wetlands").Wetlands == 2)
assert(zones(3065, "Hall of Thanes").Ironforge == 2)
assert(zones(restricted, "An unknown dungeon")["An unknown dungeon"] == 1)

local selected = { [1] = { zones = zones(189, "Scarlet Graveyard") }, [2] = { zones = horde } }
local rank, matches = addon.Proximity({ 2, restricted, 1 }, "Scarlet Monastery", selected)
assert(matches and rank == 1, "an instance counts even when the listing contains multiple dungeons")
rank, matches = addon.Proximity({ 1 }, "Booty Bay", selected)
assert(matches and rank == nil, "proximity only considers the dungeons on that player's listing")
rank, matches = addon.Proximity({ 999, restricted }, "Booty Bay", selected)
assert(not matches and rank == nil)

local players = {
    { id = 1, name = "Zed", class = "SHAMAN", rank = 2, roles = { healer = true } },
    { id = 2, name = "Ana", class = "SHAMAN", rank = 1, roles = { healer = true } },
    { id = 3, name = "Dax", class = "SHAMAN", rank = 1, roles = { dps = true, healer = false } },
    { id = 4, name = "Bo", class = "SHAMAN", roles = { healer = true } },
    { id = 5, name = "Mia", class = "UNRECOGNIZED" },
    { id = 6, name = "Kai", class = "DRUID", roles = { dps = true } },
}
local nearby, others = addon.GroupPlayers(players, { healer = true })
assert(#nearby.SHAMAN == 2 and nearby.SHAMAN[1].id == 2 and nearby.SHAMAN[2].id == 1)
assert(#others.SHAMAN == 1 and others.SHAMAN[1].id == 4)
assert(#others.UNKNOWN == 1 and others.UNKNOWN[1].id == 5)
assert(others.DRUID and #others.DRUID == 1 and others.DRUID[1].id == 6, "unknown healing role stays visible")
assert(addon.Read(restricted, "table") == nil and addon.Read(0 / 0, "number") == nil)
assert(addon.Read(math.huge, "number") == nil and addon.Read(false, "boolean") == false)
print("Passed faction-specific proximity, multiple activities, class ordering and restricted values")
