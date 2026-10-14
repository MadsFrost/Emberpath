local _, ns = ...

local Ledger = {}
ns.Ledger = Ledger

local function newStats()
	return { fires = 0, new = 0, dist = 0, honored = 0, broken = 0 }
end

function Ledger:Stats(fromDay)
	local stats = {}
	local function get(author)
		local s = stats[author]
		if not s then
			s = newStats()
			stats[author] = s
		end
		return s
	end
	for author, list in pairs(ns.Campfires.byAuthor) do
		for _, camp in ipairs(list) do
			if camp.d >= fromDay then
				local s = get(author)
				s.fires = s.fires + 1
				if camp.new then
					s.new = s.new + 1
				end
			end
		end
	end
	for author in pairs(ns.Trail.byAuthor) do
		local dist = ns.Trail:Distance(author, fromDay)
		if dist > 0 then
			get(author).dist = dist
		end
	end
	for author, days in pairs(ns.Omens.verdicts) do
		for day, v in pairs(days) do
			if day >= fromDay then
				local s = get(author)
				if v.value then
					s.honored = s.honored + 1
				else
					s.broken = s.broken + 1
				end
			end
		end
	end
	return stats
end

local TITLES = {
	{ name = "The Wanderer", field = "new", unit = "new campfires" },
	{ name = "The Pathfinder", field = "dist", unit = "yards travelled" },
	{ name = "The Firestarter", field = "fires", unit = "campfires lit" },
	{ name = "The Oathkeeper", field = "honored", unit = "omens honored" },
	{ name = "The Oathbreaker", field = "broken", unit = "omens broken" },
}

function Ledger:Titles(stats)
	local out = {}
	for _, title in ipairs(TITLES) do
		local best, value = nil, 0
		for author, s in pairs(stats) do
			if s[title.field] > value or (s[title.field] == value and best and author < best) then
				best, value = author, s[title.field]
			end
		end
		if best then
			out[#out + 1] = { name = title.name, author = best, value = value, unit = title.unit }
		end
	end
	return out
end

local function fmt(n)
	local s = tostring(math.floor(n + 0.5))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function header(text)
	return "|cffffd100" .. text .. "|r"
end

function Ledger:BuildText()
	local today = ns.Today()
	local lines = {}
	local add = function(line)
		lines[#lines + 1] = line or ""
	end

	add(header("Titles this week"))
	local weekly = self:Titles(self:Stats(today - 6))
	if #weekly == 0 then
		add("No titles yet. Light some fires.")
	end
	for _, t in ipairs(weekly) do
		add(string.format("%s: %s (%s %s)", t.name, ns.Short(t.author), fmt(t.value), t.unit))
	end
	add()

	add(header("The circle, all time"))
	local all = self:Stats(0)
	local authors = {}
	for author in pairs(all) do
		authors[#authors + 1] = author
	end
	table.sort(authors)
	for _, author in ipairs(authors) do
		local s = all[author]
		local r, g, b = ns.Color(author)
		add(string.format("|cff%02x%02x%02x%s|r: %d fires, %d new spots, %s yd, %d honored, %d broken",
			math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), ns.Short(author), s.fires, s.new, fmt(s.dist), s.honored, s.broken))
	end
	add()

	add(header("Your omens"))
	local any = false
	for day = today, today - 30, -1 do
		local omen = ns.Omens:MyOmen(day)
		if omen then
			any = true
			local verdict = ns.Omens:Verdict(ns.me, day)
			local believe, doubt = ns.Omens:VoteTally(ns.me, day)
			local state = verdict == true and "|cff60ff60honored|r" or verdict == false and "|cffff5040broken|r" or "undecided"
			add(string.format("%s: %s (%s, %d believe, %d doubt)", ns.DayLabel(day), omen.text, state, believe, doubt))
		end
	end
	if not any then
		add("No omens drawn yet.")
	end
	add()

	add(header("Campfire tales"))
	local tales = {}
	for campId, list in pairs(ns.Campfires.tales) do
		local camp = ns.Campfires.byId[campId]
		for _, tale in ipairs(list) do
			tales[#tales + 1] = { camp = camp, tale = tale }
		end
	end
	table.sort(tales, function(a, b)
		return a.tale.ts > b.tale.ts
	end)
	if #tales == 0 then
		add("No tales yet. Right-click a campfire on the map to tell one.")
	end
	for _, entry in ipairs(tales) do
		local where = entry.camp and ns.ZoneName(entry.camp.m) or "a lost fire"
		add(string.format("\"%s\", %s, %s, %s", ns.Escape(entry.tale.text), ns.Short(entry.tale.author), where,
			date("%d %b", entry.tale.ts)))
	end

	return table.concat(lines, "\n")
end
