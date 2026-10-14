local _, ns = ...

local UI = ns.UI

UI.builders.ledger = function(panel)
	local header = UI.Text(panel, "GameFontNormalLarge")
	header:SetPoint("TOPLEFT", 2, 0)
	header:SetText("The Ember Ledger")

	local scroll, child = UI.Scroll(panel, 400)
	scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
	scroll:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
	panel.child = child
	panel.body = UI.Text(child, "GameFontHighlight", 396)
	panel.body:SetPoint("TOPLEFT", 2, 0)
	panel.body:SetSpacing(3)
end

UI.refreshers.ledger = function(panel)
	panel.body:SetText(ns.Ledger:BuildText())
	panel.child:SetHeight(panel.body:GetStringHeight() + 10)
end
