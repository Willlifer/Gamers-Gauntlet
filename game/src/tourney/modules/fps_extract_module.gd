class_name FpsExtractModule
extends TourneyModule
## FPS: Extraction. A one-life raid on the seeded forest campus
## (ExtractWorld): loot chests and guards, get to the flare before the clock.
## Both contestants raid the same seed alone, judged like the OSRS trial:
## extracted beats died, then more $, then faster. Offline the human on this
## machine plays; the other seat's run is rolled (simulate / bot_run) so the
## match has a winner.

var _human: Dictionary
var _other: Dictionary
var _bot_run := {}


static func info() -> Dictionary:
	return { "id": "fps_extract", "name": "FPS: Extraction", "players": 2,
		"blurb": "One life on a seeded forest campus. Start with a pistol; loot chests and the green guards for guns, mags, armour and cash. The extract flares at 2:30: get there with the most." }


static func simulate(m: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	rng.seed = int(m.seed)
	var a: Dictionary = m.players[0]
	var b: Dictionary = m.players[1]
	var ra := bot_run(int(m.seed) * 7 + 101)
	var rb := bot_run(int(m.seed) * 7 + 202)
	var w: Dictionary = a if ExtractWorld.beats(ra, rb) else b
	return { "winner": w.id, "summary": _summary(a, ra, b, rb), "stats": {} }


## A rolled raid: extracted 55% of the time, with what it found and when.
static func bot_run(bot_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = bot_seed
	var extracted := rng.randf() < 0.55
	var cash := 150 + rng.randi_range(0, 10) * 85 + (rng.randi_range(0, 6) * 120 if extracted else 0)
	var t := FpsTune.value("extract_time")
	var secs := rng.randf_range(t - FpsTune.value("extract_reveal") + 20.0, t - 5.0) if extracted else rng.randf_range(40.0, t)
	return { "how": "extracted" if extracted else "died", "cash": cash, "secs": secs, "where": ["in the lodge", "in the barn", "in the woods", "by the chapel"][rng.randi() % 4] }


static func _summary(a: Dictionary, ra: Dictionary, b: Dictionary, rb: Dictionary) -> String:
	return "%s; %s." % [ExtractWorld.line(a, ra), ExtractWorld.line(b, rb)]


func setup(m: Dictionary) -> void:
	super.setup(m)
	_human = m.players[0]
	for p in m.players:
		if not p.get("bot", false):
			_human = p
			break
	for p in m.players:
		if p != _human:
			_other = p
			break
	_bot_run = bot_run(int(m.get("seed", 0)) * 13 + 5)
	var world := ExtractWorld.new()
	world.match_seed = int(m.get("seed", -1))
	world.run_over.connect(func(r: Dictionary) -> void:
		var won := ExtractWorld.beats(r, _bot_run)
		finished.emit({ "winner": _human.id if won else _other.id, "summary": _summary(_human, r, _other, _bot_run), "stats": {} }))
	add_child(world)
	TourneyMusic.play("fight")
