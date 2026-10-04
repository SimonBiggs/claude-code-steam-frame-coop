extends RefCounted
## Kaiju brains (host only). Every attack is TELEGRAPHED: a wind-up (the kaiju flashes and a glowing
## danger circle / line appears on the ground for everyone) gives the pilot time to block or dash, and
## the support team time to stun. Behaviour:
## - enter: walk (or fly / swim) into the city.
## - roam: go for whoever annoyed it most (aggro from punches, beams and jet shots: jets DISTRACT the
##   kaiju), otherwise for a building (or the landmark it wants). Bumping into buildings damages them.
## - windup -> attack -> recover, picking an attack its kind knows that fits the distance.
## - stunned (stun meter full) / downed (flyers fall to the ground and can be punched), dizzy when out
##   of health (bosses wait for a finishing punch), then home.
## Special rules (jelly split, crab shell, mega phases, moth knock-down) live in bosses.gd.
## `g` is combat.gd: it owns the world queries and applies the effects.

const Data := preload("res://games/mech_titans/data.gd")
const Bosses := preload("res://games/mech_titans/bosses.gd")

## attack id -> [range m, windup s, recover s, cooldown s]
const ATTACKS := {
	"fire_breath": [24.0, 1.3, 0.9, 6.0], "tail_swipe": [11.5, 1.0, 0.8, 4.0], "stomp": [12.0, 1.1, 0.7, 5.0],
	"lava_bombs": [70.0, 1.6, 1.0, 11.0], "belly_flop": [22.0, 1.2, 1.2, 7.0], "goo_spit": [30.0, 1.0, 0.7, 6.0],
	"pinch": [10.0, 0.9, 0.7, 3.5], "bubble_blast": [30.0, 1.2, 0.8, 7.0], "shell_guard": [99.0, 0.5, 0.5, 14.0],
	"zap_bolt": [45.0, 1.4, 0.8, 5.5], "electric_ring": [15.0, 1.2, 0.8, 7.0], "drain": [22.0, 1.5, 0.5, 9.0],
	"wing_gust": [26.0, 1.2, 0.8, 7.0], "sleepy_dust": [20.0, 1.3, 0.8, 9.0], "swoop": [40.0, 1.0, 1.2, 8.0],
	"ground_pound": [17.0, 1.4, 1.0, 6.0], "rock_throw": [60.0, 1.3, 0.8, 7.0], "eye_laser": [45.0, 1.6, 1.0, 9.0],
	"summon": [99.0, 1.5, 0.8, 22.0], "mega_roar": [99.0, 1.4, 1.0, 16.0], "nibble": [3.0, 0.6, 0.6, 1.6],
	"swat": [16.0, 0.8, 0.6, 3.0],
}


static func think(k: Node3D, delta: float, g: Node) -> void:
	var st: String = k.state
	k.state_t += delta
	for c in k.cooldowns.keys():
		k.cooldowns[c] = maxf(0.0, float(k.cooldowns[c]) - delta)
	for key in k.aggro.keys():
		k.aggro[key] = float(k.aggro[key]) * exp(-0.12 * delta)
	k.slip = maxf(0.0, k.slip - delta)
	k.goo = maxf(0.0, k.goo - delta)
	_altitude(k, delta)
	match st:
		"enter":
			_enter(k, delta, g)
		"roam":
			_roam(k, delta, g)
		"windup":
			_windup(k, delta, g)
		"attack":
			if k.state_t > 0.35:
				k.set_state("recover")
		"recover":
			var rec: Array = ATTACKS.get(k.attack, [0, 0, 0.8, 0])
			if k.state_t > float(rec[2]):
				k.set_state("roam")
		"stunned":
			_walk_anim(k, 0.0)
			if k.state_t > (4.5 if g.call("support_bonus") else 3.5):
				k.stun = 0.0
				k.set_state("roam")
		"downed":
			_walk_anim(k, 0.0)
			if k.state_t > 6.0:
				k.stun = 0.0
				if k.anim != null:
					k.anim.call("revive")
				k.set_state("roam")
		"dizzy":
			_walk_anim(k, 0.0)
			k.dizzy_wait -= delta
			if k.dizzy_wait <= 0.0:
				g.call("send_home", k, false)
		"grabbed":
			pass
		"thrown":
			_thrown(k, delta, g)
		"home":
			_home(k, delta, g)
	k.visual_tick(delta)


# --- Movement helpers ---------------------------------------------------------------------------------

static func _altitude(k: Node3D, delta: float) -> void:
	if k.fly_alt <= 0.0:
		k.high = false
		k.can_punch = k.state != "home"
		return
	var want: float = k.fly_alt
	if k.state == "downed" or k.state == "dizzy" or k.state == "stunned" and k.kind == "moth":
		want = 0.6
	elif k.state == "windup" and k.attack == "swoop":
		want = k.fly_alt + 3.0
	elif k.state == "attack" and k.attack == "swoop":
		want = 2.5
	elif k.state == "home" and k.info.get("home", "") == "fly":
		want = k.fly_alt + k.state_t * 6.0
	elif k.state == "enter" and k.state_t < 3.0:
		want = k.fly_alt + (3.0 - k.state_t) * 8.0
	k.alt = lerpf(k.alt, want, 1.0 - exp(-2.5 * delta))
	k.position.y = k.alt
	k.high = k.alt > 4.5
	k.can_punch = not k.high


static func _walk_anim(k: Node3D, speed: float) -> void:
	if k.anim != null:
		k.anim.call("walk", speed / maxf(k.model.scale.x, 0.01))


## Move towards p at the kaiju's speed; buildings in the way get bumped (and damaged a little).
static func _move_to(k: Node3D, p: Vector3, delta: float, g: Node, speed_mul: float = 1.0) -> float:
	var to := Vector3(p.x - k.position.x, 0, p.z - k.position.z)
	var d := to.length()
	var spd: float = float(k.info["speed"]) * speed_mul * (0.5 if k.goo > 0.0 or k.slip > 0.0 else 1.0)
	if d > 0.1:
		var step := to / d * minf(spd * delta, d)
		var before: Vector3 = k.position
		var want := before + step
		var after: Vector3 = g.call("kaiju_push", k, want)
		k.position = Vector3(after.x, k.position.y, after.z)
		var blocked := (want - after).length()
		if blocked > 0.01 and k.fly_alt <= 0.0:
			g.call("kaiju_bump", k, want, delta)
		k.face_dir(to, delta)
		_walk_anim(k, spd)
	else:
		_walk_anim(k, 0.0)
	return d


# --- States ---------------------------------------------------------------------------------------------

static func _enter(k: Node3D, delta: float, g: Node) -> void:
	var goal: Vector3 = k.attack_pos
	var d := _move_to(k, goal, delta, g, 1.2)
	if d < 4.0 or k.state_t > 16.0:
		k.set_state("roam")


static func _roam(k: Node3D, delta: float, g: Node) -> void:
	# Special per-kind decisions first (shell guard, phase changes, summons).
	if Bosses.special(k, g):
		return
	var tgt: Dictionary = g.call("pick_target", k)
	var pos: Vector3 = tgt.get("pos", k.position)
	var dist := Vector2(pos.x - k.position.x, pos.z - k.position.z).length() - float(tgt.get("size", 0.0))
	var choice := _choose_attack(k, dist, tgt, g)
	if choice != "":
		_begin(k, choice, tgt, g)
		return
	if dist > 2.0:
		var reach: float = float(tgt.get("reach", k.radius + 3.0))
		if dist > reach:
			_move_to(k, pos, delta, g)
		else:
			k.face_dir(pos - k.position, delta)
			_walk_anim(k, 0.0)
	else:
		_walk_anim(k, 0.0)


static func _choose_attack(k: Node3D, dist: float, tgt: Dictionary, g: Node) -> String:
	var list: Array = k.info.get("attacks", ["nibble"]) if not k.is_mini else ["nibble"]
	if k.is_mini and k.fly_alt > 0.0:
		list = ["nibble"]
	var what: String = tgt.get("what", "building")
	if what == "air":
		# A jet / drone is pestering it: swat at it if close, else use a ranged attack.
		if dist < 16.0 and float(k.cooldowns.get("swat", 0.0)) <= 0.0 and not k.is_mini:
			return "swat"
	var options: Array[String] = []
	for a in list:
		var id: String = a
		if not ATTACKS.has(id) or float(k.cooldowns.get(id, 0.0)) > 0.0:
			continue
		if not Bosses.attack_allowed(k, id, g):
			continue
		var rng: float = ATTACKS[id][0]
		if dist <= rng:
			options.append(id)
	if options.is_empty():
		return ""
	# Prefer close-range attacks when close; a little randomness keeps it lively.
	return options[randi() % options.size()]


static func _begin(k: Node3D, id: String, tgt: Dictionary, g: Node) -> void:
	k.attack = id
	k.attack_pos = tgt.get("pos", k.position)
	k.attack_target = tgt.get("node", null)
	var to: Vector3 = k.attack_pos - k.position
	to.y = 0.0
	k.attack_dir = to.normalized() if to.length() > 0.1 else Vector3(sin(k.yaw), 0, cos(k.yaw))
	k.cooldowns[id] = float(ATTACKS[id][3])
	k.set_state("windup")
	g.call("telegraph", k, id)
	if k.anim != null:
		k.anim.call("play", "cast", float(ATTACKS[id][1]))


static func _windup(k: Node3D, delta: float, g: Node) -> void:
	var w: float = ATTACKS.get(k.attack, [0, 1.0])[1]
	k.face_dir(k.attack_dir, delta, 5.0)
	_walk_anim(k, 0.0)
	# Track moving targets during the first part of the wind-up (then it's committed: dodgeable).
	if k.attack_target != null and is_instance_valid(k.attack_target) and k.state_t < w * 0.4:
		var tp: Vector3 = k.attack_target.global_position
		if k.attack != "lava_bombs" and k.attack != "zap_bolt":
			k.attack_pos = tp
			var to := tp - k.position
			to.y = 0.0
			if to.length() > 0.1:
				k.attack_dir = to.normalized()
	if k.state_t >= w:
		k.set_state("attack")
		if k.anim != null:
			k.anim.call("play", "attack", 0.5, k.attack_dir)
		g.call("do_attack", k, k.attack)


static func _thrown(k: Node3D, delta: float, g: Node) -> void:
	k.velocity.y -= 22.0 * delta
	k.position += k.velocity * delta
	k.rotation.x += delta * 6.0
	if k.position.y <= 0.0 and k.velocity.y < 0.0:
		k.position.y = 0.0
		k.rotation.x = 0.0
		k.velocity = Vector3.ZERO
		g.call("kaiju_landed", k)


static func _home(k: Node3D, delta: float, g: Node) -> void:
	var how: String = k.info.get("home", "walk")
	var d: Vector3 = k.home_dir
	var spd := float(k.info["speed"]) * (1.6 if k.is_mini else 1.3)
	if how == "space":
		k.position.y += delta * (4.0 + k.state_t * 6.0)
		k.rotation.y += delta * 2.0
	else:
		k.position += d * spd * delta
		k.face_dir(d, delta)
	_walk_anim(k, spd)
	if k.anim != null and int(k.state_t * 2.0) % 6 == 0 and not bool(k.anim.call("is_busy")):
		k.anim.call("play", "wave", 1.0)
	var far := maxf(absf(k.position.x), absf(k.position.z)) > Data.MAP + 30.0 or k.position.y > 80.0 or k.state_t > 22.0
	if far:
		k.set_state("gone")
		k.visible = false
	elif how == "swim" and g.call("in_water", k.position):
		k.position.y = lerpf(k.position.y, -k.height * 0.6, 1.0 - exp(-0.8 * delta))
