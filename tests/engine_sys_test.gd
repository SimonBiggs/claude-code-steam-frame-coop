extends Node
## Headless test of the engine systems: core/party.gd, core/split_view.gd, core/vr_rig.gd (fake VR
## through tests/bot_kit.gd), core/camera_rig.gd, core/save.gd and core/net.gd's additions.
## Local run (all modules, deterministic):
##   godot --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/engine_sys_test.tscn
## Networked state store + party joins + requests + shared pause (real ENet, real time):
##   DUO_PORT=7990 DUO_HOST=1 ENGINE_NET=1 godot --headless --path . res://tests/engine_sys_test.tscn &
##   DUO_PORT=7990 DUO_JOIN=127.0.0.1 ENGINE_NET=1 godot --headless --path . res://tests/engine_sys_test.tscn
## Passing runs print "BOT RESULT: PASS"; failures print SCRIPT ERROR lines.

const BotKit := preload("res://tests/bot_kit.gd")
const NetScript := preload("res://core/net.gd")
const Party := preload("res://core/party.gd")
const SplitView := preload("res://core/split_view.gd")
const VrRig := preload("res://core/vr_rig.gd")
const CameraRig := preload("res://core/camera_rig.gd")
const Save := preload("res://core/save.gd")
const PauseMenu := preload("res://core/pause_menu.gd")

var kit: BotKit
var main: TestMain
var party: Party
var split: SplitView
var rig: VrRig
var crig: CameraRig
var pads := {}  # name -> device
var joined_log: Array = []
var left_log: Array = []
var refused_log: Array = []
var lost_log: Array = []
var restored_log: Array = []
var refits: Array = []
var state_log: Array = []
var saved_count := 0
var mark := {}  # scratch values between steps
var target: Node3D
var wall: StaticBody3D
var t1: Node3D
var t2: Node3D
var net_t0 := -1.0
var net_done := false


## Stands in for a game's main.gd (engine-style: no players array, no on_p2_action).
class TestMain extends Node3D:
	var net: Node
	var party: Node
	var vr_rig: Node
	var ready_to_play := false
	var requests: Array = []
	var pauses: Array = []
	var accept_edges := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	var x_edges := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	var phys_accept_edges := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	var nav_events: Array = []
	var trig_presses := 0
	var trig_releases := 0
	var a_presses := 0
	var move_hand := false

	func on_request(slot: int, action: String, args: Array) -> void:
		requests.append([slot, action, args])
		if action == "buzz" and net != null:
			net.state_set("buzzed", slot)

	func on_pause_changed(paused: bool, by_slot: int) -> void:
		pauses.append([paused, by_slot])

	func _process(delta: float) -> void:
		if party != null:
			for s in Party.MAX_SLOTS:
				if party.just_pressed(s, "accept"):
					accept_edges[s] += 1
				if party.just_pressed(s, "x"):
					x_edges[s] += 1
				var n: Vector2i = party.nav(s)
				if n != Vector2i.ZERO:
					nav_events.append([s, n])
		if vr_rig != null and is_instance_valid(vr_rig):
			if vr_rig.trigger_pressed():
				trig_presses += 1
			if vr_rig.trigger_released():
				trig_releases += 1
			if vr_rig.a_pressed():
				a_presses += 1
			if move_hand:
				vr_rig.hand_r.position.x += 2.0 * delta

	func _physics_process(_delta: float) -> void:
		if party != null:
			for s in Party.MAX_SLOTS:
				if party.just_pressed(s, "accept"):
					phys_accept_edges[s] += 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	kit.name = "BotKit"
	add_child(kit)
	main = TestMain.new()
	main.name = "Main"
	main.process_mode = Node.PROCESS_MODE_PAUSABLE  # like a game's main under the root
	add_child(main)
	kit.main = main
	var net := NetScript.new()
	net.name = "Net"
	net.main = main
	main.net = net
	main.add_child(net)
	net.state_changed.connect(func(k: String, v: Variant) -> void: state_log.append([k, v]))
	party = Party.new()
	party.name = "Party"
	party.leave_after = 1.0
	main.party = party
	main.add_child(party)
	party.player_joined.connect(func(s: int, d: int) -> void: joined_log.append([s, d]))
	party.player_left.connect(func(s: int) -> void: left_log.append(s))
	party.join_refused.connect(func(d: int, why: String) -> void: refused_log.append([d, why]))
	party.device_lost.connect(func(s: int) -> void: lost_log.append(s))
	party.device_restored.connect(func(s: int) -> void: restored_log.append(s))
	var menu := PauseMenu.new()
	menu.main = main
	main.add_child(menu)
	if OS.has_environment("ENGINE_NET"):
		_net_setup()
	else:
		_local_timeline()


# =============================================================================================
# Local run: every module
# =============================================================================================

func _local_timeline() -> void:
	kit.info("ENGINE TEST: local run")
	kit.at(0.2, "party: a pad is already plugged in before the game is ready", func() -> void:
		pads["p0"] = party.add_virtual_pad()
		kit.assert_true(party.player_count() == 0, "nobody joins before main.ready_to_play"))
	kit.at(0.4, "party: the game is ready", func() -> void:
		main.ready_to_play = true)
	kit.at(0.6, "party: drop-in with A on a new pad", func() -> void:
		kit.assert_true(party.is_active(1) and party.device_of(1) == int(pads["p0"]), "the first pad auto-joined as P2 (slot 1)")
		kit.assert_true(not party.connected_pads().has(0), "real controllers are ignored in bots")
		pads["b"] = party.add_virtual_pad()
		kit.pad_press(int(pads["b"]), JOY_BUTTON_A))
	kit.at(0.8, "party: Start on a pad nobody owns", func() -> void:
		kit.assert_eq(party.owner_of(int(pads["b"])), 2, "A on a new pad joins the next free slot")
		kit.assert_eq(party.device_of(2), int(pads["b"]), "device_of(slot)")
		kit.assert_eq(main.accept_edges[2], 0, "the A press that joined does not also 'accept'")
		pads["c"] = party.add_virtual_pad()
		kit.pad_press(int(pads["c"]), JOY_BUTTON_START))
	kit.at(1.0, "party: tap A on P3's pad", func() -> void:
		kit.assert_true(not get_tree().paused, "Start on an unowned pad does not pause")
		kit.assert_eq(party.owner_of(int(pads["c"])), -1, "Start never joins")
		kit.assert_eq(party.active_slots(), [1, 2] as Array[int], "active_slots")
		kit.pad_press(int(pads["b"]), JOY_BUTTON_A))
	kit.at(1.2, "party: hold A and push the stick on P3's pad", func() -> void:
		kit.assert_eq(main.accept_edges[2], 1, "a quick tap is one just_pressed in _process")
		kit.assert_eq(main.phys_accept_edges[2], 1, "... and one in _physics_process")
		kit.assert_eq(main.accept_edges[1], 0, "other slots don't see it")
		kit.pad_hold(int(pads["b"]), JOY_BUTTON_A, true)
		kit.pad_stick(int(pads["b"]), "left", Vector2(1.0, 0.0)))
	kit.at(1.4, "party: d-pad down on P3's pad", func() -> void:
		kit.assert_true(party.pressed(2, "accept") and not party.pressed(1, "accept"), "pressed() reads only the slot's device")
		kit.assert_near(party.stick(2, "move").x, 1.0, 0.01, "stick(2, move)")
		kit.assert_eq(party.stick(1, "move"), Vector2.ZERO, "stick of another slot")
		kit.pad_hold(int(pads["b"]), JOY_BUTTON_A, false)
		kit.pad_stick(int(pads["b"]), "left", Vector2.ZERO)
		kit.pad_press(int(pads["b"]), JOY_BUTTON_DPAD_DOWN))
	kit.at(1.6, "party: Space on the keyboard", func() -> void:
		kit.assert_true(main.nav_events.has([2, Vector2i(0, 1)]), "nav() reports the d-pad step")
		_key(KEY_SPACE, true)
		_key(KEY_SPACE, false))
	kit.at(1.8, "party: unplug P3's pad", func() -> void:
		kit.assert_eq(party.owner_of(Party.KEYBOARD), 3, "keyboard + mouse joined as P4 (slot 3)")
		party.remove_virtual_pad(int(pads["b"])))
	kit.at(2.0, "party: plug it back in quickly", func() -> void:
		kit.assert_true(party.is_lost(2) and lost_log.has(2), "the seat waits for its controller")
		party.replug_virtual_pad(int(pads["b"])))
	kit.at(2.2, "party: unplug it for longer than leave_after", func() -> void:
		kit.assert_true(not party.is_lost(2) and restored_log.has(2), "reconnecting restores the seat")
		party.remove_virtual_pad(int(pads["b"])))
	kit.at(3.6, "party: plug it in after the player left", func() -> void:
		kit.assert_true(left_log.has(2) and not party.is_active(2), "after leave_after the player leaves")
		party.replug_virtual_pad(int(pads["b"])))
	kit.at(3.8, "pause menu: Start on an owned pad", func() -> void:
		kit.assert_eq(party.owner_of(int(pads["b"])), 2, "the returning controller rejoins its old seat")
		kit.allow_pause = true
		kit.pad_press(int(pads["b"]), JOY_BUTTON_START))
	kit.at(4.0, "pause menu: hold X while resuming with Start", func() -> void:
		kit.assert_true(get_tree().paused, "Start on an owned pad opens the pause menu (party.owner_of)")
		mark["edges"] = main.x_edges[2]
		kit.pad_hold(int(pads["b"]), JOY_BUTTON_X, true)
		kit.pad_press(int(pads["b"]), JOY_BUTTON_START))
	kit.at(4.2, "party: X still held after the unpause", func() -> void:
		kit.assert_true(not get_tree().paused, "Start again resumes")
		kit.assert_true(not party.pressed(2, "x"), "a button held across the unpause is ignored")
		kit.assert_eq(main.x_edges[2], int(mark["edges"]), "... and doesn't fire just_pressed")
		kit.pad_hold(int(pads["b"]), JOY_BUTTON_X, false))
	kit.at(4.4, "party: a fresh X press", func() -> void:
		kit.allow_pause = false
		kit.pad_press(int(pads["b"]), JOY_BUTTON_X))
	kit.at(4.6, "party: the keyboard player leaves", func() -> void:
		kit.assert_eq(main.x_edges[2], int(mark["edges"]) + 1, "after a release X counts again")
		party.leave(3))
	kit.at(4.8, "party: fill every seat, then one more", func() -> void:
		kit.assert_true(not party.is_active(3) and left_log.has(3), "leave(slot)")
		for i in 4:
			kit.join_bot(party))
	kit.at(5.0, "party: one pad too many", func() -> void:
		pads["late"] = kit.join_bot(party))
	kit.at(5.2, "party: roster", func() -> void:
		kit.assert_eq(party.active_slots(), [1, 2, 3, 4, 5, 6] as Array[int], "six TV seats")
		kit.assert_true(refused_log.has([int(pads["late"]), "full"]), "a seventh pad is refused (full)")
		var roster: Dictionary = Engine.get_meta(Party.ROSTER_META, {})
		var saved_slots: Array = roster.get("slots", [])
		kit.assert_eq(saved_slots.size(), 6, "the roster is kept in Engine metadata for reloads")
		kit.assert_eq(party.name_of(2), "P3", "name_of")
		kit.assert_true(party.color_of(1) == Party.COLORS[1], "color_of"))
	kit.at(5.5, "split view: layouts 1..7, shared mode", _test_split)
	kit.at(6.0, "vr rig: built with the trigger held (as if from the arcade)", func() -> void:
		rig = VrRig.new()
		rig.fake_trigger = 1.0
		rig.refitted.connect(func(h: float) -> void: refits.append(h))
		main.vr_rig = rig
		main.add_child(rig)
		kit.assert_true(rig.fake and not rig.is_xr, "no headset: fake mode")
		kit.assert_eq(rig.gloves.size(), 2, "two gloves")
		kit.assert_true(rig.mirror != null and rig.mirror.is_in_group("gdev_capture"), "the VR mirror is recorded by gdev"))
	kit.at(6.5, "vr rig: let go of the old trigger", func() -> void:
		kit.assert_eq(main.trig_presses, 0, "a trigger held from the previous screen never fires")
		kit.assert_true(not rig.trigger_down(), "... and isn't 'down'")
		kit.vr_trigger(rig, 0.0))
	kit.at(6.6, "vr rig: a fresh pull", func() -> void:
		kit.vr_trigger(rig, 1.0))
	kit.at(6.8, "vr rig: release", func() -> void:
		kit.assert_eq(main.trig_presses, 1, "a fresh pull fires exactly once")
		kit.assert_true(rig.trigger_down(), "trigger_down while held")
		kit.vr_trigger(rig, 0.0))
	kit.at(6.9, "vr rig: point at the wrist MENU and pull", func() -> void:
		kit.assert_eq(main.trig_presses, 1, "no second press")
		kit.assert_eq(main.trig_releases, 1, "trigger_released once")
		kit.assert_true(rig.fitted and absf(rig.head_height - 1.6) < 0.05, "fitted to the head height on start")
		kit.allow_pause = true
		_point_at_wrist_menu())
	kit.at(7.0, "vr rig: pull on the MENU button", func() -> void:
		kit.vr_trigger(rig, 1.0))
	kit.at(7.2, "vr rig: release, pull again to resume", func() -> void:
		kit.assert_true(get_tree().paused, "the wrist MENU (core/net.gd) finds the hands through main.vr_rig")
		kit.assert_eq(main.trig_presses, 1, "a pull on the wrist MENU isn't the game's")
		kit.assert_true(main.pauses.has([true, 0]), "net.toggle_pause told main.on_pause_changed")
		kit.vr_trigger(rig, 0.0))
	kit.at(7.3, "vr rig: pull to resume", func() -> void:
		kit.vr_trigger(rig, 1.0))
	kit.at(7.5, "vr rig: hands back", func() -> void:
		kit.assert_true(not get_tree().paused, "a second pull on the MENU resumes")
		kit.vr_trigger(rig, 0.0)
		kit.vr_pose(rig, Vector3(0, 1.6, 0), Vector3(-0.25, 1.1, -0.3), Vector3(0.25, 1.1, -0.3)))
	kit.at(7.8, "vr rig: pull and keep holding through a pause", func() -> void:
		kit.allow_pause = false
		mark["presses"] = main.trig_presses
		kit.vr_trigger(rig, 1.0))
	kit.at(8.0, "vr rig: pause", func() -> void:
		kit.assert_eq(main.trig_presses, int(mark["presses"]) + 1, "fresh pull counted")
		kit.allow_pause = true
		get_tree().paused = true)
	kit.at(8.2, "vr rig: unpause with the trigger still held", func() -> void:
		get_tree().paused = false)
	kit.at(8.4, "vr rig: release", func() -> void:
		kit.allow_pause = false
		kit.assert_true(not rig.trigger_down(), "a trigger held across a pause must be released first")
		kit.assert_true(main.net.just_unpaused(0.5), "net.just_unpaused() right after unpausing")
		kit.vr_trigger(rig, 0.0))
	kit.at(8.5, "vr rig: pull again", func() -> void:
		kit.vr_trigger(rig, 1.0))
	kit.at(8.6, "vr rig: A button", func() -> void:
		kit.assert_eq(main.trig_presses, int(mark["presses"]) + 2, "after the release it fires again")
		kit.vr_trigger(rig, 0.0)
		kit.vr_a(rig, true))
	kit.at(8.7, "vr rig: sit down (head at 1.1 m)", func() -> void:
		kit.assert_eq(main.a_presses, 1, "a_pressed")
		kit.vr_a(rig, false)
		mark["refits"] = refits.size()
		kit.vr_head_height(rig, 1.1))
	kit.at(9.0, "vr rig: walk forward with the left stick", func() -> void:
		mark["head"] = rig.head_position()
		kit.vr_stick(rig, Vector2(0.0, 1.0)))
	kit.at(9.5, "vr rig: snap turn right", func() -> void:
		kit.vr_stick(rig, Vector2.ZERO)
		var moved: Vector3 = rig.head_position() - (mark["head"] as Vector3)
		kit.assert_true(moved.z < -0.8 and absf(moved.x) < 0.05, "left stick walks where the head looks (moved %s)" % str(moved))
		mark["yaw"] = rig.head_yaw()
		kit.vr_stick(rig, Vector2.ZERO, Vector2(1.0, 0.0)))
	kit.at(9.8, "vr rig: snap again", func() -> void:
		kit.assert_near(angle_difference(float(mark["yaw"]), rig.head_yaw()), deg_to_rad(-30.0), 0.01, "one snap turn of 30 degrees to the right")
		kit.vr_stick(rig, Vector2.ZERO))
	kit.at(9.9, "vr rig: flick right", func() -> void:
		kit.vr_stick(rig, Vector2.ZERO, Vector2(1.0, 0.0)))
	kit.at(10.0, "vr rig: bounds", func() -> void:
		kit.assert_near(angle_difference(float(mark["yaw"]), rig.head_yaw()), deg_to_rad(-60.0), 0.01, "a second flick turns again")
		kit.vr_stick(rig, Vector2.ZERO)
		var h := rig.head_position()
		rig.bounds = Rect2(h.x - 0.5, h.z - 0.5, 1.0, 1.0)
		kit.vr_stick(rig, Vector2(0.0, 1.0)))
	kit.at(11.2, "vr rig: swing the right hand at 2 m/s", func() -> void:
		var h := rig.head_position()
		var b := rig.bounds
		kit.assert_true(h.x >= b.position.x - 0.01 and h.x <= b.end.x + 0.01 and h.z >= b.position.y - 0.01 and h.z <= b.end.y + 0.01, "locomotion stays inside bounds")
		kit.vr_stick(rig, Vector2.ZERO)
		rig.bounds = Rect2()
		main.move_hand = true)
	kit.at(11.5, "vr rig: refit, touching, haptics, avatar, perf", func() -> void:
		main.move_hand = false
		kit.assert_near(rig.hand_speed(VrRig.RIGHT), 2.0, 0.25, "hand_speed from tracking")
		kit.assert_true(refits.size() > int(mark["refits"]) and absf(rig.head_height - 1.1) < 0.05, "re-fits after the head stays lower for a few seconds")
		kit.assert_near(rig.fit_lift, 0.45, 0.01, "eye fit lifts a seated player")
		var p := rig.hand_point(VrRig.LEFT) + Vector3(0.05, 0.0, 0.0)
		kit.assert_true(rig.touching(VrRig.LEFT, p, 0.1) and not rig.touching(VrRig.RIGHT, p, 0.1), "touching(hand, point, radius)")
		kit.assert_eq(rig.touching_any(p, 0.1), VrRig.LEFT, "touching_any")
		kit.assert_true(rig.in_wrist_zone(rig.wrist_menu_position()), "in_wrist_zone")
		rig.pulse(VrRig.RIGHT, 0.5, 0.05)
		rig.pulse(VrRig.RIGHT, 0.5, 0.05)
		kit.assert_eq(rig.pulses_sent, 1, "haptics are rate-limited")
		var avatar := VrRig.Avatar.new()
		main.add_child(avatar)
		avatar.apply_pose(rig.pack_pose())
		kit.assert_true(avatar.head.global_position.distance_to(rig.head_position()) < 0.001, "Avatar follows pack_pose()")
		var ghost := VrRig.build_mirror(main, avatar.head, false)
		kit.assert_true(not ghost.is_in_group("gdev_capture") and ghost.size == Vector2i(480, 480), "TV-side mirror of the avatar")
		split.set_slots([1, 2, 3])
		split.set_bubble(rig.mirror)
		var br := split.bubble_rect()
		kit.assert_true(br.size.x > 10.0 and split.empty_cell_rect().encloses(br), "the VR bubble sits in the empty grid cell")
		var we := WorldEnvironment.new()
		we.environment = Environment.new()
		we.environment.ssao_enabled = true
		we.environment.fog_enabled = true
		main.add_child(we)
		var sun := DirectionalLight3D.new()
		sun.shadow_enabled = true
		main.add_child(sun)
		VrRig.apply_vr_performance(main)
		kit.assert_true(not we.environment.ssao_enabled and not we.environment.fog_enabled and not sun.shadow_enabled, "VR performance settings"))
	kit.at(12.0, "camera rig: follow", _camera_follow)
	kit.at(12.6, "camera rig: a wall gets in the way", func() -> void:
		kit.assert_near(_cam_dist(), 6.0, 0.25, "follow keeps the distance")
		wall = StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(10.0, 10.0, 0.4)
		shape.shape = box
		wall.add_child(shape)
		main.add_child(wall)
		wall.global_position = Vector3(0.0, 2.0, 3.0))
	kit.at(13.2, "camera rig: wall removed", func() -> void:
		kit.assert_true(_cam_dist() < 3.2, "the camera pulls in in front of the wall (%.2f m)" % _cam_dist())
		wall.queue_free())
	kit.at(14.4, "camera rig: orbit with P3's right stick", func() -> void:
		kit.assert_true(_cam_dist() > 5.0, "and eases back out (%.2f m)" % _cam_dist())
		mark["cyaw"] = crig.yaw
		kit.pad_stick(int(pads["b"]), "right", Vector2(1.0, 0.0)))
	kit.at(14.7, "camera rig: group", func() -> void:
		kit.pad_stick(int(pads["b"]), "right", Vector2.ZERO)
		kit.assert_true(crig.yaw < float(mark["cyaw"]) - 0.4, "the slot's right stick orbits (%.2f -> %.2f)" % [float(mark["cyaw"]), crig.yaw])
		t1 = Node3D.new()
		t2 = Node3D.new()
		main.add_child(t1)
		main.add_child(t2)
		t1.position = Vector3(-1.0, 0.0, 0.0)
		t2.position = Vector3(1.0, 0.0, 0.0)
		crig.follow_group([t1, t2]))
	kit.at(15.8, "camera rig: spread the group out", func() -> void:
		mark["gd"] = crig.group_distance()
		t2.position = Vector3(30.0, 0.0, 0.0))
	kit.at(17.3, "camera rig: cinematic shot", func() -> void:
		kit.assert_true(crig.group_distance() > float(mark["gd"]) + 5.0, "group zooms out to fit everyone (%.1f -> %.1f)" % [float(mark["gd"]), crig.group_distance()])
		crig.shot_look(Vector3(10.0, 5.0, 10.0), Vector3.ZERO, 0.5))
	kit.at(18.0, "camera rig: shake", func() -> void:
		kit.assert_true(crig.camera.global_position.distance_to(Vector3(10.0, 5.0, 10.0)) < 0.01, "shot blends to its transform")
		crig.shake(0.6))
	kit.at(18.05, "camera rig: shaking", func() -> void:
		kit.assert_true(crig.camera.global_position.distance_to(Vector3(10.0, 5.0, 10.0)) > 0.0005, "shake moves the camera"))
	kit.at(19.0, "camera rig: settled", func() -> void:
		kit.assert_true(crig.trauma == 0.0 and crig.camera.global_position.distance_to(Vector3(10.0, 5.0, 10.0)) < 0.01, "shake decays back to the shot"))
	kit.at(19.1, "save: round trip", _test_save)
	kit.at(19.6, "save: autosave", func() -> void:
		kit.assert_true(saved_count == 1, "the Save node autosaved after mark_dirty()")
		var d := Save.load_data("engine_test_node", {})
		kit.assert_eq(int(d.get("coins", 0)), 7, "the autosaved value is on disk")
		Save.erase("engine_test_node")
		Save.erase("engine_test"))
	kit.at(19.7, "net (local): state store, request, pause", func() -> void:
		var net: Node = main.net
		state_log.clear()
		net.state_set("turn", 3)
		net.state_set("turn", 3)
		net.state_set("board", [1, 2])
		kit.assert_eq(net.state_get("turn"), 3, "state_get")
		kit.assert_eq(state_log.size(), 2, "state_changed fires once per real change")
		net.state_set("turn", null)
		kit.assert_true(not net.state_has("turn") and state_log.back() == ["turn", null], "null erases a key")
		net.request(2, "buzz", [1])
		kit.assert_true(main.requests.has([2, "buzz", [1]]), "request() runs main.on_request right away in local play")
		kit.assert_eq(net.state_get("buzzed"), 2, "on_request can set state"))
	kit.at(19.85, "vr rig: a wall right in front", func() -> void:
		var f := rig.head_forward()
		var h := rig.head_position()
		mark["wall_from"] = h
		mark["wall_dir"] = f
		var w := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4.0, 3.0, 0.2)
		shape.shape = box
		w.add_child(shape)
		main.add_child(w)
		w.global_transform = Transform3D(Basis.looking_at(f, Vector3.UP), Vector3(h.x, 1.0, h.z) + f * 1.0)
		mark["vr_wall"] = w
		rig.collision_mask = 1)
	kit.at(19.95, "vr rig: walk into it", func() -> void:
		kit.vr_stick(rig, Vector2(0.0, 1.0)))
	kit.at(20.5, "vr rig: stopped at the wall?", func() -> void:
		kit.vr_stick(rig, Vector2.ZERO)
		var moved: float = (rig.head_position() - (mark["wall_from"] as Vector3)).dot(mark["wall_dir"] as Vector3)
		kit.assert_true(moved > 0.4 and moved < 0.7, "collision_mask: stick walking stops at walls (moved %.2f m of 1.1)" % moved)
		rig.collision_mask = 0
		(mark["vr_wall"] as Node).queue_free())
	kit.at(20.6, "vr rig: world scale, then leave", func() -> void:
		split.clear_bubble()
		rig.set_scale_of_world(2.0)
		kit.assert_near(XRServer.world_scale, 2.0, 0.001, "world_scale is applied")
		main.remove_child(rig)
		kit.assert_near(XRServer.world_scale, 1.0, 0.001, "XRServer.world_scale goes back to 1 when the rig leaves")
		rig.queue_free()
		main.vr_rig = null)
	kit.at(20.8, "done", func() -> void:
		kit.finish())


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _test_split() -> void:
	split = SplitView.new()
	main.add_child(split)
	var area: Vector2 = split._area()
	kit.info("screen area %s" % str(area))
	var want_grid := {1: Vector2i(1, 1), 2: Vector2i(2, 1), 3: Vector2i(2, 2), 4: Vector2i(2, 2),
		5: Vector2i(3, 2), 6: Vector2i(3, 2), 7: Vector2i(4, 2)}
	var last_scale := 2.0
	for n in range(1, 8):
		var slots: Array = []
		for i in n:
			slots.append(i)
		split.set_slots(slots)
		kit.assert_eq(split.view_count(), n, "%d views" % n)
		var xs := {}
		var ys := {}
		for s in n:
			var r := split.view_rect(s)
			xs[snappedf(r.position.x, 1.0)] = true
			ys[snappedf(r.position.y, 1.0)] = true
		var g: Vector2i = want_grid[n]
		kit.assert_true(xs.size() == mini(g.x, n) and ys.size() == g.y, "%d views form a %dx%d grid" % [n, g.x, g.y])
		var rects := SplitView.cell_rects(n, area)
		kit.assert_true(split.view_rect(n - 1).is_equal_approx(rects[n - 1]), "%d views: last view in its cell" % n)
		var sc := split.viewport(0).scaling_3d_scale
		kit.assert_true(sc <= last_scale, "3D resolution never rises with more views (%d: %.2f)" % [n, sc])
		last_scale = sc
		kit.assert_eq(split.empty_cell_rect().size.x > 0.0, n == 3 or n == 5 or n == 7, "%d views: empty cell" % n)
		var cr := split.view_rect(0)
		var want_s := clampf(minf(cr.size.x / 940.0, cr.size.y / 900.0), 0.5, 1.0)
		kit.assert_near(split.hud_scale(0), want_s, 0.001, "%d views: HUD scaled to the view" % n)
		kit.assert_eq(split.viewport(0).msaa_3d == Viewport.MSAA_DISABLED, n > 2, "%d views: MSAA only up to 2 views" % n)
	kit.assert_true(split.camera(0) != split.camera(1) and split.camera(0).current, "each view has its own current camera")
	kit.assert_true(split.hud(3).get_parent() is CanvasLayer and split.hud(3).scale.x < 1.0, "per-view HUD root, scaled")
	split.set_shared(true)
	kit.assert_true(split.view_count() == 1 and split.is_shared(), "shared mode: one view")
	kit.assert_true(split.view_rect(0) == Rect2() and not split.viewport(0).get_parent().visible, "shared mode hides the player views")
	kit.assert_true(split.active_camera(4) == split.shared_camera() and split.shared_hud() != null, "active_camera in shared mode")
	split.set_shared(false)
	kit.assert_eq(split.view_count(), 7, "back to split")
	split.bind_party(party)
	kit.assert_eq(split.slots(), party.local_slots(), "bind_party shows the party's local players")


func _point_at_wrist_menu() -> void:
	var btn := rig.wrist_menu_position()
	var hr := rig.hand_r
	hr.global_position = btn + Vector3(0.3, 0.05, -0.2)
	hr.global_basis = Basis.looking_at((btn - hr.global_position).normalized(), Vector3.UP)
	kit.assert_true(rig.on_wrist_menu(), "pointing at the wrist MENU")


func _camera_follow() -> void:
	split.set_slots([1, 2])
	target = Node3D.new()
	main.add_child(target)
	crig = CameraRig.new()
	crig.camera = split.camera(2)
	crig.party = party
	crig.slot = 2
	main.add_child(crig)
	crig.follow(target, 6.0, 0.0)


func _cam_dist() -> float:
	return crig.camera.global_position.distance_to(target.global_position + Vector3.UP * crig.pivot_height)


func _test_save() -> void:
	kit.assert_true(Save.test_mode() and Save.path_for("engine_test").begins_with(Save.TEST_DIR), "bots save into user://test_saves/")
	Save.erase("engine_test")
	kit.assert_true(not Save.exists("engine_test"), "erase")
	var d := Save.load_data("engine_test", {"coins": 0, "items": ["map"]})
	kit.assert_eq(d.get("coins"), 0, "defaults when there is no save")
	d["coins"] = 12
	d["where"] = Vector3(1, 2, 3)
	kit.assert_true(Save.store("engine_test", d, 1), "store")
	var back := Save.load_data("engine_test", {"coins": 0, "hat": "red"})
	kit.assert_true(typeof(back["coins"]) == TYPE_INT and back["coins"] == 12, "ints stay ints")
	kit.assert_eq(back.get("where"), Vector3(1, 2, 3), "Vector3 survives")
	kit.assert_eq(back.get("hat"), "red", "new default keys are filled in")
	var migrated := Save.load_data("engine_test", {}, 2, func(old: Dictionary, from: int) -> Dictionary:
		old["migrated_from"] = from
		return old)
	kit.assert_eq(migrated.get("migrated_from"), 1, "older versions go through migrate")
	d["coins"] = 13
	Save.store("engine_test", d, 1)
	var f := FileAccess.open(Save.path_for("engine_test"), FileAccess.WRITE)
	f.store_string("not a save")
	f.close()
	var rescued := Save.load_data("engine_test", {})
	kit.assert_eq(rescued.get("coins"), 12, "a damaged file falls back to the .bak copy")
	Save.erase("engine_test_node")
	var node := Save.new()
	node.game_id = "engine_test_node"
	node.defaults = {"coins": 0}
	node.autosave_delay = 0.2
	node.saved.connect(func() -> void: saved_count += 1)
	main.add_child(node)
	node.data["coins"] = 7
	node.mark_dirty()


# =============================================================================================
# Networked run: host + TV machine
# =============================================================================================

func _net_setup() -> void:
	var net: Node = main.net
	kit.allow_pause = true  # this test pauses on purpose
	if OS.has_environment("DUO_JOIN"):
		kit.info("ENGINE TEST: networked, TV machine")
		net.join_finished.connect(func(ok: bool) -> void:
			kit.assert_true(ok, "joined the host")
			if not ok:
				kit.finish()
				return
			main.ready_to_play = true
			net_t0 = kit.t)
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		kit.info("ENGINE TEST: networked, host")
		net.host()
		main.ready_to_play = true
		net.state_set("phase", "lobby")
		net.state_set("scores", [1, 2, 3])
		net.state_set("tmp", 5)
		party.player_joined.connect(func(_s: int, _d: int) -> void: net.state_set("seated", party.active_slots()))
		party.player_left.connect(func(_s: int) -> void: net.state_set("seated", party.active_slots()))
		net.client_connected.connect(func() -> void:
			mark["connected_at"] = kit.t
			get_tree().create_timer(0.5).timeout.connect(func() -> void:
				net.state_set("phase", "round1")
				net.state_set("tmp", null)
				net.state_set("big", {"names": ["Ann", "Bo"], "grid": [0, 1, 2]})))
		net.client_disconnected.connect(func() -> void: mark["gone_at"] = kit.t)
	kit.every(0.25, _net_tick)


func _net_tick() -> String:
	if net_done:
		return ""
	if OS.has_environment("DUO_JOIN"):
		return _client_tick()
	return _host_tick()


func _host_tick() -> String:
	if mark.has("gone_at") and kit.t > float(mark["gone_at"]) + 0.5:
		net_done = true
		kit.assert_true(joined_log.has([1, Party.REMOTE]) and joined_log.has([2, Party.REMOTE]), "host: the TV machine's players joined as REMOTE slots 1 and 2")
		kit.assert_true(main.requests.has([2, "buzz", [42]]), "host: net.request from the TV machine reached on_request")
		kit.assert_true(main.pauses.has([true, 1]) and main.pauses.has([false, 1]), "host: the TV machine paused and resumed the game")
		kit.assert_true(left_log.has(2), "host: slot 2 left (party.leave on the TV machine)")
		kit.assert_true(left_log.has(1) and party.active_slots().is_empty(), "host: the TV machine's players leave when it disconnects")
		kit.finish()
		return "host: done"
	if kit.t > 40.0:
		net_done = true
		kit.assert_true(false, "host: the TV machine never finished (timeout)")
		kit.finish()
	return "host: seats %s, requests %d" % [str(party.active_slots()), main.requests.size()]


func _client_tick() -> String:
	if net_t0 < 0.0:
		if kit.t > 20.0:
			net_done = true
			kit.assert_true(false, "TV: never connected")
			kit.finish()
		return ""
	var dt := kit.t - net_t0
	var net: Node = main.net
	var step: int = int(mark.get("step", 0))
	match step:
		0:
			if dt > 0.3:
				kit.assert_eq(net.state_get("phase"), "lobby", "TV: a late joiner gets the whole store")
				kit.assert_eq(net.state_get("scores"), [1, 2, 3], "TV: arrays arrive")
				kit.assert_eq(net.state_get("tmp"), 5, "TV: ints arrive")
				pads["a"] = kit.join_bot(party)
				mark["step"] = 1
		1:
			if dt > 1.3:
				kit.assert_true(party.is_active(1) and party.device_of(1) == int(pads["a"]), "TV: A on a pad -> the host confirmed slot 1")
				pads["b"] = kit.join_bot(party)
				mark["step"] = 2
		2:
			if dt > 2.3:
				kit.assert_true(party.is_active(2), "TV: second pad -> slot 2")
				kit.assert_eq(net.state_get("seated"), [1, 2] as Array[int], "TV: host-set state follows the party")
				kit.assert_eq(net.state_get("phase"), "round1", "TV: changed keys arrive")
				kit.assert_true(not net.state_has("tmp") and state_log.has(["tmp", null]), "TV: erased keys arrive as null")
				var big: Dictionary = net.state_get("big", {})
				kit.assert_eq(big.get("names"), ["Ann", "Bo"], "TV: dictionaries arrive")
				net.state_set("client_key", 1)
				kit.assert_true(not net.state_has("client_key"), "TV: state_set on the client is ignored")
				net.request(2, "buzz", [42])
				mark["step"] = 3
		3:
			if dt > 3.0:
				kit.assert_eq(net.state_get("buzzed"), 2, "TV: request -> host on_request -> state back")
				net.request(1, "pause", [true])
				mark["step"] = 4
		4:
			if dt > 3.7:
				kit.assert_true(get_tree().paused and main.pauses.has([true, 1]), "TV: the host's pause reaches the TV (on_pause_changed)")
				net.request(1, "pause", [false])
				mark["step"] = 5
		5:
			if dt > 4.4:
				kit.assert_true(not get_tree().paused and main.pauses.has([false, 1]), "TV: resumed")
				party.leave(2)
				mark["step"] = 6
		6:
			if dt > 5.0:
				kit.assert_true(not party.is_active(2) and left_log.has(2), "TV: leave(slot)")
				net_done = true
				kit.finish()
	return "TV: step %d, seats %s" % [step, str(party.active_slots())]
