local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local rig = script.Parent -- The Observer rig
local Remotes = game.ReplicatedStorage:WaitForChild("Remotes")

local DEBOUNCE_TIME = 3 -- seconds between attacks to prevent spam
local VISION_DISTANCE = 40
local ATTACK_DISTANCE = 5

local debounce = false
local currentTarget = nil
local currentPath = nil
local isMoving = false

-- === UTILITY FUNCTIONS === --

-- Print debug info safely
local function debugPrint(...)
	print("[Observer AI]:", ...)
end

-- Check if HumanoidRootPart exists
local function getHRP(character)
	if character and character:IsA("Model") then
		return character:FindFirstChild("HumanoidRootPart")
	end
	return nil
end

-- Raycast to check line of sight to target character
local function checkForCharacter(character)
	local myHRP = getHRP(rig)
	local targetHRP = getHRP(character)
	if not myHRP or not targetHRP then
		debugPrint("Missing HRP on rig or target")
		return false
	end

	local origin = myHRP.Position
	local direction = (targetHRP.Position - origin).Unit * VISION_DISTANCE

	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {rig}
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist

	local rayResult = workspace:Raycast(origin, direction, raycastParams)

	if rayResult and rayResult.Instance and rayResult.Instance:IsDescendantOf(character) then
		return true
	else
		return false
	end
end

-- Find nearest visible player character
local function findNearestPlayer()
	local nearestCharacter = nil
	local shortestDistance = math.huge

	for _, player in pairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local hrp = getHRP(character)
			local rigHRP = getHRP(rig)

			if hrp and rigHRP then
				local distance = (rigHRP.Position - hrp.Position).Magnitude
				if distance < shortestDistance and distance <= VISION_DISTANCE and checkForCharacter(character) then
					nearestCharacter = character
					shortestDistance = distance
				end
			end
		end
	end

	return nearestCharacter
end

-- Attempt to shake camera of player if close enough
local function tryShakeCamera(player)
	if not player then return end

	local character = player.Character
	if not character then return end

	local hrp = getHRP(character)
	local rigHRP = getHRP(rig)
	if hrp and rigHRP then
		local dist = (hrp.Position - rigHRP.Position).Magnitude
		if dist <= VISION_DISTANCE then
			Remotes.CameraShake:FireClient(player, "Light")
			debugPrint("Camera shake sent to", player.Name)
		end
	end
end

-- Attack logic: move close, jumpscare, kill, morph
local function attack(character)
	if debounce then return end
	debounce = true

	local rigHRP = getHRP(rig)
	local victimHRP = getHRP(character)
	if not rigHRP or not victimHRP then
		debounce = false
		return
	end

	local distance = (rigHRP.Position - victimHRP.Position).Magnitude

	if distance > ATTACK_DISTANCE then
		-- Move closer
		rig.Humanoid:MoveTo(victimHRP.Position)
		debugPrint("Moving to target:", character.Name)
		debounce = false
	else
		-- Close enough: attack!
		local victimHumanoid = character:FindFirstChildOfClass("Humanoid")
		local rigHumanoid = rig:FindFirstChildOfClass("Humanoid")

		if victimHumanoid and rigHumanoid then
			local player = Players:GetPlayerFromCharacter(character)
			if player then
				Remotes.Jumpscare:FireClient(player)
				debugPrint("Jumpscare triggered on player:", player.Name)
			end

			-- Play attack animation
			local animator = rigHumanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", rigHumanoid)
			local attackAnim = Instance.new("Animation")
			attackAnim.AnimationId = "rbxassetid://118559398898207" -- Your attack animation
			local animTrack = animator:LoadAnimation(attackAnim)
			animTrack.Priority = Enum.AnimationPriority.Action
			animTrack:Play()

			wait(0.5)

			-- Kill victim
			victimHumanoid.Health = 0

			wait(0.3)

			-- Morph into victim
			local description = victimHumanoid:GetAppliedDescription()
			rigHumanoid:ApplyDescription(description)
			rigHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

			debugPrint("Morph complete into:", character.Name)

			wait(DEBOUNCE_TIME) -- Cooldown after attack
		end
		debounce = false
	end
end

-- Calculate path to destination with pathfinding
local function calculatePath(destination)
	local params = {
		AgentHeight = 5.5,
		AgentRadius = 4,
		AgentCanJump = false
	}

	local path = PathfindingService:CreatePath(params)
	local rigHRP = getHRP(rig)
	if not rigHRP then
		debugPrint("No rig HRP for pathfinding")
		return nil
	end

	path:ComputeAsync(rigHRP.Position, destination)

	if path.Status == Enum.PathStatus.Success then
		debugPrint("Path computed successfully")
		return path
	else
		debugPrint("Failed to compute path")
		return nil
	end
end

-- Walk to destination by following waypoints
local function walkToDestination(destination)
	if isMoving then
		debugPrint("Already moving, skipping walkToDestination")
		return
	end

	isMoving = true

	local path = calculatePath(destination)
	if not path then
		-- Try simple MoveTo if pathfinding failed
		local rigHRP = getHRP(rig)
		if rigHRP then
			rig.Humanoid:MoveTo(destination - rigHRP.CFrame.LookVector * 10)
			debugPrint("Fallback MoveTo executed")
		end
		isMoving = false
		return
	end

	for _, waypoint in ipairs(path:GetWaypoints()) do
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			rig.Humanoid.Jump = true
		end

		rig.Humanoid:MoveTo(waypoint.Position)
		debugPrint("Moving to waypoint:", waypoint.Position)

		local reached = false
		local conn
		conn = rig.Humanoid.MoveToFinished:Connect(function(reachedSuccessfully)
			reached = reachedSuccessfully
		end)

		-- Wait until waypoint reached or timeout
		local timer = 0
		while not reached and timer < 5 do
			-- Check for new target to attack while moving
			local nearestPlayer = findNearestPlayer()
			if nearestPlayer then
				attack(nearestPlayer)
				local player = Players:GetPlayerFromCharacter(nearestPlayer)
				tryShakeCamera(player)
			end

			task.wait(0.1)
			timer = timer + 0.1
		end
		conn:Disconnect()
	end

	isMoving = false
end

-- === MAIN LOOP === --

while true do
	task.wait(0.1)

	-- Find nearest player in sight
	local target = findNearestPlayer()

	if target then
		currentTarget = target
		attack(target)
		local player = Players:GetPlayerFromCharacter(target)
		tryShakeCamera(player)
	else
		-- No player visible, roam randomly

		-- Get waypoints folder and children safely
		local waypointsFolder = workspace:FindFirstChild("Waypoints")
		if waypointsFolder then
			local waypoints = waypointsFolder:GetChildren()
			if #waypoints > 0 then
				local randomWaypoint = waypoints[math.random(1, #waypoints)]
				if randomWaypoint and randomWaypoint:IsA("BasePart") then
					walkToDestination(randomWaypoint.Position)
				else
					debugPrint("Random waypoint invalid")
				end
			else
				debugPrint("No waypoints found")
			end
		else
			debugPrint("Waypoints folder missing in workspace")
		end
	end
end
