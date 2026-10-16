class_name MmoHud
extends CanvasLayer
## WoW Classic's interface, after the author's reference
## (design/ref/mmo/wow_classic_ui.jpg), laid out on the 1600x900 canvas:
##   top left      your frame (round portrait, level, name, health, power),
##                 the target's frame beside it (portrait on the right, the
##                 gold elite dragon on the Giant), its cast bar and debuffs,
##                 target of target; the party down the left edge
##   top right     the round minimap with the zone name and a clock; your
##                 buffs to its left; the objective tracker and the boss
##                 timer bars below
##   bottom        the spells (1-8) and above them the consumables (Shift+1-8,
##                 G52) between gryphon end caps, the XP bar, the micro menu and bags; your cast bar
##                 above; chat / combat log bottom left; the damage meter and
##                 the threat meter bottom right
##   middle        raid warnings (orange), errors (red), "You have died"

const W := 1600.0
const H := 900.0
const GOLD := Color("#ffd100")
const HOSTILE := Color("#d42a20")
const FRIEND := Color("#25b51f")
const HP := Color("#1ec51e")
const MANA := Color("#2a53d4")
const RAGE := Color("#d42020")
const ENERGY := Color("#e6d32a")
const FRAME_BG := Color(0.02, 0.02, 0.03, 0.82)
const STONE := Color("#5b5650")
const STONE_HI := Color("#8a847a")

var sim: MmoSim
var me_id := ""
var view: Node                         # MmoView (untyped: no cyclic class refs)
var portraits := {}                    # unit id -> Texture2D
var serif: Font
var sans: Font

var _root: Control
var _player_f: UnitFrame
var _target_f: UnitFrame
var _tot_f: UnitFrame
var _party: Array = []                 # UnitFrame
var _buttons: Array = []               # MmoIcon
var _cast_bar: CastBar
var _tcast_bar: CastBar
var _tdebuffs: Control
var _buffs: Control
var _log: RichTextLabel
var _log_lines: Array = []
var _warn: Label
var _warn_t := 0.0
var _err: Label
var _err_t := 0.0
var _dead: Label
var _meter: Meter
var _threat: Meter
var _mini: Minimap
var _clock: Label
var _tracker: RichTextLabel
var _timers: Control
var _xp: XpBar
var _center: Label
var _center_t := 0.0
var _help: Label
var tooltip: Tooltip


func _ready() -> void:
	layer = 20
	serif = _font(["Friz Quadrata TT", "Friz Quadrata", "Palatino Linotype", "Book Antiqua", "Georgia"], 600)
	sans = _font(["Arial", "Helvetica", "Liberation Sans"], 700)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build()


static func _font(names: Array, weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return f


func _label(parent: Control, text: String, pos: Vector2, size_: int, col: Color, font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT, width := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	if width > 0.0:
		l.size = Vector2(width, size_ + 6)
	l.horizontal_alignment = align
	l.add_theme_font_override("font", font if font else serif)
	l.add_theme_font_size_override("font_size", size_)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _build() -> void:
	# unit frames
	_player_f = UnitFrame.new(self, false, 1.0)
	_player_f.position = Vector2(6, 6)
	_root.add_child(_player_f)
	_target_f = UnitFrame.new(self, true, 1.0)
	_target_f.position = Vector2(262, 6)
	_root.add_child(_target_f)
	_tot_f = UnitFrame.new(self, false, 0.55)
	_tot_f.position = Vector2(470, 84)
	_root.add_child(_tot_f)
	_tcast_bar = CastBar.new(self, Vector2(170, 14))
	_tcast_bar.position = Vector2(282, 96)
	_tcast_bar.hostile = true
	_root.add_child(_tcast_bar)
	_tdebuffs = Control.new()
	_tdebuffs.position = Vector2(282, 116)
	_root.add_child(_tdebuffs)
	for i in 7:                                         # a raid of eight: you + seven (G39)
		var f := UnitFrame.new(self, false, 0.6)
		f.position = Vector2(4, 140 + i * 66)
		f.party = true
		_root.add_child(f)
		_party.append(f)
	# the minimap, zone and clock; buffs to its left
	_mini = Minimap.new(self)
	_mini.position = Vector2(W - 178, 22)
	_mini.size = Vector2(164, 164)
	_root.add_child(_mini)
	var zone := Panel.new()
	zone.position = Vector2(W - 196, 2)
	zone.size = Vector2(200, 20)
	var zs := StyleBoxFlat.new()
	zs.bg_color = Color(0, 0, 0, 0.55)
	zs.set_corner_radius_all(3)
	zone.add_theme_stylebox_override("panel", zs)
	_root.add_child(zone)
	_label(zone, "Campus Clearing" if sim and sim.tank else "Giant's Courtyard", Vector2(0, 0), 14, GOLD, serif, HORIZONTAL_ALIGNMENT_CENTER, 200)
	_clock = _label(_root, "", Vector2(W - 54, 168), 13, Color(0.9, 0.9, 0.9), sans)
	_buffs = Control.new()
	_buffs.position = Vector2(W - 200, 8)
	_root.add_child(_buffs)
	# objective tracker and boss timers
	_tracker = RichTextLabel.new()
	_tracker.bbcode_enabled = true
	_tracker.fit_content = true
	_tracker.scroll_active = false
	_tracker.position = Vector2(W - 330, 214)
	_tracker.size = Vector2(320, 70)
	_tracker.add_theme_font_override("normal_font", serif)
	_tracker.add_theme_font_size_override("normal_font_size", 15)
	_tracker.add_theme_constant_override("outline_size", 4)
	_tracker.add_theme_color_override("font_outline_color", Color.BLACK)
	_tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_tracker)
	_timers = Control.new()
	_timers.position = Vector2(W - 330, 296)
	_root.add_child(_timers)
	# meters
	_threat = Meter.new(self, "TW Threatmeter v1.2.3", ["Name", "TPS", "Threat", "% Max"])
	_threat.position = Vector2(W - 352, H - 286)
	_threat.size = Vector2(340, 150)
	_root.add_child(_threat)
	_meter = Meter.new(self, "Current", ["DPS"])
	_meter.position = Vector2(W - 312, H - 506)        # eight rows (G39)
	_meter.size = Vector2(300, 166)
	_root.add_child(_meter)
	# chat
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_active = false
	_log.position = Vector2(6, H - 290)
	_log.size = Vector2(380, 172)
	_log.add_theme_font_override("normal_font", sans)
	_log.add_theme_font_size_override("normal_font_size", 12)
	_log.add_theme_constant_override("outline_size", 3)
	_log.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_log)
	# the main bar
	var bar := MainBar.new(self)
	bar.position = Vector2(W * 0.5 - 520, H - 108)
	bar.size = Vector2(1040, 108)
	_root.add_child(bar)
	for i in MmoClasses.SLOTS + MmoItems.ITEMS.size():
		var b := MmoIcon.new()
		b.size = Vector2(42, 42)
		var row := 1 if i < 8 else 0
		b.position = bar.position + Vector2(MainBar.X0 + 2 + (i % 8) * 46, 10 + row * 52)
		b.key = MmoClasses.key_label(i)
		b.font = sans
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		var slot := i
		b.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and view:
				view.press_slot(slot))
		b.mouse_entered.connect(func() -> void: _show_tip(slot, b))
		b.mouse_exited.connect(func() -> void: tooltip.visible = false)
		_root.add_child(b)
		_buttons.append(b)
	var utils := [["sword", "#c0c0c0", "Attack: start swinging (or shooting) at your target."],
		["hand", "#d04040", "Stop casting."], ["target", "#e05a3c", "Target the Giant (Tab)."], ["heart", "#40c040", "Target yourself (F2)."]]
	for i in utils.size():
		var u: Array = utils[i]
		var ub := MmoIcon.new(str(u[0]), Color(str(u[1])))
		ub.size = Vector2(40, 40)
		ub.position = bar.position + Vector2(MainBar.X0 + 8 * 46 + 21 + i * 46, 11)
		ub.font = sans
		ub.mouse_filter = Control.MOUSE_FILTER_STOP
		ub.tooltip_text = str(u[2])
		var idx := i
		ub.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and view:
				view.utility(idx))
		_root.add_child(ub)
	_xp = XpBar.new()
	_xp.position = bar.position + Vector2(MainBar.X0, 56)
	_xp.size = Vector2(bar.size.x - MainBar.X0 * 2, 7)
	_root.add_child(_xp)
	_cast_bar = CastBar.new(self, Vector2(260, 20))
	_cast_bar.position = Vector2(W * 0.5 - 130, H - 162)
	_root.add_child(_cast_bar)
	# middle texts
	_warn = _label(_root, "", Vector2(0, 156), 26, Color("#ff8a2a"), serif, HORIZONTAL_ALIGNMENT_CENTER, W)
	_warn.add_theme_constant_override("outline_size", 10)
	var wsb := StyleBoxFlat.new()                  # a dark band behind it: legible over the Giant
	wsb.bg_color = Color(0, 0, 0, 0.45)
	wsb.content_margin_top = 2
	wsb.content_margin_bottom = 2
	_warn.add_theme_stylebox_override("normal", wsb)
	_err = _label(_root, "", Vector2(0, 118), 18, Color("#ff2020"), serif, HORIZONTAL_ALIGNMENT_CENTER, W)
	_center = _label(_root, "", Vector2(0, 300), 40, GOLD, serif, HORIZONTAL_ALIGNMENT_CENTER, W)
	_dead = _label(_root, "", Vector2(0, 230), 30, Color("#ff4040"), serif, HORIZONTAL_ALIGNMENT_CENTER, W)
	_help = _label(_root, "", Vector2(W * 0.5 - 300, H - 200), 13, Color(0.85, 0.85, 0.85, 0.9), sans, HORIZONTAL_ALIGNMENT_CENTER, 600)
	tooltip = Tooltip.new(self)
	tooltip.visible = false
	_root.add_child(tooltip)


# ------------------------------------------------------------------ feed

func log_line(text: String, col := Color(1, 1, 1)) -> void:
	_log_lines.append("[color=#%s]%s[/color]" % [col.to_html(false), text])
	if _log_lines.size() > 8:
		_log_lines.pop_front()
	_log.text = "\n".join(_log_lines)


## Below half health the fight stops talking (G35): only the one line gets through.
func quiet() -> bool:
	return sim != null and sim.silent


func warn(text: String, col := Color("#ff8a2a"), always := false) -> void:
	if quiet() and not always:
		return
	_warn.text = text
	_warn.add_theme_color_override("font_color", col)
	_warn_t = 4.5
	log_line("[Raid Warning]: " + text, col)


func error(text: String) -> void:
	_err.text = text
	_err_t = 1.8


func center(text: String, t := 4.0) -> void:
	if quiet() and sim.winner == "":
		return
	_center.text = text
	_center_t = t


func help(text: String) -> void:
	_help.text = text


func _show_tip(slot: int, b: Control) -> void:
	var me := sim.unit(me_id) if sim else null
	if me == null:
		return
	var abs: Array = MmoClasses.abilities(me.cls)
	var ab: Dictionary = abs[slot] if slot < abs.size() else MmoItems.at_slot(slot)
	if ab.is_empty():
		return
	tooltip.show_for(ab, me)
	tooltip.position = Vector2(clampf(b.position.x - 80, 4, W - 320), b.position.y - tooltip.size.y - 8)
	tooltip.visible = true


# ---------------------------------------------------------------- update

func update(delta: float) -> void:
	if sim == null:
		return
	var me := sim.unit(me_id)
	_player_f.unit = me
	var tgt := sim.unit(me.target) if me and me.target != "" else null
	_target_f.unit = tgt
	_target_f.visible = tgt != null
	var tot := sim.unit(tgt.target) if tgt and tgt.target != "" else null
	_tot_f.unit = tot
	_tot_f.visible = tot != null
	_tcast_bar.unit = tgt
	var k := 0
	for p: MmoUnit in sim.players():
		if p.id == me_id:
			continue
		if k < _party.size():
			(_party[k] as UnitFrame).unit = p
			k += 1
	for f: UnitFrame in [_player_f, _target_f, _tot_f] + _party:
		f.queue_redraw()
	_cast_bar.unit = me
	_cast_bar.queue_redraw()
	_tcast_bar.queue_redraw()
	_bar_update(me)
	_auras(_buffs, me, false, true)
	_auras(_tdebuffs, tgt, true, false)
	_mini.queue_redraw()
	_meter.rows = _meter_rows()
	_meter.queue_redraw()
	_threat.rows = _threat_rows()
	_threat.queue_redraw()
	_tracker.text = _tracker_text()
	_timers_update()
	var secs := int(sim.time)
	_clock.text = "%d:%02d" % [secs / 60, secs % 60]
	_warn_t -= delta
	_err_t -= delta
	_center_t -= delta
	_warn.modulate.a = clampf(_warn_t, 0.0, 1.0)
	_err.modulate.a = clampf(_err_t, 0.0, 1.0)
	_center.modulate.a = clampf(_center_t, 0.0, 1.0)
	_dead.text = "You have died.  A healer can bring you back." if me and not me.alive else ""
	for b: MmoIcon in _buttons:
		b.lit = maxf(0.0, b.lit - delta * 4.0)


func flash_slot(slot: int) -> void:
	if slot >= 0 and slot < _buttons.size():
		(_buttons[slot] as MmoIcon).lit = 1.0


func _bar_update(me: MmoUnit) -> void:
	if me == null:
		return
	var abs: Array = MmoClasses.abilities(me.cls)
	var tgt := sim.unit(me.target) if me.target != "" else null
	for i in _buttons.size():
		var b: MmoIcon = _buttons[i]
		var ab: Dictionary = abs[i] if i < abs.size() else MmoItems.at_slot(i)
		if ab.is_empty():
			b.visible = false
			continue
		b.glyph = str(ab.glyph)
		b.col = Color(str(ab.col))
		var cdl := float(me.cd.get(str(ab.id), 0.0))
		var cdt := float(ab.get("cd", 0.0))
		var gcd_full := MmoTune.value("gcd")
		if cdl > 0.0 and cdt > 0.0:
			b.cd = clampf(cdl / cdt, 0.0, 1.0)
			b.cd_text = (("%d" % ceili(cdl)) if cdl < 60.0 else ("%dm" % ceili(cdl / 60.0))) if cdl >= 1.5 else ""
		elif bool(ab.get("gcd", true)) and me.gcd > 0.0:
			b.cd = clampf(me.gcd / gcd_full, 0.0, 1.0)
			b.cd_text = ""
		else:
			b.cd = 0.0
			b.cd_text = ""
		var cost := float(ab.get("cost", 0.0))
		b.dim = me.res < cost or not me.alive or (ab.get("finisher", false) and me.cp <= 0)
		var r := float(ab.get("range", 0.0))
		var t_ok := true
		if str(ab.get("tgt", "")) == "enemy":
			t_ok = tgt != null and tgt.alive and sim.is_enemy(me, tgt) and sim.dist(me, tgt) <= r
		b.red_key = not t_ok
		b.queue_redraw()


func _auras(box: Control, u: MmoUnit, debuffs: bool, big: bool) -> void:
	for c in box.get_children():
		c.queue_free()
	if u == null:
		return
	var i := 0
	var sz := 30.0 if big else 22.0
	for a: Dictionary in u.auras:
		if debuffs and not a.get("debuff", false) and u.kind == "boss":
			continue
		if i >= 12:
			break
		var ic := MmoIcon.new(str(a.get("glyph", "star")), Color(str(a.get("col", "#888888"))))
		ic.size = Vector2(sz, sz)
		ic.font = sans
		ic.border = Color("#c01010") if a.get("debuff", false) else Color(0.05, 0.05, 0.05)
		if big:
			ic.position = Vector2(-(i + 1) * (sz + 6), 0)
			var tl := float(a.t)
			var txt := ("%d m" % ceili(tl / 60.0)) if tl >= 60.0 else ("%d s" % ceili(tl))
			_label(box, txt, ic.position + Vector2(-6, sz + 1), 11, GOLD, sans, HORIZONTAL_ALIGNMENT_CENTER, sz + 12)
		else:
			ic.position = Vector2(i * (sz + 3), 0)
			if a.has("shield"):
				ic.count = "%d" % int(a.shield)
		box.add_child(ic)
		i += 1


func _meter_rows() -> Array:
	var ps := sim.players().duplicate()
	var secs := maxf(1.0, sim.time - sim.pull_time) if sim.pulled else 1.0
	ps.sort_custom(func(a: MmoUnit, b: MmoUnit) -> bool: return a.dmg_done + a.heal_done > b.dmg_done + b.heal_done)
	var total := 0.0
	for p: MmoUnit in ps:
		total += p.dmg_done + p.heal_done
	var rows: Array = []
	var top := 0.0
	for p: MmoUnit in ps:
		top = maxf(top, p.dmg_done + p.heal_done)
	var n := 1
	for p: MmoUnit in ps:
		var v := p.dmg_done + p.heal_done
		rows.append({ "text": "%d. %s" % [n, p.name], "val": "%.1f (%.1f%%)" % [v / secs, 100.0 * v / maxf(1.0, total)],
			"frac": v / maxf(1.0, top), "col": MmoClasses.color(p.cls), "me": p.id == me_id })
		n += 1
	return rows


func _threat_rows() -> Array:
	var rows: Array = []
	var b := sim.boss
	if b == null or not sim.pulled:
		return rows
	var top := 0.0
	for k: String in b.threat:
		top = maxf(top, float(b.threat[k]))
	var ids := b.threat.keys()
	ids.sort_custom(func(x: String, y: String) -> bool: return float(b.threat[x]) > float(b.threat[y]))
	var secs := maxf(1.0, sim.time - sim.pull_time)
	for id: String in ids:
		var u := sim.unit(id)
		if u == null:
			continue
		var th := float(b.threat[id])
		rows.append({ "cols": [u.name, "%d" % int(th / secs), "%d" % int(th), "%d%%" % int(100.0 * th / maxf(1.0, top))],
			"frac": th / maxf(1.0, top), "col": MmoClasses.color(u.cls), "me": id == me_id })
	return rows


func _tracker_text() -> String:
	var alive := sim.living().size()
	var b := sim.boss
	var dead := 0 if b.alive else 1
	var zone := "Planet of Tanks: the Campus Clearing" if sim.tank else "The Giant's Courtyard"
	var t := "[color=#ffd100][60+] %s[/color] [color=#%s](%d%%)[/color]\n" % [zone, ("40ff40" if dead else "ff4040"), int(100.0 - b.hp_pct() * 100.0)]
	t += "[color=#e0e0e0] - %s destroyed: %d/1[/color]\n" % [b.name, dead] if sim.tank else "[color=#e0e0e0] - The Giant slain: %d/1[/color]\n" % dead
	t += "[color=#e0e0e0] - Raid standing: %d/%d[/color]" % [alive, sim.players().size()]
	return t


func _timers_update() -> void:
	for c in _timers.get_children():
		c.queue_free()
	var rows: Array = []
	if quiet():
		return
	if sim.pulled and sim.boss.alive:
		if sim.spell.is_empty():
			var left := sim.next_spell_at - sim.time
			if left > 0.0 and left < 60.0:
				var nxt := str(sim._bag[0]) if not sim._bag.is_empty() and sim.tank == null else "?"
				rows.append(["Next: " + (sim.spell_name(nxt) if nxt != "?" else ("something" if sim.tank else "a spell")), left, MmoTune.value("spell_gap") + 2.0, Color("#c06030")])
		else:
			if str(sim.spell.stage) == "cast":
				rows.append([sim.spell_name(str(sim.spell.id)), maxf(0.0, float(sim.spell.total) - float(sim.spell.t)), float(sim.spell.total), Color("#c02020")])
		var enr := MmoTune.value("enrage") - (sim.time - sim.pull_time)
		if enr > 0.0:
			rows.append(["Enrage", enr, MmoTune.value("enrage"), Color("#802020")])
		var el := sim.time - sim.pull_time
		var sc_at := MmoTune.value("scorch_at") if sim.tank == null else INF
		if el < sc_at and el >= sc_at - MmoTune.value("scorch_warn") - 6.0:
			rows.append(["Scorched Earth", sc_at - el, MmoTune.value("scorch_warn") + 6.0, Color("#d04010")])
		elif sim.tank == null and el < MmoTune.value("scorch_spin_at") and el >= MmoTune.value("scorch_spin_at") - MmoTune.value("scorch_spin_warn"):
			rows.append(["The fire turns", MmoTune.value("scorch_spin_at") - el, maxf(0.1, MmoTune.value("scorch_spin_warn")), Color("#d04010")])   # G52: was 10 s
	for a: Dictionary in sim.areas:
		if str(a.kind) == "ring":
			rows.append(["Earthshatter: GET IN", float(a.t), float(a.dur), Color("#d0a020")])
			break
	var me := sim.unit(me_id)
	if me and me.has_aura("bomb"):
		var ba := me.aura("bomb")
		rows.append(["BOMB ON YOU: spread!", float(ba.t), float(ba.dur), Color("#ff3010")])
	if me and me.has_aura(MmoSim.BRAND):
		var br := me.aura(MmoSim.BRAND)
		rows.append(["CINDERBRAND: run, cleanse or heal", float(br.t), float(br.dur), Color("#e06018")])
	var y := 0.0
	for r: Array in rows:
		var bar := TimerBar.new(self, str(r[0]), float(r[1]), float(r[2]), r[3])
		bar.position = Vector2(0, y)
		bar.size = Vector2(300, 20)
		_timers.add_child(bar)
		y += 24.0


# ================================================================= pieces

class UnitFrame extends Control:
	var hud: MmoHud
	var unit: MmoUnit
	var mirrored := false
	var party := false
	var k := 1.0

	func _init(h: MmoHud, mirror: bool, scale_k: float) -> void:
		hud = h
		mirrored = mirror
		k = scale_k
		size = Vector2(250, 84) * k
		mouse_filter = Control.MOUSE_FILTER_STOP
		gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and unit and hud.view:
				hud.view.set_target(unit.id))

	func _draw() -> void:
		if unit == null:
			return
		var pr := 36.0 * k                                    # portrait radius
		var pc := Vector2(250 * k - pr - 4, pr + 4) if mirrored else Vector2(pr + 4, pr + 4)
		var bx := 8.0 * k if mirrored else pc.x + pr - 6.0 * k
		var bw := 160.0 * k
		# the plate behind the bars
		draw_rect(Rect2(bx, 10 * k, bw + 10 * k, 50 * k), MmoHud.FRAME_BG)
		# name plate (the target's coloured by reaction)
		var name_bg := Color(0, 0, 0, 0.6)
		if mirrored:
			name_bg = MmoHud.HOSTILE.darkened(0.15) if unit.kind == "boss" else Color("#1f3fae")
		draw_rect(Rect2(bx + 4 * k, 12 * k, bw, 16 * k), name_bg)
		var nc := MmoHud.GOLD if not mirrored else Color.WHITE
		if party:
			nc = MmoClasses.color(unit.cls)
		_text(unit.name, Vector2(bx + 4 * k, 12 * k), bw, int(13 * k + 1), nc, HORIZONTAL_ALIGNMENT_CENTER, hud.serif)
		# health
		var hy := 29.0 * k
		draw_rect(Rect2(bx + 4 * k, hy, bw, 14 * k), Color(0.05, 0.12, 0.05))
		var hpf := clampf(unit.hp / maxf(1.0, unit.max_hp), 0.0, 1.0)
		draw_rect(Rect2(bx + 4 * k, hy, bw * hpf, 14 * k), MmoHud.HP if unit.alive else Color(0.3, 0.3, 0.3))
		var htxt := ("%d%%" % int(round(hpf * 100.0))) if mirrored else "Health %d / %d" % [int(unit.hp), int(unit.max_hp)]
		if party:
			htxt = ""
		if not unit.alive:
			htxt = "Dead"
		_text(htxt, Vector2(bx + 4 * k, hy - 1), bw, int(12 * k + 1), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, hud.sans)
		# power
		var my := hy + 15.0 * k
		if unit.res_kind != "none":
			var pc2: Color = { "mana": MmoHud.MANA, "rage": MmoHud.RAGE, "energy": MmoHud.ENERGY }.get(unit.res_kind, MmoHud.MANA)
			draw_rect(Rect2(bx + 4 * k, my, bw, 12 * k), pc2.darkened(0.75))
			draw_rect(Rect2(bx + 4 * k, my, bw * clampf(unit.res / maxf(1.0, unit.res_max), 0.0, 1.0), 12 * k), pc2)
			if k >= 0.9:
				_text("%s %d / %d" % [unit.res_kind.capitalize(), int(unit.res), int(unit.res_max)], Vector2(bx + 4 * k, my - 2), bw, 11, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, hud.sans)
		elif mirrored:
			draw_rect(Rect2(bx + 4 * k, my, bw, 12 * k), Color(0.12, 0.12, 0.14))
			_text("%d / %d" % [int(unit.hp), int(unit.max_hp)], Vector2(bx + 4 * k, my - 2), bw, 11, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_CENTER, hud.sans)
		# rogue combo points
		if not mirrored and unit.cls == "rogue" and k >= 0.9:
			for i in 5:
				var c := Vector2(bx + 30 * k + i * 22 * k, my + 22 * k)
				draw_circle(c, 6 * k, Color(0, 0, 0, 0.8))
				if i < unit.cp:
					draw_circle(c, 4.5 * k, Color("#ff2a1a"))
		# portrait: a round face in a gold ring
		if unit.kind == "boss" and mirrored:
			_dragon(pc, pr)
		draw_circle(pc, pr + 3 * k, Color("#2a2418"))
		var tex: Texture2D = hud.portraits.get(unit.id)
		if tex:
			draw_set_transform(pc, 0.0, Vector2.ONE)
			_circle_tex(tex, pr)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_circle(pc, pr, Color(0.2, 0.2, 0.22))
		draw_arc(pc, pr + 1.5 * k, 0, TAU, 48, Color("#c9a54a") if unit.kind == "boss" else Color("#9a9080"), 3.0 * k, true)
		if not unit.alive:
			draw_circle(pc, pr, Color(0, 0, 0, 0.55))
		# level badge
		var lc := pc + Vector2(-pr * 0.82 if not mirrored else pr * 0.82, pr * 0.78)
		draw_circle(lc, 11 * k, Color(0.05, 0.05, 0.05))
		draw_arc(lc, 11 * k, 0, TAU, 24, Color("#c9a54a"), 2.0 * k, true)
		var lvl := "??" if unit.kind == "boss" else "60"
		_text(lvl, lc - Vector2(11 * k, 9 * k), 22 * k, int(12 * k + 1), MmoHud.GOLD if unit.kind != "boss" else Color("#ff4030"), HORIZONTAL_ALIGNMENT_CENTER, hud.sans)
		if hud.sim and hud.sim.unit(hud.me_id) and hud.sim.unit(hud.me_id).target == unit.id and party:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.85, 0.2, 0.9), false, 2.0)

	func _circle_tex(tex: Texture2D, r: float) -> void:
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in 40:
			var a := TAU * i / 40.0
			var d := Vector2(cos(a), sin(a))
			pts.append(d * r)
			uvs.append(Vector2(0.5, 0.5) + d * 0.5)
		draw_colored_polygon(pts, Color.WHITE, uvs, tex)

	func _dragon(c: Vector2, r: float) -> void:
		# the gold elite dragon curling round the portrait (a wing over the top, a tail below)
		var gold := Color("#d9a63a")
		var dark := Color("#6a4a14")
		# the wing: feathers fanning over the top of the frame
		for i in 7:
			var a := -PI * 0.95 + PI * 0.75 * i / 6.0
			var p0 := c + Vector2(cos(a), sin(a)) * r * 0.9
			var p1 := c + Vector2(cos(a), sin(a)) * r * (1.38 + 0.12 * (i % 2))
			draw_line(p0, p1, dark, 9.0 * k)
			draw_line(p0, p1, gold, 6.0 * k)
		draw_arc(c, r * 1.12, -PI * 1.0, PI * 0.25, 32, dark, 7.0 * k, true)
		draw_arc(c, r * 1.12, -PI * 1.0, PI * 0.25, 32, gold, 4.0 * k, true)
		draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.6, r * 0.6), c + Vector2(r * 1.5, r * 1.0), c + Vector2(r * 1.1, r * 0.45)]), gold)
		draw_circle(c + Vector2(-r * 0.95, -r * 0.75), r * 0.22, gold)
		draw_circle(c + Vector2(-r * 1.02, -r * 0.8), r * 0.07, Color("#ff3020"))

	func _text(t: String, at: Vector2, w: float, fs: int, c: Color, al: HorizontalAlignment, f: Font) -> void:
		draw_string_outline(f, at + Vector2(0, fs), t, al, w, fs, 3, Color(0, 0, 0, 0.9))
		draw_string(f, at + Vector2(0, fs), t, al, w, fs, c)


class CastBar extends Control:
	var hud: MmoHud
	var unit: MmoUnit
	var hostile := false

	func _init(h: MmoHud, s: Vector2) -> void:
		hud = h
		size = s
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if unit == null or not unit.casting() or not unit.cast.has("ab"):
			return
		var t := float(unit.cast.t)
		var total := maxf(0.01, float(unit.cast.total))
		var f := clampf(t / total, 0.0, 1.0)
		if unit.cast.get("channel", false):
			f = 1.0 - f
		var nm := ""
		if unit.kind == "boss":
			nm = "" if hud and hud.quiet() else (hud.sim.spell_name(str(unit.cast.ab)) if hud else "")
		else:
			nm = str(MmoClasses.ability(unit.cls, str(unit.cast.ab)).get("name", ""))
		draw_rect(Rect2(Vector2(-2, -2), size + Vector2(4, 4)), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.1, 0.04))
		var c := Color("#e0b020") if not hostile else Color("#d08020")
		if unit.cast.get("channel", false):
			c = Color("#20c020")
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * f, size.y)), c)
		draw_rect(Rect2(Vector2(-2, -2), size + Vector2(4, 4)), Color("#b8b0a0"), false, 1.5)
		var fs := int(size.y * 0.72)
		draw_string_outline(hud.serif, Vector2(0, size.y * 0.8), nm, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, 3, Color.BLACK)
		draw_string(hud.serif, Vector2(0, size.y * 0.8), nm, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color.WHITE)
		if not hostile:
			var left := "%.1f" % maxf(0.0, total - t)
			draw_string(hud.sans, Vector2(0, size.y * 0.8), left, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 6, fs - 2, Color.WHITE)


class TimerBar extends Control:
	var hud: MmoHud
	var text := ""
	var left := 0.0
	var total := 1.0
	var col := Color.RED

	func _init(h: MmoHud, t: String, l: float, tot: float, c: Color) -> void:
		hud = h
		text = t
		left = l
		total = tot
		col = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(Vector2(1, 1), Vector2((size.x - 2) * clampf(left / maxf(0.01, total), 0.0, 1.0), size.y - 2)), col)
		draw_string_outline(hud.sans, Vector2(6, 15), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 60, 13, 3, Color.BLACK)
		draw_string(hud.sans, Vector2(6, 15), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 60, 13, Color.WHITE)
		draw_string(hud.sans, Vector2(0, 15), "%.1f" % left, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 6, 13, Color.WHITE)


class Meter extends Control:
	var hud: MmoHud
	var title := ""
	var heads: Array = []
	var rows: Array = []

	func _init(h: MmoHud, t: String, hs: Array) -> void:
		hud = h
		title = t
		heads = hs
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var bg := Color(0.02, 0.03, 0.05, 0.72)
		draw_rect(Rect2(Vector2.ZERO, size), bg)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 20)), Color("#1a3a5a") if heads.size() > 1 else Color(0.08, 0.08, 0.1, 0.95))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.45, 0.5, 0.8), false, 1.0)
		var f: Font = hud.sans
		var tc := Color("#7ad0ff") if heads.size() > 1 else Color.WHITE
		draw_string(f, Vector2(8, 15), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tc)
		var y := 24.0
		if heads.size() > 1:
			var xs := [8.0, size.x * 0.48, size.x * 0.66, size.x * 0.84]
			for i in heads.size():
				draw_string(f, Vector2(xs[i], y + 12), str(heads[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.9, 0.9))
			y += 18.0
			for r: Dictionary in rows:
				if y + 18.0 > size.y:
					break
				draw_rect(Rect2(2, y, (size.x - 4) * float(r.frac), 17), Color(r.col, 0.55))
				var cols: Array = r.cols
				for i in cols.size():
					draw_string_outline(f, Vector2(xs[i], y + 13), str(cols[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 2, Color.BLACK)
					draw_string(f, Vector2(xs[i], y + 13), str(cols[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
				y += 19.0
		else:
			draw_string(f, Vector2(size.x * 0.6, 15), str(heads[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
			for r: Dictionary in rows:
				var c: Color = r.col
				draw_rect(Rect2(2, y, (size.x - 4) * float(r.frac), 20), c.darkened(0.25))
				if r.me:
					draw_rect(Rect2(2, y, size.x - 4, 20), Color(1, 1, 1, 0.8), false, 1.0)
				draw_string_outline(f, Vector2(6, y + 15), str(r.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color.BLACK)
				draw_string(f, Vector2(6, y + 15), str(r.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
				draw_string_outline(f, Vector2(0, y + 15), str(r.val), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 6, 13, 3, Color.BLACK)
				draw_string(f, Vector2(0, y + 15), str(r.val), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 6, 13, Color.WHITE)
				y += 22.0


class Minimap extends Control:
	var hud: MmoHud
	const SPAN := 64.0            # metres across

	func _init(h: MmoHud) -> void:
		hud = h
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.5
		draw_circle(c, r + 4, Color("#3a3428"))
		draw_circle(c, r, Color("#4a5a2c"))
		var sim: MmoSim = hud.sim
		if sim == null:
			return
		var me := sim.unit(hud.me_id)
		var center := me.pos if me else Vector2.ZERO
		var yaw := me.yaw if me else 0.0
		var k := size.x / SPAN
		var to := func(p: Vector2) -> Vector2:
			var d := (p - center)
			d = d.rotated(yaw - PI)                    # rotate so you face up
			return c + Vector2(-d.x, d.y) * k
		# the plaza, the curb, the cloister
		var pc: Vector2 = to.call(Vector2.ZERO)
		_clip_circle(pc, MmoSim.ARENA_R * k, Color("#9a9078"), c, r)
		for rr: float in [MmoSim.ARENA_R + 0.6, MmoArena.COL_R, MmoArena.WALL_R]:
			_ring(pc, rr * k, Color(0.25, 0.22, 0.18, 0.9), c, r)
		for a: Dictionary in sim.areas:
			var ac: Vector2 = to.call(a.pos as Vector2)
			if str(a.kind) == "sector":                  # G46: the tank's wedges, drawn as wedges
				var pts := PackedVector2Array([to.call(a.pos as Vector2)])
				for i in 13:
					var dd := (a.dir as Vector2).rotated(lerpf(-float(a.half), float(a.half), i / 12.0))
					var wp := (a.pos as Vector2) + dd * float(a.r)
					var sp: Vector2 = to.call(wp)
					if (sp - c).length() > r:
						sp = c + (sp - c).normalized() * r
					pts.append(sp)
				draw_colored_polygon(pts, Color(1, 0.35, 0.1, 0.35))
				continue
			if (ac - c).length() < r:
				var col := Color(1, 0.2, 0.1, 0.5) if str(a.kind) != "ring" else Color(1, 0.85, 0.2, 0.6)
				draw_circle(ac, maxf(2.0, float(a.get("r", 2.0)) * k), col)
		for u: MmoUnit in sim.units:
			var p: Vector2 = to.call(u.pos)
			if (p - c).length() > r - 3:
				continue
			if u.kind != "player":
				if not u.alive:
					continue
				var big := 6.0 if u.kind == "boss" else 4.5
				draw_circle(p, big, Color(0, 0, 0))
				draw_circle(p, big - 1.0, Color("#d42a20"))
			elif u.id != hud.me_id:
				draw_circle(p, 4, Color(0, 0, 0))
				draw_circle(p, 3, MmoClasses.color(u.cls) if u.alive else Color(0.4, 0.4, 0.4))
		# you: the arrow, always up
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(6, 7), c + Vector2(0, 3), c + Vector2(-6, 7)]), Color.WHITE)
		draw_arc(c, r + 2, 0, TAU, 64, Color("#b8a888"), 4.0, true)
		draw_string(hud.serif, c + Vector2(-5, -r + 14), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.85, 0.6))

	func _clip_circle(at: Vector2, rr: float, col: Color, c: Vector2, r: float) -> void:
		var a_pts := PackedVector2Array()
		var b_pts := PackedVector2Array()
		for i in 48:
			var a := TAU * i / 48.0
			a_pts.append(at + Vector2(cos(a), sin(a)) * rr)
			b_pts.append(c + Vector2(cos(a), sin(a)) * (r - 1.0))
		for poly: PackedVector2Array in Geometry2D.intersect_polygons(a_pts, b_pts):
			if poly.size() >= 3:
				draw_colored_polygon(poly, col)

	func _ring(at: Vector2, rr: float, col: Color, c: Vector2, r: float) -> void:
		var prev := Vector2.INF
		for i in 65:
			var a := TAU * i / 64.0
			var p := at + Vector2(cos(a), sin(a)) * rr
			var inside := (p - c).length() < r
			if inside and prev != Vector2.INF:
				draw_line(prev, p, col, 2.0)
			prev = p if inside else Vector2.INF


class XpBar extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2(-1, -1), size + Vector2(2, 2)), Color(0, 0, 0))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.05, 0.15))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * 0.41, size.y)), Color("#5a1f8a"))
		draw_rect(Rect2(Vector2(size.x * 0.41, 0), Vector2(size.x * 0.12, size.y)), Color("#1f4a9a"))
		for i in 20:
			var x := size.x * i / 20.0
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0, 0, 0, 0.6), 1.0)


class MainBar extends Control:
	const X0 := 110.0               ## the slab's left edge (the gryphons sit outside it)
	var hud: MmoHud

	func _init(h: MmoHud) -> void:
		hud = h
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		# the stone slab under the buttons
		var slab := Rect2(X0 - 6, 56, size.x - X0 * 2 + 12, size.y - 56)      # one bar of eight (G39)
		draw_rect(slab, Color(0.07, 0.065, 0.06, 0.95))
		draw_rect(Rect2(slab.position, Vector2(slab.size.x, 3)), MmoHud.STONE_HI)
		draw_rect(slab, MmoHud.STONE, false, 2.0)
		# empty button wells
		for i in MmoClasses.SLOTS:
			draw_rect(Rect2(X0 + i * 46, 60, 46, 46), Color(0, 0, 0, 0.6))
		# G52: the consumables bar above the spells, on its own darker stone strip
		var top := Rect2(X0 - 6, 6, 8 * 46 + 12, 50)
		draw_rect(top, Color(0.06, 0.055, 0.05, 0.9))
		draw_rect(Rect2(top.position, Vector2(top.size.x, 2)), MmoHud.STONE_HI)
		draw_rect(top, MmoHud.STONE, false, 2.0)
		for i in MmoItems.ITEMS.size():
			draw_rect(Rect2(X0 + i * 46, 8, 46, 46), Color(0, 0, 0, 0.6))
		# micro menu and bags on the right of the lower row
		var mx := X0 + 8 * 46 + 20
		var micro := ["Character", "Spellbook", "Talents", "Quests", "Social", "Map", "Menu", "Help"]
		var mcols := ["#6a8ab0", "#8a5ab0", "#b08a3a", "#e0c040", "#40a0d0", "#a08060", "#808080", "#c03030"]
		for i in micro.size():
			var r := Rect2(mx + i * 27, 64, 24, 38)
			draw_rect(r, Color(mcols[i]).darkened(0.5))
			draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(20, 22)), Color(mcols[i]))
			draw_rect(r, Color(0.7, 0.62, 0.4), false, 1.0)
		var bx := mx + micro.size() * 27 + 6
		for i in 5:
			var r := Rect2(bx + i * 34, 66, 31, 31)
			draw_rect(r, Color("#5a3a1e") if i > 0 else Color("#7a5a2e"))
			draw_rect(Rect2(r.position + Vector2(6, 8), Vector2(24, 22)), Color("#8a6a3a").darkened(0.1 * i))
			draw_rect(r, Color(0.75, 0.65, 0.4), false, 1.5)
		# the right side of the top row: a stance strip and the clock-face of the bar
		for i in 4:
			var r := Rect2(mx + i * 46, 10, 40, 40)
			draw_rect(r, Color(0, 0, 0, 0.55))
			draw_rect(r, Color(0.35, 0.33, 0.3), false, 1.0)
		# the bar's page arrows
		var f: Font = hud.serif
		draw_string(f, Vector2(mx + 192, 26), "▲", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.8, 0.5))
		draw_string(f, Vector2(mx + 194, 40), "1", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.85, 0.5))
		draw_string(f, Vector2(mx + 192, 52), "▼", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.8, 0.5))
		# gryphons at both ends
		_gryphon(Vector2(X0 + 14, size.y), 1.0)
		_gryphon(Vector2(size.x - X0 - 14, size.y), -1.0)

	func _gryphon(foot: Vector2, s: float) -> void:
		var gold := Color("#8e8a80")
		var dark := Color("#4a4740")
		var P := func(x: float, y: float) -> Vector2: return foot + Vector2(-x * s * 1.25, -y * 1.2)
		# body, wing, head, beak, paw: a seated gryphon facing the bar
		var body := PackedVector2Array([P.call(0, 0), P.call(80, 0), P.call(86, 30), P.call(70, 58), P.call(40, 66), P.call(8, 52)])
		draw_colored_polygon(body, dark)
		var wing := PackedVector2Array([P.call(70, 40), P.call(96, 100), P.call(60, 112), P.call(30, 104), P.call(46, 80), P.call(20, 74)])
		draw_colored_polygon(wing, gold)
		for k in 4:
			draw_line(P.call(36 + k * 12, 80 + k * 4), P.call(54 + k * 10, 108 - k * 2), dark, 2.0)
		var head := PackedVector2Array([P.call(6, 54), P.call(20, 92), P.call(6, 112), P.call(-14, 104), P.call(-20, 86), P.call(-6, 64)])
		draw_colored_polygon(head, gold)
		draw_colored_polygon(PackedVector2Array([P.call(-14, 104), P.call(-34, 92), P.call(-18, 88)]), Color("#c8b068"))
		draw_circle(P.call(-6, 96), 3.0, Color(0.1, 0.05, 0.0))
		draw_colored_polygon(PackedVector2Array([P.call(-6, 0), P.call(-24, 0), P.call(-22, 18), P.call(0, 24)]), gold)
		draw_polyline(PackedVector2Array([P.call(0, 0), P.call(80, 0), P.call(86, 30), P.call(70, 58), P.call(40, 66), P.call(8, 52), P.call(0, 0)]), Color(0, 0, 0, 0.6), 1.5)


class Tooltip extends PanelContainer:
	var hud: MmoHud
	var _l: RichTextLabel

	func _init(h: MmoHud) -> void:
		hud = h
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.03, 0.08, 0.94)
		sb.border_color = Color(0.75, 0.75, 0.8)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(8)
		add_theme_stylebox_override("panel", sb)
		_l = RichTextLabel.new()
		_l.bbcode_enabled = true
		_l.fit_content = true
		_l.custom_minimum_size = Vector2(300, 0)
		_l.scroll_active = false
		_l.add_theme_font_override("normal_font", h.sans)
		_l.add_theme_font_size_override("normal_font_size", 13)
		add_child(_l)

	func show_for(ab: Dictionary, me: MmoUnit) -> void:
		var t := "[font_size=16][color=#ffffff]%s[/color][/font_size]\n" % str(ab.name)
		if ab.get("item", false):
			t += "[color=#1eff00]Consumable[/color]    [color=#a0a0a0]off the global cooldown[/color]\n"
		var bits: Array = []
		if float(ab.get("cost", 0.0)) > 0.0:
			bits.append("%d %s" % [int(ab.cost), me.res_kind.capitalize()])
		if float(ab.get("range", 0.0)) > 0.0:
			bits.append("%d m range" % int(ab.range))
		if not bits.is_empty():
			t += "[color=#ffffff]%s[/color]\n" % "    ".join(bits)
		var ct := "Instant"
		if float(ab.get("cast", 0.0)) > 0.0:
			ct = "%.1f sec cast" % float(ab.cast)
		elif float(ab.get("channel", 0.0)) > 0.0:
			ct = "Channeled"
		t += "[color=#ffffff]%s[/color]" % ct
		if float(ab.get("cd", 0.0)) > 0.0:
			var mins := float(ab.cd) / 60.0
			var cd_s := ("%d min" % int(mins)) if is_equal_approx(mins, roundf(mins)) else ("%.1f min" % mins)
			t += "[color=#ffffff]    %s cooldown[/color]" % (("%d sec" % int(ab.cd)) if float(ab.cd) < 60.0 else cd_s)
		t += "\n[color=#ffd100]%s[/color]" % str(ab.get("desc", ""))
		_l.text = t
		reset_size()
