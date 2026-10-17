extends Control
## The main scene (G66): paints "Starting…" at once, then compiles the shell's
## scripts a few at a time, one step per frame, then opens the tournament
## (scenes/tourney.tscn). On the single-threaded web build one long load is
## one long freeze of the tab ("Page unresponsive"); steps with frames between
## keep it painting. Names no class: every script comes by path.
## `-- --boot-time` (or --verbose) prints when each step lands.

## Leaves first: each step compiles what the next would pull in anyway, so no
## single step carries the whole graph. Black | White's rules core (one tangle
## of ~60 scripts) is the biggest step; the games themselves load only when
## one is picked (TourneyModules.script_for).
const STEPS := [
	"res://src/core/data.gd",                       # BWData: B|W's rules core
	"res://src/game/character/anim_clips.gd",       # BWAnimClips: the animation set
	"res://src/game/character/character.gd",        # BWCharacter + BWAnimator
	"res://src/game/combat/unit_view.gd",           # BWUnitView: the figures and plates
	"res://src/game/music.gd",                      # BWMusic, BWAudio, the director
	"res://src/game/settings.gd",                   # BWSettings
	"res://src/tourney/tourney_state.gd",           # the players and profiles
	"res://src/tourney/tourney_ui.gd",              # the palette and builders
	"res://src/tourney/ui/tourney_settings.gd",
	"res://src/tourney/screens/lobby_screen.gd",
	"res://src/tourney/screens/bracket_screen.gd",
	"res://src/tourney/tourney.gd",
]
const MAIN := "res://scenes/tourney.tscn"

var _label: Label
var _report := false


func _ready() -> void:
	_report = "--boot-time" in OS.get_cmdline_user_args() or OS.is_stdout_verbose()
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_label = Label.new()
	_label.text = "Starting…"
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_label)
	_run()


func _run() -> void:
	await RenderingServer.frame_post_draw
	_mark("boot frame")
	for i in STEPS.size():
		var t := Time.get_ticks_usec()
		load(STEPS[i])
		_mark("%s (%.0f ms)" % [str(STEPS[i]).get_file(), (Time.get_ticks_usec() - t) / 1000.0])
		_label.text = "Starting…  %d / %d" % [i + 1, STEPS.size()]
		await get_tree().process_frame
	get_tree().change_scene_to_packed(load(MAIN))


func _mark(what: String) -> void:
	if _report:
		print("[boot] %s at %d ms" % [what, Time.get_ticks_msec()])
