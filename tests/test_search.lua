-- Run with Lua 5.1 and pass the addon directory as the first argument.
local root = arg[1] or "."
local addon = {}
local requests, timers, visibleIDs, results = {}, {}, {}, {}
local level, combat, clock = 32, false, 0
local searchRejected, searchFailedInline = false, false
local activities = {
    [10] = { shortName = "", groupFinderActivityGroupID = 0, orderIndex = 0, fullName = "Eligible dungeon", minLevelSuggestion = 20, maxLevelSuggestion = 60, maxNumPlayers = 5 },
    [20] = { shortName = "", groupFinderActivityGroupID = 0, orderIndex = 0, fullName = "Higher dungeon", minLevelSuggestion = 33, maxLevelSuggestion = 60 },
    [30] = { shortName = "", groupFinderActivityGroupID = 0, orderIndex = 0, fullName = "Lower dungeon", minLevelSuggestion = 20, maxLevelSuggestion = 32 },
}

function canaccessvalue() return true end
function UnitLevel() return level end
function UnitFactionGroup() return "Horde" end
function InCombatLockdown() return combat end
function strcmputf8i(a, b)
    a, b = a:lower(), b:lower()
    return a == b and 0 or (a < b and -1 or 1)
end
function hooksecurefunc(owner, method, hook)
    local original = assert(owner[method])
    owner[method] = function(...)
        local result = original(...)
        hook(...)
        return result
    end
end

local events = { registered = {} }
function events:RegisterEvent(event) self.registered[event] = true end
function events:SetScript(_, handler) self.handler = handler end
function CreateFrame() return events end
local function fire(event, ...)
    assert(events.registered[event])
    events.handler(events, event, ...)
end

C_Timer = { After = function(delay, callback) timers[#timers + 1] = { clock + delay, callback } end }
local function advance(seconds)
    local untilTime = clock + seconds
    while true do
        local nextTimer
        for index, timer in ipairs(timers) do
            if timer[1] <= untilTime and (not nextTimer or timer[1] < timers[nextTimer][1]) then nextTimer = index end
        end
        if not nextTimer then break end
        local timer = table.remove(timers, nextTimer)
        clock = timer[1]
        timer[2]()
    end
    clock = untilTime
end

C_LFGList = {
    GetAvailableActivities = function() return { 10, 20, 30 } end,
    GetActivityInfoTable = function(id) return activities[id] end,
    GetActiveEntryInfo = function() end,
    HasActiveEntryInfo = function() return false end,
    GetFilteredSearchResults = function() return #visibleIDs, visibleIDs end,
    GetSearchResultInfo = function(id) return results[id] end,
    GetSearchResultPlayerInfo = function() return { classFilename = "MAGE" } end,
    Search = function(category, _, _, languages, _, _, ids)
        requests[#requests + 1] = { category = category, ids = ids, languages = languages }
        if searchRejected then return false end
        if searchFailedInline then fire("LFG_LIST_SEARCH_FAILED") end
    end,
}

for _, name in ipairs({ "Data", "Finder" }) do
    assert(loadfile(root .. "/" .. name .. ".lua"))("PartyFinderForever", addon)
end

local function selectDungeons(...)
    local selected = {}
    for _, id in ipairs({...}) do selected[id] = true end
    addon.db.manualDungeonSelection = true
    addon.db.activities = selected
    addon.SelectionChanged()
end

local function result(id, name, ...)
    results[id] = { numMembers = 1, leaderName = name, activityIDs = {...}, isDelisted = false, hasSelf = false }
end

local function receive(...)
    visibleIDs = {...}
    fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")
end

PartyFinderForeverDB = { manualDungeonSelection = "false", activities = { [10] = false, [20] = true, ["30"] = true } }
addon.InitializeSettings()
assert(addon.db.manualDungeonSelection == nil and addon.db.activities[20] == true)
assert(next(addon.db.activities) == 20 and next(addon.db.activities, 20) == nil)
assert(addon.db.fitsMe == true, "Fits me defaults to enabled for an existing profile without the preference")
addon.db.fitsMe = false
addon.InitializeSettings()
assert(addon.db.fitsMe == false, "Fits me remembers an explicitly disabled preference")

selectDungeons(10, 20)
result(1, "Original", 10)
result(2, "Different activity", 30)
result(3, "Matching but foreign", 10)
result(4, "New selection", 20)
result(5, "Unknown ownership", 10)
results[5].hasSelf = nil
result(6, "Unknown activity", 10)
results[6].activityIDs = nil
result(7, "Unknown listing state", 10)
results[7].isDelisted = nil
assert(addon.Search() and requests[#requests].ids[1] == 10 and #requests[#requests].ids == 1)
local languages = requests[#requests].languages
local count = 0
for _, enabled in pairs(languages) do assert(enabled == true); count = count + 1 end
assert(count == 11, "search explicitly requests every available language by default")
receive(1)
assert(#addon.players == 1 and addon.players[1].name == "Original")
addon.db.searchLanguages = { deDE = true, ruRU = true, fake = true }
addon.InitializeSettings()
assert(addon.Search())
languages = requests[#requests].languages
assert(languages.deDE and languages.ruRU and languages.enUS == false and languages.fake == nil)
receive(1)
addon.db.searchLanguages = {}
assert(addon.Search())
receive(1, 5, 6, 7)
assert(#addon.players == 4 and addon.players[1].target == "Original")
for index = 2, 4 do assert(addon.players[index].name and addon.players[index].target == nil) end

level = 33
fire("PLAYER_LEVEL_UP")
assert(#addon.SelectedActivities() == 2 and #addon.players == 0 and addon.status:find("Selection changed", 1, true))
level = 32
selectDungeons(10)
assert(addon.Search())
receive(1)

visibleIDs = {3}
fire("LFG_LIST_SEARCH_RESULT_UPDATED", 3)
advance(0.2)
assert(#addon.players == 1 and addon.players[1].id == 1, "an unowned result-update event must not replace the current rows")
result(1, "Updated", 10)
fire("LFG_LIST_SEARCH_RESULT_UPDATED", 1)
advance(0.2)
assert(#addon.players == 1 and addon.players[1].name == "Updated", "owned rows repaint without reading a different global result list")

C_LFGList.Search(2, 0, 0, nil, false, nil, {30})
assert(#addon.players == 1 and not addon.players[1].target, "previous results can be read while the foreign search owns the cache")
local before = #requests
assert(addon.Search() and #requests == before, "a new click waits for the native search to settle")
receive(2)
advance(0)
assert(#requests == before + 1 and requests[#requests].ids[1] == 10)
receive(2)
assert(#addon.players == 0 and addon.status == "Searching…", "a late response for a different dungeon cannot complete the request")
receive(1)
assert(#addon.players == 1 and addon.players[1].id == 1)

assert(addon.Search())
level = 33
selectDungeons(20)
before = #requests
assert(addon.Search() and #requests == before)
fire("LFG_LIST_SEARCH_FAILED")
advance(0)
assert(#requests == before + 1 and requests[#requests].ids[1] == 20, "a click after changing selections survives a discarded search failure")
receive(4)
assert(#addon.players == 1 and addon.players[1].id == 4)

assert(addon.Search())
selectDungeons(10)
assert(addon.Search())
C_LFGList.Search(2, 0, 0, nil, false, nil, {10})
before = #requests
receive(4)
advance(0)
assert(#requests == before, "the older local reply cannot unblock dispatch while a native reply may still follow")
receive(3)
advance(0)
assert(#requests == before + 1 and requests[#requests].ids[1] == 10, "a native search preserves an explicit queued click")
assert(#addon.players == 0, "the native reply matching the queued dungeon must not become addon results")
receive(1)
assert(addon.players[1].id == 1)

assert(addon.Search())
C_LFGList.Search(2, 0, 0, nil, false, nil, {10})
before = #requests
assert(addon.Search())
receive(3)
advance(0)
assert(#requests == before)
advance(1)
assert(#requests == before + 1, "a native search that superseded the old one cannot block beyond the grace interval")
receive(1)

selectDungeons(20)
assert(addon.Search())
receive(4)
fire("LFG_LIST_SEARCH_RESULT_UPDATED", 4)
selectDungeons(10)
assert(addon.Search())
receive(1)
result(1, "Updated again", 10)
fire("LFG_LIST_SEARCH_RESULT_UPDATED", 1)
advance(0.2)
assert(addon.players[1].name == "Updated again", "a repaint for an old search does not swallow a new search's updates")

local function assertTimedOutSearchDrains(finishOldSearch)
    addon.db.searchLanguages = { enUS = true }
    assert(addon.Search() and requests[#requests].languages.enUS)
    advance(6)
    assert(addon.status:find("No response", 1, true))
    local sent = #requests
    addon.db.searchLanguages = { ruRU = true }
    addon.SelectionChanged()
    assert(addon.Search() and #requests == sent)
    finishOldSearch()
    advance(0)
    assert(#addon.players == 0 and addon.status == "Searching…")
    assert(#requests == sent + 1 and requests[#requests].languages.ruRU)
    receive(1)
    assert(addon.players[1].id == 1)
    advance(1)
    assert(#requests == sent + 1 and addon.players[1].id == 1, "the old drain timer cannot affect a new search")
end

assertTimedOutSearchDrains(function() receive(3) end)
assertTimedOutSearchDrains(function() receive() end)
assertTimedOutSearchDrains(function() fire("LFG_LIST_SEARCH_FAILED") end)

assert(addon.Search())
advance(6)
before = #requests
assert(addon.Search() and #requests == before)
advance(1)
assert(#requests == before + 1, "missing completions delay a queued search only until the drain expires")
receive(1)

assert(addon.Search())
advance(6)
C_LFGList.Search(2, 0, 0, nil, false, nil, {30})
before = #requests
assert(addon.Search())
receive(3)
advance(0)
assert(#requests == before, "one completion cannot release both the native search and the local drain")
receive(2)
advance(0)
assert(#requests == before + 1)
receive(1)
assert(addon.players[1].id == 1)

C_LFGList.Search(2, 0, 0, nil, false, nil, {30})
before = #requests
assert(addon.Search())
advance(6)
assert(#requests == before, "a native timeout starts a drain before the queued search")
fire("LFG_LIST_SEARCH_FAILED")
advance(0)
assert(#requests == before + 1)
receive(1)
assert(addon.players[1].id == 1)

assert(addon.Search())
C_LFGList.Search(2, 0, 0, nil, false, nil, {10})
before = #requests
assert(addon.Search())
advance(6)
fire("LFG_LIST_SEARCH_FAILED")
advance(0)
assert(#requests == before, "an overlapped native timeout can drain two unowned completions in one grace interval")
receive(3)
advance(0)
assert(#requests == before + 1 and #addon.players == 0)
receive(1)
assert(addon.players[1].id == 1)

C_LFGList.Search(2, 0, 0, nil, false, nil, {20})
C_LFGList.Search(2, 0, 0, nil, false, nil, {10})
C_LFGList.Search(2, 0, 0, nil, false, nil, {10})
before = #requests
assert(addon.Search())
receive(4)
advance(0)
assert(#requests == before, "successive native dispatches also leave room for a second completion")
receive(3)
advance(0)
assert(#requests == before + 1, "the unowned completion count remains bounded when multiple native calls overlap")
receive(1)
assert(addon.players[1].id == 1)

before = #requests
assert(addon.Search(function() return true end))
receive()
advance(1)
assert(#requests == before + 2, "an empty opening search retries once")
receive()
advance(1)
assert(#requests == before + 2 and #addon.players == 0 and not addon.status)

local function assertInterruptedOpeningSearch(stage)
    local interruptions = 0
    assert(addon.Search(function() return true end, function() interruptions = interruptions + 1 end))
    if stage ~= "pending" then
        receive()
        assert(addon.status == "Checking for listings…")
    end
    if stage == "retry" then
        advance(1)
        assert(addon.status == "Searching…")
    end
    C_LFGList.Search(2, 0, 0, nil, false, nil, {10})
    local dispatched = #requests
    assert(interruptions == 1, "the window can try its first search on the next open")
    assert(addon.status == "Click Search to refresh.", "an interrupted opening search has no previous rows")
    receive(3)
    advance(1)
    assert(interruptions == 1 and #requests == dispatched and #addon.players == 0,
        "the interrupted opener neither dispatches behind the native view nor adopts its results")
end

assertInterruptedOpeningSearch("pending")
assertInterruptedOpeningSearch("settling")
assertInterruptedOpeningSearch("retry")

local interruptions = 0
assert(addon.Search(function() return true end, function() interruptions = interruptions + 1 end))
fire("LFG_LIST_SEARCH_FAILED")
assert(interruptions == 1, "an asynchronous failure makes the first search eligible on reopen")
assert(addon.Search(function() return true end, function() interruptions = interruptions + 1 end))
advance(6)
assert(interruptions == 2, "a timed-out first search is eligible on reopen")
advance(1)
before = #requests
assert(addon.Search(function() return true end, function() interruptions = interruptions + 1 end))
receive()
advance(1)
assert(#requests == before + 2)
fire("LFG_LIST_SEARCH_FAILED")
assert(interruptions == 3, "failure of the single opening retry also restores opening eligibility")
assert(addon.Search(function() return true end, function() interruptions = interruptions + 1 end))
addon.SelectionChanged()
fire("LFG_LIST_SEARCH_FAILED")
assert(interruptions == 3, "an explicitly changed selection does not become an automatic opening retry")

combat = true
before = #requests
assert(not addon.Search() and #requests == before)
combat = false
searchRejected = true
assert(not addon.Search())
assert(addon.status:find("refused", 1, true))
searchRejected = false
searchFailedInline = true
assert(not addon.Search() and addon.status == "Search failed. Try again.",
    "a failure delivered inside the request must not count as an accepted opening search")
searchFailedInline = false

C_LFGList.Search(2, 0, 0, nil, false, nil, {10})
local sent = #requests
assert(addon.Search(function() return true end) and #requests == sent)
combat = true
receive()
advance(0)
assert(#requests == sent and addon.status == "Search will resume after combat.")
combat = false
fire("PLAYER_REGEN_ENABLED")
advance(0)
assert(#requests == sent + 1, "a queued opening search survives combat")
receive(1)
assert(addon.players[1].id == 1)

local windowOpen = true
C_LFGList.Search(2, 0, 0, nil, false, nil, {10})
sent = #requests
assert(addon.Search(function() return windowOpen end))
combat = true
receive()
advance(0)
windowOpen = false
combat = false
fire("PLAYER_REGEN_ENABLED")
advance(0)
assert(#requests == sent, "closing the window still cancels a queued automatic search")

local getAvailableActivities = C_LFGList.GetAvailableActivities
C_LFGList.GetAvailableActivities = function() return {} end
C_LFGList.Search(2, 0, 0, nil, false, nil, {10})
sent = #requests
local failedOpeningDispatches = 0
assert(addon.Search(function() return true end, function()
    failedOpeningDispatches = failedOpeningDispatches + 1
end))
receive()
advance(0)
assert(#requests == sent and failedOpeningDispatches == 1, "the opener is notified when a queued search could not start")
C_LFGList.GetAvailableActivities = getAvailableActivities
fire("LFG_LIST_AVAILABILITY_UPDATE")
assert(addon.Search() and #requests == sent + 1)
receive(1)

local assignedRoles = {
    [101] = { "DAMAGER", "TANK", "DAMAGER", "DAMAGER" },
    [102] = { "DAMAGER", "TANK", "DAMAGER" },
    [103] = { "TANK", "TANK", "DAMAGER", "DAMAGER" },
    [104] = { "TANK", "DAMAGER", "DAMAGER", "NONE" },
    [105] = { "TANK", "DAMAGER", "DAMAGER", "DAMAGER" },
    [106] = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "DAMAGER" },
}
local roleCounts = {
    [101] = { TANK = 1, HEALER = 0, DAMAGER = 3, TANK_REMAINING = 0, HEALER_REMAINING = 1, DAMAGER_REMAINING = 0 },
    [102] = { TANK = 1, HEALER = 0, DAMAGER = 2, TANK_REMAINING = 0, HEALER_REMAINING = 1, DAMAGER_REMAINING = 1 },
    [103] = { TANK = 2, HEALER = 0, DAMAGER = 2, TANK_REMAINING = 0, HEALER_REMAINING = 1, DAMAGER_REMAINING = 0 },
    [104] = { TANK = 1, HEALER = 0, DAMAGER = 3, TANK_REMAINING = 0, HEALER_REMAINING = 1, DAMAGER_REMAINING = 0 },
    [105] = { TANK = 1, HEALER = 0, DAMAGER = 3, TANK_REMAINING = 0, DAMAGER_REMAINING = 0 },
    [106] = { TANK = 1, HEALER = 1, DAMAGER = 3, TANK_REMAINING = 0, HEALER_REMAINING = 1, DAMAGER_REMAINING = 0 },
}
local originalPlayerInfo = C_LFGList.GetSearchResultPlayerInfo
C_LFGList.GetSearchResultPlayerInfo = function(id, index)
    if not assignedRoles[id] then return originalPlayerInfo(id, index) end
    return { classFilename = "MAGE", assignedRole = assignedRoles[id][index], name = "Member " .. index }
end
C_LFGList.GetSearchResultLeaderInfo = function(id)
    return { areaName = id == 102 and activities[10].fullName or "Elsewhere" }
end
C_LFGList.GetSearchResultMemberCounts = function(id) return roleCounts[id] end
function GetGeneralPlaystyleString(style) return ({ "Learning", "Native relaxed label" })[style] or "" end
for id = 101, 106 do
    result(id, "Group " .. id, 10)
    results[id].numMembers = #assignedRoles[id]
end
results[101].generalPlaystyle, results[102].generalPlaystyle, results[105].generalPlaystyle = 2, 1, 99
assert(addon.Search())
receive(101, 102, 103, 104, 105, 106)
for index, group in ipairs(addon.groups) do
    assert(group.id == index + 100 and not group.rank, "a leader's location does not reorder or rank groups")
end
local first, second = addon.groups[1], addon.groups[2]
assert(first.playstyle == "Native relaxed label" and second.playstyle == "Learning" and addon.groups[5].playstyle == nil)
assert(#first.rosterSlots == 5 and first.rosterSlots[1] == first.members[1]
    and first.rosterSlots[2].role == 2 and first.rosterSlots[2].vacant
    and first.rosterSlots[3].name == "Member 1", "slots keep the defined role order and preserve member identity")
assert(#second.rosterSlots == 5 and second.rosterSlots[2].vacant and second.rosterSlots[5].vacant
    and second.rosterSlots[5].role == 3, "each confirmed open role keeps its own slot")
for _, index in ipairs({ 3, 5, 6 }) do
    assert(not addon.groups[index].rosterSlots, "incompatible role evidence cannot invent vacancies")
end
local partial = addon.groups[4]
assert(partial.rosterSlots[5].role == 3 and not partial.rosterSlots[5].vacant and not partial.rosterSlots[5].class
    and not partial.members[4].role and partial.members[4].class == "MAGE",
    "complete native totals show an anonymous occupied slot without guessing the unknown member's role")
local matches = addon.FilterGroups(addon.groups, {}, { tank = true, dps = true })
assert(#matches == 1 and matches[1] == second, "Fits me matches any selected role with a native vacancy")
matches = addon.FilterGroups(addon.groups, {}, { healer = true })
assert(#matches == 4 and matches[#matches].id == 104, "a known-full group or unreadable vacancy is never counted as a fit")
results[103].isDelisted = true
fire("LFG_LIST_SEARCH_RESULT_UPDATED", 103)
advance(0.2)
local retainedGroupIDs = { 101, 102, 104, 105, 106 }
assert(#addon.groups == #retainedGroupIDs)
for index, group in ipairs(addon.groups) do
    assert(group.id == retainedGroupIDs[index], "unrelated cards do not shuffle when a group disappears")
end

Enum = { SendReportResult = { Success = 0, GeneralError = 1 }, ReportType = { GroupFinderPosting = 4 } }
local reportedGroup = addon.groups[2]
local visibleBeforeReport = addon.groups
result(107, "New native result", 10)
results[107].numMembers = 2
visibleIDs = { 106, 107, 105, 104, 101 }
fire("REPORT_PLAYER_RESULT", Enum.SendReportResult.GeneralError, Enum.ReportType.GroupFinderPosting)
fire("REPORT_PLAYER_RESULT", Enum.SendReportResult.Success, 0)
assert(addon.groups == visibleBeforeReport, "only successful Group Finder posting reports refresh the result snapshot")
visibleIDs[2] = "unreadable ID"
fire("REPORT_PLAYER_RESULT", Enum.SendReportResult.Success, Enum.ReportType.GroupFinderPosting)
assert(addon.groups == visibleBeforeReport, "incomplete filtered IDs cannot prove which owned results were removed")
visibleIDs[2] = 107
fire("REPORT_PLAYER_RESULT", Enum.SendReportResult.Success, Enum.ReportType.GroupFinderPosting)
local groupsAfterReport = { 101, 104, 105, 106 }
assert(#addon.groups == #groupsAfterReport)
for index, group in ipairs(addon.groups) do
    assert(group.id == groupsAfterReport[index], "report refresh removes owned results without adding or reordering native entries")
end
ChatFrameUtil = { SendTell = function() error("Reported listings cannot start a whisper") end }
addon.OpenWhisper(reportedGroup)
fire("LFG_LIST_SEARCH_RESULT_UPDATED", reportedGroup.id)
advance(0.2)
assert(#addon.groups == #groupsAfterReport, "later per-result updates cannot restore a reported listing")

Enum.AddOnRestrictionType = { Chat = 5, Combat = 0 }
Enum.AddOnRestrictionState = { Inactive = 0, Active = 2 }
local readableResultInfo = C_LFGList.GetSearchResultInfo
local accessibleValue = canaccessvalue
local restrictedResult = {}
canaccessvalue = function(value) return value ~= restrictedResult end
C_LFGList.GetSearchResultInfo = function() return restrictedResult end
fire("LFG_LIST_SEARCH_RESULT_UPDATED", 101)
advance(0.2)
assert(#addon.groups == 0, "restricted result data cannot be decoded or used for actions")
visibleIDs = { 101, 105, 106, 107 }
fire("REPORT_PLAYER_RESULT", Enum.SendReportResult.Success, Enum.ReportType.GroupFinderPosting)
groupsAfterReport = { 101, 105, 106 }
C_LFGList.GetSearchResultInfo = readableResultInfo
canaccessvalue = accessibleValue
before = #requests
fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Combat, Enum.AddOnRestrictionState.Inactive)
fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, Enum.AddOnRestrictionState.Active)
assert(#addon.groups == 0)
combat = true
assert(not addon.Search())
combat = false
local retainedStatus = addon.status
fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, Enum.AddOnRestrictionState.Inactive)
assert(#requests == before and #addon.groups == #groupsAfterReport and addon.status == retainedStatus,
    "chat restriction recovery restores owned clean rows without another search")
for index, group in ipairs(addon.groups) do
    assert(group.id == groupsAfterReport[index], "restriction recovery cannot resurrect reported or unowned listings")
end
assert(addon.Search())
before = #requests
fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, Enum.AddOnRestrictionState.Inactive)
assert(#addon.groups == 0 and addon.status == "Searching…" and #requests == before,
    "restriction recovery cannot complete a pending search")
receive(101, 104, 105, 106)
C_LFGList.Search(2, 0, 0, nil, false, nil, {10})
local retainedGroups = addon.groups
before = #requests
fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, Enum.AddOnRestrictionState.Inactive)
assert(addon.groups == retainedGroups and #requests == before,
    "restriction recovery does not adopt a native search or repaint retired result IDs")
for _, group in ipairs(addon.groups) do assert(not group.target) end
receive(101)
advance(1)

addon.db.activities = {}
addon.db.manualDungeonSelection = false
addon.db.showAllLevels = true
level = 10
assert(#addon.Activities() == 3 and #addon.SelectedActivities() == 0,
    "viewing every level does not automatically choose a dungeon outside the recommended level range")
before = #requests
assert(not addon.Search() and #requests == before)
level = 32
fire("PLAYER_LEVEL_UP")
assert(addon.SelectedActivities()[1].id == 10, "a newly recommended dungeon becomes the automatic choice")
level = 10
addon.ToggleActivity(20)
assert(addon.db.manualDungeonSelection and addon.SelectedActivities()[1].id == 20,
    "a player can still choose an off-level dungeon explicitly")
assert(addon.Search() and requests[#requests].ids[1] == 20)
receive(4)
assert(addon.players[1].id == 4)

level = 32
addon.db.showAllLevels = false
local activeActivityIDs = { 20 }
C_LFGList.GetActiveEntryInfo = function() return { activityIDs = activeActivityIDs } end
selectDungeons(20)
assert(addon.Search())
receive(4)
assert(addon.players[1].id == 4 and addon.players[1].target)
local staleEntry = {}
for key, value in pairs(addon.players[1]) do staleEntry[key] = value end
local restrictedActivity = {}
canaccessvalue = function(value) return value ~= restrictedActivity end
local whispered = false
ChatFrameUtil.SendTell = function() whispered = true end
before = #requests
C_LFGList.GetActiveEntryInfo = function() return restrictedActivity end
fire("LFG_LIST_AVAILABILITY_UPDATE")
assert(addon.players[1].id == 4 and not addon.players[1].target,
    "an unreadable active listing cannot prove an off-level dungeon was deselected")
addon.OpenWhisper(staleEntry)
assert(not whispered, "an older actionable card stays blocked while its selection is unverified")
C_LFGList.GetActiveEntryInfo = function() return { activityIDs = activeActivityIDs } end
activeActivityIDs = { restrictedActivity }
fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, Enum.AddOnRestrictionState.Inactive)
fire("LFG_LIST_SEARCH_RESULT_UPDATED", 4)
advance(0.2)
assert(addon.players[1].id == 4 and not addon.players[1].target and #requests == before,
    "partially readable active activity IDs preserve the query without reactivating targets")
activeActivityIDs = { 20 }
fire("LFG_LIST_AVAILABILITY_UPDATE")
assert(addon.players[1].id == 4 and addon.players[1].target and #requests == before,
    "a clean catalog restores owned targets without another search")
local resultReads = 0
C_LFGList.GetSearchResultInfo = function(id)
    resultReads = resultReads + 1
    return readableResultInfo(id)
end
fire("LFG_LIST_AVAILABILITY_UPDATE")
assert(resultReads == 0, "ordinary availability updates do not decode every roster again")
C_LFGList.GetSearchResultInfo = readableResultInfo
local completeCatalog = C_LFGList.GetAvailableActivities
C_LFGList.GetAvailableActivities = function() return { 10, restrictedActivity, 30 } end
fire("LFG_LIST_AVAILABILITY_UPDATE")
assert(addon.players[1].id == 4 and not addon.players[1].target,
    "an unreadable catalog ID is not definitive removal of the selected dungeon")
C_LFGList.GetAvailableActivities = completeCatalog
fire("ADDON_RESTRICTION_STATE_CHANGED", Enum.AddOnRestrictionType.Chat, Enum.AddOnRestrictionState.Inactive)
assert(addon.players[1].id == 4 and addon.players[1].target)
activeActivityIDs = {}
fire("LFG_LIST_AVAILABILITY_UPDATE")
assert(#addon.players == 0 and addon.status == "Selection changed. Click Search.",
    "a clean removal of the off-level activity invalidates owned results")
addon.OpenWhisper(staleEntry)
assert(not whispered)

local hasActiveEntry = true
C_LFGList.HasActiveEntryInfo = function() return hasActiveEntry end
activeActivityIDs = { 20 }
selectDungeons(20)
assert(addon.Search())
receive(4)
C_LFGList.GetActiveEntryInfo = function() end
fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
assert(addon.players[1].id == 4 and not addon.players[1].target,
    "a known active listing with missing details cannot remove its off-level activity")
C_LFGList.GetActiveEntryInfo = function() return { activityIDs = activeActivityIDs } end
hasActiveEntry = restrictedActivity
fire("LFG_LIST_AVAILABILITY_UPDATE")
assert(addon.players[1].id == 4 and not addon.players[1].target,
    "an unreadable active-state flag leaves the selection unverified")
hasActiveEntry = true
before = #requests
fire("LFG_LIST_AVAILABILITY_UPDATE")
assert(addon.players[1].id == 4 and addon.players[1].target and #requests == before,
    "readable active details restore the owned query without another request")
hasActiveEntry = false
C_LFGList.GetActiveEntryInfo = function() end
local _, completeInactiveCatalog = addon.Activities()
assert(completeInactiveCatalog, "a stable absent listing is a complete catalog snapshot")
fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
assert(#addon.players == 0 and addon.status == "Selection changed. Click Search.",
    "a confirmed inactive listing removes its off-level activity from the query")

local fullCatalog = C_LFGList.GetAvailableActivities
C_LFGList.GetAvailableActivities = function() return { 30, restrictedActivity } end
PartyFinderForeverDB = { activities = { [30] = true } }
addon.InitializeSettings()
local partialActivities, partialComplete = addon.Activities()
local legacySelection, automatic = addon.SelectedActivities(partialActivities, partialComplete)
assert(not partialComplete and legacySelection[1].id == 30 and not automatic)
assert(addon.db.activities[30] and addon.db.manualDungeonSelection == nil,
    "an incomplete catalog must not erase a legacy manual dungeon that temporarily looks like the default")
C_LFGList.GetAvailableActivities = fullCatalog
legacySelection, automatic = addon.SelectedActivities()
assert(legacySelection[1].id == 30 and not automatic and addon.db.manualDungeonSelection == true)

PartyFinderForeverDB = { activities = { [10] = true } }
addon.InitializeSettings()
C_LFGList.GetAvailableActivities = function() return { 30, restrictedActivity } end
legacySelection, automatic = addon.SelectedActivities()
assert(#legacySelection == 0 and not automatic and addon.db.manualDungeonSelection == nil and addon.db.activities[10],
    "a hidden legacy automatic dungeon must wait for the complete catalog")
C_LFGList.GetAvailableActivities = fullCatalog
legacySelection, automatic = addon.SelectedActivities()
assert(legacySelection[1].id == 10 and automatic and not addon.db.manualDungeonSelection
    and not next(addon.db.activities), "a legacy automatic choice migrates once the full catalog is available")

PartyFinderForeverDB = { activities = { [10] = true } }
addon.InitializeSettings()
C_LFGList.GetAvailableActivities = function() return { 30, restrictedActivity } end
addon.ToggleActivity(30)
assert(addon.db.manualDungeonSelection == true and addon.db.activities[10] and addon.db.activities[30],
    "an explicit dungeon click must keep legacy choices hidden during a partial read")
C_LFGList.GetAvailableActivities = fullCatalog

local function assertUnresolvedOrdering()
    PartyFinderForeverDB = { activities = { [30] = true } }
    addon.InitializeSettings()
    local entries, complete = addon.Activities()
    assert(#entries == 2 and not complete)
    local picked, automatic = addon.SelectedActivities(entries, complete)
    assert(picked[1].id == 30 and not automatic and addon.db.manualDungeonSelection == nil and addon.db.activities[30],
        "display fallbacks for incomplete ordering fields must not commit legacy preferences")
end
for _, key in ipairs({ "shortName", "orderIndex", "groupFinderActivityGroupID" }) do
    local old = activities[10][key]
    activities[10][key] = restrictedActivity
    assertUnresolvedOrdering()
    activities[10][key] = old
end
activities[10].groupFinderActivityGroupID = 99
C_LFGList.GetActivityGroupInfo = function() end
assertUnresolvedOrdering()
C_LFGList.GetActivityGroupInfo = function() return "Dungeons", 0 end
local _, completeGroupData = addon.Activities()
assert(completeGroupData, "a populated group and permitted empty short names produce a complete catalog")

print("Passed search ownership, late results, queued changes, refresh isolation, DB normalization and retry bounds")
