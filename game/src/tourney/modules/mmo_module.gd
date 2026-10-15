class_name MmoModule
extends TourneyModule
## MMO: Raid night (G22). WoW Classic in miniature: a raid of six (warrior,
## paladin, priest, mage, hunter, rogue) against the Giant in its courtyard.
## Both contestants are in the same raid, each on a class of their own; the
## other four seats are bots. Whoever rates higher wins: a rating is your
## meter score (damage + healing, less 400 a mechanic failed and 1000 a
## death) per second of the fight against what a bot of your class does
## (MmoClasses.PAR; 100 = a bot's pace), so a priest can beat a hunter.
## One human on this machine plays; the other contestant is a bot.

const PICK_TIME := 30.0

var _pick_root: Control
var _picks := {}               # player id -> class id
var _pick_t := PICK_TIME
var _timer_l: Label
var _human: Dictionary
var _other: Dictionary
var _view: MmoView
var _rng := RandomNumberGenerator.new()

static var autopilot := false


static func info() -> Dictionary:
	return { "id": "mmo_raid", "name": "MMO: Raid night", "players": 2,
		"blurb": "WoW Classic raid on the Giant. Pick a class; the better rating wins." }


static func simulate(m: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	rng.seed = int(m.seed)
	var order := MmoClasses.ORDER.duplicate()
	var a := str(order.pop_at(rng.randi() % order.size()))
	var b := str(order.pop_at(rng.randi() % order.size()))
	var s := build_raid(int(m.seed), a, str(m.players[0].name), b, str(m.players[1].name))
	var bots := {}
	var k := 0
	for p: MmoUnit in s.players():
		bots[p.id] = MmoBot.new(int(m.seed) * 31 + k, rng.randf_range(0.7, 1.3))
		k += 1
	while s.winner == "" and s.time < 600.0:
		var orders := {}
		for id: String in bots:
			orders[id] = (bots[id] as MmoBot).think(s, s.unit(id))
		s.step(orders)
	var ua: MmoUnit = s.players()[0]
	var ub: MmoUnit = s.players()[1]
	var ra := rating(s, ua)
	var rb := rating(s, ub)
	var w: Dictionary = m.players[0] if ra >= rb else m.players[1]
	return { "winner": w.id, "summary": _summary(s, m.players[0], ua, ra, m.players[1], ub, rb), "stats": {} }


## The raid: the two contestants first (seats 0 and 1), then the other
## four classes as bots with names off the class lists.
static func build_raid(seed: int, cls_a: String, name_a: String, cls_b: String, name_b: String) -> MmoSim:
	var s := MmoSim.new(seed)
	s.add_boss()
	s.add_player(cls_a, name_a)
	s.add_player(cls_b, name_b)
	for c: String in MmoClasses.ORDER:
		if c == cls_a or c == cls_b:
			continue
		var names: Array = MmoClasses.CLASSES[c].names
		s.add_player(c, str(names[seed % names.size()]))
	return s


static func rating(s: MmoSim, u: MmoUnit) -> float:
	var secs := maxf(10.0, s.time - s.pull_time)
	return 100.0 * (s.score_of(u) / secs) / float(MmoClasses.PAR[u.cls])


static func _summary(s: MmoSim, pa: Dictionary, ua: MmoUnit, ra: float, pb: Dictionary, ub: MmoUnit, rb: float) -> String:
	var how := "killed the Giant in %d s" % int(s.time - s.pull_time) if s.winner == "raid" else "wiped on the Giant"
	return "The raid %s. %s (%s) rated %d, %s (%s) %d." % [how, pa.name, MmoClasses.CLASSES[ua.cls].name, int(ra),
		pb.name, MmoClasses.CLASSES[ub.cls].name, int(rb)]


func setup(m: Dictionary) -> void:
	super.setup(m)
	_rng.seed = int(m.seed)
	_human = m.players[0]
	for p in m.players:
		if not p.get("bot", false):
			_human = p
			break
	for p in m.players:
		if p != _human:
			_other = p
			break
	_build_pick()


# -------------------------------------------------------------- class pick

func _build_pick() -> void:
	_pick_root = TourneyUI.root(self)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pick_root.add_child(bg)
	_pick_root.move_child(bg, 0)
	var head := TourneyUI.big(_pick_root, "Choose your class", 36, Color("#ffd100"))
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_KEEP_SIZE, 10)
	_timer_l = TourneyUI.big(_pick_root, "", 20, TourneyUI.DIM)
	_timer_l.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_KEEP_SIZE, 58)
	var i := 0
	for id: String in MmoClasses.ORDER:
		var c: Dictionary = MmoClasses.CLASSES[id]
		var x := 30.0 + (i % 3) * 515.0
		var y := 96.0 + (i / 3) * 400.0
		var v := TourneyUI.panel(_pick_root, Rect2(x, y, 500, 388), "")
		var row := TourneyUI.row(v, 12)
		_figure(row, id)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var n := TourneyUI.label(col, str(c.name), BWStyle.F_NAME, MmoClasses.color(id))
		n.add_theme_constant_override("outline_size", 6)
		n.add_theme_color_override("font_outline_color", Color.BLACK)
		TourneyUI.label(col, str(c.role).capitalize() + "  ·  " + str(c.res).capitalize(), BWStyle.F_SMALL, TourneyUI.DIM)
		TourneyUI.para(col, str(c.blurb), 14, Color(0.88, 0.86, 0.8))
		var icons := GridContainer.new()
		icons.columns = 8
		icons.add_theme_constant_override("h_separation", 3)
		icons.add_theme_constant_override("v_separation", 3)
		for ab: Dictionary in c.abilities:
			var ic := MmoIcon.new(str(ab.glyph), Color(str(ab.col)))
			ic.custom_minimum_size = Vector2(28, 28)
			ic.tooltip_text = "%s: %s" % [ab.name, ab.desc]
			ic.mouse_filter = Control.MOUSE_FILTER_PASS
			icons.add_child(ic)
		col.add_child(icons)
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(sp)
		var cls_id := id
		var b := TourneyUI.button(col, "Play %s" % c.name, func() -> void: _lock(_human.id, cls_id))
		b.add_theme_font_size_override("font_size", BWStyle.F_SUB)
		i += 1
	TourneyUI.after(self, _rng.randf_range(2.0, 6.0), func() -> void:
		if not _picks.has(_other.id):
			_lock(_other.id, _bot_pick()))
	if autopilot:
		TourneyUI.after(self, 0.6, func() -> void: _lock(_human.id, MmoClasses.ORDER[_rng.randi() % MmoClasses.ORDER.size()]))


func _figure(parent: Control, cls_id: String) -> void:
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(190, 340)
	svc.stretch = true
	parent.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	svc.add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#1c1812")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.7, 0.62)
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 35, 0)
	vp.add_child(sun)
	var u := MmoUnit.new()
	u.id = "pick_" + cls_id
	u.cls = cls_id
	u.kind = "player"
	var ch := MmoView.dress(u)
	ch.rotation.y = 0.35
	vp.add_child(ch)
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	cam.position = Vector3(0, 1.25, 5.2)
	cam.look_at(Vector3(0, 1.1, 0))


func _bot_pick() -> String:
	var left := MmoClasses.ORDER.filter(func(c: String) -> bool: return c != str(_picks.get(_human.id, "")))
	return str(left[_rng.randi() % left.size()])


func _lock(pid: String, cls_id: String) -> void:
	if _picks.has(pid) or _view:
		return
	if pid == _other.id and _picks.get(_human.id, "") == cls_id:
		cls_id = _bot_pick()
	if pid == _human.id and _picks.get(_other.id, "") == cls_id:
		_picks[_other.id] = _bot_pick()                       # the bot steps aside: one of each class
	_picks[pid] = cls_id
	if _picks.size() >= 2 and _picks[_human.id] != _picks[_other.id]:
		_start()


func _process(delta: float) -> void:
	if _view or _timer_l == null:
		return
	_pick_t -= delta
	var mine := str(_picks.get(_human.id, ""))
	_timer_l.text = "%d s  ·  %s" % [ceili(maxf(_pick_t, 0.0)), ("you: " + MmoClasses.CLASSES[mine].name) if mine != "" else "pick one; the raid has one of each"]
	if _pick_t <= 0.0:
		if not _picks.has(_human.id):
			_picks[_human.id] = MmoClasses.ORDER[_rng.randi() % MmoClasses.ORDER.size()]
		if not _picks.has(_other.id) or _picks[_other.id] == _picks[_human.id]:
			_picks[_other.id] = _bot_pick()
		_start()


# ------------------------------------------------------------------ match

func _start() -> void:
	if _view:
		return
	(_pick_root.get_parent() as CanvasLayer).queue_free()
	var seed := int(match_cfg.seed)
	var s := build_raid(seed, _picks[_human.id], str(_human.name), _picks[_other.id], str(_other.name))
	var me: MmoUnit = s.players()[0]
	var bots := {}
	var k := 0
	for p: MmoUnit in s.players():
		if p != me or autopilot:
			bots[p.id] = MmoBot.new(seed * 17 + k, 1.0)
		k += 1
	_view = MmoView.new()
	_view.setup(s, me.id, bots)
	_view.match_over.connect(func(_r: Dictionary) -> void:
		var ua: MmoUnit = s.players()[0]
		var ub: MmoUnit = s.players()[1]
		var ra := rating(s, ua)
		var rb := rating(s, ub)
		finished.emit({ "winner": _human.id if ra >= rb else _other.id,
			"summary": _summary(s, _human, ua, ra, _other, ub, rb), "stats": {} }))
	add_child(_view)
