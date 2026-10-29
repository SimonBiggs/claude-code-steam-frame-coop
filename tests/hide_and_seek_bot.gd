extends Node
## Headless bot for Hide and Seek. Same scene on host and client (so node paths match).
## Seeker (local / host): once the count is over, walks up to the nearest hider still hiding, aims the
## torch and clicks. In round 2 the seeker dawdles, so the hiders win on time.
## Hiders (local / client): each runs to a hiding spot while the seeker counts, disguises, and squeaks.
## BOT_PLAYERS=N (1..6): N TV hiders (P2..P{N+1}); extras join via main.debug_join(). In local mode with
## N >= 4 the bot also fakes a controller unplug/replug and a player leaving and rejoining.
## Default: 2 hiders locally (so the jail can be broken), 1 on the TV machine.
## New in this version: a CONNECTIVITY check at start (every room, doorway, hiding spot and spawn must be
## walkable from the counting spot without jumping, for both the seeker's and a hider's size); the seeker
## sniffs when close to a hider; a free hider rings the jail bell once someone is in jail; in STAR HUNT
## rounds hiders grab the nearest star before hiding. Rounds cycle classic / stars / night.
## HOUSES: the house is generated (games/hide_and_seek/housegen.gd); the connectivity check builds the
## current house, TODAY'S HOUSE and a small and a big house with real physics (cross-checking housegen's own
## grid validator, tests/hide_and_seek_gen_test.gd). PIP: in round 2 a hider runs to Pip while the seeker
## looks; prints "BOT: PIP OK" once Pip is found (and, on the TV, once the find and his new toy arrived).
## MAPS: the connectivity check runs on EVERY map (each built into its own isolated physics world), and the
## bot plays at least 3 rounds so the map rotation (house -> castle -> spaceship) happens; it prints
## "BOT: MAP ROTATION OK" once it has played on 3 different maps (and the TV mirrored each one).
## Visual teaching: records the picture cue each local view shows (cue_torch, cue_torch_hit, cue_sniff,
## cue_disguise, cue_squeak, cue_bell, cue_star, cue_jail, cue_watch, cue_plug, cue_again, ...), which
## ones each player has learned (done twice: learned_*), and that a learned cue never comes back for that
## player ("retired"); prints "BOT: CUES OK" once this machine's role has shown and retired its cues
## (local: torch + disguise + squeak; host: torch (just shown with one TV hider); client: disguise +
## squeak), else "BOT: CUES FAIL". BOT_MAP=0/1/2 starts on that map.
## BOT RESULT: once this machine has its verdicts (connectivity on the host/local, map rotation, Pip, cues) it
## prints "BOT RESULT: PASS/FAIL (n checks)"; local runs then quit, networked ones end via tests/bot_end.gd.
## "BOT: ERROR instruction text" if a headline (TV centre / a view's big word / the top line / VR) is
## anything but a short word, or the old key-help line is back. BOT_VR=1 (local): P1 is a fake VR seeker
## (XR nodes without a headset) whose hands aim the torch and touch hiders, so the 3D VR cues run.
const UiKit := preload("res://core/ui_kit.gd")
const WorldScript := preload("res://games/hide_and_seek/world.gd")
const Story := preload("res://games/hide_and_seek/story.gd")

var main
var t := 0.0
var last_print := -100.0
var click_t := 0.0
var near_t := 0.0
var bot_players := int(OS.get_environment("BOT_PLAYERS")) if OS.has_environment("BOT_PLAYERS") else (1 if OS.has_environment("DUO_JOIN") else 2)
var spots := {}  # player index -> hiding spot
var rounds_seen := {}
var conn_done := false
var conn_ok := true
var conn_worlds: Array = []  # [SubViewport, map index, spec]
var maps_seen := {}
var cues := {}  # picture cues seen / learned / retired on this machine
var cue_verdict := false
const HEADLINES := "^(|HIDE AND SEEK|HELLO!|HERE I COME!|P\\d+ FOUND!|JAILBREAK!|PAUSED|PLAYER \\d+!|P\\d+!|Connecting to the seeker…)$"
const BIG_WORDS := "^(|HIDE!|SEEK!|\\d+|HIDE!\n\\d+|STAR HUNT!\nSEEK!|NIGHT TIME!\nSEEK!)$"
var headline_re := RegEx.create_from_string(HEADLINES)
var big_re := RegEx.create_from_string(BIG_WORDS)
var bot_vr := OS.has_environment("BOT_VR") and not OS.has_environment("DUO_JOIN") and not OS.has_environment("DUO_HOST")


func _ready() -> void:
	preload("res://tests/bot_end.gd").arm(self)  # end by itself in networked runs
	if OS.has_environment("BOT_MAP"):  # BOT_MAP=0/1/2: start on this map (house / castle / spaceship)
		var cfg := ConfigFile.new()
		cfg.load("user://hide_and_seek_best.cfg")
		cfg.set_value("maps", "next", int(OS.get_environment("BOT_MAP")))
		cfg.save("user://hide_and_seek_best.cfg")
	main = load("res://games/hide_and_seek/main.tscn").instantiate()
	main.count_time = 5.0
	main.intro_time = 3.0
	main.seek_override = 25.0
	add_child(main)
	# Real controllers may be plugged into this machine: don't let someone's button presses join players.
	var no_join := Node.new()
	add_child(no_join)
	main.set_meta("join_input", no_join)


func _press(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _aim(p, target: Vector3) -> void:
	var d: Vector3 = target - (p.global_position + Vector3.UP * p.EYE_HEIGHT)
	var flat := Vector2(d.x, d.z).length()
	if flat > 0.05:
		p.yaw = atan2(-d.x, -d.z)
		p.pitch = atan2(d.y, flat)


func _walk_to(p, target: Vector3, keep: float, delta: float, speed: float) -> bool:
	var to: Vector3 = target - p.global_position
	to.y = 0.0
	if to.length() <= keep:
		return true
	var step: Vector3 = to.normalized() * minf(speed * delta, to.length() - keep)
	p.global_position += step
	return false


func _physics_process(delta: float) -> void:
	t += delta
	if main == null or main.players.size() < 2 or not main.ready_to_play:
		return
	if OS.has_environment("BOT_COUNT"):
		if t > 8.0 and not has_meta("counted"):
			set_meta("counted", true)
			var c := {"mesh": 0, "multimesh": 0, "label": 0, "particles": 0, "lights": 0}
			_count_node(main, main.players[0].camera_cull_mask(), c)
			print("COUNT ", c)
			preload("res://tests/bot_end.gd").quit_quietly(get_tree())
		return
	if conn_worlds.is_empty() and not conn_done and t > 0.3 and main.net.mode != "client":
		var builds: Array = [[0, main.map_spec if main.map_idx == 0 else Story.daily()], [0, Story.daily()],
			[0, {"seed": 4242, "level": 0, "theme": 1}], [0, {"seed": 777, "level": 6, "theme": 3}], [1, {}], [2, {}]]
		for bi in builds:
			var i: int = bi[0]
			var vp := SubViewport.new()
			vp.own_world_3d = true
			vp.size = Vector2i(4, 4)
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			add_child(vp)
			var holder := Node3D.new()
			vp.add_child(holder)
			main.MAPS[i].build(holder, bi[1])
			conn_worlds.append([vp, i, bi[1]])
	if not conn_done and t > 0.8 and not conn_worlds.is_empty():
		conn_done = true
		for cw in conn_worlds:
			var vp: SubViewport = cw[0]
			var d: Dictionary = main.MAPS[int(cw[1])].data(cw[2])
			var space: PhysicsDirectSpaceState3D = vp.find_world_3d().direct_space_state
			_connectivity(space, d, 0.32, 1.6, "seeker")
			_connectivity(space, d, 0.3, 0.9, "hider")
			vp.queue_free()
		conn_worlds.clear()
		print("%sBOT: CONNECTIVITY %s on all %d maps (4 houses)" % ["" if conn_ok else "SCRIPT ERROR: ", "OK" if conn_ok else "FAIL", main.MAPS.size()])
		if OS.has_environment("BOT_CONN_ONLY"):
			preload("res://tests/bot_end.gd").quit_quietly(get_tree())
			return
	if main.round_no > 0 and main.phase != "wait" and not maps_seen.has(main.map_title()):
		maps_seen[main.map_title()] = main.round_no
		print("BOT: round %d is on %s (%s)" % [main.round_no, main.map_title(), main.round_type])
		if maps_seen.size() >= 3:
			print("BOT: MAP ROTATION OK (%s)" % ", ".join(maps_seen.keys()))
	var mode: String = main.net.mode
	_result(mode)
	if main.pip_finder >= 0 and not has_meta("pip_ok") and (mode != "host" or main.toys > 0):
		set_meta("pip_ok", true)
		print("BOT: PIP OK (found by P%d, %d toys at his kennel, on %s)" % [main.pip_finder + 1, main.toys, main.map_title()])
	# Real controllers may be plugged into this machine (someone might be playing!): ignore them.
	var real := Input.get_connected_joypads()
	for p in main.players:
		if real.has(p.joy):
			p.joy = -1
	if bot_players >= 2 and mode != "host" and t > (6.0 if mode == "client" else 1.0) and not has_meta("joined"):
		set_meta("joined", true)
		for i in range(2, mini(bot_players, 6) + 1):
			print("BOT: P%d joins" % (i + 1))
			main.debug_join(i)
	if mode == "local" and bot_players >= 4:
		_test_pads()
	if not rounds_seen.has(main.round_no):
		rounds_seen[main.round_no] = true
		spots.clear()
	if mode != "client":
		_seeker(delta)
		if main.phase == "over" and main.over_t > 2.5:
			if main.round_no >= 2:
				main.seek_override = 25.0
			print("BOT: play again")
			main._start_round()
			if main.round_no == 2:
				main.seek_override = 8.0  # round 2: the seeker dawdles and the hiders win on time
	else:
		if main.phase == "over" and main.over_t > 2.5 and not has_meta("asked_%d" % main.round_no):
			set_meta("asked_%d" % main.round_no, true)
			print("BOT: client asks to play again")
			main.net.send_action("restart", [])
	if mode != "host":
		_hiders(delta)
	if bot_vr:
		_fake_vr(delta)
	_note_cues()
	if t - last_print >= 4.0:
		last_print = t
		var act := []
		for p in main.players:
			if p.active:
				act.append("P%d%s%s" % [p.index + 1, "*" if p.found else "", "(%s)" % WorldScript.PROP_NAMES[p.prop_kind] if p.prop_kind >= 0 else ""])
		print("BOT t=%.0f mode=%s round=%d phase=%s left=%.0f hiding=%d views=%d players=%s scores=%s" % [
			t, mode, main.round_no, main.phase, main.phase_t, main.hiders_left(), main.view_count, act, main.round_scores])


func _seeker(delta: float) -> void:
	var s = main.players[0]
	if main.phase != "seek" or s.vr:
		s.bot_fire = false
		return
	if main.round_no == 2 or (main.net.mode == "host" and main.seek_len - main.phase_t < 8.0):
		s.bot_fire = false
		s.bot_alt = false
		return  # dawdle (networked: give the TV hiders a few seconds to squeak first)
	var best = null
	var best_d := INF
	for h in main.players:
		if h.is_hiding():
			var d: float = h.global_position.distance_to(s.global_position)
			if d < best_d:
				best_d = d
				best = h
	if best == null:
		return
	# Sniff when someone's close (hiders in range sneeze: it's how a real seeker would use it).
	s.bot_alt = best_d < 4.0 and main.sniff_cd <= 0.0 and not s.bot_alt
	if s.bot_alt:
		print("BOT: the seeker sniffs (nearest hider %.1f m)" % best_d)
	# Torch from 2 m; if a wall is in the way, walk right up and bump into them instead.
	near_t = near_t + delta if best_d < 2.3 else 0.0
	# Stuck on a wall far away (no progress for 1.5 s) counts too.
	var last_d: float = get_meta("seek_last_d", INF)
	var stuck: float = float(get_meta("seek_stuck", 0.0)) + delta if best_d > last_d - 0.05 and best_d >= 2.3 else 0.0
	set_meta("seek_stuck", stuck)
	set_meta("seek_last_d", best_d)
	var squeeze: float = maxf(0.0, float(get_meta("seek_squeeze", 0.0)) - delta)
	if stuck >= 1.5:
		squeeze = 3.0  # squeeze through for a few seconds
	set_meta("seek_squeeze", squeeze)
	s.collision_mask = 1 if near_t < 1.5 and squeeze <= 0.0 else 0  # the bot can't path-find round walls: let it squeeze through
	var there := _walk_to(s, best.global_position, 2.0 if near_t < 1.5 else 0.4, delta, 3.5)
	_aim(s, best.center())
	click_t -= delta
	if there and click_t <= 0.0:
		click_t = 0.4
		s.bot_fire = not s.bot_fire
	elif not there:
		s.bot_fire = false
		if randf() < 0.01:
			s.bot_fire = true  # an occasional miss (hits a decoy or nothing)


func _hiders(delta: float) -> void:
	var used := {}
	for p in main.players:
		if p.index == 0 or p.remote or p.ghost or not p.active:
			continue
		if not p.is_hiding() or (main.phase != "count" and main.phase != "seek"):
			p.bot_fire = false
			p.bot_alt = false
			continue
		if not spots.has(p.index):
			var hs: Array = main.md().hide_spots
			var choice: Vector3 = hs[(p.index * 5 + main.round_no * 3) % hs.size()]
			spots[p.index] = choice
		var spot: Vector3 = spots[p.index]
		used[spot] = true
		# Pip: in round 2 (the seeker dawdles) the first hider runs to him (squeezing past furniture).
		if main.phase == "seek" and main.pip_on and main.round_no == 2 and p.index == _pip_hunter():
			if p.prop_kind >= 0:
				p.toggle_disguise()
			p.collision_mask = 0
			if not has_meta("pip_run"):
				set_meta("pip_run", true)
				print("BOT: P%d runs to Pip at %s" % [p.index + 1, main.pip_spot])
			_walk_to(p, main.pip_spot, 0.2, delta, 6.0)
			continue
		p.collision_mask = 1
		# Jailbreak: the last free hider (not disguised) dashes to the bell once a friend is in jail.
		if main.phase == "seek" and main.jailed_count() > 0 and main.jail_breaks > 0 and p.index == _bell_ringer():
			if p.prop_kind >= 0:
				p.toggle_disguise()
			if _walk_to(p, main.bell_pos() + Vector3(-0.5, 0, 0), 0.2, delta, 5.0) and not has_meta("rang_%d" % main.round_no):
				set_meta("rang_%d" % main.round_no, true)
				print("BOT: P%d rings the jail bell" % (p.index + 1))
			continue
		# Star hunt: grab the nearest star first.
		if main.round_type == "stars" and p.prop_kind < 0 and main.star_taken.has(false) and (p.index % 2 == 0 or main.phase == "count"):
			var best_s := Vector3.INF
			for k in main.star_idx.size():
				if not main.star_taken[k]:
					var at: Vector3 = main.star_spot(int(main.star_idx[k]))
					if best_s == Vector3.INF or at.distance_to(p.global_position) < best_s.distance_to(p.global_position):
						best_s = at
			if best_s != Vector3.INF and best_s.distance_to(p.global_position) < 9.0:
				_walk_to(p, best_s, 0.1, delta, 5.0)
				continue
		if p.prop_kind < 0:
			_walk_to(p, spot, 0.2, delta, 5.0)
			var there: bool = Vector2(p.global_position.x - spot.x, p.global_position.z - spot.z).length() < 0.7  # furniture may push back
			var wk := "walk_%d_%d" % [p.index, main.round_no]
			set_meta(wk, float(get_meta(wk, 0.0)) + delta)
			there = there or float(get_meta(wk)) > 6.0  # can't get there: hide right here
			if there and (p.index + main.round_no) % 2 == 0:
				p.toggle_disguise()  # half of the hiders turn into furniture (while counting, or late)
		elif main.phase == "seek" and fmod(t + p.index * 1.3, 3.0) < delta * 1.5:
			p.toggle_disguise()  # pops out now and then (and back in once there), like a fidgety kid
		if main.phase == "seek":
			p.bot_alt = p.taunt_cd <= 0.0 and fmod(t + p.index * 0.7, 1.5) < 0.2  # squeak whenever it's ready


## One BOT RESULT line per machine once every verdict is in.
func _result(mode: String) -> void:
	var late: bool = main.round_no >= 6  # verdicts still missing by now count as failures
	if has_meta("result") or (not late and (not cue_verdict or maps_seen.size() < 3 or not has_meta("pip_ok") or (mode != "client" and not conn_done))):
		return
	if main.phase != "over" and mode == "local":
		return
	set_meta("result", true)
	var fails: Array[String] = []
	if not conn_ok:
		fails.append("connectivity")
	if not has_meta("cues_ok"):
		fails.append("cues")
	if maps_seen.size() < 3:
		fails.append("map rotation")
	if not has_meta("pip_ok"):
		fails.append("pip")
	print("BOT RESULT: %s (4 checks)%s" % ["PASS" if fails.is_empty() else "FAIL", "" if fails.is_empty() else " failed: " + ", ".join(fails)])
	if mode == "local":
		preload("res://tests/bot_end.gd").quit_quietly(get_tree())


## The free local hider with the lowest index looks for Pip.
func _pip_hunter() -> int:
	for p in main.players:
		if p.index > 0 and p.is_hiding() and not p.remote and not p.ghost:
			return p.index
	return -1


## The free hider with the highest index rings the bell.
func _bell_ringer() -> int:
	var who := -1
	for p in main.players:
		if p.index > 0 and p.is_hiding() and not p.remote and not p.ghost:
			who = p.index
	return who


## Local only: fake a controller for P4, unplug and replug it; then P5 times out, leaves and rejoins.
func _test_pads() -> void:
	var p4 = main.players[3]
	var p5 = main.players[4]
	if t > 4.0 and not has_meta("unplug"):
		set_meta("unplug", true)
		p4.joy = 97
		main._on_joy_changed(97, false)
		print("BOT: unplugged P4's pad -> waiting=%s joy=%d" % [main.pad_wait.has(3), p4.joy])
	if t > 5.0 and not has_meta("replug"):
		set_meta("replug", true)
		main._on_joy_changed(97, true)
		print("BOT: replugged -> P4 joy=%d waiting=%s" % [p4.joy, main.pad_wait.has(3)])
		p4.joy = -1
	if t > 6.0 and not has_meta("leave"):
		set_meta("leave", true)
		p5.joy = 98
		main._on_joy_changed(98, false)
		main.pad_wait[4] = 0.3
	if t > 7.0 and not has_meta("left"):
		set_meta("left", true)
		print("BOT: P5 active after pad timeout = %s" % p5.active)
	if t > 8.0 and not has_meta("rejoin"):
		set_meta("rejoin", true)
		main.debug_join(4)
		print("BOT: P5 rejoined = %s (late=%s, phase=%s)" % [p5.active, p5.late, main.phase])


# --- Connectivity check: nobody can get trapped -------------------------------------

## Walk-ability grid (10 cm cells) for a capsule of this size against the house's collision (layer 1),
## flood-filled from the seeker's counting spot WITHOUT jumping. Every room, every doorway, every hiding
## spot and every spawn must be reachable; otherwise print "CONNECTIVITY FAIL" with what's cut off.
func _connectivity(space: PhysicsDirectSpaceState3D, md: Dictionary, radius: float, height: float, who: String) -> void:
	var title: String = md.title
	var bounds: Array = md.bounds
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	var x0: float = bounds[0]
	var x1: float = bounds[1]
	var z0: float = bounds[2]
	var z1: float = bounds[3]
	var spawns: Array = md.spawns
	var nx := int((x1 - x0) / 0.1)
	var nz := int((z1 - z0) / 0.1)
	var free := PackedByteArray()
	free.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var at := Vector3(x0 + (ix + 0.5) * 0.1, height / 2.0 + 0.02, z0 + (iz + 0.5) * 0.1)
			q.transform = Transform3D(Basis(), at)
			free[iz * nx + ix] = 1 if space.intersect_shape(q, 1).is_empty() else 0
	var start := _cell(spawns[0], x0, z0, nx, nz)
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	var stack: Array[int] = [start]
	seen[start] = 1
	var count := 0
	while not stack.is_empty():
		var c: int = stack.pop_back()
		count += 1
		var cx := c % nx
		var cz := c / nx
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n2: Vector2i = Vector2i(cx, cz) + d
			if n2.x < 0 or n2.y < 0 or n2.x >= nx or n2.y >= nz:
				continue
			var k := n2.y * nx + n2.x
			if free[k] == 1 and seen[k] == 0:
				seen[k] = 1
				stack.append(k)
	var problems: Array[String] = []
	for room in md.rooms:
		var r: Array = room
		if not _reach_near(r[1], 1.6, seen, free, x0, z0, nx, nz):
			problems.append("room %s" % r[0])
	for door in md.doors:
		var dr: Array = door
		if not _reach_near(dr[1], 0.25, seen, free, x0, z0, nx, nz):
			problems.append("doorway %s" % dr[0])
	if who == "hider":
		for sp in md.hide_spots:
			if not _reach_near(sp, 0.6, seen, free, x0, z0, nx, nz):
				problems.append("hide spot %s" % sp)
		for i in range(1, spawns.size()):
			if not _reach_near(spawns[i], 0.5, seen, free, x0, z0, nx, nz):
				problems.append("spawn %s" % spawns[i])
		for st in md.star_spots:
			if not _reach_near(st, 0.6, seen, free, x0, z0, nx, nz):
				problems.append("star spot %s" % st)
		var bell: Vector3 = md.bell
		if not _reach_near(bell, 1.0, seen, free, x0, z0, nx, nz):
			problems.append("jail bell %s" % bell)
	# Free pockets nobody can walk into (a hider bounced or jumped in there would need to jump out).
	var pockets: Array[String] = []
	var pseen := seen.duplicate()
	for i in free.size():
		if free[i] == 0 or pseen[i] == 1:
			continue
		var size := 0
		var sum := Vector2.ZERO
		var st2: Array[int] = [i]
		pseen[i] = 1
		while not st2.is_empty():
			var c: int = st2.pop_back()
			size += 1
			sum += Vector2(x0 + (c % nx + 0.5) * 0.1, z0 + (c / nx + 0.5) * 0.1)
			for d in [1, -1, nx, -nx]:
				var k: int = c + int(d)
				if k >= 0 and k < free.size() and free[k] == 1 and pseen[k] == 0 and absi((k % nx) - (c % nx)) <= 1:
					pseen[k] = 1
					st2.append(k)
		if size >= 12:
			var mid := sum / size
			var jail: Vector3 = md.jail
			if absf(mid.x - jail.x) < WorldScript.JAIL_HALF and absf(mid.y - jail.z) < WorldScript.JAIL_HALF:
				continue  # the jail cage: you only get in by being found, and out by a jailbreak
			pockets.append("%d cells at (%.1f, %.1f)" % [size, mid.x, mid.y])
	if not pockets.is_empty():
		print("BOT: %s: walled-off pockets for the %s (jump in/out only): %s" % [title, who, ", ".join(pockets)])
	if problems.is_empty():
		print("BOT: %s: CONNECTIVITY OK for the %s (r %.2f): %d walkable cells reachable, %d rooms, %d doorways" % [
			title, who, radius, count, (md.rooms as Array).size(), (md.doors as Array).size()])
	else:
		conn_ok = false
		print("SCRIPT ERROR: BOT: %s: CONNECTIVITY FAIL for the %s (r %.2f): cut off: %s" % [title, who, radius, ", ".join(problems)])


func _cell(p: Vector3, x0: float, z0: float, nx: int, nz: int) -> int:
	var ix := clampi(int((p.x - x0) / 0.1), 0, nx - 1)
	var iz := clampi(int((p.z - z0) / 0.1), 0, nz - 1)
	return iz * nx + ix


## Is any reachable cell within `r` of this point?
func _reach_near(p: Vector3, r: float, seen: PackedByteArray, _free: PackedByteArray, x0: float, z0: float, nx: int, nz: int) -> bool:
	var steps := int(r / 0.1)
	var c := _cell(p, x0, z0, nx, nz)
	var cx := c % nx
	var cz := c / nx
	for dz in range(-steps, steps + 1):
		for dx in range(-steps, steps + 1):
			var x := cx + dx
			var z := cz + dz
			if x < 0 or z < 0 or x >= nx or z >= nz:
				continue
			if seen[z * nx + x] == 1:
				return true
	return false


## BOT_COUNT=1: what the seeker's camera would draw (performance check).
func _count_node(n: Node, mask: int, c: Dictionary) -> void:
	if n is VisualInstance3D and (n as Node3D).is_visible_in_tree() and ((n as VisualInstance3D).layers & mask) != 0:
		if n is MeshInstance3D:
			c.mesh += 1
		elif n is MultiMeshInstance3D:
			c.multimesh += 1
		elif n is Label3D:
			c.label += 1
		elif n is CPUParticles3D:
			c.particles += 1
		elif n is Light3D:
			c.lights += 1
	for ch in n.get_children():
		_count_node(ch, mask, c)


# --- Visual teaching checks -------------------------------------------------------

func _text_error(where: String, text: String) -> void:
	var k := "text_err_" + where
	if not cues.has(k):
		cues[k] = true
		print("BOT: ERROR instruction text in %s: '%s'" % [where, text.replace("\n", " / ")])


## Picture cues instead of words: record what each view shows; any how-to sentence is an error.
func _note_cues() -> void:
	if main.get("help_label") != null:
		_text_error("key-help line", "help_label is back")
	var ct: String = main.center_label.text
	var results: bool = ct.begins_with("THE SEEKER FOUND EVERYONE!") or ct.begins_with("TIME'S UP!")  # (the TV may get it a frame before "over")
	if main.phase != "over" and not results and main.center_label.modulate.a > 0.05 and headline_re.search(ct) == null:
		_text_error("TV headline", main.center_label.text)
	if main.phase == "over" and (main.center_label.text.contains("A / Enter") or main.center_label.text.contains("press")):
		_text_error("results", main.center_label.text)
	if main.info_label.text != "" and main.info_label.text != "HIDE AND SEEK":
		_text_error("top line", main.info_label.text)
	if main.vr_center != null and main.vr_center.modulate.a > 0.05 and main.phase != "over":
		var vt: String = main.vr_center.text
		var vres: bool = vt.begins_with("THE SEEKER FOUND EVERYONE!") or vt.begins_with("TIME'S UP!")  # (a frame behind)
		if not vres and headline_re.search(vt) == null and big_re.search(vt) == null:
			_text_error("VR headline", vt)
	if main.vr_status != null and main.vr_status.visible and main.vr_status.text.contains("\n"):
		_text_error("VR status", main.vr_status.text)
	if main.join_cue != null and main.join_cue.visible:
		cues["join_cue"] = true
	if main.vr_torch_cue != null and main.vr_torch_cue.visible:
		if not cues.has("vr_torch_cue"):
			print("BOT: VR cue TRIGGER over the torch (t=%.0f)" % t)
		cues["vr_torch_cue"] = true
		if main.vr_torch_cue.no_depth_test or main.vr_torch_cue.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
			print("BOT: ERROR VR cue label breaks the VR text rules")
	if main.vr_sniff_cue != null and main.vr_sniff_cue.visible:
		if not cues.has("vr_sniff_cue"):
			print("BOT: VR cue nose ball on the left mitten (t=%.0f)" % t)
		cues["vr_sniff_cue"] = true
	for p in main.players:
		var hud = p.hud
		if hud == null or not is_instance_valid(hud) or not p.active:
			continue
		if hud.big_label.text != "" and big_re.search(hud.big_label.text) == null:
			_text_error("P%d big word" % (p.index + 1), hud.big_label.text)
		var key: String = hud.cue_key
		if key != "" and hud.cue.visible:
			if not cues.has("cue_" + key):
				print("BOT: P%d picture cue %s (t=%.0f, phase %s)" % [p.index + 1, key, t, main.phase])
			cues["cue_" + key] = true
			var act := "torch" if key == "torch_hit" else key
			cues["cue_" + act] = true  # (the torch cue with a hider in the beam counts as the torch cue)
			if main.cue_learned(p, act) and hud.cue.key == key and hud.cue.a >= 1.0:
				if not cues.has("back_%d_%s" % [p.index, act]):
					cues["back_%d_%s" % [p.index, act]] = true
					print("BOT: ERROR P%d's learned cue %s came back" % [p.index + 1, act])
		if hud.pointer.on and not cues.has("pointer_" + key):
			cues["pointer_" + key] = true
			print("BOT: P%d glowing pointer to the %s (t=%.0f)" % [p.index + 1, key, t])
		if hud.aim_glyph != null and hud.aim_glyph.visible:
			cues["aim_glyph"] = true
	for p in main.players:
		var done: Dictionary = p.get_meta("cue_done", {})
		for k in done:
			if int(done[k]) < 2:
				continue
			if not cues.has("learned_" + str(k)):
				cues["learned_" + str(k)] = true
				print("BOT: P%d learned %s (t=%.0f)" % [p.index + 1, k, t])
			var hud = p.hud
			var showing: bool = hud != null and is_instance_valid(hud) and hud.cue.visible \
				and (hud.cue_key == str(k) or (str(k) == "torch" and hud.cue_key == "torch_hit"))
			if not showing and cues.has("cue_" + str(k)) and not cues.has("retired_" + str(k)):
				cues["retired_" + str(k)] = true
				print("BOT: P%d cue %s retired (t=%.0f)" % [p.index + 1, k, t])
	if int(t) % 10 == 0 and cues.size() != int(get_meta("cues_shown", -1)):
		set_meta("cues_shown", cues.size())  # networked runs end on a timeout: print the cues as they come
		var ks: Array = cues.keys()
		ks.sort()
		print("BOT CUES so far: mode=%s %s" % [main.net.mode, ",".join(PackedStringArray(ks))])
	_cue_verdict()


func _cue_verdict() -> void:
	if cue_verdict:
		return
	var mode: String = main.net.mode
	var need: Array[String] = []
	set_meta("max_hiders", maxi(int(get_meta("max_hiders", 0)), main.hider_count()))
	if mode == "host" and int(get_meta("max_hiders")) < 2:
		need.append("cue_torch")  # one TV hider: only one find fits in a networked run before the timeout
	elif mode != "client":
		need.append_array(["cue_torch", "learned_torch", "retired_torch"])
	if mode != "host":
		need.append_array(["cue_disguise", "cue_squeak", "learned_squeak", "retired_squeak"])
	if mode == "local":
		need.append_array(["learned_disguise", "retired_disguise", "cue_again"])
	if bot_vr:
		need = ["vr_torch_cue", "vr_sniff_cue", "cue_disguise", "cue_squeak"]
	var missing: Array[String] = []
	for k in need:
		if not cues.has(k):
			missing.append(k)
	for k in cues:
		if str(k).begins_with("back_") or str(k).begins_with("text_err_"):
			missing.append(str(k))
	var deadline := 56.0 if mode == "local" else (36.0 if mode == "host" else 31.0)
	if missing.is_empty():
		cue_verdict = true
		set_meta("cues_ok", true)
		print("BOT: CUES OK (%s): %s" % [mode, ", ".join(need)])
	elif t >= deadline:
		cue_verdict = true
		print("BOT: CUES FAIL (%s): missing %s" % [mode, ", ".join(missing)])


## BOT_VR: P1 becomes a VR seeker made of plain XR nodes (no headset): the bot moves the origin, points
## the right hand (torch) at the nearest hider and touches them with the left hand.
func _fake_vr(delta: float) -> void:
	var s = main.players[0]
	if not s.vr:
		if t < 1.0:
			return
		var origin := XROrigin3D.new()
		main.add_child(origin)
		origin.global_position = s.global_position
		var cam := XRCamera3D.new()
		origin.add_child(cam)
		var left := XRController3D.new()
		left.tracker = "left_hand"
		origin.add_child(left)
		var right := XRController3D.new()
		right.tracker = "right_hand"
		origin.add_child(right)
		s.attach_xr(origin, cam, left, right)
		cam.position = Vector3(0, 1.5, 0)
		left.position = Vector3(-0.2, 1.2, -0.25)  # (not straight below the head: the wrist menu faces it)
		right.position = Vector3(0.2, 1.2, -0.25)
		print("BOT: P1 is a fake VR seeker")
		return
	if main.phase != "seek":
		return
	var best = null
	var best_d := INF
	for h in main.players:
		if h.is_hiding():
			var d: float = h.global_position.distance_to(s.global_position)
			if d < best_d:
				best_d = d
				best = h
	if best == null:
		return
	var o: XROrigin3D = s.xr_origin
	var to: Vector3 = best.global_position - o.global_position
	to.y = 0.0
	if to.length() > 1.6:
		o.global_position += to.normalized() * minf(3.0 * delta, to.length() - 1.6)
	var c: Vector3 = best.center()
	var head: Vector3 = s.xr_camera.global_position
	s.hand_r.global_position = head + Vector3(0.2, -0.3, 0)
	UiKit.look(s.hand_r, c, Vector3.UP)
	near_t = near_t + delta if to.length() < 1.8 else 0.0
	s.hand_l.global_position = c if near_t > 2.0 else head + Vector3(-0.2, -0.3, -0.2)
