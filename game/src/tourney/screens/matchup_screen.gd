class_name MatchupScreen
extends Node
## Before a match: the two players on stage, emoting; the house puts 5 coins
## on each side; everyone (competitors too) can back a side with 5 to 25.
## Starts after 15 s or when every player has bet or passed.

signal start

const WAIT := 15.0

var state: TourneyState
var match_id := ""
var _m: Dictionary
var _root: Control
var _stages: Array = []
var _pot_l: Label
var _t := WAIT
var _timer_l: Label
var _decided := {}        # player id -> true once bet or passed
var _amount := 10
var _amount_l: Label
var _done := false


func _ready() -> void:
	_m = state.bracket.get_match(match_id)
	_root = TourneyUI.root(self)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	_root.move_child(bg, 0)
	var head := TourneyUI.big(_root, "%s  ·  %s" % [TourneyBracket.label(_m), TourneyModules.name_of(_m.game)], 32)
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_KEEP_SIZE, 16)
	var sides := [["p1", TourneyUI.BLUE, 60], ["p2", TourneyUI.RED, 1040]]
	for s in sides:
		var p := state.player(_m[s[0]])
		var v := TourneyUI.panel(_root, Rect2(s[2], 90, 500, 620), "")
		var st := TourneyUI.stage(v, state.unit_for(p), Vector2(470, 470), true, Color(0.13, 0.13, 0.16))
		_stages.append(st.view)
		var n := TourneyUI.label(v, "%s" % p.name, BWStyle.F_NAME, s[1])
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var t := TourneyUI.label(v, "%s  ·  %d–%d" % [p.title, p.wins, p.losses], BWStyle.F_BODY, TourneyUI.DIM)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var mid := TourneyUI.panel(_root, Rect2(580, 90, 440, 620), "The pot")
	_pot_l = TourneyUI.label(mid, "", BWStyle.F_SUB)
	_pot_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	TourneyUI.para(mid, "The house puts 5 on each side. Back a side with 5 to 25; winners split the pot by stake.")
	var me := state.me()
	TourneyUI.label(mid, "Your coins: %d" % me.coins, BWStyle.F_BODY, TourneyUI.GOLD)
	var r := TourneyUI.row(mid)
	TourneyUI.button(r, "−5", func(): _amount = maxi(TourneyState.BET_MIN, _amount - 5); _amount_l.text = str(_amount))
	_amount_l = TourneyUI.label(r, str(_amount), BWStyle.F_SUB)
	_amount_l.custom_minimum_size.x = 60
	_amount_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	TourneyUI.button(r, "+5", func(): _amount = mini(TourneyState.BET_MAX, _amount + 5); _amount_l.text = str(_amount))
	var r2 := TourneyUI.row(mid)
	var b1 := TourneyUI.button(r2, "Back %s" % state.player(_m.p1).name, func(): _bet(me.id, _m.p1, _amount))
	b1.add_theme_color_override("font_color", TourneyUI.BLUE)
	var b2 := TourneyUI.button(r2, "Back %s" % state.player(_m.p2).name, func(): _bet(me.id, _m.p2, _amount))
	b2.add_theme_color_override("font_color", TourneyUI.RED)
	TourneyUI.button(mid, "Pass", func(): _decided[me.id] = true; _check())
	_timer_l = TourneyUI.label(mid, "", BWStyle.F_SMALL, TourneyUI.DIM)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(sp)
	TourneyUI.button(mid, "Start now", func(): _go())
	_refresh_pot()
	_emote()
	for p in state.players:
		if p.bot:
			TourneyUI.after(self, state.rng.randf_range(1.0, 6.0), func():
				if _done:
					return
				if state.rng.randf() < 0.7 and p.coins >= TourneyState.BET_MIN:
					var side: String = _m.p1 if state.rng.randf() < 0.5 else _m.p2
					if p.id == _m.p1 or p.id == _m.p2:
						side = p.id          # competitors back themselves
					_bet(p.id, side, mini(p.coins, [5, 10, 15, 25][state.rng.randi() % 4]))
				else:
					_decided[p.id] = true
					_check())


func _emote() -> void:
	for v in _stages:
		if is_instance_valid(v):
			v.pose_named("cheer")
	TourneyUI.after(self, 2.6, func():
		if not _done:
			for v in _stages:
				if is_instance_valid(v):
					v.pose_named("idle")
			TourneyUI.after(self, 1.2, func():
				if not _done:
					_emote()))


func _bet(pid: String, side: String, amount: int) -> void:
	if _done or _decided.has(pid):
		return
	if state.place_bet(match_id, pid, side, amount):
		_decided[pid] = true
		_refresh_pot()
		_check()


func _refresh_pot() -> void:
	var a := TourneyState.HOUSE_PER_SIDE
	var b := TourneyState.HOUSE_PER_SIDE
	var who := { _m.p1: [], _m.p2: [] }
	for pid in state.bets.get(match_id, {}):
		var bt: Dictionary = state.bets[match_id][pid]
		if bt.side == _m.p1:
			a += int(bt.amount)
		else:
			b += int(bt.amount)
		who[bt.side].append("%s %d" % [state.player(pid).name, bt.amount])
	_pot_l.text = "%d   vs   %d\n%s\n%s" % [a, b, ", ".join(who[_m.p1]), ", ".join(who[_m.p2])]


func _check() -> void:
	if _decided.size() >= state.players.size():
		_go()


func _process(delta: float) -> void:
	if _done:
		return
	_t -= delta
	_timer_l.text = "Starts in %d s" % ceili(maxf(_t, 0.0))
	if _t <= 0.0:
		_go()


func _go() -> void:
	if _done:
		return
	_done = true
	start.emit()
