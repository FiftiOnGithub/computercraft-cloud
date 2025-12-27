-- Navigation Module for Anthill
local sleep = sleep or os.sleep
-- Handles movement, traffic, and GPS resilience

local travelHeightA = nil
local travelHeightB = nil

local function setConfig(config)
    travelHeightA = config.travelHeightA or travelHeightA
    travelHeightB = config.travelHeightB or travelHeightB
end

local function tryRefuel()
    local currentLevel = turtle.getFuelLevel()
    if currentLevel ~= "unlimited" and currentLevel < 100 then
        -- Try to find fuel in inventory
        for i = 1, 16 do
            turtle.select(i)
            if turtle.refuel(0) then -- Check if it's fuel
                turtle.refuel()
                if turtle.getFuelLevel() > 500 then
                    print("Refueled. Current level: " .. turtle.getFuelLevel())
                    return true
                end
            end
        end
        return false
    end
    return true
end

local function refuelFully()
    print("Startup: Refueling fully...")
    for i = 1, 16 do
        turtle.select(i)
        while turtle.refuel(64) do
            -- Consume entire stack if it's fuel
        end
    end
    print("Current Fuel: " .. turtle.getFuelLevel())
end

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

local function getPosition(allowUnknown)
    local x, y, z = gps.locate(2)
    while not x and not allowUnknown do
        print("GPS Signal Lost. Hibernating...")
        sleep(30)
        x, y, z = gps.locate(5)
    end
    if not x and allowUnknown then
        print("No GPS. Returning unknown.")
        return nil, nil, nil
    end
    return x, y, z
end

local function face(dir)
    -- Simplified direction tracking would be better, but we can use gps to determine orientation
    -- Or assume starting orientation. For now, we use a simple turn-based movement.
end

local function safeMove(reporter, parking)
    local retries = 0
    while true do
        if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() == 0 then
            if not tryRefuel() then
                handleError("OUT OF FUEL: No fuel found in inventory.", reporter)
            end
        end

        if turtle.forward() then
            return true
        end

        local success, data = turtle.inspect()
        local isTurtle = success and
            (data.name == "computercraft:turtle_advanced" or data.name == "computercraft:turtle_normal")

        if isTurtle then
            if parking then
                retries = retries + 1
                if retries > 3 then
                    print("Parked (blocked by turtle).")
                    return false -- Stop moving
                end
            end
            print("Traffic jam. Waiting...")
            sleep(math.random(2, 5))
        else
            -- If it's not a turtle, it's probably a block.
            -- We don't dig anymore in navigation for safety.
            print("Blocked. Waiting for path clear...")
            sleep(math.random(2, 5))
        end
    end
end


-- Basic smartMoveTo uses tracks heading
local heading = 0 -- 0:North(-Z), 1:East(+X), 2:South(+Z), 3:West(-X)

local function turnTo(target)
    while heading ~= target do
        turtle.turnRight()
        heading = (heading + 1) % 4
    end
end

local function smartMoveTo(tx, ty, tz, reporter, parking)
    local cx, cy, cz = getPosition()

    if tx ~= cx or tz ~= cz then
        -- Validate heights
        if not travelHeightA or not travelHeightB then
            return "CONFIG_REQUIRED"
        end

        -- Ascend to layer
        local travelY = (tx > cx or (tx == cx and tz > cz)) and travelHeightA or travelHeightB
        while cy < travelY do
            if not turtle.up() then
                print("Blocked up. Waiting...")
                sleep(math.random(2, 5))
            else
                cy = cy + 1
            end
        end
        while cy > travelY do
            if not turtle.down() then
                print("Blocked down. Waiting...")
                sleep(math.random(2, 5))
            else
                cy = cy - 1
            end
        end

        -- Move X
        if tx > cx then
            turnTo(1)
            while cx < tx do
                if not safeMove(reporter, parking) then return "PARKED" end
                cx = cx + 1
            end
        elseif tx < cx then
            turnTo(3)
            while cx > tx do
                if not safeMove(reporter, parking) then return "PARKED" end
                cx = cx - 1
            end
        end

        -- Move Z
        if tz > cz then
            turnTo(2)
            while cz < tz do
                if not safeMove(reporter, parking) then return "PARKED" end
                cz = cz + 1
            end
        elseif tz < cz then
            turnTo(0)
            while cz > tz do
                if not safeMove(reporter, parking) then return "PARKED" end
                cz = cz - 1
            end
        end
    end

    -- Descend to target Y
    while cy > ty do
        if not turtle.down() then
            print("Blocked down. Waiting...")
            sleep(math.random(2, 5))
        else
            cy = cy - 1
        end
    end
    while cy < ty do
        if not turtle.up() then
            print("Blocked up. Waiting...")
            sleep(math.random(2, 5))
        else
            cy = cy + 1
        end
    end
end

return {
    moveTo = smartMoveTo,
    getPosition = getPosition,
    setHeading = function(h) heading = h end,
    setConfig = setConfig,
    tryRefuel = tryRefuel,
    refuelFully = refuelFully,
    handleError = handleError
}
