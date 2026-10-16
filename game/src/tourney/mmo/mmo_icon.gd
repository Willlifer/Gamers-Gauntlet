class_name MmoIcon
extends Control
## A square ability / aura icon drawn in code: a shaded tile in the
## ability's colour with a glyph on it (sword, flame, cross, ...), a dark
## bevelled frame; optional cooldown sweep, keybind, count and greying.
## WoW's icons are painted art; these are the stand-in (parked for art).

var glyph := "star"
var col := Color("#c8a040")
var cd := 0.0            ## 0..1 of the cooldown left (the clock sweep)
var cd_text := ""
var key := ""
var count := ""
var dim := false         ## not usable (no resource / out of range): darkened
var red_key := false     ## out of range: the keybind turns red
var lit := 0.0           ## a press flash, fades
var border := Color(0.05, 0.05, 0.05)
var font: Font


func _init(g := "star", c := Color("#c8a040")) -> void:
	glyph = g
	col = c
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var s := size.x
	# the tile: lit from the top left
	var base := col.darkened(0.55)
	var hi := col.lightened(0.05)
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(s, 0), Vector2(s, s), Vector2(0, s)])
	var cols := PackedColorArray([hi, base.lerp(hi, 0.4), base.darkened(0.45), base])
	draw_polygon(pts, cols)
	draw_circle(Vector2(s * 0.5, s * 0.45), s * 0.38, Color(col.lightened(0.2), 0.18))
	var ink := col.lightened(0.75)
	ink.a = 1.0
	MmoIcon.paint(self, glyph, Rect2(s * 0.12, s * 0.12, s * 0.76, s * 0.76), ink, col.darkened(0.75))
	if dim:
		draw_rect(r, Color(0, 0, 0.05, 0.55))
	if cd > 0.0:
		_sweep(cd)
	if lit > 0.0:
		draw_rect(r, Color(1, 0.95, 0.7, 0.35 * lit))
	# frame: dark edge, inner bevel
	draw_rect(r, border, false, maxf(1.0, s * 0.045))
	draw_line(Vector2(2, 2), Vector2(s - 2, 2), Color(1, 1, 1, 0.22), 1.0)
	draw_line(Vector2(2, 2), Vector2(2, s - 2), Color(1, 1, 1, 0.16), 1.0)
	var f := font if font else ThemeDB.fallback_font
	if key != "":
		var fs := int(s * 0.27)
		var kc := Color(1, 0.25, 0.2) if red_key else Color(0.92, 0.92, 0.92)
		draw_string_outline(f, Vector2(s * 0.08, fs * 1.0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.9))
		draw_string(f, Vector2(s * 0.08, fs * 1.0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, kc)
	if count != "":
		var fs := int(s * 0.3)
		draw_string_outline(f, Vector2(0, s - 3), count, HORIZONTAL_ALIGNMENT_RIGHT, s - 3, fs, 3, Color.BLACK)
		draw_string(f, Vector2(0, s - 3), count, HORIZONTAL_ALIGNMENT_RIGHT, s - 3, fs, Color(1, 1, 1))
	if cd_text != "":
		var fs := int(s * 0.42)
		draw_string_outline(f, Vector2(0, s * 0.64), cd_text, HORIZONTAL_ALIGNMENT_CENTER, s, fs, 4, Color.BLACK)
		draw_string(f, Vector2(0, s * 0.64), cd_text, HORIZONTAL_ALIGNMENT_CENTER, s, fs, Color(1, 0.95, 0.6))


func _sweep(left: float) -> void:
	var s := size.x
	var c := Vector2(s, s) * 0.5
	var pts := PackedVector2Array([c])
	var a0 := -PI / 2.0
	var a1 := a0 + TAU * left
	var n := 24
	for i in n + 1:
		var a := a0 + (a1 - a0) * i / n
		var d := Vector2(cos(a), sin(a))
		var m := maxf(absf(d.x), absf(d.y))
		pts.append(c + d / m * s * 0.5)
	if pts.size() >= 3:
		draw_colored_polygon(pts, Color(0, 0, 0, 0.62))


# ------------------------------------------------------------------ glyphs

## Draw glyph `g` into `r` on any CanvasItem (icons, the portrait badges).
static func paint(ci: CanvasItem, g: String, r: Rect2, ink: Color, shade: Color) -> void:
	var o := r.position
	var w := r.size.x
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * w
	var poly := func(a: Array, c: Color) -> void:
		var p := PackedVector2Array()
		for v: Vector2 in a:
			p.append(o + v * w)
		ci.draw_colored_polygon(p, c)
	var line := func(a: Array, c: Color, th: float) -> void:
		var p := PackedVector2Array()
		for v: Vector2 in a:
			p.append(o + v * w)
		ci.draw_polyline(p, c, th * w, true)
	var circ := func(x: float, y: float, rr: float, c: Color) -> void: ci.draw_circle(P.call(x, y), rr * w, c)
	var arc := func(x: float, y: float, rr: float, a0: float, a1: float, c: Color, th: float) -> void:
		ci.draw_arc(P.call(x, y), rr * w, a0, a1, 24, c, th * w, true)
	var sh := Color(shade, 0.65)
	match g:
		"sword", "dagger":
			var l := 0.0 if g == "sword" else 0.18
			poly.call([Vector2(0.5, 0.06 + l), Vector2(0.58, 0.18 + l), Vector2(0.56, 0.68), Vector2(0.44, 0.68), Vector2(0.42, 0.18 + l)], ink)
			poly.call([Vector2(0.28, 0.66), Vector2(0.72, 0.66), Vector2(0.72, 0.74), Vector2(0.28, 0.74)], ink.darkened(0.25))
			poly.call([Vector2(0.46, 0.74), Vector2(0.54, 0.74), Vector2(0.54, 0.9), Vector2(0.46, 0.9)], ink.darkened(0.4))
			circ.call(0.5, 0.93, 0.05, ink.darkened(0.2))
		"blades":
			for k: float in [-1.0, 1.0]:
				poly.call([Vector2(0.5 + k * 0.32, 0.1), Vector2(0.5 + k * 0.4, 0.2), Vector2(0.5 - k * 0.12, 0.78), Vector2(0.5 - k * 0.2, 0.72)], ink)
			circ.call(0.5, 0.5, 0.07, ink.darkened(0.3))
		"axe":
			line.call([Vector2(0.3, 0.92), Vector2(0.7, 0.12)], ink.darkened(0.35), 0.07)
			poly.call([Vector2(0.55, 0.12), Vector2(0.92, 0.2), Vector2(0.86, 0.5), Vector2(0.62, 0.42)], ink)
		"hammer":
			line.call([Vector2(0.28, 0.92), Vector2(0.6, 0.36)], ink.darkened(0.35), 0.08)
			poly.call([Vector2(0.38, 0.14), Vector2(0.86, 0.38), Vector2(0.74, 0.6), Vector2(0.26, 0.36)], ink)
		"shield", "wall":
			poly.call([Vector2(0.2, 0.14), Vector2(0.8, 0.14), Vector2(0.8, 0.48), Vector2(0.5, 0.9), Vector2(0.2, 0.48)], ink)
			poly.call([Vector2(0.28, 0.22), Vector2(0.5, 0.22), Vector2(0.5, 0.8), Vector2(0.28, 0.46)], sh)
			if g == "wall":
				for y: float in [0.36, 0.56]:
					line.call([Vector2(0.24, y), Vector2(0.76, y)], shade, 0.04)
		"fist", "hand", "hands":
			poly.call([Vector2(0.28, 0.32), Vector2(0.72, 0.32), Vector2(0.76, 0.66), Vector2(0.6, 0.86), Vector2(0.34, 0.86), Vector2(0.24, 0.6)], ink)
			for k in 4:
				circ.call(0.33 + k * 0.12, 0.3, 0.07, ink.lightened(0.1))
			if g == "hands":
				arc.call(0.5, 0.5, 0.42, -PI * 0.9, -PI * 0.1, Color(ink, 0.6), 0.04)
		"bolt":
			poly.call([Vector2(0.58, 0.04), Vector2(0.22, 0.56), Vector2(0.46, 0.56), Vector2(0.36, 0.96), Vector2(0.8, 0.4), Vector2(0.54, 0.4)], ink)
		"shout":
			poly.call([Vector2(0.16, 0.4), Vector2(0.36, 0.4), Vector2(0.56, 0.22), Vector2(0.56, 0.78), Vector2(0.36, 0.6), Vector2(0.16, 0.6)], ink)
			for k in 3:
				arc.call(0.56, 0.5, 0.14 + k * 0.1, -0.7, 0.7, ink, 0.04)
		"banner":
			line.call([Vector2(0.26, 0.08), Vector2(0.26, 0.94)], ink.darkened(0.3), 0.06)
			poly.call([Vector2(0.28, 0.12), Vector2(0.84, 0.12), Vector2(0.72, 0.34), Vector2(0.84, 0.56), Vector2(0.28, 0.56)], ink)
		"eye", "mark", "target":
			if g == "eye":
				poly.call([Vector2(0.08, 0.5), Vector2(0.3, 0.3), Vector2(0.7, 0.3), Vector2(0.92, 0.5), Vector2(0.7, 0.7), Vector2(0.3, 0.7)], ink)
				circ.call(0.5, 0.5, 0.14, shade)
				circ.call(0.5, 0.5, 0.06, ink)
			else:
				arc.call(0.5, 0.5, 0.36, 0, TAU, ink, 0.07)
				arc.call(0.5, 0.5, 0.18, 0, TAU, ink, 0.06)
				for d: Vector2 in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
					line.call([Vector2(0.5, 0.5) + d * 0.28, Vector2(0.5, 0.5) + d * 0.46], ink, 0.05)
				if g == "mark":
					poly.call([Vector2(0.5, 0.36), Vector2(0.6, 0.62), Vector2(0.4, 0.62)], ink)
		"boot", "paw":
			if g == "paw":
				circ.call(0.5, 0.62, 0.18, ink)
				for v: Vector2 in [Vector2(0.28, 0.36), Vector2(0.42, 0.24), Vector2(0.58, 0.24), Vector2(0.72, 0.36)]:
					circ.call(v.x, v.y, 0.08, ink)
			else:
				poly.call([Vector2(0.36, 0.1), Vector2(0.6, 0.1), Vector2(0.6, 0.6), Vector2(0.88, 0.7), Vector2(0.88, 0.86), Vector2(0.3, 0.86), Vector2(0.32, 0.6)], ink)
				for k in 3:
					line.call([Vector2(0.06, 0.4 + k * 0.14), Vector2(0.24, 0.4 + k * 0.14)], Color(ink, 0.6), 0.035)
		"heart":
			circ.call(0.36, 0.38, 0.17, ink)
			circ.call(0.64, 0.38, 0.17, ink)
			poly.call([Vector2(0.2, 0.45), Vector2(0.8, 0.45), Vector2(0.5, 0.86)], ink)
		"drop", "blood":
			poly.call([Vector2(0.5, 0.08), Vector2(0.72, 0.5), Vector2(0.28, 0.5)], ink)
			circ.call(0.5, 0.6, 0.24, ink)
			if g == "blood":
				circ.call(0.78, 0.78, 0.08, ink)
				circ.call(0.22, 0.84, 0.06, ink)
			else:
				circ.call(0.42, 0.58, 0.06, Color(1, 1, 1, 0.5))
		"crack":
			line.call([Vector2(0.5, 0.06), Vector2(0.42, 0.3), Vector2(0.6, 0.48), Vector2(0.4, 0.7), Vector2(0.54, 0.94)], ink, 0.07)
			line.call([Vector2(0.6, 0.48), Vector2(0.84, 0.56)], ink, 0.05)
			line.call([Vector2(0.42, 0.3), Vector2(0.2, 0.26)], ink, 0.05)
		"skull", "ghost":
			if g == "ghost":
				poly.call([Vector2(0.24, 0.9), Vector2(0.24, 0.4), Vector2(0.76, 0.4), Vector2(0.76, 0.9), Vector2(0.64, 0.8), Vector2(0.5, 0.9), Vector2(0.36, 0.8)], Color(ink, 0.85))
				circ.call(0.5, 0.4, 0.26, Color(ink, 0.85))
				circ.call(0.41, 0.42, 0.05, shade)
				circ.call(0.59, 0.42, 0.05, shade)
			else:
				circ.call(0.5, 0.42, 0.3, ink)
				poly.call([Vector2(0.34, 0.6), Vector2(0.66, 0.6), Vector2(0.62, 0.86), Vector2(0.38, 0.86)], ink)
				circ.call(0.39, 0.44, 0.08, shade)
				circ.call(0.61, 0.44, 0.08, shade)
				poly.call([Vector2(0.5, 0.56), Vector2(0.55, 0.66), Vector2(0.45, 0.66)], shade)
		"rage":
			for k in 7:
				var a := TAU * k / 7.0
				poly.call([Vector2(0.5, 0.5) + Vector2(cos(a - 0.25), sin(a - 0.25)) * 0.2, Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.46,
					Vector2(0.5, 0.5) + Vector2(cos(a + 0.25), sin(a + 0.25)) * 0.2], ink)
			circ.call(0.5, 0.5, 0.2, ink.lightened(0.2))
		"scales":
			line.call([Vector2(0.5, 0.12), Vector2(0.5, 0.88)], ink, 0.05)
			line.call([Vector2(0.16, 0.26), Vector2(0.84, 0.26)], ink, 0.05)
			for x: float in [0.22, 0.78]:
				poly.call([Vector2(x - 0.14, 0.56), Vector2(x + 0.14, 0.56), Vector2(x, 0.68)], ink)
				line.call([Vector2(x - 0.12, 0.56), Vector2(x, 0.27), Vector2(x + 0.12, 0.56)], ink, 0.025)
			poly.call([Vector2(0.34, 0.92), Vector2(0.66, 0.92), Vector2(0.5, 0.82)], ink)
		"sun", "spark", "nova", "burst", "star":
			var n := 12 if g == "sun" else (8 if g != "star" else 5)
			var ro := 0.46
			var ri := 0.28 if g == "sun" else (0.12 if g == "spark" else 0.2)
			var pts: Array = []
			for k in n * 2:
				var a := TAU * k / (n * 2) - PI / 2.0
				pts.append(Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * (ro if k % 2 == 0 else ri))
			poly.call(pts, ink)
			if g == "sun" or g == "nova":
				circ.call(0.5, 0.5, 0.18, ink.lightened(0.3))
		"cross", "ankh":
			if g == "ankh":
				arc.call(0.5, 0.28, 0.14, 0, TAU, ink, 0.07)
				poly.call([Vector2(0.45, 0.4), Vector2(0.55, 0.4), Vector2(0.55, 0.92), Vector2(0.45, 0.92)], ink)
				poly.call([Vector2(0.22, 0.46), Vector2(0.78, 0.46), Vector2(0.78, 0.55), Vector2(0.22, 0.55)], ink)
			else:
				poly.call([Vector2(0.4, 0.1), Vector2(0.6, 0.1), Vector2(0.6, 0.4), Vector2(0.9, 0.4), Vector2(0.9, 0.6), Vector2(0.6, 0.6),
					Vector2(0.6, 0.9), Vector2(0.4, 0.9), Vector2(0.4, 0.6), Vector2(0.1, 0.6), Vector2(0.1, 0.4), Vector2(0.4, 0.4)], ink)
		"ring":
			arc.call(0.5, 0.5, 0.34, 0, TAU, ink, 0.1)
			arc.call(0.5, 0.5, 0.18, 0, TAU, Color(ink, 0.6), 0.05)
		"bubble", "cube":
			if g == "cube":
				poly.call([Vector2(0.5, 0.12), Vector2(0.86, 0.3), Vector2(0.5, 0.48), Vector2(0.14, 0.3)], ink.lightened(0.2))
				poly.call([Vector2(0.14, 0.3), Vector2(0.5, 0.48), Vector2(0.5, 0.9), Vector2(0.14, 0.72)], ink)
				poly.call([Vector2(0.86, 0.3), Vector2(0.86, 0.72), Vector2(0.5, 0.9), Vector2(0.5, 0.48)], ink.darkened(0.25))
			else:
				circ.call(0.5, 0.5, 0.38, Color(ink, 0.35))
				arc.call(0.5, 0.5, 0.38, 0, TAU, ink, 0.06)
				arc.call(0.5, 0.5, 0.26, PI * 1.1, PI * 1.45, Color(1, 1, 1, 0.8), 0.05)
		"crown":
			poly.call([Vector2(0.14, 0.76), Vector2(0.14, 0.3), Vector2(0.32, 0.5), Vector2(0.5, 0.22), Vector2(0.68, 0.5), Vector2(0.86, 0.3), Vector2(0.86, 0.76)], ink)
			for x: float in [0.14, 0.5, 0.86]:
				circ.call(x, 0.26 if x != 0.5 else 0.18, 0.06, ink.lightened(0.2))
		"wave", "swirl":
			if g == "swirl":
				for k in 3:
					arc.call(0.5, 0.5, 0.12 + k * 0.12, k * 1.4, k * 1.4 + PI * 1.3, ink, 0.06)
			else:
				for k in 3:
					var y := 0.3 + k * 0.2
					var pts: Array = []
					for i in 9:
						pts.append(Vector2(0.1 + i * 0.1, y + sin(i * 0.9) * 0.06))
					line.call(pts, ink, 0.06)
		"wing":
			for k in 4:
				poly.call([Vector2(0.5, 0.75), Vector2(0.12 + k * 0.06, 0.18 + k * 0.12), Vector2(0.3 + k * 0.05, 0.3 + k * 0.12)], ink.darkened(k * 0.08))
				poly.call([Vector2(0.5, 0.75), Vector2(0.88 - k * 0.06, 0.18 + k * 0.12), Vector2(0.7 - k * 0.05, 0.3 + k * 0.12)], ink.darkened(k * 0.08))
		"flame", "meteor":
			if g == "meteor":
				for k in 3:
					line.call([Vector2(0.86 - k * 0.08, 0.1 + k * 0.04), Vector2(0.5 - k * 0.06, 0.48 + k * 0.03)], Color(ink, 0.5 - k * 0.12), 0.1 - k * 0.02)
				circ.call(0.38, 0.62, 0.22, ink)
				circ.call(0.34, 0.6, 0.1, ink.lightened(0.4))
			else:
				poly.call([Vector2(0.5, 0.06), Vector2(0.72, 0.36), Vector2(0.78, 0.66), Vector2(0.64, 0.88), Vector2(0.36, 0.88), Vector2(0.22, 0.66),
					Vector2(0.3, 0.44), Vector2(0.4, 0.56), Vector2(0.42, 0.32)], ink)
				poly.call([Vector2(0.52, 0.4), Vector2(0.64, 0.64), Vector2(0.56, 0.84), Vector2(0.44, 0.84), Vector2(0.38, 0.68)], ink.lightened(0.4))
		"frost", "snow":
			for k in 3:
				var a := PI * k / 3.0
				var d := Vector2(cos(a), sin(a)) * 0.42
				line.call([Vector2(0.5, 0.5) - d, Vector2(0.5, 0.5) + d], ink, 0.06)
				for sgn: float in [-1.0, 1.0]:
					var tip: Vector2 = Vector2(0.5, 0.5) + d * 0.62 * sgn
					var nrm := Vector2(-d.y, d.x).normalized() * 0.1
					line.call([tip - nrm + d.normalized() * 0.08 * sgn, tip, tip + nrm + d.normalized() * 0.08 * sgn], ink, 0.045)
			if g == "snow":
				circ.call(0.5, 0.5, 0.08, ink)
		"brain":
			circ.call(0.38, 0.44, 0.2, ink)
			circ.call(0.6, 0.42, 0.22, ink)
			circ.call(0.5, 0.6, 0.2, ink)
			arc.call(0.44, 0.44, 0.1, 0.0, PI, shade, 0.03)
			arc.call(0.6, 0.5, 0.1, PI, TAU, shade, 0.03)
		"blink":
			for k in 3:
				circ.call(0.24 + k * 0.2, 0.5, 0.06 + k * 0.04, Color(ink, 0.4 + k * 0.3))
			poly.call([Vector2(0.72, 0.28), Vector2(0.94, 0.5), Vector2(0.72, 0.72)], ink)
		"hourglass":
			poly.call([Vector2(0.24, 0.12), Vector2(0.76, 0.12), Vector2(0.54, 0.5), Vector2(0.76, 0.88), Vector2(0.24, 0.88), Vector2(0.46, 0.5)], ink)
			poly.call([Vector2(0.36, 0.78), Vector2(0.64, 0.78), Vector2(0.5, 0.6)], shade)
		"arrow", "arrows", "rain":
			var n := 1 if g == "arrow" else 3
			for k in n:
				var off := Vector2((k - (n - 1) * 0.5) * 0.2, 0.0)
				if g == "rain":
					off = Vector2((k - 1) * 0.26, (k % 2) * 0.12)
					line.call([Vector2(0.5, 0.1) + off, Vector2(0.5, 0.74) + off], ink, 0.05)
					poly.call([Vector2(0.42, 0.72) + off, Vector2(0.58, 0.72) + off, Vector2(0.5, 0.9) + off], ink)
				else:
					line.call([Vector2(0.18, 0.82) + off, Vector2(0.78, 0.22) + off], ink, 0.05)
					poly.call([Vector2(0.86, 0.14) + off, Vector2(0.66, 0.2) + off, Vector2(0.8, 0.34) + off], ink)
					line.call([Vector2(0.12, 0.74) + off, Vector2(0.26, 0.88) + off], ink.darkened(0.3), 0.06)
		"bow":
			arc.call(0.3, 0.5, 0.42, -PI * 0.4, PI * 0.4, ink, 0.07)
			line.call([Vector2(0.43, 0.1), Vector2(0.43, 0.9)], Color(ink, 0.7), 0.025)
			line.call([Vector2(0.2, 0.5), Vector2(0.9, 0.5)], ink, 0.04)
			poly.call([Vector2(0.94, 0.5), Vector2(0.82, 0.42), Vector2(0.82, 0.58)], ink)
		"snake":
			var pts: Array = []
			for i in 13:
				pts.append(Vector2(0.12 + i * 0.065, 0.5 + sin(i * 0.9) * 0.2))
			line.call(pts, ink, 0.09)
			circ.call(0.9, 0.5 + sin(12 * 0.9) * 0.2, 0.08, ink)
		"bomb":
			circ.call(0.46, 0.58, 0.3, ink)
			line.call([Vector2(0.62, 0.32), Vector2(0.74, 0.18), Vector2(0.84, 0.16)], ink.darkened(0.3), 0.05)
			circ.call(0.86, 0.14, 0.07, Color(1, 0.8, 0.3))
			circ.call(0.36, 0.48, 0.07, Color(1, 1, 1, 0.5))
		"bandage":
			poly.call([Vector2(0.12, 0.66), Vector2(0.66, 0.12), Vector2(0.88, 0.34), Vector2(0.34, 0.88)], ink)
			poly.call([Vector2(0.38, 0.4), Vector2(0.6, 0.4), Vector2(0.6, 0.6), Vector2(0.38, 0.6)], ink.darkened(0.3))
		"potion":
			# G52: a round flask, a neck and a cork; the liquid is the tile's colour
			circ.call(0.5, 0.64, 0.27, ink)
			circ.call(0.5, 0.67, 0.21, Color(shade, 0.35))
			poly.call([Vector2(0.42, 0.18), Vector2(0.58, 0.18), Vector2(0.58, 0.42), Vector2(0.42, 0.42)], ink)
			poly.call([Vector2(0.39, 0.08), Vector2(0.61, 0.08), Vector2(0.61, 0.19), Vector2(0.39, 0.19)], Color("#a07a4a"))
			circ.call(0.41, 0.56, 0.06, Color(1, 1, 1, 0.55))
		"gem":
			poly.call([Vector2(0.5, 0.1), Vector2(0.86, 0.4), Vector2(0.5, 0.9), Vector2(0.14, 0.4)], ink)
			poly.call([Vector2(0.5, 0.1), Vector2(0.86, 0.4), Vector2(0.5, 0.48)], Color(1, 1, 1, 0.35))
			line.call([Vector2(0.14, 0.4), Vector2(0.5, 0.48), Vector2(0.86, 0.4)], sh, 0.03)
			line.call([Vector2(0.5, 0.48), Vector2(0.5, 0.9)], sh, 0.03)
		"dice":
			poly.call([Vector2(0.18, 0.18), Vector2(0.82, 0.18), Vector2(0.82, 0.82), Vector2(0.18, 0.82)], ink)
			for v: Vector2 in [Vector2(0.32, 0.32), Vector2(0.68, 0.68), Vector2(0.5, 0.5), Vector2(0.68, 0.32), Vector2(0.32, 0.68)]:
				circ.call(v.x, v.y, 0.06, shade)
		_:
			circ.call(0.5, 0.5, 0.3, ink)
