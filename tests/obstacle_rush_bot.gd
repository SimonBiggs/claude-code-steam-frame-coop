extends Node
## Headless bot for games/obstacle_rush. TV bots (BOT_PLAYERS, default 2) steer their runner with
## the stick and A, using the same route brain as the CPU runners. The fake VR giant (BOT_VR=1)
## grabs balls from the bucket and throws them (first at the practice target, then at runners),
## and pokes the spinner, pads, doors, flag and a runner with its gloves.
## Design check: every course gets finished on foot (not only by the hop-in), and the show ends
## with the results; the giant's practice target gets hit.
## Local:     godot-test --headless --path . --fixed-fps 60 --quit-after 15000 res://tests/obstacle_rush_bot.tscn
## Networked: DUO_PORT=83xx DUO_HOST=1 BOT_VR=1 ... & DUO_PORT=83xx DUO_JOIN=127.0.0.1 ... (real time)
## OR_COURSE=n starts at lesson n (0..3). OR_SHOWS=n plays as if n shows were done (default 0: the lessons,
## then the next show is seeded; OR_SHOWS=3 starts on seeded courses at tier 2). BOT_NO_DAILY skips TODAY'S
## COURSE. Also checks: stars get grabbed and the grandstand gains fans (story.gd), every seeded course
## the show plays passes coursegen.gd check(), and the client builds the very same course as the host.
## Second pass (deep.gd): the bot plays as if OR_SHOWS (default 2) shows were done, so the mode and gift picks come up:
## TV runners walk under a start orb and stand there (each bot its own), the VR giant alone reaches into a small orb in
## front of it; runners wait just before a told surprise (OR_TRICKS_NOW is set: surprises on a show's first course
## too; BOT_NO_TRICKS=1 for none). OR_SHOWS=0 plays the lessons (and the practice target).

const BotKit := preload("res://tests/bot_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")
const CpuBrain := preload("res://games/obstacle_rush/cpu_brain.gd")
const CourseGen := preload("res://games/obstacle_rush/coursegen.gd")
const Story := preload("res://games/obstacle_rush/story.gd")
const Deep := preload("res://games/obstacle_rush/deep.gd")

var kit: BotKit
var main: Node
var want := 2
var brains := {}  # slot -> CpuBrain
var saw_results := false
var again_t := -1.0
var vr_step := "idle"
var vr_t := 0.0
var vr_throws := 0
var pokes := {}
var throw_to := Vector3.ZERO
var poke_i := 0
var fans0 := -1
var grabs := 0
var course_keys := {}  # var_to_str(cdesc) -> course name
var gen_checked := 0
var short := false  ## the run ends before the bot's whole run (solo VR host BOT_END=62, a 60 s local run)
var saw_orbs := false
var saw_vr_orbs := false
var waited := 0  # times a bot runner waited before a told surprise
var fence_ok := true  # nobody ran past the start while the orbs were up
var hz_seen := {}  # kind -> true (every machine)
var on_lessons := false  # host / local: orbs or a surprise during the lessons show


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/obstacle_rush/main.tscn").instantiate()
	main.force_shows = int(OS.get_environment("OR_SHOWS")) if OS.has_environment("OR_SHOWS") else 2
	if not OS.has_environment("BOT_NO_TRICKS"):
		OS.set_environment("OR_TRICKS_NOW", "1")
	add_child(main)
	kit.main = main
	kit.watch_state(main.net)  # phases counted as they happen (kit.seen): a 0.25 s poll misses quick ones under load
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	kit.at(3.0 if client else 1.0, "%d TV players press A" % want, func() -> void:
		if main.net.mode != "host":
			for i in want:
				kit.join_bot(main.party)
		elif not main.net.has_vr:
			kit.join_bot(main.party))  # a flat host (TV / Deck hosting): one pad hero here, in slot 0
	main.fake_door_hit.connect(func(rid: int, k: int) -> void:
		if brains.has(rid) and k < main.course.doors.size():
			var d: Dictionary = main.course.doors[k]
			(brains[rid] as CpuBrain).bonked_door(float(d["x"]), float(d["z"])))
	kit.every(4.0, _report)
	kit.every(0.5, _results)
	var full := 150.0 if host else (140.0 if client else 230.0)
	var end: float = preload("res://tests/bot_end.gd").end_at(full)  # (BOT_END, --quit-after, the runner's deadline)
	short = end < full - 1.0
	kit.at(end, "finish", func() -> void:
		_checks()
		kit.finish())


func _results() -> String:
	if fans0 < 0 and main.ready_to_play:
		fans0 = int(main.net.state_get("fans", 0))
	var bits := int(main.net.state_get("stars", 0))
	var got := 0
	for k in 8:
		got += 1 if bits & (1 << k) else 0
	grabs = maxi(grabs, got)
	var d: Dictionary = main.net.state_get("cdesc", {})
	var key := var_to_str(d)
	if not d.is_empty() and not course_keys.has(key) and main.built_key == key:
		course_keys[key] = main.course.course_name()
		var c: Dictionary = CourseGen.make(d)
		for w in CourseGen.check(c):
			kit.assert_true(false, "%s course %s passes the validator: %s" % [main.net.mode, c.name, w])
		gen_checked += 1
		if gen_checked == 1:
			print("BOT AGREE first_course=%s/%d" % [String(c.name), int(d.get("s", 0))])
		kit.assert_eq(var_to_str(main.course.desc.floors), var_to_str(c.floors), "%s built the described course %s" % [main.net.mode, c.name])
		kit.info("course %s (%s, tier %d): pieces %s, %d stars" % [c.name, String(d.get("k", "")), int(d.get("tier", -1)), str(c.pieces), (c.stars as Array).size()])
	if main.results_showing():
		if not saw_results:
			saw_results = true
			kit.assert_true(main.split == null or main.results_ui != null, "the results screen shows on the TV")
			kit.assert_true(main.vr_rig == null or (main.again_btn != null and main.again_btn.visible), "the AGAIN button shows in VR")
			again_t = kit.t
		if kit.t - again_t > 4.0:
			var slots: Array[int] = main.party.local_slots()
			if not slots.is_empty():
				kit.slot_press(main.party, slots[0], "accept")
			elif main.vr_rig != null:
				main.net.request(0, "again")
	return ""


func _physics_process(delta: float) -> void:
	if main == null or not main.ready_to_play or main.course == null:
		return
	if main.picks != null and main.picks.showing():
		saw_orbs = true
		saw_vr_orbs = saw_vr_orbs or bool(main.picks.vr_row)
		if String(main.net.state_get("phase", "")) == "pick" and not main.course.desc.is_empty():
			for r in main.runners.values():
				if r.owned and r.position.x > main.course.start_x + Deep.FENCE + 0.05:
					fence_ok = false
	for e in main.hazards.tells_now():
		hz_seen[String(e.kind)] = true
	if main.net.mode != "client" and main.show_no == 0 and (main.picks.showing() or not main.hazards.tells_now().is_empty()):
		on_lessons = true
	for slot in main.party.local_slots():
		_tv_bot(slot, delta)
	if main.vr_rig != null:
		_vr_bot(delta)


## A TV bot: think like a CPU runner, then push the stick and press A like a person.
func _tv_bot(slot: int, delta: float) -> void:
	if not main.runners.has(slot):
		return
	var r = main.runners[slot]
	if not brains.has(slot):
		var b := CpuBrain.new()
		b.reset(slot * 17 + 3)
		brains[slot] = b
	var br: CpuBrain = brains[slot]
	if br.get_meta("course", "") != main.built_key:  # a new course: forget the old doors
		br.set_meta("course", main.built_key)
		br.reset(slot * 17 + 3 + main.built_key.length())
	br.think(r, main.course, delta)
	# Pick orbs over the start: walk under one (each bot its own) and stand there.
	if main.picks.showing() and not main.picks.vr_row and not main.picks.spots.is_empty():
		var sp: Vector3 = main.picks.spots[slot % main.picks.spots.size()]
		var to := Vector3(sp.x - r.position.x, 0.0, sp.z - r.position.z)
		br.out_move = to.normalized() if to.length() > 0.2 else Vector3.ZERO
		br.out_jump = false
	elif main.hazards.wait_for(r.position):  # a surprise told just in front: wait for it
		if br.out_move != Vector3.ZERO:
			waited += 1
		br.out_move = Vector3.ZERO
		br.out_jump = false
	var cam: Camera3D = main.split.active_camera(slot)
	var f := -cam.global_basis.z
	f.y = 0.0
	f = f.normalized()
	var right := Vector3(-f.z, 0.0, f.x)
	var mv := Vector2(br.out_move.dot(right), br.out_move.dot(f))  # pad y DOWN is backwards
	kit.slot_stick(main.party, slot, "left", Vector2(mv.x, -mv.y))
	if br.out_jump:
		kit.slot_press(main.party, slot, "accept")


## Fake VR giant: throw balls (practice target first), then poke things.
func _vr_bot(delta: float) -> void:
	var rig = main.vr_rig
	var g = main.giant
	kit.vr_head_height(rig)  # the standard fake player (VrRig.fake_eye, x world_scale)
	vr_t += delta
	if main.picks.showing() and main.picks.vr_row:  # the small orbs in front of the giant: reach into one and stay
		kit.vr_trigger(rig, 0.0)
		var op: Vector3 = main.picks.orb_position(2)
		if op != Vector3.INF and main.picks.t > 1.0:
			kit.vr_reach(rig, VrRig.RIGHT, op, 12.0, delta)
		vr_step = "idle"
		return
	match vr_step:
		"idle":
			if String(main.net.state_get("phase", "")) != "play":
				return
			if vr_t > 2.0 and main.course_t > 2.5:
				vr_step = "reach"
				vr_t = 0.0
		"reach":
			var i: int = g._free_ball()
			if i < 0:
				vr_step = "poke"
				return
			if kit.vr_reach(rig, VrRig.RIGHT, g.balls[i].global_position, 30.0, delta) or vr_t > 2.0:
				kit.vr_trigger(rig, 1.0)
				vr_step = "wind"
				vr_t = 0.0
				throw_to = main.course.target_pos if main.course.target != null else _runner_target()
		"wind":
			var hp: Vector3 = rig.hand_point(VrRig.RIGHT)
			kit.vr_reach(rig, VrRig.RIGHT, Vector3(hp.x, 1.0, 6.0), 30.0, delta)
			if vr_t > 0.4:
				vr_step = "throw"
				vr_t = 0.0
		"throw":
			# Swing towards the target fast enough for a lob (ball speed ~ hand speed * 0.85).
			var hp2: Vector3 = rig.hand_point(VrRig.RIGHT)
			var to: Vector3 = throw_to + Vector3(0.0, 4.0, 0.0) - hp2
			kit.vr_reach(rig, VrRig.RIGHT, hp2 + to.normalized() * 2.0, 16.0, delta)
			if vr_t > 0.12:
				kit.vr_trigger(rig, 0.0)
				if OS.has_environment("BOT_DEBUG"):
					kit.info("throw from %s hand v %s to %s" % [hp2, rig.hand_velocity(VrRig.RIGHT), throw_to])
					get_tree().create_timer(0.5).timeout.connect(func() -> void:
						for b in main.giant.balls:
							kit.info("  ball %s v %s" % [b.global_position, b.linear_velocity]))
				vr_throws += 1
				vr_step = "poke" if vr_throws % 3 == 0 else "idle"
				vr_t = 0.0
		"poke":
			var spot: Vector3 = _poke_spot()
			if spot == Vector3.INF:
				vr_step = "idle"
				return
			if kit.vr_reach(rig, VrRig.LEFT, spot, 25.0, delta) or vr_t > 2.5:
				if vr_t > 0.3:
					pokes[poke_i] = true
					poke_i += 1
					vr_step = "idle"
					vr_t = 0.0
					kit.vr_reach(rig, VrRig.LEFT, spot + Vector3(0, 4, 3), 1000.0, 1.0)


func _runner_target() -> Vector3:
	for r in main.runners.values():
		if not r.done and r.position.x > -8.0:
			return r.position + Vector3(1.5, 0.0, 0.0)
	return Vector3(0, 0, 0)


func _poke_spot() -> Vector3:
	var c = main.course
	match poke_i % 5:
		0:
			if c.spinner != null:
				return c.spin_c + Vector3(0.0, 1.85, 0.0)
		1:
			if not c.pads.is_empty():
				return c.pads[0] + Vector3(0, 0.4, 0)
		2:
			if not c.doors.is_empty():
				return Vector3(float(c.doors[0]["x"]), 1.1, float(c.doors[0]["z"]))
		3:
			return c.flag.global_position + Vector3(0.6, 2.4, 0)
		4:
			for r in main.runners.values():
				return r.position + Vector3(0, 0.6, 0)
	poke_i += 1
	return Vector3(0, 6, 4)


func _report() -> String:
	var parts: Array[String] = []
	for rid in main.runners:
		var r = main.runners[rid]
		parts.append("%d:(%.0f,%.0f)%s" % [int(rid), r.position.x, r.position.y, "*" if r.done else ""])
	return "BOT %s: course %d phase %s t %.0f flags %d runners %s" % [main.net.mode, int(main.net.state_get("course", 0)),
		String(main.net.state_get("phase", "")), main.course_t, int(main.net.state_get("flags", 0)), " ".join(parts)]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode != "host":
		kit.assert_eq(kit.seated(), kit.seated_want(want), "%s: all %d TV players are seated" % [mode, want])
	kit.check_host_mode(main.net, main.mode)  # the TV machine plays at the host's mode ("deep" state)
	var several := 2 if short else 3  # (a cut-short run: solo VR host BOT_END=62, a 60 s local run)
	var courses := kit.seen_values("course").size()
	kit.assert_true(courses >= several, "%s: played through several courses (%d%s)" % [mode, courses, ", short run" if short else ""])
	kit.assert_true(gen_checked >= several, "%s: checked the courses it built (%d)" % [mode, gen_checked])
	kit.assert_true(main.stands.fans == mini(int(main.net.state_get("fans", 0)), Story.MAX_FANS), "%s: the grandstand shows the fans (%d)" % [mode, main.stands.fans])
	_deep_checks(mode)
	if mode == "client":
		kit.assert_true(main.runners.size() >= 3, "client mirrors the runners (%d)" % main.runners.size())
		kit.assert_true(main.course.checkpoints.size() > 0, "client built the course")
		return
	if not short:
		kit.assert_true(kit.seen("phase", "results") > 0, "%s: the show ended with the results" % mode)
	kit.assert_true(short or int(main.net.state_get("fans", 0)) > fans0, "%s: fans joined the grandstand (%d -> %d)" % [mode, fans0, int(main.net.state_get("fans", 0))])
	kit.assert_true(grabs > 0, "%s: a star got grabbed" % mode)
	var natural := {}
	var log_by_course := {}
	for e in main.finish_log:
		var c: int = e[0]
		if bool(e[2]):
			natural[c] = int(natural.get(c, 0)) + 1
		if not log_by_course.has(c):
			log_by_course[c] = []
		(log_by_course[c] as Array).append("%d%s@%.0f" % [int(e[1]), "" if bool(e[2]) else "(hop)", float(e[3])])
	for c in log_by_course:
		kit.info("course %d finishes: %s" % [int(c), str(log_by_course[c])])
	for c in range(int(OS.get_environment("OR_COURSE")) if OS.has_environment("OR_COURSE") else 0, 4):
		if log_by_course.has(c):
			kit.assert_true(int(natural.get(c, 0)) >= 1, "course %d is finishable on foot" % c)
	if main.vr_rig != null:
		kit.assert_true(vr_throws > 0, "the fake VR giant threw balls (%d)" % vr_throws)
		kit.assert_true(main.ghost.shown, "the ghost glove showed the throw")
		if not OS.has_environment("OR_COURSE") and main.force_shows == 0:  # (the target is on the first lesson)
			kit.assert_true(int(main.net.state_get("target_hit", 0)) > 0, "the practice target got hit")
		kit.assert_true(pokes.size() >= 3, "the giant poked things (%d)" % pokes.size())


## Second pass: picks, surprises, seasons, the medal hall (deep.gd).
func _deep_checks(mode: String) -> void:
	var lessons: bool = main.force_shows == 0
	kit.assert_true(main.season_node != null and main.season_node.season != "", "%s: the course is dressed for the season (%s)" % [mode, main.season])
	kit.assert_true(main.hall != null and main.hall.total >= 0, "%s: the medal hall is built (%d)" % [mode, main.hall.total])
	kit.assert_true(Deep.MODES.has(main.mode), "%s: a mode is set (%s)" % [mode, main.mode])
	kit.assert_true(fence_ok, "%s: nobody ran into the course while the orbs were up" % mode)
	kit.info("%s: mode %s, gift %s, season %s, surprises seen %s, bots waited %d, vr orbs %s, picks %s" % [mode, main.mode,
		main.gift, main.season, str(hz_seen.keys()), waited, str(saw_vr_orbs), str(main.picks.history)])
	if lessons:
		kit.assert_true(not on_lessons, "%s: the lessons have no picks or surprises" % mode)
		return
	kit.assert_true(saw_orbs, "%s: the pick orbs showed" % mode)
	if not OS.has_environment("BOT_NO_TRICKS"):
		kit.assert_true(not hz_seen.is_empty(), "%s: Coach Jelly's surprises were told %s" % [mode, str(main.hazards.seen)])
	if mode == "client":
		return
	var stages: Array = main.picks.history.map(func(h: Array) -> String: return String(h[0]))
	var forced := OS.has_environment("OR_MODE")  # (OR_MODE skips the mode pick: a networked run at the host's HARD)
	kit.assert_true(forced or stages.has("mode"), "%s: the mode was picked %s" % [mode, str(main.picks.history)])
	if not short:
		kit.assert_true(stages.has("gift"), "%s: a gift was picked before a later course %s" % [mode, str(main.picks.history)])
		kit.assert_true(int(main.save.data.medal_total) > 0 and main.hall.total == int(main.save.data.medal_total), "%s: a medal went up in the hall (%d)" % [mode, main.hall.total])
	var people: bool = main._people() > 0
	var by_someone := false
	for h in main.picks.history:
		if int(h[2]) >= 0:
			by_someone = true
	if people or main.vr_rig != null:
		kit.assert_true(by_someone, "%s: a player really picked an orb (not just the wait) %s" % [mode, str(main.picks.history)])
	if main.vr_rig != null and not people:
		kit.assert_true(saw_vr_orbs, "%s: VR alone: the orbs float in front of the giant" % mode)
	kit.assert_true(forced or String(main.save.data.mode) != "", "%s: the mode is saved" % mode)
