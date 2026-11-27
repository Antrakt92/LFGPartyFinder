local _, addon = ...

addon.dungeonCategory = 2
addon.roles = {
    { key = "tank", token = "TANK", label = "Tank", icon = "groupfinder-icon-role-large-tank" },
    { key = "healer", token = "HEALER", label = "Healer", icon = "groupfinder-icon-role-large-heal" },
    { key = "dps", token = "DAMAGER", label = "Damage", icon = "groupfinder-icon-role-large-dps" },
}
addon.classOrder = { "WARRIOR", "PALADIN", "HUNTER", "SHAMAN", "ROGUE", "DRUID", "PRIEST", "MAGE", "WARLOCK", "UNKNOWN" }
addon.knownClasses = {}
for _, class in ipairs(addon.classOrder) do
    if class ~= "UNKNOWN" then addon.knownClasses[class] = true end
end

local entrances = {
    [33] = {1421}, [34] = {1453}, [36] = {1436}, [43] = {1413}, [47] = {1413}, [48] = {1440},
    [70] = {1418}, [90] = {1426}, [109] = {1435}, [129] = {1413}, [189] = {1420}, [209] = {1446},
    [229] = {1427, 1428}, [230] = {1427, 1428}, [289] = {1422}, [329] = {1423}, [349] = {1443},
    [389] = {1454}, [429] = {1444}, [2959] = {1416, 1421}, [2970] = {1434}, [2974] = {1447},
    [2994] = {1445}, [2998] = {1437}, [2999] = {1420, 1458}, [3001] = {1449}, [3039] = {2548},
    [3065] = {1455},
}

function addon.Read(value, kind)
    if canaccessvalue(value) and type(value) == kind then
        if kind == "string" and value == "" then return end
        if kind == "number" and (value ~= value or math.abs(value) == math.huge) then return end
        return value
    end
end

local read = addon.Read

function addon.ActivityZones(activity, faction)
    local zones = {}
    local function add(value, rank)
        local name = read(value, "string")
        if name and (not zones[name] or rank < zones[name]) then zones[name] = rank end
    end

    add(activity.fullName, 1)
    local mapID = read(activity.mapID, "number")
    if not mapID or mapID <= 0 then return zones end
    add(GetRealZoneText(mapID), 1)
    for _, id in ipairs(entrances[mapID] or {}) do
        local map = read(C_Map.GetMapInfo(id), "table")
        if map then add(map.name, 2) end
    end
    if mapID == 229 or mapID == 230 then
        add(C_Map.GetAreaInfo(25), 2) -- Blackrock Mountain
    elseif mapID == 90 and faction == "Horde" then
        add(C_Map.GetAreaInfo(35), 3) -- Scooty's transporter in Booty Bay
    elseif mapID == 2959 then
        add(C_Map.GetAreaInfo(279), 1) -- Dalaran in the open world
        add(C_Map.GetAreaInfo(16558), 1) -- Dalaran inside the instance
        add(C_Map.GetAreaInfo(267), 3) -- Hillsbrad Foothills approach
    end
    return zones
end

function addon.Proximity(activityIDs, area, selected)
    local best, matches = nil, false
    if not activityIDs then return nil, true end
    for _, value in ipairs(activityIDs) do
        local id = read(value, "number")
        local activity = id and selected[id]
        if activity then
            matches = true
            local rank = area and activity.zones[area]
            if rank and (not best or rank < best) then best = rank end
        end
    end
    return best, matches
end

function addon.PlayerMatchesFilters(player, filters, excludedClasses)
    if excludedClasses and excludedClasses[player.class] then return false end
    if not player.roles or not next(filters) then return true end
    for key in pairs(filters) do
        if player.roles[key] ~= false then return true end
    end
    return false
end

local function MatchesGroupClasses(group, excludedClasses)
    if not excludedClasses or not next(excludedClasses) then return true end
    if not group.hasCompleteClasses then return false end
    for class in pairs(excludedClasses) do
        if group.memberClasses[class] then return false end
    end
    return true
end

function addon.FilterGroups(groups, wantedRoles, myRoles, excludedClasses)
    local filterByRole = next(wantedRoles) ~= nil
    if not filterByRole and not myRoles and (not excludedClasses or not next(excludedClasses)) then return groups end
    local visible = {}
    for _, group in ipairs(groups) do
        local hasRole = not filterByRole
        for key in pairs(wantedRoles) do
            if group.filledRoles and group.filledRoles[key] then hasRole = true; break end
        end
        local hasRoom = not myRoles
        if hasRole and myRoles then
            for key, selected in pairs(myRoles) do
                if selected and group.openRoles and group.openRoles[key] then hasRoom = true; break end
            end
        end
        if hasRole and hasRoom and MatchesGroupClasses(group, excludedClasses) then visible[#visible + 1] = group end
    end
    return visible
end

function addon.GroupPlayers(players, filters, excludedClasses)
    local nearby, others = {}, {}
    for _, player in ipairs(players) do
        if addon.PlayerMatchesFilters(player, filters, excludedClasses) then
            local buckets = player.rank and nearby or others
            local key = addon.knownClasses[player.class] and player.class or "UNKNOWN"
            if not buckets[key] then buckets[key] = {} end
            table.insert(buckets[key], player)
        end
    end
    local function sortBuckets(buckets)
        for _, bucket in pairs(buckets) do
            table.sort(bucket, function(a, b)
                local left, right = a.rank or 4, b.rank or 4
                if left ~= right then return left < right end
                if a.name ~= b.name then return a.name < b.name end
                return a.id < b.id
            end)
        end
    end
    sortBuckets(nearby)
    sortBuckets(others)
    return nearby, others
end
