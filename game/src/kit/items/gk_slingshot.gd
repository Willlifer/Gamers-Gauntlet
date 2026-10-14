class_name GKSlingshot
extends GKDef
## Wooden slingshot after the reference (design/ref/kit/slingshot.jpg): a
## natural forked branch (a straight handle, the fork a little under half
## way up, two arms splaying from a swollen crotch, the left a touch longer),
## dark walnut-brown with long streaky grain, the cut ends pale, black cord
## lashed round each tip, thin cord bands to a leather pouch that cups a
## white felt ball.
## Frame: origin = the left fist on the handle (held like a bow), +Y up the
## handle to the fork, +Z the shot direction (the fork faces it), the arms
## spread across x. `draw` pulls the pouch back toward the shooter (-Z); at
## rest `drape` lets it hang off to one side as in the photo.

func id() -> String:
	return "slingshot"


func title() -> String:
	return "Slingshot"


func version() -> int:
	return 1


func schema() -> Array[Dictionary]:
	return [
		pf("scale", "Scale", "Fit", 1.3, 0.5, 2.5, 0.01),
		pf("handle", "Handle length (m)", "Shape", 0.112, 0.08, 0.18),
		pf("arms", "Arm length (m)", "Shape", 0.118, 0.07, 0.15),
		pf("splay_l", "Left arm splay (deg)", "Shape", 31.0, 10.0, 40.0, 0.5),
		pf("splay_r", "Right arm splay (deg)", "Shape", 17.0, 10.0, 40.0, 0.5),
		pf("thick", "Wood radius (m)", "Shape", 0.0118, 0.008, 0.018),
		pi("seed", "Branch seed", "Shape", 7, 0, 999),
		pf("draw", "Draw 0-1", "Pose", 0.0, 0.0, 1.0, 0.01),
		pf("drape", "Rest drape -1..1", "Pose", -1.0, -1.0, 1.0, 0.01),
		pb("ball", "Ball in pouch", "Kit", true),
	]


func presets() -> Dictionary:
	return {
		"Reference": {},
		"Drawn": { "draw": 1.0 },
		"Hanging": { "drape": 0.0 },
		"Hunter": { "thick": 0.015, "splay_l": 32.0, "splay_r": 30.0, "seed": 41 },
	}


func _build(p: Dictionary) -> GKAsset:
	var a := GKAsset.new()
	var s: float = p.scale
	var g := GKMesh.new()
	g.push(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), Vector3.ZERO))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.seed)
	var r: float = p.thick
	var hl: float = p.handle
	var fork := Vector3(0, hl * 0.4, 0)             # the crotch, above the fist
	var base := Vector3(0, -hl * 0.6, 0)
	# handle: straight, a little irregular, thicker toward the crotch
	var hpts: Array = []
	var hrs: Array = []
	for k in 7:
		var t := k / 6.0
		var wob := Vector3((rng.randf() - 0.5) * 0.0012, 0, (rng.randf() - 0.5) * 0.0012)
		hpts.append(base.lerp(fork + Vector3(0, r * 0.8, 0), t) + wob)
		hrs.append(r * (0.95 + 0.14 * t) * (1.0 + (rng.randf() - 0.5) * 0.04))
	g.tube("wood_branch", hpts, hrs, 16, false)
	g.lathe("wood_end", base + Vector3(0, -0.0032, 0), base + Vector3(0, 0.0005, 0), [Vector2(0, r * 0.9), Vector2(0.0037, r * 0.95)], 16)
	# arms: each a gently bowed branch out of the crotch, cut square at the tip
	var tips: Array[Vector3] = []
	for side: float in [-1.0, 1.0]:
		var ang := deg_to_rad(float(p.splay_l) if side < 0.0 else float(p.splay_r))
		var L: float = float(p.arms) * (1.1 if side < 0.0 else 0.88)
		var d := Vector3(side * sin(ang), cos(ang), 0)
		var start := fork + Vector3(side * r * 0.25, -r * 0.6, 0)
		var tip := start + d * L
		var mid := start.lerp(tip, 0.5) + Vector3(side * 0.007, 0, (rng.randf() - 0.5) * 0.003)
		var pts: Array = [start, start.lerp(mid, 0.5), mid, mid.lerp(tip, 0.5), tip]
		var rs: Array = [r * 1.12, r * 1.0, r * 0.9, r * 0.83, r * 0.78]
		g.tube("wood_branch", pts, rs, 16, false)
		var td := (tip - mid).normalized()
		g.lathe("wood_end", tip - td * 0.0005, tip + td * 0.0028, [Vector2(0, r * 0.82), Vector2(0.0033, r * 0.76)], 16)
		# lashing: a bulged black wrap of cord turns, just under the tip
		var w0 := tip - td * 0.0145
		var prof: Array = [Vector2(0, r * 0.98)]
		for k in 5:
			var t := 0.0015 + k * 0.0022
			prof.append(Vector2(t, r * (1.06 + 0.03 * sin(PI * k / 4.0)) + (0.0005 if k % 2 == 0 else 0.0)))
		prof.append(Vector2(0.0125, r * 0.97))
		g.lathe("leather_black", w0, w0 + td * 0.0125, prof, 16)
		tips.append(w0 + td * 0.006)
		# a bark knot or two along the arm
		g.sphere("wood_branch", start.lerp(tip, 0.35 + rng.randf() * 0.2) + Vector3(side * r * 0.75, 0, r * 0.3), r * 0.42, 8)
	# the crotch: a swelling where the three branches meet
	var up := Basis(Vector3.RIGHT, Vector3.BACK, Vector3.UP)
	g.loft("wood_branch", [
		GKMesh.station(fork + Vector3(0, -r * 2.6, 0), r * 0.98, r * 0.98, r * 0.98, 2.0, up),
		GKMesh.station(fork + Vector3(0, -r * 1.2, 0), r * 1.38, r * 1.16, r * 1.16, 2.0, up),
		GKMesh.station(fork + Vector3(0, r * 0.2, 0), r * 1.75, r * 1.12, r * 1.12, 2.0, up),
		GKMesh.station(fork + Vector3(0, r * 0.8, 0), r * 1.1, r * 0.75, r * 0.75, 2.0, up),
		GKMesh.station(fork + Vector3(0, r * 1.05, 0), r * 0.45, r * 0.4, r * 0.4, 2.0, up)], 16, true)
	# pouch position: drawn back, or hanging off to one side at rest
	var draw: float = p.draw
	var drape: float = p.drape
	var reach: float = float(p.arms) * 0.75
	var rest := Vector3(drape * 0.115, fork.y + reach * 0.55 - absf(drape) * 0.004, 0.012 * absf(drape) - 0.03 * (1.0 - absf(drape)))
	var pulled := Vector3(0, fork.y + reach * 0.85, -0.62)
	var pouch := rest.lerp(pulled, draw)
	var slack := 1.0 - draw
	# the pouch's frame: at rest its face looks at the viewer (+z), drawn it
	# looks where it will shoot (the fork's middle)
	var aim := fork + Vector3(0, reach, 0) - pouch
	var fwd := (Vector3.BACK.lerp(aim.normalized() if aim.length() > 0.001 else Vector3.BACK, draw)).normalized()
	var to_fork := (fork + Vector3(0, reach, 0) - pouch) * Vector3(1, 0.3, 0)
	var side_v := (to_fork - fwd * to_fork.dot(fwd)).normalized() if to_fork.length() > 0.01 else Vector3.RIGHT
	var up_v := fwd.cross(side_v).normalized()
	var br := 0.0125
	# an oval leather cradle, cupped round the ball's back, two punched ears
	var ra := 0.021
	var rb := 0.0148
	var rings := 4
	var segs := 20
	var P := func(rr: float, an: float, lift: float) -> Vector3:
		var cup := -br * 0.55 + br * 0.95 * rr * rr
		return pouch + side_v * (ra * rr * cos(an)) + up_v * (rb * rr * sin(an)) + fwd * (cup + lift)
	for i in rings:
		var r0 := i / float(rings)
		var r1 := (i + 1) / float(rings)
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var n0 := (-fwd + side_v * cos(a0) * r0 * 0.6 + up_v * sin(a0) * r0 * 0.6).normalized()
			var n1 := (-fwd + side_v * cos(a0) * r1 * 0.6 + up_v * sin(a0) * r1 * 0.6).normalized()
			var n2 := (-fwd + side_v * cos(a1) * r1 * 0.6 + up_v * sin(a1) * r1 * 0.6).normalized()
			var n3 := (-fwd + side_v * cos(a1) * r0 * 0.6 + up_v * sin(a1) * r0 * 0.6).normalized()
			# the back (outside) and the front (inside, toward the ball)
			g.quad("leather_black", P.call(r0, a0, 0.0), P.call(r1, a0, 0.0), P.call(r1, a1, 0.0), P.call(r0, a1, 0.0), [n0, n1, n2, n3])
			g.quad("leather_black", P.call(r0, a1, 0.0015), P.call(r1, a1, 0.0015), P.call(r1, a0, 0.0015), P.call(r0, a0, 0.0015), [-n3, -n2, -n1, -n0])
	var ends: Array[Vector3] = [P.call(0.86, 0.0, 0.001), P.call(0.86, PI, 0.001)]
	for e in ends:
		g.cyl("rubber", e - fwd * 0.0008, e + fwd * 0.0025, 0.0024, 10)        # the punched hole
	if p.ball:
		g.sphere("felt_white", pouch + fwd * (br * 0.35), br, 18)
	# bands: thin cords from the lashing to each eyelet, nearly straight
	# tips[0] is the left arm: it takes the pouch end further left
	var e_left := ends[0] if ends[0].x <= ends[1].x else ends[1]
	var e_right := ends[1] if ends[0].x <= ends[1].x else ends[0]
	for i in 2:
		var t0: Vector3 = tips[i] + Vector3(0, 0, signf(pouch.z - tips[i].z + 0.0001) * r * 1.02)
		var edge := e_left if i == 0 else e_right
		var pts: Array = []
		for k in 9:
			var t := k / 8.0
			var q := t0.lerp(edge, t)
			q.y -= sin(t * PI) * 0.005 * slack
			pts.append(q)
		g.tube("leather_black", pts, 0.0038, 8, true, Vector3.BACK, 0.7)
	g.pop()
	a.add_part("body", g.commit())
	a.markers = {
		"grip": Transform3D.IDENTITY,
		"pouch": Transform3D(Basis.IDENTITY, pouch * s),
		"muzzle": Transform3D(Basis.IDENTITY, (fork + Vector3(0, reach, 0.0)) * s),
		"support": Transform3D(Basis.IDENTITY, pouch * s),
	}
	a.meta = { "class": "slingshot", "hands": "bow", "socket": "socket_offhand_l", "projectile": "stone",
		"length": (float(p.arms) + hl) * s, "notes": "Held like a bow: left fist on the handle, the right hand draws the pouch marker." }
	return a
