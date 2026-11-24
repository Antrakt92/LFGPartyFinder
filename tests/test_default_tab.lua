-- Run with Lua 5.1 and pass the addon directory as the first argument.
local fixturePath = (arg[0]:match("^(.*[/\\])") or "") .. "window_fixture.lua"
local addon, frames = assert(loadfile(fixturePath))(arg[1] or ".")

local function visibleButton(label)
    for _, frame in ipairs(frames) do
        if frame.kind == "Button" and frame.label == label and frame:IsVisible() then return frame end
    end
end

LFGParentFrame:Hide()
LFGVanilla_ToggleFrame(1) -- Blizzard TOGGLEGROUPFINDER binding.
assert(LFGParentFrame:IsShown() and visibleButton("Players"), "normal Group Finder toggle opens Party Finder")
local players = visibleButton("Players")
local addonPanel = players.parent.parent
assert(players.TOPLEFT[1] == 12, "the tabs span the panel even when a native portrait exists")
assert(LFGParentFramePortrait:GetFrameStrata() == "HIGH" and LFGParentFramePortrait:GetFrameLevel() == 4,
    "the native portrait keeps its own layer")
LFGVanilla_ToggleFrame(1)
assert(not LFGParentFrame:IsShown() and not visibleButton("Players"), "same key closes the native window")
assert(LFGParentFramePortrait:GetFrameStrata() == "HIGH" and LFGParentFramePortrait:GetFrameLevel() == 4,
    "closing the embedded window preserves the native portrait")

-- Some client layouts keep the native eye hidden, with the full header available.
LFGParentFramePortrait:Hide()
LFGVanilla_ToggleFrame(1)
local groups, settings = visibleButton("Groups"), visibleButton("Settings")
assert(players.TOPLEFT[1] == 12, "a hidden portrait leaves no blank space before the tabs")
assert(players.width == groups.width and groups.width == settings.width)
assert(groups.TOPLEFT[1] - (players.TOPLEFT[1] + players.width) == 8)
assert(math.abs(settings.TOPLEFT[1] + settings.width - (454 - 12)) < 0.01)
addonPanel:SetWidth(484)
addonPanel.scripts.OnSizeChanged(addonPanel)
assert(math.abs(settings.TOPLEFT[1] + settings.width - (484 - 12)) < 0.01, "tabs follow the panel width")
addonPanel:SetWidth(454)
LFGVanilla_ToggleFrame(1)
LFGParentFramePortrait:Show()

LFGVanilla_ToggleFrame(3)
assert(LFGParentFrame:IsShown() and not visibleButton("Players") and LFGParentFrame.selectedTab == 3)
LFGVanilla_ToggleFrame(1)
assert(visibleButton("Players") and LFGParentFrame.selectedTab == 1)
LFGVanilla_ToggleFrame(2)
assert(LFGParentFrame:IsShown() and not visibleButton("Players") and LFGParentFrame.selectedTab == 2)

LFGVanilla_ToggleFrame(1)
assert(visibleButton("Players"))
LFGVanilla_ShowFrame(2) -- LFG_LIST_SHOW_SEARCH goes through this path directly.
assert(LFGParentFrame:IsShown() and not visibleButton("Players") and LFGParentFrame.selectedTab == 2)

LFGVanilla_ToggleFrame(1)
assert(visibleButton("Players"))
-- The native listing event changes its own backing tab while Party Finder remains visible.
LFGParentFrame.selectedTab = 2
LFGVanilla_ToggleFrame(1)
assert(not LFGParentFrame:IsShown() and not visibleButton("Players"), "native tab drift still closes with one key press")

LFGParentFrame:Hide()
addon.openedBefore = nil
addon.Search = function() error("opening Settings must not start the default player search") end
SlashCmdList.PARTYFINDERFOREVER("settings")
assert(LFGParentFrame:IsShown() and visibleButton("Settings") and not visibleButton("Search"))

local function fire(event)
    for _, frame in ipairs(frames) do
        if frame.events and frame.events[event] then frame.scripts.OnEvent(frame, event) end
    end
end
local eligible, searchAttempts = false, 0
local continueSearch
addon.Search = function(canRetry)
    if canRetry then assert(canRetry()); continueSearch = canRetry end
    searchAttempts = searchAttempts + 1
    return eligible
end
visibleButton("Players").scripts.OnClick()
assert(searchAttempts == 1 and not addon.openedBefore)
eligible = true
fire("PLAYER_REGEN_ENABLED")
assert(searchAttempts == 2 and addon.openedBefore)
fire("LFG_LIST_AVAILABILITY_UPDATE")
assert(searchAttempts == 2)

LFGParentFrame:Hide()
assert(not continueSearch() and not addon.openedBefore, "a canceled opening search can run on reopening")
LFGVanilla_ToggleFrame(1)
assert(searchAttempts == 3 and addon.openedBefore)
addon.openedBefore = nil
visibleButton("Search").scripts.OnClick()
assert(searchAttempts == 4 and addon.openedBefore, "a manual search also satisfies first-open search")
print("Passed default Group Finder tab, native close, explicit native tabs, and direct Settings opening")
