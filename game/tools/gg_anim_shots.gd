extends SceneTree
## Review sheets for the G55 stick-figure work (GGAnim, MobaDress). Needs a
## window (not --headless):
##
##   [TAG=r1] [ONLY=loco,casts,look,game] godot --path game --script res://tools/gg_anim_shots.gd
##
## Writes to design/shots/anim/:
##   <tag>_loco.png     every new locomotion over one cycle (side row + MOBA-angle
##                      row): Merr's godly float, Temu's skip, Braves' cool walk,
##                      a Twin's float; the floor stripes are 0.5 u apart (feet
##                      that stay on a stripe are planted, not sliding)
##   <tag>_casts.png    each champion's Q / W / E / R (and flash, smite) gesture,
##                      frames 0-13 every other frame; the release is f6 (0.25 s)
##   <tag>_look.png     the three champions dressed: front, 3/4, side, back, and
##                      all three at the MOBA camera's distance and angle
##                      (MobaView.CAM_PITCH / CAM_DIST / CAM_FOV)
##   <tag>_ghost.png    Temu hidden, as his own side sees him (75% transparent)

const DT := 1.0 / 60.0
const CELL := Vector2i(200, 250)
const BG := Color(0.62, 0.64, 0.6)

var tag := "r1"
var only := ""
var out_dir := ""


func _initialize() -> void:
	tag = OS.get_environment("TAG") if OS.get_environment("TAG") != "" else "r1"
	only = OS.get_environment("ONLY")
	out_dir = ProjectSettings.globalize_path("res://").path_join("../design/shots/anim").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _want(k: String) -> bool:
	return only == "" or k in only.split(",")


func _run() -> void:
	if _want("loco"):
		await _loco()
	if _want("casts"):
		await _casts()
	if _want("look"):
		await _look()
		await _ghost()
	quit(0)


# ------------------------------------------------------------------ staging

func _viewport(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	vp.transparent_bg = false
	root.add_child(vp)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = BG
	e.ambient_light_color = Color.WHITE
	we.environment = e
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	vp.add_child(sun)
	return vp


## Floor with a stripe every 0.5 u along z (sliding feet show against it).
func _floor(vp: Node, length: float = 60.0) -> void:
	var f := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, length)
	f.mesh = pm
	f.position = Vector3(0, -0.002, length * 0.5 - 4.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.74, 0.76, 0.7)
	f.material_override = m
	vp.add_child(f)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.45, 0.47, 0.43)
	var z := -4.0
	while z < length - 4.0:
		var s := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(6, 0.002, 0.02)
		s.mesh = bm
		s.material_override = sm
		s.position = Vector3(0, 0.0, z)
		vp.add_child(s)
		z += 0.5


## A champion exactly as MobaView builds one (tint, kit weapon, dress).
func _champ(parent: Node, id: String, team: String = "blue") -> BWCharacter:
	var c: Dictionary = MobaChamps.CHAMPS[id]
	var ch := BWCharacter.create(MobaLook.champ_unit(id, team))
	parent.add_child(ch)
	ch.set_process(false)
	MobaLook.tint(ch, Color(str(c.tint)), Color(str(c.hair_hex)))
	if c.has("kit_weapon"):
		GKBWHold.swap_weapon(ch, GKRegistry.build(str(c.kit_weapon), c.get("kit_params", {})))
	MobaDress.dress(ch, id)
	ch.pose("idle", 0.0)
	if ch.animator:
		ch.animator.rotate_idles = false
	return ch


## A Twin (Noon), as B/W's Twins fight builds its look, with the float hooked.
func _twin(parent: Node) -> BWCharacter:
	var u := BWUnit.new()
	u.id = "noon_f9"
	u.name = "Noon"
	u.team = "enemy"
	u.element = "light"
	u.weapon_model = "glaive"
	u.weapon_class = str(BWWeaponView.meta_for("glaive").get("class", "polearm"))
	u.encounter = "twin"
	u.cosmetics = { "hair_style": "none", "top": "tshirt", "bottom": "tight_pants", "clothing_shade": "light" }
	for s in BWUnit.STATS:
		u.stats[s] = 5
	u.hp = u.max_hp()
	var ch := BWCharacter.create(u)
	parent.add_child(ch)
	ch.set_process(false)
	GGAnim.float_twins_under(parent)
	GGAnim._float_twin(ch)
	ch.pose("idle", 0.0)
	return ch


func _step(ch: BWCharacter, n: int, speed: float = 0.0) -> void:
	for i in n:
		ch.position.z += speed * DT
		ch._process(DT)


func _cam(vp: SubViewport, ortho: bool, size: float = 2.6) -> Camera3D:
	var cam := Camera3D.new()
	if ortho:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = size
	else:
		cam.fov = MobaView.CAM_FOV
	cam.near = 0.05
	cam.far = 200.0
	vp.add_child(cam)
	cam.make_current()
	return cam


## Side: from the figure's left (+x), looking at it walking to the right of frame.
func _aim_side(cam: Camera3D, at: Vector3) -> void:
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(-0.06, PI * 0.5, 0)), at + Vector3(12, 12 * 0.06, 0))


## The MOBA angle (CAM_PITCH, from behind-left, as the lane runs corner to corner).
func _aim_moba(cam: Camera3D, at: Vector3, dist: float) -> void:
	var pitch := deg_to_rad(MobaView.CAM_PITCH)
	var yaw := PI * 0.75
	var b := Basis.from_euler(Vector3(-pitch, yaw, 0))
	cam.global_transform = Transform3D(b, at + b.z * dist)


func _frame() -> void:
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw


func _grab(vp: SubViewport) -> Image:
	await _frame()
	return vp.get_texture().get_image()


# ------------------------------------------------------------------ compose

## rows: [{ title, cells: [[Image, label], ...] }] -> one PNG.
func _compose(path: String, title: String, rows: Array, cell: Vector2i, per_row: int) -> void:
	var head := 34
	var lab := 18
	var h := head
	var wmax := cell.x * per_row
	for r in rows:
		var cs := _cell_of(r, cell)
		var pr := maxi(1, mini(per_row, int(cell.x * per_row / cs.x)))
		wmax = maxi(wmax, cs.x * pr)
		h += 24 + int(ceil((r.cells as Array).size() / float(pr))) * (cs.y + lab)
	var size := Vector2i(wmax, h)
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.86, 0.86, 0.84)
	bg.size = Vector2(size)
	vp.add_child(bg)
	_label(vp, title, Vector2(8, 6), 18, Color.BLACK)
	var y := head
	for r in rows:
		var cs := _cell_of(r, cell)
		var pr := maxi(1, mini(per_row, int(cell.x * per_row / cs.x)))
		_label(vp, str(r.title), Vector2(6, y + 2), 15, Color(0.05, 0.05, 0.35))
		y += 24
		var cells: Array = r.cells
		for i in cells.size():
			var at := Vector2((i % pr) * cs.x, y + (i / pr) * (cs.y + lab))
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(cells[i][0])
			tr.position = at
			vp.add_child(tr)
			_label(vp, str(cells[i][1]), at + Vector2(4, cs.y + 1), 12, Color.BLACK)
		y += int(ceil(cells.size() / float(pr))) * (cs.y + lab)
	await _frame()
	vp.get_texture().get_image().save_png(path)
	print("saved ", path)
	vp.queue_free()


func _cell_of(r: Dictionary, cell: Vector2i) -> Vector2i:
	if (r.cells as Array).is_empty():
		return cell
	var img: Image = r.cells[0][0]
	return Vector2i(img.get_width(), img.get_height())


func _label(parent: Node, text: String, at: Vector2, size: int, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)


# ------------------------------------------------------------------ sheets

func _loco() -> void:
	var rows: Array = []
	var subjects := [["merr", "Merr: godly floating (gg_float, on B/W's Twin hover)"], ["temu", "Temu: skipping (gg_skip, 18 f, 2.5 u a cycle)"],
		["braves", "Braves: cool walk (gg_cool_walk, 16 f, 2.1 u a cycle; the gun along the leg)"], ["twin", "Noon (the Twins): godly floating in B/W's fight"]]
	for sj in subjects:
		var vp := _viewport(CELL)
		_floor(vp)
		var ch: BWCharacter = _twin(vp) if sj[0] == "twin" else _champ(vp, str(sj[0]))
		var an := ch.animator
		var speed := 3.4 if sj[0] != "twin" else BWAnimator.GLIDE_SPEED
		_step(ch, 30)
		ch.pose("run")
		_step(ch, 90, speed)                         # settle into the cycle
		var clip := an.top_clip()
		var length := an.library.get_animation(clip).length
		var rate := clampf(speed / maxf(float(an.clip_meta(clip).get("speed", speed)), 0.01), 0.0, 1.6)
		var cyc := length / maxf(rate, 0.01)
		var n := 8
		var side: Array = []
		var moba: Array = []
		var front: Array = []
		var cam := _cam(vp, true, 3.5)
		for i in n:
			var at := ch.global_position + Vector3(0, 1.35, 0)
			_aim_side(cam, at)
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			side.append([await _grab(vp), "%s f%.1f" % [clip, fposmod(float(an.layers.back().t), length) * 24.0]])
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = 22.0
			_aim_moba(cam, ch.global_position + Vector3(0, 1.1, 0), 10.0)
			moba.append([await _grab(vp), "MOBA angle"])
			var fb := Basis.from_euler(Vector3(-0.15, PI * 0.15, 0))
			cam.global_transform = Transform3D(fb, ch.global_position + Vector3(0, 1.3, 0) + fb.z * 9.0)
			cam.fov = 24.0
			front.append([await _grab(vp), "front 3/4"])
			_step(ch, maxi(1, int(round(cyc / n / DT))), speed)
		rows.append({ "title": "%s   (cycle %.2f s at %.1f u/s)" % [sj[1], cyc, speed], "cells": side })
		rows.append({ "title": "   ... the same frames from the front", "cells": front })
		rows.append({ "title": "   ... and from the MOBA camera's pitch", "cells": moba })
		vp.queue_free()
	await _compose(out_dir.path_join(tag + "_loco.png"), "G55 locomotion: one cycle each, 8 frames (%s)" % tag, rows, CELL, 8)


func _casts() -> void:
	var rows: Array = []
	for id in MobaChamps.ORDER:
		var slots: Array = ["q", "w", "e", "r", "flash"]
		if id == "merr":
			slots.append("smite")
		for slot in slots:
			if id == "temu" and slot == "e":
				continue                               # Temu's E is a passive
			var vp := _viewport(Vector2i(170, 210))
			_floor(vp)
			var ch := _champ(vp, id)
			_step(ch, 60)
			var pose := MobaDress.cast_pose(ch, id, slot)
			ch.pose(pose)
			var cam := _cam(vp, false)
			cam.fov = 26.0
			var cells: Array = []
			var frame := 0.0
			var marks := [0, 2, 3, 4, 5, 6, 7, 9, 11, 13]
			for m in marks:
				var target: float = m / 24.0
				while frame < target - 1e-4:
					_step(ch, 1)
					frame += DT
				cam.global_transform = Transform3D(Basis.from_euler(Vector3(-0.25, PI * 0.72, 0)), Vector3(0, 1.25, 0) + Basis.from_euler(Vector3(-0.25, PI * 0.72, 0)).z * 8.5)
				cells.append([await _grab(vp), "f%d%s" % [m, "  release" if m == 6 else ""]])
			rows.append({ "title": "%s %s: %s" % [MobaChamps.CHAMPS[id].name, slot.to_upper(), pose], "cells": cells })
			vp.queue_free()
	await _compose(out_dir.path_join(tag + "_casts.png"), "G55 cast gestures (14 f; coil f3, release f6 = 0.25 s, held to f9)  (%s)" % tag, rows, Vector2i(170, 210), 10)


func _look() -> void:
	var rows: Array = []
	for id in MobaChamps.ORDER:
		var vp := _viewport(Vector2i(220, 280))
		var ch := _champ(vp, id)
		_step(ch, 60)
		var cam := _cam(vp, false)
		cam.fov = 24.0
		var cells: Array = []
		for v in [["front", 0.0], ["3/4", PI * 0.25], ["side", PI * 0.5], ["back", PI], ["3/4 back", PI * 1.25]]:
			var b := Basis.from_euler(Vector3(-0.12, float(v[1]), 0))
			cam.global_transform = Transform3D(b, Vector3(0, 1.35, 0) + b.z * 9.0)
			cells.append([await _grab(vp), str(v[0])])
		rows.append({ "title": "%s, %s" % [MobaChamps.CHAMPS[id].name, MobaChamps.CHAMPS[id].title], "cells": cells })
		vp.queue_free()
	# all three at the MOBA camera's distance (a 400 x 300 crop of a 1600 x 900 frame)
	var vp2 := _viewport(Vector2i(1600, 900))
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.42, 0.3)
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	g.material_override = gm
	vp2.add_child(g)
	var chs: Array = []
	var i := 0
	for id in MobaChamps.ORDER:
		var ch := _champ(vp2, id)
		ch.position = Vector3(-1.6 + i * 1.6, 0, 0)
		ch.rotation.y = PI * 0.25
		chs.append(ch)
		i += 1
	var cam2 := _cam(vp2, false)
	cam2.fov = MobaView.CAM_FOV
	var pitch := deg_to_rad(MobaView.CAM_PITCH)
	cam2.global_transform = Transform3D(Basis.from_euler(Vector3(-pitch, 0, 0)), Vector3(0, sin(pitch) * MobaView.CAM_DIST, cos(pitch) * MobaView.CAM_DIST))
	var cells2: Array = []
	for k in 2:
		for ch in chs:
			_step(ch, 1)
		for n in 40:
			for ch in chs:
				_step(ch, 1, 3.4 if k == 1 else 0.0)
		if k == 0:
			for ch in chs:
				ch.pose("run")
		var img := await _grab(vp2)
		var crop := img.get_region(Rect2i(560, 240, 480, 360))
		crop.resize(720, 540, Image.INTERPOLATE_NEAREST)
		cells2.append([crop, "MOBA camera, standing (1.5x crop)" if k == 0 else "MOBA camera, moving (1.5x crop)"])
	rows.append({ "title": "At the MOBA camera: pitch %d deg, %.1f u away, fov %d (cropped 480 x 360 from 1600 x 900, shown 1.5x)" % [int(MobaView.CAM_PITCH), MobaView.CAM_DIST, int(MobaView.CAM_FOV)], "cells": cells2 })
	vp2.queue_free()
	await _compose(out_dir.path_join(tag + "_look.png"), "G55 the champions' new look (%s)" % tag, rows, Vector2i(220, 280), 5)


func _ghost() -> void:
	var vp := _viewport(Vector2i(320, 300))
	_floor(vp)
	var ch := _champ(vp, "temu")
	_step(ch, 60)
	var cam := _cam(vp, false)
	cam.fov = 24.0
	var b := Basis.from_euler(Vector3(-0.35, PI * 0.25, 0))
	cam.global_transform = Transform3D(b, Vector3(0, 1.3, 0) + b.z * 9.0)
	var a := await _grab(vp)
	MobaDress.ghost(ch, true)
	var c := await _grab(vp)
	vp.queue_free()
	await _compose(out_dir.path_join(tag + "_ghost.png"), "G55 Temu hidden (his side's view) (%s)" % tag,
		[{ "title": "Temu: seen, then hidden (75% transparent; the opponent still sees nothing)", "cells": [[a, "seen"], [c, "hidden"]] }], Vector2i(320, 300), 2)
