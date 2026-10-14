local _, ns = ...

local Map = {}
ns.Map = Map

local CAMP_TEMPLATE = "EmberpathCampPinTemplate"
local FRIEND_TEMPLATE = "EmberpathFriendPinTemplate"
local MAX_LINES = 4000
local LINE_THICKNESS = 2.5
local REPLAY_SECONDS = 20
local BROKEN_COLOR = { 0.9, 0.15, 0.1 }
local EMBER_COLOR = { 1, 0.45, 0.1 }

local provider
local worldVec

local function toMap(c, x, y, mapID)
	worldVec:SetXY(x, y)
	local _, pos = C_Map.GetMapPosFromWorldPos(c, worldVec, mapID)
	if not pos then
		return nil
	end
	local px, py = pos:GetXY()
	if px < 0 or px > 1 or py < 0 or py > 1 then
		return nil
	end
	return px, py
end

local function ageAlpha(day)
	local age = ns.Today() - day
	return math.max(0.15, 0.9 - age * 0.11)
end

local ProviderMixin = {}

function ProviderMixin:OnAdded(mapCanvas)
	MapCanvasDataProviderMixin.OnAdded(self, mapCanvas)
	local canvas = mapCanvas:GetCanvas()
	self.lineFrame = CreateFrame("Frame", nil, canvas)
	self.lineFrame:SetAllPoints(canvas)
	self.lines = {}
end

function ProviderMixin:RemoveAllData()
	local map = self:GetMap()
	map:RemoveAllPinsByTemplate(CAMP_TEMPLATE)
	map:RemoveAllPinsByTemplate(FRIEND_TEMPLATE)
	for _, line in ipairs(self.lines) do
		line:Hide()
	end
end

function ProviderMixin:RefreshAllData()
	self:RemoveAllData()
	local map = self:GetMap()
	local mapID = map:GetMapID()
	if not mapID or not ns.ready then
		return
	end
	local layers = ns.db.settings.layers
	if layers.camps then
		for _, camp in ipairs(ns.Campfires:Visible(layers.oldCamps)) do
			local px, py = toMap(camp.c, camp.x, camp.y, mapID)
			if px then
				map:AcquirePin(CAMP_TEMPLATE, camp, px, py)
			end
		end
	end
	if layers.friends then
		for author, presence in pairs(ns.Gathering:Friends()) do
			local px, py = toMap(presence.c, presence.x, presence.y, mapID)
			if px then
				map:AcquirePin(FRIEND_TEMPLATE, author, presence, px, py)
			end
		end
	end
	if layers.trails or self.replay then
		self:DrawTrails(mapID)
	end
end

function ProviderMixin:AcquireLine(i)
	local line = self.lines[i]
	if not line then
		line = self.lineFrame:CreateLine(nil, "ARTWORK")
		self.lines[i] = line
	end
	return line
end

function ProviderMixin:DrawTrails(mapID)
	local today = ns.Today()
	local fromDay = self.replay and today or today - ns.db.settings.retentionDays
	local w, h = self.lineFrame:GetSize()
	local thickness = (self.replay and LINE_THICKNESS * 1.6 or LINE_THICKNESS) / self:GetMap():GetCanvasScale()
	local n = 0
	self.lineCount = 0
	for _, seg in ipairs(ns.Trail:Segments(fromDay)) do
		local r, g, b
		if ns.Omens:Broke(seg.author, seg.d) then
			r, g, b = BROKEN_COLOR[1], BROKEN_COLOR[2], BROKEN_COLOR[3]
		else
			r, g, b = ns.Color(seg.author)
		end
		local alpha = self.replay and 1 or ageAlpha(seg.d)
		local p = seg.p
		local prevX, prevY
		for i = 1, #p, 3 do
			local px, py = toMap(seg.c, p[i], p[i + 1], mapID)
			if px and prevX then
				if n >= MAX_LINES then
					return
				end
				n = n + 1
				self.lineCount = n
				local line = self:AcquireLine(n)
				line:SetStartPoint("TOPLEFT", self.lineFrame, prevX * w, -prevY * h)
				line:SetEndPoint("TOPLEFT", self.lineFrame, px * w, -py * h)
				line:SetThickness(thickness)
				line:SetColorTexture(r, g, b, alpha)
				line.ts = seg.ts + p[i + 2]
				line:Show()
			end
			prevX, prevY = px, py
		end
	end
end

function ProviderMixin:OnCanvasScaleChanged()
	local thickness = (self.replay and LINE_THICKNESS * 1.6 or LINE_THICKNESS) / self:GetMap():GetCanvasScale()
	for _, line in ipairs(self.lines) do
		line:SetThickness(thickness)
	end
end

function ProviderMixin:OnCanvasSizeChanged()
	self:RefreshAllData()
end

function ProviderMixin:StartReplay()
	local today = ns.Today()
	self.replay = { from = ns.DayStart(today), to = GetServerTime(), started = GetTime() }
	self:RefreshAllData()
	self.lineFrame:SetScript("OnUpdate", function()
		local progress = (GetTime() - self.replay.started) / REPLAY_SECONDS
		if progress >= 1 then
			self:StopReplay()
			return
		end
		local cutoff = self.replay.from + (self.replay.to - self.replay.from) * progress
		for i = 1, self.lineCount or 0 do
			local line = self.lines[i]
			line:SetShown(line.ts <= cutoff)
		end
	end)
end

function ProviderMixin:StopReplay()
	self.replay = nil
	self.lineFrame:SetScript("OnUpdate", nil)
	self:RefreshAllData()
end

local function fillMixin(target, source)
	for k, v in pairs(source) do
		if target[k] == nil then
			target[k] = v
		end
	end
end

local function attach()
	if provider or not WorldMapFrame or not MapCanvasDataProviderMixin then
		return
	end
	fillMixin(EmberpathCampPinMixin, MapCanvasPinMixin)
	fillMixin(EmberpathFriendPinMixin, MapCanvasPinMixin)
	worldVec = CreateVector2D(0, 0)
	provider = CreateFromMixins(MapCanvasDataProviderMixin, ProviderMixin)
	WorldMapFrame:AddDataProvider(provider)
end

local refreshPending = false
function Map:Refresh()
	if not provider or not WorldMapFrame:IsShown() or refreshPending then
		return
	end
	refreshPending = true
	C_Timer.After(0.5, function()
		refreshPending = false
		if WorldMapFrame:IsShown() then
			provider:RefreshAllData()
		end
	end)
end

function Map:StartReplay()
	attach()
	if not provider then
		ns.Print("The world map is not available.")
		return
	end
	if not WorldMapFrame:IsShown() then
		ToggleWorldMap()
	end
	local mapID = C_Map.GetBestMapForUnit("player")
	if mapID then
		WorldMapFrame:SetMapID(mapID)
	end
	provider:StartReplay()
end

function Map:Open()
	if not WorldMapFrame:IsShown() then
		ToggleWorldMap()
	end
end

ns:On("EP_READY", attach)
ns:On("ADDON_LOADED", function(name)
	if name == "Blizzard_WorldMap" then
		attach()
	end
end)

for _, event in ipairs({ "EP_RECORD", "EP_PRESENCE", "EP_TRAIL_MOVED", "EP_LAYERS_CHANGED" }) do
	ns:On(event, function(_, _, _, replay)
		if not replay then
			Map:Refresh()
		end
	end)
end
