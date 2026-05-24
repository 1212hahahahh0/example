-- ok so this is the main server script lol
-- handles sanity, events, all that stuff ik its a lot
-- if i get denied again, i will cry. 
-- r oui c re us right neow
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService") -- for smoooth animations n stuff
local Debris = game:GetService("Debris") -- auto cleans up parts so server doesnt die lmao
local Players = game:GetService("Players") -- u kno wat this is

-- grabbing the events folder from replicated storage, waitforchild so it doesnt error on load
local events = ReplicatedStorage:WaitForChild("EventsFolder")
local sanityRemote = events:WaitForChild("SANITY") -- fires to client to update the sanity bar ui
local jumpjump = events:WaitForChild("JUMPJUMP") -- triggers the jumpscare on client when sanity hits 0

-- all the tuneable numbers in one place so u dont have 2 dig thru the whole script
-- change these if u want 2 tweak balence or watever
local REGEN_RATE = 1 -- sanity pts per tick, 1 per sec rn
local REGEN_DELAY = 5 -- secs after last dmg b4 regen kicks in
local MAX_SANITY = 100 -- full sanity lol
local MIN_SANITY = 0 -- floor, cant go below this
local DAMAGE_MULTIPLIER = 0.75 -- hp dmg * this = sanity loss, so 75% conversion
local KICK_DELAY = 7 -- secs between jumpscare firing and actual kick, give the anim time 2 play
local EVENT_DURATION = 30 -- how long most events last in secs
local METEOR_COUNT = 30 -- total meteors per shower event, 1 per sec
local METEOR_SPEED = -50 -- downward velocity on meteors, negative = down ik its confusing
local METEOR_BLAST_RADIUS = 10 -- explosion radius in studs
local METEOR_BLAST_PRESSURE = 500000 -- how hard the explosion yeets things lmao
local METEOR_HEIGHT_OFFSET = 50 -- how far above baseplate meteors spawn
local LOW_GRAV_VALUE = 50 -- gravity during low grav event, default is 196.2 fyi
local TSUNAMI_TARGET_X = -350 -- where the wave tweens 2 on the x axis
local LAVA_TWEEN_TIME = 299 -- almost 5 mins lol, lava rises rlly slow
local TSUNAMI_TWEEN_TIME = 100 -- secs 4 wave 2 cross the map
local LAVA_MAX_HEIGHT = 100 -- max Y size the lava baseplate grows 2
local SWORD_MIN_PLAYERS = 1 -- min players needed 2 run sword event, so 1 = always runs
local METEOR_DEBRIS_TIMEOUT = 10 -- secs b4 debris service nukes the meteor if it didnt explode
local TSUNAMI_TELEPORT_DELAY = 0.01 -- tiny wait b4 each tp so it doesnt all happen at once
local EASING_STYLE = Enum.EasingStyle.Cubic -- easing style 4 tweens, cubic looks nice
local EASING_DIRECTION = Enum.EasingDirection.Out -- eases out, starts fast slows down
local LAVA_EVENT_NAME = "LavaEscape" -- name of the lava model in events folder
local WAVE_PART_NAME = "Wave" -- name of the wave part inside tsunami folder
local TSUNAMI_FOLDER_NAME = "TsunamiFolder" -- folder name ik obv
local METEOR_MODEL_NAME = "METEOR" -- the meteor template part stored in events
local BASEPLATE_NAME = "Baseplate" -- name of the main baseplate in workspace
local BASEPLATE_TP_NAME = "BaseplateTp" -- the tp destination part after tsunami clears
local STATS_FOLDER_NAME = "Stats" -- folder we make under the player 2 store values
local SANITY_VALUE_NAME = "Sanity" -- name of the numbervalue inside stats folder

-- SanityManager is a class (well, lua table w metatable lol) that manages 1 players sanity
-- each player gets their own instance of this so state doesnt bleed between players
local SanityManager = {}
SanityManager.__index = SanityManager -- standard metatable oop pattern, google it if ur confuzed

-- constructor, call this w a player obj 2 make a new manager
-- sets up the Stats folder + Sanity NumberValue under the player
function SanityManager.new(player)
	local self = setmetatable({}, SanityManager) -- makes new tbl and points index 2 SanityManager
	self.player = player -- store ref 2 the player
	self.sanity = Instance.new("NumberValue") -- the actual sanity value stored in game hierarchy
	self.sanity.Name = "Sanity"
	self.sanity.Value = MAX_SANITY -- starts full obvs
	self.lastDamageTime = 0 -- tracks wen last dmg happened 4 regen delay calc
	self.zeroTriggered = false -- flag so we dont fire jumpscare 100 times lmao

	local stats = Instance.new("Folder") -- container folder under player
	stats.Name = "Stats"
	stats.Parent = player -- parented 2 player so scripts can find it
	self.sanity.Parent = stats -- sanity lives inside stats

	return self
end

-- updates the sanity value AND syncs 2 client in 1 call
-- always use this instead of setting .Value directly or client wont kno abt it
function SanityManager:update(value)
	self.sanity.Value = value
	sanityRemote:FireClient(self.player, value) -- tells the client ui 2 update
end

-- resets sanity back 2 100 and clears the zero flag
-- called on spawn and on death so each life starts fresh
function SanityManager:reset()
	self.zeroTriggered = false -- clear flag so jumpscare can fire again next time
	self:update(MAX_SANITY)
end

-- simple getter so we dont access .sanity.Value everywhere lol
function SanityManager:getSanity()
	return self.sanity.Value
end

-- checks if player is still in game, used 2 stop loops wen they leave
function SanityManager:isAlive()
	return self.player and self.player.Parent ~= nil -- parent is nil wen player leaves
end

-- converts hp damage 2 sanity loss using the multiplier
-- stamps the time so regen delay resets on each hit
function SanityManager:takeDamage(amount)
	local loss = amount * DAMAGE_MULTIPLIER -- 75% of hp dmg becomes sanity loss
	local newValue = math.max(MIN_SANITY, self:getSanity() - loss) -- clamp 2 0 floor
	self:update(newValue)
	self.lastDamageTime = time() -- reset regen delay timer
end

-- returns true if sanity is below max AND enough time has passed since last dmg
-- used by regen loop 2 decide whether 2 regen this tick
function SanityManager:canRegen()
	return self:getSanity() < MAX_SANITY and (time() - self.lastDamageTime) >= REGEN_DELAY
end

-- wires up health listeners on the character model
-- called every spawn bc character gets replaced on respawn, old conections die w it
function SanityManager:setupCharacter(character)
	local humanoid = character:WaitForChild("Humanoid") -- wait 4 it just in case
	local lastHealth = humanoid.Health -- track prev health 2 calc delta

	self:reset() -- fresh sanity on each spawn

	-- fires whenever hp changes, if it went down we take sanity dmg
	humanoid.HealthChanged:Connect(function(newHealth)
		if newHealth < lastHealth then
			self:takeDamage(lastHealth - newHealth) -- delta = actual dmg taken
		end
		lastHealth = newHealth -- update 4 next comparison
	end)

	-- on death just reset, next spawn will call setupCharacter again anyway
	humanoid.Died:Connect(function()
		self:reset()
	end)
end

-- handles the 0 sanity punishment, separated from regen loop so its cleaner
-- fires jumpscare then kicks after delay, flag prevents it running more than once
function SanityManager:handleZeroSanity()
	if self:getSanity() <= MIN_SANITY and not self.zeroTriggered then
		self.zeroTriggered = true -- set immediately so concurrent ticks dont double fire
		jumpjump:FireClient(self.player) -- plays the jumpscare on client side
		task.wait(KICK_DELAY) -- wait 4 anim 2 play out b4 kicking
		if self:isAlive() then -- check they didnt leave during the wait lol
			self.player:Kick("\240\159\145\129\240\159\145\129...") -- bye lmao
		end
	end
end

-- spawns a background thread that ticks every sec 4 regen + zero sanity check
-- loop exits automaticaly wen player leaves bc isAlive() returns false
function SanityManager:startRegenLoop()
	task.spawn(function() -- task.spawn so it doesnt yield the main thread
		while self:isAlive() do
			task.wait(1) -- tick every 1 sec

			if self:canRegen() then -- only regen if conditions met
				self:update(math.min(MAX_SANITY, self:getSanity() + REGEN_RATE)) -- clamp 2 max
			end

			self:handleZeroSanity() -- check if we need 2 yeet the player
		end
	end)
end

-- helper that builds a TweenInfo w our default easing style n direction
-- saves typing the same Enum.EasingStyle.Cubic thing everwhere lol
local function makeTweenInfo(duration)
	return TweenInfo.new(duration, EASING_STYLE, EASING_DIRECTION)
end

-- helper 2 destroy an instance after a delay, checks parent so it doesnt error
-- used at end of most events 2 clean up cloned models
local function destroyAfter(instance, delay)
	task.delay(delay, function()
		if instance and instance.Parent then -- might already b gone, check first
			instance:Destroy()
		end
	end)
end

-- sets up a players sanity manager and hooks into character spawns
-- pulled into its own func so PlayerAdded is cleaner
local function setupPlayer(player)
	local manager = SanityManager.new(player) -- make sanity manager 4 this player

	if player.Character then -- character might already exist if they joined weird
		manager:setupCharacter(player.Character)
	end

	-- fires every respawn, re-runs setup bc character is a new model each time
	player.CharacterAdded:Connect(function(character)
		manager:setupCharacter(character)
	end)

	manager:startRegenLoop() -- kick off the per-sec background loop
end

-- runs setupPlayer 4 every new player that joins
Players.PlayerAdded:Connect(setupPlayer)

-- LAVA EVENT
-- rises a baseplate from below 2 simulate lava coming up
-- players need 2 climb the tower or they die lol
events.Lava.Event:Connect(function()
	events.Dialogue:FireAllClients("GET UP THE TOWER BEFORE THE LAVA GETS YOU!")

	-- clone the model from events so the original stays 4 next round
	local model = events:WaitForChild(LAVA_EVENT_NAME):Clone()
	local lava = model:WaitForChild(BASEPLATE_NAME) -- the part that rises
	model.Name = LAVA_EVENT_NAME
	model.Parent = workspace
	lava.Anchored = true -- must b anchored or physics will just drop it lmao

	-- tween the Y size upward, X and Z stay the same so it only grows vertically
	local startSize = lava.Size
	local tween = TweenService:Create(lava, makeTweenInfo(LAVA_TWEEN_TIME), {
		Size = Vector3.new(startSize.X, LAVA_MAX_HEIGHT, startSize.Z)
	})
	tween:Play()

	destroyAfter(model, EVENT_DURATION) -- clean up after 30 secs
end)

-- SWORD EVENT
-- picks a rando player and shoves a sword in their backpack
-- they r the traitor now, everyone else better watch out lol
events.Sword.Event:Connect(function()
	events.Dialogue:FireAllClients("one of us is a traitor and has a sword with him!")

	local plrs = Players:GetPlayers()
	if #plrs >= SWORD_MIN_PLAYERS then -- make sure theres at least 1 player lol
		local chosen = plrs[math.random(1, #plrs)] -- pick rando player
		local clone = game.ServerStorage.Items.Sword:Clone() -- clone from serverstorage
		clone.Parent = chosen.Backpack -- drop it in their backpack, they get it instantly

		destroyAfter(clone, EVENT_DURATION) -- sword disappears after 30 secs
	end
end)

-- METEOR SHOWER EVENT
-- spawns 30 meteors 1 per sec, each falls from sky n explodes on contact
-- explosion uses roblox built-in blast so it dmgs players n parts near it
events.MeteorShower.Event:Connect(function()
	events.Dialogue:FireAllClients("OH NO! METEORS")

	local base = workspace:WaitForChild(BASEPLATE_NAME) -- need baseplate 4 spawn bounds
	local model = events:WaitForChild(METEOR_MODEL_NAME) -- template meteor part

	-- inner func bc we call it 30 times w task.delay, cleaner than inline
	local function spawnMeteor()
		local clone = model:Clone() -- clone template each time
		clone.Parent = workspace
		clone.Anchored = false -- needs 2 fall lol

		-- scatter spawn across the baseplate surface randomly
		local size = base.Size
		local pos = base.Position
		local randomX = pos.X + math.random(-size.X / 2, size.X / 2)
		local randomZ = pos.Z + math.random(-size.Z / 2, size.Z / 2)
		clone.Position = Vector3.new(randomX, pos.Y + METEOR_HEIGHT_OFFSET, randomZ)

		-- set downward velocity so it actually falls, physics handles the rest
		if clone:IsA("BasePart") then
			clone.AssemblyLinearVelocity = Vector3.new(0, METEOR_SPEED, 0)
		end

		-- debounce flag prevents explosion firing multiple times on same meteor
		-- can happen if it touches 2 parts in same frame
		local exploded = false
		clone.Touched:Connect(function(hit)
			if exploded or not hit:IsDescendantOf(workspace) then return end -- skip if already blew or hit smth outside workspace
			exploded = true
			local explosion = Instance.new("Explosion")
			explosion.Position = clone.Position
			explosion.BlastRadius = METEOR_BLAST_RADIUS
			explosion.BlastPressure = METEOR_BLAST_PRESSURE -- big number = big boom lmao
			explosion.Parent = workspace
			clone:Destroy() -- remove meteor after boom
		end)
		Debris:AddItem(clone, METEOR_DEBRIS_TIMEOUT) -- failsafe if it never touches anything
	end

	-- stagger spawns 1 per sec over 30 secs so its not all at once
	for i = 1, METEOR_COUNT do
		task.delay(i, spawnMeteor)
	end
end)

-- TSUNAMI EVENT
-- slides a giant wave across the map, players should b in bunker
-- after it clears everyone gets tped back 2 baseplate
events.Tsunami.Event:Connect(function()
	events.Dialogue:FireAllClients("TSUNAMI INCOMING! GET IN THE BUNKER!")

	-- clone folder so original stays intact 4 future rounds ik i keep saying this
	local folder = events:WaitForChild(TSUNAMI_FOLDER_NAME):Clone()
	local wave = folder:FindFirstChild(WAVE_PART_NAME)
	wave.Anchored = true -- anchored so physics doesnt mess w the tween
	folder.Parent = workspace

	-- tween the wave across the map on X axis
	TweenService:Create(wave, makeTweenInfo(TSUNAMI_TWEEN_TIME), {
		Position = Vector3.new(TSUNAMI_TARGET_X, 0, 0)
	}):Play()

	task.delay(EVENT_DURATION, function()
		folder:Destroy() -- clean up the wave n folder
		-- tp everyone back 2 spawn after wave is gone
		for _, plr in Players:GetPlayers() do
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") -- need hrp 2 move them
			if hrp then
				task.wait(TSUNAMI_TELEPORT_DELAY) -- tiny stagger so they dont all tp same frame
				hrp.CFrame = workspace.BaseplateTp.CFrame -- move em 2 the tp part
			end
		end
	end)
end)

-- LANDMINE EVENT
-- clones the bomb model into workspace, players gotta avoid stepping on it
-- bomb handles its own explosion logic presumably lol, we just spawn n clean it
events.Landmine.Event:Connect(function()
	events.Dialogue:FireAllClients("CAREFUL NOT TO EXPLODE, WATCH YOUR STEPS")

	local bomb = events.Bomb:Clone() -- clone from events, original stays
	bomb.Parent = workspace

	destroyAfter(bomb, EVENT_DURATION) -- gone after 30 secs regardless
end)

-- LOW GRAVITY EVENT
-- cuts gravity in half, everything floats around like an idiot lmao
-- saves original value so we can restore it exactly after
events.LOWGRAV.Event:Connect(function()
	events.Dialogue:FireAllClients("GRAVITY HAS BEEN CHANGED, BE CAREFUL")

	local original = workspace.Gravity -- save b4 changing obv
	workspace.Gravity = LOW_GRAV_VALUE -- set 2 low value
	task.wait(EVENT_DURATION) -- wait 30 secs
	workspace.Gravity = original -- restore, no more floaty lol
end)

-- KILLER EVENT
-- spawns an npc killer into workspace, idk wat ai it uses but it chases ppl
-- just clones it n waits 4 it 2 b cleaned up after 30 secs
events.KILLER.Event:Connect(function()
	events.Dialogue:FireAllClients("A KILLER IS ON THE LOOSE! DON'T DIE")

	local killer = events.Noob:Clone() -- the killer npc template
	killer.Parent = workspace -- spawn it in
	task.wait(EVENT_DURATION) -- wait 30 secs
	killer:Destroy() -- poof its gone lmao
end)
