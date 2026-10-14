local _, ns = ...

local Trail = {}
ns.Trail = Trail

local SAMPLE_INTERVAL = 2.5
local MIN_MOVE = 8
local MAX_POINTS = 240
local MAX_GAP = 180
local SIMPLIFY_EPSILON = 4

local Geometry = ns.Geometry

Trail.byAuthor = {}

local open

local function stripIfFaded(rec)
	if rec.p and rec.d < ns.Today() - ns.db.settings.retentionDays then
		rec.p = nil
	end
end

local function validPoints(p)
	if type(p) ~= "table" or #p < 6 or #p % 3 ~= 0 then
		return false
	end
	for i = 1, #p do
		if type(p[i]) ~= "number" then
			return false
		end
	end
	return true
end

ns:On("EP_RECORD", function(author, seq, rec)
	if rec.t ~= "trail" or type(rec.d) ~= "number" or type(rec.ts) ~= "number" or type(rec.c) ~= "number" then
		return
	end
	stripIfFaded(rec)
	if rec.p and not validPoints(rec.p) then
		rec.p = nil
	end
	local list = Trail.byAuthor[author]
	if not list then
		list = {}
		Trail.byAuthor[author] = list
	end
	list[#list + 1] = { author = author, seq = seq, rec = rec }
end)

local function close()
	if not open then
		return
	end
	local segment = open
	open = nil
	if #segment.p < 6 then
		return
	end
	local p = Geometry.Simplify(segment.p, SIMPLIFY_EPSILON)
	local len = Geometry.PathLength(segment.p)
	for i = 1, #p do
		p[i] = math.floor(p[i] + 0.5)
	end
	ns:AddRecord({ t = "trail", d = segment.d, ts = segment.ts, c = segment.c, p = p, len = math.floor(len + 0.5) })
end

local function addPoint(x, y, now)
	local p = open.p
	p[#p + 1] = x
	p[#p + 1] = y
	p[#p + 1] = now - open.ts
	open.lastX, open.lastY, open.lastT = x, y, now
end

local function sample()
	if not ns.ready then
		return
	end
	if UnitOnTaxi("player") or UnitIsDeadOrGhost("player") then
		close()
		return
	end
	local c, x, y = ns.GetPosition()
	if not c then
		close()
		return
	end
	local now = GetServerTime()
	local today = ns.Today()
	if open and (open.c ~= c or open.d ~= today or now - open.lastT > MAX_GAP) then
		close()
	end
	if not open then
		open = { d = today, ts = now, c = c, p = {} }
		addPoint(x, y, now)
		return
	end
	if Geometry.Distance(open.lastX, open.lastY, x, y) >= MIN_MOVE then
		addPoint(x, y, now)
		if #open.p >= MAX_POINTS * 3 then
			close()
			open = { d = today, ts = now, c = c, p = {} }
			addPoint(x, y, now)
		end
		ns:Fire("EP_TRAIL_MOVED")
	end
end

-- All segments to draw: synced records with points, plus the one being recorded now.
function Trail:Segments(fromDay)
	local out = {}
	for author, list in pairs(self.byAuthor) do
		for _, entry in ipairs(list) do
			local rec = entry.rec
			if rec.p and rec.d >= fromDay then
				out[#out + 1] = { author = author, d = rec.d, ts = rec.ts, c = rec.c, p = rec.p }
			end
		end
	end
	if open and #open.p >= 6 and open.d >= fromDay then
		out[#out + 1] = { author = ns.me, d = open.d, ts = open.ts, c = open.c, p = open.p }
	end
	return out
end

function Trail:Distance(author, fromDay)
	local total = 0
	for _, entry in ipairs(self.byAuthor[author] or {}) do
		if entry.rec.d >= fromDay then
			total = total + (entry.rec.len or 0)
		end
	end
	return total
end

ns:On("EP_PITCHED", close)
ns:On("PLAYER_LOGOUT", close)

ns:On("EP_READY", function()
	for _, list in pairs(Trail.byAuthor) do
		for _, entry in ipairs(list) do
			stripIfFaded(entry.rec)
		end
	end
	C_Timer.NewTicker(SAMPLE_INTERVAL, sample)
end)
