class_name ExtractHud
extends FpsHud
## Extraction's HUD: the FpsHud (reticle, health, ammo, notes) plus the raid's
## own readouts. The duel score line becomes the clock. Bottom right under
## the ammo: mags per calibre (the pouch; FpsTune.mag_cap each). Bottom left
## over the health: armour left to soak, the medkit slot (4 / hold F), the
## money. Top: a compass strip (N E S W ticks turning with your yaw) that
## carries the extract's bearing as a green diamond once the flare is up.
## Mid-screen: the interact prompt ("F  Open chest") and the loot pop-up (what
## you got, listed, fading after 3 s). Edge: a red "!" toward every guard
## whose bark you heard this moment (within guard_hear_range), 1.2 s each.

var clock := 0.0                        ## seconds left (the world sets it)
var money := 0
var armour := 0.0                       ## soak left; 0 = none worn
var medkit := false
var healing := -1.0                     ## medkit progress 0..1; < 0 idle
var extract_at := Vector3.INF           ## the pad once revealed
var extracting := -1.0                  ## seconds stood on the pad; < 0 off it
var prompt := ""
var mags := {}                          ## caliber -> count
var _pop: Label
var _pop_t := 0.0
var _prompt_l: Label
var _marks: Array = []                  # [{ pos: Vector3, t: float }]
var _extra: Control
var _mags_l: Label
var _kit_l: Label


func _ready() -> void:
	super._ready()
	_extra = Control.new()
	_extra.set_anchors_preset(Control.PRESET_FULL_RECT)
	_extra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_extra.draw.connect(_draw_extra)
	add_child(_extra)
	_mags_l = _label(Vector2(-300, -88), 15, Control.PRESET_BOTTOM_RIGHT)
	_mags_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mags_l.size.x = 276
	_mags_l.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_ammo.offset_left = -560                   # the ammo line carries the mags count now: room for it
	_ammo.size.x = 536
	_note.offset_top = 88                      # under the compass strip
	_kit_l = _label(Vector2(24, -118), 16, Control.PRESET_BOTTOM_LEFT)
	_kit_l.size.x = 400
	_prompt_l = _label(Vector2(-200, 40), 20, Control.PRESET_CENTER)
	_prompt_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_l.size.x = 400
	_pop = _label(Vector2(-220, 90), 17, Control.PRESET_CENTER)
	_pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pop.size.x = 440
	_pop.add_theme_color_override("font_color", Color("#ffe08a"))
	_dead.text = "You died."
	# the duel's hint line doesn't apply
	for c in get_children():
		if c is Label and str((c as Label).text).begins_with("F1 tune"):
			(c as Label).text = "F interact · 4 medkit · 1 primary · 2 sidearm · F1 tune"
			(c as Label).offset_left = -460
			(c as Label).size.x = 436


## The loot pop-up: one line per item.
func loot_popup(items: Array) -> void:
	var lines := PackedStringArray()
	for it: Dictionary in items:
		lines.append("+ " + ExtractLoot.label(it))
	_pop.text = "\n".join(lines)
	_pop_t = 3.0


## A guard barked at `pos`: a "!" toward it for a moment.
func guard_mark(pos: Vector3) -> void:
	_marks.append({ "pos": pos, "t": 1.2 })


func clock_text() -> String:
	var s := maxi(0, ceili(clock))
	return "%d:%02d" % [s / 60, s % 60]


func _process(delta: float) -> void:
	super._process(delta)
	if player == null:
		return
	_score_l.text = clock_text()
	_score_l.add_theme_color_override("font_color", Color("#ff6b5e") if clock < 30.0 else (Color("#ffe08a") if extract_at != Vector3.INF else Color.WHITE))
	_mags_l.text = "mags   R %d  ·  S %d  ·  P %d" % [int(mags.get("rifle", 0)), int(mags.get("shotgun", 0)), int(mags.get("pistol", 0))]
	var kit := PackedStringArray()
	kit.append(ExtractLoot.dollars(money))
	if armour > 0.0:
		kit.append("ARMOUR %d" % int(ceilf(armour)))
	if healing >= 0.0:
		kit.append("HEALING %d%%" % int(healing * 100.0))
	elif medkit:
		kit.append("MEDKIT [4]")
	_kit_l.text = "    ".join(kit)
	_pop_t -= delta
	_pop.visible = _pop_t > 0.0
	_pop.modulate.a = clampf(_pop_t / 0.6, 0.0, 1.0)
	if extracting >= 0.0:
		_prompt_l.text = "Extracting…  %.1f" % maxf(0.0, 3.0 - extracting)
	else:
		_prompt_l.text = (("" if FpsTouch.on else "F   ") + prompt) if prompt != "" else ""
	_prompt_l.visible = _prompt_l.text != "" and player.alive
	for m: Dictionary in _marks.duplicate():
		m.t -= delta
		if m.t <= 0.0:
			_marks.erase(m)
	_extra.queue_redraw()


## The compass strip, the extract diamond, the guard "!" marks, the extract ring.
func _draw_extra() -> void:
	if player == null:
		return
	var s := _extra.size
	var yaw := player.rotation.y
	# compass: 90° across a 420 px strip at the top
	var cx := s.x * 0.5
	var w := 420.0
	var y0 := 58.0
	_extra.draw_rect(Rect2(cx - w * 0.5, y0 - 16, w, 32), Color(0, 0, 0, 0.35))
	var px_per_rad := w / deg_to_rad(90.0)
	for k in 36:
		var a := deg_to_rad(k * 10.0)
		var rel := wrapf(a + yaw, -PI, PI)            # heading relative to the look (Godot: -Z is north at yaw 0)
		if absf(rel) > deg_to_rad(45.0):
			continue
		var x := cx + rel * px_per_rad
		var major := k % 9 == 0
		_extra.draw_line(Vector2(x, y0 + (5 if major else 9)), Vector2(x, y0 + 14), Color(1, 1, 1, 0.8 if major else 0.4), 2.0 if major else 1.0)
		if major:
			var nm: String = ["N", "E", "S", "W"][k / 9]
			_extra.draw_string(ThemeDB.fallback_font, Vector2(x - 7, y0 + 1), nm, HORIZONTAL_ALIGNMENT_CENTER, 14, 15, Color.WHITE)
	_extra.draw_line(Vector2(cx, y0 - 16), Vector2(cx, y0 - 10), Color.WHITE, 2.0)
	if extract_at != Vector3.INF:
		var d := extract_at - player.global_position
		var bearing := atan2(d.x, -d.z)              # 0 = -Z (north), + clockwise
		var rel := wrapf(bearing + yaw, -PI, PI)
		var x := clampf(cx + rel * px_per_rad, cx - w * 0.5 + 8, cx + w * 0.5 - 8)
		var c := Color("#7fd35a")
		_extra.draw_colored_polygon(PackedVector2Array([Vector2(x, y0 - 8), Vector2(x + 8, y0), Vector2(x, y0 + 8), Vector2(x - 8, y0)]), c)
		var dist := Vector2(d.x, d.z).length()
		_extra.draw_string(ThemeDB.fallback_font, Vector2(x - 30, y0 + 32), "%d m" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 60, 14, c)
	# guards heard: a "!" at the screen edge in their direction
	for m: Dictionary in _marks:
		var d: Vector3 = (m.pos as Vector3) - player.global_position
		var rel := wrapf(atan2(d.x, -d.z) + yaw, -PI, PI)
		var a := clampf(float(m.t) / 0.4, 0.0, 1.0)
		var p := s * 0.5 + Vector2(sin(rel), -cos(rel)) * Vector2(s.x * 0.44, s.y * 0.42)
		p.y = maxf(p.y, 110.0)                       # ahead: under the compass, not over it
		var col := Color(1.0, 0.25, 0.2, a)
		_extra.draw_circle(p, 16.0, Color(0, 0, 0, 0.6 * a))
		_extra.draw_string(ThemeDB.fallback_font, p + Vector2(-5, 9), "!", HORIZONTAL_ALIGNMENT_CENTER, 12, 26, col)
	if extracting >= 0.0:
		var c := s * 0.5
		_extra.draw_arc(c, 44.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(extracting / 3.0, 0.0, 1.0), 48, Color("#7fd35a"), 5.0)
