class_name OsrsModule
extends TourneyModule
## OSRS: Warden's Trial (G34). An Old School RuneScape raid boss after Tombs
## of Amascut's Wardens, on game squares and 0.6 s ticks (OsrsSim). Each
## contestant runs the same seeded fight alone; the better run wins: a kill
## beats a death, then the faster kill, then more damage, then less taken.
## Offline the human on this machine plays; the other contestant's run is
## a bot's, rolled at once (OsrsBot). Pick a bow or a staff first (both are
## in the inventory: click the other one to swap mid-fight).

const PICK_TIME := 12.0

var _human: Dictionary
var _other: Dictionary
var _pick: CanvasLayer
var _pick_t := PICK_TIME
var _timer_l: Label
var _view: OsrsView
var _bot_run := {}
var _picked := false

static var autopilot := false


static func info() -> Dictionary:
	return { "id": "osrs_raid", "name": "OSRS: Warden's Trial", "players": 2,
		"blurb": "Old School raid boss on 0.6 s ticks. Pray against the phantoms' shots, dodge lightning, boulders and slams, break the skulls with a lightning dagger. Fastest kill wins." }


static func simulate(m: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	rng.seed = int(m.seed)
	var runs: Array = []
	for i in 2:
		runs.append(bot_run(int(m.seed), ["bow", "staff"][rng.randi() % 2], int(m.seed) * 7 + i * 101))
	var a: Dictionary = m.players[0]
	var b: Dictionary = m.players[1]
	var w: Dictionary = a if OsrsSim.beats(runs[0], runs[1]) else b
	return { "winner": w.id, "summary": _summary(a, runs[0], b, runs[1]), "stats": {} }


## A whole fight played by a bot: its result.
static func bot_run(seed: int, weapon: String, bot_seed: int) -> Dictionary:
	var s := OsrsSim.new(seed)
	s.me.weapon = weapon
	var b := OsrsBot.new(bot_seed)
	while s.over == "":
		s.step(b.think(s))
	return s.result()


static func _line(p: Dictionary, r: Dictionary) -> String:
	match str(r.how):
		"win": return "%s killed the Warden in %s" % [p.name, OsrsHud.clock(float(r.secs))]
		"dead": return "%s died with the Warden at %d%%" % [p.name, int(round((1.0 - float(r.boss_pct)) * 100.0))]
	return "%s ran out of time at %d%%" % [p.name, int(round((1.0 - float(r.boss_pct)) * 100.0))]


static func _summary(a: Dictionary, ra: Dictionary, b: Dictionary, rb: Dictionary) -> String:
	return "%s; %s." % [_line(a, ra), _line(b, rb)]


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
	_bot_run = bot_run(int(m.seed), ["bow", "staff"][int(m.seed) % 2], int(m.seed) * 13 + 5)
	_build_pick()
	TourneyMusic.play("hype")


func _build_pick() -> void:
	_pick = CanvasLayer.new()
	add_child(_pick)
	var root := TourneyUI.root(_pick)
	var bg := ColorRect.new()
	bg.color = Color("#14110c")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	root.move_child(bg, 0)
	TourneyUI.header(root, "WARDEN'S TRIAL", "Pick your weapon. The other one and a lightning dagger stay in your inventory: click one to wield it.")
	_timer_l = TourneyUI.label(root, "", BWStyle.F_SUB, TourneyUI.DIM)
	_timer_l.position = Vector2(0, 150)
	_timer_l.size = Vector2(1600, 30)
	_timer_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bow := TourneyTile.make(root, Rect2(250, 220, 520, 300), "Bow", "Hits 10-45 every 4 ticks (2.4 s). Steady.", Color("#3d4a2a"), "BOW")
	bow.title_size = 48
	bow.pressed.connect(func(): _start("bow"))
	var staff := TourneyTile.make(root, Rect2(830, 220, 520, 300), "Staff", "Hits 15-55 every 5 ticks (3.0 s). Swingy.", Color("#3e2d55"), "STAFF")
	staff.title_size = 48
	staff.pressed.connect(func(): _start("staff"))
	var how := TourneyUI.para(root, "The two phantoms on the flanks take turns firing at you: pray against each shot (blue orb: magic, arrow: missiles) before it lands. The Warden does the rest: step off the shadows before lightning and boulders hit; when it slams, only a middle column is safe: west fist raised, the west-middle; both fists, the centre; east fist, the east-middle (faster below half HP); get off the far row when it cracks; when it shields itself against magic or bowfire, swap weapons. At 75%, 50% and 25% it raises skulls: wield the lightning dagger and click skull after skull, striking as you arrive, before they burst. Sip the damage potion; stand on a Sun Sigil as it ignites. Fastest kill wins.", BWStyle.F_BODY, Color(1, 1, 1, 0.85))
	how.position = Vector2(250, 560)
	how.size = Vector2(1100, 200)
	how.set_deferred("size", Vector2(1100, 200))                 # wrap at the tiles' width
	if autopilot:
		TourneyUI.after(self, 0.5, func(): _start("bow"))


func _process(delta: float) -> void:
	if _view or _pick == null or _picked:
		return
	_pick_t -= delta
	_timer_l.text = "%d s" % ceili(maxf(_pick_t, 0.0))
	if _pick_t <= 0.0:
		_start("bow")


func _start(weapon: String) -> void:
	if _view or _picked:
		return
	_picked = true
	_pick.queue_free()
	# G53c: the first time on this profile, a short card on the controls first
	if (not autopilot or OsrsCard.force) and OsrsCard.should_show():
		var card := OsrsCard.new()
		card.done.connect(func() -> void: _begin(weapon))
		add_child(card)
		return
	_begin(weapon)


func _begin(weapon: String) -> void:
	var s := OsrsSim.new(int(match_cfg.seed))
	s.me.weapon = weapon
	_view = OsrsView.new()
	_view.setup(s)
	if autopilot:
		_view.bot = OsrsBot.new(int(match_cfg.seed))
	_view.over.connect(func(r: Dictionary) -> void:
		var won := OsrsSim.beats(r, _bot_run)
		finished.emit({ "winner": _human.id if won else _other.id, "summary": _summary(_human, r, _other, _bot_run), "stats": {} }))
	add_child(_view)
	TourneyMusic.play("fight")
