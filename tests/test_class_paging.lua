-- Run with Lua 5.1 and pass the addon directory as the first argument.
local fixturePath = (arg[0]:match("^(.*[/\\])") or "") .. "window_fixture.lua"
local addon, frames = assert(loadfile(fixturePath))(arg[1] or ".")
local scroll
for _, frame in ipairs(frames) do
    if frame.kind == "ScrollFrame" then scroll = frame end
end
local panel = assert(scroll).parent
panel:SetSize(454, 507)

local function seedPlayers(classCount)
    addon.players = {}
    for index = 1, classCount do
        addon.players[index] = {
            class = addon.classOrder[index], count = 1, id = index,
            name = "Player " .. index, target = "Player " .. index,
        }
    end
    addon.groups = {}
    addon.Refresh()
end

local function findLabel(kind, label)
    for _, frame in ipairs(frames) do
        if frame.kind == kind and frame.label == label and frame:IsVisible() then return frame end
    end
    error("Missing " .. label)
end

local function assertPage(first, count, width, height, spacing)
    local visibleCards = 0
    for _, frame in ipairs(frames) do
        if frame.kind == "FontString" and type(frame.label) == "string"
            and frame.label:match("^Player %d+$") and frame:IsVisible() then
            visibleCards = visibleCards + 1
        end
    end
    assert(visibleCards == count, "only the current page's cards are visible")
    for index = 0, count - 1 do
        local card = findLabel("FontString", "Player " .. (first + index)).parent
        assert(card.width == width and card.height == height, "cards keep the same size on every page")
        assert(card.parent.width == width and card.parent.TOPLEFT[1] == index * spacing)
        local atlas = "groupfinder-icon-class-" .. addon.classOrder[first + index]:lower()
        local header
        for _, frame in ipairs(frames) do
            if frame.atlas == atlas and frame.parent.kind == "Frame" and frame:IsVisible() then
                header = frame.parent
                break
            end
        end
        assert(header and header.width == width and header.TOPLEFT[1] == index * spacing,
            "class header stays aligned with its cards")
    end
end

seedPlayers(9)
local firstCard = findLabel("FontString", "Player 1").parent
local secondCard = findLabel("FontString", "Player 2").parent
local width, height = firstCard.width, firstCard.height
local spacing = secondCard.parent.TOPLEFT[1]
local nextPage = findLabel("Button", "›")
local previousPage = findLabel("Button", "‹")
local inset = scroll.TOPLEFT[1]
assert(inset == -scroll.BOTTOMRIGHT[1] and 3 * spacing + width == panel.width - 2 * inset,
    "the four columns fill the area between equal side margins")
assertPage(1, 4, width, height, spacing)
nextPage.scripts.OnClick(nextPage)
assertPage(5, 4, width, height, spacing)
nextPage.scripts.OnClick(nextPage)
assertPage(9, 1, width, height, spacing)
previousPage.scripts.OnClick(previousPage)
assertPage(5, 4, width, height, spacing)
seedPlayers(6)
assertPage(5, 2, width, height, spacing)
seedPlayers(7)
assertPage(5, 3, width, height, spacing)
seedPlayers(2)
assertPage(1, 2, width, height, spacing)
panel:SetWidth(474)
panel.scripts.OnSizeChanged(panel)
assertPage(1, 2, width + 5, height, spacing + 5)
print("Passed fixed card and header sizes on full and partial pages, including pooled cards")
