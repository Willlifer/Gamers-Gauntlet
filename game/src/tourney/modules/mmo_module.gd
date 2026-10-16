class_name MmoModule
extends TourneyModule
## MMO: Raid night (G22). WoW Classic in miniature: a raid of six (warrior,
## paladin, priest, mage, hunter, rogue) against the Giant in its courtyard.
## Both contestants are in the same raid, each on a class of their own; the
## other four seats are bots. The higher grade wins (MmoGrade, G33): output
## against a bot of your class, mechanics performed, AoEs avoided, survival
## and activity, weighted into a score and a letter; the same letter goes to
## the higher score. A priest can beat a hunter.
## One human on this machine plays; the other contestant is a bot.

const PICK_TIME := 30.0
const RAID_SIZE := 8

var _pick_root: Control
var _picks := {}               # player id -> class id
var _pick_t := PICK_TIME
var _timer_l: Label
var _human: Dictionary
var _other: Dictionary
var _view: MmoView
var _rng := RandomNumberGenerator.new()
var _opts: TourneySettings     # the settings on its Raid tab (G56); null when closed

static var autopilot := false


static func info() -> Dictionary:
	return { "id": "mmo_raid", "name": "MMO: Raid night (Hard)", "players": 2,
		"blurb": "WoW Classic raid on the Giant, hard mode: the floor turns often, ring and bombs back to back. Pick a class; the better grade wins." }


static func simulate(m: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	return run(m, rng, "giant")


## The whole raid with bots in every seat; `enc` the boss ("giant", "giant_easy": easy mode, G59, or "tank": Planet of Tanks, G46).
static func run(m: Dictionary, rng: RandomNumberGenerator, enc: String) -> Dictionary:
	rng.seed = int(m.seed)
	var a := str(MmoClasses.ORDER[rng.randi() % MmoClasses.ORDER.size()])
	var b := str(MmoClasses.ORDER[rng.randi() % MmoClasses.ORDER.size()])
	var s := build_raid(int(m.seed), a, str(m.players[0].name), b, str(m.players[1].name), enc)
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
	var ga := MmoGrade.grade(s, ua)
	var gb := MmoGrade.grade(s, ub)
	var w: Dictionary = m.players[0] if MmoGrade.beats(ga, gb) else m.players[1]
	return { "winner": w.id, "summary": _summary(s, m.players[0], ua, ga, m.players[1], ub, gb), "stats": {} }


## The raid (G39): the two contestants first (seats 0 and 1, any classes,
## the same one allowed), then one bot of every class, eight in all. The
## Giant scales with the raid's size.
static func build_raid(seed: int, cls_a: String, name_a: String, cls_b: String, name_b: String, enc := "giant") -> MmoSim:
	return build_seats(seed, [[cls_a, name_a], [cls_b, name_b]], RAID_SIZE, enc)


## Any raid of up to 8: `seats` is [[class, name], ...] for the people; the
## rest of the eight are bots, one of each class, then repeats. Every seat
## takes orders the same way (MmoSim.step), human or bot, so the same raid
## runs online in lockstep with eight people (stage 3).
static func build_seats(seed: int, seats: Array, size := RAID_SIZE, enc := "giant") -> MmoSim:
	var s := MmoSim.new(seed)
	if enc == "tank":
		s.add_tank()
	else:
		s.add_boss()
		s.easy = enc == "giant_easy"            # G59: the Giant's pre-G52 rules
	for seat: Array in seats.slice(0, size):
		s.add_player(str(seat[0]), str(seat[1]))
	var k := 0
	while s.players().size() < size:
		var c: String = MmoClasses.ORDER[k % MmoClasses.ORDER.size()]
		var names: Array = MmoClasses.CLASSES[c].names
		s.add_player(c, str(names[(seed + k / MmoClasses.ORDER.size()) % names.size()]))
		k += 1
	s.scale_boss()
	return s


static func _summary(s: MmoSim, pa: Dictionary, ua: MmoUnit, ga: Dictionary, pb: Dictionary, ub: MmoUnit, gb: Dictionary) -> String:
	var who := "the Tank" if s.tank else "the Giant"
	var how := ("killed %s in %d s" % [who, int(s.time - s.pull_time)]) if s.winner == "raid" else "wiped on " + who
	return "The raid %s. %s (%s) graded %s (%d), %s (%s) %s (%d)." % [how, pa.name, MmoClasses.CLASSES[ua.cls].name, ga.letter, int(ga.score),
		pb.name, MmoClasses.CLASSES[ub.cls].name, gb.letter, int(gb.score)]


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

## Extra dressing on the class pick (Planet of Tanks puts its logo up).
func _dress_pick(_root: Control) -> void:
	pass


## Which boss: the Giant here; easy mode (MmoRaidEasyModule) says "giant_easy", Planet of Tanks (MmoTanksModule) "tank".
func encounter() -> String:
	return "giant"


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
	_hidden_tank()
	_dress_pick(_pick_root)
	var gear := TourneySettings.gear_button(_pick_root, "Settings", _toggle_opts)
	gear.position = Vector2(1400, 18)
	gear.size = Vector2(180, 44)
	TourneyUI.after(self, _rng.randf_range(2.0, 6.0), func() -> void:
		if not _picks.has(_other.id):
			_lock(_other.id, _bot_pick()))
	if autopilot:
		TourneyUI.after(self, 0.6, func() -> void: _lock(_human.id, MmoClasses.ORDER[_rng.randi() % MmoClasses.ORDER.size()]))


## The hidden class (G44): a small, faint tank parked in the bottom-right
## corner of the pick screen, past the last card. Visible if you look; it
## brightens under the mouse; click it to drive.
func _hidden_tank() -> void:
	if GKRegistry.def("tank") == null:
		return
	var svc := SubViewportContainer.new()
	svc.position = Vector2(1528, 852)
	svc.size = Vector2(64, 40)
	svc.stretch = true
	svc.modulate = Color(1, 1, 1, 0.4)
	svc.tooltip_text = "???"
	svc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_pick_root.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	svc.add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.68, 0.6)
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	vp.add_child(sun)
	var t := GKRegistry.build("tank").instantiate(false)
	t.rotation.y = -2.3
	vp.add_child(t)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.5
	vp.add_child(cam)
	cam.position = Vector3(0, 6, 12)
	cam.look_at(Vector3(0, 1.6, 0))
	svc.mouse_entered.connect(func() -> void: svc.modulate.a = 1.0)
	svc.mouse_exited.connect(func() -> void: svc.modulate.a = 0.4)
	svc.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_lock(_human.id, "tank"))


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


## The settings (G56) over the class pick, on the Raid tab; the clock waits.
func _toggle_opts() -> void:
	if _opts:
		_opts.queue_free()
		_opts = null
		return
	_opts = TourneySettings.open(_pick_root, "raid")
	_opts.closed.connect(_toggle_opts)


func _bot_pick() -> String:
	return str(MmoClasses.ORDER[_rng.randi() % MmoClasses.ORDER.size()])


func _lock(pid: String, cls_id: String) -> void:
	if _picks.has(pid) or _view:
		return
	if pid == _human.id:
		BWSfx.ui("ui_confirm")
	_picks[pid] = cls_id
	if _picks.size() >= 2:
		_start()


func _process(delta: float) -> void:
	if _view or _timer_l == null or _opts:
		return
	_pick_t -= delta
	var mine := str(_picks.get(_human.id, ""))
	_timer_l.text = "%d s  ·  %s" % [ceili(maxf(_pick_t, 0.0)), ("you: " + MmoClasses.CLASSES[mine].name) if mine != "" else "pick any class; a raid of eight"]
	if _pick_t <= 0.0:
		if not _picks.has(_human.id):
			_picks[_human.id] = MmoClasses.ORDER[_rng.randi() % MmoClasses.ORDER.size()]
		if not _picks.has(_other.id):
			_picks[_other.id] = _bot_pick()
		_start()


# ------------------------------------------------------------------ match

func _start() -> void:
	if _view:
		return
	(_pick_root.get_parent() as CanvasLayer).queue_free()
	var seed := int(match_cfg.seed)
	var s := build_raid(seed, _picks[_human.id], str(_human.name), _picks[_other.id], str(_other.name), encounter())
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
		var ga := MmoGrade.grade(s, ua)
		var gb := MmoGrade.grade(s, ub)
		finished.emit({ "winner": _human.id if MmoGrade.beats(ga, gb) else _other.id,
			"summary": _summary(s, _human, ua, ga, _other, ub, gb), "stats": {} }))
	add_child(_view)
	# G52b: the first-time card, after the pick and before the pull
	var game := str(info_id())
	if not autopilot and not _human.get("bot", false) and MmoIntro.wanted(game):
		MmoIntro.open(_view, str(_picks[_human.id]), encounter(), game)


## This raid's id for the first-time card's flag (mmo_raid / mmo_raid_easy / mmo_tanks).
func info_id() -> String:
	return str({ "tank": "mmo_tanks", "giant_easy": "mmo_raid_easy" }.get(encounter(), "mmo_raid"))
