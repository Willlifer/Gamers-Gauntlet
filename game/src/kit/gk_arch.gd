class_name GKArch
extends RefCounted
## Architecture pieces for kit environments, shared by every map: blocks that
## also collide, wall openings (windows, arches, doors), frames, sills and
## shutters, parapets, cables that sag, sign text.
## Openings are dressing ON a solid wall face (walls are solid blocks, so
## anything set into them would be hidden): a dark pane a few millimetres
## proud of the face, a darker margin round it for the reveal's shadow, the
## frame and sill standing out in front. Builders write
## geometry into a GKMesh and collision into a GKAsset, both optional.
##
## Wall frame: openings are placed on a face by its outward normal (one of
## the four horizontal axes) and a point on the face; inside, x runs along
## the wall (to the right seen from outside), y is up, z points out.

## The basis whose z is `normal` (horizontal), y up, x along the wall.
static func face_basis(normal: Vector3) -> Basis:
	var z := normal.normalized()
	var x := Vector3.UP.cross(z).normalized()
	return Basis(x, Vector3.UP, z)


## A solid block between two corners; collides unless `collide` is false.
static func block(g: GKMesh, a: GKAsset, role: String, lo: Vector3, hi: Vector3, bevel := 0.0, collide := true) -> void:
	var c := (lo + hi) * 0.5
	var s := (hi - lo).abs()
	if g != null:
		g.box(role, c, s, bevel)
	if a != null and collide:
		a.add_box_xf((g.xf if g != null else Transform3D.IDENTITY) * Transform3D(Basis.IDENTITY, c), s)


## An invisible wall (collision only): the map's edges, placed by `xf`
## (the map's own placement, so it mirrors and scales with the geometry).
static func barrier(a: GKAsset, lo: Vector3, hi: Vector3, xf := Transform3D.IDENTITY) -> void:
	a.add_box_xf(xf * Transform3D(Basis.IDENTITY, (lo + hi) * 0.5), (hi - lo).abs(), true)


## A window on a face: dark recess, frame, sill, optional shutters/bars.
## opts: frame (role), glass (role), depth, sill (bool), shutters (role or ""),
## bars (int), lintel (role or ""), mullion (bool), out (m: stand off a
## cladding layer that sits proud of the wall)
static func window(g: GKMesh, at: Vector3, normal: Vector3, w: float, h: float, opts := {}) -> void:
	g.push(Transform3D(face_basis(normal), at + normal.normalized() * float(opts.get("out", 0.0))))
	var frame: String = opts.get("frame", "window_frame")
	var glass: String = opts.get("glass", "window_dark")
	# the pane, and round it a darker band: the reveal's shadow
	g.box(glass, Vector3(0, 0, 0.006), Vector3(w, h, 0.012))
	g.tint = Color(0.55, 0.55, 0.55)
	var rv := 0.06
	var rev_role: String = opts.get("reveal", "")
	if rev_role != "":
		g.box(rev_role, Vector3(0, h * 0.5 + rv * 0.5, 0.004), Vector3(w + rv * 2.0, rv, 0.008))
		g.box(rev_role, Vector3(-w * 0.5 - rv * 0.5, 0, 0.004), Vector3(rv, h, 0.008))
		g.box(rev_role, Vector3(w * 0.5 + rv * 0.5, 0, 0.004), Vector3(rv, h, 0.008))
	g.tint = Color.WHITE
	var ft := 0.05
	if frame != "":
		g.box(frame, Vector3(0, h * 0.5 - ft * 0.5, 0.025), Vector3(w, ft, 0.04))
		g.box(frame, Vector3(0, -h * 0.5 + ft * 0.5, 0.025), Vector3(w, ft, 0.04))
		g.box(frame, Vector3(-w * 0.5 + ft * 0.5, 0, 0.025), Vector3(ft, h, 0.04))
		g.box(frame, Vector3(w * 0.5 - ft * 0.5, 0, 0.025), Vector3(ft, h, 0.04))
		if opts.get("mullion", false):
			g.box(frame, Vector3(0, 0, 0.022), Vector3(ft * 0.7, h, 0.035))
			g.box(frame, Vector3(0, h * 0.12, 0.022), Vector3(w, ft * 0.7, 0.035))
	if opts.get("sill", true):
		g.box(str(opts.get("sill_role", "sandstone_trim")), Vector3(0, -h * 0.5 - 0.04, 0.03), Vector3(w + 0.14, 0.08, 0.16), 0.015)
	var lintel: String = opts.get("lintel", "")
	if lintel != "":
		g.box(lintel, Vector3(0, h * 0.5 + 0.08, 0.015), Vector3(w + 0.2, 0.16, 0.06), 0.01)
	var bars: int = opts.get("bars", 0)
	for k in bars:
		var x := -w * 0.5 + w * (k + 1) / float(bars + 1)
		g.cyl("iron_dark", Vector3(x, -h * 0.5, 0.06), Vector3(x, h * 0.5, 0.06), 0.012, 6)
	var sh: String = opts.get("shutters", "")
	if sh != "":
		var open: float = opts.get("shutter_open", 0.85)
		for sx: float in [-1.0, 1.0]:
			# hinged on the outer edge, swung out toward the wall
			var hinge := Vector3(sx * w * 0.5, 0, 0.05)
			var ang := sx * open * PI * 0.5
			var leaf := Basis(Vector3.UP, ang)
			var c := hinge + leaf * Vector3(-sx * w * 0.25, 0, 0.0)
			g.box(sh, c, Vector3(w * 0.5, h, 0.035), 0.006, leaf)
			for k in 4:
				var y := -h * 0.5 + h * (k + 0.5) / 4.0
				g.box(sh, c + leaf * Vector3(0, y - 0.0, 0.02), Vector3(w * 0.46, 0.03, 0.012), 0.0, leaf)
	g.pop()


## Outline of an arched opening (flat bottom, round top), centred on x,
## from y=0 up to `h` at the crown.
static func arch_outline(w: float, h: float, seg := 12) -> PackedVector2Array:
	var r := w * 0.5
	var spring := h - r
	var o := PackedVector2Array([Vector2(-r, 0), Vector2(r, 0)])
	for k in seg + 1:
		var a := PI * k / float(seg)
		o.append(Vector2(r * cos(a), spring + r * sin(a)))
	return o


## An arched window or doorway: recess panel, a stone surround that follows
## the arch, optional bars or a door leaf.
static func arch(g: GKMesh, at: Vector3, normal: Vector3, w: float, h: float, opts := {}) -> void:
	g.push(Transform3D(face_basis(normal), at))
	var back: String = opts.get("glass", "window_dark")
	var o := arch_outline(w, h)
	g.extrude(back, o, 0.0, 0.01, 0.0, Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK))
	var rev: String = opts.get("reveal", "")
	if rev != "":
		# the reveal's shadow: a darker band hugging the arch
		g.tint = Color(0.6, 0.6, 0.6)
		var outer := arch_outline(w + 0.14, h + 0.07)
		var band := Geometry2D.clip_polygons(outer, o)
		for poly in band:
			if not Geometry2D.is_polygon_clockwise(poly):
				g.extrude(rev, poly, 0.0, 0.006, 0.0, Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK))
		g.tint = Color.WHITE
	var sur: String = opts.get("surround", "")
	if sur != "":
		var pts: Array = []
		var r := w * 0.5 + 0.09
		var spring := h - w * 0.5
		pts.append(Vector3(-r, 0, 0.03))
		for k in 13:
			var a := PI - PI * k / 12.0
			pts.append(Vector3(r * cos(a), spring + r * sin(a), 0.03))
		pts.append(Vector3(r, 0, 0.03))
		g.tube(sur, pts, 0.09, 6, true, Vector3.BACK, 0.6)
	var door: String = opts.get("door", "")
	if door != "":
		var planks := maxi(int(w / 0.22), 3)
		for k in planks:
			var x0 := -w * 0.5 + w * k / float(planks)
			var pw := w / float(planks) - 0.012
			var sub := PackedVector2Array()
			for v in o:
				sub.append(Vector2(clampf(v.x, x0, x0 + pw), v.y))
			g.tint = Color.WHITE.darkened(0.08 * float(k % 3))
			var clipped := Geometry2D.intersect_polygons(o, PackedVector2Array([Vector2(x0, -0.01), Vector2(x0 + pw, -0.01), Vector2(x0 + pw, h + 0.1), Vector2(x0, h + 0.1)]))
			if not clipped.is_empty():
				g.extrude(door, clipped[0], 0.012, 0.05, 0.006, Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK))
		g.tint = Color.WHITE
		for y in [h * 0.2, h * 0.55]:
			g.box("iron_dark", Vector3(0, y, 0.058), Vector3(w * 0.9, 0.05, 0.015))
	var bars: int = opts.get("bars", 0)
	for k in bars:
		var x := -w * 0.5 + w * (k + 1) / float(bars + 1)
		var top := sqrt(maxf((w * 0.5) * (w * 0.5) - x * x, 0.0)) + h - w * 0.5
		g.cyl("iron_dark", Vector3(x, 0, 0.05), Vector3(x, top, 0.05), 0.014, 6)
	g.pop()


## A rectangular plank door (or a pair) set into a face, with a frame.
static func door(g: GKMesh, at: Vector3, normal: Vector3, w: float, h: float, role := "wood_door", pair := true, frame := "sandstone_trim") -> void:
	g.push(Transform3D(face_basis(normal), at))
	var depth := -0.03                 # leaves stand just proud of the face
	var planks := maxi(int(w / 0.2), 3)
	for k in planks:
		var x := -w * 0.5 + (k + 0.5) * w / float(planks)
		g.tint = Color.WHITE.darkened(0.06 * float((k * 7) % 3))
		g.box(role, Vector3(x, h * 0.5, -depth), Vector3(w / float(planks) - 0.01, h, 0.05), 0.004)
	g.tint = Color.WHITE
	for y in [0.35, h * 0.5, h - 0.35]:
		g.box(role, Vector3(0, y, -depth + 0.035), Vector3(w * 0.96, 0.1, 0.03), 0.004)
	if pair:
		g.box("iron_dark", Vector3(0, h * 0.5, -depth + 0.05), Vector3(0.03, h, 0.02))
	for sx in [-1.0, 1.0]:
		g.box("iron_dark", Vector3(sx * 0.08, h * 0.48, -depth + 0.06), Vector3(0.025, 0.12, 0.025))
	if frame != "":
		g.box(frame, Vector3(-w * 0.5 - 0.06, h * 0.5, 0.04), Vector3(0.14, h + 0.06, 0.12), 0.012)
		g.box(frame, Vector3(w * 0.5 + 0.06, h * 0.5, 0.04), Vector3(0.14, h + 0.06, 0.12), 0.012)
		g.box(frame, Vector3(0, h + 0.09, 0.04), Vector3(w + 0.26, 0.18, 0.14), 0.012)
	g.pop()


## A hanging cable from a to b, sagging `sag` metres at the middle.
static func cable(g: GKMesh, a: Vector3, b: Vector3, sag: float, r := 0.012, role := "cable", seg := 14) -> void:
	var pts: Array = []
	for k in seg + 1:
		var t := k / float(seg)
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		pts.append(p)
	g.tube(role, pts, r, 5, false)


## Flat text standing on a face (sign lettering): glyph outlines from the
## fallback font, `size` = cap height in metres, extruded `depth` out of the
## face. Centred on `at`.
static func text(g: GKMesh, role: String, s: String, at: Vector3, normal: Vector3, size: float, depth := 0.01) -> void:
	var tm := TextMesh.new()
	tm.text = s
	tm.font = ThemeDB.fallback_font
	tm.font_size = 64
	tm.pixel_size = size / 46.0
	tm.depth = depth
	tm.curve_step = 2.0
	var arr := tm.get_mesh_arrays()
	if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
		return
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	g.push(Transform3D(face_basis(normal), at + normal.normalized() * depth * 0.5))
	if g.xf.basis.determinant() < 0.0:
		g.push(Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO))   # read the right way round in a mirror
	else:
		g.push(Transform3D.IDENTITY)
	if idx.is_empty():
		for i in range(0, vs.size(), 3):
			g.tri(role, vs[i], vs[i + 1], vs[i + 2], ns[i], ns[i + 1], ns[i + 2])
	else:
		for i in range(0, idx.size(), 3):
			g.tri(role, vs[idx[i]], vs[idx[i + 1]], vs[idx[i + 2]], ns[idx[i]], ns[idx[i + 1]], ns[idx[i + 2]])
	g.pop()
	g.pop()


## A parapet round a rectangle (x0..x1, z0..z1) standing on `y`: wall of
## `thick`, height `h`, a cap that overhangs both faces.
static func parapet(g: GKMesh, a: GKAsset, x0: float, x1: float, z0: float, z1: float, y: float, h: float, thick: float, role: String, cap: String) -> void:
	var sides := [[Vector3(x0, y, z0), Vector3(x1, y + h, z0 + thick)], [Vector3(x0, y, z1 - thick), Vector3(x1, y + h, z1)],
		[Vector3(x0, y, z0 + thick), Vector3(x0 + thick, y + h, z1 - thick)], [Vector3(x1 - thick, y, z0 + thick), Vector3(x1, y + h, z1 - thick)]]
	for sd in sides:
		var lo: Vector3 = sd[0]
		var hi: Vector3 = sd[1]
		block(g, a, role, lo, hi)
		g.box(cap, Vector3((lo.x + hi.x) * 0.5, y + h + 0.03, (lo.z + hi.z) * 0.5), (hi - lo).abs() * Vector3(1, 0, 1) + Vector3(0.08, 0.06, 0.08), 0.01)
