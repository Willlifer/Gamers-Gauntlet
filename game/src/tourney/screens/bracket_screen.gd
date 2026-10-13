class_name BracketScreen
extends Node
## The bracket, head to head. First open: every match's game is rolled at
## once, visibly, then the players are rolled into the first round. Then the
## ready matches are offered for a vote (10 s; no votes = top-left first,
## then on round the layout). Later opens skip the rolls.

signal chosen(match_id: String)
signal finished

const ROLL_TIME := 1.6
const VOTE_TIME := 10.0
const CARD := Vector2(250, 92)

var state: TourneyState
var first_open := false
var _root: Control
var _cards := {}          # match id -> { panel, game, p1, p2, state }
var _vote_box: VBoxContainer
var _votes := {}          # player id -> match id
var _vote_t := -1.0
var _timer_l: Label
var _phase := ""
var _zoom: VBoxContainer


func _ready() -> void:
	_root = TourneyUI.root(self)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	_root.move_child(bg, 0)
	TourneyUI.big(_root, "The bracket", 36).set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_KEEP_SIZE, 10)
	_layout()
	if first_open:
		_roll_games()
	else:
		_fill_all()
		_offer()


# ---------------------------------------------------------------- layout

func _layout() -> void:
	var br := state.bracket
	var cols := { "w": 0, "l": 0 }
	for m in br.matches:
		if m.bracket != "gf":
			cols[m.bracket] = maxi(cols[m.bracket], m.round)
	var x0 := 40.0
	var gap := 30.0
	for m in br.matches:
		var x: float
		var y: float
		match m.bracket:
			"w":
				x = x0 + (m.round - 1) * (CARD.x + gap)
				y = 80 + m.slot * (CARD.y + 16) * pow(2, m.round - 1) + (pow(2, m.round - 1) - 1) * (CARD.y + 16) / 2
			"l":
				x = x0 + (m.round - 1) * (CARD.x + gap)
				y = 520 + m.slot * (CARD.y + 16) * pow(2, int((m.round - 1) / 2)) + (pow(2, int((m.round - 1) / 2)) - 1) * (CARD.y + 16) / 2
			_:
				x = x0 + maxi(cols.w, cols.l) * (CARD.x + gap)
				y = 300
		_card(m, Vector2(x, y))
	var lw := TourneyUI.label(_root, "Winners", BWStyle.F_SMALL, TourneyUI.DIM)
	lw.position = Vector2(x0, 34)
	var ll := TourneyUI.label(_root, "Losers", BWStyle.F_SMALL, TourneyUI.DIM)
	ll.position = Vector2(x0, 474)


func _card(m: Dictionary, at: Vector2) -> void:
	var v := TourneyUI.panel(_root, Rect2(at, CARD), "")
	var p: PanelContainer = v.get_parent()
	var g := TourneyUI.label(v, "", BWStyle.F_SMALL, TourneyUI.GOLD)
	var a := TourneyUI.label(v, "", BWStyle.F_BODY)
	var b := TourneyUI.label(v, "", BWStyle.F_BODY)
	for l in [g, a, b]:
		l.add_theme_constant_override("line_spacing", -4)
	v.add_theme_constant_override("separation", 0)
	_cards[m.id] = { "panel": p, "game": g, "p1": a, "p2": b }
	var tag := TourneyUI.label(_root, TourneyBracket.label(m), 13, TourneyUI.DIM)
	tag.position = at + Vector2(6, -18)


func _name(pid: String) -> String:
	if pid == "":
		return "—"
	if pid == "bye":
		return "(bye)"
	return str(state.player(pid).get("name", pid))


func _fill(m: Dictionary) -> void:
	var c: Dictionary = _cards[m.id]
	c.game.text = TourneyModules.name_of(m.game) if m.game != "" else "?"
	for side in ["p1", "p2"]:
		var l: Label = c[side]
		var pid: String = m[side]
		l.text = _name(pid)
		if m.state == "done":
			l.add_theme_color_override("font_color", TourneyUI.GOLD if pid == m.winner else TourneyUI.DIM)
		else:
			l.add_theme_color_override("font_color", Color.WHITE if pid != "" else TourneyUI.DIM)
	var sb: StyleBoxFlat = (c.panel as PanelContainer).get_theme_stylebox("panel").duplicate()
	sb.border_color = TourneyUI.GOLD if m.state == "ready" else TourneyUI.PANEL_LINE
	sb.set_border_width_all(2 if m.state == "ready" else 1)
	(c.panel as PanelContainer).add_theme_stylebox_override("panel", sb)


func _fill_all() -> void:
	for m in state.bracket.matches:
		_fill(m)


# ----------------------------------------------------------------- rolls

func _roll_games() -> void:
	_phase = "games"
	var pool := TourneyModules.infos().map(func(i): return str(i.id))
	for m in state.bracket.matches:
		m.game = pool[state.rng.randi() % pool.size()]
	var t := 0.0
	var names := TourneyModules.infos().map(func(i): return str(i.name))
	while t < ROLL_TIME:
		for id in _cards:
			(_cards[id].game as Label).text = names[randi() % names.size()]
		await get_tree().create_timer(0.07).timeout
		t += 0.07
	_fill_all()
	BWMusic.sting("pick")
	await get_tree().create_timer(0.6).timeout
	_roll_players()


func _roll_players() -> void:
	_phase = "players"
	var names := state.players.map(func(p): return str(p.name))
	var t := 0.0
	while t < ROLL_TIME:
		for m in state.bracket.matches:
			if m.round == 1 and m.bracket == "w":
				for side in ["p1", "p2"]:
					(_cards[m.id][side] as Label).text = names[randi() % names.size()]
		await get_tree().create_timer(0.07).timeout
		t += 0.07
	_fill_all()
	BWMusic.sting("pick")
	await get_tree().create_timer(0.6).timeout
	_offer()


# ------------------------------------------------------------------ vote

func _offer() -> void:
	var br := state.bracket
	if br.done():
		finished.emit()
		return
	var ready := br.ready()
	if ready.is_empty():
		finished.emit()      # nothing to play (shouldn't happen)
		return
	_phase = "vote"
	_votes = {}
	_vote_t = VOTE_TIME
	var v := TourneyUI.panel(_root, Rect2(1180, 60, 400, 480), "Which match first?")
	_vote_box = v
	_timer_l = TourneyUI.label(v, "", BWStyle.F_SMALL, TourneyUI.DIM)
	var me := state.me()
	for m in ready:
		var b := TourneyUI.button(v, "%s vs %s\n%s" % [_name(m.p1), _name(m.p2), TourneyModules.name_of(m.game)],
			func(): _vote(me.id, m.id))
		b.set_meta("match", m.id)
	TourneyUI.para(v, "No votes in 10 s: top-left goes first, then on round.")
	_zoom = TourneyUI.panel(_root, Rect2(1180, 560, 400, 320), "Up next")
	_show_next(ready[0])
	# bots vote over the first few seconds
	for p in state.players:
		if p.bot and state.rng.randf() < 0.6:
			var pick: Dictionary = ready[state.rng.randi() % ready.size()]
			TourneyUI.after(self, state.rng.randf_range(1.0, 5.0), func():
				if _phase == "vote":
					_vote(p.id, pick.id))


func _show_next(m: Dictionary) -> void:
	for c in _zoom.get_children().slice(1):
		c.queue_free()
	TourneyUI.label(_zoom, "%s vs %s" % [_name(m.p1), _name(m.p2)], BWStyle.F_SUB)
	TourneyUI.label(_zoom, TourneyModules.name_of(m.game), BWStyle.F_BODY, TourneyUI.GOLD)
	var nx := state.bracket.next_of(m.id)
	for n in nx:
		TourneyUI.label(_zoom, "→ %s: %s" % [TourneyBracket.label(n), "the winner" if str(n.feed1.get("from", "")) == m.id and n.feed1.take == "winner" or str(n.feed2.get("from", "")) == m.id and n.feed2.take == "winner" else "the loser"], BWStyle.F_SMALL, TourneyUI.DIM)


func _vote(pid: String, mid: String) -> void:
	if _phase != "vote" or _votes.has(pid):
		return
	_votes[pid] = mid
	_refresh_votes()
	if _votes.size() >= state.players.size():
		_decide()


func _refresh_votes() -> void:
	for b in _vote_box.get_children():
		if b is Button:
			var n := _votes.values().count(b.get_meta("match"))
			var base: String = b.text.split("  (")[0]
			b.text = base + ("  (%d)" % n if n > 0 else "")


func _process(delta: float) -> void:
	if _phase != "vote" or _vote_t < 0.0:
		return
	_vote_t -= delta
	if _timer_l:
		_timer_l.text = "%d s" % ceili(maxf(_vote_t, 0.0))
	if _vote_t <= 0.0:
		_decide()


func _decide() -> void:
	_phase = "decided"
	_vote_t = -1.0
	var ready := state.bracket.ready()
	var tally := {}
	for mid in _votes.values():
		tally[mid] = int(tally.get(mid, 0)) + 1
	var best: Dictionary = ready[0]
	var best_n := -1
	for m in ready:              # ties: layout order
		var n := int(tally.get(m.id, 0))
		if n > best_n:
			best = m
			best_n = n
	BWMusic.sting("pick")
	chosen.emit(best.id)
