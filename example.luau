-- Fetching the core Roblox game services needed for player tracking and lifecycle
local Players = game:GetService("Players") -- Service to manage player entries and exits
local ReplicatedStorage = game:GetService("ReplicatedStorage") -- Shared storage for cross-script access
local Debris = game:GetService("Debris") -- Service for scheduled, clean asset destruction

-- Global configuration settings for game balancing and timing adjustments
local INTERMISSION_DURATION = 20 -- Time in seconds players wait before a round starts
local ROUND_DURATION = 30 -- Total active time given for an event round to finish
local MIN_PLAYERS_REQUIRED = 1 -- Minimum players needed to kick off the main cycle

-- Dynamic game states and dictionary references
local gameActive = false -- Boolean tracker to monitor if a match is running
local playerConnections = {} -- Dictionary to map user IDs to active connection events

-- Core function dedicated to handling user statistics setup
local function setupPlayerStats(player)
	-- Look for preexisting folder or create a new leaderstats folder
	local leaderstats = player:FindFirstChild("leaderstats") or Instance.new("Folder")
	leaderstats.Name = "leaderstats" -- Must be lowercase 'leaderstats' for leaderboard UI
	leaderstats.Parent = player -- Parent folder directly to player object to load UI

	-- Instantiate the custom sanity tracker integer variable
	local sanity = Instance.new("IntValue") -- Standard integer wrapper object
	sanity.Name = "Sanity" -- Sets standard label used across event systems
	sanity.Value = 100 -- Starting resource pool maximum capacity for players
	sanity.Parent = leaderstats -- Embed statistic inside the leaderstats directory
	
	-- Connect to the CharacterAdded signal to track character models dynamically
	playerConnections[player.UserId] = player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid") -- Safely index character health manager
		local lastHealth = humanoid.Health -- Establish a benchmark memory variable for health updates

		-- Monitor internal health changes to deduce sudden drops or damage spikes
		local healthConn; healthConn = humanoid.HealthChanged:Connect(function(currentHealth)
			-- Evaluate if current state indicates damage was sustained by user
			if currentHealth < lastHealth then
				local damage = lastHealth - currentHealth -- Isolate specific deduction difference value
				sanity.Value = math.max(0, sanity.Value - math.floor(damage * 0.75)) -- Reduce sanity points proportionally
			end -- Terminate damage evaluation conditional scope
			lastHealth = currentHealth -- Adjust tracker benchmark to current health value
		end) -- Terminate HealthChanged internal connection structural code block

		-- Capture character death state to reset relevant dynamic tracking systems
		local diedConn; diedConn = humanoid.Died:Connect(function()
			sanity.Value = 0 -- Instantly drain sanity value down to absolute zero base
			healthConn:Disconnect() -- Flush the old health listener out of memory scope
			diedConn:Disconnect() -- Clear this death connection instance to prevent leaking references
		end) -- Terminate Died event connection structure block
	end) -- Close dynamic character spawn connection wrapper scope
end -- Complete setup player stats master function block

-- Garbage collection script routine meant to sweep data when players leave
local function removePlayerStats(player)
	-- Verify if player possesses registered active connection entries inside our log
	if playerConnections[player.UserId] then
		playerConnections[player.UserId]:Disconnect() -- Disconnect main listener mapping tracking
		playerConnections[player.UserId] = nil -- Free table memory key index slot completely
	end -- Terminate key presence safety conditional test structure
end -- Conclude resource disposal function routine blocks

-- Storage system grouping together all individual match map activities
local MapEvents = {
	-- Dangerous environment logic handling lava interaction and creation
	Lava = function()
		local lava = Instance.new("Part") -- Create physical primitive workspace part template
		lava.Size = Vector3.new(500, 1, 500) -- Broad layout scaling parameters to coat ground floors
		lava.Position = Vector3.new(0, 0, 0) -- Target position centering directly over center stage arena
		lava.BrickColor = BrickColor.new("Bright red") -- Assign clear visual alert coloring palette
		lava.Material = Enum.Material.Neon -- Emissive surface configuration to visually emphasize threat
		lava.Anchored = true -- Static locking setting applied to freeze position space matrix
		lava.CanCollide = false -- Intentionally turn off collisions to pass damage through steps
		lava.Parent = workspace -- Insert active instanced component into standard physical layer
		
		-- Hook event logic handler tracking intersecting collisions with hazard zone
		local touchConn = lava.Touched:Connect(function(hit)
			local hum = hit.Parent:FindFirstChildOfClass("Humanoid") -- Validate hit object source origin
			if hum then hum:TakeDamage(10) end -- Deal flat health payload on intersecting collision detection
		end) -- Terminate touch tracking execution process block
		
		task.wait(ROUND_DURATION) -- Keep environment threat fully functional through whole duration loop
		touchConn:Disconnect() -- Break link connections to prevent residual background tick tracking
		lava:Destroy() -- De-allocate hazard asset entirely from server layer structures
	end, -- End lava sequence block callback structure

	-- Natural hazard generator script producing periodic overhead projectiles
	Meteors = function()
		local active = true -- Active flag tracking loop execution safety parameters
		task.spawn(function() -- Isolate internal hazard timer away from system thread blocking
			while active do -- Repeat loop execution until termination signal flag is toggled
				task.wait(math.random(1, 3)) -- Set semi-random target timing parameters between falling objects
				local meteor = Instance.new("Part") -- Instantiate fresh physics projectile part asset
				meteor.Shape = Enum.PartType.Ball -- Standard spherical geometrical structural mold representation
				meteor.Size = Vector3.new(10, 10, 10) -- Large volumetric layout scaling framework for debris
				meteor.Position = Vector3.new(math.random(-100, 100), 150, math.random(-100, 100)) -- Scatter start points overhead
				meteor.BrickColor = BrickColor.new("Camo") -- Muddy surface color palette selection setup
				meteor.Velocity = Vector3.new(0, -100, 0) -- Apply strong initial downward momentum trajectory vector force
				meteor.Parent = workspace -- Commit current instance structural link down to physics engine
				
				-- Handle spatial impacts when debris contacts structure ground segments
				meteor.Touched:Connect(function()
					local exp = Instance.new("Explosion") -- Generate dynamic explosive instance utility module
					exp.Position = meteor.Position -- Center point mapping aligned exactly onto projectile origin location
					exp.BlastRadius = 15 -- Explocive range setting bounding parameters
					exp.Parent = workspace -- Explode in global environment layout context immediately
					meteor:Destroy() -- Clean tracking projectile entity records off the grid
				end) -- Close internal projectile collision routine scope
				Debris:AddItem(meteor, 5) -- Fail-safe lifespan limitation applied to prevent infinite drifting items
			end -- Close active flag controlled conditional generation loop structure
		end) -- End system thread isolating sub-task initialization block
		task.wait(ROUND_DURATION) -- Pause master level tracking script for duration scope limits
		active = false -- Flip switch status parameter to cease object production calls
	end, -- End meteor event dictionary structure setup

	-- Dynamic moving wall obstacle utilizing basic interpolation calculations
	Tsunami = function()
		local wave = Instance.new("Part") -- Instantiate moving wall geometrical threat block profile
		wave.Size = Vector3.new(500, 50, 10) -- Broad dimensional profile scaling framework for threat walls
		wave.Position = Vector3.new(0, 25, -250) -- Starting positioning coordinate assignment framework setup
		wave.BrickColor = BrickColor.new("Bright blue") -- Assign blue thematic tint styling layout profile
		wave.Transparency = 0.5 -- Visual opacity reduction variable assignment framework parameters
		wave.Anchored = true -- Fix component tracking against active physics engine weight reactions
		wave.CanCollide = false -- Restrict rigid framework pushing behaviors during translation updates
		wave.Parent = workspace -- Mount structural instance entry record into current level workspace
		
		-- Establish active hazard interception parameters mapping physical contacts
		local touchConn = wave.Touched:Connect(function(hit)
			local hum = hit.Parent:FindFirstChildOfClass("Humanoid") -- Query hit element character configuration details
			if hum then hum:TakeDamage(50) end -- Execute massive structural damage penalty checks against health
		end) -- Close collision routine linkage structure map definitions
		
		-- Linear frame tracking simulation loop moving threat wall piece safely
		for i = 0, 1, 0.01 do -- Progress numeric fraction scale step benchmarks over loop frames
			wave.Position = wave.Position:Lerp(Vector3.new(0, 25, 250), 0.01) -- Move location using basic lerp matrix calculations
			task.wait() -- Yield processing frames explicitly to smooth graphic display refresh loops
		end -- Terminate translation framing script update loop block structure
		
		touchConn:Disconnect() -- Unlink active damage tracking connections safely before deleting assets
		wave:Destroy() -- Purge moving threat boundary part away from persistent level layers
	end, -- End tsunami event dictionary definition block structure

	-- Inventory distribution event rewarding active survivors with item loadouts
	Swords = function()
for _, player in Players:GetPlayers() do -- Cycle through active players currently connected to server instance
local char = player.Character -- Collect character model property links safely from user objects
if char and char:FindFirstChild("Humanoid") and char.Humanoid.Health > 0 then -- Verify actor viability
local sword = ReplicatedStorage:FindFirstChild("ClassicSword") -- Scan local storage assets for weapons blueprints
if sword then -- Check item template validation status parameters before running code clones
sword:Clone().Parent = player.Backpack -- Insert cloned item instances inside user inventories safely
end -- End internal configuration check verifying inventory asset status options
end -- End user state validation checks confirming active baseline health levels
end -- Close automated player grouping looping sequences structures block
task.wait(ROUND_DURATION) -- Keep loadout distribution parameters functional through core match durations
end -- Close individual loadout event action logic handling boundaries
} -- Complete full map activities mapping configuration definitions
-- Central state machine function manager running continuous round sequences
local function startLoop()
while true do -- Maintain infinite operational looping pattern workflow system cycles
local currentPlayers = Players:GetPlayers() -- Pull updated player counts currently initialized
if #currentPlayers >= MIN_PLAYERS_REQUIRED then -- Evaluate if participant thresholds meet requirements
gameActive = true -- Elevate structural state status flag variables to operational metrics
print("Intermission starting...") -- Send standard system updates over console tracking networks
task.wait(INTERMISSION_DURATION) -- Halt game flow for standard intermission countdown timings
-- Array index registry specifying active available option pathways
local eventKeys = {"Lava", "Meteors", "Tsunami", "Swords"} -- Mapping array of valid event identifiers
local chosenEvent = eventKeys[math.random(1, #eventKeys)] -- Extract random target keys from index pools
print("Event chosen: " .. chosenEvent) -- Log active operations data directly inside diagnostics logs
-- Shield master game loop routine tracking using protective wrapper layers
local success, err = pcall(function()
MapEventschosenEvent -- Launch index matched event routine directly from configuration definitions
end) -- Close protected execution parameter structural definition code block
if not success then -- Inspect outcome metrics to isolate structural execution runtime faults
warn("Error running event " .. chosenEvent .. ": " .. tostring(err)) -- Output tracked exceptions safely
end -- Terminate code execution error monitoring status verification structures
-- Process points distribution profiles checking ongoing state details
for _, player in Players:GetPlayers() do -- Iterate active session player registries sequentially
local stats = player:FindFirstChild("leaderstats") -- Query active user statistics storage folders
local sanity = stats and stats:FindFirstChild("Sanity") -- Pull point profile records tracking sanity metrics
if sanity and sanity.Value > 0 then -- Confirm survivor profile viability via resource values
print(player.Name .. " survived the round!") -- Print celebration success entries across standard consoles
end -- Terminate survivor health metric verification code block segments
end -- Close data distribution player parsing loop sequence bounds
print("Round finished. Restarting loop...") -- Append sequence termination markers inside tracking consoles
else -- Fallback route handling low server activity state scenarios
gameActive = false -- Lower structural match activity indicators down to dormant states
print("Waiting for more players...") -- Stream connectivity requirement notices down tracking dashboards
task.wait(5) -- Set basic cool-down loops before evaluating connection populations again
end -- End participant verification structural evaluation statement blocks
end -- Terminate master framework infinite sequencing runtime execution paths
end -- End core lifecycle game loop manager system definitions
-- Initialize stats setup layout configurations processing retroactively existing profiles
for _, player in Players:GetPlayers() do -- Process player models matching active historical load connections
setupPlayerStats(player) -- Execute baseline profile layout setups targeting existing session contexts
end -- Terminate active historical registry setup parsing workflows completely
-- Attach primary global event listening systems mapping session updates safely
Players.PlayerAdded:Connect(setupPlayerStats) -- Direct system pipeline routes to handle incoming connection setups
Players.PlayerRemoving:Connect(removePlayerStats) -- Direct system connections ensuring data cleanup on departures
-- Execute master framework loop routines across independent background threads safely
task.spawn(startLoop) -- Initialize main processing structures tracking session round pipelines safely
