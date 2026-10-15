class_name FpsWorld
extends Node3D
## The FPS prototype: you against a bot on the Gauntlet kit's apartment
## rooftops (G17), first to FpsTune.kills_to_win. Builds the map from the
## kit (its colliders are the level), seats the player on roof A and the bot
## on roof B, and owns the shared effects (traces, tracers, flashes, impacts,
## slingshot balls) and the score. Run it alone:
##   godot --path . res://scenes/fps_proto.tscn
## or inside the tournament as FpsModule.

signal match_over(human_won: bool, summary: String)

var map: GKAsset
var player: FpsPlayer
var bot: FpsBot
var hud: FpsHud
var score := Vector2i.ZERO
var _over := false
var _balls: Array[Dictionary] = []
var _tune: FpsTunePanel


func _ready() -> void:
	map = GKRegistry.build("rooftop")
	var stage := GKStage.outdoor(map.lights)
	add_child(stage)
	var sun := stage.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.light_cull_mask = 1                 # the world; the gun has its own light (FpsHud)
	add_child(map.instantiate(true))
	player = FpsPlayer.new()
	player.world = self
	add_child(player)
	player.global_transform = _spawn("a")
	player.died.connect(_on_player_died)
	bot = FpsBot.new()
	bot.world = self
	bot.target = player
	for r in (map.meta.roofs.b as Array):
		bot.roof.append(Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1])))
	add_child(bot)
	bot.global_transform = _spawn("b")
	bot.respawn(bot.global_transform)
	bot.died.connect(_on_bot_died)
	hud = FpsHud.new()
	hud.player = player
	add_child(hud)
	player.cam.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.note("First to %d. The bot is on the far roof." % int(FpsTune.value("kills_to_win")))


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _spawn(side: String) -> Transform3D:
	var k := randi() % 3
	var t := map.marker("spawn_%s%d" % [side, k])
	return Transform3D(t.basis, t.origin + Vector3(0, 0.2, 0))


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif ev.physical_keycode == KEY_F1:
			_toggle_tune()
	elif ev is InputEventMouseButton and ev.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and _tune == null:
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
	else:
		impact(hit.position, hit.normal)


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


func _physics_process(delta: float) -> void:
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


func muzzle_flash(at: Vector3, dir: Vector3) -> void:
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
		get_tree().create_timer(3.0).timeout.connect(func() -> void: bot.respawn(_spawn("b")))


func _on_player_died() -> void:
	score.y += 1
	hud.score = score
	hud.note("You're down.  %d – %d" % [score.x, score.y])
	if not _check():
		get_tree().create_timer(3.0).timeout.connect(func() -> void: player.respawn(_spawn("a")))


func _check() -> bool:
	var goal := int(FpsTune.value("kills_to_win"))
	if _over or (score.x < goal and score.y < goal):
		return false
	_over = true
	var won := score.x >= goal
	hud.note("You win %d – %d" % [score.x, score.y] if won else "The bot wins %d – %d" % [score.y, score.x])
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		match_over.emit(won, "Rooftop duel, %d – %d." % [score.x, score.y]))
	return true
