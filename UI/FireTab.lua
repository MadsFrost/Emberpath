local _, ns = ...

local UI = ns.UI

local CARD_BACK_ICON = "Interface\\Icons\\Spell_Fire_Fire"
local KIND_LABEL = { restriction = "A restriction", ritual = "A ritual", goal = "A goal" }
local ROW_HEIGHT = 40
local MAX_ROWS = 20

local function makeCard(panel)
	local card = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	card:SetSize(430, 104)
	card:SetPoint("TOPLEFT", 0, -22)
	card:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	card:SetBackdropBorderColor(1, 0.55, 0.1)

	card.glow = card:CreateTexture(nil, "BACKGROUND", nil, 1)
	card.glow:SetTexture(CARD_BACK_ICON)
	card.glow:SetSize(76, 76)
	card.glow:SetPoint("LEFT", 6, 0)
	card.glow:SetBlendMode("ADD")
	card.glow:SetAlpha(0.35)
	local flicker = card.glow:CreateAnimationGroup()
	flicker:SetLooping("BOUNCE")
	local fade = flicker:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.2)
	fade:SetToAlpha(0.6)
	fade:SetDuration(0.7)
	flicker:Play()

	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(56, 56)
	card.icon:SetPoint("LEFT", 16, 0)

	card.kind = UI.Text(card, "GameFontNormalSmall")
	card.kind:SetPoint("TOPLEFT", 86, -14)
	card.text = UI.Text(card, "GameFontHighlightLarge", 320)
	card.text:SetPoint("TOPLEFT", card.kind, "BOTTOMLEFT", 0, -6)

	card.reveal = card:CreateAnimationGroup()
	local alpha = card.reveal:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.9)
	alpha:SetSmoothing("OUT")
	local scale = card.reveal:CreateAnimation("Scale")
	if scale.SetScaleFrom then
		scale:SetScaleFrom(0.85, 0.85)
		scale:SetScaleTo(1, 1)
	else
		scale:SetScale(1.15, 1.15)
	end
	scale:SetDuration(0.6)
	scale:SetSmoothing("OUT")
	return card
end

local function makeRow(parent, i)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(400, ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
	row.name = UI.Text(row, "GameFontNormal")
	row.name:SetPoint("TOPLEFT", 4, -3)
	row.status = UI.Text(row, "GameFontHighlightSmall", 270)
	row.status:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
	row.status:SetMaxLines(2)
	row.believe = UI.Button(row, "Believe", 62, function()
		ns.Omens:Vote(row.author, true)
	end)
	row.believe:SetPoint("TOPRIGHT", -66, -8)
	row.doubt = UI.Button(row, "Doubt", 62, function()
		ns.Omens:Vote(row.author, false)
	end)
	row.doubt:SetPoint("TOPRIGHT", 0, -8)
	return row
end

UI.builders.fire = function(panel)
	panel.title = UI.Text(panel, "GameFontNormalLarge")
	panel.title:SetPoint("TOPLEFT", 2, 0)
	panel.card = makeCard(panel)

	panel.draw = UI.Button(panel, "Draw your omen", 140, function()
		local _, fresh = ns.Omens:Draw()
		UI:Refresh()
		if fresh then
			panel:PlayDraw()
		end
	end)
	panel.draw:SetPoint("TOPLEFT", panel.card, "BOTTOMLEFT", 0, -8)
	panel.revealButton = UI.Button(panel, "Reveal at the fire", 140, function()
		ns.Omens:Reveal()
	end)
	panel.revealButton:SetPoint("TOPLEFT", panel.card, "BOTTOMLEFT", 0, -8)
	panel.honored = UI.Button(panel, "I honored it", 110, function()
		ns.Omens:SetVerdict(true)
	end)
	panel.honored:SetPoint("TOPLEFT", panel.card, "BOTTOMLEFT", 0, -8)
	panel.broken = UI.Button(panel, "I broke it", 110, function()
		ns.Omens:SetVerdict(false)
	end)
	panel.broken:SetPoint("LEFT", panel.honored, "RIGHT", 6, 0)

	panel.hint = UI.Text(panel, "GameFontHighlightSmall", 430)
	panel.hint:SetPoint("TOPLEFT", panel.card, "BOTTOMLEFT", 0, -36)

	panel.flare = UI.Text(panel, "GameFontNormal", 430)
	panel.flare:SetPoint("TOPLEFT", panel.hint, "BOTTOMLEFT", 0, -8)
	panel.flare:SetTextColor(1, 0.55, 0.1)

	local header = UI.Text(panel, "GameFontNormal")
	header:SetPoint("TOPLEFT", panel.card, "BOTTOMLEFT", 0, -88)
	header:SetText("The circle")

	local scroll, child = UI.Scroll(panel, 200)
	scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	scroll:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
	panel.rowParent = child
	panel.rows = {}

	function panel:PlayDraw()
		self.card.reveal:Stop()
		self.card.reveal:Play()
		PlaySound(SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_OPEN or 829)
	end
end

local function statusFor(author, day)
	local O = ns.Omens
	local parts = {}
	local info = O:RevealInfo(author, day)
	if info then
		if info.ok == nil then
			parts[#parts + 1] = "revealed, checking..."
		elseif not info.ok then
			parts[#parts + 1] = "|cffff4040revealed an omen that does not match their draw!|r"
		elseif info.deckMismatch then
			parts[#parts + 1] = "|cff60ff60verified|r (different deck version, update Emberpath)"
		else
			parts[#parts + 1] = (info.omen and info.omen.text or "?") .. " |cff60ff60verified|r"
		end
	elseif O:HasDrawn(author, day) then
		parts[#parts + 1] = "drew an omen (hidden until the Gathering)"
	else
		parts[#parts + 1] = "no omen drawn yet"
	end
	local verdict = O:Verdict(author, day)
	if verdict ~= nil then
		local believe, doubt = O:VoteTally(author, day)
		parts[#parts + 1] = string.format("%s, %d believe, %d doubt",
			verdict and "|cff60ff60says honored|r" or "|cffff5040says broken|r", believe, doubt)
	end
	return table.concat(parts, "\n")
end

UI.refreshers.fire = function(panel)
	local O = ns.Omens
	local day = ns.Today()
	panel.title:SetText("Tonight's Fire: " .. ns.DayLabel(day))

	local drawn = O:HasDrawn(ns.me, day)
	local omen = drawn and O:MyOmen(day)
	local card = panel.card
	if omen then
		card.icon:SetTexture(omen.icon)
		card.kind:SetText(KIND_LABEL[omen.kind] .. ", for your eyes only")
		card.text:SetText(omen.text)
	elseif drawn then
		card.icon:SetTexture(CARD_BACK_ICON)
		card.kind:SetText("Your omen")
		card.text:SetText("This character lost its omen seed, so today's omen cannot be shown.")
	else
		card.icon:SetTexture(CARD_BACK_ICON)
		card.kind:SetText("Your omen awaits")
		card.text:SetText("Pitch your first camp of the day to draw it, or draw it now.")
	end

	local revealed = O.reveals[ns.me] and O.reveals[ns.me][day] ~= nil
	local verdict = O:Verdict(ns.me, day)
	panel.draw:SetShown(not drawn)
	panel.revealButton:SetShown(drawn and not revealed and omen ~= nil)
	panel.honored:SetShown(revealed)
	panel.broken:SetShown(revealed)
	panel.honored:SetEnabled(verdict ~= true)
	panel.broken:SetEnabled(verdict ~= false)

	local hint = ns.char.hints[day]
	if hint then
		local color = hint.state == "broken" and "|cffff5040" or "|cff60ff60"
		panel.hint:SetText(color .. "The embers whisper: " .. hint.why .. ".|r")
	else
		panel.hint:SetText("")
	end
	panel.flare:SetText(ns.Gathering:HasFlared(day) and "The fire flares! Reveal your omens and judge each other." or "")

	local authors, seen = {}, {}
	local function add(author)
		if not seen[author] then
			seen[author] = true
			authors[#authors + 1] = author
		end
	end
	add(ns.me)
	for _, author in ipairs(O:AuthorsWithDraw(day)) do
		add(author)
	end
	for author in pairs(ns.Comm:OnlinePeers()) do
		add(author)
	end
	table.sort(authors, function(a, b)
		if a == ns.me or b == ns.me then
			return a == ns.me
		end
		return a < b
	end)

	local online = ns.Comm:OnlinePeers()
	for i = 1, math.min(#authors, MAX_ROWS) do
		local row = panel.rows[i] or makeRow(panel.rowParent, i)
		panel.rows[i] = row
		local author = authors[i]
		row.author = author
		local r, g, b = ns.Color(author)
		local dot = (author == ns.me or online[author]) and " |cff60ff60(online)|r" or ""
		row.name:SetText(ns.Short(author) .. dot)
		row.name:SetTextColor(r, g, b)
		row.status:SetText(statusFor(author, day))
		local canVote = author ~= ns.me and O:Verdict(author, day) ~= nil
		local _, _, mine = O:VoteTally(author, day)
		row.believe:SetShown(canVote)
		row.doubt:SetShown(canVote)
		row.believe:SetEnabled(mine ~= true)
		row.doubt:SetEnabled(mine ~= false)
		row:Show()
	end
	for i = #authors + 1, #panel.rows do
		panel.rows[i]:Hide()
	end
	panel.rowParent:SetHeight(math.max(10, #authors * ROW_HEIGHT))
end
