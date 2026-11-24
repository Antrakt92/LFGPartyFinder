local _, addon = ...
local read = addon.Read
local title = "LFG Party Finder"
local currentView, roleFilters, viewRevision = "players", {}, 0
local groupRoleFilters = {}
local window, nativeLauncher
local commentEdit, commentPost, commentListing, nativeDraft, inlineComposer
local pendingPostButton, pendingBackButton
local deferredNativeDraft, deferredComposer
local OpenListingDetails, RefreshCommentEditor
local openingNativeFromAddon
local classPage, classPageCount = 1, 1
local parts = {}
local playerGap = 2
local cardHeight, actionWidth = 64, 25
local playerRowGap = 2
local groupCardHeight, groupGap, visibleMemberSlots = 78, 4, 5
local memberIconSize, memberStep = 23, 27
local columnsPerPage, groupColumns = 4, 2
local fallbackResultsWidth = 392
local playersTop, groupsTop, resultsBottom = 187, 160, 18
local playersInset, groupsInset, scrollbarInset = 22, 12, 24
local toolbarButtonWidth, toolbarButtonHeight = 82, 27
local white = "Interface\\Buttons\\WHITE8X8"
local neutralName = { r = 0.95, g = 0.95, b = 0.95 }
local detailColor = { 0.68, 0.76, 0.79 }
local dungeonColor = { 0.90, 0.79, 0.52 }
local playstyleColor = { 0.66, 0.79, 0.62 }

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

local searchMenuInset = { left = 7, right = 7, top = 5, bottom = 5 }
local searchMenuPadding = { width = 0, height = 0 }
local searchMenuStyle = {}

function searchMenuStyle:Generate()
    local border = self:AttachTexture()
    border:SetAllPoints()
    border:SetDrawLayer("BACKGROUND", 0)
    border:SetColorTexture(0.41, 0.33, 0.22, 1)
    local fill = self:AttachTexture()
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetDrawLayer("BACKGROUND", 1)
    fill:SetColorTexture(0.10, 0.085, 0.067, 1)
end

function searchMenuStyle:GetInset() return searchMenuInset end
function searchMenuStyle:GetChildExtentPadding() return searchMenuPadding end

local function SearchDropdown(parent, label, width, alignRight)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "BackdropTemplate,WowStyle1DropdownTemplate")
    dropdown:SetSize(width, toolbarButtonHeight)
    dropdown:SetDefaultText(label)
    dropdown.menuMixin = searchMenuStyle
    dropdown:SetMenuAnchor(AnchorUtil.CreateAnchor(alignRight and "TOPRIGHT" or "TOPLEFT", dropdown,
        alignRight and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, -2))
    surface(dropdown, 0.14, 0.11, 0.078)

    if dropdown.Background then dropdown.Background:Hide() end
    if dropdown.Arrow then dropdown.Arrow:Hide() end
    if dropdown.Text then
        dropdown.Text:ClearAllPoints()
        dropdown.Text:SetPoint("LEFT", alignRight and 26 or 8, 0)
        dropdown.Text:SetPoint("RIGHT", -22, 0)
        dropdown.Text:SetMaxLines(1)
        dropdown.Text:SetWordWrap(false)
    end

    if alignRight then
        local chat = dropdown:CreateTexture(nil, "ARTWORK")
        chat:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
        chat:SetPoint("LEFT", 7, 0)
        chat:SetSize(15, 15)
        chat:SetVertexColor(0.83, 0.71, 0.50)
    end
    local left = dropdown:CreateTexture(nil, "ARTWORK")
    local right = dropdown:CreateTexture(nil, "ARTWORK")
    for _, stroke in ipairs({ left, right }) do
        stroke:SetSize(5, 1.3)
        stroke:SetColorTexture(0.83, 0.71, 0.50, 1)
    end
    left:SetPoint("RIGHT", -13, 0)
    right:SetPoint("RIGHT", -10, 0)
    local function update(open)
        dropdown:SetBackdropColor(open and 0.20 or 0.14, open and 0.15 or 0.11, open and 0.095 or 0.078, 1)
        dropdown:SetBackdropBorderColor(open and 0.71 or 0.42, open and 0.54 or 0.33, open and 0.30 or 0.21, 1)
        left:SetRotation(open and 0.6 or -0.6)
        right:SetRotation(open and -0.6 or 0.6)
    end
    update(false)
    dropdown:RegisterCallback("OnMenuOpen", function() update(true) end)
    dropdown:RegisterCallback("OnMenuClose", function() update(false) end)
    return dropdown
end

local function StyleSearchOption(option, selected, name, range)
    option:AddInitializer(function(frame, description)
        local font = frame.fontString
        if selected(description:GetData()) then
            local highlight = frame:AttachTexture()
            highlight:SetPoint("TOPLEFT", -3, 0)
            highlight:SetPoint("BOTTOMRIGHT", 0, 0)
            highlight:SetDrawLayer("BACKGROUND", -1)
            highlight:SetColorTexture(0.22, 0.16, 0.096, 1)
        end
        local extra = 0
        if range then
            font:SetTextToFit(name)
            local levels = frame:AttachFontString()
            levels:SetFontObject(GameFontHighlightSmall)
            levels:SetTextColor(0.76, 0.70, 0.61)
            levels:SetHeight(20)
            levels:SetTextToFit(range)
            levels:SetPoint("RIGHT", -4, 0)
            extra = (read(levels:GetUnboundedStringWidth(), "number") or 44) + 16
        end
        return 31 + (read(font:GetUnboundedStringWidth(), "number") or 155) + extra, 22
    end)
end

local function SearchLanguageLabel(selected)
    local codes = {}
    for _, locale in ipairs(addon.searchLocales) do
        local code = locale[1]
        if selected[code] then
            local language = code:sub(1, 2):upper()
            if code == "esMX" or code == "zhTW" then language = language .. "-" .. code:sub(3) end
            codes[#codes + 1] = language
        end
    end
    if #codes == 0 then return "Languages" end
    if #codes == 1 or (#codes == 2 and #codes[1] + #codes[2] == 4) then
        return table.concat(codes, " · ")
    end
    return #codes .. " selected"
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

local function CardCanAct(entry)
    return entry ~= nil and not entry.own and entry.target ~= nil
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

local function DescribeCardAction(entry)
    if entry.count ~= 1 then return "Ask to Join" end
    if addon.ShouldSuggestInvite() then return SUGGEST_INVITE or "Suggest Invite", true end
    return "Invite to Party", false
end

local function OpenCardMenu(card, entry)
    if not CardCanAct(entry) then return end
    local function currentEntry()
        local current = card.entry
        if card:IsVisible() and CardCanAct(current) and SameCardEntry(entry, current) then return current end
    end
    GameTooltip_Hide()
    local actionLabel, wasSuggestion = DescribeCardAction(entry)
    MenuUtil.CreateContextMenu(card, function(_, menu)
        menu:CreateTitle(entry.name)
        menu:CreateButton(SEND_MESSAGE or "Send Message", function()
            local current = currentEntry()
            if current then addon.OpenWhisper(current) end
        end)
        menu:CreateButton(actionLabel, function()
            local current = currentEntry()
            if not current then return end
            local _, isSuggestion = DescribeCardAction(current)
            if isSuggestion == wasSuggestion then ActOnCard(current) end
        end)
    end)
end

local function CaptureCardPress(control, card, isActionButton)
    control:SetScript("OnMouseDown", function(self, mouseButton)
        self.pressedCardEntry = card.entry
        self.pressedCardButton = mouseButton
        self.pressedCardSuggestion = nil
        if isActionButton and mouseButton == "LeftButton" and CardCanAct(card.entry) then
            local _, suggestion = DescribeCardAction(card.entry)
            self.pressedCardSuggestion = suggestion
        end
    end)
end

local function FinishCardPress(control, card, mouseButton)
    local entry, buttonPressed = control.pressedCardEntry, control.pressedCardButton
    local wasSuggestion = control.pressedCardSuggestion
    control.pressedCardEntry, control.pressedCardButton, control.pressedCardSuggestion = nil, nil, nil
    if buttonPressed ~= mouseButton or not control:IsVisible() or not CardCanAct(card.entry)
        or not SameCardEntry(entry, card.entry) then return end
    if wasSuggestion ~= nil then
        local _, isSuggestion = DescribeCardAction(card.entry)
        if isSuggestion ~= wasSuggestion then return end
    end
    return card.entry
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
        if not entry or (action and not CardCanAct(entry)) then return end
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
        if entry.playstyle then AddTooltipLine(entry.playstyle, playstyleColor) end
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
        if action then AddTooltipLine(DescribeCardAction(entry), detailColor) end
        GameTooltip:Show()
    end
    local function hide(self)
        if GameTooltip:GetOwner() == self then GameTooltip_Hide() end
    end
    control:SetScript("OnEnter", show)
    control:SetScript("OnLeave", hide)
    control:HookScript("OnHide", function(self)
        self.pressedCardEntry, self.pressedCardButton, self.pressedCardSuggestion = nil, nil, nil
        hide(self)
    end)
    return show
end

local function BuildCard(parent, width, group)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    local height = group and groupCardHeight or cardHeight
    card:SetSize(width, height)
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
    card.dungeon = text(card, "", "GameFontHighlightSmall")
    local dungeonY = group and -22 or -36
    card.dungeon:SetPoint("TOPLEFT", 6, dungeonY)
    card.dungeon:SetWordWrap(false)
    card.dungeon:SetTextColor(unpack(dungeonColor))
    card.extraDungeons = text(card, "", "GameFontHighlightSmall")
    card.extraDungeons:SetPoint("TOPRIGHT", -actionWidth - 5, dungeonY)
    card.extraDungeons:SetTextColor(unpack(dungeonColor))
    card.zone = text(card, "", "GameFontHighlightSmall")
    card.zone:SetPoint("TOPLEFT", 6, dungeonY - 13)
    card.zone:SetWordWrap(false)
    card.zone:SetTextColor(unpack(detailColor))
    if group then
        card.playstyle = text(card, "", "GameFontHighlightSmall")
        card.playstyle:SetJustifyH("RIGHT")
        card.playstyle:SetWordWrap(false)
        card.playstyle:SetTextColor(unpack(playstyleColor))
        card.members = {}
        for index = 1, visibleMemberSlots do
            local slot = CreateFrame("Frame", nil, card)
            slot:SetSize(memberIconSize, memberIconSize + 5)
            slot.roleIcon = slot:CreateTexture(nil, "ARTWORK")
            slot.roleIcon:SetSize(memberIconSize, memberIconSize)
            slot.roleIcon:SetPoint("TOP")
            slot.classBar = slot:CreateTexture(nil, "ARTWORK")
            slot.classBar:SetSize(16, 3)
            slot.classBar:SetPoint("BOTTOM")
            slot.unknownRole = text(slot, "?", "GameFontDisableSmall")
            slot.unknownRole:SetPoint("TOP")
            card.members[index] = slot
        end
        card.memberOverflow = text(card, "", "GameFontHighlightSmall")
        card.memberOverflow:SetPoint("RIGHT", card.members[1], "LEFT", -4, 0)
        card.memberOverflow:SetTextColor(unpack(detailColor))
    else
        card.detail = text(card, "", "GameFontHighlightSmall")
        card.detail:SetPoint("TOPLEFT", 6, -22)
        card.detail:SetWordWrap(false)
        card.detail:SetTextColor(unpack(detailColor))
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
    end, height - 2)
    CaptureCardPress(card.action, card, true)
    card.action:SetNormalFontObject(GameFontHighlightLarge)
    card.action:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    card.action:SetPoint("RIGHT", -1, 0)
    card.ShowTooltip = SetCardTooltip(card, card, false)
    card.action.ShowTooltip = SetCardTooltip(card.action, card, true)
    return card
end

local function MeasuredTextWidth(label, fallback)
    local width = read(label:GetUnboundedStringWidth(), "number")
    return width and width > 0 and width or fallback
end

local function PaintCard(card, entry, compact, index, fontPadding)
    card.entry = entry
    local color = NameColor(entry)
    card.name:SetTextColor(color.r, color.g, color.b)
    card.name:SetText(entry.name)
    local width = card:GetWidth()
    local textWidth = math.max(1, width - actionWidth - 11)
    local extra = entry.listedDungeons and #entry.listedDungeons - 1 or 0
    card.dungeon:SetText(entry.activity and entry.activity.name or "Unknown dungeon")
    card.extraDungeons:SetText(extra > 0 and ("+" .. extra) or "")
    local badgeSpace = extra > 0 and (MeasuredTextWidth(card.extraDungeons, 16) + 4) or 0
    card.dungeon:SetWidth(math.max(1, textWidth - badgeSpace))
    card.zone:SetText(entry.area or "Unknown zone")
    card.zone:SetWidth(textWidth)
    local tint = index % 2 == 0 and 0.012 or 0
    card:SetBackdropColor(0.101 + tint, 0.090 + tint, 0.074 + tint, 1)
    local isNearby = compact and entry.rank ~= nil
    card.nearby:SetShown(isNearby)
    local nameLeft = isNearby and 15 or 6
    card.name:SetPoint("TOPLEFT", nameLeft, -7)
    card.commentMark:SetShown(entry.comment ~= nil)
    local commentSpace = entry.comment and (MeasuredTextWidth(card.commentMark, 7) + 4) or 0
    local titleRight = actionWidth + 4 + commentSpace
    local nameWidth = width - titleRight - nameLeft
    if card.playstyle then
        card.playstyle:SetText(entry.playstyle or "")
        card.playstyle:SetShown(entry.playstyle ~= nil)
        if entry.playstyle then
            local widthLimit = textWidth * 0.43
            local styleWidth = math.min(MeasuredTextWidth(card.playstyle, 64), widthLimit)
            card.playstyle:SetWidth(styleWidth)
            card.playstyle:SetPoint("TOPRIGHT", -titleRight, -7)
            nameWidth = nameWidth - styleWidth - 6
        end
    end
    card.name:SetWidth(math.max(1, nameWidth))
    card:SetBackdropBorderColor(0.66, 0.56, 0.29, isNearby and 1 or 0)
    if compact then
        card.detail:SetPoint("TOPLEFT", 6, -22 - fontPadding)
        local dungeonY = -36 - 2 * fontPadding
        card.dungeon:SetPoint("TOPLEFT", 6, dungeonY)
        card.extraDungeons:SetPoint("TOPRIGHT", -actionWidth - 5, dungeonY)
        card.zone:SetPoint("TOPLEFT", 6, -49 - 3 * fontPadding)
        local detail = entry.count > 1 and (entry.count .. " players") or (entry.level and tostring(entry.level) or "")
        card.detail:SetText(detail)
        card.detail:SetWidth(math.max(1, width - actionWidth - 52))
        local shown = 0
        for _, role in ipairs(addon.roles) do
            local icon = card.icons[role.key]
            local visible = entry.roles ~= nil and entry.roles[role.key] == true
            icon:SetShown(visible)
            if visible then
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", width - actionWidth - 44 + 14 * shown, -20 - fontPadding)
                shown = shown + 1
            end
        end
    else
        local dungeonY = -22 - fontPadding
        card.dungeon:SetPoint("TOPLEFT", 6, dungeonY)
        card.extraDungeons:SetPoint("TOPRIGHT", -actionWidth - 5, dungeonY)
        card.zone:SetPoint("TOPLEFT", 6, -35 - 2 * fontPadding)
        local members = entry.rosterSlots or entry.members or {}
        local memberCount = math.min(#members, visibleMemberSlots)
        local overflow = entry.count - visibleMemberSlots
        local overflowWidth = overflow > 0 and 23 or 0
        local step = math.min(memberStep, math.max(1, (textWidth - overflowWidth) / math.max(1, memberCount)))
        local size = math.min(memberIconSize, math.max(1, step - 4))
        local left = 6 + (textWidth + overflowWidth - memberCount * step) / 2
        for slotIndex, slot in ipairs(card.members) do
            local member = members[slotIndex]
            local role = member and addon.roles[member.role]
            local class = member and member.class
            local vacant = member ~= nil and member.vacant == true
            local classColor = not vacant and addon.knownClasses[class] and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            if member then
                slot:SetSize(size, size + 5)
                slot:SetPoint("TOPLEFT", left + (slotIndex - 1) * step + (step - size) / 2, -47 - 3 * fontPadding)
            end
            if role then
                slot.roleIcon:SetSize(size, size)
                slot.roleIcon:SetAtlas(role.icon, false)
                slot.roleIcon:SetDesaturated(vacant)
                slot.roleIcon:SetAlpha(vacant and 0.66 or 1)
            end
            if classColor then
                slot.classBar:SetWidth(math.min(16, size))
                slot.classBar:SetColorTexture(classColor.r, classColor.g, classColor.b, 1)
            end
            slot.roleIcon:SetShown(role ~= nil)
            slot.unknownRole:SetShown(member ~= nil and role == nil)
            slot.classBar:SetShown(not not classColor)
            slot:SetShown(member ~= nil)
        end
        card.memberOverflow:SetText(overflow > 0 and ("+" .. overflow) or "")
    end
    local actionable = CardCanAct(entry)
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
    local fontHeight = GameFontHighlightSmall and select(2, GameFontHighlightSmall:GetFont())
    local fontPadding = math.max(0, (read(fontHeight, "number") or 10) - 10)
    if currentView == "groups" then
        local groups = parts.visibleGroups or {}
        local rowHeight = groupCardHeight + 3 * fontPadding
        count = #groups
        if count > 0 then height = math.ceil(count / groupColumns) * (rowHeight + groupGap) - groupGap end
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
            card:SetSize(width, rowHeight)
            card.action:SetHeight(rowHeight - 2)
            card:SetPoint("TOPLEFT", (index - 1) % groupColumns * (width + groupGap),
                -math.floor((index - 1) / groupColumns) * (rowHeight + groupGap))
            PaintCard(card, entry, false, index, fontPadding)
            card:Show()
        end
    end
    for index = count + 1, #parts.groupCards do parts.groupCards[index]:Hide() end

    if currentView == "players" then
        local playerHeight = cardHeight + 4 * fontPadding
        local playerRowHeight = playerHeight + playerRowGap
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
                height = math.max(height, (size - 1) * playerRowHeight + playerHeight)
            end
            if size > 0 then columnsShown = columnsShown + 1 end
            nearbyCount = nearbyCount + #near
            for index = 1, visible and size or 0 do
                local entry = near[index] or far[index - #near]
                local card = column.cards[index]
                if not card then card = BuildCard(column, columnWidth); column.cards[index] = card end
                card:SetSize(columnWidth, playerHeight)
                card.action:SetHeight(playerHeight - 2)
                card:ClearAllPoints()
                card:SetPoint("TOPLEFT", 0, -(index - 1) * playerRowHeight)
                PaintCard(card, entry, true, index, fontPadding)
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
    local source = addon.groups
    if currentView == "players" then source = addon.players end
    local canResetFilters = count == 0 and source ~= nil and #source > 0
    if not status then
        if currentView == "players" then
            if not addon.players then
                status = "Choose a dungeon and click Search."
            elseif count > 0 then
                status = (count == 1 and "1 player" or count .. " players") .. " found  ·  " .. nearbyCount .. " nearby"
            elseif canResetFilters then
                status = "No players match your filters."
            else
                status = "No players found for the selected dungeons. Try Search again or choose another dungeon."
            end
        else
            if count > 0 then
                status = count == 1 and "1 group" or count .. " groups"
            elseif canResetFilters then
                status = "No groups match your filters."
            else
                status = addon.groups and "No groups found for the selected dungeons." or "Choose a dungeon and click Search."
            end
        end
    end
    if canResetFilters then
        parts.status:SetPoint("TOPRIGHT", parts.resetFilters, "TOPLEFT", -8, -4)
    else
        parts.status:SetPoint("TOPRIGHT", -65, -141)
    end
    parts.status:SetText(status)
    parts.resetFilters:SetShown(canResetFilters)
end

local function RefreshNativePostPending()
    local listing = LFGListingFrame
    local post = listing and listing.PostButton
    if not post or post ~= commentPost then return end
    if InCombatLockdown() then return end
    local _, active, waiting = addon.ListingState()
    if waiting then
        pendingPostButton = post
        post:SetEnabled(false)
    elseif pendingPostButton == post then
        pendingPostButton = nil
        -- Recompute native permissions, comment validity and dirty state.
        listing:UpdatePostButtonEnableState()
    end
    local back = listing.BackButton
    if waiting and active == true and back then
        pendingBackButton = back
        back:SetEnabled(false)
    elseif back and pendingBackButton == back then
        pendingBackButton = nil
        listing:UpdateBackButtonEnableState()
    end
end

function addon.Refresh()
    RefreshNativePostPending()
    if not window or not window:IsVisible() then return end
    parts.results:SetShown(currentView == "players" or currentView == "groups")
    parts.status:SetShown(parts.results:IsShown())
    if not parts.results:IsShown() then parts.resetFilters:Hide() end
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
    parts.languageFilter:OverrideText(SearchLanguageLabel(addon.db.searchLanguages))
    local hasRoomRoles = roles ~= nil and (roles.tank == true or roles.healer == true or roles.dps == true)
    local fitsMe = hasRoomRoles and addon.db.fitsMe == true
    parts.roomFilter:SetEnabled(hasRoomRoles)
    parts.roomFilter.tick:SetShown(fitsMe)
    paintButton(parts.roomFilter, fitsMe)
    parts.visibleGroups = addon.FilterGroups(addon.groups or {}, groupRoleFilters,
        fitsMe and roles or nil, excludedClasses)
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

    local activities, automatic = addon.SelectedActivities()
    parts.automaticDungeon:SetChecked(automatic)
    local label = activities[1] and activities[1].name or "Choose dungeons"
    if #activities > 1 then label = label .. " +" .. (#activities - 1) end
    parts.activity:OverrideText(label)
    if currentView == "settings" then RefreshCommentEditor(activities) end
    local showListing = currentView ~= "settings" and (#activities > 0 or active == true or waiting ~= nil)
    parts.listingControls:SetShown(showListing)
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
        if canManage and GameTooltip:GetOwner() == parts.createListing then GameTooltip_Hide() end
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
        parts.createListing:SetEnabled(canManage and active ~= nil and not waiting)
        parts.updateListingStatus(active)
    end
    for key, check in pairs(parts.roleChecks) do check:SetChecked(roleFilters[key] == true) end
    for key, check in pairs(parts.groupRoleChecks) do check:SetChecked(groupRoleFilters[key] == true) end
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
    if addon.Search(ContinueOpeningSearch, function() addon.openedBefore = nil end) then
        addon.openedBefore = true
    end
end

local function SelectView(view, focusComment)
    if currentView == view then return end
    if inlineComposer then addon.EndNativeDraft() end
    currentView = view
    viewRevision = viewRevision + 1
    parts.results:SetVerticalScroll(0)
    addon.Refresh()
    if view == "settings" then OpenListingDetails(focusComment) end
    SearchOnFirstOpen()
end

local function OpenNativeListing(keepOverlay)
    if InCombatLockdown() then
        print(title .. ": open Group Finder after combat.")
        return
    end
    addon.EndNativeDraft()
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
        if window and not keepOverlay then window:Hide() end
        return true
    end
end

local function CommentAnchorsMatch(frame, points)
    if frame:GetNumPoints() ~= #points then return false end
    for _, expected in ipairs(points) do
        local point, relative, relativePoint, x, y = frame:GetPointByName(expected[1])
        if read(point, "string") ~= expected[1] or not canaccessvalue(relative) or relative ~= expected[2]
            or read(relativePoint, "string") ~= expected[3]
            or read(x, "number") ~= expected[4] or read(y, "number") ~= expected[5] then return false end
    end
    return true
end

local function SetCommentAnchors(frame, points)
    if CommentAnchorsMatch(frame, points) then return end
    frame:ClearAllPoints()
    for _, point in ipairs(points) do frame:SetPoint(unpack(point, 1, 5)) end
    if not CommentAnchorsMatch(frame, points) then error("Native frame could not be anchored") end
end

local function RestoreCommentControls(composer)
    local restored = true
    for _, original in ipairs(composer.frames) do
        local frame = original.frame
        local anchors = pcall(SetCommentAnchors, frame, original.points)
        local strata = pcall(frame.SetFrameStrata, frame, original.strata)
        local level = pcall(frame.SetFrameLevel, frame, original.level)
        restored = restored and anchors and strata and level
            and read(frame:GetFrameStrata(), "string") == original.strata
            and read(frame:GetFrameLevel(), "number") == original.level
    end
    return restored
end

local function CloseInlineComposer()
    local composer = inlineComposer
    if not composer then return end
    inlineComposer = nil
    if GameTooltip:GetOwner() == parts.commentReferenceOwner then GameTooltip_Hide() end
    parts.commentComposer:Hide()
    parts.commentFallback:Hide()
    parts.commentHint:Show()
    if not RestoreCommentControls(composer) and InCombatLockdown() then deferredComposer = composer end
end

local function NativeDraftMatches(listing, data)
    local view = listing.ActivityView
    local friendly = listing.NewPlayerFriendlyButton and listing.NewPlayerFriendlyButton.CheckButton
    if read(listing:GetCategorySelection(), "number") ~= addon.dungeonCategory
        or read(view.generalPlaystyle, "number") ~= data.generalPlaystyle
        or read(listing.voiceMode, "number") ~= data.voiceMode
        or read(listing.selectedActivities, "number") ~= #data.activityIDs
        or not friendly or read(friendly:GetChecked(), "boolean") ~= data.newPlayerFriendly then return false end
    for _, id in ipairs(data.activityIDs) do
        if read(listing:IsActivitySelected(id), "boolean") ~= true then return false end
    end
    return true
end

local function NativeDraftRolesMatch(roles)
    if not roles then return true end
    local native = addon.NativeListingRoles()
    return native and roles.tank == native.tank and roles.healer == native.healer and roles.dps == native.dps
end

local function RestoreNativeDraftOptions(listing, before, applied)
    local view = listing.ActivityView
    if not applied or read(view.generalPlaystyle, "number") == applied.generalPlaystyle then
        LFGListingActivityView_OnPlayStyleSelectedInternal(view, before.playstyle)
        if view.PlayStyleDropdown then view.PlayStyleDropdown:GenerateMenu() end
    end
    if not applied or read(listing.voiceMode, "number") == applied.voiceMode then
        listing.voiceMode = before.voice
        if view.VoiceChatDropdown then view.VoiceChatDropdown:GenerateMenu() end
    end
    local friendly = listing.NewPlayerFriendlyButton and listing.NewPlayerFriendlyButton.CheckButton
    if friendly and before.friendly ~= nil
        and (not applied or read(friendly:GetChecked(), "boolean") == applied.newPlayerFriendly) then
        friendly:SetChecked(before.friendly)
    end
end

local function RestoreNativeDraft(draft)
    if not draft or draft.postAttempted or not draft.original then return end
    local listing, before = draft.listing, draft.original
    if listing ~= LFGListingFrame then return end
    local grouped, active = addon.ListingState()
    if active ~= false or grouped ~= draft.grouped then return end

    local comment = addon.NativeListingComment()
    local category = listing:GetCategorySelection()
    if category ~= addon.dungeonCategory then
        -- Blizzard can discard the selection table without releasing its count.
        if not category and not listing:IsAnyActivitySelected()
            and (comment == "" or comment == draft.text) then
            if draft.prepared and read(listing.selectedActivities, "number") == #draft.data.activityIDs then
                listing.selectedActivities = before.count
                listing:SetDirty(false)
                RestoreNativeDraftOptions(listing, before, draft.data)
            end
            if comment ~= "" then pcall(C_LFGList.ClearCreationTextFields) end
            addon.RestoreListingRoleDraft(draft.roleChange)
        end
        return
    end
    if draft.prepared and (not NativeDraftMatches(listing, draft.data)
        or not NativeDraftRolesMatch(draft.roles)
        or comment ~= draft.text) then return end
    if comment ~= "" then
        local cleared = pcall(C_LFGList.ClearCreationTextFields)
        if not cleared or addon.NativeListingComment() ~= "" then return end
    end
    addon.RestoreListingRoleDraft(draft.roleChange)
    listing:SetAllActivities(false)
    if before.category then
        listing:SetCategorySelection(before.category)
    else
        listing:ClearCategorySelection()
    end
    RestoreNativeDraftOptions(listing, before)
    listing:SetDirty(false)
end

function addon.EndNativeDraft()
    local draft = nativeDraft
    nativeDraft = nil
    if inlineComposer then
        CloseInlineComposer()
        local _, active = addon.ListingState()
        if active == true then
            parts.commentBlocked = true
            parts.commentHint:SetText("Unlist before writing a new comment.")
        end
    end
    if draft then
        draft.edit:ClearFocus()
        if InCombatLockdown() then
            deferredNativeDraft = draft
        else
            RestoreNativeDraft(draft)
        end
    end
end

local function PositionCommentControls(composer)
    local pane = parts.commentComposer
    local comment, post = composer.frames[1].frame, composer.frames[2].frame
    SetCommentAnchors(comment, {
        { "TOPLEFT", pane, "TOPLEFT", 0, 0 },
        { "TOPRIGHT", pane, "TOPRIGHT", 0, 0 },
    })
    SetCommentAnchors(post, { { "TOPRIGHT", pane, "TOPRIGHT", 0, -55 } })
end

local function ShowInlineComposer(comment, post)
    local pane = parts.commentComposer
    if not pane or not window:IsVisible() or not post or not post:IsVisible() then return false end
    local composer = { frames = {} }
    local ok = pcall(function()
        for _, frame in ipairs({ comment, post }) do
            local strata = read(frame:GetFrameStrata(), "string")
            local level = read(frame:GetFrameLevel(), "number")
            if not strata or not level then error("Native frame layer unavailable") end
            local points = {}
            for index = 1, frame:GetNumPoints() do
                local point, relative, relativePoint, x, y = frame:GetPoint(index)
                if not read(point, "string") or not canaccessvalue(relative) or not relative
                    or not read(relativePoint, "string") or not read(x, "number") or not read(y, "number") then
                    error("Native frame anchor unavailable")
                end
                points[index] = { point, relative, relativePoint, x, y }
            end
            composer.frames[#composer.frames + 1] = { frame = frame, strata = strata, level = level, points = points }
        end
        local strata, level = window:GetFrameStrata(), pane:GetFrameLevel() + 2
        for _, entry in ipairs(composer.frames) do
            local frame = entry.frame
            frame:SetFrameStrata(strata)
            frame:SetFrameLevel(level)
            local actualLevel = read(frame:GetFrameLevel(), "number")
            if read(frame:GetFrameStrata(), "string") ~= strata or not actualLevel or actualLevel < level then
                error("Native frame could not be raised")
            end
        end
        PositionCommentControls(composer)
    end)
    if #composer.frames > 0 then inlineComposer = composer end
    if not ok then
        CloseInlineComposer()
        return false
    end

    local saved = read(addon.db.listingComment, "string")
    parts.commentReference:SetText(saved and saved:gsub("|", "||") or "")
    parts.commentHint:Hide()
    pane:Show()
    parts.commentFallback:Show()
    return true
end

local function ListingError(reason)
    UIErrorsFrame:AddMessage(reason, 1, 0.32, 0.24)
end

local function TrackNativeListingPost(listing)
    local post = listing and listing.PostButton
    if not post or commentPost == post then return end
    commentPost = post
    hooksecurefunc(listing, "UpdatePostButtonEnableState", RefreshNativePostPending)
    if listing.BackButton and listing.RemoveListing then
        hooksecurefunc(listing, "UpdateBackButtonEnableState", RefreshNativePostPending)
        hooksecurefunc(listing, "RemoveListing", function()
            addon.ObserveNativeListingPost(nil, "remove")
        end)
    end
    RefreshNativePostPending()
    local hasPreClick = read(post:HasScript("PreClick"), "boolean") == true
    local failureRevision, submissionKind
    if hasPreClick then
        post:HookScript("PreClick", function()
            local _, active = addon.ListingState()
            failureRevision, submissionKind = nil, nil
            if listing.dirty then
                local selected = listing:IsAnyActivitySelected()
                if active == false and selected then
                    failureRevision, submissionKind = addon.ListingFailureRevision(), "create"
                elseif active == true and not selected then
                    submissionKind = "remove"
                end
            end
        end)
    end
    post:HookScript("OnClick", function()
        local revision, kind = failureRevision, submissionKind
        failureRevision, submissionKind = nil, nil
        local current = nativeDraft
        if current and current.listing ~= listing then current = nil end
        if kind == nil and (hasPreClick or not current) then return end
        local attempted = current and current.postAttempted
        if current then current.postAttempted = true end
        local ok, reason = addon.ObserveNativeListingPost(revision, kind)
        if not ok and current then
            current.postAttempted = attempted
            ListingError(reason)
        end
    end)
end

OpenListingDetails = function(focus)
    if inlineComposer then
        if focus and nativeDraft then nativeDraft.edit:SetFocus() end
        return
    end
    parts.commentFallback:Hide()
    parts.commentRetry:Hide()
    parts.commentBlocked = nil
    local activities = addon.SelectedActivities()
    local allowed, reason = addon.CanCreateListing(activities)
    if not allowed then
        parts.commentHint:SetText(reason)
        parts.commentBlocked = true
        return
    end
    local listing = LFGListingFrame
    if not listing then
        parts.commentHint:SetText("WoW's comment field is unavailable.")
        return
    end
    if C_LFGList.IsPlayerAuthenticatedForLFG
        and read(C_LFGList.IsPlayerAuthenticatedForLFG(addon.dungeonCategory), "boolean") == false then
        parts.commentHint:SetText("WoW requires account authentication for listing comments.")
        return
    end
    local view = listing.ActivityView
    local edit, post = view.Comment.EditBox, listing.PostButton
    local grouped = addon.ListingState()
    local roles = addon.ListingRoles()
    if grouped == false and not (roles.tank or roles.healer or roles.dps) then
        parts.commentHint:SetText("Choose at least one listing role.")
        return
    end
    local category = listing:GetCategorySelection()
    local data = addon.ListingData(activities)
    local friendlyButton = listing.NewPlayerFriendlyButton and listing.NewPlayerFriendlyButton.CheckButton
    local draft = { edit = edit, listing = listing, data = data, grouped = grouped,
        roles = grouped == false and roles or nil, text = "" }
    local nativeComment = addon.NativeListingComment()
    local occupied = listing.dirty or listing:IsAnyActivitySelected() or nativeComment ~= ""
    if occupied then
        if not NativeDraftMatches(listing, data) or not NativeDraftRolesMatch(draft.roles) then
            parts.commentHint:SetText("A different Blizzard listing draft is already open.")
            parts.commentFallback:Show()
            return
        end
    else
        draft.original = {
            category = category, playstyle = view.generalPlaystyle, voice = listing.voiceMode,
            friendly = friendlyButton and read(friendlyButton:GetChecked(), "boolean"),
            count = read(listing.selectedActivities, "number") or 0,
        }
    end
    if not OpenNativeListing(true) or not listing:IsVisible() then
        parts.commentHint:SetText("WoW's comment field is unavailable.")
        return
    end

    if draft.original then
        local ok, prepared = pcall(function()
            listing:SetCategorySelection(addon.dungeonCategory)
            if grouped == false then
                local rolesApplied
                rolesApplied, draft.roleChange = addon.ApplyListingRoleDraft(roles, true)
                if not rolesApplied then return false end
                listing:LoadSoloRoles()
            end
            listing:SetAllActivities(false)
            for _, id in ipairs(data.activityIDs) do listing:SetActivity(id, true, true, true) end
            LFGListingActivityView_OnPlayStyleSelectedInternal(view, data.generalPlaystyle)
            if view.PlayStyleDropdown then view.PlayStyleDropdown:GenerateMenu() end
            listing.voiceMode = data.voiceMode
            if friendlyButton then friendlyButton:SetChecked(data.newPlayerFriendly) end
            if view.VoiceChatDropdown then view.VoiceChatDropdown:GenerateMenu() end
            return NativeDraftMatches(listing, data) and NativeDraftRolesMatch(draft.roles)
        end)
        if not ok or not prepared then
            pcall(RestoreNativeDraft, draft)
            parts.commentHint:SetText("WoW could not prepare the listing form.")
            parts.commentFallback:Show()
            return
        end
        draft.prepared = true
    end
    if view:IsShown() then
        LFGListingActivityView_UpdateActivities(view)
        if commentListing ~= listing then
            commentListing = listing
            hooksecurefunc(listing, "UpdatePostButtonEnableState", function(self)
                if nativeDraft and nativeDraft.listing == self and inlineComposer then
                    RefreshCommentEditor(addon.SelectedActivities())
                end
            end)
        end
        TrackNativeListingPost(listing)
        if commentEdit ~= edit then
            commentEdit = edit
            edit:HookScript("OnTextChanged", function(self, fromUser)
                if not fromUser or not nativeDraft or nativeDraft.edit ~= self or not view:IsVisible() then return end
                local _, active = addon.ListingState()
                if active ~= false then addon.EndNativeDraft(); return end
                local value = addon.NativeListingComment()
                if value ~= nil then
                    nativeDraft.text = value
                    addon.SaveListingComment(value)
                end
            end)
            view:HookScript("OnShow", function()
                local composer = inlineComposer
                if composer and nativeDraft and nativeDraft.edit == edit then
                    if NativeDraftMatches(nativeDraft.listing, nativeDraft.data) and NativeDraftRolesMatch(nativeDraft.roles)
                        and pcall(PositionCommentControls, composer) then return end
                    addon.EndNativeDraft()
                    parts.commentHint:SetText("WoW refreshed the listing form.")
                    parts.commentBlocked = true
                    RefreshCommentEditor(addon.SelectedActivities())
                end
            end)
            view:HookScript("OnHide", function()
                local draft = nativeDraft
                if not draft or draft.edit ~= edit then return end
                -- Blizzard briefly hides and shows this view during roster updates.
                C_Timer.After(0, function()
                    if nativeDraft ~= draft or view:IsVisible() then return end
                    local wasInline = inlineComposer ~= nil
                    addon.EndNativeDraft()
                    if wasInline and window:IsVisible() and currentView == "settings" then
                        parts.commentHint:SetText("WoW refreshed the listing form.")
                        parts.commentBlocked = true
                        RefreshCommentEditor(addon.SelectedActivities())
                    end
                end)
            end)
        end
        if edit:IsEnabled() then
            local embedded = ShowInlineComposer(view.Comment, post)
            if embedded then
                nativeDraft = draft
                if focus then edit:SetFocus() end
            else
                RestoreNativeDraft(draft)
                parts.commentHint:SetText("Open the Blizzard form to add a comment.")
                parts.commentFallback:Show()
            end
        else
            RestoreNativeDraft(draft)
            parts.commentHint:SetText("WoW has disabled the comment field for this listing.")
        end
    else
        RestoreNativeDraft(draft)
        parts.commentHint:SetText("WoW's comment field is unavailable.")
    end
end

RefreshCommentEditor = function(activities)
    if inlineComposer and nativeDraft then
        local allowed, reason = addon.CanCreateListing(activities)
        local ids = nativeDraft.data.activityIDs
        local changed = #activities ~= #ids
        for index, activity in ipairs(activities) do
            if activity.id ~= ids[index] then changed = true; break end
        end
        if allowed and not changed and addon.ListingState() == nativeDraft.grouped
            and NativeDraftMatches(nativeDraft.listing, nativeDraft.data)
            and NativeDraftRolesMatch(nativeDraft.roles) then return end
        addon.EndNativeDraft()
        parts.commentHint:SetText(reason or "Listing selections changed.")
        parts.commentBlocked = true
    end
    if parts.commentBlocked then
        local allowed, reason = addon.CanCreateListing(activities)
        parts.commentHint:SetText(allowed and "Open the comment field to continue." or reason)
        parts.commentRetry:SetShown(allowed == true)
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
    local hint = text(pane, "", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 5, -9)
    parts.commentHint = hint

    local composer = CreateFrame("Frame", nil, pane)
    composer:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 5, -7)
    composer:SetSize(377, 86)
    local referenceOwner = CreateFrame("Frame", nil, composer)
    referenceOwner:SetPoint("TOPLEFT", caption, "TOPLEFT", 110, 0)
    referenceOwner:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -17, -327)
    referenceOwner:SetHeight(15)
    referenceOwner:EnableMouse(true)
    local reference = text(referenceOwner, "", "GameFontDisableSmall")
    reference:SetPoint("TOPLEFT")
    reference:SetPoint("TOPRIGHT")
    reference:SetWordWrap(false)
    referenceOwner:SetScript("OnEnter", function(self)
        local saved = read(reference:GetText(), "string")
        if not saved then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Saved listing comment")
        GameTooltip:AddLine(saved, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    referenceOwner:SetScript("OnLeave", function(self)
        if GameTooltip:GetOwner() == self then GameTooltip_Hide() end
    end)
    parts.commentReference = reference
    parts.commentReferenceOwner = referenceOwner

    local useNative = button(pane, "Open Blizzard form", 118, function()
        local draft = nativeDraft
        CloseInlineComposer()
        if draft then draft.original = nil end
        if not LFGListingFrame or not LFGListingFrame:IsVisible() then
            LFGParentFrameTab1_OnClick()
        end
        window:Hide()
        if draft then draft.edit:SetFocus() end
    end)
    useNative:SetPoint("TOPLEFT", composer, "TOPLEFT", 0, -55)
    useNative:Hide()
    parts.commentFallback = useNative
    local retry = button(pane, "Open comment field", 118, function() OpenListingDetails(true) end)
    retry:SetPoint("TOPLEFT", composer, "TOPLEFT", 0, -55)
    retry:Hide()
    parts.commentRetry = retry
    composer:Hide()
    parts.commentComposer = composer
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
    local submit = button(controls, "List Me", toolbarButtonWidth, function()
        local _, active, waiting = addon.ListingState()
        if waiting then return end
        if active == true then
            local ok, reason = addon.RemoveListing()
            if not ok then ListingError(reason) end
            return
        end
        local ok, reason = addon.CreateListing()
        if not ok then ListingError(reason) end
    end, toolbarButtonHeight)
    submit:SetPoint("RIGHT", options, "LEFT", -6, 0)
    paintButton(submit, true)
    parts.createListing = submit
    submit:SetMotionScriptsWhileDisabled(true)
    submit:SetScript("OnEnter", function(self)
        local grouped = addon.ListingState()
        if grouped ~= true or addon.CanManageListing(grouped) then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Only the party leader can list or unlist the party.")
        GameTooltip:Show()
    end)
    submit:SetScript("OnLeave", function(self)
        if GameTooltip:GetOwner() == self then GameTooltip_Hide() end
    end)
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
    submit:HookScript("OnHide", function(self)
        pulse:Stop()
        if GameTooltip:GetOwner() == self then GameTooltip_Hide() end
    end)
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
        menu:CreateButton("Comment…", function()
            SelectView("settings", true)
        end)
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
        end, "Used by Fits me and when listing solo. While listed solo, the checked icons show your current listing roles.")
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
    local views = {{"players", "Players"}, {"groups", "Groups"}, {"settings", "Settings"}}
    for _, view in ipairs(views) do
        parts.tabs[view[1]] = button(header, view[2], 1, function() SelectView(view[1]) end)
    end
    local function LayoutTabs()
        local inset, gap = 12, 8
        local width = read(window:GetWidth(), "number")
        if not width or width <= 0 then width = 454 end
        local tabWidth = math.max(1, (width - 2 * inset - gap * (#views - 1)) / #views)
        for index, view in ipairs(views) do
            local tab = parts.tabs[view[1]]
            tab:SetWidth(tabWidth)
            tab:SetPoint("TOPLEFT", inset + (index - 1) * (tabWidth + gap), -12)
        end
    end
    LayoutTabs()
    local toolbar = CreateFrame("Frame", nil, header)
    toolbar:SetAllPoints()
    parts.toolbar = toolbar
    local activity = SearchDropdown(toolbar, "Choose dungeons", 216)
    activity:SetPoint("LEFT", toolbar, "TOPLEFT", 12, -48 - toolbarButtonHeight / 2)
    activity:SetupMenu(function(dropdown, menu)
        local function showAllLevels() return addon.db.showAllLevels end
        local allLevels = menu:CreateCheckbox("Show all levels", showAllLevels, function()
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
            local revision = viewRevision
            C_Timer.After(0, function()
                if revision == viewRevision and dropdown:IsVisible() and not Menu.GetManager():GetOpenMenu() then
                    dropdown:OpenMenu()
                end
            end)
        end)
        StyleSearchOption(allLevels, showAllLevels)
        allLevels:SetSelectionIgnored()
        allLevels:SetResponse(MenuResponse.Close)
        menu:CreateDivider()
        local entries, complete = addon.Activities()
        if #entries == 0 then menu:CreateTitle("No dungeons for this level"); return end
        menu:SetScrollMode(190)
        local function selected(id)
            if addon.db.manualDungeonSelection then return addon.db.activities[id] == true end
            local selectedActivities, automatic = addon.SelectedActivities(entries, complete)
            if not automatic then return addon.db.activities[id] == true end
            return selectedActivities[1] ~= nil and id == selectedActivities[1].id
        end
        for _, entry in ipairs(entries) do
            local range = entry.min > 0 and (entry.min .. "–" .. entry.max) or nil
            local label = range and (entry.name .. "  (" .. range .. ")") or entry.name
            local option = menu:CreateCheckbox(label, selected,
                function(id)
                    parts.results:SetVerticalScroll(0)
                    classPage = 1
                    addon.ToggleActivity(id)
                end, entry.id)
            StyleSearchOption(option, selected, entry.name, range)
        end
    end)
    parts.activity = activity
    local search = button(toolbar, "Search", toolbarButtonWidth, function()
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
    parts.groupRoleChecks = {}
    for index, role in ipairs(addon.roles) do
        local check = iconCheck(groupFilter, role, "Has " .. role.label, function(self)
            groupRoleFilters[role.key] = self:GetChecked() == true or nil
            refreshGroupFilters()
        end, "Shows groups with at least one of the checked roles already filled.")
        check:SetPoint("LEFT", 57 + (index - 1) * 30, 0)
        parts.groupRoleChecks[role.key] = check
    end
    local room = button(groupFilter, "Fits me", 84, function()
        addon.db.fitsMe = not addon.db.fitsMe
        refreshGroupFilters()
    end, 22)
    room:SetMotionScriptsWhileDisabled(true)
    room:SetPoint("LEFT", 151, 0)
    room.tick = room:CreateTexture(nil, "ARTWORK")
    room.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    room.tick:SetSize(14, 14)
    room.tick:SetPoint("LEFT", 4, 0)
    hover(room, "Fits me", "Shows groups with an opening for any of your selected roles. Select at least one role to use this filter.")
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
    local languageFilter = SearchDropdown(toolbar, "Languages", 130, true)
    languageFilter:SetPoint("RIGHT", toolbar, "TOPRIGHT", -12, -119)
    local function languageChanged()
        classPage = 1
        parts.results:SetVerticalScroll(0)
        addon.SelectionChanged()
    end
    languageFilter:SetupMenu(function(_, menu)
        local function allLanguages() return not next(addon.db.searchLanguages) end
        menu:SetMinimumWidth(194)
        menu:SetScrollMode(190)
        local all = menu:CreateCheckbox("All languages", allLanguages, function()
            if not next(addon.db.searchLanguages) then return end
            addon.db.searchLanguages = {}
            languageChanged()
        end)
        StyleSearchOption(all, allLanguages)
        all:SetSelectionIgnored()
        menu:CreateDivider()
        local function selected(code) return addon.db.searchLanguages[code] == true end
        for _, locale in ipairs(addon.searchLocales) do
            local option = menu:CreateCheckbox(locale[2], selected,
                function(code)
                    local selected = addon.db.searchLanguages
                    selected[code] = not selected[code] or nil
                    languageChanged()
                end, locale[1])
            StyleSearchOption(option, selected)
            option:SetSelectionIgnored()
        end
    end)
    parts.languageFilter = languageFilter
    parts.status = text(header, "", "GameFontHighlightSmall")
    parts.status:SetPoint("TOPLEFT", 12, -141)
    parts.status:SetPoint("TOPRIGHT", -65, -141)
    parts.status:SetTextColor(0.80, 0.74, 0.64)
    parts.resetFilters = button(header, "Reset filters", 88, function()
        if not parts.resetFilters:IsVisible() then return end
        if currentView == "players" then
            roleFilters = {}
        elseif currentView == "groups" then
            groupRoleFilters = {}
            addon.db.fitsMe = false
        end
        addon.db.excludedClasses = {}
        classPage = 1
        parts.results:SetVerticalScroll(0)
        addon.Refresh()
    end, 20)
    parts.resetFilters:SetPoint("RIGHT", header, "TOPRIGHT", -65, -147)
    parts.resetFilters:Hide()
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
        LayoutTabs()
        if scroll:IsVisible() then RenderResults() end
    end)
end

local showEmbedded

local function AddNativeLauncher()
    local parent = LFGParentFrame
    TrackNativeListingPost(LFGListingFrame)
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
        viewRevision = viewRevision + 1
        if inlineComposer then addon.EndNativeDraft() end
        for texture, alpha in pairs(selectionAlpha) do texture:SetAlpha(alpha) end
        selectionAlpha = {}
        nativeLauncher:SetChecked(false)
    end)

    showEmbedded = function(view)
        if not addon.db then return end
        if not parts.toolbar then BuildContents() end
        if view and view ~= currentView then
            if inlineComposer then addon.EndNativeDraft() end
            currentView = view
            viewRevision = viewRevision + 1
            parts.results:SetVerticalScroll(0)
        end
        window:Show()
        addon.Refresh()
        if currentView == "settings" then OpenListingDetails() end
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
loader:RegisterEvent("PLAYER_REGEN_DISABLED")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:SetScript("OnEvent", function(self, event, addonName)
    if event == "PLAYER_LOGIN" then
        addon.InitializeSettings()
        AddNativeLauncher()
    elseif event == "ADDON_LOADED" and addonName == "Blizzard_GroupFinder_VanillaStyle" then
        AddNativeLauncher()
    elseif event == "PLAYER_REGEN_DISABLED" then
        addon.Refresh()
    elseif event == "PLAYER_REGEN_ENABLED" or event == "LFG_LIST_AVAILABILITY_UPDATE" then
        if not addon.db then return end
        if event == "PLAYER_REGEN_ENABLED" then
            if deferredComposer then
                RestoreCommentControls(deferredComposer)
                deferredComposer = nil
            end
            local draft = deferredNativeDraft
            deferredNativeDraft = nil
            RestoreNativeDraft(draft)
            addon.Refresh()
        end
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
