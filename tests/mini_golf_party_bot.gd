extends Node
## Headless bot for games/mini_golf_party. TV bots (BOT_PLAYERS, default 2) aim with the stick at the
## hole's aim point and hold A for about the right power; the fake VR golfer (BOT_VR=1) teleports
## to its ball with A and swings the putter through it, and plays with the toys (duck, spare ball).
## Design check: every hole gets holed by the aiming bots within par + 3 on average.
## Local:     godot --headless --path . --fixed-fps 60 --quit-after 12000 res://tests/mini_golf_party_bot.tscn
## Networked: DUO_PORT=83xx DUO_HOST=1 BOT_VR=1 ... & DUO_PORT=83xx DUO_JOIN=127.0.0.1 ... (real time)
## Flat host: add DUO_FLAT_HOST=1 to the host (one bot pad plays on the host). DUO_MACHINE_KIND=deck: the
## Deck follow camera. Every machine checks it can SEE its own players' balls (in its camera's view, with
## their name tag) all game long (Simon on his Deck: "I can't see my ball").
## MGP_HOLE=n starts at hole n.
## Second pass (deep.gd): every bot putts at a pad of the pick green (the mode pick, then Gus's gift after the practice
## putt); the fake VR golfer reaches a hand into an orb when it is alone (or nobody has picked for a while). Surprises
## come from hole 2, soon after it starts (MGP_HAZARD_NOW, still fair: deep_test). Checks: the picks happened, every
## surprise was told before it happened (steady tells), the garden is dressed for the season, the corner matches the stars.

const BotKit := preload("res://tests/bot_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")
const Deep := preload("res://games/mini_golf_party/deep.gd")

var kit: BotKit
var main: Node
var want := 2
var hold := {}  # slot -> seconds left holding A
var vr_step := "idle"
var vr_t := 0.0
var vr_speed := 1.0
var vr_putts := 0
var toy_step := 0
var saw_results := false
var again_t := -1.0
var seen_checks := 0
var unseen: Array[String] = []
var unseen_streak := {}  # slot -> samples in a row it wasn't seen (a ball made this frame gets its tag next frame)
var short_run := false  # a short run (BOT_END): real progress, not a whole course
var deep := {}  # second pass seen: orbs, picks, tells, season, corner
var on_shown := {}  # surprise key -> seconds its tell had shown when it happened


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_environment("MGP_HAZARD_NOW"):
		OS.set_environment("MGP_HAZARD_NOW", "1")  # surprises from hole 2, soon (deep.gd bot spec: still fair)
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/mini_golf_party/main.tscn").instantiate()
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
			kit.join_bot(main.party))  # a flat host (DUO_FLAT_HOST=1): one pad player here
	kit.every(3.0, _report)
	kit.every(0.5, _results)
	kit.every(0.5, _own_balls_seen)
	kit.every(15.0, func() -> String: return "BOT DEEP %s: %s" % [main.net.mode, str(deep)])
	var end := 150.0 if host else (140.0 if client else 190.0)
	if client and OS.has_environment("BOT_LATE"):  # (tools/multibot.ts --late: joined late, leave before the host does)
		end -= float(OS.get_environment("BOT_LATE"))
	end = minf(end, preload("res://tests/bot_end.gd").end_at(end))  # BOT_END (solo VR host: 62), --quit-after, deadline
	short_run = end < 120.0
	kit.at(end, "finish", func() -> void:
		_checks()
		kit.finish())


## Every machine: each of its own players' balls is on its screen (inside the camera's view, not behind
## it) and carries a visible name tag. Sampled while a hole is being played.
func _own_balls_seen() -> String:
	if main.split == null or String(main.net.state_get("phase", "")) != "play" or main.course == null:
		return ""
	var cam: Camera3D = main.split.shared_camera()
	for slot in main.party.local_slots():
		if not main.balls.has(slot):
			continue
		var b: Node3D = main.balls[slot]
		seen_checks += 1
		var tag = main.tags.get(slot)
		var why := ""
		if not b.visible or not b.is_inside_tree():
			why = "hidden"
		elif not cam.is_position_in_frustum(b.global_position):
			why = "off screen at %s" % b.global_position
		elif tag == null or not is_instance_valid(tag) or not (tag as Label3D).visible:
			why = "no name tag"
		unseen_streak[slot] = int(unseen_streak.get(slot, 0)) + 1 if why != "" else 0
		if int(unseen_streak[slot]) >= 2 and unseen.size() < 6:
			unseen.append("%s ball %d %s (hole %d)" % [main.net.machine_kind, slot, why, int(main.net.state_get("hole", 0)) + 1])
	return ""


func _results() -> String:
	if main.results_showing():
		if not saw_results:
			saw_results = true
			kit.assert_true(main.split == null or main.results_ui != null, "the results screen shows on the TV")
			kit.assert_true(main.vr_rig == null or main.vr_results != null, "the results card shows in VR")
			again_t = kit.t
		if kit.t - again_t > 3.0:
			var slots: Array[int] = main.party.local_slots()
			if not slots.is_empty():
				kit.slot_press(main.party, slots[0], "accept")
			elif main.vr_rig != null:
				main.net.request(0, "again")
	return ""


func _physics_process(delta: float) -> void:
	if main == null or not main.ready_to_play or main.course == null:
		return
	_note_deep()
	for slot in main.party.local_slots():
		_tv_bot(slot, delta)
	if main.vr_rig != null:
		_vr_bot(delta)


## Speed a putt needs to reach `to` from `from` on this hole (the generator's proof uses the same rule).
func _speed_for(from: Vector2, to: Vector2) -> float:
	return main.HoleGen.putt_speed(main.course, from, to)


func _tv_bot(slot: int, delta: float) -> void:
	if not main.balls.has(slot):
		return
	var b = main.balls[slot]
	var arrow_on: bool = main.arrows.has(slot) and (main.arrows[slot] as Node3D).visible
	var bp := Vector2(b.position.x, b.position.z)
	var to: Vector2 = _target(slot, bp)
	if hold.has(slot):
		hold[slot] = float(hold[slot]) - delta
		if float(hold[slot]) <= 0.0:
			kit.slot_hold(main.party, slot, "accept", false)
			hold.erase(slot)
		return
	if not arrow_on:
		kit.slot_stick(main.party, slot, "left", Vector2.ZERO)
		return
	# Point the stick at the target (pad y DOWN = +Z on this course), then charge.
	var dir := (to - bp).normalized()
	kit.slot_stick(main.party, slot, "left", dir)
	if absf(angle_difference(float(main.aim.get(slot, 0.0)), dir.angle())) > 0.05:
		return
	kit.slot_stick(main.party, slot, "left", Vector2.ZERO)
	var v := _speed_for(bp, to)
	var p := clampf((v - 0.35) / 3.6, 0.05, 1.0)
	hold[slot] = p * main.CHARGE_TIME
	kit.slot_hold(main.party, slot, "accept", true)


## Fake VR golfer: A to stand behind the ball, wind back, swing through.
func _vr_bot(delta: float) -> void:
	var rig = main.vr_rig
	kit.vr_head_height(rig)  # the standard fake player (VrRig.fake_eye, x world_scale)
	vr_t += delta
	_toys(rig, delta)
	if toy_step in [1, 2, 3]:
		return
	if not main.balls.has(0):
		return
	var b = main.balls[0]
	var bp := Vector2(b.pos.x, b.pos.y)
	var to: Vector2 = _target(0, bp)
	var fwd := Vector3(to.x - bp.x, 0.0, to.y - bp.y).normalized()
	var reach: float = main.putter.max_reach
	if _vr_hand_pick(rig, delta):
		return
	match vr_step:
		"idle":
			if b.resting() and main.results_showing() == false and String(main.net.state_get("phase", "")) == "play":
				kit.vr_a(rig, true)
				vr_step = "teleport"
				vr_t = 0.0
		"teleport":
			kit.vr_a(rig, false)
			if vr_t > 0.3:
				vr_step = "wind"
				vr_t = 0.0
				vr_speed = _speed_for(bp, to) / main.VR_GAIN
		"wind":
			var start: Vector3 = b.position - fwd * (reach + 0.25)
			start.y = 0.8
			if kit.vr_reach(rig, VrRig.RIGHT, start, 1.5, delta) or vr_t > 2.0:
				vr_step = "swing"
				vr_t = 0.0
		"swing":
			var end: Vector3 = b.position - fwd * (reach - 0.3)
			end.y = 0.8
			kit.vr_reach(rig, VrRig.RIGHT, end, vr_speed, delta)
			if not b.resting():
				vr_putts += 1
				vr_step = "wait"
			elif vr_t > 2.0:
				vr_step = "idle"
		"wait":
			if b.resting() or b.state == "cup":
				vr_step = "idle"


## Once: poke the duck with the left glove, then throw a spare ball.
func _toys(rig, delta: float) -> void:
	var p = main.props
	match toy_step:
		0:
			if kit.t > 8.0 and main.vr_rig != null:
				toy_step = 1
				main.vr_rig.place(p.anchor + Vector3(0.6, 0.0, 0.4), 0.0)
		1:
			if kit.vr_reach(rig, VrRig.LEFT, p.duck.global_position + Vector3.UP * 0.15, 2.0, delta):
				toy_step = 2
		2:
			var s: Vector3 = p.spares[0].global_position
			if kit.vr_reach(rig, VrRig.RIGHT, s, 2.0, delta):
				kit.vr_trigger(rig, 1.0)
				toy_step = 3
				vr_t = 0.0
		3:
			kit.vr_reach(rig, VrRig.RIGHT, rig.hand_point(VrRig.RIGHT) + Vector3(0.0, 0.5, -1.0), 3.0, delta)
			if vr_t > 0.4:
				kit.vr_trigger(rig, 0.0)
				toy_step = 4
				vr_step = "idle"


## Where a bot aims: the hole's aim point, or on the pick green a pad (each player its own, changing every pick).
func _target(slot: int, bp: Vector2) -> Vector2:
	if main.course.pick and main.hole_def.has("pads"):
		var pads: Array = main.hole_def.pads
		return pads[(slot + main.picks.history.size()) % pads.size()]
	return main.course.aim_point(bp)


## The fake VR golfer picks by hand when it's alone or nobody has picked for a while: it walks up beside the orb
## and the left glove reaches into it and stays (picks.gd: a glove has to move in and stay a moment).
func _vr_hand_pick(rig, delta: float) -> bool:
	rig.camera.rotation.x = 0.0
	if main.net.mode == "client" or not main.picks.active() or main.picks.chosen >= 0:
		return false
	if not ((main.pick_solo() and main.picks.t > 3.0) or main.picks.t > 9.0):
		return false
	var i: int = 0 if main.picks.history.size() % 2 == 0 else 2
	var op: Vector3 = main.picks.orb_position(i)
	if op == Vector3.INF:
		return false
	var feet := Vector3(op.x + 0.25, 0.0, op.z + 0.55)
	if rig._place_feet.distance_to(feet) > 0.3:
		rig.place(feet, 0.0)  # (a real golfer walks up with the left stick)
	rig.camera.rotation.x = -0.75  # (and looks down at the orb they reach for)
	if int(main.picks.inside.get("l", -1)) == main.picks.RESTING:
		kit.vr_reach(rig, VrRig.LEFT, op + Vector3(-0.2, -0.35, 0.35), 1.5, delta)  # resting in one: take the hand out first
	else:
		kit.vr_reach(rig, VrRig.LEFT, op, 1.5, delta)
	return true


## The second pass: pick orbs, picks, surprise tells, the season, Gus's garden corner.
func _note_deep() -> void:
	if main.picks.showing():
		deep["orbs"] = true
	for h in main.picks.history:
		deep["pick_" + String(h[0])] = true
		deep["by_" + ("nobody" if int(h[2]) < 0 else ("vr" if int(h[2]) == 0 and main.vr_rig != null else "putt"))] = true
	for kind in main.hazards.seen:
		deep["told_" + String(kind)] = int(main.hazards.seen[kind])
	for kind in main.hazards.on_seen:
		deep["on_" + String(kind)] = true
	if main.hazards.early > 0:
		deep["early"] = main.hazards.early
	var hz: Dictionary = main.hz_now
	if String(hz.get("phase", "")) == "on" and not on_shown.has(main.hz_key):
		on_shown[main.hz_key] = main.hazards.shown_t
	if main.gift != "":
		deep["gift"] = main.gift
	deep["mode"] = main.mode
	deep["season"] = main.season
	deep["dressed"] = main.season_node.season
	deep["corner"] = main.corner.count


func _report() -> String:
	var parts: Array[String] = []
	for s in main.balls:
		var b = main.balls[s]
		parts.append("%d:%s/%d" % [int(s), String(b.state), int(b.strokes)])
	return "BOT %s: hole %d phase %s balls %s" % [main.net.mode, int(main.net.state_get("hole", 0)) + 1,
		String(main.net.state_get("phase", "")), ", ".join(parts)]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode != "host":
		kit.assert_eq(kit.seated(), kit.seated_want(want), "%s: all %d TV players are seated" % [mode, want])
	var holes := kit.seen_values("hole").size()
	kit.assert_true(holes >= (2 if short_run else 3), "%s: played through several holes (%d)" % [mode, holes])
	if main.split != null and not main.party.local_slots().is_empty():
		kit.assert_true(seen_checks > 0, "%s: own balls were checked for visibility" % mode)
		kit.assert_true(unseen.is_empty(), "%s (%s): every own ball is on screen with its tag %s" % [mode, main.net.machine_kind, str(unseen)])
	if main.net.machine_kind == "deck" and main.party.local_slots().size() == 1 and not main.course.pick:  # (the pick green: all of it)
		kit.assert_true(main.cam_follow == main.party.local_slots()[0], "deck: the camera follows its player's ball")
	# Gus's garden course: a seeded hole built from the host's description, the garden and Gus on every machine.
	kit.assert_true(not main.hole_def.is_empty() and (int(main.hole_def.get("course_seed", 0)) > 0 or main.course.pick), "%s: the hole came from a course seed" % mode)
	kit.assert_true(main.gus != null and main.gus.is_inside_tree(), "%s: Gus is by the board" % mode)
	kit.assert_true(main.garden != null and is_instance_valid(main.garden), "%s: Gus's garden is built" % mode)
	if mode == "client":
		kit.assert_true(main.balls.size() >= want, "client mirrors the balls")
		var hd: Array = main.net.state_get("hdesc", [])
		kit.assert_true(hd.size() >= 6 and (int(hd[1]) == int(main.hole_def["index"])) and (int(hd[1]) < 0 or int(hd[0]) == int(main.hole_def["course_seed"])),
			"client: built the host's hole %s" % str(hd))
		_deep_checks(mode)
		return
	_deep_checks(mode)
	kit.assert_true(main.course_seed > 0, "%s: a seeded course (%d)" % [mode, main.course_seed])
	kit.assert_true(int(main.save.data["days"]) >= 1, "%s: the play-day was counted" % mode)
	if short_run:  # real progress in a short run: holes sunk (a lone golfer is never stuck)
		kit.assert_true(main.sink_log.size() >= 1, "%s: a short run still sinks holes (%d)" % [mode, main.sink_log.size()])
	else:
		kit.assert_true(int(main.save.data["courses"]) >= 1, "%s: a finished course was saved" % mode)
		kit.assert_true(kit.seen("phase", "results") > 0, "%s: the course ended with the results" % mode)
	# Design check: aiming bots hole out within par + 3 (6 putts = automatic pick-up).
	var per_hole := {}
	for e in main.sink_log:
		var h: int = e[0]
		if not per_hole.has(h):
			per_hole[h] = []
		(per_hole[h] as Array).append(int(e[2]))
	for h in per_hole:
		var arr: Array = per_hole[h]
		var tot := 0
		for n in arr:
			tot += int(n)
		var avg := float(tot) / arr.size()
		var par: int = int(main.sink_log.filter(func(e: Array) -> bool: return int(e[0]) == int(h))[0][4])
		kit.info("hole %d: putts %s (par %d)" % [int(h) + 1, str(arr), par])
		kit.assert_true(avg <= par + 3, "hole %d is completable within par+3 (avg %.1f)" % [int(h) + 1, avg])
	if main.vr_rig != null:
		kit.assert_true(vr_putts > 0, "the fake VR golfer putted with the club")
		kit.assert_true(main.ghost.shown, "the ghost glove showed the swing")
		kit.assert_true(main.props.touched.has("duck"), "the duck was poked")
		kit.assert_true(main.props.touched.has("spare"), "a spare ball was grabbed")


## The second pass on every machine.
func _deep_checks(mode: String) -> void:
	kit.info("BOT DEEP %s: %s, surprises told for %s s before they happened" % [mode, str(deep), str(on_shown.values())])
	var late := OS.has_environment("DUO_JOIN") and kit.t < 60.0  # (a late joiner may arrive mid-tell)
	kit.assert_true(String(deep.get("dressed", "")) != "" and String(deep.get("dressed", "")) == String(deep.get("season", "?")),
		"%s: the garden is dressed for the season %s" % [mode, str(deep.get("season"))])
	kit.assert_true(int(deep.get("early", 0)) <= (1 if OS.has_environment("DUO_JOIN") else 0),
		"%s: no surprise happened before its tell showed (%d)" % [mode, int(deep.get("early", 0))])
	for k in on_shown:
		if not late:
			kit.assert_true(float(on_shown[k]) >= Deep.MIN_WARN - 0.4, "%s: surprise %s was told %.1f s before it happened" % [mode, k, float(on_shown[k])])
	for kind in ["gust", "mole"]:
		if deep.has("on_" + kind):
			kit.assert_true(int(deep.get("told_" + kind, 0)) > 0, "%s: a %s happened with a tell" % [mode, kind])
	if mode == "client":
		return
	kit.assert_true(deep.has("pick_mode") or OS.has_environment("MGP_MODE"), "%s: the mode was picked on the pick green %s" % [mode, str(deep)])
	if kit.seen("hole", 1) > 0 or kit.seen("hole", 2) > 0:
		kit.assert_true(deep.has("pick_gift") or OS.has_environment("MGP_GIFT"), "%s: Gus's gift was picked after the practice putt" % mode)
	if main.vr_rig != null and kit.tv_players() == 0 and main.party.local_slots().is_empty():
		kit.assert_true(deep.has("by_vr") or deep.has("by_putt"), "%s: a lone VR golfer picked by hand or by putting %s" % [mode, str(deep)])
	if kit.seen_values("hole").size() >= 4:
		kit.assert_true(deep.has("told_gust") or deep.has("told_mole"), "%s: a surprise was told on the later holes %s" % [mode, str(deep)])
	kit.assert_eq(int(deep.get("corner", -1)), Deep.corner(int(main.save.data["stars_total"])), "%s: Gus's garden corner matches the stars" % mode)
