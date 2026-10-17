class_name ExtractWorld
extends FpsWorld
## Extraction: the FpsWorld without the duel. One life, no respawn, no
## radial: you start at a seeded edge spawn with the pistol in hand and one
## spare mag (scarce ammo: a reload spends a mag of the gun's calibre).
## Chests (meta.chests, tiers 1–3) and dead guards (meta.guards: green, loud,
## slow, on patrol) hold the loot: guns (a primary or a sidearm by calibre;
## the old one drops as a pickup), mags, a medkit, body armour, money. The
## clock runs FpsTune.extract_time; with extract_reveal s left a flare goes
## up over the extract pad farthest from your spawn and the compass shows
## its bearing; 3 s on the pad extracts. Death ends the run after 2 s; so
## does the clock. The result ({ how, cash, secs, where }) goes out on
## `run_over`; the module judges it against a simulated rival (beats()).
## Map: "extract_forest" (agent A's GKExtractForest); while it isn't
## registered, or with STUB on, the campus stands in with synthesized chests,
## guards and pads so the game can be developed and probed.

signal run_over(result: Dictionary)

## Tools: force the campus stand-in even when extract_forest exists.
static var STUB := false
const PAD_RADIUS := 3.0
const EXTRACT_HOLD := 3.0
const SHOT_LANDS_NEAR := 6.0           ## G65: a bullet of yours landing this close to a guard alerts it
const GUARD_GUNS := ["pistol", "carbine", "shotgun", "auto_rifle", "pistol", "carbine"]

var stubbed := false                   ## the campus stand-in is in use
var chests: Array = []                 ## ExtractChest
var guards: Array = []                 ## ExtractGuard
var pickups: Array = []                ## ExtractLoot.Pickup
var pads: Array = []                   ## Node3D, one per extract marker
var pad_pos: Array = []                ## Vector3 of each pad
var extract_i := -1                    ## the revealed pad; -1 before the flare
var clock := 0.0
var money := 0
var armour := 0.0                      ## soak left on the worn piece
var medkit := false
var heal_t := -1.0                     ## medkit progress in seconds; < 0 idle
var extracting := -1.0
var ended := false
var result := {}
var spawn_pos := Vector3.ZERO
var started := 0.0
var _f_held := -1.0
var _loot_rng := RandomNumberGenerator.new()
var _flare: Node3D
var xhud: ExtractHud


func _ready() -> void:
	if match_seed >= 0:
		_rng.seed = match_seed
	else:
		_rng.randomize()
	_loot_rng.seed = _rng.randi()
	map_id = "extract_forest"
	if STUB or GKRegistry.def(map_id) == null:
		map_id = "campus"
		stubbed = true
	map = GKRegistry.build(map_id, { "seed": match_seed } if not stubbed else {})
	FpsMuzzleFlash.warm()
	paintball = false
	hide_volumes = map.meta.get("hide_volumes", [])
	var stage := GKStage.outdoor(map.lights)
	add_child(stage)
	var sun := stage.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.light_cull_mask = 1
	var level := map.instantiate(true)
	add_child(level)
	nav = FpsNav.new()
	add_child(nav)
	if bake_nav:
		nav.bake(map, level)
	audio = FpsAudio.new()
	audio.world = self
	add_child(audio)
	player = FpsPlayer.new()
	player.world = self
	player.scarce = true
	add_child(player)
	player.global_transform = _spawn("a")
	spawn_pos = player.global_position
	player.died.connect(_on_player_died)
	player.fired.connect(func(from: Vector3, _hits: Array) -> void:
		on_player_shot(from)
		if heal_t >= 0.0:
			heal_t = -1.0
			hud.note("Healing interrupted"))
	xhud = ExtractHud.new()
	hud = xhud
	hud.player = player
	add_child(hud)
	player.cam.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	clock = FpsTune.value("extract_time")
	started = Time.get_ticks_msec() / 1000.0
	if stubbed:
		_synth_meta()
	_place_chests()
	_place_guards()
	_place_pads()
	open_loadout()
	hud.note("Loot. The extract is revealed at %s. One life." % _mmss(FpsTune.value("extract_reveal")))


## The starting kit instead of the radial: the pistol in hand, one spare mag.
func open_loadout() -> void:
	player.slots = ["pistol", "pistol"]           # no primary yet: both keys are the pistol
	player.set_slot(1, "pistol")
	player.mags = { "rifle": 0, "shotgun": 0, "pistol": 1 }
	player.input_on = _tune == null
	player.shielded = false


# ----------------------------------------------------------------- the stub

## The campus stand-in's meta: 20 chests (12 beside bushes, 8 against the
## big wall colliders), 4 guard posts with square patrols, 4 pads at the
## play area's corners. Seeded, so a seed is a layout.
func _synth_meta() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed if match_seed >= 0 else 1
	var pa: Array = map.meta.play_area
	var chests_m: Array = []
	var bushes := hide_volumes.duplicate()
	bushes.shuffle()
	for i in mini(12, bushes.size()):
		var h: Dictionary = bushes[i]
		var c: Vector3 = h.center
		var off := Vector3(cos(rng.randf() * TAU), 0, sin(rng.randf() * TAU)) * (float((h.half as Vector3).x) + 0.8)
		var g := ground(c + off)
		if g != Vector3.INF:
			chests_m.append({ "pos": g, "yaw": rng.randf() * TAU, "where": "bush", "tier": 1 if rng.randf() < 0.7 else 2 })
	var walls: Array = map.colliders.filter(func(c: Dictionary) -> bool:
		var s: Vector3 = c.size
		return not c.get("barrier", false) and s.y > 3.0 and maxf(s.x, s.z) > 6.0 and minf(s.x, s.z) < 2.0)
	walls.shuffle()
	for i in mini(8, walls.size()):
		var c: Dictionary = walls[i]
		var xf: Transform3D = c.xform
		var s: Vector3 = c.size
		var n: Vector3 = xf.basis.x if s.x < s.z else xf.basis.z
		var thick := s.x if s.x < s.z else s.z
		for side: float in [1.0, -1.0]:
			var p := xf.origin + n * side * (thick * 0.5 + 0.6)
			var g := ground(p)
			if g != Vector3.INF and g.x > float(pa[0]) and g.x < float(pa[2]) and g.z > float(pa[1]) and g.z < float(pa[3]):
				chests_m.append({ "pos": g, "yaw": atan2(n.x, n.z) + PI * 0.5, "where": "building", "tier": 2 if rng.randf() < 0.6 else 3 })
				break
	map.meta["chests"] = chests_m
	var guards_m: Array = []
	var posts := [Vector2(-25, -22), Vector2(25, -22), Vector2(-20, 18), Vector2(22, 16)]
	for i in posts.size():
		var p2: Vector2 = posts[i] + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
		var at := ground(Vector3(p2.x, 0, p2.y))
		if at == Vector3.INF:
			continue
		var loop: Array = []
		var r := 7.0
		for k in 4:
			var q := ground(at + Vector3(r * (1 if k < 2 else -1), 0, r * (1 if k in [1, 2] else -1)))
			if q != Vector3.INF:
				loop.append(q)
		guards_m.append({ "pos": at, "building": i, "patrol": loop })
	map.meta["guards"] = guards_m
	var inset := 8.0
	var corners := [Vector2(float(pa[0]) + inset, float(pa[1]) + inset), Vector2(float(pa[2]) - inset, float(pa[1]) + inset),
		Vector2(float(pa[2]) - inset, float(pa[3]) - inset), Vector2(float(pa[0]) + inset, float(pa[3]) - inset)]
	for i in 4:
		var c: Vector2 = corners[i]
		var g := ground(Vector3(c.x, 0, c.y))
		if g == Vector3.INF:
			g = Vector3(c.x, 0.0, c.y)
		map.markers["extract%d" % i] = Transform3D(Basis.IDENTITY, g)
	map.meta["extract"] = true


## The ground under (x, z): a ray from 40 m up against the level.
func ground(p: Vector3) -> Vector3:
	var hit := trace(Vector3(p.x, 40.0, p.z), Vector3(p.x, -30.0, p.z), [], 1)
	return hit.position if not hit.is_empty() else Vector3.INF


# ----------------------------------------------------------------- the map's things

func _place_chests() -> void:
	for c: Dictionary in map.meta.get("chests", []):
		var ch := ExtractChest.new()
		ch.tier = int(c.get("tier", 1))
		add_child(ch)
		ch.global_transform = Transform3D(Basis(Vector3.UP, float(c.get("yaw", 0.0))), c.pos)
		chests.append(ch)


func _place_guards() -> void:
	var i := 0
	for g: Dictionary in map.meta.get("guards", []):
		var gd := ExtractGuard.new()
		gd.world = self
		gd.target = player
		gd.post = i
		gd.patrol = (g.get("patrol", []) as Array).duplicate()
		gd.weapon = GUARD_GUNS[_rng.randi() % GUARD_GUNS.size()]
		if not FpsWeapons.available(gd.weapon):
			gd.weapon = "sniper"
		gd.roof = [Rect2(-1000, -1000, 2000, 2000)]
		add_child(gd)
		var at: Vector3 = g.pos
		gd.respawn(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.2, 0)))
		gd.barked.connect(_on_guard_bark)
		gd.died.connect(_on_guard_died.bind(gd))
		guards.append(gd)
		i += 1


## The four pads: a concrete disc with four short posts; the chosen one
## lights up at the reveal.
func _place_pads() -> void:
	for i in 4:
		if not map.markers.has("extract%d" % i):
			continue
		var at := map.marker("extract%d" % i).origin
		var g := ground(at + Vector3(0, 0.5, 0))
		if g != Vector3.INF and absf(g.y - at.y) < 3.0:
			at = g
		var n := Node3D.new()
		var m := GKMesh.new()
		m.tube("concrete_light", [Vector3(0, -0.05, 0), Vector3(0, 0.08, 0)], PAD_RADIUS, 24)
		for k in 4:
			var a := TAU * k / 4.0 + PI * 0.25
			m.box("iron_dark", Vector3(cos(a) * (PAD_RADIUS - 0.2), 0.5, sin(a) * (PAD_RADIUS - 0.2)), Vector3(0.12, 1.0, 0.12))
		var mi := MeshInstance3D.new()
		mi.mesh = m.commit()
		GKMaterials.apply(mi)
		n.add_child(mi)
		add_child(n)
		n.global_position = at
		pads.append(n)
		pad_pos.append(at)


# ----------------------------------------------------------------- the run

func _process(delta: float) -> void:
	if ended:
		return
	clock -= delta
	xhud.clock = clock
	xhud.money = money
	xhud.armour = armour
	xhud.medkit = medkit
	xhud.healing = heal_t / 4.0 if heal_t >= 0.0 else -1.0
	xhud.mags = player.mags
	xhud.extracting = extracting
	var tgt := interact_target()
	xhud.prompt = _prompt_for(tgt)
	if extract_i < 0 and clock <= FpsTune.value("extract_reveal"):
		reveal()
	if clock <= 0.0:
		clock = 0.0
		end_run("timeout")
	# the medkit: medkit_heal over 4 s, a shot stops it (player.fired)
	if heal_t >= 0.0 and player.alive:
		var rate := FpsTune.value("medkit_heal") / 4.0
		player.hp = minf(100.0, player.hp + rate * delta)
		heal_t += delta
		if heal_t >= 4.0:
			heal_t = -1.0
	# F held 0.6 s with nothing to open: the medkit
	if _f_held >= 0.0:
		_f_held += delta
		if _f_held > 0.6 and tgt == null and medkit and heal_t < 0.0:
			use_medkit()
			_f_held = -1.0


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if ended or extract_i < 0 or not player.alive:
		extracting = -1.0
		return
	var pad: Vector3 = pad_pos[extract_i]
	var d := player.global_position - pad
	if Vector2(d.x, d.z).length() <= PAD_RADIUS and absf(d.y) < 2.5:
		if extracting < 0.0:
			extracting = 0.0
			hud.note("Hold the pad")
		extracting += delta
		if extracting >= EXTRACT_HOLD:
			end_run("extracted")
	else:
		extracting = -1.0


## The flare: the pad farthest from your spawn lights up, a flare climbs
## over it and hangs there (a bright light and a tall beam you can see over
## the trees); the compass carries its bearing from now on.
func reveal() -> void:
	if extract_i >= 0 or pad_pos.is_empty():
		return
	var best := 0
	for i in pad_pos.size():
		if (pad_pos[i] as Vector3).distance_to(spawn_pos) > (pad_pos[best] as Vector3).distance_to(spawn_pos):
			best = i
	extract_i = best
	var at: Vector3 = pad_pos[best]
	xhud.extract_at = at
	_flare = Node3D.new()
	add_child(_flare)
	_flare.global_position = at
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.6
	cm.bottom_radius = 1.2
	cm.height = 90.0
	cm.radial_segments = 10
	beam.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.albedo_color = Color(1.0, 0.3, 0.2, 0.6)
	bm.no_depth_test = false
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 50.0                     # its foot at 5 m: standing on the pad isn't standing in it
	_flare.add_child(beam)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.0
	sm.height = 4.0
	ball.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.55, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.2)
	mat.emission_energy_multiplier = 6.0
	ball.material_override = mat
	ball.position.y = 2.0
	_flare.add_child(ball)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.3)
	light.light_energy = 2.5                   # a glow over the pad, not the whole valley dyed red
	light.omni_range = 30.0
	light.position.y = 2.0
	_flare.add_child(light)
	var smoke := CPUParticles3D.new()
	smoke.amount = 60
	smoke.lifetime = 4.0
	smoke.direction = Vector3.UP
	smoke.spread = 10.0
	smoke.initial_velocity_min = 2.0
	smoke.initial_velocity_max = 4.0
	smoke.gravity = Vector3(0.6, 1.5, 0)
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 2.2
	var pm := SphereMesh.new()
	pm.radius = 0.5
	pm.height = 1.0
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.9, 0.5, 0.4, 0.5)
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.material = pmat
	smoke.mesh = pm
	smoke.position.y = 2.0
	_flare.add_child(smoke)
	# the climb: the ball and its light rise to 40 m over 2.5 s and stay
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ball, "position:y", 40.0, 2.5).set_ease(Tween.EASE_OUT)
	tw.tween_property(light, "position:y", 40.0, 2.5).set_ease(Tween.EASE_OUT)
	tw.tween_property(smoke, "position:y", 40.0, 2.5).set_ease(Tween.EASE_OUT)
	# the pad glows
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = PAD_RADIUS - 0.3
	tm.outer_radius = PAD_RADIUS
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color("#7fd35a")
	rm.emission_enabled = true
	rm.emission = Color("#7fd35a")
	rm.emission_energy_multiplier = 2.0
	ring.material_override = rm
	ring.position.y = 0.12
	(pads[best] as Node3D).add_child(ring)
	hud.note("Flare up: the extract is %d m %s" % [int(Vector2(at.x - player.global_position.x, at.z - player.global_position.z).length()), _compass_word(at - player.global_position)])


static func _compass_word(d: Vector3) -> String:
	var a := wrapf(atan2(d.x, -d.z), -PI, PI)
	var k := int(round(a / (PI * 0.25))) % 8
	return ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][posmod(k, 8)]


func end_run(how: String) -> void:
	if ended:
		return
	ended = true
	_over = true
	extracting = -1.0
	heal_t = -1.0
	var secs := FpsTune.value("extract_time") - clock
	result = { "how": how, "cash": worth(), "secs": secs, "where": where_am_i() }
	match how:
		"extracted":
			hud.note("Extracted with %s" % ExtractLoot.dollars(int(result.cash)))
		"timeout":
			hud.note("Time's up")
		_:
			hud.note("You died")
	player.input_on = false
	var t := Timer.new()                     # a child, so a world freed early emits nothing
	t.one_shot = true
	t.wait_time = 2.0 if how == "died" else 3.0
	add_child(t)
	t.timeout.connect(func() -> void: run_over.emit(result))
	t.start()


## Everything held, in $: cash, the guns in the slots, the kit.
func worth() -> int:
	var v := money
	var seen := {}
	for id: String in player.slots:
		if id != "" and not seen.has(id):
			seen[id] = true
			v += ExtractLoot.value(id)
	if medkit:
		v += ExtractLoot.VALUE.medkit
	if armour > 0.0:
		v += ExtractLoot.VALUE.armour
	return v


## For the summary: the nearest building you are in or beside, else the ground.
func where_am_i() -> String:
	var p := player.global_position
	var best := ""
	var bd := 12.0
	for b: Dictionary in map.meta.get("buildings", []):
		var box: AABB = b.aabb
		var d := 0.0 if box.has_point(p) else (box.get_center() - p).length() - box.size.length() * 0.5
		if d < bd:
			bd = d
			var nm := str(b.get("name", b.get("kind", "building")))
			best = "in %s" % (nm if nm.begins_with("the ") else "the " + nm)
	if best != "":
		return best
	return "on the campus" if stubbed else ("in the woods" if not in_bush(p) else "in a bush")


func _on_player_died() -> void:
	xhud._dead.text = "You died."
	end_run("died")


# ----------------------------------------------------------------- hits

## Guards take your bullets (and their own friendly fire is ignored); your
## hits come through the armour first.
func on_hit(shooter: Node, hit: Dictionary, damage: float, head_mult: float) -> void:
	if shooter == player:
		alert_near(hit.position, SHOT_LANDS_NEAR)        # G65: a miss that lands by a guard alerts it
	if hit.collider is ExtractGuard:
		var g := hit.collider as ExtractGuard
		if shooter == player and g.alive:
			var head := int(hit.shape) == 1
			g.hurt(damage * (head_mult if head else 1.0), head)
			hud.hit_marker()
			puff(hit.position, Color(0.75, 0.2, 0.15))
			if head:
				hud.note("Headshot")
		else:
			impact(hit.position, hit.normal)
		return
	if hit.collider == player and player.alive:
		var head: bool = hit.position.y > player.cam.global_position.y - 0.25
		var d := damage * (head_mult if head else 1.0)
		if armour > 0.0:
			var cut := d * FpsTune.value("armour_cut")
			d -= cut
			armour -= cut
			if armour <= 0.0:
				armour = 0.0
				hud.note("Armour broken")
		player.take_damage(d)
		player_hit(head)
		return
	super.on_hit(shooter, hit, damage, head_mult)


func player_hit(head: bool) -> void:
	hud.hurt()
	if head:
		hud.note("Headshot")


# ----------------------------------------------------------------- guards

## G65, the aggro rule's shot half: your shot alerts every calm guard within
## guard_shot_alert of where you fired (it heard it); the guard you hit and
## any within SHOT_LANDS_NEAR of where the bullet landed are alerted in
## on_hit / ExtractGuard.hurt. Guards farther off stay calm.
func on_player_shot(from: Vector3) -> void:
	alert_near(from, FpsTune.value("guard_shot_alert"))


func alert_near(at: Vector3, r: float) -> void:
	if r <= 0.0:
		return
	for g: ExtractGuard in guards:
		if is_instance_valid(g) and g.alive and not g.alerted and g.global_position.distance_to(at) <= r:
			g.alert()


func _on_guard_bark(g: ExtractGuard) -> void:
	if ended or not player.alive:
		return
	if g.global_position.distance_to(player.global_position) <= FpsTune.value("guard_hear_range"):
		xhud.guard_mark(g.global_position)


func _on_guard_died(g: ExtractGuard) -> void:
	var at := ground(g.global_position + Vector3(0.6, 1.0, 0.4))
	if at == Vector3.INF:
		at = g.global_position
	var pk := ExtractLoot.Pickup.make(at, ExtractLoot.guard_drop(g.weapon, _loot_rng))
	add_child(pk)
	pickups.append(pk)
	hud.note("Guard down")
	get_tree().create_timer(6.0).timeout.connect(g.queue_free)


# ----------------------------------------------------------------- loot

## The chest or pickup within chest_range of you (nearest), else null.
func interact_target() -> Node3D:
	var reach := FpsTune.value("chest_range")
	var best: Node3D = null
	var bd := reach
	var p := player.global_position
	for ch: ExtractChest in chests:
		if ch.is_open:
			continue
		var d := ch.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = ch
	for pk in pickups:
		if not is_instance_valid(pk):
			continue
		var d := (pk as Node3D).global_position.distance_to(p)
		if d < bd:
			bd = d
			best = pk
	return best


func _prompt_for(t: Node3D) -> String:
	if t is ExtractChest:
		return "Open chest"
	if t is ExtractLoot.Pickup:
		return "Take %s" % (t as ExtractLoot.Pickup).label
	return "Medkit (hold)" if medkit and heal_t < 0.0 else ""


## F: open the chest / take the pickup in reach.
func interact() -> bool:
	if ended or not player.alive:
		return false
	var t := interact_target()
	if t is ExtractChest:
		var items := (t as ExtractChest).open(_loot_rng)
		take(items)
		return true
	if t is ExtractLoot.Pickup:
		var pk := t as ExtractLoot.Pickup
		var left := take(pk.items)
		if left.is_empty():
			pickups.erase(pk)
			pk.queue_free()
		else:
			pk.items = left
		return true
	return false


## Items into the kit; what couldn't be taken (a full pouch, a second
## medkit) is returned. The pop-up lists what you got.
func take(items: Array) -> Array:
	var got: Array = []
	var left: Array = []
	for it: Dictionary in items:
		if give(it):
			got.append(it)
		else:
			left.append(it)
	if not got.is_empty():
		xhud.loot_popup(got)
	return left


func give(it: Dictionary) -> bool:
	match str(it.kind):
		"money":
			money += int(it.amount)
			return true
		"mag":
			if player.give_mag(str(it.caliber)):
				return true
			hud.note("Mags full")
			return false
		"medkit":
			if medkit:
				hud.note("Already carrying a medkit")
				return false
			medkit = true
			return true
		"armour":
			if armour > 0.0:
				hud.note("Already wearing armour")
				return false
			armour = float(it.amount)
			return true
		"gun":
			equip_gun(str(it.id), int(it.amount))
			return true
	return false


## A gun into its slot by calibre (rifle / shotgun: primary; pistol: sidearm),
## into the hand; the one it replaces drops at your feet as a pickup.
func equip_gun(id: String, rounds: int) -> void:
	var slot := 0 if ExtractLoot.is_primary(id) else 1
	var old: String = player.slots[slot]
	var old_rounds := int(player.ammo.get(old, 0))
	player.set_slot(slot, id, rounds)
	if old != "" and old != id and not (old in player.slots):
		var at := ground(player.global_position + Vector3(0.6, 1.0, -0.4))
		var pk := ExtractLoot.Pickup.make(at if at != Vector3.INF else player.global_position, [ExtractLoot.gun_item(old, old_rounds)], old)
		add_child(pk)
		pickups.append(pk)


func use_medkit() -> bool:
	if not medkit or heal_t >= 0.0 or not player.alive or ended:
		return false
	medkit = false
	heal_t = 0.0
	hud.note("Healing")
	return true


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and not ev.echo and player.input_on:
		if ev.physical_keycode == KEY_F:
			if ev.pressed:
				_f_held = 0.0
			else:
				if _f_held >= 0.0 and _f_held < 0.6:
					interact()
				_f_held = -1.0
			return
		if ev.physical_keycode == KEY_4 and ev.pressed:
			use_medkit()
			return
	super._unhandled_input(ev)


# ----------------------------------------------------------------- verdict

## a beats b: extracted over died or timed out; then more $; then faster.
static func beats(a: Dictionary, b: Dictionary) -> bool:
	var ea := str(a.how) == "extracted"
	var eb := str(b.how) == "extracted"
	if ea != eb:
		return ea
	if int(a.cash) != int(b.cash):
		return int(a.cash) > int(b.cash)
	return float(a.secs) < float(b.secs)


static func _mmss(s: float) -> String:
	var k := maxi(0, ceili(s))
	return "%d:%02d" % [k / 60, k % 60]


## "<name> extracted with $1,250 at 3:12." / "<name> died in the lodge with $400."
static func line(p: Dictionary, r: Dictionary) -> String:
	match str(r.how):
		"extracted": return "%s extracted with %s at %s" % [p.name, ExtractLoot.dollars(int(r.cash)), _mmss(float(r.secs))]
		"died": return "%s died %s with %s" % [p.name, str(r.get("where", "out there")), ExtractLoot.dollars(int(r.cash))]
	return "%s ran out of time with %s" % [p.name, ExtractLoot.dollars(int(r.cash))]
