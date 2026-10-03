extends Node
## Headless bot for Bee Garden. Drives whichever players are local on this machine:
##  - the flat gardener (local split screen / non-VR host) shoos pests, picks ripe fruit, waters
##    thirsty plants (and the sun lily) with the can, and plants seeds in empty spots;
##  - the bees fly to glowing flowers for pollen (a different flower each time, so fruit grows)
##    and take full loads to the hive.
## BOT_PLAYERS=n (2..6): n TV bees play (via main.debug_join; the last one drops in through a fake
## controller pressing A, gets unplugged at 22 s and plugged back in at 28 s).
## Prints progress every 10 s and "Bot: LEVEL COMPLETE" when the first day's jars are full.

const W := preload("res://games/bee_garden/world.gd")
const PlantScript := preload("res://games/bee_garden/plant.gd")

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


func _ready() -> void:
	main = load("res://games/bee_garden/main.tscn").instantiate()
	add_child(main)


func _physics_process(delta: float) -> void:
	t += delta
	if not main.ready_to_play:
		return
	_party()
	if main.gardener != null and main.gardener.flat and not main.gardener.ghost:
		_drive_gardener(delta)
	for b in main.bees():
		if not b.remote:
			_drive_bee(b)
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
		print("   stats: %s" % str(main.stats))


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
	if b.pollen > 0:
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
			g_kind = [0, 1, 0, 2][g_seeds % 4]
			g_state = "fetch_seed"
			return
	g_state = "idle"
	main.gardener.bot_target = Vector3(0.0, 0.0, 0.8)
