-- Mining Module for Anthill
local sleep = sleep or os.sleep
-- Handles shaft digging and ore scanning
local gps = require("bettergps")
local function handleError(msg, reporter)
    if reporter then
        while true do
            reporter(msg)
            sleep(10)
        end
    else
        error(msg)
    end
end

local oreWhitelist = {
    ["minecraft:coal_ore"] = true,
    ["minecraft:deepslate_coal_ore"] = true,
    ["minecraft:iron_ore"] = true,
    ["minecraft:deepslate_iron_ore"] = true,
    ["minecraft:gold_ore"] = true,
    ["minecraft:deepslate_gold_ore"] = true,
    ["minecraft:redstone_ore"] = true,
    ["minecraft:deepslate_redstone_ore"] = true,
    ["minecraft:lapis_ore"] = true,
    ["minecraft:deepslate_lapis_ore"] = true,
    ["minecraft:diamond_ore"] = true,
    ["minecraft:deepslate_diamond_ore"] = true,
    ["minecraft:emerald_ore"] = true,
    ["minecraft:deepslate_emerald_ore"] = true,
    ["minecraft:copper_ore"] = true,
    ["minecraft:deepslate_copper_ore"] = true,
    ["minecraft:raw_iron_block"] = true,
    ["minecraft:raw_gold_block"] = true,
    ["minecraft:raw_copper_block"] = true
}

local function scanAndDig()
    for i = 1, 4 do
        local success, data = turtle.inspect()
        if success and oreWhitelist[data.name] then
            turtle.dig()
        end
        turtle.turnRight()
    end
end

local function digShaft(targetY, onUpdate, reporter)
    local x, y, z = gps.locate(5)
    if not y then
        -- GPS outage at surface (we're at surface when digShaft called)
        while not y do
            print("GPS outage - hibernating...")
            sleep(30)
            x, y, z = gps.locate(5)
        end
    end
    local startY = y

    while y > targetY do
        -- Try to dig down if blocked
        if turtle.inspectDown() then
            turtle.digDown()
        end

        -- Try to move down
        if turtle.down() then
            y = y - 1
            if onUpdate then onUpdate(y) end

            -- Scan at new level (skips surfaceY, ends at targetY)
            scanAndDig()
        else
            -- Cannot move down after digging - likely bedrock
            -- Check if it's a fuel issue first
            if turtle.getFuelLevel() == 0 then
                handleError("OUT OF FUEL: Depth reached but fuel depleted during descent.", reporter)
            end
            -- Otherwise it's bedrock or an unbreakable block - stop here
            break
        end

        -- Check inventory space
        local full = true
        for i = 1, 16 do
            if turtle.getItemCount(i) == 0 then
                full = false
                break
            end
        end
        if full then return "FULL", startY - y end
    end

    return "DONE", startY - y
end

return {
    digShaft = digShaft
}
