class_name BWFightModule
extends TourneyModule
## The Black | White Twins fight as a tournament game: each player takes a
## thunder, fire and wind unit against Noon and Dusk. A human plays it on
## this machine; a bot's run is rolled. The author's rule (10-13): the win
## in the fewest turns takes it; a win beats a loss; two losses go to whoever
## lasted longer. Wanted later: the room votes the winner instead.

## G50 (author 10-16): the three each carry two elements and two weapons.
## The first element is native (hair, focus); every element skill offers both
## (the element buttons on each skill). The first weapon is drawn at the
## start, the second is carried: Swap under Attack, free and unlimited
## (Black | White's D181/D195). Fire is set faster than everyone on the court
## so it goes first.
const KITS := [
	{ "role": "thunder", "elements": ["thunder", "dark"], "weapons": ["bow", "staff"] },
	{ "role": "fire", "elements": ["fire", "dark"], "weapons": ["lance", "staff"] },
	{ "role": "wind", "elements": ["wind", "thunder"], "weapons": ["bow", "daggers"] },
]
const FIRST := 1         ## KITS index that acts first

## Tools: true rolls the human's run too instead of opening the fight.
static var scripted := false

var _results := {}       # player id -> { won, cycles }
var _queue: Array = []   # humans still to play
var _screen: BWCombatScreen
var _rng := RandomNumberGenerator.new()


static func info() -> Dictionary:
	return { "id": "bw_twins", "name": "Black | White: the Twins", "players": 2,
		"blurb": "Thunder, fire and wind against Noon and Dusk. Fastest win takes it." }


func setup(m: Dictionary) -> void:
	super.setup(m)
	_rng.seed = int(m.seed)
	for p in m.players:
		if p.bot or scripted:
			_results[p.id] = _roll(_rng)
		else:
			_queue.append(p)
	_next.call_deferred()


static func _roll(rng: RandomNumberGenerator) -> Dictionary:
	var won := rng.randf() < 0.55
	return { "won": won, "cycles": rng.randi_range(6, 13) if won else rng.randi_range(4, 10) }


static func simulate(m: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	rng.seed = int(m.seed)
	var rs := {}
	for p in m.players:
		rs[p.id] = _roll(rng)
	return _decide(m, rs)


static func _decide(m: Dictionary, rs: Dictionary) -> Dictionary:
	var a: Dictionary = m.players[0]
	var b: Dictionary = m.players[1]
	var ra: Dictionary = rs[a.id]
	var rb: Dictionary = rs[b.id]
	var w: Dictionary
	if ra.won != rb.won:
		w = a if ra.won else b
	elif ra.won:
		w = a if ra.cycles <= rb.cycles else b
	else:
		w = a if ra.cycles >= rb.cycles else b
	var line := func(p: Dictionary, r: Dictionary) -> String:
		return "%s %s in %d turns" % [p.name, "beat the Twins" if r.won else "fell", r.cycles]
	return { "winner": w.id, "summary": line.call(a, ra) + ".  " + line.call(b, rb) + ".", "stats": rs }


func _next() -> void:
	if _queue.is_empty():
		finished.emit(_decide(match_cfg, _results))
		return
	var p: Dictionary = _queue.pop_front()
	_play(p)


func _play(p: Dictionary) -> void:
	var seed_value := int(match_cfg.seed) + absi(hash(p.id))
	var fight := build_fight(seed_value)
	var players: Array = fight.players
	var enemies: Array = fight.enemies
	var trun: BWRun = fight.run
	_screen = BWCombatScreen.new()
	_screen.configure("res://maps/%s.json" % BWRun.TWINS_MAP, players, enemies, [], seed_value)
	_screen.trust_fn = trun.trust_stage
	add_child(_screen)
	GGAnim.float_twins_under(_screen)        # G55: Noon and Dusk glide with godly floating
	TourneyMusic.play("boss")
	var result: Array = await _screen.finished
	var battle: BWBattle = result[1]
	_results[p.id] = { "won": result[0] == "player", "cycles": maxi(1, battle.cycle) }
	await get_tree().create_timer(1.5).timeout
	_screen.queue_free()
	_screen = null
	_next()


## The fight's units (as boot.gd's --boss twins): a run at the Twins' fight,
## its first three given the KITS, levelled and geared to it; the Twins (Noon
## and Dusk) are `enemies`. A look or a movement style for either side goes
## on these units before the combat screen is configured.
## Returns { run, players, enemies }.
static func build_fight(seed_value: int) -> Dictionary:
	var trun := BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), seed_value)
	var tn := BWRun.TWINS_FIGHT
	var carried := {}                           # unit id -> the second weapon's model
	for i in KITS.size():
		var u: BWUnit = trun.squad[i]
		var kit: Dictionary = KITS[i]
		u.element = str(kit.elements[0])
		u.affinity = {}
		for el in kit.elements:
			u.affinity[el] = BWUnit.POINTS_PER_RANK
		u.focus_element = u.element
		var main := _model_for(u, str(kit.weapons[0]))
		carried[u.id] = _model_for(u, str(kit.weapons[1]))
		u.weapon_class = str(kit.weapons[0])
		u.weapon_model = main
	for u in trun.squad:
		BWProgression.level_up(u, tn - u.level)
		BWPicks.auto_resolve(u)
		for slot in BWRun.ARMOR_SLOTS:
			var bases: Array = BWData.table("equipment").filter(func(r): return r.slot == slot)
			u.equipment[slot] = trun.make_item(str(bases[absi(hash(u.id + slot)) % bases.size()].id), trun.tier_for(tn))
		u.equipment["main_hand"] = trun.make_item(u.weapon_model, trun.tier_for(tn))
	for i in KITS.size():
		var u: BWUnit = trun.squad[i]
		var kit: Dictionary = KITS[i]
		u.equipment[BWUnit.SECOND] = trun.make_item(str(carried[u.id]), trun.tier_for(tn))
		u.expertise[str(kit.weapons[1])] = int(u.expertise.get(u.weapon_class, 0))   # the carried class as trained as the drawn one
		var top := int(u.affinity.get(u.element, 0))
		for el in kit.elements:
			u.affinity[el] = maxi(int(u.affinity.get(el, 0)), top)                # both elements at the same rank
		u.sync_weapon()
		u.refresh_effects()
	trun.fight = tn
	var players: Array = trun.squad.slice(0, KITS.size())
	trun.prepare_for_battle(players)
	var enemies := trun.enemies_for(tn, { "kind": BWRooms.BOSS, "boss": BWSchedule.TWINS, "map": BWRun.TWINS_MAP, "fight": tn, "enemies": [] })
	_fire_first(players[FIRST], players + enemies)
	return { "run": trun, "players": players, "enemies": enemies }


## The unit's own model when it already holds that class, else the class's first main-hand row.
static func _model_for(u: BWUnit, wc: String) -> String:
	if u.weapon_class == wc:
		return u.weapon_model
	for r in BWData.table("equipment"):
		if str(r.slot) == "main_hand" and str(r.weight) == wc:
			return str(r.id)
	return wc


## The fastest a unit can be at a turn start, either weapon drawn (or the slowest, `slow`).
static func speed_span(u: BWUnit, slow: bool = false) -> int:
	var s := u.speed()
	if not u.second_weapon().is_empty():
		u.swap_weapons()
		s = mini(s, u.speed()) if slow else maxi(s, u.speed())
		u.swap_weapons()
	return s


## G50: `u` outpaces everyone in `all` with either weapon drawn, so it opens every cycle.
static func _fire_first(u: BWUnit, all: Array) -> void:
	var fastest := 0
	for o: BWUnit in all:
		if o != u:
			fastest = maxi(fastest, speed_span(o))
	var need := fastest + 1 - speed_span(u, true)
	if need > 0:
		u.stats["spd"] = int(u.stats.get("spd", 0)) + need
