local Players = game:GetService("Players")
local Pathfinding = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Monster = {}
Monster.__index = Monster

-- Settings
local VIEW_DIST = 50
local FOV = 120
local WALK_SPEED = 12
local CHASE_SPEED = 22
local ATTACK_DIST = 6
local KILL_COOLDOWN = 5

-- Placeholders (Replace with your actual IDs)
local ANIM_KILL = "rbxassetid://1212121212"
local SFX_MORPH = "rbxassetid://123456789"
local SFX_STEP = "rbxassetid://987654321"

function Monster.new(rigModel)
	local self = setmetatable({}, Monster)
	
	self.rig = rigModel
	self.hum = rigModel:WaitForChild("Humanoid")
	self.root = rigModel:WaitForChild("HumanoidRootPart")
	self.remotes = game.ReplicatedStorage:WaitForChild("Remotes")
	
	self.state = "IDLE"
	self.targetPlr = nil
	self.lastKill = 0
	self.lastTick = 0
	self.isPathing = false
	
	self._connections = {}
	
	self:Init()
	return self
end

function Monster:PlaySfx(soundId, volume)
	local sfx = Instance.new("Sound")
	sfx.SoundId = soundId
	sfx.Volume = volume or 1
	sfx.PlaybackSpeed = math.clamp(math.random(90, 110) / 100, 0.9, 1.1)
	sfx.Parent = self.root
	sfx:Play()
	Debris:AddItem(sfx, 3)
end

function Monster:CanSee(targetChar)
	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetRoot then return false end

	local rayDirection = (targetRoot.Position - self.root.Position)
	if rayDirection.Magnitude > VIEW_DIST then return false end

	local angle = math.deg(math.acos(self.root.CFrame.LookVector:Dot(rayDirection.Unit)))
	if angle > (FOV / 2) then return false end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {self.rig, targetChar}
	params.FilterType = Enum.RaycastFilterType.Exclude

	return workspace:Raycast(self.root.Position, rayDirection, params) == nil
end

function Monster:FindTarget()
	local closestTarget = nil
	local shortestDist = VIEW_DIST

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local pRoot = char and char:FindFirstChild("HumanoidRootPart")
		local pHum = char and char:FindFirstChild("Humanoid")

		if pRoot and pHum and pHum.Health > 0 then
			local dist = (self.root.Position - pRoot.Position).Magnitude
			if dist < shortestDist and self:CanSee(char) then
				shortestDist = dist
				closestTarget = player
			end
		end
	end
	return closestTarget
end

function Monster:Init()
	local lastStepTime = 0
	
	local heartbeat = RunService.Heartbeat:Connect(function()
		if os.clock() - self.lastTick < 0.1 then return end
		self.lastTick = os.clock()
		
		-- Simple human-written step timing logic
		if self.hum.MoveDirection.Magnitude > 0 then
			local currentSpeed = self.hum.WalkSpeed
			local stepInterval = currentSpeed > WALK_SPEED and 0.3 or 0.5
			
			if os.clock() - lastStepTime >= stepInterval then
				local stepVol = currentSpeed > WALK_SPEED and 0.4 or 0.2
				self:PlaySfx(SFX_STEP, stepVol)
				lastStepTime = os.clock()
			end
		end
		
		-- State Machine logic goes here
		local potentialTarget = self:FindTarget()
		if potentialTarget then
			self.targetPlr = potentialTarget
			self.state = "CHASE"
			self.hum.WalkSpeed = CHASE_SPEED
		else
			self.targetPlr = nil
			self.state = "IDLE"
			self.hum.WalkSpeed = WALK_SPEED
		end
	end)
	
	table.insert(self._connections, heartbeat)
end

function Monster:Destroy()
	for _, connection in ipairs(self._connections) do
		if connection then connection:Disconnect() end
	end
	
	if self.rig then self.rig:Destroy() end
	setmetatable(self, nil)
end

return Monster
