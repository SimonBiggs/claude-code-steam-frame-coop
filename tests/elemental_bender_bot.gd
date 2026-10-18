extends Node
## Headless bot for games/elemental_bender.
## TV bots (BOT_PLAYERS, default 2) drop in with A, turn their chase camera towards the nearest
## target, switch (d-pad) to the element that beats it, keep their distance and hold RT; now and then
## they jump, dash, use their special (LT) and enter Spirit State (L3) when the team meter is full.
## The fake VR master (BOT_VR=1, local / host) looks at the nearest target, touches the orb of the
## element that beats it, pulls the trigger and punches at it (earth: lifts a boulder, then pushes),
## jabs with the left fist, slams both hands down for specials and presses A for Spirit State.
## Design checks: practice dummies popped, waves cleared, the boss (wave 5) appeared and swapped
## element, counter hits happened, specials of several elements, Spirit State, the TV machine sees
## the raiders, the results + PLAY AGAIN restart work (local).
## BOT_GIVEUP=t: from t seconds on the bots stop fighting (and are one hit from going down) so the
## temple falls: checks the results screen, the VR card and PLAY AGAIN (a fresh wave 1, no practice).
## EB_SHOT=dir (windowed run, not headless): saves screenshots of the TV picture (and the VR mirror)
## to dir at a few moments, to check the look.
## Local:     godot --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/elemental_bender_bot.tscn
##            (EB_FAST=1 for short waves: wave 6 inside a minute)
## Networked: DUO_PORT=80xx DUO_HOST=1 BOT_VR=1 ... & DUO_PORT=80xx DUO_JOIN=127.0.0.1 ... (real time)

const BotKit := preload("res://tests/bot_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")
const E := preload("res://games/elemental_bender/elem.gd")

var kit: BotKit
var main: Node
var want := 2
var end_t := 58.0
var saw_results := false
var results_t := -1.0
var again_sent := false
var restarted := false
var max_raiders := 0
var max_wave := 0
var cd := {}  # slot -> {"elem": t, "special": t, "jump": t, "dash": t}
var client_saw_raiders := 0
var boss_alive_t := 0.0
var giveup_t := float(OS.get_environment("BOT_GIVEUP")) if OS.has_environment("BOT_GIVEUP") else -1.0
var wave_after_again := 0
var max_snap := 0
# Fake VR
var vr_state := "rest"
var vr_t := 0.0
var vr_need := 0
var vr_target := Vector3.ZERO
var vr_slam_t := 6.0
var vr_jab_t := 3.0
var vr_a_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	if OS.has_environment("EB_SHOT"):
		get_tree().root.set_meta("fullscreen_done", true)  # stay a small window
		for t in [7.0, 20.0, 32.0]:
			var at: float = t
			kit.at(at, "screenshot", func() -> void: _shot("t%d" % int(at)))
	main = load("res://games/elemental_bender/main.tscn").instantiate()
	add_child(main)
	kit.main = main
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	if OS.has_environment("BOT_END"):
		end_t = float(OS.get_environment("BOT_END"))
	elif host:
		end_t = 52.0
	elif client:
		end_t = 46.0
	kit.at(3.0 if client else 1.0, "%d TV players press A" % want, func() -> void:
		if main.net.mode != "host":
			for i in want:
				kit.join_bot(main.party))
	kit.every(4.0, _report)
	kit.every(0.25, _watch)
	kit.at(end_t, "finish", func() -> void:
		_checks()
		kit.finish())


func _watch() -> String:
	max_raiders = maxi(max_raiders, main.raiders.size())
	for r in main.raiders.values():
		if is_instance_valid(r) and r.boss:
			boss_alive_t += 0.25
	max_wave = maxi(max_wave, int(main.net.state_get("wave", 0)))
	if main.net.mode == "client":
		client_saw_raiders = maxi(client_saw_raiders, main.raiders.size())
	if main.results_showing():
		if not saw_results:
			saw_results = true
			results_t = kit.t
			kit.assert_true(main.split == null or main.results_ui != null, "the results screen shows on the TV")
			kit.assert_true(main.vr_rig == null or main.vr_results != null, "the results card shows in VR")
		if kit.t - results_t > 5.0 and not again_sent and main.net.mode != "client":
			again_sent = true
			kit.info("PLAY AGAIN")
			giveup_t = -1.0
			main.choose_end("again")
	elif again_sent and not restarted:
		restarted = true
		giveup_t = -1.0
	if restarted:
		wave_after_again = maxi(wave_after_again, int(main.net.state_get("wave", 0)))
	if giving_up() and main.net.mode != "client":
		for f in main.fighters(true):
			f.hp = minf(f.hp, 1.0)
	return ""


func giving_up() -> bool:
	return giveup_t >= 0.0 and kit.t > giveup_t


func _physics_process(delta: float) -> void:
	if main == null or not main.ready_to_play:
		return
	if giving_up():
		for slot in main.party.local_slots():
			kit.slot_stick(main.party, slot, "left", Vector2.ZERO)
			kit.pad_trigger(main.party.device_of(slot), "rt", 0.0)
		if main.vr_rig != null:
			kit.vr_trigger(main.vr_rig, 0.0)
		return
	for slot in main.party.local_slots():
		_tv_bot(slot, delta)
	if main.vr_rig != null:
		_vr_bot(delta)


func _nearest_target(from: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for t in main.targets_for(0):
		if not is_instance_valid(t):
			continue
		var n: Node3D = t
		var d := n.global_position.distance_to(from)
		if d < bd:
			bd = d
			best = n
	return best


func _tv_bot(slot: int, delta: float) -> void:
	var b = main.benders.get(slot)
	if b == null or not is_instance_valid(b):
		return
	var dev: int = main.party.device_of(slot)
	if dev < 0:
		return
	if not cd.has(slot):
		cd[slot] = {"elem": 0.0, "special": 3.0 + slot, "jump": 2.0, "dash": 4.0 + slot * 0.5, "spirit": 0.0}
	var c: Dictionary = cd[slot]
	for k in c:
		c[k] = float(c[k]) - delta
	var bp: Vector3 = b.global_position
	var target := _nearest_target(bp)
	if target == null or b.dead:
		kit.pad_trigger(dev, "rt", 0.0)
		var home := Vector3(0, 0, 0) - bp
		home.y = 0.0
		kit.slot_stick(main.party, slot, "left", _stick_for(slot, home.normalized() * 0.5) if home.length() > 4.0 else Vector2.ZERO)
		return
	var d: Vector3 = target.global_position - bp
	d.y = 0.0
	var dist := d.length()
	var dn := d / maxf(dist, 0.01)
	var cam = main.cams.get(slot)
	if cam != null:
		cam.yaw = atan2(-dn.x, -dn.z)
		cam.pitch = -0.25
	# The element that beats it.
	var te: int = int(target.get("element"))
	var need: int = E.beater(te)
	if b.element != need and float(c["elem"]) <= 0.0:
		c["elem"] = 0.4
		var pads: Array[String] = ["up", "left", "down", "right"]
		kit.slot_press(main.party, slot, pads[need])
	# Keep a good distance and circle a little.
	var mv := Vector3.ZERO
	if dist > 10.0:
		mv = dn
	elif dist < 5.0:
		mv = -dn
	else:
		mv = Vector3(-dn.z, 0.0, dn.x) * (0.5 if slot % 2 == 0 else -0.5)
	kit.slot_stick(main.party, slot, "left", _stick_for(slot, mv))
	kit.pad_trigger(dev, "rt", 1.0 if dist < 30.0 else 0.0)
	if float(c["jump"]) <= 0.0:
		c["jump"] = randf_range(3.0, 6.0)
		kit.slot_press(main.party, slot, "accept")
	if float(c["dash"]) <= 0.0 and dist > 12.0:
		c["dash"] = randf_range(4.0, 8.0)
		kit.slot_press(main.party, slot, "b")
	if float(c["special"]) <= 0.0 and dist < 8.0 and b.chi > 45.0:
		c["special"] = randf_range(4.0, 7.0)
		kit.slot_press(main.party, slot, "lt" if false else "y")
	if float(c["spirit"]) <= 0.0 and main.team_spirit_full():
		c["spirit"] = 2.0
		kit.slot_press(main.party, slot, "l3")


## A world direction -> this slot's stick (y DOWN), relative to the camera it sees.
func _stick_for(slot: int, dir: Vector3) -> Vector2:
	if dir.length() < 0.01:
		return Vector2.ZERO
	var b = main.benders.get(slot)
	var f: Vector3 = b.forward()
	var r := Vector3(-f.z, 0.0, f.x)
	return Vector2(dir.dot(r), -dir.dot(f)).limit_length(1.0)


func _vr_bot(delta: float) -> void:
	var rig: VrRig = main.vr_rig
	var m = main.master
	vr_t += delta
	vr_slam_t -= delta
	vr_jab_t -= delta
	vr_a_t -= delta
	rig.camera.position.y = 1.6
	var head := rig.head_position()
	var target := _nearest_target(head)
	if target != null:
		vr_target = target.global_position + Vector3.UP * float(target.get("hit_height"))
		kit.vr_look_at(rig, Vector3(vr_target.x, head.y - 0.2, vr_target.z))
	var xf: Transform3D = rig.global_transform
	var fwd := rig.head_forward()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var rest_r := head + right * 0.25 + Vector3.DOWN * 0.45 + fwd * 0.3
	var rest_l := head - right * 0.25 + Vector3.DOWN * 0.45 + fwd * 0.3
	if m.dead:
		kit.vr_trigger(rig, 0.0)
		return
	# Spirit State with A.
	if main.team_spirit_full() and vr_a_t <= 0.0:
		vr_a_t = 1.0
		kit.vr_a(rig, true)
	elif vr_a_t < 0.8:
		kit.vr_a(rig, false)
	match vr_state:
		"rest":
			kit.vr_trigger(rig, 0.0)
			kit.vr_reach(rig, VrRig.RIGHT, rest_r, 3.0, delta)
			kit.vr_reach(rig, VrRig.LEFT, rest_l, 3.0, delta)
			if vr_slam_t <= 0.0 and m.chi > 45.0:
				vr_slam_t = randf_range(7.0, 10.0)
				_vr_go("slam_up")
			elif vr_jab_t <= 0.0 and target != null:
				vr_jab_t = randf_range(3.0, 5.0)
				_vr_go("jab_wind")
			elif vr_t > 0.25 and target != null:
				vr_need = E.beater(int(target.get("element")))
				_vr_go("orb" if m.element != vr_need else "wind")
		"orb":
			kit.vr_reach(rig, VrRig.LEFT, rest_l, 3.0, delta)
			if kit.vr_reach(rig, VrRig.RIGHT, m.orb_position(vr_need), 4.0, delta) or m.element == vr_need or vr_t > 1.5:
				_vr_go("wind")
		"wind":
			var chest := head + right * 0.15 + Vector3.DOWN * (0.6 if m.element == E.EARTH else 0.3) + fwd * 0.15
			kit.vr_trigger(rig, 1.0)
			if kit.vr_reach(rig, VrRig.RIGHT, chest, 3.0, delta) or vr_t > 0.8:
				_vr_go("lift" if m.element == E.EARTH else "punch")
		"lift":
			kit.vr_trigger(rig, 1.0)
			if kit.vr_reach(rig, VrRig.RIGHT, head + right * 0.15 + Vector3.DOWN * 0.05 + fwd * 0.2, 3.5, delta) or vr_t > 0.6:
				_vr_go("punch")
		"punch":
			kit.vr_trigger(rig, 1.0)
			var to := (vr_target - head).normalized()
			if kit.vr_reach(rig, VrRig.RIGHT, head + right * 0.1 + to * 0.65 + Vector3.DOWN * 0.15, 4.0, delta) or vr_t > 0.5:
				_vr_go("rest")
		"jab_wind":
			if kit.vr_reach(rig, VrRig.LEFT, head - right * 0.15 + Vector3.DOWN * 0.3 + fwd * 0.1, 3.0, delta) or vr_t > 0.6:
				_vr_go("jab")
		"jab":
			var to2 := (vr_target - head).normalized()
			if kit.vr_reach(rig, VrRig.LEFT, head - right * 0.1 + to2 * 0.65 + Vector3.DOWN * 0.15, 5.0, delta) or vr_t > 0.4:
				_vr_go("rest")
		"slam_up":
			kit.vr_trigger(rig, 0.0)
			var a := kit.vr_reach(rig, VrRig.RIGHT, head + right * 0.25 + Vector3.UP * 0.3, 4.0, delta)
			var b := kit.vr_reach(rig, VrRig.LEFT, head - right * 0.25 + Vector3.UP * 0.3, 4.0, delta)
			if (a and b) or vr_t > 1.0:
				_vr_go("slam_down")
		"slam_down":
			var a2 := kit.vr_reach(rig, VrRig.RIGHT, head + right * 0.3 + Vector3.DOWN * 0.75 + fwd * 0.2, 5.0, delta)
			var b2 := kit.vr_reach(rig, VrRig.LEFT, head - right * 0.3 + Vector3.DOWN * 0.75 + fwd * 0.2, 5.0, delta)
			if (a2 and b2) or vr_t > 0.6:
				_vr_go("rest")
	if xf != rig.global_transform:
		pass


func _shot(tag: String) -> void:
	var dir := OS.get_environment("EB_SHOT")
	get_viewport().get_texture().get_image().save_png("%s/tv_%s.png" % [dir, tag])
	if main.vr_rig != null and main.vr_rig.mirror != null:
		main.vr_rig.mirror.get_texture().get_image().save_png("%s/vr_%s.png" % [dir, tag])
	if OS.has_environment("EB_DUMP"):
		_dump(main, "")


func _dump(n: Node, ind: String) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			var t := ""
			if c is Label:
				t = (c as Label).text
			print("DUMP %s%s %s %s '%s'" % [ind, c.name, c.get_class(), str((c as Control).get_global_rect()), t])
		elif c is Label3D:
			print("DUMP3D %s %s '%s' vis %s" % [c.get_path(), str((c as Label3D).global_position), (c as Label3D).text, str((c as Label3D).is_visible_in_tree())])
		_dump(c, ind + " ")


func _vr_go(s: String) -> void:
	vr_state = s
	vr_t = 0.0


func _report() -> String:
	var m = main.master
	if main.net.mode == "host":
		var sz := var_to_bytes(main.make_snapshot()).size()
		max_snap = maxi(max_snap, sz)
	return "BOT %s: phase %s wave %d raiders %d score %d spirit %d | benders %s | tv shots %d vr shots %d%s" % [
		main.net.mode, main.phase(), int(main.net.state_get("wave", 0)), main.raiders.size(),
		int(main.net.state_get("score", 0)), int(main.team_spirit()), str(main.benders.keys()), main.log_tv_shots,
		main.log_vr_shots, "" if m == null else " | VR punches %d jabs %d slams %d rocks %d orbs %d hp %d" % [
			m.punches, m.jabs, m.slams, m.rocks_lifted, m.orb_touches, int(m.hp)]]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode != "host":
		kit.assert_eq(main.party.player_count(), want, "%s: all %d TV players are seated" % [mode, want])
		kit.assert_true(main.log_tv_shots > 0, "%s: TV benders bent" % mode)
	if mode == "client":
		kit.assert_true(client_saw_raiders > 0, "client: raider ghosts mirrored from the host")
		kit.assert_true(max_wave >= 1, "client: waves reached the TV machine (%d)" % max_wave)
		return
	if mode == "host":
		kit.assert_true(max_snap < 1400, "host: snapshots stay small (max %d bytes before compression)" % max_snap)
	kit.assert_true(main.log_practice >= 1, "%s: practice dummies popped (%d)" % [mode, main.log_practice])
	kit.assert_true(max_wave >= 1, "%s: waves started (max %d)" % [mode, max_wave])
	kit.assert_true(main.log_counters > 0, "%s: counter hits x2 (%d)" % [mode, main.log_counters])
	kit.assert_true(max_raiders <= main.MAX_ALIVE, "%s: at most %d raiders alive (%d)" % [mode, main.MAX_ALIVE, max_raiders])
	kit.assert_true(main.log_specials.size() >= 1, "%s: specials used %s" % [mode, str(main.log_specials)])
	if OS.has_environment("BOT_GIVEUP"):
		kit.assert_true(saw_results, "%s: the temple fell and the results showed" % mode)
		if mode != "client":
			kit.assert_true(restarted and wave_after_again >= 1, "%s: PLAY AGAIN started a new game (wave %d)" % [mode, wave_after_again])
		return
	# Wave 6 + the General inside 58 s needs the short test waves (EB_FAST=1, see the header).
	if mode == "local" and main.fast and not OS.has_environment("BOT_END"):
		kit.assert_true(max_wave >= 6 or saw_results, "local: reached wave 6 (max %d)" % max_wave)
		kit.assert_true(main.log_boss or saw_results, "local: the Shadow General appeared")
	if boss_alive_t > 6.0:
		kit.assert_true(main.log_boss_swaps > 0, "the General swapped elements (%d, alive %.1f s)" % [main.log_boss_swaps, boss_alive_t])
	if main.vr_rig != null:
		var m = main.master
		kit.assert_true(m.punches > 0 and main.log_vr_shots > 0, "VR: punches fired (%d)" % m.punches)
		kit.assert_true(m.orb_touches > 0, "VR: orbs touched (%d)" % m.orb_touches)
		kit.assert_true(m.jabs > 0, "VR: left jabs (%d)" % m.jabs)
		kit.assert_true(m.slams > 0, "VR: slam specials (%d)" % m.slams)
		kit.assert_true(int(main.log_hits_by.get(0, 0)) > 0, "VR: the master hit raiders (%d)" % int(main.log_hits_by.get(0, 0)))
	print("BOT stats: practice %d waves %d boss %s swaps %d counters %d ring outs %d specials %s spirits %d downs %d hits %s" % [
		main.log_practice, main.log_waves, str(main.log_boss), main.log_boss_swaps, main.log_counters, main.log_ring_outs,
		str(main.log_specials), main.log_spirits, main.log_downs, str(main.log_hits_by)])
