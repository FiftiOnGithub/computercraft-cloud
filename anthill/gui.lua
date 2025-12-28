local sleep = sleep or os.sleep

local gui = {}

-- State
local activeTab = "STATUS"
local selectedTurtle = nil
local scrollX, scrollY = 0, 0
local mapCanvas = nil
local width, height = term.getSize()

-- Colors
local COLORS = {
    BG = colors.black,
    HEADER = colors.blue,
    TAB_ACTIVE = colors.white,
    TAB_INACTIVE = colors.gray,
    DONE = colors.green,
    DIGGING = colors.yellow,
    TODO = colors.lightGray,
    ERROR = colors.red,
    HOME = colors.magenta,
    TEXT = colors.white,
    HOST = colors.cyan,
    DROPOFF = colors.lightBlue,
    FUEL = colors.orange
}

local function drawHeader()
    term.setBackgroundColor(COLORS.HEADER)
    term.setCursorPos(1, 1)
    term.clearLine()

    local tabs = { "STATUS", "LOGS", "MAP" }
    local x = 2
    for _, t in ipairs(tabs) do
        if activeTab == t then
            term.setTextColor(COLORS.TAB_ACTIVE)
            term.write("[" .. t .. "] ")
        else
            term.setTextColor(COLORS.TAB_INACTIVE)
            term.write(" " .. t .. "  ")
        end
    end

    term.setTextColor(COLORS.TEXT)
    local title = "ANTHILL HIVE"
    term.setCursorPos(width - #title, 1)
    term.write(title)
end

local function drawStatus(state)
    local turtleStatus = state.turtleStatus
    local availableShafts = state.availableShafts
    term.setBackgroundColor(COLORS.BG)
    term.setTextColor(COLORS.TEXT)
    term.setCursorPos(1, 3)
    term.write(string.format(" Shafts Left: %d", #availableShafts))

    -- Draw Stop/Start All at bottom
    term.setCursorPos(1, height)
    -- Simply check if any turtle is assigned MINING to decide button state?
    -- Or just have two buttons? Let's generic switch:
    -- If we want "Stop All", we set IDLE. If "Start All", we set MINING.
    -- Let's check the first turtle's assignment to guess state for the button label, or just static.
    -- Better: Toggle based on majority? or just "STOP ALL" (Red) | "RESUME ALL" (Green)

    local anyMining = false
    for id, assign in pairs(state.turtleAssignments) do
        if assign.task == "MINING" then
            anyMining = true
            break
        end
    end

    if anyMining then
        term.setBackgroundColor(colors.red)
        term.write(" [ STOP ALL MINING ] ")
    else
        term.setBackgroundColor(colors.green)
        term.write(" [ START MINING ]    ")
    end
    term.setBackgroundColor(COLORS.BG)

    term.setCursorPos(1, 4)
    term.write(string.rep("-", width))
    term.setCursorPos(1, 5)
    -- Adjusted columns to fit Age
    term.write(string.format(" %-3s %-8s %-8s %-4s %-7s %-4s %s", "ID", "Assign", "Status", "Age", "Pos", "Fuel", "Error"))
    term.setCursorPos(1, 6)
    term.write(string.rep("-", width))

    local sortedIds = {}
    for id in pairs(turtleStatus) do table.insert(sortedIds, id) end
    table.sort(sortedIds)

    local now = os.clock()

    for i, id in ipairs(sortedIds) do
        local s = turtleStatus[id]
        local assign = state.turtleAssignments[id] or { task = "?" }
        local posStr = s.pos and (s.pos[1] .. "," .. s.pos[3]) or "?"
        local statusStr = s.status or "?"
        local assignStr = assign.task or "-"

        -- Age Calculation
        local age = now - (s.lastSeen or now)
        local ageStr = string.format("%ds", math.floor(age))
        if age > 60 then
            ageStr = string.format("%dm", math.floor(age / 60))
        end

        if s.error then
            statusStr = "ERR"
            term.setTextColor(COLORS.ERROR)
        end

        local fuelPct = s.fuel or 0
        term.setCursorPos(1, 6 + i)
        -- Truncate strings to fit
        term.write(string.format(" %-3s %-8s %-8s %-4s %-7s %-4s %s",
            id,
            assignStr:sub(1, 8),
            statusStr:sub(1, 8),
            ageStr,
            posStr:sub(1, 7),
            fuelPct .. "%",
            (s.error or ""):sub(1, width - 40)
        ))
        term.setTextColor(COLORS.TEXT)
    end
end

local function drawLogs(state)
    local turtleLogs = state.turtleLogs
    local turtleStatus = state.turtleStatus
    if not selectedTurtle then
        term.setCursorPos(2, 4)
        print("Select a turtle in STATUS tab first.")
        return
    end

    -- Header Line
    term.setCursorPos(1, 3)
    term.setBackgroundColor(COLORS.BG)
    term.clearLine()
    term.setTextColor(COLORS.TEXT)
    term.write(" LOGS FOR TURTLE #" .. selectedTurtle)
    term.setBackgroundColor(COLORS.BG)

    -- Layout
    local detailsWidth = math.floor(width / 3)
    local logsWidth = width - detailsWidth - 1
    local sepX = logsWidth + 1

    -- Draw Separator
    term.setTextColor(colors.gray)
    for y = 4, height - 2 do
        term.setCursorPos(sepX, y)
        term.write("|")
    end
    term.setTextColor(COLORS.TEXT)

    -- Bottom Button (Adjusted to left side)
    term.setCursorPos(1, height)
    term.setBackgroundColor(COLORS.BG)
    term.clearLine() -- Clear old button if needed

    local assign = state.turtleAssignments[selectedTurtle]
    -- We can put the button on the left side or full width.
    -- Left side seems better to correspond with logs/control.
    term.setCursorPos(1, height)
    if assign and assign.task == "IDLE" then
        term.setBackgroundColor(colors.green)
        term.write(" [ RESUME (MINE) ] ")
    else
        term.setBackgroundColor(colors.red)
        term.write(" [ STOP (IDLE)   ] ")
    end
    term.setBackgroundColor(COLORS.BG)

    -- Draw Logs (Left Side)
    local logs = turtleLogs[selectedTurtle] or {}
    local maxLogLines = height - 5
    local startIndex = math.max(1, #logs - maxLogLines + 1)
    local drawY = 5

    for i = startIndex, #logs do
        term.setCursorPos(2, drawY)
        drawY = drawY + 1

        term.setBackgroundColor(COLORS.BG)
        term.setTextColor(colors.lightGray)
        local timeStr = "[" .. logs[i].time .. "] "
        term.write(timeStr)
        term.setTextColor(COLORS.TEXT)

        local msg = logs[i].msg
        if logs[i].raw and logs[i].raw.fuel then
            -- msg usually already contains info, but let's be sure
        end

        -- Truncate to fit in logsWidth
        local maxMsgLen = logsWidth - #timeStr - 2
        if #msg > maxMsgLen then msg = msg:sub(1, maxMsgLen) .. "..." end
        term.write(msg)
    end

    -- Draw Details (Right Side)
    local status = turtleStatus[selectedTurtle] or {}
    local dX = sepX + 2
    local dY = 5

    local function printDetail(label, val)
        term.setCursorPos(dX, dY)
        term.setTextColor(colors.gray)
        term.write(label .. ": ")
        term.setTextColor(COLORS.TEXT)
        term.write(tostring(val))
        dY = dY + 1
    end

    printDetail("Pos", status.pos and (status.pos[1] .. "," .. status.pos[2] .. "," .. status.pos[3]) or "?")
    printDetail("Fuel", status.fuel or "?")
    printDetail("Prog", status.program or "?")

    local assign = state.turtleAssignments[selectedTurtle]
    printDetail("Task", assign and assign.task or "None")
    dY = dY + 1

    term.setCursorPos(dX, dY)
    term.setTextColor(COLORS.HEADER)
    term.write("INVENTORY")
    dY = dY + 1

    if status.inventory then
        term.setCursorPos(dX, dY)
        term.setTextColor(colors.gray)
        term.write("Empty Slots: ")
        term.setTextColor(COLORS.TEXT)
        term.write(status.inventory.empty)
        dY = dY + 1

        local counts = status.inventory.counts or {}
        local sortedItems = {}
        for name, count in pairs(counts) do
            table.insert(sortedItems, { name = name, count = count })
        end
        table.sort(sortedItems, function(a, b) return a.count > b.count end)

        for _, item in ipairs(sortedItems) do
            if dY > height - 2 then break end
            term.setCursorPos(dX, dY)
            -- Shorten name: "minecraft:cobblestone" -> "cobblestone"
            local name = item.name:match(":(.+)") or item.name
            if #name > 12 then name = name:sub(1, 12) .. "." end

            term.setTextColor(COLORS.TEXT)
            term.write(string.format("%dx %s", item.count, name))
            dY = dY + 1
        end
    else
        term.setCursorPos(dX, dY)
        term.setTextColor(colors.lightGray)
        term.write("No Data")
    end
end

local function drawMap(quarry, availableShafts, activeAssignments, completedShafts, turtleHomeBases, hostPos)
    local minX, maxX = math.min(quarry.minX, quarry.maxX), math.max(quarry.minX, quarry.maxX)
    local minZ, maxZ = math.min(quarry.minZ, quarry.maxZ), math.max(quarry.minZ, quarry.maxZ)

    -- Map area (leave room for header and footer)
    local mapW, mapH = width, height - 1

    -- Clear map canvas if needed
    if not mapCanvas or #mapCanvas ~= mapW or #mapCanvas[1] ~= mapH then
        mapCanvas = {}
        for x = 1, mapW do
            mapCanvas[x] = {}
            for z = 1, mapH do
                mapCanvas[x][z] = colors.gray -- Default background
            end
        end
    else
        -- Clear existing canvas
        for x = 1, mapW do
            for z = 1, mapH do
                mapCanvas[x][z] = colors.gray
            end
        end
    end

    -- Coordinate mapping helper (1 block = 1 screen position, will be rendered as 2x2)
    local function worldToScreen(wx, wz)
        return (wx - minX) + 1 - scrollX, (wz - minZ) + 1 - scrollY
    end

    local function setPixel(sx, sz, color)
        if sx > 0 and sx <= mapW and sz > 0 and sz <= mapH then
            mapCanvas[sx][sz] = color
        end
    end

    -- Completed (Green)
    for key in pairs(completedShafts) do
        local x, z = key:match("([^,]+),([^,]+)")
        x, z = tonumber(x), tonumber(z)
        local sx, sz = worldToScreen(x, z)
        setPixel(sx, sz, COLORS.DONE)
    end

    -- To Be Dug (Light Gray)
    for _, s in ipairs(availableShafts) do
        local sx, sz = worldToScreen(s.x, s.z)
        setPixel(sx, sz, COLORS.TODO)
    end

    -- Active Assignments (Yellow)
    for id, assign in pairs(activeAssignments) do
        if assign.task == "MINING" and assign.data then
            local s = assign.data
            local sx, sz = worldToScreen(s.x, s.z)
            setPixel(sx, sz, COLORS.DIGGING)
        end
    end

    -- Home Bases (Magenta)
    for _, h in pairs(turtleHomeBases or {}) do
        local sx, sz = worldToScreen(h.x, h.z)
        setPixel(sx, sz, COLORS.HOME)
    end

    -- Mining Area Outline (Red)
    local ox1, oz1 = worldToScreen(minX - 1, minZ - 1)
    local ox2, oz2 = worldToScreen(maxX + 1, maxZ + 1)

    -- Draw outline
    for x = ox1, ox2 do
        setPixel(x, oz1, colors.red)
        setPixel(x, oz2, colors.red)
    end
    for z = oz1, oz2 - 1 do
        setPixel(ox1, z, 10000)
        setPixel(ox2, z, 10000)
    end

    setPixel(ox1, oz2, colors.red)
    setPixel(ox2, oz2, colors.red)

    -- Render the canvas using character 143 (2x2 blocks)
    term.setBackgroundColor(colors.gray)
    for z = 1, mapH do
        term.setCursorPos(1, z + 1) -- +1 for header
        for x = 1, mapW do
            local color = mapCanvas[x][z]
            if color ~= 10000 then
                term.setTextColor(color)
                term.setBackgroundColor(colors.gray)
                term.write("\143")
            else
                term.setBackgroundColor(colors.red)
                term.write(" ")
            end
        end
    end
end

function gui.run(state)
    local lastTab = nil
    local needsRedraw = true
    local refreshTimer = os.startTimer(1)

    while true do
        local oldW, oldH = width, height
        width, height = term.getSize()
        local resized = (oldW ~= width or oldH ~= height)

        if resized then
            mapCanvas = nil
            needsRedraw = true
        end

        if activeTab ~= lastTab or resized then
            term.setBackgroundColor(COLORS.BG)
            term.clear()
            drawHeader()
            lastTab = activeTab
            needsRedraw = true
        end

        if needsRedraw then
            if activeTab == "STATUS" then
                drawStatus(state)
            elseif activeTab == "LOGS" then
                drawLogs(state)
            elseif activeTab == "MAP" then
                if not mapCanvas then
                    local q = state.quarry
                    local x1, x2 = math.min(q.minX, q.maxX), math.max(q.minX, q.maxX)
                    local z1, z2 = math.min(q.minZ, q.maxZ), math.max(q.minZ, q.maxZ)
                    local mapW, mapH = width, height - 1
                    local midWorldX = (x1 + x2) / 2
                    local midWorldZ = (z1 + z2) / 2
                    scrollX = (midWorldX - x1) + 1 - (mapW / 2)
                    scrollY = (midWorldZ - z1) + 1 - (mapH / 2)
                end
                drawMap(state.quarry, state.availableShafts, state.turtleAssignments, state.completedShafts,
                    state.turtleHomeBases, state.hostPos)
            end
            needsRedraw = false
        end

        local event, p1, p2, p3 = os.pullEvent()

        if event == "anthill_update" then
            needsRedraw = true
        elseif event == "timer" and p1 == refreshTimer then
            needsRedraw = true
            refreshTimer = os.startTimer(1)
        elseif event == "term_resize" then
            needsRedraw = true
        elseif event == "mouse_click" then
            if p3 == 1 then -- Header area
                if p2 >= 2 and p2 <= 9 then
                    activeTab = "STATUS"
                elseif p2 >= 11 and p2 <= 16 then
                    activeTab = "LOGS"
                elseif p2 >= 18 and p2 <= 22 then
                    activeTab = "MAP"
                end
                needsRedraw = true
            elseif activeTab == "STATUS" and p3 == height and p2 <= 20 then
                -- Toggle All
                local anyMining = false
                for id, assign in pairs(state.turtleAssignments) do
                    if assign.task == "MINING" then
                        anyMining = true
                        break
                    end
                end

                if anyMining then
                    state.setAllAssignments("IDLE")
                else
                    state.setAllAssignments("MINING")
                end
                needsRedraw = true
            elseif activeTab == "LOGS" and p3 == height and p2 <= 20 and selectedTurtle then
                local assign = state.turtleAssignments[selectedTurtle]
                if assign and assign.task == "IDLE" then
                    state.setAssignment(selectedTurtle, "MINING")
                else
                    state.setAssignment(selectedTurtle, "IDLE")
                end
                needsRedraw = true
            elseif activeTab == "STATUS" and p3 >= 7 then
                local idx = p3 - 6
                local sortedIds = {}
                for id in pairs(state.turtleStatus) do table.insert(sortedIds, id) end
                table.sort(sortedIds)
                if sortedIds[idx] then
                    selectedTurtle = sortedIds[idx]
                    activeTab = "LOGS"
                    needsRedraw = true
                end
            elseif activeTab == "MAP" and p3 > 1 and p3 < height then
                local mapW, mapH = width, height - 1
                local clickedRelX = p2 - 1
                local clickedRelY = p3 - 2
                scrollX = scrollX + (clickedRelX - mapW / 2)
                scrollY = scrollY + (clickedRelY - mapH / 2)
                needsRedraw = true
            end
        elseif event == "key" then
            if p1 == keys.s then
                activeTab = "STATUS"; needsRedraw = true
            elseif p1 == keys.l then
                activeTab = "LOGS"; needsRedraw = true
            elseif p1 == keys.m then
                activeTab = "MAP"; needsRedraw = true
            elseif activeTab == "MAP" then
                if p1 == keys.up then
                    scrollY = scrollY - 1; needsRedraw = true
                elseif p1 == keys.down then
                    scrollY = scrollY + 1; needsRedraw = true
                elseif p1 == keys.left then
                    scrollX = scrollX - 1; needsRedraw = true
                elseif p1 == keys.right then
                    scrollX = scrollX + 1; needsRedraw = true
                end
            end
        end
    end
end

return gui


