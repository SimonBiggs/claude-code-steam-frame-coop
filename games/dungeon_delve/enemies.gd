extends Node3D
## DUNGEON DELVE monsters. The host simulates them (AI, attacks, damage, defeat); the TV machine
## mirrors them from three quantised ints per monster in each snapshot (position, yaw, height, HP %,
## state flags), so late joiners see everything and bandwidth stays tiny.
## AI kinds (data.gd ENEMIES.ai): melee (walk up, wind up, swipe), hopper (bouncy hops), ranged (keep
## their distance and shoot slow, blockable shots), flyer (wobbly swoops), charger (telegraphed dash,
## then dizzy), tank (slow, ground slam), mimic (chomp lunges). Every attack is telegraphed (the monster
## flashes and squashes first) and at most 3 monsters attack the same hero at once (kid-friendly).
## Defeated monsters poof into sparkles and coins. Bosses run their patterns from bosses.gd.

const Data := preload("res://games/dungeon_delve/data.gd")
const Creatures := preload("res://core/creatures.gd")
const HudKit := preload("res://core/hud_kit.gd")
const Bosses := preload("res://games/dungeon_delve/bosses.gd")

const MAX_ALIVE := 18
const POS_OFFSET := 300.0
const POS_SCALE := 50.0  # 2 cm steps

## State codes (snapshot): what the TV machine shows.
const S_IDLE := 0
const S_WALK := 1
const S_WINDUP := 2
const S_ATTACK := 3
const S_STUN := 4
const S_SPAWN := 5
const S_SLEEP := 6

const F_ELITE := 1
const F_FROZEN := 2
const F_ASLEEP := 4
const F_BOSS := 8
const F_STUN := 16
const F_WINDUP := 32
const F_KEY := 64


class Mon extends RefCounted:
	var id := 0
	var eid := ""
	var def: Dictionary = {}
	var node: Node3D
	var anim: Node
	var bar: Node3D
	var pos := Vector3.ZERO
	var yaw := 0.0
	var y := 0.0
	var hp := 10.0
	var max_hp := 10.0
	var dmg := 5.0
	var speed := 2.0
	var r := 0.4
	var height := 1.0
	var ai := "melee"
	var state := "spawn"
	var st := 0.0
	var target := -1
	var path := PackedVector3Array()
	var path_t := 0.0
	var kb := Vector3.ZERO
	var hitstop := 0.0
	var slow := 0.0
	var burn := 0.0
	var burn_by := -1
	var frozen := 0.0
	var asleep := 0.0
	var room := -1
	var elite := false
	var boss := false
	var key := false
	var aim := Vector3.FORWARD
	var phase := 0.0
	var hurt_t := 0.0
	var dead := false
	var contact_t := {}
	var bs: Dictionary = {}  # boss pattern state
	# TV machine: interpolation targets
	var tpos := Vector3.ZERO
	var tyaw := 0.0
	var ty := 0.0
	var code := 0
	var flags := 0
	var last_pos := Vector3.ZERO


var main: Node
var mons := {}  # id -> Mon
var next_id := 1
var kinds: Array[String] = []
var boss: Mon
var lod_distance := 14.0
var _sep_t := 0.0


func _ready() -> void:
	kinds = Data.enemy_ids()


func alive_count() -> int:
	var n := 0
	for id in mons:
		if not (mons[id] as Mon).dead:
			n += 1
	return n


func clear() -> void:
	for id in mons:
		var m: Mon = mons[id]
		if is_instance_valid(m.node):
			m.node.queue_free()
	mons.clear()
	boss = null


# =================================================================================================
# Spawning
# =================================================================================================

## Host / local: a monster appears (with a poof). eid: data.gd ENEMIES / BOSSES id.
func spawn(eid: String, pos: Vector3, room: int, opts: Dictionary = {}) -> Mon:
	var is_boss := Data.BOSSES.has(eid)
	var def: Dictionary = Data.BOSSES[eid] if is_boss else Data.ENEMIES[eid]
	var m := Mon.new()
	m.id = next_id
	next_id += 1
	m.eid = eid
	m.def = def
	m.pos = Vector3(pos.x, 0.0, pos.z)
	m.room = room
	m.boss = is_boss
	m.elite = bool(opts.get("elite", false))
	m.key = eid == "key_goblin"
	m.ai = "boss" if is_boss else String(def["ai"])
	var sc: Dictionary = main.enemy_scale()
	var hp_mult: float = float(sc["hp"]) * (1.8 if m.elite else 1.0)
	var dmg_mult: float = float(sc["dmg"]) * (1.25 if m.elite else 1.0)
	if is_boss:
		hp_mult = float(sc["boss_hp"])
	m.max_hp = float(def["hp"]) * hp_mult
	m.hp = m.max_hp
	m.dmg = float(def["dmg"]) * dmg_mult
	m.speed = float(def["speed"]) * (1.1 if m.elite else 1.0)
	m.r = float(def["r"]) * (1.2 if m.elite else 1.0)
	m.state = "spawn"
	m.st = 0.8 if not is_boss else 0.1
	m.yaw = randf() * TAU
	m.phase = randf() * TAU
	_make_visual(m)
	mons[m.id] = m
	if is_boss:
		boss = m
		Bosses.start(m, self)
	else:
		main.fx_event("spawn_poof", [m.pos, _color_of(m)])
	return m


func _color_of(m: Mon) -> Color:
	if m.def.has("color"):
		return m.def["color"]
	return Color(0.95, 0.9, 0.8)


func _make_visual(m: Mon) -> void:
	var def := m.def
	var opts := {"lod": "auto", "lod_distance": lod_distance, "seed": m.id}
	if def.has("color"):
		opts["color"] = def["color"]
	if def.has("color2"):
		opts["color2"] = def["color2"]
	if def.has("weapon"):
		opts["weapon"] = def["weapon"]
	var sc := float(def.get("scale", 1.0)) * (1.25 if m.elite else 1.0)
	opts["scale"] = sc
	if m.boss:
		opts["boss"] = true
		opts["lod"] = "near"
	var node := Creatures.monster(String(def["kind"]), opts)
	node.name = "Mon%d" % m.id
	add_child(node)
	node.position = m.pos
	node.rotation.y = m.yaw
	m.node = node
	m.anim = Creatures.anim(node)
	m.height = Creatures.height_of(node)
	if m.anim != null and String(def["kind"]) == "bat" or String(def["kind"]) == "ghost":
		if m.anim != null:
			m.anim.set("flying", String(def["kind"]) == "bat")
	if m.elite and not m.boss:
		var halo := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.35
		tm.outer_radius = 0.45
		tm.rings = 16
		tm.ring_segments = 4
		halo.mesh = tm
		halo.material_override = preload("res://core/mesh_kit.gd").material(Color(1.0, 0.8, 0.3), 3.0)
		halo.position = Vector3(0, m.height + 0.25, 0)
		halo.scale = Vector3(1, 0.3, 1)
		node.add_child(halo)
	if m.key:
		var k := preload("res://games/dungeon_delve/loot.gd").key_mesh_instance()
		k.position = Vector3(0, m.height + 0.45, 0)
		k.name = "Key"
		node.add_child(k)
	if not m.boss:
		m.bar = HudKit.bar3d(node, {"max": 1.0, "value": 1.0, "hide_full": true, "width": 0.7, "height": 0.09,
			"offset": Vector3(0, m.height + 0.3, 0)})
	if m.state == "spawn" and not m.boss:
		node.scale = Vector3.ONE * 0.2
		var tw := node.create_tween()
		tw.tween_property(node, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# =================================================================================================
# Host simulation
# =================================================================================================

func _process(delta: float) -> void:
	if main == null or not main.ready_to_play or main.layout == null:
		return
	if main.net.mode == "client":
		_mirror(delta)
		return
	var targets: Array = main.player_targets()
	var attackers := {}
	for id in mons:
		var m: Mon = mons[id]
		if m.state == "windup" or m.state == "attack":
			attackers[m.target] = int(attackers.get(m.target, 0)) + 1
	for id in mons.keys():
		var m: Mon = mons[id]
		if m.dead:
			continue
		_tick_status(m, delta)
		if m.dead:
			continue
		if m.hitstop > 0.0:
			m.hitstop -= delta
			if m.anim != null:
				m.anim.set("rate", 0.0)
			continue
		if m.anim != null:
			m.anim.set("rate", 0.4 if m.slow > 0.0 else 1.0)
		if m.boss:
			Bosses.update(m, self, delta, targets)
		else:
			_think(m, delta, targets, attackers)
		# knockback
		if m.kb.length() > 0.05:
			m.pos = main.layout.move(m.pos, m.kb * delta, minf(m.r, 0.7))
			m.kb *= exp(-7.0 * delta)
		_place(m, delta)
	_separate(delta)


func _tick_status(m: Mon, delta: float) -> void:
	m.hurt_t = maxf(0.0, m.hurt_t - delta)
	if m.slow > 0.0:
		m.slow -= delta
	if m.frozen > 0.0:
		m.frozen -= delta
	if m.asleep > 0.0:
		m.asleep -= delta
	if m.burn > 0.0:
		var before := m.burn
		m.burn -= delta
		if int(before * 2.0) != int(m.burn * 2.0):
			damage(m.id, 3.0 + m.max_hp * 0.02, m.burn_by, Vector3.ZERO, {"silent_kb": true, "burn": true})


func _think(m: Mon, delta: float, targets: Array, attackers: Dictionary) -> void:
	m.st -= delta
	var spd := m.speed * (0.45 if m.slow > 0.0 else 1.0)
	if m.frozen > 0.0 or m.asleep > 0.0:
		if m.anim != null:
			m.anim.call("walk", 0.0)
		return
	var tgt := _pick_target(m, targets)
	var tpos := m.pos
	var dist := 999.0
	if tgt.size() > 0:
		m.target = int(tgt[0])
		tpos = tgt[1]
		dist = Vector2(tpos.x - m.pos.x, tpos.z - m.pos.z).length()
	else:
		m.target = -1
	var to := Vector3(tpos.x - m.pos.x, 0.0, tpos.z - m.pos.z)
	var dir := to.normalized() if to.length() > 0.01 else Vector3.FORWARD
	match m.state:
		"spawn":
			if m.st <= 0.0:
				_set_state(m, "chase", 0.0)
		"recover", "stun":
			if m.anim != null:
				m.anim.call("walk", 0.0)
			if m.st <= 0.0:
				_set_state(m, "chase", 0.0)
		"chase":
			if m.target < 0:
				if m.anim != null:
					m.anim.call("walk", 0.0)
				return
			var reach := m.r + 0.75 + (0.4 if m.ai == "tank" else 0.0)
			var busy := int(attackers.get(m.target, 0)) >= 3
			match m.ai:
				"ranged":
					var los: bool = main.layout.los(m.pos, tpos)
					if dist < 3.6:
						_walk(m, -dir, spd * 0.8, delta)
					elif dist < 8.5 and los and m.st <= 0.0:
						m.aim = dir
						_set_state(m, "windup", 0.7)
						main.fx_event("eflash", [m.id, 0])
					else:
						_go(m, tpos, spd, delta)
				"charger":
					var los2: bool = main.layout.los(m.pos, tpos)
					if dist < 8.0 and dist > 2.2 and los2 and m.st <= 0.0 and not busy:
						m.aim = dir
						_set_state(m, "windup", 0.85)
						main.fx_event("tele", ["line", m.pos + dir * 3.5, 7.0, 0.85, dir, 0.0, 1.4])
					elif dist <= reach and not busy and m.st <= 0.0:
						m.aim = dir
						_set_state(m, "windup", 0.55)
						main.fx_event("eflash", [m.id, 0])
					else:
						_go(m, tpos, spd, delta)
				"flyer":
					var side := Vector3(-dir.z, 0.0, dir.x) * sin(m.phase + Time.get_ticks_msec() * 0.003) * 0.9
					if dist <= reach + 0.3 and not busy and m.st <= 0.0:
						m.aim = dir
						_set_state(m, "windup", 0.45)
						main.fx_event("eflash", [m.id, 0])
					else:
						_go(m, tpos + side * 2.0, spd, delta)
				_:
					if dist <= reach:
						if busy:
							# wait your turn: circle round the hero
							var orbit := Vector3(-dir.z, 0.0, dir.x)
							_walk(m, orbit * (1.0 if m.id % 2 == 0 else -1.0) - dir * 0.3, spd * 0.5, delta)
						elif m.st <= 0.0:
							m.aim = dir
							_set_state(m, "windup", 0.75 if m.ai == "tank" else 0.55)
							main.fx_event("eflash", [m.id, 0])
							if m.ai == "tank":
								main.fx_event("tele", ["circle", m.pos + dir * 0.9, 1.9, 0.75, dir, 0.0, 0.0])
						else:
							_walk(m, dir, spd * 0.2, delta)
					else:
						_go(m, tpos, spd * (1.25 if m.ai == "hopper" else 1.0), delta)
		"windup":
			if m.anim != null:
				m.anim.call("walk", 0.0)
				m.anim.call("face", m.aim)
			if m.ai == "ranged" and m.target >= 0:
				m.aim = dir  # keep aiming at the hero while winding up
			if m.st <= 0.0:
				_attack(m, targets)
		"charge":
			var before := m.pos
			m.pos = main.layout.move(m.pos, m.aim * 9.0 * delta, m.r)
			if m.anim != null:
				m.anim.call("walk", 9.0)
			for t in targets:
				var ta: Array = t
				var tp: Vector3 = ta[1]
				var slot := int(ta[0])
				if Vector2(tp.x - m.pos.x, tp.z - m.pos.z).length() < m.r + 0.45 and not m.contact_t.has(slot):
					m.contact_t[slot] = true
					var res: String = main.hurt_player(slot, m.dmg, m.pos, "melee", m.id)
					if res == "blocked":
						_stun(m, 1.4)
						return
			if m.st <= 0.0 or before.distance_to(m.pos) < 9.0 * delta * 0.3:
				_stun(m, 1.1)
				main.fx_event("stars", [m.id])


func _pick_target(m: Mon, targets: Array) -> Array:
	var best: Array = []
	var bd := 1e9
	var aggro := 16.0 if m.room < 0 or main.room_active(m.room) else 7.0
	for t in targets:
		var ta: Array = t
		var p: Vector3 = ta[1]
		var d := Vector2(p.x - m.pos.x, p.z - m.pos.z).length()
		if int(ta[0]) == m.target:
			d -= 2.0  # stick with the current target
		if d < bd and d < aggro + 2.0:
			bd = d
			best = ta
	return best


func _set_state(m: Mon, s: String, t: float) -> void:
	m.state = s
	m.st = t
	if s == "chase":
		m.contact_t.clear()


func _stun(m: Mon, t: float) -> void:
	_set_state(m, "stun", t)
	m.kb = Vector3.ZERO


## Head towards p: straight if we can see it, else follow an A* path (refreshed now and then).
func _go(m: Mon, p: Vector3, spd: float, delta: float) -> void:
	var lay = main.layout
	var to := Vector3(p.x - m.pos.x, 0.0, p.z - m.pos.z)
	if to.length() < 0.05:
		return
	if lay.los(m.pos, p):
		m.path = PackedVector3Array()
		_walk(m, to.normalized(), spd, delta)
		return
	m.path_t -= delta
	if m.path.is_empty() or m.path_t <= 0.0:
		m.path_t = 0.6 + randf() * 0.3
		m.path = lay.path(m.pos, p)
		if m.path.size() > 0:
			m.path.remove_at(0)
	while m.path.size() > 0 and Vector2(m.path[0].x - m.pos.x, m.path[0].z - m.pos.z).length() < 0.5:
		m.path.remove_at(0)
	if m.path.is_empty():
		_walk(m, to.normalized(), spd, delta)
		return
	var nxt: Vector3 = m.path[0]
	var d := Vector3(nxt.x - m.pos.x, 0.0, nxt.z - m.pos.z)
	_walk(m, d.normalized(), spd, delta)


func _walk(m: Mon, dir: Vector3, spd: float, delta: float) -> void:
	var v := dir * spd
	if m.ai == "hopper":
		# move only while in the air: bouncy hops
		var hop := fposmod(m.phase + Time.get_ticks_msec() * 0.0045, PI)
		var air := sin(hop)
		v *= 0.25 + 1.5 * air
		m.y = air * 0.45
	m.pos = main.layout.move(m.pos, v * delta, minf(m.r, 0.7))
	if m.anim != null:
		m.anim.call("walk", spd)
		if dir.length() > 0.01:
			m.anim.call("face", dir)


func _attack(m: Mon, targets: Array) -> void:
	main.fx_event("eatk", [m.id])
	match m.ai:
		"ranged":
			var proj := String(m.def.get("proj", "orb"))
			var from := m.pos + Vector3.UP * 1.05 + m.aim * (m.r + 0.2)
			main.projectiles.spawn(proj, from, m.aim, 6.5 if proj != "arrow_e" else 8.5, "enemy", m.id, m.dmg)
			if m.elite:
				for a in [-0.35, 0.35]:
					main.projectiles.spawn(proj, from, m.aim.rotated(Vector3.UP, float(a)), 6.0, "enemy", m.id, m.dmg)
			main.sound_at("bow" if proj == "arrow_e" else "magic", m.pos, -6.0)
			_set_state(m, "recover", 1.4 + randf() * 0.8)
		"charger":
			if m.st <= 0.0 and m.state == "windup" and Vector2(m.aim.x, m.aim.z).length() > 0.5:
				pass
			# a long windup means a charge; a short one a bite
			_set_state(m, "charge", 0.85)
			m.contact_t.clear()
			main.sound_at("whoosh", m.pos, -4.0)
		"tank":
			var c := m.pos + m.aim * 0.9
			for t in targets:
				var ta: Array = t
				var tp: Vector3 = ta[1]
				if Vector2(tp.x - c.x, tp.z - c.z).length() < 1.9:
					main.hurt_player(int(ta[0]), m.dmg, m.pos, "slam", m.id)
			main.fx_event("ring", [c, 2.0, Color(0.9, 0.75, 0.5)])
			main.shake(0.25)
			main.sound_at("explosion", c, -10.0)
			_set_state(m, "recover", 1.0)
		_:
			var reach := m.r + 1.0
			var blocked := false
			for t in targets:
				var ta: Array = t
				var tp: Vector3 = ta[1]
				var to := Vector3(tp.x - m.pos.x, 0.0, tp.z - m.pos.z)
				if to.length() < reach and (to.length() < 0.5 or to.normalized().dot(m.aim) > 0.2):
					var res: String = main.hurt_player(int(ta[0]), m.dmg, m.pos, "melee", m.id)
					if res == "blocked":
						blocked = true
			if m.ai == "mimic" or m.ai == "flyer":
				m.kb = m.aim * 5.0
			if blocked:
				_stun(m, 1.2)
				m.kb = -m.aim * 4.0
			else:
				_set_state(m, "recover", 0.8 + randf() * 0.5)
			main.sound_at("swish", m.pos, -8.0)
	if m.anim != null:
		m.anim.call("play", "attack", -1.0, m.aim)


func _place(m: Mon, delta: float) -> void:
	if not is_instance_valid(m.node):
		return
	var fly := 0.0
	if String(m.def["kind"]) == "bat":
		fly = 1.0 + 0.15 * sin(m.phase + Time.get_ticks_msec() * 0.005)
	elif String(m.def["kind"]) == "ghost":
		fly = 0.25 + 0.12 * sin(m.phase + Time.get_ticks_msec() * 0.003)
	if m.ai != "hopper" or m.state != "chase":
		m.y = lerpf(m.y, 0.0, 1.0 - exp(-10.0 * delta))
	if not m.boss or not m.bs.has("air"):
		m.node.position = Vector3(m.pos.x, m.y + fly, m.pos.z)
	m.yaw = m.node.rotation.y


## Keep monsters from stacking on top of each other.
func _separate(delta: float) -> void:
	var arr: Array = []
	for id in mons:
		var m: Mon = mons[id]
		if not m.dead:
			arr.append(m)
	for i in arr.size():
		var a: Mon = arr[i]
		for j in range(i + 1, arr.size()):
			var b: Mon = arr[j]
			var d := Vector2(b.pos.x - a.pos.x, b.pos.z - a.pos.z)
			var need := (a.r + b.r) * 0.9
			var l := d.length()
			if l < need and l > 0.0001:
				var push := d / l * (need - l) * 0.5 * minf(1.0, delta * 12.0)
				var pv := Vector3(push.x, 0.0, push.y)
				if not a.boss:
					a.pos = main.layout.move(a.pos, -pv, minf(a.r, 0.7))
				if not b.boss:
					b.pos = main.layout.move(b.pos, pv, minf(b.r, 0.7))


# =================================================================================================
# Damage
# =================================================================================================

## Host: hurt monster `id`. opts: crit, effects (weapon affixes), ranged, silent_kb, burn, kb (force),
## stun (s), hitstop (s). Returns the damage dealt (0 if it couldn't be hurt).
func damage(id: int, amount: float, slot: int, dir: Vector3, opts: Dictionary = {}) -> float:
	var m: Mon = mons.get(id, null)
	if m == null or m.dead or m.state == "spawn":
		return 0.0
	if m.boss and m.bs.get("invuln", false):
		main.fx_event("miss", [m.pos + Vector3.UP * m.height])
		return 0.0
	var dmg := amount
	var crit := bool(opts.get("crit", false))
	if m.asleep > 0.0:
		dmg *= 1.5
		m.asleep = 0.0
	if m.frozen > 0.0:
		dmg *= 1.25
	m.hp -= dmg
	m.hurt_t = 0.3
	if slot >= 0:
		m.target = slot if slot < 10 else m.target
	if not bool(opts.get("silent_kb", false)):
		var force := float(opts.get("kb", 2.5 if not crit else 4.0))
		if m.boss:
			force *= 0.1
		elif m.ai == "tank":
			force *= 0.4
		m.kb += Vector3(dir.x, 0.0, dir.z).normalized() * force if dir.length() > 0.01 else Vector3.ZERO
		m.hitstop = float(opts.get("hitstop", 0.07 if crit else 0.045))
	if opts.has("stun") and not m.boss:
		_stun(m, float(opts["stun"]))
	for e in opts.get("effects", []):
		match String(e):
			"frost":
				m.slow = 2.5
			"ember":
				m.burn = 3.0
				m.burn_by = slot
	if m.bar != null and is_instance_valid(m.bar):
		m.bar.call("set_value", m.hp / m.max_hp)
	main.on_enemy_hurt(m, dmg, slot, crit, opts)
	if m.hp <= 0.0:
		_defeat(m, slot)
	return dmg


func _defeat(m: Mon, slot: int) -> void:
	m.dead = true
	mons.erase(m.id)
	if m.boss:
		boss = null
	main.on_enemy_defeated(m, slot)
	if is_instance_valid(m.node):
		var n := m.node
		var tw := n.create_tween()
		tw.tween_property(n, "scale", Vector3(1.3, 0.2, 1.3), 0.12)
		tw.tween_callback(n.queue_free)


## Host: freeze (frost nova), sleep (lullaby) or stun every monster within radius of p.
func status_area(p: Vector3, radius: float, kind: String, t: float) -> int:
	var n := 0
	for id in in_radius(p, radius):
		var m: Mon = mons[id]
		match kind:
			"freeze":
				m.frozen = t * (0.4 if m.boss else 1.0)
				m.slow = t + 1.5
			"sleep":
				if not m.boss:
					m.asleep = t
			"stun":
				if not m.boss:
					_stun(m, t)
		n += 1
	return n


# =================================================================================================
# Queries
# =================================================================================================

## Monster ids whose body touches a circle at p (xz) of radius r, minus `exclude` (a Dictionary).
func query(p: Vector3, r: float, exclude: Dictionary = {}) -> Array:
	var out: Array = []
	for id in mons:
		var m: Mon = mons[id]
		if m.dead or m.state == "spawn" or exclude.has(id):
			continue
		if Vector2(m.pos.x - p.x, m.pos.z - p.z).length() < r + m.r:
			out.append(id)
	return out


func in_radius(p: Vector3, r: float) -> Array:
	return query(p, r)


## Monsters in a cone in front of `origin` (melee swings).
func in_arc(origin: Vector3, dir: Vector3, reach: float, arc_deg: float) -> Array:
	var out: Array = []
	var d := Vector3(dir.x, 0.0, dir.z).normalized()
	var cos_half := cos(deg_to_rad(arc_deg) * 0.5)
	for id in mons:
		var m: Mon = mons[id]
		if m.dead or m.state == "spawn":
			continue
		var to := Vector3(m.pos.x - origin.x, 0.0, m.pos.z - origin.z)
		var l := to.length()
		if l > reach + m.r:
			continue
		if l < m.r + 0.3 or to.normalized().dot(d) >= cos_half:
			out.append(id)
	return out


## Monsters touched by a 3D segment (the VR sword blade) within `radius`.
func on_segment(a: Vector3, b: Vector3, radius: float) -> Array:
	var out: Array = []
	for id in mons:
		var m: Mon = mons[id]
		if m.dead or m.state == "spawn":
			continue
		var base := m.node.global_position if is_instance_valid(m.node) else m.pos
		var top := base + Vector3.UP * maxf(0.5, m.height)
		var pts := Geometry3D.get_closest_points_between_segments(a, b, base + Vector3.UP * 0.1, top)
		var p0: Vector3 = pts[0]
		var p1: Vector3 = pts[1]
		if p0.distance_to(p1) < radius + m.r * 0.9:
			out.append(id)
	return out


func get_mon(id: int) -> Mon:
	return mons.get(id, null)


## The monster's chest point (for popups and sparks).
func center_of(id: int) -> Vector3:
	var m: Mon = mons.get(id, null)
	if m == null:
		return Vector3.ZERO
	var base := m.node.global_position if is_instance_valid(m.node) else m.pos
	return base + Vector3.UP * m.height * 0.6


# =================================================================================================
# Replication
# =================================================================================================

## Host: 3 ints per monster.
func pack() -> PackedInt32Array:
	var out := PackedInt32Array()
	for id in mons:
		var m: Mon = mons[id]
		if m.dead:
			continue
		var code := S_WALK
		match m.state:
			"spawn":
				code = S_SPAWN
			"windup":
				code = S_WINDUP
			"attack", "charge":
				code = S_ATTACK
			"stun":
				code = S_STUN
			"recover":
				code = S_IDLE
		var flags := 0
		if m.elite:
			flags |= F_ELITE
		if m.frozen > 0.0:
			flags |= F_FROZEN
		if m.asleep > 0.0:
			flags |= F_ASLEEP
			code = S_SLEEP
		if m.boss:
			flags |= F_BOSS
		if m.state == "stun":
			flags |= F_STUN
		if m.state == "windup":
			flags |= F_WINDUP
		if m.key:
			flags |= F_KEY
		var kind_i := kinds.find(m.eid)
		var np: Vector3 = m.node.position if is_instance_valid(m.node) else m.pos
		var qx := clampi(int((np.x + POS_OFFSET) * POS_SCALE), 0, 0xFFFF)
		var qz := clampi(int((np.z + POS_OFFSET) * POS_SCALE), 0, 0xFFFF)
		var qyaw := int(fposmod(m.node.rotation.y if is_instance_valid(m.node) else m.yaw, TAU) / TAU * 255.0) & 0xFF
		var hp := clampi(int(ceil(m.hp / m.max_hp * 100.0)), 0, 100)
		var qy := clampi(int(np.y * 20.0), 0, 127)
		out.append((m.id & 0xFFFF) | ((kind_i & 0xFF) << 16) | ((code & 0x7F) << 24))
		out.append(qx | (qz << 16))
		out.append(qyaw | (hp << 8) | ((flags & 0xFF) << 16) | (qy << 24))
	return out


## TV machine: mirror the host's monsters.
func unpack(a: PackedInt32Array) -> void:
	var seen := {}
	var i := 0
	while i + 2 < a.size():
		var w0 := a[i]
		var w1 := a[i + 1]
		var w2 := a[i + 2]
		i += 3
		var id := w0 & 0xFFFF
		var kind_i := (w0 >> 16) & 0xFF
		var code := (w0 >> 24) & 0x7F
		var x := float(w1 & 0xFFFF) / POS_SCALE - POS_OFFSET
		var z := float((w1 >> 16) & 0xFFFF) / POS_SCALE - POS_OFFSET
		var yaw := float(w2 & 0xFF) / 255.0 * TAU
		var hp := (w2 >> 8) & 0xFF
		var flags := (w2 >> 16) & 0xFF
		var y := float((w2 >> 24) & 0x7F) / 20.0
		seen[id] = true
		var m: Mon = mons.get(id, null)
		if m == null:
			if kind_i < 0 or kind_i >= kinds.size():
				continue
			var eid := kinds[kind_i]
			m = Mon.new()
			m.id = id
			m.eid = eid
			m.boss = Data.BOSSES.has(eid)
			m.def = Data.BOSSES[eid] if m.boss else Data.ENEMIES[eid]
			m.elite = (flags & F_ELITE) != 0
			m.key = (flags & F_KEY) != 0
			m.state = "spawn" if code == S_SPAWN else "chase"
			m.pos = Vector3(x, 0, z)
			m.yaw = yaw
			_make_visual(m)
			m.node.position = Vector3(x, y, z)
			m.last_pos = m.node.position
			mons[id] = m
			if m.boss:
				boss = m
		m.tpos = Vector3(x, y, z)
		m.tyaw = yaw
		var prev_code := m.code
		m.code = code
		m.flags = flags
		var new_hp := float(hp) / 100.0
		if m.bar != null and is_instance_valid(m.bar) and absf(new_hp - m.hp) > 0.001:
			m.bar.call("set_value", new_hp)
		m.hp = new_hp
		if code == S_WINDUP and prev_code != S_WINDUP and m.anim != null:
			m.anim.call("flash", Color(1.0, 0.9, 0.6), 0.35)
			m.anim.call("squash", 0.25)
	for id in mons.keys():
		if not seen.has(id):
			var m: Mon = mons[id]
			mons.erase(id)
			if m == boss:
				boss = null
			if is_instance_valid(m.node):
				m.node.queue_free()


func _mirror(delta: float) -> void:
	var k := 1.0 - exp(-14.0 * delta)
	for id in mons:
		var m: Mon = mons[id]
		if not is_instance_valid(m.node):
			continue
		var n := m.node
		n.position = n.position.lerp(m.tpos, k)
		n.rotation.y = lerp_angle(n.rotation.y, m.tyaw, k)
		var v := Vector2(n.position.x - m.last_pos.x, n.position.z - m.last_pos.z).length() / maxf(delta, 0.001)
		m.last_pos = n.position
		m.pos = Vector3(n.position.x, 0.0, n.position.z)
		if m.anim != null:
			m.anim.call("walk", v if v > 0.3 else 0.0)
			m.anim.set("rate", 0.0 if (m.flags & (F_FROZEN | F_ASLEEP)) != 0 else 1.0)


## TV machine: show a hit on a mirrored monster (flash, knock-back squash).
func show_hit(id: int, dir: Vector3) -> void:
	var m: Mon = mons.get(id, null)
	if m == null or m.anim == null:
		return
	m.anim.call("hurt", Color(1, 1, 1), dir)


## Both machines: the monster attacks (animation).
func show_attack(id: int) -> void:
	var m: Mon = mons.get(id, null)
	if m != null and m.anim != null and main.net.mode == "client":
		m.anim.call("play", "attack")


## Both: windup flash.
func show_flash(id: int) -> void:
	var m: Mon = mons.get(id, null)
	if m != null and m.anim != null:
		m.anim.call("flash", Color(1.0, 0.9, 0.6), 0.35)
		m.anim.call("squash", 0.25)


## Both: a defeated monster disappears (TV machine; the host already removed it).
func remove_now(id: int) -> void:
	var m: Mon = mons.get(id, null)
	if m == null:
		return
	mons.erase(id)
	if m == boss:
		boss = null
	if is_instance_valid(m.node):
		var n := m.node
		var tw := n.create_tween()
		tw.tween_property(n, "scale", Vector3(1.3, 0.2, 1.3), 0.12)
		tw.tween_callback(n.queue_free)
