extends Control
## The kit bench: the workshop UI over the Gamer Kit. Pick an asset, shape it
## with its parameters, keep presets, export a .glb + sidecar. The kit itself
## never needs this scene (GKRegistry builds without it); the bench is only
## the hands-on front end for developers and artists.
##
##   godot --path . res://scenes/kit_bench.tscn
##
## Editing: every change is one undo step (Ctrl+Z, Ctrl+Y / Ctrl+Shift+Z); a
## slider drag merges into one step. Rebuilds are debounced while dragging
## and timed; the status line shows triangles, build time, and any warning
## or error in colour. Presets: the generator's own plus yours, saved per
## asset in user://kit_presets/<id>.json. View: drag to orbit, right-drag to
## pan, wheel to zoom; F frames, G toggles the 2.2 m scale figure, C shows
## collision boxes (environments).

const USER_DIR := "user://kit_presets"
const DEBOUNCE := 0.12

var headless := false                 ## tests: no viewport, synchronous builds
var def: GKDef
var params := {}
var asset: GKAsset
var undo := UndoRedo.new()

var _list: ItemList
var _preset_pick: OptionButton
var _form: VBoxContainer
var _status: RichTextLabel
var _editors := {}                    # key -> Control
var _view: SubViewport
var _world: Node3D
var _stage: Node3D
var _inst: Node3D
var _figure: Node3D
var _cam: Camera3D
var _orbit := Vector2(-0.6, -0.35)   # yaw, pitch
var _dist := 2.0
var _target := Vector3.ZERO
var _pending := 0.0
var _dragging_key := ""
var _drag_from: Variant = null
var _show_col := false
var _export_dialog: FileDialog
var _syncing := false


func _ready() -> void:
	if headless:
		return
	_build_ui()
	var ids := GKRegistry.ids()
	for id in ids:
		_list.add_item(GKRegistry.def(id).title())
		_list.set_item_metadata(_list.item_count - 1, id)
	if ids.size() > 0:
		_list.select(0)
		select(ids[0])


func _exit_tree() -> void:
	undo.free()


# ----------------------------------------------------------------- API (tests use it too)

func select(id: String) -> void:
	var d := GKRegistry.def(id)
	if d == null:
		_say("No asset '%s'." % id, "error")
		return
	def = d
	params = d.defaults()
	undo.clear_history()
	if not headless:
		_fill_form()
		_fill_presets()
		_set_stage()
	_rebuild(true)


func value(key: String) -> Variant:
	return params.get(key)


## One undoable change. Slider drags call this many times; they merge.
func set_param(key: String, v: Variant, merge := false) -> void:
	var e := def.entry(key)
	if e.is_empty():
		_say("Unknown parameter '%s'." % key, "error")
		return
	var errs := PackedStringArray()
	var nv: Variant = GKDef.coerce(e, v, errs)
	if not errs.is_empty():
		_say(errs[0], "warn")
	var old: Variant = params.get(key)
	if not merge and nv == old:
		return
	undo.create_action("Set %s" % str(e.label), UndoRedo.MERGE_ENDS if merge else UndoRedo.MERGE_DISABLE)
	undo.add_do_method(_apply.bind(key, nv))
	undo.add_undo_method(_apply.bind(key, old if not merge or _drag_from == null else _drag_from))
	undo.commit_action()


func apply_preset(preset_name: String) -> void:
	var src := def.presets()
	var mine := user_presets()
	if not src.has(preset_name) and not mine.has(preset_name):
		_say("No preset '%s'." % preset_name, "error")
		return
	var target := def.preset(preset_name) if src.has(preset_name) else def.validate(mine[preset_name])
	var before := params.duplicate()
	undo.create_action("Preset %s" % preset_name)
	undo.add_do_method(_apply_all.bind(target))
	undo.add_undo_method(_apply_all.bind(before))
	undo.commit_action()
	_say("Preset \"%s\" applied." % preset_name, "ok")


func undo_step() -> void:
	if undo.has_undo():
		var n := undo.get_current_action_name()
		undo.undo()
		_say("Undid: %s" % n, "ok")
	else:
		_say("Nothing to undo.", "warn")


func redo_step() -> void:
	if undo.has_redo():
		undo.redo()
		_say("Redid: %s" % undo.get_current_action_name(), "ok")
	else:
		_say("Nothing to redo.", "warn")


func user_presets() -> Dictionary:
	var path := USER_DIR.path_join(def.id() + ".json")
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) != TYPE_DICTIONARY:
		_say("Your preset file for %s is unreadable; it was left alone." % def.id(), "error")
		return {}
	return d


func save_preset(preset_name: String) -> bool:
	preset_name = preset_name.strip_edges()
	if preset_name == "":
		_say("Give the preset a name first.", "warn")
		return false
	if def.presets().has(preset_name):
		_say("\"%s\" is a built-in preset; pick another name." % preset_name, "warn")
		return false
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var all := user_presets()
	all[preset_name] = params.duplicate()
	var f := FileAccess.open(USER_DIR.path_join(def.id() + ".json"), FileAccess.WRITE)
	if f == null:
		_say("Could not save the preset (%s)." % error_string(FileAccess.get_open_error()), "error")
		return false
	f.store_string(JSON.stringify(all, "\t"))
	f.close()
	if not headless:
		_fill_presets()
	_say("Saved preset \"%s\"." % preset_name, "ok")
	return true


func delete_preset(preset_name: String) -> void:
	var all := user_presets()
	if not all.has(preset_name):
		return
	all.erase(preset_name)
	var f := FileAccess.open(USER_DIR.path_join(def.id() + ".json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all, "\t"))
		f.close()
	if not headless:
		_fill_presets()
	_say("Deleted preset \"%s\"." % preset_name, "ok")


func export_to(path: String) -> Dictionary:
	if asset == null:
		return { "ok": false, "error": "nothing built" }
	_say("Exporting %s…" % path.get_file(), "busy")
	var res := GKExport.export_glb(asset, path)
	if res.ok:
		_say("Exported %s (%d KB) and its .json sidecar." % [path.get_file(), int(res.bytes) / 1024], "ok")
	else:
		_say("Export failed: %s" % res.error, "error")
	return res


# ----------------------------------------------------------------- internals

func _apply(key: String, v: Variant) -> void:
	params[key] = v
	_sync_editor(key)
	_rebuild(false)


func _apply_all(p: Dictionary) -> void:
	params = p.duplicate()
	for k in params:
		_sync_editor(k)
	_rebuild(false)


func _rebuild(now: bool) -> void:
	if headless or now:
		_build_now()
	else:
		_pending = DEBOUNCE


func _process(delta: float) -> void:
	if _pending > 0.0:
		_pending -= delta
		if _pending <= 0.0:
			_build_now()


func _build_now() -> void:
	_pending = 0.0
	var t0 := Time.get_ticks_usec()
	asset = def.build(params)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if asset == null or asset.parts.is_empty():
		_say("The build produced nothing; check the parameters.", "error")
		return
	if headless:
		return
	if _inst:
		_inst.queue_free()
	_inst = asset.instantiate(true)
	_world.add_child(_inst)
	_show_collision(_show_col)
	var msg := "%s · %s tris · %d markers · %.1f ms" % [def.title(), _thousands(asset.triangle_count()), asset.markers.size(), ms]
	if asset.kind == "env":
		msg += " · %d colliders" % asset.colliders.size()
	if asset.warnings.is_empty():
		_say(msg, "ok")
	else:
		_say(msg + " · " + "; ".join(asset.warnings), "warn")


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _say(text: String, kind := "ok") -> void:
	if headless:
		if kind == "error":
			push_warning("kit bench: " + text)
		return
	var col: String = { "ok": "#cfd6dc", "warn": "#f0b54a", "error": "#ff6b5e", "busy": "#8fc6ff" }.get(kind, "#cfd6dc")
	_status.text = "[color=%s]%s[/color]" % [col, text]


# ----------------------------------------------------------------- UI

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("#1b1e22")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	# left: assets, presets, parameters
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(360, 0)
	side.add_theme_constant_override("separation", 6)
	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 10)
	pad.add_child(side)
	root.add_child(pad)
	side.add_child(_label("Asset", true))
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 120)
	_list.item_selected.connect(func(i: int) -> void: select(str(_list.get_item_metadata(i))))
	side.add_child(_list)
	side.add_child(_label("Preset", true))
	var prow := HBoxContainer.new()
	_preset_pick = OptionButton.new()
	_preset_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_pick.item_selected.connect(func(i: int) -> void:
		if i > 0:
			apply_preset(_preset_pick.get_item_text(i).trim_prefix("★ ")))
	prow.add_child(_preset_pick)
	var save := Button.new()
	save.text = "Save as…"
	save.pressed.connect(_ask_preset_name)
	prow.add_child(save)
	var del := Button.new()
	del.text = "Delete"
	del.tooltip_text = "Delete the selected preset of yours"
	del.pressed.connect(func() -> void:
		var t := _preset_pick.get_item_text(_preset_pick.selected)
		if t.begins_with("★ "):
			delete_preset(t.trim_prefix("★ "))
		else:
			_say("Only your own presets (★) can be deleted.", "warn"))
	prow.add_child(del)
	side.add_child(prow)
	var urow := HBoxContainer.new()
	for spec in [["Undo", undo_step], ["Redo", redo_step], ["Defaults", func() -> void: _apply_defaults()], ["Export .glb", _ask_export]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		urow.add_child(b)
	side.add_child(urow)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_form)
	side.add_child(scroll)
	# right: the view and the status line
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	var vc := SubViewportContainer.new()
	vc.stretch = true
	vc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vc.gui_input.connect(_view_input)
	right.add_child(vc)
	_view = SubViewport.new()
	_view.msaa_3d = Viewport.MSAA_4X
	_view.own_world_3d = true
	vc.add_child(_view)
	_world = Node3D.new()
	_view.add_child(_world)
	_cam = Camera3D.new()
	_cam.fov = 35.0
	_view.add_child(_cam)
	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.scroll_active = false
	_status.custom_minimum_size = Vector2(0, 28)
	var sp := MarginContainer.new()
	sp.add_theme_constant_override("margin_left", 10)
	sp.add_child(_status)
	right.add_child(sp)
	var help := _label("Drag: orbit · right-drag: pan · wheel: zoom · F frame · G scale figure · C collision · Ctrl+Z / Ctrl+Y")
	help.add_theme_color_override("font_color", Color("#7d868e"))
	right.add_child(help)
	_export_dialog = FileDialog.new()
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.filters = PackedStringArray(["*.glb ; glTF binary"])
	_export_dialog.file_selected.connect(func(p: String) -> void: export_to(p))
	add_child(_export_dialog)


func _label(t: String, head := false) -> Label:
	var l := Label.new()
	l.text = t
	if head:
		l.add_theme_color_override("font_color", Color("#e8c37a"))
	return l


func _fill_form() -> void:
	for c in _form.get_children():
		c.queue_free()
	_editors.clear()
	var group := ""
	for e in def.schema():
		if str(e.group) != group:
			group = str(e.group)
			var h := _label(group, true)
			_form.add_child(h)
		var row := HBoxContainer.new()
		var l := _label(str(e.label))
		l.custom_minimum_size = Vector2(150, 0)
		l.clip_text = true
		l.tooltip_text = "%s (%s)" % [e.label, e.key]
		row.add_child(l)
		var key: String = e.key
		match str(e.type):
			"bool":
				var cb := CheckBox.new()
				cb.button_pressed = bool(params[key])
				cb.toggled.connect(func(on: bool) -> void:
					if not _syncing:
						set_param(key, on))
				row.add_child(cb)
				_editors[key] = cb
			"enum":
				var ob := OptionButton.new()
				for o in e.options:
					ob.add_item(str(o))
				ob.select((e.options as Array).find(params[key]))
				ob.item_selected.connect(func(i: int) -> void:
					if not _syncing:
						set_param(key, e.options[i]))
				ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(ob)
				_editors[key] = ob
			_:
				var sl := HSlider.new()
				sl.min_value = float(e.min)
				sl.max_value = float(e.max)
				sl.step = float(e.get("step", 0.001))
				sl.value = float(params[key])
				sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var sb := SpinBox.new()
				sb.min_value = sl.min_value
				sb.max_value = sl.max_value
				sb.step = sl.step
				sb.value = sl.value
				sb.custom_minimum_size = Vector2(84, 0)
				sl.drag_started.connect(func() -> void:
					_dragging_key = key
					_drag_from = params[key])
				sl.drag_ended.connect(func(_changed: bool) -> void:
					_dragging_key = ""
					_drag_from = null)
				sl.value_changed.connect(func(v: float) -> void:
					if _syncing:
						return
					sb.set_value_no_signal(v)
					set_param(key, v, _dragging_key == key))
				sb.value_changed.connect(func(v: float) -> void:
					if _syncing:
						return
					sl.set_value_no_signal(v)
					set_param(key, v))
				row.add_child(sl)
				row.add_child(sb)
				_editors[key] = [sl, sb]
		_form.add_child(row)


func _sync_editor(key: String) -> void:
	if headless or not _editors.has(key):
		return
	_syncing = true
	var ed: Variant = _editors[key]
	var v: Variant = params[key]
	if ed is CheckBox:
		(ed as CheckBox).button_pressed = bool(v)
	elif ed is OptionButton:
		(ed as OptionButton).select((def.entry(key).options as Array).find(v))
	elif ed is Array:
		(ed[0] as HSlider).value = float(v)
		(ed[1] as SpinBox).value = float(v)
	_syncing = false


func _fill_presets() -> void:
	_preset_pick.clear()
	_preset_pick.add_item("— choose a preset —")
	for n in def.presets():
		_preset_pick.add_item(str(n))
	for n in user_presets():
		_preset_pick.add_item("★ " + str(n))
	_preset_pick.select(0)


func _apply_defaults() -> void:
	var before := params.duplicate()
	undo.create_action("Defaults")
	undo.add_do_method(_apply_all.bind(def.defaults()))
	undo.add_undo_method(_apply_all.bind(before))
	undo.commit_action()


func _ask_preset_name() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Save preset"
	var le := LineEdit.new()
	le.placeholder_text = "Preset name"
	dlg.add_child(le)
	dlg.confirmed.connect(func() -> void:
		save_preset(le.text)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(320, 100))
	le.grab_focus()


func _ask_export() -> void:
	_export_dialog.current_file = def.id() + ".glb"
	_export_dialog.popup_centered_ratio(0.6)


func _set_stage() -> void:
	if _stage:
		_stage.queue_free()
	if _figure:
		_figure.queue_free()
		_figure = null
	if def.kind() == "env":
		_stage = GKStage.outdoor(def.build(def.defaults()).lights)
	else:
		_stage = GKStage.studio(Color("#2a2e33"))
	_world.add_child(_stage)
	_frame_view.call_deferred()


func _frame_view() -> void:
	if asset == null:
		return
	var b := asset.aabb()
	if asset.kind == "env" and asset.markers.has("ref_cam"):
		var t := asset.marker("ref_cam")
		_target = t.origin - t.basis.z * 20.0
		_dist = 20.0
		var f := -t.basis.z
		_orbit = Vector2(atan2(-f.x, -f.z), asin(clampf(f.y, -1.0, 1.0)))
	else:
		_target = b.get_center()
		_dist = b.size.length() * 1.6
		_orbit = Vector2(-0.9, -0.3)
	_place_cam()


func _place_cam() -> void:
	var dir := Vector3(sin(_orbit.x) * cos(_orbit.y), -sin(_orbit.y), cos(_orbit.x) * cos(_orbit.y))
	_cam.position = _target + dir * _dist
	_cam.look_at(_target, Vector3.UP)
	_cam.near = maxf(_dist * 0.01, 0.01)
	_cam.far = maxf(_dist * 200.0, 500.0)


func _view_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_orbit.x -= mm.relative.x * 0.008
			_orbit.y = clampf(_orbit.y + mm.relative.y * 0.008, -1.5, 1.5)
			_place_cam()
		elif mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			var b := _cam.global_transform.basis
			_target += (-b.x * mm.relative.x + b.y * mm.relative.y) * _dist * 0.0015
			_place_cam()
	elif ev is InputEventMouseButton and ev.pressed:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist *= 0.9
			_place_cam()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist *= 1.1
			_place_cam()


func _unhandled_key_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.ctrl_pressed and k.keycode == KEY_Z:
		if k.shift_pressed:
			redo_step()
		else:
			undo_step()
	elif k.ctrl_pressed and k.keycode == KEY_Y:
		redo_step()
	elif k.keycode == KEY_F:
		_frame_view()
	elif k.keycode == KEY_G:
		_toggle_figure()
	elif k.keycode == KEY_C:
		_show_col = not _show_col
		_show_collision(_show_col)
		_say("Collision boxes %s." % ("shown" if _show_col else "hidden"), "ok")


## A 2.2 m stand-in body beside the asset, for scale.
func _toggle_figure() -> void:
	if _figure:
		_figure.queue_free()
		_figure = null
		return
	_figure = Node3D.new()
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 2.2
	body.mesh = cap
	body.position.y = 1.1
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.5, 0.2, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body.material_override = m
	_figure.add_child(body)
	var b := asset.aabb() if asset else AABB()
	_figure.position = Vector3(b.end.x + 0.5, b.position.y if asset.kind == "item" else 0.0, b.get_center().z) if asset.kind == "item" else _target
	_world.add_child(_figure)


func _show_collision(on: bool) -> void:
	if _inst == null:
		return
	var body := _inst.get_node_or_null("Collision")
	var old := _inst.get_node_or_null("CollisionView")
	if old:
		old.queue_free()
	if not on or body == null:
		return
	var view := Node3D.new()
	view.name = "CollisionView"
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.2, 0.6, 0.25)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	for cs in body.get_children():
		var shape := (cs as CollisionShape3D).shape as BoxShape3D
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = shape.size
		mi.mesh = bm
		mi.material_override = m
		mi.transform = (cs as CollisionShape3D).transform
		view.add_child(mi)
	_inst.add_child(view)
