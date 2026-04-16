--// SERVICES
-- these are just the standard roblox tools we need to make things move/sound/work
local Players = game:GetService("Players")
local Pathfinding = game:GetService("PathfindingService") -- for the npc to walk around corners
local RunService = game:GetService("RunService") -- lets us run code every frame
local Debris = game:GetService("Debris") -- cleans up sounds so they dont clog the server
--// SETTINGS
-- play around with these if he's too fast or too dumb
local config = {
	viewDist = 50, -- how far he can see players
	fov = 120, -- his "cone" of vision. 180 would be like having eyes on the side of his head
	
	walkSpeed = 12, -- speed when just chillin
	chaseSpeed = 22, -- speed when he wants to eat you
	attackDist = 6, -- how close he needs to be to start the kill
	killCooldown = 5, -- stops him from wiping the whole server in 2 seconds
	
	-- I hope these IDs still work... if not, the npc will just be a gray block
	killAnim = "rbxassetid://1212121212",
	morphSfx = "rbxassetid://123456789",
	stepSfx = "rbxassetid://987654321"
}
--// VARS
local rig = script.Parent -- the npc model
local hum = rig:WaitForChild("Humanoid")
local root = rig:WaitForChild("HumanoidRootPart") -- the main "body" part for physics
local remotes = game.ReplicatedStorage:WaitForChild("Remotes") -- for sending effects to players
local state = "IDLE" -- keeping track of what he's doing
local targetPlr = nil -- who are we chasing right now?
local lastKill = 0 -- timestamp of the last murder
local isPathing = false -- so we dont try to start 5 paths at once

--// HELPERS

-- quick function to get the HRP of a player. saves a lot of typing.
local function getRoot(char)
	return char and char:FindFirstChild("HumanoidRootPart")
end

-- helper for sounds. I added math.random for the pitch so it doesnt 
-- sound like a robot repeating the same clip over and over.
local function playSfx(id, vol)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 1
	s.PlaybackSpeed = math.random(9, 11) / 10 -- random pitch variation
	s.Parent = root
	s:Play()
	Debris:AddItem(s, 3) -- deletes the sound after 3 seconds so we dont lag
end

--// THE BRAINS

-- this is the complicated part. it checks distance, THEN field of view, THEN walls.
local function canSee(target)
	local tRoot = getRoot(target)
	if not tRoot then return false end

	local dir = (tRoot.Position - root.Position)
	local dist = dir.Magnitude

	-- if theyre too far, dont even bother with the math
	if dist > config.viewDist then return false end

	-- DOT PRODUCT MATH: basically checks if the player is in front of the NPC
	local dot = root.CFrame.LookVector:Dot(dir.Unit)
	local angle = math.deg(math.acos(dot))

	-- if they are behind him or off to the side, he cant see them
	if angle > (config.fov / 2) then
		return false
	end

	-- RAYCASTING: draws an invisible line to see if a wall is in the way
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {rig, target} -- ignore the npc and the player
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(root.Position, dir, params)

	-- if the line doesnt hit any bricks, he can see the player. sucesfully.
	return result == nil
end

-- scans all the players in the game to find the closest one he can actually see
local function findTarget()
	local best = nil
	local closest = config.viewDist

	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local pRoot = getRoot(char)
		local pHum = char and char:FindFirstChild("Humanoid")

		-- make sure the player is alive and close enough
		if pRoot and pHum and pHum.Health > 0 then
			local d = (root.Position - pRoot.Position).Magnitude
			if d < closest and canSee(char) then
				best = char
				closest = d
			end
		end
	end

	targetPlr = best -- set our global target
end

-- THE MORPHING BIT: this steals the players outfit and name
local function stealIdentity(victim)
	state = "MORPHING"
	local vHum = victim:FindFirstChild("Humanoid")
	
	if vHum then
		print("stealing " .. victim.Name .. "s identity lol") -- just for the output log
		
		playSfx(config.morphSfx, 1.5)
		
		-- HumanoidDescription is great because it handles hats/clothes automatically
		local desc = vHum:GetAppliedDescription()
		local ok, err = pcall(function()
			hum:ApplyDescription(desc)
		end)
		
		if not ok then warn("rip, morph failed: " .. err) end
		
		-- make him look like a real player by hiding his "NPC" overhead gui and stealing the name
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		rig.Name = victim.Name
	end
end
-- basic pathfinding so he doesnt get stuck on a part when wandering
local function wander(pos)
	if isPathing then return end
	isPathing = true
	local path = Pathfinding:CreatePath({AgentRadius = 3, AgentCanJump = true})
	path:ComputeAsync(root.Position, pos)
	if path.Status == Enum.PathStatus.Success then
		local wps = path:GetWaypoints()
		for i, wp in ipairs(wps) do
			-- if he sees someone mid-walk, he should stop wandering and start chasing
			if not isPathing or targetPlr then break end 
			
			hum:MoveTo(wp.Position)
			if wp.Action == Enum.PathfindingWaypointAction.Jump then
				hum.Jump = true
			end
			-- wait for him to reach the point or give up after 2 secs (so he doesnt get stuck forever)
			local arrived = hum.MoveToFinished:Wait(2)
			if not arrived then break end
		end
	end
	isPathing = false
end
--// MAIN LOOP
-- we use heartbeat because it's reliable for AI. 
local lastTick = 0
RunService.Heartbeat:Connect(function()
	-- only run this logic 10 times a second. running it 60 times is overkil and laggy.
	if tick() - lastTick < 0.1 then return end
	lastTick = tick()
	findTarget() -- look for players probaly
	if targetPlr then
		local tRoot = getRoot(targetPlr)
		local d = (tRoot.Position - root.Position).Magnitude

		-- if we are close enough to kill them...
		if d <= config.attackDist then
			-- check if the kill is on cooldown first
			if tick() - lastKill < config.killCooldown then return end
			
			state = "ATTACKING"
			lastKill = tick()

			-- trigger the jumpscare on the players screen
			local p = Players:GetPlayerFromCharacter(targetPlr)
			if p then remotes.Jumpscare:FireClient(p) end

			-- play the kill animation
			local track = hum:LoadAnimation(Instance.new("Animation"))
			track.AnimationId = config.killAnim
			track:Play()

			task.wait(0.6) -- wait for the "hit" part of the animation
			targetPlr.Humanoid.Health = 0 -- rip player
			stealIdentity(targetPlr) -- morph into them
			
			task.wait(2) -- stay in "attack" mode for a bit so it looks cool
			state = "IDLE"
		else
			-- if theyre too far to hit, just run at them
			state = "CHASING"
			hum.WalkSpeed = config.chaseSpeed
			hum:MoveTo(tRoot.Position) -- direct move is faster than pathfinding for chasing
		end
	else
		-- nobody is around, so just walk to a random waypoint part in the map
		state = "PATROLLING"
		hum.WalkSpeed = config.walkSpeed
		local nodes = workspace:FindFirstChild("Waypoints")
		if nodes and not isPathing then
			local all = nodes:GetChildren()
			local goal = all[math.random(1, #all)]
			if goal:IsA("BasePart") then
				-- use task.spawn so the pathfinding doesnt block the rest of the loop
				task.spawn(function() wander(goal.Position) end)
			end
		end
	end
end)
-- SEPARATE THREAD FOR SOUNDS
-- this just loops and plays footstep sounds if the npc is actually moving
task.spawn(function()
	while task.wait(0.4) do
		-- velocity.magnitude is basically just checking "how fast is he moving"
		if root.Velocity.Magnitude > 2 then
			playSfx(config.stepSfx, 0.2)
		end
	end
end)
