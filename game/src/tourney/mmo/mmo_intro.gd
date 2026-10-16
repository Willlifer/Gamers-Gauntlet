class_name MmoIntro
extends CanvasLayer
## The first-time card (G52b): the first time a person plays a raid (per game,
## a flag in user://tourney.cfg, [seen] mmo_raid=true / mmo_tanks=true), a
## ~10 s card after the class pick and before the pull: what's on your bar
## (the class's 8 spells, the consumables on Shift+1-8), how to move, and the
## fight's four key mechanics with the cue each one shows. It explains; it
## doesn't help: nothing in the fight changes. The raid waits under it
## (MmoView.hold_sim); any key or click starts.
## Shown again with `-- --fresh` on the command line, or MmoTune intro_always.

signal closed

const CFG := "user://tourney.cfg"
const W := 1600.0
const H := 900.0
const SECS := 10.0

const MOVES := [
	["W  S", "run forward / back up"],
	["A  D", "turn (hold the right mouse button: strafe)"],
	["Q  E", "strafe left / right"],
	["Space", "jump"],
	["Right mouse drag", "steer; left drag looks around"],
	["Tab  ·  F2-F7", "target the boss  ·  you and your party"],
]

## The fight's key mechanics: [glyph, colour, the cue you'll see, what to do].
const FIGHT := {
	"giant": [
		["crack", "#ff7a20", "Orange strips and circles on the ground", "Cracks and meteors: step out before they fill."],
		["bomb", "#ff4a3a", "A bomb over your head, a red circle round you", "Spread out. A gold ring on the floor: get in it. Below 75% they come back to back."],
		["flame", "#ff6a20", "Half the courtyard burns; chevrons on its edge", "Stay on the safe side. The chevrons point the way the fire is about to turn."],
		["flame", "#ffb030", "You're on fire (Cinderbrand)", "Run (every step burns it off), get cleansed, drink a Restorative, or be healed."],
	],
	"tank": [
		["arrow", "#ff5a1a", "An orange wedge from the gun", "Aimed at the closest warrior or paladin. Everyone else out: each extra body hits harder."],
		["bomb", "#d02a2a", "Red circles, then red craters; a grey canister", "Out of the circles and craters. The smoke spreads from the canister: keep away, then cross its front."],
		["crack", "#ffb040", "Treads glowing red, dust on one side", "That side explodes. Nose and tail are safe. It also rams and sweeps the middle later."],
		["shield", "#e02020", "Light tanks parked back to back, red wedges", "Never stand in a wedge. Kill them for room; their wedges go with them."],
	],
}

var view: Node
var _t := SECS
var _bar: ColorRect
var _count: Label
var _serif: Font
var _sans: Font
var _done := false


## Has this person seen `game`'s card?
static func seen(game: String) -> bool:
	var cf := ConfigFile.new()
	if cf.load(CFG) != OK:
		return false
	return bool(cf.get_value("seen", game, false))


static func mark_seen(game: String) -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("seen", game, true)
	cf.save(CFG)


## Show it now? The first time, or always with --fresh / intro_always.
static func wanted(game: String) -> bool:
	if "--fresh" in OS.get_cmdline_user_args() or "--fresh" in OS.get_cmdline_args():
		return true
	if MmoTune.value("intro_always") > 0.5:
		return true
	return not seen(game)


## Put the card over `v` (an MmoView), holding the raid until it closes.
static func open(v: Node, cls: String, enc: String, game: String, mark := true) -> MmoIntro:
	var c := MmoIntro.new()
	c.view = v
	v.set("hold_sim", true)
	v.set("input_on", false)
	c._build(cls, enc)
	v.add_child(c)
	if mark:
		mark_seen(game)
	return c


func _build(cls: String, enc: String) -> void:
	layer = 40
	_serif = MmoHud._font(["Friz Quadrata TT", "Friz Quadrata", "Palatino Linotype", "Book Antiqua", "Georgia"], 600)
	_sans = MmoHud._font(["Arial", "Helvetica", "Liberation Sans"], 700)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var card := Panel.new()
	card.position = Vector2(70, 40)
	card.size = Vector2(W - 140, H - 80)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.035, 0.06, 0.95)
	sb.border_color = Color("#c9a54a")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(card)
	var c: Dictionary = MmoClasses.CLASSES[cls]
	var title := "Planet of Tanks" if enc == "tank" else "Raid night: the Giant"
	_lbl(card, title, Vector2(0, 14), 34, MmoHud.GOLD, _serif, W - 140, HORIZONTAL_ALIGNMENT_CENTER)
	_lbl(card, "Your first raid here as a %s: what's on your bar, and what to watch for." % str(c.name), Vector2(0, 58), 16,
		Color(0.85, 0.83, 0.78), _sans, W - 140, HORIZONTAL_ALIGNMENT_CENTER)
	# left: the spells
	var x0 := 40.0
	var y := 100.0
	_lbl(card, "Your spells: 1-8", Vector2(x0, y), 20, MmoClasses.color(cls), _serif, 640)
	y += 32.0
	var abs: Array = MmoClasses.abilities(cls)
	for i in abs.size():
		var ab: Dictionary = abs[i]
		_icon(card, str(ab.glyph), Color(str(ab.col)), Vector2(x0, y), 40.0, MmoClasses.key_label(i))
		_lbl(card, str(ab.name), Vector2(x0 + 50, y - 2), 15, Color.WHITE, _sans, 610)
		var d := _lbl(card, str(ab.get("desc", "")), Vector2(x0 + 50, y + 17), 12, Color(0.82, 0.8, 0.72), _sans, 610)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.size = Vector2(610, 30)
		d.clip_text = true
		y += 50.0
	# left, below: the consumables
	y += 6.0
	_lbl(card, "Consumables: Shift+1-8 (off the global cooldown, each on its own cooldown)", Vector2(x0, y), 17, Color("#1eff00"), _sans, 680)
	y += 28.0
	for i in MmoItems.ITEMS.size():
		var it: Dictionary = MmoItems.ITEMS[i]
		var px := x0 + float(i % 4) * 172.0
		var py := y + float(i / 4) * 44.0
		_icon(card, str(it.glyph), Color(str(it.col)), Vector2(px, py), 36.0, MmoClasses.key_label(MmoItems.SLOT0 + i))
		var nm := str(it.name)
		if nm.length() > 18:                             # two short lines rather than one that runs into the next
			var cut := nm.rfind(" ", nm.length() / 2 + 3)
			nm = nm.substr(0, cut) + "\n" + nm.substr(cut + 1)
		_lbl(card, nm, Vector2(px + 42, py + (2 if nm.find("\n") < 0 else -4)), 12, Color(0.9, 0.9, 0.86), _sans, 126)
	# right: moving
	var x1 := 760.0
	y = 100.0
	_lbl(card, "Moving", Vector2(x1, y), 20, MmoHud.GOLD, _serif, 600)
	y += 32.0
	for m: Array in MOVES:
		_key_cap(card, str(m[0]), Vector2(x1, y))
		_lbl(card, str(m[1]), Vector2(x1 + 190, y + 2), 15, Color(0.88, 0.88, 0.84), _sans, 420)
		y += 30.0
	_lbl(card, "Casting bars break if you move. A hostile target must be in front of you.", Vector2(x1, y + 2), 13,
		Color(0.7, 0.7, 0.66), _sans, 600)
	# right, below: the fight
	y += 40.0
	_lbl(card, "The fight: watch for", Vector2(x1, y), 20, Color("#ff7a40"), _serif, 600)
	y += 34.0
	for f: Array in FIGHT.get(enc, FIGHT.giant):
		_icon(card, str(f[0]), Color(str(f[1])), Vector2(x1, y), 44.0, "")
		_lbl(card, str(f[2]), Vector2(x1 + 56, y - 2), 15, Color(str(f[1])).lightened(0.25), _sans, 560)
		var t := _lbl(card, str(f[3]), Vector2(x1 + 56, y + 18), 13, Color(0.86, 0.85, 0.8), _sans, 560)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.size = Vector2(560, 36)
		y += 66.0
	# the clock
	var back := ColorRect.new()
	back.color = Color(0.15, 0.13, 0.1)
	back.position = Vector2(40, H - 80 - 46)
	back.size = Vector2(W - 140 - 80, 8)
	card.add_child(back)
	_bar = ColorRect.new()
	_bar.color = MmoHud.GOLD
	_bar.position = back.position
	_bar.size = back.size
	card.add_child(_bar)
	_count = _lbl(card, "", Vector2(0, H - 80 - 34), 15, Color(0.9, 0.88, 0.8), _sans, W - 140, HORIZONTAL_ALIGNMENT_CENTER)


func _lbl(parent: Control, text: String, pos: Vector2, size_: int, col: Color, font: Font, width := 0.0, al := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	if width > 0.0:
		l.size = Vector2(width, size_ + 8)
	l.horizontal_alignment = al
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size_)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _icon(parent: Control, glyph: String, col: Color, pos: Vector2, s: float, key: String) -> void:
	var ic := MmoIcon.new(glyph, col)
	ic.position = pos
	ic.size = Vector2(s, s)
	ic.key = key
	ic.font = _sans
	parent.add_child(ic)


func _key_cap(parent: Control, text: String, pos: Vector2) -> void:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.15, 0.13)
	sb.border_color = Color(0.55, 0.5, 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.size = Vector2(176, 24)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	_lbl(p, text, Vector2(0, 1), 14, Color.WHITE, _sans, 176, HORIZONTAL_ALIGNMENT_CENTER)


func _process(delta: float) -> void:
	if _done:
		return
	_t -= delta
	_bar.size.x = (W - 140 - 80) * clampf(_t / SECS, 0.0, 1.0)
	_count.text = "Any key to start  ·  %d" % ceili(maxf(_t, 0.0))
	if _t <= 0.0:
		close()


func _input(ev: InputEvent) -> void:
	if _done:
		return
	if (ev is InputEventKey and ev.pressed and not ev.echo) or (ev is InputEventMouseButton and ev.pressed):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(view):
		view.set("hold_sim", false)
		view.set("input_on", true)
	closed.emit()
	queue_free()
