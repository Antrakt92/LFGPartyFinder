-- Run with Lua 5.1 and pass the addon directory as the first argument.
local fixturePath = (arg[0]:match("^(.*[/\\])") or "") .. "window_fixture.lua"
local addon, frames, deferred = assert(loadfile(fixturePath))(arg[1] or ".")

local dropdown
for _, frame in ipairs(frames) do
    if frame.kind == "DropdownButton" then dropdown = frame; break end
end
assert(dropdown and dropdown:IsVisible())

assert(#addon.SelectedActivities() == 1 and not addon.db.manualDungeonSelection)
addon.SetAutomaticDungeonSelection(false)
assert(addon.db.manualDungeonSelection and #addon.SelectedActivities() == 0 and dropdown.label == "Choose dungeons")
addon.InitializeSettings()
assert(#addon.SelectedActivities() == 0 and not next(addon.db.activities), "reload must not restore an automatic selection")
addon.ToggleActivity(2)
addon.SetAutomaticDungeonSelection(true)
assert(addon.SelectedActivities()[1].id == 1)
addon.SetAutomaticDungeonSelection(false)
assert(addon.SelectedActivities()[1].id == 2, "turning auto off restores the manual choice")
addon.db.activities = {}
addon.SetAutomaticDungeonSelection(true)

local function assertOrder(expected)
    assert(dropdown.options[1].label == "Show all levels" and dropdown.options[1].ignored)
    assert(dropdown.dividerAfter == 1 and #dropdown.options == #expected + 1)
    for index, id in ipairs(expected) do assert(dropdown.options[index + 1].id == id) end
end

local function switchLevelMode()
    dropdown:PickOption(1)
    assert(not dropdown:IsMenuOpen() and #deferred == 1)
    table.remove(deferred, 1)()
    assert(dropdown:IsMenuOpen() and dropdown.menuOffset == 0)
end

dropdown:OpenMenu()
assertOrder({ 1, 2, 3 })
switchLevelMode()
assertOrder({ 5, 1, 2, 3, 4 })
assert(dropdown.options[1].selected())
local fullMenu = dropdown.options
dropdown.menuOffset = 2
dropdown:PickOption(4)
dropdown:PickOption(5)
assert(dropdown.options == fullMenu and dropdown.menuOffset == 2 and #deferred == 0)
assertOrder({ 5, 1, 2, 3, 4 })
assert(dropdown.label == "Scarlet Graveyard +2")
assert(dropdown.options[3].selected(1) and dropdown.options[4].selected(2) and dropdown.options[5].selected(3))
switchLevelMode()
assertOrder({ 1, 2, 3 })
assert(not dropdown.options[1].selected() and dropdown.label == "Scarlet Graveyard +2")
switchLevelMode()
assertOrder({ 5, 1, 2, 3, 4 })
dropdown:PickOption(6)
assert(dropdown.options[6].selected(4))
switchLevelMode()
assert(not dropdown.options[1].selected() and addon.db.activities[4] and #addon.SelectedActivities() == 3)
switchLevelMode()
assert(dropdown.options[6].selected(4) and #addon.SelectedActivities() == 4)
dropdown:PickOption(1)
LFGParentFrame:Hide()
table.remove(deferred, 1)()
assert(not dropdown:IsMenuOpen(), "do not reopen after the parent closes")

LFGVanilla_ToggleFrame(1)
dropdown:OpenMenu()
dropdown:PickOption(1)
local groups
for _, frame in ipairs(frames) do
    if frame.kind == "Button" and frame:IsVisible() and frame.label:match("^Groups") then groups = frame; break end
end
assert(groups).scripts.OnClick()
table.remove(deferred, 1)()
assert(dropdown:IsVisible() and not dropdown:IsMenuOpen(), "a deferred menu cannot cross tabs")

dropdown:OpenMenu()
dropdown:PickOption(1)
LFGParentFrame:Hide()
SlashCmdList.PARTYFINDERFOREVER()
table.remove(deferred, 1)()
assert(dropdown:IsVisible() and not dropdown:IsMenuOpen(), "a deferred menu cannot cross a close and reopen")
print("Passed activity menu order, in-place dungeon checks, level changes and cancellation")
