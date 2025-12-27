term.clear()
term.setCursorPos(1, 1)
print("Anthill Host Debug Log")
while true do
    local _, text = os.pullEvent("log")
    print(os.date("%H:%M:%S") .. " | " .. text .. "\n")
end
