extends Node
## Headless bot for Giant's Table. Drives whichever players are local on this machine:
## the flat giant grabs goblins/ogres and throws them off the table, drops boulders on armoured
## goblins and carries downed knights to the campfire; the knights chase goblins with sword and
## crossbow and fetch dropped embers. Prints progress every 10 s.

const W := preload("res://games/giants_table/world.gd")

var main
var t := 0.0
var grabs := 0
var giant_mode := "pick"
var giant_target = null
var giant_wait := 0.0
var last_print := -100.0
var lazy := OS.has_environment("BOT_LAZY_GIANT")  # giant only rescues knights: tests downs and revives


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


func _drive_knight(k) -> void:
	var inp := {"move": Vector3.ZERO, "sword": false, "bow": false, "jump": false}
	if not k.active:
		inp.sword = int(t * 2.0) % 2 == 0  # player 3 presses attack to join
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
					if g.kind == "ogre" or g.held or g.flying:
						continue
					var d: float = g.global_position.distance_to(pos) + Vector2(g.global_position.x, g.global_position.z).length() * 0.3
					if d < best:
						best = d
						target = g
						target_pos = g.global_position
	var to := target_pos - pos
	to.y = 0.0
	var dist := to.length()
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
		target = _nearest_goblin(Vector3.ZERO, ["ogre"])
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


func _nearest_goblin(from: Vector3, kinds: Array):
	var best = null
	var bd := INF
	for g in get_tree().get_nodes_in_group("goblins"):
		if g.held or g.flying or not (g.kind in kinds) or g.has_meta("dead"):
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
func _drive_vr_giant(delta: float) -> void:
	var g = main.giant
	g.bot = true
	var ctrl: Node3D = g.hand_r
	var h = g.hands[1]
	if main.game_over:
		g.bot_grip = false
		return
	var grab_off: Vector3 = ctrl.global_basis * g.GRAB_OFFSET
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
		vr_target = _nearest_goblin(Vector3.ZERO, ["goblin", "ogre"])
		g.bot_grip = false
		if vr_target == null:
			return
	var c: Vector3 = vr_target.grab_center()
	ctrl.global_position = ctrl.global_position.move_toward(c - grab_off, 30.0 * delta)
	if h.pos.distance_to(c) < 0.6:
		g.bot_grip = true
		grabs += 1
