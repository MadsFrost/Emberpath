local _, ns = ...

local Campfires = {}
ns.Campfires = Campfires

local MERGE_RADIUS = 20
local NEW_SPOT_RADIUS = 30
local NEARBY_RADIUS = 50
local TALE_MAX = 200

Campfires.byId = {}
Campfires.byAuthor = {}
Campfires.tales = {}
Campfires.atFire = false

local Distance = ns.Geometry.Distance

local function isNum(...)
	for i = 1, select("#", ...) do
		if type(select(i, ...)) ~= "number" then
			return false
		end
	end
	return true
end

ns:On("EP_RECORD", function(author, seq, rec)
	if rec.t == "camp" and isNum(rec.d, rec.ts, rec.c, rec.x, rec.y) then
		local camp = {
			id = author .. "#" .. seq,
			author = author,
			d = rec.d, ts = rec.ts, c = rec.c, x = rec.x, y = rec.y, m = rec.m, new = rec.n,
		}
		Campfires.byId[camp.id] = camp
		local list = Campfires.byAuthor[author]
		if not list then
			list = {}
			Campfires.byAuthor[author] = list
		end
		list[#list + 1] = camp
	elseif rec.t == "tale" and type(rec.cid) == "string" and type(rec.text) == "string" then
		local list = Campfires.tales[rec.cid]
		if not list then
			list = {}
			Campfires.tales[rec.cid] = list
		end
		list[#list + 1] = { author = author, ts = rec.ts or 0, text = rec.text:sub(1, TALE_MAX) }
		table.sort(list, function(a, b)
			return a.ts < b.ts
		end)
	end
end)

function Campfires:Tales(id)
	return self.tales[id]
end

function Campfires:Visible(includeOld)
	local cutoff = ns.Today() - ns.db.settings.retentionDays
	local out = {}
	for id, camp in pairs(self.byId) do
		if includeOld or camp.d >= cutoff or self.tales[id] then
			out[#out + 1] = camp
		end
	end
	return out
end

function Campfires:NearestTo(c, x, y, radius, filter)
	local best, bestDist
	for _, camp in pairs(self.byId) do
		if camp.c == c and (not filter or filter(camp)) then
			local d = Distance(x, y, camp.x, camp.y)
			if d <= radius and (not bestDist or d < bestDist) then
				best, bestDist = camp, d
			end
		end
	end
	return best, bestDist
end

function Campfires:CountMine(day)
	local n = 0
	for _, camp in ipairs(self.byAuthor[ns.me] or {}) do
		if camp.d == day then
			n = n + 1
		end
	end
	return n
end

function Campfires:CountMineWithTale(day)
	local n = 0
	for _, camp in ipairs(self.byAuthor[ns.me] or {}) do
		if camp.d == day and self.tales[camp.id] then
			n = n + 1
		end
	end
	return n
end

function Campfires:LastMine()
	local list = self.byAuthor[ns.me]
	return list and list[#list]
end

function Campfires:Pitch(source)
	local c, x, y, mapID = ns.GetPosition()
	if not c then
		ns.Print("You cannot pitch camp here.")
		return
	end
	local today = ns.Today()
	local mine = function(camp)
		return camp.author == ns.me
	end
	local existing = self:NearestTo(c, x, y, MERGE_RADIUS, function(camp)
		return camp.author == ns.me and camp.d == today
	end)
	if existing then
		self.lastPitch = { c = c, x = x, y = y, t = GetTime() }
		if source == "manual" then
			ns.Print("You already have a campfire here today.")
		end
		return existing
	end
	local isNew = self:NearestTo(c, x, y, NEW_SPOT_RADIUS, mine) == nil
	local seq = ns:AddRecord({
		t = "camp",
		d = today,
		ts = GetServerTime(),
		c = c,
		x = math.floor(x + 0.5),
		y = math.floor(y + 0.5),
		m = mapID,
		n = isNew or nil,
	})
	local camp = self.byId[ns.me .. "#" .. seq]
	self.lastPitch = { c = c, x = x, y = y, t = GetTime() }
	ns.Print(string.format("You pitch camp in %s.%s Right-click it on the map, or type /ember tale, to leave a tale.",
		ns.ZoneName(mapID), isNew and " A new spot!" or ""))
	ns:Fire("EP_PITCHED", camp, isNew)
	return camp
end

function Campfires:AddTale(campId, text)
	text = strtrim(text or "")
	if text == "" or not self.byId[campId] then
		return
	end
	ns:AddRecord({ t = "tale", cid = campId, ts = GetServerTime(), text = text:sub(1, TALE_MAX) })
	ns:Fire("EP_TALE_ADDED", campId)
end

function Campfires:TaleAtNearest(text)
	local c, x, y = ns.GetPosition()
	local camp = c and self:NearestTo(c, x, y, NEARBY_RADIUS)
	camp = camp or self:LastMine()
	if not camp then
		ns.Print("There is no campfire nearby. Pitch one first with /pitch.")
		return
	end
	if strtrim(text or "") == "" then
		self:PromptTale(camp.id)
	else
		self:AddTale(camp.id, text)
		ns.Print("Your tale is told.")
	end
end

StaticPopupDialogs.EMBERPATH_TALE = {
	text = "Leave a tale at %s's campfire:",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = TALE_MAX,
	editBoxWidth = 260,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function(dialog, campId)
		local editBox = dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox or dialog.EditBox
		Campfires:AddTale(campId, editBox:GetText())
	end,
	EditBoxOnEnterPressed = function(editBox)
		local dialog = editBox:GetParent()
		Campfires:AddTale(dialog.data, editBox:GetText())
		dialog:Hide()
	end,
	EditBoxOnEscapePressed = function(editBox)
		editBox:GetParent():Hide()
	end,
}

function Campfires:PromptTale(campId)
	local camp = self.byId[campId]
	if camp then
		StaticPopup_Show("EMBERPATH_TALE", ns.Short(camp.author), nil, campId)
	end
end

local function matchesCampSpell(name)
	for _, pattern in ipairs(ns.db.settings.campSpellPatterns) do
		if name:find(pattern) then
			return true
		end
	end
	return false
end

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, _, spellID)
	if not ns.ready or (issecretvalue and issecretvalue(spellID)) then
		return
	end
	local name = C_Spell.GetSpellName(spellID)
	if name and matchesCampSpell(name) then
		C_Timer.After(0.5, function()
			Campfires:Pitch("spell")
		end)
	end
end)

ns:On("UNIT_AURA", function()
	if not ns.ready or InCombatLockdown() then
		return
	end
	local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", ns.db.settings.campAuraName, "HELPFUL")
	local atFire = ok and aura ~= nil
	if atFire ~= Campfires.atFire then
		Campfires.atFire = atFire
		ns:Fire("EP_FIRE_NEARBY", atFire)
	end
end)
