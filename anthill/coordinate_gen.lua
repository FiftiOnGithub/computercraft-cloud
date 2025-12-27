-- Knight's Move Coordinate Generator for Anthill
-- Generates a grid of shafts where x % 5 == (2 * z) % 5

local function generate(xA, xB, zA, zB)
    local minX, maxX = math.min(xA, xB), math.max(xA, xB)
    local minZ, maxZ = math.min(zA, zB), math.max(zA, zB)
    local shafts = {}

    -- Iterate row-by-row (along Z axis)
    for z = minZ, maxZ do
        -- For each z, find the first x >= minX that satisfies the condition
        -- x % 5 == (2 * z) % 5
        local targetMod = (2 * z) % 5
        local startX = minX + (targetMod - (minX % 5) + 5) % 5

        for x = startX, maxX, 5 do
            table.insert(shafts, { x = x, z = z })
        end
    end

    return shafts
end

return {
    generate = generate
}
