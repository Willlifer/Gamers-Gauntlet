class_name OsrsView
extends Node3D
## The OSRS raid on screen (G34): the square floor (clear tiles, a gold rim),
## the Warden in the void north and its two phantoms on the flanks (they
## loose the prayable shots, G53), you on your square, skulls when it raises them.
## OsrsSim ticks every 0.6 s; between ticks everything glides along the
## squares it crossed, so pieces look like they pass between squares while
## the game only knows squares.
##   left click a square   walk / run there (the path snaps to squares)
##   left click the Warden  attack (walks into range first)
##   left click a skull     attack it (G53: wield the lightning dagger first)
##   1 / 2 / 3             Protect from Magic / Missiles / Melee
##   arrows, A/D, W/S       turn and tilt the camera; middle drag too; wheel zoom
##   F1                     the numbers (OsrsTune)
## The camera turns freely and always centres on you.

signal over(result: Dictionary)

const TILE := 1.6
const SKULL_PICK_PX := 34.0                     ## a click this close to a skull (head or feet) on screen targets it
const BOSS_POS := Vector3(0, 0, -13.6)          ## the 5x5 piece's centre (square 7, -3)

var sim: OsrsSim
var bot: OsrsBot                                  ## autopilot (tools); null: the mouse plays
var input_on := true

var _acc := 0.0
var _orders := {}
var _cam: Camera3D
var _yaw := 0.0
var _pitch := deg_to_rad(45.0)
var _dist := 27.0
var _drag := false
var _player: BWCharacter
var _player_root: Node3D
var _player_weapon := ""
var _boss: BWCharacter
var _boss_root: Node3D
var _boss_move := ""
var _boss_move_t := 0.0
var _tiles := {}                                  # Vector2i -> MeshInstance3D
var _glow := {}                                   # Vector2i -> MeshInstance3D (slam / tear-out overlay)
var _marks := {}                                  # "bolt:x,y" / "fall:x,y" / "sigil:x,y" -> Node3D
var _rocks := {}                                  # Vector2i -> Node3D
var _projs := {}                                  # id -> { node, proj }
var _shots: Array = []                            # your arrows / bolts in flight
var _hover: MeshInstance3D
var _true_tile: MeshInstance3D
var _click: Node3D
var _click_t := 0.0
var _overhead: Label3D
var _my_overhead: Label3D
var _over_t := -1.0
var _shake := 0.0
var _pose_t := 0.0
var hud: OsrsHud
var _tune: OsrsTunePanel
var _mats := {}
var _phantoms := {}                               # "mage" (west) / "ranger" (east) -> { node, light, label, orb, ... }
var _skulls := {}                                 # skull id -> { node, pips, ring, head, light }
var _fists := {}                                  # "west" / "east" -> Node3D: the Warden's slam fists (G53d)
var _mid_marks := {}                              # middle column x -> MeshInstance3D: the three-square marker (G53d)
var _shield: MeshInstance3D                       # the Warden's magic / bowfire shield bubble (G53b)
var _shield_mark: Label3D


func setup(p_sim: OsrsSim) -> void:
	sim = p_sim


func _ready() -> void:
	BWCharacter.animate = true
	_build_world()
	_build_floor()
	_build_boss()
	_build_player()
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 400.0
	add_child(_cam)
	_cam.make_current()
	hud = OsrsHud.new()
	hud.view = self
	add_child(hud)
	hud.chat("Welcome to the Warden's Trial.", Color("#0000a0"))
	hud.chat("Click a square to move; click the Warden to attack. 1 2 3 pray against magic, missiles, melee.", Color("#000000"))
	hud.chat("The phantoms on the flanks fire the shots you pray against; the Warden does the specials.", Color("#000000"))
	hud.chat("At 75%, 50% and 25% it raises skulls: wield the lightning dagger and skate the lane, clicking skull after skull.", Color("#7a0060"))
	hud.chat("When it shields itself against magic, use the bow; against bowfire, the staff.", Color("#00407a"))
	hud.chat("Stand on a Sun Sigil as it ignites: your next shots hit twice as hard.", Color("#7a4a00"))
	_place_camera(1.0)


# ------------------------------------------------------------------ world

func w(t: Vector2i) -> Vector3:
	return Vector3((t.x - 7) * TILE, 0.0, (t.y - 5.5) * TILE)


func _mat(key: String, col: Color, emit := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var k := "%s%s%.2f%.2f" % [key, col.to_html(), emit, alpha]
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col, alpha)
	m.roughness = 0.9
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[k] = m
	return m


func _box(size: Vector3, at: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	(parent if parent else self).add_child(mi)
	mi.position = at
	return mi


func _build_world() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#06060b")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#8e98b4")
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.05
	e.fog_enabled = true
	e.fog_light_color = Color("#120e18")
	e.fog_density = 0.0035
	we.environment = e
	add_child(we)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 200, 0)
	fill.light_color = Color("#7f96d0")
	fill.light_energy = 0.45
	add_child(fill)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 28, 0)
	sun.light_color = Color("#ffe2b8")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	# the void: a far dark floor, rock shelves round the platform, floating chunks
	_box(Vector3(400, 1, 400), Vector3(0, -26, 0), _mat("void", Color("#0c0b12")))
	_box(Vector3(90, 1, 80), Vector3(0, -14.0, -2), _mat("rubble_floor", Color("#1a2030")))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var rock := _mat("rock", Color("#4a5878"))
	var rock2 := _mat("rock2", Color("#5d6a88"))
	for i in 46:
		var a := rng.randf() * TAU
		var r := rng.randf_range(18.0, 34.0)
		var s := rng.randf_range(0.6, 1.8)
		var b := _box(Vector3(s * rng.randf_range(0.8, 2.0), s * 0.6, s), Vector3(cos(a) * r, rng.randf_range(-12.0, -4.0), sin(a) * r - 4.0), rock if i % 2 else rock2)
		b.rotation = Vector3(rng.randf() * 0.6, rng.randf() * TAU, rng.randf() * 0.6)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the cracked shelf the Warden stands on, falling away into the void
	for i in 9:
		var b := _box(Vector3(rng.randf_range(1.5, 3.5), rng.randf_range(1.0, 2.2), rng.randf_range(1.5, 3.0)),
			BOSS_POS + Vector3(rng.randf_range(-8, 8), rng.randf_range(-3.0, -1.8), rng.randf_range(-4, 3)), rock if i % 2 else rock2)
		b.rotation.y = rng.randf() * TAU
	_box(Vector3(12, 1.2, 9), BOSS_POS + Vector3(0, -0.6, -0.5), _mat("dais", Color("#3b3a46")))
	# jagged rock along the platform's sides and round the Warden's shelf
	for i in 26:
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := rng.randf_range(-16.0, 10.0)
		var s := rng.randf_range(0.5, 1.3)
		var b := _box(Vector3(s * 1.4, s * rng.randf_range(0.6, 1.4), s), Vector3(side * rng.randf_range(13.2, 15.5), rng.randf_range(-2.8, -1.0), z), rock if i % 3 else rock2)
		b.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
	# stars far out
	var star := _mat("star", Color("#cfd8ff"), 3.0)
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	sm.radial_segments = 4
	sm.rings = 2
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sm
	mm.instance_count = 260
	for i in 260:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.2), rng.randf_range(-1, 1)).normalized() * rng.randf_range(160.0, 240.0)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * rng.randf_range(0.5, 1.4)), d))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = star
	add_child(mmi)


func _build_floor() -> void:
	var base := _mat("gap", Color("#160f11"))
	_box(Vector3(OsrsSim.W * TILE + 0.3, 0.6, OsrsSim.H * TILE + 0.3), Vector3(0, -0.42, (OsrsSim.H * 0.5 - 6.0) * TILE + 0.8), base)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for y in OsrsSim.H:
		for x in OsrsSim.W:
			var t := Vector2i(x, y)
			var light := (x + y) % 2 == 0
			var col := Color("#674848") if light else Color("#5f4244")
			col = col.lerp(Color("#55393c"), rng.randf() * 0.15)
			var mi := _box(Vector3(TILE - 0.08, 0.3, TILE - 0.08), w(t) + Vector3(0, -0.15, 0), _mat("tile%d" % (x * 31 + y), col))
			_tiles[t] = mi
			var g := MeshInstance3D.new()
			var q := PlaneMesh.new()
			q.size = Vector2(TILE - 0.1, TILE - 0.1)
			g.mesh = q
			g.visible = false
			add_child(g)
			g.position = w(t) + Vector3(0, 0.03, 0)
			_glow[t] = g
	# the gold rim round the floor
	var gold := _mat("rim", Color("#e0b43a"), 0.6)
	var x0 := -7.5 * TILE
	var x1 := 7.5 * TILE
	var z0 := -6.0 * TILE
	var z1 := (OsrsSim.H - 6.0) * TILE
	for seg in [[Vector3((x0 + x1) * 0.5, 0.02, z0), Vector3(x1 - x0, 0.05, 0.1)], [Vector3((x0 + x1) * 0.5, 0.02, z1), Vector3(x1 - x0, 0.05, 0.1)],
			[Vector3(x0, 0.02, (z0 + z1) * 0.5), Vector3(0.1, 0.05, z1 - z0)], [Vector3(x1, 0.02, (z0 + z1) * 0.5), Vector3(0.1, 0.05, z1 - z0)]]:
		_box(seg[1], seg[0], gold)
	# the hover square and the click cross
	_hover = MeshInstance3D.new()
	_hover.mesh = _square_outline(TILE - 0.12, 0.07)
	_hover.material_override = _mat("hover", Color("#ffff40"), 1.0, 0.6)
	add_child(_hover)
	_true_tile = MeshInstance3D.new()
	_true_tile.mesh = _square_outline(TILE - 0.1, 0.06)
	_true_tile.material_override = _mat("true_tile", Color("#e8f4ff"), 1.5, 0.95)
	add_child(_true_tile)
	_click = Node3D.new()
	add_child(_click)
	for a in [45.0, -45.0]:
		var b := _box(Vector3(0.9, 0.04, 0.12), Vector3(0, 0.06, 0), _mat("clickx", Color("#ffff00"), 1.0), _click)
		b.rotation_degrees.y = a
	_click.visible = false


func _square_outline(s: float, th: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := s * 0.5
	for e in [[Vector2(-h, -h), Vector2(h, -h + th)], [Vector2(-h, h - th), Vector2(h, h)], [Vector2(-h, -h), Vector2(-h + th, h)], [Vector2(h - th, -h), Vector2(h, h)]]:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var p := [Vector3(a.x, 0.04, a.y), Vector3(b.x, 0.04, a.y), Vector3(b.x, 0.04, b.y), Vector3(a.x, 0.04, b.y)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(p[i])
	return st.commit()


func _build_boss() -> void:
	_boss_root = Node3D.new()
	add_child(_boss_root)
	_boss_root.position = BOSS_POS
	_boss = BWCharacter.create(MobaLook.boss_unit())
	MobaLook.tint(_boss, Color("#d9a441"))
	_boss.scale = Vector3.ONE * 2.6
	_boss_root.add_child(_boss)
	_boss.pose("idle")
	_overhead = Label3D.new()
	_overhead.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_overhead.fixed_size = true
	_overhead.pixel_size = 0.0016
	_overhead.font_size = 28
	_overhead.outline_size = 10
	_overhead.no_depth_test = true
	_overhead.position = Vector3(0, 7.6, 0)
	_boss_root.add_child(_overhead)
	var l := OmniLight3D.new()
	l.light_color = Color("#ffcf7a")
	l.light_energy = 1.4
	l.omni_range = 12.0
	l.position = Vector3(0, 5, 3)
	_boss_root.add_child(l)
	# the phantoms on the flanks (after the reference: red ghosts), G53d: the
	# mage (robes, staff) west casts every magic shot, the ranger (a bow) east
	# looses every arrow; which one fires follows the shot's style
	for side in [-1.0, 1.0]:
		var ph := BWCharacter.create(_phantom_unit("mage" if side < 0.0 else "ranger"))
		MobaLook.tint(ph, Color("#ff4a3a"))
		_ghost(ph)
		ph.scale = Vector3.ONE * 2.6
		add_child(ph)
		ph.position = Vector3(side * 14.4, 0.2, -6.0)
		ph.rotation.y = -side * PI * 0.5
		ph.pose("idle")
		var pl := OmniLight3D.new()
		pl.light_color = Color("#ff3a2a")
		pl.light_energy = 4.0
		pl.omni_range = 11.0
		add_child(pl)
		pl.position = ph.position + Vector3(0, 3, 1)
		var lab := Label3D.new()
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.fixed_size = true
		lab.pixel_size = 0.0016
		lab.font_size = 34
		lab.outline_size = 10
		lab.no_depth_test = true
		lab.position = ph.position + Vector3(0, 6.6, 0)
		add_child(lab)
		var orb := MeshInstance3D.new()                       # G53b: the shot gathering in its hand before it looses
		var om := SphereMesh.new()
		om.radius = 0.4
		om.height = 0.8
		orb.mesh = om
		orb.material_override = _mat("ph_orb", Color("#bcd8ff") if side < 0.0 else Color("#7cff5a"), 6.0).duplicate()
		orb.visible = false
		add_child(orb)
		_phantoms["mage" if side < 0.0 else "ranger"] = { "node": ph, "light": pl, "label": lab, "t": 0.0, "side": side, "orb": orb, "wind": false }
	# the shield bubble and its mark (G53b)
	_shield = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 5.4
	sm.height = 10.8
	_shield.mesh = sm
	var shm := StandardMaterial3D.new()
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield.material_override = shm
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield.position = Vector3(0, 3.6, 0)
	_shield.visible = false
	_boss_root.add_child(_shield)
	_shield_mark = Label3D.new()
	_shield_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_shield_mark.fixed_size = true
	_shield_mark.pixel_size = 0.0016
	_shield_mark.font_size = 64
	_shield_mark.outline_size = 10
	_shield_mark.no_depth_test = true
	_shield_mark.position = Vector3(0, 9.2, 0)
	_boss_root.add_child(_shield_mark)
	# G53d: its two great stone fists, either side of it; the one it raises
	# (or both) says which middle column the slam spares
	for side in ["west", "east"]:
		var fist := Node3D.new()
		var stone := _mat("fist_stone", Color("#6e6250"))
		_box(Vector3(2.0, 1.6, 1.8), Vector3.ZERO, stone, fist)
		for k in 4:
			_box(Vector3(0.42, 0.4, 0.5), Vector3(-0.72 + k * 0.48, 0.55, 0.85), stone, fist)
		_box(Vector3(0.9, 0.5, 0.8), Vector3(0.9 if side == "west" else -0.9, -0.2, 0.7), stone, fist)
		var glow := OmniLight3D.new()
		glow.name = "Glow"
		glow.light_color = Color("#ff9a30")
		glow.light_energy = 0.0
		glow.omni_range = 7.0
		fist.add_child(glow)
		add_child(fist)
		fist.position = _fist_rest(side)
		_fists[side] = fist
	# the three middle columns marked at the top row, like a player's tile marker
	for x in [OsrsSim.W / 2 - 1, OsrsSim.W / 2, OsrsSim.W / 2 + 1]:
		var mk := MeshInstance3D.new()
		mk.mesh = _square_outline(TILE - 0.14, 0.09)
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.albedo_color = Color("#d02020")
		mk.material_override = mm
		add_child(mk)
		mk.position = w(Vector2i(x, 0)) + Vector3(0, 0.03, 0)
		_mid_marks[x] = mk


## A phantom: every mesh half see-through with a red glow laid over it.
func _ghost(n: Node) -> void:
	if n is GeometryInstance3D and not n is Label3D:
		var g := n as GeometryInstance3D
		g.transparency = 0.45
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(1.0, 0.12, 0.06, 0.75)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g.material_overlay = m
	for c in n.get_children():
		_ghost(c)


## A phantom's body (G53d): the mage in robes and a wizard's hat with a
## staff, the ranger in leathers with a bow.
func _phantom_unit(kind: String) -> BWUnit:
	var u := BWUnit.new()
	u.id = "phantom_" + kind
	u.name = kind.capitalize()
	u.team = "enemy"
	var mage := kind == "mage"
	u.weapon_model = "moon_staff" if mage else "longbow"
	u.weapon_class = "staff" if mage else "bow"
	u.cosmetics = { "hair_style": "buzzed", "hair_hex": "#c03020", "gender": "a", "top": "hoodie", "bottom": "sweatpants", "clothing_shade": "dark" }
	var gear: Dictionary = { "head": "wizard_hat", "chest": "silken_robe", "legs": "robe_bottoms" } if mage \
		else { "head": "feathered_cap", "chest": "leather_cuirass", "legs": "chaps" }
	for slot: String in gear:
		if BWEquipmentView.has_model(str(gear[slot])):
			u.equipment[slot] = { "base": str(gear[slot]), "slot": slot, "element": "" }
	for st in BWUnit.STATS:
		u.stats[st] = 9
	u.hp = u.max_hp()
	return u


## Which phantom shows a shot of `style`: the mage magic, the ranger arrows.
static func shooter(style: String) -> String:
	return { "magic": "mage", "ranged": "ranger" }.get(style, "")


func _player_unit(weapon: String) -> BWUnit:
	var u := BWUnit.new()
	u.id = "you"
	u.name = "You"
	u.team = "player"
	u.weapon_model = { "bow": "longbow", "staff": "moon_staff", "dagger": "jagged_dagger" }.get(weapon, "longbow")
	u.weapon_class = "daggers" if weapon == "dagger" else weapon
	var p := TourneyState.load_profile()
	u.cosmetics = { "hair_style": str(p.get("hair_style", "buzzed")), "hair_hex": str(p.get("hair_hex", "#e0b040")), "gender": "a",
		"top": str(p.get("top", "hoodie")), "bottom": str(p.get("bottom", "sweatpants")), "clothing_shade": str(p.get("shade", "mid")) }
	for s in BWUnit.STATS:
		u.stats[s] = 5
	u.hp = u.max_hp()
	return u


func _build_player() -> void:
	_player_root = Node3D.new()
	add_child(_player_root)
	_player_root.position = w(sim.me.tile)
	_dress(str(sim.me.weapon))
	_my_overhead = Label3D.new()
	_my_overhead.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_my_overhead.fixed_size = true
	_my_overhead.pixel_size = 0.0016
	_my_overhead.font_size = 30
	_my_overhead.outline_size = 8
	_my_overhead.no_depth_test = true
	_my_overhead.position = Vector3(0, 2.75, 0)
	_player_root.add_child(_my_overhead)


func _dress(weapon: String) -> void:
	if _player:
		_player.queue_free()
	_player = BWCharacter.create(_player_unit(weapon))
	_player.scale = Vector3.ONE * 0.8
	_player_root.add_child(_player)
	_player.pose("idle")
	_player_weapon = weapon


# ------------------------------------------------------------------ input

## Orders for the next tick (the HUD's buttons come through here too).
func queue(o: Dictionary) -> void:
	if not input_on or sim.over != "":
		return
	for k in o:
		_orders[k] = o[k]


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.physical_keycode:
			KEY_1: queue({ "pray": "magic" })
			KEY_2: queue({ "pray": "ranged" })
			KEY_3: queue({ "pray": "melee" })
			KEY_F1: _toggle_tune()
	elif ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = ev.pressed
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(7.0, _dist - 1.2)
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(30.0, _dist + 1.2)
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_click_at(ev.position)
	elif ev is InputEventMouseMotion and _drag:
		_yaw -= ev.relative.x * 0.008
		_pitch = clampf(_pitch + ev.relative.y * 0.006, deg_to_rad(22.0), deg_to_rad(80.0))


func _ray(screen: Vector2) -> Array:
	return [_cam.project_ray_origin(screen), _cam.project_ray_normal(screen)]


## The skull a click at `screen` means (G53d), or -1: a skull wins over the
## floor and the Warden when the click is on its square, on its body (a
## generous sphere), or within SKULL_PICK_PX of it on screen; the nearest
## to the click if several.
func skull_at_screen(screen: Vector2) -> int:
	var best := -1
	var bd := 1e9
	var r := _ray(screen)
	var tile := _tile_at(screen)
	for k: Dictionary in sim.skulls:
		var c: Vector3 = w(k.tile) + Vector3(0, 1.0, 0)
		var d := 1e9
		if tile == k.tile:
			d = 0.0
		var t := (c - (r[0] as Vector3)).dot(r[1] as Vector3)
		if t > 0.0 and ((r[0] as Vector3) + (r[1] as Vector3) * t).distance_to(c) < 0.95:
			d = minf(d, 1.0)
		if not _cam.is_position_behind(c):
			var px := _cam.unproject_position(c).distance_to(screen)
			var px_feet := _cam.unproject_position(w(k.tile)).distance_to(screen)
			if minf(px, px_feet) < SKULL_PICK_PX:
				d = minf(d, 2.0 + minf(px, px_feet) / SKULL_PICK_PX)
		if d < bd:
			bd = d
			best = int(k.id)
	return best


func _click_at(screen: Vector2) -> void:
	var sk := skull_at_screen(screen)
	if sk >= 0:
		queue({ "target": sk })
		_mark(w(sim.skull(sk).tile) + Vector3(0, 0.05, 0), Color("#ff2020"))
		return
	var r := _ray(screen)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	# the Warden: a sphere round its body
	var c := BOSS_POS + Vector3(0, 3.2, 0)
	var t := (c - o).dot(d)
	if t > 0.0 and (o + d * t).distance_to(c) < 3.2:
		queue({ "attack": true })
		_mark(_boss_root.global_position + Vector3(0, 0.1, 2.5), Color("#ff2020"))
		return
	var tile := _tile_at(screen)
	if tile != Vector2i(-99, -99) and sim.skull_at(tile) >= 0:
		queue({ "target": sim.skull_at(tile) })
		_mark(w(tile) + Vector3(0, 0.05, 0), Color("#ff2020"))
		return
	if tile != Vector2i(-99, -99):
		queue({ "move": tile, "attack": false })
		_mark(w(tile), Color("#ffff00"))


func _tile_at(screen: Vector2) -> Vector2i:
	var r := _ray(screen)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	if absf(d.y) < 0.0001:
		return Vector2i(-99, -99)
	var k := -o.y / d.y
	if k < 0.0:
		return Vector2i(-99, -99)
	var p := o + d * k
	var t := Vector2i(roundi(p.x / TILE + 7.0), roundi(p.z / TILE + 5.5))
	if not OsrsSim.inside(t):
		t = Vector2i(clampi(t.x, 0, OsrsSim.W - 1), clampi(t.y, 0, OsrsSim.H - 1))
	return t


func _mark(at: Vector3, col: Color) -> void:
	_click.position = at
	for b in _click.get_children():
		(b as MeshInstance3D).material_override = _mat("clickx", col, 1.0)
	_click.visible = true
	_click_t = 0.5


func _toggle_tune() -> void:
	if _tune:
		_tune.queue_free()
		_tune = null
		return
	_tune = OsrsTunePanel.new()
	add_child(_tune)


# ------------------------------------------------------------------- tick

func _process(delta: float) -> void:
	if sim.over == "":
		_acc += delta
		while _acc >= OsrsSim.TICK:
			_acc -= OsrsSim.TICK
			_step()
	_animate(delta)
	if _over_t >= 0.0:
		_over_t += delta
		if _over_t > 4.5 and _over_t - delta <= 4.5:
			over.emit(sim.result())


func _step() -> void:
	var o := _orders
	_orders = {}
	if bot:
		o = bot.think(sim)
	var prev_weapon := str(sim.me.weapon)
	for e: Dictionary in sim.step(o):
		_event(e)
	if str(sim.me.weapon) != prev_weapon:
		_dress(str(sim.me.weapon))
	_sync_marks()


func _event(e: Dictionary) -> void:
	match str(e.type):
		"proj":
			var p: Dictionary = e.proj
			var n := _proj_node(str(p.style))
			add_child(n)
			var who := shooter(str(p.style)) if str(p.get("src", "")) != "warden" else ""
			n.position = _src_hand(who)
			_projs[int(p.id)] = { "node": n, "proj": p, "from": n.position }
			var ph: Dictionary = _phantoms.get(who, {})
			if not ph.is_empty():
				var body: BWCharacter = ph.node
				body.anim_speed = 1.6
				body.pose("cast" if who == "mage" and body.has_clip("cast") else "strike")
				var lab: Label3D = ph.label
				lab.text = "✦" if p.style == "magic" else "➶"
				lab.modulate = Color("#5ab0ff") if p.style == "magic" else Color("#7cff5a")
				(ph.light as OmniLight3D).light_color = lab.modulate
				ph.t = 1.4
				ph.wind = false
				(ph.orb as MeshInstance3D).visible = false
				_dust(n.position, lab.modulate)
			else:
				_boss.anim_speed = 1.6
				_boss.pose("strike")
				_pose_t = 0.7
		"blocked":
			hud.splat(_player_root, 0, true, false, 1.1)
		"hurt":
			if float(e.dmg) > 0.0 or str(e.what) != "magic" and str(e.what) != "ranged":
				hud.splat(_player_root, int(e.dmg), false, false, 1.1)
			if str(e.what) in ["slam", "boulder", "fall", "skulls"]:
				_shake = 0.35
		"attack":
			_player.anim_speed = 1.6
			_player.pose("cast" if str(e.weapon) == "staff" and _player.has_clip("cast") else "strike")
			_pose_t = 0.5
			var arrow := _shot_node(str(e.weapon), bool(e.empowered))
			add_child(arrow)
			arrow.position = _player_root.position + Vector3(0, 1.3, 0)
			var sk := int(e.get("skull", -1))
			var to := BOSS_POS + Vector3(0, 3.5, 0)
			var hit_node: Node3D = _boss_root
			if sk >= 0:
				to = w(e.tile) + Vector3(0, 0.9, 0)
				hit_node = _skulls[sk].node if _skulls.has(sk) else null
			_shots.append({ "node": arrow, "from": arrow.position, "to": to, "t": 0.0, "dur": (int(e.land) - int(e.tick)) * OsrsSim.TICK,
				"dmg": int(e.dmg), "emp": bool(e.empowered), "hit": hit_node, "h": 1.5 if sk >= 0 else 3.6 })
			if bool(e.get("warded", false)) and not _overhead.has_meta("warded" + str(sim.boss.shield_n)):
				_overhead.set_meta("warded" + str(sim.boss.shield_n), true)
				hud.chat("Your %s can't get through its shield!" % ("spells" if str(e.weapon) == "staff" else "arrows"), Color("#b00000"))
			if bool(e.get("shielded", false)) and not _overhead.has_meta("shield"):
				_overhead.set_meta("shield", true)
				hud.chat("The Warden is shielded while its skulls are up!", Color("#7a0060"))
		"bolt":
			_bolt_fx(w(e.tile))
		"boulder":
			_dust(w(e.tile), Color("#7a7468"))
			_shake = maxf(_shake, 0.15)
		"slam_land":
			# G53d: the shock rolls out from the fist's side (both: from both
			# edges in), over every column but the spared one
			var side := str(e.side)
			for x in e.cols:
				var from_w := float(int(x))
				var from_e := float(OsrsSim.W - 1 - int(x))
				var d: float = from_w if side == "west" else (from_e if side == "east" else minf(from_w, from_e))
				for y in OsrsSim.H:
					var t := Vector2i(int(x), y)
					if _tiles.has(t) and not sim.gone.has(t):
						var mi: MeshInstance3D = _tiles[t]
						var tw := create_tween()
						tw.tween_interval(d * 0.035)
						tw.tween_property(mi, "position:y", 0.35, 0.08)
						tw.tween_property(mi, "position:y", -0.15, 0.25)
			for fs in (["west", "east"] if side == "both" else [side]):
				_dust(_fists[fs].position + Vector3(0, -1.0, 0), Color("#8a7a60"))
			_shake = maxf(_shake, 0.25)
			hud.chat("The Warden slams the floor!", Color("#b00000"))
		"slam":
			if int(e.get("i", 0)) == 0:
				hud.chat("The Warden raises its fists!", Color("#7a4a00"))
		"rip_warn":
			hud.chat("The far row cracks!", Color("#b00000"))
		"rip":
			for x in OsrsSim.W:
				var t := Vector2i(x, int(e.row))
				var mi: MeshInstance3D = _tiles[t]
				var tw := create_tween()
				tw.tween_property(mi, "position:y", -30.0, 1.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				tw.tween_callback(mi.hide)
				(_glow[t] as MeshInstance3D).visible = false
		"lightning":
			hud.chat("Red lightning gathers!", Color("#b00000"))
		"boulders":
			hud.chat("Boulders fall from above!", Color("#b00000"))
		"sigil":
			hud.chat("A Sun Sigil kindles nearby.", Color("#7a4a00"))
		"skulls":
			_say("Rise, and burn!")                          # G53c: read by the screen, not a banner
			_skull_burst()
			hud.pulse(Color("#c040ff"))
			_shake = maxf(_shake, 0.3)
		"skull_dead":
			_dust(w(e.tile) + Vector3(0, 0.6, 0), Color("#e8e0c8"))
			if _skulls.has(int(e.id)):
				var sn: Node3D = _skulls[int(e.id)].node
				var tw := create_tween()
				tw.tween_property(sn, "scale", Vector3.ONE * 0.05, 0.25)
				tw.tween_callback(sn.queue_free)
				_skulls.erase(int(e.id))
		"skulls_end":
			_overhead.remove_meta("shield")
			if int(e.left) == 0:
				hud.chat("You break every skull. The Warden's shield falls.", Color("#007000"))
			else:
				for t in e.tiles:
					_dust(w(t) + Vector3(0, 0.6, 0), Color("#ff40c0"))
					_bolt_fx(w(t))
				hud.chat("%d skulls burst!" % int(e.left), Color("#b00000"))
				hud.pulse(Color("#ff2010"))
				_shake = 0.5
		"shield":
			var mag := str(e.style) == "magic"
			_say("Your magic is nothing to me!" if mag else "Your arrows are nothing to me!")
			_dust(BOSS_POS + Vector3(0, 4.0, 1.0), Color("#4aa0ff") if mag else Color("#5aff4a"))
		"boost":
			hud.chat("You drink some of your damage potion. Your bow and staff hit harder.", Color("#000000"))
		"swap":
			if str(e.weapon) == "dagger":
				hud.chat("You wield the lightning dagger.", Color("#000000"))
		"sigil_fire":
			if e.took:
				hud.chat("The Sun Sigil blesses your next attacks!", Color("#7a4a00"))
				_dust(_player_root.position, Color("#ffd040"))
		"boss_anim":
			_boss_move = str(e.anim)
			_boss_move_t = 0.0
		"phase":
			hud.chat("The Warden grows desperate. (Phase %d)" % int(e.phase), Color("#b00000"))
		"eat":
			hud.chat("You eat the shark. It heals some health.", Color("#000000"))
		"drink":
			hud.chat("You drink some of your prayer potion.", Color("#000000"))
		"pray":
			if str(e.get("why", "")) == "out":
				hud.chat("You have run out of prayer points.", Color("#b00000"))
		"death":
			_player.anim_speed = 1.0
			_player.pose("fall")
			hud.chat("Oh dear, you are dead!", Color("#b00000"))
		"over":
			_over_t = 0.0
			hud.finish(sim.result())
			if str(e.how) == "win":
				_boss.pose("fall")
				hud.chat("The Warden falls! Time %s." % OsrsHud.clock(sim.tick * OsrsSim.TICK), Color("#007000"))


func _boss_hand() -> Vector3:
	return BOSS_POS + Vector3(0, 5.5, 1.6)


func _fist_rest(side: String) -> Vector3:
	return BOSS_POS + Vector3(-4.6 if side == "west" else 4.6, 1.0, 2.2)


## The slam whose pose is showing now: the next to land, once its warning starts.
func _posing() -> Dictionary:
	var best := {}
	for sl: Dictionary in sim.slams:
		if int(sl.t) <= int(sl.total) + 1 and (best.is_empty() or int(sl.t) < int(best.t)):
			best = sl
	return best


## The Warden says something over its head, OSRS style (yellow, ~3 s), and
## the chat box echoes it.
func _say(text: String) -> void:
	_overhead.text = text
	_overhead.modulate = Color("#ffff00")
	_overhead.set_meta("t", 3.0)
	hud.chat("Tumeken's Warden: %s" % text, Color("#000080"))


## The skulls' call (G53c): a big skull swells over the Warden and smaller
## ones scatter out of it.
func _skull_burst() -> void:
	var big := _skull_head()
	add_child(big)
	big.position = BOSS_POS + Vector3(0, 7.0, 1.0)
	big.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(big, "scale", Vector3.ONE * 3.2, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.9)
	tw.tween_property(big, "scale", Vector3.ONE * 0.05, 0.3)
	tw.tween_callback(big.queue_free)
	for i in 8:
		var h := _skull_head()
		add_child(h)
		h.position = big.position
		h.scale = Vector3.ONE * 0.9
		var dir := Vector3(cos(i * TAU / 8.0), 0.4 + 0.3 * sin(i * 1.7), sin(i * TAU / 8.0) * 0.6 + 0.5)
		var t2 := create_tween()
		t2.tween_property(h, "position", big.position + dir * 7.0, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t2.parallel().tween_property(h, "scale", Vector3.ONE * 0.1, 0.9).set_ease(Tween.EASE_IN)
		t2.tween_callback(h.queue_free)
	var l := OmniLight3D.new()
	l.light_color = Color("#c040ff")
	l.light_energy = 12.0
	l.omni_range = 18.0
	add_child(l)
	l.position = big.position
	var t3 := create_tween()
	t3.tween_property(l, "light_energy", 0.0, 1.2)
	t3.tween_callback(l.queue_free)


## A bone-white skull head (the skulls and their burst).
func _skull_head() -> Node3D:
	var head := Node3D.new()
	var bone := _mat("skull_bone", Color("#efe6cf"), 0.35)
	var dark := _mat("skull_eye", Color("#120408"))
	var s := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.42
	sm.height = 0.8
	s.mesh = sm
	s.material_override = bone
	head.add_child(s)
	_box(Vector3(0.46, 0.22, 0.4), Vector3(0, -0.34, 0.08), bone, head)
	for x in [-0.15, 0.15]:
		var e := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.11
		em.height = 0.22
		e.mesh = em
		e.material_override = _mat("skull_glint", Color("#ff40c0"), 5.0)
		head.add_child(e)
		e.position = Vector3(x, 0.02, 0.34)
	_box(Vector3(0.08, 0.1, 0.06), Vector3(0, -0.14, 0.4), dark, head)
	return head


## Where a shot leaves: a phantom's hand (west / east), or the Warden's.
func _src_hand(src: String) -> Vector3:
	if _phantoms.has(src):
		var ph: Dictionary = _phantoms[src]
		if src == "mage":                                  # the staff's tip, held high
			return (ph.node as Node3D).position + Vector3(-float(ph.side) * 1.5, 6.4, 0.8)
		return (ph.node as Node3D).position + Vector3(-float(ph.side) * 1.6, 3.9, 0.8)   # the bow at the chest
	return _boss_hand()


func _proj_node(style: String) -> Node3D:
	var n := Node3D.new()
	if style == "magic":
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.32
		sm.height = 0.64
		s.mesh = sm
		s.material_override = _mat("pmagic", Color("#4aa0ff"), 4.0)
		n.add_child(s)
		var l := OmniLight3D.new()
		l.light_color = Color("#4aa0ff")
		l.light_energy = 2.0
		l.omni_range = 4.0
		n.add_child(l)
	elif style == "ranged":
		_box(Vector3(0.08, 0.08, 1.3), Vector3.ZERO, _mat("parrow", Color("#e8f0e0"), 1.5), n)
		_box(Vector3(0.22, 0.22, 0.3), Vector3(0, 0, 0.7), _mat("ptip", Color("#7cff5a"), 3.0), n)
	else:
		_box(Vector3(0.6, 0.6, 0.6), Vector3.ZERO, _mat("pmelee", Color("#ff4030"), 3.0, 0.7), n)
	return n


func _shot_node(weapon: String, emp: bool) -> Node3D:
	var n := Node3D.new()
	var col := Color("#ffd040") if emp else (Color("#c8ff9a") if weapon == "bow" else Color("#c07aff"))
	if weapon == "dagger":
		var zap := _mat("szap", Color("#bfe8ff"), 6.0)
		for i in 3:
			var seg := _box(Vector3(0.05, 0.05, 0.35), Vector3(0.08 * (1 - i % 2 * 2), 0, -0.3 + i * 0.3), zap, n)
			seg.rotation.y = 0.5 * (1 - i % 2 * 2)
		return n
	if weapon == "bow":
		_box(Vector3(0.05, 0.05, 0.9), Vector3.ZERO, _mat("sarrow" + col.to_html(), col, 2.0), n)
	else:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.2
		sm.height = 0.4
		s.mesh = sm
		s.material_override = _mat("sorb" + col.to_html(), col, 4.0)
		n.add_child(s)
	return n


func _bolt_fx(at: Vector3) -> void:
	var n := Node3D.new()
	add_child(n)
	n.position = at
	var mat := _mat("bolt", Color("#ff3020"), 6.0)
	var y := 9.0
	var x := 0.0
	while y > 0.2:
		var ny := maxf(0.0, y - randf_range(1.2, 2.2))
		var nx := randf_range(-0.5, 0.5) if ny > 0.0 else 0.0
		var a := Vector3(x, y, 0)
		var b := Vector3(nx, ny, 0)
		var seg := _box(Vector3(0.12, a.distance_to(b), 0.12), (a + b) * 0.5, mat, n)
		seg.rotation.z = atan2(b.x - a.x, a.y - b.y) * -1.0
		y = ny
		x = nx
	var l := OmniLight3D.new()
	l.light_color = Color("#ff4030")
	l.light_energy = 6.0
	l.omni_range = 5.0
	l.position = Vector3(0, 1, 0)
	n.add_child(l)
	n.rotation.y = randf() * TAU
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_property(l, "light_energy", 0.0, 0.25)
	tw.tween_callback(n.queue_free)


func _dust(at: Vector3, col: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 18
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.25
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 3
	m.material = _mat("dust" + col.to_html(), col, 0.5)
	p.mesh = m
	add_child(p)
	p.position = at + Vector3(0, 0.2, 0)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


## Telegraph nodes follow the sim's lists: shadows, sigils, rocks.
func _sync_marks() -> void:
	var want := {}
	for b in sim.bolts:
		want["bolt:%s" % str(b.tile)] = b
	for f in sim.falls:
		want["fall:%s" % str(f.tile)] = f
	for s in sim.sigils:
		want["sigil:%s" % str(s.tile)] = s
	for k in _marks.keys():
		if not want.has(k):
			(_marks[k].node as Node3D).queue_free()
			_marks.erase(k)
	for k in want:
		if not _marks.has(k):
			var d: Dictionary = want[k]
			var kind := str(k).split(":")[0]
			var n := Node3D.new()
			add_child(n)
			n.position = w(d.tile) + Vector3(0, 0.04, 0)
			var disc := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = TILE * 0.48
			cm.bottom_radius = TILE * 0.48
			cm.height = 0.02
			disc.mesh = cm
			match kind:
				"bolt": disc.material_override = _mat("scorch", Color("#1a0806"), 0.0, 0.55)
				"fall": disc.material_override = _mat("shadow_fall", Color("#050303"), 0.0, 0.75)
				_: disc.material_override = _mat("sigil_core", Color("#ffcf40"), 1.5, 0.25)
			n.add_child(disc)
			if kind == "sigil":
				var ring := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = TILE * 0.36
				tm.outer_radius = TILE * 0.46
				ring.mesh = tm
				ring.material_override = _mat("sigil_ring", Color("#ffcf40"), 3.0)
				ring.scale.y = 0.15
				disc.add_child(ring)
				for r8 in 8:
					var ray := _box(Vector3(0.07, 0.03, TILE * 0.3), Vector3.ZERO, _mat("sigil_ray", Color("#ffe080"), 3.0), disc)
					ray.rotation.y = r8 * TAU / 8.0
					ray.position = Vector3(sin(ray.rotation.y), 0.02, cos(ray.rotation.y)) * TILE * 0.17
				var sl := OmniLight3D.new()
				sl.light_color = Color("#ffcf40")
				sl.light_energy = 1.5
				sl.omni_range = 2.5
				sl.position.y = 0.5
				n.add_child(sl)
			if kind == "fall":
				var r := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.62
				sm.height = 1.1
				sm.radial_segments = 7
				sm.rings = 4
				r.mesh = sm
				r.material_override = _mat("boulder", Color("#6d665c"))
				n.add_child(r)
				r.name = "Rock"
				r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # G53b: only the landing square is marked
			if kind == "bolt":
				var zz := Node3D.new()
				zz.name = "Zig"
				n.add_child(zz)
				var zm := _mat("zig", Color("#ff4a30"), 6.0)
				var pts := [Vector3(0.05, 2.2, 0), Vector3(-0.3, 1.5, 0), Vector3(0.25, 1.05, 0), Vector3(-0.14, 0.4, 0), Vector3(0.08, 0.0, 0)]
				for i in pts.size() - 1:
					var a: Vector3 = pts[i]
					var b: Vector3 = pts[i + 1]
					var seg := _box(Vector3(0.09, a.distance_to(b), 0.09), (a + b) * 0.5, zm, zz)
					seg.rotation.z = -atan2(b.x - a.x, a.y - b.y)
				zz.rotation.y = randf() * TAU
				var rim := MeshInstance3D.new()
				rim.mesh = _square_outline(TILE - 0.12, 0.08)
				var rm := _mat("bolt_rim", Color("#ff3020"), 3.0, 0.95).duplicate() as StandardMaterial3D
				rm.no_depth_test = true
				rm.render_priority = 2
				rim.material_override = rm
				n.add_child(rim)
			_marks[k] = { "node": n, "disc": disc, "data": d, "kind": kind }
		else:
			_marks[k].data = want[k]
	# skulls
	for k: Dictionary in sim.skulls:
		if not _skulls.has(int(k.id)):
			_skulls[int(k.id)] = _skull_node(k)
	# rocks that landed
	for t in sim.rocks:
		if not _rocks.has(t):
			var r := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.68
			sm.height = 1.0
			sm.radial_segments = 7
			sm.rings = 4
			r.mesh = sm
			r.material_override = _mat("boulder", Color("#6d665c"))
			add_child(r)
			r.position = w(t) + Vector3(0, 0.4, 0)
			r.rotation.y = randf() * TAU
			_rocks[t] = r
	for t in _rocks.keys():
		if not sim.rocks.has(t):
			(_rocks[t] as Node3D).queue_free()
			_rocks.erase(t)


## A skull (G53, G53b): a bone-white head floating over its square. As it
## charges it swells, shakes, glows hotter and its ring grows from pink to
## white-hot red; a yellow mark over the one you're after.
func _skull_node(k: Dictionary) -> Dictionary:
	var n := Node3D.new()
	add_child(n)
	n.position = w(k.tile)
	var head := Node3D.new()
	head.name = "Head"
	n.add_child(head)
	var bone := _mat("skull_bone", Color("#efe6cf"), 0.35)
	var dark := _mat("skull_eye", Color("#120408"))
	var s := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.42
	sm.height = 0.8
	s.mesh = sm
	s.material_override = bone
	head.add_child(s)
	s.position.y = 1.0
	_box(Vector3(0.46, 0.22, 0.4), Vector3(0, 0.66, 0.08), bone, head)
	for x in [-0.15, 0.15]:
		var e := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.11
		em.height = 0.22
		e.mesh = em
		e.material_override = dark
		head.add_child(e)
		e.position = Vector3(x, 1.02, 0.33)
		var glow := MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = 0.045
		gm.height = 0.09
		glow.mesh = gm
		glow.material_override = _mat("skull_glint", Color("#ff40c0"), 5.0)
		head.add_child(glow)
		glow.position = Vector3(x, 1.02, 0.4)
	_box(Vector3(0.08, 0.1, 0.06), Vector3(0, 0.86, 0.4), dark, head)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = TILE * 0.36
	tm.outer_radius = TILE * 0.47
	ring.mesh = tm
	ring.scale.y = 0.2
	ring.position.y = 0.05
	ring.material_override = _mat("skull_ring", Color("#ff40c0"), 2.0).duplicate()
	n.add_child(ring)
	var l := OmniLight3D.new()
	l.light_color = Color("#ff40c0")
	l.light_energy = 1.6
	l.omni_range = 2.6
	l.position.y = 1.0
	n.add_child(l)
	var pips := Label3D.new()
	pips.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pips.fixed_size = true
	pips.pixel_size = 0.0016
	pips.font_size = 26
	pips.outline_size = 8
	pips.no_depth_test = true
	pips.position.y = 1.85
	n.add_child(pips)
	n.scale = Vector3.ONE * 0.1
	create_tween().tween_property(n, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return { "node": n, "pips": pips, "ring": ring, "head": head, "bob": randf() * TAU, "light": l }


# ------------------------------------------------------------------ frame

func _animate(delta: float) -> void:
	var f := clampf(_acc / OsrsSim.TICK, 0.0, 1.0)
	# you glide along the squares you crossed this tick
	var trail: Array = sim.me.trail
	var pos := w(sim.me.tile)
	var heading := Vector3.ZERO
	if trail.size() >= 2:
		var segs := trail.size() - 1
		var k := minf(f * segs, segs - 0.0001)
		var i := int(floor(k))
		var a := w(trail[i])
		var b := w(trail[i + 1])
		pos = a.lerp(b, k - i)
		heading = b - a
	_player_root.position = pos
	var moving := trail.size() >= 2 and f < 0.999 or not (sim.me.path as Array).is_empty()
	var face := heading
	if face.length() < 0.01 and sim.me.attack:
		face = BOSS_POS - pos
	if face.length() > 0.01:
		var yaw := atan2(face.x, face.z)
		_player_root.rotation.y = lerp_angle(_player_root.rotation.y, yaw, minf(1.0, delta * 14.0))
	_pose_t -= delta
	if sim.me.alive and _pose_t <= 0.0:
		var want := "run" if moving and sim.me.run and _player.has_clip("run") else ("walk" if moving else "idle")
		if _player.pose_name() != want:
			_player.anim_speed = 1.0
			_player.pose(want)
	_my_overhead.text = { "magic": "✦", "ranged": "➶", "melee": "⚔" }.get(str(sim.me.prayer), "")
	_my_overhead.modulate = { "magic": Color("#5ab0ff"), "ranged": Color("#7cff5a"), "melee": Color("#ff6a5a") }.get(str(sim.me.prayer), Color.WHITE)
	# the Warden's overhead fades; its big moves play
	if _overhead.has_meta("t"):
		var t := float(_overhead.get_meta("t")) - delta
		_overhead.set_meta("t", t)
		_overhead.modulate.a = clampf(t / 0.4, 0.0, 1.0)
		_overhead.outline_modulate = Color(0, 0, 0, _overhead.modulate.a)
	_boss_root.rotation.y = lerp_angle(_boss_root.rotation.y, atan2(pos.x - BOSS_POS.x, pos.z - BOSS_POS.z), minf(1.0, delta * 3.0))
	if _boss_move != "":
		_boss_move_t += delta
		if _boss_move_t >= MmoMoves.length(_boss_move) or sim.over == "win":
			_boss_move = ""
			_boss.poser.override = {}
			_boss.poser.override_w = 1.0
		else:
			_boss.poser.override = MmoMoves.sample(_boss_move, _boss_move_t)
			_boss.poser.override_w = MmoMoves.weight(_boss_move, _boss_move_t)
	elif _pose_t <= 0.0 and _boss.pose_name() != "idle" and sim.over != "win":
		_boss.anim_speed = 1.0
		_boss.pose("idle")
	# projectiles fly from the hand to you, landing on their tick: launch to land
	# is the sim's flight (3 s) from any distance, so a near one crawls (G45)
	var now := float(sim.tick) + f
	for id in _projs.keys():
		var p: Dictionary = _projs[id].proj
		var n: Node3D = _projs[id].node
		var k := clampf((now - float(p.launch)) / maxf(1.0, float(p.land) - float(p.launch)), 0.0, 1.0)
		var to := _player_root.position + Vector3(0, 1.2, 0)
		var at := (_projs[id].from as Vector3).lerp(to, k) + Vector3(0, sin(k * PI) * 1.2, 0)
		_fly(n, at)
		if float(sim.tick) >= float(p.land):
			n.queue_free()
			_projs.erase(id)
	for s in _shots.duplicate():
		s.t = float(s.t) + delta
		var n: Node3D = s.node
		var k := clampf(float(s.t) / maxf(0.1, float(s.dur)), 0.0, 1.0)
		var to: Vector3 = s.to
		var at: Vector3 = (s.from as Vector3).lerp(to, k) + Vector3(0, sin(k * PI) * 0.8, 0)
		_fly(n, at)
		if k >= 1.0:
			if is_instance_valid(s.hit):
				hud.splat(s.hit, int(s.dmg), false, bool(s.emp), float(s.h))
			n.queue_free()
			_shots.erase(s)
	# the phantom whose shot comes next winds up the tick before it looses
	# (G53b/d): the mage gathers an orb at his staff's tip, the ranger draws
	var due := {}
	if sim.over == "" and int(sim.boss.auto_cd) <= 1 and OsrsSim.boss_dist(sim.me.tile) > 1 and str(sim.boss.next_style) != "":
		due[shooter(str(sim.boss.next_style))] = true
	if str(sim.boss.twin) != "":
		due[shooter(str(sim.boss.twin))] = true
	for side in _phantoms:
		var ph: Dictionary = _phantoms[side]
		var winding: bool = due.has(side)
		var orb := ph.orb as MeshInstance3D
		if winding and not bool(ph.wind):
			ph.wind = true
			var body: BWCharacter = ph.node
			body.anim_speed = 0.7
			body.pose("windup" if body.has_clip("windup") else ("cast" if body.has_clip("cast") else "strike"))
		if side == "ranger":
			(orb.material_override as StandardMaterial3D).albedo_color = Color("#7cff5a")
		orb.visible = winding
		if winding:
			orb.position = _src_hand(side)
			if side == "ranger":
				orb.scale = Vector3(0.25, 0.25, 0.25)
				continue
			orb.scale = Vector3.ONE * (0.3 + 1.0 * f) * randf_range(0.92, 1.08)
	# the phantoms' overheads fade after they loose
	for side in _phantoms:
		var ph: Dictionary = _phantoms[side]
		ph.t = maxf(0.0, float(ph.t) - delta)
		var lab: Label3D = ph.label
		var pb := ph.node as Node3D
		pb.rotation.y = lerp_angle(pb.rotation.y, atan2(pos.x - pb.position.x, pos.z - pb.position.z), minf(1.0, delta * 4.0))
		lab.modulate.a = clampf(float(ph.t) / 0.4, 0.0, 1.0)
		lab.outline_modulate = Color(0, 0, 0, lab.modulate.a)
		(ph.light as OmniLight3D).light_energy = 4.0 + 6.0 * clampf(float(ph.t) - 0.8, 0.0, 1.0)
		var body: BWCharacter = ph.node
		if float(ph.t) <= 0.6 and not bool(ph.wind) and body.pose_name() != "idle":
			body.anim_speed = 1.0
			body.pose("idle")
	# skulls charge: swell, shake, glow, a growing ring
	var left := 1.0
	if not sim.skull_phase.is_empty():
		left = clampf((float(sim.skull_phase.t) - f) / maxf(1.0, float(sim.skull_phase.total)), 0.0, 1.0)
	for id in _skulls:
		var sd: Dictionary = _skulls[id]
		var k := sim.skull(int(id))
		if k.is_empty():
			continue
		var ch := 1.0 - left                                   # 0 just risen .. 1 bursting
		var head := sd.head as Node3D
		var shake := ch * ch * 0.14
		head.position = Vector3(randf_range(-shake, shake), 0.12 * sin(Time.get_ticks_msec() / 300.0 + float(sd.bob)) + randf_range(-shake, shake) * 0.5, randf_range(-shake, shake))
		head.scale = Vector3.ONE * (1.0 + 0.45 * ch * ch)
		head.rotation.y = atan2(_cam.global_position.x - (sd.node as Node3D).position.x, _cam.global_position.z - (sd.node as Node3D).position.z)
		(sd.pips as Label3D).text = "▼" if int(k.id) == int(sim.me.target) else ""
		(sd.pips as Label3D).modulate = Color("#ffff40")
		var pulse := 0.5 + 0.5 * absf(sin(Time.get_ticks_msec() / (50.0 + 250.0 * left)))
		var rc := Color("#ff40c0").lerp(Color("#ff1010"), ch).lerp(Color("#fff0e0"), ch * ch * pulse * 0.6)
		var rm := (sd.ring as MeshInstance3D).material_override as StandardMaterial3D
		rm.albedo_color = rc
		rm.emission = rc
		rm.emission_energy_multiplier = 2.0 + 6.0 * ch * pulse
		var ring := sd.ring as MeshInstance3D
		ring.scale = Vector3(0.55 + 0.75 * ch, 0.2, 0.55 + 0.75 * ch)
		var lt := sd.light as OmniLight3D
		lt.light_color = rc
		lt.light_energy = 1.6 + 7.0 * ch * pulse
		lt.omni_range = 2.6 + 1.6 * ch
	# telegraphs grow
	for k in _marks:
		var m: Dictionary = _marks[k]
		var d: Dictionary = m.data
		var prog := 1.0 - (float(d.t) - f) / maxf(1.0, float(d.total))
		prog = clampf(prog, 0.0, 1.0)
		var disc: MeshInstance3D = m.disc
		match str(m.kind):
			"bolt":
				disc.scale = Vector3.ONE * lerpf(0.3, 1.0, prog)
				var zig := (m.node as Node3D).get_node_or_null("Zig") as Node3D
				if zig:
					zig.scale = Vector3.ONE * lerpf(0.7, 1.45, prog) * randf_range(0.92, 1.08)
					zig.rotate_y(delta * 1.5)
			"fall":
				disc.scale = Vector3.ONE * lerpf(0.35, 1.0, prog)
				var rock := (m.node as Node3D).get_node_or_null("Rock") as Node3D
				if rock:
					rock.position.y = lerpf(16.0, 0.4, prog * prog)
			_:
				disc.scale = Vector3.ONE * (0.75 + 0.2 * sin(Time.get_ticks_msec() / 1000.0 * (4.0 + prog * 10.0)))
	# the Warden's shield: a blue (magic) or green (bowfire) bubble and its mark
	var sh := str(sim.boss.shield)
	_shield.visible = sh != ""
	_shield_mark.text = ("✦" if sh == "magic" else "➶") if sh != "" else ""
	if sh != "":
		var sc := Color("#4aa0ff") if sh == "magic" else Color("#5aff4a")
		(_shield.material_override as StandardMaterial3D).albedo_color = Color(sc, 0.05 + 0.025 * sin(Time.get_ticks_msec() / 200.0))
		_shield_mark.modulate = sc
	# the slam (G53d): no floor glow. The pose tells it: the fist it raises
	# (or both) climbs, glows and comes down on the hit; it leans that way;
	# the matching square of the three-square marker lights gold
	var ps := _posing()
	var pose := str(ps.get("side", ""))
	var pk := 0.0
	if not ps.is_empty():
		pk = clampf(1.0 - (float(ps.t) - f) / float(ps.total), 0.0, 1.0)     # 0 the pose starts .. 1 it lands
	for fs in _fists:
		var fist: Node3D = _fists[fs]
		var up: bool = pose == fs or pose == "both"
		var want := _fist_rest(fs)
		if up:
			want += Vector3(0, 2.0 + 7.0 * sin(minf(pk, 0.85) / 0.85 * PI * 0.5), 0.6)
			if pk > 0.85:
				want.y = lerpf(want.y, _fist_rest(fs).y - 0.4, (pk - 0.85) / 0.15)
		fist.position = fist.position.lerp(want, minf(1.0, delta * (30.0 if pk > 0.85 else 8.0)))
		var gl := fist.get_node("Glow") as OmniLight3D
		gl.light_energy = lerpf(gl.light_energy, 9.0 * pk if up else 0.0, minf(1.0, delta * 10.0))
	var lean := { "west": 0.22, "east": -0.22 }.get(pose, 0.0) as float
	_boss.rotation.z = lerpf(_boss.rotation.z, lean, minf(1.0, delta * 6.0))
	for x in _mid_marks:
		var on: bool = not ps.is_empty() and int(ps.safe) == int(x)
		(_mid_marks[x].material_override as StandardMaterial3D).albedo_color = Color("#ffd040") if on else Color("#d02020")
		(_mid_marks[x] as MeshInstance3D).visible = not sim.gone.has(Vector2i(int(x), 0))
	# the tear-out glow
	var lit := {}
	if not sim.rip.is_empty():
		var a := 0.35 + 0.35 * absf(sin(Time.get_ticks_msec() / 90.0))
		for x in OsrsSim.W:
			lit[Vector2i(x, int(sim.rip.row))] = [Color("#ff2010"), a]
	for t in _glow:
		var g: MeshInstance3D = _glow[t]
		if lit.has(t) and not sim.gone.has(t):
			g.visible = true
			g.material_override = _mat("glow" + (lit[t][0] as Color).to_html(), lit[t][0], 2.0, snappedf(float(lit[t][1]), 0.05))
		else:
			g.visible = false
	_true_tile.position = w(sim.me.tile) + Vector3(0, 0.025, 0)
	_true_tile.visible = sim.me.alive
	# the hover square
	var mp := get_viewport().get_mouse_position()
	var ht := _tile_at(mp)
	var hs := skull_at_screen(mp) if input_on else -1
	if hs >= 0:
		ht = sim.skull(hs).tile                         # the skull a click would hit (G53d)
	_hover.visible = ht != Vector2i(-99, -99) and not sim.gone.has(ht) and input_on
	_hover.material_override = _mat("hover_skull", Color("#ff3030"), 1.5, 0.9) if hs >= 0 else _mat("hover", Color("#ffff40"), 1.0, 0.6)
	if _hover.visible:
		_hover.position = w(ht) + Vector3(0, 0.02, 0)
	_click_t -= delta
	_click.visible = _click_t > 0.0
	_click.scale = Vector3.ONE * (0.6 + maxf(_click_t, 0.0))
	# the camera: free yaw / pitch, always centred on you
	if input_on:
		var turn := float(Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A))
		var tilt := float(Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S))
		_yaw += turn * delta * 1.8
		_pitch = clampf(_pitch + tilt * delta * 1.0, deg_to_rad(22.0), deg_to_rad(80.0))
	_place_camera(delta)
	hud.refresh(sim)


## Move a flying thing to `at`, pointing along its flight.
func _fly(n: Node3D, at: Vector3) -> void:
	var d := at - n.position
	if d.length() > 0.001 and absf(d.normalized().y) < 0.999:
		n.look_at_from_position(at, at + d, Vector3.UP)
	else:
		n.position = at


func _place_camera(delta: float) -> void:
	# centred on you, aimed a few metres ahead so what you face (the Warden) stays in frame
	var c := _player_root.position + Vector3(0, 1.0, 0) - Vector3(sin(_yaw), 0, cos(_yaw)) * 4.5
	var off := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	_shake = maxf(0.0, _shake - delta)
	var jit := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.4
	_cam.position = c + off + jit
	_cam.look_at(c, Vector3.UP)
