---[Please note that this is an old project, so dont mind the intermiadite style sscripting lolz.]


local ReplicatedStorage = game:GetService("ReplicatedStorage")--refers to the replicatedstorage
local TweenService = game:GetService("TweenService")-- refers to the tween service
local Debris = game:GetService("Debris")-- refers to the debris service
local Players = game:GetService("Players")-- refers to the players

local events = ReplicatedStorage:WaitForChild("EventsFolder")-- waits for the folder to load in replicated storage. and makign a var called events

-- LAVA EVENT
events.Lava.Event:Connect(function()-- if the lava event is fired then 
	events.Dialogue:FireAllClients("GET UP THE TOWER BEFORE THE LAVA GETS YOU!") -- fires the dialogue event to all clients
	local model = events:WaitForChild("LavaEscape"):Clone() -- clones the lava model
	local lava = model:WaitForChild("Baseplate")-- waits for the baseplate
	model.Name = "LavaEscape" -- renames it
	model.Parent = workspace-- places it in the workspace

	lava.Anchored = true -- anchors the model

	local tweenInfo = TweenInfo.new( --- tween info
		299, -- duration
		Enum.EasingStyle.Cubic, -- easing style
		Enum.EasingDirection.Out-- easing direction
	)

	local startPos = lava.Size -- start size
	local goal = {Size = Vector3.new(startPos.X, 100, startPos.Z)} -- slowly making the model rise to give off the impression that lava is rising

	local tween = TweenService:Create(lava, tweenInfo, goal) -- create the tween
	tween:Play()-- play the tween

	-- cleanup after 30 seconds
	task.delay(30, function()
		if model then
			model:Destroy()
		end
	end)
end)

-- SWORD EVENT
events.Sword.Event:Connect(function() -- if the sword event is fired then 
	-- fires the dialogue event to all clients
	events.Dialogue:FireAllClients("one of us is a traitor and has a sword with him!")
	-- chooses a random player
	local model = game.ServerStorage.Items.Sword
	
	local plrs = Players:GetPlayers()-- gets all the players in Players
	if #plrs >= 1 then -- if the number is bigger than 1
		local chosen = plrs[math.random(1, #plrs)]-- chooses a random player
		local clone = model:Clone()-- clones the sword
		clone.Parent = chosen.Backpack-- places it in the backpack of the chosen player
			-- cleanup
		task.delay(30, function()
			if clone then
				clone:Destroy()
			end
		end)
	end
end)

-- METEOR SHOWER EVENT
events.MeteorShower.Event:Connect(function() -- if the meteor shower event is fired then 
	-- fires the dialogue event to all clients
	events.Dialogue:FireAllClients("OH NO! METEORS")
	local base = workspace:WaitForChild("Baseplate")-- gets the baseplate
	local model = events:WaitForChild("METEOR") -- gets the meteor model

	local duration = 30
	local interval = 1

	local function spawnMeteor() -- spawns a meteor
		local clone = model:Clone()
		clone.Parent = workspace
		clone.Anchored = false

		local size = base.Size-- gets the size of the baseplate
		local pos = base.Position -- gets the position of the baseplate
		local randomX = pos.X + math.random(-size.X/2, size.X/2) -- randomizes the x position
		local randomZ = pos.Z + math.random(-size.Z/2, size.Z/2)-- randomizes the z position
		local spawnY = pos.Y + 50-- spawns it 50 studs above the baseplate

		clone.Position = Vector3.new(randomX, spawnY, randomZ)-- spawns the meteor

		if clone:IsA("BasePart") then -- if the meteor is a part
			clone.AssemblyLinearVelocity = Vector3.new(0, -50, 0)
		end
		-- exposion
		clone.Touched:Connect(function(hit)
			if hit:IsDescendantOf(workspace) then
				local explosion = Instance.new("Explosion")
				explosion.Position = clone.Position
				explosion.BlastRadius = 10
				explosion.BlastPressure = 500000
				explosion.Parent = workspace

				clone:Destroy()
			end
		end)
		
		Debris:AddItem(clone, 10)
	end

	for i = 1, duration do
		task.delay(i * interval, spawnMeteor)
	end
end)
events.Tsunami.Event:Connect(function() -- if the tsunami event is fired then
	events.Dialogue:FireAllClients("TSUNAMI INCOMING! GET IN THE BUNKER!")

	local folder = events:WaitForChild("TsunamiFolder") -- gets the tsunami folder
	local wave = folder:FindFirstChild("Wave") -- gets the wave part
	wave.Anchored = true -- anchors the wave
	folder.Parent = workspace -- places the tsunami into workspace

	local TimeUntilRemove = 30 -- how long the tsunami lasts

	local goal = { Position = Vector3.new(-350, 0, 0)} -- target position for the wave

	local tif = TweenInfo.new(
		100, -- duration
		Enum.EasingStyle.Cubic, -- easing style
		Enum.EasingDirection.Out, -- easing direction
		0, -- repeat count
		false, -- reverses
		0 -- delay time
	)

	TweenService:Create(wave, tif, goal):Play() -- creates and plays the tween

	local plrs = game.Players -- gets the players service

	task.delay(30, function() -- waits before cleanup
		folder:Destroy()	-- destroys the tsunami

		for _, plr in pairs(plrs:GetChildren()) do -- loops through all players
			local char = plr.Character -- gets the character
			local hrp = char:FindFirstChild("HumanoidRootPart") -- gets humanoidrootpart

			if hrp then -- if hrp exists
				wait(0.01)
				hrp.CFrame = workspace.BaseplateTp.CFrame -- teleports player back
			end
		end
	end)
end)

events.Landmine.Event:Connect(function() -- if the landmine event is fired then
	events.Dialogue:FireAllClients("CAREFUL NOT TO EXPLODE, WATCH YOUR STEPS")

	local bomb = events.Bomb -- gets the bomb object
	bomb.Parent = workspace -- places it into workspace

	task.delay(30, function() -- cleanup after 30 seconds
		bomb:Destroy()
	end)
end)

events.LOWGRAV.Event:Connect(function() -- if the low gravity event is fired then
	events.Dialogue:FireAllClients("GRAVITY HAS BEEN CHANGED, BE CAREFUL")

	local grav = workspace.Gravity -- stores original gravity

	workspace.Gravity = 50 -- lowers gravity

	wait(30) -- waits 30 seconds

	workspace.Gravity = 196.2 -- restores normal gravity
end)

events.KILLER.Event:Connect(function() -- if the killer event is fired then
	local killer = events.Noob:Clone() -- clones the killer npc

	events.Dialogue:FireAllClients("A KILLER IS ON THE LOOSE! DON'T DIE")

	killer.Parent = workspace -- places the killer in workspace

	task.wait(30) -- waits 30 seconds

	killer.Parent = events -- stores the killer back
end)

local Players = game:GetService("Players") -- refers to the players service
local ReplicatedStorage = game:GetService("ReplicatedStorage") -- refers to replicated storage

local sanityremote = ReplicatedStorage.EventsFolder:WaitForChild("SANITY") -- remote event for sanity updates
local jumpjump = ReplicatedStorage.EventsFolder:WaitForChild("JUMPJUMP") -- remote event for sanity death effect

local REGEN_RATE = 0 -- sanity regeneration amount
local REGEN_DELAY = 0 -- delay before sanity regeneration

Players.PlayerAdded:Connect(function(plr) -- when a player joins

	-- creates stats folder
	local stats = Instance.new("Folder")
	stats.Name = "Stats"
	stats.Parent = plr

	-- creates sanity value
	local sanity = Instance.new("NumberValue")
	sanity.Name = "Sanity"
	sanity.Value = 100
	sanity.Parent = stats

	local lastDamageTime = 0 -- tracks when player last took damage
	local zeroTriggered = false -- prevents zero sanity from triggering multiple times

	local function setupCharacter(chr) -- setup function for character
		local hum = chr:WaitForChild("Humanoid") -- gets humanoid

		local lastHealth = hum.Health -- stores previous health

		-- resets sanity on spawn
		sanity.Value = 100
		sanityremote:FireClient(plr, sanity.Value)

		zeroTriggered = false

		-- listens for health changes
		hum.HealthChanged:Connect(function(newHealth)

			if newHealth < lastHealth then -- if player took damage

				local dmg = lastHealth - newHealth -- calculates damage taken

				local loss = dmg * 0.75 -- converts damage into sanity loss

				sanity.Value = math.max(0, sanity.Value - loss) -- decreases sanity

				lastDamageTime = time() -- updates last damage timestamp

				sanityremote:FireClient(plr, sanity.Value) -- updates client ui
			end

			lastHealth = newHealth -- updates stored health
		end)

		hum.Died:Connect(function() -- when player dies

			sanity.Value = 100 -- resets sanity

			sanityremote:FireClient(plr, sanity.Value)

			zeroTriggered = false -- resets trigger
		end)
	end

	-- setup first spawn
	if plr.Character then
		setupCharacter(plr.Character)
	end

	plr.CharacterAdded:Connect(setupCharacter) -- setup future respawns

	-- sanity regeneration loop
	task.spawn(function()

		while plr.Parent do -- while player exists

			task.wait(1)

			if sanity.Value < 100 and (time() - lastDamageTime) >= REGEN_DELAY then

				sanity.Value = math.min(100, sanity.Value + REGEN_RATE) -- regenerates sanity

				sanityremote:FireClient(plr, sanity.Value) -- updates client
			end

			-- if sanity reaches zero
			if sanity.Value <= 0 and not zeroTriggered then

				zeroTriggered = true -- prevents retriggering

				jumpjump:FireClient(plr) -- fires hallucination/jumpscare

				task.wait(7)

				if plr.Parent then -- if player still exists
					plr:Kick("👁👁...") -- kicks the player
				end
			end
		end
	end)
end)
