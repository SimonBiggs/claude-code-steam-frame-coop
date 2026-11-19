extends Node
## Headless bot for games/sky_bots. TV bots (BOT_PLAYERS, default 2) steer their robots with the stick, A (jump /
## hold to hover) and X (punch), thinking with the same route brain as the CPU buddies (games/sky_bots/brain.gd). The
## fake VR giant (BOT_VR=1) walks along with the robots, grabs a lift's handle with the right trigger and lifts it,
## flicks grumbles and reaches into the pick orbs. Solo VR (DUO_HOST=1 BOT_VR=1, no TV machine): BIP and BOP play.
## Checks: an island is built (the client builds the very same one) and passes levelgen.gd check(), bolts get
## collected, a pick happens on the pick orbs (a robot walks under the glowing one; the giant alone reaches in), the
## island gets cleared and everyone goes home to Gizmo Town, which grows; the giant lifted a lift; zero script errors.
## SKY_ISLAND=n starts straight on island n (3 = Crab Cove: Cranky Crab must be beaten; 6 = Clockwork Keep: King
## Keywind must be beaten; 4 Snowy Peaks springs, 5 Jungle Jumble fans; 0 = TODAY'S ISLAND). Every island: a bot box
## gets opened (a little bot rescued), and the bots' brains ground-pound boxes (B in the air).
## Local:     godot-test --headless --path . --fixed-fps 60 --quit-after 7200 res://tests/sky_bots_bot.tscn
## Networked: DUO_PORT=2xxxx DUO_HOST=1 BOT_VR=1 ... & DUO_PORT=2xxxx DUO_JOIN=127.0.0.1 ... (real time)
## multibot: seconds=180

const BotKit := preload("res://tests/bot_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")
const G := preload("res://games/sky_bots/levelgen.gd")
const Brain := preload("res://games/sky_bots/brain.gd")
const Hub := preload("res://games/sky_bots/hub.gd")

var kit: BotKit
var main: Node
var want := 2
var brains := {}  # slot -> Brain
var held := {}  # slot -> A held now
var island_keys := {}
var short := false
var saw_orbs := false
var saw_vr_orbs := false
var picked_by_robot := false
var max_bolts := 0
var vr_lifted := 0
var vr_grab := -1
var vr_t := 0.0
var grew_from := -1
var grew_to := -1
var gear_seen := false
var wall_seen := false
var crab_down := false
var built_on_island := false
var boxes_seen := 0
var sprung := false
var fanned := false
var hats_seen := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = BotKit.new()
	add_child(kit)
	main = load("res://games/sky_bots/main.tscn").instantiate()
	main.hub_wait = 1.5
	add_child(main)
	kit.main = main
	kit.watch_state(main.net)
	want = BotKit.bot_players(2, 6)
	var client := OS.has_environment("DUO_JOIN")
	var host := OS.has_environment("DUO_HOST")
	kit.at(3.0 if client else 1.0, "%d TV players press A" % want, func() -> void:
		if main.net.mode != "host":
			for i in want:
				kit.join_bot(main.party)
		elif not main.net.has_vr:
			kit.join_bot(main.party))  # a flat host (TV / Deck hosting): one pad robot here, in slot 0
	kit.at(1.2, "quick picks", func() -> void:
		if main.picks != null:
			main.picks.wait_scale = 0.4)
	if host:  # (while the TV machines are still connected: they leave before the host's end)
		kit.at(30.0, "host: everyone seated", func() -> void:
			var host_p := 0 if main.net.has_vr else 1  # (a flat host seats its own pad; a VR host never does)
			kit.assert_eq(kit.seated(), kit.seated_want(want, host_p), "host: every TV machine's players (+%d on the host) are seated" % host_p))
	kit.every(4.0, _report)
	kit.every(0.25, _watch)
	var full := 150.0 if host else (140.0 if client else 120.0)
	var end: float = preload("res://tests/bot_end.gd").end_at(full)
	short = preload("res://tests/bot_end.gd").short_run(48.0)  # (an island takes the bots 15-35 s)
	kit.at(end, "finish", func() -> void:
		_checks()
		kit.finish())


func _watch() -> String:
	if not main.ready_to_play:
		return ""
	if OS.has_environment("SKY_DEBUG") and not brains.is_empty() and not main.level.lv.is_empty() and (brains.values()[0] as Brain).k >= 4:
		var br0: Brain = brains.values()[0]
		var r1: CharacterBody3D = main.robots.values()[0]
		print("DBG2 t %.2f pos %s v %s floor %s k %d move %s jump %s hold %s" % [kit.t, r1.position, r1.velocity, r1.is_on_floor(), br0.k, br0.out_move, br0.out_jump, br0.out_hold])
	var d: Dictionary = main.net.state_get("ldesc", {})
	var key := var_to_str(d)
	if not d.is_empty() and not island_keys.has(key) and main.built_key == key:
		island_keys[key] = true
		built_on_island = true
		var lv := G.generate(d)
		for w in G.check(lv):
			kit.assert_true(false, "%s island %s passes the validator: %s" % [main.net.mode, G.island_name(d), w])
		kit.assert_true(var_to_str(main.level.lv.plats) == var_to_str(lv.plats), "%s built the described island %s" % [main.net.mode, G.island_name(d)])
		if island_keys.size() == 1:
			print("BOT AGREE first_island=%d/%d" % [int(d.get("i", -1)), int(d.get("s", 0))])
		kit.info("island %s seed %d: %d platforms, %d bolts, %d grumbles, %d zaps" % [G.island_name(d), int(d.get("s", 0)),
			(lv.plats as Array).size(), (lv.bolts as Array).size(), (lv.grumbles as Array).size(), (lv.zaps as Array).size()])
	if not main.level.lv.is_empty():
		max_bolts = maxi(max_bolts, (main.level.lv.bolts as Array).size() - main.level.bolts_left())
		gear_seen = gear_seen or main.level.gear_got
		wall_seen = wall_seen or main.level.wall_broken
	if main.boss != null and not main.boss.alive():
		crab_down = true
	if not main.level.lv.is_empty():
		var nb := 0
		for i in (main.level.lv.get("boxes", []) as Array).size():
			nb += 1 if main.level.box_open(i) else 0
		boxes_seen = maxi(boxes_seen, nb)
		for rb in main.robots.values():
			sprung = sprung or main.level.boings > 0
			fanned = fanned or main.gadget_push(rb, false).y > 0.0
	hats_seen = hats_seen or (main.net.state_get("hats", []) as Array).size() == 10
	var hp: Array = main.net.state_get("hubp", [])
	if hp.size() >= 1:
		if grew_from < 0:
			grew_from = int(hp[0])
		grew_to = int(hp[0])
	if main.picks != null and main.picks.showing():
		saw_orbs = true
		saw_vr_orbs = saw_vr_orbs or bool(main.picks.vr_row)
	return ""


func _physics_process(delta: float) -> void:
	if main == null or not main.ready_to_play or main.level == null:
		return
	for slot in main.party.local_slots():
		_tv_bot(slot, delta)
	if main.vr_rig != null:
		_vr_bot(delta)


## A TV bot: think like a CPU buddy, then push the stick and press A / X like a person.
func _tv_bot(slot: int, delta: float) -> void:
	var r: Node3D = main.robots.get(slot)
	if r == null:
		return
	if not brains.has(slot):
		brains[slot] = Brain.new()
	var br: Brain = brains[slot]
	var ph: String = main.phase()
	var move := Vector3.ZERO
	var jump := false
	var hold := false
	var punch := false
	if ph == "play" and not main.level.lv.is_empty():
		if br.get_meta("key", "") != main.built_key:
			br.set_meta("key", main.built_key)
			br.reset()
		var last: Vector3 = br.get_meta("last", r.position)
		if last.distance_to(r.position) > 3.0:  # popped back at a checkpoint flag
			br.respawned(main.level.lv, int(r.get("checkpoint")))
		br.set_meta("last", r.position)
		br.think(r, main.level, main.boss, delta)
		move = br.out_move
		jump = br.out_jump
		hold = br.out_hold
		punch = br.out_punch
	elif ph == "pick" and main.picks.showing() and not main.picks.vr_row and slot == main.party.local_slots()[0]:
		# Walk under the glowing (suggested) orb and stand there.
		var spots: Array = main.picks.spots
		var i: int = clampi(int(main.picks.def_i) if main.net.mode != "client" else spots.size() / 2, 0, spots.size() - 1)
		if i < spots.size():
			var to: Vector3 = spots[i]
			var f := Vector3(to.x - r.position.x, 0.0, to.z - r.position.z)
			if f.length() > 0.25:
				move = f.normalized()
			picked_by_robot = true
	var v := Vector2.ZERO
	if move.length() > 0.05 and main.split != null:
		var cam: Camera3D = main.split.active_camera(slot)
		var fw := -cam.global_basis.z
		fw.y = 0.0
		fw = fw.normalized()
		var right := Vector3(-fw.z, 0.0, fw.x)
		v = Vector2(move.dot(right), -move.dot(fw)).limit_length(1.0)
	kit.slot_stick(main.party, slot, "left", v)
	# A: a fresh press only to jump (then kept down to hover while the brain wants); never pressed again mid-air (a
	# press in the air is a buffered jump on landing, like a person's).
	if jump:
		if bool(held.get(slot, false)):
			kit.slot_hold(main.party, slot, "accept", false)
		kit.slot_hold(main.party, slot, "accept", true)
		held[slot] = true
	elif bool(held.get(slot, false)) and not hold:
		kit.slot_hold(main.party, slot, "accept", false)
		held[slot] = false
	if punch:
		kit.slot_press(main.party, slot, "x")
	if br.out_pound:
		kit.slot_press(main.party, slot, "b")


## The fake VR giant: stand like a real player, walk along with the robots, lift lifts, poke grumbles, take picks.
func _vr_bot(delta: float) -> void:
	var rig = main.vr_rig
	kit.vr_head_height(rig)
	vr_t += delta
	var head: Vector3 = rig.head_position()
	var ph: String = main.phase()
	if ph == "pick" and main.picks.showing() and main.picks.vr_row:
		var spots: Array = main.picks.spots
		var i: int = clampi(int(main.picks.def_i), 0, spots.size() - 1)
		kit.vr_stick(rig, Vector2.ZERO)
		kit.vr_reach(rig, VrRig.RIGHT, (spots[i] as Vector3) + Vector3(0, 0.0, 0), 2.0, delta)
		return
	if ph != "play" or main.level.lv.is_empty():
		kit.vr_idle(rig)
		kit.vr_stick(rig, Vector2.ZERO)
		kit.vr_trigger(rig, 0.0)
		return
	# Walk along with the robots (their middle in x).
	var mx := 0.0
	var n := 0
	for rb in main.robots.values():
		mx += (rb as Node3D).position.x
		n += 1
	mx = mx / maxf(1.0, n)
	var dx := mx - head.x
	kit.vr_stick(rig, Vector2(clampf(dx / 6.0, -1.0, 1.0) if absf(dx) > 3.0 else 0.0, 0.0))
	# A lift near the head: grab its handle, lift it to the top, let go.
	var lifts: Array = main.level.lifts()
	var best := -1
	for li in lifts:
		if absf(main.level.handle_point(int(li)).x - head.x) < 7.0:
			best = int(li)
	if vr_grab >= 0:
		var p: Dictionary = main.level.lv.plats[vr_grab]
		var top: float = float((p.b as Vector3).y)
		var hp: Vector3 = main.level.handle_point(vr_grab)
		kit.vr_reach(rig, VrRig.RIGHT, hp + Vector3(0, 0.8, 0), 4.0, delta)
		if main.level.plat_pos(vr_grab).y >= top - 0.2 or vr_t > 4.0:
			kit.vr_trigger(rig, 0.0)
			vr_grab = -1
			vr_t = 0.0
		return
	if best >= 0 and main.giant.lifts_used == vr_lifted and vr_t > 1.0:
		var hp2: Vector3 = main.level.handle_point(best)
		if kit.vr_reach(rig, VrRig.RIGHT, hp2, 4.0, delta):
			kit.vr_trigger(rig, 1.0)
			if main.giant.held_lift == best:
				vr_grab = best
				vr_lifted += 1
				vr_t = 0.0
		return
	kit.vr_trigger(rig, 0.0)
	kit.vr_idle(rig)


func _report() -> String:
	var lv: Dictionary = main.level.lv if main.level != null else {}
	var xs: Array = []
	for rb in main.robots.values():
		xs.append(snappedf((rb as Node3D).position.x, 0.1))
	if OS.has_environment("SKY_DEBUG") and not brains.is_empty() and not main.level.lv.is_empty():
		var br: Brain = brains.values()[0]
		var r0: Node3D = main.robots.values()[0]
		print("DBG pos %s floor %s k %d step %s on %d move %s" % [r0.position, r0.is_on_floor(), br.k, str(main.level.lv.route[br.k]),
			main.level.support(r0.position + Vector3.UP * 0.05, 0.3, 0.3), br.out_move])
	return "BOT %s: phase %s, island %s, robots x %s, bolts %d, gear %s, cp %d, cleared %s" % [main.net.mode, main.phase(),
		G.island_name(lv.desc) if not lv.is_empty() else "-", str(xs), max_bolts, str(main.level.gear_got),
		int(main.net.state_get("cp", 0)), str(main.finish_log)]


func _checks() -> void:
	var mode: String = main.net.mode
	kit.assert_true(main.ready_to_play, "the game started (%s)" % mode)
	if mode == "client":
		kit.assert_true(main.party.local_slots().size() == want, "client: all %d local players are seated" % want)
	elif mode == "local":
		kit.assert_eq(kit.seated(), want, "local: the TV players are seated")
	kit.assert_true(not island_keys.is_empty(), "%s: an island was built" % mode)
	kit.assert_true(max_bolts > 0, "%s: bolts were collected (%d)" % [mode, max_bolts])
	if mode != "client":
		kit.check_host_mode(main.net, main.mode)
	var cleared: bool = kit.seen("phase", "cheer") > 0
	if short:
		kit.info("short run: %s" % ("cleared an island" if cleared else "still on the island"))
	else:
		kit.assert_true(cleared, "%s: an island was cleared (the spark)" % mode)
		kit.assert_true(kit.seen("phase", "hub") > 0 or mode == "client", "%s: back home in Gizmo Town" % mode)
		if cleared and mode != "client":
			kit.assert_true(grew_to > grew_from or grew_from >= 10, "%s: Gizmo Town grew (%d -> %d)" % [mode, grew_from, grew_to])
	if mode != "client" and kit.seen("phase", "pick") > 0:
		kit.assert_true(saw_orbs, "%s: the pick orbs showed" % mode)
	if main.vr_rig != null and mode != "client" and not short:
		kit.assert_true(vr_lifted > 0 or main.giant.lifts_used > 0 or not _saw_lift(), "the VR giant lifted a lift")
	if OS.get_environment("SKY_ISLAND") == "3" and not short and mode != "client":
		kit.assert_true(crab_down, "Cranky Crab was beaten")
	if OS.get_environment("SKY_ISLAND") == "6" and not short and mode != "client":
		kit.assert_true(crab_down, "King Keywind was beaten")
	if OS.get_environment("SKY_ISLAND") == "4" and not short:
		kit.assert_true(sprung, "%s: a spring threw a robot up" % mode)
	if OS.get_environment("SKY_ISLAND") == "5" and not short:
		kit.assert_true(fanned, "%s: a fan's updraft lifted a robot" % mode)
	if not short and cleared:
		kit.assert_true(boxes_seen > 0, "%s: a bot box was opened (%d)" % [mode, boxes_seen])
	kit.assert_true(hats_seen, "%s: every robot's hat is shared" % mode)


func _saw_lift() -> bool:
	for k in island_keys:
		var d: Dictionary = str_to_var(k)
		for p in G.generate(d).plats:
			if String(p.k) == "lift":
				return true
	return false
