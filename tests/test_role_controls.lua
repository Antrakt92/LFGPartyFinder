local fixturePath = (arg[0]:match("^(.*[/\\])") or "") .. "window_fixture.lua"
local addon, frames, _, events = assert(loadfile(fixturePath))(arg[1] or ".")

local function visible(kind, label)
    for _, frame in ipairs(frames) do
        if frame.kind == kind and frame.label == label and frame:IsVisible() then return frame end
    end
end

local function rosterUpdated()
    events.scripts.OnEvent(events, "GROUP_ROSTER_UPDATE")
end

local grouped, active = false, false
function IsInGroup() return grouped end
function UnitIsGroupLeader() return true end
C_LFGList.HasActiveEntryInfo = function() return active end
local nativeRoles = { tank = true, healer = false, dps = false }
C_LFGListRoles = { GetRoles = function() return nativeRoles end }
addon.SetListingRole("healer", true)
addon.SetListingRole("dps", false)
addon.groups = {
    { id = 1, name = "Tank needed", count = 4, openRoles = { tank = true } },
    { id = 2, name = "Healer needed", count = 4, openRoles = { healer = true } },
}
addon.Refresh()
assert(visible("Button", "Groups (2)")).scripts.OnClick()
local groupFilter = assert(visible("FontString", "Has roles")).parent
local room
for _, control in ipairs(frames) do
    if control.parent == groupFilter and control.template == "UICheckButtonTemplate" then room = control end
end
assert(room)
room:SetChecked(true)
room.scripts.OnClick(room)
assert(visible("Button", "Groups (1)") and visible("FontString", "Healer needed"))

grouped = true
rosterUpdated()
local myRoles = assert(visible("FontString", "My roles"), "party members can see the roles used for the group filter")
local tank, healer
for _, control in ipairs(frames) do
    if control.parent == myRoles.parent and control.icon then
        if control.icon.atlas == addon.roles[1].icon then tank = control end
        if control.icon.atlas == addon.roles[2].icon then healer = control end
    end
end
assert(tank.enabled and healer:GetChecked() and visible("FontString", "Healer needed"))
tank:SetChecked(true)
tank.scripts.OnClick(tank)
assert(visible("Button", "Groups (2)"), "the group filter follows the visible role choices")
tank:SetChecked(false)
tank.scripts.OnClick(tank)

grouped, active = false, true
rosterUpdated()
assert(visible("FontString", "Listed") and tank:GetChecked() and not healer:GetChecked())
assert(tank.enabled == false and visible("FontString", "Tank needed"))
assert(not visible("FontString", "Healer needed") and addon.db.listingRoles.healer)
nativeRoles = nil
addon.Refresh()
assert(not room.enabled and not room:GetChecked() and visible("Button", "Groups (2)"),
    "uncertain active roles suspend the room filter rather than hiding groups")

active = false
rosterUpdated()
assert(room.enabled and room:GetChecked() and healer:GetChecked() and healer.enabled)
assert(visible("FontString", "Healer needed") and not visible("FontString", "Tank needed"))
grouped = true
local leader = false
function UnitIsGroupLeader() return leader end
rosterUpdated()
local submit = assert(visible("Button", "List Party"))
assert(submit.enabled == false, "only the group leader can start a listing")
local tooltip, owner
GameTooltip = {
    GetOwner = function() return owner end,
    SetOwner = function(_, control) owner = control end,
    SetText = function(_, value) tooltip = value end,
    Show = function() end,
}
function GameTooltip_Hide() owner = nil end
submit.scripts.OnEnter(submit)
assert(tooltip == "Only the party leader can list or unlist the party.")
leader = true
assert(events.events.PARTY_LEADER_CHANGED, "the addon listens for the native leadership event")
events.scripts.OnEvent(events, "PARTY_LEADER_CHANGED")
assert(submit.enabled == true and owner == nil, "promotion enables listing and dismisses the old tooltip")
active, leader = true, false
rosterUpdated()
assert(visible("Button", "Listed") == submit and submit.enabled == false)
print("Passed visible filter roles, native role readback, and party listing permissions")
