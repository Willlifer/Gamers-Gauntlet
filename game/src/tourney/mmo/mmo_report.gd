class_name MmoReport
extends CanvasLayer
## The raid's report card (G33): the two contestants (seats 0 and 1) side by
## side, a big letter each, the score, and the five graded parts as bars
## with their points and the facts behind them. The winner's card is lit.

var sim: MmoSim
var me_id := ""


func _ready() -> void:
	layer = 20
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = BWStyle.theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var title := TourneyUI.display(root, "RAID REPORT", 34, Color("#ffd100"))
	title.position = Vector2(0, 110)
	title.size = Vector2(1600, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var a: MmoUnit = sim.players()[0]
	var b: MmoUnit = sim.players()[1]
	var ga := MmoGrade.grade(sim, a)
	var gb := MmoGrade.grade(sim, b)
	var a_wins := MmoGrade.beats(ga, gb)
	_card(root, Rect2(250, 180, 520, 470), a, ga, a_wins)
	_card(root, Rect2(830, 180, 520, 470), b, gb, not a_wins)
	var how := TourneyUI.label(root, "Higher grade wins; the same grade goes to the higher score.", BWStyle.F_SMALL, TourneyUI.DIM)
	how.position = Vector2(0, 664)
	how.size = Vector2(1600, 24)
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.modulate.a = 0.0
	create_tween().tween_property(root, "modulate:a", 1.0, 0.35)


func _card(root: Control, rect: Rect2, u: MmoUnit, g: Dictionary, won: bool) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", TourneyUI.panel_box(TourneyUI.GOLD if won else Color(1, 1, 1, 0.2)))
	p.position = rect.position
	p.size = rect.size
	root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var top := TourneyUI.row(v, 16)
	var letter := TourneyUI.display(top, str(g.letter), 96, MmoGrade.colour(str(g.letter)))
	letter.custom_minimum_size.x = 110
	var who := VBoxContainer.new()
	top.add_child(who)
	var n := TourneyUI.label(who, u.name + ("  (you)" if u.id == me_id else ""), BWStyle.F_NAME, MmoClasses.color(u.cls))
	n.add_theme_color_override("font_outline_color", Color.BLACK)
	n.add_theme_constant_override("outline_size", 5)
	TourneyUI.label(who, str(MmoClasses.CLASSES[u.cls].name), BWStyle.F_SMALL, TourneyUI.DIM)
	TourneyUI.display(who, "%d / 100" % int(round(float(g.score))), 26, Color.WHITE)
	if won:
		TourneyUI.display(who, "WINNER", 18, TourneyUI.GOLD)
	var f: Dictionary = g.facts
	var facts := {
		"output": "%d%% of a bot's pace  ·  %d dmg, %d heal" % [int(f.output_pct), int(u.dmg_done), int(u.heal_done)],
		"mechanics": "%s done  ·  %d cleanses on others (+%.1f)" % [str(f.mech), int(f.cleanses), int(f.cleanses) * MmoTune.value("cleanse_credit")],
		"avoidance": "%s dodged" % str(f.dodge),
		"survival": "%d%% alive  ·  %d deaths" % [int(round(float(g.parts.survival) * 100.0)), int(f.deaths)],
		"activity": "%d%% of the time busy" % int(round(float(g.parts.activity) * 100.0)),
	}
	for part in MmoGrade.PARTS:
		var row := TourneyUI.row(v, 8)
		var nl := TourneyUI.label(row, str(MmoGrade.NAMES[part]), BWStyle.F_SMALL)
		nl.custom_minimum_size.x = 130
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = float(g.parts[part])
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(200, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = MmoGrade.colour(MmoGrade.letter_for(float(g.parts[part]) * 100.0))
		var back := StyleBoxFlat.new()
		back.bg_color = Color(1, 1, 1, 0.08)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", back)
		row.add_child(bar)
		var pts := TourneyUI.label(row, "%.1f pts" % float(g.points[part]), BWStyle.F_SMALL, Color.WHITE)
		pts.custom_minimum_size.x = 80
		pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		TourneyUI.label(v, "      " + str(facts[part]), 13, TourneyUI.DIM)
