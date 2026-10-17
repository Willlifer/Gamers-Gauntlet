class_name FpsNav
extends NavigationRegion3D
## The FPS bot's navigation (G62): a NavigationMesh baked at match start
## from the map's own colliders (the kit levels are boxes: roofs, ramps,
## the bridge deck, crates, the campus's COL_ boxes; the invisible barrier
## walls count too, so the mesh stops at the parapet fences). The bake is
## bounded to the play volume (`filter_baking_aabb`) so the rooftop's
## streets and the city ground stay out of it.
##   path(from, to)      the waypoints to walk (empty when the map isn't ready)
##   reachable(from, to) the path ends within ARRIVE of `to`
##   random_point()      a point on the mesh
##   snap(p)             the nearest point on the mesh
## Bushes are not colliders, so the campus mesh runs through them (the bot
## walks through leaves like you do).

const CELL := 0.25
const AGENT_RADIUS := 0.5
const AGENT_HEIGHT := 2.0
## A CharacterBody3D doesn't step up: only slopes and kerbs under a cell (the capsule rolls over those).
const CLIMB := 0.25
const ARRIVE := 1.5

var polygons := 0


## Bake the mesh for `map` (its instantiated node `node`, in the tree).
func bake(map: GKAsset, node: Node3D) -> void:
	var nm := NavigationMesh.new()
	nm.cell_size = CELL                         # both match the navigation map's defaults (0.25)
	nm.cell_height = 0.25
	nm.agent_radius = AGENT_RADIUS
	nm.agent_height = AGENT_HEIGHT
	nm.agent_max_climb = CLIMB
	nm.agent_max_slope = 50.0
	nm.filter_ledge_spans = true               # keep paths off the ramps' and roofs' edges
	nm.filter_walkable_low_height_spans = true
	nm.region_min_size = 4.0
	nm.edge_max_length = 8.0
	nm.edge_max_error = 1.0
	nm.detail_sample_distance = 4.0
	nm.detail_sample_max_error = 1.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1 | GKAsset.BARRIER_LAYER
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.filter_baking_aabb = bounds(map)
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, node)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	navigation_mesh = nm
	polygons = nm.get_polygon_count()
	_synced = false
	_armed = false
	if polygons > 0:
		_probe_v = nm.get_vertices()[0]
	# the server takes the region on a later physics frame (map_changed):
	# nothing queries the map before that signal. The map's iteration may
	# still be building after it (on a thread), so ready() then checks the
	# mesh is really there: the nearest point to one of its own vertices.
	if not NavigationServer3D.map_changed.is_connected(_on_map_changed):
		NavigationServer3D.map_changed.connect(_on_map_changed)


var _synced := false
var _armed := false                         # map_changed has fired since the bake
var _probe_v := Vector3.INF


func _on_map_changed(map: RID) -> void:
	if map == get_navigation_map() and polygons > 0:
		_armed = true


## The play volume to bake: the roofs with the floor below (rooftop); on
## any other map the play area (xz, 2 m margin) over the span of the map's
## own colliders (y, so hills and halls are in; a map with none bakes
## -2..14 m).
static func bounds(map: GKAsset) -> AABB:
	var m := map.meta
	if m.has("roofs"):
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for side in ["a", "b"]:
			for r in (m.roofs[side] as Array):
				lo.x = minf(lo.x, float(r[0]))
				lo.z = minf(lo.z, float(r[1]))
				hi.x = maxf(hi.x, float(r[2]))
				hi.z = maxf(hi.z, float(r[3]))
		lo.y = float(m.get("floor_height", float(m.roof_height) - 4.0)) - 1.0
		hi.y = float(m.roof_height) + 4.0
		return AABB(lo - Vector3(1, 0, 1), hi - lo + Vector3(2, 0, 2))
	var pa: Array = m.get("play_area", [-60, -60, 60, 60])
	var y0 := INF
	var y1 := -INF
	for c in map.colliders:
		var xf: Transform3D = c.xform
		var half: Vector3 = (c.size as Vector3) * 0.5
		var ext := (xf.basis * Vector3(half.x, 0, 0)).abs() + (xf.basis * Vector3(0, half.y, 0)).abs() + (xf.basis * Vector3(0, 0, half.z)).abs()
		y0 = minf(y0, xf.origin.y - ext.y)
		y1 = maxf(y1, xf.origin.y + ext.y)
	if "trimeshes" in map:
		for t in map.get("trimeshes"):
			var mesh: ArrayMesh = t.mesh
			var box: AABB = (t.xform as Transform3D) * mesh.get_aabb()
			y0 = minf(y0, box.position.y)
			y1 = maxf(y1, box.end.y)
	if y0 == INF:
		y0 = -2.0
		y1 = 14.0
	return AABB(Vector3(float(pa[0]) - 2.0, y0 - 1.0, float(pa[1]) - 2.0), Vector3(float(pa[2]) - float(pa[0]) + 4.0, y1 - y0 + 3.0, float(pa[3]) - float(pa[1]) + 4.0))


## The mesh is baked and the server has taken it: map_changed has fired and
## a query finds the mesh (see bake).
func ready() -> bool:
	if polygons <= 0 or not is_inside_tree() or not _armed:
		return false
	if not _synced:
		_synced = NavigationServer3D.map_get_closest_point(get_navigation_map(), _probe_v).distance_to(_probe_v) < 0.3
	return _synced


func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not ready():
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(get_navigation_map(), from, to, true)


func snap(p: Vector3) -> Vector3:
	if not ready():
		return p
	return NavigationServer3D.map_get_closest_point(get_navigation_map(), p)


func reachable(from: Vector3, to: Vector3) -> bool:
	var pth := path(from, to)
	return pth.size() >= 2 and pth[pth.size() - 1].distance_to(to) < ARRIVE


## A point on the mesh (anywhere; the caller checks it is reachable).
func random_point() -> Vector3:
	if not ready():
		return Vector3.INF
	return NavigationServer3D.map_get_random_point(get_navigation_map(), 1, false)


## Walking distance along the path from `from` to `to` (INF when unreachable).
func walk_length(from: Vector3, to: Vector3) -> float:
	var pth := path(from, to)
	if pth.size() < 2 or pth[pth.size() - 1].distance_to(to) >= ARRIVE:
		return INF
	var d := 0.0
	for i in pth.size() - 1:
		d += pth[i].distance_to(pth[i + 1])
	return d
