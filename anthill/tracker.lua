-- ANTHILL TRACKER DASHBOARD
-- Standalone program to track and view turtle position history.

local TRACKER_PROTOCOL = "tracker"
local DATA_FILE = "tracker_data.json"
local MODEM_SIDE = "left" -- Default, adjust as needed
local gps = require("bettergps")
-- State
local turtles = {}       -- [id] = { lastSeen = text, history = { {pos, time}, ... } }
local selectedID = nil
local activeTab = "LIST" -- "LIST" or "DETAILS"
local width, height = term.getSize()
local myPos = nil        -- Cached position of the tracker itself

-- Colors (Premium Aesthetic)
local COLORS = {
    BG = colors.white,
    HEADER = colors.yellow,
    HEADER_TEXT = colors.black,
    TEXT = colors.black,
    HIGHLIGHT = colors.black,
    ID = colors.cyan,
    POS = colors.green,
    TIME = colors.gray
}

-- Helpers
local function saveData()
    local f = fs.open(DATA_FILE, "w")
    f.write(textutils.serializeJSON(turtles))
    f.close()
end

local function loadData()
    if fs.exists(DATA_FILE) then
        local f = fs.open(DATA_FILE, "r")
        local ok, data = pcall(textutils.unserializeJSON, f.readAll())
        f.close()
        if ok and type(data) == "table" then turtles = data end
    end
end

local function getTime()
    local t = os.time()
    local h = math.floor(t)
    local m = math.floor((t - h) * 60)
    return string.format("%02d:%02d", h, m)
end

-- UI components
local function drawHeader()
    term.setBackgroundColor(COLORS.HEADER)
    term.setTextColor(COLORS.HEADER_TEXT)
    term.setCursorPos(1, 1)
    term.clearLine()

    if activeTab == "DETAILS" then
        term.setCursorPos(2, 1)
        term.setTextColor(COLORS.HEADER_TEXT)
        term.write("< BACK")
    end



    term.setTextColor(COLORS.HEADER_TEXT)
    local title = "TRACKER - " .. os.date("%H:%M:%S")
    term.setCursorPos(width - #title, 1)
    term.write(title)
end

local function drawList()
    term.setBackgroundColor(COLORS.BG)
    term.setTextColor(COLORS.TEXT)
    term.setCursorPos(1, 3)
    -- Wider columns: ID(3), Prog(10), Pos(18), Dist(8), Seen(10) -- Tightened: Pos(16), Dist(6)
    term.write(string.format(" %-3s %-10s %-16s %-6s %-10s", "ID", "Prog", "Last Position", "Dist", "Last Seen"))
    term.setCursorPos(1, 4)
    term.write(string.rep("-", width))

    local sortedIds = {}
    for id in pairs(turtles) do table.insert(sortedIds, id) end
    table.sort(sortedIds, function(a, b) return tonumber(a) < tonumber(b) end)

    table.sort(sortedIds, function(a, b) return tonumber(a) < tonumber(b) end)

    local hx, hy, hz = nil, nil, nil
    if myPos then hx, hy, hz = myPos[1], myPos[2], myPos[3] end

    for i, id in ipairs(sortedIds) do
        if i > height - 6 then break end
        local data = turtles[id]
        local last = data.history[1] or { pos = { 0, 0, 0 }, timestamp = os.epoch("local") / 1000 }

        -- Position
        local posStr = "NO GPS"
        local posColor = colors.red -- Default for NO GPS

        if last.pos then
            posStr = string.format("%d,%d,%d", last.pos[1], last.pos[2], last.pos[3])
            posColor = COLORS.POS
        elseif data.lastKnownPos then
            -- Cached location
            -- User asked for: "? (<coords>)" in red
            posStr = string.format("? (%d,%d,%d)", data.lastKnownPos[1], data.lastKnownPos[2], data.lastKnownPos[3])
            posColor = colors.red
        else
            posColor = colors.red
        end

        -- Distance
        local distStr = "?"
        -- Use last.pos or data.lastKnownPos
        local trackingPos = last.pos or data.lastKnownPos
        if hx and trackingPos then
            local dist = math.sqrt((trackingPos[1] - hx) ^ 2 + (trackingPos[2] - hy) ^ 2 + (trackingPos[3] - hz) ^ 2)
            distStr = string.format("%dm", math.floor(dist))
        end

        -- Program (Remove extension)
        local prog = last.program or "?"
        prog = prog:match("([^/]+)$") or prog -- Get filename
        prog = prog:gsub("%.lua$", "")        -- Remove .lua extension

        -- Compute relative time
        local now = os.epoch("local") / 1000
        local delta = now - (last.timestamp or now)
        local relStr, col
        if delta < 60 then
            relStr = string.format("%ds ago", delta)
            col = COLORS.TIME
        elseif delta < 3600 then
            relStr = string.format("%dm ago", math.floor(delta / 60))
            col = colors.orange
        else
            relStr = string.format("%dh ago", math.floor(delta / 3600))
            col = colors.red
        end

        term.setCursorPos(1, 5 + i)
        if selectedID == id then term.setBackgroundColor(colors.gray) end

        term.setTextColor(COLORS.ID)
        term.write(string.format(" %-3s ", id))
        term.setTextColor(COLORS.TEXT)
        term.write(string.format(" %-10s ", prog:sub(1, 10)))
        term.setTextColor(posColor)
        term.write(string.format("%-16s ", posStr))
        term.setTextColor(COLORS.TEXT)
        term.write(string.format("%-6s ", distStr))
        term.setTextColor(col)
        term.write(string.format("%-10s", relStr))

        term.setBackgroundColor(COLORS.BG)
    end
end

local function drawDetails()
    if not selectedID or not turtles[selectedID] then
        term.setBackgroundColor(COLORS.BG)
        term.setCursorPos(2, 4)
        term.setTextColor(colors.red)
        term.write("Select a turtle in LIST view first.")
        return
    end

    term.setBackgroundColor(COLORS.BG)
    term.setCursorPos(1, 3)
    term.setTextColor(COLORS.HIGHLIGHT)
    term.write(" HISTORY FOR TURTLE #" .. selectedID)
    term.setCursorPos(1, 4)
    term.setTextColor(COLORS.TEXT)
    term.write(string.rep("-", width))

    local history = turtles[selectedID].history
    local maxLines = height - 6
    local count = math.min(#history, maxLines)

    -- Print from oldest (visible) to newest
    -- history[1] is newest. history[count] is oldest visible.
    -- We want to print oldest at top? No, user said "newest at the bottom".
    -- So we just print in reverse order of the list?
    -- No, "lines output from oldest to newest".
    -- So index count (Oldest) -> index 1 (Newest).
    -- And we want Newest at the bottom of the screen?
    -- Yes.

    for i = 1, count do
        local entryIndex = count - i + 1 -- Start from count, go down to 1
        local entry = history[entryIndex]

        term.setCursorPos(2, 4 + i)
        term.setBackgroundColor(COLORS.BG)

        local posStr = "NO GPS"
        if entry.pos then
            posStr = string.format("%d, %d, %d", entry.pos[1], entry.pos[2], entry.pos[3])
        elseif turtles[selectedID].lastKnownPos then
            posStr = string.format("NO GPS (%d, %d, %d)",
                turtles[selectedID].lastKnownPos[1],
                turtles[selectedID].lastKnownPos[2],
                turtles[selectedID].lastKnownPos[3])
        end
        local timeStr = os.date("%H:%M:%S", entry.timestamp)
        term.setCursorPos(2, 5 + i)
        local termRGB = term.getTextColor()
        term.setTextColor(COLORS.TIME)
        term.write("[" .. timeStr .. "] ")

        if entry.pos then
            -- Check if same as previous (older) entry
            -- entryIndex is current (newer), entryIndex + 1 is older
            local prevEntry = history[entryIndex + 1]
            if prevEntry and prevEntry.pos and
                prevEntry.pos[1] == entry.pos[1] and
                prevEntry.pos[2] == entry.pos[2] and
                prevEntry.pos[3] == entry.pos[3] then
                term.setTextColor(COLORS.TIME) -- Gray if unchanged
            else
                term.setTextColor(COLORS.POS)
            end
        else
            term.setTextColor(colors.red)
        end
        term.write(posStr)
        if entry.fuel then
            term.setTextColor(COLORS.TIME)
            term.write(" (" .. entry.fuel .. "%)")
        end
        if entry.program then
            term.setTextColor(COLORS.TIME)
            term.write(" (" .. entry.program .. ")")
        end
    end
end

-- Main loops
local function listener()
    while true do
        local id, msg = rednet.receive(TRACKER_PROTOCOL)
        if id and type(msg) == "table" and msg.type == "POSITION" then
            local turtleId = tostring(msg.id or id)
            if not turtles[turtleId] then turtles[turtleId] = { history = {} } end
            local lastUpdate = turtles[turtleId].lastUpdate or 0
            local now = os.epoch("local") / 1000

            if now - lastUpdate >= 5 then
                turtles[turtleId].lastUpdate = now

                -- Update cache if we have a position
                if msg.pos then
                    -- CLONE to prevent shared references causing JSON serialization errors
                    turtles[turtleId].lastKnownPos = { msg.pos[1], msg.pos[2], msg.pos[3] }
                end

                table.insert(turtles[turtleId].history, 1, {
                    pos = msg.pos, -- Can be nil now
                    timestamp = now,
                    fuel = msg.fuel,
                    program = msg.program
                })

                -- Cap at 100
                while #turtles[turtleId].history > 100 do
                    table.remove(turtles[turtleId].history)
                end

                saveData()
                os.queueEvent("tracker_update")
            end
        end
    end
end

local function uiTask()
    local needsRedraw = true
    local refreshTimer = os.startTimer(1)
    while true do
        if needsRedraw then
            term.setBackgroundColor(COLORS.BG)
            term.clear()
            drawHeader()
            if activeTab == "LIST" then
                drawList()
            else
                drawDetails()
            end
            needsRedraw = false
        end

        local event, p1, p2, p3 = os.pullEvent()
        if event == "tracker_update" then
            needsRedraw = true
        elseif event == "timer" and p1 == refreshTimer then
            needsRedraw = true
            refreshTimer = os.startTimer(1)
        elseif event == "mouse_click" then
            if p3 == 1 and activeTab == "DETAILS" and p2 <= 8 then
                -- Back button clicked
                activeTab = "LIST"
                selectedID = nil
                needsRedraw = true
            elseif activeTab == "LIST" and p3 >= 6 then
                local idx = p3 - 5
                local sortedIds = {}
                for id in pairs(turtles) do table.insert(sortedIds, id) end
                table.sort(sortedIds, function(a, b) return tonumber(a) < tonumber(b) end)
                if sortedIds[idx] then
                    selectedID = sortedIds[idx]
                    activeTab = "DETAILS"
                    needsRedraw = true
                end
            end
        elseif event == "key" then
            if (p1 == keys.backspace or p1 == keys.left) and activeTab == "DETAILS" then
                activeTab = "LIST"; selectedID = nil; needsRedraw = true
            elseif p1 == keys.q then
                return
            end
        end
    end
end

local function gpsLoop()
    while true do
        local x, y, z = gps.locate(2)
        if x then
            myPos = { x, y, z }
            os.queueEvent("tracker_update")
        end
        os.sleep(3) -- Update own position occasionally
    end
end

-- Start
loadData()
if not rednet.isOpen(MODEM_SIDE) then
    print("Opening modem on " .. MODEM_SIDE .. "...")
    rednet.open(MODEM_SIDE)
end

if not rednet.isOpen(MODEM_SIDE) then
    print("Opening modem on " .. MODEM_SIDE .. "...")
    rednet.open(MODEM_SIDE)
end

parallel.waitForAny(listener, uiTask, gpsLoop)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
print("Tracker closed.")
