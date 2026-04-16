

--// SERVICES
local Players = game:GetService("Players")
local Pathfinding = game:GetService("PathfindingService")
local RunService = game:GetService("RunService") -- switched to heartbeat for better performance than a while loop

--// SETTINGS
local rig = script.Parent
local Remotes = game.ReplicatedStorage:WaitForChild("Remotes")

local VIEW_DIST = 40
local ATTACK_RANGE = 5
local COOLDOWN = 3

--// STATE VARS
local busy = false
local pathing = false

-- quick helper to get the root part without typing it out 100 times
-- also stops the script from breaking if the character isnt fully loaded yet
local function getRoot(model)
	return model:FindFirstChild("HumanoidRootPart")
end

--// VISION CHECK
-- we dont want the npc to be a cheater. distance check isnt enough,
-- so I'm using raycasting to make sure he actually has a clear line of sight
local function canSee(target)
	local myRoot = getRoot(rig)
	local targetRoot = getRoot(target)

	if not myRoot or not targetRoot then return false end

	-- get the direction vector between the two
	local rayDir = (targetRoot.Position - myRoot.Position)
	
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {rig}
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(myRoot.Position, rayDir, params)

	-- if the ray hits the target model first, we know he can see them
	return result and result.Instance:IsDescendantOf(target)
end

--// TARGETING LOGIC
-- this finds the closest player but only if theyre visible.
-- i used a magnitude check here cuz its cheap on performance
local function findClosestPlayer()
	local bestTarget = nil
	local maxDist = VIEW_DIST
	local myRoot = getRoot(rig)

	if not myRoot then return end

	for _, plyr in ipairs(Players:GetPlayers()) do
		local char = plyr.Character
		local root = getRoot(char)

		if root then
			local d = (myRoot.Position - root.Position).Magnitude
			if d < maxDist and canSee(char) then
				bestTarget = char
				maxDist = d
			end
		end
	end

	return bestTarget
end

--// ATTACK & MORPH
-- this handles the jumpscare logic and the morphing bit.
-- i put a debounce here so he doesnt try to kill 5 people at once and break the anims
local function initiateAttack(victim)
	if busy then return end
	busy = true

	local root = getRoot(rig)
	local vRoot = getRoot(victim)
	if not root or not vRoot then busy = false return end

	local dist = (root.Position - vRoot.Position).Magnitude

	-- if theyre too far, just move toward them instead of trigering the kill
	if dist > ATTACK_RANGE then
		rig.Humanoid:MoveTo(vRoot.Position)
		busy = false
		return
	end

	-- the kill sequence
	local vHum = victim:FindFirstChildOfClass("Humanoid")
	local myHum = rig:FindFirstChildOfClass("Humanoid")

	if vHum and myHum then
		local p = Players:GetPlayerFromCharacter(victim)
		if p then Remotes.Jumpscare:FireClient(p) end

		-- playing the kill anim
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://1212121212" -- obviously i used random id for this script dont judeg lol
		local track = myHum:LoadAnimation(anim)
		track:Play()

		task.wait(0.5)
		vHum.Health = 0
		task.wait(0.3)

		-- morphing logic: we copy the victims look after theyre dead.
		-- makes it feel more like he "stole" their identity
		local look = vHum:GetAppliedDescription()
		myHum:ApplyDescription(look)
		myHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		
		print("Succesfully morphed into: " .. victim.Name)
		
		task.wait(COOLDOWN)
	end

	busy = false
end

--// MOVEMENT
-- basic pathfinding for when he's just wandering around.
-- i added a check inside the loop so he can interupt his walk if he sees someone
local function walkTo(pos)
	if pathing then return end
	pathing = true

	local path = Pathfinding:CreatePath({AgentCanJump = false})
	path:ComputeAsync(getRoot(rig).Position, pos)

	if path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		
		for i, wp in ipairs(waypoints) do
			if findClosestPlayer() then break end -- stop walking if we found someone to hunt
			
			rig.Humanoid:MoveTo(wp.Position)
			rig.Humanoid.MoveToFinished:Wait()
		end
	end

	pathing = false
end

--// MAIN ENGINE
-- using heartbeat instead of a while loop cuz its cleaner for AI logic.(and because it lowk sounds proffessional)
-- runs every frame but i added a tiny delay so it doesnt TANK the server
local lastUpdate = 0
RunService.Heartbeat:Connect(function()
	if tick() - lastUpdate < 0.2 then return end
	lastUpdate = tick()

	local target = findClosestPlayer()

	if target then
		initiateAttack(target)
		
		-- camera shake feedback
		local p = Players:GetPlayerFromCharacter(target)
		if p then Remotes.CameraShake:FireClient(p, "Light") end
	else
		-- if no ones around, just pick a random waypoint to walk to
		local nodes = workspace:FindFirstChild("Waypoints")
		if nodes and not pathing then
			local parts = nodes:GetChildren()
			local randomNode = parts[math.random(1, #parts)]
			if randomNode:IsA("BasePart") then
				walkTo(randomNode.Position)
			end
		end
	end
end)
