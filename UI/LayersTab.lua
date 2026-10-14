local _, ns = ...

local UI = ns.UI

local LAYERS = {
	{ key = "trails", label = "Ghost trails (fade over a week)" },
	{ key = "camps", label = "Campfires" },
	{ key = "oldCamps", label = "Old campfires without tales" },
	{ key = "friends", label = "Friends' positions" },
}

local function checkbox(parent, label, get, set)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	local text = UI.Text(parent, "GameFontHighlight")
	text:SetPoint("LEFT", check, "RIGHT", 4, 0)
	text:SetText(label)
	check:SetScript("OnClick", function(self)
		set(self:GetChecked())
	end)
	check.Sync = function(self)
		self:SetChecked(get())
	end
	return check
end

UI.builders.layers = function(panel)
	local header = UI.Text(panel, "GameFontNormalLarge")
	header:SetPoint("TOPLEFT", 2, 0)
	header:SetText("World map layers")

	panel.checks = {}
	local anchor = header
	for i, layer in ipairs(LAYERS) do
		local check = checkbox(panel, layer.label, function()
			return ns.db.settings.layers[layer.key]
		end, function(value)
			ns.db.settings.layers[layer.key] = value
			ns:Fire("EP_LAYERS_CHANGED")
		end)
		check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -8 or -2)
		panel.checks[#panel.checks + 1] = check
		anchor = check
	end

	local live = checkbox(panel, "Share my live position with the circle", function()
		return ns.db.settings.shareLive
	end, function(value)
		ns.db.settings.shareLive = value
	end)
	live:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
	panel.checks[#panel.checks + 1] = live

	local openMap = UI.Button(panel, "Open world map", 200, function()
		ns.Map:Open()
	end)
	openMap:SetPoint("TOPLEFT", live, "BOTTOMLEFT", 2, -16)
	local replay = UI.Button(panel, "Replay today's trails", 200, function()
		ns.Map:StartReplay()
	end)
	replay:SetPoint("LEFT", openMap, "RIGHT", 8, 0)

	local pitch = UI.Button(panel, "Pitch camp here", 200, function()
		ns.Campfires:Pitch("manual")
	end)
	pitch:SetPoint("TOPLEFT", openMap, "BOTTOMLEFT", 0, -8)
	local tale = UI.Button(panel, "Tell a tale at the nearest fire", 200, function()
		ns.Campfires:TaleAtNearest("")
	end)
	tale:SetPoint("LEFT", pitch, "RIGHT", 8, 0)

	panel.info = UI.Text(panel, "GameFontHighlightSmall", 420)
	panel.info:SetPoint("TOPLEFT", pitch, "BOTTOMLEFT", 0, -20)
	panel.info:SetSpacing(3)
end

UI.refreshers.layers = function(panel)
	for _, check in ipairs(panel.checks) do
		check:Sync()
	end
	local settings = ns.db.settings
	local online = 0
	for _ in pairs(ns.Comm:OnlinePeers()) do
		online = online + 1
	end
	panel.info:SetText(table.concat({
		"Friends online with Emberpath: " .. online,
		"Records in your journal: " .. ns.store:Count(),
		"Gathering hour: " .. (settings.gatherHour and (settings.gatherHour .. ":00 local time") or "off") .. "  (/ember gatherhour)",
		"New day starts: " .. settings.resetHourUTC .. ":00 UTC  (/ember reset)",
		"Sync: guild" .. (IsInGroup() and " and group" or "") .. (IsInGuild() and "" or " (you are not in a guild)"),
	}, "\n"))
end
