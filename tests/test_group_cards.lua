-- Run with Lua 5.1 and pass the addon directory as the first argument.
local fixturePath = (arg[0]:match("^(.*[/\\])") or "") .. "window_fixture.lua"
local addon, frames, _, events, search = assert(loadfile(fixturePath))(arg[1] or ".")

local function find(kind, label)
    for _, frame in ipairs(frames) do
        if frame.kind == kind and frame.label == label and frame:IsVisible() then return frame end
    end
    error("Missing " .. label)
end

local scroll
for _, frame in ipairs(frames) do
    if frame.kind == "ScrollFrame" then scroll = frame end
end
local panel = assert(scroll).parent
panel:SetSize(454, 507)
RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    DRUID = { r = 1, g = 0.49, b = 0.04 },
    MAGE = { r = 0.25, g = 0.78, b = 0.92 },
}
function UnitFactionGroup() return "Horde" end
C_LFGList.Search = function() end
C_LFGList.GetFilteredSearchResults = function() return 2, { 1, 2 } end
C_LFGList.GetSearchResultInfo = function(id)
    return { leaderName = id == 1 and "Leader" or "Other group", numMembers = 4, activityIDs = { 1 },
        hasSelf = false, isDelisted = false }
end
C_LFGList.GetSearchResultLeaderInfo = function()
    return { classFilename = "MAGE", lfgRoles = { dps = true } }
end
local roster = {
    { name = "Leader", classFilename = "MAGE", className = "Mage", assignedRole = "DAMAGER", isLeader = true },
    { name = "Second mage", classFilename = "MAGE", className = "Mage", assignedRole = "DAMAGER" },
    { name = "Tank friend", classFilename = "WARRIOR", className = "Warrior", assignedRole = "TANK" },
    { name = "Healer friend", classFilename = "DRUID", className = "Druid", specName = "Restoration", assignedRole = "HEALER" },
}
C_LFGList.GetSearchResultPlayerInfo = function(id, index) if id == 1 then return roster[index] end end
local classCountsAvailable = true
C_LFGList.GetSearchResultMemberCounts = function(id)
    if id == 1 then
        return { TANK = 1, HEALER = 1, DAMAGER = 2, TANK_REMAINING = 0, HEALER_REMAINING = 0,
            DAMAGER_REMAINING = 1, WARRIOR = 1, DRUID = 1, MAGE = 2 }
    end
    return { TANK = 1, DAMAGER = 2, HEALER_REMAINING = 1, WARRIOR = 1, ROGUE = classCountsAvailable and 3 or nil }
end
search()
events.scripts.OnEvent(events, "LFG_LIST_SEARCH_RESULTS_RECEIVED")
assert(addon.db.fitsMe == true and find("Button", "Groups (1)"), "the default filter applies to the results counter")
find("Button", "Groups (1)").scripts.OnClick()
local room = find("Button", "Fits me")
assert(room.tick:IsVisible() and find("FontString", "Leader"), "the enabled filter is visible on the button")
room.scripts.OnClick()
assert(addon.db.fitsMe == false and not room.tick:IsVisible() and find("Button", "Groups (2)"))
local first = find("FontString", "Leader").parent
local second = find("FontString", "Other group").parent
if first.TOPLEFT[1] ~= 0 then first, second = second, first end
assert(first.width == second.width and second.TOPLEFT[1] - first.width == 4)
assert(scroll.TOPLEFT[1] == 12 and scroll.BOTTOMRIGHT[1] == -12, "a short list has equal side margins")
assert(first.width == 213 and second.TOPLEFT[1] + second.width == 430)
local shortList = addon.groups
addon.groups = {}
for index = 1, 11 do addon.groups[index] = shortList[(index - 1) % 2 + 1] end
addon.Refresh()
assert(scroll.BOTTOMRIGHT[1] == -24 and first.width == 207, "an overflowing list makes room for the scrollbar")
addon.groups = shortList
addon.Refresh()
assert(scroll.BOTTOMRIGHT[1] == -12 and first.width == 213, "shrinking the list reclaims the scrollbar space")
local nativeFont = GameFontHighlightSmall
addon.groups = {}
for index = 1, 8 do addon.groups[index] = shortList[(index - 1) % 2 + 1] end
addon.Refresh()
assert(scroll.BOTTOMRIGHT[1] == -12, "four rows fit with the default font height")
GameFontHighlightSmall = { GetFont = function() return "Fonts\\ARKai_T.ttf", 15 end }
addon.Refresh()
assert(first.height == 93 and first.action.height == first.height - 2 and scroll.BOTTOMRIGHT[1] == -24,
    "a taller localized font enlarges the recycled cards and the scroll content")
assert(first.dungeon.TOPLEFT[2] - first.zone.TOPLEFT[2] >= 15
    and first.zone.TOPLEFT[2] - first.members[1].TOPLEFT[2] >= 15,
    "localized dungeon and zone rows clear the roster")
GameFontHighlightSmall = nativeFont
addon.groups = shortList
addon.Refresh()
assert(first.height == 78 and scroll.BOTTOMRIGHT[1] == -12)
panel:SetWidth(466)
panel.scripts.OnSizeChanged(panel)
assert(first.width == 219 and second.TOPLEFT[1] + second.width == 442)

local detailed = find("FontString", "Leader").parent
local anonymous = find("FontString", "Other group").parent
assert(detailed.action:IsVisible() and detailed.action:GetText() == "+", "groups use the same plus action as player cards")
local actedOn
addon.Act = function(entry) actedOn = entry end
detailed.action.scripts.OnMouseDown(detailed.action, "LeftButton")
detailed.action.scripts.OnClick(detailed.action, "LeftButton")
assert(actedOn == detailed.entry)
local slots = detailed.members
local expectedRoles = { 1, 2, 3, 3 }
local expectedClasses = { "WARRIOR", "DRUID", "MAGE", "MAGE" }
for index, class in ipairs(expectedClasses) do
    local slot = slots[index]
    assert(slot.roleIcon.atlas == addon.roles[expectedRoles[index]].icon and slot.roleIcon.width == 23)
    assert(slot.TOPLEFT[2] == -47 and (index == 1 or slot.TOPLEFT[1] == slots[index - 1].TOPLEFT[1] + 27),
        "member slots share one evenly spaced row")
    assert(slot.roleIcon.desaturated == false and slot.classBar:IsVisible() and slot.classBar.height == 3 and slot.classBar.width == 16)
    local red, green, blue = unpack(slot.classBar.textureColor)
    local color = RAID_CLASS_COLORS[class]
    assert(red == color.r and green == color.g and blue == color.b)
end
assert(detailed.dungeon.TOPLEFT[2] > detailed.zone.TOPLEFT[2]
    and detailed.zone.TOPLEFT[2] - 10 > slots[1].TOPLEFT[2]
    and -slots[1].TOPLEFT[2] + slots[1].height < detailed.height,
    "dungeon and zone rows have space above the roster")
assert(slots[5].roleIcon:IsVisible() and slots[5].roleIcon.desaturated and not slots[5].classBar:IsVisible()
    and slots[5].roleIcon.atlas == addon.roles[3].icon, "confirmed damage vacancy stays in its assigned slot")
local entry = detailed.entry
local count, members, dungeons, rosterSlots = entry.count, entry.members, entry.listedDungeons, entry.rosterSlots
entry.count = 6
entry.members = { members[1], members[2], members[3], members[4], {}, {} }
entry.rosterSlots = nil
entry.listedDungeons = { dungeons[1], { name = "Razorfen Kraul" } }
entry.playstyle = "Learning"
entry.comment = "First run"
addon.Refresh()
assert(detailed.dungeon.width >= 150 and detailed.extraDungeons:GetText() == "+1",
    "roster overflow does not shrink the multi-dungeon name")
assert(detailed.dungeon.TOPLEFT[2] == detailed.extraDungeons.TOPRIGHT[2])
assert(detailed.action.height == detailed.height - 2)
assert(detailed.memberOverflow:GetText() == "+1", "overflow leaves a compact count beside the roster")
assert(detailed.playstyle:GetText() == "Learning" and detailed.playstyle:IsVisible() and not anonymous.playstyle:IsVisible())
assert(detailed.name.TOPLEFT[1] + detailed.name.width < detailed.width + detailed.playstyle.TOPRIGHT[1] - detailed.playstyle.width
    and detailed.playstyle.TOPRIGHT[1] < detailed.commentMark.TOPRIGHT[1], "title, playstyle, and comment each have their own space")
entry.count, entry.members, entry.listedDungeons, entry.rosterSlots = count, members, dungeons, rosterSlots
entry.playstyle, entry.comment = nil, nil
addon.Refresh()
assert(slots[5].roleIcon.desaturated and not detailed.playstyle:IsVisible() and detailed.memberOverflow:GetText() == "")
assert(anonymous.members[1].roleIcon.atlas == addon.roles[1].icon and not anonymous.members[1].classBar:IsVisible())
assert(anonymous.members[4].unknownRole:IsVisible() and not anonymous.members[4].roleIcon:IsVisible()
    and not anonymous.members[5]:IsVisible(), "an incomplete roster does not claim a vacancy")
entry.rosterSlots = { rosterSlots[1], rosterSlots[2], rosterSlots[3], rosterSlots[4], { role = 3, class = "MAGE" } }
addon.Refresh()
assert(not slots[5].roleIcon.desaturated and slots[5].classBar:IsVisible(), "reusing a slot clears its vacant treatment")
entry.rosterSlots = rosterSlots
addon.Refresh()

local tooltip = {}
GameTooltip = { GetOwner = function() end, SetOwner = function() end, SetText = function() end, Show = function() end,
    AddLine = function(_, line) tooltip[#tooltip + 1] = line end }
detailed.scripts.OnEnter(detailed)
local lines = table.concat(tooltip, "\n")
assert(lines:find("Tank · Tank friend · Warrior", 1, true))
assert(lines:find("Healer · Healer friend · Druid · Restoration", 1, true))
assert(lines:find("Damage · Leader · Mage (leader)", 1, true))
detailed.action.scripts.OnEnter(detailed.action)
assert(tooltip[#tooltip] == "Ask to Join")

C_LFGList.GetSearchResultPlayerInfo = function() end
search()
events.scripts.OnEvent(events, "LFG_LIST_SEARCH_RESULTS_RECEIVED")
assert(not slots[1].classBar:IsVisible() and slots[1].roleIcon:IsVisible(), "refresh clears old class colors")
local filterRow = find("FontString", "Has roles").parent
local tank, healer
for _, frame in ipairs(frames) do
    if frame.parent == filterRow and frame.kind == "CheckButton" then
        if not tank then tank = frame
        elseif not healer then healer = frame end
    end
end
local function check(button, checked)
    button:SetChecked(checked)
    button.scripts.OnClick(button)
end
check(healer, true)
assert(find("Button", "Groups (1)") and find("FontString", "Leader"))
check(tank, true)
assert(find("Button", "Groups (2)") and detailed:IsVisible() and anonymous:IsVisible())
room.scripts.OnClick()
assert(find("Button", "Groups (1)") and find("FontString", "Leader"))
addon.SetListingRole("healer", true)
addon.SetListingRole("dps", false)
assert(find("Button", "Groups (1)") and find("FontString", "Other group"))
check(tank, false)
assert(find("Button", "Groups (0)") and find("FontString", "No groups match your filters."))
find("Button", "Players (0)").scripts.OnClick()
assert(not filterRow:IsVisible() and find("FontString", "Find roles"))
find("Button", "Groups (0)").scripts.OnClick()
assert(filterRow:IsVisible() and room.tick:IsVisible() and healer:GetChecked())
room.scripts.OnClick()
check(healer, false)
local classChecks = {}
for _, frame in ipairs(frames) do
    if frame.kind == "CheckButton" and frame.icon then
        local class = frame.icon.atlas:match("^groupfinder%-icon%-class%-(.+)$")
        if class then
            assert(frame:GetChecked() and frame:IsVisible(), "all classes are included by default")
            classChecks[class] = frame
        end
    end
end
local mage, priest = assert(classChecks.mage), assert(classChecks.priest)
check(mage, false)
check(priest, false)
assert(find("Button", "Groups (1)") and find("FontString", "Other group"))
assert(not mage:GetChecked() and not priest:GetChecked())
classCountsAvailable = false
search()
events.scripts.OnEvent(events, "LFG_LIST_SEARCH_RESULTS_RECEIVED")
assert(find("Button", "Groups (0)"), "a partial class count cannot confirm the group has none of the excluded classes")
assert(find("FontString", "No groups match your filters."))
local resetFilters = find("Button", "Reset filters")
local selections, searchLanguages = addon.db.activities, addon.db.searchLanguages
local combat = true
function InCombatLockdown() return combat end
search()
combat = false
addon.Refresh()
local combatStatus = find("FontString", "Finish combat before searching.")
assert(resetFilters:IsVisible(), "groups can reset filters while a blocked search leaves a status")
assert(combatStatus.TOPRIGHT[1] == resetFilters and combatStatus.TOPRIGHT[2] == "TOPLEFT"
    and combatStatus.TOPRIGHT[3] < 0, "the status text has a gap before the visible action")
room.scripts.OnClick()
check(healer, true)
resetFilters.scripts.OnClick()
assert(find("Button", "Groups (2)") and not resetFilters:IsVisible())
assert(combatStatus:GetText() == "Finish combat before searching." and combatStatus.TOPRIGHT[1] == -65,
    "reset preserves the search status and restores its usual width")
assert(not room.tick:IsVisible() and not healer:GetChecked())
assert(not next(addon.db.excludedClasses) and mage:GetChecked() and priest:GetChecked())
assert(addon.db.activities == selections and addon.db.searchLanguages == searchLanguages)
check(mage, false)
check(priest, false)

local damageRole = { tank = false, healer = false, dps = true }
addon.players = {
    { id = 50, name = "Solo mage", count = 1, class = "MAGE", roles = damageRole },
    { id = 51, name = "Solo priest", count = 1, class = "PRIEST", roles = damageRole },
    { id = 52, name = "Solo rogue", count = 1, class = "ROGUE", roles = damageRole },
}
addon.Refresh()
find("Button", "Players (1)").scripts.OnClick()
assert(mage:IsVisible() and not mage:GetChecked() and not priest:GetChecked() and find("FontString", "Solo rogue"))
addon.InitializeSettings()
assert(addon.db.excludedClasses.MAGE and addon.db.excludedClasses.PRIEST)
check(mage, true)
assert(find("Button", "Players (2)") and find("FontString", "Solo mage"))
local playerRoleFilter = find("FontString", "Find roles").parent
local playerRoleCheck
for _, frame in ipairs(frames) do
    if frame.parent == playerRoleFilter and frame.icon and frame.icon.atlas == addon.roles[1].icon then
        playerRoleCheck = frame
        break
    end
end
check(assert(playerRoleCheck), true)
assert(find("Button", "Players (0)") and resetFilters:IsVisible())
resetFilters.scripts.OnClick()
assert(find("Button", "Players (3)") and not resetFilters:IsVisible())
assert(not playerRoleCheck:GetChecked() and priest:GetChecked() and not next(addon.db.excludedClasses))
assert(combatStatus:GetText() == "Finish combat before searching.")
local players = addon.players
addon.players = nil
addon.Refresh()
assert(find("Button", "Groups (2)") and not resetFilters:IsVisible(),
    "another view's existing results do not offer a reset before this view has results")
addon.players = players
local languages = find("DropdownButton", "Languages")
languages:OpenMenu()
local localeRows = {}
for index, option in ipairs(languages.options) do
    if option.id then localeRows[option.id] = index end
end
assert(#languages.options == 12 and languages.options[1].selected())
languages:PickOption(localeRows.ruRU)
assert(addon.db.searchLanguages.ruRU and find("DropdownButton", "RU") == languages)
languages:PickOption(localeRows.enUS)
assert(addon.db.searchLanguages.enUS and find("DropdownButton", "EN · RU") == languages)
languages:PickOption(localeRows.esMX)
assert(find("DropdownButton", "3 selected") == languages)
languages:PickOption(localeRows.ruRU)
languages:PickOption(localeRows.enUS)
assert(find("DropdownButton", "ES-MX") == languages)
languages:PickOption(1)
assert(not next(addon.db.searchLanguages) and find("DropdownButton", "Languages") == languages)
print("Passed group layout, roster and filters, shared class exclusions, and result counts")
