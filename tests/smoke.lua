-- End-to-end smoke test: loads the full addon into three fake clients with stubbed WoW APIs
-- and plays a day of camping, syncing, revealing and voting between them.
-- Run from the repo root: luajit tests/smoke.lua
bit = bit or require("bit")

local clock = 1760000000
local monotonic = 1000
local network = {}
local clients = {}
local verbose = os.getenv("VERBOSE")

local registry, registryNext = {}, 0
local function deepcopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = deepcopy(x)
	end
	return out
end
local C_EncodingUtil = {
	SerializeCBOR = function(v)
		registryNext = registryNext + 1
		registry["obj" .. registryNext] = deepcopy(v)
		return "obj" .. registryNext
	end,
	DeserializeCBOR = function(s)
		return deepcopy(assert(registry[s], "unknown payload"))
	end,
	CompressString = function(s) return s end,
	DecompressString = function(s) return s end,
	EncodeBase64 = function(s) return s end,
	DecodeBase64 = function(s) return s end,
}

local NUMERIC = { GetStringHeight = 12, GetWidth = 100, GetHeight = 100, GetFrameLevel = 1 }
local dummyMT
local function dummy()
	return setmetatable({ _scripts = {} }, dummyMT)
end
dummyMT = {
	__index = function(_, key)
		if NUMERIC[key] then
			return function() return NUMERIC[key] end
		elseif key == "GetSize" then
			return function() return 1000, 800 end
		elseif key == "SetScript" then
			return function(self, name, fn) self._scripts[name] = fn end
		elseif key == "GetScript" then
			return function(self, name) return self._scripts[name] end
		end
		return function() return dummy() end
	end,
}

local function vector(x, y)
	return {
		x = x, y = y,
		GetXY = function(self) return self.x, self.y end,
		SetXY = function(self, nx, ny) self.x, self.y = nx, ny end,
	}
end

local function newClient(name)
	local client = { name = name, full = name .. "-Forever", pos = { x = 100, y = 100 }, frames = {}, timers = {}, log = {} }
	local env = {}

	local function frameFor(f)
		f.RegisterEvent = function(self, event)
			client.frames[#client.frames + 1] = { frame = self, event = event }
		end
		f.RegisterUnitEvent = f.RegisterEvent
		return f
	end

	local stubs = {
		bit = bit,
		C_EncodingUtil = C_EncodingUtil,
		Enum = {
			CompressionMethod = { Deflate = 0 },
			SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3 },
			PlayerInteractionType = { Auctioneer = 21, Merchant = 5, MailInfo = 17, Banker = 8 },
		},
		LE_PARTY_CATEGORY_HOME = 1,
		SOUNDKIT = {},
		ACCEPT = "Accept",
		CANCEL = "Cancel",
		SlashCmdList = {},
		StaticPopupDialogs = {},
		UISpecialFrames = {},
		UIParent = dummy(),
		GameTooltip = dummy(),
		DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) client.log[#client.log + 1] = msg; if verbose then print("[" .. name .. "] " .. msg) end end },
		CreateFrame = function() return frameFor(dummy()) end,
		CreateVector2D = vector,
		CreateFromMixins = function(...)
			local out = {}
			for i = 1, select("#", ...) do
				for k, v in pairs((select(i, ...))) do
					out[k] = v
				end
			end
			return out
		end,
		MapCanvasDataProviderMixin = {
			OnAdded = function(self, map) self.owningMap = map end,
			GetMap = function(self) return self.owningMap end,
		},
		MapCanvasPinMixin = { SetPosition = function(self, x, y) self.px, self.py = x, y end },
		C_Timer = {
			After = function(delay, fn) client.timers[#client.timers + 1] = { due = monotonic + delay, fn = fn } end,
			NewTicker = function(interval, fn) client.timers[#client.timers + 1] = { due = monotonic + interval, fn = fn, every = interval } end,
		},
		C_ChatInfo = {
			RegisterAddonMessagePrefix = function() end,
			SendAddonMessage = function(prefix, msg, chatType, target)
				network[#network + 1] = { from = client, prefix = prefix, msg = msg, chatType = chatType, target = target }
				return 0
			end,
		},
		C_Map = {
			GetBestMapForUnit = function() return 1429 end,
			GetPlayerMapPosition = function() return vector(client.pos.x / 1000, client.pos.y / 1000) end,
			GetWorldPosFromMapPos = function(_, pos) return 0, vector(pos.x * 1000, pos.y * 1000) end,
			GetMapPosFromWorldPos = function(_, world, mapID) return mapID, vector(world.x / 1000, world.y / 1000) end,
			GetMapInfo = function() return { name = "Elwynn Forest" } end,
		},
		C_Spell = { GetSpellName = function(id) return id == 1 and "Basic Campfire" or "Fireball" end },
		C_UnitAuras = { GetAuraDataBySpellName = function() return nil end },
		UnitName = function() return name end,
		UnitFullName = function() return name, "Forever" end,
		GetNormalizedRealmName = function() return "Forever" end,
		GetServerTime = function() return clock end,
		GetTime = function() return monotonic end,
		debugprofilestop = function() return monotonic * 1000 end,
		GetCursorPosition = function() return 0, 0 end,
		IsInInstance = function() return false end,
		IsInGuild = function() return true end,
		IsInGroup = function() return false end,
		IsInRaid = function() return false end,
		IsMounted = function() return false end,
		InCombatLockdown = function() return false end,
		UnitOnTaxi = function() return false end,
		UnitIsDeadOrGhost = function() return false end,
		PlaySound = function() end,
		ToggleWorldMap = function() end,
		StaticPopup_Show = function() end,
		Ambiguate = function(full) return (full:gsub("%-.*$", "")) end,
		strsplit = function(sep, s, limit)
			local a, b = s:match("^(.-)" .. sep .. "(.*)$")
			if a then return a, b end
			return s
		end,
		strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
		tinsert = table.insert,
		date = os.date,
	}

	local worldMap = dummy()
	worldMap.pins = {}
	worldMap.AddDataProvider = function(self, provider) self.provider = provider; provider:OnAdded(self) end
	worldMap.IsShown = function() return true end
	worldMap.GetMapID = function() return 1429 end
	worldMap.GetCanvasScale = function() return 1 end
	worldMap.RemoveAllPinsByTemplate = function(self, template) self.pins[template] = {} end
	worldMap.AcquirePin = function(self, template, ...)
		local mixin = template == "EmberpathCampPinTemplate" and env.EmberpathCampPinMixin or env.EmberpathFriendPinMixin
		local pin = dummy()
		for k, v in pairs(mixin) do
			rawset(pin, k, v)
		end
		pin.Icon, pin.Omen, pin.Tale, pin.Glow = dummy(), dummy(), dummy(), dummy()
		pin:OnLoad()
		pin:OnAcquired(...)
		self.pins[template] = self.pins[template] or {}
		table.insert(self.pins[template], pin)
		return pin
	end
	stubs.WorldMapFrame = worldMap
	client.worldMap = worldMap

	setmetatable(env, { __index = function(_, k)
		local v = stubs[k]
		if v ~= nil then return v end
		return _G[k]
	end })
	client.env = env

	local ns = {}
	client.ns = ns
	local toc = assert(io.open("Emberpath.toc")):read("*a")
	for line in toc:gmatch("[^\r\n]+") do
		if line:match("%.lua$") then
			local chunk = assert(loadfile((line:gsub("\\", "/"))))
			setfenv(chunk, env)
			chunk("Emberpath", ns)
		end
	end

	function client:Fire(event, ...)
		for _, reg in ipairs(self.frames) do
			if reg.event == event then
				reg.frame._scripts.OnEvent(reg.frame, event, ...)
			end
		end
	end

	function client:RunTimers()
		local ran = true
		while ran do
			ran = false
			for i = #self.timers, 1, -1 do
				local t = self.timers[i]
				if t.due <= monotonic then
					if t.every then
						t.due = t.due + t.every
					else
						table.remove(self.timers, i)
					end
					t.fn()
					ran = true
				end
			end
		end
	end

	client:Fire("ADDON_LOADED", "Emberpath")
	client:Fire("PLAYER_LOGIN")
	clients[#clients + 1] = client
	return client
end

local function deliver()
	local guard = 0
	while #network > 0 do
		guard = guard + 1
		assert(guard < 100000, "network never settled")
		local packet = table.remove(network, 1)
		for _, c in ipairs(clients) do
			if c ~= packet.from and c.online ~= false then
				local toMe = packet.chatType ~= "WHISPER" or packet.target == c.full
				if toMe then
					c:Fire("CHAT_MSG_ADDON", packet.prefix, packet.msg, packet.chatType, packet.from.full)
				end
			end
		end
	end
end

local function advance(seconds)
	local step = 0.1
	for _ = 1, math.floor(seconds / step + 0.5) do
		monotonic = monotonic + step
		clock = clock + step
		for _, c in ipairs(clients) do
			if c.online ~= false then
				c:RunTimers()
			end
		end
		deliver()
	end
	clock = math.floor(clock + 0.5)
end

local passed, failed = 0, 0
local function check(label, cond)
	if cond then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL " .. label)
	end
end

local alice = newClient("Alice")
local bob = newClient("Bob")
local A, B = alice.ns, bob.ns
advance(6)
check("peers discovered each other", B.Comm:OnlinePeers()[A.me] ~= nil and A.Comm:OnlinePeers()[B.me] ~= nil)

alice:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 1)
advance(1)
local day = A.Today()
check("campfire spell pitches a camp", A.Campfires:CountMine(day) == 1)
check("first camp draws the omen", A.Omens:HasDrawn(A.me, day) and A.Omens:MyOmen(day) ~= nil)

for i = 1, 30 do
	alice.pos.x = 100 + i * 10
	advance(2.5)
end
alice.env.SlashCmdList.EMBERPATHPITCH()
advance(1)
check("second camp in a new spot", A.Campfires:CountMine(day) == 2)
check("trail segment saved between camps", #(A.Trail.byAuthor[A.me] or {}) == 1)
local trailRec = A.Trail.byAuthor[A.me][1].rec
check("trail simplified to a straight line", #trailRec.p == 6 and trailRec.len >= 280)

local camp = A.Campfires:LastMine()
A.Campfires:AddTale(camp.id, "Elite patrols here, RUN |cffff0000")
advance(30)
check("bob received all of alice's records", B.store:Contig(A.me) == A.store:High(A.me))
check("bob sees the tale", B.Campfires:Tales(camp.id) ~= nil)
check("bob sees the draw but not the omen", B.Omens:HasDrawn(A.me, day) and B.Omens:RevealInfo(A.me, day) == nil)

bob.pos.x, bob.pos.y = alice.pos.x + 5, alice.pos.y
bob.env.SlashCmdList.EMBERPATHPITCH()
advance(25)
check("camping together flares the Gathering", A.Gathering:HasFlared(day) and B.Gathering:HasFlared(day))

A.Omens:Reveal()
advance(5)
local info = B.Omens:RevealInfo(A.me, day)
check("bob verifies alice's reveal", info and info.ok == true)
check("bob sees alice's omen", info and info.omen and info.omen.id == A.Omens:MyOmen(day).id)

A.Omens:SetVerdict(false)
advance(5)
B.Omens:Vote(A.me, false)
advance(5)
local believe, doubt = A.Omens:VoteTally(A.me, day)
check("alice sees bob's doubt", believe == 0 and doubt == 1)
check("broken omen shows on bob's side", B.Omens:Broke(A.me, day))

local forged = { t = "reveal", d = day + 1, s = info and A.Omens:SeasonFor(day) or day, k = 2, v = string.rep("a", 64) }
B.store:Ingest(A.me, 999, forged)
B.Omens.reveals[A.me][day + 1] = forged
check("forged reveal fails verification", B.Omens:RevealInfo(A.me, day + 1).ok == false)
B.Omens.reveals[A.me][day + 1] = nil
B.store.records[A.me].list[999] = nil
B.store.records[A.me].high = B.store:Contig(A.me)

alice.online = false
local carol = newClient("Carol")
advance(40)
check("carol got alice's records relayed through bob", carol.ns.store:Contig(A.me) == A.store:High(A.me))
local cinfo = carol.ns.Omens:RevealInfo(A.me, day)
check("carol verifies alice's omen without alice online", cinfo and cinfo.ok == true)

local ok, text = pcall(A.Ledger.BuildText, A.Ledger)
check("ledger builds", ok and text:find("The Wanderer") ~= nil)
check("tale text is escaped in the ledger", ok and text:find("||cffff0000", 1, true) ~= nil)

A.UI:Show("fire")
A.UI:Show("layers")
A.UI:Show("ledger")
check("all tabs render without errors", true)

alice.worldMap.provider:RefreshAllData()
check("map draws trail lines", (alice.worldMap.provider.lineCount or 0) > 0)
check("map shows campfire pins", #(alice.worldMap.pins.EmberpathCampPinTemplate or {}) >= 2)
alice.worldMap.provider:StartReplay()
alice.worldMap.provider:StopReplay()

local errors = 0
for _, c in ipairs(clients) do
	for _, msg in ipairs(c.log) do
		if msg:find("error") then
			errors = errors + 1
		end
	end
end
check("no error messages printed", errors == 0)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
