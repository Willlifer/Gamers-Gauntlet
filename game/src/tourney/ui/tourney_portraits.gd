class_name TourneyPortraits
extends Node
## Head-and-shoulders snapshots of the contestants for the bracket plates
## (G27), rendered once per look in a small SubViewport and cached for the
## session. Black | White's BWPortraits keys on its own looks and ignores the
## tournament's hair colour, so the tournament keeps its own small cache.
##   TourneyPortraits.ensure(host)
##   var tex := TourneyPortraits.portrait(state, p)   # null until rendered
##   TourneyPortraits.inst().landed.connect(func(key): ...)

signal landed(key: String)

const SIZE := 96

static var _cache := {}                     # key -> Texture2D
static var _inst: TourneyPortraits

var _queue: Array = []                      # [key, BWUnit]
var _busy := false


static func ensure(host: Node) -> TourneyPortraits:
	if _inst == null or not is_instance_valid(_inst):
		_inst = TourneyPortraits.new()
		_inst.name = "TourneyPortraits"
		host.add_child(_inst)
	return _inst


static func inst() -> TourneyPortraits:
	return _inst


static func key_for(p: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in ["hair_style", "hair_hex", "top", "shade", "head", "chest"]:
		parts.append(str(p.get(k, "")))
	return "|".join(parts)


static func portrait(state: TourneyState, p: Dictionary) -> Texture2D:
	if p.is_empty():
		return null
	var k := key_for(p)
	if _cache.has(k):
		return _cache[k]
	if _inst and DisplayServer.get_name() != "headless":
		_inst._want(k, state.unit_for(p))
	return null


func _want(k: String, u: BWUnit) -> void:
	for q in _queue:
		if q[0] == k:
			return
	_queue.append([k, u])
	if not _busy:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var q: Array = _queue.pop_front()
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 40, 0)
	vp.add_child(sun)
	var view := BWUnitView.new()
	vp.add_child(view)
	view.setup(q[1])
	view.show_label(false)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.25
	var hy := view.head_height()
	var yaw := deg_to_rad(22.0)
	cam.position = Vector3(sin(yaw) * 3.0, hy - 0.02, cos(yaw) * 3.0)
	vp.add_child(cam)
	cam.look_at(Vector3(0, hy - 0.18, 0))
	cam.make_current()
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	_cache[q[0]] = ImageTexture.create_from_image(img)
	vp.queue_free()
	landed.emit(q[0])
	_next()
