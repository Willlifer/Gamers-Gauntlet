class_name PitModule
extends AramModule
## MOBA: Objective take. Each player leads a team of three (themself and two
## bot allies) into a pit around the Giant. It turns on whoever comes
## closest and telegraphs slams and novas. Fight the other team, keep the
## boss's attention off you, and land the kill: smite does 600 true damage.
## Whoever's team lands the last hit wins (about 1.5 minutes).
## G54: the Giant sits off centre among rocks; each player's champion has
## 2x health and damage and is the only one with smite; V / C ping your bot
## allies to go in or hold (MobaSim.pings, MobaBot._answer_ping).

const ALLIES := 2


static func info() -> Dictionary:
	return { "id": "pit", "name": "MOBA: Objective take", "players": 2,
		"blurb": "3v3 around the Giant in its pit. Smite in hand; the last hit takes it." }


static func simulate(m: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	rng.seed = int(m.seed)
	var s := MobaSim.new(int(m.seed), "pit")
	s.add_boss()
	var bots := {}
	var lead := {}
	for team in ["blue", "red"]:
		for k in ALLIES + 1:
			var c := s.add_champ(MobaChamps.ORDER[rng.randi() % 3], team, "%s%d" % [team, k])
			s.seat_pit(c, k == 0)            # G54: the players hit 2x, have 2x health, and alone carry smite
			bots[c.id] = MobaBot.new(0.6, int(m.seed) * 13 + k * 5 + (0 if team == "blue" else 1))
			if k == 0:
				lead[team] = c
	var how := ""
	while s.winner == "" and s.time < 300.0:
		var orders := {}
		for id in bots:
			orders[id] = (bots[id] as MobaBot).think(s, s.unit(id))
		for e in s.step(orders):
			if e.type == "win":
				how = str(e.get("how", ""))
	var w: Dictionary = m.players[0] if s.winner == "blue" else m.players[1]
	return { "winner": w.id, "summary": "Team %s took the Giant%s at %d s; kills %d – %d." % [w.name,
		" with a smite" if how == "smite" else "", int(s.time), s.score.blue, s.score.red], "stats": {} }


func _start() -> void:
	if _view:
		return
	(_pick_root.get_parent() as CanvasLayer).queue_free()
	var seed := int(match_cfg.seed)
	var s := MobaSim.new(seed, "pit")
	s.add_boss()
	var me := s.add_champ(_picks[_human.id], "blue", str(_human.name))
	var them := s.add_champ(_picks[_bot_p.id], "red", str(_bot_p.name))
	s.seat_pit(me, true)                 # G54: the two players: 2x health and damage, smite
	s.seat_pit(them, true)
	var bots := { them.id: MobaBot.new(0.55, seed * 7) }
	if autopilot:
		bots[me.id] = MobaBot.new(0.6, seed * 3)
	# the allies: the other champions, two a side
	for team in ["blue", "red"]:
		var lead: String = _picks[_human.id] if team == "blue" else _picks[_bot_p.id]
		var rest := MobaChamps.ORDER.filter(func(c): return c != lead)     # the two the lead didn't pick
		for k in ALLIES:
			var champ: String = rest[k % rest.size()]
			var label := "%s (ally)" % MobaChamps.CHAMPS[champ].name if team == "blue" else "%s (%s)" % [MobaChamps.CHAMPS[champ].name, _bot_p.name]
			var a := s.add_champ(champ, team, label)
			s.seat_pit(a, false)             # bot allies: no smite, base stats
			bots[a.id] = MobaBot.new(0.5, seed * 17 + k * 3 + (0 if team == "blue" else 1))
	_view = MobaView.new()
	_view.setup(s, me.id, bots, _binds(),
		{ "blue": str(_human.name), "red": str(_bot_p.name), me.id: str(_human.name), them.id: str(_bot_p.name) })
	_view.match_over.connect(func(team: String):
		var w: Dictionary = _human if team == "blue" else _bot_p
		finished.emit({ "winner": w.id, "summary": "Team %s took the Giant at %d s; kills %d – %d." % [w.name, int(s.time),
			s.score.blue, s.score.red], "stats": {} }))
	add_child(_view)
	TourneyMusic.play("boss")
