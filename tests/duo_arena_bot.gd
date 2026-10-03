extends Node
## Headless bot for Duo Arena party mode. Every local player aims at the nearest enemy and fires.
## BOT_PLAYERS=N: total TV players to have (local split screen: P1 + P2 + drop-ins, up to 6;
## TV machine (DUO_JOIN): P2 + drop-ins, up to 6). In local mode it also joins one player with a fake
## controller (A press), unplugs it briefly (rejoins), then unplugs it for good (it leaves).

const FAKE_PAD := 40

var main
var t := 0.0
var joined := false
var report_t := 0.0
var pad_step := 0
var target := 2


func _ready() -> void:
	main = load("res://games/duo_arena/main.tscn").instantiate()
	add_child(main)
	if not OS.has_environment("DUO_JOIN") and not OS.has_environment("DUO_HOST"):
		for k in [KEY_SPACE, KEY_ENTER]:
			_key(k, true)
	elif OS.has_environment("DUO_HOST"):
		_key(KEY_SPACE, true)


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _pad_press(device: int, button: JoyButton) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = device
		e.button_index = button
		e.pressed = down
		Input.parse_input_event(e)


func _local_players() -> Array:
	return main.players.filter(func(p) -> bool: return not p.vr and not p.remote and not p.ghost)


func _physics_process(delta: float) -> void:
	t += delta
	if main == null or not main.ready_to_play:
		return
	var mode: String = main.net.mode
	if not joined and t > (3.0 if mode == "client" else 1.0):
		joined = true
		_join_players(mode)
	if mode == "local" and joined:
		_pad_script()
	for p in main.players:
		if p.vr or p.remote or p.ghost or not p.active:
			continue
		p.force_fire = p.index >= 2 or mode == "client"
		_aim(p)
	report_t -= delta
	if report_t <= 0.0:
		report_t = 4.0
		_report(mode)


func _join_players(mode: String) -> void:
	var want := int(OS.get_environment("BOT_PLAYERS")) if OS.has_environment("BOT_PLAYERS") else (2 if mode == "local" else 1)
	if mode == "host":
		return
	var have := 2 if mode == "local" else 1
	target = clampi(want, have, 6)
	print("BOT: %s mode, joining %d extra TV players" % [mode, target - have])
	var extra := target - have
	if mode == "local" and extra > 0:
		_pad_press(FAKE_PAD, JOY_BUTTON_START)  # a new controller presses Start: joins (no pause menu)
		extra -= 1
	for i in extra:
		var p = main.debug_join()
		print("BOT: debug_join -> %s" % ("P%d" % (p.index + 1) if p != null else "none"))


## Local mode: unplug the fake controller briefly (rejoin), then for good (leave after 20 s), then replug.
func _pad_script() -> void:
	if not main.joy_owner.has(FAKE_PAD) and pad_step == 0:
		return
	if pad_step == 0 and t > 2.0 and not has_meta("checked"):
		set_meta("checked", true)
		print("BOT: fake controller %d drives P%d, paused=%s" % [FAKE_PAD, int(main.joy_owner.get(FAKE_PAD, -1)) + 1, get_tree().paused])
	if pad_step == 0 and t > 8.0:
		pad_step = 1
		print("BOT: unplug controller %d" % FAKE_PAD)
		main._on_joy_changed(FAKE_PAD, false)
	elif pad_step == 1 and t > 10.0:
		pad_step = 2
		main._on_joy_changed(FAKE_PAD, true)
		print("BOT: replugged, controller %d drives P%d" % [FAKE_PAD, int(main.joy_owner.get(FAKE_PAD, -1)) + 1])
	elif pad_step == 2 and t > 12.0:
		pad_step = 3
		print("BOT: unplug controller %d for good" % FAKE_PAD)
		main._on_joy_changed(FAKE_PAD, false)
	elif pad_step == 3 and t > 34.0:
		pad_step = 4
		print("BOT: after 22 s unplugged: active players %d" % main.active_player_count())
		main._on_joy_changed(FAKE_PAD, true)
	elif pad_step == 4 and t > 35.0:
		pad_step = 5
		print("BOT: replugged after leaving: active players %d" % main.active_player_count())


func _aim(p) -> void:
	var best = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		var dd: float = e.global_position.distance_to(p.global_position)
		if dd < best_d:
			best_d = dd
			best = e
	if best == null:
		return
	var d: Vector3 = best.global_position + Vector3.UP * best.radius - (p.global_position + Vector3.UP * 1.55)
	var flat := Vector2(d.x, d.z).length()
	if flat > 0.1:
		p.yaw = atan2(-d.x, -d.z)
		p.pitch = atan2(d.y, flat)


func _report(mode: String) -> void:
	var act: Array[String] = []
	for p in main.players:
		if p.active:
			act.append("P%d%s%s" % [p.index + 1, "(down)" if p.is_down else "", "[ghost]" if p.ghost and p.index > 0 else ""])
	var views := 0
	var cell := Vector2.ZERO
	for p in _local_players():
		if p.has_meta("view") and p.get_meta("view").visible:
			views += 1
			cell = p.get_meta("view").size
	var synced := 0
	for p in main.players:
		if p.remote and p.active and p.net_started:
			synced += 1
	if mode == "host":
		print("BOT host: %d active TV players are sending their position" % synced)
	elif views > 0:
		print("BOT view cell %s" % cell)
	print("BOT %s t=%.0f wave=%d score=%d enemies=%d slots=%d active=%s views=%d" % [mode, t, main.wave, main.score,
		get_tree().get_nodes_in_group("enemies").size(), main.players.size(), ", ".join(act), views])
