extends Node
## Headless bot for games/mech_titans (MECH TITANS), built on tests/bot_kit.gd.
## It buys an upgrade in the hangar, launches a mission, plays the PRACTICE warm-up and the boss fight
## (fake-VR punches / beam / dash, or a pad pilot, or the autopilot), drives the TV support vehicles
## (jets paint weak spots, rescue trucks rescue, repair drones repair, stun tanks stun), sees the
## results, and goes back to the hangar.
## Env: BOT_PLAYERS=n TV pads (default 2; locally without VR the first pad pilots the Titan),
## BOT_VR=1 fake VR pilot, MT_MISSION=n play mission n's boss (no practice; default: mission 1 with
## the practice warm-up, boss only).
## Local:      godot --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/mech_titans_bot.tscn
## Networked:  DUO_PORT=8090 DUO_HOST=1 ... & DUO_PORT=8090 DUO_JOIN=127.0.0.1 ... (same scene, real time)

const BotKit := preload("res://tests/bot_kit.gd")
const Data := preload("res://games/mech_titans/data.gd")
const Kaiju := preload("res://games/mech_titans/kaiju.gd")
const VrRig := preload("res://core/vr_rig.gd")

var kit: BotKit
var main: Node
var want := 2
var mission := 0
var practice := true
var host := false
var client := false
var saw_play := false
var saw_results := false
var saw_kaiju := false
var saw_practice := false
var saw_painted := false
var back_in_hangar := false
var results_win := false
var vr_punches := 0
var vr_beam_t := 0.0
var _held := {}  ## slot -> {action: bool}
var _punch_t := 0.0
var _punch_hand := 0
var _punch_step := 0.0
var _dash_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)  # first: real controllers are ignored, saves go to user://test_saves/
	main = load("res://games/mech_titans/main.tscn").instantiate()
	if OS.has_environment("MT_MISSION"):
		mission = clampi(int(OS.get_environment("MT_MISSION")), 0, Data.MISSIONS.size() - 1)
		practice = false
	main.set("test_boss_only", true)
	main.set("test_practice", practice)
	main.set("test_hp_scale", 1.0 if practice else 0.6)
	add_child(main)
	kit.main = main
	want = BotKit.bot_players(2, 6)
	client = OS.has_environment("DUO_JOIN")
	host = OS.has_environment("DUO_HOST")
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d TV players press A on their pads" % want, _join)
	if not client:
		kit.at(t0 + 1.5, "the hangar gets some parts to spend", func() -> void:
			main.save.data["parts"] = 400
			var cl: Array = main.save.data["cleared"]
			for i in mission:
				if not cl.has(i):
					cl.append(i)  # MT_MISSION: unlock the missions before it
			main._publish_save())
	var item := "thrusters" if client else "armour2"
	kit.at(t0 + 3.0, "buy %s in the hangar" % item, func() -> void:
		var s := _menu_slot()
		main._menu_chosen("upgrades", s == 0 and main.vr_rig != null, s)
		main._menu_chosen("u_" + item, s == 0 and main.vr_rig != null, s))
	if not client:
		kit.at(12.0 if host else t0 + 5.0, "choose the mission and launch", func() -> void:
			kit.assert_true(main.has_upgrade("armour2"), "the upgrade was bought (saved parts went down)")
			var s := _menu_slot()
			var vr: bool = s == 0 and main.vr_rig != null
			main._hangar("select", str(mission))
			main._menu_chosen("launch", vr, s))
	if host:
		kit.at(50.0, "host checks (the TV machine is still connected)", _checks)
		kit.at(58.0, "finish", kit.finish)
	else:
		kit.at(52.0 if client else 57.0, "checks", func() -> void:
			_checks()
			kit.finish())
	kit.every(2.0, _report)
	kit.every(0.4, _flow)


func _menu_slot() -> int:
	var seats: Array[int] = main.party.local_slots()
	if main.vr_rig != null or seats.is_empty():
		return 0
	return seats[0]


func _join() -> void:
	if main.net.mode == "host":
		return  # the TV machine brings the pads in the networked test
	for i in want:
		kit.join_bot(main.party)


## Briefing: skip lines; results: continue.
func _flow() -> String:
	var phase := String(main.net.state_get("phase", ""))
	if phase == "play":
		if not saw_play and main.net.mode != "client":
			main.mech.armour = main.mech.armour_max * 0.6  # a bump, so the repair drones get work
		saw_play = true
	if phase == "briefing" and main.dlg.is_playing():
		if main.net.mode == "client":
			main._client_advance()
		else:
			main.dlg.advance()
	if phase == "results":
		if not saw_results:
			saw_results = true
			var data: Dictionary = main.net.state_get("results", {})
			results_win = bool(data.get("win", false))
			kit.assert_true(main.split == null or main.results_ui != null, "the results screen shows on the TV")
			kit.assert_true(main.vr_rig == null or main.vr_results != null, "the results card shows in VR")
			kit.info("RESULTS: win %s, stars %d, parts %d" % [str(results_win), int(data.get("stars", 0)), int(data.get("parts", 0))])
		if main.net.mode != "client":
			main.on_request(0, "continue", [])
	if phase == "hangar" and saw_results:
		back_in_hangar = true
	return ""


func _physics_process(delta: float) -> void:
	if main == null or not main.ready_to_play or main.city == null:
		return
	var phase := String(main.net.state_get("phase", ""))
	for id in main.combat.kaiju:
		var k: Kaiju = main.combat.kaiju[id]
		saw_kaiju = true
		if k.state == "practice":
			saw_practice = true
		if k.any_painted():
			saw_painted = true
	for slot in main.party.local_slots():
		if slot == 0:
			_drive_pad_pilot(slot, delta, phase)
		else:
			_drive_vehicle(slot, phase)
	if main.vr_rig != null:
		_drive_vr(delta, phase)


# --- TV support vehicles ------------------------------------------------------------------------------

func _hold(slot: int, action: String, down: bool) -> void:
	var h: Dictionary = _held.get(slot, {})
	if bool(h.get(action, false)) == down:
		return
	h[action] = down
	_held[slot] = h
	kit.slot_hold(main.party, slot, action, down)


func _target_kaiju(from: Vector3) -> Kaiju:
	var best: Kaiju = null
	var bd := INF
	for id in main.combat.kaiju:
		var k: Kaiju = main.combat.kaiju[id]
		if not k.is_active():
			continue
		var d := from.distance_to(k.global_position) - (1000.0 if not k.is_mini else 0.0)
		if d < bd:
			bd = d
			best = k
	return best


func _unpainted(k: Kaiju) -> int:
	for i in k.weak.size():
		var w: Dictionary = k.weak[i]
		if not bool(w["broken"]) and float(w["painted"]) <= 0.0:
			return i
	return -1


func _drive_vehicle(slot: int, phase: String) -> void:
	var v: Node3D = main.support.vehicles.get(slot, null)
	var c = main.cams.get(slot, null)
	if v == null or c == null:
		return
	if phase != "play":
		kit.slot_stick(main.party, slot, "left", Vector2.ZERO)
		_hold(slot, "accept", false)
		_hold(slot, "x", false)
		return
	var kind: String = v.get("kind")
	var pos := v.global_position
	var goal := pos
	var aim := Vector3.INF
	var a := false
	var x := false
	var mech: Node3D = main.mech
	match kind:
		"jet", "tank":
			var k := _target_kaiju(pos)
			if k != null:
				var to := k.global_position - pos
				to.y = 0.0
				goal = k.global_position - to.normalized() * (24.0 if kind == "jet" else 30.0)
				var wi := _unpainted(k)
				if wi >= 0 and kind == "jet":
					aim = k.weak_world(wi)
					x = true
				else:
					aim = k.center() + (Vector3.UP * 4.0 if kind == "tank" else Vector3.ZERO)
					a = kind == "jet" or int(Time.get_ticks_msec() / 1200) % 2 == 0
		"truck":
			var carry: int = v.get("carry")
			var gi: int = main.support._nearest_group(pos)
			if carry > 0 and (carry >= 2 or gi < 0):
				goal = main.support._nearest_shelter(pos)
			elif gi >= 0:
				goal = main.support.groups[gi]["pos"]
		"drone":
			goal = mech.global_position + mech.global_basis.z * 6.0
			aim = mech.chest_world()
			a = pos.distance_to(mech.chest_world()) < 18.0
	if kind == "truck" or kind == "tank":
		goal = main.support._route(pos, goal)  # follow the roads around buildings
	var d := goal - pos
	d.y = 0.0
	if aim != Vector3.INF:
		var ad := (aim - (pos + Vector3(0, 2.5, 0))).normalized()
		c.yaw = atan2(-ad.x, -ad.z)
		c.pitch = clampf(asin(clampf(ad.y, -1.0, 1.0)), c.pitch_min, c.pitch_max)
	else:
		c.yaw = atan2(-d.x, -d.z) if d.length() > 0.5 else c.yaw
	var cam: Camera3D = main.view_camera(slot)
	var stick := Vector2.ZERO
	if d.length() > 3.0 and cam != null:
		var f := -cam.global_basis.z
		f.y = 0.0
		f = f.normalized()
		var r := Vector3(-f.z, 0.0, f.x)
		var dn := d.normalized()
		stick = Vector2(dn.dot(r), -dn.dot(f))
	kit.slot_stick(main.party, slot, "left", stick)
	_hold(slot, "accept", a)
	_hold(slot, "x", x)


# --- The pilot ------------------------------------------------------------------------------------------

## Local play without a headset: slot 0 pilots the Titan with a pad.
func _drive_pad_pilot(slot: int, delta: float, phase: String) -> void:
	var c = main.cams.get(slot, null)
	var cam: Camera3D = main.view_camera(slot)
	if c == null or cam == null or phase != "play":
		kit.slot_stick(main.party, slot, "left", Vector2.ZERO)
		_hold(slot, "rb", false)
		return
	var mech: Node3D = main.mech
	var k := _pilot_target()
	if k == null:
		kit.slot_stick(main.party, slot, "left", Vector2.ZERO)
		_hold(slot, "rb", false)
		return
	var to := k.global_position - mech.global_position
	to.y = 0.0
	var reach := k.radius + 5.5
	var aim := k.aim_point()
	var ad := (aim - cam.global_position).normalized()
	c.yaw = atan2(-ad.x, -ad.z)
	c.pitch = clampf(asin(clampf(ad.y, -1.0, 1.0)), c.pitch_min, c.pitch_max)
	var stick := Vector2.ZERO
	if to.length() > reach and (k.can_punch or k.state == "practice" and k.alt < 8.0):
		var f := -cam.global_basis.z
		f.y = 0.0
		f = f.normalized()
		var r := Vector3(-f.z, 0.0, f.x)
		var dn := to.normalized()
		stick = Vector2(dn.dot(r), -dn.dot(f))
	kit.slot_stick(main.party, slot, "left", stick)
	_punch_t -= delta
	if to.length() < reach + 1.5 and k.can_punch and _punch_t <= 0.0:
		_punch_t = 0.5
		kit.slot_press(main.party, slot, "x")
	_hold(slot, "rb", to.length() > reach and main.mech.energy > 15.0)


## What the pilot goes for: practice targets, dizzy bosses (finishing punch), then the boss.
func _pilot_target() -> Kaiju:
	var best: Kaiju = null
	var score := INF
	for id in main.combat.kaiju:
		var k: Kaiju = main.combat.kaiju[id]
		if k.state == "home" or k.state == "gone" or k.state == "grabbed" or k.state == "thrown":
			continue
		var s: float = (main.mech as Node3D).global_position.distance_to(k.global_position)
		if k.state == "dizzy":
			s -= 2000.0
		elif k.state == "practice":
			s -= 1000.0
		elif not k.is_mini:
			s -= 500.0
		if s < score:
			score = s
			best = k
	return best


## Fake VR: walk with the stick, throw real (fast) punches with alternating hands, point the right hand
## and hold the trigger for the beam, dash with A now and then. Positions are rig-local (the rig rides in
## the cockpit).
func _drive_vr(delta: float, phase: String) -> void:
	var rig: VrRig = main.vr_rig
	var head := Vector3(0, 1.6, 0)
	var rest_l := Vector3(-0.25, 1.15, -0.3)
	var rest_r := Vector3(0.25, 1.15, -0.3)
	rig.camera.position = head
	rig.camera.basis = Basis()
	var k: Kaiju = _pilot_target() if phase == "play" else null
	if k == null:
		kit.vr_stick(rig, Vector2.ZERO)
		kit.vr_trigger(rig, 0.0)
		rig.hand_l.position = rest_l
		rig.hand_r.position = rest_r
		rig.hand_l.basis = Basis()
		rig.hand_r.basis = Basis()
		kit.vr_a(rig, false)
		return
	var mech: Node3D = main.mech
	var to := k.global_position - mech.global_position
	to.y = 0.0
	var reach := k.radius + 5.5
	var close := to.length() < reach + 1.5 and k.can_punch
	# Turn towards it with the right stick, walk with the left.
	var fwd: Vector3 = mech.call("forward")
	fwd.y = 0.0
	var ang := fwd.signed_angle_to(to.normalized(), Vector3.UP)
	var turn := clampf(-ang * 2.0, -1.0, 1.0)
	var walk := 0.0
	if to.length() > reach and (k.can_punch or k.state == "practice" and k.alt < 8.0):
		walk = 1.0 if absf(ang) < 0.6 else 0.3
	kit.vr_stick(rig, Vector2(0.0, walk), Vector2(turn, 0.0))
	_dash_t -= delta
	kit.vr_a(rig, false)
	if walk > 0.9 and to.length() > 40.0 and _dash_t <= 0.0:
		_dash_t = 6.0
		kit.vr_a(rig, true)
	# Punches: pull back, then a fast jab forward (velocity, not a pose).
	if close and absf(ang) < 0.5:
		kit.vr_trigger(rig, 0.0)
		var h: Node3D = rig.hand(_punch_hand)
		var other: Node3D = rig.hand(1 - _punch_hand)
		other.position = rest_l if _punch_hand == 1 else rest_r
		_punch_step += delta
		var sx := -0.22 if _punch_hand == 0 else 0.22
		if _punch_step < 0.25:
			h.position = Vector3(sx, 1.35, -0.12)
		elif _punch_step < 0.4:
			var f := (_punch_step - 0.25) / 0.15
			h.position = Vector3(sx, 1.35, -0.12 - f * 0.5)
		else:
			_punch_step = 0.0
			_punch_hand = 1 - _punch_hand
			vr_punches += 1
		return
	# Beam: point the right hand at the target, hold the trigger.
	rig.hand_l.position = rest_l
	rig.hand_r.position = Vector3(0.25, 1.3, -0.45)
	var aim := k.aim_point()
	var hr: Node3D = rig.hand_r
	var dir := (aim - hr.global_position).normalized()
	if absf(dir.y) < 0.99:
		hr.global_basis = Basis.looking_at(dir, Vector3.UP)
	var on: bool = absf(ang) < 0.6 and main.mech.energy > 10.0
	kit.vr_trigger(rig, 1.0 if on else 0.0)
	if on:
		vr_beam_t += delta


# --- Report and checks ------------------------------------------------------------------------------------

func _report() -> String:
	if main == null or main.combat == null:
		return "BOT: starting"
	var bosses := 0
	var hp := 0.0
	for k in main.combat.active_bosses():
		var kk: Kaiju = k
		bosses += 1
		hp += kk.hp
	var dbg := ""
	var k := _pilot_target()
	if k != null:
		dbg += " | mech %s beam %s pilot %s | %s %s at %s d %.0f" % [str(main.mech.position.round()), str(main.mech.beam_on), main.pilot.mode,
			k.kind, k.state, str(k.position.round()), (main.mech as Node3D).position.distance_to(k.position)]
	return "BOT %s: phase %s, seats %s, veh %s, kaiju %d (bosses %d, hp %d), armour %d, score %d, saved %d" % [main.net.mode,
		String(main.net.state_get("phase", "")), str(main.party.active_slots()), str(main.net.state_get("veh", {})),
		main.combat.kaiju.size(), bosses, int(hp), int(main.mech.armour), int(main.net.state_get("score", 0)), int(main.net.state_get("rescued", 0))] + dbg


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	kit.assert_eq(main.party.player_count(), want, "%s: all %d TV players are seated" % [mode, want])
	kit.assert_true(saw_play, "%s: the mission was played" % mode)
	kit.assert_true(saw_kaiju, "%s: kaiju showed up" % mode)
	kit.assert_true(saw_results, "%s: the mission ended with results" % mode)
	if mode != "client":
		kit.assert_true(main.has_upgrade("armour2"), "the upgrade is owned")
		if host:
			kit.assert_true(main.has_upgrade("thrusters"), "the TV machine bought an upgrade too")
		kit.assert_true(results_win, "the mission was won (the boss went home)")
		kit.assert_true(back_in_hangar, "continue went back to the hangar")
		var cleared: Array = main.save.data.get("cleared", [])
		kit.assert_true(cleared.has(mission), "mission %d is saved as cleared" % (mission + 1))
		if practice:
			kit.assert_true(saw_practice and main.has_meta("practiced"), "the PRACTICE warm-up ran and finished")
		kit.assert_true(main.awards.total("assists") > 0 or saw_painted, "weak spots were painted")
		kit.assert_true(main.awards.total("rescues") > 0, "rescue trucks saved citizens")
		kit.assert_true(main.awards.total("healing") > 0, "repair drones repaired the Titan")
		kit.info("awards: assists %d, rescues %d, healing %d, stuns %d" % [int(main.awards.total("assists")),
			int(main.awards.total("rescues")), int(main.awards.total("healing")), int(main.awards.total("stuns"))])
		if main.vr_rig != null:
			kit.assert_true(vr_punches > 0 and vr_beam_t > 0.0, "the fake VR pilot punched and beamed")
	else:
		kit.assert_true(saw_painted, "client: painted weak spots were mirrored")
