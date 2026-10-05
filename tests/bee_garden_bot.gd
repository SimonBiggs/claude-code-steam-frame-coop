extends Node
## Headless bot for Bee Garden. Drives whichever players are local on this machine:
##  - the flat gardener (local split screen / non-VR host) shoos pests, picks ripe fruit, waters
##    thirsty plants (and the sun lily) with the can, and plants seeds in empty spots;
##  - the bees fly to glowing flowers for pollen (a different flower each time, so fruit grows)
##    and take full loads to the hive.
## BOT_PLAYERS=n (2..6): n TV bees play (via main.debug_join; the last one drops in through a fake
## controller pressing A, gets unplugged at 22 s and plugged back in at 28 s).
## Prints progress every 10 s and "Bot: LEVEL COMPLETE" when the first day's jars are full.
## Events: the host/local bot starts each surprise event early (golden flower, queen, wasp raid, rain)
## because its bees fill the jars long before the day's own schedule; bees then visit the golden
## flower, bring the Queen her pollen and bump raid wasps away. (Not in SIMPLE_MODE: those are off.)
## SIMPLE_MODE (main.gd): checks the practice (seed -> glowing ring -> water), the ghost glove showing,
## the bees' halo flower, no pests / no events but rain, one seed kind then two, and prints
## "Bot: SIMPLE CHECK ..." at 50 s. BOT_VR=1 (local / host): the real VR gardener code runs with fake
## hands: it does the practice by hand (seed, can tipped over), then touches every prop (flower, gnome,
## snail, bird bath, chime, butterfly, rake in the soil) and picks, plants and waters like a person.
## DUO_HOST=1 with nobody joining = solo VR: the helper bees must make honey.

const W := preload("res://games/bee_garden/world.gd")
const PlantScript := preload("res://games/bee_garden/plant.gd")
const G := preload("res://games/bee_garden/gardener.gd")
const PR := preload("res://games/bee_garden/props.gd")

var main
var t := 0.0
var last_print := -100.0
var bot_players := clampi(int(OS.get_environment("BOT_PLAYERS")), 0, 6) if OS.has_environment("BOT_PLAYERS") else 0
var joined := 1
var fake_pad := 13
var pad_phase := 0
var reported := false
# gardener state machine
var g_state := "idle"
var g_spot := -1
var g_kind := 0
var g_timer := 0.0
var g_target := Vector3.ZERO
var g_seeds := 0
var g_tasks := {}
var test_events: Array[String] = ["golden", "queen", "raid", "rain"]
var test_event_i := 0
var events_seen := {}
# simple-mode checks
var simple := false
var ghost_seen := false
var halo_seen := false
var glow_seen := false
var max_pests := 0
var max_kinds := 0
var simple_reported := false
# fake VR gardener: waypoints [grab-point position, trigger 0/1, pitch, hold seconds]
var vr_queue: Array = []
var vr_pos := Vector3.ZERO
var vr_pitch := -0.6
var vr_hold := 0.0
var vr_task := ""
var vr_props_done := false
var vr_tasks_done := 0


func _ready() -> void:
	main = load("res://games/bee_garden/main.tscn").instantiate()
	add_child(main)


func _physics_process(delta: float) -> void:
	t += delta
	if not main.ready_to_play:
		return
	_party()
	simple = main.simple
	if main.gardener != null and main.gardener.flat and not main.gardener.ghost:
		_drive_gardener(delta)
	elif main.gardener != null and main.gardener.fake_vr:
		_drive_vr(delta)
	if simple:
		_simple_checks()
	for b in main.bees():
		if not b.remote:
			_drive_bee(b)
	if not simple and main.net.mode != "client" and main.phase == "day" and main.event == "" and test_event_i < test_events.size() \
			and t > 4.0 + test_event_i * 7.0:
		print("Bot: starting event %s" % test_events[test_event_i])
		main._start_event(test_events[test_event_i])
		test_event_i += 1
	if main.event != "" and not events_seen.has(main.event):
		events_seen[main.event] = true
		print("Bot: sees event %s (mode=%s)" % [main.event, main.net.mode])
	if main.days_done >= 1 and not reported:
		reported = true
		print("Bot: LEVEL COMPLETE at t=%.1f (mode=%s, day %d done, honey %d)" % [t, main.net.mode, main.days_done, main.total_honey])
	if t - last_print >= 10.0:
		last_print = t
		var bs: Array[String] = []
		for b in main.bees():
			if b.active:
				bs.append("P%d pollen=%d made=%d" % [b.index + 1, b.pollen, b.honey_made])
		var planted := 0
		var blooming := 0
		var fruit := 0
		for s in main.spots:
			if int(s.kind) >= 0:
				planted += 1
			if s.bloom:
				blooming += 1
			if float(s.fruit) >= 0.0:
				fruit += 1
		print("t=%.0f mode=%s phase=%s day=%d honey=%d/%d days_done=%d plants=%d bloom=%d fruit=%d pests=%d views=%d gardener=%s %s" % [
			t, main.net.mode, main.phase, main.day, main.honey, main.target, main.days_done, planted, blooming, fruit,
			get_tree().get_nodes_in_group("pests").size(), main.view_count, g_state, ", ".join(bs)])
		print("   stats: %s  event=%s rain=%.0f rainbow=%.0f golden=%d decor=%d wish=%s %d done=%s queen_gifts=%d" % [str(main.stats),
			main.event, main.rain_t, main.rainbow_t, main.golden_spot, main.decor_count, str(main.wish), main.wish_progress,
			main.wish_done, main.queen_gifts])


## BOT_PLAYERS: bring in extra TV bees one by one, and exercise unplug / replug.
func _party() -> void:
	if bot_players < 2 or main.net.mode == "host":
		return
	if main.net.mode == "client" and not main.synced:
		return
	if joined < bot_players and t >= 3.0 + joined * 1.5:
		joined += 1
		if joined == bot_players and joined >= 3:
			var ev := InputEventJoypadButton.new()
			ev.device = fake_pad
			ev.button_index = JOY_BUTTON_A
			ev.pressed = true
			Input.parse_input_event(ev)
			print("Bot: fake controller %d pressed A (expect P%d)" % [fake_pad, joined + 1])
		else:
			print("Bot: P%d joins" % (joined + 1))
			main.debug_join(joined)
	if joined == bot_players and bot_players >= 3:
		if pad_phase == 0 and t >= 22.0:
			pad_phase = 1
			print("Bot: unplugging controller %d (owner P%d)" % [fake_pad, main.pad_owner(fake_pad) + 1])
			main._on_joy_changed(fake_pad, false)
		elif pad_phase == 1 and t >= 28.0:
			pad_phase = 2
			print("Bot: plugging controller %d back in" % fake_pad)
			main._on_joy_changed(fake_pad, true)
			print("Bot: controller %d now owned by P%d" % [fake_pad, main.pad_owner(fake_pad) + 1])


# --- Bees ----------------------------------------------------------------------

func _drive_bee(b) -> void:
	var inp := {"move": Vector3.ZERO, "zoom": false}
	if not b.active:
		# P3 presses zoom to join (the original 2-player TV test)
		inp.zoom = bot_players == 0 and main.net.mode == "client" and b.index == 2 and int(t * 2.0) % 2 == 0
		b.bot_input = inp
		return
	if main.game_over:
		inp.zoom = int(t) % 3 == 0
		b.bot_input = inp
		return
	var pos: Vector3 = b.global_position
	var goal := Vector3.ZERO
	var have_goal := false
	var last: int = b.get_meta("bot_last", -1)
	# Events: bump raid wasps, bring the Queen her pollen.
	if main.event == "raid":
		for p in get_tree().get_nodes_in_group("pests"):
			if p.kind == "wasp" and not p.is_fleeing():
				goal = p.global_position
				have_goal = true
				break
	if not have_goal and main.event == "queen" and b.pollen > 0 and (int(b.pollen_kinds) & (1 << int(main.queen_kind))) != 0:
		goal = main.events_node.queen_pos()
		have_goal = true
	if not have_goal and b.pollen > 0:
		var to_hive := W.HIVE_ENTRY + Vector3(0.2, 0.0, 0.0)
		if b.pollen >= 3:
			goal = to_hive
			have_goal = true
	if not have_goal:
		var best := INF
		for i in main.spots.size():
			var s: Dictionary = main.spots[i]
			if not s.bloom or i == last:
				continue
			var hp: Vector3 = main.head_pos(i)
			var d := hp.distance_to(pos)
			if not s.ready:
				d += 6.0
			if i == main.golden_spot:
				d -= 4.0
			if main.event == "queen" and int(s.kind) == int(main.queen_kind):
				d -= 3.0
			# spread the bees out over the flowers
			for o in main.bees():
				if o != b and o.active and int(o.get_meta("bot_goal", -1)) == i:
					d += 3.0
			if d < best:
				best = d
				goal = hp
				have_goal = true
				b.set_meta("bot_goal", i)
		if b.pollen > 0 and (not have_goal or best > 7.0):
			goal = W.HIVE_ENTRY + Vector3(0.2, 0.0, 0.0)
			have_goal = true
	if not have_goal:
		goal = Vector3(0.0, 1.2, 0.0)
	# remember which flower we touched (the host decides pollen; we just keep moving on)
	for i in main.spots.size():
		var s: Dictionary = main.spots[i]
		if s.bloom and main.head_pos(i).distance_to(pos) < 0.45:
			if b.get_meta("bot_last", -1) != i:
				b.set_meta("bot_last", i)
	if b.pollen == 0 and pos.distance_to(W.HIVE_ENTRY) < 1.0:
		b.set_meta("bot_last", -1)
	var to := goal - pos
	if to.length() > 0.12:
		inp.move = to.normalized() * clampf(to.length() / 0.5, 0.3, 1.0)
	inp.zoom = to.length() > 4.0 and int(t * 3.0 + b.index) % 7 == 0
	b.bot_input = inp


# --- Gardener ------------------------------------------------------------------

func _drive_gardener(delta: float) -> void:
	var g = main.gardener
	g.bot = true
	var h = g.hands[0]
	var hp: Vector3 = h.pos
	g_timer += delta
	if main.game_over:
		g.bot_grip = false
		g_state = "idle"
		return
	match g_state:
		"idle":
			g.bot_grip = false
			if g_timer < 0.25:
				return
			_pick_task()
		"click":
			g.bot_target = g_target
			if _near(hp, g_target, 0.18) or g_timer > 4.0:
				g.bot_grip = true
				g_state = "release"
				g_timer = 0.0
		"release":
			g.bot_grip = false
			if g_timer > 0.15:
				g_state = "idle"
				g_timer = 0.0
		"fetch_can":
			g.bot_target = W.CAN_HOME
			if _near(hp, W.CAN_HOME, 0.25):
				g.bot_grip = true
				g_state = "carry_can"
				g_timer = 0.0
			elif g_timer > 5.0:
				g_state = "idle"
		"carry_can":
			g.bot_grip = true
			var sp := W.spot_pos(g_spot)
			g.bot_target = sp
			var s: Dictionary = main.spots[g_spot]
			if (_near(hp, sp, 0.3) and float(s.water) >= 0.95) or g_timer > 8.0 or int(s.kind) < 0:
				g.bot_grip = false
				g_state = "release"
				g_timer = 0.0
		"fetch_seed":
			var slot := W.tray_slot(g_kind)
			g.bot_target = slot
			if _near(hp, slot, 0.1):
				g.bot_grip = true
				g_state = "carry_seed"
				g_timer = 0.0
			elif g_timer > 5.0:
				g_state = "idle"
		"carry_seed":
			g.bot_grip = true
			var sp := W.spot_pos(g_spot)
			g.bot_target = sp
			if _near(hp, sp, 0.15) or g_timer > 6.0:
				g.bot_grip = false
				g_seeds += 1
				g_state = "release"
				g_timer = 0.0


func _near(a: Vector3, b: Vector3, r: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() < r


func _pick_task() -> void:
	g_timer = 0.0
	# 1. pests
	for p in get_tree().get_nodes_in_group("pests"):
		if not p.is_fleeing() and p.state == "munch":
			g_target = p.global_position
			g_state = "click"
			print("Bot gardener: shooing a %s" % p.kind)
			return
	# 2. ripe fruit
	for i in main.spots.size():
		var s: Dictionary = main.spots[i]
		if int(s.kind) >= 0 and float(s.fruit) >= 1.0:
			g_target = main.head_pos(i) + Vector3(0.0, 0.0, 0.08)
			g_state = "click"
			return
	# 3. thirsty plants (and the sun lily, which wants a lot)
	var worst := -1
	var worst_w := 0.4
	for i in main.spots.size():
		var s: Dictionary = main.spots[i]
		var k: int = s.kind
		if k < 0:
			continue
		var w: float = s.water
		if k == 2 and not s.bloom:
			w -= 0.5
		if w < worst_w:
			worst_w = w
			worst = i
	if worst >= 0:
		g_spot = worst
		g_state = "fetch_can"
		return
	# 4. empty spots get a seed (daisy, sunflower, daisy, sun lily, ...)
	for i in main.spots.size():
		if int(main.spots[i].kind) < 0:
			g_spot = i
			g_kind = (g_seeds % int(main.seed_kinds)) if main.simple else [0, 1, 0, 2][g_seeds % 4]
			g_state = "fetch_seed"
			return
	g_state = "idle"
	main.gardener.bot_target = Vector3(0.0, 0.0, 0.8)


# --- Simple mode checks -----------------------------------------------------------

func _simple_checks() -> void:
	if main.ghost_hand != null and main.ghost_hand.visible:
		ghost_seen = true
	if main.glow_spot >= 0 and main.plant_nodes[main.glow_spot].ring.visible:
		glow_seen = true
	if main.halo_spot >= 0 and main.plant_nodes[main.halo_spot].halo.visible:
		halo_seen = true
	max_pests = maxi(max_pests, get_tree().get_nodes_in_group("pests").size())
	if main.props != null and (absf(main.props.chime_ang) > 0.05 or absf(main.props.gnome_ang) > 0.05):
		events_seen["props_moving"] = true  # on the TV: the snapshots carry the props
	max_kinds = maxi(max_kinds, int(main.seed_kinds))
	if main.event != "" and main.event != "rain" and not events_seen.has("bad_" + main.event):
		events_seen["bad_" + main.event] = true
		print("Bot: SIMPLE FAIL: event %s should be off" % main.event)
	if main.game_over and not events_seen.has("bad_over"):
		events_seen["bad_over"] = true
		print("Bot: SIMPLE FAIL: game over in simple mode")
	if t >= 50.0 and not simple_reported:
		simple_reported = true
		var touched: Dictionary = main.props.touched if main.props != null else {}
		var helped: int = main.helpers.delivered if main.helpers != null else 0
		print("Bot: SIMPLE CHECK mode=%s practice=%s ghost_glove=%s glow_ring=%s halo=%s max_pests=%d seed_kinds=%d rounds=%d honey=%d game_over=%s helpers_delivered=%d props_moving=%s props=%s" % [
			main.net.mode, main.practice_g, ghost_seen, glow_seen, halo_seen, max_pests, max_kinds, main.days_done,
			main.total_honey, main.game_over, helped, events_seen.has("props_moving"), str(touched)])
		if main.gardener.fake_vr:
			var missing: Array[String] = []
			for k in ["flower", "gnome", "snail", "bath", "chime", "butterfly", "rake", "rake_soil"]:
				if not touched.has(k):
					missing.append(k)
			print("Bot: VR props %s" % ("ALL TOUCHED" if missing.is_empty() else "MISSING " + str(missing)))


# --- Fake VR gardener --------------------------------------------------------------

func _drive_vr(delta: float) -> void:
	var g = main.gardener
	if not g.calibrated:
		return
	g.hand_l.global_position = Vector3(-1.5, 2.2, 3.5)  # the left hand stays out of the way
	if vr_pos == Vector3.ZERO:
		vr_pos = g.hands[1].pos
	if vr_queue.is_empty():
		_plan_vr()
	if vr_queue.is_empty():
		return
	var wp: Array = vr_queue[0]
	var target: Vector3 = wp[0]
	vr_pos = vr_pos.move_toward(target, 3.0 * delta)
	vr_pitch = move_toward(vr_pitch, float(wp[2]), 2.5 * delta)
	if vr_pos.distance_to(target) < 0.01:
		g.fake_trigger = float(wp[1])
		vr_hold += delta
		if vr_hold >= float(wp[3]):
			vr_hold = 0.0
			vr_queue.pop_front()
	var b := Basis(Vector3.RIGHT, vr_pitch)
	g.hand_r.global_transform = Transform3D(b, vr_pos - b * G.GRAB_OFFSET)


func _wp(p: Vector3, trig: float, hold: float = 0.2, pitch: float = -0.6) -> void:
	vr_queue.append([p, trig, pitch, hold])


func _plan_vr() -> void:
	if not main.can_interact():
		return
	var spot: int = main.glow_spot
	if main.practice_g == "seed" and spot >= 0:
		_vr_plant(spot, 0)
		vr_task = "practice seed"
	elif main.practice_g == "water" and spot >= 0:
		_vr_water(spot)
		vr_task = "practice water"
	elif not vr_props_done:
		vr_props_done = true
		vr_task = "props"
		var P = main.props
		_wp(PR.GNOME + Vector3(0.6, 0.35, 0.0), 0.0, 0.0)
		_wp(PR.GNOME + Vector3(0.0, 0.35, 0.0), 0.0, 0.3)
		_wp(Vector3(P.snail_x + 0.1 * P.snail_dir, 0.14, PR.SNAIL_Z), 0.0, 0.3)
		for i in main.spots.size():
			if main.spots[i].bloom:
				_wp(main.head_pos(i) + Vector3(0.4, 0.0, 0.0), 0.0, 0.0)
				_wp(main.head_pos(i), 0.0, 0.3)
				break
		_wp(P.flies[0]["pos"] + Vector3(0.0, 0.3, 0.0), 0.0, 0.0)
		_wp(P.flies[0]["pos"], 0.0, 0.3)
		_wp(PR.BATH + Vector3(0.0, 0.4, 0.0), 0.0, 0.0)
		_wp(PR.BATH + Vector3(0.0, 0.05, 0.0), 0.0, 0.3)
		_wp(PR.CHIME + Vector3(-0.5, 0.0, 0.0), 0.0, 0.0)
		_wp(PR.CHIME, 0.0, 0.3)
		_wp(PR.RAKE_HOME + Vector3(0.0, 0.1, 0.0), 0.0, 0.2)
		_wp(PR.RAKE_HOME + Vector3(0.0, 0.1, 0.0), 1.0, 0.3)
		for k in 3:
			_wp(Vector3(1.8, 0.25, 0.9), 1.0, 0.0)
			_wp(Vector3(3.0, 0.25, 0.9), 1.0, 0.0)
		_wp(PR.RAKE_HOME + Vector3(0.0, 0.3, 0.0), 1.0, 0.0)
		_wp(PR.RAKE_HOME + Vector3(0.0, 0.3, 0.0), 0.0, 0.3)
	else:
		vr_tasks_done += 1
		# Like a person: pick ripe fruit, water thirsty plants, plant empty spots.
		for i in main.spots.size():
			var s: Dictionary = main.spots[i]
			if int(s.kind) >= 0 and float(s.fruit) >= 1.0:
				var fp: Vector3 = main.head_pos(i) + Vector3(0.0, -0.1, 0.08)
				_wp(fp + Vector3(0.0, 0.3, 0.0), 0.0, 0.0)
				_wp(fp, 0.0, 0.1)
				_wp(fp, 1.0, 0.2)
				_wp(fp + Vector3(0.0, 0.3, 0.0), 0.0, 0.2)
				vr_task = "pick"
				return
		for i in main.spots.size():
			var s2: Dictionary = main.spots[i]
			if int(s2.kind) >= 0 and float(s2.water) < 0.3:
				_vr_water(i)
				vr_task = "water"
				return
		for i in main.spots.size():
			if int(main.spots[i].kind) < 0:
				_vr_plant(i, vr_tasks_done % int(main.seed_kinds))
				vr_task = "plant"
				return
		_wp(Vector3(0.0, 1.0, 2.6), 0.0, 0.5)
		vr_task = "idle"


func _vr_plant(spot: int, kind: int) -> void:
	var slot := W.tray_slot(kind) + Vector3(0.0, 0.05, 0.0)
	var sp := W.spot_pos(spot)
	_wp(slot + Vector3(0.0, 0.3, 0.0), 0.0, 0.0)
	_wp(slot, 0.0, 0.1)
	_wp(slot, 1.0, 0.3)
	_wp(sp + Vector3(0.0, 0.6, 0.0), 1.0, 0.0)
	_wp(sp + Vector3(0.0, 0.3, 0.0), 1.0, 0.3)
	_wp(sp + Vector3(0.0, 0.3, 0.0), 0.0, 0.6)


func _vr_water(spot: int) -> void:
	var can := W.CAN_HOME + Vector3(0.0, 0.3, 0.0)
	var over := W.spot_pos(spot) + Vector3(0.0, 1.0, 0.3)
	_wp(can + Vector3(0.0, 0.3, 0.0), 0.0, 0.0)
	_wp(can, 0.0, 0.1)
	_wp(can, 1.0, 0.3)
	_wp(over, 1.0, 0.0)
	_wp(over, 1.0, 3.5, -1.3)
	_wp(can + Vector3(0.0, 0.3, 0.0), 1.0, 0.0)
	_wp(can + Vector3(0.0, 0.3, 0.0), 0.0, 0.3)
