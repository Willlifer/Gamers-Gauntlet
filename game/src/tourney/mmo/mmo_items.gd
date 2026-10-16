class_name MmoItems
extends RefCounted
## The consumables bar (G52, the author: "give them healing potions or damage
## increase potions or something, the first time someone plays this they
## should be overwhelmed at the amount of options"). Eight items on the bar
## above the spells, Shift+1-8 (click works too), the same for every class
## and both raids. WoW Classic's kind: off the global cooldown, each on its
## own cooldown, no charges to run out of. They're abilities as far as MmoSim
## is concerned (MmoClasses.ability falls back to this list), so the same
## `fx` vocabulary runs them, plus `restore` (a share of max HP back, which
## doesn't count as healing done for the meter or the grade). Using one counts
## a second of activity (ITEM_BUSY) toward the grade, like a GCD would.
## Bots use them by `ai` (MmoBot._item).

const SLOT0 := 8                 ## bar slots 8-15 (Shift+1-8) are the items
const ITEM_BUSY := 1.0           ## activity credited per use (s)

const ITEMS := [
	{ "id": "item_heal", "name": "Major Healing Potion", "glyph": "potion", "col": "#d02a2a", "cd": 60.0, "gcd": false, "item": true,
		"tgt": "self", "anim": "none", "fx": [{ "restore": 0.35 }], "ai": "potion_heal",
		"desc": "Drink: restore 35% of your health at once." },
	{ "id": "item_mana", "name": "Major Mana Potion", "glyph": "potion", "col": "#2a5ad4", "cd": 60.0, "gcd": false, "item": true,
		"tgt": "self", "anim": "none", "fx": [{ "mana": 0.35 }], "ai": "potion_mana",
		"desc": "Drink: restore 35% of your mana (rage or energy, if that's what you run on)." },
	{ "id": "item_power", "name": "Elixir of Giants' Might", "glyph": "potion", "col": "#e08a1a", "cd": 90.0, "gcd": false, "item": true,
		"tgt": "self", "anim": "none", "fx": [{ "buff": { "dmg": 1.15, "heal": 1.15 }, "dur": 20.0, "id": "item_power" }], "ai": "potion_power",
		"desc": "Drink: 15% more damage and healing for 20 sec." },
	{ "id": "item_stone", "name": "Major Healthstone", "glyph": "gem", "col": "#3fbf4a", "cd": 120.0, "gcd": false, "item": true,
		"tgt": "self", "anim": "none", "fx": [{ "restore": 0.25 }], "ai": "stone",
		"desc": "Crush it: restore 25% of your health. A separate cooldown from your potions." },
	{ "id": "item_cleanse", "name": "Restorative Potion", "glyph": "potion", "col": "#d8d0a0", "cd": 90.0, "gcd": false, "item": true,
		"tgt": "self", "anim": "none", "fx": [{ "cleanse": true, "all": true }], "ai": "potion_cleanse",
		"desc": "Drink: wash off every burn, curse and crack on you (Cinderbrand too)." },
	{ "id": "item_speed", "name": "Swiftness Potion", "glyph": "boot", "col": "#4ab0c8", "cd": 60.0, "gcd": false, "item": true,
		"tgt": "self", "anim": "none", "fx": [{ "buff": { "speed": 1.5 }, "dur": 6.0, "id": "item_speed" }], "ai": "potion_speed",
		"desc": "Drink: run 50% faster for 6 sec. Out of the fire, into the ring, off with the brand." },
	{ "id": "item_stoneskin", "name": "Greater Stoneshield Potion", "glyph": "shield", "col": "#8a8a7a", "cd": 90.0, "gcd": false, "item": true,
		"tgt": "self", "anim": "none", "fx": [{ "buff": { "dr": 0.7 }, "dur": 10.0, "id": "item_stoneskin" }], "ai": "potion_shield",
		"desc": "Drink: take 30% less damage for 10 sec." },
	{ "id": "item_dynamite", "name": "Dense Dynamite", "glyph": "bomb", "col": "#b0402a", "cd": 45.0, "gcd": false, "item": true,
		"tgt": "enemy", "range": 30.0, "school": "fire", "anim": "none", "fx": [{ "aoe": 900.0, "r": 5.0, "at": "target" }], "ai": "dynamite",
		"desc": "Throw it at your target: 900 fire damage to every enemy within 5 m of it." },
]


static func item(id: String) -> Dictionary:
	for it: Dictionary in ITEMS:
		if str(it.id) == id:
			return it
	return {}


## The item on bar slot `slot` (SLOT0..SLOT0+7), or {}.
static func at_slot(slot: int) -> Dictionary:
	var i := slot - SLOT0
	return ITEMS[i] if i >= 0 and i < ITEMS.size() else {}
