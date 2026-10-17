class_name FpsWorld
extends Node3D
## The FPS prototype: you against a bot on a Gauntlet kit map, first to
## FpsTune.kills_to_win. `map_id` picks it: "rooftop" (the apartment roofs,
## G20) or "dust_mid" (the Dust2-mid hallway, G29). Builds the map from the
## kit (its colliders are the level), seats the player at side A and the bot
## at side B, and owns the shared effects (bullets, traces, flashes, impacts,
## slingshot balls) and the score. Run it alone:
##   godot --path . res://scenes/fps_proto.tscn
## or inside the tournament as FpsModule.
## Every life starts on the radial loadout (G43, FpsLoadoutMenu): pick a
## primary; the sidearm is rolled (the 92FS, half the time the Desert Eagle).
## You can't be hurt while you pick. "campus" (G43) is paintball: shots
## leave paint, and the bushes (the map's hide volumes) can be walked
## through and hide whoever is inside from the other side's eyes.

signal match_over(human_won: bool, summary: String)

var map_id := "rooftop"
var map: GKAsset
var player: FpsPlayer
var bot: FpsBot
var hud: FpsHud
var score := Vector2i.ZERO
var _over := false
var _balls: Array[Dictionary] = []
var _bullets: Array[Dictionary] = []
var _tune: FpsTunePanel
var _menu: FpsLoadoutMenu
var _last_pick := ""
var _rng := RandomNumberGenerator.new()
## The match seed (G51): spawn pockets and loadout rolls follow it; < 0 random.
var match_seed := -1
## Tools: skip the radial and take the first primary at once.
static var ask_loadout := true
var paintball := false
var hide_volumes: Array = []                ## [{ center, half, basis }] from the map
const PAINT := { "player": Color("#2a7ad8"), "bot": Color("#e0308a") }
var nav: FpsNav                             ## G62: the map's baked NavigationMesh (the bot's paths)
var audio: FpsAudio                         ## G62: the duel's sounds
## Tools: skip the bake (the bot falls back to its straight-line walk).
static var bake_nav := true
## Tools: the G62 map polish pieces (FpsMapPolish); off for "before" frames.
static var polish := true


func _ready() -> void:
	if match_seed >= 0:
		_rng.seed = match_seed
	else:
		_rng.randomize()
	map = GKRegistry.build(map_id)
	FpsMuzzleFlash.warm()                       # build the flash textures now, not on the first shot
	paintball = map_id == "campus"
	hide_volumes = map.meta.get("hide_volumes", [])
	var stage := GKStage.outdoor(map.lights)
	add_child(stage)
	var sun := stage.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.light_cull_mask = 1                 # the world; the gun has its own light (FpsHud)
	var level := map.instantiate(true)
	add_child(level)
	if polish:
		FpsMapPolish.apply(map_id, level)       # G62: one play fix per map, before the bake
	nav = FpsNav.new()
	add_child(nav)
	if bake_nav:
		nav.bake(map, level)
	audio = FpsAudio.new()
	audio.world = self
	add_child(audio)
	player = FpsPlayer.new()
	player.world = self
	if paintball:
		player.run_key = "campus_speed"         # G51: the floaty max speed is the campus's alone
	add_child(player)
	player.global_transform = _spawn("a")
	player.died.connect(_on_player_died)
	bot = FpsBot.new()
	bot.world = self
	bot.target = player
	bot.roof = _bot_area()
	add_child(bot)
	bot.global_transform = _spawn("b")
	_bot_loadout()
	bot.respawn(bot.global_transform)
	bot.died.connect(_on_bot_died)
	hud = FpsHud.new()
	hud.player = player
	add_child(hud)
	player.cam.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.note("First to %d. The bot is %s." % [int(FpsTune.value("kills_to_win")), { "rooftop": "on the far roof", "dust_mid": "at the tower end" }.get(map_id, "at the far end")])
	open_loadout()


## The radial before a life: the player can't move, shoot or be hurt until
## they pick (or the timer keeps their last pick).
func open_loadout() -> void:
	var side := FpsWeapons.roll_sidearm(_rng)
	var prim := FpsWeapons.primaries()
	if prim.is_empty():
		prim = ["sniper"]
	if not ask_loadout:
		player.set_loadout(str(prim[0]), side)
		return
	player.input_on = false
	player.shielded = true
	_menu = FpsLoadoutMenu.new()
	_menu.options = prim + ["random"]
	_menu.sidearm = side
	_menu.last = _last_pick
	_menu.picked.connect(func(id: String) -> void:
		_last_pick = id
		_menu = null
		player.set_loadout(id, side)
		player.input_on = _tune == null
		player.shielded = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		hud.note("%s  +  %s" % [FpsWeapons.SPECS[id].name, FpsWeapons.SPECS[side].name]))
	add_child(_menu)


## The bot's life: a random primary.
func _bot_loadout() -> void:
	var prim := FpsWeapons.primaries()
	bot.set_weapon(str(prim[_rng.randi() % prim.size()]) if not prim.is_empty() else "sniper")


## Where the bot may walk: roof B, or the half of the play area its spawns are in.
func _bot_area() -> Array:
	var out: Array = []
	if map.meta.has("roofs"):
		for r in (map.meta.roofs.b as Array):
			out.append(Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1])))
		return out
	var pa: Array = map.meta.play_area                 # [x0, z0, x1, z1]
	var r := Rect2(float(pa[0]), float(pa[1]), float(pa[2]) - float(pa[0]), float(pa[3]) - float(pa[1]))
	var b := map.marker("spawn_b0").origin
	var a := map.marker("spawn_a0").origin
	if absf(b.z - a.z) >= absf(b.x - a.x):               # the spawns face along z: split across z
		var zm := r.get_center().y
		return [Rect2(r.position.x, r.position.y, r.size.x, r.size.y * 0.5) if b.z < zm else Rect2(r.position.x, zm, r.size.x, r.size.y * 0.5)]
	var xm := r.get_center().x
	return [Rect2(r.position.x, r.position.y, r.size.x * 0.5, r.size.y) if b.x < xm else Rect2(xm, r.position.y, r.size.x * 0.5, r.size.y)]


## Can a body walk straight from `a` to `b` (G51: the bot has no pathfinding,
## so it only picks spots it can reach in a line)? A capsule swept along the
## floor at knee height, against the level.
func walk_clear(a: Vector3, b: Vector3, radius := 0.4) -> bool:
	var sh := CapsuleShape3D.new()
	sh.radius = radius
	sh.height = 1.2
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.collision_mask = 1
	var from := a + Vector3(0, 1.0, 0)
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = Vector3(b.x - a.x, 0, b.z - a.z)
	var r := get_world_3d().direct_space_state.cast_motion(q)
	return r.size() == 2 and r[0] >= 0.999


## Is `p` inside a bush (a hide volume)?
func in_bush(p: Vector3) -> bool:
	for h: Dictionary in hide_volumes:
		var l: Vector3 = (h.basis as Basis).transposed() * (p - (h.center as Vector3))
		var hf: Vector3 = h.half
		if absf(l.x) <= hf.x and absf(l.y) <= hf.y and absf(l.z) <= hf.z:
			return true
	return false


## How many metres of bush the segment runs through. Exact: each hide
## volume near the segment clips it (a slab test in the box's frame), and the
## overlapping pieces are merged. G65: it was sampled every 0.5 m against
## every bush, which on Extraction's 110 bushes and guards looking 150 m cost
## ~40k box tests a guard a tick (the frame rate fell to 3-5).
func bush_between(a: Vector3, b: Vector3) -> float:
	if hide_volumes.is_empty():
		return 0.0
	var seg := b - a
	var ln := seg.length()
	if ln < 0.001:
		return 0.0
	var spans: Array[Vector2] = []
	for h: Dictionary in hide_volumes:
		var c: Vector3 = h.center
		var hf: Vector3 = h.half
		if Geometry3D.get_closest_point_to_segment(c, a, b).distance_squared_to(c) > hf.length_squared():
			continue
		var bt := (h.basis as Basis).transposed()
		var la := bt * (a - c)
		var ld := bt * seg
		var t0 := 0.0
		var t1 := 1.0
		for k in 3:
			if absf(ld[k]) < 1e-6:
				if absf(la[k]) > hf[k]:
					t1 = -1.0
					break
				continue
			var u := (-hf[k] - la[k]) / ld[k]
			var v := (hf[k] - la[k]) / ld[k]
			t0 = maxf(t0, minf(u, v))
			t1 = minf(t1, maxf(u, v))
			if t1 <= t0:
				break
		if t1 > t0:
			spans.append(Vector2(t0, t1))
	if spans.is_empty():
		return 0.0
	spans.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	var total := 0.0
	var cur := spans[0]
	for i in range(1, spans.size()):
		var s := spans[i]
		if s.x <= cur.y:
			cur.y = maxf(cur.y, s.y)
		else:
			total += cur.y - cur.x
			cur = s
	total += cur.y - cur.x
	return total * ln


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## A life's start: one of the side's spawn markers, from the seeded rng
## (G51: the Dust hallway has two tucked pockets a side, so which one is a
## coin flip the other player can't read).
func _spawn(side: String) -> Transform3D:
	var n := 0
	while map.markers.has("spawn_%s%d" % [side, n]):
		n += 1
	var k := _rng.randi() % maxi(n, 1)
	var t := map.marker("spawn_%s%d" % [side, k])
	return Transform3D(t.basis, t.origin + Vector3(0, 0.2, 0))


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif ev.physical_keycode == KEY_F1 and _menu == null:
			_toggle_tune()
	elif ev is InputEventMouseButton and ev.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and _tune == null and _menu == null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _toggle_tune() -> void:
	if _tune:
		_tune.queue_free()
		_tune = null
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		player.input_on = true
		return
	_tune = FpsTunePanel.new()
	add_child(_tune)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.input_on = false


# ----------------------------------------------------------------- shots

## A ray against the level (mask 1), bodies (4 you, 8 the bot) unless told.
func trace(from: Vector3, to: Vector3, exclude: Array = [], mask := 1 | 4 | 8) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	return get_world_3d().direct_space_state.intersect_ray(q)


func on_hit(_shooter: Node, hit: Dictionary, damage: float, head_mult: float) -> void:
	if hit.collider == bot and bot.alive:
		var head := int(hit.shape) == 1
		bot.hurt(damage * (head_mult if head else 1.0), head)
		hud.hit_marker()
		puff(hit.position, Color(0.75, 0.2, 0.15))
		if head:
			hud.note("Headshot")
		if audio:
			audio.ui("headshot" if head else "hitmark")
			if not bot.alive:
				audio.ui("kill", { "delay": 0.08 })
		BWSfx.play("hit_flesh", hit.position, { "gain_db": -2.0 })
	elif hit.collider == player and player.alive:
		var head: bool = hit.position.y > player.cam.global_position.y - 0.25
		var was := player.alive
		player.take_damage(damage * (head_mult if head else 1.0))
		player_hit(head)
		if not player.shielded:
			BWSfx.ui("hit_flesh", { "gain_db": 2.0 })
			if was and not player.alive:
				BWSfx.ui("ko_thud", { "gain_db": 0.0 })
	else:
		impact(hit.position, hit.normal)
		if paintball:
			splat(hit.position, hit.normal, PAINT.player if _shooter == player else PAINT.bot)


## A bullet (G28): flown from `from` along `dir` at FpsWeapons.bullet_speed()
## with a ray per tick (so nothing is skipped), hitting whatever it meets:
## the level, the bot, or you. Its trail starts at `vis_from` (the muzzle) and
## converges on the true path within a few metres.
func fire_bullet(from: Vector3, dir: Vector3, shooter: Node, damage: float, head_mult: float, reach: float, col: Color, vis_from: Vector3) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, 1.0)
	m.mesh = bm
	var mat := ShaderMaterial.new()
	mat.shader = _trail_shader()
	mat.set_shader_parameter("col", Color(col, 0.95))
	mat.set_shader_parameter("fade", FpsTune.value("trail_fade"))
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.visible = false
	add_child(m)
	_bullets.append({ "pos": from, "dir": dir.normalized(), "shooter": shooter, "damage": damage, "head": head_mult,
		"left": reach, "col": col, "mesh": m, "mat": mat, "off": vis_from - from, "went": 0.0, "dead": false, "fade": 0.1 })


func _fly_bullets(delta: float) -> void:
	var speed := FpsWeapons.bullet_speed()
	var trail := FpsTune.value("bullet_trail")
	for b in _bullets.duplicate():
		var mesh: MeshInstance3D = b.mesh
		if b.dead:
			b.fade -= delta
			(b.mat as ShaderMaterial).set_shader_parameter("col", Color(b.col as Color, maxf(0.0, b.fade / 0.1) * 0.95))
			if b.fade <= 0.0:
				mesh.queue_free()
				_bullets.erase(b)
			continue
		var step := minf(speed * delta, float(b.left))
		var from: Vector3 = b.pos
		var to: Vector3 = from + b.dir * step
		var shooter := b.shooter as CollisionObject3D
		var hit := trace(from, to, [shooter.get_rid()] if shooter else [])
		if not hit.is_empty():
			to = hit.position
			b.dead = true
			on_hit(b.shooter, hit, float(b.damage), float(b.head))
		# G62: the bot's bullet passing within WHIZZ_M of your head, once per bullet
		if b.shooter == bot and not b.get("whizzed", false) and player and player.alive and audio:
			var head: Vector3 = player.cam.global_position
			var near := Geometry3D.get_closest_point_to_segment(head, from, to)
			if near.distance_to(head) < WHIZZ_M and float(b.went) > 2.0:
				b.whizzed = true
				audio.play("whizz", near, { "unit": FpsAudio.UNIT_WHIZZ, "pitch": randf_range(0.9, 1.15) })
		b.went += from.distance_to(to)
		b.left -= step
		b.pos = to
		if b.left <= 0.0:
			b.dead = true
		# the trail: from the muzzle-offset head back along the path
		var head: Vector3 = to + (b.off as Vector3) * exp(-float(b.went) / 4.0)
		var ln := minf(trail, float(b.went))
		if ln < 0.05:
			continue
		var tail: Vector3 = head - b.dir * ln
		var d: Vector3 = head - tail
		var n := d.normalized()
		mesh.visible = true
		(b.mat as ShaderMaterial).set_shader_parameter("len", d.length())
		(b.mat as ShaderMaterial).set_shader_parameter("tail_d", float(b.went) - ln)
		mesh.global_transform = Transform3D(Basis.looking_at(n, Vector3.UP if absf(n.y) < 0.99 else Vector3.RIGHT).scaled_local(Vector3(1, 1, d.length())), tail + d * 0.5)


static var _trail_sh: Shader


## The trail's look (G51): additive, see-through at the barrel and full
## strength `fade` metres out (the author: ~3 ft), so a 30 m streak doesn't
## start as a bar out of the gun. The box runs local z +0.5 (tail) to -0.5
## (head); tail_d is how far the tail is from the barrel along the path.
static func _trail_shader() -> Shader:
	if _trail_sh == null:
		_trail_sh = Shader.new()
		_trail_sh.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0);
uniform float len = 1.0;
uniform float tail_d = 0.0;
uniform float fade = 1.1;
varying float d;
void vertex() { d = tail_d + (0.5 - VERTEX.z) * len; }
void fragment() {
	float a = fade <= 0.001 ? 1.0 : smoothstep(0.0, fade, d);
	ALBEDO = col.rgb;
	ALPHA = col.a * a;
}
"""
	return _trail_sh


func player_hit(head: bool) -> void:
	hud.hurt()
	if head:
		hud.note("Headshot by the bot")


func shot_near_player(_from: Vector3) -> void:
	pass


func loose_ball(at: Vector3, vel: Vector3, owner: Node, damage: float) -> void:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.03
	s.height = 0.06
	m.mesh = s
	m.material_override = GKMaterials.get_material("felt_white")
	add_child(m)
	m.global_position = at
	_balls.append({ "node": m, "vel": vel, "owner": owner, "damage": damage, "life": 4.0 })


const WHIZZ_M := 2.2                        ## a bot bullet this close to your head whizzes (G62)


func _physics_process(delta: float) -> void:
	_fly_bullets(delta)
	if audio:
		audio.update(delta)
	for b in _balls.duplicate():
		var n: Node3D = b.node
		var from := n.global_position
		b.vel += Vector3(0, -FpsPlayer.GRAVITY, 0) * delta
		var to: Vector3 = from + b.vel * delta
		var hit := trace(from, to, [(b.owner as CollisionObject3D).get_rid()])
		b.life -= delta
		if not hit.is_empty():
			on_hit(b.owner, hit, float(b.damage), 2.0)
			n.queue_free()
			_balls.erase(b)
		elif b.life <= 0.0:
			n.queue_free()
			_balls.erase(b)
		else:
			n.global_position = to


func tracer(from: Vector3, to: Vector3, col: Color) -> void:
	var d := to - from
	var ln := d.length()
	if ln < 0.5:
		return
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, ln)
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(col, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_transform = Transform3D(Basis.looking_at(d / ln, Vector3.UP if absf(d.y / ln) < 0.99 else Vector3.RIGHT), from + d * 0.5)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.12)
	tw.tween_callback(m.queue_free)


func muzzle_flash(at: Vector3, dir: Vector3, size := 1.0) -> void:
	# the flash itself (G51, FpsMuzzleFlash), along the shot
	var f := FpsMuzzleFlash.new()
	f.size = size
	add_child(f)
	var d := dir.normalized()
	f.global_transform = Transform3D(Basis.looking_at(-d, Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT), at)
	f.pop()
	get_tree().create_timer(FpsMuzzleFlash.LIFE + 0.1).timeout.connect(f.queue_free)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.4)
	l.light_energy = 4.0
	l.omni_range = 5.0
	add_child(l)
	l.global_position = at + dir * 0.2
	puff(at + dir * 0.15, Color(1.0, 0.7, 0.3), 0.06)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.08)
	tw.tween_callback(l.queue_free)


## The player's shot lights the world round the muzzle (G51), sized by the
## gun's flash; the Desert Eagle has its own, bigger boom().
func muzzle_light(at: Vector3, size: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.72, 0.38)
	l.light_energy = 2.5 + 3.0 * size
	l.omni_range = 3.0 + 3.5 * size
	add_child(l)
	l.global_position = at
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.06 + 0.04 * size)
	tw.tween_callback(l.queue_free)


## Paint on a wall or the ground (campus paintball): a flat blob that stays a while.
func splat(at: Vector3, normal: Vector3, col: Color) -> void:
	var d := Decal.new()
	d.size = Vector3(0.5, 0.3, 0.5) * randf_range(0.7, 1.3)
	d.texture_albedo = _splat_tex(col)
	add_child(d)
	var up := normal.normalized()
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	d.global_transform = Transform3D(Basis(side, up, side.cross(up)), at)
	get_tree().create_timer(40.0).timeout.connect(d.queue_free)


var _splats := {}


func _splat_tex(col: Color) -> Texture2D:
	var key := col.to_html()
	if _splats.has(key):
		return _splats[key]
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	for y in 48:
		for x in 48:
			var v := Vector2(x - 23.5, y - 23.5)
			var wob := 0.72 + 0.18 * sin(atan2(v.y, v.x) * 5.0) + 0.1 * sin(atan2(v.y, v.x) * 11.0 + 1.3)
			img.set_pixel(x, y, Color(col, clampf((wob - v.length() / 23.5) * 6.0, 0.0, 1.0)))
	_splats[key] = ImageTexture.create_from_image(img)
	return _splats[key]


## The Desert Eagle's bigger boom: a fat flash and a camera kick (G43).
func boom(at: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.35)
	l.light_energy = 9.0
	l.omni_range = 9.0
	add_child(l)
	l.global_position = at
	puff(at, Color(1.0, 0.65, 0.25), 0.12)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.14)
	tw.tween_callback(l.queue_free)


func impact(at: Vector3, normal: Vector3) -> void:
	puff(at + normal * 0.03, Color(0.7, 0.66, 0.6))


## A quick burst of small particles (dust, sparks, a hit).
func puff(at: Vector3, col: Color, life := 0.35) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 14
	p.lifetime = life
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.09
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = mat
	p.mesh = m
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(life + 0.2).timeout.connect(p.queue_free)


# ----------------------------------------------------------------- score

func _on_bot_died() -> void:
	score.x += 1
	hud.score = score
	hud.note("Bot down.  %d – %d" % [score.x, score.y])
	if not _check():
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			_bot_loadout()
			bot.respawn(_spawn("b")))


func _on_player_died() -> void:
	score.y += 1
	hud.score = score
	hud.note("You're down.  %d – %d" % [score.x, score.y])
	if not _check():
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			player.respawn(_spawn("a"))
			open_loadout())


func _check() -> bool:
	var goal := int(FpsTune.value("kills_to_win"))
	if _over or (score.x < goal and score.y < goal):
		return false
	_over = true
	var won := score.x >= goal
	hud.note("You win %d – %d" % [score.x, score.y] if won else "The bot wins %d – %d" % [score.y, score.x])
	BWSfx.ui("sting_victory" if won else "sting_defeat", { "delay": 0.6 })
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		match_over.emit(won, "%s, %d – %d." % [{ "rooftop": "Rooftop duel", "dust_mid": "Mid duel", "campus": "Campus paintball" }.get(map_id, "Duel"), score.x, score.y]))
	return true
