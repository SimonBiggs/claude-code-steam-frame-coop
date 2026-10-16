extends Node
## Headless bot for games/tower_stack. TV bots push blocks onto the pad (and one climbs the tower);
## BOT_VR=1 adds a fake VR giant that grabs boinged-up blocks and stacks them on the stage.
## Without VR the helper crane does the stacking.
## Local:      godot --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/tower_stack_bot.tscn
## Networked:  DUO_PORT=8137 DUO_HOST=1 ... & DUO_PORT=8137 DUO_JOIN=127.0.0.1 ... (same scene, real time)

const BotKit := preload("res://tests/bot_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")

var kit: BotKit
var main: Node
var want := 2
var saw_results := false
var max_climb := 0.0
var jump_t := 0.0
var vr_phase := "find"
var vr_wait := 0.0
var ghosts_seen := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/tower_stack/main.tscn").instantiate()
	main.set("round_time", 24.0)
	add_child(main)
	kit.main = main
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d TV players press A on their pads" % want, _join)
	if not host:
		kit.at(t0 + 6.0, "P2 presses Start: pause menu", func() -> void:
			kit.allow_pause = true
			_press("start"))
		kit.at(t0 + 6.6, "paused?", func() -> void:
			kit.assert_true(get_tree().paused and main.tv_banner != null and main.tv_banner.visible, "Start pauses and shows the banner")
			_press("start"))
		kit.at(t0 + 7.2, "resumed?", func() -> void:
			kit.assert_true(not get_tree().paused, "Start again resumes everyone")
			kit.allow_pause = false)
	if host:
		kit.at(34.0, "host checks", _checks)
		kit.at(38.0, "finish", kit.finish)
	else:
		kit.at(30.0 if client else 36.0, "finish", func() -> void:
			_checks()
			kit.finish())
	kit.every(2.0, _report)
	kit.every(0.5, _continue_results)


func _continue_results() -> String:
	if main.results_showing():
		if not saw_results:
			saw_results = true
			kit.assert_true(main.split == null or main.results_ui != null, "the results screen shows on the TV")
		_press("accept")
	return ""


func _join() -> void:
	if main.net.mode == "host":
		return
	for i in want:
		kit.join_bot(main.party)


func _press(action: String) -> void:
	var slots: Array[int] = main.party.local_slots()
	if not slots.is_empty():
		kit.slot_press(main.party, slots[0], action)


func _physics_process(delta: float) -> void:
	if main == null or not main.ready_to_play:
		return
	if main.net.mode == "client":
		ghosts_seen = maxi(ghosts_seen, main.blocks.size())
	var slots: Array[int] = main.party.local_slots()
	jump_t -= delta
	for slot in slots:
		var climber: bool = slot == slots[slots.size() - 1] and slots.size() >= 2 and kit.t > 12.0
		_steer(slot, climber, delta)
	if main.vr_rig != null:
		_drive_vr(delta)


func _steer(slot: int, climber: bool, _delta: float) -> void:
	if not main.avatars.has(slot):
		return
	var a: Node3D = main.avatars[slot]
	max_climb = maxf(max_climb, a.position.y)
	var goal := Vector3.ZERO
	if climber:
		goal = Vector3(0.0, 0.0, 0.0)
		if Vector2(a.position.x, a.position.z).length() < 2.2 and jump_t <= 0.0:
			jump_t = 0.45
			kit.slot_press(main.party, slot, "accept")
	else:
		var blk := _loose_block(a.position)
		if blk == null:
			kit.slot_stick(main.party, slot, "left", Vector2.ZERO)
			return
		var bp := blk.global_position
		var dest := _route(Vector3(bp.x, 0.0, bp.z))
		var to_pad: Vector3 = dest - bp
		to_pad.y = 0.0
		var behind := bp - to_pad.normalized() * 0.95
		var ap := Vector3(a.position.x, 0.0, a.position.z)
		var bflat := Vector3(bp.x, 0.0, bp.z)
		var dirp := to_pad.normalized()
		if ap.distance_to(Vector3(behind.x, 0.0, behind.z)) > 0.35 and (bflat - ap).normalized().dot(dirp) < 0.85:
			goal = behind
			if ap.distance_to(bflat) < 1.3 and (bflat - ap).dot(dirp) < 0.0:
				goal = bflat + Vector3(-dirp.z, 0.0, dirp.x) * 1.3  # walk round it, don't push it the wrong way
		else:
			goal = dest
	var d := goal - a.position
	d.y = 0.0
	var v := Vector2.ZERO
	if d.length() > 0.1:
		d = d.normalized()
		var cam: Camera3D = main.split.active_camera(slot)
		var f := -cam.global_basis.z
		f.y = 0.0
		f = f.normalized()
		var r := Vector3(-f.z, 0.0, f.x)
		v = Vector2(d.dot(r), -d.dot(f))
	kit.slot_stick(main.party, slot, "left", v)


## Where to push a block next: straight to the pad, or round the tower stage if it is in the way.
func _route(from: Vector3) -> Vector3:
	var pad := Vector3(main.PAD.x, 0.0, main.PAD.z)
	var seg := pad - from
	var k := clampf(-from.dot(seg) / maxf(seg.length_squared(), 0.001), 0.0, 1.0)
	var c := from + seg * k
	var clear: float = main.BASE_R + 1.2
	if c.length() < clear:
		var side := c if c.length() > 0.1 else Vector3(-seg.z, 0.0, seg.x)
		return side.normalized() * (clear + 0.6)
	return pad


## The nearest block lying in the field (not on the stage, the pad, or in the air).
func _loose_block(from: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for id in main.blocks:
		var b: Node3D = main.blocks[id]
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
		var p := b.global_position
		if p.y > 1.0 or Vector2(p.x, p.z).length() < main.BASE_R + 0.3:
			continue
		if Vector2(p.x - main.PAD.x, p.z - main.PAD.z).length() < main.PAD_R:
			continue
		var dd := from.distance_to(p)
		if dd < bd:
			bd = dd
			best = b
	return best


## Fake VR giant: reach for a hovering block, pull the trigger, carry it over the tower, let go.
func _drive_vr(delta: float) -> void:
	var rig = main.vr_rig
	kit.vr_head_height(rig, 1.5)
	vr_wait -= delta
	if main.results_showing():
		kit.vr_trigger(rig, 1.0 if int(kit.t * 2.0) % 2 == 0 else 0.0)  # the giant pulls the trigger: play again
		vr_phase = "find"
		return
	match vr_phase:
		"find":
			kit.vr_trigger(rig, 0.0)
			var id := -1
			for h in main.hover:
				if h >= 0 and float(main.hover_t.get(h, 0.0)) > 0.7:
					id = h
					break
			if id >= 0 and vr_wait <= 0.0:
				vr_phase = "reach"
				rig.set_meta("bot_target", id)
		"reach":
			var id: int = rig.get_meta("bot_target", -1)
			if not main.blocks.has(id) or main.held_id >= 0:
				vr_phase = "find"
				return
			var p: Vector3 = (main.blocks[id] as Node3D).global_position
			if kit.vr_reach(rig, VrRig.RIGHT, p, 6.0, delta) or rig.hand_point(VrRig.RIGHT).distance_to(p) < 0.15:
				kit.vr_trigger(rig, 1.0)
				vr_phase = "carry"
				vr_wait = 0.3
		"carry":
			if main.held_id < 0:
				if vr_wait <= 0.0:
					vr_phase = "find"
				return
			var top := Vector3(main.top_xz.x, float(main.tower_h), main.top_xz.y)
			var goal := Vector3(top.x, maxf(top.y, main.BASE_H) + main.H + 0.12, top.z)
			if kit.vr_reach(rig, VrRig.RIGHT, goal, 3.0, delta):
				kit.vr_trigger(rig, 0.0)
				vr_phase = "find"
				vr_wait = 0.8


func _report() -> String:
	return "BOT %s: players %s, blocks %d, hover %s, height %.1f, rec %.1f, best %.1f, delivered %d, placed %d" % [
		main.net.mode, str(main.party.active_slots()), main.blocks.size(), str(main.hover),
		float(main.net.state_get("height", 0.0)), float(main.net.state_get("rec", 0.0)),
		float(main.net.state_get("best", 0.0)), main.total_delivered, main.total_placed]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	kit.assert_true(int(main.net.state_get("round", 0)) >= 2, "%s: round 1 ended with results and round 2 started" % mode)
	if mode == "client":
		kit.assert_eq(main.party.player_count(), want, "client: all %d TV players are seated" % want)
		kit.assert_true(ghosts_seen > 0, "client: ghost blocks mirrored from the host")
		kit.assert_true(saw_results, "client: saw the results")
		return
	if mode == "local":
		kit.assert_eq(main.party.player_count(), want, "local: all %d TV players are seated" % want)
	if want > 0 and mode == "local" or mode == "host":
		kit.assert_true(main.total_delivered > 0, "%s: blocks reached the pad" % mode)
	kit.assert_true(main.max_height > 0.7, "%s: a tower was built (%.1f m)" % [mode, main.max_height])
	if main.vr_rig != null:
		kit.assert_true(main.total_placed > 0, "the fake VR giant placed blocks (%d)" % main.total_placed)
	if mode == "local" and want >= 2:
		kit.info("highest a TV player climbed: %.2f m" % max_climb)
		kit.assert_true(max_climb > main.BASE_H + 0.3, "a TV player climbed onto the tower")
