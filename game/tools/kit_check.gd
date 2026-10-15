extends SceneTree
## Headless: compile every kit script (fast feedback while authoring).
func _initialize() -> void:
	var bad := 0
	for d in ["res://src/kit", "res://src/kit/items", "res://src/kit/envs", "res://src/kit/bench", "res://src/kit/bw", "res://src", "res://src/tourney", "res://src/tourney/screens", "res://src/tourney/fps", "res://src/tourney/mmo", "res://src/tourney/moba", "res://src/tourney/modules"]:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			if f.ends_with(".gd"):
				var sc := load(d.path_join(f)) as GDScript
				if sc == null or not sc.can_instantiate():
					print("FAIL ", d.path_join(f))
					bad += 1
	print("kit_check: %d failing" % bad)
	quit(1 if bad else 0)
