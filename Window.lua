local _, addon = ...
local read = addon.Read
local title = "LFG Party Finder"
local currentView, roleFilters = "players", {}
local groupRoleFilters, roomForMe = {}, false
local window, nativeLauncher
local commentEdit, nativeDraft
local openingNativeFromAddon
local classPage, classPageCount = 1, 1
local parts = {}
local playerGap = 2
local cardHeight, actionWidth = 64, 25
local playerRowHeight = cardHeight + 2
local groupGap, visibleMemberSlots = 4, 5
local memberIconSize, memberStep = 20, 22
local columnsPerPage, groupColumns = 4, 2
local fallbackResultsWidth = 392
local playersTop, groupsTop, resultsBottom = 187, 160, 18
local playersInset, groupsInset, scrollbarInset = 22, 12, 24
local toolbarButtonWidth, toolbarButtonHeight = 82, 27
local white = "Interface\\Buttons\\WHITE8X8"
local neutralName = { r = 0.95, g = 0.95, b = 0.95 }
local detailColor = { 0.68, 0.76, 0.79 }
local dungeonColor = { 0.90, 0.79, 0.52 }

local function surface(frame, r, g, b)
    frame:SetBackdrop({ bgFile = white, edgeFile = white, edgeSize = 1 })
    frame:SetBackdropColor(r, g, b, 1)
    frame:SetBackdropBorderColor(0.25, 0.21, 0.16, 1)
end

local function paintButton(control, active)
    local r, g, b = 0.082, 0.074, 0.062
    if active then r, g, b = 0.23, 0.16, 0.068 end
    control:SetBackdropColor(r, g, b, 1)
    control:SetBackdropBorderColor(r + 0.13, g + 0.13, b + 0.13, 1)
end

local function button(parent, label, width, action, height)
    local control = CreateFrame("Button", nil, parent, "BackdropTemplate")
    control:SetSize(width, height or 27)
    surface(control, 0.082, 0.074, 0.062)
    paintButton(control, false)
    control:SetNormalFontObject(GameFontHighlightSmall)
    control:SetHighlightTexture(white)
    control:GetHighlightTexture():SetVertexColor(0.89, 0.75, 0.39, 0.16)
    control:SetText(label)
    control:SetScript("OnClick", action)
    return control
end

local function SideTab(parent, action)
    local tab = CreateFrame("Frame", nil, parent, "LargeSideTabButtonTemplate")
    tab:EnableMouse(true)
    tab.Icon:SetTexture("Interface\\Icons\\inv_misc_map02")
    tab:SetFillToInterior(true, 30)
    tab.tooltipText = title
    tab:SetChecked(false)
    tab:SetCustomOnMouseUpHandler(function(_, mouseButton, upInside)
        if mouseButton == "LeftButton" and upInside then action() end
    end)
    return tab
end

local function GroupFinderRule(parent, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetAtlas("groupfinder-ScrollLine", true)
    line:SetPoint("LEFT", parent, "TOPLEFT", 8, -y)
    line:SetPoint("RIGHT", parent, "TOPRIGHT", -8, -y)
end

local function text(parent, label, style)
    local control = parent:CreateFontString(nil, "ARTWORK", style or "GameFontNormal")
    control:SetJustifyH("LEFT")
    control:SetText(label)
    return control
end

local function hover(control, label, detail)
    control:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(label)
        if detail then GameTooltip:AddLine(detail, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    control:SetScript("OnLeave", GameTooltip_Hide)
end

local function SameCardEntry(previous, current)
    return previous and current and previous.id == current.id and previous.target == current.target
        and previous.count == current.count and previous.own == current.own and previous.partyGUID == current.partyGUID
        and (previous.activity and previous.activity.id) == (current.activity and current.activity.id)
end

local function ActOnCard(entry)
    local ok, reason = addon.Act(entry)
    if ok == false and reason then UIErrorsFrame:AddMessage(reason, 1, 0.32, 0.24) end
end

local function OpenCardMenu(card, entry)
    if not entry or entry.own or not entry.target then return end
    GameTooltip_Hide()
    MenuUtil.CreateContextMenu(card, function(_, menu)
        menu:CreateTitle(entry.name)
        menu:CreateButton(SEND_MESSAGE or "Send Message", function()
            if card:IsVisible() and SameCardEntry(entry, card.entry) then addon.OpenWhisper(entry) end
        end)
        menu:CreateButton(entry.count == 1 and "Invite to Party" or "Ask to Join", function()
            if card:IsVisible() and SameCardEntry(entry, card.entry) then ActOnCard(entry) end
        end)
    end)
end

local function CaptureCardPress(control, card)
    control:SetScript("OnMouseDown", function(self, mouseButton)
        self.pressedCardEntry = card.entry
        self.pressedCardButton = mouseButton
    end)
end

local function FinishCardPress(control, card, mouseButton)
    local entry, buttonPressed = control.pressedCardEntry, control.pressedCardButton
    control.pressedCardEntry, control.pressedCardButton = nil, nil
    if buttonPressed == mouseButton and control:IsVisible() and SameCardEntry(entry, card.entry) then return card.entry end
end

local function iconCheck(parent, role, label, click, detail)
    local check = CreateFrame("CheckButton", nil, parent)
    check:SetSize(28, 27)
    check:RegisterForClicks("LeftButtonUp")
    local icon = check:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER")
    icon:SetAtlas(role.icon, false)
    check.icon = icon
    local tickPath = "Interface\\Buttons\\UI-CheckBox-Check"
    check:SetCheckedTexture(tickPath)
    check:SetDisabledCheckedTexture(tickPath)
    for _, tick in ipairs({ check:GetCheckedTexture(), check:GetDisabledCheckedTexture() }) do
        tick:ClearAllPoints()
        tick:SetSize(13, 13)
        tick:SetPoint("BOTTOMLEFT", 0, 0)
        tick:SetDrawLayer("OVERLAY")
    end
    check:SetMotionScriptsWhileDisabled(true)
    check:SetScript("OnClick", click)
    hover(check, label, detail)
    return check
end

local function NameColor(entry)
    return RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.class] or neutralName
end

local function AddTooltipLine(value, color)
    GameTooltip:AddLine(value, color[1], color[2], color[3], true)
end

local function SetCardTooltip(control, card, action)
    local function show(self)
        local entry = card.entry
        if not entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local color = NameColor(entry)
        GameTooltip:SetText(entry.name, color.r, color.g, color.b)
        local details = {}
        if entry.count > 1 then
            details[#details + 1] = entry.count .. " players"
        elseif entry.level then
            details[#details + 1] = "Level " .. entry.level
        end
        if entry.specName then
            details[#details + 1] = (entry.count > 1 and "Leader: " or "") .. entry.specName
        end
        if #details > 0 then AddTooltipLine(table.concat(details, " · "), detailColor) end

        local dungeons = entry.listedDungeons or {}
        local dungeon = entry.activity and entry.activity.name or "Unknown"
        AddTooltipLine((#dungeons > 1 and "Dungeons: " or "Dungeon: ") .. dungeon, dungeonColor)
        for index = 2, #dungeons do
            AddTooltipLine(dungeons[index].name, dungeonColor)
        end

        local zone = entry.area or "Unknown"
        if entry.rank then zone = zone .. " (nearby)" end
        AddTooltipLine("Zone: " .. zone, detailColor)
        for _, member in ipairs(entry.members or {}) do
            local role = addon.roles[member.role]
            local class = member.className or (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[member.class])
            local label = role and role.label or "Role unknown"
            if member.name then label = label .. " · " .. member.name:gsub("|", "||") end
            if class then label = label .. " · " .. class end
            if member.specName then label = label .. " · " .. member.specName end
            if member.leader then label = label .. " (leader)" end
            local memberColor = NameColor(member)
            GameTooltip:AddLine(label, memberColor.r, memberColor.g, memberColor.b, true)
        end
        if entry.members and entry.count > #entry.members then
            AddTooltipLine("+" .. (entry.count - #entry.members) .. " more", detailColor)
        end
        if entry.comment then GameTooltip:AddLine("Comment: " .. entry.comment:gsub("|", "||"), 0.95, 0.95, 0.95, true) end
        if action then AddTooltipLine(entry.count == 1 and "Invite to Party" or "Ask to Join", detailColor) end
        GameTooltip:Show()
    end
    local function hide(self)
        if GameTooltip:GetOwner() == self then GameTooltip_Hide() end
    end
    control:SetScript("OnEnter", show)
    control:SetScript("OnLeave", hide)
    control:HookScript("OnHide", function(self)
        self.pressedCardEntry, self.pressedCardButton = nil, nil
        hide(self)
    end)
    return show
end

local function BuildCard(parent, width, group)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetSize(width, cardHeight)
    card:SetBackdrop({ bgFile = white, edgeFile = white, edgeSize = 1 })
    card:EnableMouse(true)
    CaptureCardPress(card, card)
    card:SetScript("OnMouseUp", function(self, mouseButton, upInside)
        local entry = FinishCardPress(self, self, mouseButton)
        if mouseButton == "RightButton" and upInside then OpenCardMenu(self, entry) end
    end)
    card.name = text(card, "", "GameFontHighlightSmall")
    card.name:SetPoint("TOPLEFT", 6, -7)
    card.name:SetWordWrap(false)
    card.commentMark = text(card, "…", "GameFontHighlightSmall")
    card.commentMark:SetPoint("TOPRIGHT", -actionWidth - 4, -7)
    card.commentMark:SetTextColor(unpack(dungeonColor))
    card.nearby = card:CreateTexture(nil, "ARTWORK")
    card.nearby:SetSize(5, 5)
    card.nearby:SetPoint("LEFT", card.name, "LEFT", -9, 0)
    card.nearby:SetColorTexture(1, 0.72, 0.25, 1)
    card.detail = text(card, "", "GameFontHighlightSmall")
    card.detail:SetPoint("TOPLEFT", 6, -22)
    card.detail:SetWordWrap(false)
    card.detail:SetTextColor(unpack(detailColor))
    card.dungeon = text(card, "", "GameFontHighlightSmall")
    card.dungeon:SetPoint("TOPLEFT", 6, -36)
    card.dungeon:SetWordWrap(false)
    card.dungeon:SetTextColor(unpack(dungeonColor))
    card.extraDungeons = text(card, "", "GameFontHighlightSmall")
    card.extraDungeons:SetPoint("TOPRIGHT", -actionWidth - 5, -36)
    card.extraDungeons:SetTextColor(unpack(dungeonColor))
    card.zone = text(card, "", "GameFontHighlightSmall")
    card.zone:SetPoint("TOPLEFT", 6, -49)
    card.zone:SetWordWrap(false)
    card.zone:SetTextColor(unpack(detailColor))
    if group then
        card.members = {}
        for index = 1, visibleMemberSlots do
            local slot = CreateFrame("Frame", nil, card)
            slot:SetSize(memberIconSize, 24)
            slot.roleIcon = slot:CreateTexture(nil, "ARTWORK")
            slot.roleIcon:SetSize(memberIconSize, memberIconSize)
            slot.roleIcon:SetPoint("TOP")
            slot.classBar = slot:CreateTexture(nil, "ARTWORK")
            slot.classBar:SetSize(14, 3)
            slot.classBar:SetPoint("BOTTOM")
            slot.unknownRole = text(slot, "?", "GameFontDisableSmall")
            slot.unknownRole:SetPoint("TOP")
            card.members[index] = slot
        end
        card.memberOverflow = text(card, "", "GameFontHighlightSmall")
        card.memberOverflow:SetPoint("RIGHT", card.members[1], "LEFT", -4, 0)
        card.memberOverflow:SetTextColor(unpack(detailColor))
    else
        card.icons = {}
        for _, role in ipairs(addon.roles) do
            local icon = card:CreateTexture(nil, "ARTWORK")
            icon:SetSize(13, 13)
            icon:SetAtlas(role.icon, false)
            card.icons[role.key] = icon
        end
    end
    card.action = button(card, "+", actionWidth, function(self, mouseButton)
        local entry = FinishCardPress(self, card, mouseButton)
        if not entry then return end
        if mouseButton == "RightButton" then OpenCardMenu(card, entry) else ActOnCard(entry) end
    end, cardHeight - 2)
    CaptureCardPress(card.action, card)
    card.action:SetNormalFontObject(GameFontHighlightLarge)
    card.action:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    card.action:SetPoint("RIGHT", -1, 0)
    card.ShowTooltip = SetCardTooltip(card, card, false)
    card.action.ShowTooltip = SetCardTooltip(card.action, card, true)
    return card
end

local function PaintCard(card, entry, compact, index)
    card.entry = entry
    local color = NameColor(entry)
    card.name:SetTextColor(color.r, color.g, color.b)
    card.name:SetText(entry.name)
    local detail = entry.count > 1 and (entry.count .. " players") or (entry.level and tostring(entry.level) or "")
    local width = card:GetWidth()
    local memberCount = not compact and entry.members and math.min(#entry.members, visibleMemberSlots) or 0
    local overflow = not compact and entry.count > visibleMemberSlots
    local rosterWidth = memberCount * memberStep + (overflow and 23 or 0)
    local textWidth = width - actionWidth - 11 - rosterWidth
    card.detail:SetText(detail)
    card.detail:SetWidth(compact and width - actionWidth - 52 or textWidth)
    local extra = entry.listedDungeons and #entry.listedDungeons - 1 or 0
    card.dungeon:SetText(entry.activity and entry.activity.name or "Unknown dungeon")
    card.dungeon:SetWidth(textWidth - (extra > 0 and 20 or 0))
    if not compact then card.extraDungeons:SetPoint("TOPRIGHT", -actionWidth - 5 - rosterWidth, -36) end
    card.extraDungeons:SetText(extra > 0 and ("+" .. extra) or "")
    card.zone:SetText(entry.area or "Unknown zone")
    card.zone:SetWidth(width - actionWidth - 11)
    local tint = index % 2 == 0 and 0.012 or 0
    card:SetBackdropColor(0.101 + tint, 0.090 + tint, 0.074 + tint, 1)
    local isNearby = compact and entry.rank ~= nil
    card.nearby:SetShown(isNearby)
    local nameLeft = isNearby and 15 or 6
    card.name:SetPoint("TOPLEFT", nameLeft, -7)
    card.commentMark:SetShown(entry.comment ~= nil)
    card.name:SetWidth(width - actionWidth - nameLeft - (entry.comment and 15 or 4))
    card:SetBackdropBorderColor(0.66, 0.56, 0.29, isNearby and 1 or 0)
    if compact then
        local shown = 0
        for _, role in ipairs(addon.roles) do
            local icon = card.icons[role.key]
            local visible = entry.roles ~= nil and entry.roles[role.key] == true
            icon:SetShown(visible)
            if visible then
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", width - actionWidth - 44 + 14 * shown, -20)
                shown = shown + 1
            end
        end
    else
        for slotIndex, slot in ipairs(card.members) do
            local member = entry.members and entry.members[slotIndex]
            local role = member and addon.roles[member.role]
            local class = member and member.class
            local classColor = addon.knownClasses[class] and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            if role then slot.roleIcon:SetAtlas(role.icon, false) end
            if classColor then slot.classBar:SetColorTexture(classColor.r, classColor.g, classColor.b, 1) end
            if member then slot:SetPoint("TOPRIGHT", -actionWidth - 6 - (memberCount - slotIndex) * memberStep, -22) end
            slot.roleIcon:SetShown(role ~= nil)
            slot.unknownRole:SetShown(member ~= nil and role == nil)
            slot.classBar:SetShown(not not classColor)
            slot:SetShown(member ~= nil)
        end
        card.memberOverflow:SetText(overflow and ("+" .. (entry.count - visibleMemberSlots)) or "")
    end
    local actionable = not entry.own and entry.target ~= nil
    card.action:SetShown(actionable)
    local tooltipOwner = GameTooltip:GetOwner()
    if tooltipOwner == card or (actionable and tooltipOwner == card.action) then
        tooltipOwner:ShowTooltip()
    end
end

local function LayoutResults(left, right, top)
    local width = read(window:GetWidth(), "number")
    local availableWidth = width and width > left + right and width - left - right or fallbackResultsWidth
    parts.results:SetPoint("TOPLEFT", left, -top)
    parts.results:SetPoint("BOTTOMRIGHT", -right, resultsBottom)
    parts.content:SetWidth(availableWidth)
    return availableWidth
end

local function RenderResults()
    local count, height = 0, 0
    local nearbyCount, columnsShown = 0, 0
    if currentView == "groups" then
        local groups = parts.visibleGroups or {}
        count = #groups
        if count > 0 then height = math.ceil(count / groupColumns) * (cardHeight + groupGap) - groupGap end
        local windowHeight = read(window:GetHeight(), "number")
        local needsScrollbar = not windowHeight or height > windowHeight - groupsTop - resultsBottom
        local availableWidth = LayoutResults(groupsInset, needsScrollbar and scrollbarInset or groupsInset, groupsTop)
        local width = (availableWidth - groupGap * (groupColumns - 1)) / groupColumns
        for index, entry in ipairs(groups) do
            local card = parts.groupCards[index]
            if not card then
                card = BuildCard(parts.content, width, true)
                parts.groupCards[index] = card
            end
            card:SetWidth(width)
            card:SetPoint("TOPLEFT", (index - 1) % groupColumns * (width + groupGap),
                -math.floor((index - 1) / groupColumns) * (cardHeight + groupGap))
            PaintCard(card, entry, false, index)
            card:Show()
        end
    end
    for index = count + 1, #parts.groupCards do parts.groupCards[index]:Hide() end

    if currentView == "players" then
        local availableWidth = LayoutResults(playersInset, playersInset, playersTop)
        local columnWidth = (availableWidth - playerGap * (columnsPerPage - 1)) / columnsPerPage
        local columnStep = columnWidth + playerGap
        parts.classHeaders:SetWidth(availableWidth)
        local nearby, others = addon.GroupPlayers(addon.players or {}, roleFilters, addon.db.excludedClasses)
        local occupied = 0
        for _, class in ipairs(addon.classOrder) do
            if nearby[class] or others[class] then occupied = occupied + 1 end
        end
        classPageCount = math.max(1, math.ceil(occupied / columnsPerPage))
        classPage = math.min(classPage, classPageCount)
        parts.pages:SetShown(classPageCount > 1)
        parts.pageLabel:SetShown(classPageCount > 1)
        parts.pageLabel:SetText(classPage .. " / " .. classPageCount)
        parts.previousPage:SetEnabled(classPage > 1)
        parts.nextPage:SetEnabled(classPage < classPageCount)
        parts.previousPage:SetAlpha(classPage > 1 and 1 or 0.35)
        parts.nextPage:SetAlpha(classPage < classPageCount and 1 or 0.35)
        local firstColumn = (classPage - 1) * columnsPerPage
        for _, class in ipairs(addon.classOrder) do
            local column = parts.columns[class]
            local near, far = nearby[class] or {}, others[class] or {}
            local size = #near + #far
            local visible = size > 0 and columnsShown >= firstColumn and columnsShown < firstColumn + columnsPerPage
            column:SetShown(visible)
            column.heading:SetShown(visible)
            if visible then
                local x = (columnsShown - firstColumn) * columnStep
                column:SetWidth(columnWidth)
                column.heading:SetWidth(columnWidth)
                column:ClearAllPoints()
                column:SetPoint("TOPLEFT", x, 0)
                column:SetPoint("BOTTOMLEFT", parts.playerColumns, "BOTTOMLEFT", x, 0)
                column.heading:ClearAllPoints()
                column.heading:SetPoint("TOPLEFT", x, 0)
                column.count:SetText(size)
                height = math.max(height, (size - 1) * playerRowHeight + cardHeight)
            end
            if size > 0 then columnsShown = columnsShown + 1 end
            nearbyCount = nearbyCount + #near
            for index = 1, visible and size or 0 do
                local entry = near[index] or far[index - #near]
                local card = column.cards[index]
                if not card then card = BuildCard(column, columnWidth); column.cards[index] = card end
                card:SetWidth(columnWidth)
                card:ClearAllPoints()
                card:SetPoint("TOPLEFT", 0, -(index - 1) * playerRowHeight)
                PaintCard(card, entry, true, index)
                card:Show()
            end
            for index = size + 1, #column.cards do column.cards[index]:Hide() end
            count = count + size
        end
    else
        parts.pages:Hide()
        parts.pageLabel:Hide()
    end
    parts.content:SetHeight(math.max(1, height))
    local status = addon.status
    if not status then
        if currentView == "players" then
            if not addon.players then
                status = "Choose a dungeon and click Search."
            elseif count > 0 then
                status = (count == 1 and "1 player" or count .. " players") .. " found  ·  " .. nearbyCount .. " nearby"
            elseif #addon.players > 0 then
                status = "No players match your filters."
            else
                status = "No players found for the selected dungeons. Try Search again or choose another dungeon."
            end
        else
            if count > 0 then
                status = count == 1 and "1 group" or count .. " groups"
            elseif addon.groups and #addon.groups > 0 then
                status = "No groups match your filters."
            else
                status = addon.groups and "No groups found for the selected dungeons." or "Choose a dungeon and click Search."
            end
        end
    end
    parts.status:SetText(status)
end

function addon.Refresh()
    if not window or not window:IsVisible() then return end
    parts.results:SetShown(currentView == "players" or currentView == "groups")
    parts.status:SetShown(parts.results:IsShown())
    parts.roleFilter:SetShown(currentView == "players")
    parts.groupFilter:SetShown(currentView == "groups")
    parts.classHeaders:SetShown(currentView == "players")
    parts.playerColumns:SetShown(currentView == "players")
    parts.settings:SetShown(currentView == "settings")
    parts.toolbar:SetShown(currentView ~= "settings")
    for key, tab in pairs(parts.tabs) do paintButton(tab, key == currentView) end

    local playerLabel, groupLabel = "Players", "Groups"
    local grouped, active, waiting = addon.ListingState()
    local listedSolo = grouped == false and active == true
    local roles
    if listedSolo then
        roles = addon.NativeListingRoles()
    else
        roles = addon.ListingRoles()
    end
    local excludedClasses = addon.db.excludedClasses
    for class, check in pairs(parts.classChecks) do
        local included = not excludedClasses[class]
        check:SetChecked(included)
        check.icon:SetDesaturated(not included)
        check.icon:SetAlpha(included and 1 or 0.42)
    end
    local languageCount = 0
    for _ in pairs(addon.db.searchLanguages) do languageCount = languageCount + 1 end
    parts.languageFilter:OverrideText(languageCount == 0 and "All languages" or ("Languages (" .. languageCount .. ")"))
    local hasRoomRoles = roles ~= nil and (roles.tank or roles.healer or roles.dps)
    parts.roomFilter:SetEnabled(hasRoomRoles)
    parts.roomFilter:SetChecked(roomForMe and hasRoomRoles)
    parts.visibleGroups = addon.FilterGroups(addon.groups or {}, groupRoleFilters,
        roomForMe and hasRoomRoles and roles or nil, excludedClasses)
    if addon.players and (not addon.status or #addon.players > 0) then
        local playerCount = 0
        for _, player in ipairs(addon.players) do
            if addon.PlayerMatchesFilters(player, roleFilters, excludedClasses) then playerCount = playerCount + 1 end
        end
        playerLabel = playerLabel .. " (" .. playerCount .. ")"
    end
    if addon.groups and (not addon.status or #addon.groups > 0) then
        groupLabel = groupLabel .. " (" .. #parts.visibleGroups .. ")"
    end
    parts.tabs.players:SetText(playerLabel)
    parts.tabs.groups:SetText(groupLabel)

    local activities = addon.SelectedActivities()
    parts.automaticDungeon:SetChecked(not addon.db.manualDungeonSelection)
    local label = activities[1] and activities[1].name or "Choose dungeons"
    if #activities > 1 then label = label .. " +" .. (#activities - 1) end
    parts.activity:OverrideText(label)
    local showListing = currentView ~= "settings" and (#activities > 0 or active == true or waiting ~= nil)
    parts.listingControls:SetShown(showListing)
    local savedComment = read(addon.db.listingComment, "string")
    parts.savedCommentMark:SetShown(savedComment ~= nil)
    if parts.savedComment:GetText() ~= (savedComment or "") then
        parts.savedComment:SetText(savedComment or "")
    end
    parts.myRoles:SetShown(currentView == "groups" or (showListing and grouped == false))
    parts.myRolesLabel:SetText(listedSolo and "Listed" or "My roles")
    for _, role in ipairs(addon.roles) do
        local check = parts.roleChoices[role.key]
        check:SetChecked(roles ~= nil and roles[role.key] == true)
        check:SetEnabled(not listedSolo and not waiting and grouped ~= nil)
    end
    if showListing then
        local buttonLabel = grouped and "List Party" or "List Me"
        local canManage = addon.CanManageListing(grouped)
        local friendly = addon.db.listingNewPlayerFriendly
        if active == true then
            local entry = read(C_LFGList.GetActiveEntryInfo(), "table")
            friendly = entry and read(entry.newPlayerFriendly, "boolean") == true
        end
        parts.newPlayerFriendly:SetChecked(friendly == true)
        parts.newPlayerFriendly:SetEnabled(canManage and active == false and not waiting)
        if waiting then
            buttonLabel = waiting.kind == "remove" and "Unlisting…" or "Listing…"
        elseif active == true then
            buttonLabel = canManage and "Unlist" or "Listed"
        end
        parts.createListing:SetText(buttonLabel)
        parts.createListing:SetEnabled(not waiting and (active == false or (active == true and canManage)))
        parts.updateListingStatus(active)
    end
    for key, check in pairs(parts.roleChecks) do check:SetChecked(roleFilters[key] == true) end
    parts.header:EnableMouseWheel(currentView == "players")
    if currentView ~= "players" then parts.pageLabel:Hide() end
    if parts.results:IsShown() then RenderResults() end
end

local function IsResultsViewVisible()
    return window and window:IsVisible() and (currentView == "players" or currentView == "groups")
end

local function ContinueOpeningSearch()
    if IsResultsViewVisible() then return true end
    addon.openedBefore = nil
    return false
end

local function SearchOnFirstOpen()
    if addon.openedBefore or not IsResultsViewVisible() then return end
    if addon.Search(ContinueOpeningSearch) then addon.openedBefore = true end
end

local function SelectView(view)
    if currentView == view then return end
    currentView = view
    parts.results:SetVerticalScroll(0)
    addon.Refresh()
    SearchOnFirstOpen()
end

local function OpenNativeListing()
    if InCombatLockdown() then
        print(title .. ": open Group Finder after combat.")
        return
    end
    nativeDraft = nil
    if not LFGParentFrame then GroupFinderVanillaStyle_LoadUI() end
    if not LFGVanilla_ToggleFrame then return end
    if LFGParentFrame and LFGParentFrame:IsShown() then
        LFGParentFrameTab1_OnClick()
    else
        openingNativeFromAddon = true
        local ok, reason = pcall(LFGVanilla_ToggleFrame, 1)
        openingNativeFromAddon = nil
        if not ok then error(reason, 0) end
    end
    if LFGParentFrame and LFGParentFrame:IsVisible() then
        if window then window:Hide() end
        return true
    end
end

function addon.EndNativeDraft()
    nativeDraft = nil
end

local function ListingError(reason)
    UIErrorsFrame:AddMessage(reason, 1, 0.32, 0.24)
end

local function OpenListingDetails()
    local activities = addon.SelectedActivities()
    local allowed, reason = addon.CanCreateListing(activities)
    if not allowed then ListingError(reason); return end
    local grouped = addon.ListingState()
    local roles = addon.ListingRoles()
    if grouped == false and not (roles.tank or roles.healer or roles.dps) then
        ListingError("Choose at least one role.")
        return
    end
    if not OpenNativeListing() or not LFGListingFrame:IsVisible() then return end

    if grouped == false then
        if not addon.ApplySoloListingRoles(roles) then
            ListingError("WoW did not accept those roles.")
            return
        end
        LFGListingFrame:LoadSoloRoles()
    end

    local data = addon.ListingData(activities)
    LFGListingFrame:SetCategorySelection(addon.dungeonCategory)
    LFGListingFrame:SetAllActivities(false)
    for _, id in ipairs(data.activityIDs) do LFGListingFrame:SetActivity(id, true, true, true) end
    local view = LFGListingFrame.ActivityView
    LFGListingActivityView_OnPlayStyleSelectedInternal(view, data.generalPlaystyle)
    if view.PlayStyleDropdown then view.PlayStyleDropdown:GenerateMenu() end
    LFGListingFrame.voiceMode = data.voiceMode
    local friendlyButton = LFGListingFrame.NewPlayerFriendlyButton
    if friendlyButton and friendlyButton.CheckButton then
        friendlyButton.CheckButton:SetChecked(data.newPlayerFriendly)
    end
    if view.VoiceChatDropdown then view.VoiceChatDropdown:GenerateMenu() end
    if view:IsShown() then
        LFGListingActivityView_UpdateActivities(view)
        local edit = view.Comment.EditBox
        if commentEdit ~= edit then
            commentEdit = edit
            edit:HookScript("OnTextChanged", function(self, fromUser)
                if not fromUser or not nativeDraft or nativeDraft.edit ~= self or not view:IsVisible() then return end
                local _, active = addon.ListingState()
                if active ~= false then nativeDraft = nil; return end
                local value = addon.NativeListingComment()
                if value ~= nil then addon.SaveListingComment(value) end
            end)
            view:HookScript("OnHide", function()
                local draft = nativeDraft
                if not draft or draft.edit ~= edit then return end
                -- Blizzard briefly hides and shows this view during roster updates.
                C_Timer.After(0, function()
                    if nativeDraft == draft and not view:IsVisible() then nativeDraft = nil end
                end)
            end)
        end
        if edit:IsEnabled() then
            nativeDraft = { edit = edit }
            edit:SetFocus()
            local post = LFGListingFrame.PostButton
            local label = post and read(post:GetText(), "string")
            UIErrorsFrame:AddMessage("Enter your saved comment here, then click " .. (label or "the listing button") .. ".",
                1, 0.82, 0)
        else
            ListingError("WoW has disabled the comment field for this listing.")
        end
    end
end

local function BuildSettings(parent)
    local pane = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    pane:SetPoint("TOPLEFT", 12, -48)
    pane:SetPoint("BOTTOMRIGHT", -12, 14)
    surface(pane, 0.10, 0.085, 0.068)
    local heading = text(pane, "Settings", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 16, -15)
    GroupFinderRule(pane, 44)
    local function checkbox(y, label, detail, click)
        local check = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
        check:SetSize(25, 25)
        check:SetPoint("TOPLEFT", 14, -y)
        local caption = text(check, label, "GameFontHighlight")
        caption:SetPoint("LEFT", check, "RIGHT", 4, 0)
        check:SetHitRectInsets(0, -305, 0, 0)
        check:SetScript("OnClick", function(self) click(self:GetChecked() == true) end)
        hover(check, label, detail)
        return check
    end
    parts.automaticDungeon = checkbox(54, "Automatically select the first recommended dungeon",
        "Uses the first dungeon recommended for your level.", addon.SetAutomaticDungeonSelection)
    local selectionHint = text(pane, "When off, only your manually picked dungeons stay selected.", "GameFontDisableSmall")
    selectionHint:SetPoint("TOPLEFT", 44, -80)
    local whisper = checkbox(102, "Whisper on invite", "Send the message when you click + on a player.",
        function(enabled) addon.db.inviteWhisper = enabled end)
    whisper:SetChecked(addon.db.inviteWhisper)
    local function template(y, key, label, tokens)
        local caption = text(pane, label)
        caption:SetPoint("TOPLEFT", 12, -y)
        local edit = CreateFrame("EditBox", nil, pane, "InputBoxTemplate")
        edit:SetSize(296, 28)
        edit:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 5, -7)
        edit:SetAutoFocus(false)
        edit:SetMaxLetters(255)
        edit:SetText(addon.db[key])
        edit:SetScript("OnTextChanged", function(self, fromUser)
            if fromUser then addon.db[key] = self:GetText() end
        end)
        edit:SetScript("OnEnterPressed", edit.ClearFocus)
        edit:SetScript("OnEscapePressed", edit.ClearFocus)
        local reset = button(pane, "Reset", 72, function()
            addon.db[key] = addon.defaults[key]
            edit:SetText(addon.db[key])
        end)
        reset:SetPoint("LEFT", edit, "RIGHT", 9, 0)
        local hint = text(pane, tokens, "GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -6)
    end
    template(139, "inviteText", "Invite message", "%dungeon%   %party%   %needed%")
    template(233, "askText", "Ask to join message", "%level%   %talents%   %class%")
    local caption = text(pane, "Listing comment")
    caption:SetPoint("TOPLEFT", 12, -327)
    local edit = CreateFrame("EditBox", nil, pane, "InputBoxTemplate")
    edit:SetSize(377, 28)
    edit:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 5, -7)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(255)
    edit:SetScript("OnTextChanged", function(self, fromUser)
        if not fromUser then return end
        local value = self:GetText()
        if canaccessvalue(value) and type(value) == "string" then addon.SaveListingComment(value) end
    end)
    edit:SetScript("OnEnterPressed", edit.ClearFocus)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    parts.savedComment = edit
    local hint = text(pane, "Saved here. WoW may ask you to enter it again when listing.", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -6)
    return pane
end

local function BuildListingControls(parent)
    local controls = CreateFrame("Frame", nil, parent)
    controls:SetAllPoints()
    local options = CreateFrame("DropdownButton", nil, controls, "LFGOptionsButton")
    options:SetPoint("TOPRIGHT", -12, -48)
    options:SetSize(28, toolbarButtonHeight)
    options.Icon:SetSize(16, 16)
    options.Icon:SetPoint("CENTER")
    local mark = options:CreateTexture(nil, "OVERLAY")
    mark:SetSize(5, 5)
    mark:SetPoint("TOPRIGHT", -3, -3)
    mark:SetColorTexture(1, 0.72, 0.25, 1)
    parts.savedCommentMark = mark

    local submit = button(controls, "List Me", toolbarButtonWidth, function()
        local _, active, waiting = addon.ListingState()
        if waiting then return end
        if active == true then
            local ok, reason = addon.RemoveListing()
            if not ok then ListingError(reason) end
            return
        end
        local ok, reason, needsComment = addon.CreateListing()
        if needsComment then OpenListingDetails() elseif not ok then ListingError(reason) end
    end, toolbarButtonHeight)
    submit:SetPoint("RIGHT", options, "LEFT", -6, 0)
    paintButton(submit, true)
    parts.createListing = submit
    local light = submit:CreateTexture(nil, "OVERLAY")
    light:SetSize(6, 6)
    light:SetPoint("LEFT", 6, 0)
    light:SetTexture(white)
    local mask = submit:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(light)
    light:AddMaskTexture(mask)
    local pulse = light:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.55)
    fade:SetToAlpha(1)
    fade:SetDuration(1.2)
    fade:SetSmoothing("IN_OUT")
    submit:HookScript("OnHide", function() pulse:Stop() end)
    parts.updateListingStatus = function(active)
        light:SetShown(active ~= nil)
        if active == true then
            light:SetVertexColor(0.32, 0.93, 0.41)
            if not pulse:IsPlaying() then pulse:Play() end
        else
            pulse:Stop()
            light:SetVertexColor(1, 0.32, 0.30)
        end
    end

    options:HookScript("OnEnter", function(self)
        local saved = read(addon.db.listingComment, "string")
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Listing options")
        if saved then GameTooltip:AddLine(saved:gsub("|", "||"), 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    options:HookScript("OnLeave", function() GameTooltip_Hide() end)
    options:SetupMenu(function(_, menu)
        local styles = menu:CreateButton("Playstyle")
        for _, value in ipairs({ {"Learning", "Learning"}, {"FunRelaxed", "Relaxed"},
            {"FunSerious", "Competitive"}, {"Expert", "Expert"} }) do
            local key, fallback = value[1], value[2]
            local label = GetGeneralPlaystyleString and GetGeneralPlaystyleString(Enum.LFGEntryGeneralPlaystyle[key]) or fallback
            styles:CreateRadio(label, function(choice) return addon.db.listingPlaystyle == choice end,
                function(choice) addon.db.listingPlaystyle = choice end, key)
        end
        local voice = menu:CreateButton("Voice chat")
        for _, value in ipairs({ {"None", VOICE_CHAT_MODE_NONE or "None"}, {"Discord", VOICE_CHAT_MODE_DISCORD or "Discord"},
            {"Legacy", VOICE_CHAT_MODE_LEGACY or "In-game"}, {"Custom", VOICE_CHAT_MODE_CUSTOM or "Custom"} }) do
            voice:CreateRadio(value[2], function(choice) return addon.db.listingVoice == choice end,
                function(choice) addon.db.listingVoice = choice end, value[1])
        end
        menu:CreateDivider()
        menu:CreateButton("Comment…", function() SelectView("settings"); parts.savedComment:SetFocus() end)
    end)

    local myRoles = CreateFrame("Frame", nil, parent)
    myRoles:SetSize(135, 27)
    local friendly = iconCheck(controls, { icon = "UI-LFG-RoleIcon-Leader" }, "New Player Friendly", function(self)
        addon.db.listingNewPlayerFriendly = self:GetChecked() == true
    end, LFG_LIST_NEW_PLAYER_FRIENDLY_TOOLTIP or "Welcome players who are new to the dungeon.")
    friendly:SetPoint("TOPRIGHT", -12, -77)
    parts.newPlayerFriendly = friendly
    myRoles:SetPoint("RIGHT", friendly, "LEFT", -4, 0)
    parts.myRolesLabel = text(myRoles, "My roles", "GameFontHighlightSmall")
    parts.myRolesLabel:SetPoint("LEFT")
    for index, role in ipairs(addon.roles) do
        local check = iconCheck(myRoles, role, role.label, function(self)
            addon.SetListingRole(role.key, self:GetChecked() == true)
        end, "Used by Room for me and when listing solo. While listed solo, the checked icons show your current listing roles.")
        check:SetPoint("LEFT", 47 + (index - 1) * 30, 0)
        parts.roleChoices[role.key] = check
    end
    parts.myRoles = myRoles
    return controls
end

local function BuildContents()
    parts.tabs, parts.roleChecks, parts.roleChoices, parts.groupCards, parts.columns = {}, {}, {}, {}, {}
    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(playersTop)
    parts.header = header
    for index, view in ipairs({{"players", "Players"}, {"groups", "Groups"}, {"settings", "Settings"}}) do
        local tab = button(header, view[2], 138, function() SelectView(view[1]) end)
        tab:SetPoint("TOPLEFT", 12 + (index - 1) * 146, -12)
        parts.tabs[view[1]] = tab
    end
    local toolbar = CreateFrame("Frame", nil, header)
    toolbar:SetAllPoints()
    parts.toolbar = toolbar
    local activity = CreateFrame("DropdownButton", nil, toolbar, "WowStyle1DropdownTemplate")
    activity:SetPoint("LEFT", toolbar, "TOPLEFT", 12, -48 - toolbarButtonHeight / 2)
    activity:SetWidth(216)
    activity:SetDefaultText("Choose dungeons")
    activity:SetupMenu(function(dropdown, menu)
        local allLevels = menu:CreateCheckbox("Show all levels", function()
            return addon.db.showAllLevels
        end, function()
            local before = addon.SelectedActivities()
            addon.db.showAllLevels = not addon.db.showAllLevels
            local after = addon.SelectedActivities()
            local ids = {}
            for _, entry in ipairs(before) do ids[entry.id] = true end
            local changed = #before ~= #after
            for _, entry in ipairs(after) do if not ids[entry.id] then changed = true end end
            if changed then
                classPage = 1
                parts.results:SetVerticalScroll(0)
                addon.SelectionChanged()
            else
                addon.Refresh()
            end
            -- Replacing an open scrollable menu can leave its old row positions in use.
            -- Let the menu finish closing before the dropdown builds the new list.
            C_Timer.After(0, function()
                if dropdown:IsVisible() and not dropdown:IsMenuOpen() then dropdown:OpenMenu() end
            end)
        end)
        allLevels:SetSelectionIgnored()
        allLevels:SetResponse(MenuResponse.Close)
        menu:CreateDivider()
        local entries = addon.Activities()
        if #entries == 0 then menu:CreateTitle("No dungeons for this level"); return end
        menu:SetScrollMode(280)
        for _, entry in ipairs(entries) do
            local range = entry.min > 0 and ("  (" .. entry.min .. "–" .. entry.max .. ")") or ""
            menu:CreateCheckbox(entry.name .. range, function(id)
                    if addon.db.manualDungeonSelection then return addon.db.activities[id] == true end
                    local automatic = addon.SelectedActivities(entries)[1]
                    return automatic ~= nil and id == automatic.id
                end,
                function(id)
                    parts.results:SetVerticalScroll(0)
                    classPage = 1
                    addon.ToggleActivity(id)
                end, entry.id)
        end
    end)
    parts.activity = activity
    local search = button(toolbar, "Search", toolbarButtonWidth, function()
        if currentView == "settings" then SelectView("players") end
        parts.results:SetVerticalScroll(0)
        classPage = 1
        if addon.Search() then addon.openedBefore = true end
    end, toolbarButtonHeight)
    paintButton(search, true)

    local roleFilter = CreateFrame("Frame", nil, header)
    roleFilter:SetSize(150, 27)
    roleFilter:SetPoint("LEFT", header, "TOPLEFT", 14, -90)
    local filterLabel = text(roleFilter, "Find roles", "GameFontHighlightSmall")
    filterLabel:SetPoint("LEFT")
    for index, role in ipairs(addon.roles) do
        local check = iconCheck(roleFilter, role, "Show " .. role.label, function(self)
            classPage = 1
            roleFilters[role.key] = self:GetChecked() == true or nil
            parts.results:SetVerticalScroll(0)
            addon.Refresh()
        end)
        check:SetPoint("LEFT", 62 + (index - 1) * 30, 0)
        parts.roleChecks[role.key] = check
    end
    parts.roleFilter = roleFilter

    local groupFilter = CreateFrame("Frame", nil, header)
    groupFilter:SetSize(253, 27)
    groupFilter:SetPoint("LEFT", header, "TOPLEFT", 14, -90)
    text(groupFilter, "Has roles", "GameFontHighlightSmall"):SetPoint("LEFT")
    local function refreshGroupFilters()
        parts.results:SetVerticalScroll(0)
        addon.Refresh()
    end
    for index, role in ipairs(addon.roles) do
        local check = iconCheck(groupFilter, role, "Has " .. role.label, function(self)
            groupRoleFilters[role.key] = self:GetChecked() == true or nil
            refreshGroupFilters()
        end, "Shows groups with at least one of the checked roles already filled.")
        check:SetPoint("LEFT", 57 + (index - 1) * 30, 0)
    end
    local room = CreateFrame("CheckButton", nil, groupFilter, "UICheckButtonTemplate")
    room:SetSize(21, 21)
    room:SetPoint("LEFT", 151, 0)
    local roomLabel = text(groupFilter, "Room for me", "GameFontHighlightSmall")
    roomLabel:SetPoint("LEFT", room, "RIGHT", 4, 0)
    room:SetHitRectInsets(0, -78, 0, 0)
    room:SetScript("OnClick", function(self)
        roomForMe = self:GetChecked() == true
        refreshGroupFilters()
    end)
    hover(room, "Room for me", "Shows groups with a slot for one of the roles checked on the right. Select at least one role to use this filter.")
    parts.roomFilter = room
    parts.groupFilter = groupFilter

    parts.classHeaders = CreateFrame("Frame", nil, header)
    parts.classHeaders:SetPoint("TOPLEFT", playersInset, -164)
    parts.classHeaders:SetSize(fallbackResultsWidth, 20)
    local pages = CreateFrame("Frame", nil, parts.classHeaders)
    pages:SetAllPoints()
    local function turnPage(direction)
        local nextPage = math.max(1, math.min(classPage + direction, classPageCount))
        if nextPage == classPage then return end
        classPage = nextPage
        parts.results:SetVerticalScroll(0)
        addon.Refresh()
    end
    header:SetScript("OnMouseWheel", function(_, delta)
        if currentView == "players" and delta ~= 0 then turnPage(delta > 0 and -1 or 1) end
    end)
    parts.previousPage = button(pages, "‹", 18, function() turnPage(-1) end, 20)
    parts.previousPage:SetPoint("RIGHT", pages, "LEFT", -2, 0)
    parts.nextPage = button(pages, "›", 18, function() turnPage(1) end, 20)
    parts.nextPage:SetPoint("LEFT", pages, "RIGHT", 2, 0)
    hover(parts.previousPage, "Previous classes")
    hover(parts.nextPage, "Next classes")
    parts.pageLabel = text(header, "", "GameFontHighlightSmall")
    parts.pageLabel:SetPoint("TOPRIGHT", -22, -141)
    parts.pages = pages

    parts.classChecks = {}
    for index, class in ipairs(addon.classOrder) do
        if addon.knownClasses[class] then
            local className = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
            local icon = { icon = "groupfinder-icon-class-" .. class:lower() }
            local check = iconCheck(toolbar, icon, className or class, function(self)
                addon.db.excludedClasses[class] = not self:GetChecked() or nil
                classPage = 1
                parts.results:SetVerticalScroll(0)
                addon.Refresh()
            end, "Click to show or hide this class in Players and Groups.")
            check:SetPoint("LEFT", toolbar, "TOPLEFT", 12 + (index - 1) * 29, -119)
            parts.classChecks[class] = check
        end
    end
    local languageFilter = CreateFrame("DropdownButton", nil, toolbar, "WowStyle1DropdownTemplate")
    languageFilter:SetPoint("RIGHT", toolbar, "TOPRIGHT", -12, -119)
    languageFilter:SetWidth(140)
    languageFilter:SetDefaultText("All languages")
    local function languageChanged()
        classPage = 1
        parts.results:SetVerticalScroll(0)
        addon.SelectionChanged()
    end
    languageFilter:SetupMenu(function(_, menu)
        local all = menu:CreateCheckbox("All languages", function() return not next(addon.db.searchLanguages) end, function()
            if not next(addon.db.searchLanguages) then return end
            addon.db.searchLanguages = {}
            languageChanged()
        end)
        all:SetSelectionIgnored()
        menu:CreateDivider()
        for _, locale in ipairs(addon.searchLocales) do
            local option = menu:CreateCheckbox(locale[2], function(code) return addon.db.searchLanguages[code] == true end,
                function(code)
                    local selected = addon.db.searchLanguages
                    selected[code] = not selected[code] or nil
                    languageChanged()
                end, locale[1])
            option:SetSelectionIgnored()
        end
    end)
    parts.languageFilter = languageFilter
    parts.status = text(header, "", "GameFontHighlightSmall")
    parts.status:SetPoint("TOPLEFT", 12, -141)
    parts.status:SetPoint("TOPRIGHT", -65, -141)
    parts.status:SetTextColor(0.80, 0.74, 0.64)
    local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    scroll.scrollBarHideable = true
    ScrollFrame_OnScrollRangeChanged(scroll, 0, 0)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        if delta == 0 then return end
        local range = read(self:GetVerticalScrollRange(), "number")
        if currentView == "players" and range and range < 1 then
            turnPage(delta > 0 and -1 or 1)
        else
            ScrollFrameTemplate_OnMouseWheel(self, delta)
        end
    end)
    scroll:SetPoint("TOPLEFT", playersInset, -playersTop)
    scroll:SetPoint("BOTTOMRIGHT", -playersInset, resultsBottom)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(fallbackResultsWidth, 1)
    scroll:SetScrollChild(content)
    parts.results, parts.content = scroll, content
    parts.playerColumns = CreateFrame("Frame", nil, content)
    parts.playerColumns:SetAllPoints()
    for _, class in ipairs(addon.classOrder) do
        local column = CreateFrame("Frame", nil, parts.playerColumns)
        parts.columns[class] = column
        column.cards = {}
        local heading = CreateFrame("Frame", nil, parts.classHeaders, "BackdropTemplate")
        heading:SetHeight(20)
        surface(heading, 0.15, 0.12, 0.085)
        column.heading = heading
        if class ~= "UNKNOWN" then
            local icon = heading:CreateTexture(nil, "ARTWORK")
            icon:SetSize(15, 15)
            icon:SetPoint("CENTER", -8, 0)
            icon:SetAtlas("groupfinder-icon-class-" .. class:lower(), false)
        else
            local unknown = text(heading, "?", "GameFontHighlightSmall")
            unknown:SetPoint("CENTER", -8, 0)
        end
        column.count = text(heading, "", "GameFontDisableSmall")
        column.count:SetPoint("LEFT", heading, "CENTER", 4, 0)
    end
    parts.settings = BuildSettings(window)
    parts.listingControls = BuildListingControls(toolbar)
    search:SetPoint("RIGHT", parts.createListing, "LEFT", -8, 0)
    window:HookScript("OnSizeChanged", function()
        if scroll:IsVisible() then RenderResults() end
    end)
end

local showEmbedded

local function AddNativeLauncher()
    local parent = LFGParentFrame
    if nativeLauncher or not parent or not parent.ListingTab or not parent.BrowsingTab or not parent.WhoListingTab then return end

    window = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    window:Hide()
    window:SetPoint("TOPLEFT", 2, -26)
    window:SetPoint("BOTTOMRIGHT", -2, 2)
    window:SetFrameStrata("DIALOG")
    window:EnableMouse(true)
    window:EnableMouseWheel(true)
    surface(window, 0.066, 0.052, 0.039)
    local art = window:CreateTexture(nil, "BACKGROUND", nil, 1)
    art:SetAtlas("groupfinder-background")
    art:SetPoint("TOPLEFT", 1, -1)
    art:SetPoint("BOTTOMRIGHT", -1, 1)
    art:SetAlpha(0.45)

    local nativeTabs = { parent.ListingTab, parent.BrowsingTab, parent.WhoListingTab }
    local selectionAlpha = {}
    window:SetScript("OnShow", function()
        for _, tab in ipairs(nativeTabs) do
            local texture = tab.SelectedTexture
            local alpha = texture and read(texture:GetAlpha(), "number")
            if alpha then
                selectionAlpha[texture] = alpha
                texture:SetAlpha(0)
            end
        end
        nativeLauncher:SetChecked(true)
    end)
    window:SetScript("OnHide", function()
        for texture, alpha in pairs(selectionAlpha) do texture:SetAlpha(alpha) end
        selectionAlpha = {}
        nativeLauncher:SetChecked(false)
    end)

    showEmbedded = function(view)
        if not addon.db then return end
        if not parts.toolbar then BuildContents() end
        if view and view ~= currentView then
            currentView = view
            parts.results:SetVerticalScroll(0)
        end
        window:Show()
        addon.Refresh()
        SearchOnFirstOpen()
    end
    nativeLauncher = SideTab(parent, function()
        if window:IsShown() then window:Hide() else showEmbedded() end
    end)
    nativeLauncher:SetPoint("BOTTOMLEFT", parent.ListingTab, "TOPLEFT", 0, 2)

    local function ReturnToNative(_, mouseButton, upInside)
        if mouseButton == "LeftButton" and upInside and window:IsShown() then
            window:Hide()
        end
    end
    for _, tab in ipairs(nativeTabs) do tab:HookScript("OnMouseUp", ReturnToNative) end
    parent:HookScript("OnHide", function()
        if window:IsShown() then window:Hide() end
    end)
    hooksecurefunc("LFGVanilla_ShowFrame", function(tab)
        if (tab == 2 or tab == 3) and window:IsShown() then window:Hide() end
    end)
    -- TOGGLEGROUPFINDER passes tab 1. Run after Blizzard’s toggle so the
    -- native window still opens and closes through its own panel manager.
    hooksecurefunc("LFGVanilla_ToggleFrame", function(tab)
        if openingNativeFromAddon or not parent:IsShown() or InCombatLockdown() then return end
        if tab == 1 then
            if window:IsShown() then
                -- Native listing updates can select its browser under the overlay.
                -- The outer toggle has returned to tab 1, so finish the user's close.
                openingNativeFromAddon = true
                local ok, reason = pcall(LFGVanilla_ToggleFrame, 1)
                openingNativeFromAddon = nil
                if not ok then error(reason, 0) end
            else
                showEmbedded("players")
            end
        end
    end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("LFG_LIST_AVAILABILITY_UPDATE")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:SetScript("OnEvent", function(self, event, addonName)
    if event == "PLAYER_LOGIN" then
        addon.InitializeSettings()
        AddNativeLauncher()
    elseif event == "ADDON_LOADED" and addonName == "Blizzard_GroupFinder_VanillaStyle" then
        AddNativeLauncher()
    elseif event == "PLAYER_REGEN_ENABLED" or event == "LFG_LIST_AVAILABILITY_UPDATE" then
        if not addon.db then return end
        if event == "PLAYER_REGEN_ENABLED" then addon.Refresh() end
        SearchOnFirstOpen()
    end
    if nativeLauncher then self:UnregisterEvent("ADDON_LOADED") end
end)

SLASH_PARTYFINDERFOREVER1 = "/pff"
SlashCmdList.PARTYFINDERFOREVER = function(message)
    local view = type(message) == "string" and message:match("^%s*settings%s*$") and "settings" or nil
    if not LFGParentFrame or not LFGParentFrame:IsShown() then
        if not OpenNativeListing() then return end
    end
    if showEmbedded then showEmbedded(view) end
end
