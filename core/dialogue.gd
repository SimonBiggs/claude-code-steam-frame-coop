extends Node
## Conversations and cutscene text: a typewriter dialogue box with the speaker's name and colour,
## optional choices (core/ui_menu.gd on the TV, core/vr_menu.gd in VR), advance with A / Enter /
## trigger, hold to skip. Shows on any number of TV views (a box at the bottom of each) and/or in VR (a
## world-space panel below eye level, never attached to the camera, never billboarded).
##
##   const Dialogue := preload("res://core/dialogue.gd")
##   var dlg := Dialogue.new()
##   add_child(dlg)
##   dlg.add_tv_view(ui_root)                          # each split-screen view's UiKit.ui_root
##   dlg.set_vr(xr_camera, hand_r)                     # optional: show it in VR too
##   dlg.play([
##       {"speaker": "ELDER", "color": "gold", "text": "Welcome, {hero}!"},
##       {"speaker": "ELDER", "text": "Will you help us?", "choices": [
##           {"text": "Of course!", "goto": "yes"}, {"text": "Not today", "goto": "no"}]},
##       {"label": "yes", "text": "Wonderful!", "event": "quest_start", "goto": "end"},
##       {"label": "no", "speaker": "ELDER", "text": "Oh... come back soon."},
##       {"label": "end"},
##   ], {"vars": {"hero": "Sir Bun"}})
##   await dlg.finished
##
## Line keys: speaker, text ({var} substitution), color (Color / palette name / player index),
## portrait (initials or an icon kind; "" = none), choices (Strings or {text, id, goto, set, event,
## disabled, reason}), label, goto, event (emits `event`), set ({var: value}), if ("var" or "!var":
## skip the line unless true), call (Callable), wait (seconds without a box), auto (advance N s after
## typing), speed (chars/s), pitch (voice blip pitch), sound (sfx name), chooser ("tv"/"vr"),
## device (controller that answers the choices), end (true = stop here).
##
## Networking: run it on the host; mirror on the client with `remote = true` and `show_line(index)` /
## `stop()` from net events (line_started gives the index). In remote mode input emits
## advance_requested / choice_requested(index) instead of acting.

signal started()
signal line_started(index: int, line: Dictionary)
signal line_typed(index: int)
signal choice_made(id: String, choice_index: int)
signal event(name: String, line: Dictionary)
signal finished()
signal advance_requested()
signal choice_requested(choice_index: int)

const UiKit := preload("res://core/ui_kit.gd")
const UiInput := preload("res://core/ui_input.gd")
const UiMenu := preload("res://core/ui_menu.gd")
const VrMenu := preload("res://core/vr_menu.gd")

# --- Options ---
var device := UiInput.PAD_ANY     ## who can advance: a joypad id or PAD_ANY
var keys := UiInput.KEYS_ALL
var speed := 46.0                 ## characters per second
var skippable := true             ## hold confirm to skip to the next choice / the end
var skip_hold := 0.9              ## seconds to hold
var remote := false               ## mirror mode (see header)
var portraits := true
var sounds := true
var vars := {}                    ## {name} substitutions, set/if
var vr_distance := 1.5            ## metres (times vr_text COMFORT 1.6)
var vr_height := -0.28            ## metres below eye level (times COMFORT)
var vr_layers := 1

# --- State ---
var lines: Array = []
var pos := -1                     ## index of the line on screen
var playing := false
var typing := false
var line: Dictionary = {}
var reader: UiInput

var _labels := {}                 ## label name -> index
var _tv: Array = []               ## TvBox nodes
var _tv_roots: Array[Control] = []
var _vr: Node3D = null            ## VrBox
var _vr_cam: Node3D = null
var _vr_hand: Node3D = null
var _vr_world: Node = null
var _shown := 0.0                 ## characters revealed (float for speed)
var _full := ""                   ## current substituted text
var _pause := 0.0                 ## punctuation pause
var _auto := -1.0
var _wait := 0.0
var _hold := 0.0
var _menu: Control = null
var _vr_menu: Node3D = null
var _blip := 0


## Show the dialogue box on a TV view (a UiKit.ui_root, or any Control). Call once per view.
func add_tv_view(root: Control) -> void:
	if root != null and not _tv_roots.has(root):
		_tv_roots.append(root)


## Show it in VR too: the XR camera (placement), the pointing hand (choices) and the world node to put
## the panel in (default: this node's parent).
func set_vr(cam: Node3D, hand: Node3D = null, world: Node = null) -> void:
	_vr_cam = cam
	_vr_hand = hand
	_vr_world = world
	if reader != null:
		reader.hand = hand


## Start a conversation. opts: device, keys, speed, skippable, vars (merged), remote, portraits, start
## (label or index).
func play(script_lines: Array, opts: Dictionary = {}) -> void:
	lines = script_lines.duplicate()
	device = int(opts.get("device", device))
	keys = int(opts.get("keys", keys))
	speed = float(opts.get("speed", speed))
	skippable = bool(opts.get("skippable", skippable))
	remote = bool(opts.get("remote", remote))
	portraits = bool(opts.get("portraits", portraits))
	var v: Dictionary = opts.get("vars", {})
	vars.merge(v, true)
	_labels.clear()
	for i in lines.size():
		var l: Dictionary = lines[i]
		if l.has("label"):
			_labels[String(l["label"])] = i
	reader = UiInput.new(device, keys, _vr_hand)
	reader.latch()
	playing = true
	started.emit()
	var start: Variant = opts.get("start", 0)
	if start is String:
		_run_from(int(_labels.get(start, 0)))
	elif not remote:
		_run_from(int(start))


## One line, then done: `await dlg.say("GUARD", "Halt!", "bad")`-style convenience (returns at once;
## await `finished`).
func say(speaker: String, text: String, color: Variant = null, opts: Dictionary = {}) -> void:
	var l := {"speaker": speaker, "text": text}
	if color != null:
		l["color"] = color
	play([l], opts)


## Advance: finish the typing, or go to the next line.
func advance() -> void:
	if not playing or pos < 0:
		return
	if typing:
		_finish_typing()
		return
	if _has_choices():
		return
	_next()


## Pick choice `i` of the current line (also what the choice menus call).
func choose(i: int) -> void:
	if not playing or pos < 0 or not _has_choices():
		return
	var choices: Array = UiKit.normalize_items(line.get("choices", []))
	if i < 0 or i >= choices.size():
		return
	var c: Dictionary = choices[i]
	_close_menus()
	choice_made.emit(String(c.id), i)
	vars["last_choice"] = String(c.id)
	if c.has("set"):
		var sd: Dictionary = c["set"]
		vars.merge(sd, true)
	if c.has("event"):
		event.emit(String(c["event"]), line)
	if remote:
		return
	if c.has("goto"):
		_jump(String(c["goto"]))
	else:
		_run_from(pos + 1)


## Skip ahead: run side effects (set/event/call) of the lines in between and stop at the next line with
## choices, or the end.
func skip() -> void:
	if not playing or not skippable:
		return
	if typing:
		_finish_typing()
	var i := pos + 1
	if _has_choices():
		return
	while i >= 0 and i < lines.size():
		var l: Dictionary = lines[i]
		if not _condition(l):
			i += 1
			continue
		if l.has("choices") or bool(l.get("end", false)):
			_run_from(i)
			return
		_side_effects(l)
		if l.has("goto"):
			i = int(_labels.get(String(l["goto"]), lines.size()))
		else:
			i += 1
	stop()


## Stop and hide everything (emits finished).
func stop() -> void:
	if not playing:
		return
	playing = false
	typing = false
	pos = -1
	_close_menus()
	for b in _tv:
		if is_instance_valid(b):
			b.call("hide_box")
	_tv.clear()
	if _vr != null and is_instance_valid(_vr):
		_vr.call("hide_box")
	_vr = null
	finished.emit()


## Remote mirrors: show line `index` as-is (no control flow).
func show_line(index: int) -> void:
	if index < 0 or index >= lines.size():
		return
	playing = true
	_display(index)


## True while a conversation is running.
func is_playing() -> bool:
	return playing


# --- Flow ------------------------------------------------------------------------------------------

func _next() -> void:
	if remote:
		advance_requested.emit()
		return
	var l: Dictionary = line
	if bool(l.get("end", false)):
		stop()
		return
	if l.has("goto") and not l.has("choices"):
		_jump(String(l["goto"]))
	else:
		_run_from(pos + 1)


func _jump(label: String) -> void:
	if label == "end" and not _labels.has("end"):
		stop()
		return
	_run_from(int(_labels.get(label, lines.size())))


## Execute control lines from i until a line to display, a wait, or the end.
func _run_from(i: int) -> void:
	var guard := 0
	while i >= 0 and i < lines.size() and guard < 1000:
		guard += 1
		var l: Dictionary = lines[i]
		if not _condition(l):
			i += 1
			continue
		if l.has("text") and String(l["text"]) != "":
			_display(i)
			return
		_side_effects(l)
		if l.has("wait"):
			pos = i
			line = l
			_wait = float(l["wait"])
			_hide_boxes_soft()
			return
		if bool(l.get("end", false)):
			break
		if l.has("goto"):
			var g := String(l["goto"])
			if g == "end" and not _labels.has("end"):
				break
			i = int(_labels.get(g, lines.size()))
		else:
			i += 1
	stop()


func _condition(l: Dictionary) -> bool:
	if not l.has("if"):
		return true
	var cond := String(l["if"])
	var neg := cond.begins_with("!")
	var key := cond.substr(1) if neg else cond
	var val := bool(vars.get(key, false))
	return val != neg


func _side_effects(l: Dictionary) -> void:
	if l.has("set"):
		var sd: Dictionary = l["set"]
		vars.merge(sd, true)
	if l.has("sound") and sounds:
		UiKit.sound(String(l["sound"]))
	if l.has("event"):
		event.emit(String(l["event"]), l)
	if l.has("call"):
		var c: Variant = l["call"]
		if c is Callable:
			(c as Callable).call()


func _has_choices() -> bool:
	return line.has("choices") and not (line["choices"] as Array).is_empty()


func _display(i: int) -> void:
	pos = i
	line = lines[i]
	if not remote:
		_side_effects_display(line)
	_full = _substitute(String(line.get("text", "")))
	_shown = 0.0
	_pause = 0.0
	_blip = 0
	typing = true
	_auto = -1.0
	_close_menus()
	var speaker := _substitute(String(line.get("speaker", "")))
	var col := UiKit.color_of(line.get("color", null), UiKit.ACCENT)
	var portrait := String(line.get("portrait", speaker.substr(0, 1) if speaker != "" else ""))
	if not portraits:
		portrait = ""
	_ensure_boxes()
	for b in _tv:
		b.call("show_line", speaker, col, _full, portrait)
	if _vr != null:
		_vr.call("show_line", speaker, col, _full)
	line_started.emit(i, line)
	if reader != null:
		reader.latch()
	_hold = 0.0


## Side effects that belong to a displayed line (set, sound, event, call) run when it appears.
func _side_effects_display(l: Dictionary) -> void:
	_side_effects(l)


func _substitute(t: String) -> String:
	if t.contains("{"):
		return t.format(vars)
	return t


func _finish_typing() -> void:
	_shown = float(_full.length())
	_set_visible_chars(_full.length())
	_typed()


func _typed() -> void:
	if not typing:
		return
	typing = false
	line_typed.emit(pos)
	for b in _tv:
		b.call("set_done", not _has_choices())
	if _vr != null:
		_vr.call("set_done", not _has_choices())
	if _has_choices():
		_open_choices()
	elif line.has("auto"):
		_auto = float(line["auto"])


func _set_visible_chars(n: int) -> void:
	for b in _tv:
		b.call("set_chars", n)
	if _vr != null:
		_vr.call("set_chars", n)


func _ensure_boxes() -> void:
	# drop views that went away (split-screen re-layout), add missing ones
	var live: Array = []
	for b in _tv:
		if is_instance_valid(b):
			live.append(b)
	_tv = live
	for r in _tv_roots:
		if not is_instance_valid(r):
			continue
		var has := false
		for b in _tv:
			if b.get_parent() == r:
				has = true
		if not has:
			var box := TvBox.new()
			r.add_child(box)
			_tv.append(box)
	if _vr_cam != null and is_instance_valid(_vr_cam) and (_vr == null or not is_instance_valid(_vr)):
		var world: Node = _vr_world if _vr_world != null else get_parent()
		var vb := VrBox.new()
		vb.cam = _vr_cam
		vb.distance = vr_distance
		vb.height = vr_height
		vb.vis_layers = vr_layers
		world.add_child(vb)
		_vr = vb


func _hide_boxes_soft() -> void:
	for b in _tv:
		if is_instance_valid(b):
			b.call("set_hidden", true)
	if _vr != null and is_instance_valid(_vr):
		_vr.call("set_hidden", true)


func _open_choices() -> void:
	var choices: Array = UiKit.normalize_items(line.get("choices", []))
	var chooser := String(line.get("chooser", "tv" if not _tv_roots.is_empty() else "vr"))
	var dev := int(line.get("device", device))
	if chooser == "vr" and _vr_cam != null:
		var world: Node = _vr_world if _vr_world != null else get_parent()
		_vr_menu = VrMenu.open(world, {"items": choices, "cam": _vr_cam, "hand": _vr_hand, "distance": vr_distance,
			"height": vr_height - 0.42, "follow": false, "allow_cancel": false, "layers": vr_layers})
		_vr_menu.connect("chosen", func(id: String, _it: Dictionary) -> void: _on_choice_id(id, choices))
	elif not _tv_roots.is_empty() and is_instance_valid(_tv_roots[0]):
		var root := _tv_roots[0]
		_menu = UiMenu.open(root, {"items": choices, "device": dev, "keys": keys, "allow_cancel": false, "anchor": "bottom_right",
			"margin": 36.0, "width": 520.0, "prompts": false, "desc": false})
		# sit above the dialogue box
		_menu.offset_bottom -= _tv_box_height(root)
		_menu.offset_top -= _tv_box_height(root)
		_menu.connect("chosen", func(id: String, _it: Dictionary) -> void: _on_choice_id(id, choices))
	if remote:
		if _menu != null:
			_menu.set("close_on_choose", false)
		if _vr_menu != null:
			_vr_menu.set("close_on_choose", false)


func _tv_box_height(root: Control) -> float:
	for b in _tv:
		if is_instance_valid(b) and b.get_parent() == root:
			return float(b.call("box_height")) + 24.0 * UiKit.scale_of(root)
	return 260.0


func _on_choice_id(id: String, choices: Array) -> void:
	for k in choices.size():
		if String(choices[k].id) == id:
			if remote:
				choice_requested.emit(k)
			else:
				choose(k)
			return


func _close_menus() -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.call("close")
	_menu = null
	if _vr_menu != null and is_instance_valid(_vr_menu):
		_vr_menu.call("close")
	_vr_menu = null


# --- Per frame -------------------------------------------------------------------------------------

func _input(ev: InputEvent) -> void:
	if reader != null:
		reader.note_event(ev)


func _process(delta: float) -> void:
	if not playing:
		return
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0 and not remote:
			_run_from(pos + 1)
		return
	if typing:
		_type(delta)
	elif _auto > 0.0:
		_auto -= delta
		if _auto <= 0.0:
			_next()
	if reader == null or pos < 0:
		return
	var acts := reader.poll(delta)
	if acts.has("confirm") and _menu == null and _vr_menu == null:
		if remote and not typing:
			advance_requested.emit()
		else:
			advance()
	# hold to skip
	if skippable and not remote and reader.held("confirm") and not _has_choices():
		_hold += delta
		if _hold > 0.2:
			for b in _tv:
				b.call("set_skip", (_hold - 0.2) / maxf(0.1, skip_hold - 0.2))
		if _hold >= skip_hold:
			_hold = 0.0
			for b in _tv:
				b.call("set_skip", 0.0)
			skip()
	elif _hold > 0.0:
		_hold = 0.0
		for b in _tv:
			b.call("set_skip", 0.0)


func _type(delta: float) -> void:
	if _pause > 0.0:
		_pause -= delta
		return
	var sp := float(line.get("speed", speed))
	var before := int(_shown)
	_shown += sp * delta
	var n := mini(int(_shown), _full.length())
	if n > before:
		var ch := _full.substr(n - 1, 1)
		if ".!?".contains(ch) and n < _full.length():
			_pause = 0.22
		elif ",;:".contains(ch):
			_pause = 0.09
		if ch != " " and sounds:
			_blip += 1
			if _blip % 2 == 1:
				UiKit.sound("type", -9.0, float(line.get("pitch", _voice_pitch())))
		_set_visible_chars(n)
	if n >= _full.length():
		_typed()


func _voice_pitch() -> float:
	var sp := String(line.get("speaker", ""))
	if sp == "":
		return 1.0
	return 0.85 + float(sp.hash() % 40) / 100.0


# --- Views -----------------------------------------------------------------------------------------

class TvBox extends Control:
	## The TV dialogue box at the bottom of one view: name pill, portrait disc, typewriter text,
	## a bobbing "next" arrow and the hold-to-skip meter.
	const UiKit := preload("res://core/ui_kit.gd")
	var panel: PanelContainer
	var text: Label
	var name_pill: PanelContainer
	var name_label: Label
	var portrait: PanelContainer
	var portrait_label: Label
	var portrait_icon: Control
	var next_icon: Control
	var skip_box: HBoxContainer
	var skip_bar: Control
	var done := false
	var shown := false
	var t := 0.0
	var _s := 1.0
	var _color := Color.WHITE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_s = UiKit.scale_of(self)
		panel = UiKit.panel("dialogue")
		add_child(panel)
		var row := UiKit.hbox(22, _s)
		panel.add_child(row)
		portrait = PanelContainer.new()
		portrait.custom_minimum_size = Vector2(104, 104) * _s
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(portrait)
		portrait_label = UiKit.label("", "title", null, HORIZONTAL_ALIGNMENT_CENTER)
		portrait.add_child(portrait_label)
		portrait_icon = UiKit.icon("person", "text", 64.0 * _s)
		portrait_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		portrait_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		portrait.add_child(portrait_icon)
		text = UiKit.paragraph("", "body")
		text.add_theme_font_size_override("font_size", UiKit.font_size("body", _s) + int(2 * _s))
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.custom_minimum_size = Vector2(200, UiKit.font_size("body", _s) * 4.2)
		row.add_child(text)
		name_pill = PanelContainer.new()
		name_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(name_pill)
		name_label = UiKit.label("", "heading")
		name_pill.add_child(name_label)
		next_icon = UiKit.icon("arrow_down", "accent", 26.0 * _s)
		add_child(next_icon)
		skip_box = UiKit.hbox(8, _s)
		add_child(skip_box)
		skip_box.add_child(UiKit.label("HOLD TO SKIP", "tiny", "dim"))
		var sb: UiKit.Bar = UiKit.bar("custom", 90.0, 10.0, "accent")
		sb.set_value(0.0, 1.0, false)
		skip_bar = sb
		skip_box.add_child(sb)
		skip_box.modulate.a = 0.0
		panel.resized.connect(_place)
		resized.connect(_place)
		modulate.a = 0.0

	## Width of the box for this view (max 1500 px at scale 1, with margins).
	func _place() -> void:
		var m := 34.0 * _s
		var w := minf(1500.0 * _s, size.x - m * 2.0)
		panel.custom_minimum_size.x = w
		var h := panel.get_combined_minimum_size().y
		panel.size = Vector2(w, h)
		panel.position = Vector2((size.x - w) * 0.5, size.y - h - m)
		name_pill.size = name_pill.get_combined_minimum_size()
		name_pill.position = panel.position + Vector2(36.0 * _s, -name_pill.size.y * 0.6)
		skip_box.size = skip_box.get_combined_minimum_size()
		skip_box.position = panel.position + Vector2(w - skip_box.size.x - 26.0 * _s, 12.0 * _s)

	func box_height() -> float:
		return panel.size.y + 34.0 * _s

	func show_line(speaker: String, col: Color, full: String, portrait_text: String) -> void:
		_color = col
		var speaker_changed := name_label.text != speaker
		name_label.text = speaker
		name_pill.visible = speaker != ""
		name_pill.add_theme_stylebox_override("panel", UiKit.stylebox(col.darkened(0.55), _s, 200.0, col, 3.0, 6.0, Vector2(22, 4)))
		name_label.add_theme_color_override("font_color", col.lightened(0.55))
		panel.add_theme_stylebox_override("panel", UiKit.stylebox(UiKit.BG_DEEP, _s, 24.0, Color(col.r, col.g, col.b, 0.55), 3.0, 22.0, Vector2(34, 26)))
		portrait.visible = portrait_text != ""
		if portrait.visible:
			portrait.add_theme_stylebox_override("panel", UiKit.stylebox(col.darkened(0.35), _s, 200.0, col.lightened(0.3), 4.0, 0.0, Vector2(0, 0)))
			var is_icon := portrait_text.length() > 2
			portrait_icon.visible = is_icon
			portrait_label.visible = not is_icon
			if is_icon:
				portrait_icon.set("kind", portrait_text)
				portrait_icon.set("color", col.lightened(0.6))
			else:
				portrait_label.text = portrait_text.to_upper()
		text.text = full
		text.visible_characters = 0
		done = false
		next_icon.modulate.a = 0.0
		set_hidden(false)
		if speaker_changed and speaker != "":
			UiKit.pulse(name_pill, 1.12)
		_place.call_deferred()

	func set_chars(n: int) -> void:
		text.visible_characters = n

	func set_done(show_next: bool) -> void:
		done = show_next
		text.visible_characters = -1

	func set_skip(frac: float) -> void:
		skip_box.modulate.a = 1.0 if frac > 0.0 else 0.0
		(skip_bar as UiKit.Bar).set_value(clampf(frac, 0.0, 1.0), 1.0, false)

	func set_hidden(h: bool) -> void:
		if h == not shown:
			return
		shown = not h
		var tw := create_tween().set_parallel()
		tw.tween_property(self, "modulate:a", 0.0 if h else 1.0, 0.2)
		if not h:
			var target := panel.position.y
			panel.position.y = target + 40.0 * _s
			tw.tween_property(panel, "position:y", target, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func hide_box() -> void:
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.22)
		tw.tween_callback(queue_free)

	func _process(delta: float) -> void:
		t += delta
		var a := 1.0 if done else 0.0
		next_icon.modulate.a = lerpf(next_icon.modulate.a, a, 1.0 - exp(-12.0 * delta))
		next_icon.size = Vector2(26, 26) * _s
		next_icon.position = panel.position + panel.size - Vector2(52, 44) * _s + Vector2(0, sin(t * 6.0) * 4.0 * _s)


class VrBox extends Node3D:
	## The VR dialogue panel: speaker name, pre-wrapped typewriter text and an "A / TRIGGER" hint,
	## lazily following the view below eye level.
	const UiKit := preload("res://core/ui_kit.gd")
	const W := 1.5
	const H := 0.46
	const TEXT_PX := 64
	var cam: Node3D
	var distance := 1.5
	var height := -0.28
	var vis_layers := 1
	var panel: MeshInstance3D
	var name_l: Label3D
	var text_l: Label3D
	var hint_l: Label3D
	var wrapped := ""
	var shown := false

	func _ready() -> void:
		scale = Vector3.ONE * distance * UiKit.VrText.COMFORT / 2.4
		panel = UiKit.panel3d(Vector2(W, H), UiKit.BG_DEEP)
		add_child(panel)
		name_l = UiKit.label3d("", 0.055, "accent", true)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT  # Label3D: left-aligned text starts at the origin
		name_l.position = Vector3(-W * 0.5 + 0.06, H * 0.5 - 0.06, 0.004)
		add_child(name_l)
		text_l = UiKit.label3d("", 0.05)
		text_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		text_l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		text_l.position = Vector3(-W * 0.5 + 0.07, H * 0.5 - 0.11, 0.004)  # top-left anchored
		add_child(text_l)
		hint_l = UiKit.label3d("A / TRIGGER", 0.028, "dim")
		add_child(hint_l)
		hint_l.position = Vector3(W * 0.5 - 0.17, -H * 0.5 + 0.04, 0.004)
		for c in get_children():
			(c as VisualInstance3D).layers = vis_layers
		if cam != null:
			UiKit.vr_place(self, cam, distance, height)
		_fade(false)

	func show_line(speaker: String, col: Color, full: String) -> void:
		name_l.text = speaker
		name_l.modulate = col.lightened(0.4)
		panel.mesh = UiKit.panel_mesh(Vector2(W, H), UiKit.BG_DEEP, Color(col.r, col.g, col.b, 0.6))
		wrapped = UiKit.wrap_text(full, (W - 0.14) / text_l.pixel_size, text_l.font_size)
		text_l.text = ""
		hint_l.visible = false
		set_hidden(false)

	func set_chars(n: int) -> void:
		# count characters of the original text through the wrapped copy (wrapping swaps spaces for \n)
		var out := wrapped.substr(0, mini(n, wrapped.length()))
		text_l.text = out

	func set_done(show_next: bool) -> void:
		text_l.text = wrapped
		hint_l.visible = show_next

	func set_hidden(h: bool) -> void:
		if h == not shown:
			return
		shown = not h
		_fade(not h)

	func _fade(on: bool) -> void:
		var tw := create_tween().set_parallel()
		for c in get_children():
			var g := c as GeometryInstance3D
			if g != null:
				tw.tween_property(g, "transparency", 0.0 if on else 1.0, 0.2)

	func hide_box() -> void:
		_fade(false)
		get_tree().create_timer(0.25).timeout.connect(queue_free)

	func _process(delta: float) -> void:
		if cam != null and is_instance_valid(cam):
			UiKit.vr_follow(self, cam, distance, height, delta)
