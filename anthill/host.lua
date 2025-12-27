-- Anthill Host Manager

local sleep = sleep or os.sleep
-- Manages turtle assignments and tracks progress

local coordGen = require("coordinate_gen")
local gui = require("gui")

local config = require("config")

-- CONFIGURATION
local PROTOCOL = config.PROTOCOL
local HOSTNAME = config.HOSTNAME
local MODEM_SIDE = config.MODEM_SIDE
local QUARRY_DIMENSIONS = config.QUARRY_DIMENSIONS
local DEFAULT_ASSIGNMENT = config.DEFAULT_ASSIGNMENT or "IDLE"

-- STATE
local STATE_FILE = "anthill_state.dat"
local availableShafts = {}
local activeAssignments = {} -- turtleID -> { task="...", data={...}, callback={...} } ("turtlesAssignments" in plan, but keeping activeAssignments name is fine, just structure changes)
-- actually, let's rename it to turtleAssignments to be clear and match the plan
local turtleAssignments = {} -- turtleID -> { task="...", data={...}, callback={...} }
local turtleStatus = {}      -- turtleID -> latestUpdate
local completedShafts = {}   -- "x,z" -> true
local turtleHomeBases = {}   -- turtleID -> {x, z}
local turtleLogs = {}        -- turtleID -> { {time, msg}, ... }
-- Removed recallAll and recalledTurtles
local baseCorner = nil       -- {x, z}
local stagingCorner = nil    -- {x, z}

-- Persistence Helpers
local function saveState()
    local file = fs.open(STATE_FILE, "w")
    if file then
        file.write(textutils.serialize({
            assignments = turtleAssignments,
            completed = completedShafts,
            homeBases = turtleHomeBases
        }))
        file.close()
    end
end

local function loadState()
    if fs.exists(STATE_FILE) then
        local file = fs.open(STATE_FILE, "r")
        if file then
            local data = textutils.unserialize(file.readAll())
            file.close()
            if data then
                turtleAssignments = data.assignments or {}
                completedShafts = data.completed or {}
                turtleHomeBases = data.homeBases or {}
            end
        end
    end
end

-- Initialization
rednet.open(MODEM_SIDE)
os.queueEvent("log", "[INIT] Opening rednet on " .. MODEM_SIDE)
loadState()
os.queueEvent("log", "[INIT] State loaded")

-- Calculate Recall Corners (BC and SC)
os.queueEvent("log", "[INIT] Locating host via GPS...")
local hX, hY, hZ = gps.locate(5)
if hX then
    os.queueEvent("log", string.format("[INIT] GPS located at %d, %d, %d", hX, hY, hZ))
    local q = QUARRY_DIMENSIONS
    local minX, maxX = math.min(q.minX, q.maxX), math.max(q.minX, q.maxX)
    local minZ, maxZ = math.min(q.minZ, q.maxZ), math.max(q.minZ, q.maxZ)
    local corners = {
        { x = minX, z = minZ }, { x = minX, z = maxZ },
        { x = maxX, z = minZ }, { x = maxX, z = maxZ }
    }

    local bestDist = 1e10
    local bcIdx = 1
    for i, c in ipairs(corners) do
        local d = (hX - c.x) ^ 2 + (hZ - c.z) ^ 2
        if d < bestDist then
            bestDist = d
            bcIdx = i
        end
    end
    baseCorner = corners[bcIdx]

    -- Pick an adjacent corner to be the staging corner (SC)
    -- We'll just shift Z if possible, or X if at the edge.
    if bcIdx == 1 then
        stagingCorner = corners[2] -- (minX, minZ) -> (minX, maxZ)
    elseif bcIdx == 2 then
        stagingCorner = corners[1] -- (minX, maxZ) -> (minX, minZ)
    elseif bcIdx == 3 then
        stagingCorner = corners[4] -- (maxX, minZ) -> (maxX, maxZ)
    elseif bcIdx == 4 then
        stagingCorner = corners[3] -- (maxX, maxZ) -> (maxX, minZ)
    end

    -- Calculate height for SC -> BC trip
    local q = QUARRY_DIMENSIONS
    local hA, hB = q.travelHeightA, q.travelHeightB
    recallTravelHeight = (baseCorner.x > stagingCorner.x or (baseCorner.x == stagingCorner.x and baseCorner.z > stagingCorner.z)) and
        hA or hB

    os.queueEvent("log", string.format("[INIT] BC: %d,%d | SC: %d,%d | Height: %d",
        baseCorner.x, baseCorner.z, stagingCorner.x, stagingCorner.z, recallTravelHeight))
else
    print("WARNING: Host could not locate itself via GPS. Recall features may not work reliably.")
    os.queueEvent("log", "[INIT] WARNING: GPS location failed")
end

print("Anthill Host Started: " .. HOSTNAME)
local allShafts = coordGen.generate(
    QUARRY_DIMENSIONS.minX, QUARRY_DIMENSIONS.maxX,
    QUARRY_DIMENSIONS.minZ, QUARRY_DIMENSIONS.maxZ
)

-- Filter out shafts that are already active or completed
for _, shaft in ipairs(allShafts) do
    local key = shaft.x .. "," .. shaft.z
    local isActive = false
    local isActive = false
    -- Check if shaft is in any mining assignment
    for id, assign in pairs(turtleAssignments) do
        if assign.task == "MINING" and assign.data and assign.data.x == shaft.x and assign.data.z == shaft.z then
            isActive = true
            break
        end
    end

    if not completedShafts[key] and not isActive then
        table.insert(availableShafts, shaft)
    end
end
print("Resuming operation. " .. #availableShafts .. " shafts remaining.")
os.queueEvent("log", string.format("[INIT] %d shafts available, %d completed", #availableShafts, #completedShafts))

local function updateTurtle(id, data)
    turtleStatus[id] = turtleStatus[id] or {}
    for k, v in pairs(data) do
        turtleStatus[id][k] = v
    end
    turtleStatus[id].lastSeen = os.clock()

    -- Log update
    turtleLogs[id] = turtleLogs[id] or {}
    local timestamp = os.date("%H:%M:%S")
    local posStr = data.pos and (data.pos[1] .. "," .. data.pos[2] .. "," .. data.pos[3]) or ""
    local logMsg = (data.status or "Update") .. " " .. posStr
    if data.error then logMsg = "ERR: " .. data.error .. " " .. posStr end

    table.insert(turtleLogs[id], 1, { time = timestamp, msg = logMsg, raw = data })
    if #turtleLogs[id] > 50 then table.remove(turtleLogs[id]) end
end

local function setAssignment(id, task, data, callback)
    turtleAssignments[id] = {
        task = task,
        data = data,
        callback = callback
    }
    local dataStr = ""
    if data and data.x and data.z then
        dataStr = string.format(" [%d,%d]", data.x, data.z)
    end
    os.queueEvent("log", string.format("[ASSIGN] Turtle %d -> %s%s", id, task, dataStr))
    saveState()
    os.queueEvent("anthill_update")
end

local function handleMessage(id, msg)
    if type(msg) ~= "table" then return end

    if msg.type == "DISCOVER" then
        os.queueEvent("log", string.format("[MSG] DISCOVER from turtle %d", id))
        rednet.send(id, {
            type = "ADVERTISE",
            requiredFiles = config.REQUIRED_FILES
        }, PROTOCOL)
        if not turtleAssignments[id] then
            setAssignment(id, DEFAULT_ASSIGNMENT)
        end
        updateTurtle(id, { status = "IDLE", lastSeen = os.clock() })
    elseif msg.type == "BEACON" then
        os.queueEvent("log", string.format("[MSG] BEACON from turtle %d", id))
        -- Respond via modem for surface detection
        local modem = peripheral.wrap(config.MODEM_SIDE)
        if modem then
            modem.transmit(9999, 9999, "HOST_BEACON")
            os.queueEvent("log", string.format("[BEACON] Sent HOST_BEACON response to turtle %d", id))
        else
            os.queueEvent("log", string.format("[BEACON] ERROR: Could not wrap modem on %s", config.MODEM_SIDE))
        end
        updateTurtle(id, { status = "BEACON", lastSeen = os.clock() })
    elseif msg.type == "HANDSHAKE" then
        local posStr = msg.pos and string.format("%d,%d,%d", msg.pos[1], msg.pos[2], msg.pos[3]) or "unknown"
        os.queueEvent("log",
            string.format("[MSG] HANDSHAKE from turtle %d at %s, fuel: %s", id, posStr, tostring(msg.fuel)))
        if msg then
            updateTurtle(id, {
                fuel = msg.fuel,
                pos = msg.pos,
                inventory = msg.inventory,
                program = msg.program,
                lastSeen = os.clock()
            })
        end

        local assign = turtleAssignments[id] or { task = DEFAULT_ASSIGNMENT }
        -- Ensure assignment is set if missing (e.g. restart)
        if not turtleAssignments[id] then setAssignment(id, assign.task, assign.data) end

        if assign.task == "IDLE" then
            -- Smart Recall: Check if on parking row
            local onParkingRow = false
            if baseCorner and stagingCorner and msg.pos then
                local tx, tz = msg.pos[1], msg.pos[3]
                os.queueEvent("log", string.format("[PARKING] Turtle %d pos: %d,%d | BC: %d,%d | SC: %d,%d",
                    id, tx, tz, baseCorner.x, baseCorner.z, stagingCorner.x, stagingCorner.z))

                -- BC and SC are adjacent corners forming a line
                -- Check if turtle is on that line (either X or Z matches both corners)
                if (baseCorner.x == stagingCorner.x and tx == baseCorner.x) then
                    -- North-south line (Z-aligned: same X, different Z)
                    local minZ, maxZ = math.min(baseCorner.z, stagingCorner.z), math.max(baseCorner.z, stagingCorner.z)
                    os.queueEvent("log",
                        string.format("[PARKING] Turtle %d N-S check: X match (%d==%d), Z range [%d,%d], tz=%d",
                            id, tx, baseCorner.x, minZ, maxZ, tz))
                    if tz >= minZ and tz <= maxZ then
                        onParkingRow = true
                        os.queueEvent("log", string.format("[PARKING] Turtle %d IS on N-S parking row", id))
                    else
                        os.queueEvent("log", string.format("[PARKING] Turtle %d NOT in Z range", id))
                    end
                elseif (baseCorner.z == stagingCorner.z and tz == baseCorner.z) then
                    -- East-west line (X-aligned: same Z, different X)
                    local minX, maxX = math.min(baseCorner.x, stagingCorner.x), math.max(baseCorner.x, stagingCorner.x)
                    os.queueEvent("log",
                        string.format("[PARKING] Turtle %d E-W check: Z match (%d==%d), X range [%d,%d], tx=%d",
                            id, tz, baseCorner.z, minX, maxX, tx))
                    if tx >= minX and tx <= maxX then
                        onParkingRow = true
                        os.queueEvent("log", string.format("[PARKING] Turtle %d IS on E-W parking row", id))
                    else
                        os.queueEvent("log", string.format("[PARKING] Turtle %d NOT in X range", id))
                    end
                else
                    os.queueEvent("log",
                        string.format(
                            "[PARKING] Turtle %d no axis match - BC.x=%d SC.x=%d tx=%d | BC.z=%d SC.z=%d tz=%d",
                            id, baseCorner.x, stagingCorner.x, tx, baseCorner.z, stagingCorner.z, tz))
                end
            else
                os.queueEvent("log", string.format("[PARKING] Turtle %d missing data - BC:%s SC:%s pos:%s",
                    id, tostring(baseCorner ~= nil), tostring(stagingCorner ~= nil), tostring(msg.pos ~= nil)))
            end
            if not onParkingRow and baseCorner and stagingCorner and recallTravelHeight then
                os.queueEvent("log", string.format("[RECALL] Sending RECALL to turtle %d", id))
                rednet.send(id, {
                    type = "RECALL",
                    bc = baseCorner,
                    sc = stagingCorner,
                    surfaceY = QUARRY_DIMENSIONS.surfaceY,
                    travelHeightA = QUARRY_DIMENSIONS.travelHeightA,
                    travelHeightB = QUARRY_DIMENSIONS.travelHeightB,
                    recallTravelHeight = recallTravelHeight
                }, PROTOCOL)
                updateTurtle(id, { status = "RECALLING" })
            else
                os.queueEvent("log", string.format("[RECALL] Turtle %d already parked", id))
                updateTurtle(id, { status = "PARKED" })
            end
        elseif assign.task == "MINING" then
            local shaft = assign.data

            if not shaft and #availableShafts > 0 then
                local home = turtleHomeBases[id]
                -- Check if we should reset home cluster
                if home then
                    local nearestDist = 1000000
                    for _, candidate in ipairs(availableShafts) do
                        local dist = math.sqrt((candidate.x - home.x) ^ 2 + (candidate.z - home.z) ^ 2)
                        if dist < nearestDist then nearestDist = dist end
                    end
                    if nearestDist > 10 then
                        turtleHomeBases[id] = nil
                        home = nil
                    end
                end

                if not home then
                    -- INITIAL ASSIGNMENT: Maximin
                    local bestShaftIndex = 1
                    local maxMinDist = -1
                    for i, candidate in ipairs(availableShafts) do
                        local minDistToOtherBase = 1000000
                        local hasOtherBases = false
                        for otherId, otherHome in pairs(turtleHomeBases) do
                            if otherId ~= id then
                                hasOtherBases = true
                                local dist = math.sqrt((candidate.x - otherHome.x) ^ 2 + (candidate.z - otherHome.z) ^ 2)
                                if dist < minDistToOtherBase then minDistToOtherBase = dist end
                            end
                        end
                        if not hasOtherBases or minDistToOtherBase > maxMinDist then
                            maxMinDist = minDistToOtherBase
                            bestShaftIndex = i
                        end
                    end
                    shaft = table.remove(availableShafts, bestShaftIndex)
                    turtleHomeBases[id] = { x = shaft.x, z = shaft.z }
                else
                    -- SUBSEQUENT ASSIGNMENT: Nearest
                    local bestShaftIndex = 1
                    local minDist = 1000000
                    for i, candidate in ipairs(availableShafts) do
                        local dist = math.sqrt((candidate.x - home.x) ^ 2 + (candidate.z - home.z) ^ 2)
                        if dist < minDist then
                            minDist = dist
                            bestShaftIndex = i
                        end
                    end
                    shaft = table.remove(availableShafts, bestShaftIndex)
                end

                -- Update assignment with specific shaft data
                setAssignment(id, "MINING", shaft)
            end

            if shaft then
                os.queueEvent("log", string.format("[MINING] Assigned shaft %d,%d to turtle %d", shaft.x, shaft.z, id))
                rednet.send(id, {
                    type = "ASSIGNMENT",
                    x = shaft.x,
                    z = shaft.z,
                    depth = QUARRY_DIMENSIONS.targetY,
                    surfaceY = QUARRY_DIMENSIONS.surfaceY,
                    travelHeightA = QUARRY_DIMENSIONS.travelHeightA,
                    travelHeightB = QUARRY_DIMENSIONS.travelHeightB,
                    dropoffPos = QUARRY_DIMENSIONS.dropoffPos,
                    fuelPickupPos = QUARRY_DIMENSIONS.fuelPickupPos
                }, PROTOCOL)
                updateTurtle(id, { status = "ASSIGNED" })
            else
                os.queueEvent("log", string.format("[MINING] No work available for turtle %d", id))
                updateTurtle(id, { status = "NO_WORK" })
            end
        elseif assign.task == "DROPOFF" then
            os.queueEvent("log", string.format("[DROPOFF] Sending DROPOFF to turtle %d", id))
            rednet.send(id, {
                type = "DROPOFF",
                dropoffPos = QUARRY_DIMENSIONS.dropoffPos
            }, PROTOCOL)
            updateTurtle(id, { status = "DROPOFF" })
        elseif assign.task == "REFUEL" then
            os.queueEvent("log", string.format("[REFUEL] Sending REFUEL to turtle %d", id))
            rednet.send(id, {
                type = "REFUEL",
                fuelPickupPos = QUARRY_DIMENSIONS.fuelPickupPos
            }, PROTOCOL)
            updateTurtle(id, { status = "REFUELING" })
        end
    elseif msg.type == "CONFIRM" then
        os.queueEvent("log", string.format("[MSG] CONFIRM from turtle %d", id))
        updateTurtle(id, {
            status = "TRAVELING",
            fuel = msg.fuel,
            pos = msg.pos,
            inventory = msg.inventory,
            program = msg.program
        })
    elseif msg.type == "UPDATE" then
        local statusStr = msg.status or "OK"
        if msg.error then
            os.queueEvent("log", string.format("[MSG] UPDATE from turtle %d: %s (ERROR: %s)", id, statusStr, msg.error))
        end
        updateTurtle(id, {
            status = msg.status or "OK",
            pos = msg.pos,
            fuel = msg.fuel,
            error = msg.error,
            inventory = msg.inventory,
            program = msg.program
        })
    elseif msg.type == "COMPLETE" then
        -- Task Finished
        local assign = turtleAssignments[id]
        if assign and assign.task == "MINING" and assign.data then
            -- Mark shaft complete
            local shaft = assign.data
            os.queueEvent("log", string.format("[COMPLETE] Turtle %d completed shaft %d,%d", id, shaft.x, shaft.z))
            completedShafts[shaft.x .. "," .. shaft.z] = true
            saveState()
        else
            os.queueEvent("log",
                string.format("[COMPLETE] Turtle %d completed task: %s", id, assign and assign.task or "unknown"))
        end

        local nextTask = assign and assign.callback or nil
        if nextTask then
            -- Restore callback assignment
            setAssignment(id, nextTask.task, nextTask.data, nextTask.callback)
        else
            -- Default behavior for completion
            if assign and assign.task == "MINING" then
                -- Stay mining, just clear the specific shaft so we pick a new one
                setAssignment(id, "MINING", nil)
            else
                setAssignment(id, "IDLE") -- Completed dropoff/refuel/etc and no callback -> Go Idle
            end
        end


        updateTurtle(id, {
            status = "COMPLETED",
            fuel = msg.fuel,
            pos = msg.pos,
            inventory = msg.inventory,
            program = msg.program
        })
        handleMessage(id,
            { type = "HANDSHAKE", fuel = msg.fuel, pos = msg.pos, inventory = msg.inventory, program = msg.program }) -- Re-evaluate
    elseif msg.type == "RETURNING" then
        os.queueEvent("log", string.format("[MSG] RETURNING from turtle %d, reason: %s", id, msg.reason or "unknown"))
        updateTurtle(id, { status = "RETURNING", reason = msg.reason })
    elseif msg.type == "FILE_SYNC" then
        os.queueEvent("log", string.format("[MSG] FILE_SYNC request from turtle %d", id))
        local files = {}
        local programPath = shell.getRunningProgram()
        local programDir = programPath:match("(.*)/") or ""

        for _, path in ipairs(config.REQUIRED_FILES) do
            local fullPath = fs.combine(programDir, path)
            if fs.exists(fullPath) and not fs.isDir(fullPath) then
                local f = fs.open(fullPath, "r")
                files[path] = f.readAll()
                f.close()
            end
        end
        os.queueEvent("log", string.format("[FILE_SYNC] Sending %d files to turtle %d", #files, id))
        rednet.send(id, {
            type = "FILE_SYNC_DATA",
            files = files
        }, PROTOCOL)
    end
end

-- State Pack for GUI
local sharedState = {
    quarry = QUARRY_DIMENSIONS,
    availableShafts = availableShafts,
    turtleAssignments = turtleAssignments,
    turtleStatus = turtleStatus,
    completedShafts = completedShafts,
    turtleLogs = turtleLogs,
    setAssignment = setAssignment,
    setAllAssignments = function(task)
        for id in pairs(turtleStatus) do
            setAssignment(id, task)
        end
    end,
    turtleHomeBases = turtleHomeBases,
    hostPos = (hX and hZ) and { x = hX, z = hZ } or nil
}

local function messageListener()
    while true do
        local id, msg = rednet.receive(PROTOCOL)
        if id then
            handleMessage(id, msg)
        end
    end
end

-- Main Loop
parallel.waitForAny(messageListener, function() gui.run(sharedState) end)
