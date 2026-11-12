extends Node
## Headless bot for Duo Arena party mode. Every local player aims at the nearest enemy and fires.
## BOT_PLAYERS=N: total TV players to have (local split screen: P1 + P2 + drop-ins, up to 6;
## TV machine (DUO_JOIN): P2 + drop-ins, up to 6). In local mode it also joins one player with a fake
## controller (A press), unplugs it briefly (rejoins), then unplugs it for good (it leaves).
## SIMPLE_MODE (main.gd): the bot pops the practice targets, checks wave 1 starts, spawns the dinos and
## a Fishwort dive, then forces the (short) game over. Otherwise (full mode):
## Local / host also exercise the new content: pterodactyl, ankylo and raptor spawns, every arena event
## (meteor, gold, stampede, surge, dive), then a forced game over (awards) at BOT_END seconds (default 56).
## BOT_WAVE=N: jump to wave N first (e.g. 10 = KING REX, 15 = the finale; clearing it = VICTORY).
## BOT_GOD=1: players can't be hurt (so the finale can be cleared).
## BOT_VR=1 (local): player 1 runs the real VR code with fake hands: it draws the sword over the
## shoulder, walks up to monsters and swings (slices, shell cracks), and shoots with the right hand.
## Second pass (deep.gd): on the host / local game the bot forces a TOLD surprise (its warn ring must be up at once),
## opens NOVA'S GIFT orbs (the bots shoot one), saves the zone's lost friend when there is one (DA_ZONE=jungle), and
## checks phases through tests/bot_kit.gd watch_state (net "da_phase" / "da_surprise" / "da_gifts" / "da_friend"),
## the arena's shape + spring, the season (ARCADE_SEASON_DUO_ARENA) and this run's own telemetry RUN lines.
const UiKit := preload("res://core/ui_kit.gd")
const BotKit := preload("res://tests/bot_kit.gd")
const Gen := preload("res://games/duo_arena/arenagen.gd")
const Deep := preload("res://games/duo_arena/deep.gd")

const FAKE_PAD := 40

var main
var t := 0.0
var joined := false
var report_t := 0.0
var pad_step := 0
var target := 2
var script_step := 0
var vr_draw_t := 0.0
var end_t: float = preload("res://tests/bot_end.gd").end_at(56.0)  # BOT_END, pulled in before a --quit-after cut
var kit: BotKit
var rings_at_surprise := -1  # warn rings up the moment the surprise was forced


func _ready() -> void:
	preload("res://tests/bot_end.gd").arm(self)  # end by itself in networked runs
	kit = BotKit.new()
	kit.verbose = false
	add_child(kit)
	main = load("res://games/duo_arena/main.tscn").instantiate()
	add_child(main)
	kit.main = main
	kit.watch_state(main.net)
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
		if p.vr and not p.ghost:
			_drive_vr(p, delta)
			continue
		if p.vr or p.remote or p.ghost or not p.active:
			continue
		p.force_fire = p.index >= 2 or mode == "client"
		_aim(p)
	if mode == "client" and t >= end_t - 1.0:
		_deep_checks()  # a TV machine's verdict too (the host's comes from its content script)
	if main.game_over:
		main.game_over_time = 0.0  # (a firing bot must never press "play again": a reload would restart this bot too)
	if mode != "client":
		_content_script()
		if OS.has_environment("BOT_GOD"):
			for p in main.players:
				p.invuln_t = 1.0  # BOT_GOD=1: nobody gets hurt (to reach the finale's victory)
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


## Spawns the new monsters and starts every arena event once, then ends the round to show the awards.
func _content_script() -> void:
	var steps := _simple_steps() if main.SIMPLE_MODE else [
		[1.5, func() -> void:
			if OS.has_environment("BOT_WAVE"):
				main.debug_skip_to_wave(int(OS.get_environment("BOT_WAVE")))
				print("BOT: skip to wave %s" % OS.get_environment("BOT_WAVE"))],
		[4.0, func() -> void:
			for k in ["ptero", "ankylo", "raptor"]:
				main.debug_spawn(k)
			print("BOT: spawned ptero, ankylo, raptor")],
		[8.0, func() -> void: main.debug_event("meteor")],
		[20.0, func() -> void: main.debug_event("gold")],
		[27.0, func() -> void: main.debug_event("stampede")],
		[33.0, func() -> void: main.debug_event("surge")],
		[40.0, func() -> void: main.debug_event("dive")],
		[end_t, func() -> void:
			if not main.game_over:
				print("BOT: forcing game over to show the awards")
				main._on_game_over()
				print("BOT: end screen:\n%s" % main.center_label.text)],
	]
	while script_step < steps.size() and t >= float(steps[script_step][0]):
		var f: Callable = steps[script_step][1]
		f.call()
		script_step += 1


## Simple mode: the practice targets must pop (the bot shoots them), then wave 1 starts with grunts
## only; later the dinos, a Fishwort dive and the game over (a short end screen, no awards).
func _simple_steps() -> Array:
	return [
		[1.5, func() -> void:
			if OS.has_environment("BOT_WAVE"):
				main.practice_step = main.PRACTICE_SPOTS.size()
				main.debug_skip_to_wave(int(OS.get_environment("BOT_WAVE")))
				print("BOT: skip to wave %s" % OS.get_environment("BOT_WAVE"))],
		[6.0, func() -> void:
			var targets: int = get_tree().get_nodes_in_group("enemies").filter(func(e) -> bool: return e.kind == "target").size()
			print("BOT: practice step %d/%d, targets up %d, wave %d" % [main.practice_step, main.PRACTICE_SPOTS.size(), targets, main.wave])],
		[16.0, func() -> void:
			print("BOT: practice %s, wave %d (want >= 1), center '%s', hint '%s'" % [
				"done" if main.practice_step >= main.PRACTICE_SPOTS.size() else "NOT DONE", main.wave,
				main.center_label.text, main.director().hint_label.text])],
		[24.0, func() -> void:
			for k in ["ptero", "ankylo", "raptor"]:
				main.debug_spawn(k)
			print("BOT: spawned ptero, ankylo, raptor")
			var p0 = main.players[0]
			if p0.vr and not p0.ghost:
				print("BOT VR: sword demo shown=%s, swaps=%d, wrist '%s'" % [p0.has_meta("sword_demo"),
					int(p0.get_meta("swapped", 0)), p0.wrist_label.text])],
		[30.0, func() -> void: main.debug_event("dive")],
		[34.0, func() -> void:
			main.debug_event("surprise")
			rings_at_surprise = main.zone.rings.count()
			print("BOT: forced a told surprise in %s, warn rings up %d" % [main.zone.zone_id, rings_at_surprise])],
		[40.0, func() -> void:
			main.debug_event("gift")
			print("BOT: gift orbs %s" % [main.pick_ids])],
		[48.0, func() -> void:
			if main.deep.lost_friend() != "":
				print("BOT: saving %s" % main.deep.lost_friend())
				main.debug_event("rescue")],
		[end_t - 1.0, func() -> void: _deep_checks()],
		[end_t, func() -> void:
			if not main.game_over:
				print("BOT: forcing game over")
				main._on_game_over()
				print("BOT: end screen:\n%s" % main.center_label.text)],
		[end_t + 0.4, func() -> void: _telemetry_checks()],
	]


## This run's own RUN lines (kit.my_runs: never another bot's): a game-over line with the second pass's fields.
func _telemetry_checks() -> void:
	if main.net.mode == "client":
		return
	var mine: Array = kit.my_runs("duo_arena")
	var over: Array = mine.filter(func(e: Dictionary) -> bool: return String(e.get("end", "")) == "over")
	kit.assert_true(not over.is_empty(), "this run wrote its game-over RUN line (%d lines of mine)" % mine.size())
	if not over.is_empty():
		var e: Dictionary = over[-1]
		kit.assert_true(e.has("season") and e.has("gifts") and e.has("surprises") and e.has("shape"), "the RUN line has season, gifts, surprises, shape (%s)" % [e.keys()])
		kit.assert_true(int(e.get("surprises", 0)) >= 1, "the RUN line counts the surprise (%s)" % e.get("surprises"))


## Fake VR: aim the gun hand at the nearest monster and fire; draw the sword over the left shoulder,
## then walk up to monsters and swing it.
func _drive_vr(p, delta: float) -> void:
	p.force_fire = true
	var best = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		var dd: float = e.global_position.distance_to(p.global_position)
		if e.get("armor") != null and e.armor > 0:
			dd -= 6.0  # go for the armoured ones first
		if dd < best_d:
			best_d = dd
			best = e
	var cam: Node3D = p.xr_camera
	var origin: Node3D = p.xr_origin
	vr_draw_t += delta
	var sword: Node3D = p.get_meta("sword") if p.has_meta("sword") else null
	if sword != null and not sword.visible and fmod(vr_draw_t, 3.0) < 0.3:
		p.hand_l.position = cam.position + Vector3(-0.2, 0.12, 0.2)  # reach over the left shoulder
	else:
		var swing := sin(t * 7.0)
		p.hand_l.position = cam.position + Vector3(swing * 0.6, -0.3, -0.5)
	var orb = _orb_for(p)
	if orb != null:
		p.hand_r.global_basis = UiKit.aim((orb.global_position - p.hand_r.global_position).normalized(), Vector3.UP)
		return
	if best == null:
		return
	var c: Vector3 = best.center()
	var to: Vector3 = best.global_position - p.global_position
	to.y = 0.0
	if to.length() > 0.01:
		origin.global_basis = Basis(Vector3.UP, atan2(-to.x, -to.z))
	var diving: bool = main.sky_fish != null and main.sky_fish.dive_progress() >= 0.0
	if to.length() > best.radius + 1.0 and not diving:  # hold still while Fishwort dives at us
		origin.global_position += to.normalized() * 3.0 * delta
	p.hand_r.global_basis = UiKit.aim((c - p.hand_r.global_position).normalized(), Vector3.UP)
	if not has_meta("vr_sword_seen") and sword != null and sword.visible:
		set_meta("vr_sword_seen", true)
		print("BOT VR: sword drawn")


## The pick orb a bot player goes for (zone.gd orbs: each player a different one), or null.
func _orb_for(p):
	var orbs: Array = main.zone.orbs if main.zone != null else []
	if orbs.is_empty():
		return null
	var o = orbs[(p.index + main.wave) % orbs.size()]
	return o if is_instance_valid(o) and o.is_inside_tree() else null


func _aim(p) -> void:
	var orb = _orb_for(p)
	if orb != null:
		var od: Vector3 = orb.global_position - (p.global_position + Vector3.UP * 1.55)
		p.yaw = atan2(-od.x, -od.z)
		p.pitch = atan2(od.y, Vector2(od.x, od.z).length())
		return
	var best = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		var dd: float = e.global_position.distance_to(p.global_position)
		if dd < best_d:
			best_d = dd
			best = e
	if best == null:
		return
	var d: Vector3 = best.center() - (p.global_position + Vector3.UP * 1.55)
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
	var kinds := {}
	for e in get_tree().get_nodes_in_group("enemies"):
		kinds[e.kind] = int(kinds.get(e.kind, 0)) + 1
	var d = main.director()
	if main.zone != null:
		print("BOT   zone=%s pillars=%d pads=%d orbs=%d stage=%s mode=%s heroes=%s perks=%s story=%d" % [main.zone.zone_id,
			main.zone.lay.get("pillars", []).size(), main.zone.lay.get("pads", []).size(), main.zone.orbs.size(), main.pick_stage,
			main.game_mode, main.heroes, main.perks, main.story_queue.size()])
	print("BOT %s t=%.0f wave=%d score=%d enemies=%d slots=%d active=%s views=%d" % [mode, t, main.wave, main.score,
		get_tree().get_nodes_in_group("enemies").size(), main.players.size(), ", ".join(act), views])
	print("BOT   kinds=%s combo=%d best=%d event=%s mood=%s boss=%s %.2f left=%d fish=%s" % [kinds, d.combo, d.best_combo,
		d.event_name, d.mood, d.boss_name, d.boss_frac, d.left, main.sky_fish.dive_progress() if main.sky_fish else -2.0])


## The deep content (arenagen / zone / picks / story) works: a zone was built, everyone picked a hero, Nova told the
## story. Fails print SCRIPT ERROR (the runner's verdict); the summary is the BOT RESULT line.
func _deep_checks() -> void:
	if has_meta("deep_checked"):
		return
	set_meta("deep_checked", true)
	var z = main.zone
	kit.assert_true(z != null and z.zone_id != "", "a zone was built")
	if z != null:
		kit.assert_true((z.lay.get("pillars", []) as Array).size() >= 3, "zone %s has pillars (%d)" % [z.zone_id, (z.lay.get("pillars", []) as Array).size()])
		kit.assert_true(Gen.SHAPES.has(String(z.lay.get("shape", ""))) and z.lay.has("spring") and z.spring != null, "the arena has a shape and Nova's spring (%s)" % z.lay.get("shape", "-"))
	kit.assert_true(main.story_shown >= 1, "a story card was shown (%d)" % main.story_shown)
	kit.assert_true(kit.seen("da_phase", "wave") > 0, "the wave phase was seen (%s)" % [kit.seen_values("da_phase")])
	var want_season: String = load("res://core/season_kit.gd").override("duo_arena", "", Deep.SEASONS)  # "" = none asked for
	kit.assert_true(main.deep.season != "" and (want_season == "" or main.deep.season == want_season), "the season is %s (want %s)" % [main.deep.season, want_season if want_season != "" else "any"])
	if main.net.mode != "client":
		kit.assert_true(main.wave >= 1, "wave 1 started (pick stage '%s')" % main.pick_stage)
		var need: int = main.players.filter(func(p) -> bool: return p.active).size()
		kit.assert_true(main.heroes.size() >= mini(need, 1), "everyone got a hero (%s)" % [main.heroes])
		kit.assert_true(main.run_seed != 0 or OS.has_environment("DA_SEED"), "the run has a seed")
		if not OS.has_environment("BOT_WAVE"):
			kit.assert_true(kit.seen("da_phase", "pick:hero") > 0, "the hero orbs were up")
		kit.assert_true(rings_at_surprise >= 1, "the forced surprise was told by a warn ring at once (%d)" % rings_at_surprise)
		kit.assert_true(not kit.seen_values("da_surprise").is_empty(), "a surprise counted (da_surprise)")
		kit.assert_true(kit.seen("da_phase", "pick:gift") > 0, "Nova's gift orbs came up")
		kit.assert_true(main.deep.gifts.size() >= 1 and not kit.seen_values("da_gifts").is_empty(), "the team got a gift (%s)" % [main.deep.gifts])
		if OS.get_environment("DA_ZONE") in ["jungle", "lava", "ice", "star"]:
			kit.assert_true(not kit.seen_values("da_friend").is_empty() and main.deep.friends.size() >= 1, "the lost friend was saved (%s)" % [main.deep.friends])
	else:
		if not kit.seen_values("da_surprise").is_empty():
			kit.assert_true(main.deep.tells_seen >= 1, "the host's surprise was told on this TV machine too (%d)" % main.deep.tells_seen)
		kit.assert_true(main.deep.season != "", "the host's season reached the TV machine")
	print("BOT deep: zone %s shape %s, mode %s, heroes %s, perks %s, gifts %s, friends %s, season %s, wave %d, phases %s" % [
		z.zone_id if z != null else "-", z.lay.get("shape", "-") if z != null else "-", main.game_mode, main.heroes, main.perks,
		main.deep.gifts, main.deep.friends, main.deep.season, main.wave, kit.seen_values("da_phase")])
