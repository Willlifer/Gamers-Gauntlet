class_name FpsOptic
extends Node3D
## A sight bolted to a gun in first person (G51c): the automatic rifle and the
## personal carbine take iron sights, a red dot or a scope, picked on the
## buy-phase radial (FpsTune.optic). Built in the gun's own frame (x left,
## y up, +z ahead of the grip; the model's metres times its build scale) from
## FpsWeapons.SPECS[id].optics[kind]:
##   reflex  an open red dot on a riser: a hood round a faintly tinted pane,
##           and the dot, which sits where your line of sight crosses the
##           pane (so it stays on the point of aim) with a touch of parallax
##   scope   a short 1-inch tube on two rings; the ocular lens gets the
##           view model's low-res magnified picture (FpsViewmodel lens)
##   irons   a flipped-up rear aperture and a clean front post
## A kind can instead name a part of the model to keep (the automatic rifle's
## own tube optic as its scope, the carbine's own flip-ups as its irons);
## FpsViewmodel shows or hides those parts. `eye` (gun frame) is where the
## eye sits when aimed in; `lens` (if any) where the picture goes.

const PARALLAX := 0.12                      ## how far the dot drifts from the aim point (share of the offset)

var kind := ""
var eye := Vector3.ZERO
var lens := {}                              ## { pos: Vector3, r: float } or empty
var _dot: MeshInstance3D
var _window := Vector2.ZERO                 ## the pane's half size (gun frame)
var _pane_at := Vector3.ZERO                ## the pane's centre (gun frame)


## Build the sight `k` from its spec `o` (one entry of SPECS[id].optics), for
## a model built at scale `sc`, its rail top at `rail` (model metres).
func build(k: String, o: Dictionary, sc: float, rail: float, layer: int) -> void:
	kind = k
	var g := GKMesh.new()
	g.push(Transform3D(Basis.from_scale(Vector3.ONE * sc), Vector3.ZERO))
	var axis := float(o.get("axis", 0.17))
	var at := float(o.get("at", 0.1))
	match str(o.get("build", "")):
		"reflex":
			_reflex(g, axis, at, rail)
			eye = Vector3(0, axis, at - float(o.get("eye_back", 0.09))) * sc
		"scope":
			var ln := float(o.get("len", 0.16))
			var r := float(o.get("r", 0.016))
			_scope(g, axis, at, ln, r, rail)
			eye = Vector3(0, axis, at - ln * 0.5 - float(o.get("eye_back", 0.07))) * sc
			lens = { "pos": Vector3(0, axis, at - ln * 0.5 - 0.001) * sc, "r": (r + 0.001) * sc }     # just behind the eyepiece's end
		"irons":
			_irons(g, axis, float(o.get("rear", 0.03)), float(o.get("front", 0.45)), rail)
			eye = Vector3(0, axis, float(o.get("rear", 0.03)) - float(o.get("eye_back", 0.07))) * sc
		_:
			var e: Array = o.get("eye", [axis, at])
			eye = Vector3(0, float(e[0]), float(e[1])) * sc
			if o.has("lens"):
				var l: Array = o.lens
				lens = { "pos": Vector3(0, float(e[0]), float(l[0])) * sc, "r": float(l[1]) * sc }
	g.pop()
	var mesh := g.commit()
	if mesh != null and mesh.get_surface_count() > 0:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		GKMaterials.apply(mi)
		mi.layers = layer
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	if str(o.get("build", "")) == "reflex":
		_pane_at *= sc
		_window *= sc
		_make_pane(layer, sc)


## The open reflex sight: a riser on the rail, a hood, the window.
func _reflex(g: GKMesh, axis: float, at: float, rail: float) -> void:
	var w := 0.028
	var h := 0.022
	var base_top := axis - h * 0.5 - 0.004
	g.box("alloy_black", Vector3(0, (rail + base_top) * 0.5, at), Vector3(0.024, base_top - rail, 0.04), 0.002)        # riser
	g.box("alloy_black", Vector3(0, rail + 0.003, at), Vector3(0.028, 0.008, 0.044), 0.0015)                        # rail clamp
	g.box("alloy_black", Vector3(0, base_top + 0.002, at), Vector3(w + 0.008, 0.006, 0.03), 0.0015)                 # the body under the window
	var hz := at + 0.008
	for sx in [-1.0, 1.0]:                                                                                           # the hood's sides
		g.box("alloy_black", Vector3(sx * (w * 0.5 + 0.002), axis, hz), Vector3(0.004, h + 0.004, 0.016), 0.001)
	g.box("alloy_black", Vector3(0, axis + h * 0.5 + 0.002, hz), Vector3(w + 0.008, 0.004, 0.016), 0.001)          # its top
	g.box("alloy_black", Vector3(0.011, base_top + 0.006, at - 0.012), Vector3(0.006, 0.004, 0.006))                  # the emitter
	_window = Vector2(w * 0.5, h * 0.5)
	_pane_at = Vector3(0, axis, hz + 0.004)


func _make_pane(layer: int, _sc: float) -> void:
	var pane := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = _window * 2.0
	pane.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.55, 0.85, 0.95, 0.12)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	pane.material_override = m
	pane.layers = layer
	pane.position = _pane_at
	add_child(pane)
	_dot = MeshInstance3D.new()
	var dq := QuadMesh.new()
	dq.size = Vector2.ONE * _window.y * 0.16
	_dot.mesh = dq
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_texture = _dot_tex()
	dm.albedo_color = Color(1.0, 0.12, 0.08)
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dm.no_depth_test = true
	dm.render_priority = 2
	_dot.material_override = dm
	_dot.layers = layer
	add_child(_dot)


static var _dtex: Texture2D


static func _dot_tex() -> Texture2D:
	if _dtex == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var r := Vector2(x - 15.5, y - 15.5).length() / 15.5
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.6 - r * 2.0, 0.0, 1.0) + 0.35 * exp(-r * r * 6.0)))
		_dtex = ImageTexture.create_from_image(img)
	return _dtex


## A short tube scope on two rings.
func _scope(g: GKMesh, axis: float, at: float, ln: float, r: float, rail: float) -> void:
	var z0 := at - ln * 0.5
	var z1 := at + ln * 0.5
	g.lathe("alloy_black", Vector3(0, axis, z0), Vector3(0, axis, z1), [
		Vector2(0.0, r + 0.003), Vector2(0.035, r + 0.003), Vector2(0.045, r), Vector2(ln - 0.04, r), Vector2(ln - 0.025, r + 0.005), Vector2(ln, r + 0.005)], 20)
	g.cyl("glass_lens", Vector3(0, axis, z1 + 0.0005), Vector3(0, axis, z1 + 0.0015), r + 0.003, 20)    # the objective
	g.cyl("alloy_black", Vector3(0, axis + r - 0.002, at), Vector3(0, axis + r + 0.008, at), 0.007, 12)  # turret
	for rz in [at - ln * 0.22, at + ln * 0.22]:
		g.box("alloy_black", Vector3(0, (rail + axis) * 0.5, rz), Vector3(0.02, axis - rail, 0.014), 0.0015)
		g.cyl("alloy_black", Vector3(0, axis, rz - 0.007), Vector3(0, axis, rz + 0.007), r + 0.0025, 16)


## Flipped-up irons: a rear aperture ring on its leaf, a front post between ears.
func _irons(g: GKMesh, axis: float, rear: float, front: float, rail: float) -> void:
	g.box("alloy_black", Vector3(0, rail + 0.004, rear), Vector3(0.022, 0.008, 0.03), 0.001)
	# a ghost ring: a thin-walled aperture, the leaf stopping under it
	var ro := 0.0085
	var ri := 0.0068
	var leaf_top := axis - ro + 0.001
	g.box("alloy_black", Vector3(0, (rail + leaf_top) * 0.5, rear), Vector3(0.007, leaf_top - rail, 0.003), 0.0006)
	var seg := 20
	for k in seg:                                                                                                  # the ring as a band of short boxes
		var a0 := TAU * k / seg
		var c := Vector3(cos(a0) * (ro + ri) * 0.5, axis + sin(a0) * (ro + ri) * 0.5, rear)
		g.box("alloy_black", c, Vector3(ro - ri, TAU * ro / seg + 0.0004, 0.003), 0.0, Basis(Vector3.BACK, a0))
	g.box("alloy_black", Vector3(0, rail + 0.004, front), Vector3(0.022, 0.008, 0.026), 0.001)
	for sx in [-1.0, 1.0]:
		g.box("alloy_black", Vector3(sx * 0.0075, (rail + axis + 0.006) * 0.5, front), Vector3(0.003, axis + 0.006 - rail, 0.008), 0.0006)
	g.box("alloy_black", Vector3(0, (rail + axis) * 0.5, front), Vector3(0.0024, axis - rail, 0.0035))            # the post, its top on the sight line


## Each frame (reflex only): put the dot where the eye's line of sight crosses
## the pane, eased a little toward the pane's centre (parallax), and hide it
## when that point is off the glass. `eye_xf` is the camera in gun space.
func track(eye_xf: Transform3D) -> void:
	if _dot == null:
		return
	var o := eye_xf.origin
	var d := -eye_xf.basis.z
	if absf(d.z) < 0.05:
		_dot.visible = false
		return
	var t := (_pane_at.z - o.z) / d.z
	var hit := o + d * t
	var off := Vector2(hit.x - _pane_at.x, hit.y - _pane_at.y) * (1.0 - PARALLAX)
	_dot.visible = t > 0.0 and absf(off.x) < _window.x * 0.92 and absf(off.y) < _window.y * 0.92
	_dot.position = _pane_at + Vector3(off.x, off.y, 0.0005)
