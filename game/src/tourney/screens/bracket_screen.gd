class_name BracketScreen
extends Node
## The bracket, after the author's Smash Ultimate cup reference (G27): name
## plates with portraits, winners flowing in from the left, losers from the
## right, the grand final under a trophy in the middle. First open: every
## match's game and the first round's players spin like slot reels and stop
## in a cascade, the last pick rolling into place over half a second. Then
## the top ready match (layout order) is up next: no vote (author 10-15).

signal chosen(match_id: String)
signal finished

const PW := 140.0                           ## plate width
const PH := 26.0
const COL := 166.0                          ## column pitch
const MARGIN := 40.0
const TOP := 160.0
const BOTTOM := 810.0
const SPIN_LEAD := 0.9                      ## spin this long before the first reel stops
const CASCADE := 0.09                       ## between one reel stopping and the next
const NEXT_HOLD := 2.4                      ## "up next" shows this long, then the matchup

var state: TourneyState
var first_open := false
var _root: Control
var _lines: Control
var _fx: Control
var _cards := {}          # match id -> { game: SlotReel, p1: {...}, p2: {...}, glow: Panel, at: Vector2 }
var _y := {}              # match id -> centre y
var _phase := ""
var _next_id := ""
var _t := 0.0


func _ready() -> void:
	_root = TourneyUI.root(self)
	var n := state.players.size()
	TourneyUI.header(_root, "THE BRACKET", "%d players   ·   double elimination   ·   every match rolls a game" % n)
	_fx = Control.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.draw.connect(_draw_trophy)
	_root.add_child(_fx)
	_lines = Control.new()
	_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.draw.connect(_draw_lines)
	_root.add_child(_lines)
	var lw := TourneyUI.display(_root, "WINNERS  ▸", 18, Color(1, 1, 1, 0.85))
	lw.position = Vector2(MARGIN, 104)
	var ll := TourneyUI.display(_root, "◂  LOSERS", 18, Color(1, 1, 1, 0.85))
	ll.position = Vector2(1600 - MARGIN - 130, 104)
	_layout()
	if TourneyPortraits.inst():
		TourneyPortraits.inst().landed.connect(func(_k): _refresh_portraits())
	if first_open:
		_roll()
	else:
		_fill_all()
		_offer()


# ---------------------------------------------------------------- layout

func _x(m: Dictionary) -> float:
	match m.bracket:
		"w":
			return MARGIN + (m.round - 1) * COL
		"l":
			return 1600.0 - MARGIN - PW - (m.round - 1) * COL
	return 800.0 - PW * 0.5


func _feeders(m: Dictionary, same: bool) -> Array:
	var out: Array = []
	for f in [m.feed1, m.feed2]:
		if f.is_empty():
			continue
		var src := state.bracket.get_match(str(f.from))
		if not same or src.bracket == m.bracket:
			out.append(src)
	return out


func _yc(m: Dictionary) -> float:
	if _y.has(m.id):
		return _y[m.id]
	var y: float
	if m.bracket == "gf":
		y = (TOP + BOTTOM) * 0.5 + 40.0
	else:
		var fs := _feeders(m, true)
		if fs.size() == 2:
			y = (_yc(fs[0]) + _yc(fs[1])) * 0.5
		elif fs.size() == 1:
			y = _yc(fs[0])
		else:
			var peers := state.bracket.matches.filter(func(o): return o.bracket == m.bracket and o.round == m.round)
			var k := peers.find(m)
			y = TOP + (k + 0.5) * (BOTTOM - TOP) / peers.size()
	_y[m.id] = y
	return y


func _layout() -> void:
	for m in state.bracket.matches:
		_card(m, Vector2(_x(m), _yc(m)))


func _card(m: Dictionary, at: Vector2) -> void:
	var glow := Panel.new()
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(0, 0, 0, 0)
	gs.border_color = TourneyUI.ACCENT
	gs.set_border_width_all(3)
	gs.set_corner_radius_all(4)
	gs.shadow_color = Color(TourneyUI.ACCENT, 0.5)
	gs.shadow_size = 10
	glow.add_theme_stylebox_override("panel", gs)
	glow.position = Vector2(at.x - 5, at.y - PH - 6)
	glow.size = Vector2(PW + 10, PH * 2 + 14)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.visible = false
	_root.add_child(glow)
	var game := SlotReel.new()
	game.font = TourneyUI.display_font()
	game.font_size = 13
	game.outline = 4
	game.color = Color(1, 1, 1, 0.8)
	game.align = HORIZONTAL_ALIGNMENT_CENTER if m.bracket == "gf" else (HORIZONTAL_ALIGNMENT_LEFT if m.bracket == "w" else HORIZONTAL_ALIGNMENT_RIGHT)
	game.position = Vector2(at.x - 4, at.y - PH - 24)
	game.size = Vector2(PW + 8, 20)
	_root.add_child(game)
	_cards[m.id] = { "game": game, "glow": glow, "at": at,
		"p1": _plate(Vector2(at.x, at.y - PH - 1), m.bracket == "l"),
		"p2": _plate(Vector2(at.x, at.y + 1), m.bracket == "l") }


## A name plate: off-white, a portrait chip on the outer side, a slot reel for the name.
func _plate(at: Vector2, mirror: bool) -> Dictionary:
	var p := Panel.new()
	p.position = at
	p.size = Vector2(PW, PH)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(p)
	var chip := Panel.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color("#1d2433")
	chip.add_theme_stylebox_override("panel", cs)
	chip.size = Vector2(PH + 4, PH)
	chip.position = Vector2(0 if mirror else PW - PH - 4, 0)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(chip)
	var face := TextureRect.new()
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(face)
	var bar := ColorRect.new()                # the winner's gold edge
	bar.color = TourneyUI.GOLD
	bar.size = Vector2(4, PH)
	bar.position = Vector2(PW - 4 if mirror else 0, 0)
	bar.visible = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(bar)
	var reel := SlotReel.new()
	reel.font_size = 15
	reel.position = Vector2((PH + 10) if mirror else 9, 0)
	reel.size = Vector2(PW - PH - 18, PH)
	reel.align = HORIZONTAL_ALIGNMENT_RIGHT if mirror else HORIZONTAL_ALIGNMENT_LEFT
	p.add_child(reel)
	return { "panel": p, "reel": reel, "face": face, "chip": chip, "bar": bar, "pid": "" }


func _plate_style(p: Panel, filled: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TourneyUI.PLATE if filled else Color(1, 1, 1, 0.1)
	sb.border_color = Color(1, 1, 1, 0.0 if filled else 0.22)
	sb.set_border_width_all(0 if filled else 1)
	sb.set_corner_radius_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.35 if filled else 0.0)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(2, 3)
	p.add_theme_stylebox_override("panel", sb)


func _name(pid: String) -> String:
	if pid == "bye":
		return "(bye)"
	return str(state.player(pid).get("name", pid))


## "Loser of W1·A": where an empty side will come from.
func _from_text(f: Dictionary) -> String:
	if f.is_empty():
		return ""
	var src := state.bracket.get_match(str(f.from))
	var short := ("W" if src.bracket == "w" else "L") + str(src.round)
	var peers := state.bracket.matches.filter(func(o): return o.bracket == src.bracket and o.round == src.round)
	if peers.size() > 1:
		short += "·" + "ABCD"[peers.find(src)]
	return ("Winner of " if f.take == "winner" else "Loser of ") + short


func _fill(m: Dictionary) -> void:
	var c: Dictionary = _cards[m.id]
	(c.game as SlotReel).text = TourneyModules.name_of(m.game).to_upper() if m.game != "" else "?"
	(c.game as SlotReel).color = TourneyUI.ACCENT if m.id == _next_id else Color(1, 1, 1, 0.8)
	for side in ["1", "2"]:
		var pl: Dictionary = c["p" + side]
		var pid: String = m["p" + side]
		var reel: SlotReel = pl.reel
		var filled := pid != "" and pid != "bye"
		_plate_style(pl.panel, filled)
		(pl.chip as Control).visible = filled
		pl.pid = pid if filled else ""
		if pid == "":
			reel.text = _from_text(m["feed" + side])
			reel.font_size = 12
			reel.color = Color(1, 1, 1, 0.45)
		else:
			reel.text = _name(pid)
			reel.font_size = 15
			reel.color = TourneyUI.ACCENT.darkened(0.15) if pid == state.me().get("id", "") else TourneyUI.PLATE_INK
			if pid == "bye":
				reel.color = Color(1, 1, 1, 0.45)
		var lost: bool = m.state == "done" and pid != m.winner
		(pl.panel as Panel).modulate = Color(1, 1, 1, 0.42) if lost else Color.WHITE
		(pl.bar as Control).visible = m.state == "done" and pid == m.winner and filled
	_refresh_portrait(c)


func _fill_all() -> void:
	for m in state.bracket.matches:
		_fill(m)
	_lines.queue_redraw()


func _refresh_portrait(c: Dictionary) -> void:
	for side in ["p1", "p2"]:
		var pl: Dictionary = c[side]
		if pl.pid != "":
			(pl.face as TextureRect).texture = TourneyPortraits.portrait(state, state.player(pl.pid))


func _refresh_portraits() -> void:
	for id in _cards:
		_refresh_portrait(_cards[id])


# ----------------------------------------------------------------- lines

func _draw_lines() -> void:
	for m in state.bracket.matches:
		for f in _feeders(m, false):
			var same: bool = f.bracket == m.bracket or m.bracket == "gf"
			if not same:
				continue
			var a: Vector2 = _cards[f.id].at
			var b: Vector2 = _cards[m.id].at
			var col := Color(1, 1, 1, 0.7) if f.state == "done" else Color(1, 1, 1, 0.28)
			var pts: PackedVector2Array
			if f.bracket == "w":
				var x0 := a.x + PW
				var x1 := b.x
				var mx := x0 + minf(13.0, (x1 - x0) * 0.5) if m.bracket != "gf" else x0 + 13.0
				pts = [Vector2(x0, a.y), Vector2(mx, a.y), Vector2(mx, b.y), Vector2(x1, b.y)]
			else:
				var x0 := a.x
				var x1 := b.x + PW
				var mx := x0 - 13.0
				pts = [Vector2(x0, a.y), Vector2(mx, a.y), Vector2(mx, b.y), Vector2(x1, b.y)]
			_lines.draw_polyline(pts, col, 2.0)


## The trophy over the grand final, with slow light rays behind it.
func _draw_trophy() -> void:
	var gf := state.bracket.get_match("gf")
	var c := Vector2(800, _yc(gf) - 150)
	var t := Time.get_ticks_msec() / 1000.0
	for i in 12:
		var a := t * 0.12 + i * TAU / 12.0
		var d1 := Vector2(cos(a - 0.09), sin(a - 0.09)) * 150.0
		var d2 := Vector2(cos(a + 0.09), sin(a + 0.09)) * 150.0
		_fx.draw_colored_polygon(PackedVector2Array([c, c + d1, c + d2]), Color(TourneyUI.GOLD, 0.05))
	var g := TourneyUI.GOLD
	var cup := PackedVector2Array([c + Vector2(-38, -44), c + Vector2(38, -44), c + Vector2(30, -6), c + Vector2(14, 12), c + Vector2(-14, 12), c + Vector2(-30, -6)])
	_fx.draw_colored_polygon(cup, g)
	_fx.draw_arc(c + Vector2(-38, -26), 14.0, PI * 0.5, PI * 1.5, 12, g, 6.0)
	_fx.draw_arc(c + Vector2(38, -26), 14.0, -PI * 0.5, PI * 0.5, 12, g, 6.0)
	_fx.draw_rect(Rect2(c + Vector2(-6, 12), Vector2(12, 18)), g)
	_fx.draw_colored_polygon(PackedVector2Array([c + Vector2(-26, 30), c + Vector2(26, 30), c + Vector2(30, 42), c + Vector2(-30, 42)]), g.darkened(0.15))
	_fx.draw_colored_polygon(PackedVector2Array([c + Vector2(-22, -40), c + Vector2(-10, -40), c + Vector2(-16, -10)]), Color(1, 1, 1, 0.35))
	var f := TourneyUI.display_font()
	var s := "GRAND FINAL"
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	_fx.draw_string_outline(f, c + Vector2(-w * 0.5, 76), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.8))
	_fx.draw_string(f, c + Vector2(-w * 0.5, 76), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, g)


func _process(delta: float) -> void:
	_t += delta
	_fx.queue_redraw()
	if _next_id != "" and _cards.has(_next_id):
		var glow: Panel = _cards[_next_id].glow
		glow.modulate.a = 0.55 + 0.45 * sin(_t * 6.0)


# ----------------------------------------------------------------- rolls

## Every game reel and the first round's name reels spin together; the games
## stop in a cascade (left to right, top to bottom), then the players.
func _roll() -> void:
	_phase = "rolling"
	var pool := TourneyModules.infos().map(func(i): return str(i.id))
	for m in state.bracket.matches:
		m.game = pool[state.rng.randi() % pool.size()]
	var names := TourneyModules.infos().map(func(i): return str(i.name).to_upper())
	var people := state.players.map(func(p): return str(p.name))
	_fill_all()
	var order := state.bracket.matches.duplicate()
	order.sort_custom(func(a, b): return _cards[a.id].at.x < _cards[b.id].at.x or (_cards[a.id].at.x == _cards[b.id].at.x and _cards[a.id].at.y < _cards[b.id].at.y))
	var first := true
	for m in order:
		var r: SlotReel = _cards[m.id].game
		r.ticks = first
		first = false
		r.spin(names)
	var seats: Array = []
	for m in order:
		if m.bracket == "w" and m.round == 1:
			for side in ["p1", "p2"]:
				var pl: Dictionary = _cards[m.id][side]
				if pl.pid != "":
					(pl.face as TextureRect).texture = null
					(pl.reel as SlotReel).spin(people)
					seats.append([pl, _name(m[side])])
	var last: SlotReel
	for i in order.size():
		var m: Dictionary = order[i]
		last = _cards[m.id].game
		last.stop(TourneyModules.name_of(m.game).to_upper(), SPIN_LEAD + i * CASCADE)
	await last.landed
	BWMusic.sting("pick")
	var last_p: SlotReel
	for i in seats.size():
		last_p = seats[i][0].reel
		last_p.stop(str(seats[i][1]), 0.3 + i * CASCADE)
	if last_p:
		await last_p.landed
	BWMusic.sting("pick")
	_fill_all()
	await get_tree().create_timer(0.5).timeout
	_offer()


# --------------------------------------------------------------- up next

## The top ready match in layout order plays next (no vote, author 10-15).
func _offer() -> void:
	var br := state.bracket
	if br.done():
		finished.emit()
		return
	var ready := br.ready()
	if ready.is_empty():
		finished.emit()      # nothing to play (shouldn't happen)
		return
	var m: Dictionary = ready[0]
	_phase = "next"
	_next_id = m.id
	_cards[m.id].glow.visible = true
	_fill(m)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", TourneyUI.panel_box(TourneyUI.ACCENT))
	bar.position = Vector2(470, 832)
	bar.size = Vector2(660, 52)
	_root.add_child(bar)
	var r := TourneyUI.row(bar, 14)
	TourneyUI.display(r, "UP NEXT", 20, TourneyUI.ACCENT)
	TourneyUI.label(r, "%s  vs  %s" % [_name(m.p1), _name(m.p2)], BWStyle.F_BODY)
	TourneyUI.label(r, "·  " + TourneyModules.name_of(m.game), BWStyle.F_BODY, TourneyUI.GOLD)
	BWMusic.sting("pick")
	TourneyUI.after(self, NEXT_HOLD, func(): decide())


## Go to the up-next match now (tools call it to skip the hold).
func decide() -> void:
	if _phase != "next":
		return
	_phase = "decided"
	chosen.emit(_next_id)
