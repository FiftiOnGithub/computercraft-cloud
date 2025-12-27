-- Anthill Host Configuration
return {
    PROTOCOL = "anthill",
    HOSTNAME = "main",
    MODEM_SIDE = "left",
    DEFAULT_ASSIGNMENT = "MINING",

    -- Mining Area
    QUARRY_DIMENSIONS = {
        minX = 121,
        maxX = 150,
        minZ = -30,
        maxZ = 0,
        targetY = -15,
        surfaceY = -8,
        travelHeightA = -7,
        travelHeightB = -6,

        -- Logistics Chests
        dropoffPos = { x = 119, y = -9, z = -8 },
        fuelPickupPos = { x = 119, y = -9, z = -5 }
    },

    -- Files served to turtles on boot
    REQUIRED_FILES = {
        "navigation.lua",
        "mining.lua",
        "worker.lua"
    }
}
