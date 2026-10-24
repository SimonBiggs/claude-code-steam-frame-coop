extends Node
## Headless bot for games/roller_coaster (Coaster Crew).
## BOT_PLAYERS=n: TV riders on virtual pads (default 3). Locally without VR the first pad is P1, the
## builder: it does the practice with A, then builds more through main's functions and rides with Y.
## BOT_VR=1: a fake VR builder does it with its hands (grab tray pieces, drop them at the glowing end,
## pull a hill, drop a star, plop a guest into a car, poke a tree, push the lever, ride along and stop).
## Local:     godot --headless --path . --fixed-fps 60 --quit-after 4800 res://tests/roller_coaster_bot.tscn
## Networked: DUO_PORT=8190 DUO_HOST=1 ... & DUO_PORT=8190 DUO_JOIN=127.0.0.1 ... (same scene, real time)

const BotKit := preload("res://tests/bot_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")
const Track := preload("res://games/roller_coaster/track.gd")

var kit: BotKit
var main: Node
var want := 3
var tasks: Array = []
var task_t := 0.0
var step := 0
var vmin := 99.0
var vmax := 0.0
var saw_ride := false
var saw_vr_ride := false
var saw_lift := false
var guest_rode := false
var poked := 0
var checks: Array = []  # [time, Callable, msg]: asserts a moment after a hand let go


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/roller_coaster/main.tscn").instantiate()
	add_child(main)
	kit.main = main
	want = BotKit.bot_players(3, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	var vr := OS.has_environment("BOT_VR")
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d TV players press A" % want, _join)
	if host or client:
		kit.at(45.0 if client else 52.0, "finish", func() -> void:
			_checks()
			kit.finish())
	elif vr:
		kit.at(2.0, "fake VR: the builder does the practice with its hands", func() -> void:
			for t in ["straight", "left", "up"]:
				tasks.append(["piece", t])
			tasks.append(["touch_lever"]))
		kit.at(9.0, "practice done?", func() -> void:
			kit.assert_eq(main.pieces.size(), 3, "three practice pieces snapped on by hand")
			kit.assert_true(main.phase == "ride", "the lever started the practice ride"))
		kit.every(0.5, _vr_after_ride)
		kit.at(75.0, "finish", func() -> void:
			_checks()
			kit.finish())
	else:
		kit.at(3.0, "P1 presses A three times (practice pieces)", func() -> void: _p1("accept"))
		kit.at(3.5, "", func() -> void: _p1("accept"))
		kit.at(4.0, "", func() -> void: _p1("accept"))
		kit.at(4.6, "practice built?", func() -> void:
			kit.assert_eq(main.pieces.size(), 3, "P1 placed the three glowing practice pieces")
			kit.assert_true(main.practice_piece() == "", "practice is over"))
		kit.at(5.0, "P1 pulls the lever (Y)", func() -> void: _p1("y"))
		kit.at(6.0, "riding?", func() -> void: kit.assert_true(main.phase == "ride", "Y started the practice ride"))
		kit.every(0.5, _pad_after_ride)
		kit.at(70.0, "finish", func() -> void:
			_checks()
			kit.finish())
	kit.every(2.0, _report)


func _join() -> void:
	if main.net.mode == "host":
		return
	for i in want:
		kit.join_bot(main.party)


func _p1(action: String) -> void:
	if main.party.is_active(0):
		kit.slot_press(main.party, 0, action)


## Local pad play: after each ride, build something new (the same functions the hands use).
func _pad_after_ride() -> String:
	if main.phase != "build" or main.rides_done < 1 or step >= 2:
		return ""
	step += 1
	if step == 1:
		var n0: int = main.pieces.size()
		_add_some(["down", "right", "loop", "up", "down", "splash", "right"])
		main.set_end_height(1.5)
		kit.assert_true(main.pieces.size() > n0 + 2, "more pieces snapped on (%d)" % main.pieces.size())
		kit.assert_near(main.last_height(), 1.5, 0.01, "pulled the end up into a hill")
		main.undo_piece()
		main.add_piece("straight")
		main.close_loop()
		kit.assert_true(main.closed, "the close button closed the loop")
		_p1("y")
	return "built round %d" % step


## Add pieces in this order, turning left whenever one would fall off the table.
func _add_some(order: Array) -> void:
	for t in order:
		if not main.add_piece(String(t)):
			main.add_piece("left")


## Fake VR: after the practice ride, more building with the hands, then a ride along.
func _vr_after_ride() -> String:
	if main.phase != "build" or main.rides_done < 1 or not tasks.is_empty():
		return ""
	step += 1
	if step == 1:
		tasks.append(["turn"])
		for t in ["down", "right", "loop", "straight"]:
			tasks.append(["piece", t])
		tasks.append(["wait", 0.4])
		tasks.append(["knob", 1.5])
		tasks.append(["star"])
		tasks.append(["guest"])
		tasks.append(["tree"])
		tasks.append(["touch_seat"])
		tasks.append(["touch_lever"])
		return "VR builds more and asks to ride along"
	return ""


func _physics_process(delta: float) -> void:
	if main == null or not main.ready_to_play:
		return
	if main.phase == "ride":
		saw_ride = true
		vmin = minf(vmin, main.train_v)
		vmax = maxf(vmax, main.train_v)
		if main.train_v <= main.LIFT_V + 0.05:
			saw_lift = true
	for slot in main.party.local_slots():
		if slot == 0 and main.net.mode == "local" and main.phase == "build":
			continue
		kit.slot_hold(main.party, slot, "accept", main.phase == "ride" and fmod(kit.t + slot, 3.0) < 2.0)
	for g in main.guest_state.size():
		if main.guest_state[g] == "ride":
			guest_rode = true
	for c in checks.duplicate():
		if kit.t >= float(c[0]):
			checks.erase(c)
			kit.assert_true((c[1] as Callable).call(), String(c[2]))
	if main.vr_rig != null:
		_drive_vr(delta)


# --- Fake VR hands -----------------------------------------------------------------------------

func _drive_vr(delta: float) -> void:
	var rig: VrRig = main.vr_rig
	if rig.real_head_height() < 1.0:
		kit.vr_head_height(rig, 1.6)
	if main.builder.riding:
		saw_vr_ride = true
		if main.ride_d > 25.0:
			kit.vr_trigger(rig, 1.0)  # stop the ride: back to the table
		return
	if tasks.is_empty():
		kit.vr_trigger(rig, 0.0)
		kit.vr_stick(rig, Vector2.ZERO)
		return
	task_t += delta
	var task: Array = tasks[0]
	var b = main.builder
	match String(task[0]):
		"piece":
			var i: int = b.TRAY_ITEMS.find(String(task[1]))
			var item: Node3D = b.items[i]
			if task.size() == 2:
				kit.vr_trigger(rig, 0.0)
				if _reach(rig, VrRig.RIGHT, item.global_position, delta):
					kit.vr_trigger(rig, 1.0)
					task.append("held")
					task.append(main.pieces.size())
			else:
				var end: Array = main.track["end"]
				var ep: Vector3 = main.park.to_global(end[0])
				if _reach(rig, VrRig.RIGHT, ep + Vector3.UP * 0.4, delta):
					kit.vr_trigger(rig, 0.0)
					var n0 := int(task[3])
					_done_later(func() -> bool: return main.pieces.size() > n0, "snapped a %s on by hand" % task[1])
		"touch_lever":
			_touch(rig, task, b.lever.global_position + Vector3.UP * 1.3, func() -> bool: return main.phase == "ride", "the lever starts the ride", delta)
		"touch_seat":
			_touch(rig, task, b.seat.global_position, func() -> bool: return bool(main.net.state_get("vr_ride", false)), "touching the RIDE car asks to ride along", delta)
		"wait":
			if task_t > float(task[1]):
				tasks.pop_front()
				task_t = 0.0
		"turn":
			kit.vr_stick(rig, Vector2.ZERO, Vector2(1.0, 0.0))
			if task_t > 0.6:
				kit.vr_stick(rig, Vector2.ZERO)
				_done(absf(main.park.rotation.y) > 0.2, "the right stick turns the table")
		"knob":
			if task.size() == 2:
				if _reach(rig, VrRig.RIGHT, b.knob.global_position, delta):
					kit.vr_trigger(rig, 1.0)
					task.append(rig.hand_r.global_position + Vector3.UP * float(task[1]))
			elif _reach(rig, VrRig.RIGHT, task[2], delta, 6.0):
				kit.vr_trigger(rig, 0.0)
				_done_later(func() -> bool: return main.last_height() >= 1.0, "pulled the end up into a hill")
		"star":
			var item: Node3D = b.items[b.TRAY_ITEMS.find("star")]
			if task.size() == 1:
				if _reach(rig, VrRig.RIGHT, item.global_position, delta):
					kit.vr_trigger(rig, 1.0)
					task.append(int((main.net.state_get("stars", []) as Array).size()))
			else:
				var xf := Track.sample(main.track, Track.STATION_LEN + 3.0)
				if _reach(rig, VrRig.RIGHT, main.park.to_global(xf.origin + Vector3.UP * 1.6), delta):
					kit.vr_trigger(rig, 0.0)
					var n0 := int(task[1])
					_done_later(func() -> bool: return (main.net.state_get("stars", []) as Array).size() > n0, "dropped a star by the track")
		"guest":
			if task.size() == 1:
				var gn: Node3D = main.park.guests[0]
				if _reach(rig, VrRig.RIGHT, main.park.to_global(gn.position + Vector3.UP * 0.6), delta):
					kit.vr_trigger(rig, 1.0)
					task.append("held")
			else:
				var car: Node3D = main.train.cars[(main.net.state_get("cars", []) as Array).find(-1)]
				if _reach(rig, VrRig.RIGHT, car.global_position + Vector3.UP * 1.2, delta):
					kit.vr_trigger(rig, 0.0)
					_done_later(func() -> bool: return main.guest_state[0] == "ride", "plopped a guest into a car")
		"tree":
			var tr: Node3D = main.park.trees[2]
			_touch(rig, task, main.park.to_global(tr.position + Vector3.UP * 2.0), func() -> bool:
				return (main.park.springs["tree2"][1] as Vector2).length() > 0.01 or (main.park.springs["tree2"][0] as Vector2).length() > 0.01, "poking a tree makes it sway", delta)
	if task_t > 8.0 and not tasks.is_empty():
		kit.assert_true(false, "VR task timed out: %s" % str(task))
		tasks.pop_front()
		task_t = 0.0


func _reach(rig: VrRig, h: int, world_point: Vector3, delta: float, speed: float = 40.0) -> bool:
	var hand: Node3D = rig.hand(h)
	var off: Vector3 = rig.hand_point(h) - hand.global_position
	kit.vr_reach(rig, h, world_point - off, speed, delta)
	return rig.hand_point(h).distance_to(world_point) < 0.15


## Touch something with the left glove, keep it there a moment, then take the hand away.
func _touch(rig: VrRig, task: Array, at: Vector3, cond: Callable, msg: String, delta: float) -> void:
	if task.size() == 1:
		if _reach(rig, VrRig.LEFT, at, delta):
			task.append(task_t)
	elif task_t - float(task[1]) > 0.2:
		_away(rig)
		_done_later(cond, msg)


func _away(rig: VrRig) -> void:
	rig.hand_l.position = Vector3(-4.0, 20.0, 0.0)


func _done(ok: bool, msg: String) -> void:
	kit.assert_true(ok, msg)
	tasks.pop_front()
	task_t = 0.0


## Let go now, check a moment later (the game sees the release next frame).
func _done_later(cond: Callable, msg: String) -> void:
	checks.append([kit.t + 0.3, cond, msg])
	tasks.pop_front()
	task_t = 0.0


func _report() -> String:
	return "BOT %s: phase %s, pieces %d, rides %d, stars %d, decor %d, cars %s, v %.1f, players %s" % [main.net.mode,
		main.phase, main.pieces.size(), int(main.net.state_get("rides", 0)), int(main.net.state_get("score", 0)),
		int(main.net.state_get("decor", 0)), str(main.net.state_get("cars", [])), main.train_v, str(main.party.active_slots())]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	kit.assert_true(saw_ride, "%s: the train rode" % mode)
	kit.assert_true(int(main.net.state_get("rides", 0)) >= (1 if mode == "client" else 2), "%s: rides finished (%d)" % [mode, int(main.net.state_get("rides", 0))])
	kit.assert_true(int(main.net.state_get("score", 0)) > 0, "%s: stars were grabbed" % mode)
	kit.assert_true(int(main.net.state_get("decor", 0)) >= 1, "%s: the park got a new decoration" % mode)
	kit.assert_true(main.pieces.size() >= 3, "%s: the track has pieces (%d)" % [mode, main.pieces.size()])
	var cars: Array = main.net.state_get("cars", [])
	kit.assert_true(cars.size() >= 4 and main.train.cars.size() == cars.size(), "%s: a car per rider (%d)" % [mode, cars.size()])
	if mode != "host":
		kit.assert_eq(main.party.player_count(), want, "%s: all %d players seated" % [mode, want])
	if mode != "client":
		kit.assert_true(vmax > vmin + 3.0, "%s: speed follows the hills (%.1f..%.1f)" % [mode, vmin, vmax])
		kit.assert_true(saw_lift, "%s: the chain lift pulled the train up" % mode)
	if main.vr_rig != null:
		kit.assert_true(saw_vr_ride, "the VR builder rode along")
		kit.assert_true(not main.builder.riding and is_equal_approx(float(main.vr_rig.world_scale), main.builder.WS), "the trigger stopped the VR ride: back to giant size")
		kit.assert_true(guest_rode, "a guest rode in a car")
