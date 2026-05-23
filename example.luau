local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local events = ReplicatedStorage:WaitForChild("EventsFolder")
local sanityRemote = events:WaitForChild("SANITY")
local jumpjump = events:WaitForChild("JUMPJUMP")

local REGEN_RATE = 1 -- sanity points restored per tick
local REGEN_DELAY = 5 -- seconds after taking damage before regen resumes

-- SanityManager handles all sanity state for a single player instance
local SanityManager = {}
SanityManager.__index = SanityManager

-- creates a new SanityManager, builds the Stats folder and Sanity value under the player
function SanityManager.new(player)
	local self = setmetatable({}, SanityManager)
	self.player = player
	self.sanity = Instance.new("NumberValue")
	self.sanity.Name = "Sanity"
	self.sanity.Value = 100
	self.lastDamageTime = 0
	self.zeroTriggered = false

	local stats = Instance.new("Folder")
	stats.Name = "Stats"
	stats.Parent = player
	self.sanity.Parent = stats

	return self
end

-- sets the sanity value and syncs it to the client UI in one call
function SanityManager:update(value)
	self.sanity.Value = value
	sanityRemote:FireClient(self.player, value)
end

-- resets sanity to 100 and clears the zero trigger flag
function SanityManager:reset()
	self.zeroTriggered = false
	self:update(100)
end

-- converts raw damage into a 75% sanity loss and stamps the damage time for regen delay
function SanityManager:takeDamage(amount)
	local loss = amount * 0.75
	self:update(math.max(0, self.sanity.Value - loss))
	self.lastDamageTime = time()
end

-- wires up HealthChanged and Died listeners each time the character spawns
function SanityManager:setupCharacter(character)
	local humanoid = character:WaitForChild("Humanoid")
	local lastHealth = humanoid.Health

	self:reset()

	humanoid.HealthChanged:Connect(function(newHealth)
		if newHealth < lastHealth then
			self:takeDamage(lastHealth - newHealth)
		end
		lastHealth = newHealth
	end)

	humanoid.Died:Connect(function()
		self:reset()
	end)
end

-- runs a per-second loop that handles regen and zero-sanity punishment
function SanityManager:startRegenLoop()
	task.spawn(function()
		while self.player.Parent do
			task.wait(1)

			if self.sanity.Value < 100 and (time() - self.lastDamageTime) >= REGEN_DELAY then
				self:update(math.min(100, self.sanity.Value + REGEN_RATE))
			end

			-- fires a jumpscare to the client then kicks after a short delay
			if self.sanity.Value <= 0 and not self.zeroTriggered then
				self.zeroTriggered = true
				jumpjump:FireClient(self.player)
				task.wait(7)
				if self.player.Parent then
					self.player:Kick("👁👁...")
				end
			end
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	local manager = SanityManager.new(player)

	if player.Character then
		manager:setupCharacter(player.Character)
	end

	-- re-runs character setup on every respawn
	player.CharacterAdded:Connect(function(character)
		manager:setupCharacter(character)
	end)

	manager:startRegenLoop()
end)

-- LAVA EVENT
events.Lava.Event:Connect(function()
	events.Dialogue:FireAllClients("GET UP THE TOWER BEFORE THE LAVA GETS YOU!")

	local model = events:WaitForChild("LavaEscape"):Clone()
	local lava = model:WaitForChild("Baseplate")
	model.Name = "LavaEscape"
	model.Parent = workspace
	lava.Anchored = true

	-- tweens the baseplate's Y size upward to simulate lava rising
	local startSize = lava.Size
	local tween = TweenService:Create(lava, TweenInfo.new(299, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
		Size = Vector3.new(startSize.X, 100, startSize.Z)
	})
	tween:Play()

	task.delay(30, function()
		if model and model.Parent then
			model:Destroy()
		end
	end)
end)

-- SWORD EVENT
events.Sword.Event:Connect(function()
	events.Dialogue:FireAllClients("one of us is a traitor and has a sword with him!")

	local plrs = Players:GetPlayers()
	if #plrs >= 1 then
		-- picks a random player and drops the sword into their backpack
		local chosen = plrs[math.random(1, #plrs)]
		local clone = game.ServerStorage.Items.Sword:Clone()
		clone.Parent = chosen.Backpack

		task.delay(30, function()
			if clone and clone.Parent then
				clone:Destroy()
			end
		end)
	end
end)

-- METEOR SHOWER EVENT
events.MeteorShower.Event:Connect(function()
	events.Dialogue:FireAllClients("OH NO! METEORS")

	local base = workspace:WaitForChild("Baseplate")
	local model = events:WaitForChild("METEOR")

	local function spawnMeteor()
		local clone = model:Clone()
		clone.Parent = workspace
		clone.Anchored = false

		-- scatters spawn points randomly across the baseplate surface
		local size = base.Size
		local pos = base.Position
		clone.Position = Vector3.new(
			pos.X + math.random(-size.X / 2, size.X / 2),
			pos.Y + 50,
			pos.Z + math.random(-size.Z / 2, size.Z / 2)
		)

		if clone:IsA("BasePart") then
			clone.AssemblyLinearVelocity = Vector3.new(0, -50, 0)
		end
		-- debounce prevents the explosion from firing more than once per meteor
		local exploded = false
		clone.Touched:Connect(function(hit)
			if exploded or not hit:IsDescendantOf(workspace) then return end
			exploded = true
			local explosion = Instance.new("Explosion")
			explosion.Position = clone.Position
			explosion.BlastRadius = 10
			explosion.BlastPressure = 500000
			explosion.Parent = workspace
			clone:Destroy()
		end)
		Debris:AddItem(clone, 10)
	end
	-- staggers one meteor per second over 30 seconds
	for i = 1, 30 do
		task.delay(i, spawnMeteor)
	end
end)
-- TSUNAMI EVENT
events.Tsunami.Event:Connect(function()
	events.Dialogue:FireAllClients("TSUNAMI INCOMING! GET IN THE BUNKER!")
	-- clones the folder so the original stays intact for future rounds
	local folder = events:WaitForChild("TsunamiFolder"):Clone()
	local wave = folder:FindFirstChild("Wave")
	wave.Anchored = true
	folder.Parent = workspace
	-- slides the wave across the map using a tween
	TweenService:Create(wave, TweenInfo.new(100, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
		Position = Vector3.new(-350, 0, 0)
	}):Play()
	task.delay(30, function()
		folder:Destroy()
		-- teleports all players back to the designated spawn point after the wave clears
		for _, plr in Players:GetPlayers() do
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				task.wait(0.01)
				hrp.CFrame = workspace.BaseplateTp.CFrame
			end
		end
	end)
end)
-- LANDMINE EVENT
events.Landmine.Event:Connect(function()
	events.Dialogue:FireAllClients("CAREFUL NOT TO EXPLODE, WATCH YOUR STEPS")
	-- clones the bomb so the original stays in events for future rounds
	local bomb = events.Bomb:Clone()
	bomb.Parent = workspace
	task.delay(30, function()
		if bomb and bomb.Parent then
			bomb:Destroy()
		end
	end)
end)
-- LOW GRAVITY EVENT
events.LOWGRAV.Event:Connect(function()
	events.Dialogue:FireAllClients("GRAVITY HAS BEEN CHANGED, BE CAREFUL")
	-- stores the original gravity so it can be restored exactly after the event
	local original = workspace.Gravity
	workspace.Gravity = 50
	task.wait(30)
	workspace.Gravity = original
end)
-- KILLER EVENT
events.KILLER.Event:Connect(function()
	events.Dialogue:FireAllClients("A KILLER IS ON THE LOOSE! DON'T DIE")
	-- clones the NPC so the original stays in events for future rounds
	local killer = events.Noob:Clone()
	killer.Parent = workspace
	task.wait(30)
	killer:Destroy()
end)
