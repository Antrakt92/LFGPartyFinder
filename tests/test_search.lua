-- Run with Lua 5.1 and pass the addon directory as the first argument.
local root = arg[1] or "."
local addon = {}
local requests, timers, visibleIDs, results = {}, {}, {}, {}
local level, combat, clock = 32, false, 0
local searchRejected = false
local activities = {
    [10] = { fullName = "Eligible dungeon", minLevelSuggestion = 20, maxLevelSuggestion = 60 },
    [20] = { fullName = "Higher dungeon", minLevelSuggestion = 33, maxLevelSuggestion = 60 },
    [30] = { fullName = "Lower dungeon", minLevelSuggestion = 20, maxLevelSuggestion = 32 },
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
    GetFilteredSearchResults = function() return #visibleIDs, visibleIDs end,
    GetSearchResultInfo = function(id) return results[id] end,
    GetSearchResultPlayerInfo = function() return { classFilename = "MAGE" } end,
    Search = function(category, _, _, languages, _, _, ids)
        requests[#requests + 1] = { category = category, ids = ids, languages = languages }
        if searchRejected then return false end
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

combat = true
before = #requests
assert(not addon.Search() and #requests == before)
combat = false
searchRejected = true
assert(not addon.Search())
assert(addon.status:find("refused", 1, true))

print("Passed search ownership, late results, queued changes, refresh isolation, DB normalization and retry bounds")
