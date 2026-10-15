extends SceneTree
## Windowed: the reference-gauntlet frames for Gauntlet Kit assets (G16). Each
## asset is built from its defaults (or PRESET), shot from fixed cameras and
## laid out on one sheet beside its reference image:
##   items  row 1: the reference | ours from the reference's angle
##          row 2: right side | left side      row 3: top | 3/4 front | 3/4 rear
##   envs   row 1: the reference | ours from the reference's camera
##          row 2: overview from above | eye level A | eye level B
## Same build, same cameras, every run, so rounds compare like for like.
##   godot --path . --script res://tools/kit_ref_shots.gd
## ASSETS=sniper,shotgun (default all), TAG=r0 (default "now"),
## SHOTS=<dir> (default ../design/shots/kit), PRESET=<name>, FULL=1 also
## saves every single view at full size.

const W := 1600
const H := 900
const REF_DIR := "../design/ref/kit"

## Item reference angles: the asset turned so its muzzle points where the
## photo's does, seen from the photo's side. side: +1 = the gun's left (+x).
const ITEM_REF := {
	"sniper": { "img": "sniper.jpg", "side": 1.0, "tilt": 27.0, "elev": 10.0, "yaw": 8.0 },
	"shotgun": { "img": "shotgun.jpg", "side": -1.0, "tilt": 50.0, "elev": 6.0, "yaw": 0.0 },
	"slingshot": { "img": "slingshot.jpg", "front": true, "tilt": 0.0, "elev": 4.0, "yaw": 0.0 },
}
const ENV_REF := { "dust_mid": "dust_mid.jpg", "rooftop": "rooftop.png" }

var out := ""
var tag := "now"
var full := false
var stage_root: Node3D
var cam: Camera3D


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../design/shots/kit").simplify_path()
	if OS.get_environment("TAG") != "":
		tag = OS.get_environment("TAG")
	full = OS.get_environment("FULL") == "1"
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(W, H))
	_go.call_deferred()


func _go() -> void:
	var want := OS.get_environment("ASSETS")
	var ids := GKRegistry.ids() if want == "" else PackedStringArray(want.split(","))
	var fails := 0
	for asset_id in ids:
		var d := GKRegistry.def(asset_id)
		if d == null:
			push_error("kit_ref_shots: no asset " + asset_id)
			fails += 1
			continue
		var p := d.preset(OS.get_environment("PRESET"))
		var t0 := Time.get_ticks_msec()
		var a := d.build(p)
		print("%s: %d tris, %d parts, built in %d ms" % [asset_id, a.triangle_count(), a.parts.size(), Time.get_ticks_msec() - t0])
		for w in a.warnings:
			print("  warning: ", w)
		if a.parts.is_empty():
			print("  (nothing built yet)")
			continue
		if a.kind == "env":
			await _env_sheet(a)
		else:
			await _item_sheet(a)
	quit(1 if fails > 0 else 0)


# ----------------------------------------------------------------- items

func _item_sheet(a: GKAsset) -> void:
	var r: Dictionary = ITEM_REF.get(a.id, { "side": 1.0, "tilt": 0.0, "elev": 10.0, "yaw": 0.0 })
	stage_root = Node3D.new()
	root.add_child(stage_root)
	stage_root.add_child(GKStage.studio())
	var pivot := Node3D.new()
	stage_root.add_child(pivot)
	var inst := a.instantiate(false)
	pivot.add_child(inst)
	cam = Camera3D.new()
	cam.fov = 14.0
	cam.far = 200.0
	stage_root.add_child(cam)
	cam.make_current()
	var views := {}
	# the reference angle: muzzle tilted up by `tilt`, seen from the photo's side
	if r.get("front", false):
		pivot.rotation_degrees = Vector3(0, float(r.yaw), 0)
		views["ref"] = await _frame(pivot, inst, Vector3(0, sin(deg_to_rad(float(r.elev))), 1).normalized(), 800.0 / 450.0)
	else:
		var side: float = r.side
		pivot.basis = Basis(Vector3.UP, deg_to_rad(float(r.yaw))) * Basis(Vector3.RIGHT, deg_to_rad(-float(r.tilt)))
		var dir := Vector3(side, sin(deg_to_rad(float(r.elev))), 0).normalized()
		views["ref"] = await _frame(pivot, inst, dir, 800.0 / 450.0)
	pivot.basis = Basis.IDENTITY
	views["right"] = await _frame(pivot, inst, Vector3(-1, 0.02, 0).normalized(), 800.0 / 375.0)
	views["left"] = await _frame(pivot, inst, Vector3(1, 0.02, 0).normalized(), 800.0 / 375.0)
	views["top"] = await _frame(pivot, inst, Vector3(0, 1, 0), 533.0 / 375.0, Vector3.RIGHT)
	views["front"] = await _frame(pivot, inst, Vector3(-0.55, 0.42, 0.7).normalized(), 533.0 / 375.0)
	views["rear"] = await _frame(pivot, inst, Vector3(0.6, 0.38, -0.7).normalized(), 533.0 / 375.0)
	var sheet := Image.create(W, 1200, false, Image.FORMAT_RGB8)
	sheet.fill(Color("#202226"))
	_paste(sheet, _ref_image(str(r.get("img", ""))), Rect2i(0, 0, 800, 450))
	_paste(sheet, views["ref"], Rect2i(800, 0, 800, 450))
	_paste(sheet, views["right"], Rect2i(0, 450, 800, 375))
	_paste(sheet, views["left"], Rect2i(800, 450, 800, 375))
	_paste(sheet, views["top"], Rect2i(0, 825, 533, 375))
	_paste(sheet, views["front"], Rect2i(533, 825, 533, 375))
	_paste(sheet, views["rear"], Rect2i(1066, 825, 534, 375))
	sheet.save_png(out.path_join("%s_%s.png" % [tag, a.id]))
	if full:
		for k in views:
			(views[k] as Image).save_png(out.path_join("%s_%s_%s.png" % [tag, a.id, k]))
	print("sheet ", a.id)
	stage_root.queue_free()
	await process_frame


## Aim the camera along -dir at the asset, at a distance that fits its box
## in a frame of `aspect`, and return that frame cropped from the window.
func _frame(_pivot: Node3D, inst: Node3D, dir: Vector3, aspect: float, up := Vector3.UP) -> Image:
	await process_frame
	var box := _world_aabb(inst)
	var c := box.get_center()
	if absf(dir.dot(up)) > 0.95:
		up = Vector3.FORWARD
	var basis := Basis.looking_at(-dir, up)
	var half_w := 0.0
	var half_h := 0.0
	var depth := 0.0
	for i in 8:
		var p := box.get_endpoint(i) - c
		half_w = maxf(half_w, absf(p.dot(basis.x)))
		half_h = maxf(half_h, absf(p.dot(basis.y)))
		depth = maxf(depth, absf(p.dot(basis.z)))
	# the fov is vertical over a 16:9 window; _grab crops to `aspect`
	var t := tan(deg_to_rad(cam.fov * 0.5))
	var wide := float(W) / float(H)
	var need_h := 0.0
	if aspect >= wide:
		need_h = maxf(half_h * aspect / wide, half_w / wide)
	else:
		need_h = maxf(half_h, half_w / aspect)
	need_h *= 1.1
	var dist := need_h / t + depth
	cam.basis = basis
	cam.position = c + dir * dist
	cam.near = maxf(dist * 0.02, 0.01)
	return await _grab(aspect)


func _world_aabb(n: Node) -> AABB:
	var out_box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.global_transform * m.get_aabb()
		out_box = b if first else out_box.merge(b)
		first = false
	return out_box


## The window, cropped to the centre `aspect` (the camera's fov is vertical,
## so the crop keeps the full height when the aspect is narrower than 16:9).
func _grab(aspect: float) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var iw := img.get_width()
	var ih := img.get_height()
	var cw := iw
	var ch := int(round(iw / aspect))
	if ch > ih:
		ch = ih
		cw = int(round(ih * aspect))
	return img.get_region(Rect2i((iw - cw) / 2, (ih - ch) / 2, cw, ch))


func _ref_image(file: String) -> Image:
	if file == "":
		return null
	var path := ProjectSettings.globalize_path("res://").path_join(REF_DIR).path_join(file).simplify_path()
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		push_warning("kit_ref_shots: no reference at " + path)
		return null
	img.convert(Image.FORMAT_RGB8)
	return img


## Fit `img` inside `cell` (letterboxed), keeping its aspect.
func _paste(sheet: Image, img: Image, cell: Rect2i) -> void:
	if img == null:
		return
	var im := img.duplicate() as Image
	im.convert(Image.FORMAT_RGB8)
	var k := minf(float(cell.size.x) / im.get_width(), float(cell.size.y) / im.get_height())
	var sz := Vector2i(maxi(int(im.get_width() * k), 1), maxi(int(im.get_height() * k), 1))
	im.resize(sz.x, sz.y, Image.INTERPOLATE_LANCZOS)
	sheet.blit_rect(im, Rect2i(Vector2i.ZERO, sz), cell.position + (cell.size - sz) / 2)


# ----------------------------------------------------------------- envs

func _env_sheet(a: GKAsset) -> void:
	stage_root = Node3D.new()
	root.add_child(stage_root)
	stage_root.add_child(GKStage.outdoor(a.lights))
	var inst := a.instantiate(false)
	stage_root.add_child(inst)
	cam = Camera3D.new()
	cam.far = 1500.0
	stage_root.add_child(cam)
	cam.make_current()
	var views := {}
	views["ref"] = await _env_view(a, "ref_cam", 800.0 / 450.0)
	views["eye_a"] = await _env_view(a, "eye_a", 533.0 / 450.0)
	views["eye_b"] = await _env_view(a, "eye_b", 533.0 / 450.0)
	# overview: straight down, orthographic, over the playable part (the
	# colliders' bounds; the scenery may run to the horizon)
	var box := a.aabb()
	if not a.colliders.is_empty():
		var first := true
		for c in a.colliders:
			var cb := AABB((c.xform as Transform3D).origin - (c.size as Vector3) * 0.5, c.size)
			box = cb if first else box.merge(cb)
			first = false
		box = box.grow(6.0)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(box.size.z, box.size.x / (533.0 / 450.0)) * 1.05
	cam.basis = Basis.looking_at(Vector3.DOWN, Vector3.FORWARD)
	cam.position = box.get_center() + Vector3(0, box.size.y + 50.0, 0)
	cam.near = 1.0
	views["over"] = await _grab(533.0 / 450.0)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	var sheet := Image.create(W, 900, false, Image.FORMAT_RGB8)
	sheet.fill(Color("#202226"))
	_paste(sheet, _ref_image(str(ENV_REF.get(a.id, ""))), Rect2i(0, 0, 800, 450))
	_paste(sheet, views["ref"], Rect2i(800, 0, 800, 450))
	_paste(sheet, views["over"], Rect2i(0, 450, 533, 450))
	_paste(sheet, views["eye_a"], Rect2i(533, 450, 533, 450))
	_paste(sheet, views["eye_b"], Rect2i(1066, 450, 534, 450))
	sheet.save_png(out.path_join("%s_%s.png" % [tag, a.id]))
	if full:
		for k in views:
			(views[k] as Image).save_png(out.path_join("%s_%s_%s.png" % [tag, a.id, k]))
	print("sheet ", a.id)
	stage_root.queue_free()
	await process_frame


## A camera marker: its transform, its fov in meta "<name>_fov" (default 60).
func _env_view(a: GKAsset, mk: String, aspect: float) -> Image:
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.transform = a.marker(mk)
	cam.fov = float(a.meta.get(mk + "_fov", 60.0))
	cam.near = 0.05
	# vertical fov is for 16:9; keep the reference's framing in narrower cells
	return await _grab(aspect)
