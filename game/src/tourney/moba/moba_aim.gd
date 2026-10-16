extends Node3D
## The cast modes and the aim indicator (G54). The view hands every Q W E R
## key event to `key()`; in Quick cast it casts at once, in Slow and Release
## cast it first shows the spell's range (a ring round you) and its shape
## (MobaChamps.SHAPES: a line, a circle where it lands, a cone, the target
## ring, the dash), then casts on the second press / the release / a left
## click. Right click or Esc cancels. Draws on render layer 2 (never on the
## minimap photo). Preloaded by MobaView, not a global class.

const MobaOptions := preload("res://src/tourney/moba/moba_options.gd")
const COL := Color(0.55, 0.85, 1.0, 0.85)
const FILL := Color(0.45, 0.75, 1.0, 0.22)

var view                         # MobaView
var mode := "quick"
var armed := ""                  # the slot whose indicator shows ("" = none)

var _range: MeshInstance3D
var _shape: MeshInstance3D
var _shape_key := ""


func _ready() -> void:
	mode = MobaOptions.load_cast_mode()


## A Q W E R key went down (`down`) or up. Returns true when it was used.
func key(slot: String, down: bool) -> bool:
	if mode == "quick" or not _aims(slot):
		if down:
			_cast(slot)
		return down
	if mode == "release":
		if down and armed == "":
			armed = slot
		elif not down and armed == slot:
			_cast(slot)
			armed = ""
		return true
	# slow
	if not down:
		return false
	if armed == slot:
		_cast(slot)
		armed = ""
	else:
		armed = slot
	return true


## A left click while armed casts it (slow cast); a right click cancels.
func click(left: bool) -> bool:
	if armed == "":
		return false
	if left and mode == "slow":
		_cast(armed)
	armed = ""
	return true


func cancel() -> void:
	armed = ""


## Spells with nothing to aim (Temu's W, his passive E) cast on the press in every mode.
func _aims(slot: String) -> bool:
	var me = view.sim.unit(view.local_id)
	if me == null:
		return false
	return not str(MobaChamps.shape(me.champ, slot).get("shape", "none")) in ["self", "none"]


func _cast(slot: String) -> void:
	var h = view._hovered()
	view._order["cast"] = { "slot": slot, "aim": view._mouse_world(), "target": h.id if h else "" }


func _process(_d: float) -> void:
	var me = view.sim.unit(view.local_id) if view else null
	var show: bool = armed != "" and me != null and me.alive
	if not show:
		if _range:
			_range.visible = false
		if _shape:
			_shape.visible = false
		if me == null or not me.alive:
			armed = ""
		return
	var sp: Dictionary = MobaChamps.shape(me.champ, armed)
	var at := Vector3(me.pos.x, 0.06, me.pos.y)
	if view._views.has(me.id):
		var rp: Vector3 = (view._views[me.id].root as Node3D).position
		at = Vector3(rp.x, 0.06, rp.z)
	var rng := float(sp.get("range", 0.0))
	if _range == null or not is_equal_approx(float(_range.get_meta("r", 0.0)), rng):
		if _range:
			_range.queue_free()
		_range = _ring_mesh(rng, 0.06, COL)
		_range.set_meta("r", rng)
	_range.position = at
	_range.visible = rng > 0.0
	var key_ := "%s:%s" % [me.champ, armed]
	if key_ != _shape_key:
		if _shape:
			_shape.queue_free()
		_shape = _shape_mesh(sp)
		_shape_key = key_
	var mw: Vector2 = view._mouse_world()
	var p2 := Vector2(at.x, at.z)
	var dir: Vector2 = (mw - p2).normalized() if mw.distance_to(p2) > 0.05 else me.facing
	_shape.visible = true
	match str(sp.shape):
		"circle":
			var land := p2 + (mw - p2).limit_length(rng)
			_shape.position = Vector3(land.x, 0.07, land.y)
		"target":
			var t = view._hovered()
			if t and t.pos.distance_to(me.pos) <= rng + t.radius:
				_shape.position = Vector3(t.pos.x, 0.07, t.pos.y)
			else:
				var land := p2 + (mw - p2).limit_length(rng)
				_shape.position = Vector3(land.x, 0.07, land.y)
		_:
			_shape.position = Vector3(at.x, 0.07, at.z)
			_shape.rotation.y = -dir.angle()


func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 2
	return m


func _ring_mesh(r: float, w: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = maxf(0.01, r - w)
	tm.outer_radius = maxf(0.02, r)
	tm.rings = 96
	mi.mesh = tm
	mi.material_override = _mat(col)
	mi.scale = Vector3(1, 0.05, 1)
	mi.layers = 2
	add_child(mi)
	return mi


## The spell's footprint, built along +x from the champion (lines, cones,
## dashes) or centred where it lands (circles, targets).
func _shape_mesh(sp: Dictionary) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := func(a: Vector3, b: Vector3, c: Vector3) -> void:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
	var rng := float(sp.get("range", 1.0))
	match str(sp.get("shape", "none")):
		"line", "dash":
			var hw := float(sp.get("width", 0.4)) if str(sp.shape) == "line" else 0.35
			tri.call(Vector3(0, 0, -hw), Vector3(rng, 0, -hw), Vector3(rng, 0, hw))
			tri.call(Vector3(0, 0, -hw), Vector3(rng, 0, hw), Vector3(0, 0, hw))
			if str(sp.shape) == "dash":          # an arrowhead at the end
				tri.call(Vector3(rng, 0, -0.7), Vector3(rng + 0.6, 0, 0), Vector3(rng, 0, 0.7))
		"cone":
			var half := deg_to_rad(float(sp.get("deg", 60.0))) * 0.5
			for i in 16:
				var a0 := -half + 2.0 * half * i / 16.0
				var a1 := -half + 2.0 * half * (i + 1) / 16.0
				tri.call(Vector3.ZERO, Vector3(cos(a0) * rng, 0, sin(a0) * rng), Vector3(cos(a1) * rng, 0, sin(a1) * rng))
		"circle", "target":
			var r := float(sp.get("r", 1.0))
			for i in 32:
				var a0 := TAU * i / 32.0
				var a1 := TAU * (i + 1) / 32.0
				tri.call(Vector3.ZERO, Vector3(cos(a0) * r, 0, sin(a0) * r), Vector3(cos(a1) * r, 0, sin(a1) * r))
		_:
			tri.call(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(FILL)
	mi.layers = 2
	add_child(mi)
	if str(sp.get("shape", "")) in ["circle", "target"]:     # a crisp rim on the landing circle
		var rim := _ring_mesh(float(sp.get("r", 1.0)), 0.07, COL)
		rim.reparent(mi, false)
		rim.position = Vector3.ZERO
	return mi
