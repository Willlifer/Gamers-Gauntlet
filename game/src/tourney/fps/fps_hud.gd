class_name FpsHud
extends CanvasLayer
## First-person HUD. Under it, the view-model layer: a full-screen
## SubViewport sharing the world, its camera following the player's eye but
## seeing only render layer 2 (the gun) at its own FOV.
## On top:
##   reticle   CS:GO-style: four lines round a gap. The gap is the player's
##             current inaccuracy (FpsPlayer.spread_deg) in screen pixels, so
##             it snaps open when you run or jump and closes when you stop;
##             FpsTune.cross_snap sets how fast it follows.
##   scope     the sniper's 4x: black round the lens, thin crosshair with
##             mil dots, a faint lens vignette
##   status    health, weapon + ammo, stance, score, kill notes, hit marker,
##             a red edge when hurt, "click to play" when the mouse is free

var player: FpsPlayer
var score := Vector2i.ZERO                  ## you, bot
var vm_view: SubViewport
var vm_cam: Camera3D
var _cross: Control
var _scope: Control
var _gap := 5.0
var _hit_t := 0.0
var _hurt_t := 0.0
var _note: Label
var _note_t := 0.0
var _status: Label
var _ammo: Label
var _score_l: Label
var _hp_bar: ColorRect
var _hp_back: ColorRect
var _paused: Label
var _dead: Label


func _ready() -> void:
	layer = 10
	# the view model's own render
	var vc := SubViewportContainer.new()
	vc.stretch = true
	vc.set_anchors_preset(Control.PRESET_FULL_RECT)
	vc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vc)
	vm_view = SubViewport.new()
	vm_view.transparent_bg = true
	vm_view.world_3d = get_viewport().world_3d
	vm_view.msaa_3d = Viewport.MSAA_4X
	vc.add_child(vm_view)
	vm_cam = Camera3D.new()
	vm_cam.cull_mask = FpsViewmodel.LAYER
	vm_cam.near = 0.01
	vm_cam.far = 10.0
	# the gun's own light: a sky to reflect, a key from above-left and a
	# fill, on its layer only, so it reads the same wherever you stand
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#8fb3d9")
	sm.sky_horizon_color = Color("#e3e6e4")
	sm.ground_horizon_color = Color("#9a9a90")
	sm.ground_bottom_color = Color("#4a4a44")
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	vm_cam.environment = env
	vm_view.add_child(vm_cam)
	vm_cam.make_current()
	for spec in [[Vector3(-50, 35, 0), 1.6, Color("#fff2dc")], [Vector3(-10, -140, 0), 0.5, Color("#dce6ff")]]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = spec[0]
		l.light_energy = spec[1]
		l.light_color = spec[2]
		l.light_cull_mask = FpsViewmodel.LAYER
		vm_cam.add_child(l)
	# the overlays
	_scope = Control.new()
	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope.draw.connect(_draw_scope)
	add_child(_scope)
	_cross = Control.new()
	_cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	add_child(_cross)
	_status = _label(Vector2(24, -64), 18, Control.PRESET_BOTTOM_LEFT)
	_ammo = _label(Vector2(-300, -64), 22, Control.PRESET_BOTTOM_RIGHT)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo.size.x = 276
	_score_l = _label(Vector2(-160, 14), 26, Control.PRESET_CENTER_TOP)
	_score_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_l.size.x = 320
	_note = _label(Vector2(-300, 56), 18, Control.PRESET_CENTER_TOP)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.size.x = 600
	_hp_back = ColorRect.new()
	_hp_back.color = Color(0, 0, 0, 0.45)
	_hp_back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hp_back.position = Vector2(24, -30)
	_hp_back.size = Vector2(240, 12)
	_hp_back.offset_top = -30
	_hp_back.offset_bottom = -18
	_hp_back.offset_left = 24
	_hp_back.offset_right = 264
	add_child(_hp_back)
	_hp_bar = ColorRect.new()
	_hp_bar.color = Color("#7fd35a")
	_hp_bar.size = Vector2(240, 12)
	_hp_back.add_child(_hp_bar)
	var hint := _label(Vector2(-260, -26), 13, Control.PRESET_BOTTOM_RIGHT)
	hint.text = "F1 tune · Esc free mouse · 1 primary · 2 sidearm"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.size.x = 236
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	_paused = _label(Vector2(-200, -20), 24, Control.PRESET_CENTER)
	_paused.text = "Click to play"
	_paused.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paused.size.x = 400
	_dead = _label(Vector2(-200, 40), 30, Control.PRESET_CENTER)
	_dead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dead.size.x = 400
	_dead.add_theme_color_override("font_color", Color("#ff6b5e"))


func _label(at: Vector2, size: int, preset: int) -> Label:
	var l := Label.new()
	l.set_anchors_preset(preset)
	l.position = at
	l.offset_left = at.x
	l.offset_top = at.y
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func note(t: String) -> void:
	_note.text = t
	_note_t = 2.2


func hit_marker() -> void:
	_hit_t = 0.18


func hurt() -> void:
	_hurt_t = 0.6


func _process(delta: float) -> void:
	if player == null:
		return
	# the view-model camera rides the eye at its own FOV
	vm_cam.global_transform = player.cam.global_transform
	vm_cam.fov = FpsTune.value("vm_fov") * lerpf(1.0, 0.82, player.vm.ads)
	# reticle gap: the spread cone's half-angle in pixels; snaps open, eases shut
	var vp := get_viewport().get_visible_rect().size
	var half := deg_to_rad(player.spread_deg) * 0.5
	var px := tan(half) / tan(deg_to_rad(player.cam.fov) * 0.5) * vp.y * 0.5
	var want := FpsTune.value("cross_gap") + px
	var rate := FpsTune.value("cross_snap") * (3.0 if want > _gap else 1.0)
	_gap = lerpf(_gap, want, minf(1.0, delta * rate))
	_hit_t -= delta
	_hurt_t -= delta
	_note_t -= delta
	_note.visible = _note_t > 0.0
	_cross.queue_redraw()
	_scope.queue_redraw()
	var sp := player.spec()
	var mag := int(sp.mag)
	if sp.get("dual", false):
		_ammo.text = "%s   %d  |  %d" % [sp.name, int(player.ammo.dual_l), int(player.ammo.dual_r)]
	else:
		_ammo.text = "%s   %s" % [sp.name, ("%d / %d" % [player.ammo[player.weapon], mag]) if mag > 0 else "∞"]
	if player.scarce and mag > 0:
		# Extraction: the pouch's magazines of this gun's caliber
		_ammo.text += "  |  %d mags" % int(player.mags.get(str(sp.get("caliber", "rifle")), 0))
	_status.text = "%d HP    %s" % [int(player.hp), player.stance.to_upper()]
	_hp_bar.size.x = 240.0 * player.hp / 100.0
	_hp_bar.color = Color("#7fd35a") if player.hp > 40.0 else Color("#ff6b5e")
	_score_l.text = "You %d  –  %d Bot" % [score.x, score.y]
	_paused.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and player.input_on
	_dead.visible = not player.alive


func _draw_cross() -> void:
	var c := _cross.size * 0.5
	if player and player.alive and not player.scoped and player.vm.ads < 0.6:
		var g := _gap
		var ln := FpsTune.value("cross_len")
		var col := Color(0.55, 1.0, 0.45, 0.95)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var a: Vector2 = c + d * g
			var b: Vector2 = c + d * (g + ln)
			_cross.draw_line(a, b, Color(0, 0, 0, 0.75), 5.0)
			_cross.draw_line(a, b, col, 2.5)
	if _hit_t > 0.0:
		var k := 6.0 + (0.18 - _hit_t) * 30.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_cross.draw_line(c + d * k, c + d * (k + 7.0), Color(1, 1, 1, 0.9), 2.0)
	if _hurt_t > 0.0:
		var a := clampf(_hurt_t, 0.0, 0.6) * 0.5
		var s := _cross.size
		for i in 6:
			var w := 40.0 + i * 18.0
			var col := Color(0.8, 0.05, 0.05, a * (1.0 - i / 6.0) * 0.5)
			_cross.draw_rect(Rect2(0, 0, w, s.y), col)
			_cross.draw_rect(Rect2(s.x - w, 0, w, s.y), col)


func _draw_scope() -> void:
	if player == null or not player.scoped:
		return
	var s := _scope.size
	var c := s * 0.5
	var r := s.y * 0.46
	# black all round the lens
	_scope.draw_rect(Rect2(Vector2.ZERO, Vector2(c.x - r + 1, s.y)), Color.BLACK)
	_scope.draw_rect(Rect2(Vector2(c.x + r - 1, 0), Vector2(s.x, s.y)), Color.BLACK)
	for k in 64:
		var a0 := TAU * k / 64.0
		var a1 := TAU * (k + 1) / 64.0
		var p0 := c + Vector2(cos(a0), sin(a0)) * r
		var p1 := c + Vector2(cos(a1), sin(a1)) * r
		var q0 := c + Vector2(cos(a0), sin(a0)) * r * 1.6
		var q1 := c + Vector2(cos(a1), sin(a1)) * r * 1.6
		_scope.draw_colored_polygon(PackedVector2Array([p0, q0, q1, p1]), Color.BLACK)
	# lens vignette
	for i in 5:
		_scope.draw_arc(c, r - i * 6.0, 0, TAU, 96, Color(0, 0, 0, 0.35 - i * 0.07), 6.0)
	# the reticle: thin cross, thick posts, mil dots
	var col := Color(0.03, 0.03, 0.03)
	_scope.draw_line(c - Vector2(r, 0), c + Vector2(r, 0), col, 1.5)
	_scope.draw_line(c - Vector2(0, r), c + Vector2(0, r), col, 1.5)
	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
		_scope.draw_line(c + d * r * 0.55, c + d * r, col, 5.0)
	for k in range(1, 5):
		for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			_scope.draw_circle(c + d * r * 0.11 * k, 2.2, col)
