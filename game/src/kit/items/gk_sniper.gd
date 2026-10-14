class_name GKSniper
extends GKDef
## Bolt-action sniper rifle after the reference (design/ref/kit/sniper.jpg):
## a long thin free-floated barrel, a round receiver with the bolt knob on the
## right, an olive fibreglass tactical stock (deep flat forend, near-vertical
## grip, straight high comb, black cheek hardware and recoil pad), a 1-inch
## scope on a rail, a bipod on the forend stud.
## Modelled at real size in metres in the weapon frame (GKAsset), then scaled
## by `scale` to the 2.2 m Black | White body.

func id() -> String:
	return "sniper"


func title() -> String:
	return "Sniper rifle"


func version() -> int:
	return 1


func schema() -> Array[Dictionary]:
	return [
		pf("scale", "Scale", "Fit", 1.25, 0.5, 2.0, 0.01),
		pf("barrel", "Barrel length (m)", "Shape", 0.61, 0.4, 0.8),
		pf("forend", "Forend length (m)", "Shape", 0.27, 0.15, 0.35),
		pf("comb", "Comb height (m)", "Shape", 0.095, 0.075, 0.115),
		pb("scope", "Scope", "Optics", true),
		pf("scope_len", "Scope length (m)", "Optics", 0.33, 0.22, 0.42),
		pf("objective", "Objective radius (m)", "Optics", 0.026, 0.016, 0.032),
		pe("bipod", "Bipod", "Kit", "deployed", ["none", "folded", "deployed"]),
		pf("bipod_angle", "Bipod leg angle (deg)", "Kit", 40.0, 0.0, 90.0, 1.0),
		pe("stock", "Stock colour", "Finish", "olive", ["olive", "black", "tan", "grey"]),
		pb("orange_tip", "Orange tip (airsoft)", "Finish", false),
	]


func presets() -> Dictionary:
	return {
		"Reference": {},
		"Black ops": { "stock": "black", "bipod": "folded" },
		"Desert": { "stock": "tan", "bipod": "folded" },
		"Iron sights": { "scope": false, "bipod": "none", "barrel": 0.56 },
		"Airsoft": { "orange_tip": true },
	}


const BORE_Y := 0.075             ## bore axis above the grip fist


func _build(p: Dictionary) -> GKAsset:
	var a := GKAsset.new()
	var s: float = p.scale
	var g := GKMesh.new()
	g.push(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), Vector3.ZERO))
	var stock_role: String = { "olive": "polymer_olive", "black": "polymer_black", "tan": "polymer_olive:#a48e6a", "grey": "polymer_olive:#6a6e70" }[p.stock]
	var act_end := 0.245
	var muzzle_z := act_end + float(p.barrel)
	var fore_end := act_end + float(p.forend)
	_stock(g, stock_role, p, fore_end)
	_action(g, act_end)
	# the barrel: tapered, crowned, its bore a dark dot
	# a heavy contour barrel: thick at the chamber, a long gentle taper, a crown
	g.lathe("gunmetal", Vector3(0, BORE_Y, act_end - 0.005), Vector3(0, BORE_Y, muzzle_z), [
		Vector2(0.0, 0.0172), Vector2(0.035, 0.0172), Vector2(0.07, 0.0158), Vector2(float(p.barrel) * 0.5, 0.0143),
		Vector2(float(p.barrel) - 0.006, 0.0132), Vector2(float(p.barrel) + 0.002, 0.0128), Vector2(float(p.barrel) + 0.005, 0.0118)], 16)
	g.cyl("rubber", Vector3(0, BORE_Y, muzzle_z + 0.0045), Vector3(0, BORE_Y, muzzle_z + 0.0056), 0.0045, 10)
	if p.orange_tip:
		g.lathe("orange_tip", Vector3(0, BORE_Y, muzzle_z - 0.035), Vector3(0, BORE_Y, muzzle_z + 0.004),
			[Vector2(0, 0.0136), Vector2(0.039, 0.0136)], 14)
	if p.scope:
		_scope(g, float(p.scope_len), float(p.objective))
	if p.bipod != "none":
		_bipod(g, fore_end - 0.035, 0.0 if p.bipod == "folded" else float(p.bipod_angle))
	g.pop()
	a.add_part("body", g.commit())
	var eye_y := (BORE_Y + 0.056) if p.scope else (BORE_Y + 0.02)
	a.markers = {
		"grip": Transform3D.IDENTITY,
		"support": Transform3D(Basis.IDENTITY, Vector3(0, 0.02, act_end + float(p.forend) * 0.42) * s),
		"muzzle": Transform3D(Basis.IDENTITY, Vector3(0, BORE_Y, muzzle_z + 0.006) * s),
		"eye": Transform3D(Basis.IDENTITY, Vector3(0, eye_y, -0.2) * s),
		"butt": Transform3D(Basis.IDENTITY, Vector3(0, 0.0, -0.418) * s),
	}
	a.meta = { "class": "rifle", "hands": "two", "socket": "socket_weapon_r", "projectile": "bullet",
		"length": (muzzle_z + 0.418) * s, "notes": "Bolt-action, scoped; aim from the eye marker." }
	return a


## The stock as one skinned run butt -> forend tip: a deep butt whose lower
## edge climbs steeply into a notch behind the grip (the A5 shape), a slim
## wrist, a forend that tapers and rounds toward the tip. The grip hangs
## under the wrist down to the butt's lower line; the recoil pad, spacers and
## the big cheek-riser plates are black.
func _stock(g: GKMesh, role: String, p: Dictionary, fore_end: float) -> void:
	var comb: float = p.comb
	var st := GKMesh.station
	var runs := [
		st.call(Vector3(0, 0, -0.372), 0.0205, comb, 0.116, 3.6),
		st.call(Vector3(0, 0, -0.33), 0.021, comb, 0.117, 3.6),
		st.call(Vector3(0, 0, -0.25), 0.0205, comb - 0.001, 0.116, 3.4),
		st.call(Vector3(0, 0, -0.17), 0.0198, comb - 0.003, 0.113, 3.4),
		st.call(Vector3(0, 0, -0.15), 0.0195, comb - 0.005, 0.11, 3.4),
		st.call(Vector3(0, 0, -0.138), 0.019, comb - 0.007, 0.08, 3.0),
		st.call(Vector3(0, 0, -0.128), 0.0185, comb - 0.009, 0.042, 2.6),
		st.call(Vector3(0, 0, -0.11), 0.0175, comb - 0.014, 0.026, 2.4),
		st.call(Vector3(0, 0, -0.07), 0.0165, comb - 0.024, 0.022, 2.4),
		st.call(Vector3(0, 0, -0.03), 0.0168, 0.066, 0.024, 2.6),
		st.call(Vector3(0, 0, 0.02), 0.0205, 0.07, 0.03, 2.8),
		st.call(Vector3(0, 0, 0.12), 0.0215, 0.071, 0.034, 3.0),
		st.call(Vector3(0, 0, 0.24), 0.022, 0.071, 0.03, 3.0),
		st.call(Vector3(0, 0.03, 0.29), 0.0215, 0.041, 0.042, 2.8),
		st.call(Vector3(0, 0.044, 0.33), 0.0205, 0.027, 0.026, 2.8),
		st.call(Vector3(0, 0.045, fore_end - 0.06), 0.0195, 0.026, 0.024, 2.6),
		st.call(Vector3(0, 0.046, fore_end - 0.022), 0.0175, 0.024, 0.021, 2.4),
		st.call(Vector3(0, 0.048, fore_end - 0.006), 0.0135, 0.019, 0.015, 2.2),
		st.call(Vector3(0, 0.05, fore_end + 0.003), 0.007, 0.011, 0.008, 2.0),
	]
	g.loft(role, runs, 22)
	# the barrel channel: a dark slot along the forend top
	g.box("polymer_black", Vector3(0, 0.0712, (0.26 + fore_end) * 0.5), Vector3(0.02, 0.002, fore_end - 0.26))
	# grip: near vertical, palm swell, flared base, down to the butt's lower line
	var dir := Vector3(0, 1, 0.2).normalized()
	var fwd := Vector3(0, -0.2, 1).normalized()
	var basis := Basis(Vector3.RIGHT, fwd, dir)
	var grips := [
		st.call(Vector3(0, -0.116, -0.036), 0.0172, 0.024, 0.029, 2.6, basis),
		st.call(Vector3(0, -0.106, -0.034), 0.0182, 0.026, 0.031, 2.4, basis),
		st.call(Vector3(0, -0.07, -0.026), 0.0172, 0.02, 0.028, 2.2, basis),
		st.call(Vector3(0, -0.03, -0.018), 0.016, 0.018, 0.026, 2.2, basis),
		st.call(Vector3(0, 0.01, -0.01), 0.0162, 0.02, 0.03, 2.4, basis),
	]
	g.loft(role, grips, 16)
	g.loft("polymer_black", [st.call(Vector3(0, -0.121, -0.037), 0.0165, 0.023, 0.028, 2.6, basis),
		st.call(Vector3(0, -0.114, -0.036), 0.0176, 0.0245, 0.0295, 2.6, basis)], 16)
	# recoil pad: two spacers then a thick pad, following the butt's section
	g.tint = Color(2.2, 2.2, 2.2)
	g.loft("polymer_black", [st.call(Vector3(0, 0, -0.381), 0.0206, comb + 0.0005, 0.1165, 3.6), st.call(Vector3(0, 0, -0.371), 0.0206, comb + 0.0005, 0.1165, 3.6)], 20)
	g.tint = Color.WHITE
	g.loft("polymer_black", [st.call(Vector3(0, 0, -0.39), 0.0206, comb + 0.0005, 0.1165, 3.6), st.call(Vector3(0, 0, -0.3805), 0.0206, comb + 0.0005, 0.1165, 3.6)], 20)
	g.loft("rubber", [st.call(Vector3(0, 0.0, -0.418), 0.0195, comb - 0.004, 0.112, 3.6),
		st.call(Vector3(0, 0.0, -0.41), 0.0212, comb + 0.001, 0.118, 3.6),
		st.call(Vector3(0, 0, -0.3895), 0.021, comb + 0.001, 0.117, 3.6)], 20)
	# the adjustable cheek riser: black plates on both flanks of the rear comb,
	# a black comb top, the posts' knurled knobs
	var plate := PackedVector2Array([Vector2(-0.365, comb - 0.002), Vector2(-0.215, comb - 0.002), Vector2(-0.215, comb - 0.05),
		Vector2(-0.24, comb - 0.072), Vector2(-0.365, comb - 0.072)])
	g.extrude("polymer_black", plate, 0.0185, 0.0235, 0.002)
	g.extrude("polymer_black", plate, -0.0235, -0.0185, 0.002)
	for sx in [-1.0, 1.0]:
		for kz in [[-0.25, comb - 0.024], [-0.33, comb - 0.05]]:
			g.cyl("steel", Vector3(sx * 0.021, kz[1], kz[0]), Vector3(sx * 0.03, kz[1], kz[0]), 0.004, 10)
			g.cyl("alloy_black", Vector3(sx * 0.028, kz[1], kz[0]), Vector3(sx * 0.037, kz[1], kz[0]), 0.0085, 14)   # the knob
	g.loft("polymer_black", [st.call(Vector3(0, comb - 0.01, -0.366), 0.0215, 0.013, 0.008, 4.0),
		st.call(Vector3(0, comb - 0.01, -0.214), 0.0215, 0.013, 0.008, 4.0)], 16)
	# sling studs
	g.cyl("gunmetal", Vector3(0, -0.108, -0.29), Vector3(0, -0.121, -0.29), 0.004, 8)
	g.cyl("gunmetal", Vector3(0, 0.026, fore_end - 0.07), Vector3(0, 0.014, fore_end - 0.07), 0.004, 8)
	# the spacer column on the butt plate: three stacked knobs
	for k in 3:
		for sx in [-1.0, 1.0]:
			g.cyl("steel", Vector3(sx * 0.0235, comb - 0.03 - k * 0.015, -0.29), Vector3(sx * 0.027, comb - 0.03 - k * 0.015, -0.29), 0.0045, 10)
	# trigger guard: an open flat loop hanging clear of the stock, the blade inside
	var tg: Array = []
	for k in 11:
		var an := lerpf(-0.1, PI + 0.15, k / 10.0)
		tg.append(Vector3(0, -0.028 - sin(an) * 0.03, 0.055 + cos(an) * 0.05))
	g.tube("alloy_black", tg, 0.0042, 10, true, Vector3.RIGHT, 2.0)
	g.tube("gunmetal", [Vector3(0, -0.026, 0.064), Vector3(0, -0.036, 0.064), Vector3(0, -0.045, 0.06), Vector3(0, -0.05, 0.053)], [0.0026, 0.003, 0.003, 0.0026], 8, true, Vector3.RIGHT, 2.2)
	g.box("alloy_black", Vector3(0, -0.03, 0.165), Vector3(0.032, 0.006, 0.09), 0.002)


## Receiver, bolt, rail, the knob on the right (-x).
func _action(g: GKMesh, act_end: float) -> void:
	g.lathe("gunmetal", Vector3(0, BORE_Y, -0.03), Vector3(0, BORE_Y, act_end), [
		Vector2(0.0, 0.006), Vector2(0.006, 0.0125), Vector2(0.02, 0.0135), Vector2(0.03, 0.0168), Vector2(act_end + 0.03 - 0.008, 0.0168),
		Vector2(act_end + 0.03, 0.015)], 18)
	# ejection port, a dark recess on the right
	g.box("rubber", Vector3(-0.0158, BORE_Y + 0.004, 0.115), Vector3(0.004, 0.012, 0.06), 0.001)
	# bolt handle: down and back from the receiver to a big tactical knob
	g.tube("gunmetal", [Vector3(-0.012, BORE_Y + 0.002, 0.032), Vector3(-0.034, BORE_Y - 0.006, 0.026), Vector3(-0.054, BORE_Y - 0.026, 0.016)], [0.0048, 0.0044, 0.0042], 10)
	g.sphere("alloy_black", Vector3(-0.061, BORE_Y - 0.033, 0.012), 0.0135, 16, Vector3(1.0, 1.0, 1.12))
	# picatinny rail with its cross slots
	var top := BORE_Y + 0.0168
	g.box("alloy_black", Vector3(0, top + 0.003, 0.11), Vector3(0.016, 0.006, 0.25), 0.0008)
	g.box("alloy_black", Vector3(0, top + 0.0075, 0.11), Vector3(0.021, 0.004, 0.25), 0.0008)
	var z := -0.01
	while z < 0.23:
		g.box("gunmetal", Vector3(0, top + 0.0098, z), Vector3(0.0215, 0.0012, 0.0035))
		z += 0.01
	# bolt shroud at the back
	g.lathe("gunmetal", Vector3(0, BORE_Y, -0.05), Vector3(0, BORE_Y, -0.02), [Vector2(0, 0.004), Vector2(0.004, 0.009), Vector2(0.03, 0.011)], 12)


## 1-inch scope: eyepiece, power ring, tube, turrets, objective bell, lenses.
func _scope(g: GKMesh, length: float, obj: float) -> void:
	var y := BORE_Y + 0.056
	var z0 := 0.165 - length * 0.55
	var L := length
	g.lathe("alloy_black", Vector3(0, y, z0), Vector3(0, y, z0 + L), [
		Vector2(0.0, 0.0175), Vector2(0.004, 0.0188), Vector2(0.03, 0.0188), Vector2(0.034, 0.0182), Vector2(0.045, 0.0186),
		Vector2(0.062, 0.0186), Vector2(0.07, 0.0165), Vector2(0.086, 0.0128), Vector2(L * 0.74, 0.0128), Vector2(L * 0.8, 0.0135),
		Vector2(L * 0.88, obj * 0.95), Vector2(L - 0.006, obj), Vector2(L, obj * 0.94)], 24, false)
	# eyepiece rubber
	g.lathe("rubber", Vector3(0, y, z0 - 0.008), Vector3(0, y, z0 + 0.002), [Vector2(0, 0.0182), Vector2(0.01, 0.0178)], 24, false)
	# lenses, set in
	g.cyl("glass_lens", Vector3(0, y, z0 + 0.004), Vector3(0, y, z0 + 0.005), 0.0172, 24)
	g.cyl("glass_lens", Vector3(0, y, z0 + L - 0.008), Vector3(0, y, z0 + L - 0.007), obj * 0.9, 24)
	g.cyl("rubber", Vector3(0, y, z0 + 0.012), Vector3(0, y, z0 + 0.013), 0.0185, 24)
	g.cyl("rubber", Vector3(0, y, z0 + L - 0.016), Vector3(0, y, z0 + L - 0.015), obj * 0.98, 24)
	# turrets: elevation on top, windage on the right
	var tz := z0 + L * 0.48
	g.cyl("alloy_black", Vector3(0, y + 0.012, tz), Vector3(0, y + 0.026, tz), 0.0105, 16)
	g.cyl("alloy_black", Vector3(0, y + 0.026, tz), Vector3(0, y + 0.034, tz), 0.0118, 16)
	g.box("alloy_black", Vector3(0, y + 0.006, tz), Vector3(0.026, 0.014, 0.03), 0.004)
	g.cyl("alloy_black", Vector3(-0.012, y, tz), Vector3(-0.03, y, tz), 0.0098, 16)
	g.cyl("alloy_black", Vector3(-0.026, y, tz), Vector3(-0.034, y, tz), 0.011, 16)
	g.cyl("alloy_black", Vector3(0.012, y, tz), Vector3(0.024, y, tz), 0.0085, 14)   # parallax, left
	# rings on the rail
	var top := BORE_Y + 0.0168 + 0.0095
	for rz in [0.07, 0.19]:
		g.lathe("alloy_black", Vector3(0, y, rz - 0.008), Vector3(0, y, rz + 0.008), [Vector2(0, 0.0152), Vector2(0.016, 0.0152)], 20)
		g.box("alloy_black", Vector3(0, (top + y - 0.012) * 0.5, rz), Vector3(0.02, y - 0.012 - top + 0.004, 0.016), 0.002)
		g.box("alloy_black", Vector3(-0.0135, top + 0.004, rz), Vector3(0.007, 0.009, 0.014), 0.0015)   # cross bolt nut
		g.cyl("steel", Vector3(-0.015, y + 0.008, rz), Vector3(-0.0175, y + 0.008, rz), 0.002, 6)


## Harris-style bipod on the forend stud; `angle` 0 = folded along the
## barrel, 90 = straight down.
func _bipod(g: GKMesh, z: float, angle: float) -> void:
	var y := 0.03                     # the slim forend's underside
	g.box("alloy_black", Vector3(0, y - 0.006, z), Vector3(0.058, 0.022, 0.036), 0.004)
	g.cyl("alloy_black", Vector3(0, y + 0.004, z), Vector3(0, y + 0.012, z), 0.008, 12)
	g.cyl("steel", Vector3(-0.031, y - 0.006, z), Vector3(0.031, y - 0.006, z), 0.0045, 10)   # the pivot pin
	var a := deg_to_rad(angle)
	for sx in [-1.0, 1.0]:
		var base := Vector3(sx * 0.022, y - 0.012, z)
		var dir := Vector3(sx * sin(a) * 0.08, -sin(a), cos(a)).normalized()
		var knee := base + dir * 0.13
		var foot := base + dir * 0.2
		g.cyl("alloy_black", base, knee, 0.0092, 12)
		g.lathe("alloy_black", knee - dir * 0.012, knee + dir * 0.006, [Vector2(0, 0.0104), Vector2(0.018, 0.0104)], 12)   # the leg lock
		g.cyl("gunmetal", knee - dir * 0.005, foot, 0.0064, 10)
		g.sphere("rubber", foot + dir * 0.005, 0.0105, 12, Vector3(1.0, 1.0, 1.0))
		g.cyl("steel", base + Vector3(0, 0.004, 0.01), base + Vector3(0, -0.004, 0.06) + dir * 0.02, 0.0035, 6)   # the spring
