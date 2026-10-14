local _, ns = ...

local Gathering = {}
ns.Gathering = Gathering

local PRESENCE_INTERVAL = 20
local PRESENCE_FORCE = 60
local PRESENCE_TTL = 300
local FIRE_RADIUS = 40
local FIRE_FRESH = 90
local PITCH_LINGER = 900

Gathering.presence = {}

local Distance = ns.Geometry.Distance
local lastSent = { t = 0 }

local function atFire()
	if ns.Campfires.atFire then
		return true
	end
	local pitch = ns.Campfires.lastPitch
	if not pitch or GetTime() - pitch.t > PITCH_LINGER then
		return false
	end
	local c, x, y = ns.GetPosition()
	return c == pitch.c and Distance(x, y, pitch.x, pitch.y) <= FIRE_RADIUS
end

function Gathering:Flare(reason, force)
	local day = ns.Today()
	if ns.char.gathered[day] and not force then
		return
	end
	ns.char.gathered[day] = reason
	PlaySound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960)
	if reason == "together" then
		ns.Print("You camp beside a friend. The fire flares up: time for the Gathering!")
	else
		ns.Print("The fire flares up: time for the Gathering! Reveal your omens.")
	end
	ns.UI:Show("fire", true)
	ns:Fire("EP_GATHERING", reason)
end

function Gathering:HasFlared(day)
	return ns.char.gathered[day] ~= nil
end

local function checkTogether()
	if not atFire() then
		return
	end
	local c, x, y = ns.GetPosition()
	if not c then
		return
	end
	local now = GetTime()
	for _, p in pairs(Gathering.presence) do
		if p.f and p.c == c and now - p.t <= FIRE_FRESH and Distance(x, y, p.x, p.y) <= FIRE_RADIUS then
			Gathering:Flare("together")
			return
		end
	end
end

ns:On("EP_PRESENCE", function(author, msg)
	if type(msg.c) ~= "number" or type(msg.x) ~= "number" or type(msg.y) ~= "number" then
		return
	end
	Gathering.presence[author] = { c = msg.c, x = msg.x, y = msg.y, m = msg.m, f = msg.f == true, t = GetTime() }
	if msg.f then
		checkTogether()
	end
end)

function Gathering:Friends()
	local out = {}
	local now = GetTime()
	for author, p in pairs(self.presence) do
		if now - p.t <= PRESENCE_TTL then
			out[author] = p
		end
	end
	return out
end

local function sendPresence()
	local fire = atFire()
	if not ns.db.settings.shareLive and not fire then
		return
	end
	local c, x, y, m = ns.GetPosition()
	if not c then
		return
	end
	local now = GetTime()
	local moved = lastSent.c ~= c or Distance(x, y, lastSent.x or 0, lastSent.y or 0) > 10
	if not moved and fire == lastSent.f and now - lastSent.t < PRESENCE_FORCE then
		return
	end
	lastSent = { c = c, x = x, y = y, f = fire, t = now }
	ns.Comm:Presence({ c = c, x = math.floor(x + 0.5), y = math.floor(y + 0.5), m = m, f = fire or nil })
end

local function checkHour()
	local hour = ns.db.settings.gatherHour
	if hour and tonumber(date("%H")) >= hour then
		Gathering:Flare("hour")
	end
end

ns:On("EP_FIRE_NEARBY", function()
	sendPresence()
	checkTogether()
end)

ns:On("EP_PITCHED", function()
	lastSent.t = 0
	sendPresence()
	checkTogether()
end)

ns:On("EP_READY", function()
	C_Timer.NewTicker(PRESENCE_INTERVAL, sendPresence)
	C_Timer.NewTicker(30, checkHour)
end)
