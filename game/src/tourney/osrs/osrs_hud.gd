class_name OsrsHud
extends CanvasLayer
## The OSRS raid's interface, after the classic layout (the author's
## screenshot): the stone side panel on the right with the minimap and its
## orbs (hitpoints, prayer, run), the inventory always open with the three
## protect prayers beside it, the chat box bottom left, the Warden's health
## bar top centre, hitsplats over heads. Everything here only sends orders
## through OsrsView.queue; the sim decides.

const STONE := Color("#3e3529")
const STONE_DARK := Color("#2a241b")
const STONE_LIGHT := Color("#5a4d3b")
const YELLOW := Color("#ffff00")
const ORANGE := Color("#ff981f")
const CHAT_BG := Color("#d3c4a0")
const SLOT := 46.0
const PANEL_X := 1336.0

var view: OsrsView
var _root: Control
var _font: Font
var _chat: VBoxContainer
var _lines: Array = []
var _inv: Array = []                          # slot Controls
var _pray_btns := {}
var _boss_bar: Control
var _orbs: Control
var _mini: Control
var _top: Label
var _splats: Array = []                       # { node, val, col, t, height, emp }
var _splat_layer: Control
var _end: PanelContainer
var _sim: OsrsSim


static func clock(secs: float) -> String:
	return "%d:%02d" % [int(secs) / 60, int(secs) % 60]


func _ready() -> void:
	layer = 10
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Verdana", "Tahoma", "Arial"])
	f.font_weight = 700
	_font = f
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_splat_layer = Control.new()
	_splat_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_splat_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splat_layer.draw.connect(_draw_splats)
	_root.add_child(_splat_layer)
	_build_side()
	_build_chat()
	_build_boss_bar()
	_top = _text(_root, "", Vector2(14, 40), 15, YELLOW)


func _text(parent: Control, s: String, at: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.position = at
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _stone(rect: Rect2, parent: Control = null) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = STONE
	sb.border_color = STONE_DARK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(4)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 4
	p.add_theme_stylebox_override("panel", sb)
	p.position = rect.position
	p.size = rect.size
	(parent if parent else _root).add_child(p)
	return p


# ------------------------------------------------------------------- side

func _build_side() -> void:
	# the minimap and its orbs
	_mini = Control.new()
	_mini.position = Vector2(PANEL_X + 70, 8)
	_mini.size = Vector2(176, 176)
	_mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini.draw.connect(_draw_minimap)
	_root.add_child(_mini)
	_orbs = Control.new()
	_orbs.position = Vector2(PANEL_X, 20)
	_orbs.size = Vector2(80, 170)
	_orbs.draw.connect(_draw_orbs)
	_orbs.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and ev.position.y > 112:
			view.queue({ "run": not bool(_sim.me.run) }))
	_root.add_child(_orbs)
	# the panel: protect prayers beside the inventory
	var panel := _stone(Rect2(PANEL_X - 6, 200, 1600 - PANEL_X + 2, 420))
	var head := _text(panel, "Inventory", Vector2(86, 8), 13, ORANGE)
	head.size.x = 160
	var pr := _text(panel, "Prayer", Vector2(8, 8), 13, ORANGE)
	pr.size.x = 70
	var i := 0
	for p in ["magic", "ranged", "melee"]:
		var b := Control.new()
		b.position = Vector2(8, 32 + i * 76)
		b.size = Vector2(64, 70)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = { "magic": "Protect from Magic (1)", "ranged": "Protect from Missiles (2)", "melee": "Protect from Melee (3)" }[p]
		var pid: String = p
		b.draw.connect(_draw_prayer.bind(b, pid))
		b.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				view.queue({ "pray": pid })
				BWSfx.ui("ui_click"))
		panel.add_child(b)
		_pray_btns[p] = b
		i += 1
	for k in 28:
		var s := Control.new()
		s.position = Vector2(86 + (k % 4) * SLOT, 32 + (k / 4) * (SLOT + 7))
		s.size = Vector2(SLOT - 2, SLOT)
		var slot := k
		s.draw.connect(_draw_slot.bind(s, slot))
		s.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_use(slot))
		panel.add_child(s)
		_inv.append(s)
	var keys := _stone(Rect2(PANEL_X - 6, 626, 1600 - PANEL_X + 2, 70))
	_text(keys, "Click a square: move · click the Warden: attack", Vector2(8, 8), 11, Color("#e0d6b8"))
	_text(keys, "1 2 3: pray · arrows / middle-drag: camera", Vector2(8, 26), 11, Color("#e0d6b8"))
	_text(keys, "wheel: zoom · F1: numbers", Vector2(8, 44), 11, Color("#e0d6b8"))


## What the 28 slots hold, from the sim: the other weapon, sharks, potions.
func _items() -> Array:
	var out: Array = []
	if _sim == null:
		return out
	out.append({ "kind": "staff" if _sim.me.weapon == "bow" else "bow" })
	for k in int(_sim.me.food):
		out.append({ "kind": "shark" })
	var doses := int(_sim.me.doses)
	while doses > 0:
		out.append({ "kind": "potion", "doses": mini(4, doses) })
		doses -= 4
	return out


func _use(slot: int) -> void:
	var it: Array = _items()
	if slot >= it.size():
		return
	match str(it[slot].kind):
		"shark": view.queue({ "eat": true })
		"potion": view.queue({ "drink": true })
		_: view.queue({ "swap": true })
	BWSfx.ui("ui_click")


func _draw_slot(c: Control, slot: int) -> void:
	var it: Array = _items()
	if slot >= it.size():
		return
	var d: Dictionary = it[slot]
	var m := c.size * 0.5
	match str(d.kind):
		"shark":
			var body := PackedVector2Array([m + Vector2(-16, 0), m + Vector2(-6, -8), m + Vector2(10, -6), m + Vector2(16, 0), m + Vector2(10, 6), m + Vector2(-6, 7)])
			c.draw_colored_polygon(body, Color("#7b8fa3"))
			c.draw_colored_polygon(PackedVector2Array([m + Vector2(-16, 0), m + Vector2(-22, -7), m + Vector2(-21, 7)]), Color("#62778c"))
			c.draw_colored_polygon(PackedVector2Array([m + Vector2(-2, -7), m + Vector2(3, -14), m + Vector2(5, -6)]), Color("#62778c"))
			c.draw_circle(m + Vector2(10, -2), 1.5, Color.BLACK)
		"potion":
			c.draw_rect(Rect2(m + Vector2(-9, -6), Vector2(18, 20)), Color("#b9c8cf", 0.7))
			var fill := 18.0 * float(d.doses) / 4.0
			c.draw_rect(Rect2(m + Vector2(-8, 13 - fill), Vector2(16, fill)), Color("#3fc7d8"))
			c.draw_rect(Rect2(m + Vector2(-4, -14), Vector2(8, 8)), Color("#b9c8cf", 0.8))
			c.draw_rect(Rect2(m + Vector2(-5, -17), Vector2(10, 4)), Color("#8a5a2a"))
			c.draw_string(_font, Vector2(2, 12), "(%d)" % int(d.doses), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, YELLOW)
		"bow":
			c.draw_arc(m + Vector2(6, 0), 17.0, PI * 0.6, PI * 1.4, 14, Color("#8a5a2a"), 3.0)
			c.draw_line(m + Vector2(-2, -16), m + Vector2(-2, 16), Color("#e0e0e0"), 1.0)
			c.draw_string(_font, Vector2(2, 12), "Bow", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, YELLOW)
		"staff":
			c.draw_line(m + Vector2(-12, 16), m + Vector2(8, -10), Color("#7a5230"), 3.0)
			c.draw_circle(m + Vector2(10, -13), 5.0, Color("#b07aff"))
			c.draw_string(_font, Vector2(2, 12), "Staff", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, YELLOW)


func _draw_prayer(b: Control, p: String) -> void:
	var on := _sim != null and str(_sim.me.prayer) == p
	var r := Rect2(Vector2.ZERO, b.size)
	b.draw_rect(r, Color("#5a4d3b") if on else STONE_DARK)
	if on:
		b.draw_rect(r.grow(-2), Color("#e8d27a", 0.35))
	b.draw_rect(r, Color("#b89a5a") if on else Color("#1a1610"), false, 2.0)
	var c := b.size * 0.5 + Vector2(0, -4)
	var col := { "magic": Color("#5ab0ff"), "ranged": Color("#7cff5a"), "melee": Color("#ff6a5a") }[p] as Color
	if not on:
		col = col.darkened(0.45)
	match p:
		"magic":
			for k in 5:
				var a := k * TAU / 5.0 - PI * 0.5
				b.draw_line(c, c + Vector2(cos(a), sin(a)) * 18.0, col, 3.0)
			b.draw_circle(c, 6.0, col)
		"ranged":
			b.draw_line(c + Vector2(-16, 14), c + Vector2(14, -14), col, 3.0)
			b.draw_colored_polygon(PackedVector2Array([c + Vector2(16, -16), c + Vector2(6, -14), c + Vector2(14, -6)]), col)
			b.draw_line(c + Vector2(-16, 14), c + Vector2(-20, 8), col, 2.0)
			b.draw_line(c + Vector2(-16, 14), c + Vector2(-10, 18), col, 2.0)
		"melee":
			b.draw_line(c + Vector2(-14, 14), c + Vector2(14, -14), col, 4.0)
			b.draw_line(c + Vector2(-8, 2), c + Vector2(2, 12), col, 3.0)
	b.draw_string(_font, Vector2(0, b.size.y - 4), { "magic": "Magic", "ranged": "Missiles", "melee": "Melee" }[p], HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 10, YELLOW if on else Color("#c8b88a"))


func _draw_orbs() -> void:
	if _sim == null:
		return
	var orbs := [
		["%d" % int(ceilf(float(_sim.me.hp))), float(_sim.me.hp) / float(_sim.me.max_hp), Color("#c2281e"), "HP"],
		["%d" % int(ceilf(float(_sim.me.pray))), float(_sim.me.pray) / float(_sim.me.max_pray), Color("#3fc7d8"), "PR"],
		["ON" if _sim.me.run else "OFF", 1.0 if _sim.me.run else 0.3, Color("#e0c040"), "RUN"],
	]
	for i in orbs.size():
		var o: Array = orbs[i]
		var c := Vector2(46, 18 + i * 52)
		_orbs.draw_rect(Rect2(c + Vector2(-46, -13), Vector2(30, 26)), STONE_DARK)
		_orbs.draw_string(_font, c + Vector2(-44, 6), str(o[0]), HORIZONTAL_ALIGNMENT_CENTER, 28, 13, Color("#00ff00") if float(o[1]) > 0.5 else (YELLOW if float(o[1]) > 0.25 else Color("#ff3020")))
		_orbs.draw_circle(c, 19.0, STONE_DARK)
		_orbs.draw_circle(c, 16.0, Color("#1a1610"))
		var fill := clampf(float(o[1]), 0.0, 1.0)
		var pts := PackedVector2Array()
		var top := 16.0 - 32.0 * fill
		for k in 25:
			var a := PI * k / 24.0
			var p := c + Vector2(cos(a) * 16.0, sin(a) * 16.0)
			if p.y - c.y >= top:
				pts.append(p)
		if fill > 0.02:
			var hw := sqrt(maxf(0.0, 256.0 - top * top))
			pts.append(c + Vector2(-hw, top))
			pts.append(c + Vector2(hw, top))
			var hull := Geometry2D.convex_hull(pts)
			if hull.size() >= 3:
				_orbs.draw_colored_polygon(hull, o[2])
		_orbs.draw_string(_font, c + Vector2(-16, 4), str(o[3]), HORIZONTAL_ALIGNMENT_CENTER, 32, 10, Color.WHITE)
	if str(_sim.me.prayer) != "":
		_orbs.draw_circle(Vector2(46, 70) + Vector2(14, -14), 5.0, Color.WHITE)


func _draw_minimap() -> void:
	var c := _mini.size * 0.5
	_mini.draw_circle(c, 86.0, STONE_DARK)
	_mini.draw_circle(c, 80.0, Color("#0b0b10"))
	if _sim == null:
		return
	var px := 8.4
	var origin := c + Vector2(-OsrsSim.W * px * 0.5, -OsrsSim.H * px * 0.5 + 18.0)
	for y in OsrsSim.H:
		for x in OsrsSim.W:
			var t := Vector2i(x, y)
			if _sim.gone.has(t):
				continue
			var col := Color("#6b3f37") if (x + y) % 2 else Color("#7a4a40")
			if _sim.rocks.has(t):
				col = Color("#8a8a8a")
			_mini.draw_rect(Rect2(origin + Vector2(x, y) * px, Vector2(px - 1, px - 1)), col)
	_mini.draw_rect(Rect2(origin + Vector2(OsrsSim.BOSS_RECT.position) * px, Vector2(OsrsSim.BOSS_RECT.size) * px), Color("#d9a441", 0.8))
	_mini.draw_circle(origin + Vector2(OsrsSim.BOSS_RECT.get_center()) * px, 4.0, Color("#ff2020"))
	for s in _sim.sigils:
		_mini.draw_circle(origin + (Vector2(s.tile) + Vector2(0.5, 0.5)) * px, 3.0, Color("#ffcf40"))
	_mini.draw_circle(origin + (Vector2(_sim.me.tile) + Vector2(0.5, 0.5)) * px, 3.5, Color.WHITE)
	_mini.draw_arc(c, 82.0, 0, TAU, 48, Color("#5a4d3b"), 5.0)
	_mini.draw_string(_font, c + Vector2(-70, -60), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ff3020"))


# ------------------------------------------------------------------- chat

func _build_chat() -> void:
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CHAT_BG
	sb.border_color = STONE
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(3)
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(8, 742)
	box.size = Vector2(540, 150)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_chat = VBoxContainer.new()
	_chat.position = Vector2(10, 6)
	_chat.size = Vector2(520, 138)
	_chat.add_theme_constant_override("separation", 0)
	_chat.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(_chat)


func chat(text: String, col := Color.BLACK) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", col)
	l.clip_text = true
	l.custom_minimum_size.x = 510
	_chat.add_child(l)
	_lines.append(l)
	while _lines.size() > 8:
		(_lines.pop_front() as Label).queue_free()


# ------------------------------------------------------------------- boss

func _build_boss_bar() -> void:
	_boss_bar = Control.new()
	_boss_bar.position = Vector2(500, 10)
	_boss_bar.size = Vector2(600, 56)
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.draw.connect(_draw_boss_bar)
	_root.add_child(_boss_bar)


func _draw_boss_bar() -> void:
	if _sim == null:
		return
	var f := clampf(float(_sim.boss.hp) / float(_sim.boss.max_hp), 0.0, 1.0)
	_boss_bar.draw_rect(Rect2(0, 0, 600, 24), Color("#1a1610"))
	_boss_bar.draw_rect(Rect2(2, 2, 596, 20), Color("#b01010"))
	_boss_bar.draw_rect(Rect2(2, 2, 596 * f, 20), Color("#18a818"))
	_boss_bar.draw_string(_font, Vector2(0, 17), "Tumeken's Warden   %d / %d" % [int(ceilf(float(_sim.boss.hp))), int(_sim.boss.max_hp)],
		HORIZONTAL_ALIGNMENT_CENTER, 600, 13, Color.WHITE)
	for m in [0.66, 0.33]:
		_boss_bar.draw_line(Vector2(2 + 596 * m, 2), Vector2(2 + 596 * m, 22), Color(0, 0, 0, 0.6), 2.0)


# ---------------------------------------------------------------- splats

func splat(node: Node3D, val: int, blocked: bool, emp := false, height := 2.2) -> void:
	var col := Color("#3a6fd8") if (blocked or val == 0) else (Color("#d8a020") if emp else Color("#c81e1e"))
	_splats.append({ "node": node, "val": val, "col": col, "t": 1.0, "h": height, "off": Vector2(randf_range(-14, 14), randf_range(-8, 8)) })


func _draw_splats() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for s in _splats:
		var n: Node3D = s.node
		if not is_instance_valid(n):
			continue
		var wp := n.global_position + Vector3(0, float(s.h), 0)
		if cam.is_position_behind(wp):
			continue
		var p := cam.unproject_position(wp) + (s.off as Vector2)
		var a := clampf(float(s.t) / 0.3, 0.0, 1.0)
		_splat_layer.draw_circle(p, 14.0, Color(s.col, a))
		_splat_layer.draw_arc(p, 14.0, 0, TAU, 20, Color(0, 0, 0, a), 2.0)
		_splat_layer.draw_string(_font, p + Vector2(-20, 5), str(s.val), HORIZONTAL_ALIGNMENT_CENTER, 40, 14, Color(1, 1, 1, a))


# ---------------------------------------------------------------- refresh

func refresh(s: OsrsSim) -> void:
	_sim = s
	var dt := get_process_delta_time()
	for sp in _splats.duplicate():
		sp.t = float(sp.t) - dt
		if float(sp.t) <= 0.0:
			_splats.erase(sp)
	_splat_layer.queue_redraw()
	_boss_bar.queue_redraw()
	_orbs.queue_redraw()
	_mini.queue_redraw()
	for b in _pray_btns.values():
		(b as Control).queue_redraw()
	for c in _inv:
		(c as Control).queue_redraw()
	var emp := int(s.me.empowered)
	_top.text = "Time %s   ·   Phase %d   ·   %s%s" % [clock(s.tick * OsrsSim.TICK), s.phase(), "Bow (10-45, 4 ticks)" if s.me.weapon == "bow" else "Staff (15-55, 5 ticks)",
		("   ·   Sun-blessed x%d" % emp) if emp > 0 else ""]


func finish(r: Dictionary) -> void:
	_end = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(STONE, 0.95)
	sb.border_color = Color("#b89a5a")
	sb.set_border_width_all(3)
	sb.set_content_margin_all(18)
	_end.add_theme_stylebox_override("panel", sb)
	_end.position = Vector2(520, 300)
	_end.size = Vector2(560, 180)
	_root.add_child(_end)
	var v := VBoxContainer.new()
	_end.add_child(v)
	var title: String = { "win": "The Warden falls!", "dead": "Oh dear, you are dead!", "time": "Out of time." }.get(str(r.how), "")
	var t := _text(v, title, Vector2.ZERO, 26, YELLOW if r.how == "win" else Color("#ff3020"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var lines := "Time %s   ·   damage dealt %d (%d%%)\nPrayed right %d of %d   ·   dodged %d, hit by %d   ·   Sun Sigils %d" % [clock(float(r.secs)), int(r.boss_dmg),
		int(round(float(r.boss_pct) * 100.0)), int(r.blocked), int(r.blocked) + int(r.unblocked), int(r.dodged), int(r.struck), int(r.sigils)]
	var l := _text(v, lines, Vector2.ZERO, 14, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
