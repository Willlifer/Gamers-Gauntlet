class_name FpsTouch
extends CanvasLayer
## G67: the shooters' touch controls, over every FPS world (the three duels
## and Extraction). On only on a phone or tablet (a native mobile build, or
## the web build on a touchscreen whose main pointer is coarse), or with
## `-- --touch` (the desktop mouse then plays one finger), or `?touch=1` on
## the web page; `-- --no-touch` / `?touch=0` turn it off. Off, nothing here
## exists and the desktop game is unchanged.
##   Left: a floating stick: touch anywhere in the left part of the screen;
##     how far you push is how fast you go (FpsTune.touch_stick is its radius).
##   Right: drag anywhere that isn't a button to look (FpsTune.touch_sens,
##     degrees per 100 px). FIRE: hold to fire; drag the same finger to look.
##     AIM: a toggle (aim in / out). With the Dual Berettas AIM becomes the
##     right gun's trigger (FIRE the left), held like FIRE, as LMB / RMB are
##     on a desktop. RELOAD, SWAP (the other slot), JUMP (stand up first when
##     down), CROUCH (tap crouch / stand, hold prone, as Shift).
##   Extraction: USE (F: the chest or pickup in reach; it lights up when
##     there is one) and MED (4: the medkit, only while you carry one).
##   Top left: II pauses (what Esc is on a desktop: the match keeps running;
##     look speed, the F1 feel numbers, Leave = F10), and on the web a
##     full-screen button. Portrait: a "turn your phone" card.
## The fingers are read as InputEventScreenTouch / ScreenDrag by index, so
## move, look and fire work at once. While the controls are live they eat
## the mouse events Godot emulates from the first finger, so a touch never
## clicks, captures or fires through the desktop path. They stand down
## (and let taps through) while the radial loadout, the F1 panel or the
## pause card is up, and when you're dead.

## Tools: 1 forces the controls on, 0 off; -1 decides from the device.
static var force := -1
## Resolved by wanted(): are the touch controls on this run?
static var on := false
static var _decided := false

const DEAD := 0.12                          # stick dead zone (of its radius)
const FULL := 0.85                          # stick push that is full speed

var world: FpsWorld
var _pad: Control
var _touches := {}                          # finger index -> { role, at }
var _stick_c := Vector2.ZERO                # where the stick's ring is (rest spot when idle)
var _stick_p := Vector2.ZERO
var _stick_i := -1
var _btn := {}                              # id -> { at: Vector2, r: float, label: String }
var _live := false
var _pause: CanvasLayer
var _rot: CanvasLayer
var _leave_armed := false
var _size := Vector2.ZERO


## Should this run have the touch controls (decided once)?
static func wanted() -> bool:
	if force >= 0:
		on = force == 1
		return on
	if _decided:
		return on
	_decided = true
	on = _detect()
	if on and not OS.has_feature("mobile") and not OS.has_feature("web"):
		Input.emulate_touch_from_mouse = true   # -- --touch on a desktop: the mouse is a finger
	return on


static func _detect() -> bool:
	var args := OS.get_cmdline_user_args()
	if "--no-touch" in args:
		return false
	if "--touch" in args:
		return true
	if OS.has_feature("mobile"):
		return true
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("window.location.search", true))
		if q.contains("touch=1"):
			return true
		if q.contains("touch=0"):
			return false
		if not DisplayServer.is_touchscreen_available():
			return false
		# a touch laptop keeps the mouse: only a coarse main pointer (a phone, a tablet)
		return bool(JavaScriptBridge.eval("!!(window.matchMedia && window.matchMedia('(pointer: coarse)').matches)", true))
	return false                            # desktop: only on -- --touch (a touch laptop keeps the mouse)


func _ready() -> void:
	layer = 15                              # over the HUD (10), under the radial (20) and F1 (50)
	_pad = Control.new()
	_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.draw.connect(_draw_pad)
	add_child(_pad)
	_rot = CanvasLayer.new()
	_rot.layer = 60
	_rot.visible = false
	add_child(_rot)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.03, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rot.add_child(dim)
	var l := Label.new()
	l.text = "Turn your phone sideways\n\nThe shooters play in landscape."
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 64)
	dim.add_child(l)
	_layout()
	_stick_c = _stick_rest()
	_stick_p = _stick_c
	_fit_hud.call_deferred()


# ----------------------------------------------------------------- layout

func _margin() -> Vector2:
	var m := Vector2(36, 30)
	if OS.has_feature("mobile"):
		# a notch: the display's safe area, in canvas units
		var safe := DisplayServer.get_display_safe_area()
		var scr := Vector2(DisplayServer.window_get_size())
		if scr.x > 0 and safe.size.x > 0:
			var k := _size.x / scr.x
			m.x = maxf(m.x, maxf(safe.position.x, scr.x - safe.end.x) * k + 12.0)
			m.y = maxf(m.y, maxf(safe.position.y, scr.y - safe.end.y) * k + 8.0)
	return m


func _stick_rest() -> Vector2:
	var m := _margin()
	var r := FpsTune.value("touch_stick")
	return Vector2(m.x + r + 70.0, _size.y - m.y - r - 50.0)


## The buttons around FIRE, in the bottom-right thumb's arc.
func _layout() -> void:
	_size = _pad.size if _pad.size != Vector2.ZERO else get_viewport().get_visible_rect().size
	var m := _margin()
	var f := Vector2(_size.x - m.x - 118.0, _size.y - m.y - 132.0)
	_btn = {}
	var duals := world != null and world.player != null and bool(world.player.spec().get("dual", false))
	_btn.fire = { "at": f, "r": 92.0, "label": "FIRE" if not duals else "FIRE L" }
	_btn.aim = { "at": f + Vector2(-178, -132), "r": 64.0, "label": "AIM" if not duals else "FIRE R" }
	_btn.reload = { "at": f + Vector2(-206, 52), "r": 58.0, "label": "RELOAD" }
	_btn.swap = { "at": f + Vector2(4, -222), "r": 58.0, "label": "SWAP" }
	_btn.jump = { "at": f + Vector2(-350, 8), "r": 58.0, "label": "JUMP" }
	_btn.crouch = { "at": f + Vector2(-340, -170), "r": 58.0, "label": "CROUCH" }
	if world is ExtractWorld:
		_btn.use = { "at": f + Vector2(-176, -300), "r": 62.0, "label": "USE" }
		if (world as ExtractWorld).medkit:
			_btn.med = { "at": f + Vector2(4, -380), "r": 52.0, "label": "MED" }
	_btn.pause = { "at": Vector2(m.x + 40.0, m.y + 40.0), "r": 40.0, "label": "II" }
	if OS.has_feature("web"):
		_btn.full = { "at": Vector2(m.x + 140.0, m.y + 40.0), "r": 40.0, "label": "[  ]" }


## The HUD's bottom corners are the thumbs' now: HP and stance to the top
## left (after the pause button), the gun and the mags to the top right;
## the key hint line goes.
func _fit_hud() -> void:
	var hud := world.hud if world else null
	if hud == null:
		return
	var m := _margin()
	var x := m.x + 96.0 + (100.0 if OS.has_feature("web") else 0.0)
	_place(hud._status, x, m.y + 2.0, 400.0, 28.0, false)
	_place(hud._hp_back, x, m.y + 34.0, 240.0, 12.0, false)
	_place(hud._ammo, m.x, m.y + 2.0, 560.0, 32.0, true)
	if hud is ExtractHud:
		var xh := hud as ExtractHud
		_place(xh._kit_l, x, m.y + 52.0, 400.0, 24.0, false)
		_place(xh._mags_l, m.x, m.y + 36.0, 400.0, 24.0, true)
	for c in hud.get_children():
		if c is Label and (str((c as Label).text).begins_with("F1 tune") or str((c as Label).text).begins_with("F interact")):
			(c as Label).visible = false


## Pin `c` to the top left (or top right, `right` = its distance from the right edge).
func _place(c: Control, x: float, y: float, w: float, h: float, right: bool) -> void:
	if right:
		c.anchor_left = 1.0
		c.anchor_right = 1.0
		c.offset_left = -x - w
		c.offset_right = -x
	else:
		c.anchor_left = 0.0
		c.anchor_right = 0.0
		c.offset_left = x
		c.offset_right = x + w
	c.anchor_top = 0.0
	c.anchor_bottom = 0.0
	c.offset_top = y
	c.offset_bottom = y + h


# ----------------------------------------------------------------- state

func _portrait() -> bool:
	return _size.x < _size.y * 1.1


## Do the controls take the fingers right now?
func live() -> bool:
	var p := world.player if world else null
	return p != null and p.input_on and p.alive and not world.menu_open() and _pause == null and not _portrait() \
		and not (world is ExtractWorld and (world as ExtractWorld).ended)


func _process(_delta: float) -> void:
	_layout()
	_rot.visible = _portrait()
	var now := live()
	if _live and not now:
		_release_all()
	_live = now
	if _pause and world.menu_open():
		_close_pause()
	if _stick_i < 0:
		_stick_c = _stick_rest()
		_stick_p = _stick_c
	_pad.queue_redraw()


func _release_all() -> void:
	_touches.clear()
	_stick_i = -1
	var p := world.player
	p.touch_move = Vector2.ZERO
	p.touch_fire = false
	p.touch_fire_r = false
	p.touch_crouch = false


# ----------------------------------------------------------------- input

func _input(ev: InputEvent) -> void:
	if not _live:
		if ev is InputEventScreenTouch and not ev.pressed:
			_touches.erase(ev.index)
		return
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_press(ev.index, ev.position)
		else:
			_release(ev.index)
		get_viewport().set_input_as_handled()
	elif ev is InputEventScreenDrag:
		_drag(ev.index, ev.position, ev.relative)
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton or ev is InputEventMouseMotion:
		# the mouse Godot emulates from the first finger (or, with -- --touch,
		# the real one): never the desktop path's click, capture or trigger
		get_viewport().set_input_as_handled()


## Which button (if any) is under `at`: the nearest within 1.15 radii.
func button_at(at: Vector2) -> String:
	var best := ""
	var bd := INF
	for id: String in _btn:
		var b: Dictionary = _btn[id]
		var d := at.distance_to(b.at) / float(b.r)
		if d <= 1.15 and d < bd:
			bd = d
			best = id
	return best


func _press(i: int, at: Vector2) -> void:
	var p := world.player
	var id := button_at(at)
	if id != "":
		_touches[i] = { "role": id, "at": at }
		match id:
			"fire":
				p.touch_fire = true
			"aim":
				if p.spec().get("dual", false):
					p.touch_fire_r = true
				else:
					p.touch_aim = not p.touch_aim
			"reload":
				p.reload()
			"swap":
				p.next_weapon()
			"jump":
				p.jump()
			"crouch":
				p.touch_crouch = true
			"use":
				(world as ExtractWorld).interact()
			"med":
				(world as ExtractWorld).use_medkit()
			"pause":
				_open_pause()
			"full":
				_fullscreen()
		return
	if at.x < _size.x * 0.42 and at.y > _size.y * 0.22 and _stick_i < 0:
		_stick_i = i
		var r := FpsTune.value("touch_stick")
		var m := _margin()
		_stick_c = Vector2(clampf(at.x, m.x + r, _size.x * 0.42), clampf(at.y, m.y + r, _size.y - m.y - r))
		_stick_p = at
		_touches[i] = { "role": "stick", "at": at }
		_update_stick()
		return
	_touches[i] = { "role": "look", "at": at }


func _release(i: int) -> void:
	if not _touches.has(i):
		return
	var role := str(_touches[i].role)
	_touches.erase(i)
	var p := world.player
	match role:
		"stick":
			_stick_i = -1
			p.touch_move = Vector2.ZERO
		"fire":
			p.touch_fire = false
		"aim":
			p.touch_fire_r = false
		"crouch":
			p.touch_crouch = false


func _drag(i: int, at: Vector2, rel: Vector2) -> void:
	if not _touches.has(i):
		return
	var role := str(_touches[i].role)
	_touches[i].at = at
	if role == "stick":
		_stick_p = at
		_update_stick()
	elif role == "look" or role == "fire" or (role == "aim" and world.player.touch_fire_r):
		world.player.touch_look(rel)


func _update_stick() -> void:
	var r := FpsTune.value("touch_stick")
	var v := (_stick_p - _stick_c) / r
	var n := v.length()
	if n < DEAD:
		world.player.touch_move = Vector2.ZERO
		return
	var amt := clampf((n - DEAD) / (FULL - DEAD), 0.0, 1.0)
	var d := v / n
	world.player.touch_move = Vector2(d.x, -d.y) * amt   # screen up is forward


# ----------------------------------------------------------------- draw

func _draw_pad() -> void:
	if not _live:
		return
	var a := FpsTune.value("touch_alpha")
	var font := ThemeDB.fallback_font
	var p := world.player
	# the stick
	var r := FpsTune.value("touch_stick")
	var held := _stick_i >= 0
	_pad.draw_circle(_stick_c, r, Color(0, 0, 0, 0.22 * a * (1.4 if held else 1.0)))
	_pad.draw_arc(_stick_c, r, 0, TAU, 64, Color(1, 1, 1, 0.55 * a), 3.0, true)
	var off := (_stick_p - _stick_c).limit_length(r)
	_pad.draw_circle(_stick_c + off, r * 0.42, Color(1, 1, 1, (0.55 if held else 0.3) * a))
	if not held:
		_pad.draw_string(font, _stick_c + Vector2(-r, r + 30), "MOVE", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 18, Color(1, 1, 1, 0.6 * a))
	# the buttons
	var down := {}
	for i in _touches:
		down[str(_touches[i].role)] = true
	for id: String in _btn:
		var b: Dictionary = _btn[id]
		var on_ := down.has(id) or (id == "aim" and p.touch_aim) or (id == "crouch" and p.stance != "stand")
		var lit := false
		if id == "use" and world is ExtractWorld:
			lit = (world as ExtractWorld).xhud.prompt != ""
		var fill := Color(1, 1, 1, 0.38 * a) if on_ else (Color(0.5, 0.85, 0.35, 0.4 * a) if lit else Color(0, 0, 0, 0.3 * a))
		if id == "fire":
			fill = Color(0.85, 0.2, 0.15, (0.6 if on_ else 0.35) * a)
		_pad.draw_circle(b.at, b.r, fill)
		_pad.draw_arc(b.at, b.r, 0, TAU, 48, Color(1, 1, 1, (0.9 if on_ else 0.6) * a), 3.0, true)
		var label := str(b.label)
		if id == "crouch" and p.stance == "prone":
			label = "PRONE"
		var fs := 26 if id == "fire" else (20 if label.length() <= 4 else 16)
		var tc := Color(1, 1, 1, minf(1.0, 0.95 * a + 0.3))
		_pad.draw_string_outline(font, b.at + Vector2(-b.r, fs * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER, b.r * 2.0, fs, 4, Color(0, 0, 0, 0.6 * a))
		_pad.draw_string(font, b.at + Vector2(-b.r, fs * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER, b.r * 2.0, fs, tc)
		if id == "swap":
			var other := str(p.slots[(p.slots.find(p.weapon) + 1) % p.slots.size()])
			var nm := str(FpsWeapons.spec(other).get("name", other))
			_pad.draw_string_outline(font, b.at + Vector2(-90, b.r + 20), nm, HORIZONTAL_ALIGNMENT_CENTER, 180, 14, 4, Color(0, 0, 0, 0.6))
			_pad.draw_string(font, b.at + Vector2(-90, b.r + 20), nm, HORIZONTAL_ALIGNMENT_CENTER, 180, 14, Color(1, 1, 1, 0.8 * a + 0.2))
		if id == "use" and lit:
			var pr := (world as ExtractWorld).xhud.prompt
			_pad.draw_string_outline(font, b.at + Vector2(-110, -b.r - 10), pr, HORIZONTAL_ALIGNMENT_CENTER, 220, 15, 4, Color(0, 0, 0, 0.7))
			_pad.draw_string(font, b.at + Vector2(-110, -b.r - 10), pr, HORIZONTAL_ALIGNMENT_CENTER, 220, 15, Color("#c8f0a0"))


# ----------------------------------------------------------------- pause

## II: the desktop's Esc (the match keeps running), with what a phone has no
## key for: look speed, the F1 numbers, Leave (F10).
func _open_pause() -> void:
	_release_all()
	_leave_armed = false
	_pause = CanvasLayer.new()
	_pause.layer = 55
	add_child(_pause)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = BWStyle.theme()
	_pause.add_child(root)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.045, 0.05, 0.9)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(28)
	sb.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.custom_minimum_size = Vector2(520, 0)
	panel.offset_left = -_margin().x - 560
	panel.offset_right = -_margin().x - 40
	panel.offset_top = -250
	panel.offset_bottom = 250
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)
	var t := Label.new()
	t.text = "Paused"
	t.add_theme_font_size_override("font_size", 40)
	col.add_child(t)
	var sub := Label.new()
	sub.text = "The match keeps running."
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	col.add_child(sub)
	_big_button(col, "Resume", _close_pause)
	var sl := Label.new()
	sl.add_theme_font_size_override("font_size", 22)
	col.add_child(sl)
	var s := HSlider.new()
	var e: Array = FpsTune.ENTRIES.touch_sens
	s.min_value = float(e[2])
	s.max_value = float(e[3])
	s.step = float(e[4])
	s.value = FpsTune.value("touch_sens")
	s.custom_minimum_size = Vector2(0, 56)
	var show := func(v: float) -> void: sl.text = "Look speed  %.1f" % v
	show.call(s.value)
	s.value_changed.connect(func(v: float) -> void:
		FpsTune.set_value("touch_sens", v)
		show.call(v))
	col.add_child(s)
	_big_button(col, "Feel numbers (F1)", func() -> void: world.toggle_tune())
	var leave := _big_button(col, "Leave game", Callable())
	leave.pressed.connect(func() -> void:
		if not _leave_armed:
			_leave_armed = true
			leave.text = "Tap again to leave (forfeit)"
			return
		_close_pause()
		var k := InputEventKey.new()      # F10: the shell leaves the game (quick play: the lobby; a match: a forfeit)
		k.physical_keycode = KEY_F10
		k.keycode = KEY_F10
		k.pressed = true
		Input.parse_input_event(k)
		var up := k.duplicate()
		up.pressed = false
		Input.parse_input_event(up))


func _big_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 76)
	b.add_theme_font_size_override("font_size", 26)
	if cb.is_valid():
		b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _close_pause() -> void:
	if _pause:
		_pause.queue_free()
		_pause = null
	if world._tune != null:
		world.toggle_tune()


func pause_open() -> bool:
	return _pause != null


## The web build: full screen (and landscape where the browser allows it).
func _fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try { screen.orientation.lock('landscape').catch(function(){}); } catch (e) {}", true)
