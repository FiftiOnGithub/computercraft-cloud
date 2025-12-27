-- Anthill Turtle Worker Script
-- This file is managed by the central host and updated dynamically.
local sleep = sleep or os.sleep

local nav = require("navigation")
local mining = require("mining")

-- CONFIG
local PROTOCOL = "anthill"
local MODEM_SIDE = "left" -- Standard
local hostID = tonumber(...)

-- STATE
local surfaceY = 60
local BEACON_CHANNEL = 9999 -- For surface detection via host beacon

local function ascendToSurfaceViaBeacon()
    print("No GPS - using beacon to find surface...")

    local modem = peripheral.find("modem")
    if not modem then
        print("ERROR: No modem found")
        return false
    end

    modem.open(BEACON_CHANNEL)

    local function getHostDistance()
        -- Send beacon request via rednet
        rednet.send(hostID, { type = "BEACON" }, PROTOCOL)

        -- Wait for modem response with timeout
        local timer = os.startTimer(2)
        while true do
            local event, side, channel, replyChannel, message, distance = os.pullEvent()

            if event == "modem_message" then
                -- Filter out rednet's own channels
                if channel ~= 65535 and channel ~= 65533 then
                    if channel == BEACON_CHANNEL and message == "HOST_BEACON" then
                        os.cancelTimer(timer)
                        return distance
                    end
                end
            elseif event == "timer" and side == timer then
                return nil
            end
        end
    end

    local lastDistance = getHostDistance()
    if not lastDistance then
        print("Cannot reach host beacon")
        modem.close(BEACON_CHANNEL)
        return false
    end

    print("Initial distance to host: " .. lastDistance)
    local increasingCount = 0

    while true do
        -- Try to move up
        if not turtle.up() then
            -- Blocked - cannot proceed
            print("Blocked during ascent - hibernating")
            modem.close(BEACON_CHANNEL)
            return false
        end

        -- Check new distance
        local distance = getHostDistance()

        if not distance then
            print("Lost host beacon during ascent")
            modem.close(BEACON_CHANNEL)
            return false
        end

        print("Distance: " .. distance .. " (was " .. lastDistance .. ")")

        if distance > lastDistance then
            -- Distance increasing - we've passed surface
            increasingCount = increasingCount + 1
            if increasingCount >= 2 then
                print("Surface detected (distance increasing)")
                modem.close(BEACON_CHANNEL)
                return true
            end
        else
            increasingCount = 0
        end

        lastDistance = distance
    end
end

local VALUABLES = {
    ["minecraft:diamond"] = true,
    ["minecraft:emerald"] = true,
    ["minecraft:raw_iron"] = true,
    ["minecraft:iron_ingot"] = true,
    ["minecraft:raw_gold"] = true,
    ["minecraft:gold_ingot"] = true,
    ["minecraft:raw_copper"] = true,
    ["minecraft:copper_ingot"] = true,
    ["minecraft:redstone"] = true,
    ["minecraft:lapis_lazuli"] = true,
    ["minecraft:coal"] = true,
    ["minecraft:coal_block"] = true,
    ["minecraft:charcoal"] = true,
    ["minecraft:lava_bucket"] = true,
    ["minecraft:bucket"] = true,
}

local function getFuelPct()
    return math.floor((turtle.getFuelLevel() / turtle.getFuelLimit()) * 100)
end

local function dumpJunk()
    print("Dumping junk...")
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and not VALUABLES[item.name] then
            turtle.select(i)
            turtle.dropDown() -- Drop down the shaft
        end
    end
    turtle.select(1)
end

local function handleLogistics(msg, reason)
    local fuelPct = getFuelPct()
    local emptySlots = 0
    for i = 1, 16 do if turtle.getItemCount(i) == 0 then emptySlots = emptySlots + 1 end end

    if fuelPct < 20 then
        print("Low Fuel (" .. fuelPct .. "%). Heading to Refuel...")
        nav.moveTo(msg.fuelPickupPos.x, msg.fuelPickupPos.y + 1, msg.fuelPickupPos.z, reportError)
        while getFuelPct() < 50 do
            local droppables = {}
            for i = 1, 16 do
                if turtle.getItemCount(i) == 0 then
                    turtle.select(i)
                    if turtle.suckDown(64) then
                        turtle.refuel(64)
                        local d = turtle.getItemDetail()
                        if d and d.name == "minecraft:bucket" then
                            table.insert(droppables, i)
                        end
                        if getFuelPct() >= 50 then
                            break
                        end
                    end
                end
            end
            for i = 1, #droppables do
                turtle.select(droppables[i])
                turtle.dropDown()
            end
            turtle.select(1)
            if turtle.getFuelLevel() >= 50 then
                break
            end
            sleep(10)
        end
        print("Refueled. Returning to task.")
    end

    if emptySlots < 4 or reason == "full" then
        print("Inventory Full (" .. emptySlots .. " slots left). Heading to Dropoff...")
        nav.moveTo(msg.dropoffPos.x, msg.dropoffPos.y + 1, msg.dropoffPos.z, reportError)
        for i = 1, 16 do
            local item = turtle.getItemDetail(i)
            if item then
                turtle.select(i)
                turtle.dropDown()
            end
        end
        turtle.select(1)
        print("Inventory cleared.")
    end
end

local function sendUpdate(msgType, extraData)
    local x, y, z = nav.getPosition(true)
    local payload = {
        type = msgType,
        fuel = getFuelPct(),
        program = shell.getRunningProgram()
    }
    if x then
        payload.pos = { x, y, z }
    end

    -- Inventory Scan
    local counts = {}
    local empty = 0
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item then
            counts[item.name] = (counts[item.name] or 0) + item.count
        else
            empty = empty + 1
        end
    end
    payload.inventory = { counts = counts, empty = empty }

    -- Merge extra data
    if extraData then
        for k, v in pairs(extraData) do
            payload[k] = v
        end
    end

    rednet.send(hostID, payload, PROTOCOL)
end

local function reportError(msg)
    print("CRITICAL ERROR: " .. msg)
    while true do
        sendUpdate("UPDATE", { status = "ERROR", error = msg })
        sleep(10)
    end
end

-- Calibration: Determine starting heading
local function calibrate()
    print("Calibrating GPS and Heading...")

    if not nav.tryRefuel() and turtle.getFuelLevel() == 0 then
        reportError("Fuel required for calibration.")
    end

    local x1, y1, z1 = nav.getPosition()
    local moved = false

    while not moved do
        for i = 1, 4 do
            if turtle.forward() then
                moved = true
                break
            else
                if turtle.getFuelLevel() == 0 then
                    nav.tryRefuel()
                    if turtle.forward() then
                        moved = true
                        break
                    end
                end
                turtle.turnRight()
            end
        end

        if not moved then
            print("Horizontal movement blocked. Ascending...")
            if not turtle.up() then
                reportError("Turtle is stuck during calibration (no horizontal or vertical exit).")
            else
                y1 = y1 + 1
            end
        end
    end

    local x2, y2, z2 = nav.getPosition()
    if x2 > x1 then
        nav.setHeading(1)
    elseif x2 < x1 then
        nav.setHeading(3)
    elseif z2 > z1 then
        nav.setHeading(2)
    elseif z2 < z1 then
        nav.setHeading(0)
    end
    print("Heading calibrated.")
    -- Move back to original position - critical for shaft navigation where
    -- the exit is at the exact X,Z coordinate we started at
    turtle.back()
end

-- Main Flow
-- Try to get GPS first
local x, y, z = gps.locate(5)

if not x then
    -- No GPS at startup - might be in shaft
    print("No GPS at startup - attempting beacon-based surface detection")
    local reachedSurface = ascendToSurfaceViaBeacon()

    if reachedSurface then
        -- Try GPS again
        x, y, z = gps.locate(5)
        if x then
            print("GPS acquired at surface - proceeding with calibration")
            calibrate()
        else
            -- At surface but GPS service down - hibernate
            print("At surface but GPS service unavailable")
            while not x do
                print("GPS Signal Lost. Hibernating...")
                sleep(30)
                x, y, z = gps.locate(5)
            end
            calibrate()
        end
    else
        -- Couldn't reach surface - hibernate
        print("Cannot reach surface - hibernating")
        while not x do
            print("GPS Signal Lost. Hibernating...")
            sleep(30)
            x, y, z = gps.locate(5)
        end
        calibrate()
    end
else
    -- GPS available - normal calibration
    calibrate()
end


while true do
    print(string.format("Status: Idle | Fuel: %d (%d%%)", turtle.getFuelLevel(), getFuelPct()))
    -- Request Work (Initial handshake remains explicit as per request)
    rednet.send(hostID, {
        type = "HANDSHAKE",
        fuel = getFuelPct(),
        pos = { nav.getPosition() }
    }, PROTOCOL)

    local id, msg = rednet.receive(PROTOCOL, 30)
    if id == hostID and msg then
        if msg.type == "RECALL" then
            print("RECALL RECEIVED. Returning to base row...")
            nav.setConfig({
                travelHeightA = msg.travelHeightA,
                travelHeightB = msg.travelHeightB
            })
            -- Stay at recallTravelHeight for entire trip to base
            nav.moveTo(msg.sc.x, msg.recallTravelHeight, msg.sc.z, reportError)
            print("Staging complete. Parking at base corner...")
            nav.moveTo(msg.bc.x, msg.recallTravelHeight, msg.bc.z, reportError, true) -- true = park mode
            print("Parked at base at travel height.")
            -- Hibernate and wait for new assignment
            while true do
                print("Parked. Waiting for new assignment...")
                sleep(30)
                -- Request new assignment
                rednet.send(hostID, {
                    type = "HANDSHAKE",
                    fuel = getFuelPct(),
                    pos = { nav.getPosition() }
                }, PROTOCOL)
                local id, newMsg = rednet.receive(PROTOCOL, 5)
                if id == hostID and newMsg and newMsg.type ~= "RECALL" then
                    -- Got a new assignment, exit hibernation
                    break
                end
            end
        elseif msg.type == "DROPOFF" then
            print("JOB: One-time Dropoff")
            sendUpdate("CONFIRM", { status = "NAV" })

            nav.moveTo(msg.dropoffPos.x, msg.dropoffPos.y + 1, msg.dropoffPos.z, reportError)
            print("Dumping inventory...")
            for i = 1, 16 do
                local item = turtle.getItemDetail(i)
                if item then
                    turtle.select(i)
                    turtle.dropDown()
                end
            end
            turtle.select(1)

            sendUpdate("COMPLETE")
        elseif msg.type == "ASSIGNMENT" then
            print(string.format("JOB: Shaft at %d, %d | Depth: %d", msg.x, msg.z, msg.depth))
            sendUpdate("CONFIRM", { status = "NAV" })

            surfaceY = msg.surfaceY or surfaceY
            nav.setConfig({
                travelHeightA = msg.travelHeightA,
                travelHeightB = msg.travelHeightB
            })

            -- STARTUP CHECK: Handle logistics before moving to site
            handleLogistics(msg)

            local tx, tz = msg.x, msg.z
            local res = nav.moveTo(tx, surfaceY, tz, reportError)
            if res == "CONFIG_REQUIRED" then
                print("Cannot move: Travel heights missing. Waiting for update...")
                return -- Exit handleMessage, will handshake again
            end
            sendUpdate("UPDATE", { status = "DIG", pos = { tx, surfaceY, tz } })
            print("Now at surfaceY")
            local result, depth = mining.digShaft(msg.depth, function(currentY)
                if currentY % 10 == 0 then
                    sendUpdate("UPDATE", { status = "DIG", pos = { tx, currentY, tz } })
                end
            end, reportError)

            if result == "DONE" or result == "FULL" then
                if result == "FULL" then print("Mining stopped: inventory full.") end

                -- Junk disposal at bottom
                dumpJunk()

                -- Logistics check (Dropoff/Fuel)
                handleLogistics(msg, result == "FULL" and "full" or nil)

                print("Shaft complete. Ascending " .. (depth or 0) .. " blocks...")
                -- Blind ascent because GPS might fail at depth
                for i = 1, (depth or 0) do
                    if not turtle.up() then
                        -- Something is blocking us - this shouldn't happen during ascent
                        local success, data = turtle.inspectUp()
                        local blockName = success and data.name or "unknown"
                        reportError("BLOCKED DURING ASCENT: Stuck below " ..
                            blockName .. " at block " .. i .. " of " .. (depth or 0))
                        return -- Freeze and wait for intervention
                    end
                end
                -- Move to surface before reporting complete to ensure GPS reaches
                sendUpdate("COMPLETE", { shaft = { tx, tz } })
            end
        end
    else
        print("No assignment received. Retrying...")
    end
    sleep(1)
end
