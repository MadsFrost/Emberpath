local _, ns = ...

local FIRE_ICON = "Interface\\Icons\\Spell_Fire_Fire"
local FRIEND_ICON = "Interface\\WorldMap\\WorldMapPartyIcon"

-- MapCanvasPinMixin is filled in by Map\Provider.lua once Blizzard_WorldMap has loaded.
EmberpathCampPinMixin = {}
EmberpathFriendPinMixin = {}

function EmberpathCampPinMixin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self:SetScalingLimits(1, 0.9, 1.4)
end

function EmberpathCampPinMixin:OnAcquired(camp, px, py)
	self.camp = camp
	self.Icon:SetTexture(FIRE_ICON)
	local age = ns.Today() - camp.d
	self.Icon:SetDesaturated(age > 0)
	self:SetAlpha(age > ns.db.settings.retentionDays and 0.6 or 1)
	local omen = ns.Omens:RevealedOmen(camp.author, camp.d)
	if omen then
		self.Omen:SetTexture(omen.icon)
		self.Omen:Show()
	else
		self.Omen:Hide()
	end
	self.Tale:SetShown(ns.Campfires:Tales(camp.id) ~= nil)
	self:SetPosition(px, py)
end

function EmberpathCampPinMixin:OnMouseEnter()
	local camp = self.camp
	local r, g, b = ns.Color(camp.author)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(ns.Short(camp.author) .. "'s campfire", r, g, b)
	GameTooltip:AddLine(ns.DayLabel(camp.d) .. ", " .. date("%H:%M", camp.ts), 0.8, 0.8, 0.8)
	local omen = ns.Omens:RevealedOmen(camp.author, camp.d)
	if omen then
		local broke = ns.Omens:Broke(camp.author, camp.d)
		GameTooltip:AddLine("During the omen: " .. omen.text, 1, broke and 0.4 or 0.82, broke and 0.3 or 0, true)
	end
	for _, tale in ipairs(ns.Campfires:Tales(camp.id) or {}) do
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("\"" .. ns.Escape(tale.text) .. "\"", 1, 1, 1, true)
		GameTooltip:AddLine("- " .. ns.Short(tale.author), 0.7, 0.7, 0.7)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Right-click to leave a tale", 0.5, 0.8, 1)
	GameTooltip:Show()
end

function EmberpathCampPinMixin:OnMouseLeave()
	GameTooltip:Hide()
end

function EmberpathCampPinMixin:OnMouseUp(button)
	if button == "RightButton" then
		ns.Campfires:PromptTale(self.camp.id)
	end
end

function EmberpathFriendPinMixin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_GROUP_MEMBER")
	self:SetScalingLimits(1, 1, 1.2)
end

function EmberpathFriendPinMixin:OnAcquired(author, presence, px, py)
	self.author = author
	self.presence = presence
	self.Icon:SetTexture(FRIEND_ICON)
	self.Icon:SetVertexColor(ns.Color(author))
	self.Glow:SetShown(presence.f)
	self:SetPosition(px, py)
end

function EmberpathFriendPinMixin:OnMouseEnter()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(ns.Short(self.author), ns.Color(self.author))
	if self.presence.f then
		GameTooltip:AddLine("Sitting by a campfire", 1, 0.6, 0.2)
	end
	GameTooltip:Show()
end

function EmberpathFriendPinMixin:OnMouseLeave()
	GameTooltip:Hide()
end
