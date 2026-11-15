-- Run with Lua 5.1 and pass the addon directory as the first argument.
local fixturePath = (arg[0]:match("^(.*[/\\])") or "") .. "window_fixture.lua"
local addon, frames, deferred, finderEvents, search = assert(loadfile(fixturePath))(arg[1] or ".")

local function find(kind, label)
    for _, frame in ipairs(frames) do
        if frame.kind == kind and frame.label == label and frame:IsVisible() then return frame end
    end
end

local gear, commentMark
for _, frame in ipairs(frames) do
    if frame.template == "LFGOptionsButton" then gear = frame end
    if gear and frame.parent == gear and frame ~= gear.Icon then commentMark = frame end
end
assert(gear and gear.width == 28 and commentMark and not commentMark:IsVisible())
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
C_LFGListRoles = { SetRoles = function(roles, limitToClassRoles)
    assert(limitToClassRoles == false)
    sentRoles = roles
    return true
end }
function IsInGroup() return grouped end
function UnitIsGroupLeader() return leader end
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
C_LFGList.CreateListing = function() return true end
submit.scripts.OnClick(submit)
assert(not submit.enabled)
finderEvents.scripts.OnEvent(finderEvents, "LFG_LIST_ENTRY_CREATION_FAILED")
assert(submit.enabled and redStatus() and listingError, "server failure immediately enables a retry")
C_LFGList.CreateListing = createListing
-- The deferred retry timer from the failed request must not release a newer request.
local failedTimer = deferred[#deferred]
submit.scripts.OnClick(submit)
failedTimer()
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
local nativeActivities, focused, style = { 5 }, false, nil
local nativeComment, commentChanged, nativeHidden = ""
local viewVisible = true
local edit = {
    IsEnabled = function() return true end,
    SetFocus = function() focused = true end,
    GetText = function() return nativeComment end,
    HookScript = function(_, event, callback) assert(event == "OnTextChanged"); commentChanged = callback end,
}
local nativeView = {
    IsShown = function() return true end,
    IsVisible = function() return viewVisible end,
    HookScript = function(_, event, callback) assert(event == "OnHide"); nativeHidden = callback end,
    Comment = { EditBox = edit },
}
LFGListingFrame = {
    IsVisible = function() return true end,
    LoadSoloRoles = function() end,
    SetAllActivities = function(_, selected) assert(not selected); nativeActivities = {} end,
    SetCategorySelection = function(_, category)
        assert(category == addon.dungeonCategory)
        nativeActivities = { 5 }
    end,
    SetActivity = function(_, id, selected) if selected then nativeActivities[#nativeActivities + 1] = id end end,
    ActivityView = nativeView,
    NewPlayerFriendlyButton = { CheckButton = { SetChecked = function(_, value) nativeView.friendly = value end } },
}
function LFGVanilla_ToggleFrame() end
function LFGParentFrameTab1_OnClick() end
function LFGListingActivityView_UpdateActivities() end
function LFGListingActivityView_OnPlayStyleSelectedInternal(_, value) style = value end
local guidance
UIErrorsFrame = { AddMessage = function(_, value) guidance = value end }
openComment()
assert(find("FontString", "Listing comment") and not focused and #nativeActivities == 1)
for _, frame in ipairs(frames) do
    if frame.kind == "EditBox" and frame:IsVisible() and frame:GetText() == "" then
        frame:SetText("First run draft.")
        frame.scripts.OnTextChanged(frame, true)
        break
    end
end
assert(addon.db.listingComment == "First run draft.")
find("Button", "Players").scripts.OnClick()
friendly:SetChecked(true)
friendly.scripts.OnClick(friendly)
sentRoles = nil
submit.scripts.OnClick(submit)
assert(focused and #publications == 2 and #nativeActivities == 2, "open native composer without publishing")
assert(nativeActivities[1] == 1 and nativeActivities[2] == 3)
assert(nativeView.friendly == true, "native composer receives the same flag")
assert(sentRoles.tank and not sentRoles.healer and not sentRoles.dps, "native composer receives the same manual role")
assert(guidance and guidance:find("listing button", 1, true))
assert(style == Enum.LFGEntryGeneralPlaystyle.Learning and LFGListingFrame.voiceMode == Enum.LFGEntryVoiceMode.Discord)
nativeComment = "First run, please wait for mana."
commentChanged(edit, true)
assert(addon.db.listingComment == nativeComment)
local savedDraft = nativeComment
viewVisible = false
nativeHidden()
deferred[#deferred]()
viewVisible = true
nativeComment = "Unrelated Blizzard draft"
commentChanged(edit, true)
assert(addon.db.listingComment == savedDraft, "typing in a later native composer cannot overwrite the draft")
nativeComment = savedDraft
local getActiveEntry = C_LFGList.GetActiveEntryInfo
active = true
C_LFGList.GetActiveEntryInfo = function() return { activityIDs = { 1, 3 }, comment = "Other leader's listing" } end
finderEvents.scripts.OnEvent(finderEvents, "LFG_LIST_ACTIVE_ENTRY_UPDATE")
assert(addon.db.listingComment == savedDraft, "unrelated listing events do not replace the draft")
active = false
C_LFGList.GetActiveEntryInfo = getActiveEntry
SlashCmdList.PARTYFINDERFOREVER()
assert(gear:IsVisible() and commentMark:IsVisible())
addon.InitializeSettings()
assert(addon.db.listingComment == nativeComment)
nativeComment = ""
local ok, _, needsComment = addon.CreateListing()
assert(not ok and needsComment and #publications == 2, "missing native draft must not publish without saved comment")
nativeComment = addon.db.listingComment
cleared = false
C_LFGList.CreateListing = function(data)
    assert(not cleared and nativeComment == addon.db.listingComment)
    publications[#publications + 1] = data
    return true
end
assert(addon.CreateListing() and #publications == 3)
active = true
finderEvents.scripts.OnEvent(finderEvents, "LFG_LIST_ACTIVE_ENTRY_UPDATE")
active = false
SlashCmdList.PARTYFINDERFOREVER("settings")
local savedEdit = assert(find("EditBox", nativeComment))
assert(not find("Button", "Remove"))
savedEdit:SetText("")
savedEdit.scripts.OnTextChanged(savedEdit, true)
find("Button", "Players").scripts.OnClick()
assert(not cleared and addon.db.listingComment == nil and gear:IsVisible() and not commentMark:IsVisible(),
    "clearing the addon's draft does not wipe independent native editor fields")

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
