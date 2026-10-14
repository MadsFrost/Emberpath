local _, ns = ...

-- Omens are chosen by index, so every friend must have the same deck.
-- Append new omens at the end and bump VERSION; never reorder or remove.
ns.DeckVersion = 1

ns.Deck = {
	{ id = "no_ah", kind = "restriction", text = "No auction house today.", icon = "Interface\\Icons\\INV_Misc_Coin_01", watch = { interaction = "Auctioneer" } },
	{ id = "no_mount", kind = "restriction", text = "No mount today. Your feet will do.", icon = "Interface\\Icons\\Ability_Mount_RidingHorse", watch = { mount = true } },
	{ id = "no_vendor", kind = "restriction", text = "Buy nothing and sell nothing at vendors.", icon = "Interface\\Icons\\INV_Misc_Bag_08", watch = { interaction = "Merchant" } },
	{ id = "no_mail", kind = "restriction", text = "Leave the mailbox alone today.", icon = "Interface\\Icons\\INV_Letter_15", watch = { interaction = "MailInfo" } },
	{ id = "no_flight", kind = "restriction", text = "No flight paths. The road is the point.", icon = "Interface\\Icons\\INV_Misc_Map_01", watch = { taxi = true } },
	{ id = "no_hearth", kind = "restriction", text = "No hearthstone. You sleep where you stop.", icon = "Interface\\Icons\\INV_Misc_Rune_01", watch = { spell = "Hearthstone" } },
	{ id = "no_bank", kind = "restriction", text = "No bank visits. Carry what you carry.", icon = "Interface\\Icons\\INV_Misc_Bag_10", watch = { interaction = "Banker" } },
	{ id = "fire_food", kind = "restriction", text = "Eat and drink only what you cooked at a fire.", icon = "Interface\\Icons\\INV_Misc_Food_15" },
	{ id = "no_flee", kind = "restriction", text = "No fleeing. Finish every fight you start.", icon = "Interface\\Icons\\Ability_Warrior_BattleShout" },
	{ id = "emotes_only", kind = "restriction", text = "No /say today. Speak only in emotes.", icon = "Interface\\Icons\\INV_Misc_Note_01" },
	{ id = "bow_quest", kind = "ritual", text = "/bow to every quest giver before you speak to them.", icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing" },
	{ id = "wave_road", kind = "ritual", text = "/wave at every player you pass on the road.", icon = "Interface\\Icons\\Ability_Rogue_Sprint" },
	{ id = "salute_guard", kind = "ritual", text = "/salute every guard you walk past.", icon = "Interface\\Icons\\INV_Misc_Spyglass_03" },
	{ id = "dance_fire", kind = "ritual", text = "/dance at every campfire you light.", icon = "Interface\\Icons\\Spell_Fire_Fire" },
	{ id = "thank_inn", kind = "ritual", text = "/thank every innkeeper and flight master you meet.", icon = "Interface\\Icons\\INV_Drink_04" },
	{ id = "cheer_ding", kind = "ritual", text = "/cheer every time you level up or gain a skill point.", icon = "Interface\\Icons\\INV_Misc_Gift_01" },
	{ id = "tale_each", kind = "ritual", text = "Leave a tale at every campfire you light.", icon = "Interface\\Icons\\INV_Misc_Book_09", watch = { goal = "tale" } },
	{ id = "new_camp", kind = "goal", text = "Camp somewhere you have never camped before.", icon = "Interface\\Icons\\INV_Misc_Map_01", watch = { goal = "newcamp" } },
	{ id = "three_fires", kind = "goal", text = "Light three campfires today.", icon = "Interface\\Icons\\Spell_Fire_Fire", watch = { goal = "camps", n = 3 } },
	{ id = "two_zones", kind = "goal", text = "Cross two zones on foot.", icon = "Interface\\Icons\\Spell_Nature_Swiftness" },
	{ id = "fish_camp", kind = "goal", text = "Catch a fish within sight of your campfire.", icon = "Interface\\Icons\\INV_Fishingpole_02" },
	{ id = "stranger", kind = "goal", text = "Share your fire with a stranger.", icon = "Interface\\Icons\\INV_Misc_Bandage_15" },
	{ id = "cook_new", kind = "goal", text = "Cook something you have never cooked before.", icon = "Interface\\Icons\\INV_Misc_Food_15" },
	{ id = "help_low", kind = "goal", text = "Help a lower-level player with a quest.", icon = "Interface\\Icons\\Spell_Holy_Heal" },
	{ id = "old_zone", kind = "goal", text = "Revisit a zone you have not seen in a week.", icon = "Interface\\Icons\\Spell_Shadow_Teleport" },
	{ id = "high_place", kind = "goal", text = "Camp at the highest point you can reach.", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01" },
}
