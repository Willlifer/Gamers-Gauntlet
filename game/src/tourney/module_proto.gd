extends Node
## Any tournament game on its own, you against a bot, no lobby or bracket:
##   godot --path . res://scenes/module.tscn -- --module pit
## Ids: bw_twins, aram, pit, fps_roof, mmo_raid (TourneyModules). When the
## game ends its result prints and the same game starts again.

var _mod: TourneyModule
var _round := 0


func _ready() -> void:
	BWSettings.init(true)
	BWMusic.ensure(self)
	TourneyMusic.ensure(self)
	BWSettings.apply_all()
	_new()


func _id() -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--module")
	return args[i + 1] if i >= 0 and i + 1 < args.size() else "mmo_raid"


func _new() -> void:
	if _mod:
		_mod.queue_free()
	_round += 1
	var script := TourneyModules.script_for(_id())
	if script == null:
		push_error("module_proto: no module '%s'; ids: %s" % [_id(), TourneyModules.infos().map(func(i): return i.id)])
		get_tree().quit(1)
		return
	_mod = script.new()
	_mod.finished.connect(func(r: Dictionary) -> void:
		print("[%s] %s" % [_id(), r.summary])
		get_tree().create_timer(3.0).timeout.connect(_new))
	add_child(_mod)
	TourneyMusic.play("hype")
	_mod.setup({ "id": "proto", "seed": 2000 + _round, "players": [
		{ "id": "you", "name": "You", "bot": false }, { "id": "rival", "name": "Rival", "bot": true }],
		"binds": TourneyState.load_binds(), "sens": TourneyState.load_sens() })
