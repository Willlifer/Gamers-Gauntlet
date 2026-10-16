class_name TourneyState
extends RefCounted
## One evening: who is in the lobby, their coins, the bracket, every match's
## game and result, and the bets. Pure data; the screens read and write it.
## The local player's profile and keybinds persist in user://tourney.cfg.

const CFG := "user://tourney.cfg"
const COINS_PER_GAME := 5
const BET_MIN := 5
const BET_MAX := 25
const HOUSE_PER_SIDE := 5
const MIN_PLAYERS := 4
const MAX_PLAYERS := 8
const TITLES := ["Rookie", "Contender", "Veteran", "Menace", "Legend", "Washed", "Sweat", "Casual"]
const BOT_NAMES := ["Gorbo", "Nina", "Tusk", "Pip", "Vexley", "Mort", "Juno", "Blaze"]
const HAIR_COLOURS := ["#f2f2f2", "#1a1a1a", "#e0b040", "#c43c2a", "#3a7bd5", "#6b3fa0", "#2fa36b", "#ff7ab8", "#8b5a2b", "#20c0d0"]

var join_code := ""
var players: Array = []        # { id, name, title, exp, hair_style, hair_hex, bot, ready, coins, wins, losses }
var modules: Array = []        # module ids in the pool (TourneyModules.POOL)
var bracket: TourneyBracket
var bets := {}                 # match id -> { player id: { side, amount } }
var log: Array = []            # { match, game, winner, loser, comments: [{ who, text }] }
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()
	join_code = _code()


func _code() -> String:
	var letters := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var s := ""
	for i in 5:
		s += letters[rng.randi() % letters.length()]
	return s


func me() -> Dictionary:
	for p in players:
		if not p.bot:
			return p
	return {}


func player(id: String) -> Dictionary:
	for p in players:
		if p.id == id:
			return p
	return {}


func add_local(profile: Dictionary) -> Dictionary:
	var p := _blank("you", false)
	p.merge(profile, true)
	players.append(p)
	return p


func add_bot() -> Dictionary:
	if players.size() >= MAX_PLAYERS:
		return {}
	var used := players.map(func(x): return x.name)
	var names := BOT_NAMES.filter(func(n): return not n in used)
	var p := _blank("bot%d" % players.size(), true)
	p.name = names[rng.randi() % names.size()] if not names.is_empty() else "Bot %d" % players.size()
	p.title = TITLES[rng.randi() % TITLES.size()]
	p.exp = ["new", "some", "lots"][rng.randi() % 3]
	p.hair_style = BWHair.styles()[rng.randi() % BWHair.styles().size()]
	p.hair_hex = HAIR_COLOURS[rng.randi() % HAIR_COLOURS.size()]
	_random_look(p)
	p.ready = true
	players.append(p)
	return p


func remove_bot() -> void:
	for i in range(players.size() - 1, -1, -1):
		if players[i].bot:
			players.remove_at(i)
			return


func _blank(id: String, bot: bool) -> Dictionary:
	var p := { "id": id, "bot": bot, "ready": false, "coins": 0, "wins": 0, "losses": 0 }
	p.merge(DEFAULT_LOOK, true)
	return p


## Everything the creator sets. Armour "" = none.
const DEFAULT_LOOK := { "name": "Player", "title": "Rookie", "exp": "new", "hair_style": "buzzed",
	"hair_hex": "#e0b040", "weapon": "sword", "top": "tshirt", "bottom": "sweatpants", "shade": "mid",
	"head": "", "chest": "", "legs": "" }
const SHADES := ["light", "mid", "dark"]


## Weapon models by class, for the creator (benched classes included: it's a look).
static func weapon_models() -> Array:
	var out: Array = []
	for id in BWWeaponView.ids():
		var c := str(BWWeaponView.meta_for(id).get("class", ""))
		if c != "":
			out.append(id)
	out.sort_custom(func(a, b):
		var ca := str(BWWeaponView.meta_for(a).class)
		var cb := str(BWWeaponView.meta_for(b).class)
		return ca < cb or (ca == cb and a < b))
	return out


## Armour pieces that have a model, for one slot ("" first = none).
static func armour_for(slot: String) -> Array:
	var out: Array = [""]
	for r in BWData.table("equipment"):
		if str(r.slot) == slot and BWEquipmentView.has_model(str(r.id)):
			out.append(str(r.id))
	return out


func _random_look(p: Dictionary) -> void:
	random_look(p, rng)


## A random outfit (weapon, clothes, shade, armour) from `r`: bots at seating, the creator's dice (G50).
static func random_look(p: Dictionary, r: RandomNumberGenerator) -> void:
	var w := weapon_models()
	p.weapon = w[r.randi() % w.size()]
	p.top = BWClothing.TOPS[r.randi() % BWClothing.TOPS.size()]
	p.bottom = BWClothing.BOTTOMS[r.randi() % BWClothing.BOTTOMS.size()]
	p.shade = SHADES[r.randi() % SHADES.size()]
	for slot in ["head", "chest", "legs"]:
		var a := armour_for(slot)
		p[slot] = a[r.randi() % a.size()] if r.randf() < 0.4 else ""


func all_ready() -> bool:
	return players.size() >= MIN_PLAYERS and players.all(func(p): return p.ready)


## The BWUnit that stands in for a player on the emote stages.
func unit_for(p: Dictionary) -> BWUnit:
	var u := BWUnit.new()
	u.id = str(p.id)
	u.name = str(p.name)
	u.team = "player"
	u.element = ""
	u.weapon_model = str(p.get("weapon", "sword"))
	u.weapon_class = str(BWWeaponView.meta_for(u.weapon_model).get("class", "sword"))
	u.cosmetics = { "hair_style": str(p.hair_style), "hair_hex": str(p.hair_hex), "gender": "a",
		"top": str(p.get("top", "tshirt")), "bottom": str(p.get("bottom", "sweatpants")),
		"clothing_shade": str(p.get("shade", "mid")) }
	for slot in ["head", "chest", "legs"]:
		if str(p.get(slot, "")) != "":
			u.equipment[slot] = { "base": str(p[slot]), "id": str(p[slot]) }
	for s in BWUnit.STATS:
		u.stats[s] = 5
	u.hp = u.max_hp()
	return u


# ---------------------------------------------------------------- coins

func hand_out_coins() -> void:
	for p in players:
		p.coins += COINS_PER_GAME


func place_bet(match_id: String, pid: String, side: String, amount: int) -> bool:
	var p := player(pid)
	amount = clampi(amount, BET_MIN, BET_MAX)
	if p.is_empty() or p.coins < amount:
		return false
	if not bets.has(match_id):
		bets[match_id] = {}
	if bets[match_id].has(pid):
		return false
	p.coins -= amount
	bets[match_id][pid] = { "side": side, "amount": amount }
	return true


## Pay the pot (the house's 5 a side + every bet) to the winner's backers,
## split by stake. Returns { player id: payout }.
func settle(match_id: String, winner: String) -> Dictionary:
	var pot := HOUSE_PER_SIDE * 2
	var stakes := {}
	var total_win := 0
	for pid in bets.get(match_id, {}):
		var b: Dictionary = bets[match_id][pid]
		pot += int(b.amount)
		if b.side == winner:
			stakes[pid] = int(b.amount)
			total_win += int(b.amount)
	var out := {}
	if total_win == 0:
		return out
	for pid in stakes:
		var share := int(floor(pot * float(stakes[pid]) / total_win))
		player(pid).coins += share
		out[pid] = share
	return out


# ------------------------------------------------------------ persistence

static func load_profile() -> Dictionary:
	var cf := ConfigFile.new()
	var out := DEFAULT_LOOK.duplicate()
	out.name = "You"
	if cf.load(CFG) != OK:
		return out
	for k in out:
		out[k] = cf.get_value("profile", k, out[k])
	return out


static func save_profile(p: Dictionary) -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	for k in DEFAULT_LOOK:
		cf.set_value("profile", k, p.get(k, DEFAULT_LOOK[k]))
	cf.save(CFG)


const DEFAULT_BINDS := { "q": KEY_Q, "w": KEY_W, "e": KEY_E, "r": KEY_R, "flash": KEY_D, "spell2": KEY_F,
	"stop": KEY_S, "recall": KEY_B }
const DEFAULT_SENS := { "mouse": 1.0, "camera_lock": true }


static func load_binds() -> Dictionary:
	var cf := ConfigFile.new()
	var out := DEFAULT_BINDS.duplicate()
	if cf.load(CFG) == OK:
		for k in out:
			out[k] = int(cf.get_value("binds", k, out[k]))
	return out


static func save_binds(b: Dictionary) -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	for k in b:
		cf.set_value("binds", k, int(b[k]))
	cf.save(CFG)


static func load_sens() -> Dictionary:
	var cf := ConfigFile.new()
	var out := DEFAULT_SENS.duplicate()
	if cf.load(CFG) == OK:
		for k in out:
			out[k] = cf.get_value("sens", k, out[k])
	return out


static func save_sens(s: Dictionary) -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	for k in s:
		cf.set_value("sens", k, s[k])
	cf.save(CFG)
