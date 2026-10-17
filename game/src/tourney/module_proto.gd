extends Node
## Any tournament game on its own, you against a bot, no lobby or bracket:
##   godot --path . res://scenes/module.tscn -- --module pit
## Ids: any in TourneyModules.POOL (bw_twins, fps_roof, fps_mid, fps_campus,
## mmo_raid_easy, mmo_raid, mmo_tanks, osrs_easy, osrs_raid) or SHELVED (aram,
## pit: out of the roll since G60, still playable here). When the game ends
## its result prints and the same game starts again.

var _mod: TourneyModule
var _round := 0


func _ready() -> void:
	BWSettings.init(true)
	if OS.has_feature("web"):
		BWWebInstanceShim.install(get_tree())                                  # D492: WebGL instance-uniform cap (Black | White hex board, bodies)
	BWMusic.ensure(self)
	TourneyMusic.ensure(self)
	BWSettings.apply_all()
	TourneySettings.apply_audio()                                          # G56: the settings' volumes ([audio] in tourney.cfg)
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
