--[[
	advanced npc ai. 
	this script started as a super simple chase npc,
	but i kept adding stuff after testing 

	features:
	- patrols randomly
	- chases players if seen
	- remembers last position for a few seconds
	- uses pathfinding so it doesnt slam into walls forever
	- basic stuck detection because roblox humanoids are... special
	- attack system
	- footsteps + ambient sounds
	- optional debug mode

	if you use this for multiple npcs at once,
	my lawyer said that its not my fault you didnt use moduler(spelt that wrong </3) script.
]]

local PathfindingService = game:GetService("PathfindingService") --- just a service on roblox. 
local Players = game:GetService("Players")--- players
local RunService = game:GetService("RunService") -- runservice
local Debris = game:GetService("Debris")---debris, which deletes...

local npc = script.Parent-- im guessing that this is where the npc is?
local humanoid = npc:WaitForChild("Humanoid")-- humanoid
local root = npc:WaitForChild("HumanoidRootPart")
local head = npc:WaitForChild("Head")
-- keeping settings in one table makes balancing easier later.
-- instead of hunting random numbers across 500 lines of code.
-- // settings

local SETTINGS = {
	debug = true, --- determains should we debug or not.

	walkSpeed = 10,-- kinda self explanatory isnt it?
	chaseSpeed = 18,-- this too

	detectionRadius = 80,--- where the scawwy monster see that victim. then he will go num num num on their legs
	loseDistance = 120, --- if somehow the player managed to go 120+ studs away the monster is dumb and will look for other persons

	attackDistance = 4,---down here is pretty understandable and im tired of making comments. 
	attackDamage = 25,

	memoryTime = 8,

	stuckCheckDelay = 1.5,
	stuckDistance = 2,

	footstepDelay = 0.35,

	pathRetryLimit = 2,
}
-- currentState is mostly for organization and debugging.
-- the npc doesnt REALLY need states to function,
-- but it makes behavior easier to track while testing.
-- and also it looks professional.

-- // state vars

local currentState = "idle"
-- target stores the actual player object.
-- not just the character.
-- this is useful because characters respawn while players stay consistant.
local target = nil

local lastSeenPos = nil
local lastSeenTime = 0

local lastPosition = root.Position
local lastFootstep = 0

local isAttacking = false
local isPathfinding = false

local patrolPoints = {}

-- i dont like using globals for retry stuff
-- because debugging becomes annoying later
local retryCount = 0

-- // patrol points setup

-- if a folder called PatrolPoints exists,
-- the npc will randomly walk between them
local patrolFolder = workspace:FindFirstChild("PatrolPoints")

if patrolFolder then
	for _, point in ipairs(patrolFolder:GetChildren()) do
		if point:IsA("BasePart") then
			table.insert(patrolPoints, point)
		end
	end
end

-- // debug printing

local function debugPrint(...)
	if SETTINGS.debug then
		print("[NPC]", ...)
	end
end

-- // changing states

-- mostly for debugging honestly
-- makes it easier to see what the npc thinks its doing
local function setState(newState)
	if currentState ~= newState then
		debugPrint(currentState .. " -> " .. newState)
		currentState = newState
	end
end

-- // alive check

-- i separated this into its own function because i kept reusing the same checks everywhere
local function isPlayerAlive(player)
	if not player.Character then
		return false
	end

	local char = player.Character
	local hum = char:FindFirstChild("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")

	if hum and hrp and hum.Health > 0 then
		return true
	end

	return false
end

-- // closest player

-- this is simple magnitude checking.
-- technically not the most optimized solution ever,
-- but unless you have like 50 npcs at once its fine.
local function getClosestPlayer()
	local closestPlayer = nil
	local closestDistance = SETTINGS.detectionRadius

	for _, player in ipairs(Players:GetPlayers()) do
		if isPlayerAlive(player) then
			local char = player.Character
			local hrp = char:FindFirstChild("HumanoidRootPart")

			if hrp then
				local dist = (root.Position - hrp.Position).Magnitude

				if dist < closestDistance then
					closestDistance = dist
					closestPlayer = player
				end
			end
		end
	end

	return closestPlayer
end

-- // line of sight

-- without this the npc would detect players through walls which looked SOOO dumb
local function hasLineOfSight(character)
	local hrp = character:FindFirstChild("HumanoidRootPart")

	if not hrp then
		return false
	end

	local origin = head.Position
	local direction = hrp.Position - origin

	local params = RaycastParams.new()

	-- ignoring the npc itself otherwise
	-- the ray instantly hits its own body, we dont want that...... or do we?
	params.FilterDescendantsInstances = {npc}
	params.FilterType = Enum.RaycastFilterType.Blacklist

	local result = workspace:Raycast(origin, direction, params)

	if result then
		return result.Instance:IsDescendantOf(character)
	end

	return true
end

-- // path creation

-- originally i used humanoid:MoveTo directly
-- but the npc got stuck on literally everything
-- now i have chosen another way
local function createPath(destination)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentJumpHeight = 10, ---yeah btw change this to the hight of the rig. trust.
		AgentMaxSlope = 45
	})

	local success, err = pcall(function()
		path:ComputeAsync(root.Position, destination)
	end)

	if success and path.Status == Enum.PathStatus.Success then
		return path
	else
		debugPrint("path failed", err)
		return nil
	end
end

-- // debug waypoint visuals

local function showWaypoint(pos)
	if not SETTINGS.debug then
		return
	end

	local marker = Instance.new("Part")---makes a new waypoints and puts it right at pos. this way if the pathfinding is dumb again we will know what he did

	marker.Shape = Enum.PartType.Ball
	marker.Material = Enum.Material.Neon
	marker.Size = Vector3.new(0.4,0.4,0.4)

	marker.Anchored = true
	marker.CanCollide = false

	marker.Position = pos
	marker.Parent = workspace

	Debris:AddItem(marker, 1.5)
end

-- // movement

-- this function is honestly the core of the whole npc.
-- everything eventually funnels into here.

local function moveTo(destination)

	-- prevents overlapping path calls
	if isPathfinding then
		return false
	end

	isPathfinding = true

	local path = createPath(destination)

	if not path then
		isPathfinding = false
		return false
	end

	local waypoints = path:GetWaypoints()

	-- path.Blocked doesnt always save you,
	-- but it helps sometimes when doors close etc
	path.Blocked:Connect(function()
		debugPrint("path got blocked")

		if retryCount < SETTINGS.pathRetryLimit then
			retryCount += 1
			-- as you can see comments are getting less and less. this is because im really tired of always typing comments
			debugPrint("retrying path")

			isPathfinding = false
			moveTo(destination)
		end
	end)

	for _, waypoint in ipairs(waypoints) do

		showWaypoint(waypoint.Position)

		-- roblox pathfinding tells us
		-- when a jump is needed
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end

		humanoid:MoveTo(waypoint.Position)

		local reached = humanoid.MoveToFinished:Wait()

		if not reached then
			debugPrint("failed to reach waypoint")

			isPathfinding = false
			return false
		end
	end

	retryCount = 0
	isPathfinding = false

	return true
end

-- // stuck detection

-- humanoids randomly freezing on corners
-- is basically a roblox rite of passage
local function checkIfStuck()

	local movedDistance = (root.Position - lastPosition).Magnitude

	if movedDistance <= SETTINGS.stuckDistance then

		debugPrint("npc might be stuck")

		-- jumping actually fixes it surprisingly often
		humanoid.Jump = true

		return true
	end

	lastPosition = root.Position

	return false
end

-- // footsteps

-- this only plays while actually moving.
-- without a delay it sounded like a machine gun. 
local function playFootstep()

	if tick() - lastFootstep < SETTINGS.footstepDelay then
		return
	end

	lastFootstep = tick()

	local sound = Instance.new("Sound")

	sound.SoundId = "rbxassetid://123123123"----this doesnt work btw. i mean its obv but alot do not know
	sound.Volume = 0.3
	sound.Parent = root

	sound:Play()

	Debris:AddItem(sound, 2)
end

-- // attack logic

-- not super advanced combat,
-- but enough for a horror/survival npc
local function attackPlayer(player)

	if isAttacking then
		return
	end

	if not isPlayerAlive(player) then
		return
	end

	local char = player.Character
	local hum = char:FindFirstChild("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")

	if not hum or not hrp then
		return
	end

	local dist = (root.Position - hrp.Position).Magnitude

	if dist > SETTINGS.attackDistance then
		return
	end

	isAttacking = true

	debugPrint("attacking", player.Name)

	-- using old animation loading here mainly
	-- because it still works fine for this setup
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://10469630950"

	local track = humanoid:LoadAnimation(anim)

	track:Play()

	-- synced roughly with the hit frame
	task.wait(0.4)

	if isPlayerAlive(player) then
		hum:TakeDamage(SETTINGS.attackDamage)
	end

	task.wait(1)

	isAttacking = false
end

-- // patrol selection

local function getRandomPatrolPoint()

	if #patrolPoints <= 0 then
		return nil
	end

	return patrolPoints[math.random(1, #patrolPoints)]
end

-- // patrol behavior

local function patrol()

	setState("patrol")

	humanoid.WalkSpeed = SETTINGS.walkSpeed

	local point = getRandomPatrolPoint()

	if point then

		debugPrint("walking to patrol point:", point.Name)

		moveTo(point.Position)

		-- small pause makes movement feel less robotic
		task.wait(math.random(2,5))
	else
		task.wait(1)
	end
end

-- // chase behavior

local function chasePlayer(player)

	if not isPlayerAlive(player) then
		target = nil
		return
	end

	local char = player.Character
	local hrp = char:FindFirstChild("HumanoidRootPart")

	if not hrp then
		return
	end

	setState("chasing")

	humanoid.WalkSpeed = SETTINGS.chaseSpeed

	local dist = (root.Position - hrp.Position).Magnitude

	-- if target gets too far,
	-- npc gives up eventually
	if dist > SETTINGS.loseDistance then
		debugPrint("lost target")

		target = nil
		return
	end

	-- npc remembers where it last saw the player
	if hasLineOfSight(char) then
		lastSeenPos = hrp.Position
		lastSeenTime = tick()
	end

	if dist <= SETTINGS.attackDistance then
		attackPlayer(player)
	else
		moveTo(hrp.Position)
	end
end

-- // searching

-- this helps the npc feel less dumb.
-- instead of instantly forgetting the player,
-- it checks the last known spot first.
local function searchLastPosition()

	if not lastSeenPos then
		return
	end

	setState("searching")

	humanoid.WalkSpeed = SETTINGS.walkSpeed

	debugPrint("checking last seen position")

	moveTo(lastSeenPos)

	task.wait(2)

	if tick() - lastSeenTime >= SETTINGS.memoryTime then
		lastSeenPos = nil
	end
end

-- // idle

local function idle()
	setState("idle")
	task.wait(1)
end

-- // heartbeat loop

-- mostly handles stuff that needs constant updating
RunService.Heartbeat:Connect(function()

	if humanoid.MoveDirection.Magnitude > 0 then
		playFootstep()
	end

	-- making npc face the target constantly
	-- looks better during chasing
	if target and isPlayerAlive(target) then

		local char = target.Character
		local hrp = char:FindFirstChild("HumanoidRootPart")

		if hrp then

			local lookPos = Vector3.new(
				hrp.Position.X,
				root.Position.Y,
				hrp.Position.Z
			)

			root.CFrame = CFrame.lookAt(root.Position, lookPos)
		end
	end
end)

-- // stuck checking loop

task.spawn(function()

	while true do

		task.wait(SETTINGS.stuckCheckDelay)

		checkIfStuck()
	end
end)

-- // ambient sounds

-- i added this because complete silence
-- during patrols felt awkward in testing
-- these also dont work, you need to add your own. 
local ambientSounds = {
	"rbxassetid://9125719131",
	"rbxassetid://9125721022",
	"rbxassetid://9125723307"
}
--- you might be asking if these dont work how did i get the id? i didnt. i just mashed random numbers.
local function playAmbient()

	local sound = Instance.new("Sound")

	sound.SoundId = ambientSounds[math.random(1,#ambientSounds)]
	sound.Volume = 0.5
	sound.Parent = head

	sound:Play()

	Debris:AddItem(sound, 8)
end

task.spawn(function()

	while true do

		task.wait(math.random(15,35))

		playAmbient()
	end
end)

-- // main ai loop

-- i tried using fewer loops originally,
-- but separating behavior logic ended up cleaner
task.spawn(function()

	while true do

		task.wait(0.1)

		local closest = getClosestPlayer()

		if closest then

			local char = closest.Character

			if char and hasLineOfSight(char) then
				target = closest
			end
		end

		if target then
			chasePlayer(target)

		elseif lastSeenPos then
			searchLastPosition()

		elseif #patrolPoints > 0 then
			patrol()

		else
			idle()
		end
	end
end)

-- // death handling

humanoid.HealthChanged:Connect(function(health)

	if health <= 0 then

		setState("dead")

		debugPrint("npc died")

		return
	end
end)

debugPrint("npc ai loaded")
setState("ready")




----- THE END------
