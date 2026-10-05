extends Node
## Headless bot for Giant's Table. Drives whichever players are local on this machine:
## the flat giant grabs goblins/ogres and throws them off the table, drops boulders on armoured
## goblins and carries downed knights to the campfire; the knights chase goblins with sword and
## crossbow and fetch dropped embers. Prints progress every 10 s.
## BOT_PLAYERS=n (2..6): n TV knights join (via main.debug_join; the last one drops in through a fake
## controller button press, then gets unplugged at 22 s and plugged back in at 28 s).
## Simple mode (main.simple): the giant does the practice throws first (the training goblin is a plain
## goblin to it), and between waves pulls up a tree and throws it (once per bot run per hand type).

const W := preload("res://games/giants_table/world.gd")

var main
var t := 0.0
var grabs := 0
var giant_mode := "pick"
var giant_target = null
var giant_wait := 0.0
var last_print := -100.0
var lazy := OS.has_environment("BOT_LAZY_GIANT")  # giant only rescues knights: tests downs and revives
var bot_players := clampi(int(OS.get_environment("BOT_PLAYERS")), 0, 6) if OS.has_environment("BOT_PLAYERS") else 0
var joined := 1
var fake_pad := 13  # device id for the simulated drop-in controller
var pad_phase := 0
var seen := {}
var smacks := 0


func _ready() -> void:
	main = load("res://games/giants_table/main.tscn").instantiate()
	add_child(main)
	if OS.has_environment("START_WAVE"):
		main.wave = int(OS.get_environment("START_WAVE"))


func _physics_process(delta: float) -> void:
	t += delta
	if not main.ready_to_play:
		return
	# Knock knight P2 down at t=25 s (host side) so the giant has someone to rescue.
	if OS.has_environment("BOT_DOWN") and t >= 25.0 and t - delta < 25.0 and main.net.mode != "client":
		print("Bot: knocking P2 down")
		main.knight_hurt(main.players[1], 999.0, Vector3.ZERO)
	_party(delta)
	_note_features()
	if OS.has_environment("GT_LOSE") and t > 20.0 and not main.game_over and main.net.mode != "client" and not has_meta("lost"):
		set_meta("lost", true)
		print("Bot: forcing a game over (tests the heroes screen)")
		main._on_game_over("The goblins stole the campfire!")
	if main.giant != null and main.giant.flat:
		_drive_giant(delta)
	elif main.giant != null and main.giant.vr:
		_drive_vr_giant(delta)
	for k in main.knights():
		if not k.remote:
			_drive_knight(k)
	if t - last_print >= 10.0:
		last_print = t
		var ks: Array[String] = []
		for k in main.knights():
			ks.append("P%d hp=%d%s%s%s" % [k.index + 1, int(k.hp), " DOWN" if k.is_down else "", " ember" if k.carrying else "", "" if k.active else " (asleep)"])
		var cell := Vector2.ZERO
		if main.knights()[0].has_meta("view"):
			cell = main.knights()[0].get_meta("view").size
		print("t=%.0f knights=%d views=%d cell=%s" % [t, main.active_knight_count(), main.view_count, cell])
		print("t=%.0f mode=%s wave=%d score=%d embers=%d goblins=%d boulders=%d loose_embers=%d grabs=%d %s%s" % [
			t, main.net.mode, main.wave, main.score, main.embers,
			get_tree().get_nodes_in_group("goblins").size(), get_tree().get_nodes_in_group("boulders").size(),
			get_tree().get_nodes_in_group("embers").size(), grabs, ", ".join(ks), " GAME OVER" if main.game_over else ""])
		var gl := get_tree().get_nodes_in_group("goblins")
		if gl.size() <= 2:
			for g in gl:
				print("   %s at %s flying=%s dizzy=%.1f carrying=%s" % [g.kind, g.global_position.snapped(Vector3.ONE * 0.1), g.flying, g.dizzy_t, g.carrying])
		if not main.kills.is_empty():
			print("   kills: %s" % str(main.kills))


## Prints each new feature the first time it shows up.
func _note_features() -> void:
	var kinds := {}
	var floating := false
	var king_broken := false
	for g in get_tree().get_nodes_in_group("goblins"):
		kinds[g.kind] = true
		if g.floating:
			floating = true
		if g.kind == "king" and g.armor <= 0.0:
			king_broken = true
	var checks := {
		"practice done": main.practice_done,
		"tree pulled up": not get_tree().get_nodes_in_group("props").is_empty(),
		"scenery touched": main.scenery != null and main.scenery.touches > 0,
		"balloon goblin floating": floating,
		"goblin king": kinds.has("king"),
		"king armour broken": king_broken,
		"rain": main.rain_t > 0.0,
		"giant shielding the fire": main.shield,
	}
	if not main.simple:
		checks.merge({"village grew": main.built > 0, "combo": main.combo >= 3,
			"giant tip": main.giant_tip_t > 0.0, "stats": main.stats_text != ""})
	for k in checks:
		if checks[k] and not seen.has(k):
			seen[k] = true
			var extra := ""
			if k == "giant tip":
				extra = ": " + main.giant_tip
			elif k == "village grew":
				extra = ": %d building(s)" % main.built
			print("Bot: seen %s (t=%.0f, wave %d)%s" % [k, t, main.wave, extra])


## BOT_PLAYERS: bring in extra TV knights one by one, and exercise unplug / replug.
func _party(_delta: float) -> void:
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


func _drive_knight(k) -> void:
	var inp := {"move": Vector3.ZERO, "sword": false, "bow": false, "jump": false}
	if not k.active:
		# player 3 presses attack to join (the original 2-player TV test)
		inp.sword = bot_players == 0 and main.net.mode == "client" and k.index == 2 and int(t * 2.0) % 2 == 0
		k.bot_input = inp
		return
	if main.game_over:
		inp.sword = int(t) % 3 == 0  # restart
		k.bot_input = inp
		return
	var pos: Vector3 = k.global_position
	var target = null
	var target_pos := Vector3.ZERO
	if k.carrying:
		target_pos = Vector3(0.0, 0.0, 1.8)
	else:
		var best := INF
		for o in main.knights():
			if o != k and o.active and o.is_down:
				target_pos = o.global_position
				best = 0.0
		if best > 0.0:
			for e in get_tree().get_nodes_in_group("embers"):
				var d: float = e.global_position.distance_to(pos)
				if d < best:
					best = d
					target_pos = e.global_position
			if best > 6.0:
				for g in get_tree().get_nodes_in_group("goblins"):
					if g.held or g.flying or g.practice or (not main.simple and (g.kind == "ogre" or (g.kind == "king" and g.armor <= 0.0))):
						continue
					var d: float = g.global_position.distance_to(pos) + Vector2(g.global_position.x, g.global_position.z).length() * 0.3
					if d < best:
						best = d
						target = g
						target_pos = g.global_position
	var to := target_pos - pos
	to.y = 0.0
	var dist := to.length()
	if target != null and target.floating:
		# A balloon goblin up in the air: stand back a little and shoot the balloon.
		if dist < 3.0:
			to = -to
		inp.move = to.normalized() * (0.6 if dist < 3.0 else 1.0) if absf(dist - 4.0) > 1.0 else Vector3.ZERO
		k.face = atan2(-(target_pos - pos).x, -(target_pos - pos).z)
		inp.bow = true
		inp.jump = false
		k.bot_input = inp
		return
	if dist > 1.0 or target == null:
		inp.move = to.normalized() if dist > 0.3 else Vector3.ZERO
	if target != null:
		var face_dir := Basis(Vector3.UP, k.face) * Vector3(0, 0, -1)
		if dist < 1.5:
			inp.sword = true
			k.face = atan2(-to.x, -to.z)
		elif dist < 9.0 and face_dir.dot(to / dist) > 0.9:
			inp.bow = true
	# hop now and then (tests jumping onto boulders / out of the river)
	inp.jump = int(t * 10.0) % 37 == 0
	k.bot_input = inp


func _drive_giant(delta: float) -> void:
	var g = main.giant
	g.bot = true
	var h = g.hands[0]
	giant_wait -= delta
	if main.game_over:
		g.bot_grip = false
		return
	if h.held != null and is_instance_valid(h.held):
		var obj = h.held
		if obj.is_in_group("boulders"):
			# drop it onto the nearest armoured goblin (or any goblin)
			var best = _nearest_goblin(obj.global_position, ["armored", "goblin"])
			if best == null:
				g.bot_target = Vector3(0, 0, -5.5)  # stepping stone in the river
				if Vector2(h.pos.x - 0.0, h.pos.z + 5.5).length() < 0.6:
					g.bot_grip = false
			else:
				g.bot_target = best.global_position
				if Vector2(h.pos.x - best.global_position.x, h.pos.z - best.global_position.z).length() < 0.5:
					g.bot_grip = false
		elif obj.is_in_group("props"):
			g.bot_target = Vector3(3.0, 0.0, 6.0)  # simple mode: toss the tree back onto the table
			if Vector2(h.pos.x - 3.0, h.pos.z - 6.0).length() < 0.8:
				g.bot_grip = false
				print("Bot: giant threw a tree")
		elif obj.is_in_group("knights"):
			g.bot_target = Vector3(0.0, 0.0, 1.8)
			if Vector2(h.pos.x, h.pos.z - 1.8).length() < 0.6 and h.vel.length() < 4.0:
				g.bot_grip = false
				print("Bot: giant carried P%d to the campfire" % (obj.index + 1))
		else:
			var flat := Vector2(obj.global_position.x, obj.global_position.z)
			var out := flat.normalized() * (W.EDGE + 2.5) if flat.length() > 0.5 else Vector2(0, W.EDGE + 2.5)
			g.bot_target = Vector3(out.x, 0.0, out.y)
			if Vector2(h.pos.x, h.pos.z).length() > W.EDGE + 1.5:
				g.bot_grip = false
		if not g.bot_grip:
			giant_wait = 3.0
		return
	if main.rain_t > 0.0 and not g.bot_grip:
		g.bot_target = Vector3(0.3, 0.0, 0.3)  # hold the hand over the campfire like an umbrella
		return
	if g.bot_grip and giant_wait < -1.5:
		g.bot_grip = false  # couldn't grab it; pick something else
		giant_wait = 0.2
	if giant_wait > 0.0:
		g.bot_grip = false
		return
	# Pick a target: a downed knight, else an ogre, else (every third grab) a boulder, else a goblin.
	var target = null
	for k in main.knights():
		if k.active and k.is_down and not k.carried:
			target = k
	if lazy and target == null:
		g.bot_grip = false
		g.bot_target = Vector3(0, 0, 6)
		return
	if target == null:
		target = _nearest_goblin(Vector3.ZERO, ["ogre", "king"])
	if target == null:
		target = _nearest_goblin(Vector3.ZERO, ["balloon"])
	if target == null and grabs % 3 == 2 and _nearest_goblin(Vector3.ZERO, ["armored"]) != null:
		var bb := INF
		for b in get_tree().get_nodes_in_group("boulders"):
			if b.flying:
				continue
			var d: float = b.global_position.distance_to(h.pos)
			if d < bb:
				bb = d
				target = b
	if target == null:
		target = _nearest_goblin(Vector3.ZERO, ["goblin"])
	if target == null and main.simple and main.practice_done and not has_meta("tree_done"):
		var tp := _a_tree()
		g.bot_target = tp
		if Vector2(h.pos.x - tp.x, h.pos.z - tp.z).length() < 0.8 and not g.bot_grip:
			g.bot_grip = true
			giant_wait = 0.0
			set_meta("tree_done", true)
			print("Bot: giant reaches for a tree")
		return
	if target == null:
		g.bot_grip = false
		g.bot_target = Vector3(0, 0, 5)
		return
	g.bot_target = target.global_position
	var close: bool = Vector2(h.pos.x - target.global_position.x, h.pos.z - target.global_position.z).length() < 0.8
	if close and not g.bot_grip:
		g.bot_grip = true
		giant_wait = 0.0
		grabs += 1


## A tree near the giant's side of the table (simple mode: trees can be pulled up).
func _a_tree() -> Vector3:
	var best := Vector3.ZERO
	var bd := INF
	for t in W.trees():
		var p := Vector3(t[0], W.height(t[0], t[1]), t[1])
		var d := p.distance_to(Vector3(0, 0, 10))
		if d < bd:
			bd = d
			best = p
	return best


func _nearest_goblin(from: Vector3, kinds: Array):
	var best = null
	var bd := INF
	for g in get_tree().get_nodes_in_group("goblins"):
		if g.held or g.flying or not (g.kind in kinds) or g.has_meta("dead") or not g.can_grab():
			continue
		var d: float = g.global_position.distance_to(from)
		if d < bd:
			bd = d
			best = g
	return best


## GT_FAKE_VR: move the right controller node by hand (no headset) and squeeze to grab goblins,
## carry them past the table edge and let go.
var vr_phase := 0
var vr_target = null
var smack_phase := 0
func _drive_vr_giant(delta: float) -> void:
	var g = main.giant
	g.bot = true
	var ctrl: Node3D = g.hand_r
	var h = g.hands[1]
	if main.game_over:
		g.bot_grip = false
		return
	var grab_off: Vector3 = ctrl.global_basis * g.GRAB_OFFSET
	if main.rain_t > 0.0 and h.held == null:
		g.bot_grip = false
		ctrl.global_position = ctrl.global_position.move_toward(Vector3(0.0, 4.0, 0.0) - grab_off, 25.0 * delta)
		return
	# Every few goblins, SMACK one flat with the left hand instead (no button: a fast slap down).
	var left: Node3D = g.hand_l
	var lh = g.hands[0]
	var lgrab: Vector3 = left.global_basis * g.GRAB_OFFSET
	var victim = _nearest_goblin(Vector3.ZERO, ["goblin"])
	if victim != null and grabs % 3 == 1:
		var c2: Vector3 = victim.global_position
		var above := c2 + Vector3.UP * 3.0 - lgrab
		if smack_phase == 0:
			left.global_position = left.global_position.move_toward(above, 30.0 * delta)
			if left.global_position.distance_to(above) < 0.3:
				smack_phase = 1
		else:
			left.global_position = left.global_position.move_toward(c2 + Vector3.UP * 0.3 - lgrab, 45.0 * delta)
			if lh.pos.y < c2.y + 0.6:
				smack_phase = 0
				smacks += 1
				grabs += 1
				print("Bot: VR giant smacked down at a goblin (vel %.0f)" % lh.vel.y)
		return
	if h.held != null and is_instance_valid(h.held):
		var p: Vector3 = h.held.global_position
		var out := Vector2(p.x, p.z).normalized() * (W.EDGE + 3.0)
		var want := Vector3(out.x, 6.0, out.y)
		ctrl.global_position = ctrl.global_position.move_toward(want - grab_off, 25.0 * delta)
		if Vector2(h.pos.x, h.pos.z).length() > W.EDGE + 2.0:
			g.bot_grip = false
			print("Bot: VR giant threw a %s" % h.held.get("kind"))
		return
	if vr_target == null or not is_instance_valid(vr_target) or vr_target.flying:
		vr_target = _nearest_goblin(Vector3.ZERO, ["goblin", "ogre", "king"])
		g.bot_grip = false
		if vr_target == null and main.simple and main.practice_done and not has_meta("tree_done"):
			# Between waves: pull up a tree with the right hand (and throw it off the table).
			var tp := _a_tree() + Vector3.UP * 1.3
			ctrl.global_position = ctrl.global_position.move_toward(tp - grab_off, 30.0 * delta)
			if h.pos.distance_to(tp) < 0.6:
				g.bot_grip = true
				set_meta("tree_done", true)
				print("Bot: VR giant grabs a tree")
			return
		if vr_target == null:
			return
	var c: Vector3 = vr_target.grab_center()
	ctrl.global_position = ctrl.global_position.move_toward(c - grab_off, 30.0 * delta)
	if h.pos.distance_to(c) < 0.6:
		g.bot_grip = true
		grabs += 1


func _count_visuals(n: Node) -> int:
	var c := 0
	if (n is MeshInstance3D or n is MultiMeshInstance3D or n is CPUParticles3D or n is Label3D) and n.is_visible_in_tree():
		c += 1
	for ch in n.get_children():
		c += _count_visuals(ch)
	return c


func _exit_tree() -> void:
	if main != null:
		print("FINAL mode=%s wave=%d score=%d embers=%d built=%d smacks=%d kills=%s seen=%s" % [main.net.mode, main.wave, main.score, main.embers, main.built, smacks, main.kills, seen.keys()])
		if main.scenery != null:
			print("Scenery: %d touches, trees pulled up now: %s" % [main.scenery.touches, main.scenery.gone_list()])
		print("Visual instances in the scene: %d" % _count_visuals(main))
		if OS.has_environment("GT_BREAKDOWN"):
			var by := {}
			for ch in main.get_children():
				var key: String = ch.get_script().resource_path.get_file() if ch.get_script() else ch.get_class()
				by[key] = by.get(key, 0) + _count_visuals(ch)
			print("Breakdown: %s" % by)
