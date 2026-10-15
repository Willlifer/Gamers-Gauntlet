class_name SlotReel
extends Control
## A one-line slot-machine window (G27). spin(items) runs the names past fast;
## stop(final, delay) waits `delay`, then the reel slows and the final pick
## rolls up into the window over ROLL seconds (an ease-out, so the last
## step is the slow one). Idle, it just shows `text`.
##   reel.spin(names)
##   reel.stop("Gorbo", 0.3)
##   await reel.landed

signal landed(text: String)

const ROLL := 0.5                           ## the final pick rolling into place
const SPIN := 17.0                          ## items per second at full spin

var text := "":
	set(v):
		text = v
		queue_redraw()
var font_size := 16
var color := Color.WHITE:
	set(v):
		color = v
		queue_redraw()
var outline := 0
var align := HORIZONTAL_ALIGNMENT_LEFT
var font: Font
var ticks := false                          ## play a tick as items pass (one reel per group)

var _items: Array = []
var _p := 0.0                               # position in items
var _state := "idle"                        # idle | spin | roll
var _stop_in := -1.0
var _final := ""
var _final_k := 0
var _from := 0.0
var _t := 0.0
var _last_k := 0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font == null:
		font = get_theme_default_font()


func spinning() -> bool:
	return _state != "idle"


func spin(items: Array) -> void:
	_items = items.duplicate()
	if _items.is_empty():
		return
	_state = "spin"
	_stop_in = -1.0
	_p = randf() * _items.size()
	queue_redraw()


func stop(final: String, delay: float = 0.0) -> void:
	_final = final
	if _state == "idle":
		text = final
		landed.emit(final)
		return
	_stop_in = maxf(delay, 0.0)


func _process(delta: float) -> void:
	match _state:
		"spin":
			_p += SPIN * delta
			if _stop_in >= 0.0:
				_stop_in -= delta
				if _stop_in <= 0.0:
					_state = "roll"
					_from = _p
					_final_k = int(floor(_p)) + 2
					_t = 0.0
		"roll":
			_t += delta
			var k := clampf(_t / ROLL, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - k, 3.0)
			_p = lerpf(_from, float(_final_k), e)
			if k >= 1.0:
				_state = "idle"
				text = _final
				landed.emit(_final)
		_:
			return
	var kk := int(floor(_p))
	if ticks and kk != _last_k:
		BWSfx.ui("ui_hover", { "volume_db": -10.0 })
	_last_k = kk
	queue_redraw()


func _item(k: int) -> String:
	if _state == "roll" and k == _final_k:
		return _final
	if _items.is_empty():
		return text
	return str(_items[posmod(k, _items.size())])


func _draw() -> void:
	if font == null:
		return
	var h := size.y
	if _state == "idle":
		_line(text, 0.0, 1.0)
		return
	var k := int(floor(_p))
	var f := _p - float(k)
	# items scroll upward: k leaves through the top as k + 1 comes in below
	_line(_item(k), -f * h, 1.0 - f * 0.6)
	_line(_item(k + 1), (1.0 - f) * h, 0.4 + f * 0.6)


func _line(s: String, dy: float, a: float) -> void:
	var fs := font_size
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while w > size.x - 4.0 and fs > 9:
		fs -= 1
		w = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc := font.get_ascent(fs)
	var desc := font.get_descent(fs)
	var y := dy + (size.y + asc - desc) * 0.5
	var x := 2.0
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x = (size.x - w) * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x = size.x - w - 2.0
	var c := Color(color, color.a * a)
	if outline > 0:
		draw_string_outline(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Color(0, 0, 0, 0.8 * a))
	draw_string(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
