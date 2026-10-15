class_name GKMesh
extends RefCounted
## Geometry collector for the Gauntlet Kit: primitives go in, one ArrayMesh
## comes out with one surface per material ROLE (the surface name is the
## role; GKMaterials turns roles into materials). No randomness here:
## builders that want variety pass in their own seeded RandomNumberGenerator,
## so the same parameters always give the same mesh.
##
##   var g := GKMesh.new()
##   g.box("polymer_olive", Vector3(0, 0.05, 0.2), Vector3(0.04, 0.06, 0.3), 0.006)
##   g.tube("gunmetal", [a, b], [0.01, 0.008], 12)
##   g.extrude("polymer_olive", outline, -0.02, 0.02, 0.004)     # side profile, thickness along x
##   var mesh := g.commit()
##
## Every primitive is placed through the current transform (push/pop; a
## mirrored transform is fine, windings flip to match), and
## takes an optional vertex tint (multiplied by the material, so one role can
## carry a darker part without a new material). UVs: a box projection in
## object space, so exported meshes texture sensibly in other tools.

const SMOOTH_DEG := 38.0          ## outline corners sharper than this keep a hard edge

var _surf := {}                   # role -> { v, n, c, uv }
var _stack: Array[Transform3D] = []
var xf := Transform3D.IDENTITY    ## current placement of everything added
var tint := Color.WHITE           ## current vertex tint


func push(t: Transform3D) -> void:
	_stack.append(xf)
	xf = xf * t


func pop() -> void:
	xf = _stack.pop_back()


func roles() -> PackedStringArray:
	return PackedStringArray(_surf.keys())


func triangle_count() -> int:
	var n := 0
	for r in _surf:
		n += (_surf[r].v as PackedVector3Array).size() / 3
	return n


func is_empty() -> bool:
	return _surf.is_empty()


# ----------------------------------------------------------------- low level

func _s(role: String) -> Dictionary:
	if not _surf.has(role):
		_surf[role] = { "v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "uv": PackedVector2Array() }
	return _surf[role]


static func _proj(p: Vector3, n: Vector3) -> Vector2:
	var a := n.abs()
	if a.x >= a.y and a.x >= a.z:
		return Vector2(p.z, p.y)
	if a.y >= a.z:
		return Vector2(p.x, p.z)
	return Vector2(p.x, p.y)


## One triangle, points and normals in local space (xf applied here).
## Winding: counter-clockwise seen from the front (Godot's front face is
## clockwise in screen space after its own flip; we emit CW for the front).
func tri(role: String, a: Vector3, b: Vector3, c: Vector3, na := Vector3.ZERO, nb := Vector3.ZERO, nc := Vector3.ZERO) -> void:
	var s := _s(role)
	if xf.basis.determinant() < 0.0:
		# a mirrored placement: keep the front face in front
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	var pa := xf * a
	var pb := xf * b
	var pc := xf * c
	var fn := (pc - pa).cross(pb - pa)
	if fn.length_squared() < 1e-14:
		return
	fn = fn.normalized()
	var nm := xf.basis.inverse().transposed()
	var ns := [na, nb, nc]
	var pts := [pa, pb, pc]
	for i in 3:
		var nv: Vector3 = ns[i]
		nv = fn if nv == Vector3.ZERO else (nm * nv).normalized()
		s.v.append(pts[i])
		s.n.append(nv)
		s.c.append(tint)
		s.uv.append(_proj(pts[i], fn))


## A quad a-b-c-d (in order round its edge), flat or with corner normals.
func quad(role: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ns: Array = []) -> void:
	if ns.size() == 4:
		tri(role, a, b, c, ns[0], ns[1], ns[2])
		tri(role, a, c, d, ns[0], ns[2], ns[3])
	else:
		tri(role, a, b, c)
		tri(role, a, c, d)


## A convex polygon, fanned from its first point.
func poly(role: String, pts: PackedVector3Array) -> void:
	for i in range(1, pts.size() - 1):
		tri(role, pts[0], pts[i], pts[i + 1])


# ----------------------------------------------------------------- solids

## Axis-aligned box (in the current frame), optionally chamfered on every edge.
func box(role: String, c: Vector3, size: Vector3, bevel := 0.0, basis := Basis.IDENTITY) -> void:
	push(Transform3D(basis, c))
	var h := size * 0.5
	if bevel <= 0.0:
		var p := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
			Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
		quad(role, p[0], p[1], p[2], p[3])   # -z
		quad(role, p[4], p[7], p[6], p[5])   # +z
		quad(role, p[0], p[3], p[7], p[4])   # -x
		quad(role, p[1], p[5], p[6], p[2])   # +x
		quad(role, p[3], p[2], p[6], p[7])   # +y
		quad(role, p[0], p[4], p[5], p[1])   # -y
	else:
		var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.45)   # past half, the inset turns inside out
		var o := PackedVector2Array([Vector2(-h.x + b, -h.y), Vector2(h.x - b, -h.y), Vector2(h.x, -h.y + b), Vector2(h.x, h.y - b),
			Vector2(h.x - b, h.y), Vector2(-h.x + b, h.y), Vector2(-h.x, h.y - b), Vector2(-h.x, -h.y + b)])
		extrude(role, o, -h.z, h.z, b, Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK))
	pop()


## A tube along a polyline, radius per point (0 = a cone point). Ring frames
## are parallel-transported so twisting paths stay clean. Ends are capped
## unless `caps` is false. `sides` sets the roundness.
func tube(role: String, pts: Array, radii: Variant, sides := 12, caps := true, ref := Vector3.UP, scale_y := 1.0) -> void:
	var n := pts.size()
	if n < 2:
		return
	var rs: Array = []
	for i in n:
		rs.append(float(radii[i]) if radii is Array or radii is PackedFloat32Array else float(radii))
	var tans: Array[Vector3] = []
	for i in n:
		var t: Vector3
		if i == 0:
			t = (pts[1] as Vector3) - (pts[0] as Vector3)
		elif i == n - 1:
			t = (pts[n - 1] as Vector3) - (pts[n - 2] as Vector3)
		else:
			t = ((pts[i + 1] as Vector3) - (pts[i] as Vector3)).normalized() + ((pts[i] as Vector3) - (pts[i - 1] as Vector3)).normalized()
		tans.append(t.normalized())
	var nrm := ref
	if absf(nrm.dot(tans[0])) > 0.95:
		nrm = Vector3.RIGHT if absf(tans[0].x) < 0.9 else Vector3.BACK
	var rings: Array = []          # each: [positions, normals]
	for i in n:
		var t: Vector3 = tans[i]
		nrm = (nrm - t * nrm.dot(t)).normalized()
		var bi := t.cross(nrm)
		var ps: Array[Vector3] = []
		var nn: Array[Vector3] = []
		# radius slope -> tilt the normals so cones shade right
		var dr := 0.0
		if i > 0 and i < n - 1:
			dr = (float(rs[i + 1]) - float(rs[i - 1])) / maxf(((pts[i + 1] as Vector3) - (pts[i - 1] as Vector3)).length(), 1e-5)
		elif i == 0:
			dr = (float(rs[1]) - float(rs[0])) / maxf(((pts[1] as Vector3) - (pts[0] as Vector3)).length(), 1e-5)
		else:
			dr = (float(rs[n - 1]) - float(rs[n - 2])) / maxf(((pts[n - 1] as Vector3) - (pts[n - 2] as Vector3)).length(), 1e-5)
		for k in sides:
			var a := TAU * (float(k) + 0.5) / float(sides)
			var radial := nrm * cos(a) + bi * sin(a) * scale_y
			ps.append((pts[i] as Vector3) + radial * float(rs[i]))
			nn.append((radial.normalized() - t * dr).normalized())
		rings.append([ps, nn])
	for i in n - 1:
		var p0: Array = rings[i][0]
		var n0: Array = rings[i][1]
		var p1: Array = rings[i + 1][0]
		var n1: Array = rings[i + 1][1]
		for k in sides:
			var k2 := (k + 1) % sides
			if float(rs[i]) <= 1e-6 and float(rs[i + 1]) <= 1e-6:
				continue
			quad(role, p0[k], p1[k], p1[k2], p0[k2], [n0[k], n1[k], n1[k2], n0[k2]])
	if caps:
		if float(rs[0]) > 1e-6:
			var c0: Vector3 = pts[0]
			for k in sides:
				tri(role, c0, rings[0][0][k], rings[0][0][(k + 1) % sides], -tans[0], -tans[0], -tans[0])
		if float(rs[n - 1]) > 1e-6:
			var c1: Vector3 = pts[n - 1]
			for k in sides:
				tri(role, c1, rings[n - 1][0][(k + 1) % sides], rings[n - 1][0][k], tans[n - 1], tans[n - 1], tans[n - 1])


## Skin a run of cross-sections: how stocks, grips, forends and fuel tanks
## get their rounded, swelling shapes. Each station:
##   at  Transform3D: origin = the section's centre, basis.z = along the run,
##       basis.x = across (width), basis.y = the section's up
##   w   half width;  t / d  extent up / down from the centre
##   p   squareness: 2 = ellipse, 3-4 = rounded box, 8+ = nearly square
## Normals come from the skinned surface itself, so swells shade smoothly.
static func station(at: Vector3, w: float, t: float, d: float, p := 3.0, basis := Basis.IDENTITY) -> Dictionary:
	return { "at": Transform3D(basis, at), "w": w, "t": t, "d": d, "p": p }


func loft(role: String, stations: Array, sides := 16, caps := true) -> void:
	var n := stations.size()
	if n < 2:
		return
	var P: Array = []
	for s in stations:
		var t: Transform3D = s.at
		var e := 2.0 / maxf(float(s.get("p", 2.0)), 0.5)
		var hand := -1.0 if t.basis.determinant() < 0.0 else 1.0   # a left-handed frame: walk the section the other way
		var ring: Array[Vector3] = []
		for k in sides:
			var a := TAU * (float(k) + 0.5) / float(sides)
			var c := cos(a)
			var sn := sin(a)
			var x := float(s.w) * signf(c) * pow(absf(c), e) * hand
			var y := (float(s.t) if sn > 0.0 else float(s.d)) * signf(sn) * pow(absf(sn), e)
			ring.append(t * Vector3(x, y, 0.0))
		P.append(ring)
	var N: Array = []
	for i in n:
		var ring_n: Array[Vector3] = []
		var ia := maxi(i - 1, 0)
		var ib := mini(i + 1, n - 1)
		for k in sides:
			var around: Vector3 = (P[i][(k + 1) % sides] as Vector3) - (P[i][(k - 1 + sides) % sides] as Vector3)
			var along: Vector3 = (P[ib][k] as Vector3) - (P[ia][k] as Vector3)
			var nv := around.cross(along)
			ring_n.append(nv.normalized() if nv.length_squared() > 1e-16 else Vector3.UP)
		N.append(ring_n)
	for i in n - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			quad(role, P[i][k], P[i + 1][k], P[i + 1][k2], P[i][k2], [N[i][k], N[i + 1][k], N[i + 1][k2], N[i][k2]])
	if caps:
		for end in [0, n - 1]:
			var ring: Array = P[end]
			var c := Vector3.ZERO
			for v in ring:
				c += v
			c /= float(sides)
			var ax: Vector3 = (stations[end].at as Transform3D).basis.z.normalized()
			if end == 0:
				for k in sides:
					tri(role, c, ring[k], ring[(k + 1) % sides], -ax, -ax, -ax)
			else:
				for k in sides:
					tri(role, c, ring[(k + 1) % sides], ring[k], ax, ax, ax)


func cyl(role: String, a: Vector3, b: Vector3, r: float, sides := 12, caps := true) -> void:
	tube(role, [a, b], [r, r], sides, caps)


## A solid of revolution round the a->b axis. `prof` = (distance from a, radius).
func lathe(role: String, a: Vector3, b: Vector3, prof: Array, sides := 16, caps := true) -> void:
	var d := (b - a).normalized()
	var pts: Array = []
	var rs: Array = []
	for q in prof:
		var v: Vector2 = q
		pts.append(a + d * v.x)
		rs.append(v.y)
	tube(role, pts, rs, sides, caps)


func sphere(role: String, c: Vector3, r: float, seg := 12, squash := Vector3.ONE) -> void:
	var rings := maxi(seg / 2, 3)
	for i in rings:
		var t0 := PI * float(i) / float(rings)
		var t1 := PI * float(i + 1) / float(rings)
		for k in seg:
			var a0 := TAU * float(k) / float(seg)
			var a1 := TAU * float(k + 1) / float(seg)
			var q := [Vector3(sin(t0) * cos(a0), cos(t0), sin(t0) * sin(a0)), Vector3(sin(t0) * cos(a1), cos(t0), sin(t0) * sin(a1)),
				Vector3(sin(t1) * cos(a1), cos(t1), sin(t1) * sin(a1)), Vector3(sin(t1) * cos(a0), cos(t1), sin(t1) * sin(a0))]
			var ps: Array = []
			var ns: Array = []
			for v in q:
				ps.append(c + (v as Vector3) * squash * r)
				ns.append(((v as Vector3) / squash).normalized())
			quad(role, ps[3], ps[2], ps[1], ps[0], [ns[3], ns[2], ns[1], ns[0]])


## A flat outline (2D, any winding, no holes) extruded between depth z0 and
## z1, every rim chamfered by `bevel`. `plane` maps (outline x, outline y,
## depth) into the current frame: the default puts the outline in the
## (forward +Z, up +Y) side plane with thickness along x, which is how gun
## stocks and receivers are drawn. `half` (optional Callable(Vector2) ->
## float) overrides the half thickness per outline point, for parts that
## swell (a stock's cheek piece, a grip's palm swell); z0/z1 are then ignored.
func extrude(role: String, outline: PackedVector2Array, z0: float, z1: float, bevel := 0.0, plane := Basis(Vector3.BACK, Vector3.UP, Vector3.RIGHT), half := Callable()) -> void:
	var o := outline
	if o.size() < 3:
		return
	if plane.determinant() < 0.0:
		# a left-handed mapping: flip depth so windings come out front-facing
		plane = Basis(plane.x, plane.y, -plane.z)
		var t0 := z0
		z0 = -z1
		z1 = -t0
	if Geometry2D.is_polygon_clockwise(o):
		o = o.duplicate()
		o.reverse()
	var n := o.size()
	# outward edge normals and per-vertex miter
	var en: Array[Vector2] = []
	for i in n:
		var e := o[(i + 1) % n] - o[i]
		en.append(Vector2(e.y, -e.x).normalized())
	var inset := PackedVector2Array()
	inset.resize(n)
	var smooth: Array[bool] = []
	var vn: Array[Vector2] = []
	for i in n:
		var a := en[(i - 1 + n) % n]
		var b := en[i]
		var m := (a + b).normalized()
		var cs := maxf(m.dot(b), 0.35)
		inset[i] = o[i] - m * (bevel / cs)
		smooth.append(rad_to_deg(a.angle_to(b)) < SMOOTH_DEG and rad_to_deg(a.angle_to(b)) > -SMOOTH_DEG)
		vn.append(m)
	var hz := func(i: int, back: bool) -> float:
		if half.is_valid():
			var h: float = half.call(o[i])
			return -h if back else h
		return z0 if back else z1
	var P := func(v: Vector2, z: float) -> Vector3:
		return plane.x * v.x + plane.y * v.y + plane.z * z
	var D := func(v: Vector2, z: float) -> Vector3:
		return (plane.x * v.x + plane.y * v.y + plane.z * z).normalized()
	var b := bevel if bevel > 0.0 else 0.0
	# rings: back inset, back full, front full, front inset
	var r0: Array[Vector3] = []
	var r1: Array[Vector3] = []
	var r2: Array[Vector3] = []
	var r3: Array[Vector3] = []
	for i in n:
		var zb: float = hz.call(i, true)
		var zf: float = hz.call(i, false)
		r0.append(P.call(inset[i] if b > 0.0 else o[i], zb))
		r1.append(P.call(o[i], zb + b))
		r2.append(P.call(o[i], zf - b))
		r3.append(P.call(inset[i] if b > 0.0 else o[i], zf))
	var wall_n := func(i: int, edge: int) -> Vector3:
		# the outline normal at vertex i, as used by the face along `edge`
		var use: Vector2 = vn[i] if smooth[i] else en[edge]
		return D.call(use, 0.0)
	for i in n:
		var j := (i + 1) % n
		var na: Vector3 = wall_n.call(i, i)
		var nb: Vector3 = wall_n.call(j, i)
		quad(role, r1[i], r2[i], r2[j], r1[j], [na, na, nb, nb])
		if b > 0.0:
			# a rolled edge: the rim side leans to the wall, the cap side to the cap
			var fz: Vector3 = plane.z.normalized()
			quad(role, r0[i], r1[i], r1[j], r0[j], [(-fz + na * 0.4).normalized(), (na - fz * 0.4).normalized(),
				(nb - fz * 0.4).normalized(), (-fz + nb * 0.4).normalized()])
			quad(role, r2[i], r3[i], r3[j], r2[j], [(na + fz * 0.4).normalized(), (fz + na * 0.4).normalized(),
				(fz + nb * 0.4).normalized(), (nb + fz * 0.4).normalized()])
	# caps
	var cap := inset if b > 0.0 else o
	var idx := Geometry2D.triangulate_polygon(cap)
	if idx.is_empty():
		idx = Geometry2D.triangulate_polygon(o)
	if idx.is_empty():
		push_warning("GKMesh.extrude: outline could not be triangulated (%d points)" % n)
		return
	var cap_n := _cap_normals(idx, r0, n, true)
	var cap_f := _cap_normals(idx, r3, n, false)
	for t in range(0, idx.size(), 3):
		var i0 := idx[t]
		var i1 := idx[t + 1]
		var i2 := idx[t + 2]
		# caps face out of the solid: the back one toward -depth, the front toward +depth
		tri(role, r0[i0], r0[i1], r0[i2], -cap_n[i0], -cap_n[i1], -cap_n[i2])
		tri(role, r3[i0], r3[i2], r3[i1], -cap_f[i0], -cap_f[i2], -cap_f[i1])


func _cap_normals(idx: PackedInt32Array, ring: Array[Vector3], n: int, back: bool) -> Array[Vector3]:
	var acc: Array[Vector3] = []
	acc.resize(n)
	acc.fill(Vector3.ZERO)
	for t in range(0, idx.size(), 3):
		var a := ring[idx[t]]
		var b := ring[idx[t + 1]]
		var c := ring[idx[t + 2]]
		var fn := (c - a).cross(b - a) if not back else (b - a).cross(c - a)
		for k in 3:
			acc[idx[t + k]] += fn
	for i in n:
		acc[i] = acc[i].normalized() if acc[i].length_squared() > 1e-16 else Vector3.ZERO
	return acc


# ----------------------------------------------------------------- output

## The mesh: one surface per role, named after it (sorted, so surface order
## is stable). Returns null if nothing was added.
func commit() -> ArrayMesh:
	if _surf.is_empty():
		return null
	var m := ArrayMesh.new()
	var keys := _surf.keys()
	keys.sort()
	for r in keys:
		var s: Dictionary = _surf[r]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = s.v
		arr[Mesh.ARRAY_NORMAL] = s.n
		arr[Mesh.ARRAY_COLOR] = s.c
		arr[Mesh.ARRAY_TEX_UV] = s.uv
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_name(m.get_surface_count() - 1, str(r))
	return m
