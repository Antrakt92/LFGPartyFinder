-- Run with Lua 5.1 and pass the addon directory as the first argument.
local fixturePath = (arg[0]:match("^(.*[/\\])") or "") .. "window_fixture.lua"
local addon, frames = assert(loadfile(fixturePath))(arg[1] or ".")

local function listing(id, name)
    return { id = id, count = 1, class = "MAGE", name = name, target = name }
end

local function show(entry)
    addon.players = entry and { entry } or {}
    addon.groups = {}
    addon.Refresh()
end

local actedOn, whisperedTo, tooltipOwner, tooltipTitle, tooltipLastLine
addon.Act = function(entry) actedOn = entry end
addon.OpenWhisper = function(entry) whisperedTo = entry end
GameTooltip = {
    GetOwner = function() return tooltipOwner end,
    SetOwner = function(_, owner) tooltipOwner = owner end,
    SetText = function(_, title) tooltipTitle = title end,
    AddLine = function(_, line) tooltipLastLine = line end,
    Show = function() end,
}
function GameTooltip_Hide() tooltipOwner = nil end

local contextTitle, contextActions
MenuUtil = { CreateContextMenu = function(owner, populate)
    contextActions = {}
    populate(owner, {
        CreateTitle = function(_, title) contextTitle = title end,
        CreateButton = function(_, label, action) contextActions[label] = action end,
    })
end }

local alice, bob = listing(1, "Alice"), listing(2, "Bob")
show(alice)
local card
for _, frame in ipairs(frames) do
    if frame.entry == alice then card = frame; break end
end
local action = assert(card).action
action.scripts.OnEnter(action)
assert(tooltipTitle == "Alice" and tooltipLastLine == "Invite to Party")
action.scripts.OnMouseDown(action, "LeftButton")
show(bob)
assert(card.entry == bob and tooltipTitle == "Bob", "reused hovered card refreshes its tooltip")
action.scripts.OnClick(action, "LeftButton")
assert(not actedOn, "reused card cannot change the target of a click already in progress")

action.scripts.OnMouseDown(action, "LeftButton")
local refreshedBob = listing(2, "Bob")
show(refreshedBob)
action.scripts.OnClick(action, "LeftButton")
assert(actedOn == refreshedBob, "refreshing the same listing preserves the click")

local formerParty, newParty = listing(2, "Bob"), listing(2, "Bob")
formerParty.partyGUID, newParty.partyGUID = "original", "replacement"
formerParty.activity, newParty.activity = { id = 1 }, { id = 1 }
show(formerParty)
action.scripts.OnMouseDown(action, "LeftButton")
show(newParty)
action.scripts.OnClick(action, "LeftButton")
assert(actedOn == refreshedBob, "same result ID cannot target a different party")
action.scripts.OnMouseDown(action, "LeftButton")
local newDungeon = listing(2, "Bob")
newDungeon.partyGUID, newDungeon.activity = "replacement", { id = 2 }
show(newDungeon)
action.scripts.OnClick(action, "LeftButton")
assert(actedOn == refreshedBob, "same party cannot target a different dungeon")

card.scripts.OnMouseDown(card, "RightButton")
show(alice)
card.scripts.OnMouseUp(card, "RightButton", true)
assert(not contextTitle, "right press cannot move to a new target")
card.scripts.OnMouseDown(card, "RightButton")
card.scripts.OnMouseUp(card, "RightButton", true)
assert(contextTitle == "Alice")
contextActions["Send Message"]()
assert(whisperedTo == alice)
show(bob)
contextActions["Invite to Party"]()
assert(actedOn == refreshedBob, "stale context action is ignored after the row's target changes")

action.scripts.OnEnter(action)
action.scripts.OnMouseDown(action, "LeftButton")
show(nil)
assert(not action:IsVisible())
action.scripts.OnClick(action, "LeftButton")
assert(actedOn == refreshedBob, "a hidden row cannot trigger a pending action")

function IsInGroup() return true end
function UnitIsGroupLeader() return false end
function UnitIsGroupAssistant() return false end
show(alice)
action.scripts.OnEnter(action)
assert(tooltipLastLine == "Suggest Invite")
card.scripts.OnMouseDown(card, "RightButton")
card.scripts.OnMouseUp(card, "RightButton", true)
contextActions["Suggest Invite"]()
assert(actedOn == alice, "the suggestion menu uses the same listing action as the plus button")
print("Passed card hover identity, press/repaint, context actions, and hidden rows")
