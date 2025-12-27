Anthill - Autonomous Mining System
Overview
Anthill is a distributed autonomous mining system for ComputerCraft turtles. It coordinates multiple mining turtles through a central host computer, managing assignments, tracking progress, and providing a graphical user interface for monitoring and control.

Key Features:

Task-based assignment system (MINING, IDLE, DROPOFF, REFUEL)
GPS-resilient navigation for shaft operations
Real-time position tracking and visualization
Automatic logistics (inventory dropoff, refueling)
Graphical dashboard with status monitoring and map view
Architecture
Components
Host Computer (
host.lua
)
Central coordinator that manages all turtles. Runs continuously and handles:

Assignment management (MINING, IDLE, DROPOFF, REFUEL)
Shaft allocation from available mining area
State persistence to disk
File synchronization to turtles
Beacon responses for GPS-less surface detection
Worker Turtles (
worker.lua
)
Autonomous mining units that:

Execute assigned tasks (mining, dropoff, refuel, recall)
Handle logistics automatically (inventory management, fuel monitoring)
Report status and position to host
Recover from reboots in shafts using beacon-based surface detection
GUI (
gui.lua
)
Graphical interface using Blittle library that provides:

Status Tab: List of all turtles with fuel, assignment, and age
Logs Tab: Detailed turtle information, inventory view, and position history
Map Tab: 2D visualization of turtle positions and mining area
Control buttons for assignment management (Stop All, Start Mining, Recall)
Tracker (
tracker.lua
)
Standalone position tracking dashboard that:

Displays turtle positions, programs, and last seen times
Shows distance from tracker
Handles GPS failures gracefully (displays cached coordinates in red)
Provides detail view with position history
Supporting Modules
navigation.lua
: Movement and pathfinding

GPS-based positioning with hibernation on outage
Travel height system (A/B lanes for traffic management)
Heading tracking and calibration
Parking mode for base operations
mining.lua
: Shaft digging operations

Vertical shaft excavation to target depth
Ore scanning and collection (whitelist-based)
Fuel monitoring during descent
Returns depth mined for blind ascent
main.lua
: Turtle bootstrap

Host discovery via rednet
File synchronization from host
Position broadcasting to tracker (handles GPS failures)
Worker launch
config.lua
: System configuration

Mining area dimensions and coordinates
Logistics positions (dropoff, fuel pickup)
Travel heights for traffic management
Default assignment behavior
Assignment System
Assignment Types
MINING: Turtle mines assigned shaft to target depth

Host assigns available shaft coordinates
Turtle navigates to shaft, descends, mines, ascends
Automatically handles logistics (dropoff if full, refuel if low)
Reports completion when shaft finished
IDLE: Turtle returns to base and parks

Navigates to staging corner, then base corner
Parks at travel height (not on ground)
Smart recall: if already on parking row, stays put
DROPOFF: One-time task to empty inventory

Navigates to dropoff position
Dumps all items
Returns to previous assignment (callback system)
REFUEL: One-time task to refuel

Navigates to fuel pickup position
Collects fuel from chest below
Returns to previous assignment (callback system)
Assignment Flow
Startup: Turtle defaults to config.DEFAULT_ASSIGNMENT (typically MINING or IDLE)
Handshake: Turtle requests assignment from host
Execution: Turtle performs assigned task
Logistics: During mining, automatically triggers DROPOFF/REFUEL if needed
Completion: Reports to host, receives next assignment
Callback System
When a turtle is mining and needs logistics:

Current assignment (MINING) saved as callback
Temporary assignment (DROPOFF/REFUEL) executed
After completion, callback restored → turtle resumes mining
GPS-Resilient Navigation
Problem
GPS is unavailable deep in mining shafts. Turtles can reboot in shafts (e.g., world reload), causing them to get stuck waiting for GPS that will never arrive.

Solution: Beacon-Based Surface Detection
At startup only, if GPS unavailable:

Send BEACON request via rednet to host
Host responds via modem on channel 9999 with "HOST_BEACON" (includes distance)
Turtle ascends while tracking distance to host
Distance increases → turtle has passed surface level (host is at surface)
Stop ascending, retry GPS
If GPS works → continue normally
If GPS still down → hibernate (service outage)
During operation: GPS failure → hibernate (existing behavior, correct for surface operations)

Safety Features
Only ascends (never digs or moves horizontally)
Only runs at startup (not during operation)
Stops when distance increases (can't fly to stratosphere)
Hibernates if host unreachable (total outage)
Hibernates if blocked during ascent
Communication Protocols
Rednet Protocol: "anthill"
DISCOVER (turtle → host):

Turtle searching for host
Response: ADVERTISE with required files list
HANDSHAKE (turtle → host):

Turtle requesting assignment
Includes: fuel level, position, inventory, program
Response: Assignment message (RECALL, ASSIGNMENT, DROPOFF, REFUEL)
UPDATE (turtle → host):

Status update during task execution
Includes: status, position, fuel, inventory
COMPLETE (turtle → host):

Task completion notification
Includes: shaft coordinates (for MINING)
BEACON (turtle → host):

Surface detection request (GPS-less startup)
Response: Modem transmission on channel 9999
Tracker Protocol: "tracker"
POSITION (turtle → broadcast):

Periodic position broadcast (every 10 seconds)
Includes: position (or nil if GPS failed), fuel %, program name
Tracker displays cached coordinates in red if GPS unavailable
Workflows
Normal Mining Operation
Turtle boots, calibrates heading via GPS
Handshake with host → receives MINING assignment with shaft coordinates
Navigate to shaft at surface
Call mining.digShaft() → descends to target depth
Scan for ores at each level, collect valuable blocks
Check inventory → if full, trigger DROPOFF logistics
Check fuel → if low, trigger REFUEL logistics
Reach target depth → blind ascent using tracked depth
At surface → report COMPLETE
Handshake for next assignment
Reboot in Shaft Recovery
Turtle boots in shaft → GPS unavailable
ascendToSurfaceViaBeacon() called
Send BEACON request to host
Host responds via modem with distance
Ascend while tracking distance
Distance increases → surface detected
Retry GPS → now available
Calibrate heading
Continue normal operation
Logistics During Mining
Inventory Full:

Save current MINING assignment as callback
Set assignment to DROPOFF
Navigate to dropoff position
Dump all items
Restore MINING callback
Return to shaft, continue mining
Low Fuel (similar flow with REFUEL)

User Control via GUI
Stop All: Sets all turtles to IDLE assignment

Turtles finish current task, then return to base
Start Mining: Sets all IDLE turtles to MINING

Turtles receive shaft assignments and begin mining
Recall (individual): Sets specific turtle to IDLE

Available in Logs tab for per-turtle control
Data Structures
Host State
turtleAssignments = {
    [turtleID] = {
        task = "MINING" | "IDLE" | "DROPOFF" | "REFUEL",
        data = { x, z },  -- shaft coordinates for MINING
        callback = { task, data }  -- saved assignment for logistics
    }
}
turtleData = {
    [turtleID] = {
        fuel = number,
        pos = {x, y, z},
        status = string,
        inventory = { counts, empty },
        program = string,
        lastSeen = number
    }
}
availableShafts = { {x, z}, ... }  -- unassigned shafts
activeAssignments = { [turtleID] = {x, z} }  -- assigned shafts
Tracker State
turtles = {
    [turtleID] = {
        pos = {x, y, z} or nil,
        lastKnownPos = {x, y, z},  -- cached for GPS failures
        lastSeen = string,
        program = string,
        fuel = number,
        history = { {pos, timestamp}, ... }
    }
}
Configuration
Mining Area (
config.lua
)
QUARRY_DIMENSIONS = {
    minX, maxX, minZ, maxZ,  -- Mining area bounds
    targetY,  -- Depth to mine to
    surfaceY,  -- Surface level
    travelHeightA, travelHeightB,  -- Traffic lanes
    dropoffPos = {x, y, z},  -- Inventory dropoff chest
    fuelPickupPos = {x, y, z}  -- Fuel source chest
}
Shaft Grid: Automatically generated from mining area

Spacing: 3 blocks between shafts
Covers entire defined area
Tracked as available/assigned
Travel Heights: Two-lane system

Turtles moving in positive X/Z direction use height A
Turtles moving in negative X/Z direction use height B
Prevents mid-air collisions
Default Assignment
DEFAULT_ASSIGNMENT = "MINING" or "IDLE"

Determines turtle behavior on first boot
MINING: Turtles immediately start mining
IDLE: Turtles wait at base for manual start
Display Features
Tracker Dashboard
List View:

ID, Program (without .lua), Last Position, Distance, Last Seen
Position shown as ? (x,y,z) in red if GPS unavailable but cached
Distance calculated from tracker's position to turtle
Detail View:

Position history (newest at bottom, oldest at top)
Cached coordinates shown in red if GPS unavailable
Duplicate positions grayed out to reduce visual noise
Fuel percentage and program name per entry
GUI Dashboard
Status Tab:

Turtle list with ID, fuel %, assignment, age
"Stop All" / "Start Mining" toggle button
Real-time updates
Logs Tab:

Selected turtle details (fuel, position, program, assignment)
Inventory view (item counts, empty slots)
Position history
Individual "Recall" button
Map Tab:

2D overhead view of mining area
Turtle positions marked
Mining area boundaries
Dropoff/fuel positions
Error Handling
GPS Failures
In shaft: Use beacon-based surface detection
At surface: Hibernate until GPS returns
During mining: Not called (uses relative tracking)
Blocked Movement
During ascent from shaft: Report error, freeze (don't dig infrastructure)
During navigation: Wait for path to clear (traffic jam handling)
During calibration: Attempt to move up, retry
Communication Failures
Host unreachable: Retry discovery
Beacon timeout: Hibernate (assume total outage)
File sync failure: Retry sync
Fuel Depletion
During mining: Attempt to refuel from inventory
If stuck: Report error and freeze
Low fuel: Automatic REFUEL logistics
File Synchronization
On turtle boot:

Discover host via DISCOVER message
Request FILE_SYNC
Host sends all files in config.REQUIRED_FILES
Turtle writes files to disk
Launch worker with host ID
Files synced: 
navigation.lua
, 
mining.lua
, 
worker.lua

State Persistence
Host State
Saved to state.json on every update
Contains: assignments, turtle data, available shafts
Loaded on host restart
Tracker State
Saved to tracker_data.json periodically
Contains: turtle positions, history
Loaded on tracker restart
Design Decisions
Why Task-Based Assignments?
Replaced binary recall system with flexible task model to support:

One-time logistics tasks (dropoff, refuel)
Callback system for resuming work
Clear separation of concerns
Why Beacon-Based Surface Detection?
State persistence unreliable (chunk unloading)
Auto-ascent to stratosphere dangerous (GPS service might be down)
Distance measurement provides reliable surface detection
Only runs at startup (minimal overhead)
Why Travel Heights?
Prevents mid-air collisions between turtles
Simple directional routing (no complex pathfinding)
Predictable traffic patterns
Why Smart Recall?
Turtles already at base don't waste fuel traveling
Reduces unnecessary movement
Faster response to "Stop All" command
Limitations
Requires GPS service for normal operation
Host must be at surface level for beacon system
Turtles cannot navigate without GPS (except startup recovery)
Single-threaded host (processes messages sequentially)
No multi-world support