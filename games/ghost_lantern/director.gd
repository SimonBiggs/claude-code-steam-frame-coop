extends Node
## Ghost Lantern director: night events (thunderstorm, ghost party, treat time), treats, per-player stats
## and end-of-night awards, the LAST CHANCE rescue, the once-a-night lantern relight, short hints on the
## TV and in VR, and the sunrise when the family survives the last night. The host decides; the TV
## machine mirrors pack()/unpack() and gets one-off events ("hint", "lightning").

const VrText := preload("res://core/vr_text.gd")

const EVENTS := {
	"storm": ["THUNDERSTORM!", "Lightning shows EVERY ghost for a moment - vacuum fast when it flashes!", 18.0],
	"party": ["GHOST PARTY!", "The ghosts are dancing in the BALLROOM - they're dizzy and easy to catch!", 14.0],
	"treats": ["TREAT TIME!", "Candy appeared around the mansion - grab it for courage and points!", 22.0],
}
const KIND_HINTS := {
	"thief": "THIEVES (bandit masks) steal photos! Stun them in the light or vacuum them to save it.",
	"spooker": "SPOOKERS (witch hats) say BOO! Too many BOOs and you're spooked - friends cheer you up.",
	"sprite": "SPRITES are tiny and fast - follow the lantern light!",
	"shy": "SHY GHOSTS hide from normal light! Lantern: hold the TRIGGER to FOCUS the beam on them!",
	"snuffer": "SNUFFERS (floating brass hats!) want to blow out the lantern - vacuum them first!",
	"golden": "A GOLDEN GHOST! Worth 500 points - follow its sparkles and catch it before it escapes!",
	"king": "THE GHOST KING has your lost photos! Light him up and vacuum him TOGETHER to get them back!",
}
const AWARDS := [
	["GHOSTBUSTER", "caught"],
	["PHOTO HERO", "saved"],
	["CHEERLEADER", "cheers"],
	["LIGHT BRINGER", "stuns"],
	["BELL RINGER", "bells"],
	["CANDY COLLECTOR", "treats"],
	["NEVER GIVES UP", "spooked"],
]
const TV_HOWTO := "HOW TO PLAY: ghosts only show up in the LANTERN light! TV players: hold RT to VACUUM a lit-up " \
	+ "ghost. Save the family photos from the thieves, and stand next to spooked friends to cheer them up."
const VR_HOWTO := "HOW TO PLAY (LANTERN)\nPoint your RIGHT hand: ghosts only appear in your light!\n" \
	+ "Hold a ghost in the beam to STUN it  -  TRIGGER = focused beam\nSHAKE your LEFT hand to ring the bell: ghosts flee\n" \
	+ "LEFT STICK walk  -  RIGHT STICK turn"

var main
var event_name := ""
var event_t := 0.0
var pending_event := ""
var pending_t := 0.0
var last_event := ""
var lightning_t := 0.0
var treats := {}  # id -> Node3D (host: real, client: mirrors)
var stats := {}
var told := {}
var last_chance_t := 0.0  # > 0: catch the king before it runs out
var last_chance_used := false
var relight_t := 0.0
var relight_night := -1
var dawn := 0.0
var won := false
# UI
var layer: CanvasLayer
var hint_label: Label
var timer_label: Label
var hint_3d: Label3D
var hint_tween: Tween


func _ready() -> void:
	name = "Director"


func tick(delta: float) -> void:
	_ensure_ui()
	if main.net.mode != "client" and not main.game_over:
		_host_tick(delta)
	main.storm_flash = maxf(0.0, main.storm_flash - delta * 2.2)
	var want_dawn := 1.0 if won and main.in_break and main.night == main.FINAL_NIGHT else 0.0
	dawn = move_toward(dawn, want_dawn, delta * 0.25)
	_animate_treats(delta)
	_update_ui()


func _host_tick(delta: float) -> void:
	if pending_event != "":
		pending_t -= delta
		if pending_t <= 0.0:
			var ev := pending_event
			pending_event = ""
			start_event(ev)
	if event_name != "":
		event_t -= delta
		if event_name == "storm":
			lightning_t -= delta
			if lightning_t <= 0.0:
				lightning_t = randf_range(2.2, 3.8)
				lightning()
		if event_name == "treats":
			_collect_treats()
		if event_t <= 0.0:
			end_event()
	if last_chance_t > 0.0:
		last_chance_t -= delta
		if last_chance_t <= 0.0:
			last_chance_t = 0.0
			main._on_game_over("The Ghost King kept every photo!")
	if relight_t > 0.0:
		relight_t -= delta
		if relight_t <= 0.0:
			_relight()


# --- Nights & events ------------------------------------------------------------

func on_night_started(night: int, king_night: bool) -> void:
	end_event()
	relight_night = -1
	if night >= 2 and not king_night and night != main.FINAL_NIGHT:
		var choices: Array[String] = ["storm", "party", "treats"]
		choices.erase(last_event)
		pending_event = choices.pick_random()
		pending_t = 9.0


func on_night_ended() -> void:
	end_event()
	pending_event = ""


func start_event(ev: String) -> void:
	if not EVENTS.has(ev) or main.net.mode == "client":
		return
	end_event()
	var info: Array = EVENTS[ev]
	event_name = ev
	event_t = info[2]
	last_event = ev
	print("Event: %s" % ev)
	main._show_center(info[0], 2.0)
	hint(info[1], 5.0)
	match ev:
		"storm":
			lightning_t = 1.0
		"party":
			main.sound("clear", -2.0, 1.5)
		"treats":
			for i in 8:
				_spawn_treat()


func end_event() -> void:
	if event_name == "":
		return
	print("Event over: %s" % event_name)
	if event_name == "treats" and main.net.mode != "client":
		for id in treats.keys():
			var n: Node3D = treats[id]
			if is_instance_valid(n):
				n.queue_free()
		treats.clear()
	event_name = ""


## A flash of lightning: every ghost shows up for a moment (both machines).
func lightning() -> void:
	main.storm_flash = 1.0
	main.local_sound("thunder", -2.0, randf_range(0.8, 1.1))
	if main.net.mode == "host":
		main.net.event("lightning", [])


# --- Treats ---------------------------------------------------------------------

func _spawn_treat() -> void:
	var id: int = main.next_net_id()
	var pos := Vector3(randf_range(-19.0, 19.0), 0.0, randf_range(-6.5, 6.5))
	for x in [-7.0, 7.0]:
		if absf(pos.x - x) < 0.6:
			pos.x += 1.0  # not inside the interior walls
	treats[id] = _make_treat(pos, id)


func _make_treat(pos: Vector3, id: int) -> Node3D:
	var n := Node3D.new()
	main.add_child(n)
	n.position = pos + Vector3.UP * 0.7
	var cols: Array[Color] = [Color(1.0, 0.35, 0.55), Color(0.45, 0.85, 1.0), Color(1.0, 0.8, 0.3), Color(0.6, 1.0, 0.5)]
	var col: Color = cols[id % cols.size()]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 1.6
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.24
	sm.radial_segments = 10
	sm.rings = 5
	var ball := MeshInstance3D.new()
	ball.mesh = sm
	ball.material_override = m
	n.add_child(ball)
	var wrap := CylinderMesh.new()
	wrap.top_radius = 0.0
	wrap.bottom_radius = 0.1
	wrap.height = 0.16
	wrap.radial_segments = 6
	for sx in [-1.0, 1.0]:
		var w := MeshInstance3D.new()
		w.mesh = wrap
		w.material_override = m
		w.position.x = sx * 0.2
		w.rotation.z = sx * PI / 2.0
		n.add_child(w)
	n.set_meta("t", randf() * 6.0)
	return n


func _animate_treats(delta: float) -> void:
	for id in treats.keys():
		var n: Node3D = treats[id]
		if not is_instance_valid(n):
			continue
		var tt: float = float(n.get_meta("t", 0.0)) + delta
		n.set_meta("t", tt)
		n.rotation.y = tt * 2.0
		n.position.y = 0.7 + sin(tt * 3.0) * 0.12


func _collect_treats() -> void:
	for id in treats.keys():
		var n: Node3D = treats[id]
		if not is_instance_valid(n):
			treats.erase(id)
			continue
		for p in main.players:
			if not p.active or p.is_down:
				continue
			var near: bool = Vector2(p.global_position.x - n.position.x, p.global_position.z - n.position.z).length() < 0.9
			if p.vr:
				near = near or p.hand_l.global_position.distance_to(n.global_position) < 0.4 \
					or p.hand_r.global_position.distance_to(n.global_position) < 0.4
			if near:
				p.courage = minf(p.MAX_COURAGE, p.courage + 25.0)
				main.score += 50
				add_stat(p, "treats", 1)
				main.popup(n.global_position + Vector3.UP * 0.4, "YUM! +COURAGE", Color(1.0, 0.8, 0.4))
				main.burst(n.global_position, Color(1.0, 0.7, 0.4), 12, 0.06)
				main.sound("pickup", -3.0, 1.4)
				n.queue_free()
				treats.erase(id)
				break


# --- Last chance & relight -------------------------------------------------------

## Every photo is gone: instead of ending, the Ghost King grabs them all - catch him in time!
func try_last_chance() -> bool:
	if last_chance_used or main.net.mode == "client":
		return false
	last_chance_used = true
	last_chance_t = 50.0
	var king = main.ensure_king()
	main.give_king_lost_photos(king)
	main._show_center("LAST CHANCE!\nThe GHOST KING has ALL the photos!\nCatch him in 50 seconds!", 3.5)
	hint("Light up the GHOST KING (look for the golden crown) and vacuum him TOGETHER!", 6.0)
	main.sound("wave", 0.0, 0.6)
	print("Last chance started")
	return true


func on_king_caught() -> void:
	if last_chance_t > 0.0:
		last_chance_t = 0.0
		main._show_center("YOU SAVED THE PHOTOS!\nThe hunt goes on!", 3.0)
		main.sound("clear", 0.0, 1.0)
		print("Last chance won")


## Everyone is spooked: once per night the lantern flickers back to life and P1 gets up again.
func try_relight() -> bool:
	if main.net.mode == "client" or relight_night == main.night or relight_t > 0.0:
		return relight_t > 0.0
	relight_night = main.night
	relight_t = 3.0
	main._show_center("Hold on…\nThe lantern flickers…", 2.5)
	return true


func _relight() -> void:
	var p = main.players[0] if main.players[0].active else main.players[1]
	if p.is_down:
		p.revive(0.6)
	main._show_center("THE LANTERN SHINES AGAIN!\nCheer each other up!", 2.5)
	hint("Stand next to a spooked friend to cheer them up!", 4.0)


# --- Stats & awards ---------------------------------------------------------------

func add_stat(p, key: String, amount: int) -> void:
	if p == null or not is_instance_valid(p) or main.net.mode == "client":
		return
	var idx: int = p.index
	if not stats.has(idx):
		stats[idx] = {}
	var d: Dictionary = stats[idx]
	d[key] = int(d.get(key, 0)) + amount


func get_stat(idx: int, key: String) -> int:
	if not stats.has(idx):
		return 0
	return int(stats[idx].get(key, 0))


func awards_text() -> String:
	var active: Array = main.players.filter(func(p) -> bool: return p.active)
	if active.is_empty():
		return ""
	var given := {}
	for p in active:
		given[p.index] = []
	for aw in AWARDS:
		var key: String = aw[1]
		var best = null
		var best_v := 0
		for p in active:
			var v := get_stat(p.index, key)
			var mine: Array = given[p.index]
			if v > best_v and mine.size() < 2:
				best_v = v
				best = p
		if best != null:
			given[best.index].append(aw[0])
	var lines: Array[String] = ["* AWARDS *"]
	for p in active:
		var mine: Array = given[p.index]
		if mine.is_empty():
			mine.append("GHOST HUNTER")
		var who := "P%d%s" % [p.index + 1, " (lantern)" if p.index == 0 else ""]
		lines.append("%s  %s  (%d caught)" % [who, " + ".join(PackedStringArray(mine)), get_stat(p.index, "caught")])
	return "\n".join(lines)


# --- Hints -----------------------------------------------------------------------

func hint(text: String, duration: float = 4.0, key: String = "") -> void:
	if key != "":
		if told.has(key):
			return
		told[key] = true
	if main.net.mode == "host":
		main.net.event("hint", [text, duration])
	show_hint(text, duration)


func on_ghost_spawned(kind: String) -> void:
	if KIND_HINTS.has(kind):
		hint(KIND_HINTS[kind], 5.0, "kind_" + kind)


func howto() -> void:
	var tv_ready: bool = main.net.mode != "host" or main.net.connected
	if not told.has("howto_tv") and tv_ready:
		told["howto_tv"] = true
		if main.net.mode == "host":
			main.net.event("hint", [TV_HOWTO, 12.0])
		if not _vr():
			show_hint(TV_HOWTO, 12.0)
	if not told.has("howto_vr") and _vr():
		told["howto_vr"] = true
		show_hint(VR_HOWTO, 16.0)


func show_hint(text: String, duration: float) -> void:
	_ensure_ui()
	hint_label.text = text
	var nodes: Array = [hint_label]
	if _vr():
		if hint_3d == null:
			hint_3d = Label3D.new()
			hint_3d.font_size = 40
			hint_3d.outline_size = 26
			hint_3d.outline_modulate = Color.BLACK
			hint_3d.pixel_size = 0.0022
			hint_3d.no_depth_test = false
			hint_3d.render_priority = 10
			hint_3d.outline_render_priority = 9
			hint_3d.width = 1100.0
			hint_3d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint_3d.modulate = Color(1.0, 0.9, 0.6)
			main.add_child(hint_3d)
			main.players[0]._set_layers(hint_3d, main.players[0].viewmodel_layer())
		hint_3d.text = text
		VrText.follow(hint_3d, main.players[0].xr_camera, main, -0.62, 1.7)
		nodes.append(hint_3d)
	if hint_tween:
		hint_tween.kill()
	hint_tween = create_tween().set_parallel()
	for n in nodes:
		n.modulate.a = 1.0
		hint_tween.tween_property(n, "modulate:a", 0.0, 0.5).set_delay(duration)
	if hint_3d != null and _vr():
		hint_3d.outline_modulate = Color(0, 0, 0, 1)
		hint_tween.tween_property(hint_3d, "outline_modulate:a", 0.0, 0.5).set_delay(duration)


# --- Network ------------------------------------------------------------------

func pack() -> Array:
	var tr := []
	for id in treats.keys():
		var n: Node3D = treats[id]
		if is_instance_valid(n):
			tr.append([id, n.position])
	return [event_name, last_chance_t, won, tr]


func unpack(a: Array) -> void:
	if a.size() < 4:
		return
	event_name = a[0]
	last_chance_t = a[1]
	won = a[2]
	var seen := {}
	for item in a[3]:
		var id: int = item[0]
		seen[id] = true
		if not treats.has(id) or not is_instance_valid(treats[id]):
			var pos: Vector3 = item[1]
			treats[id] = _make_treat(Vector3(pos.x, 0.0, pos.z), id)
	for id in treats.keys():
		if not seen.has(id):
			var n: Node3D = treats[id]
			if is_instance_valid(n):
				n.queue_free()
			treats.erase(id)


func client_event(kind: String, args: Array) -> void:
	match kind:
		"hint":
			show_hint(args[0], args[1])
		"lightning":
			main.storm_flash = 1.0
			main.local_sound("thunder", -2.0, randf_range(0.8, 1.1))


# --- UI -------------------------------------------------------------------------

func _vr() -> bool:
	return not main.players.is_empty() and main.players[0].vr


func _ensure_ui() -> void:
	if layer != null and is_instance_valid(layer):
		return
	layer = CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	hint_label = main._make_label(28)
	hint_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(hint_label)
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.offset_left = -820
	hint_label.offset_right = 820
	hint_label.offset_top = -190
	hint_label.offset_bottom = -60
	hint_label.modulate.a = 0.0
	timer_label = main._make_label(40)
	timer_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(timer_label)
	timer_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	timer_label.offset_left = -400
	timer_label.offset_right = 400
	timer_label.offset_top = 150
	timer_label.offset_bottom = 200


func _update_ui() -> void:
	timer_label.visible = last_chance_t > 0.0
	if last_chance_t > 0.0:
		timer_label.text = "CATCH THE GHOST KING: %d s" % ceili(last_chance_t)
	if hint_3d != null and _vr():
		VrText.follow(hint_3d, main.players[0].xr_camera, main, -0.62, 1.7)
