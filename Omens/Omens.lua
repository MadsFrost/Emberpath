local _, ns = ...

local Omens = {}
ns.Omens = Omens

local Chain = ns.OmenChain

Omens.commits = {}
Omens.draws = {}
Omens.reveals = {}
Omens.verdicts = {}
Omens.votes = {}

local verified = setmetatable({}, { __mode = "k" })

local function bucket(t, k)
	local v = t[k]
	if not v then
		v = {}
		t[k] = v
	end
	return v
end

local function setLatest(t, key, value, seq)
	local current = t[key]
	if not current or current.seq < seq then
		t[key] = { value = value, seq = seq }
	end
end

ns:On("EP_RECORD", function(author, seq, rec)
	local t = rec.t
	if t == "commit" and type(rec.s) == "number" and Chain.IsHash(rec.v0) then
		bucket(Omens.commits, author)[rec.s] = rec
	elseif t == "draw" and type(rec.d) == "number" then
		bucket(Omens.draws, author)[rec.d] = true
	elseif t == "reveal" and type(rec.d) == "number" then
		bucket(Omens.reveals, author)[rec.d] = rec
	elseif t == "verdict" and type(rec.d) == "number" then
		setLatest(bucket(Omens.verdicts, author), rec.d, rec.h == true, seq)
	elseif t == "vote" and type(rec.d) == "number" and type(rec.a) == "string" then
		setLatest(bucket(bucket(Omens.votes, rec.a), rec.d), author, rec.b == true, seq)
	end
end)

local function entropy()
	local parts = {
		GetServerTime(), GetTime(), debugprofilestop(), tostring({}), GetCursorPosition(),
	}
	for _ = 1, 16 do
		parts[#parts + 1] = math.random(0, 0x7fffffff)
	end
	for i = 1, #parts do
		parts[i] = tostring(parts[i])
	end
	return table.concat(parts, ":")
end

function Omens:SeasonFor(day)
	for start, season in pairs(ns.char.seasons) do
		if day >= start and day < start + season.L then
			return start, season
		end
	end
end

function Omens:NewSeason(day)
	local length = Chain.SEASON_LENGTH
	local seed = ns.SHA256(entropy())
	local season = { seed = seed, L = length }
	ns.char.seasons[day] = season
	ns:AddRecord({ t = "commit", s = day, L = length, v0 = Chain.Commit(seed, length), dv = ns.DeckVersion })
	return day, season
end

function Omens:HasDrawn(author, day)
	return self.draws[author] and self.draws[author][day] or false
end

local function valueFor(day)
	local start, season = Omens:SeasonFor(day)
	if not start then
		return nil
	end
	local k = day - start + 1
	return Chain.Value(season.seed, season.L, k), start, k
end

local myOmenCache = {}

function Omens:MyOmen(day)
	if not self:HasDrawn(ns.me, day) then
		return nil
	end
	if myOmenCache[day] then
		return myOmenCache[day]
	end
	local vk = valueFor(day)
	if not vk then
		return nil
	end
	local omen = ns.Deck[Chain.OmenIndex(vk, #ns.Deck)]
	myOmenCache[day] = omen
	return omen
end

function Omens:Draw()
	local day = ns.Today()
	if self:HasDrawn(ns.me, day) then
		return self:MyOmen(day), false
	end
	if not self:SeasonFor(day) then
		self:NewSeason(day)
	end
	ns:AddRecord({ t = "draw", d = day })
	local omen = self:MyOmen(day)
	ns:Fire("EP_OMEN_DRAWN", omen)
	return omen, true
end

function Omens:Reveal()
	local day = ns.Today()
	if not self:HasDrawn(ns.me, day) then
		ns.Print("You have not drawn an omen today.")
		return
	end
	if self.reveals[ns.me] and self.reveals[ns.me][day] then
		return
	end
	local vk, start, k = valueFor(day)
	if not vk then
		ns.Print("This character's omen seed is missing, so today's omen cannot be revealed.")
		return
	end
	ns:AddRecord({ t = "reveal", d = day, s = start, k = k, v = vk })
end

function Omens:SetVerdict(honored)
	ns:AddRecord({ t = "verdict", d = ns.Today(), h = honored and true or false })
end

function Omens:Vote(target, believe)
	ns:AddRecord({ t = "vote", d = ns.Today(), a = target, b = believe and true or false })
end

-- Returns { omen = deck entry or nil, ok = true/false/nil (nil = commit not synced yet) } or nil if not revealed.
function Omens:RevealInfo(author, day)
	local rec = self.reveals[author] and self.reveals[author][day]
	if not rec then
		return nil
	end
	local cached = verified[rec]
	if cached then
		return cached
	end
	local commit = self.commits[author] and self.commits[author][rec.s]
	if not commit then
		return { ok = nil }
	end
	local anchors = { [0] = commit.v0 }
	for _, other in pairs(self.reveals[author]) do
		if other ~= rec and other.s == rec.s and type(other.k) == "number" and other.k < rec.k then
			local info = verified[other]
			if info and info.ok then
				anchors[other.k] = other.v
			end
		end
	end
	local ok = Chain.Verify(anchors, rec.k, rec.v)
	local omen
	if ok and commit.dv == ns.DeckVersion then
		omen = ns.Deck[Chain.OmenIndex(rec.v, #ns.Deck)]
	end
	local info = { ok = ok, omen = omen, deckMismatch = ok and commit.dv ~= ns.DeckVersion }
	verified[rec] = info
	return info
end

function Omens:RevealedOmen(author, day)
	local info = self:RevealInfo(author, day)
	return info and info.ok and info.omen or nil
end

function Omens:Verdict(author, day)
	local v = self.verdicts[author] and self.verdicts[author][day]
	if v then
		return v.value
	end
end

function Omens:VoteTally(target, day)
	local believe, doubt, mine = 0, 0, nil
	local votes = self.votes[target] and self.votes[target][day]
	if votes then
		for voter, v in pairs(votes) do
			if v.value then
				believe = believe + 1
			else
				doubt = doubt + 1
			end
			if voter == ns.me then
				mine = v.value
			end
		end
	end
	return believe, doubt, mine
end

function Omens:Broke(author, day)
	return self:Verdict(author, day) == false
end

function Omens:AuthorsWithDraw(day)
	local out = {}
	for author, days in pairs(self.draws) do
		if days[day] then
			out[#out + 1] = author
		end
	end
	return out
end

local function hint(state, why)
	local day = ns.Today()
	if ns.char.hints[day] then
		return
	end
	ns.char.hints[day] = { state = state, why = why }
	if state == "broken" then
		ns.Print("|cffff5040Your omen is broken:|r " .. why .. ". Be honest at the Gathering.")
	else
		ns.Print("|cff60ff60Your omen is fulfilled:|r " .. why .. ".")
	end
	ns:Fire("EP_HINT")
end

local function todaysWatch()
	local omen = Omens:MyOmen(ns.Today())
	return omen and omen.watch
end

ns:On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(interactionType)
	local watch = todaysWatch()
	local types = Enum.PlayerInteractionType
	if watch and watch.interaction and types and types[watch.interaction] == interactionType then
		hint("broken", "you used the " .. watch.interaction:lower())
	end
end)

ns:On("PLAYER_MOUNT_DISPLAY_CHANGED", function()
	local watch = todaysWatch()
	if watch and watch.mount and IsMounted() then
		hint("broken", "you mounted up")
	end
end)

ns:On("PLAYER_CONTROL_LOST", function()
	local watch = todaysWatch()
	if watch and watch.taxi then
		C_Timer.After(1, function()
			if UnitOnTaxi("player") then
				hint("broken", "you took a flight path")
			end
		end)
	end
end)

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, _, spellID)
	local watch = todaysWatch()
	if not watch or not watch.spell or (issecretvalue and issecretvalue(spellID)) then
		return
	end
	local name = C_Spell.GetSpellName(spellID)
	if name == watch.spell then
		hint("broken", "you cast " .. name)
	end
end)

ns:On("EP_PITCHED", function(camp, isNew)
	local day = ns.Today()
	if not Omens:HasDrawn(ns.me, day) then
		local omen = Omens:Draw()
		if omen then
			ns.Print("The first fire of the day. Your omen is drawn.")
			ns.UI:Show("fire", true)
		end
	end
	local watch = todaysWatch()
	if not watch or not watch.goal then
		return
	end
	if watch.goal == "newcamp" and isNew then
		hint("honored", "you camped somewhere new")
	elseif watch.goal == "camps" and ns.Campfires:CountMine(day) >= (watch.n or 1) then
		hint("honored", "you lit " .. watch.n .. " campfires")
	end
end)

ns:On("EP_TALE_ADDED", function()
	local watch = todaysWatch()
	if watch and watch.goal == "tale" then
		local day = ns.Today()
		local camps, told = ns.Campfires:CountMine(day), ns.Campfires:CountMineWithTale(day)
		if camps > 0 and told >= camps then
			hint("honored", "every fire you lit has a tale")
		end
	end
end)

ns:On("EP_READY", function()
	local day = ns.Today()
	if Omens:HasDrawn(ns.me, day) then
		return
	end
	if ns.db.settings.autoDraw then
		Omens:Draw()
	else
		C_Timer.After(8, function()
			ns.Print("Pitch camp (/pitch) or type /ember draw to draw today's omen.")
		end)
	end
end)
