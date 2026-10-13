class_name BWFightModule
extends TourneyModule
## The Black | White Twins fight as a tournament game: each player takes a
## thunder, fire and wind unit against Noon and Dusk. A human plays it on
## this machine; a bot's run is rolled. The faster win takes the match; a
## win beats a loss; two losses go to whoever lasted longer.

const ELEMENTS := ["thunder", "fire", "wind"]

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
		return "%s %s in %d rounds" % [p.name, "beat the Twins" if r.won else "fell", r.cycles]
	return { "winner": w.id, "summary": line.call(a, ra) + ".  " + line.call(b, rb) + ".", "stats": rs }


func _next() -> void:
	if _queue.is_empty():
		finished.emit(_decide(match_cfg, _results))
		return
	var p: Dictionary = _queue.pop_front()
	_play(p)


func _play(p: Dictionary) -> void:
	# A run at the Twins' fight, three units re-elemented, levelled and geared to it (as boot.gd's --boss twins).
	var seed_value := int(match_cfg.seed) + absi(hash(p.id))
	var trun := BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), seed_value)
	var tn := BWRun.TWINS_FIGHT
	for i in 3:
		var u: BWUnit = trun.squad[i]
		u.element = ELEMENTS[i]
		u.affinity = { ELEMENTS[i]: BWUnit.POINTS_PER_RANK }
		u.focus_element = ELEMENTS[i]
	for u in trun.squad:
		BWProgression.level_up(u, tn - u.level)
		BWPicks.auto_resolve(u)
		for slot in BWRun.ARMOR_SLOTS:
			var bases: Array = BWData.table("equipment").filter(func(r): return r.slot == slot)
			u.equipment[slot] = trun.make_item(str(bases[absi(hash(u.id + slot)) % bases.size()].id), trun.tier_for(tn))
		u.equipment["main_hand"] = trun.make_item(u.weapon_model, trun.tier_for(tn))
	trun.fight = tn
	var players: Array = trun.squad.slice(0, 3)
	trun.prepare_for_battle(players)
	var enemies := trun.enemies_for(tn, { "kind": BWRooms.BOSS, "boss": BWSchedule.TWINS, "map": BWRun.TWINS_MAP, "fight": tn, "enemies": [] })
	_screen = BWCombatScreen.new()
	_screen.configure("res://maps/%s.json" % BWRun.TWINS_MAP, players, enemies, [], seed_value)
	_screen.trust_fn = trun.trust_stage
	add_child(_screen)
	BWMusic.play("boss")
	var result: Array = await _screen.finished
	var battle: BWBattle = result[1]
	_results[p.id] = { "won": result[0] == "player", "cycles": maxi(1, battle.cycle) }
	await get_tree().create_timer(1.5).timeout
	_screen.queue_free()
	_screen = null
	_next()
