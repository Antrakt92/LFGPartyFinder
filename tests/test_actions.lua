-- Run with Lua 5.1 and pass the addon directory as the first argument.
local fixturePath = (arg[0]:match("^(.*[/\\])") or "") .. "window_fixture.lua"
local addon, _, _, events, search = assert(loadfile(fixturePath))(arg[1] or ".")

local now, partyCount = 1, 0
local canInvite, lockdown, confirmInvite, inviteThrows, combat = true, false, false, false, false
local requestThrows = false
local grouped, leader, assistant, partyFull = false, false, false, false
local calls = {}
function GetTime() return now end
function InCombatLockdown() return combat end
function UnitFactionGroup() return "Horde" end
function GetNumGroupMembers() return partyCount end
function IsInGroup() return grouped end
function UnitIsGroupLeader() return leader end
function UnitIsGroupAssistant() return assistant end
function IsInRaid() return false end
function UnitClass() return "Mage", "MAGE" end
function UnitGroupRolesAssigned() return "NONE" end
ChatFrameUtil = { SendTell = function(target) calls[#calls + 1] = { "open", target } end }
C_PartyInfo = {
    CanInvite = function() return canInvite end,
    IsPartyFull = function() return partyFull end,
    InviteUnit = function(target)
        if inviteThrows then error("protected invite failed") end
        calls[#calls + 1] = { "invite", target }
        if confirmInvite then events.scripts.OnEvent(events, "INVITE_TO_PARTY_CONFIRMATION", target .. "-Realm") end
    end,
    RequestInviteFromUnit = function(target, tank, healer, dps)
        if requestThrows then error("protected request failed") end
        calls[#calls + 1] = { "request", target, tank = tank, healer = healer, dps = dps }
    end,
}
C_ChatInfo = {
    InChatMessagingLockdown = function() return lockdown end,
    SendChatMessage = function(text, chatType, _, target)
        assert(chatType == "WHISPER")
        calls[#calls + 1] = { "send", target, text }
    end,
}
local originalActivity = C_LFGList.GetActivityInfoTable
C_LFGList.GetActivityInfoTable = function(id)
    local activity = originalActivity(id)
    if activity then activity.maxNumPlayers = 5 end
    return activity
end
local results = {
    { activityIDs = { 1 }, hasSelf = false, isDelisted = false, leaderName = "Solo", numMembers = 1, partyGUID = "old-solo" },
    { activityIDs = { 1 }, hasSelf = false, isDelisted = false, leaderName = "Group leader", numMembers = 4 },
}
C_LFGList.GetSearchResultInfo = function(id) return results[id] end
C_LFGList.Search = function() return true end
C_LFGList.GetFilteredSearchResults = function() return 2, { 1, 2 } end
C_LFGList.GetSearchResultPlayerInfo = function() return {} end
C_LFGList.GetSearchResultLeaderInfo = function() return {} end
addon.db.manualDungeonSelection = true
addon.db.activities = { [1] = true, [2] = true }
search()
events.scripts.OnEvent(events, "LFG_LIST_SEARCH_RESULTS_RECEIVED")
local solo, group = assert(addon.players[1]), assert(addon.groups[1])
local function assertAction(kind, target, pattern)
    local call = assert(table.remove(calls, 1))
    assert(call[1] == kind and call[2] == target)
    if pattern then assert(call[3]:find(pattern, 1, true)) end
end

partyCount = 5
local blocked, reason = addon.Act(solo)
assert(blocked == false and reason and #calls == 0, "a full dungeon party neither invites nor whispers")
partyCount, canInvite = 0, false
assert(addon.Act(solo) == false and #calls == 0, "native invite permission cannot be skipped")
canInvite, combat = true, true
addon.Act(solo)
assert(#calls == 0)
combat, confirmInvite = false, true
addon.Act(solo)
assertAction("invite", "Solo")
assert(#calls == 0, "a pending native confirmation has not sent an invite whisper")

confirmInvite, now = false, 3
inviteThrows = true
assert(addon.Act(solo) == false and #calls == 0, "a native invite error suppresses its whisper")
inviteThrows, now = false, 5
addon.Act(solo)
assertAction("invite", "Solo")
assertAction("send", "Solo", "Need a tank, a healer, 2 DPS.")
addon.Act(group)
assert(#calls == 0, "the click cooldown also covers a second card")

now, lockdown = 7, true
assert(addon.Act(group) == false and #calls == 0, "a locked chat does not call SendChatMessage")
now, lockdown = 9, false
addon.Act(group)
assertAction("send", "Group leader", "level 32 Mage")
addon.OpenWhisper(group)
assertAction("open", "Group leader")
now = 11
addon.db.askText = " "
addon.db.listingRoles = { tank = false, healer = true, dps = true }
addon.Act(group)
assert(calls[1].tank == false and calls[1].healer == true and calls[1].dps == true,
    "a blank ask template conveys the selected multi-role preferences to the native request")
assertAction("request", "Group leader")
addon.Act(group)
assert(#calls == 0, "an empty join template requests entry without a whisper and uses the action cooldown")
local isInGroup = IsInGroup
function IsInGroup() return false end
C_LFGList.HasActiveEntryInfo = function() return true end
C_LFGListRoles = { GetRoles = function() return { tank = true, healer = false, dps = false } end }
now = 13
addon.Act(group)
assert(calls[1].tank == true and calls[1].healer == false and calls[1].dps == false,
    "an active solo listing uses its actual roles just like the visible role controls")
assertAction("request", "Group leader")
C_LFGListRoles.GetRoles = function() return nil end
now = 15
addon.Act(group)
assert(calls[1].tank == nil and calls[1].healer == nil and calls[1].dps == nil,
    "unreadable active roles stay unspecified instead of using a conflicting saved preference")
assertAction("request", "Group leader")
function IsInGroup() return true end
now = 17
addon.Act(group)
assert(calls[1].tank == false and calls[1].healer == true and calls[1].dps == true,
    "party requests use the editable role preferences")
assertAction("request", "Group leader")
IsInGroup = isInGroup
C_LFGList.HasActiveEntryInfo = function() return false end
addon.db.listingRoles = { tank = false, healer = false, dps = false }
now = 19
addon.Act(group)
assert(calls[1].tank == nil and calls[1].healer == nil and calls[1].dps == nil,
    "all roles unchecked retains a role-agnostic native request")
assertAction("request", "Group leader")
now, requestThrows = 21, true
local ok, requestError = addon.Act(group)
assert(ok == false and requestError and #calls == 0, "a native request error is reported without sending a whisper")
now = 23
results[1].activityIDs = { 2 }
addon.Act(solo)
addon.OpenWhisper(solo)
assert(#calls == 0, "a stale card cannot act for an activity that left the listing")
results[1].activityIDs, results[1].partyGUID = { 1 }, "new-solo"
addon.Act(solo)
assert(#calls == 0, "a stale card cannot act on a replacement listing from the same leader")

results[1].partyGUID = "old-solo"
grouped, partyCount, canInvite = true, 3, false
addon.Act(solo)
assertAction("invite", "Solo")
assert(#calls == 0, "a suggestion uses the native invite API without whispering to the candidate")
addon.Act(solo)
assert(#calls == 0, "a suggestion shares the action cooldown")
now, partyCount = 25, 5
assert(addon.Act(solo) == false and #calls == 0, "a full dungeon party cannot suggest an invite")
partyCount, partyFull = 3, true
assert(addon.Act(solo) == false and #calls == 0, "native party capacity also applies to suggestions")
partyFull, inviteThrows = false, true
local suggested, suggestionError = addon.Act(solo)
assert(suggested == false and suggestionError:find("suggest", 1, true) and #calls == 0)
now, inviteThrows, leader, canInvite = 27, false, true, true
addon.Act(solo)
assertAction("invite", "Solo")
assertAction("send", "Solo", "Invited you")
now, leader, assistant = 29, false, true
addon.Act(solo)
assertAction("invite", "Solo")
assertAction("send", "Solo", "Invited you")

local prefix = string.rep("a", 254)
assert(addon.RenderTemplate(prefix .. "€", {}) == prefix, "cuts at the 255-byte limit without breaking UTF-8")
assert(addon.RenderTemplate("x %unknown%  %class%", { class = "Mage" }) == "x %unknown% Mage")
assert(addon.RenderTemplate(string.rep(string.char(128), 256), {}) == "", "malformed input cannot run past byte zero")
print("Passed action identity, invite capacity, native confirmation, whisper restrictions and UTF-8 limits")
