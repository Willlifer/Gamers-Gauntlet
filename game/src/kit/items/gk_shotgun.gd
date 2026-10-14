class_name GKShotgun
extends GKDef
## Pump-action shotgun after the reference (design/ref/kit/shotgun.jpg): a
## long vent-ribbed barrel with a bead, the magazine tube under it ending in
## a cap, a ribbed pump forend on the tube, a rounded alloy receiver with the
## ejection port on the right, a black synthetic sporting stock with a curved
## wrist and a ribbed recoil pad. All black, different blacks.
## Real size in metres in the weapon frame (GKAsset), scaled by `scale`.

func id() -> String:
	return "shotgun"


func title() -> String:
	return "Pump shotgun"


func version() -> int:
	return 1


func schema() -> Array[Dictionary]:
	return [
		pf("scale", "Scale", "Fit", 1.25, 0.5, 2.0, 0.01),
		pf("barrel", "Barrel length (m)", "Shape", 0.71, 0.36, 0.8),
		pf("mag", "Magazine tube (m)", "Shape", 0.42, 0.25, 0.6),
		pb("vent_rib", "Vent rib", "Shape", true),
		pf("pump", "Pump position 0-1", "Pose", 0.0, 0.0, 1.0, 0.01),
		pe("stock", "Stock", "Shape", "sporting", ["sporting", "pistol_grip"]),
		pe("finish", "Finish", "Finish", "black", ["black", "wood", "olive"]),
	]


func presets() -> Dictionary:
	return {
		"Reference": {},
		"Riot": { "barrel": 0.47, "mag": 0.45, "vent_rib": false, "stock": "pistol_grip" },
		"Field wood": { "finish": "wood" },
		"Racked": { "pump": 1.0 },
	}


const BORE_Y := 0.072


func _build(p: Dictionary) -> GKAsset:
	var a := GKAsset.new()
	var s: float = p.scale
	var g := GKMesh.new()
	g.push(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), Vector3.ZERO))
	var furn: String = { "black": "polymer_black", "wood": "wood_branch:#6b4528", "olive": "polymer_olive" }[p.finish]
	var rec_end := 0.25
	var muzzle := rec_end + float(p.barrel)
	var mag_end := minf(rec_end - 0.04 + float(p.mag), muzzle - 0.01)
	_receiver(g, rec_end)
	_stock(g, furn, str(p.stock))
	# barrel and rib
	g.lathe("blued", Vector3(0, BORE_Y, rec_end - 0.01), Vector3(0, BORE_Y, muzzle), [
		Vector2(0.0, 0.0138), Vector2(0.05, 0.0138), Vector2(0.07, 0.0118), Vector2(float(p.barrel) + 0.01 - 0.01, 0.0112), Vector2(float(p.barrel) + 0.01, 0.0108)], 16)
	g.cyl("rubber", Vector3(0, BORE_Y, muzzle + 0.0005), Vector3(0, BORE_Y, muzzle + 0.002), 0.0092, 14)
	g.lathe("blued", Vector3(0, BORE_Y, rec_end - 0.004), Vector3(0, BORE_Y, rec_end + 0.022), [Vector2(0, 0.0158), Vector2(0.026, 0.0152)], 18)   # the barrel collar
	var rib_y := BORE_Y + 0.0112
	if p.vent_rib:
		g.box("blued", Vector3(0, rib_y + 0.0052, (rec_end + muzzle) * 0.5 + 0.005), Vector3(0.0085, 0.0016, muzzle - rec_end - 0.012), 0.0006)
		var z := rec_end + 0.012
		while z < muzzle - 0.01:
			g.box("blued", Vector3(0, rib_y + 0.0024, z), Vector3(0.0035, 0.0044, 0.005))
			z += 0.032
		g.sphere("brass", Vector3(0, rib_y + 0.0084, muzzle - 0.008), 0.0024, 10)
	else:
		g.sphere("brass", Vector3(0, rib_y + 0.003, muzzle - 0.012), 0.0026, 10)
	# magazine tube, its cap, the barrel lug that clamps onto it
	var my := BORE_Y - 0.0255
	g.cyl("blued", Vector3(0, my, rec_end - 0.04), Vector3(0, my, mag_end), 0.0118, 16, false)
	g.lathe("alloy_black", Vector3(0, my, mag_end - 0.002), Vector3(0, my, mag_end + 0.026), [
		Vector2(0, 0.0128), Vector2(0.022, 0.0128), Vector2(0.026, 0.0118), Vector2(0.028, 0.0108)], 16)
	g.box("gunmetal", Vector3(0, my - 0.016, mag_end + 0.014), Vector3(0.006, 0.01, 0.012), 0.002)     # swivel stud
	g.cyl("gunmetal", Vector3(-0.005, my - 0.019, mag_end + 0.014), Vector3(0.005, my - 0.019, mag_end + 0.014), 0.0028, 8)
	g.box("blued", Vector3(0, (my + BORE_Y) * 0.5, mag_end - 0.03), Vector3(0.016, 0.026, 0.026), 0.003)
	# the pump: slides back `pump` of its 0.09 m stroke
	var stroke := 0.09 * float(p.pump)
	var f1 := mag_end - 0.006 - stroke               # the pump ends just behind the cap
	var f0 := maxf(f1 - 0.3, rec_end + 0.02 - stroke)
	# the pump and its action bars are their own part: a viewmodel racks it
	var pg := GKMesh.new()
	pg.push(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), Vector3.ZERO))
	_forend(pg, furn, f0, f1, my)
	for sx in [-1.0, 1.0]:
		pg.box("blued", Vector3(sx * 0.0115, my + 0.002, (rec_end - 0.03 + f0 + 0.02) * 0.5), Vector3(0.0025, 0.007, f0 + 0.02 - (rec_end - 0.03)))
	pg.pop()
	g.pop()
	a.add_part("body", g.commit())
	a.add_part("pump", pg.commit())
	a.markers = {
		"grip": Transform3D.IDENTITY,
		"support": Transform3D(Basis.IDENTITY, Vector3(0, my - 0.02, (f0 + f1) * 0.5) * s),
		"muzzle": Transform3D(Basis.IDENTITY, Vector3(0, BORE_Y, muzzle + 0.003) * s),
		"eye": Transform3D(Basis.IDENTITY, Vector3(0, rib_y + 0.03, -0.16) * s),
		"butt": Transform3D(Basis.IDENTITY, Vector3(0, -0.035, -0.358) * s),
	}
	a.meta = { "class": "shotgun", "hands": "two", "socket": "socket_weapon_r", "projectile": "pellets",
		"length": (muzzle + 0.355) * s, "pump_stroke": 0.09 * s, "notes": "Pump action: animate `pump` 0 -> 1 -> 0 to rack." }
	return a


## The receiver: long and low, its top just under the rib line, rounded
## all over (a skinned box), the front corner eased, the back sweeping down
## into the stock's wrist.
func _receiver(g: GKMesh, rec_end: float) -> void:
	var st := GKMesh.station
	var cy := 0.052
	g.loft("blued", [
		st.call(Vector3(0, cy - 0.006, -0.004), 0.0155, 0.022, 0.03, 3.4),
		st.call(Vector3(0, cy, 0.012), 0.0168, 0.032, 0.038, 4.0),
		st.call(Vector3(0, cy, 0.04), 0.0172, 0.038, 0.04, 4.6),
		st.call(Vector3(0, cy, rec_end - 0.02), 0.0172, 0.038, 0.04, 4.6),
		st.call(Vector3(0, cy, rec_end - 0.006), 0.0168, 0.035, 0.038, 4.0),
		st.call(Vector3(0, cy + 0.003, rec_end), 0.015, 0.03, 0.033, 3.0)], 22)
	# ejection port (right): a deep dark slot with the bolt face showing
	g.tint = Color(0.15, 0.15, 0.15)
	g.box("rubber", Vector3(-0.01725, BORE_Y + 0.002, 0.175), Vector3(0.0008, 0.019, 0.07))
	g.tint = Color.WHITE
	g.box("gunmetal", Vector3(-0.0174, BORE_Y + 0.002, 0.15), Vector3(0.0006, 0.015, 0.02))
	# loading port underneath, the elevator inside
	g.box("rubber", Vector3(0, cy - 0.039, 0.16), Vector3(0.026, 0.004, 0.11), 0.0015)
	# top-tang safety: a ridged button on the receiver's back slope
	g.box("polymer_black", Vector3(0, cy + 0.03, 0.006), Vector3(0.011, 0.007, 0.02), 0.0025)
	for k in 3:
		g.box("polymer_black", Vector3(0, cy + 0.0345, 0.0 + k * 0.006), Vector3(0.011, 0.0016, 0.002))
	# trigger guard: a thin rounded loop under the receiver, the trigger in it
	var tg: Array = []
	for k in 13:
		var a := lerpf(-0.15, PI + 0.25, k / 12.0)                  # a smooth U under the receiver
		tg.append(Vector3(0, 0.012 - pow(maxf(sin(a), 0.0), 0.6) * 0.03, 0.068 + cos(a) * 0.055))
	g.tube("polymer_black", tg, 0.0036, 12, true, Vector3.RIGHT, 1.6)
	g.tube("blued", [Vector3(0, 0.012, 0.074), Vector3(0, 0.0, 0.072), Vector3(0, -0.012, 0.066), Vector3(0, -0.018, 0.058)], [0.0024, 0.0028, 0.0028, 0.0024], 8, true, Vector3.RIGHT, 2.0)
	g.box("polymer_black", Vector3(0, 0.012, 0.068), Vector3(0.022, 0.006, 0.1), 0.002)
	for pz in [0.05, 0.11]:
		g.cyl("steel", Vector3(-0.0174, 0.026, pz), Vector3(0.0174, 0.026, pz), 0.0022, 8)


func _stock(g: GKMesh, role: String, kind: String) -> void:
	var st := GKMesh.station
	if kind == "pistol_grip":
		var dir := Vector3(0, 1, 0.3).normalized()
		var basis := Basis(Vector3.RIGHT, Vector3(0, -0.3, 1).normalized(), dir)
		g.loft(role, [st.call(Vector3(0, -0.095, -0.03), 0.016, 0.021, 0.025, 2.4, basis),
			st.call(Vector3(0, -0.05, -0.018), 0.0165, 0.02, 0.026, 2.2, basis),
			st.call(Vector3(0, 0.0, -0.002), 0.0165, 0.02, 0.026, 2.2, basis),
			st.call(Vector3(0, 0.02, 0.01), 0.017, 0.025, 0.026, 2.4, basis)], 16)
		g.loft(role, [st.call(Vector3(0, 0.045, 0.0), 0.0165, 0.028, 0.032, 3.0),
			st.call(Vector3(0, 0.045, -0.04), 0.0158, 0.022, 0.028, 3.0)], 16)
		return
	# the sporting stock: from the receiver's back down into a slim wrist with
	# a pistol-grip swell under it, then dropping and deepening to the butt
	g.loft(role, [
		st.call(Vector3(0, 0, 0.004), 0.0158, 0.074, 0.016, 3.0),
		st.call(Vector3(0, 0, -0.012), 0.0156, 0.058, 0.02, 2.8),
		st.call(Vector3(0, 0, -0.03), 0.0138, 0.038, 0.03, 2.3),
		st.call(Vector3(0, 0, -0.055), 0.0145, 0.034, 0.06, 2.2),
		st.call(Vector3(0, 0, -0.08), 0.0158, 0.033, 0.07, 2.3),
		st.call(Vector3(0, 0, -0.11), 0.017, 0.031, 0.066, 2.4),
		st.call(Vector3(0, 0, -0.17), 0.0188, 0.027, 0.082, 2.6),
		st.call(Vector3(0, 0, -0.24), 0.0202, 0.02, 0.104, 2.8),
		st.call(Vector3(0, 0, -0.31), 0.021, 0.012, 0.13, 3.0),
		st.call(Vector3(0, 0, -0.325), 0.0208, 0.011, 0.134, 3.0),
	], 30)
	# recoil pad: thick dark rubber with horizontal ribs
	g.loft("rubber", [st.call(Vector3(0, 0.0, -0.358), 0.0196, 0.008, 0.13, 3.2),
		st.call(Vector3(0, 0.0, -0.348), 0.0214, 0.0125, 0.136, 3.2),
		st.call(Vector3(0, 0.0, -0.3245), 0.0209, 0.0112, 0.1342, 3.0)], 20)
	# the pad's bold vent slots on each side, and ribs on its face
	g.tint = Color(0.3, 0.3, 0.3)
	for k in 4:
		var y := -0.1 + k * 0.026
		for sx in [-1.0, 1.0]:
			g.box("rubber", Vector3(sx * 0.0213, y, -0.341), Vector3(0.0012, 0.008, 0.016), 0.0004)
	g.tint = Color(0.55, 0.55, 0.55)
	for k in 8:
		g.box("rubber", Vector3(0, -0.115 + k * 0.016, -0.3585), Vector3(0.03, 0.005, 0.0012))
	g.tint = Color.WHITE
	g.cyl("gunmetal", Vector3(0, -0.084, -0.25), Vector3(0, -0.096, -0.25), 0.0035, 8)   # sling stud


## The pump: a ribbed sleeve round the magazine tube.
func _forend(g: GKMesh, role: String, f0: float, f1: float, my: float) -> void:
	var st := GKMesh.station
	var top := BORE_Y - 0.0145 - my
	g.loft(role, [
		st.call(Vector3(0, my, f0), 0.02, top - 0.004, 0.03, 3.0),
		st.call(Vector3(0, my, f0 + 0.014), 0.026, top, 0.04, 3.2),
		st.call(Vector3(0, my, f1 - 0.014), 0.026, top, 0.04, 3.2),
		st.call(Vector3(0, my, f1), 0.0205, top - 0.004, 0.031, 3.0)], 22)
	# grip grooves round the bottom half
	var z := f0 + 0.03
	g.tint = Color(0.28, 0.28, 0.28)
	while z < f1 - 0.025:
		g.loft(role, [st.call(Vector3(0, my - 0.0005, z), 0.0262, top * 0.6, 0.0403, 3.2),
			st.call(Vector3(0, my - 0.0005, z + 0.007), 0.0262, top * 0.6, 0.0403, 3.2)], 22, false)
		z += 0.03
	g.tint = Color.WHITE
