class_name MobaHud
extends CanvasLayer
## The MOBA HUD, after League's (the author's reference, design/ref/
## league_aram_hud.jpg): the champion panel bottom centre (portrait, passive,
## QWER with cooldown sweeps, the two summoner spells, HP), the stats panel
## to its left, the minimap bottom right, the K/D/A, CS and clock strip top
## right, the score plate top centre and the kill feed under the strip.
## Overhead bars (MobaHud.Bar) are drawn by the view on `bars`, under the rest.
## Design space 1600x900 (the project stretches canvas items).

const NAVY := Color("#0a1320")
const NAVY2 := Color("#13202f")
const TRIM := Color("#7a6232")
const GOLD := Color("#c8aa6e")
const TEXT := Color("#e8e2d0")
const DIM := Color("#8a8f99")
const HP_SELF := Color("#3aa83a")
const HP_ALLY := Color("#2e7fd8")
const HP_FOE := Color("#c83a32")
const PANEL_W := 428.0
const PANEL_X := -PANEL_W / 2.0 + 50.0      # the champion panel's left edge from the screen centre
## The summoner spells' colours (G54: smite cold teal, flash bright yellow, never alike).
const SUMMONER_COL := { "flash": Color("#ffe14a"), "ignite": Color("#ff7a2e"), "smite": Color("#36d1c4") }
const SUMMONER_TIP := {
	"flash": ["Flash", "Blink a short way toward the cursor, over anything in between."],
	"ignite": ["Ignite", "Set an enemy champion near the cursor burning: 120 true damage over 5 s."],
	"smite": ["Smite", "600 true damage to the Giant. Only you carry it: land the last hit and your team takes the fight."],
}

## What each spell's icon shows (a drawn glyph; MobaHud.Icon).
const GLYPHS := {
	"merr": { "passive": "flame", "q": "spit", "w": "pyre", "e": "spread", "r": "bounce" },
	"temu": { "passive": "eye", "q": "toxic", "w": "chevrons", "e": "drop", "r": "mine" },
	"braves": { "passive": "shell", "q": "cone", "w": "smoke", "e": "dash", "r": "blast" },
}

var view: MobaView
var root: Control
var bars: Control                   # overhead bars live here (the view fills it)
var _icons := {}                    # slot -> Icon
var _hp_fill: ColorRect
var _hp_chip: ColorRect
var _hp_l: Label
var _hp_w := 0.0
var _chip := 1.0
var _stats := {}                    # key -> Label
var _strip: Label
var _score_l: Label
var _sub_l: Label
var _center_l: Label
var _feed: VBoxContainer
var _boss_fill: ColorRect
var _boss_l: Label
var _portrait: TextureRect
var _dead_veil: ColorRect
var _map: Minimap
var _tip: Tip                       # the spell tooltip (G54: hover an icon, like Raid night's)
var cs := 0                         # minions the local champion finished


func setup(v: MobaView) -> void:
	view = v


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = BWStyle.theme()
	add_child(root)
	_dead_veil = ColorRect.new()
	_dead_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dead_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dead_veil.color = Color(0.1, 0.1, 0.12, 0.45)
	_dead_veil.visible = false
	root.add_child(_dead_veil)
	var vig := ColorRect.new()               # League's darkened screen edges
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := Shader.new()
	vs.code = """shader_type canvas_item;
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.0, 0.8);
	d.y *= 1.15;                                // heavier top and bottom
	COLOR = vec4(0.0, 0.02, 0.03, smoothstep(0.28, 0.72, length(d)) * 0.75);
}"""
	var vm := ShaderMaterial.new()
	vm.shader = vs
	vig.material = vm
	root.add_child(vig)
	root.move_child(vig, 0)
	bars = Control.new()
	bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bars)
	_build_top()
	_center_l = _label(root, "", 40)
	_center_l.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	_center_l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center_l.grow_vertical = Control.GROW_DIRECTION_BOTH
	_center_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_l.add_theme_constant_override("outline_size", 10)
	_map = Minimap.new()
	_map.view = view
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_map)
	pin(_map, Control.PRESET_BOTTOM_RIGHT, Vector2(-238, -238), Vector2(230, 230))
	var me := view.sim.unit(view.local_id)
	if me:
		_build_panel(me)
		_build_stats(me)
	_tip = Tip.new()
	_tip.visible = false
	root.add_child(_tip)


# ------------------------------------------------------------------ build

func _label(parent: Control, text: String, size: int, col: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", maxi(3, size / 4))
	parent.add_child(l)
	return l


static func plate_style(alpha: float = 0.94) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(NAVY, alpha)
	sb.border_color = TRIM
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	return sb


## Pin `c` to an anchor preset, `pos` measured from that anchor point.
static func pin(c: Control, preset: int, pos: Vector2, sz: Vector2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + sz.x
	c.offset_bottom = pos.y + sz.y


func _plate(parent: Control, rect: Rect2, alpha: float = 0.94) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", plate_style(alpha))
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func _build_top() -> void:
	# score plate, top centre
	var sc := _plate(root, Rect2(0, 0, 360, 58))
	pin(sc, Control.PRESET_CENTER_TOP, Vector2(-180, 6), Vector2(360, 58))
	_score_l = _label(sc, "", 24)
	_score_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_l.size = Vector2(360, 30)
	_score_l.position = Vector2(0, 2)
	_sub_l = _label(sc, "", 13, DIM)
	_sub_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_l.size = Vector2(360, 18)
	_sub_l.position = Vector2(0, 34)
	if view.sim.mode == "pit":
		var bb := _plate(root, Rect2(0, 0, 360, 22))
		pin(bb, Control.PRESET_CENTER_TOP, Vector2(-180, 62), Vector2(360, 22))
		var back := ColorRect.new()
		back.color = Color(0, 0, 0, 0.9)
		back.position = Vector2(4, 4)
		back.size = Vector2(352, 14)
		bb.add_child(back)
		_boss_fill = ColorRect.new()
		_boss_fill.color = MobaLook.BOSS
		_boss_fill.position = Vector2(4, 4)
		_boss_fill.size = Vector2(352, 14)
		bb.add_child(_boss_fill)
		var mark := ColorRect.new()          # one smite kills it left of this line
		mark.color = Color(1, 0.85, 0.3)
		mark.size = Vector2(3, 22)
		mark.position = Vector2(4 + 352 * MobaSim.SMITE_DMG / MobaSim.BOSS_HP, 0)
		bb.add_child(mark)
		_boss_l = _label(bb, "", 12)
		_boss_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_boss_l.size = Vector2(360, 22)
		_boss_l.position.y = 0
	# K/D/A, CS, clock: top right
	var st := _plate(root, Rect2(0, 0, 220, 30), 0.85)
	pin(st, Control.PRESET_TOP_RIGHT, Vector2(-226, 6), Vector2(220, 30))
	_strip = _label(st, "", 15)
	_strip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_strip.size = Vector2(220, 28)
	_strip.position = Vector2(0, 1)
	_feed = VBoxContainer.new()
	pin(_feed, Control.PRESET_TOP_RIGHT, Vector2(-420, 46), Vector2(414, 0))
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)


## The champion panel: portrait, passive, QWER, D/F, HP.
func _build_panel(me: MobaUnit) -> void:
	var W := PANEL_W
	var H := 118.0
	var pan := _plate(root, Rect2(0, 0, W, H))
	var ps := plate_style()
	ps.bg_color = NAVY
	ps.set_border_width_all(1)
	ps.border_width_top = 3
	pan.add_theme_stylebox_override("panel", ps)
	pin(pan, Control.PRESET_CENTER_BOTTOM, Vector2(PANEL_X, -H), Vector2(W, H))
	pan.draw.connect(func():                  # a lighter upper half and League's gold top rule
		pan.draw_rect(Rect2(1, 3, W - 2, H * 0.5), Color(NAVY2, 0.6))
		pan.draw_line(Vector2(0, 1), Vector2(W, 1), GOLD, 2.0))
	# portrait, a circle at the left, overlapping the edge like League's
	var ring := Control.new()
	ring.position = Vector2(-58, 10)
	ring.size = Vector2(104, 104)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pan.add_child(ring)
	ring.draw.connect(func():
		ring.draw_circle(Vector2(52, 52), 52, NAVY)
		ring.draw_circle(Vector2(52, 52), 48, Color(str(MobaChamps.CHAMPS[me.champ].tint)).darkened(0.55))
		ring.draw_arc(Vector2(52, 52), 50, 0, TAU, 48, GOLD, 3.0, true))
	_portrait = TextureRect.new()
	_portrait.position = Vector2(4, 4)
	_portrait.size = Vector2(96, 96)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = distance(UV, vec2(0.5));
	COLOR = vec4(c.rgb, c.a * (1.0 - smoothstep(0.47, 0.5, d)));
}"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_portrait.material = sm
	ring.add_child(_portrait)
	var bu := MobaLook.champ_unit(me.champ, me.team)
	BWPortraits.ensure(self)
	_portrait.texture = BWPortraits.portrait(bu)
	if _portrait.texture == null and BWPortraits.instance():
		var key := BWPortraits.key_for(bu)
		BWPortraits.instance().portrait_ready.connect(func(k: String):
			if k == key and is_instance_valid(_portrait):
				_portrait.texture = BWPortraits.cached(k))
	var lvl := _label(ring, "%d" % me.kills, 15, GOLD)
	lvl.name = "lvl"
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl.position = Vector2(36, 86)
	lvl.size = Vector2(32, 22)
	ring.draw.connect(func():
		ring.draw_rect(Rect2(36, 88, 32, 20), NAVY)
		ring.draw_rect(Rect2(36, 88, 32, 20), GOLD, false, 1.5))
	# spells
	var c: Dictionary = MobaChamps.CHAMPS[me.champ]
	var spell2 := "smite" if view.sim.mode == "pit" else "ignite"
	var x := 54.0
	var tint := Color(str(c.tint))
	var pas := Icon.new()
	pas.setup(str(GLYPHS[me.champ].passive), tint, "", 34.0)
	pas.position = Vector2(x, 20)
	pan.add_child(pas)
	_icons["passive"] = pas
	_hoverable(pas, me, "passive")
	x += 40.0
	for slot in ["q", "w", "e", "r"]:
		var ic := Icon.new()
		ic.setup(str(GLYPHS[me.champ][slot]), tint, view.key_label(slot), 52.0)
		ic.position = Vector2(x, 10)
		pan.add_child(ic)
		_icons[slot] = ic
		_hoverable(ic, me, slot)
		x += 57.0
	x += 8.0
	for slot in ["flash", spell2]:
		var gl: String = { "flash": "flash", "ignite": "ignite", "smite": "smite" }[slot]
		var col: Color = SUMMONER_COL[slot]
		var ic := Icon.new()
		ic.setup(gl, col, view.key_label(slot), 40.0)
		ic.position = Vector2(x, 8)
		pan.add_child(ic)
		_icons[slot] = ic
		_hoverable(ic, me, slot)
		var nl := _label(pan, slot.to_upper(), 10, col.lightened(0.2))     # G54: flash and smite told apart by name too
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.position = Vector2(x - 4, 50)
		nl.size = Vector2(48, 14)
		x += 45.0
	# HP, nearly full width right under the icons
	_hp_w = W - 54.0 - 10.0
	var hb := ColorRect.new()
	hb.color = Color(0.02, 0.03, 0.05)
	hb.position = Vector2(54, 70)
	hb.size = Vector2(_hp_w, 20)
	pan.add_child(hb)
	_hp_chip = ColorRect.new()
	_hp_chip.color = Color(0.95, 0.9, 0.8)
	_hp_chip.position = Vector2(1, 1)
	_hp_chip.size = Vector2(_hp_w - 2, 18)
	hb.add_child(_hp_chip)
	_hp_fill = ColorRect.new()
	_hp_fill.color = HP_SELF
	_hp_fill.position = Vector2(1, 1)
	_hp_fill.size = Vector2(_hp_w - 2, 18)
	hb.add_child(_hp_fill)
	var shine := ColorRect.new()         # the top highlight of a League bar
	shine.color = Color(1, 1, 1, 0.12)
	shine.position = Vector2(1, 1)
	shine.size = Vector2(_hp_w - 2, 6)
	hb.add_child(shine)
	_hp_l = _label(hb, "", 14)
	_hp_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_l.size = Vector2(_hp_w, 20)
	# the slot where League keeps mana: here, what is on you (burns, hidden, fast)
	var slot_bg := ColorRect.new()
	slot_bg.color = Color(0.03, 0.05, 0.08)
	slot_bg.position = Vector2(54, 93)
	slot_bg.size = Vector2(_hp_w, 16)
	pan.add_child(slot_bg)
	var sl := _label(pan, "", 12, Color("#9fb4c8"))
	sl.name = "status"
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.position = Vector2(54, 92)
	sl.size = Vector2(_hp_w, 18)


## The stats panel to the left of the champion panel (League's bottom-left box).
func _build_stats(me: MobaUnit) -> void:
	var p := _plate(root, Rect2(0, 0, 190, 104), 0.92)
	pin(p, Control.PRESET_CENTER_BOTTOM, Vector2(PANEL_X - 58.0 - 190.0 + 8.0, -104.0), Vector2(190, 104))
	var rows := [["ad", "AD"], ["as", "AS"], ["range", "RNG"], ["ms", "MS"], ["kd", "K/D"], ["dmg", "DMG"]]
	for i in rows.size():
		var col := i % 2
		var row := i / 2
		var k := _label(p, str(rows[i][1]), 12, DIM)
		k.position = Vector2(10 + col * 92, 9 + row * 30)
		var v := _label(p, "", 15, TEXT)
		v.position = Vector2(42 + col * 92, 6 + row * 30)
		_stats[rows[i][0]] = v
	_stats.ad.text = "%d" % int(me.ad * me.power)          # the pit's players hit 2x (G54)
	_stats.range.text = "%d" % int(me.range * 100.0)


## League's kill notice: killer, a sword, victim, each in their team colour.
func feed_kill(killer: String, kcol: Color, victim: String, vcol: Color) -> void:
	var pp := PanelContainer.new()
	var sb := plate_style(0.86)
	sb.set_content_margin_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	pp.add_theme_stylebox_override("panel", sb)
	pp.size_flags_horizontal = Control.SIZE_SHRINK_END
	pp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	pp.add_child(row)
	if killer != "":
		_label(row, killer, 16, kcol.lightened(0.4))
	_label(row, "⚔", 16, GOLD)
	_label(row, victim, 16, vcol.lightened(0.4))
	_feed.add_child(pp)
	TourneyUI.after(self, 5.0, func(): if is_instance_valid(pp): pp.queue_free())


func feed_line(text: String, col: Color) -> void:
	var pp := PanelContainer.new()
	var sb := plate_style(0.82)
	sb.set_content_margin_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.border_color = col.darkened(0.2)
	pp.add_theme_stylebox_override("panel", sb)
	pp.size_flags_horizontal = Control.SIZE_SHRINK_END
	pp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label(pp, text, 16, col.lightened(0.35))
	_feed.add_child(pp)
	TourneyUI.after(self, 5.0, func(): if is_instance_valid(pp): pp.queue_free())


func center(text: String, col: Color = TEXT) -> void:
	_center_l.text = text
	_center_l.add_theme_color_override("font_color", col)


# ------------------------------------------------------------------ update

func update(me: MobaUnit, delta: float) -> void:
	var sim := view.sim
	var mine := me.team if me else "blue"          # your side reads first
	var theirs := "red" if mine == "blue" else "blue"
	var nm := func(t: String) -> String: return str(view.names.get(t, t.capitalize()))
	if sim.mode == "practice":
		_score_l.text = "Practice"
		_sub_l.text = "hit the dummy"
	else:
		_score_l.text = "%s   %d  ⚔  %d   %s" % [nm.call(mine), sim.score[mine], sim.score[theirs], nm.call(theirs)]
		_score_l.add_theme_color_override("font_color", TEXT)
		_sub_l.text = "first to %d kills" % MobaSim.KILLS_TO_WIN if sim.mode == "duel" else "last hit wins  ·  %s go in  ·  %s hold" % [
			TourneyUI.key_name(int(view.binds.get("ping_go", KEY_V))), TourneyUI.key_name(int(view.binds.get("ping_hold", KEY_C)))]
	var boss := sim.boss()
	if boss and _boss_fill:
		_boss_fill.size.x = 352.0 * clampf(boss.hp / boss.max_hp, 0.0, 1.0)
		_boss_l.text = "The Giant   %d" % maxi(0, int(boss.hp))
	var secs := int(sim.time)
	var deaths := 0
	if me:
		deaths = int(me.get_meta("deaths", 0))
	_strip.text = "%d / %d    CS %d    %02d:%02d" % [me.kills if me else 0, deaths, cs, secs / 60, secs % 60]
	_map.queue_redraw()
	if me == null:
		return
	_dead_veil.visible = not me.alive
	if not view.is_over():
		_center_l.text = "" if me.alive else "Respawn in %d" % ceili(me.respawn_t)
	for slot in _icons:
		var ic: Icon = _icons[slot]
		if slot == "passive":
			ic.active = me.champ == "temu" and me.stealth or me.champ == "merr"
			ic.queue_redraw()
			continue
		var cd := float(me.cd.get(slot, 0.0))
		var full := view.cd_full(me, slot)
		ic.cd = cd
		ic.cd_max = full
		ic.passive = me.champ == "temu" and slot == "e"
		ic.queue_redraw()
	var frac := clampf(me.hp / me.max_hp, 0.0, 1.0)
	_chip = minf(1.0, maxf(frac, _chip - delta * 0.6)) if frac < _chip else frac
	_hp_fill.size.x = (_hp_w - 2.0) * frac
	_hp_chip.size.x = (_hp_w - 2.0) * _chip
	_hp_l.text = "%d / %d" % [maxi(0, int(me.hp)), int(me.max_hp)]
	var lvl := _portrait.get_parent().get_node("lvl") as Label
	lvl.text = "%d" % me.kills
	var status := PackedStringArray()
	for d in me.dots:
		status.append(str(d.kind).capitalize())
	if me.stealth:
		status.append("Hidden")
	if me.blind_t > 0.0:
		status.append("Blinded")
	for b in me.buffs:
		if b.kind == "ms":
			status.append("Fast")
	(_hp_fill.get_parent().get_parent().get_node("status") as Label).text = "  ·  ".join(status)
	if _stats.has("as"):
		_stats["as"].text = "%.2f" % (1.0 / me.period)
		_stats.ms.text = "%d" % int(me.ms_now() * 100.0)
		_stats.kd.text = "%d / %d" % [me.kills, deaths]
		_stats.dmg.text = "%d" % int(me.dmg_done)


## Hovering a spell icon shows its tooltip (G54, after Raid night's).
func _hoverable(ic: Icon, me: MobaUnit, slot: String) -> void:
	ic.mouse_filter = Control.MOUSE_FILTER_PASS
	ic.mouse_entered.connect(func() -> void:
		_tip.show_for(view, me, slot)
		var r := ic.get_global_rect()
		var vs := root.get_viewport_rect().size
		_tip.global_position = Vector2(clampf(r.position.x - 120.0, 4.0, vs.x - _tip.size.x - 4.0), r.position.y - _tip.size.y - 10.0)
		_tip.visible = true)
	ic.mouse_exited.connect(func() -> void: _tip.visible = false)


## The text of a slot's tooltip: name, key, range in League units, cooldown, cast time, what it does.
static func tip_text(v: MobaView, me: MobaUnit, slot: String) -> String:
	var c: Dictionary = MobaChamps.CHAMPS[me.champ]
	var nm := ""
	var desc := ""
	if SUMMONER_TIP.has(slot):
		nm = str(SUMMONER_TIP[slot][0])
		desc = str(SUMMONER_TIP[slot][1])
	else:
		nm = str(c.spells[slot][0])
		desc = str(c.spells[slot][1])
	var bits: Array = []
	if slot == "passive":
		bits.append("Passive")
	else:
		bits.append("[%s]" % v.key_label(slot))
		var rg := MobaChamps.spell_range(me.champ, slot)
		if rg > 0.0:
			bits.append("%d range" % int(round(rg * 100.0)))
		var sp := MobaChamps.shape(me.champ, slot)
		if str(sp.get("shape", "")) == "none":
			bits.append("No active")
		else:
			var cdv := v.cd_full(me, slot)
			if cdv > 0.0:
				bits.append("%s cooldown" % ("%d s" % int(cdv) if cdv < 60.0 else "%d min" % int(cdv / 60.0)))
			bits.append("%.1f s cast" % MobaChamps.CAST_TIME if slot in ["q", "w", "e", "r"] else "Instant")
	var t := "[font_size=17][color=#ffffff]%s[/color][/font_size]\n" % nm
	t += "[color=#c8d0dc]%s[/color]\n" % "    ".join(bits)
	t += "[color=#ffd100]%s[/color]" % desc
	return t


## The tooltip box: Raid night's (MmoHud.Tooltip) look, in the MOBA's navy.
class Tip:
	extends PanelContainer
	var _l: RichTextLabel

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.03, 0.08, 0.94)
		sb.border_color = MobaHud.GOLD
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(8)
		add_theme_stylebox_override("panel", sb)
		_l = RichTextLabel.new()
		_l.bbcode_enabled = true
		_l.fit_content = true
		_l.scroll_active = false
		_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_l.custom_minimum_size = Vector2(320, 0)
		_l.add_theme_font_size_override("normal_font_size", 14)
		add_child(_l)

	func show_for(v: MobaView, me: MobaUnit, slot: String) -> void:
		_l.text = MobaHud.tip_text(v, me, slot)
		reset_size()


# ------------------------------------------------------------------ widgets

## A spell square: a gradient in the spell's colour, a drawn glyph, the key
## in the corner, and League's clockwise dark sweep + seconds on cooldown.
class Icon:
	extends Control
	var glyph := ""
	var col := Color.WHITE
	var key := ""
	var cd := 0.0
	var cd_max := 0.0
	var passive := false
	var active := false
	var side := 60.0

	func setup(g: String, c: Color, k: String, s: float) -> void:
		glyph = g
		col = c
		key = k
		side = s
		size = Vector2(s, s)
		custom_minimum_size = size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := side
		draw_rect(Rect2(0, 0, s, s), MobaHud.TRIM)
		var a := col.darkened(0.7)
		var b := col.darkened(0.25)
		draw_polygon(PackedVector2Array([Vector2(2, 2), Vector2(s - 2, 2), Vector2(s - 2, s - 2), Vector2(2, s - 2)]),
			PackedColorArray([b, b.darkened(0.2), a, a.lightened(0.05)]))
		MobaHud.draw_glyph(self, glyph, Rect2(s * 0.14, s * 0.14, s * 0.72, s * 0.72), col.lightened(0.55))
		if cd > 0.0 and cd_max > 0.0:
			var f := clampf(cd / cd_max, 0.0, 1.0)
			var c := Vector2(s, s) / 2.0
			var pts := PackedVector2Array([c])
			var n := 32
			for i in n + 1:
				var t := -PI / 2.0 + TAU * (1.0 - f) + TAU * f * i / n
				var p := c + Vector2(cos(t), sin(t)) * s
				pts.append(Vector2(clampf(p.x, 2, s - 2), clampf(p.y, 2, s - 2)))
			draw_colored_polygon(pts, Color(0, 0, 0, 0.68))
			var fnt := get_theme_default_font()
			var txt := "%d" % ceili(cd)
			var fs := int(s * 0.42)
			var w := fnt.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(fnt, Vector2((s - w) / 2.0, s * 0.64), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color.BLACK)
			draw_string(fnt, Vector2((s - w) / 2.0, s * 0.64), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		if passive:
			draw_rect(Rect2(2, 2, s - 4, s - 4), Color(0, 0, 0, 0.35))
		if active:
			draw_rect(Rect2(1, 1, s - 2, s - 2), col.lightened(0.4), false, 2.0)
		if key != "":
			var fnt := get_theme_default_font()
			var fs := 13 if s > 50 else 11
			var w := fnt.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_rect(Rect2(s - w - 7, s - fs - 5, w + 6, fs + 4), Color(0.02, 0.04, 0.07, 0.9))
			draw_string(fnt, Vector2(s - w - 4, s - 4), key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, MobaHud.GOLD)


## A glyph for a spell icon, drawn into rect `r` on `ci` (no icon art yet).
static func draw_glyph(ci: CanvasItem, g: String, r: Rect2, c: Color) -> void:
	var P := func(x: float, y: float) -> Vector2: return r.position + Vector2(x, y) * r.size
	var w := maxf(2.0, r.size.x * 0.07)
	var ink := Color(0, 0, 0, 0.55)
	match g:
		"flame", "ignite":
			var pts := PackedVector2Array([P.call(0.5, 0.0), P.call(0.68, 0.3), P.call(0.86, 0.55), P.call(0.8, 0.85), P.call(0.5, 1.0),
				P.call(0.2, 0.85), P.call(0.14, 0.55), P.call(0.32, 0.38), P.call(0.42, 0.55)])
			ci.draw_colored_polygon(pts, c)
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.45), P.call(0.66, 0.72), P.call(0.5, 0.92), P.call(0.34, 0.72)]), c.lightened(0.6))
		"spit":
			ci.draw_line(P.call(0.08, 0.92), P.call(0.55, 0.45), Color(c, 0.6), w * 1.6)
			ci.draw_circle(P.call(0.66, 0.34), r.size.x * 0.22, c)
			ci.draw_circle(P.call(0.6, 0.28), r.size.x * 0.07, c.lightened(0.6))
		"pyre":
			ci.draw_arc(P.call(0.5, 0.66), r.size.x * 0.42, 0, TAU, 32, c, w)
			draw_glyph(ci, "flame", Rect2(P.call(0.28, 0.12), r.size * 0.44), c)
		"spread":
			for i in 8:
				var a := i * TAU / 8.0
				ci.draw_line(P.call(0.5, 0.5) + Vector2(cos(a), sin(a)) * r.size.x * 0.18, P.call(0.5, 0.5) + Vector2(cos(a), sin(a)) * r.size.x * 0.48, c, w)
			ci.draw_circle(P.call(0.5, 0.5), r.size.x * 0.16, c.lightened(0.4))
		"bounce":
			var pts := PackedVector2Array([P.call(0.05, 0.85), P.call(0.32, 0.25), P.call(0.6, 0.75), P.call(0.9, 0.15)])
			ci.draw_polyline(pts, Color(c, 0.7), w)
			for p in pts.slice(1):
				ci.draw_circle(p, r.size.x * 0.11, c)
		"eye":
			var pts := PackedVector2Array()
			for i in 25:
				var t := TAU * i / 24.0
				pts.append(P.call(0.5 + cos(t) * 0.48, 0.5 + sin(t) * 0.26))
			ci.draw_colored_polygon(pts, c)
			ci.draw_circle(P.call(0.5, 0.5), r.size.x * 0.17, ink)
			ci.draw_circle(P.call(0.5, 0.5), r.size.x * 0.08, c.lightened(0.6))
		"toxic":
			ci.draw_line(P.call(0.1, 0.9), P.call(0.8, 0.2), c, w * 1.2)
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.92, 0.08), P.call(0.62, 0.18), P.call(0.82, 0.38)]), c)
			draw_glyph(ci, "drop", Rect2(P.call(0.05, 0.08), r.size * 0.4), c.lightened(0.3))
		"drop":
			var pts := PackedVector2Array([P.call(0.5, 0.0)])
			for i in 17:
				var t := PI * 1.15 * i / 16.0 - PI * 0.075
				pts.append(P.call(0.5 + cos(t) * 0.34, 0.64 + sin(t) * 0.34))
			ci.draw_colored_polygon(pts, c)
		"chevrons", "dash":
			for k in 2:
				var o := 0.3 * k
				ci.draw_polyline(PackedVector2Array([P.call(0.12 + o, 0.15), P.call(0.42 + o, 0.5), P.call(0.12 + o, 0.85)]), c, w * 1.4)
			if g == "dash":
				for k in 3:
					ci.draw_line(P.call(0.0, 0.3 + k * 0.2), P.call(0.12, 0.3 + k * 0.2), Color(c, 0.6), w * 0.7)
		"mine":
			for i in 8:
				var a := i * TAU / 8.0
				ci.draw_line(P.call(0.5, 0.55), P.call(0.5, 0.55) + Vector2(cos(a), sin(a)) * r.size.x * 0.42, c, w)
			ci.draw_circle(P.call(0.5, 0.55), r.size.x * 0.26, c)
			ci.draw_circle(P.call(0.5, 0.55), r.size.x * 0.09, Color("#ff4f4f"))
		"shell":
			ci.draw_rect(Rect2(P.call(0.3, 0.35), r.size * Vector2(0.4, 0.6)), c)
			ci.draw_circle(P.call(0.5, 0.35), r.size.x * 0.2, c.lightened(0.2))
			ci.draw_rect(Rect2(P.call(0.26, 0.82), r.size * Vector2(0.48, 0.12)), c.darkened(0.3))
		"cone":
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.05, 0.5), P.call(0.95, 0.1), P.call(0.95, 0.9)]), Color(c, 0.45))
			for p in [P.call(0.62, 0.3), P.call(0.8, 0.52), P.call(0.6, 0.72)]:
				ci.draw_circle(p, r.size.x * 0.08, c.lightened(0.4))
		"smoke":
			for p in [Vector3(0.32, 0.6, 0.24), Vector3(0.6, 0.52, 0.28), Vector3(0.48, 0.32, 0.22), Vector3(0.7, 0.74, 0.18)]:
				ci.draw_circle(P.call(p.x, p.y), r.size.x * p.z, Color(c.lerp(Color(0.6, 0.6, 0.62), 0.5), 0.85))
		"blast":
			for i in 12:
				var a := i * TAU / 12.0
				var l := 0.48 if i % 2 == 0 else 0.34
				ci.draw_line(P.call(0.5, 0.5), P.call(0.5, 0.5) + Vector2(cos(a), sin(a)) * r.size.x * l, c, w)
			ci.draw_circle(P.call(0.5, 0.5), r.size.x * 0.22, c.lightened(0.5))
		"flash":                 # a four-point star with a dash trail
			for k in 3:
				ci.draw_line(P.call(0.0, 0.62 + k * 0.12), P.call(0.28 - k * 0.06, 0.62 + k * 0.12), Color(c, 0.55), w * 0.7)
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.0), P.call(0.6, 0.4), P.call(1.0, 0.5), P.call(0.6, 0.6),
				P.call(0.5, 1.0), P.call(0.4, 0.6), P.call(0.0, 0.5), P.call(0.4, 0.4)]), c)
			ci.draw_circle(P.call(0.5, 0.5), r.size.x * 0.1, Color.WHITE)
		"smite":                 # a blade driven down into a burst (G54: unlike flash's star)
			for i in 7:
				var a := PI + i * PI / 6.0
				ci.draw_line(P.call(0.5, 0.86), P.call(0.5, 0.86) + Vector2(cos(a), sin(a)) * r.size.x * 0.34, Color(c, 0.75), w * 0.8)
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.42, 0.18), P.call(0.58, 0.18), P.call(0.58, 0.72),
				P.call(0.5, 0.9), P.call(0.42, 0.72)]), c)
			ci.draw_rect(Rect2(P.call(0.24, 0.12), r.size * Vector2(0.52, 0.08)), c.lightened(0.3))
			ci.draw_rect(Rect2(P.call(0.45, 0.0), r.size * Vector2(0.1, 0.13)), c.darkened(0.3))
		_:
			ci.draw_circle(P.call(0.5, 0.5), r.size.x * 0.3, c)


## The minimap: the map turned the way your camera looks (your base bottom
## left in the duel, your entrance at the bottom in the pit), towers, every
## unit as a dot, and the camera's view as a white frame.
class Minimap:
	extends Control
	var view: MobaView

	func _xf() -> Array:
		var f := view.view_forward()
		var right := Vector2(-f.y, f.x)
		var half := size.x / 2.0
		var ext := 13.0 if view.sim.mode == "pit" else (MobaSim.HALF_LEN + 4.0 + MobaSim.HALF_W + 2.0) * 0.7072
		return [f, right, half, (half - 12.0) / ext]

	func to_map(p: Vector2) -> Vector2:
		var x := _xf()
		var f: Vector2 = x[0]
		var right: Vector2 = x[1]
		return Vector2(x[2], x[2]) + Vector2(p.dot(right), -p.dot(f)) * float(x[3])

	var photo: Texture2D

	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), MobaHud.TRIM)
		draw_rect(Rect2(Vector2(3, 3), s - Vector2(6, 6)), Color("#16241c"))
		var sim := view.sim
		var sc: float = _xf()[3]
		if photo == null and s.x > 0.0:
			photo = view.minimap_photo(256, (s.x - 6.0) / sc)
		if photo:
			draw_texture_rect(photo, Rect2(Vector2(3, 3), s - Vector2(6, 6)), false)
			if sim.mode != "pit":
				for team in ["blue", "red"]:
					var c := to_map(Vector2(-MobaSim.HALF_LEN - 1.0 if team == "blue" else MobaSim.HALF_LEN + 1.0, 0))
					draw_rect(Rect2(c - Vector2(6, 6), Vector2(12, 12)), MobaLook.team_color(team).lightened(0.25))
					draw_rect(Rect2(c - Vector2(6, 6), Vector2(12, 12)), Color.BLACK, false, 1.5)
		elif sim.mode == "pit":
			draw_circle(to_map(Vector2.ZERO), (MobaSim.PIT_R + 1.4) * sc, Color("#3d3a4c"))
			draw_circle(to_map(Vector2.ZERO), MobaSim.PIT_R * sc, Color("#6b6680"))
		else:
			var L := MobaSim.HALF_LEN + 2.5
			var Wd := MobaSim.HALF_W + 0.5
			var pts := PackedVector2Array([to_map(Vector2(-L, -Wd)), to_map(Vector2(L, -Wd)), to_map(Vector2(L, Wd)), to_map(Vector2(-L, Wd))])
			draw_colored_polygon(pts, Color("#7d8291"))
			for team in ["blue", "red"]:
				var x := -MobaSim.HALF_LEN - 1.0 if team == "blue" else MobaSim.HALF_LEN + 1.0
				var c := to_map(Vector2(x, 0))
				draw_circle(c, 2.6 * sc, MobaLook.team_color(team).darkened(0.3))
				draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), MobaLook.team_color(team).lightened(0.2))
				draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), Color.BLACK, false, 1.5)
		var me := sim.unit(view.local_id)
		for u in sim.units:
			if not u.alive or (u.stealth and me and u.team != me.team):
				continue
			var p := to_map(u.pos)
			var col := MobaLook.BOSS if u.kind == "boss" else MobaLook.team_color(u.team)
			match u.kind:
				"champ":
					draw_circle(p, 8.0, Color.BLACK)
					draw_circle(p, 6.5, col)
					if me and u.id == me.id:
						draw_arc(p, 8.5, 0, TAU, 24, Color("#ffe066"), 2.0, true)
				"boss":
					draw_circle(p, 10.0, Color.BLACK)
					draw_circle(p, 8.5, col)
				_:
					draw_circle(p, 2.6, col.lightened(0.15))
		var pg: Dictionary = sim.pings.get(me.team if me else "", {})
		if not pg.is_empty() and sim.time - float(pg.time) < MobaSim.PING_TIME:      # your side's ping (G54)
			var pc := Color("#ff6a3d") if str(pg.kind) == "go" else Color("#4fb0ff")
			var pp := to_map(pg.pos)
			var pulse := 7.0 + 3.0 * absf(sin(sim.time * 5.0))
			draw_arc(pp, pulse, 0, TAU, 24, pc, 2.5, true)
			draw_circle(pp, 3.5, pc)
		# the camera's view on the ground
		var cam := view.camera()
		if cam:
			var vs := view.get_viewport().get_visible_rect().size
			var q := PackedVector2Array()
			for c in [Vector2(0, 0), Vector2(vs.x, 0), Vector2(vs.x, vs.y), Vector2(0, vs.y), Vector2(0, 0)]:
				var o := cam.project_ray_origin(c)
				var d := cam.project_ray_normal(c)
				if absf(d.y) < 0.001:
					continue
				var t := -o.y / d.y
				var g := o + d * t
				var m := to_map(Vector2(g.x, g.z))
				q.append(Vector2(clampf(m.x, 3, s.x - 3), clampf(m.y, 3, s.y - 3)))
			if q.size() >= 2:
				draw_polyline(q, Color(1, 1, 1, 0.85), 1.5)


## A unit's overhead bar, League-style: champions get a name, a level box
## (here: kills) and an HP bar ticked every 100 HP; minions a thin bar; the
## Giant a wide one ticked every 1000. A white chip trails damage taken.
class Bar:
	extends Control
	var kind := "champ"
	var title := ""
	var col := Color.RED
	var frac := 1.0
	var chip := 1.0
	var max_hp := 700.0
	var level := 0

	func setup(k: String, t: String, c: Color, mhp: float) -> void:
		kind = k
		title = t
		col = c
		max_hp = mhp
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		match k:
			"champ": size = Vector2(132, 38)
			"boss": size = Vector2(180, 18)
			_: size = Vector2(52, 7)

	func set_hp(f: float, delta: float) -> void:
		chip = maxf(f, chip - delta * 0.5) if f < chip else f
		if absf(f - frac) > 0.0005 or chip > f:
			frac = f
			queue_redraw()

	## Where the bar's own bottom-centre should sit.
	func anchor_offset() -> Vector2:
		return Vector2(size.x / 2.0, size.y)

	func _draw() -> void:
		var fnt := get_theme_default_font()
		if kind == "champ":
			var bx := Rect2(0, 18, 22, 20)
			var hp := Rect2(22, 20, size.x - 22, 16)
			if title != "":
				var fs := 13
				var w := fnt.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string_outline(fnt, Vector2(22 + (size.x - 22 - w) / 2.0, 11), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color.BLACK)
				draw_string(fnt, Vector2(22 + (size.x - 22 - w) / 2.0, 11), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
			draw_rect(Rect2(hp.position - Vector2(1, 2), hp.size + Vector2(2, 4)), Color(0.02, 0.02, 0.03))
			_hp(Rect2(hp.position + Vector2(1, 1), hp.size - Vector2(2, 2)), 100.0)
			draw_rect(bx, Color(0.04, 0.05, 0.08))
			draw_rect(bx, MobaHud.TRIM, false, 1.5)
			var t := "%d" % level
			var w2 := fnt.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(fnt, Vector2(bx.position.x + (bx.size.x - w2) / 2.0, bx.position.y + 15), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MobaHud.GOLD)
		elif kind == "boss":
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.03))
			_hp(Rect2(Vector2(2, 2), size - Vector2(4, 4)), 1000.0)
		else:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.03))
			_hp(Rect2(Vector2(1, 1), size - Vector2(2, 2)), 0.0)

	func _hp(r: Rect2, tick: float) -> void:
		draw_rect(Rect2(r.position, Vector2(r.size.x * chip, r.size.y)), Color(0.95, 0.92, 0.85))
		draw_rect(Rect2(r.position, Vector2(r.size.x * frac, r.size.y)), col)
		draw_rect(Rect2(r.position, Vector2(r.size.x * frac, r.size.y * 0.35)), Color(1, 1, 1, 0.16))
		if tick > 0.0:
			var n := int(max_hp / tick)
			for i in range(1, n + 1):
				var x := r.position.x + r.size.x * (i * tick / max_hp)
				if x >= r.position.x + r.size.x - 1.0:
					break
				var big := i % 10 == 0 and tick < 1000.0
				draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + r.size.y * (1.0 if big else 0.55)), Color(0, 0, 0, 0.75), 1.5 if big else 1.0)
