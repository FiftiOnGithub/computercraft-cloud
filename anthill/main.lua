local PROTOCOL = "anthill"
local TRACKER_PROTOCOL = "tracker"
local MODEM_SIDE = "left" -- Standard
local gps = require("bettergps")
rednet.open(MODEM_SIDE)

-- Background task to broadcast GPS position
local function trackerLoop()
    while true do
        local x, y, z = gps.locate(2)
        -- Send update regardless of GPS success (send nil if failed)
        rednet.broadcast({
            type = "POSITION",
            id = os.getComputerID(),
            pos = x and { x, y, z } or nil,
            fuel = math.floor((turtle.getFuelLevel() / turtle.getFuelLimit()) * 100),
            program = shell.getRunningProgram()
        }, TRACKER_PROTOCOL)
        os.sleep(10)
    end
end

-- Core bootstrapper logic
local function bootAndRun()
    print("Booting Anthill Hive...")

    -- 1. Discover Host
    local hostID = nil
    while not hostID do
        print("Searching for Host...")
        rednet.broadcast({ type = "DISCOVER" }, PROTOCOL)
        local id, msg = rednet.receive(PROTOCOL, 5)
        if id and type(msg) == "table" and msg.type == "ADVERTISE" then
            hostID = id
        end
    end
    print("Connected to Host: " .. hostID)

    -- 2. Sync Files
    print("Syncing all files...")
    local programPath = shell.getRunningProgram()
    local programDir = programPath:match("(.*)/") or ""

    local synced = false
    while not synced do
        rednet.send(hostID, { type = "FILE_SYNC" }, PROTOCOL)
        local id, msg = rednet.receive(PROTOCOL, 5)
        if id == hostID and msg and msg.type == "FILE_SYNC_DATA" then
            for path, content in pairs(msg.files) do
                local fullPath = fs.combine(programDir, path)
                print("Received: " .. path)
                local f = fs.open(fullPath, "w")
                f.write(content)
                f.close()
            end
            synced = true
        else
            print("Retrying sync...")
            os.sleep(2)
        end
    end

    print("Sync complete. Launching worker...")
    shell.run(fs.combine(programDir, "worker.lua"), hostID)
end

-- Main entry point with error handling and parallel tasks
local function main()
    parallel.waitForAny(bootAndRun, trackerLoop)
end

while true do
    local ok, err = pcall(main)
    if not ok then
        print("CRITICAL ERROR: " .. tostring(err))
    else
        print("Program exited. (Unknown reason)")
    end
    print("Re-running in 10 seconds...")
    os.sleep(10)
end
