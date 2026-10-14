local _, ns = ...

local UI = {}
ns.UI = UI

UI.builders = {}
UI.refreshers = {}

local TABS = {
	{ key = "layers", label = "Map layers" },
	{ key = "fire", label = "Tonight's Fire" },
	{ key = "ledger", label = "Ledger" },
}

local frame
local tabButtons, panels = {}, {}

local function build()
	frame = CreateFrame("Frame", "EmberpathFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(460, 520)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	tinsert(UISpecialFrames, "EmberpathFrame")

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", 0, -5)
	title:SetText("Emberpath")

	for i, tab in ipairs(TABS) do
		local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		button:SetSize(140, 22)
		button:SetPoint("TOPLEFT", 12 + (i - 1) * 146, -30)
		button:SetText(tab.label)
		button:SetScript("OnClick", function()
			UI:Show(tab.key)
		end)
		tabButtons[tab.key] = button

		local panel = CreateFrame("Frame", nil, frame)
		panel:SetPoint("TOPLEFT", 14, -60)
		panel:SetPoint("BOTTOMRIGHT", -14, 12)
		panel:Hide()
		panels[tab.key] = panel
		UI.builders[tab.key](panel)
	end
end

function UI:Show(key, animate)
	if not frame then
		build()
	end
	self.current = key
	for k, panel in pairs(panels) do
		panel:SetShown(k == key)
		tabButtons[k]:SetEnabled(k ~= key)
	end
	frame:Show()
	self:Refresh()
	if animate and key == "fire" and panels.fire.PlayDraw then
		panels.fire:PlayDraw()
	end
end

function UI:Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		self:Show(self.current or "fire")
	end
end

function UI:Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	local refresh = self.refreshers[self.current]
	if refresh then
		refresh(panels[self.current])
	end
end

local refreshPending = false
local function scheduleRefresh(_, _, _, replay)
	if replay or refreshPending then
		return
	end
	refreshPending = true
	C_Timer.After(0.3, function()
		refreshPending = false
		UI:Refresh()
	end)
end

for _, event in ipairs({ "EP_RECORD", "EP_PEERS", "EP_PRESENCE", "EP_OMEN_DRAWN", "EP_HINT", "EP_GATHERING" }) do
	ns:On(event, scheduleRefresh)
end

function UI.Button(parent, text, width, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

function UI.Text(parent, template, width)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
	fs:SetJustifyH("LEFT")
	if width then
		fs:SetWidth(width)
		fs:SetWordWrap(true)
	end
	return fs
end

function UI.Scroll(parent, height)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	scroll:SetHeight(height)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(400, 10)
	scroll:SetScrollChild(child)
	return scroll, child
end
