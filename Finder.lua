local _, addon = ...
local read = addon.Read
local category = addon.dungeonCategory
local activeQuery, activeResults, pending, nextAction = {}, {}, nil, 0
local openingRetry, queuedSearch, foreignSearch, callingSearch, drainingSearch, selectionUncertain
local searchTimeout, searchDrainGrace = 6, 1
local listingPending, uncertainCreate
local listingRoleRevision, listingFailureRevision = 0, 0
local inviteAttempt

addon.defaults = {
    inviteWhisper = true,
    inviteText = "Hey! Invited you for %dungeon%. %party% %needed%",
    askText = "Hey! Got room for a level %level% %talents% %class%?",
    activities = {},
    excludedClasses = {},
    searchLanguages = {},
    showAllLevels = false,
    fitsMe = true,
    listingPlaystyle = "FunRelaxed",
    listingVoice = "None",
    listingNewPlayerFriendly = false,
}

addon.searchLocales = {
    { "enUS", "English" }, { "deDE", "Deutsch" }, { "frFR", "Français" },
    { "itIT", "Italiano" }, { "esES", "Español (España)" }, { "esMX", "Español (América Latina)" },
    { "ptBR", "Português (Brasil)" }, { "ruRU", "Русский" }, { "koKR", "한국어" },
    { "zhCN", "简体中文" }, { "zhTW", "繁體中文" },
}

function addon.InitializeSettings()
    if type(PartyFinderForeverDB) ~= "table" then PartyFinderForeverDB = {} end
    addon.db = PartyFinderForeverDB
    for key, value in pairs(addon.defaults) do
        if type(addon.db[key]) ~= type(value) then
            addon.db[key] = type(value) == "table" and {} or value
        end
    end
    if type(addon.db.manualDungeonSelection) ~= "boolean" then addon.db.manualDungeonSelection = nil end
    for id, selected in pairs(addon.db.activities) do
        if type(id) ~= "number" or id <= 0 or id == math.huge or id % 1 ~= 0 or selected ~= true then
            addon.db.activities[id] = nil
        end
    end
    for class, excluded in pairs(addon.db.excludedClasses) do
        if not addon.knownClasses[class] or excluded ~= true then addon.db.excludedClasses[class] = nil end
    end
    local selectedLanguages = {}
    for _, locale in ipairs(addon.searchLocales) do
        local code = locale[1]
        if addon.db.searchLanguages[code] == true then selectedLanguages[code] = true end
    end
    addon.db.searchLanguages = selectedLanguages
end

local function SearchLanguageFilter()
    local selected = addon.db.searchLanguages
    local all = not next(selected)
    local filter = {}
    for _, locale in ipairs(addon.searchLocales) do
        local code = locale[1]
        filter[code] = all or selected[code] == true
    end
    return filter
end

function addon.Activities()
    local entries = {}
    local groups = {}
    local level = read(UnitLevel("player"), "number")
    local rawActiveEntry = not addon.db.showAllLevels and C_LFGList.GetActiveEntryInfo()
    local activeEntry = read(rawActiveEntry, "table")
    local complete = level ~= nil and level > 0 and canaccessvalue(rawActiveEntry)
    if not addon.db.showAllLevels then
        local hasActiveEntry = read(C_LFGList.HasActiveEntryInfo(), "boolean")
        if hasActiveEntry == nil or (hasActiveEntry and not activeEntry) then complete = false end
    end
    local activeIDs = activeEntry and read(activeEntry.activityIDs, "table")
    if activeEntry and not activeIDs then complete = false end
    local listed = {}
    for _, value in ipairs(activeIDs or {}) do
        local id = read(value, "number")
        if id then listed[id] = true else complete = false end
    end
    local availableIDs = read(C_LFGList.GetAvailableActivities(category), "table")
    if not availableIDs then complete = false end
    for _, value in ipairs(availableIDs or {}) do
        local id = read(value, "number")
        local info = id and read(C_LFGList.GetActivityInfoTable(id), "table")
        local name = info and read(info.fullName, "string")
        if name then
            local min = read(info.minLevelSuggestion, "number")
            local max = read(info.maxLevelSuggestion, "number")
            if not min or not max then complete = false end
            min, max = min or 0, max or 0
            local recommended = level and level > 0 and (min <= 0 or level >= min) and (max <= 0 or level <= max)
            if recommended or listed[id] or addon.db.showAllLevels then
                local groupID = read(info.groupFinderActivityGroupID, "number")
                local order = read(info.orderIndex, "number")
                local shortName = info.shortName
                local hasShortName = canaccessvalue(shortName) and type(shortName) == "string"
                if not groupID or not order or not hasShortName then complete = false end
                groupID = groupID or 0
                local group = groups[groupID]
                if not group then
                    local groupName, groupOrder = "", 0
                    if groupID ~= 0 then
                        groupName, groupOrder = C_LFGList.GetActivityGroupInfo(groupID)
                        if not canaccessvalue(groupName) or type(groupName) ~= "string" then groupName = nil end
                        groupOrder = read(groupOrder, "number")
                        if not groupName or not groupOrder then complete = false end
                    end
                    group = { id = groupID, name = groupName or "", order = groupOrder or 0 }
                    groups[groupID] = group
                end
                entries[#entries + 1] = { id = id, name = hasShortName and shortName ~= "" and shortName or name,
                    fullName = name, min = min, max = max, order = order or 0, group = group,
                    recommended = recommended, capacity = read(info.maxNumPlayers, "number") }
            end
        else
            complete = false
        end
    end
    table.sort(entries, function(a, b)
        if a.group ~= b.group then
            if a.group.id == 0 or b.group.id == 0 then return a.group.id == 0 end
            if a.group.order ~= b.group.order then return a.group.order < b.group.order end
            local groupOrder = strcmputf8i(a.group.name, b.group.name)
            if groupOrder ~= 0 then return groupOrder < 0 end
            return a.group.id < b.group.id
        end
        if a.order ~= b.order then
            return a.group.id ~= 0 and a.order > b.order or a.group.id == 0 and a.order < b.order
        end
        if a.max ~= b.max then return a.max == 0 or (b.max ~= 0 and a.max > b.max) end
        if a.min ~= b.min then return a.min > b.min end
        local nameOrder = strcmputf8i(a.name, b.name)
        if nameOrder ~= 0 then return nameOrder < 0 end
        return a.id < b.id
    end)
    return entries, complete
end

local function ComesBeforeOriginalDefault(a, b)
    if not b then return true end
    if a.recommended ~= b.recommended then return a.recommended == true end
    if a.order ~= b.order then return a.order > b.order end
    if a.max ~= b.max then return a.max > b.max end
    if a.fullName ~= b.fullName then return a.fullName < b.fullName end
    return a.id < b.id
end

local function ComesBeforePreviousDefault(a, b)
    if not b then return true end
    if a.order ~= b.order then return a.order < b.order end
    local nameOrder = strcmputf8i(a.name, b.name)
    if nameOrder ~= 0 then return nameOrder < 0 end
    return a.id < b.id
end

function addon.SelectedActivities(available, complete)
    if not available then available, complete = addon.Activities() end
    local saved = addon.db.activities
    local manual = addon.db.manualDungeonSelection
    if manual == nil then
        local only = next(saved)
        -- Retain any visible saved choices while the catalog is incomplete.
        manual = only ~= nil
        if complete and #available > 0 then
            -- Older versions saved the auto-selected entry as a regular checkbox.
            local legacyFirst, previousFirst
            for _, entry in ipairs(available) do
                if ComesBeforeOriginalDefault(entry, legacyFirst) then legacyFirst = entry end
                if ComesBeforePreviousDefault(entry, previousFirst) then previousFirst = entry end
            end
            manual = only ~= nil
                and (next(saved, only) ~= nil or (only ~= legacyFirst.id and only ~= previousFirst.id))
            addon.db.manualDungeonSelection = manual
            if only and not manual then saved[only] = nil end
        end
    end
    if not manual then
        for _, entry in ipairs(available) do
            if entry.recommended then return { entry }, true end
        end
        return {}, true
    end
    local result = {}
    for _, entry in ipairs(available) do
        if saved[entry.id] == true then result[#result + 1] = entry end
    end
    return result, false
end

function addon.SetAutomaticDungeonSelection(enabled)
    local available, complete = addon.Activities()
    local before = addon.SelectedActivities(available, complete)
    if addon.db.manualDungeonSelection == (not enabled) then return end
    addon.db.manualDungeonSelection = not enabled

    local after = addon.SelectedActivities(available, complete)
    if #before ~= #after then addon.SelectionChanged(); return end
    for index, entry in ipairs(before) do
        if entry.id ~= after[index].id then addon.SelectionChanged(); return end
    end
    if addon.Refresh then addon.Refresh() end
end

function addon.ToggleActivity(id)
    local available, complete = addon.Activities()
    local visible
    for _, entry in ipairs(available) do
        if entry.id == id then visible = true; break end
    end
    if not visible then return end
    local selected, automatic = addon.SelectedActivities(available, complete)
    if automatic then
        addon.db.activities = {}
        if selected[1] then addon.db.activities[selected[1].id] = true end
    end
    local saved = addon.db.activities
    saved[id] = not saved[id] or nil
    addon.db.manualDungeonSelection = true
    addon.SelectionChanged()
end

local function QuerySnapshot(entries)
    local ids, activities = {}, {}
    local faction = read(UnitFactionGroup("player"), "string")
    for _, entry in ipairs(entries) do
        local info = read(C_LFGList.GetActivityInfoTable(entry.id), "table")
        if info then
            ids[#ids + 1] = entry.id
            activities[entry.id] = { id = entry.id, name = entry.name, order = #ids, zones = addon.ActivityZones(info, faction),
                capacity = read(info.maxNumPlayers, "number") }
        end
    end
    return ids, activities
end

local function changed()
    if addon.Refresh then addon.Refresh() end
end

local function ResetSearchResults(status)
    selectionUncertain = nil
    openingRetry, queuedSearch = nil, nil
    activeQuery, activeResults = {}, {}
    addon.players, addon.groups = {}, {}
    addon.status = status
end

function addon.SelectionChanged()
    if pending then pending.discard = true end
    ResetSearchResults("Selection changed. Click Search.")
    changed()
end

local function ReconcileQuerySelection()
    local query = pending and not pending.discard and pending.activities or activeQuery
    if not next(query) then return true end
    local available, complete = addon.Activities()
    if not complete then
        selectionUncertain = true
        for _, entry in ipairs(addon.players or {}) do entry.target = nil end
        for _, entry in ipairs(addon.groups or {}) do entry.target = nil end
        changed()
        return false
    end
    local recovered = selectionUncertain == true
    selectionUncertain = nil
    local selected, selectedActivities = {}, addon.SelectedActivities(available, complete)
    for _, entry in ipairs(selectedActivities) do
        if not query[entry.id] then addon.SelectionChanged(); return false end
        selected[entry.id] = true
    end
    for id in pairs(query) do
        if not selected[id] then addon.SelectionChanged(); return false end
    end
    return true, recovered
end

local function DispatchQueuedSearch()
    local request = queuedSearch
    if not request then return end
    C_Timer.After(0, function()
        if queuedSearch ~= request or pending or foreignSearch or drainingSearch then return end
        if InCombatLockdown() then
            addon.status = "Search will resume after combat."
            changed()
            return
        end
        queuedSearch = nil
        local canDispatch = request.canDispatch or request.canRetry
        if not canDispatch or canDispatch() then
            local accepted = addon.Search(request.canRetry, request.onInterrupted)
            if not accepted and request.onInterrupted then request.onInterrupted() end
        else
            addon.status = "Click Search to refresh."
            changed()
        end
    end)
end

local function BeginSearchDrain(remainingCompletions)
    -- Native search events have no request ID. Wait briefly for up to two
    -- retired or overlapping requests before dispatching another search.
    local alreadyDraining = drainingSearch and drainingSearch.remainingCompletions or 0
    local drain = { remainingCompletions = math.min(alreadyDraining + remainingCompletions, 2) }
    drainingSearch = drain
    C_Timer.After(searchDrainGrace, function()
        if drainingSearch ~= drain then return end
        drainingSearch = nil
        DispatchQueuedSearch()
    end)
end

local function ConsumeUnownedSearchCompletion()
    if foreignSearch then
        local remainingCompletions = foreignSearch.remainingCompletions - 1
        foreignSearch = nil
        if remainingCompletions > 0 then
            BeginSearchDrain(remainingCompletions)
            return true
        end
    elseif drainingSearch then
        drainingSearch.remainingCompletions = drainingSearch.remainingCompletions - 1
        if drainingSearch.remainingCompletions > 0 then return true end
        drainingSearch = nil
    else
        return false
    end
    DispatchQueuedSearch()
    return true
end

function addon.Search(canRetry, onInterrupted)
    if InCombatLockdown() then
        addon.status = "Finish combat before searching."
        changed()
        return false
    end
    if foreignSearch or drainingSearch or pending then
        if foreignSearch or drainingSearch or (pending and pending.discard) then
            queuedSearch = { canRetry = canRetry, onInterrupted = onInterrupted }
            addon.status = "Waiting for the previous search to finish…"
            changed()
        end
        return true
    end
    local ids, activities = QuerySnapshot(addon.SelectedActivities())
    if #ids == 0 then
        ResetSearchResults("Choose a dungeon to search.")
        changed()
        return false
    end

    local request = { activities = activities, canRetry = canRetry, onInterrupted = onInterrupted }
    ResetSearchResults("Searching…")
    pending, callingSearch = request, true
    local ok, result = pcall(C_LFGList.Search, category, 0, 0, SearchLanguageFilter(), false, nil, ids)
    callingSearch = nil
    if request.failed then return false end
    if pending == request and (not ok or read(result, "boolean") == false) then
        pending, addon.status = nil, "Group Finder refused the search."
        changed()
        return false
    end
    changed()
    if pending == request then
        C_Timer.After(searchTimeout, function()
            if pending ~= request then return end
            pending = nil
            BeginSearchDrain(1)
            addon.status = request.discard and "Selection changed. Click Search." or "No response. Click Search to try again."
            if not request.discard and request.onInterrupted then request.onInterrupted() end
            changed()
        end)
    end
    return true
end

if type(C_LFGList.Search) == "function" then
    hooksecurefunc(C_LFGList, "Search", function()
        if callingSearch then return end
        local overlaps = pending ~= nil or foreignSearch ~= nil
        local token = { remainingCompletions = overlaps and 2 or 1 }
        foreignSearch = token
        local deferredRetry = queuedSearch and queuedSearch.canDispatch and queuedSearch
        if deferredRetry then queuedSearch = nil end
        if pending or openingRetry or deferredRetry or next(activeQuery) then
            local interrupted = pending and not pending.discard and pending or openingRetry or deferredRetry
            pending, openingRetry = nil, nil
            activeResults = {}
            for _, entry in ipairs(addon.players or {}) do entry.target = nil end
            for _, entry in ipairs(addon.groups or {}) do entry.target = nil end
            local hasPreviousResults = #(addon.players or {}) > 0 or #(addon.groups or {}) > 0
            addon.status = hasPreviousResults and "Showing previous results. Click Search to refresh."
                or "Click Search to refresh."
            if interrupted and interrupted.onInterrupted then interrupted.onInterrupted() end
            C_Timer.After(0, changed)
        end
        C_Timer.After(searchTimeout, function()
            if foreignSearch ~= token then return end
            foreignSearch = nil
            BeginSearchDrain(token.remainingCompletions)
        end)
    end)
end

local function rolesFrom(record)
    local roles = record and read(record.lfgRoles, "table")
    if not roles then return nil end
    local tank, healer, dps = read(roles.tank, "boolean"), read(roles.healer, "boolean"), read(roles.dps, "boolean")
    if tank == nil and healer == nil and dps == nil then return nil end
    return { tank = tank, healer = healer, dps = dps }
end

local function ListingSpecialization(member, class)
    local spec = member and read(member.specName, "string")
    if not spec then return end
    spec = spec:match("^%s*(.-)%s*$")
    if spec == "" then return end

    -- Forever may return the class name in specName when it has no talent branch.
    local className = read(member.className, "string")
    if not class and not className then return end
    local male = class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
    local female = class and LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[class]
    for _, name in pairs({className, class, male, female}) do
        if name and strcmputf8i(spec, name) == 0 then return end
    end
    return spec
end

local function GroupRoster(id, count, counts)
    local members, knownRoles = {}, {}
    local limit = math.min(count, 10)
    local roleIndex = {}
    for index, role in ipairs(addon.roles) do roleIndex[role.token] = index end
    for index = 1, limit do
        local info = read(C_LFGList.GetSearchResultPlayerInfo(id, index), "table")
        if info then
            local name = read(info.name, "string")
            local class = read(info.classFilename, "string")
            local className = read(info.className, "string")
            local role = roleIndex[read(info.assignedRole, "string") or ""]
            if name or class or className or role then
                members[#members + 1] = { index = index, name = name, class = class, className = className,
                    role = role, specName = ListingSpecialization(info, class), leader = read(info.isLeader, "boolean") }
                if role then knownRoles[role] = (knownRoles[role] or 0) + 1 end
            end
        end
    end

    if #members < limit and counts then
        for index, role in ipairs(addon.roles) do
            local total = read(counts[role.token], "number") or 0
            local missing = math.min(limit - #members, total - (knownRoles[index] or 0))
            for _ = 1, missing do members[#members + 1] = { role = index } end
        end
    end
    for index = #members + 1, limit do members[index] = {} end
    table.sort(members, function(a, b)
        if a.role ~= b.role then return (a.role or 4) < (b.role or 4) end
        return (a.index or 11) < (b.index or 11)
    end)
    local filled, open = {}, {}
    for index, role in ipairs(addon.roles) do
        local total = counts and read(counts[role.token], "number") or 0
        local remaining = counts and read(counts[role.token .. "_REMAINING"], "number") or 0
        filled[role.key] = total > 0 or knownRoles[index] ~= nil
        open[role.key] = remaining > 0 and remaining % 1 == 0
    end
    return members, filled, open
end

local function StandardRoster(members, count, activity, counts)
    if not counts or not activity or activity.capacity ~= 5 or count > 5 then return end
    if (read(counts.NOROLE, "number") or 0) ~= 0 then return end
    local buckets = { {}, {}, {} }
    for _, member in ipairs(members) do
        local bucket = buckets[member.role]
        if bucket then
            bucket[#bucket + 1] = member
        elseif addon.knownClasses[member.class] then
            -- Keep the known class in the unslotted roster if its role is unknown.
            return
        end
    end

    -- Publish a role placeholder only when the native vacancy count and the
    -- occupied totals agree on all five standard dungeon slots.
    local slots, occupied = {}, 0
    for index, role in ipairs(addon.roles) do
        local limit = index == 3 and 3 or 1
        local bucket = buckets[index]
        local total = read(counts[role.token], "number")
        local remaining = read(counts[role.token .. "_REMAINING"], "number")
        if not total or total < #bucket or total > limit or total % 1 ~= 0 or remaining ~= limit - total then return end
        occupied = occupied + total
        for i = 1, total do slots[#slots + 1] = bucket[i] or { role = index } end
        for _ = 1, remaining do slots[#slots + 1] = { role = index, vacant = true } end
    end
    if occupied == count then return slots end
end

local function GroupHasSpace(count, activities)
    for _, activity in ipairs(activities) do
        local capacity = activity.capacity
        if not capacity or capacity <= 0 or count < capacity then return true end
    end
    return #activities == 0
end

local function GroupClassSummary(members, counts, memberCount)
    local classes, knownMembers, countedMembers = {}, 0, 0
    for _, member in ipairs(members) do
        if addon.knownClasses[member.class] then
            classes[member.class] = true
            knownMembers = knownMembers + 1
        end
    end
    if counts then
        for class in pairs(addon.knownClasses) do
            local count = read(counts[class], "number")
            if count and count > 0 and count <= memberCount and count % 1 == 0 then
                classes[class] = true
                countedMembers = countedMembers + count
            end
        end
    end
    return classes, knownMembers == memberCount or countedMembers == memberCount
end

local function ResultSnapshot()
    local _, raw = C_LFGList.GetFilteredSearchResults()
    local results = read(raw, "table")
    local ids, seen = {}, {}
    local complete = results ~= nil
    for _, value in ipairs(results or {}) do
        local id = read(value, "number")
        if not id then
            complete = false
        elseif not seen[id] then
            ids[#ids + 1], seen[id] = id, true
        end
    end
    return { ids = ids, seen = seen }, complete
end

local function CollectResults(query, snapshot)
    local players, groups = {}, {}
    local foundMatchingActivity, foundOtherActivity = false, false
    for _, id in ipairs(snapshot.ids) do
        local result = read(C_LFGList.GetSearchResultInfo(id), "table")
        local count = result and read(result.numMembers, "number")
        local delisted = result and read(result.isDelisted, "boolean")
        if count and count >= 1 and count % 1 == 0 and delisted ~= true then
            local rawMember
            if count == 1 then
                rawMember = C_LFGList.GetSearchResultPlayerInfo(id, 1)
            else
                rawMember = C_LFGList.GetSearchResultLeaderInfo(id)
            end
            local member = read(rawMember, "table")
            local area = member and read(member.areaName, "string")
            local activities = read(result.activityIDs, "table")
            local rank, matches = addon.Proximity(activities, area, query)
            if activities then
                if matches then
                    foundMatchingActivity = true
                else
                    for _, activityID in ipairs(activities) do
                        if read(activityID, "number") then foundOtherActivity = true; break end
                    end
                end
            end
            if matches then
                local leader = read(result.leaderName, "string")
                local name = leader or (member and read(member.name, "string"))
                local own = read(result.hasSelf, "boolean")
                local target = not selectionUncertain and activities and own == false and delisted == false and leader or nil
                local listedDungeons, seen = {}, {}
                for _, activityID in ipairs(activities or {}) do
                    local key = read(activityID, "number")
                    local activity = key and query[key]
                    if activity and not seen[key] then
                        listedDungeons[#listedDungeons + 1] = activity
                        seen[key] = true
                    end
                end
                table.sort(listedDungeons, function(a, b)
                    local aRank = area and a.zones[area] or math.huge
                    local bRank = area and b.zones[area] or math.huge
                    if aRank ~= bRank then return aRank < bRank end
                    return a.order < b.order
                end)
                local comment = read(result.comment, "string")
                local class = member and read(member.classFilename, "string")
                local entry = { id = id, name = name or (count == 1 and "Unnamed player" or "Unnamed group"),
                    target = target, partyGUID = read(result.partyGUID, "string"), count = count, own = own,
                    class = class, specName = ListingSpecialization(member, class),
                    level = member and read(member.level, "number"), roles = rolesFrom(member),
                    area = area, rank = count == 1 and rank or nil, activity = listedDungeons[1], listedDungeons = listedDungeons,
                    comment = comment and comment:find("%S") and comment or nil }
                if count > 1 then
                    local counts = C_LFGList.GetSearchResultMemberCounts and read(C_LFGList.GetSearchResultMemberCounts(id), "table")
                    entry.members, entry.filledRoles, entry.openRoles = GroupRoster(id, count, counts)
                    entry.memberClasses, entry.hasCompleteClasses = GroupClassSummary(entry.members, counts, count)
                    entry.rosterSlots = StandardRoster(entry.members, count, entry.activity, counts)
                    if not GroupHasSpace(count, listedDungeons) then entry.openRoles = {} end
                    local playstyle = read(result.generalPlaystyle, "number")
                    if playstyle and GetGeneralPlaystyleString then
                        entry.playstyle = read(GetGeneralPlaystyleString(playstyle), "string")
                    end
                end
                local list = count == 1 and players or groups
                list[#list + 1] = entry
            end
        end
    end
    return players, groups, foundOtherActivity and not foundMatchingActivity
end

local function ShowResults(players, groups)
    addon.players, addon.groups = players, groups
    addon.status = nil
    changed()
end

local function PruneReportedResults()
    if not activeResults.ids or openingRetry then return end
    local filtered, complete = ResultSnapshot()
    if not complete then return end
    -- A native report can hide a row without removing its detail record.
    -- Only remove IDs from the snapshot this addon already owns.
    local ids, seen = {}, {}
    for _, id in ipairs(activeResults.ids) do
        if filtered.seen[id] then
            ids[#ids + 1], seen[id] = id, true
        end
    end
    if #ids == #activeResults.ids then return end
    activeResults = { ids = ids, seen = seen }
    ShowResults(CollectResults(activeQuery, activeResults))
end

local function FinishSearch(request)
    local snapshot = ResultSnapshot()
    local players, groups, otherActivities = CollectResults(request.activities, snapshot)
    -- Received supplies no request ID. A response known to cover only other
    -- activities cannot complete this request, even if it arrived after a timeout.
    if otherActivities then return end
    pending = nil
    activeQuery, activeResults = request.activities, snapshot
    if #players > 0 or #groups > 0 or not request.canRetry or not request.canRetry() then
        ShowResults(players, groups)
        return
    end

    -- The native result event is shared and supplies no request ID. Give the
    -- first empty response a chance to settle before retrying once.
    openingRetry = request
    addon.status = "Checking for listings…"
    changed()
    C_Timer.After(1, function()
        if openingRetry ~= request then return end
        openingRetry = nil
        local updated = ResultSnapshot()
        local updatedPlayers, updatedGroups, unrelatedActivities = CollectResults(request.activities, updated)
        if unrelatedActivities then
            updated = activeResults
            updatedPlayers, updatedGroups = CollectResults(request.activities, updated)
        end
        if #updatedPlayers == 0 and #updatedGroups == 0 and request.canRetry() then
            if InCombatLockdown() then
                -- Keep the visibility check for dispatch. This request is already the single retry.
                queuedSearch = { canDispatch = request.canRetry, onInterrupted = request.onInterrupted }
                addon.status = "Search will resume after combat."
                changed()
            else
                local accepted = addon.Search(nil, request.onInterrupted)
                if not accepted and request.onInterrupted then request.onInterrupted() end
            end
        else
            activeResults = updated
            ShowResults(updatedPlayers, updatedGroups)
        end
    end)
end

local treeRoles = { WARRIOR = {"dps", "dps", "tank"}, PALADIN = {"healer", "tank", "dps"},
    PRIEST = {"healer", "healer", "dps"}, SHAMAN = {"dps", "dps", "healer"}, DRUID = {"dps", "dps", "healer"} }

function addon.PreferredRole()
    local _, classToken = UnitClass("player")
    local class = read(classToken, "string")
    local slot = C_SpecializationInfo.GetActiveSpecGroup()
    local config = slot and C_SpecializationInfo.GetCombatConfigIDForSpecGroup(slot)
    local info = config and C_Traits.GetConfigInfo(config)
    local tree = info and info.treeIDs and info.treeIDs[1]
    local nodeGroups = tree and C_Traits.GetGroupDisplayInfoByTreeID(tree)
    local winner, talent = 0, nil
    if nodeGroups and #nodeGroups > 0 then
        table.sort(nodeGroups, function(a, b) return a.orderIndex < b.orderIndex end)
        local ids, spent = {}, {}
        for i, group in ipairs(nodeGroups) do ids[i] = group.groupID end
        for _, group in ipairs(C_Traits.GetGroupCurrencyInfo(config, ids) or {}) do
            local currency = group.currencyInfos and group.currencyInfos[1]
            spent[group.traitNodeGroupID] = currency and currency.spent or 0
        end
        local best = 0
        for index, group in ipairs(nodeGroups) do
            local points = spent[group.groupID] or 0
            if points > best then
                winner, best, talent = index, points, read(group.displayName, "string")
            end
        end
    end
    local roles = treeRoles[class]
    return (roles and roles[winner]) or "dps", talent
end

function addon.ListingRoles()
    local saved = type(addon.db.listingRoles) == "table" and addon.db.listingRoles
    local preferred = not saved and (addon.PreferredRole() or "dps")
    local roles = {}
    for _, role in ipairs(addon.roles) do
        local key = role.key
        roles[key] = (saved and saved[key] == true) or key == preferred
    end
    return roles
end

function addon.NativeListingRoles()
    if not C_LFGListRoles or type(C_LFGListRoles.GetRoles) ~= "function" then return end
    local ok, value = pcall(C_LFGListRoles.GetRoles)
    local raw = ok and read(value, "table")
    if not raw then return end
    local roles = {}
    for _, role in ipairs(addon.roles) do
        local enabled = read(raw[role.key], "boolean")
        if enabled == nil then return end
        roles[role.key] = enabled
    end
    return roles
end

function addon.SetListingRole(key, checked)
    local roles = addon.ListingRoles()
    if roles[key] == nil then return end
    roles[key] = checked
    addon.db.listingRoles = roles
    changed()
end

function addon.ListingState()
    local grouped = read(IsInGroup(LE_PARTY_CATEGORY_HOME), "boolean")
    return grouped, read(C_LFGList.HasActiveEntryInfo(), "boolean"), listingPending
end

function addon.ListingData(activities)
    local ids = {}
    for _, entry in ipairs(activities) do ids[#ids + 1] = entry.id end
    local playstyles = Enum.LFGEntryGeneralPlaystyle
    local voices = Enum.LFGEntryVoiceMode
    return { activityIDs = ids, generalPlaystyle = playstyles[addon.db.listingPlaystyle] or playstyles.FunRelaxed,
        voiceMode = voices[addon.db.listingVoice] or voices.None,
        newPlayerFriendly = addon.db.listingNewPlayerFriendly == true }
end

local function SetNativeListingRoles(roles)
    if not C_LFGListRoles or type(C_LFGListRoles.SetRoles) ~= "function" then return false end
    local ok, success = pcall(C_LFGListRoles.SetRoles, roles, false)
    return ok and read(success, "boolean") == true
end

function addon.NativeListingComment()
    local view = LFGListingFrame and LFGListingFrame.ActivityView
    local edit = view and view.Comment and view.Comment.EditBox
    if not edit then return end
    local ok, value = pcall(edit.GetText, edit)
    if ok and canaccessvalue(value) and type(value) == "string" then return value end
end

function addon.SaveListingComment(value)
    addon.db.listingComment = value and value:find("%S") and value or nil
    changed()
end

function addon.CanManageListing(grouped)
    return grouped == false or (grouped == true and
        read(UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME), "boolean") == true)
end

function addon.CanCreateListing(activities, ownPending)
    if InCombatLockdown() then return nil, "Finish combat before listing." end
    local grouped, active, waiting = addon.ListingState()
    if (waiting and waiting ~= ownPending) or active ~= false then
        return nil, "A listing is already active or being created."
    end
    if not addon.CanManageListing(grouped) then
        return nil, "Only the party leader can list the group."
    end
    if #activities == 0 then return nil, "Choose a dungeon first." end
    local max = Constants and Constants.LFGConstsExposed and Constants.LFGConstsExposed.GROUP_FINDER_MAX_ACTIVITY_CAPACITY
    if max and #activities > max then return nil, "Too many dungeons selected." end
    if grouped then
        local count = read(GetNumGroupMembers(LE_PARTY_CATEGORY_HOME), "number")
        for _, activity in ipairs(activities) do
            local capacity = activity.capacity
            if count and capacity and capacity > 0 and count >= capacity then
                return nil, "Your party is full for " .. activity.name .. "."
            end
        end
    end
    return true
end

local function RolesMatch(left, right)
    return left and right and left.tank == right.tank and left.healer == right.healer and left.dps == right.dps
end

function addon.ApplyListingRoleDraft(roles, requirePrior)
    local selected = { tank = roles.tank == true, healer = roles.healer == true, dps = roles.dps == true }
    if not (selected.tank or selected.healer or selected.dps) then return false end
    local prior = addon.NativeListingRoles()
    if requirePrior and not prior then return false end
    if not SetNativeListingRoles(selected) then return false end
    if prior and not RolesMatch(prior, selected) then
        return true, { prior = prior, applied = selected, revision = listingRoleRevision }
    end
    return true
end

function addon.RestoreListingRoleDraft(change)
    if not change or listingRoleRevision ~= change.revision then return end
    local grouped, active = addon.ListingState()
    if grouped ~= false or active ~= false then return end
    if RolesMatch(addon.NativeListingRoles(), change.applied) then return SetNativeListingRoles(change.prior) end
end

local function ScheduleListingTimeout(request)
    C_Timer.After(5, function()
        if listingPending ~= request then return end
        listingPending = nil
        if request.active then uncertainCreate = true end
        changed()
    end)
end

local listingRefusedMessage = "WoW declined the listing. Check the selected dungeons and roles."

function addon.ListingFailureRevision()
    return listingFailureRevision
end

function addon.ObserveNativeListingPost(previousFailureRevision, kind, onRefused)
    kind = kind or "create"
    if kind == "create" and previousFailureRevision and previousFailureRevision ~= listingFailureRevision then
        return false, listingRefusedMessage
    end
    local _, active, waiting = addon.ListingState()
    local desiredActive = kind == "create"
    if active == desiredActive or waiting then return true end
    -- The stock Post handler just ran. Share its wait with direct addon listing
    -- actions so another click cannot clear the text before the outcome.
    local request = { kind = kind, active = desiredActive, onRefused = onRefused }
    listingPending = request
    ScheduleListingTimeout(request)
    changed()
    return true
end

local function RequestListingChange(kind, action, roleChange, ...)
    local request = { kind = kind, active = kind == "create", dispatching = true }
    listingPending = request
    local ok, success = pcall(action, ...)
    request.dispatching = false
    local accepted = ok and read(success, "boolean")
    if request.failed or not ok or accepted == false or (request.active and accepted ~= true) then
        if listingPending == request then listingPending = nil end
        if request.failed or (ok and accepted == false) then
            addon.RestoreListingRoleDraft(roleChange)
        elseif request.active then
            uncertainCreate = true
        end
        changed()
        return false
    end
    if listingPending == request then ScheduleListingTimeout(request) end
    changed()
    return true
end

function addon.RemoveListing()
    local grouped, active, waiting = addon.ListingState()
    if waiting or active ~= true then return false, "No active listing is ready to remove." end
    if InCombatLockdown() then return false, "Finish combat before unlisting." end
    if not addon.CanManageListing(grouped) then return false, "Only the party leader can unlist the group." end
    if not RequestListingChange("remove", C_LFGList.RemoveListing, nil) then
        return false, "WoW could not remove the listing. Try again."
    end
    return true
end

function addon.CreateListing()
    local activities = addon.SelectedActivities()
    local allowed, reason = addon.CanCreateListing(activities)
    if not allowed then return false, reason end
    local create = C_LFGList.CreateListing
    local clear = C_LFGList.ClearCreationTextFields
    if type(create) ~= "function" or type(clear) ~= "function" then
        return false, "WoW's listing controls are unavailable."
    end
    local data = addon.ListingData(activities)
    local grouped = addon.ListingState()
    local roleChange
    if grouped == false then
        local applied
        applied, roleChange = addon.ApplyListingRoleDraft(addon.ListingRoles())
        if not applied then
            return false, "Choose at least one role the game accepts."
        end
    end
    local cleared, result = pcall(clear)
    local comment = cleared and addon.NativeListingComment()
    if not cleared or read(result, "boolean") == false or (comment and comment ~= "") then
        addon.RestoreListingRoleDraft(roleChange)
        return false, "WoW could not clear the listing text. Open the comment form to review it."
    end
    if not RequestListingChange("create", create, roleChange, data) then
        return false, listingRefusedMessage
    end
    return true
end

local function defaultRoster(capacity, count)
    local raid = read(IsInRaid(LE_PARTY_CATEGORY_HOME), "boolean")
    if not count or raid == nil then return "", "" end
    local size, roster = math.max(count, 1), {}
    local _, talent = addon.PreferredRole()
    local roles = { TANK = "tank", HEALER = "healer", DAMAGER = "DPS" }
    local assigned = { TANK = 0, HEALER = 0, DAMAGER = 0 }
    for i = 1, math.min(size, 4) do
        local unit = raid and "raid" .. i or i == 1 and "player" or "party" .. (i - 1)
        local class = read(UnitClass(unit), "string")
        local role = read(UnitGroupRolesAssigned(unit), "string")
        if count == 0 and unit == "player" then
            local active = read(C_LFGList.HasActiveEntryInfo(), "boolean")
            local chosen
            if active == true then chosen = addon.NativeListingRoles() end
            if active == false then chosen = addon.ListingRoles() end
            if chosen then
                role = nil
                for _, candidate in ipairs(addon.roles) do
                    if read(chosen[candidate.key], "boolean") == true then
                        if role then role = nil; break end
                        role = candidate.token
                    end
                end
            end
        end
        if class then
            local tag = unit == "player" and talent
            if tag then class = tag .. " " .. class end
            if not tag and roles[role] then class = class .. " (" .. roles[role] .. ")" end
            roster[#roster + 1] = class
        end
        local roleCount = role and assigned[role]
        if role and roleCount then assigned[role] = roleCount + 1 end
    end
    if #roster > 0 and #roster < size then roster[#roster + 1] = "+" .. (size - #roster) .. " more" end
    local missing = capacity and capacity - size or 0
    local needed = ""
    if missing > 0 then
        if capacity == 5 and assigned.TANK + assigned.HEALER + assigned.DAMAGER == size
            and assigned.TANK <= 1 and assigned.HEALER <= 1 and assigned.DAMAGER <= 3 then
            local wanted = {}
            if assigned.TANK == 0 then wanted[#wanted + 1] = "a tank" end
            if assigned.HEALER == 0 then wanted[#wanted + 1] = "a healer" end
            if assigned.DAMAGER < 3 then wanted[#wanted + 1] = 3 - assigned.DAMAGER .. " DPS" end
            needed = "Need " .. table.concat(wanted, ", ") .. "."
        else
            needed = missing .. (missing == 1 and " spot left." or " spots left.")
        end
    end
    local party = #roster > 0 and ((size == 1 and "I'm " or "We have ") .. table.concat(roster, ", ") .. ".") or ""
    return party, needed
end

function addon.RenderTemplate(template, tokens)
    local message = template:gsub("%%([a-z]+)%%", function(key) return tokens[key] end)
    message = message:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    local length = math.min(#message, 255)
    while length > 0 and length < #message do
        local following = message:byte(length + 1)
        if following < 128 or following >= 192 then break end
        length = length - 1
    end
    return message:sub(1, length)
end

local function whisper(target, text)
    if text == "" then return true end
    if read(C_ChatInfo.InChatMessagingLockdown(), "boolean") ~= false then return false end
    return pcall(C_ChatInfo.SendChatMessage, text, "WHISPER", nil, target)
end

local function ActionTarget(entry)
    if selectionUncertain or not entry or not entry.target or entry.own then return end
    local destination = entry.activity and entry.activity.id
    if not destination or not activeQuery[destination] or not activeResults.seen or not activeResults.seen[entry.id] then return end
    local current = read(C_LFGList.GetSearchResultInfo(entry.id), "table")
    if not current or read(current.leaderName, "string") ~= entry.target or read(current.hasSelf, "boolean") ~= false
        or read(current.numMembers, "number") ~= entry.count or read(current.isDelisted, "boolean") ~= false then return end
    if entry.partyGUID and read(current.partyGUID, "string") ~= entry.partyGUID then return end
    for _, activity in ipairs(read(current.activityIDs, "table") or {}) do
        if read(activity, "number") == destination then return entry.target end
    end
end

function addon.OpenWhisper(entry)
    local target = ActionTarget(entry)
    if target then ChatFrameUtil.SendTell(target) end
end

function addon.ShouldSuggestInvite()
    return read(IsInGroup(LE_PARTY_CATEGORY_HOME), "boolean") == true
        and read(UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME), "boolean") == false
        and read(UnitIsGroupAssistant("player"), "boolean") == false
end

function addon.Act(entry)
    local now = GetTime()
    if InCombatLockdown() or now < nextAction then return end
    local target = ActionTarget(entry)
    if not target then return end

    if entry.count == 1 then
        local count = read(GetNumGroupMembers(LE_PARTY_CATEGORY_HOME), "number")
        local capacity = entry.activity and entry.activity.capacity
        local suggest = addon.ShouldSuggestInvite()
        if not suggest and read(C_PartyInfo.CanInvite(), "boolean") ~= true then
            return false, "You cannot invite players right now."
        end
        local full = read(C_PartyInfo.IsPartyFull(LE_PARTY_CATEGORY_HOME), "boolean")
        if count == nil or full == nil then return false, "Could not verify an open slot in your party." end
        if full or (capacity and capacity > 0 and count >= capacity) then
            return false, "Your party has no room for this dungeon."
        end
        local attempt = {}
        nextAction = now + 2
        inviteAttempt = attempt
        local ok = pcall(C_PartyInfo.InviteUnit, target)
        inviteAttempt = nil
        if not ok then
            return false, suggest and "WoW could not suggest the invite to your leader." or "WoW could not send the party invite."
        end
        if not suggest and not attempt.needsConfirmation and addon.db.inviteWhisper and entry.activity then
            local party, needed = defaultRoster(capacity, count)
            local text = addon.RenderTemplate(addon.db.inviteText, { dungeon = entry.activity.name, party = party, needed = needed })
            if not whisper(target, text) then
                return false, "WoW could not send the invite whisper."
            end
        end
    else
        local _, talent = addon.PreferredRole()
        local level = read(UnitLevel("player"), "number")
        local text = addon.RenderTemplate(addon.db.askText, { level = level and tostring(level) or "", talents = talent or "",
            class = read(UnitClass("player"), "string") or "" })
        nextAction = now + 2
        if text == "" then
            local grouped, active = addon.ListingState()
            local roles
            if grouped == false and active == true then
                roles = addon.NativeListingRoles()
            else
                roles = addon.ListingRoles()
            end
            if roles and not (roles.tank or roles.healer or roles.dps) then roles = nil end
            if not pcall(C_PartyInfo.RequestInviteFromUnit, target,
                roles and roles.tank, roles and roles.healer, roles and roles.dps) then
                return false, "WoW could not request an invite to the group."
            end
            return
        end
        if not whisper(target, text) then
            return false, "WoW could not send the join whisper."
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
events:RegisterEvent("LFG_LIST_SEARCH_FAILED")
events:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
events:RegisterEvent("REPORT_PLAYER_RESULT")
events:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
events:RegisterEvent("PLAYER_TALENT_UPDATE")
events:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
events:RegisterEvent("LFG_LIST_AVAILABILITY_UPDATE")
events:RegisterEvent("LFG_LIST_ENTRY_CREATION_FAILED")
events:RegisterEvent("LFG_LIST_ROLE_UPDATE")
events:RegisterEvent("INVITE_TO_PARTY_CONFIRMATION")
events:RegisterEvent("INVITE_TRAVEL_PASS_CONFIRMATION")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PARTY_LEADER_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
local repaintPending
events:SetScript("OnEvent", function(_, event, ...)
    if event == "INVITE_TO_PARTY_CONFIRMATION" or event == "INVITE_TRAVEL_PASS_CONFIRMATION" then
        if inviteAttempt then inviteAttempt.needsConfirmation = true end
    elseif event == "PLAYER_REGEN_ENABLED" then
        DispatchQueuedSearch()
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        local restriction, state = ...
        if read(restriction, "number") == Enum.AddOnRestrictionType.Chat
            and read(state, "number") == Enum.AddOnRestrictionState.Inactive then
            if not ReconcileQuerySelection() then return end
            if not pending and not openingRetry and activeResults.ids then
                addon.players, addon.groups = CollectResults(activeQuery, activeResults)
            end
            changed()
        end
    elseif event == "LFG_LIST_ROLE_UPDATE" then
        listingRoleRevision = listingRoleRevision + 1
        changed()
    elseif event == "LFG_LIST_ENTRY_CREATION_FAILED" then
        listingFailureRevision = listingFailureRevision + 1
        if listingPending and listingPending.kind == "create" then
            local request = listingPending
            -- A delayed failure can belong to an earlier attempt. Only an
            -- in-call refusal can safely undo changes to the native roles.
            if not request.dispatching and uncertainCreate then return end
            listingPending = nil
            request.failed = true
            if not request.dispatching then
                if request.onRefused then request.onRefused() end
                changed()
                UIErrorsFrame:AddMessage(listingRefusedMessage, 1, 0.32, 0.24)
            end
        end
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        if ConsumeUnownedSearchCompletion() then return end
        if pending and pending.discard then
            pending = nil
            addon.status = "Selection changed. Click Search."
            changed()
            DispatchQueuedSearch()
        elseif pending then
            FinishSearch(pending)
        end
    elseif event == "LFG_LIST_SEARCH_FAILED" then
        if ConsumeUnownedSearchCompletion() then return end
        if pending then
            local request = pending
            request.failed = true
            addon.status = request.discard and "Selection changed. Click Search." or "Search failed. Try again."
            pending = nil
            -- The dispatch caller handles a refusal returned from the native search call.
            if not request.discard and not callingSearch and request.onInterrupted then request.onInterrupted() end
            changed()
            DispatchQueuedSearch()
        end
    elseif event == "REPORT_PLAYER_RESULT" then
        local outcome, reportType = ...
        if read(outcome, "number") == Enum.SendReportResult.Success
            and read(reportType, "number") == Enum.ReportType.GroupFinderPosting then
            PruneReportedResults()
        end
    elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        local resultID = read((...), "number")
        if pending or openingRetry or repaintPending == activeResults or not activeResults.seen or not resultID
            or not activeResults.seen[resultID] then return end
        local query, snapshot = activeQuery, activeResults
        repaintPending = snapshot
        C_Timer.After(0.2, function()
            if repaintPending == snapshot then repaintPending = nil end
            if not pending and not openingRetry and activeQuery == query and activeResults == snapshot then
                ShowResults(CollectResults(query, snapshot))
            end
        end)
    elseif event == "PLAYER_LEVEL_UP" or event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" or event == "LFG_LIST_AVAILABILITY_UPDATE" then
        if not addon.db then return end
        if event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
            local active = read(C_LFGList.HasActiveEntryInfo(), "boolean")
            if listingPending and listingPending.active == active then
                -- An active update could be a belated create. Start trusting
                -- untagged failures again only after tracking its removal.
                if listingPending.kind == "remove" then uncertainCreate = nil end
                listingPending = nil
            end
            if active == true and addon.EndNativeDraft then addon.EndNativeDraft() end
        end
        local matched, recovered = ReconcileQuerySelection()
        if not matched then return end
        if recovered and not pending and not openingRetry and activeResults.ids then
            addon.players, addon.groups = CollectResults(activeQuery, activeResults)
        end
        changed()
    else
        changed()
    end
end)
