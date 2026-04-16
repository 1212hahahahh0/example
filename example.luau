--// SERVICES
-- these are core roblox systems. we cache them once so we dont keep asking for them later
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")

--// MAIN REFERENCES
-- the npc itself and the remotes used to talk to the client
local rig = script.Parent
local Remotes = game.ReplicatedStorage:WaitForChild("Remotes")

--// SETTINGS
-- these control behavior, not logic. changing them changes how aggressive or aware the npc feels
local DEBOUNCE_TIME = 3
local VISION_DISTANCE = 40
local ATTACK_DISTANCE = 5

--// STATE
-- these track what the npc is currently doing so it doesnt conflict with itself
local debounce = false
local isMoving = false

--// DEBUG
-- central print so if you remove debugging later, you only remove it here
local function debugPrint(...)
	print("[Observer AI]:", ...)
end

--// CORE POSITION ACCESS
-- everything in this script depends on positions. instead of trusting every model blindly,
-- we safely extract the root part. if its missing, we stop early to avoid errors spreading
local function getHRP(character)
	if character and character:IsA("Model") then
		return character:FindFirstChild("HumanoidRootPart")
	end
	return nil
end

--// LINE OF SIGHT CHECK
-- distance alone is not enough. this function makes the npc "commit" to seeing something
-- by verifying there is no obstruction between it and the target
--
-- the important idea here is: the npc only reacts to what it can confirm visually,
-- not just what exists in range. this prevents it from feeling unfair
local function canSee(character)
	local myHRP = getHRP(rig)
	local targetHRP = getHRP(character)

	if not myHRP or not targetHRP then return false end

	local direction = (targetHRP.Position - myHRP.Position)

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {rig}
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(myHRP.Position, direction, rayParams)

	return result and result.Instance and result.Instance:IsDescendantOf(character)
end

--// TARGET SELECTION
-- instead of locking onto a random player, the npc constantly reevaluates the world
-- every loop. this makes its behavior feel reactive rather than scripted
--
-- the "nearest visible" rule gives it a simple priority system:
-- closer targets are more important, but only if they are actually visible
local function getNearestPlayer()
	local closest = nil
	local shortest = math.huge

	local rigHRP = getHRP(rig)
	if not rigHRP then return nil end

	for _, player in pairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = getHRP(char)

		if hrp then
			local dist = (rigHRP.Position - hrp.Position).Magnitude

			if dist < shortest and dist <= VISION_DISTANCE and canSee(char) then
				closest = char
				shortest = dist
			end
		end
	end

	return closest
end

--// PLAYER FEEDBACK
-- the npc doesnt just act, it also signals its presence.
-- this creates pressure on the player before the actual attack happens
local function shakePlayer(player)
	if not player then return end

	local char = player.Character
	local hrp = getHRP(char)
	local rigHRP = getHRP(rig)

	if hrp and rigHRP then
		local dist = (hrp.Position - rigHRP.Position).Magnitude
		if dist <= VISION_DISTANCE then
			Remotes.CameraShake:FireClient(player, "Light")
		end
	end
end

--// ATTACK SYSTEM
-- this function is designed to be interrupt-safe.
-- debounce prevents overlapping attacks, which would otherwise break animations and logic
--
-- the flow is intentional:
-- 1. check distance
-- 2. if far, move instead of attacking
-- 3. if close, commit fully to attack sequence
--
-- this separation keeps behavior predictable and avoids half-executed actions
local function attack(character)
	if debounce then return end
	debounce = true

	local rigHRP = getHRP(rig)
	local targetHRP = getHRP(character)

	if not rigHRP or not targetHRP then
		debounce = false
		return
	end

	local dist = (rigHRP.Position - targetHRP.Position).Magnitude

	-- movement is treated as a continuation of attack intent,
	-- not a separate system. this is why it happens here
	if dist > ATTACK_DISTANCE then
		rig.Humanoid:MoveTo(targetHRP.Position)
		debounce = false
		return
	end

	local victimHum = character:FindFirstChildOfClass("Humanoid")
	local rigHum = rig:FindFirstChildOfClass("Humanoid")

	if victimHum and rigHum then
		local player = Players:GetPlayerFromCharacter(character)

		if player then
			Remotes.Jumpscare:FireClient(player)
		end

		local animator = rigHum:FindFirstChildOfClass("Animator") or Instance.new("Animator", rigHum)

		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://118559398898207"

		local track = animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action
		track:Play()

		task.wait(0.5)

		victimHum.Health = 0

		task.wait(0.3)

		-- morphing copies the victim appearance after the attack finishes.
		-- this happens after the kill so the visual change feels like a result,
		-- not something happening mid-action
		local desc = victimHum:GetAppliedDescription()
		rigHum:ApplyDescription(desc)
		rigHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

		debugPrint("morphed into", character.Name)

		task.wait(DEBOUNCE_TIME)
	end

	debounce = false
end

--// PATHFINDING MOVEMENT
-- this is separate from attack movement because it handles "idle behavior"
--
-- the npc doesnt stand still when no players are found.
-- instead, it keeps moving so that eventually it enters a player's space
--
-- while moving, it still checks for targets. this is important:
-- movement never blocks awareness
local function goTo(position)
	if isMoving then return end
	isMoving = true

	local rigHRP = getHRP(rig)
	if not rigHRP then
		isMoving = false
		return
	end

	local path = PathfindingService:CreatePath({
		AgentHeight = 5,
		AgentRadius = 3,
		AgentCanJump = false
	})

	path:ComputeAsync(rigHRP.Position, position)

	if path.Status ~= Enum.PathStatus.Success then
		rig.Humanoid:MoveTo(position)
		isMoving = false
		return
	end

	for _, waypoint in ipairs(path:GetWaypoints()) do
		rig.Humanoid:MoveTo(waypoint.Position)

		local reached = false
		local conn

		conn = rig.Humanoid.MoveToFinished:Connect(function()
			reached = true
		end)

		local timer = 0

		-- during movement, the npc constantly rechecks for targets.
		-- this allows it to "change its mind" mid-path
		while not reached and timer < 5 do
			local target = getNearestPlayer()

			if target then
				attack(target)

				local player = Players:GetPlayerFromCharacter(target)
				shakePlayer(player)
			end

			task.wait(0.1)
			timer += 0.1
		end

		conn:Disconnect()
	end

	isMoving = false
end

--// MAIN LOOP
-- this acts as the decision layer.
-- every cycle, the npc asks:
-- "is there a valid target right now?"
--
-- if yes, it switches into aggressive behavior
-- if not, it continues roaming to eventually create encounters
while true do
	task.wait(0.1)

	local target = getNearestPlayer()

	if target then
		attack(target)

		local player = Players:GetPlayerFromCharacter(target)
		shakePlayer(player)
	else
		local folder = workspace:FindFirstChild("Waypoints")

		if folder then
			local points = folder:GetChildren()

			if #points > 0 then
				local randomPoint = points[math.random(1, #points)]

				if randomPoint:IsA("BasePart") then
					goTo(randomPoint.Position)
				end
			end
		end
	end
end
