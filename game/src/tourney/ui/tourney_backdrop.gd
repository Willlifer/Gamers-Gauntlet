class_name TourneyBackdrop
extends CanvasLayer
## Behind every tournament screen (G27): one of the games' maps, built once
## and cached, seen from a camera that circles it slowly. It renders into its
## own small world (SubViewport) so a game's WorldEnvironment never meets it,
## and a shader softens it (blur, a little grey, ink grade, vignette) so the
## UI reads on top. Hidden, and not rendered, while a game is on.
##   var bd := TourneyBackdrop.new(); add_child(bd); bd.show_map("rooftop")

const MAPS := ["rooftop", "dust_mid", "courtyard"]
const SPEED := TAU / 160.0                  ## one lap in ~2.7 minutes
## Which backdrop each game's matchup shows (games without a kit map keep the current one).
const FOR_GAME := { "fps_roof": "rooftop", "fps_mid": "dust_mid", "fps_campus": "campus", "mmo_raid": "courtyard" }

var current := ""
var _vp: SubViewport
var _rect: TextureRect
var _cam: Camera3D
var _maps := {}                             # id -> { node, focus, radius, height }
var _ang := 0.0

static var _shader: Shader


func _ready() -> void:
	layer = -10
	_vp = SubViewport.new()
	_vp.size = Vector2i(960, 540)
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 2000.0
	_vp.add_child(_cam)
	_cam.current = true
	var ink := ColorRect.new()                # until the first map lands
	ink.color = TourneyUI.INK
	ink.set_anchors_preset(Control.PRESET_FULL_RECT)
	ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ink)
	_rect = TextureRect.new()
	_rect.texture = _vp.get_texture()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _shader == null:
		_shader = load("res://src/tourney/ui/backdrop.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader
	_rect.material = m
	add_child(_rect)
	_ang = randf() * TAU


## Show a map (built on first use). "" or an unknown id: a random one.
func show_map(id: String = "") -> void:
	if id == "campus" and not GKGlb.exists("campus"):
		id = ""
	if not id in MAPS and id != "campus":
		id = MAPS[randi() % MAPS.size()]
	if id == current:
		return
	if current != "" and _maps.has(current):
		_vp.remove_child(_maps[current].node)
	if not _maps.has(id):
		_maps[id] = _build(id)
	_vp.add_child(_maps[id].node)
	current = id
	_place()


## The map as it circles (the load-in frames it, G42).
func map_texture() -> Texture2D:
	return _vp.get_texture()


## Off while a game runs: hidden and not rendering.
func set_active(on: bool) -> void:
	visible = on
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	set_process(on)


func _build(id: String) -> Dictionary:
	var root := Node3D.new()
	root.name = "Backdrop_" + id
	match id:
		"rooftop":
			var a := GKRegistry.build("rooftop")
			root.add_child(GKStage.outdoor(a.lights))
			root.add_child(a.instantiate(false))
			var h := float(a.meta.get("roof_height", 20.0))
			return { "node": root, "focus": Vector3(0, h, -12.0), "radius": 78.0, "height": 34.0 }
		"dust_mid":
			var a := GKRegistry.build("dust_mid")
			root.add_child(GKStage.outdoor(a.lights))
			root.add_child(a.instantiate(false))
			var pa: Array = a.meta.play_area
			var c := Vector3((float(pa[0]) + float(pa[2])) * 0.5, 0.0, (float(pa[1]) + float(pa[3])) * 0.5)
			return { "node": root, "focus": c + Vector3(0, 3.0, 0), "radius": 34.0, "height": 22.0 }
		"campus":
			var a := GKRegistry.build("campus")
			root.add_child(GKStage.outdoor(a.lights))
			root.add_child(a.instantiate(false))
			var pa: Array = a.meta.play_area
			var c := Vector3((float(pa[0]) + float(pa[2])) * 0.5, 0.0, (float(pa[1]) + float(pa[3])) * 0.5)
			return { "node": root, "focus": c + Vector3(0, 4.0, 0), "radius": 75.0, "height": 38.0 }
		_:
			root.add_child(GKStage.outdoor(MmoArena.lights()))
			MmoArena.build(root)
			return { "node": root, "focus": Vector3(0, 2.0, 0), "radius": 34.0, "height": 15.0 }


func _process(delta: float) -> void:
	_ang = fmod(_ang + SPEED * delta, TAU)
	_place()


func _place() -> void:
	if not _maps.has(current):
		return
	var m: Dictionary = _maps[current]
	var f: Vector3 = m.focus
	var r: float = m.radius
	var bob := sin(_ang * 2.0) * 0.06
	_cam.position = f + Vector3(cos(_ang) * r, float(m.height) * (1.0 + bob), sin(_ang) * r)
	_cam.look_at(f, Vector3.UP)
