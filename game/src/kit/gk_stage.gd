class_name GKStage
extends RefCounted
## Light and sky for kit assets (the rendering side of the kit). Two stages:
## studio() for items (the light-grey product-photo sweep the references are
## shot on: key, fill and rim, a neutral sky for metal to reflect), and
## outdoor(lights) for environments, from the numbers an env asset carries
## (sun direction and colour, sky colours, fog). Both return one Node3D to add
## beside the asset and free with it.

static func studio(bg := Color("#ececec")) -> Node3D:
	var root := Node3D.new()
	root.name = "GKStudio"
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#d9dde2")
	sm.sky_horizon_color = Color("#f2f2f2")
	sm.ground_bottom_color = Color("#6a6a6a")
	sm.ground_horizon_color = Color("#d0d0d0")
	sky.sky_material = sm
	env.sky = sky
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 0.08
	env.ssao_intensity = 1.2
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.rotation_degrees = Vector3(-50, -35, 0)
	key.light_energy = 1.5
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 6.0
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-15, 140, 0)
	fill.light_energy = 0.45
	fill.light_color = Color("#dfe8ff")
	root.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.rotation_degrees = Vector3(-25, 180, 0)
	rim.light_energy = 0.9
	root.add_child(rim)
	return root


## lights: { sun_dir: [x,y,z] (pointing from the sun), sun_col, sun_energy,
##   sky_top, sky_horizon, ground, ambient, ambient_col, sky_share (0-1),
##   fog_col, fog_density, exposure, saturation, contrast, shadow_dist, ssil }
static func outdoor(lights: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "GKOutdoor"
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(str(lights.get("sky_top", "#4f86c6")))
	sm.sky_horizon_color = Color(str(lights.get("sky_horizon", "#b9cfe0")))
	sm.ground_horizon_color = Color(str(lights.get("sky_horizon", "#b9cfe0")))
	sm.ground_bottom_color = Color(str(lights.get("ground", "#5a5040")))
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(lights.get("ambient", 0.8))
	# a clear sky alone makes every shadow blue; mix in a warm bounce colour
	env.ambient_light_color = Color(str(lights.get("ambient_col", "#b9b2a4")))
	env.ambient_light_sky_contribution = float(lights.get("sky_share", 0.45))
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = float(lights.get("exposure", 1.0))
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = float(lights.get("ssao", 1.6))
	env.ssil_enabled = bool(lights.get("ssil", true))
	env.ssil_intensity = 0.6
	env.fog_enabled = float(lights.get("fog_density", 0.0)) > 0.0
	env.fog_light_color = Color(str(lights.get("fog_col", "#c8d6e2")))
	env.fog_density = float(lights.get("fog_density", 0.0))
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.5
	env.adjustment_enabled = true
	env.adjustment_saturation = float(lights.get("saturation", 1.0))
	env.adjustment_contrast = float(lights.get("contrast", 1.0))
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	var d: Array = lights.get("sun_dir", [-0.4, -0.7, 0.3])
	var dir := Vector3(float(d[0]), float(d[1]), float(d[2])).normalized()
	sun.basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.BACK)
	sun.light_color = Color(str(lights.get("sun_col", "#fff1dc")))
	sun.light_energy = float(lights.get("sun_energy", 1.4))
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = float(lights.get("shadow_dist", 120.0))
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_blur = 1.2
	sun.shadow_bias = float(lights.get("shadow_bias", 0.06))
	sun.shadow_normal_bias = float(lights.get("normal_bias", 0.9))
	root.add_child(sun)
	return root
