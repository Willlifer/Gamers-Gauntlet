class_name ChampionScreen
extends Node
## The evening's end: the champion on stage, then the standings.

signal done

var state: TourneyState


func _ready() -> void:
	var root := TourneyUI.root(self)
	var champ := state.player(state.bracket.champion)
	var v := TourneyUI.panel(root, Rect2(100, 60, 600, 780), "Champion")
	var st := TourneyUI.stage(v, state.unit_for(champ), Vector2(560, 520), true, Color(0.14, 0.12, 0.08))
	(st.view as BWUnitView).pose_named("cheer")
	TourneyUI.big(v, champ.name, 48, TourneyUI.GOLD)
	TourneyUI.label(v, champ.title, BWStyle.F_SUB, TourneyUI.DIM).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := TourneyUI.panel(root, Rect2(740, 60, 760, 780), "Standings")
	var rows := state.players.duplicate()
	rows.sort_custom(func(a, b): return a.wins > b.wins or (a.wins == b.wins and a.coins > b.coins))
	for p in rows:
		TourneyUI.label(s, "%-14s  %d–%d   %d coins" % [p.name, p.wins, p.losses, p.coins], BWStyle.F_BODY)
	TourneyUI.label(s, "Matches", BWStyle.F_SUB)
	for e in state.log:
		TourneyUI.label(s, "%s  ·  %s beat %s" % [TourneyModules.name_of(e.game), state.player(e.winner).name, state.player(e.loser).name], BWStyle.F_SMALL, TourneyUI.DIM)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.add_child(sp)
	TourneyUI.button(s, "Back to the lobby", func(): done.emit())
	TourneyMusic.play("hype")
