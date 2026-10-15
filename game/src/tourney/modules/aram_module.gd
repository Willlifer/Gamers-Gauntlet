class_name AramModule
extends TourneyModule
## MOBA: the ARAM duel. Pick Merr, Temu or Braves, then fight down one lane
## with minion waves; first to 3 kills. HP comes back only on death.
## One human on this machine plays; a bot takes the other seat.

const PICK_TIME := 20.0

var _pick_root: Control
var _picks := {}               # player id -> champ id
var _pick_t := PICK_TIME
var _timer_l: Label
var _human: Dictionary
var _bot_p: Dictionary
var _view: MobaView
var _rng := RandomNumberGenerator.new()

## Tools: auto-pick for the human and let a bot drive their champion too.
static var autopilot := false
## Which side this machine's player starts on (online will set it; the
## camera turns so your own tower is always bottom-left).
static var human_side := "blue"


static func info() -> Dictionary:
	return { "id": "aram", "name": "MOBA: ARAM duel", "players": 2,
		"blurb": "Pick a champion, fight down one lane. First to 3 kills." }


static func simulate(m: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	rng.seed = int(m.seed)
	var s := MobaSim.new(int(m.seed))
	var a := s.add_champ(MobaChamps.ORDER[rng.randi() % 3], "blue", str(m.players[0].name))
	var b := s.add_champ(MobaChamps.ORDER[rng.randi() % 3], "red", str(m.players[1].name))
	var ba := MobaBot.new(0.6, int(m.seed) * 3)
	var bb := MobaBot.new(0.6, int(m.seed) * 5)
	while s.winner == "" and s.time < 420.0:
		s.step({ a.id: ba.think(s, a), b.id: bb.think(s, b) })
	var w: Dictionary = m.players[0] if s.winner == "blue" else m.players[1]
	if s.winner == "":
		w = m.players[0] if s.score.blue >= s.score.red else m.players[1]
	return { "winner": w.id, "summary": "%s (%s) %d – %d %s (%s), %d s." % [m.players[0].name, MobaChamps.CHAMPS[a.champ].name,
		s.score.blue, s.score.red, m.players[1].name, MobaChamps.CHAMPS[b.champ].name, int(s.time)], "stats": {} }


func setup(m: Dictionary) -> void:
	super.setup(m)
	_rng.seed = int(m.seed)
	for p in m.players:
		if p.bot or autopilot:
			if _human.is_empty() and not p.bot:
				_human = p
			else:
				_bot_p = p
		elif _human.is_empty():
			_human = p
		else:
			_bot_p = p
	if _bot_p.is_empty():
		_bot_p = m.players[1] if m.players[0] == _human else m.players[0]
	_build_pick()


# ------------------------------------------------------------- champ select

func _build_pick() -> void:
	_pick_root = TourneyUI.root(self)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pick_root.add_child(bg)
	_pick_root.move_child(bg, 0)
	var head := TourneyUI.big(_pick_root, "Choose your champion", 36)
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_KEEP_SIZE, 14)
	_timer_l = TourneyUI.big(_pick_root, "", 22, TourneyUI.DIM)
	_timer_l.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_KEEP_SIZE, 62)
	var x := 60.0
	for id in MobaChamps.ORDER:
		var c: Dictionary = MobaChamps.CHAMPS[id]
		var v := TourneyUI.panel(_pick_root, Rect2(x, 110, 480, 760), "")
		MobaLook.stage(v, id, Vector2(450, 330))
		var n := TourneyUI.label(v, "%s, %s" % [c.name, c.title], BWStyle.F_NAME, Color(str(c.tint)))
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		TourneyUI.label(v, str(c.role), BWStyle.F_SMALL, TourneyUI.DIM).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		for slot in ["passive", "q", "w", "e", "r"]:
			var sp: Array = c.spells[slot]
			TourneyUI.para(v, "%s  %s: %s" % [slot.to_upper() if slot != "passive" else "P", sp[0], sp[1]], 14, Color(0.85, 0.85, 0.9))
		var sp2 := Control.new()
		sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(sp2)
		var b := TourneyUI.button(v, "Lock in %s" % c.name, func(): _lock(_human.id, id))
		b.add_theme_font_size_override("font_size", BWStyle.F_SUB)
		x += 500.0
	# the bot picks after a moment
	TourneyUI.after(self, _rng.randf_range(2.0, 6.0), func():
		if not _picks.has(_bot_p.id):
			_lock(_bot_p.id, MobaChamps.ORDER[_rng.randi() % MobaChamps.ORDER.size()]))
	if autopilot:
		TourneyUI.after(self, 1.0, func(): _lock(_human.id, MobaChamps.ORDER[_rng.randi() % 3]))


func _lock(pid: String, champ: String) -> void:
	if _picks.has(pid) or _view:
		return
	_picks[pid] = champ
	if _picks.size() >= 2:
		_start()


func _process(delta: float) -> void:
	if _view or _timer_l == null:
		return
	_pick_t -= delta
	_timer_l.text = "%d s  ·  %s" % [ceili(maxf(_pick_t, 0.0)), "you picked " + MobaChamps.CHAMPS[_picks[_human.id]].name if _picks.has(_human.id) else "pick one"]
	if _pick_t <= 0.0:
		for p in [_human, _bot_p]:
			if not _picks.has(p.id):
				_picks[p.id] = MobaChamps.ORDER[_rng.randi() % 3]
		_start()


# ------------------------------------------------------------------ match

func _start() -> void:
	if _view:
		return
	(_pick_root.get_parent() as CanvasLayer).queue_free()
	var s := MobaSim.new(int(match_cfg.seed))
	var mine := human_side
	var theirs := "red" if mine == "blue" else "blue"
	var me := s.add_champ(_picks[_human.id], mine, str(_human.name))
	var them := s.add_champ(_picks[_bot_p.id], theirs, str(_bot_p.name))
	var bots := { them.id: MobaBot.new(0.55, int(match_cfg.seed) * 7) }
	if autopilot:
		bots[me.id] = MobaBot.new(0.6, int(match_cfg.seed) * 3)
	_view = MobaView.new()
	_view.setup(s, me.id, bots, match_cfg.get("binds", TourneyState.load_binds()),
		{ mine: str(_human.name), theirs: str(_bot_p.name) })
	_view.match_over.connect(func(team: String):
		var w: Dictionary = _human if team == mine else _bot_p
		finished.emit({ "winner": w.id, "summary": "%s (%s) %d – %d %s (%s), %d s." % [_human.name, MobaChamps.CHAMPS[me.champ].name,
			s.score[mine], s.score[theirs], _bot_p.name, MobaChamps.CHAMPS[them.champ].name, int(s.time)], "stats": {} }))
	add_child(_view)
	TourneyMusic.play("fight")
