-- Run with Lua 5.1 and pass the addon directory as the first argument.
local fixturePath = (arg[0]:match("^(.*[/\\])") or "") .. "window_fixture.lua"
local addon, frames, deferred, finderEvents, search, loader = assert(loadfile(fixturePath))(arg[1] or ".")

local function find(kind, label)
    for _, frame in ipairs(frames) do
        if frame.kind == kind and frame.label == label and frame:IsVisible() then return frame end
    end
end

local gear
for _, frame in ipairs(frames) do
    if frame.template == "LFGOptionsButton" then gear = frame end
end
assert(gear and gear.width == 28)
for index, label in ipairs({ "Players", "Groups", "Settings" }) do
    local tab = assert(find("Button", label))
    assert(tab.width == 138 and tab.TOPLEFT[1] == 12 + (index - 1) * 146)
end
local roleButtons = {}
for _, label in ipairs({ "Find roles", "My roles" }) do
    local rolesFrame = assert(find("FontString", label)).parent
    local previousEdge, roleCount = 0, 0
    roleButtons[label] = {}
    for _, frame in ipairs(frames) do
        if frame.parent == rolesFrame and frame.kind == "CheckButton" then
            assert(frame.template ~= "UICheckButtonTemplate" and frame.width == 28)
            assert(frame.tick and frame.tick.BOTTOMLEFT[1] == 0 and frame.tick.width == 13)
            assert(frame.LEFT[1] >= previousEdge)
            previousEdge = frame.LEFT[1] + frame.width
            roleCount = roleCount + 1
            roleButtons[label][roleCount] = frame
        end
    end
    assert(roleCount == 3 and previousEdge <= rolesFrame.width)
end

local active, grouped, leader, publications = false, false, false, {}
local sentRoles, cleared, removals, rejectRemoval = nil, nil, 0, false
local nativeRoles, roleWrites = { tank = false, healer = true, dps = false }, 0
C_LFGList.HasActiveEntryInfo = function() return active end
C_LFGList.RemoveListing = function()
    removals = removals + 1
    if rejectRemoval then return false end
end
local listingError
UIErrorsFrame = { AddMessage = function(_, message) listingError = message end }
C_LFGList.ClearCreationTextFields = function() cleared = true end
C_LFGList.CreateListing = function(data)
    assert(cleared)
    publications[#publications + 1] = data
    return true
end
C_LFGListRoles = { GetRoles = function() return nativeRoles end, SetRoles = function(roles, limitToClassRoles)
    assert(limitToClassRoles == false)
    sentRoles = roles
    nativeRoles = roles
    roleWrites = roleWrites + 1
    finderEvents.scripts.OnEvent(finderEvents, "LFG_LIST_ROLE_UPDATE")
    return true
end }
function IsInGroup() return grouped end
function UnitIsGroupLeader() return leader end
local groupSize, combat = 2, false
function GetNumGroupMembers() return groupSize end
function InCombatLockdown() return combat end
local activityInfo = C_LFGList.GetActivityInfoTable
function C_LFGList.GetActivityInfoTable(id)
    local info = activityInfo(id)
    if info then info.maxNumPlayers = 5 end
    return info
end
Enum = {
    LFGEntryGeneralPlaystyle = { Learning = 1, FunRelaxed = 2, FunSerious = 3, Expert = 4 },
    LFGEntryVoiceMode = { None = 0, Discord = 1, Legacy = 2, Custom = 3 },
}
local inferred = "healer"
addon.PreferredRole = function() return inferred end
assert(addon.ListingRoles, "the listing must support multi-role preferences")
assert(addon.ListingRoles().healer)
inferred = "dps"
assert(addon.ListingRoles().dps and not addon.ListingRoles().healer)
addon.SetListingRole("healer", true)
inferred = "tank"
local roles = addon.ListingRoles()
assert(roles.healer and roles.dps and not roles.tank)
addon.InitializeSettings()
assert(addon.ListingRoles().healer and addon.ListingRoles().dps)

function UnitGetAvailableRoles(unit)
    assert(unit == "player")
    return false, false, true
end
inferred = "dps"
addon.db.listingRoles = nil
addon.Refresh()
local myRoles = roleButtons["My roles"]
assert(myRoles[1]:IsVisible() and myRoles[2]:IsVisible() and myRoles[3]:IsVisible(), "every class can choose all three roles")
assert(not myRoles[1]:GetChecked() and not myRoles[2]:GetChecked() and myRoles[3]:GetChecked(), "damage is selected by default for a damage spec")
myRoles[1]:SetChecked(true)
myRoles[1].scripts.OnClick(myRoles[1])
assert(addon.ListingRoles().tank and addon.ListingRoles().dps, "listing roles can be combined")
myRoles[3]:SetChecked(false)
myRoles[3].scripts.OnClick(myRoles[3])
addon.InitializeSettings()
assert(addon.ListingRoles().tank and not addon.ListingRoles().dps, "manual tank-only choice survives settings initialization")
assert(roleButtons["Find roles"][1]:IsVisible() and not roleButtons["Find roles"][1]:GetChecked())

assert(not find("Button", "My listing"))
assert(find("Button", "List Me"))
addon.db.manualDungeonSelection = true
addon.db.activities = {}
addon.SelectionChanged()
assert(not find("Button", "List Me"))
assert(not addon.CreateListing() and #publications == 0)
addon.db.activities = { [1] = true, [3] = true }
addon.SelectionChanged()

local submit = assert(find("Button", "List Me"))
local friendly
for _, frame in ipairs(frames) do
    if frame.atlas == "UI-LFG-RoleIcon-Leader" then friendly = frame.parent end
end
assert(friendly and friendly:IsVisible() and friendly.enabled and not friendly:GetChecked())
assert(roleButtons["My roles"][1].parent.RIGHT[1] == friendly)
friendly:SetChecked(true)
friendly.scripts.OnClick(friendly)
addon.InitializeSettings()
assert(addon.db.listingNewPlayerFriendly)
local searchButton = assert(find("Button", "Search"))
assert(searchButton.width == submit.width and searchButton.height == submit.height, "toolbar buttons have equal size")
assert(searchButton.RIGHT[1] == submit and searchButton.RIGHT[2] == "LEFT" and searchButton.RIGHT[4] == 0,
    "search and listing buttons share a vertical center")
local light, pulse
for _, frame in ipairs(frames) do
    if frame.parent == submit and frame.mask then light = frame end
    if frame.kind == "AnimationGroup" and frame.parent == light then pulse = frame end
end
assert(light and pulse and light.mask.texture == "Interface\\CharacterFrame\\TempPortraitAlphaMask")
assert(light.width == light.height and light.LEFT[2] == 0)
local function redStatus()
    return light:IsVisible() and light.vertexColor[1] > light.vertexColor[2] and not pulse:IsPlaying()
end
local function greenStatus()
    return light:IsVisible() and light.vertexColor[2] > light.vertexColor[1] and pulse:IsPlaying()
end
assert(redStatus())
local createListing = C_LFGList.CreateListing
local clearCreationFields = C_LFGList.ClearCreationTextFields
local writesBeforeMissingCreate = roleWrites
C_LFGList.CreateListing = nil
local available, unavailableReason = addon.CreateListing()
assert(available == false and unavailableReason and not cleared and roleWrites == writesBeforeMissingCreate,
    "missing native create control leaves native text and roles alone")
C_LFGList.CreateListing = createListing
local nativeGetRoles = C_LFGListRoles.GetRoles
C_LFGListRoles.GetRoles = function() error("native role read unavailable") end
assert(not addon.ApplyListingRoleDraft(addon.ListingRoles(), true) and roleWrites == writesBeforeMissingCreate,
    "borrowing a native form requires readable previous role preferences")
C_LFGListRoles.GetRoles = nativeGetRoles
local nativeDraftBeforeFailure = LFGListingFrame
LFGListingFrame = { ActivityView = { Comment = { EditBox = { GetText = function() return "previous native draft" end } } } }
for _, clearFields in ipairs({
    function() error("native clear failure") end,
    function() return false end,
    function() end,
}) do
    C_LFGList.ClearCreationTextFields = clearFields
    local accepted, reason = addon.CreateListing()
    assert(accepted == false and reason and #publications == 0 and submit.enabled,
        "a failed or ineffective clear never publishes")
    assert(nativeRoles.healer and not nativeRoles.tank, "a failed preflight clear restores the previous native roles")
end
LFGListingFrame = nativeDraftBeforeFailure
C_LFGList.ClearCreationTextFields = clearCreationFields
C_LFGList.CreateListing = function() return false end
submit.scripts.OnClick(submit)
assert(nativeRoles.healer and not nativeRoles.tank, "explicit refusal restores the prior native roles")
C_LFGList.CreateListing = function()
    finderEvents.scripts.OnEvent(finderEvents, "LFG_LIST_ENTRY_CREATION_FAILED")
    return true
end
submit.scripts.OnClick(submit)
assert(nativeRoles.healer and not nativeRoles.tank and submit.enabled, "synchronous failure restores native roles")
C_LFGList.CreateListing = function() return true end
submit.scripts.OnClick(submit)
assert(not submit.enabled)
finderEvents.scripts.OnEvent(finderEvents, "LFG_LIST_ENTRY_CREATION_FAILED")
assert(submit.enabled and redStatus() and listingError, "server failure immediately enables a retry")
assert(nativeRoles.tank, "an untagged asynchronous failure does not rewrite roles")

nativeRoles = { tank = false, healer = true, dps = false }
C_LFGList.CreateListing = function()
    nativeRoles = { tank = false, healer = false, dps = true }
    return false
end
submit.scripts.OnClick(submit)
assert(nativeRoles.dps, "explicit failure leaves a newer native selection intact")

C_LFGList.CreateListing = function()
    C_LFGListRoles.SetRoles({ tank = false, healer = true, dps = false }, false)
    C_LFGListRoles.SetRoles({ tank = true, healer = false, dps = false }, false)
    return false
end
submit.scripts.OnClick(submit)
assert(nativeRoles.tank, "intervening role updates invalidate rollback even when values match")
C_LFGList.CreateListing = function() return true end
nativeRoles = { tank = false, healer = true, dps = false }
submit.scripts.OnClick(submit)
local writesBeforeTimeout = roleWrites
deferred[#deferred]()
assert(nativeRoles.tank and roleWrites == writesBeforeTimeout and submit.enabled, "an unconfirmed timeout does not restore native roles")
nativeRoles = { tank = false, healer = true, dps = false }
C_LFGList.CreateListing = function() error("ambiguous API outcome") end
submit.scripts.OnClick(submit)
assert(nativeRoles.tank and submit.enabled, "an ambiguous API exception does not restore native roles")
C_LFGList.CreateListing = createListing
-- The deferred retry timer from the failed request must not release a newer request.
local failedTimer = deferred[#deferred]
submit.scripts.OnClick(submit)
failedTimer()
finderEvents.scripts.OnEvent(finderEvents, "LFG_LIST_ENTRY_CREATION_FAILED")
assert(not submit.enabled and sentRoles.tank, "a late failure cannot complete the newer attempt")
assert(#publications == 1 and publications[1].generalPlaystyle == Enum.LFGEntryGeneralPlaystyle.FunRelaxed)
assert(publications[1].voiceMode == Enum.LFGEntryVoiceMode.None)
assert(publications[1].newPlayerFriendly == true)
assert(#publications[1].activityIDs == 2 and publications[1].activityIDs[1] == 1 and publications[1].activityIDs[2] == 3)
assert(sentRoles.tank and not sentRoles.healer and not sentRoles.dps)
assert(submit.enabled == false and not addon.CreateListing() and #publications == 1)
assert(redStatus(), "pending is not active")

active = true
C_LFGList.GetActiveEntryInfo = function() if active then return { newPlayerFriendly = true } end end
finderEvents.scripts.OnEvent(finderEvents, "LFG_LIST_ACTIVE_ENTRY_UPDATE")
assert(find("Button", "Unlist") == submit and submit.enabled and not addon.CreateListing())
assert(friendly:GetChecked() and not friendly.enabled, "active listing displays the published flag")
assert(greenStatus(), "active listing shows a pulsing indicator")
rejectRemoval = true
submit.scripts.OnClick(submit)
assert(listingError and removals == 1 and submit.enabled and greenStatus())
rejectRemoval = false
addon.db.activities = {}
addon.SelectionChanged()
assert(find("Button", "Unlist") == submit, "the active listing can be removed without a search selection")
submit.scripts.OnClick(submit)
assert(removals == 2 and not submit.enabled and greenStatus())
submit.scripts.OnClick(submit)
assert(removals == 2, "pending removal blocks duplicate requests")
active = false
finderEvents.scripts.OnEvent(finderEvents, "LFG_LIST_ACTIVE_ENTRY_UPDATE")
assert(not submit:IsVisible())
addon.db.activities = { [1] = true, [3] = true }
addon.SelectionChanged()
assert(find("Button", "List Me") == submit and submit.enabled)
assert(redStatus(), "removal restores the red indicator")
table.remove(deferred, 1)()
local menuItems = {}
local function menuItem(data)
    local options = {}
    menuItems[data] = options
    return { CreateRadio = function(_, _, _, click, key) options[key] = click end }
end
local openComment
gear.generator(nil, {
    CreateButton = function(_, label, click)
        assert(label ~= "Add comment…" and label ~= "Saved comment…")
        if label == "Comment…" then openComment = click end
        return menuItem(label)
    end,
    CreateDivider = function() end,
})
menuItems.Playstyle.Learning("Learning")
menuItems["Voice chat"].Discord("Discord")
addon.InitializeSettings()
grouped = true
assert(not addon.CreateListing() and #publications == 1)
leader = true
finderEvents.scripts.OnEvent(finderEvents, "GROUP_ROSTER_UPDATE")
assert(find("Button", "List Party") == submit)
assert(friendly:IsVisible() and friendly.enabled)
groupSize, cleared = 5, false
local created, reason = addon.CreateListing()
assert(not created and reason:find("Your party is full", 1, true) and not cleared and #publications == 1)
groupSize = 2
friendly:SetChecked(false)
friendly.scripts.OnClick(friendly)
submit.scripts.OnClick(submit)
assert(#publications == 2)
assert(publications[2].generalPlaystyle == Enum.LFGEntryGeneralPlaystyle.Learning)
assert(publications[2].voiceMode == Enum.LFGEntryVoiceMode.Discord)
assert(publications[2].newPlayerFriendly == false)

active = true
finderEvents.scripts.OnEvent(finderEvents, "LFG_LIST_ACTIVE_ENTRY_UPDATE")
leader = false
finderEvents.scripts.OnEvent(finderEvents, "GROUP_ROSTER_UPDATE")
assert(find("Button", "Listed") == submit and not submit.enabled and greenStatus())
submit.scripts.OnClick(submit)
assert(removals == 2, "party members cannot remove the leader's listing")
leader = true
finderEvents.scripts.OnEvent(finderEvents, "GROUP_ROSTER_UPDATE")
submit.scripts.OnClick(submit)
assert(removals == 3)
deferred[#deferred]()
assert(find("Button", "Unlist") == submit and submit.enabled and greenStatus(), "unconfirmed removal can be retried")
submit.scripts.OnClick(submit)
assert(removals == 4)
active = false
finderEvents.scripts.OnEvent(finderEvents, "LFG_LIST_ACTIVE_ENTRY_UPDATE")
assert(find("Button", "List Party") == submit and redStatus())
active, grouped = false, false
local nativeActivities, focused, style, nativeCategory = {}, false, nil, nil
local nativeComment, commentChanged, nativeHidden, nativeShown = ""
local viewVisible = true
local edit = {
    IsEnabled = function() return true end,
    SetFocus = function() focused = true end,
    ClearFocus = function() focused = false end,
    GetText = function() return nativeComment end,
    HookScript = function(_, event, callback) assert(event == "OnTextChanged"); commentChanged = callback end,
}
local nativeView = {
    IsShown = function() return true end,
    IsVisible = function() return viewVisible end,
    HookScript = function(_, event, callback)
        if event == "OnShow" then nativeShown = callback
        else assert(event == "OnHide"); nativeHidden = callback end
    end,
    Comment = { EditBox = edit },
}
LFGListingFrame = {
    IsVisible = function() return true end,
    LoadSoloRoles = function() end,
    UpdatePostButtonEnableState = function() end,
    selectedActivities = 0,
    IsAnyActivitySelected = function() return #nativeActivities > 0 end,
    IsActivitySelected = function(_, id)
        for _, selected in ipairs(nativeActivities) do if selected == id then return true end end
    end,
    GetCategorySelection = function() return nativeCategory end,
    ClearCategorySelection = function(self) self:SetCategorySelection(nil) end,
    SetDirty = function(self, dirty) self.dirty = dirty end,
    SetAllActivities = function(self, selected)
        assert(not selected)
        self.selectedActivities = self.selectedActivities - #nativeActivities
        nativeActivities = {}
    end,
    SetCategorySelection = function(self, category)
        nativeCategory = category
        nativeActivities = {}
    end,
    SetActivity = function(self, id, selected)
        if selected then
            nativeActivities[#nativeActivities + 1] = id
            self.selectedActivities = self.selectedActivities + 1
            self.dirty = true
        end
        self:UpdatePostButtonEnableState()
    end,
    ActivityView = nativeView,
    voiceMode = Enum.LFGEntryVoiceMode.Legacy,
    NewPlayerFriendlyButton = { CheckButton = {
        GetChecked = function() return nativeView.friendly == true end,
        SetChecked = function(_, value) nativeView.friendly = value end,
    } },
}
function LFGVanilla_ToggleFrame() end
function LFGParentFrameTab1_OnClick() end
function LFGListingActivityView_UpdateActivities() end
function LFGListingActivityView_OnPlayStyleSelectedInternal(view, value)
    view.generalPlaystyle, style = value, value
end
local actualComment = CreateFrame("ScrollFrame", nil, LFGParentFrame)
actualComment.EditBox = edit
actualComment:SetFrameLevel(8)
actualComment:SetPoint("BOTTOM", 0, 42)
local actualPost = CreateFrame("Button", nil, LFGParentFrame)
actualPost:SetFrameLevel(4)
actualPost:SetPoint("BOTTOMRIGHT", -24, 19)
actualPost:SetText("List Self")
function actualPost:HasScript(name) return name == "PreClick" end
local nativePostClicks = 0
local refuseNativePost = false
local nativePost = function()
    nativePostClicks = nativePostClicks + 1
    if refuseNativePost then finderEvents.scripts.OnEvent(finderEvents, "LFG_LIST_ENTRY_CREATION_FAILED") end
end
actualPost:SetScript("OnClick", nativePost)
local function clickNativePost()
    actualPost.scripts.PreClick(actualPost)
    actualPost.scripts.OnClick(actualPost)
end
nativeView.Comment = actualComment
LFGListingFrame.PostButton = actualPost
C_LFGList.ClearCreationTextFields = function()
    cleared = true
    nativeComment = ""
end

local function assertInline()
    assert(find("FontString", "Listing comment") and not submit:IsVisible())
    assert(actualComment:GetFrameStrata() == "DIALOG" and actualPost:GetFrameStrata() == "DIALOG")
    local composer = actualComment.TOPLEFT[1]
    assert(composer:IsVisible() and actualComment.TOPRIGHT[1] == composer)
    assert(actualComment:GetFrameLevel() > composer:GetFrameLevel())
    assert(actualPost.TOPRIGHT[1] == composer and actualPost.TOPRIGHT[4] == -55)
end

local function assertRestored()
    assert(actualComment:GetFrameLevel() == 8 and actualPost:GetFrameLevel() == 4)
    assert(actualComment:GetFrameStrata() == "MEDIUM" and actualPost:GetFrameStrata() == "MEDIUM")
    local _, commentParent, _, _, commentY = actualComment:GetPoint(1)
    local _, postParent, _, _, postY = actualPost:GetPoint(1)
    assert(commentParent == LFGParentFrame and commentY == 42 and postParent == LFGParentFrame and postY == 19)
end

local settings = assert(find("Button", "Settings"))
LFGListingFrame:SetCategorySelection(9)
LFGListingFrame:SetActivity(5, true)
nativeComment = "Unrelated Blizzard draft"
local writesBeforeSettings = roleWrites
settings.scripts.OnClick()
assert(nativeCategory == 9 and nativeActivities[1] == 5 and nativeComment == "Unrelated Blizzard draft")
assert(roleWrites == writesBeforeSettings and find("Button", "Open Blizzard form"),
    "visiting Settings preserves an unrelated Blizzard draft")
assert(find("Button", "Players")).scripts.OnClick()
LFGListingFrame:SetAllActivities(false)
LFGListingFrame:ClearCategorySelection()
LFGListingFrame:SetDirty(false)
nativeComment = ""
C_LFGListRoles.SetRoles({ tank = false, healer = true, dps = false }, false)

settings.scripts.OnClick()
assertInline()
assert(not focused and not addon.db.listingComment and #publications == 2,
    "the real field is present on first opening Settings without a saved draft")
assert(nativeActivities[1] == 1 and nativeActivities[2] == 3)
assert(sentRoles.tank and not sentRoles.healer and not sentRoles.dps)
assert(style == Enum.LFGEntryGeneralPlaystyle.Learning and LFGListingFrame.voiceMode == Enum.LFGEntryVoiceMode.Discord)
nativeComment = "First run, please wait for mana."
commentChanged(edit, true)
local savedDraft = nativeComment
assert(addon.db.listingComment == savedDraft)
actualComment:ClearAllPoints()
actualComment:SetPoint("BOTTOM", 0, 42)
nativeShown()
assertInline()

assert(find("Button", "Players")).scripts.OnClick()
assertRestored()
assert(submit:IsVisible() and not focused)
assert(nativeCategory == nil and #nativeActivities == 0 and not LFGListingFrame.dirty and nativeComment == "")
assert(LFGListingFrame.selectedActivities == 0, "restoring the blank category must also release its activity count")
assert(nativeRoles.healer and not nativeRoles.tank and style == nil
    and LFGListingFrame.voiceMode == Enum.LFGEntryVoiceMode.Legacy, "abandoning the editor restores the borrowed native state")

local setActivity = LFGListingFrame.SetActivity
LFGListingFrame.SetActivity = function() error("activity changed during setup") end
settings.scripts.OnClick()
assertRestored()
assert(nativeCategory == nil and nativeRoles.healer and not nativeRoles.tank)
assert(find("Button", "Open Blizzard form"):IsVisible())
LFGListingFrame.SetActivity = setActivity
find("Button", "Players").scripts.OnClick()

settings.scripts.OnClick()
assertInline()
nativeComment = "A newer Blizzard draft"
LFGListingFrame:SetAllActivities(false)
LFGListingFrame:SetActivity(4, true)
assertRestored()
assert(find("Button", "Open comment field"):IsVisible(), "a native activity change removes the embedded Post")
find("Button", "Players").scripts.OnClick()
assertRestored()
assert(nativeCategory == addon.dungeonCategory and nativeActivities[1] == 4
    and nativeComment == "A newer Blizzard draft")
LFGListingFrame:SetAllActivities(false)
LFGListingFrame:ClearCategorySelection()
LFGListingFrame:SetDirty(false)
nativeComment = ""

settings.scripts.OnClick()
assertInline()
C_LFGListRoles.SetRoles({ tank = false, healer = true, dps = false }, false)
finderEvents.scripts.OnEvent(finderEvents, "LFG_LIST_ROLE_UPDATE")
assertRestored()
assert(nativeRoles.healer and not nativeRoles.tank, "role changes remove Post and preserve the new native role")
find("Button", "Players").scripts.OnClick()
LFGListingFrame:SetAllActivities(false)
LFGListingFrame:ClearCategorySelection()
LFGListingFrame:SetDirty(false)
LFGListingFrame.voiceMode = Enum.LFGEntryVoiceMode.Legacy

settings.scripts.OnClick()
assertInline()
addon.SetAutomaticDungeonSelection(true)
addon.Refresh()
assertRestored()
local retryComment = assert(find("Button", "Open comment field"))
assert(retryComment:IsVisible())
retryComment.scripts.OnClick()
assertInline()
assert(#nativeActivities == 1 and nativeActivities[1] == addon.SelectedActivities()[1].id)
assert(style == Enum.LFGEntryGeneralPlaystyle.Learning and LFGListingFrame.voiceMode == Enum.LFGEntryVoiceMode.Discord)
nativeComment = "Draft retained after an activity refresh"
commentChanged(edit, true)
viewVisible = false
LFGListingFrame:ClearCategorySelection()
LFGListingActivityView_OnPlayStyleSelectedInternal(nativeView, Enum.LFGEntryGeneralPlaystyle.Expert)
nativeHidden()
deferred[#deferred]()
assertRestored()
assert(retryComment:IsVisible(), "the editor can reopen after Blizzard resets its activity view")
assert(LFGListingFrame.selectedActivities == 0 and nativeComment == ""
    and not LFGListingFrame.dirty and addon.db.listingComment == "Draft retained after an activity refresh")
assert(style == Enum.LFGEntryGeneralPlaystyle.Expert and LFGListingFrame.voiceMode == Enum.LFGEntryVoiceMode.Legacy,
    "reset restores owned options and preserves externally updated options")
viewVisible = true
retryComment.scripts.OnClick()
assertInline()
local setPostStrata = actualPost.SetFrameStrata
function actualPost:SetFrameStrata(strata)
    if combat then error("native frame layer temporarily locked") end
    return setPostStrata(self, strata)
end
combat = true
loader.scripts.OnEvent(loader, "PLAYER_REGEN_DISABLED")
assert(actualComment:GetFrameStrata() == "MEDIUM" and actualPost:GetFrameStrata() == "DIALOG")
assert(not retryComment:IsVisible() and nativeCategory == addon.dungeonCategory)
combat = false
loader.scripts.OnEvent(loader, "PLAYER_REGEN_ENABLED")
assertRestored()
actualPost.SetFrameStrata = setPostStrata
assert(retryComment:IsVisible() and nativeCategory == nil)
retryComment.scripts.OnClick()
assertInline()

local clearPostPoints, setPostPoint = actualPost.ClearAllPoints, actualPost.SetPoint
function actualPost:ClearAllPoints()
    if not combat then clearPostPoints(self) end
end
function actualPost:SetPoint(...)
    if not combat then setPostPoint(self, ...) end
end
combat = true
loader.scripts.OnEvent(loader, "PLAYER_REGEN_DISABLED")
assert(actualPost:GetPoint(1) == "TOPRIGHT" and actualPost:GetFrameStrata() == "MEDIUM",
    "the combat model silently denies only the anchor restore")
combat = false
loader.scripts.OnEvent(loader, "PLAYER_REGEN_ENABLED")
assertRestored()
actualPost.ClearAllPoints, actualPost.SetPoint = clearPostPoints, setPostPoint
local longComment = string.rep("Dungeon notes. ", 12) .. "|rRead this too."
addon.db.listingComment = longComment
retryComment.scripts.OnClick()
assertInline()
local reference = assert(find("FontString", (longComment:gsub("|", "||")))).parent
local tooltipOwner, tooltipLine, tooltipWrap
GameTooltip = {
    GetOwner = function() return tooltipOwner end,
    SetOwner = function(_, owner) tooltipOwner = owner end,
    SetText = function() end,
    Show = function() end,
    AddLine = function(_, value, ...) tooltipLine, tooltipWrap = value, select(4, ...) end,
}
function GameTooltip_Hide() tooltipOwner = nil end
addon.db.listingComment = "Newly typed comment"
reference.scripts.OnEnter(reference)
assert(tooltipOwner == reference and tooltipLine == longComment:gsub("|", "||") and tooltipWrap,
    "the Settings tooltip wraps the entire escaped reference shown when the editor opened")
addon.EndNativeDraft()
assert(not tooltipOwner and not reference:IsVisible(), "unmounting the editor dismisses its tooltip")
addon.db.listingComment = savedDraft
addon.SetAutomaticDungeonSelection(false)
find("Button", "Players").scripts.OnClick()

nativeComment = "A stale native value"
cleared = false
submit.scripts.OnClick(submit)
assert(cleared and nativeComment == "" and #publications == 3 and submit:IsVisible(),
    "List Me publishes without comments even with a saved draft and text in the native field")
assert(addon.db.listingComment == savedDraft)
active = true
finderEvents.scripts.OnEvent(finderEvents, "LFG_LIST_ACTIVE_ENTRY_UPDATE")
active = false
finderEvents.scripts.OnEvent(finderEvents, "LFG_LIST_ACTIVE_ENTRY_UPDATE")

openComment()
assertInline()
assert(focused and find("FontString", savedDraft))
nativeComment = "New comment typed into the genuine field."
commentChanged(edit, true)
assert(addon.db.listingComment == nativeComment)
listingError = nil
refuseNativePost = true
clickNativePost()
local _, _, refusedNativePost = addon.ListingState()
assert(not refusedNativePost and listingError and nativeComment == addon.db.listingComment,
    "a refusal inside the stock click does not start a wait even after an earlier timeout")
assertInline()
refuseNativePost = false
clickNativePost()
local _, _, nativePostPending = addon.ListingState()
assert(nativePostPending and nativePostPending.kind == "create", "the native Post reserves the listing until its outcome")
local nativePostTimer = deferred[#deferred]
find("Button", "Players").scripts.OnClick()
assert(find("Button", "Listing…") == submit and not submit.enabled)
local publishedBeforeFollowup, textBeforeFollowup = #publications, nativeComment
assert(not addon.CreateListing() and #publications == publishedBeforeFollowup and nativeComment == textBeforeFollowup,
    "direct posting cannot overlap a pending native Post or clear its comment")
find("Button", "Settings").scripts.OnClick()
active = true
finderEvents.scripts.OnEvent(finderEvents, "LFG_LIST_ACTIVE_ENTRY_UPDATE")
nativePostTimer()
local _, publishedByNative, waitingForNative = addon.ListingState()
assert(publishedByNative and not waitingForNative, "native activation settles the pending Post before its timer")
assert(nativePostClicks == 2 and not focused)
assertRestored()
assert(nativeCategory == addon.dungeonCategory and #nativeActivities == 2
    and nativeComment == addon.db.listingComment, "a posted listing keeps its native state")
active = false
finderEvents.scripts.OnEvent(finderEvents, "LFG_LIST_ACTIVE_ENTRY_UPDATE")
assert(retryComment:IsVisible(), "Settings can reopen the comment field after the listing ends")
find("Button", "Players").scripts.OnClick()

settings.scripts.OnClick()
assertInline()
find("Button", "Open Blizzard form").scripts.OnClick()
assertRestored()
assert(focused and not submit:IsVisible())
clickNativePost()
local _, _, fallbackPostPending = addon.ListingState()
assert(fallbackPostPending and not addon.CreateListing(), "a Post after explicit handoff also reserves the managed draft")
deferred[#deferred]()
local _, _, fallbackStillPending = addon.ListingState()
assert(not fallbackStillPending, "a missing native outcome allows a retry after the bounded wait")
SlashCmdList.PARTYFINDERFOREVER("settings")
assertInline()

find("Button", "Players").scripts.OnClick()
local setPostLevel = actualPost.SetFrameLevel
actualPost.SetFrameLevel = function(self, level)
    if level > 4 then return end
    setPostLevel(self, level)
end
settings.scripts.OnClick()
assertRestored()
assert(find("Button", "Open Blizzard form") and not submit:IsVisible(),
    "when native controls cannot mount, Settings keeps the explicit fallback")
actualPost.SetFrameLevel = setPostLevel
find("Button", "Players").scripts.OnClick()

function UnitFactionGroup() return "Horde" end
local searchResults = {
    { leaderName = "Commenter", numMembers = 1, activityIDs = { 1 }, comment = "Learning | first run" },
    { leaderName = "Quiet", numMembers = 1, activityIDs = { 1 }, comment = "" },
    { leaderName = "Restricted", numMembers = 1, activityIDs = { 1 }, comment = "restricted" },
    { leaderName = "Team", numMembers = 3, activityIDs = { 1 }, comment = "Bring water" },
    { leaderName = "Hunter placeholder", numMembers = 1, activityIDs = { 1 } },
    { leaderName = "Real hunter spec", numMembers = 1, activityIDs = { 1 } },
}
function canaccessvalue(value) return value ~= "restricted" end
C_LFGList.Search = function() end
C_LFGList.GetFilteredSearchResults = function() return 6, { 1, 2, 3, 4, 5, 6 } end
C_LFGList.GetSearchResultInfo = function(id) return searchResults[id] end
C_LFGList.GetSearchResultPlayerInfo = function(id)
    local specNames = { "Elemental", "Shaman", "restricted", nil, " hunter ", "Beast Mastery" }
    return { classFilename = id >= 5 and "HUNTER" or "SHAMAN", level = 31,
        className = id < 5 and "Shaman" or nil, specName = specNames[id], lfgRoles = { dps = true } }
end
C_LFGList.GetSearchResultLeaderInfo = function()
    return { classFilename = "HUNTER", specName = "Survival", lfgRoles = { dps = true } }
end
search()
finderEvents.scripts.OnEvent(finderEvents, "LFG_LIST_SEARCH_RESULTS_RECEIVED")
local card = assert(find("FontString", "Commenter")).parent
assert(card.commentMark:IsVisible() and not find("FontString", "Quiet").parent.commentMark:IsVisible())
assert(not find("FontString", "Restricted").parent.commentMark:IsVisible())
local tooltip = {}
GameTooltip = { GetOwner = function() end, SetOwner = function() tooltip = {} end, SetText = function() end, Show = function() end,
    AddLine = function(_, line) tooltip[#tooltip + 1] = line end }
card.scripts.OnEnter(card)
assert(tooltip[1] == "Level 31 · Elemental" and card.icons.dps:IsVisible())
assert(tooltip[#tooltip] == "Comment: Learning || first run")
for _, name in ipairs({ "Quiet", "Restricted", "Hunter placeholder" }) do
    local playerCard = find("FontString", name).parent
    playerCard.scripts.OnEnter(playerCard)
    assert(tooltip[1] == "Level 31" and playerCard.icons.dps:IsVisible())
end
local hunter = assert(find("FontString", "Real hunter spec")).parent
hunter.scripts.OnEnter(hunter)
assert(tooltip[1] == "Level 31 · Beast Mastery")
find("Button", "Groups (1)").scripts.OnClick()
local team = assert(find("FontString", "Team")).parent
team.scripts.OnEnter(team)
assert(tooltip[1] == "3 players · Leader: Survival")
assert(team.commentMark:IsVisible() and tooltip[#tooltip] == "Comment: Bring water")
print("Passed direct listing, saved preferences, native composer, and comment save, reuse and removal")
