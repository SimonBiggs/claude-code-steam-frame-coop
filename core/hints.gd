extends Node
## "How to play" intro cards per role (VR vs TV) and contextual once-only hints with cooldowns, shown on
## the TV views and in VR. Kids constantly ask "how do I...?": show the intro at the start and a short
## hint the first time something matters (a door, low HP, a new ability).
##
##   const Hints := preload("res://core/hints.gd")
##   var hints := Hints.new()
##   add_child(hints)
##   hints.add_view(ui_root_p2, 2)               # each TV player's view (slot = player index), or -1 shared
##   hints.set_vr(xr_camera, self, hand_r)        # the VR player (slot 0 by default)
##   # with the engine systems: hints.bind_party(party); hints.set_vr_rig(vr_rig, self);
##   # hints.add_view(UiKit.ui_root(split.hud(slot)), slot) for each local seat
##   hints.intro({"title": "DUNGEON DASH", "goal": "Find the key and escape together!",
##       "vr": {"role": "THE KNIGHT", "controls": [["TRIGGER", "Swing your sword"], ["STICK", "Walk"]]},
##       "tv": {"role": "THE WIZARDS", "controls": [["A", "Cast"], ["L-STICK", "Move"]], "tips": ["Stay near the knight!"]}})
##   await hints.intro_done
##   hints.hint("door", "Doors open with a KEY: look for a gold glow!", {"to": "all", "icon": "key"})
##   hints.hint("low_hp", "Low health! Drink a potion (Y).", {"to": 3, "button": "Y", "times": 3, "cooldown": 40})
##
## Targets (opts "to"): "all" (default: every TV view + VR), "tv", "vr", or a player slot (int).

signal intro_done()
signal hint_shown(id: String, target: String)

const UiKit := preload("res://core/ui_kit.gd")
const UiInput := preload("res://core/ui_input.gd")
const HudKit := preload("res://core/hud_kit.gd")
const SAVE_PATH := "user://hints_seen.cfg"

var gap := 6.0                    ## min seconds between two hints on the same screen
var duration := 4.5               ## default seconds a hint stays
var persist := false              ## remember once-only hints across sessions (user://hints_seen.cfg)
var vr_slot := 0                  ## the player slot that is in VR
var device := UiInput.PAD_ANY     ## who can dismiss intro cards
var keys := UiInput.KEYS_ALL

var _views := {}                  ## slot -> Control
var _vr_cam: Node3D = null
var _vr_world: Node = null
var _vr_hand: Node3D = null
var _vr_rig: Node = null
var _party: Node = null
var _seen := {}                   ## "id@target" -> times shown
var _last := {}                   ## "id@target" -> time shown
var _busy := {}                   ## target -> time it is free again
var _queue: Array = []            ## pending hints
var _now := 0.0
var _intro_nodes: Array = []
var _intro_t := 0.0
var _intro_min := 1.5
var _intro_max := 14.0
var _reader: UiInput
var _loaded := false


## Register a TV view: `root` is that view's UiKit.ui_root; slot = the player index it belongs to
## (-1 = a shared screen that shows everyone's hints).
func add_view(root: Control, slot: int = -1) -> void:
	_views[slot] = root


## Remove a view (player left / split screen re-layout).
func remove_view(slot: int) -> void:
	_views.erase(slot)


## Register the VR player: XR camera, the world node to put panels in (default: this node's parent),
## and the hand whose trigger dismisses the intro.
func set_vr(cam: Node3D, world: Node = null, hand: Node3D = null) -> void:
	_vr_cam = cam
	_vr_world = world
	_vr_hand = hand


## Use core/party.gd for dismissing the intro (any seat on this machine) instead of device/keys.
func bind_party(party: Node) -> void:
	_party = party


## Register the VR player through core/vr_rig.gd (camera, right hand, guarded trigger / A).
func set_vr_rig(rig: Node, world: Node = null) -> void:
	_vr_rig = rig
	set_vr(rig.get("camera"), world, rig.get("hand_r"))


## Show a contextual hint (if it hasn't been shown `times` times to that target, isn't cooling down,
## and the screen isn't busy - then it waits in a short queue). opts: to ("all", "tv", "vr", or a slot),
## times (1), cooldown (s before the same hint may repeat, 30), duration, icon (UiKit icon kind),
## button (a glyph such as "A" shown before the text), vr_text (different wording for VR), color,
## priority (higher jumps the queue), force (ignore times/cooldown). Returns true if shown or queued.
func hint(id: String, text: String, opts: Dictionary = {}) -> bool:
	_load()
	var targets := _targets(opts.get("to", "all"))
	var any := false
	for target in targets:
		var key := "%s@%s" % [id, target]
		var times := int(opts.get("times", 1))
		var force := bool(opts.get("force", false))
		if not force:
			if int(_seen.get(key, 0)) >= times:
				continue
			if _now - float(_last.get(key, -9999.0)) < float(opts.get("cooldown", 30.0)):
				continue
			var queued := false
			for q in _queue:
				if String(q.key) == key:
					queued = true
			if queued:
				continue
		_queue.append({"id": id, "key": key, "text": text, "opts": opts, "target": target, "t": _now,
			"priority": int(opts.get("priority", 0))})
		any = true
	_pump()
	return any


## Has this hint already been shown (to anyone, or to `target` such as "vr" / "tv:2" / "tv:-1")?
func was_shown(id: String, target: String = "") -> bool:
	for k in _seen:
		var ks := String(k)
		if ks.begins_with(id + "@") and (target == "" or ks == id + "@" + target):
			return true
	return false


## Forget a hint (or all of them with "") so it can show again.
func reset(id: String = "") -> void:
	for k in _seen.keys():
		if id == "" or String(k).begins_with(id + "@"):
			_seen.erase(k)
			_last.erase(k)
	_save()


## The how-to-play cards: the TV role card on every TV view and the VR role card in VR. data: title,
## goal, tv {role, color, controls [[glyph, text]], tips [String]}, vr {...}, slots {slot: {...}} for
## per-player roles. opts: duration (auto close, 14 s), min_time (1.5 s before A closes it),
## vr_card ("short" = role + goal only, the default since VR text must stay short; "full" = with the
## controls and tips list; "none" = no VR card at all).
func intro(data: Dictionary, opts: Dictionary = {}) -> void:
	_close_intro()
	_intro_t = 0.0
	_intro_min = float(opts.get("min_time", 1.5))
	_intro_max = float(opts.get("duration", 14.0))
	_reader = UiInput.new(device, keys, _vr_hand)
	if _party != null:
		_reader.bind_party(_party, -1)
	if _vr_rig != null:
		_reader.rig = _vr_rig
	_reader.latch()
	for slot in _views:
		var root: Control = _views[slot]
		if not is_instance_valid(root) or (int(slot) == vr_slot and _vr_cam != null):
			continue
		var role: Dictionary = data.get("tv", {})
		var per: Dictionary = data.get("slots", {})
		if per.has(slot):
			role = per[slot]
		var card := _tv_card(root, data, role)
		_intro_nodes.append(card)
	var vr_mode := String(opts.get("vr_card", "short"))
	if _vr_cam != null and is_instance_valid(_vr_cam) and vr_mode != "none":
		var vrole: Dictionary = data.get("vr", data.get("tv", {}))
		_intro_nodes.append(_vr_intro(data, vrole, vr_mode == "full"))
	UiKit.sound("ui_open")
	if _intro_nodes.is_empty():
		intro_done.emit.call_deferred()


## Close the intro cards now.
func dismiss_intro() -> void:
	if _intro_nodes.is_empty():
		return
	_close_intro()
	UiKit.sound("ui_select")
	intro_done.emit()


## True while intro cards are up.
func intro_showing() -> bool:
	return not _intro_nodes.is_empty()


# --- Internals -------------------------------------------------------------------------------------

func _targets(to: Variant) -> Array[String]:
	var out: Array[String] = []
	if to is int:
		var slot: int = to
		if slot == vr_slot and _vr_cam != null:
			out.append("vr")
		elif _views.has(slot):
			out.append("tv:%d" % slot)
		elif _views.has(-1):
			out.append("tv:-1")
		return out
	var s := String(to)
	if s == "all" or s == "tv":
		for slot in _views:
			if int(slot) == vr_slot and _vr_cam != null:
				continue
			out.append("tv:%d" % int(slot))
	if (s == "all" or s == "vr") and _vr_cam != null:
		out.append("vr")
	return out


func _process(delta: float) -> void:
	_now += delta
	if not _queue.is_empty():
		_pump()
	if not _intro_nodes.is_empty():
		_intro_t += delta
		var progress := clampf(1.0 - _intro_t / maxf(0.1, _intro_max), 0.0, 1.0)
		for n in _intro_nodes:
			if is_instance_valid(n) and n.has_meta("timer_bar"):
				var b: UiKit.Bar = n.get_meta("timer_bar")
				if is_instance_valid(b):
					b.set_value(progress, 1.0, false)
		var acts := _reader.poll(delta) if _reader != null else PackedStringArray()
		if _intro_t >= _intro_max or (_intro_t >= _intro_min and (acts.has("confirm") or acts.has("cancel"))):
			dismiss_intro()


func _input(ev: InputEvent) -> void:
	if _reader != null:
		_reader.note_event(ev)


func _pump() -> void:
	# drop stale hints (the moment has passed), best priority first
	_queue = _queue.filter(func(q: Dictionary) -> bool: return _now - float(q.t) < 12.0)
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.priority) > int(b.priority))
	var keep: Array = []
	for q in _queue:
		var target := String(q.target)
		if _now < float(_busy.get(target, 0.0)) or (not _intro_nodes.is_empty()):
			keep.append(q)
			continue
		_show(q)
	_queue = keep


func _show(q: Dictionary) -> void:
	var opts: Dictionary = q.opts
	var target := String(q.target)
	var dur := float(opts.get("duration", duration))
	var col := UiKit.color_of(opts.get("color", "info"), UiKit.INFO)
	var text := String(q.text)
	if target == "vr":
		if _vr_cam == null or not is_instance_valid(_vr_cam):
			return
		var world: Node = _vr_world if _vr_world != null else get_parent()
		var vt := String(opts.get("vr_text", text))
		HudKit.vr_toast(world, _vr_cam, vt, {"duration": dur, "color": col, "height": -0.36})
	else:
		var slot := int(target.substr(3))
		var root: Control = _views.get(slot, null)
		if root == null or not is_instance_valid(root):
			return
		var pill := HintPill.new()
		pill.text = text
		pill.icon_kind = String(opts.get("icon", "" if opts.has("button") else "question"))
		pill.button = String(opts.get("button", ""))
		pill.accent = col
		pill.duration = dur
		root.add_child(pill)
	UiKit.sound("ui_notify", -8.0, 1.12)
	_seen[q.key] = int(_seen.get(q.key, 0)) + 1
	_last[q.key] = _now
	_busy[target] = _now + dur + gap * 0.5
	_save()
	hint_shown.emit(String(q.id), target)


func _tv_card(root: Control, data: Dictionary, role: Dictionary) -> Control:
	var s := UiKit.scale_of(root)
	var col := UiKit.color_of(role.get("color", "accent"), UiKit.ACCENT)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := UiKit.tinted_panel(col, s, "accent")
	holder.add_child(card)
	var v := UiKit.vbox(12, s)
	card.add_child(v)
	v.add_child(UiKit.title(String(data.get("title", "HOW TO PLAY"))))
	if role.has("role"):
		var rr := UiKit.hbox(10, s)
		rr.alignment = BoxContainer.ALIGNMENT_CENTER
		rr.add_child(UiKit.label("YOU ARE", "small", "dim"))
		var rl := UiKit.label(String(role["role"]), "heading", col.lightened(0.3))
		rr.add_child(rl)
		v.add_child(rr)
	var goal := String(role.get("goal", data.get("goal", "")))
	if goal != "":
		var gl := UiKit.paragraph(goal, "body", null, HORIZONTAL_ALIGNMENT_CENTER)
		gl.custom_minimum_size.x = 640.0 * s
		v.add_child(gl)
	var controls: Array = role.get("controls", [])
	if not controls.is_empty():
		var grid := GridContainer.new()
		grid.columns = 2 if controls.size() > 3 else 1
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_theme_constant_override("h_separation", int(28 * s))
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		for c in controls:
			var pair: Array = c
			var row := UiKit.hbox(12, s)
			row.add_child(UiKit.glyph(String(pair[0]), s))
			row.add_child(UiKit.label(String(pair[1]), "body"))
			grid.add_child(row)
		var cp := UiKit.panel("tooltip")
		cp.add_child(grid)
		v.add_child(cp)
	var tips: Array = role.get("tips", [])
	for tip in tips:
		var th := UiKit.hbox(8, s)
		th.alignment = BoxContainer.ALIGNMENT_CENTER
		var ic := UiKit.icon("star", "gold", 20.0 * s)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		th.add_child(ic)
		th.add_child(UiKit.label(String(tip), "small", "dim"))
		v.add_child(th)
	var g := _reader.glyphs() if _reader != null else UiInput.new(device, keys).glyphs()
	v.add_child(UiKit.prompts([[String(g["confirm"]), "Got it!"]], s))
	var bar: UiKit.Bar = UiKit.bar("custom", 360.0, 8.0, col)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.set_value(1.0, 1.0, false)
	v.add_child(bar)
	holder.set_meta("timer_bar", bar)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size.x = minf(820.0 * s, root.size.x * 0.94 if root.size.x > 10.0 else 820.0 * s)
	UiKit.pop_in(card, 0.05)
	dim.modulate.a = 0.0
	UiKit.fade(dim, 1.0, 0.25)
	return holder


func _vr_intro(data: Dictionary, role: Dictionary, full: bool = false) -> Node3D:
	var world: Node = _vr_world if _vr_world != null else get_parent()
	var lines: PackedStringArray = []
	if role.has("role"):
		lines.append("YOU ARE " + String(role["role"]))
	var goal := String(role.get("goal", data.get("goal", "")))
	if goal != "":
		lines.append(goal)
	if full:
		lines.append("")
		for c in role.get("controls", []):
			var pair: Array = c
			lines.append("%s:  %s" % [String(pair[0]), String(pair[1])])
		for tip in role.get("tips", []):
			lines.append("* " + String(tip))
	lines.append("")
	lines.append("TRIGGER: got it!")
	var col := UiKit.color_of(role.get("color", "accent"), UiKit.ACCENT)
	return HudKit.vr_card(world, _vr_cam, String(data.get("title", "HOW TO PLAY")), "\n".join(lines),
		{"width": 1.5, "color": col, "distance": 1.6, "height": 0.0, "body_size": 0.046})


func _close_intro() -> void:
	for n in _intro_nodes:
		if not is_instance_valid(n):
			continue
		if n is Control:
			var c := n as Control
			var t := c.create_tween()
			t.tween_property(c, "modulate:a", 0.0, 0.2)
			t.tween_callback(c.queue_free)
		elif n.has_method("hide_card"):
			n.call("hide_card")
	_intro_nodes.clear()
	_reader = null


func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not persist:
		return
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK and cfg.has_section("seen"):
		for k in cfg.get_section_keys("seen"):
			_seen[k] = int(cfg.get_value("seen", k, 0))


func _save() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	for k in _seen:
		cfg.set_value("seen", String(k), int(_seen[k]))
	cfg.save(SAVE_PATH)


class HintPill extends Control:
	## A hint at the bottom of one TV view: glyph/icon + text in an info pill, with a draining line.
	const UiKit := preload("res://core/ui_kit.gd")
	var text := ""
	var icon_kind := "question"
	var button := ""
	var accent := Color.WHITE
	var duration := 4.5
	var t := 0.0
	var _card: PanelContainer
	var _line: Control
	var _s := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_s = UiKit.scale_of(self)
		_card = UiKit.tinted_panel(accent, _s, "toast")
		add_child(_card)
		var h := UiKit.hbox(12, _s)
		_card.add_child(h)
		if button != "":
			var g := UiKit.glyph(button, _s)
			g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(g)
		elif icon_kind != "":
			var ic := UiKit.icon(icon_kind, accent, 34.0 * _s)
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(ic)
		var l := UiKit.label(text, "body")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var max_w := 900.0 * _s
		var tw := UiKit.font(false).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.font_size("body", _s)).x
		l.custom_minimum_size.x = minf(tw + 4.0, max_w)
		h.add_child(l)
		_line = ColorRect.new()
		(_line as ColorRect).color = Color(accent.r, accent.g, accent.b, 0.8)
		_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_line)
		modulate.a = 0.0

	func _process(delta: float) -> void:
		t += delta
		var cs := _card.get_combined_minimum_size()
		var w := minf(cs.x, size.x * 0.94)
		_card.size = Vector2(w, cs.y)
		var rise := 1.0 - pow(1.0 - clampf(t / 0.3, 0.0, 1.0), 3.0)
		var y := size.y * 0.74 - cs.y * 0.5 + (1.0 - rise) * 30.0 * _s
		_card.position = Vector2((size.x - w) * 0.5, y)
		var left := clampf(1.0 - t / duration, 0.0, 1.0)
		_line.position = _card.position + Vector2(18.0 * _s, cs.y - 6.0 * _s)
		_line.size = Vector2((w - 36.0 * _s) * left, maxf(2.0, 3.0 * _s))
		var a := minf(1.0, t / 0.2)
		if t > duration:
			a = 1.0 - (t - duration) / 0.3
		modulate.a = clampf(a, 0.0, 1.0)
		if t > duration + 0.3:
			queue_free()
