local addonRoot = ...
local frames, deferred = {}, {}
local openMenu
local methods = {}
setmetatable(methods, { __index = function(_, key)
    if key:match("^[A-Z]") then return function() end end
end })

function CreateFrame(kind, _, parent, template)
    local frame = setmetatable({ kind = kind, parent = parent, template = template, shown = true, scripts = {} }, { __index = methods })
    frames[#frames + 1] = frame
    if template == "LargeSideTabButtonTemplate" or template == "LFGOptionsButton" then
        frame.Icon = CreateFrame("Texture", nil, frame)
    elseif template == "BackdropTemplate,WowStyle1DropdownTemplate" then
        frame.Background = CreateFrame("Texture", nil, frame)
        frame.Arrow = CreateFrame("Texture", nil, frame)
        frame.Text = CreateFrame("FontString", nil, frame)
    end
    return frame
end
function methods:CreateFontString() return CreateFrame("FontString", nil, self) end
function methods:CreateTexture() return CreateFrame("Texture", nil, self) end
function methods:CreateMaskTexture() return CreateFrame("MaskTexture", nil, self) end
function methods:AddMaskTexture(mask) self.mask = mask end
function methods:SetVertexColor(...) self.vertexColor = { ... } end
function methods:SetDesaturated(value) self.desaturated = value end
function methods:SetColorTexture(...) self.textureColor = { ... } end
function methods:SetRotation(rotation) self.rotation = rotation end
function methods:SetBackdropColor(...) self.backdropColor = { ... } end
function methods:CreateAnimationGroup()
    local animation = CreateFrame("AnimationGroup", nil, self)
    animation.Play = function(self) self.playing = true end
    animation.Stop = function(self) self.playing = false end
    animation.IsPlaying = function(self) return self.playing == true end
    animation.CreateAnimation = function(self) return CreateFrame("Animation", nil, self) end
    return animation
end
function methods:GetHighlightTexture() return self:CreateTexture() end
function methods:SetText(label) self.label = label end
function methods:GetText() return self.label or "" end
function methods:SetChecked(checked) self.checked = checked end
function methods:GetChecked() return self.checked end
function methods:SetCheckedTexture(texture)
    self.tick = self:CreateTexture()
    self.tick:SetTexture(texture)
end
function methods:GetCheckedTexture() return self.tick end
function methods:SetDisabledCheckedTexture(texture)
    self.disabledTick = self:CreateTexture()
    self.disabledTick:SetTexture(texture)
end
function methods:GetDisabledCheckedTexture() return self.disabledTick end
function methods:SetEnabled(enabled) self.enabled = enabled end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:GetWidth() return self.width end
function methods:SetHeight(height) self.height = height end
function methods:GetHeight() return self.height end
function methods:GetFrameLevel()
    return self.level or (self.parent and self.parent:GetFrameLevel() + 1 or 1)
end
function methods:SetFrameLevel(level) self.level = level end
function methods:GetFrameStrata() return self.strata or "MEDIUM" end
function methods:SetFrameStrata(strata) self.strata = strata end
function methods:SetPoint(point, ...)
    self[point] = { ... }
    self.points = self.points or {}
    for _, existing in ipairs(self.points) do if existing == point then return end end
    self.points[#self.points + 1] = point
end
function methods:GetNumPoints() return self.points and #self.points or 0 end
function methods:GetPoint(index)
    local point = self.points[index]
    if not point then return end
    local relative, relativePoint, x, y = unpack(self[point])
    if type(relative) == "number" then
        return point, self.parent, point, relative, relativePoint
    end
    return point, relative, relativePoint, x, y
end
function methods:GetPointByName(name)
    for index, point in ipairs(self.points or {}) do
        if point == name then return self:GetPoint(index) end
    end
end
function methods:ClearAllPoints()
    for _, point in ipairs(self.points or {}) do self[point] = nil end
    self.points = {}
end
function methods:SetHitRectInsets(_, right) self.hitRight = right end
function methods:SetAtlas(atlas) self.atlas = atlas end
function methods:SetTexture(texture) self.texture = texture end
function methods:OverrideText(label) self.label = label end
function methods:RegisterEvent(event)
    self.events = self.events or {}
    self.events[event] = true
end
function methods:UnregisterEvent(event)
    if self.events then self.events[event] = nil end
end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:HookScript(event, callback)
    local original = self.scripts[event]
    self.scripts[event] = function(...)
        if original then original(...) end
        callback(...)
    end
end
function methods:SetShown(shown)
    if shown == self.shown then return end
    self.shown = shown
    local callback = self.scripts[shown and "OnShow" or "OnHide"]
    if callback then callback(self) end
end
function methods:Show() self:SetShown(true) end
function methods:Hide() self:SetShown(false) end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:SetCustomOnMouseUpHandler(callback) self.launch = callback end
function methods:EnableRegenerateOnResponse() self.regenerateOnResponse = true end
function methods:SetupMenu(generator) self.generator = generator end
function methods:SetMenuAnchor(anchor) self.menuAnchor = anchor end
function methods:RegisterCallback(event, callback)
    self.callbacks = self.callbacks or {}
    self.callbacks[event] = callback
end
function methods:IsMenuOpen() return self.options ~= nil end
function methods:CloseMenu()
    self.options = nil
    if openMenu == self then openMenu = nil end
    if self.callbacks and self.callbacks.OnMenuClose then self.callbacks.OnMenuClose(self) end
end
function methods:OpenMenu()
    assert(not self:IsMenuOpen(), "never replace an open menu")
    if openMenu then openMenu:CloseMenu() end
    local options = {}
    self.generator(self, {
        CreateCheckbox = function(_, label, selected, click, data)
            local option = {
                label = label, selected = selected, click = click, id = data,
                SetSelectionIgnored = function(self) self.ignored = true end,
                SetResponse = function(self, response) self.response = response end,
                AddInitializer = function(self, initializer) self.initializer = initializer end,
            }
            options[#options + 1] = option
            return option
        end,
        CreateDivider = function() self.dividerAfter = #options end,
        SetScrollMode = function(_, height) self.scrollHeight = height end,
        SetMinimumWidth = function(_, width) self.menuWidth = width end,
    })
    self.options = options
    openMenu = self
    self.menuOffset = 0
    if self.callbacks and self.callbacks.OnMenuOpen then self.callbacks.OnMenuOpen(self) end
end
function methods:PickOption(index)
    local option = self.options[index]
    option.click(option.id)
    -- The native dropdown receives the selection callback before processing its response.
    if self.regenerateOnResponse then self:OpenMenu() end
    if option.response == MenuResponse.Close then self:CloseMenu() end
end

function canaccessvalue() return true end
function UnitLevel() return 32 end
function strcmputf8i(a, b)
    a, b = a:lower(), b:lower()
    return a == b and 0 or (a < b and -1 or 1)
end
function ScrollFrame_OnScrollRangeChanged() end

SlashCmdList = {}
AnchorUtil = { CreateAnchor = function(...) return { ... } end }
local menuManager = { GetOpenMenu = function() return openMenu end }
Menu = { GetManager = function() return menuManager end }
MenuResponse = { Close = "close" }
C_Timer = { After = function(delay, callback)
    assert(delay == 0 or delay == 5 or delay == 6)
    deferred[#deferred + 1] = callback
end }
local activities = {
    { shortName = "", groupFinderActivityGroupID = 0, fullName = "Scarlet Graveyard", minLevelSuggestion = 30, maxLevelSuggestion = 38, orderIndex = 0, maxNumPlayers = 5 },
    { shortName = "", groupFinderActivityGroupID = 0, fullName = "Gnomeregan", minLevelSuggestion = 29, maxLevelSuggestion = 38, orderIndex = 0 },
    { shortName = "", groupFinderActivityGroupID = 0, fullName = "Razorfen Kraul", minLevelSuggestion = 29, maxLevelSuggestion = 38, orderIndex = 0 },
    { shortName = "", groupFinderActivityGroupID = 0, fullName = "Ragefire Chasm", minLevelSuggestion = 13, maxLevelSuggestion = 18, orderIndex = 0 },
    { shortName = "", groupFinderActivityGroupID = 0, fullName = "Scholomance", minLevelSuggestion = 58, maxLevelSuggestion = 60, orderIndex = 0 },
}
C_LFGList = {
    GetAvailableActivities = function() return { 3, 1, 4, 2, 5 } end,
    GetActivityInfoTable = function(id) return activities[id] end,
    GetActiveEntryInfo = function() end,
    HasActiveEntryInfo = function() return false end,
}
function IsInGroup() return false end
function UnitGetAvailableRoles() return true, true, true end
function InCombatLockdown() return false end
GameTooltip = { GetOwner = function() end }
function GameTooltip_Hide() end
LFGParentFrame = CreateFrame("Frame")
LFGParentFramePortrait = CreateFrame("Button", nil, LFGParentFrame)
LFGParentFramePortrait:SetFrameStrata("HIGH")
LFGParentFramePortrait:SetFrameLevel(4)
function LFGVanilla_ShowFrame(tab)
    LFGParentFrame:Show()
    tab = tab or LFGParentFrame.selectedTab
    LFGParentFrame.selectedTab = (tab == 2 or tab == 3) and tab or 1
end
function LFGVanilla_ToggleFrame(tab)
    if LFGParentFrame:IsShown() and (not tab or LFGParentFrame.selectedTab == tab) then
        LFGParentFrame:Hide()
    else
        LFGVanilla_ShowFrame(tab)
    end
end
function hooksecurefunc(target, name, callback)
    if type(target) == "string" then target, name, callback = _G, target, name end
    local original = assert(target[name])
    target[name] = function(...)
        original(...)
        callback(...)
    end
end
for _, key in ipairs({ "ListingTab", "BrowsingTab", "WhoListingTab" }) do
    LFGParentFrame[key] = CreateFrame("Frame", nil, LFGParentFrame)
    LFGParentFrame[key].SelectedTexture = false
end

local addon, finderEvents = {}, nil
for _, file in ipairs({ "Data", "Finder", "Window" }) do
    assert(loadfile(addonRoot .. "/" .. file .. ".lua"))("PartyFinderForever", addon)
    if file == "Finder" then finderEvents = frames[#frames] end
end
local loader = frames[#frames]
addon.PreferredRole = function() end
local search = addon.Search
addon.Search = function() end
loader.scripts.OnEvent(loader, "PLAYER_LOGIN")
for _, frame in ipairs(frames) do
    if frame.launch then frame.launch(frame, "LeftButton", true) end
end

return addon, frames, deferred, finderEvents, search, loader
