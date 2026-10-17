class_name FpsMuzzleFlash
extends Node3D
## A gunshot's flash (G51), after design/ref/kit/muzzle_flash.png: a
## white-hot core just ahead of the muzzle, a ragged, fibrous cloud thrown
## forward and out, a warm orange glow round it. Built as three crossed planes
## along the barrel (the plume, seen from the side) and one plane across it
## (the burst, seen down the barrel from first person), additive, on a
## hand-built flipbook (G61: art/fx/muzzle_flash_side.png and _star.png from
## tools/fx_flash_flipbook.py, VARIANTS frames each, drawn tongues and
## fibres after the reference; the procedural textures below are the
## fallback when the sheets are missing). Shots pick a frame from a seed, so
## they differ but review frames repeat. A plane fades as it turns edge-on,
## so no bright seam shows.
## No black: the textures' darkness is their transparency (luminance keyed
## to alpha), so no dark quad shows over the sky or inside the view model's
## transparent viewport (the author, 10-16).
## Local +Z is the barrel's forward; `size` scales it per gun
## (FpsWeapons.SPECS[*].flash). pop() fires it; it fades over LIFE.
## Review frames: tools/fps_flash_shots.gd (the reference-gauntlet loop).

const VARIANTS := 4
const LIFE := 0.07
const PLUME := Vector2(0.40, 0.18)           ## plume length ahead, half height (m at size 1)
const STAR := 0.12                          ## the burst's half size (m at size 1)
const SHEET_SIDE := "res://art/fx/muzzle_flash_side.png"
const SHEET_STAR := "res://art/fx/muzzle_flash_star.png"

var size := 1.0
var layer := 1
var roll := 0.0                             ## this shot's turn about the barrel (a parent that re-places it each frame applies it)
var _t := 1.0
var _planes: Array[MeshInstance3D] = []
var _star: MeshInstance3D
var _mats_side: Array[ShaderMaterial] = []
var _mat_star: ShaderMaterial
var _rng := RandomNumberGenerator.new()

static var _side_tex: Array[Texture2D] = []
static var _star_tex: Array[Texture2D] = []
static var _sheet := false                  ## the flipbook sheets loaded (frames side by side)
static var _shaders: Array[Shader] = []


func _ready() -> void:
	_textures()
	for k in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = _plane_mesh()
		var m := _mat(_side_tex[0])
		_mats_side.append(m)
		mi.material_override = m
		mi.rotation.z = k * PI / 3.0
		mi.layers = layer
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_planes.append(mi)
	_star = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 2.0
	_star.mesh = q
	_mat_star = _mat(_star_tex[0])
	_star.material_override = _mat_star
	_star.layers = layer
	_star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_star)
	visible = false


func _mat(tex: Texture2D) -> ShaderMaterial:
	if _shaders.is_empty():
		for top in [false, true]:
			var sh := Shader.new()
			sh.code = SHADER % (", depth_test_disabled" if top else "")
			_shaders.append(sh)
	var m := ShaderMaterial.new()
	# the view model's flash draws over its own gun (in first person the
	# barrel would hide the root of it); in the world it depth-tests
	m.shader = _shaders[1 if layer != 1 else 0]
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("frame", Vector2(0.0, 1.0 / VARIANTS if _sheet else 1.0))
	m.render_priority = 1
	return m


const SHADER := """shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled, depth_draw_never%s;
uniform sampler2D tex : source_color, filter_linear, repeat_disable;
uniform vec2 frame = vec2(0.0, 1.0);   // this shot's frame on the sheet: u offset, u width
uniform float alpha = 1.0;
// The textures are light on black. Black must be see-through everywhere,
// also in the view model's transparent viewport, where an additive quad
// would leave a black box (the author, 10-16): so the brightness becomes
// the alpha and the colour is un-premultiplied, a mix blend that adds light.
void fragment() {
	float facing = smoothstep(0.08, 0.55, abs(dot(NORMAL, VIEW)));
	vec3 c = texture(tex, vec2(frame.x + UV.x * frame.y, UV.y)).rgb;
	float a = clamp(max(c.r, max(c.g, c.b)), 0.0, 1.0);
	ALBEDO = min(c / max(a, 0.001) * 1.15, vec3(1.0));
	ALPHA = min(1.0, pow(a, 0.5) * 1.2) * alpha * facing;
}
"""


## The plume's plane: u runs from just behind the muzzle (0) out ahead (1),
## v across; in local x-z with z forward.
static func _plane_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z0 := -0.08
	var z1 := 1.0
	var pts := [Vector3(-1, 0, z0), Vector3(1, 0, z0), Vector3(1, 0, z1), Vector3(-1, 0, z1)]
	var uvs := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uvs[i])
		st.set_normal(Vector3.UP)
		st.add_vertex(pts[i])
	return st.commit()


## Fire it. `seed_` picks the variant and roll (pass one for a fixed frame).
func pop(seed_ := -1) -> void:
	if seed_ >= 0:
		_rng.seed = seed_
	else:
		_rng.randomize()
	_t = 0.0
	visible = true
	var v := _rng.randi() % VARIANTS
	for k in _mats_side.size():
		var f := (v + k) % VARIANTS
		_mats_side[k].set_shader_parameter("tex", _side_tex[0 if _sheet else f])
		_mats_side[k].set_shader_parameter("frame", Vector2(float(f) / VARIANTS if _sheet else 0.0, 1.0 / VARIANTS if _sheet else 1.0))
	_mat_star.set_shader_parameter("tex", _star_tex[0 if _sheet else v])
	_mat_star.set_shader_parameter("frame", Vector2(float(v) / VARIANTS if _sheet else 0.0, 1.0 / VARIANTS if _sheet else 1.0))
	roll = _rng.randf() * TAU
	rotation.z = roll
	_shape(0.0)


func _process(delta: float) -> void:
	if _t >= 1.0:
		return
	_t = minf(1.0, _t + delta / LIFE)
	_shape(_t)
	if _t >= 1.0:
		visible = false


## t 0..1: the cloud pushes out a little and the light dies.
func _shape(t: float) -> void:
	var grow := lerpf(0.85, 1.15, t)
	var a := 1.0 - t * t
	for p in _planes:
		p.scale = Vector3(PLUME.y * size * grow, 1.0, PLUME.x * size * grow)
	_star.scale = Vector3.ONE * STAR * size * lerpf(0.9, 1.1, t)
	_star.position.z = 0.03 * size
	for m in _mats_side:
		m.set_shader_parameter("alpha", a)
	_mat_star.set_shader_parameter("alpha", a * 0.85)


# ------------------------------------------------------------- textures

## Build the textures ahead of the first shot (FpsWorld does, on load).
static func warm() -> void:
	_textures()


static func _textures() -> void:
	if not _side_tex.is_empty():
		return
	if ResourceLoader.exists(SHEET_SIDE) and ResourceLoader.exists(SHEET_STAR):
		var a := load(SHEET_SIDE) as Texture2D
		var b := load(SHEET_STAR) as Texture2D
		if a and b:
			_side_tex.append(a)
			_star_tex.append(b)
			_sheet = true
			return
	for k in VARIANTS:
		_side_tex.append(ImageTexture.create_from_image(_plume_image(101 + k * 17)))
		_star_tex.append(ImageTexture.create_from_image(_star_image(303 + k * 29)))


## Colour for a heat value: white-hot, pale gold, orange, deep red, nothing.
static func _heat(h: float) -> Color:
	h = maxf(h, 0.0)
	var c: Color
	if h > 0.8:
		c = Color(1.0, 0.94, 0.82).lerp(Color(1, 1, 0.98), clampf((h - 0.8) / 0.3, 0.0, 1.0))
	elif h > 0.5:
		c = Color(1.0, 0.74, 0.36).lerp(Color(1.0, 0.94, 0.82), (h - 0.5) / 0.3)
	else:
		c = Color(1.0, 0.42, 0.08).lerp(Color(1.0, 0.74, 0.36), h / 0.5)
	return c * minf(1.0, h * 1.6)


## Smooth value noise on a lattice, seeded.
static func _noise(x: float, y: float, s: int) -> float:
	var xi := floori(x)
	var yi := floori(y)
	var fx := x - xi
	var fy := y - yi
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _hash(xi, yi, s)
	var b := _hash(xi + 1, yi, s)
	var c := _hash(xi, yi + 1, s)
	var d := _hash(xi + 1, yi + 1, s)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


static func _hash(x: int, y: int, s: int) -> float:
	var h := (x * 374761393 + y * 668265263 + s * 2147483) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


static func _fbm(x: float, y: float, s: int) -> float:
	return _noise(x, y, s) * 0.55 + _noise(x * 2.1, y * 2.1, s + 1) * 0.3 + _noise(x * 4.3, y * 4.3, s + 2) * 0.15


## The cloud's heat at polar (ang, r) round its centre: a ragged edge from
## noise on the angle, fibres from noise stretched along the radius.
static func _cloud(ang: float, r: float, reach: float, s: int) -> float:
	var cx := cos(ang)
	var sy := sin(ang)
	var edge := reach * (0.62 + 0.75 * _fbm(cx * 1.2 + 3.0, sy * 1.2 + 5.0, s))
	# 4-6 tongues with gaps between them (the reference's few big petals)
	var n := 4.0 + float(s % 3)
	var lobe := pow(absf(cos(ang * n * 0.5 + float(s % 7))), 1.6)
	edge *= 0.5 + 0.7 * lobe
	var fib := _fbm(cx * 7.0 + 11.0 + r * 1.5 * cx, sy * 7.0 + r * 1.5 * sy, s + 7)
	var q := r / maxf(edge, 0.01) + (fib - 0.5) * 0.7
	var k := clampf(1.0 - q, 0.0, 1.0)
	# eroded, wispy tips: fine noise eats the thin outer part
	var ero := _fbm(cx * 18.0 + r * 9.0, sy * 18.0 - r * 7.0, s + 13)
	return k * smoothstep(0.0, 0.35, k + ero * 0.3 - 0.12)


## The side plume (u forward from the muzzle at U0, v across).
static func _plume_image(seed_: int) -> Image:
	var W := 256
	var H := 128
	const U0 := 0.074
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var c0 := Vector2(0.3, rng.randf_range(-0.03, 0.03))
	# a few long feathered tendrils past the cloud, thrown unevenly
	var tendrils: Array = []
	for i in rng.randi_range(4, 7):
		var ang := rng.randf_range(-1.25, 1.25) + (0.25 if i % 2 == 0 else -0.25)
		tendrils.append([ang, rng.randf_range(0.5, 0.95) * (1.0 - 0.3 * absf(ang)), rng.randf_range(0.025, 0.05), rng.randf() * 50.0])
	for y in H:
		for x in W:
			var u := x / float(W - 1)
			var v := (y / float(H - 1)) * 2.0 - 1.0
			# plume units: forward f (0..1), across (the plane is ~2x longer than half high)
			var p := Vector2((u - U0) / (1.0 - U0), v * 0.5)
			var d := p - c0
			var ang := atan2(d.y, d.x)
			# forward-biased reach: long ahead, shorter to the sides, short behind
			var reach := 0.34 * (0.62 + 0.5 * cos(ang)) + 0.05
			var k := _cloud(ang, Vector2(d.x * 0.85, d.y * 1.15).length(), reach, seed_)
			var heat := pow(k, 0.9) * 0.95
			for t: Array in tendrils:
				var dir := Vector2(cos(t[0]), sin(t[0]))
				var along := p.dot(dir)
				if along > 0.05:
					var across := absf(p.dot(Vector2(-dir.y, dir.x)))
					var w: float = float(t[2]) * (0.6 + along * 1.4) * (0.6 + 0.8 * _noise(along * 14.0, float(t[3]), seed_ + 3))
					var tip := clampf(1.0 - along / float(t[1]), 0.0, 1.0)
					heat += exp(-pow(across / maxf(w, 0.003), 2.0)) * pow(tip, 0.6) * 0.75
			# the neck: a tight hot jet from the muzzle into the cloud
			if p.x > -0.02 and p.x < 0.35:
				heat += exp(-pow(p.y / (0.03 + p.x * 0.18), 2.0)) * clampf((p.x + 0.02) * 20.0, 0.0, 1.0) * 0.7
			var glow := exp(-pow(Vector2(d.x * 0.9, d.y * 1.3).length() / 0.24, 2.0)) * 0.1
			if p.x < 0.0:
				heat *= clampf(1.0 + p.x * 10.0, 0.0, 1.0)
				glow *= clampf(1.0 + p.x * 4.0, 0.0, 1.0)
			var c := _heat(heat) + Color(1.0, 0.42, 0.07) * glow
			var e := smoothstep(0.0, 1.0, clampf(minf(minf(u, 1.0 - u) * 5.0, (1.0 - absf(v)) * 3.0), 0.0, 1.0))
			c = c * e
			img.set_pixel(x, y, Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0), 1.0))
	return img


## Down the barrel: a white core, the same ragged fibrous cloud all round,
## an orange halo.
static func _star_image(seed_: int) -> Image:
	var N := 128
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var p := Vector2(x / float(N - 1) * 2.0 - 1.0, y / float(N - 1) * 2.0 - 1.0)
			var r := p.length()
			var k := _cloud(atan2(p.y, p.x), r, 0.55, seed_)
			var heat := pow(k, 0.85) * 1.1 + exp(-pow(r / 0.13, 2.0)) * 0.6
			var glow := exp(-pow(r / 0.34, 2.0)) * 0.16
			var c := _heat(heat) + Color(1.0, 0.42, 0.07) * glow
			c = c * clampf((1.0 - r) * 4.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0), 1.0))
	return img
