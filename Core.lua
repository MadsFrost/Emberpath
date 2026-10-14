local ADDON, ns = ...

ns.name = ADDON

local DEFAULTS = {
	settings = {
		resetHourUTC = 4,
		gatherHour = 21,
		retentionDays = 7,
		shareLive = true,
		autoDraw = false,
		campSpellPatterns = { "[Cc]ampfire", "Cooking Fire" },
		campAuraName = "Campfire Nearby",
		layers = { trails = true, camps = true, oldCamps = false, friends = true },
	},
	records = {},
}

local CHAR_DEFAULTS = {
	seasons = {},
	hints = {},
	gathered = {},
}

local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns:On(event, fn)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		if not event:find("^EP_") then
			if event:find("^UNIT_") then
				pcall(eventFrame.RegisterUnitEvent, eventFrame, event, "player")
			else
				pcall(eventFrame.RegisterEvent, eventFrame, event)
			end
		end
	end
	list[#list + 1] = fn
end

function ns:Fire(event, ...)
	local list = handlers[event]
	if not list then
		return
	end
	for i = 1, #list do
		list[i](...)
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	ns:Fire(event, ...)
end)

local function merge(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			merge(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffff8c1aEmberpath|r: " .. msg)
end

function ns.Escape(text)
	return (tostring(text):gsub("|", "||"))
end

function ns.Short(author)
	return Ambiguate(author, "short")
end

function ns.IsMe(sender)
	local name, realm = strsplit("-", sender, 2)
	return name == UnitName("player") and (not realm or realm == "" or realm == ns.realm)
end

function ns.Today()
	return ns.DayClock.Key(GetServerTime(), ns.db.settings.resetHourUTC)
end

function ns.DayStart(day)
	return ns.DayClock.Start(day, ns.db.settings.resetHourUTC)
end

function ns.DayLabel(day)
	return date("%a %d %b", ns.DayStart(day))
end

local PALETTE = {
	{ 1.00, 0.55, 0.10 },
	{ 0.35, 0.75, 1.00 },
	{ 0.55, 0.95, 0.35 },
	{ 0.95, 0.45, 0.85 },
	{ 1.00, 0.85, 0.25 },
	{ 0.45, 0.95, 0.85 },
	{ 0.75, 0.55, 1.00 },
	{ 1.00, 0.70, 0.55 },
}

function ns.Color(author)
	local sum = 0
	for i = 1, #author do
		sum = sum + author:byte(i) * i
	end
	local c = PALETTE[sum % #PALETTE + 1]
	return c[1], c[2], c[3]
end

local function secret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

-- Returns continentID, worldX, worldY, uiMapID in the open world; nil inside instances.
function ns.GetPosition()
	if IsInInstance() then
		return nil
	end
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then
		return nil
	end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then
		return nil
	end
	local continent, world = C_Map.GetWorldPosFromMapPos(mapID, pos)
	if not continent or not world then
		return nil
	end
	local x, y = world:GetXY()
	if secret(x) or secret(y) then
		return nil
	end
	return continent, x, y, mapID
end

function ns.ZoneName(mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	return info and info.name or "somewhere"
end

function ns:AddRecord(rec)
	local seq = ns.store:Append(ns.me, rec)
	ns:Fire("EP_RECORD", ns.me, seq, rec, false)
	ns.Comm:Publish(ns.me, seq, rec)
	return seq
end

function ns:Ingest(author, seq, rec)
	if ns.store:Ingest(author, seq, rec) then
		ns:Fire("EP_RECORD", author, seq, rec, false)
	end
end

ns:On("ADDON_LOADED", function(name)
	if name ~= ADDON then
		return
	end
	EmberpathDB = EmberpathDB or {}
	EmberpathCharDB = EmberpathCharDB or {}
	merge(EmberpathDB, DEFAULTS)
	merge(EmberpathCharDB, CHAR_DEFAULTS)
	ns.db = EmberpathDB
	ns.char = EmberpathCharDB
end)

ns:On("PLAYER_LOGIN", function()
	local name, realm = UnitFullName("player")
	realm = (realm and realm ~= "") and realm or GetNormalizedRealmName()
	ns.realm = realm
	ns.me = (realm and realm ~= "") and (name .. "-" .. realm) or name
	ns.store = ns.NewStore(ns.db.records)
	ns.store:Each(function(author, seq, rec)
		ns:Fire("EP_RECORD", author, seq, rec, true)
	end)
	ns.ready = true
	ns:Fire("EP_READY")
end)

local HELP = {
	"/ember - open or close the Emberpath window",
	"/ember camp (or /pitch) - pitch a campfire where you stand",
	"/ember tale <text> - leave a tale at the nearest campfire",
	"/ember draw - draw today's omen",
	"/ember reveal - reveal today's omen to the circle",
	"/ember gather - call the Gathering now",
	"/ember replay - replay today's trails on the world map",
	"/ember gatherhour <0-23|off> - set the Gathering hour (local time)",
	"/ember reset <0-23> - set the daily reset hour (UTC, agree on it with your friends)",
	"/ember sync - ask friends for missing records",
}

SLASH_EMBERPATH1 = "/ember"
SLASH_EMBERPATH2 = "/emberpath"
SlashCmdList.EMBERPATH = function(input)
	local cmd, rest = strtrim(input or ""):match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	if cmd == "" then
		ns.UI:Toggle()
	elseif cmd == "camp" or cmd == "pitch" then
		ns.Campfires:Pitch("manual")
	elseif cmd == "tale" then
		ns.Campfires:TaleAtNearest(rest)
	elseif cmd == "draw" then
		ns.Omens:Draw()
		ns.UI:Show("fire")
	elseif cmd == "reveal" then
		ns.Omens:Reveal()
	elseif cmd == "gather" then
		ns.Gathering:Flare("manual", true)
	elseif cmd == "replay" then
		ns.Map:StartReplay()
	elseif cmd == "gatherhour" then
		local hour = tonumber(rest)
		ns.db.settings.gatherHour = (hour and hour >= 0 and hour <= 23) and hour or false
		ns.Print("Gathering hour: " .. (ns.db.settings.gatherHour and (ns.db.settings.gatherHour .. ":00") or "off"))
	elseif cmd == "reset" then
		local hour = tonumber(rest)
		if hour and hour >= 0 and hour <= 23 then
			ns.db.settings.resetHourUTC = hour
			ns.Print("Day reset: " .. hour .. ":00 UTC. Every friend must use the same value.")
		end
	elseif cmd == "sync" then
		ns.Comm:Hello(true)
		ns.Print("Asked the circle for missing records.")
	else
		for _, line in ipairs(HELP) do
			ns.Print(line)
		end
	end
end

-- Not "/camp": that is WoW's built-in logout command.
SLASH_EMBERPATHPITCH1 = "/pitch"
SlashCmdList.EMBERPATHPITCH = function()
	ns.Campfires:Pitch("manual")
end

function Emberpath_OnAddonCompartmentClick()
	ns.UI:Toggle()
end
