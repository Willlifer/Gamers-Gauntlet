extends Node
## The raid alone, outside the tournament: the class pick, then the fight;
## when it ends, the verdict and back to the pick.
##   godot --path . res://scenes/mmo_proto.tscn

var _mod: MmoModule
var _round := 0


func _ready() -> void:
	_new()


func _new() -> void:
	if _mod:
		_mod.queue_free()
	_round += 1
	_mod = MmoModule.new()
	_mod.finished.connect(func(r: Dictionary) -> void:
		print("[mmo] ", r.summary)
		get_tree().create_timer(3.0).timeout.connect(_new))
	add_child(_mod)
	_mod.setup({ "id": "proto", "seed": 1000 + _round, "players": [
		{ "id": "you", "name": "You", "bot": false }, { "id": "rival", "name": "Rival", "bot": true }] })
