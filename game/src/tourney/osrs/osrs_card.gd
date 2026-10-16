class_name OsrsCard
extends CanvasLayer
## The first-time card for Warden's Trial (G53c): the first time a human plays
## it (per profile: [seen] osrs_raid in user://tourney.cfg), about 10 s on
## what's in the inventory, the prayers and the mechanics, one line each
## with its icon, before the fight starts. Any key or click skips it. It only
## explains the controls; the fight itself gives no extra help.
##   --fresh (a user arg) or OsrsCard.force shows it again, for testing;
##   OsrsTune card_always (G56: the settings' OSRS tab) shows it every run.

signal done

const TIME := 10.0
const SEEN := "osrs_raid"

static var force := false

var _t := TIME
var _font: Font
var _clock: Label
var _closed := false


## Show it this time? (Marks it seen when it says yes.)
static func should_show() -> bool:
	if force or OS.get_cmdline_user_args().has("--fresh") or OsrsTune.value("card_always") > 0.5:
		return true
	var cf := ConfigFile.new()
	cf.load(TourneyState.CFG)
	if bool(cf.get_value("seen", SEEN, false)):
		return false
	cf.set_value("seen", SEEN, true)
	cf.save(TourneyState.CFG)
	return true


func _ready() -> void:
	layer = 20
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Verdana", "Tahoma", "Arial"])
	f.font_weight = 700
	_font = f
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = OsrsHud.STONE
	sb.border_color = Color("#b89a5a")
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", sb)
	card.position = Vector2(230, 70)
	card.size = Vector2(1140, 760)
	add_child(card)
	_label(card, "Warden's Trial", Vector2(0, 16), 30, OsrsHud.YELLOW, 1140, true)
	# the inventory
	_label(card, "Your inventory", Vector2(40, 74), 16, OsrsHud.ORANGE)
	var items := [
		[{ "kind": "bow" }, "Bow: steady hits from range."],
		[{ "kind": "staff" }, "Staff: harder, slower, from range."],
		[{ "kind": "dagger" }, "Lightning dagger: 1 a tick, melee. For the skulls."],
		[{ "kind": "boost", "doses": 4 }, "Damage potion: a sip and your bow / staff hit harder."],
	]
	for i in items.size():
		var at := Vector2(40 + (i % 2) * 540, 104 + (i / 2) * 58)
		_icon(card, at, func(c: Control) -> void: OsrsHud.draw_item(c, items[i][0], _font, c.size))
		_label(card, items[i][1], at + Vector2(62, 14), 14, Color.WHITE)
	_label(card, "Click one to wield or drink it. Sharks heal; prayer potions restore prayer.", Vector2(40, 222), 13, Color("#c8b88a"))
	# the prayers
	_label(card, "Prayers  (1  2  3, or click)", Vector2(40, 262), 16, OsrsHud.ORANGE)
	var i2 := 0
	for p in ["magic", "ranged", "melee"]:
		var pid: String = p
		_icon(card, Vector2(40 + i2 * 76, 292), func(c: Control) -> void: OsrsHud.draw_prayer_icon(c, pid, true, _font, c.size), Vector2(64, 70))
		i2 += 1
	_label(card, "Protect from the style of the shot about to land. It's judged the moment it hits.", Vector2(280, 318), 14, Color.WHITE)
	# the mechanics
	_label(card, "The fight", Vector2(40, 388), 16, OsrsHud.ORANGE)
	var lines := [
		["shots", "The phantoms on the flanks fire by turns: blue orb is magic, green arrow is missiles."],
		["slam", "Slams: only a middle column is safe. West fist up: west-middle; both: centre; east fist: east-middle."],
		["shadow", "Shadows mark lightning and boulders: step off. The far row cracks and falls."],
		["skull", "Skulls rise at 75 / 50 / 25%: wield the dagger, click skull after skull before they burst."],
		["shield", "A blue shield stops magic, a green one arrows: swap weapons."],
	]
	for k in lines.size():
		var at := Vector2(40, 420 + k * 56)
		var what: String = lines[k][0]
		_icon(card, at, func(c: Control) -> void: _draw_mech(c, what))
		_label(card, lines[k][1], at + Vector2(62, 14), 14, Color.WHITE)
	_label(card, "Click a square to move, the Warden to attack. Fastest kill wins.", Vector2(0, 706), 14, Color("#c8b88a"), 1140, true)
	_clock = _label(card, "", Vector2(0, 732), 12, Color("#9a8a6a"), 1140, true)


func _label(parent: Control, text: String, at: Vector2, size: int, col: Color, width := 0.0, centre := false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = at
	if width > 0.0:
		l.size.x = width
	if centre:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(l)
	return l


func _icon(parent: Control, at: Vector2, draw: Callable, size := Vector2(48, 48)) -> void:
	var c := Control.new()
	c.position = at
	c.size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		c.draw_rect(Rect2(Vector2.ZERO, size), OsrsHud.STONE_DARK)
		draw.call(c))
	parent.add_child(c)


## The mechanics' icons, after what they look like in the fight.
func _draw_mech(c: Control, what: String) -> void:
	var m := c.size * 0.5
	match what:
		"shots":
			c.draw_circle(m + Vector2(-9, -6), 8.0, Color("#4aa0ff"))
			c.draw_line(m + Vector2(-2, 16), m + Vector2(16, -2), Color("#e8f0e0"), 2.0)
			c.draw_colored_polygon(PackedVector2Array([m + Vector2(18, -4), m + Vector2(10, -2), m + Vector2(16, 4)]), Color("#7cff5a"))
		"slam":
			for x in 3:
				c.draw_rect(Rect2(6 + x * 12, 26, 10, 10), Color("#ffd040") if x == 0 else Color("#d02020"), false, 2.0)
			c.draw_rect(Rect2(4, 6, 14, 12), Color("#9a8a6a"))
			c.draw_line(Vector2(11, 20), Vector2(11, 24), Color("#ff9a30"), 2.0)
		"shadow":
			c.draw_circle(m + Vector2(0, 8), 14.0, Color(0, 0, 0, 0.8))
			c.draw_polyline(PackedVector2Array([m + Vector2(2, -18), m + Vector2(-5, -6), m + Vector2(4, -2), m + Vector2(-2, 8)]), Color("#ff4a30"), 3.0)
		"skull":
			c.draw_circle(m + Vector2(0, -3), 13.0, Color("#efe6cf"))
			c.draw_rect(Rect2(m + Vector2(-8, 6), Vector2(16, 9)), Color("#efe6cf"))
			c.draw_circle(m + Vector2(-5, -3), 3.5, Color("#ff40c0"))
			c.draw_circle(m + Vector2(5, -3), 3.5, Color("#ff40c0"))
			c.draw_arc(m, 21.0, 0, TAU, 24, Color("#ff40c0"), 2.0)
		"shield":
			for k in 2:
				var at := m + Vector2(-10 + k * 20, 0)
				var col := Color("#5ab0ff") if k == 0 else Color("#7cff5a")
				c.draw_colored_polygon(PackedVector2Array([at + Vector2(-9, -12), at + Vector2(9, -12), at + Vector2(9, 0), at + Vector2(0, 12), at + Vector2(-9, 0)]), Color(col, 0.6))


func _process(delta: float) -> void:
	_t -= delta
	_clock.text = "Any key to start  ·  %d s" % ceili(maxf(_t, 0.0))
	if _t <= 0.0:
		_close()


func _input(ev: InputEvent) -> void:
	if (ev is InputEventKey or ev is InputEventMouseButton) and ev.is_pressed() and not ev.is_echo():
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	if _closed:
		return
	_closed = true
	done.emit()
	queue_free()
