class_name VersusScreen
extends Node
## The load-in between the matchup and the game (G42): a black screen with the
## Chris loop under it, then three slams: the left player (name, title, model),
## the right player, and the challenge in the centre (its map, circling, and
## its name). Then `done`. Any key or click after the third slam skips the hold.

signal done

const LEFT_AT := 0.7
const RIGHT_AT := 1.5
const MID_AT := 2.3
const HOLD := 2.2                             ## after the last slam
const SLAM := 0.16                            ## each slam's fall

var state: TourneyState
var players: Array = []                       # [p1, p2] player dicts
var game_id := ""
var map_tex: Texture2D                        # the backdrop's map, circling; null = the game's tile colours

var _root: Control
var _shake := 0.0
var _flash: ColorRect
var _t := 0.0
var _ended := false


func _ready() -> void:
	_root = TourneyUI.root(self)
	var ink := ColorRect.new()
	ink.color = Color.BLACK
	ink.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(ink)
	var sides := [[players[0], TourneyUI.BLUE, 40.0, -1.0, LEFT_AT], [players[1], TourneyUI.RED, 1100.0, 1.0, RIGHT_AT]]
	for s in sides:
		var card := _player_card(s[0], s[1], s[2], s[3])
		TourneyUI.after(self, s[4], func(): _slam(card, "ph_colossus_step"))
	var mid := _challenge()
	TourneyUI.after(self, MID_AT, func(): _slam(mid, "tile_detonate"))
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)
	TourneyUI.after(self, MID_AT + SLAM + HOLD, _end)


## One side: a slanted band in the side's colour, the model standing on it, the name and title below.
func _player_card(p: Dictionary, col: Color, x: float, side: float) -> Control:
	var c := Control.new()
	c.position = Vector2(x, 70)
	c.size = Vector2(460, 760)
	c.pivot_offset = c.size * 0.5
	c.modulate.a = 0.0
	_root.add_child(c)
	var band := ColorRect.new()
	band.color = Color(col, 0.85)
	band.position = Vector2(40, 40)
	band.size = Vector2(380, 640)
	band.pivot_offset = band.size * 0.5
	band.rotation = deg_to_rad(-6.0 * side)
	c.add_child(band)
	var edge := ColorRect.new()                # a bright lip on the inner edge
	edge.color = Color(1, 1, 1, 0.9)
	edge.position = Vector2(380 if side < 0.0 else -8, 0)
	edge.size = Vector2(8, 640)
	band.add_child(edge)
	var holder := Control.new()
	holder.position = Vector2(10, 46)
	holder.size = Vector2(440, 560)
	c.add_child(holder)
	var st := TourneyUI.stage(holder, state.unit_for(p), Vector2(440, 560), true, Color(0, 0, 0, 0))
	(st.view as Node3D).rotation.y = deg_to_rad(28.0 * -side)   # each faces the middle
	var n := TourneyUI.display(c, str(p.get("name", "?")).to_upper(), 56, Color.WHITE)
	n.position = Vector2(0, 580)
	n.size = Vector2(460, 70)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t := TourneyUI.label(c, str(p.get("title", "")), BWStyle.F_SUB, Color(1, 1, 1, 0.8))
	t.position = Vector2(0, 656)
	t.size = Vector2(460, 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rec := "%d–%d" % [int(p.get("wins", 0)), int(p.get("losses", 0))]
	var r := TourneyUI.label(c, rec, BWStyle.F_BODY, Color(col.lightened(0.35), 0.9))
	r.position = Vector2(0, 694)
	r.size = Vector2(460, 30)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return c


## The centre: the map in a frame and the challenge's name.
func _challenge() -> Control:
	var c := Control.new()
	c.position = Vector2(560, 230)
	c.size = Vector2(480, 440)
	c.pivot_offset = c.size * 0.5
	c.modulate.a = 0.0
	_root.add_child(c)
	var frame := Panel.new()
	frame.position = Vector2(0, 0)
	frame.size = Vector2(480, 290)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.BLACK
	sb.border_color = TourneyUI.GOLD
	sb.set_border_width_all(4)
	frame.add_theme_stylebox_override("panel", sb)
	frame.clip_contents = true
	c.add_child(frame)
	var look: Array = LobbyScreen.LOOKS.get(game_id, ["#2c3546", ""])
	if map_tex:
		var m := TextureRect.new()
		m.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		m.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		m.texture = map_tex
		frame.add_child(m)
		m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	else:
		var bg := ColorRect.new()
		bg.color = Color(look[0])
		bg.position = Vector2(4, 4)
		bg.size = Vector2(472, 282)
		frame.add_child(bg)
		var mark := TourneyUI.display(bg, str(look[1]), 120, Color(1, 1, 1, 0.9))
		mark.set_anchors_preset(Control.PRESET_FULL_RECT)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if look.size() > 2 and ResourceLoader.exists(str(look[2])):
		var logo := TextureRect.new()                       # the game's own logo over its map (G46)
		logo.texture = load(str(look[2]))
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.position = Vector2(40, 40)
		logo.size = Vector2(400, 210)
		frame.add_child(logo)
	var name_ := TourneyModules.name_of(game_id)
	var parts := name_.split(":", true, 1)
	var kind := TourneyUI.label(c, parts[0].strip_edges().to_upper() if parts.size() > 1 else "", BWStyle.F_SUB, TourneyUI.GOLD)
	kind.position = Vector2(0, 304)
	kind.size = Vector2(480, 36)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title := TourneyUI.display(c, (parts[1] if parts.size() > 1 else parts[0]).strip_edges().to_upper(), 50, Color.WHITE)
	title.position = Vector2(0, 336)
	title.size = Vector2(480, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return c


## Boom: from big and clear to its place in a blink, a flash, a shake, a thud.
func _slam(c: Control, sfx: String) -> void:
	c.scale = Vector2(1.7, 1.7)
	c.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, SLAM).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(c, "modulate:a", 1.0, SLAM * 0.6)
	tw.chain().tween_callback(func():
		_shake = 1.0
		_flash.color.a = 0.35
		BWSfx.play(sfx))


func _process(delta: float) -> void:
	_t += delta
	_shake = maxf(0.0, _shake - delta * 4.0)
	_root.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 14.0 * _shake * _shake
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 2.2)


func _unhandled_input(ev: InputEvent) -> void:
	if _t < MID_AT + SLAM:
		return
	if (ev is InputEventKey or ev is InputEventMouseButton) and ev.pressed:
		_end()


func _end() -> void:
	if _ended:
		return
	_ended = true
	done.emit()
