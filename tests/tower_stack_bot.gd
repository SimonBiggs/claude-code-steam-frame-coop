extends Node
## Headless bot for games/tower_stack. TV bots push blocks onto the pad (and one climbs the tower);
## BOT_VR=1 adds a fake VR giant that grabs boinged-up blocks and stacks them on the stage.
## Without VR the helper crane does the stacking.
## Local:      godot-test --headless --path . --fixed-fps 60 --quit-after 2400 res://tests/tower_stack_bot.tscn
## Networked:  DUO_PORT=8137 DUO_HOST=1 ... & DUO_PORT=8137 DUO_JOIN=127.0.0.1 ... (same scene, real time)
## Flat host: add DUO_FLAT_HOST=1 to the host (no VR: one bot pad plays slot 0 on the host).
## Second pass: every special block is open (try_open) and TODAY'S TOWER is off (daily_ok) so the builder pick
## comes after the first tower. On the pick orbs the first TV player WALKS into one (the middle one for the mode,
## the first one for the next building), the fake VR giant TOUCHES one; the bot checks the team's choice is the job
## built next, and a weather warning reaches every machine (its ring on the TV too).
## Third pass: Rolo rolls a ball early in every job (try_rolls): its lane is told on every machine before the ball
## rolls, nobody is ever bowled over by a ball whose lane showed too briefly, the green shows Wren's neighbours, and
## every machine dresses for the host's season.

const BotKit := preload("res://tests/bot_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")
const WarnRings := preload("res://core/warn_rings.gd")

var kit: BotKit
var main: Node
var want := 2
var saw_results := false
var max_climb := 0.0
var jump_t := 0.0
var vr_phase := "find"
var vr_wait := 0.0
var ghosts_seen := 0
var orbs_seen := 0  # most pick orbs seen at once (every machine)
var rings_seen := 0  # most warning rings seen at once (every machine)
var pick_want := ""  # host: the building the bot walked to
var pick_ok := 0
var pick_bad := 0
var job_seen := -1
var cheers_done := 0  # towers whose CHEER ended during play (the round did not run out first): each opens a build pick
var cheer_was := -1.0
var cheer_round := 0
var lanes_seen := 0  # most of Rolo's lane tells seen at once (every machine)
var balls_seen := 0  # most balls rolling at once


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/tower_stack/main.tscn").instantiate()
	# One flat player alone (no VR giant, nobody else) pushes blocks slowly: a longer round, still under the real 180 s,
	# so the crane can finish a tower for them before the lone check's end (120 s).
	var lone := BotKit.bot_players(2, 6) == 1 and not OS.has_environment("DUO_HOST") and not OS.has_environment("DUO_JOIN") and not OS.has_environment("BOT_VR")
	# 50 s rounds, local and networked (round 2 still starts by ~53 s). 42 s left no room for one toppled stack, so
	# about 1 local run in 30 never finished a tower (2026-11-12); networked runs had the same 42 s and the same risk,
	# so their checks moved 8 s later too (client finish 61 s, host checks 64 s, host finish 68 s).
	main.set("round_time", 95.0 if lone else 50.0)
	main.set("daily_ok", false)
	main.set("try_open", 7)  # towergen OPEN_ALL: special blocks from job 2 on
	main.set("try_rolls", true)  # TS_TRY=rollers: Rolo rolls a ball early in every job
	add_child(main)
	kit.main = main
	kit.watch_state(main.net)  # phases counted as they happen (kit.seen): a 0.25 s poll misses quick ones under load
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	var t0 := 3.0 if client else 1.0
	kit.at(t0, "%d TV players press A on their pads" % want, _join)
	if not host and BotKit.lead_machine():
		kit.at(t0 + 6.0, "P2 presses Start: pause menu", func() -> void:
			kit.allow_pause = true
			_press("start"))
		kit.at(t0 + 6.6, "paused?", func() -> void:
			kit.assert_true(get_tree().paused and main.tv_banner != null and not main.tv_banner.visible, "Start pauses and shows the banner (on_pause_changed made the banner; the open pause menu alone says PAUSED)")
			_press("start"))
		kit.at(t0 + 7.2, "resumed?", func() -> void:
			kit.assert_true(not get_tree().paused, "Start again resumes everyone")
			kit.allow_pause = false)
	kit.drop_in_out(main.party, t0 + 9.0, 3.0, func(slot: int) -> bool:
		return main.avatars.has(slot) and main.huds.has(slot) and main.cams.has(slot))
	if host:
		kit.at(64.0, "host checks", _checks)
		kit.at(68.0, "finish", kit.finish)
	else:
		kit.at(61.0 if client else (110.0 if lone else 58.0), "finish", func() -> void:
			_checks()
			kit.finish())
	if not OS.has_environment("DUO_JOIN"):
		kit.at(14.0, "a quake warning (host / local sends it to every machine)", func() -> void:
			main.weather_warn("quake")
			kit.assert_true(main.weather.rings.count() > 0, "the warning ring shows round the stage"))
	kit.every(2.0, _report)
	kit.every(0.5, _continue_results)


func _continue_results() -> String:
	if main.results_showing():
		if not saw_results:
			saw_results = true
			kit.assert_true(main.split == null or main.results_ui != null, "the results screen shows on the TV")
			kit.assert_true(main.results_ui == null or (main.results_ui.get("data") as Dictionary).has("title"),
				"the results screen has the round's results")
		_press("accept")
	return ""


func _join() -> void:
	if main.net.mode == "host":
		if main.flat_host:
			kit.join_bot(main.party)  # a flat host (DUO_FLAT_HOST=1): one pad player here, in slot 0
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
	orbs_seen = maxi(orbs_seen, main.picks.orbs.orbs.size())
	rings_seen = maxi(rings_seen, main.weather.rings.count())
	lanes_seen = maxi(lanes_seen, main.rollers.rings.count())
	balls_seen = maxi(balls_seen, main.rollers.balls().size())
	_watch_picks()
	var slots: Array[int] = main.party.local_slots()
	jump_t -= delta
	if not main.picks.orbs.orbs.is_empty() and not slots.is_empty():
		_walk_to_orb(slots[0])
		slots = slots.slice(1)
	for slot in slots:
		var climber: bool = slot == slots[slots.size() - 1] and slots.size() >= 2 and kit.t > 12.0
		_steer(slot, climber, delta)
	if main.vr_rig != null:
		_drive_vr(delta)


## The orb this bot goes for: the middle one for the mode, the first one for the next building.
func _orb_target() -> int:
	var row: Array = main.picks.orbs.orbs
	if row.is_empty():
		return -1
	return row.size() / 2 if main.picks.orbs.stage == "mode" else 0


## Host / local: remember which building the bot is choosing; when the next job starts, it must be that one.
func _watch_picks() -> void:
	if main.net.mode == "client":
		return
	var rn := int(main.net.state_get("round", 0))
	if cheer_was >= 0.0 and main.done_t < 0.0 and rn == cheer_round and not main.results_showing():
		cheers_done += 1
	cheer_was = main.done_t
	cheer_round = rn
	if main.picks.stage == "build" and main.picks.chosen >= 0 and pick_want == "":
		var opt: Array = main.picks.options[main.picks.chosen]
		pick_want = String(main.G.from_job(opt).building)
	if pick_want != "" and main.job_n != job_seen and main.picks.stage == "":
		if String(main.site.get("building", "")) == pick_want:
			pick_ok += 1
		else:
			pick_bad += 1
		pick_want = ""
	job_seen = main.job_n


func _walk_to_orb(slot: int) -> void:
	if not main.avatars.has(slot):
		return
	var i := _orb_target()
	var o: Node3D = main.picks.orbs.orbs[i]
	var a: Node3D = main.avatars[slot]
	var d := o.global_position - a.position
	d.y = 0.0
	var v := Vector2.ZERO
	if d.length() > 0.15:
		d = d.normalized()
		var cam: Camera3D = main.split.active_camera(slot)
		var f := -cam.global_basis.z
		f.y = 0.0
		f = f.normalized()
		var r := Vector3(-f.z, 0.0, f.x)
		v = Vector2(d.dot(r), -d.dot(f))
	kit.slot_stick(main.party, slot, "left", v)


func _steer(slot: int, climber: bool, _delta: float) -> void:
	if not main.avatars.has(slot):
		return
	var a: Node3D = main.avatars[slot]
	max_climb = maxf(max_climb, a.position.y)
	var goal := Vector3.ZERO
	var out := _lane_escape(a.position)
	if out != Vector3.INF:  # in one of Rolo's told lanes: step out of it first (like a child who sees the pink lane)
		goal = out
	elif climber:
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


## Standing in a told lane (or a rolling ball's)? The nearest spot just outside it (Vector3.INF: not in one).
func _lane_escape(p: Vector3) -> Vector3:
	for t in main.rollers.rings.tells():
		if String(t.kind) != "line" or not WarnRings.inside("line", t.pos, t.dir, t.size, p, 0.35):
			continue
		var fwd := Vector3(t.dir.x, 0.0, t.dir.z).normalized()
		var side := Vector3(-fwd.z, 0.0, fwd.x)
		var off: float = (p - (t.pos as Vector3)).dot(side)
		var sgn := 1.0 if off >= 0.0 else -1.0
		var dest: Vector3 = Vector3(p.x, 0.0, p.z) + side * sgn * ((t.size as Vector2).y * 0.5 + 0.7 - absf(off))
		if Vector2(dest.x, dest.z).length() > main.ARENA - 0.3:  # the park's edge: the other side
			dest = Vector3(p.x, 0.0, p.z) - side * sgn * ((t.size as Vector2).y * 0.5 + 0.7 + absf(off))
		return dest
	return Vector3.INF


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


## The plan's next block kind (main._crane_spot's rule), or -1: a block of that kind snaps into the plan; any other
## kind is dropped on top anywhere and can knock plan blocks off (2026-11-12: about 1 run in 30 never finished a
## tower in 58 s because the bots fed the crane whatever block was nearest).
func _next_kind() -> int:
	if main.site.is_empty():
		return -1
	var plan: Array = main.site.plan
	for i in plan.size():
		if (main.fill >> i) & 1 == 0:
			return int(plan[i][0])
	return -1


## The nearest block lying in the field (not on the stage, the pad, or in the air), the plan's next kind first.
func _loose_block(from: Vector3) -> Node3D:
	var need := _next_kind()
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
		var dd := from.distance_to(p) + (0.0 if need < 0 or int(main.bkind.get(id, -1)) == need else 1000.0)
		if dd < bd:
			bd = dd
			best = b
	return best


## Fake VR giant: reach for a hovering block, pull the trigger, carry it over the tower, let go.
func _drive_vr(delta: float) -> void:
	var rig = main.vr_rig
	kit.vr_head_height(rig)
	vr_wait -= delta
	if main.results_showing():
		kit.vr_trigger(rig, 1.0 if int(kit.t * 2.0) % 2 == 0 else 0.0)  # the giant pulls the trigger: play again
		vr_phase = "find"
		return
	if main.picks.stage != "" and main.picks.chosen < 0 and main.held_id < 0:  # the giant touches an orb
		kit.vr_trigger(rig, 0.0)
		var o: Node3D = main.picks.orbs.orbs[_orb_target()]
		kit.vr_reach(rig, VrRig.LEFT, o.global_position, 4.0, delta)
		vr_phase = "find"
		return
	match vr_phase:
		"find":
			kit.vr_trigger(rig, 0.0)
			var id := -1
			var need := _next_kind()
			for h in main.hover:  # the plan's next kind first (see _next_kind)
				if h >= 0 and float(main.hover_t.get(h, 0.0)) > 0.7 and (id < 0 or (need >= 0 and int(main.bkind.get(h, -1)) == need)):
					id = h
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
			var goal := Vector3(top.x, maxf(top.y, main.BASE_H) + main._half(main.held_id).y + 0.12, top.z)
			var spot: Array = main._crane_spot(main.held_id)
			if not spot.is_empty():  # the plan's next spot: hold it just above, the snap lines it up
				goal = Vector3(float(spot[1]), float(spot[2]) + 0.1, float(spot[3]))
			if kit.vr_reach(rig, VrRig.RIGHT, goal, 3.0, delta):
				kit.vr_trigger(rig, 0.0)
				vr_phase = "find"
				vr_wait = 0.8


func _report() -> String:
	return "BOT %s: players %s, blocks %d, hover %s, height %.1f / %.2f, rec %.1f, best %.1f, delivered %d, placed %d, job %d %s fill %d, built %d, town %d" % [
		main.net.mode, str(main.party.active_slots()), main.blocks.size(), str(main.hover),
		float(main.net.state_get("height", 0.0)), float(main.site.get("top", 0.0)), float(main.net.state_get("rec", 0.0)),
		float(main.net.state_get("best", 0.0)), main.total_delivered, main.total_placed, main.job_n,
		String(main.site.get("building", "")), main.fill, main.total_built, main.town.entries.size()]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	kit.assert_true(int(main.net.state_get("round", 0)) >= 2, "%s: round 1 ended with results and round 2 started" % mode)
	# The job (towergen.gd) is the same on every machine, with its see-through plan, hoop and Wren.
	kit.assert_true(not main.site.is_empty() and main.site == main.G.from_job(main.net.state_get("job", [])), "%s: the job is rebuilt from the job state" % mode)
	kit.assert_eq(main.ghosts.size(), (main.site.get("plan", []) as Array).size(), "%s: the plan shows as see-through blocks" % mode)
	kit.assert_true(absf(main.ring.position.y - float(main.site.top)) < 0.01, "%s: the gold hoop marks the goal height" % mode)
	kit.assert_true(main.wren != null and main.wren.is_inside_tree(), "%s: Wren the builder bird is here" % mode)
	kit.assert_eq(main.town.entries.size(), mini((main.net.state_get("town", []) as Array).size(), main.G.town_size()), "%s: the town shows every saved tower" % mode)
	kit.assert_eq(main.districts.get_child_count(), main.Districts.reached(int(main.net.state_get("made", 0))), "%s: the town shows its districts" % mode)
	kit.assert_true(orbs_seen >= 3, "%s: the pick orbs showed (%d)" % [mode, orbs_seen])
	kit.assert_true(rings_seen > 0, "%s: a weather warning ring showed" % mode)
	for id in main.blocks:
		kit.assert_true(main.bkind.has(id), "%s: block %d knows its kind" % [mode, int(id)])
		break
	# Third pass: Rolo's told balls, the neighbours' green, the season.
	kit.assert_true(kit.seen_values("rolls").size() >= 1, "%s: Rolo rolled a ball (%s)" % [mode, str(kit.seen_values("rolls"))])
	kit.assert_true(lanes_seen > 0, "%s: a ball's lane was told on the grass" % mode)
	kit.assert_true(balls_seen > 0, "%s: a ball rolled" % mode)
	kit.assert_eq(main.unwarned_hits, 0, "%s: nobody was bowled over by a ball that wasn't told (%d bowled over)" % [mode, main.roll_hits])
	kit.info("%s: %d bowled over by Rolo's balls, season %s" % [mode, main.roll_hits, main.season])
	kit.assert_true(main.roll_hits <= 1, "%s: builders who step out of a told lane are never bowled over (%d)" % [mode, main.roll_hits])
	kit.assert_true(main.season != "" and main.season == String(main.net.state_get("season", "")) and main.season_node.season == main.season, "%s: dressed for the host's season (%s)" % [mode, main.season])
	kit.assert_eq(main.green.folk_count(), mini(int(main.net.state_get("made", 0)), main.GreenScript.SHOW), "%s: the green shows Wren's newest neighbours" % mode)
	kit.assert_eq(main.green.piece_count(), main.GreenScript.grown(int(main.net.state_get("made", 0))), "%s: the green has grown its pieces" % mode)
	if mode == "client":
		kit.assert_eq(main.party.local_slots().size(), want, "client: all %d local players are seated" % want)
		kit.assert_true(ghosts_seen > 0, "client: ghost blocks mirrored from the host")
		kit.assert_true(kit.seen("phase", "results") > 0, "client: saw the results")
		return
	if mode == "local":
		kit.assert_eq(kit.seated(), kit.seated_want(want), "local: all %d TV players are seated" % want)
	if main.flat_host:
		kit.assert_true(main.party.is_local(0) and main.avatars.has(0) and main.cams.has(0), "flat host: slot 0 plays here with a camera")
	if want > 0 and mode == "local" or mode == "host":
		kit.assert_true(main.total_delivered > 0, "%s: blocks reached the pad" % mode)
	kit.assert_true(main.max_height > 0.7, "%s: a tower was built (%.1f m)" % [mode, main.max_height])
	kit.assert_true(main.total_built >= 1, "%s: a tower reached the hoop, got its roof and joined the town (%d)" % [mode, main.total_built])
	kit.assert_true(int(main.save.data.built) >= main.total_built and (main.save.data.town as Array).size() >= 1, "%s: finished towers are saved" % mode)
	if main.vr_rig != null:
		kit.assert_true(main.total_placed > 0, "the fake VR giant placed blocks (%d)" % main.total_placed)
	var hist: Array = main.picks.history
	kit.info("%s picks: %s, mode %s, builds %s, specials %d, glued %d, cheers ended in play %d, picks kept %d" % [mode, str(hist), main.game_mode, str(main.round_builds), main.round_specials, main.specials.glues_made, cheers_done, pick_ok])
	kit.assert_true(not hist.is_empty() or int(main.net.state_get("round", 0)) >= 2, "%s: the team picked on the orbs" % mode)
	var someone: bool = (mode == "local" and want > 0) or main.vr_rig != null or main.flat_host or mode == "host"
	if someone and Engine.get_meta("ts_mode_set", false):
		kit.assert_true(pick_bad == 0, "%s: the chosen building is the one built next (%d ok, %d wrong)" % [mode, pick_ok, pick_bad])
	# A tower counts as built when its roof goes on, but the build pick opens only after its CHEER, and never when
	# the round runs out during it (2026-11-11: a tower finished in round 1's last seconds failed this). So: every
	# tower whose cheer ended during play must have led to a pick (done, or still being chosen / about to start).
	var pick_pending: bool = main.picks.active() or pick_want != ""
	if cheers_done >= 1:
		kit.assert_true(pick_ok >= 1 or pick_pending, "%s: after a tower the team chose the next building (%d)" % [mode, pick_ok])
	if mode == "local" and want >= 2:
		kit.info("highest a TV player climbed: %.2f m" % max_climb)
		kit.assert_true(max_climb > main.BASE_H + 0.3, "a TV player climbed onto the tower")
