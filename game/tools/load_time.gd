extends SceneTree
## Times `load()` of scripts in this fresh process (G66: startup cost).
##   SCRIPTS=res://a.gd,res://b.gd godot --headless --path . --script res://tools/load_time.gd
## Prints "load_ms <path> <ms>" per script, in order: the first pays for every
## script it pulls in; later ones pay only for what is new.


func _initialize() -> void:
	for p in OS.get_environment("SCRIPTS").split(",", false):
		var t := Time.get_ticks_usec()
		var r = load(p)
		print("load_ms %s %.1f%s" % [p, (Time.get_ticks_usec() - t) / 1000.0, "" if r else " (FAILED)"])
	quit(0)
