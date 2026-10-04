extends Node3D
## World-space VR menu: a rounded panel of options you select by POINTING the right hand and pulling
## the trigger, by TOUCHING an option (when the panel is within reach), or with the right stick + A.
## Follows core/vr_text.gd rules: never attached to the camera, never billboarded, placed at a
## comfortable distance and gliding back in front only when the player turns well away.
##
##   const VrMenu := preload("res://core/vr_menu.gd")
##   var m := VrMenu.open(self, {"title": "YOUR TURN", "items": ["Attack", "Magic", "Item"], "rig": vr_rig})
##   # (or "cam": xr_camera, "hand": right_controller without core/vr_rig.gd)
##   m.chosen.connect(func(id: String, item: Dictionary) -> void: ...)
##
## Items are the same as core/ui_menu.gd (String or Dictionary with id, text, desc, disabled, reason,
## right, color). columns > 1 makes a grid (e.g. 2x2 quiz answers). opts "reach": true puts the panel
## low and close (about 0.5 m) so it can be touched. Bots: hand can be any Node3D with metadata
## "trigger" (float), "ax_button" / "by_button" (bool), "primary" (Vector2); or call press("down").

signal chosen(id: String, item: Dictionary)
signal cancelled()
signal rejected(id: String, item: Dictionary)
signal focus_changed(id: String, item: Dictionary)
signal closed()

const UiKit := preload("res://core/ui_kit.gd")
const UiInput := preload("res://core/ui_input.gd")
const Me := preload("res://core/vr_menu.gd")
const VrText := preload("res://core/vr_text.gd")

# --- Options ---
var rig: Node = null              ## core/vr_rig.gd VrRig: camera, right hand and guarded trigger/A (bind_rig)
var cam: Node3D = null            ## the XR camera (placement + lazy follow)
var hand: Node3D = null           ## pointing hand (right XRController3D)
var title_text := ""
var columns := 1
var max_rows := 6                 ## visible rows (scrolls beyond)
var width := 1.0                  ## metres at the design distance (2 m)
var row_height := 0.115
var distance := 1.25              ## metres (times vr_text COMFORT 1.6 = 2.0 m)
var height := -0.12               ## metres relative to eye level (times COMFORT)
var follow := true                ## lazy-follow the view
var touch := true                 ## touching an option chooses it
var allow_cancel := false         ## adds a BACK row (and B button) when true
var close_on_choose := true
var free_on_close := true
var accent := UiKit.ACCENT
var player := -1
var layers := 1                   ## visual layers (e.g. a VR-only layer the TV cameras don't render)
var sounds := true
var haptics := true
var input_enabled := true

# --- State ---
var items: Array = []
var index := 0
var scroll := 0
var hovered := -1
var is_open := false
var reader: UiInput

var _panel: MeshInstance3D
var _hilite: MeshInstance3D
var _title: Label3D
var _desc: Label3D
var _footer: Label3D
var _labels: Array[Label3D] = []
var _rights: Array[Label3D] = []
var _arrows: Array[MeshInstance3D] = []
var _laser: MeshInstance3D
var _dot: MeshInstance3D
var _cell_rects: Array[Rect2] = []   ## visible cell rects in panel space (index = visible slot)
var _panel_size := Vector2.ONE
var _touch_latched := false
var _hover_slot := -1
var _built := false
var _hilite_tween: Tween
var _appear_tween: Tween
var _pending_pos: Variant = null


## Make a VR menu under `world` (usually Main) with opts (see setup) and open it.
static func open(world: Node, opts: Dictionary) -> Me:
	var m: Me = Me.new()
	m.setup(opts)
	world.add_child(m)
	return m


## Configure: title, items, columns, max_rows, width, rig (a core/vr_rig.gd VrRig: the usual way) or
## cam + hand, distance, height, follow, touch,
## reach (true = close + low for touching), allow_cancel, close_on_choose, free_on_close, accent, player,
## layers, sounds, haptics, start (id or index), position (Vector3: fixed spot instead of in front).
func setup(opts: Dictionary) -> Me:
	title_text = String(opts.get("title", title_text))
	items = UiKit.normalize_items(opts.get("items", items))
	columns = maxi(1, int(opts.get("columns", columns)))
	max_rows = maxi(1, int(opts.get("max_rows", max_rows)))
	width = float(opts.get("width", 1.0 if columns == 1 else 1.3))
	row_height = float(opts.get("row_height", 0.115 if columns == 1 else 0.17))
	cam = opts.get("cam", cam)
	hand = opts.get("hand", hand)
	if opts.has("rig"):
		bind_rig(opts["rig"])
	follow = bool(opts.get("follow", follow))
	touch = bool(opts.get("touch", touch))
	if bool(opts.get("reach", false)):
		distance = 0.42
		height = -0.22
		follow = false
	distance = float(opts.get("distance", distance))
	height = float(opts.get("height", height))
	allow_cancel = bool(opts.get("allow_cancel", allow_cancel))
	close_on_choose = bool(opts.get("close_on_choose", close_on_choose))
	free_on_close = bool(opts.get("free_on_close", free_on_close))
	player = int(opts.get("player", player))
	if player >= 0:
		accent = UiKit.player_color(player)
	if opts.has("accent"):
		accent = UiKit.color_of(opts["accent"], accent)
	layers = int(opts.get("layers", layers))
	sounds = bool(opts.get("sounds", sounds))
	haptics = bool(opts.get("haptics", haptics))
	input_enabled = bool(opts.get("input", input_enabled))
	if opts.has("position"):
		_pending_pos = opts["position"]
	if allow_cancel:
		var has_back := false
		for it in items:
			if String(it.id) == "__back":
				has_back = true
		if not has_back:
			items.append({"id": "__back", "text": "BACK", "disabled": false, "desc": "", "reason": "", "icon": "", "right": "", "badge": "", "color": UiKit.TEXT_DIM})
	if opts.has("start"):
		var st: Variant = opts["start"]
		if st is String:
			for k in items.size():
				if String(items[k].id) == String(st):
					index = k
		else:
			index = clampi(int(st), 0, maxi(0, items.size() - 1))
	if _built:
		_rebuild()
	return self


## Use a core/vr_rig.gd VrRig: its camera, its right hand for pointing, and its guarded trigger / A
## (a pull held over from another screen, or one that started on the wrist MENU, never chooses).
func bind_rig(p_rig: Node) -> void:
	rig = p_rig
	if rig == null:
		return
	cam = rig.get("camera")
	hand = rig.get("hand_r")
	if reader != null:
		reader = UiInput.for_rig(rig)
		reader.latch()


func _ready() -> void:
	reader = UiInput.for_rig(rig) if rig != null else UiInput.new(UiInput.PAD_NONE, UiInput.KEYS_NONE, hand)
	_build()
	_built = true
	_rebuild()
	open_menu()


func _exit_tree() -> void:
	if _laser != null and is_instance_valid(_laser):
		_laser.queue_free()
	if _dot != null and is_instance_valid(_dot):
		_dot.queue_free()


## The apparent-size factor: panels further away are scaled up so they read the same.
func size_scale() -> float:
	return distance * VrText.COMFORT / 2.0


## Show (again): place it in front of the camera and ignore a trigger still held from before.
func open_menu() -> void:
	visible = true
	is_open = true
	if rig == null:
		reader.hand = hand
	reader.latch()
	_touch_latched = true
	scale = Vector3.ONE * size_scale()
	if _pending_pos is Vector3:
		global_position = _pending_pos
		if cam != null:
			var to := cam.global_position - global_position
			to.y = 0.0
			if to.length() > 0.01:
				global_basis = Basis(Vector3.UP, atan2(to.x, to.z)).scaled(Vector3.ONE * size_scale())
	elif cam != null:
		UiKit.vr_place(self, cam, distance, height)
	_appear(true)
	_sound("ui_open")


## Close (fade out, then free unless free_on_close is false).
func close() -> void:
	if not is_open:
		return
	is_open = false
	_laser.visible = false
	_dot.visible = false
	closed.emit()
	_appear(false)


## Inject an action: "up", "down", "left", "right", "confirm", "cancel".
func press(action: String) -> void:
	if not is_open or items.is_empty():
		return
	match action:
		"up":
			_move(-columns)
		"down":
			_move(columns)
		"left":
			if columns > 1:
				_move(-1)
		"right":
			if columns > 1:
				_move(1)
		"confirm":
			confirm()
		"cancel":
			if allow_cancel:
				_sound("ui_back")
				cancelled.emit()
				close()


## Confirm the focused item (or `at`).
func confirm(at: int = -1) -> void:
	if items.is_empty() or not is_open:
		return
	if at >= 0:
		focus(at)
	var it: Dictionary = items[index]
	if String(it.id) == "__back":
		press("cancel")
		return
	if it.disabled:
		_sound("ui_error")
		_pulse_hand(0.6, 0.12)
		_set_desc(it, true)
		_shake()
		rejected.emit(String(it.id), it)
		return
	_sound("ui_select")
	_pulse_hand(0.5, 0.06)
	chosen.emit(String(it.id), it)
	if close_on_choose:
		close()


## Focus an item by index or id.
func focus(which: Variant) -> void:
	var i := -1
	if which is String or which is StringName:
		for k in items.size():
			if String(items[k].id) == String(which):
				i = k
	else:
		i = int(which)
	if i < 0 or items.is_empty():
		return
	i = clampi(i, 0, items.size() - 1)
	if i == index:
		return
	index = i
	var row := index / columns
	var first := scroll
	if row < scroll:
		scroll = row
	elif row >= scroll + max_rows:
		scroll = row - max_rows + 1
	if scroll != first:
		_layout_rows()
	_move_hilite(true)
	_set_desc(items[index], false)
	focus_changed.emit(String(items[index].id), items[index])


## Replace the items.
func set_items(list: Array) -> void:
	items = UiKit.normalize_items(list)
	index = clampi(index, 0, maxi(0, items.size() - 1))
	if _built:
		_rebuild()


# --- Building --------------------------------------------------------------------------------------

func _build() -> void:
	_panel = MeshInstance3D.new()
	_panel.material_override = UiKit.vr_panel_material(UiKit.VR_PRIO_PANEL)
	_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_panel)
	_hilite = MeshInstance3D.new()
	_hilite.material_override = UiKit.vr_panel_material(UiKit.VR_PRIO_HILITE)
	_hilite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hilite)
	_title = UiKit.label3d("", 0.07, "text", true)
	add_child(_title)
	_desc = UiKit.label3d("", 0.038, "dim")
	add_child(_desc)
	_footer = UiKit.label3d("POINT + TRIGGER   or   STICK + A", 0.03, UiKit.TEXT_OFF)
	add_child(_footer)
	for k in 2:
		var a := MeshInstance3D.new()
		a.mesh = _triangle_mesh(k == 0)
		a.material_override = UiKit.vr_panel_material(UiKit.VR_PRIO_HILITE)
		a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(a)
		_arrows.append(a)
	_laser = MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.004, 0.004, 1.0)
	_laser.mesh = lm
	_laser.material_override = _glow_material(accent)
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser.top_level = true
	add_child(_laser)
	_dot = MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.012
	dm.height = 0.024
	dm.radial_segments = 10
	dm.rings = 5
	_dot.mesh = dm
	_dot.material_override = _glow_material(Color.WHITE)
	_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dot.top_level = true
	add_child(_dot)


func _glow_material(c: Color) -> StandardMaterial3D:
	var key := "ui_vrlaser_%s_%s" % [c.to_html(), UiKit.VERSION]
	return UiKit.ResCache.get_or_make(key, func() -> Resource:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(c.r, c.g, c.b, 0.85)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = false
		m.render_priority = UiKit.VR_PRIO_TEXT + 1
		return m)


func _triangle_mesh(up: bool) -> ArrayMesh:
	var key := "ui_vrtri_%s_%s" % [up, UiKit.VERSION]
	return UiKit.ResCache.get_or_make(key, func() -> Resource:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var s := 1.0 if up else -1.0
		var c := Color(1, 1, 1, 0.75)
		var pts: Array[Vector3] = [Vector3(-0.03, -0.012 * s, 0), Vector3(0, 0.018 * s, 0), Vector3(0.03, -0.012 * s, 0)]
		if not up:
			pts.reverse()
		for p in pts:
			st.set_color(c)
			st.set_normal(Vector3.BACK)
			st.add_vertex(p)
		return st.commit())


func _rebuild() -> void:
	for l in _labels:
		l.queue_free()
	for l in _rights:
		l.queue_free()
	_labels.clear()
	_rights.clear()
	var visible_rows := mini(max_rows, ceili(float(items.size()) / columns))
	var pad := 0.05
	var gap := 0.014
	var title_h := 0.11 if title_text != "" else 0.0
	var desc_h := 0.0
	for it in items:
		if String(it.desc) != "" or String(it.reason) != "":
			desc_h = 0.1
	var footer_h := 0.06
	var body_h := visible_rows * row_height + maxi(0, visible_rows - 1) * gap
	_panel_size = Vector2(width, pad * 2.0 + title_h + body_h + desc_h + footer_h)
	_panel.mesh = UiKit.panel_mesh(_panel_size, UiKit.BG, Color(accent.r, accent.g, accent.b, 0.55), 0.05, 0.01)
	var top := _panel_size.y * 0.5 - pad
	_title.text = title_text
	_title.visible = title_text != ""
	_title.position = Vector3(0, top - title_h * 0.4, 0.004)
	var body_top := top - title_h
	var cell_w := (width - pad * 2.0 - gap * (columns - 1)) / columns
	_cell_rects.clear()
	for slot in visible_rows * columns:
		var r := slot / columns
		var c := slot % columns
		var x0 := -width * 0.5 + pad + c * (cell_w + gap)
		var y1 := body_top - r * (row_height + gap)
		_cell_rects.append(Rect2(Vector2(x0, y1 - row_height), Vector2(cell_w, row_height)))
		var l := UiKit.label3d("", 0.05 if columns == 1 else 0.045, "text", false, cell_w - 0.04 if columns > 1 else 0.0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if columns == 1 else HORIZONTAL_ALIGNMENT_CENTER
		add_child(l)
		_labels.append(l)
		var rl := UiKit.label3d("", 0.038, "dim")
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(rl)
		_rights.append(rl)
	_hilite.mesh = UiKit.panel_mesh(Vector2(cell_w, row_height), Color(accent.r, accent.g, accent.b, 0.3), accent, 0.03, 0.008)
	_desc.position = Vector3(0, body_top - body_h - desc_h * 0.5 - 0.01, 0.004)
	_desc.width = (width - pad * 2.0) / _desc.pixel_size
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.visible = desc_h > 0.0
	_footer.position = Vector3(0, -_panel_size.y * 0.5 + pad + 0.012, 0.004)
	_footer.text = "POINT + TRIGGER   or   STICK + A" if not touch or distance > 0.6 else "TOUCH  or  POINT + TRIGGER"
	_arrows[0].position = Vector3(width * 0.5 - pad * 0.6, body_top - 0.02, 0.003)
	_arrows[1].position = Vector3(width * 0.5 - pad * 0.6, body_top - body_h + 0.02, 0.003)
	_apply_layers()
	var row := index / columns
	scroll = clampi(row - max_rows + 1, 0, maxi(0, row)) if row >= max_rows else 0
	_layout_rows()
	_move_hilite(false)
	if not items.is_empty():
		_set_desc(items[index], false)


func _layout_rows() -> void:
	for slot in _labels.size():
		var i := scroll * columns + slot
		var l := _labels[slot]
		var rl := _rights[slot]
		var rect := _cell_rects[slot]
		if i >= items.size():
			l.visible = false
			rl.visible = false
			continue
		var it: Dictionary = items[i]
		l.visible = true
		l.text = String(it.text)
		var col: Color = UiKit.TEXT_OFF if it.disabled else UiKit.color_of(it.get("color", null), UiKit.TEXT)
		l.modulate = col
		if columns == 1:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT  # left alignment: the text starts at the origin
			l.position = Vector3(rect.position.x + 0.035, rect.get_center().y, 0.005)
		else:
			l.position = Vector3(rect.get_center().x, rect.get_center().y, 0.005)
		var rt := String(it.right) if String(it.right) != "" else String(it.badge)
		if it.disabled and rt == "":
			rt = "LOCKED"
		rl.visible = rt != "" and columns == 1
		rl.text = rt
		rl.modulate = UiKit.TEXT_OFF if it.disabled else UiKit.TEXT_DIM
		rl.position = Vector3(rect.end.x - 0.03, rect.get_center().y, 0.005)  # right-aligned: ends at the origin
	var rows_total := ceili(float(items.size()) / columns)
	_arrows[0].visible = scroll > 0
	_arrows[1].visible = scroll + max_rows < rows_total


func _apply_layers() -> void:
	for c in get_children():
		if c is VisualInstance3D:
			(c as VisualInstance3D).layers = layers


func _move_hilite(animate: bool) -> void:
	var slot := index - scroll * columns
	if slot < 0 or slot >= _cell_rects.size():
		_hilite.visible = false
		return
	_hilite.visible = true
	var target := Vector3(_cell_rects[slot].get_center().x, _cell_rects[slot].get_center().y, 0.002)
	if _hilite_tween != null and _hilite_tween.is_valid():
		_hilite_tween.kill()
	if animate:
		_hilite_tween = create_tween()
		_hilite_tween.tween_property(_hilite, "position", target, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_hilite.position = target
	for k in _labels.size():
		var i := scroll * columns + k
		if i < items.size() and not items[i].disabled:
			_labels[k].modulate = Color.WHITE if i == index else UiKit.color_of(items[i].get("color", null), UiKit.TEXT)


func _set_desc(it: Dictionary, reason_alert: bool) -> void:
	var txt := String(it.desc)
	if it.disabled and String(it.reason) != "":
		txt = "Can't: " + String(it.reason)
	_desc.text = txt
	_desc.modulate = UiKit.BAD.lightened(0.3) if reason_alert else UiKit.TEXT_DIM


func _shake() -> void:
	var base := _hilite.position
	var t := create_tween()
	for k in 4:
		t.tween_property(_hilite, "position:x", base.x + (0.012 if k % 2 == 0 else -0.012), 0.04)
	t.tween_property(_hilite, "position:x", base.x, 0.04)


func _appear(on: bool) -> void:
	if _appear_tween != null and _appear_tween.is_valid():
		_appear_tween.kill()
	var t := create_tween().set_parallel()
	_appear_tween = t
	var nodes: Array[GeometryInstance3D] = []
	for c in get_children():
		if c is GeometryInstance3D and c != _laser and c != _dot:
			nodes.append(c)
	for g in nodes:
		if on:
			g.transparency = 1.0
		t.tween_property(g, "transparency", 0.0 if on else 1.0, 0.18 if on else 0.15)
	if on:
		var sc := scale
		scale = sc * 0.92
		t.tween_property(self, "scale", sc, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		t.chain().tween_callback(func() -> void:
			visible = false
			if free_on_close:
				queue_free())


# --- Per frame -------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_open:
		return
	if follow and cam != null and is_instance_valid(cam):
		UiKit.vr_follow(self, cam, distance, height, delta)
	_update_pointer()
	if not input_enabled:
		return
	for a in reader.poll(delta):
		if a == "confirm":
			# the trigger confirms what you point at; A confirms the focused item
			if reader.hand_float("trigger") > 0.6 and not reader.hand_bool("ax_button"):
				if _hover_slot >= 0:
					confirm(scroll * columns + _hover_slot)
			else:
				confirm()
		else:
			press(a)
	_update_touch()


## Ray from the hand onto the panel: hover highlight, laser and dot.
func _update_pointer() -> void:
	_hover_slot = -1
	if hand == null or not is_instance_valid(hand) or not hand.is_inside_tree():
		_laser.visible = false
		_dot.visible = false
		return
	var o := hand.global_position
	var d := -hand.global_basis.z.normalized()
	var n := global_basis.z.normalized()
	var denom := d.dot(n)
	var hit_ok := false
	var hit := Vector3.ZERO
	if denom < -0.05:
		var t := (global_position - o).dot(n) / denom
		if t > 0.0 and t < 8.0:
			hit = o + d * t
			var lp := to_local(hit)
			var half := _panel_size * 0.5
			if absf(lp.x) <= half.x and absf(lp.y) <= half.y:
				hit_ok = true
				for slot in _cell_rects.size():
					var i := scroll * columns + slot
					if i < items.size() and _cell_rects[slot].has_point(Vector2(lp.x, lp.y)):
						_hover_slot = slot
						if i != index:
							_sound("ui_move", -6.0)
							_pulse_hand(0.18, 0.02)
							focus(i)
	var end := hit if hit_ok else o + d * 0.35
	var length := o.distance_to(end)
	_laser.visible = length > 0.02
	if _laser.visible:
		var b := Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT) * Basis.from_scale(Vector3(1, 1, length))
		_laser.global_transform = Transform3D(b, o + d * length * 0.5)
		_laser.transparency = 0.0 if hit_ok else 0.7
	_dot.visible = hit_ok
	if hit_ok:
		_dot.global_position = hit + n * 0.004


## Touching an option with the controller tip chooses it (only possible when the panel is in reach).
func _update_touch() -> void:
	if not touch or hand == null or not is_instance_valid(hand) or not hand.is_inside_tree():
		return
	var tip := hand.global_position - hand.global_basis.z.normalized() * 0.04
	var lp := to_local(tip)
	var depth := absf(lp.z) * global_basis.get_scale().z
	if depth > 0.06:
		_touch_latched = false
		return
	if _touch_latched or depth > 0.03:
		return
	for slot in _cell_rects.size():
		var i := scroll * columns + slot
		if i < items.size() and _cell_rects[slot].has_point(Vector2(lp.x, lp.y)):
			_touch_latched = true
			confirm(i)
			return


func _move(step: int) -> void:
	if items.is_empty():
		return
	var i := posmod(index + step, items.size())
	if i != index:
		_sound("ui_move", -4.0)
		_pulse_hand(0.15, 0.02)
		focus(i)


func _sound(name: String, vol: float = 0.0) -> void:
	if sounds:
		UiKit.sound(name, vol)


func _pulse_hand(amp: float, dur: float) -> void:
	if haptics and rig != null and rig.has_method("pulse"):
		rig.call("pulse", 1, amp, dur)  # VrRig.RIGHT
	elif haptics and hand is XRController3D:
		(hand as XRController3D).trigger_haptic_pulse("haptic", 0.0, amp, dur, 0.0)
