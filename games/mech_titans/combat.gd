extends Node
## MECH TITANS combat (the `g` that kaiju_ai.gd / bosses.gd call, and the `ctx` for pilot.gd).
## Host / local only decide anything here: kaiju spawning and brains, punches, the chest beam, the foam
## cannon, the claw (grab + throw minis and boulders), telegraphed kaiju attacks hitting the Titan, the
## support vehicles and the city, finishing punches and sending kaiju home. Every visible effect goes
## through emit_fx(), which plays it here and sends it to the TV machine as a "fx" event.
## The TV machine only uses this node to mirror kaiju and boulders (apply_kaiju / apply_boulders) and
## to play effects (play_fx).

const Data := preload("res://games/mech_titans/data.gd")
const Kaiju := preload("res://games/mech_titans/kaiju.gd")
const KaijuAI := preload("res://games/mech_titans/kaiju_ai.gd")
const Bosses := preload("res://games/mech_titans/bosses.gd")
const Mech := preload("res://games/mech_titans/mech.gd")
const City := preload("res://games/mech_titans/city.gd")
const Fx := preload("res://games/mech_titans/fx.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const UiMenu := preload("res://core/ui_menu.gd")
const VrRig := preload("res://core/vr_rig.gd")

const BEAM_DPS := 34.0
const BEAM_RANGE := 140.0
const BEAM_ENERGY := 20.0  ## per second
const PUNCH_DAMAGE := 30.0
const PUNCH_REACH := 3.2  ## metres beyond the fist that still count (generous)
const FOAM_RANGE := 30.0
const BOULDER_SCALE := 3.2

var main: Node  ## main.gd
var city: City
var mech: Mech
var fx: Fx
var kaiju := {}  ## id -> Kaiju
var next_id := 1
var boulders := {}  ## id -> Node3D
var boulder_vel := {}  ## host: id -> Vector3 (flying boulders)
var next_boulder := 1
var held_kind := ""  ## "kaiju" / "boulder" / "" (claw)
var held_id := -1
var held_t := 0.0
var hp_scale := 1.0  ## bots shorten fights
var threat_t := 0.0
var _bld_dirty := false
var _bld_t := 0.0
var _foam_acc := {}  ## building -> seconds of foam
var _beam_sound := false
var _slowmo := 0.0
var _tele_warned := 0.0


func setup(p_main: Node, p_city: City, p_mech: Mech, p_fx: Fx) -> void:
	main = p_main
	city = p_city
	mech = p_mech
	fx = p_fx


## Remove every kaiju and boulder (new mission / back to the hangar).
func clear() -> void:
	for id in kaiju:
		(kaiju[id] as Node).queue_free()
	kaiju.clear()
	for id in boulders:
		(boulders[id] as Node).queue_free()
	boulders.clear()
	boulder_vel.clear()
	held_kind = ""
	held_id = -1
	_foam_acc.clear()
	if _slowmo > 0.0:
		Engine.time_scale = 1.0
		_slowmo = 0.0


func _is_host() -> bool:
	return main.net.mode != "client"


# --- Spawning ---------------------------------------------------------------------------------------

## Host: a new kaiju walking (or flying / swimming) in from `from` towards `goal`.
func spawn(k: String, from: Vector3, goal: Vector3, split_gen: int = 0, blocking: bool = true) -> Kaiju:
	var n := _make_kaiju(next_id, k, split_gen)
	next_id += 1
	n.position = Vector3(from.x, n.fly_alt, from.z)
	n.attack_pos = goal
	n.hp_max *= hp_scale if not n.is_mini else 1.0
	n.hp = n.hp_max
	n.set_meta("blocking", blocking)
	if Data.SIMPLE_MODE and not n.is_mini and main.missions != null:
		# SIMPLE_MODE: this round's kaiju is softer, slower and calmer (round 1: very friendly).
		var info: Dictionary = main.missions.info
		n.hp_max *= float(info.get("hp", 1.0))
		n.hp = n.hp_max
		n.set_meta("slow", float(info.get("slow", 1.0)))
		n.set_meta("calm", float(info.get("calm", 1.0)))
	var to := goal - from
	n.yaw = atan2(to.x, to.z)
	n.rotation.y = n.yaw
	n.set_state("enter")
	return n


func _make_kaiju(id: int, k: String, split_gen: int) -> Kaiju:
	var n := Kaiju.new()
	n.setup(id, k, split_gen)
	main.world_root.add_child(n)
	kaiju[id] = n
	return n


## Host: n minis of `kind` arriving from the edges (or around `near`).
func spawn_minis(kind: String, n: int, blocking: bool, near: Vector3 = Vector3.INF) -> void:
	for i in n:
		var from: Vector3
		var goal: Vector3
		if near != Vector3.INF:
			var a := randf() * TAU
			from = near + Vector3(cos(a), 0, sin(a)) * randf_range(6.0, 12.0)
			goal = from + Vector3(cos(a), 0, sin(a)) * 8.0
		else:
			var side := randi() % 3
			var t := randf_range(-50.0, 50.0)
			from = [Vector3(t, 0, -Data.MAP - 6.0), Vector3(-Data.MAP - 6.0, 0, t * 0.6 - 20.0), Vector3(Data.MAP + 6.0, 0, t * 0.6 - 20.0)][side]
			goal = Vector3(randf_range(-45.0, 45.0), 0, randf_range(-50.0, 18.0))
		spawn(kind, from, goal, 0, blocking)


## Host: a boss enters from the north.
func spawn_boss(k: String, index: int, count: int) -> Kaiju:
	var x := 0.0 if count <= 1 else (-22.0 if index == 0 else 22.0)
	var n: Kaiju
	if Data.SIMPLE_MODE:
		n = spawn(k, Vector3(x, 0, -44.0), Vector3(x * 0.6, 0, 4.0))  # closer: no long wait for little ones
	else:
		n = spawn(k, Vector3(x, 0, -Data.MAP - 14.0), Vector3(x * 0.6, 0, -22.0))
	emit_fx("sfx", ["explosion", n.global_position, 6.0, 0.4])
	return n


## Host: a PRACTICE target (missions.gd's warm-up): a little zap bat that hovers at `local` (Titan
## space: -Z is ahead, y = height) with a glowing ring, waiting for a punch or the beam.
func spawn_practice(local: Vector3) -> Kaiju:
	var p := mech.to_global(Vector3(local.x, 0.0, local.z))
	var n := _make_kaiju(next_id, "batlet", 0)
	next_id += 1
	n.fly_alt = local.y
	n.alt = local.y
	n.position = Vector3(p.x, local.y, p.z)
	n.hp_max = 14.0
	n.hp = n.hp_max
	n.set_meta("blocking", true)
	var to := mech.global_position - n.position
	n.yaw = atan2(to.x, to.z)
	n.rotation.y = n.yaw
	n.set_state("practice")
	emit_fx("burst", ["stars", n.center(), 2.0])
	return n


func active_bosses() -> Array[Kaiju]:
	var out: Array[Kaiju] = []
	for id in kaiju:
		var k: Kaiju = kaiju[id]
		if not k.is_mini and k.state != "gone" and k.state != "home":
			out.append(k)
	return out


## Blocking kaiju still in the fight (for mission steps).
func blocking_left() -> int:
	var n := 0
	for id in kaiju:
		var k: Kaiju = kaiju[id]
		if bool(k.get_meta("blocking", true)) and k.state != "home" and k.state != "gone":
			n += 1
	return n


func minis_alive() -> int:
	var n := 0
	for id in kaiju:
		var k: Kaiju = kaiju[id]
		if k.is_mini and k.state != "home" and k.state != "gone":
			n += 1
	return n


# --- Host tick --------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	threat_t = maxf(0.0, threat_t - delta)
	_tele_warned = maxf(0.0, _tele_warned - delta)
	for id in kaiju.keys():
		var k: Kaiju = kaiju[id]
		if k.state == "gone":
			if k.state_t > 0.5 or not k.visible:
				k.queue_free()
				kaiju.erase(id)
			k.state_t += delta
			continue
		KaijuAI.think(k, delta, self)
		if k.state != "home" and k.state != "thrown" and k.state != "grabbed" and k.fly_alt <= 0.0:
			# Keep walkers out of the Titan (it's a big robot).
			var to := Vector2(k.position.x - mech.position.x, k.position.z - mech.position.z)
			var minr := k.radius * 0.7 + Mech.RADIUS
			if to.length() < minr:
				var nrm := to.normalized() if to.length() > 0.01 else Vector2(0, -1)
				k.position.x = mech.position.x + nrm.x * minr
				k.position.z = mech.position.z + nrm.y * minr
		if k.hp <= 0.0 and k.is_active():
			_defeated(k)
	_tick_boulders(delta)
	_tick_held(delta)
	if _bld_dirty:
		_bld_t -= delta
		if _bld_t <= 0.0:
			_bld_dirty = false
			_bld_t = 0.2
			main.net.state_set("bld", city.pack_states())


## The Titan's pilot output for this frame (pilot.gd): punches, beam / foam, tool lever.
func pilot_actions(delta: float, out: Dictionary) -> void:
	if mech.rebooting > 0.0:
		mech.beam_on = false
		mech.foam_on = false
		_set_beam_sound(false)
		return
	var flip: int = out.get("tool", 0)
	if flip != 0 and not Data.SIMPLE_MODE:
		main.cycle_tool(flip)
	for p in out.get("punches", []):
		var arr: Array = p
		_punch(int(arr[0]), float(arr[1]), out)
	var trig: bool = out.get("beam", false) and bool(main.move_ok("beam"))
	var from: Vector3 = out.get("aim_from", mech.chest_world())
	var dir: Vector3 = out.get("aim_dir", mech.forward())
	if mech.tool == "foam":
		mech.beam_on = false
		_set_beam_sound(false)
		mech.foam_on = trig and mech.use_energy(6.0 * delta)
		if mech.foam_on:
			_foam(delta, dir)
	else:
		mech.foam_on = false
		var on := trig and mech.energy > 0.5
		if on and not mech.beam_on and mech.energy < 8.0:
			on = false  # empty: wait for a little charge before restarting
		mech.beam_on = on
		if on and not Data.SIMPLE_MODE:  # SIMPLE_MODE: no energy meter, the beam never runs out
			mech.use_energy(BEAM_ENERGY * delta * float(main.energy_mult()))
		if on:
			_beam(delta, from, dir)
		else:
			mech.beam_hot = false
		_set_beam_sound(on)


func _set_beam_sound(on: bool) -> void:
	if on == _beam_sound:
		return
	_beam_sound = on
	if on:
		main.sfx.play_loop("hum", -4.0, 0.1)
		main.sfx.set_loop_pitch("hum", 1.6)
	else:
		main.sfx.stop_loop("hum", 0.2)


# --- Beam, foam --------------------------------------------------------------------------------------

## The beam starts at the chest and ends where the pilot points (ray from the hand / camera).
func _beam(delta: float, from: Vector3, dir: Vector3) -> void:
	dir = dir.normalized()
	var hit := _ray_kaiju(from, dir, BEAM_RANGE, 1.4)
	var end := from + dir * BEAM_RANGE
	if dir.y < -0.01:
		var tg := -from.y / dir.y
		if tg < BEAM_RANGE:
			end = from + dir * tg
	var bt := city.ray_hit(from, dir, BEAM_RANGE)
	mech.beam_hot = false
	# Kid-friendly: a kaiju on the beam's line is hit even behind a building (the beam hops over roofs).
	if not hit.is_empty():
		var k: Kaiju = hit["k"]
		var wi: int = hit["weak"]
		end = from + dir * float(hit["t"])
		var mult := 1.0
		if wi >= 0:
			if float(k.weak[wi]["painted"]) > 0.0:
				mult = 3.0
				mech.beam_hot = true
				end = k.weak_world(wi)
			else:
				mult = 1.5
		var dmg := BEAM_DPS * float(main.beam_mult()) * mult * delta
		damage_kaiju(k, dmg, wi, 0, "beam")
		k.stun = minf(100.0, k.stun + 6.0 * delta)
		k.aggro["mech"] = float(k.aggro.get("mech", 0.0)) + 4.0 * delta
		if randf() < delta * 8.0:
			emit_fx("burst", ["sparks", end, 1.6 if mult > 2.0 else 1.0], false)
		if mult > 2.0:
			main.hint_vr("triple", "TRIPLE DAMAGE on painted spots!")
	elif bt < BEAM_RANGE:
		end = from + dir * bt
		if randf() < delta * 5.0:
			emit_fx("burst", ["sparks", end, 0.7], false)
	mech.beam_end = end


func _foam(delta: float, dir: Vector3) -> void:
	var from := mech.fist_world(1)
	dir = dir.normalized()
	for i in city.burning():
		var top := city.building_top(i)
		var to := top - from
		if to.length() < FOAM_RANGE + 6.0 and to.normalized().dot(dir) > 0.82:
			_foam_acc[i] = float(_foam_acc.get(i, 0.0)) + delta
			if float(_foam_acc[i]) > 0.8:
				_foam_acc.erase(i)
				put_out(i, 0)
	for id in kaiju:
		var k: Kaiju = kaiju[id]
		if not k.is_active():
			continue
		var to2 := k.center() - from
		if to2.length() < FOAM_RANGE + k.radius and to2.normalized().dot(dir) > 0.8:
			k.slip = 2.0
			damage_kaiju(k, 6.0 * delta, -1, 0, "foam")


## A fire went out (foam, a truck's hose, rain).
func put_out(i: int, by: int) -> void:
	if city.set_fire(i, false):
		_bld_dirty = true
		emit_fx("burst", ["foam" if by == 0 else "splash", city.building_top(i), 3.0])
		emit_fx("sfx", ["splash", city.building_top(i), 0.0, 0.8])
		main.missions.add_score(by, 15, "fires")


## Nearest kaiju along a ray: {"k": Kaiju, "t": float, "weak": int} or {}. Generous aim assist.
func _ray_kaiju(from: Vector3, dir: Vector3, max_d: float, assist: float) -> Dictionary:
	var best := {}
	var bt := INF
	for id in kaiju:
		var k: Kaiju = kaiju[id]
		if k.state == "home" or k.state == "gone" or k.state == "grabbed":
			continue
		var h := k.ray(from, dir, max_d, assist)
		if not h.is_empty() and float(h["t"]) < bt:
			bt = float(h["t"])
			best = {"k": k, "t": bt, "weak": int(h["weak"])}
	if best.is_empty():
		# Assist: snap to a kaiju within ~5 degrees of the ray.
		var best_dot := cos(deg_to_rad(5.0))
		for id in kaiju:
			var k2: Kaiju = kaiju[id]
			if not k2.is_active():
				continue
			var to := k2.center() - from
			if to.length() > max_d:
				continue
			var d := to.normalized().dot(dir)
			if d > best_dot:
				best_dot = d
				best = {"k": k2, "t": maxf(to.length() - k2.radius * 0.7, 1.0), "weak": -1}
	return best


# --- Punches and the claw ------------------------------------------------------------------------------

func _punch(hand: int, strength: float, out: Dictionary) -> void:
	var tool := mech.tool if hand == 1 else "fist"
	var sh := mech.to_global(mech.shoulder_local(hand))
	var tgt := mech.to_global(mech.fist_target[hand])
	var dir := (tgt - sh).normalized()
	var probe := sh + dir * Mech.REACH
	mech.punch_flash[hand] = 1.0
	if main.toys != null and main.toys.held[hand] >= 0:
		# A tree in this fist: the punch throws it.
		var tv: Vector3 = out.get("throw_vel", dir * 26.0)
		var vel := dir * 26.0 + Vector3(0, 7.0, 0)
		if main.pilot.mode == "vr" and tv.length() > 8.0:
			vel = tv.limit_length(40.0) + Vector3(0, 5.0, 0)
		main.toys.throw_tree(hand, vel)
		main.pulse(hand, 0.6, 0.1)
		return
	if tool == "claw" and hand == 1:
		if held_kind != "":
			_throw(out)
			return
		if _try_grab(probe):
			return
	var best: Kaiju = null
	var bd := PUNCH_REACH + 1.0
	for id in kaiju:
		var k: Kaiju = kaiju[id]
		if k.state == "home" or k.state == "gone" or k.state == "thrown" or k.state == "grabbed":
			continue
		if not k.can_punch and k.state != "downed":
			continue
		var d := minf(k.surface_distance(probe), k.surface_distance(mech.fist_world(hand)))
		if d < bd:
			bd = d
			best = k
	main.pulse(hand, 0.35 + strength * 0.4, 0.08)
	if best != null and bd <= PUNCH_REACH:
		_punch_kaiju(best, hand, strength, tool, probe, dir)
		return
	# Missed the kaiju: buildings and props in reach wobble, trees and cars get bonked.
	var bi := city.nearest_building(probe, 3.0)
	if bi >= 0 and Data.SIMPLE_MODE:
		# SIMPLE_MODE: buildings just wobble (boing!), they never break from a punch.
		emit_fx("wobble", [int(city.buildings[bi]["block"])])
		emit_fx("sfx", ["boing", probe, 4.0, 0.45])
		main.cockpit_rattle(0.25)
	elif bi >= 0:
		emit_fx("burst", ["dust", probe, 2.0])
		emit_fx("sfx", ["hit", probe, 2.0, 0.6])
		if city.damage_building(bi, 5.0 * strength):
			on_building_changed(bi)
		main.cockpit_rattle(0.25)
	if probe.y < 5.0:
		city.squash_at(probe, 4.0)
		main.net.event("squash", [probe, 4.0])
	emit_fx("sfx", ["whoosh", probe, -4.0, 0.6])


func _punch_kaiju(k: Kaiju, hand: int, strength: float, tool: String, probe: Vector3, dir: Vector3) -> void:
	var wi := k.weak_near(probe, 3.5)
	var mult := 1.0 + (1.0 if tool == "drill" else 0.0)
	if wi >= 0:
		mult *= 1.5
	var dmg := PUNCH_DAMAGE * (0.5 + strength) * mult
	var finishing := k.state == "dizzy" and not k.is_mini
	var hit_at := k.weak_world(wi) if wi >= 0 else probe
	main.pulse(hand, 0.9, 0.14)
	main.cockpit_rattle(0.5)
	if finishing:
		_finishing_punch(k, hit_at)
		return
	damage_kaiju(k, dmg, wi, 0, "punch", tool == "drill")
	k.stun = minf(100.0, k.stun + 12.0 * strength)
	k.aggro["mech"] = float(k.aggro.get("mech", 0.0)) + 10.0
	if k.state != "dizzy" and k.fly_alt <= 0.0:
		var push := Vector3(dir.x, 0, dir.z).normalized() * (2.5 if not k.is_mini else 5.0) * strength
		var p := city.push_out(k.position + push, k.radius * 0.5)
		k.position = Vector3(p.x, k.position.y, p.z)
	k.hit_fx(Color(1, 1, 1), -dir)
	emit_fx("burst", ["boom", hit_at, 1.4 + strength])
	emit_fx("sfx", ["crit" if strength > 0.7 else "sword_hit", hit_at, 4.0, 0.55 + randf() * 0.1])
	emit_fx("shake", [0.25 + strength * 0.25])
	emit_fx("pop", [hit_at + Vector3.UP * 2.0, "POW!" if strength > 0.6 else "BONK!", Color(1.0, 0.85, 0.3), 3.0])
	main.missions.add_score(0, int(dmg), "damage")
	main.awards.add(0, "hits")


## A defeated boss is dizzy: a punch sends it home in slow motion.
func _finishing_punch(k: Kaiju, at: Vector3) -> void:
	emit_fx("burst", ["stars", at, 4.0])
	emit_fx("burst", ["boom", at, 4.0])
	emit_fx("ring", [k.global_position + Vector3.UP, 40.0, Color(1.0, 0.85, 0.3)])
	emit_fx("sfx", ["big_kill", at, 8.0, 0.8])
	emit_fx("slowmo", [0.6])
	main.cockpit_message("SUPER PUNCH!", Color(1.0, 0.85, 0.3), 2.0)
	main.missions.add_score(0, 300, "finishers")
	k.velocity = (Vector3(k.position.x - mech.position.x, 0, k.position.z - mech.position.z).normalized() * 14.0)
	send_home(k, true)


func _try_grab(probe: Vector3) -> bool:
	var fist := mech.fist_world(1)
	for id in kaiju:
		var k: Kaiju = kaiju[id]
		if not k.is_mini or k.state == "home" or k.state == "gone" or k.state == "thrown":
			continue
		if minf(k.surface_distance(probe), k.surface_distance(fist)) < 3.5:
			held_kind = "kaiju"
			held_id = int(id)
			k.set_state("grabbed")
			_grabbed_fx(fist, "GOT ONE!")
			return true
	for id2 in boulders:
		var b: Node3D = boulders[id2]
		if boulder_vel.has(id2):
			continue
		if minf(b.global_position.distance_to(probe), b.global_position.distance_to(fist)) < 4.5:
			held_kind = "boulder"
			held_id = int(id2)
			_grabbed_fx(fist, "BOULDER!")
			return true
	return false


func _grabbed_fx(at: Vector3, text: String) -> void:
	mech.claw_closed = true
	held_t = 0.0
	emit_fx("sfx", ["pickup", at, 4.0, 0.6])
	main.pulse(1, 0.7, 0.12)
	main.cockpit_message(text + " SWING TO THROW", Color(1.0, 0.8, 0.3), 2.0)


func _tick_held(delta: float) -> void:
	if held_kind == "":
		mech.claw_closed = false
		return
	held_t += delta
	var at := mech.fist_world(1) + Vector3(0, 1.2, 0)
	if mech.tool != "claw" or mech.rebooting > 0.0:
		_drop()
		return
	if held_kind == "kaiju":
		if not kaiju.has(held_id):
			_drop()
			return
		var k: Kaiju = kaiju[held_id]
		k.position = at - Vector3(0, k.height * 0.5, 0)
		k.rotation.y += delta * 2.0
	elif boulders.has(held_id):
		(boulders[held_id] as Node3D).global_position = at


func _drop() -> void:
	if held_kind == "kaiju" and kaiju.has(held_id):
		var k: Kaiju = kaiju[held_id]
		k.velocity = Vector3.ZERO
		k.set_state("thrown")
	elif held_kind == "boulder" and boulders.has(held_id):
		boulder_vel[held_id] = Vector3.ZERO
	held_kind = ""
	held_id = -1
	mech.claw_closed = false


func _throw(out: Dictionary) -> void:
	var dir: Vector3 = out.get("aim_dir", mech.forward())
	dir.y = clampf(dir.y, -0.1, 0.5)
	var v := dir.normalized() * 30.0 + Vector3(0, 9.0, 0)
	emit_fx("sfx", ["whoosh", mech.fist_world(1), 6.0, 0.5])
	main.pulse(1, 0.8, 0.1)
	if held_kind == "kaiju" and kaiju.has(held_id):
		var k: Kaiju = kaiju[held_id]
		k.velocity = v
		k.set_state("thrown")
	elif held_kind == "boulder" and boulders.has(held_id):
		boulder_vel[held_id] = v
	held_kind = ""
	held_id = -1
	mech.claw_closed = false
	main.awards.add(0, "throws")


## A thrown mini landed (kaiju_ai): bonk anything it hits, then it goes home.
func kaiju_landed(k: Kaiju) -> void:
	emit_fx("burst", ["dust", k.global_position, 3.0])
	emit_fx("sfx", ["land", k.global_position, 6.0, 0.6])
	_impact(k.global_position, 6.0, 45.0, k)
	send_home(k, true)


func _impact(p: Vector3, r: float, dmg: float, except: Node) -> void:
	for id in kaiju:
		var o: Kaiju = kaiju[id]
		if o == except or not o.is_active():
			continue
		if o.surface_distance(p) < r:
			damage_kaiju(o, dmg, -1, 0, "throw")
			o.stun = minf(100.0, o.stun + 30.0)
			o.hit_fx()
			emit_fx("pop", [o.center() + Vector3.UP * o.height * 0.5, "BONK!", Color(1.0, 0.8, 0.3), 3.0])


# --- Boulders -------------------------------------------------------------------------------------------

func add_boulder(p: Vector3, flying: Vector3 = Vector3.INF) -> int:
	var id := next_boulder
	next_boulder += 1
	_make_boulder(id, p)
	if flying != Vector3.INF:
		boulder_vel[id] = flying
	return id


func _make_boulder(id: int, p: Vector3) -> Node3D:
	var mi := MeshKit.instance(MeshKit.prop("rock"))
	mi.scale = Vector3.ONE * BOULDER_SCALE
	main.world_root.add_child(mi)
	mi.global_position = p
	boulders[id] = mi
	return mi


func _tick_boulders(delta: float) -> void:
	for id in boulder_vel.keys():
		if not boulders.has(id):
			boulder_vel.erase(id)
			continue
		var b: Node3D = boulders[id]
		var v: Vector3 = boulder_vel[id]
		v.y -= 22.0 * delta
		var p := b.global_position + v * delta
		var hit := false
		for kid in kaiju:
			var k: Kaiju = kaiju[kid]
			if k.is_active() and k.surface_distance(p) < 1.5 and v.length() > 8.0:
				hit = true
		if p.y <= 0.0 or hit:
			p.y = maxf(p.y, 0.0)
			_impact(p, 6.0, 50.0 if hit else 25.0, null)
			emit_fx("burst", ["dust", p, 3.5])
			emit_fx("sfx", ["explosion", p, 2.0, 0.7])
			emit_fx("shake", [0.3])
			var bi := city.nearest_building(p, 2.0)
			if bi >= 0 and city.damage_building(bi, 25.0):
				on_building_changed(bi)
			p.y = 0.0
			boulder_vel.erase(id)
		else:
			boulder_vel[id] = v
		b.global_position = p
		b.rotation += Vector3(delta * 3.0, delta * 2.0, 0) * minf(v.length() * 0.1, 1.0)


# --- Damage, defeat, going home -----------------------------------------------------------------------

## Host: damage a kaiju (and weak spot wi). by: slot for awards (0 = the Titan).
func damage_kaiju(k: Kaiju, amount: float, wi: int, by: int, source: String, crack: bool = false) -> void:
	if not k.is_active() and k.state != "dizzy":
		return
	if k.state == "dizzy":
		return
	if k.state == "practice" and by != 0:
		return  # warm-up targets are the pilot's to hit
	var m := Bosses.damage_mult(k, wi)
	var dmg := amount * m
	if wi >= 0 and wi < k.weak.size():
		var w: Dictionary = k.weak[wi]
		if float(w["hp_max"]) > 0.0 and not bool(w["broken"]):
			w["hp"] = float(w["hp"]) - amount * (3.0 if crack else 1.0) * (1.0 if source != "beam" else 0.8)
			if float(w["hp"]) <= 0.0:
				w["broken"] = true
				Bosses.on_weak_broken(k, wi, self)
				main.missions.add_score(by, 100, "weak_spots")
	k.hp = maxf(0.0, k.hp - dmg)
	if by > 0:
		main.awards.add(by, "damage", dmg)
	Bosses.after_damage(k, self)
	if k.stun >= 100.0 and (k.state == "roam" or k.state == "windup" or k.state == "recover" or k.state == "enter"):
		stun_kaiju(k, 0)


## A full stun meter / stun shell: dizzy for a moment (flyers fall down and can be punched).
func stun_kaiju(k: Kaiju, by: int) -> void:
	if not k.is_active() or k.state == "stunned" or k.state == "downed" or k.state == "practice":
		return
	var st := Bosses.stun_state(k)
	k.set_state(st)
	k.stun = 0.0
	if st == "downed" and k.anim != null:
		k.anim.call("faint")
	emit_fx("burst", ["stars", k.center() + Vector3.UP * k.height * 0.5, 2.5])
	emit_fx("sfx", ["boing", k.center(), 4.0, 0.6])
	if not k.is_mini:
		var what := "KNOCKED DOWN!" if st == "downed" else "STUNNED!"
		announce(what, "PUNCH IT NOW!" if st == "downed" else "Hit it while it's dizzy!", "info")
		main.cockpit_message(what + " PUNCH!", Color(0.6, 0.9, 1.0), 2.0)
	if by > 0:
		main.awards.add(by, "stuns")


func _defeated(k: Kaiju) -> void:
	if k.is_mini:
		emit_fx("pop", [k.center() + Vector3.UP * k.height * 0.6, "BYE!", Color(1.0, 0.9, 0.5), 2.2])
		send_home(k, false)
		main.missions.add_score(0, 40, "minis")
		return
	# Bosses get dizzy and wait for a finishing punch (or wander off after a while).
	k.set_state("dizzy")
	k.dizzy_wait = 14.0
	k.attack = ""
	if k.anim != null:
		k.anim.call("play", "hurt", 1.0)
	emit_fx("burst", ["stars", k.center() + Vector3.UP * k.height * 0.5, 4.0])
	emit_fx("sfx", ["faint", k.center(), 6.0, 0.6])
	announce("%s IS DIZZY!" % String(k.info["name"]), "Titan: PUNCH it to send it home!", "victory")
	main.cockpit_message("DIZZY! PUNCH IT!", Color(1.0, 0.85, 0.3), 3.0)
	main.hint_vr("finish", "PUNCH the dizzy kaiju!")


## Send a kaiju home (kid-friendly: it waves and walks / swims / flies away).
func send_home(k: Kaiju, punched: bool) -> void:
	if k.state == "home" or k.state == "gone":
		return
	if held_kind == "kaiju" and held_id == k.id:
		held_kind = ""
		held_id = -1
	var how: String = k.info.get("home", "walk")
	var away := Vector3(k.position.x, 0, k.position.z)
	if how == "swim" and city.has_water:
		away = Vector3(k.position.x * 0.2, 0, -60.0) - away
	if away.length() < 1.0:
		away = Vector3(0, 0, -1)
	k.home_dir = away.normalized()
	if k.velocity.length() > 1.0 and punched:
		k.position += k.velocity * 0.3
	k.velocity = Vector3.ZERO
	k.rotation.x = 0.0
	k.position.y = maxf(k.position.y, 0.0) if k.fly_alt <= 0.0 else k.position.y
	k.set_state("home")
	if k.anim != null and bool(k.anim.call("is_down")):
		k.anim.call("revive")
	if not k.is_mini:
		emit_fx("burst", ["stars", k.center(), 5.0])
		announce("%s WENT HOME!" % String(k.info["name"]), "Bye bye, %s!" % String(k.info["name"]).to_lower().capitalize(), "victory")
		main.missions.add_score(0, 500, "bosses")
		main.music.play_mood("victory")
	main.missions.on_kaiju_home(k)


# --- Calls from kaiju_ai.gd / bosses.gd ------------------------------------------------------------------

func support_bonus() -> bool:
	return bool(main.has_upgrade("support"))


func in_water(p: Vector3) -> bool:
	if not city.has_water:
		return false
	var water: String = city.place_info.get("water", "")
	if water == "all":
		return Vector2(p.x, p.z).length() > Data.MAP - 4.0
	return p.z < -Data.MAP + 16.0


## Where a kaiju may step (buildings push it back: it bumps into them instead).
func kaiju_push(k: Kaiju, want: Vector3) -> Vector3:
	if k.fly_alt > 0.0:
		return want
	var p := city.push_out(want, k.radius * (0.45 if not k.is_mini else 0.4))
	p.x = clampf(p.x, -Data.MAP - 30.0, Data.MAP + 30.0)
	p.z = clampf(p.z, -Data.MAP - 30.0, Data.MAP + 30.0)
	return p


## A kaiju walked into a building: it gets bumped (and slowly crumbles).
func kaiju_bump(k: Kaiju, want: Vector3, delta: float) -> void:
	var i := city.nearest_building(want, k.radius * 0.5 + 1.5)
	if i < 0:
		return
	if city.damage_building(i, (14.0 if not k.is_mini else 5.0) * delta):
		on_building_changed(i)


## Host: a building changed state (damaged / rubble / repaired): publish + debris.
func on_building_changed(i: int) -> void:
	_bld_dirty = true
	var rec: Dictionary = city.buildings[i]
	if int(rec["state"]) != City.STATE_OK:
		emit_fx("debris", [rec["pos"], rec["size"], [rec["wall"], rec["roof"]], 26 if int(rec["state"]) == City.STATE_RUBBLE else 12])
		emit_fx("burst", ["dust", (rec["pos"] as Vector3) + Vector3.UP * 2.0, 4.0])
		emit_fx("sfx", ["crash", rec["pos"], 4.0, 0.7])
		if int(rec["state"]) == City.STATE_RUBBLE:
			emit_fx("shake", [0.35])
	main.missions.on_city_changed()


## What should this kaiju go for? {pos, size, what, node, reach}
func pick_target(k: Kaiju) -> Dictionary:
	var to_mech := Vector2(mech.position.x - k.position.x, mech.position.z - k.position.z).length()
	var best_key := ""
	var best_aggro := 6.0
	for key in k.aggro:
		if float(k.aggro[key]) > best_aggro:
			best_aggro = float(k.aggro[key])
			best_key = String(key)
	if best_key.begins_with("v"):
		var v: Node3D = main.support.vehicle(int(best_key.substr(1)))
		if v != null:
			var air: bool = main.support.is_flyer(v)
			return {"pos": v.global_position, "size": 0.0, "what": "air" if air else "ground", "node": v, "reach": k.radius + 6.0}
	if not k.is_mini and (to_mech < 46.0 or best_key == "mech"):
		return {"pos": mech.position, "size": Mech.RADIUS, "what": "mech", "node": mech, "reach": k.radius + Mech.RADIUS + 1.5}
	if city.landmark != null and city.landmark_hp > 0.0:
		var ld := Vector2(city.landmark_pos.x - k.position.x, city.landmark_pos.z - k.position.z).length()
		if ld < 60.0 or k.is_mini == false:
			return {"pos": city.landmark_pos, "size": city.landmark_radius * 0.8, "what": "landmark", "node": null, "reach": k.radius + 2.0}
	var bi := city.nearest_building(k.position, 80.0, true)
	if bi >= 0:
		var rec: Dictionary = city.buildings[bi]
		var s: Vector3 = rec["size"]
		return {"pos": rec["pos"], "size": maxf(s.x, s.z) * 0.5, "what": "building", "node": null, "reach": k.radius * 0.6 + 1.0, "bld": bi}
	return {"pos": mech.position, "size": Mech.RADIUS, "what": "mech", "node": mech, "reach": k.radius + Mech.RADIUS + 1.5}


## The wind-up warning: a glowing danger shape on the ground for everyone.
func telegraph(k: Kaiju, id: String) -> void:
	var w: float = KaijuAI.ATTACKS[id][1]
	var c := Color(1.0, 0.3, 0.2)
	var shape := _attack_shape(k, id)
	match String(shape["kind"]):
		"circle":
			emit_fx("marker", [shape["pos"], shape["r"], c, w])
		"line":
			emit_fx("line", [shape["a"], shape["b"], shape["w"], c, w])
		"multi":
			for p in shape["list"]:
				emit_fx("marker", [p, shape["r"], c, w])
	emit_fx("sfx", ["alarm" if not k.is_mini else "beep", k.center(), -4.0 if not k.is_mini else -10.0, 1.2])
	if k.is_mini:
		return
	if _shape_hits(shape, mech.position, Mech.RADIUS):
		threat_t = w + 0.3
		if _tele_warned <= 0.0:
			_tele_warned = 3.0
			main.cockpit_message("WATCH OUT!" if Data.SIMPLE_MODE else "INCOMING! BLOCK OR DASH", Color(1.0, 0.45, 0.35), w)
			main.pulse(0, 0.3, 0.1)
			main.pulse(1, 0.3, 0.1)
			main.hint_vr("block", "Raise BOTH hands to BLOCK!")


## Where an attack lands, decided at the wind-up: {kind: circle/line/multi/none, pos, r, a, b, w, list}.
func _attack_shape(k: Kaiju, id: String) -> Dictionary:
	var p := Vector3(k.position.x, 0, k.position.z)
	var d := k.attack_dir
	var tp := Vector3(k.attack_pos.x, 0, k.attack_pos.z)
	var s := k.height / 10.0
	var out := {"kind": "none"}
	match id:
		"fire_breath":
			out = {"kind": "line", "a": p + d * k.radius, "b": p + d * 24.0 * s, "w": 7.0 * s}
		"bubble_blast", "eye_laser":
			out = {"kind": "line", "a": p + d * k.radius, "b": p + d * (30.0 if id == "bubble_blast" else 45.0), "w": 5.0}
		"wing_gust":
			out = {"kind": "line", "a": p, "b": p + d * 26.0, "w": 10.0}
		"swoop":
			out = {"kind": "line", "a": p, "b": tp, "w": 7.0}
		"tail_swipe", "stomp", "electric_ring", "ground_pound", "mega_roar":
			var r: float = {"tail_swipe": 11.5, "stomp": 12.0, "electric_ring": 15.0, "ground_pound": 17.0, "mega_roar": 26.0}[id]
			out = {"kind": "circle", "pos": p, "r": r * (s if id == "tail_swipe" or id == "stomp" else 1.0)}
		"pinch", "nibble":
			out = {"kind": "circle", "pos": p + d * k.radius, "r": 6.0 if id == "pinch" else 3.0}
		"belly_flop":
			out = {"kind": "circle", "pos": tp, "r": 9.0}
		"goo_spit", "zap_bolt", "rock_throw", "swat":
			out = {"kind": "circle", "pos": tp, "r": {"goo_spit": 5.0, "zap_bolt": 5.5, "rock_throw": 6.0, "swat": 7.0}[id]}
		"sleepy_dust":
			out = {"kind": "circle", "pos": tp, "r": 8.0}
		"lava_bombs":
			var list: Array[Vector3] = [tp]
			for i in 3:
				var a := randf() * TAU
				list.append(tp + Vector3(cos(a), 0, sin(a)) * randf_range(8.0, 16.0))
			out = {"kind": "multi", "list": list, "r": 5.0}
		"drain":
			out = {"kind": "line", "a": p, "b": tp, "w": 3.0}
	k.set_meta("shape_" + id, out)  # do_attack() lands exactly where this telegraph showed
	return out


func _shape_hits(shape: Dictionary, p: Vector3, r: float) -> bool:
	match String(shape["kind"]):
		"circle":
			var c: Vector3 = shape["pos"]
			return Vector2(p.x - c.x, p.z - c.z).length() < float(shape["r"]) + r
		"line":
			var a: Vector3 = shape["a"]
			var b: Vector3 = shape["b"]
			var q := Geometry3D.get_closest_point_to_segment(Vector3(p.x, 0, p.z), Vector3(a.x, 0, a.z), Vector3(b.x, 0, b.z))
			return q.distance_to(Vector3(p.x, 0, p.z)) < float(shape["w"]) * 0.5 + r
		"multi":
			for c2 in shape["list"]:
				var cc: Vector3 = c2
				if Vector2(p.x - cc.x, p.z - cc.z).length() < float(shape["r"]) + r:
					return true
	return false


## The attack lands where the telegraph showed.
func do_attack(k: Kaiju, id: String) -> void:
	var key := "shape_" + id
	var shape: Dictionary = k.get_meta(key) if k.has_meta(key) else _attack_shape(k, id)
	k.remove_meta(key)
	var dmg: float = {"fire_breath": 14.0, "tail_swipe": 10.0, "stomp": 9.0, "lava_bombs": 8.0, "belly_flop": 14.0,
		"goo_spit": 6.0, "pinch": 12.0, "bubble_blast": 8.0, "zap_bolt": 12.0, "electric_ring": 10.0, "drain": 4.0,
		"wing_gust": 6.0, "sleepy_dust": 3.0, "swoop": 10.0, "ground_pound": 14.0, "rock_throw": 12.0, "eye_laser": 16.0,
		"mega_roar": 5.0, "nibble": 2.0, "swat": 4.0}.get(id, 0.0)
	var col := Color(1.0, 0.5, 0.2)
	var center := k.center()
	match id:
		"shell_guard":
			k.cooldowns["guarding"] = 4.0
			emit_fx("burst", ["sparks", center, 3.0])
			announce("SHELL GUARD!", "PINCHY is hiding: wait for it!", "info")
			return
		"summon":
			summon_minis(k, 3)
			return
		"belly_flop":
			var tp: Vector3 = shape["pos"]
			k.position = Vector3(tp.x, k.position.y, tp.z)
			emit_fx("burst", ["goo", tp + Vector3.UP, 4.0])
		"swoop":
			var tp2: Vector3 = shape["b"]
			k.position = Vector3(tp2.x, k.position.y, tp2.z)
		"rock_throw":
			add_boulder(center + Vector3.UP * k.height * 0.4, ((shape["pos"] as Vector3) - center) * 0.9 + Vector3(0, 14.0, 0))
			return  # the boulder itself does the damage where it lands
	# Visuals per attack.
	match id:
		"fire_breath", "eye_laser", "bubble_blast", "drain", "wing_gust":
			var a: Vector3 = shape["a"]
			var b: Vector3 = shape["b"]
			var kind := {"fire_breath": "fire", "eye_laser": "zap", "bubble_blast": "splash", "drain": "zap", "wing_gust": "dust"}[id] as String
			for t in 4:
				emit_fx("burst", [kind, a.lerp(b, (t + 0.5) / 4.0) + Vector3.UP * 2.0, 2.5])
			emit_fx("tracer", [center + Vector3.UP * k.height * 0.3, b + Vector3.UP, Color(1.0, 0.5, 0.2) if id != "bubble_blast" else Color(0.5, 0.8, 1.0), -1])
		"lava_bombs":
			for p in shape["list"]:
				emit_fx("burst", ["fire", (p as Vector3) + Vector3.UP, 2.5])
		_:
			if shape.has("pos"):
				emit_fx("ring", [shape["pos"], float(shape["r"]), col])
				emit_fx("burst", ["dust" if id != "electric_ring" and id != "zap_bolt" else "zap", (shape["pos"] as Vector3) + Vector3.UP, 3.0])
	emit_fx("sfx", [{"fire_breath": "fire", "eye_laser": "laser", "zap_bolt": "zap", "electric_ring": "zap", "drain": "power_down",
		"bubble_blast": "splash", "goo_spit": "spit", "sleepy_dust": "magic", "mega_roar": "crowd_oh"}.get(id, "explosion"), center, 6.0, 0.6])
	if not k.is_mini and id != "nibble":
		emit_fx("shake", [0.3])
	# The Titan.
	if _shape_hits(shape, mech.position, Mech.RADIUS):
		match id:
			"goo_spit", "sleepy_dust":
				mech.slowed = 3.0
			"drain":
				mech.energy = maxf(0.0, mech.energy - 30.0)
			"wing_gust":
				var push := k.attack_dir * 8.0
				mech.position = city.push_out(mech.position + push, Mech.RADIUS)
		hurt_mech(dmg * (1.0 if not k.is_mini else 0.5), k)
	# Buildings in the area.
	var fire := id == "fire_breath" or id == "lava_bombs" or id == "eye_laser"
	if not k.is_mini or id == "nibble":
		for i in city.buildings.size():
			var rec: Dictionary = city.buildings[i]
			if int(rec["state"]) == City.STATE_RUBBLE:
				continue
			var bp: Vector3 = rec["pos"]
			var bs: Vector3 = rec["size"]
			if _shape_hits(shape, bp, maxf(bs.x, bs.z) * 0.4):
				var changed := city.damage_building(i, dmg * (1.6 if id != "nibble" else 3.0))
				if fire and randf() < 0.5 and city.set_fire(i, true):
					changed = true
					main.hint_tv("fires", "FIRE! Rescue trucks: hose it with A!")
					main.hint_vr("foam", "Fires! Pull the LEVER for the FOAM CANNON")
				if changed:
					on_building_changed(i)
	# The landmark.
	if city.landmark != null and _shape_hits(shape, city.landmark_pos, city.landmark_radius * 0.6):
		main.missions.damage_landmark(dmg * (1.2 if id != "drain" else 3.0))
	# Support vehicles get spun around (nobody gets hurt).
	main.support.hit_shape(shape, self)


## Host: the Titan takes a hit.
func hurt_mech(amount: float, from: Node3D) -> void:
	if mech.rebooting > 0.0:
		return
	var blocking := mech.blocking
	var taken := mech.take_damage(amount * float(main.armour_taken_mult()))
	main.cockpit_rattle(0.35 if blocking else 0.8)
	main.pulse(0, 0.6 if not blocking else 0.3, 0.15)
	main.pulse(1, 0.6 if not blocking else 0.3, 0.15)
	if blocking:
		main.cockpit_message("BLOCKED!", Color(0.5, 0.9, 1.0), 1.0)
		main.awards.add(0, "blocks")
		emit_fx("burst", ["sparks", mech.chest_world() + mech.forward() * 4.0, 3.0])
		emit_fx("sfx", ["block", mech.chest_world(), 6.0, 0.6])
	else:
		emit_fx("burst", ["sparks", mech.chest_world(), 2.5])
		emit_fx("sfx", ["hurt", mech.chest_world(), 6.0, 0.5])
	main.awards.add(0, "damage_taken", taken)
	if from != null and from is Kaiju:
		(from as Kaiju).aggro["mech"] = float((from as Kaiju).aggro.get("mech", 0.0)) + 2.0
	if mech.rebooting > 0.0 and Data.SIMPLE_MODE:
		# Knocked down (never game over): a sit-down with dizzy stars, then it pops back up.
		emit_fx("burst", ["stars", mech.chest_world() + Vector3.UP * 4.0, 3.0])
		emit_fx("sfx", ["boing", mech.chest_world(), 6.0, 0.5])
		main.cockpit_message("WHOA!", Color(1.0, 0.75, 0.3), 2.5)
	elif mech.rebooting > 0.0:
		main.missions.on_reboot()
		announce("TITAN REBOOTING!", "Repair drones: fix the Titan fast!", "defeat")
		main.cockpit_message("REBOOTING...", Color(1.0, 0.5, 0.3), 5.0)
		emit_fx("sfx", ["power_down", mech.chest_world(), 6.0, 0.8])


## Jelly split: two smaller jellies pop out (they're part of the same fight).
func split_jelly(k: Kaiju) -> void:
	var gen := k.split_gen + 1
	var r := mech.right() * k.radius
	for s in [-1.0, 1.0]:
		var from: Vector3 = k.position + r * s
		var n := spawn("jelly", from, from + r * s * 1.5, gen, bool(k.get_meta("blocking", true)))
		n.set_state("roam")
		n.aggro = k.aggro.duplicate()
	emit_fx("burst", ["goo", k.center(), 5.0])
	emit_fx("sfx", ["boing", k.center(), 8.0, 0.5])
	announce("SPLIT!", "Two smaller jellies! Keep going!", "info")
	k.set_state("gone")
	k.visible = false
	main.missions.add_score(0, 100, "splits")


func summon_minis(k: Kaiju, n: int) -> void:
	var kind: String = "batlet" if k.kind == "mega" else main.missions.extra_kind()
	spawn_minis(kind, n, false, k.position)
	emit_fx("ring", [k.global_position + Vector3.UP, 20.0, Color(0.7, 0.5, 1.0)])


func announce(title: String, sub: String, style: String) -> void:
	main.announce(title, sub, style)
	main.net.event("announce", [title, sub, style])


## For pilot.gd's autopilot: the kaiju to fight (nearest; dizzy bosses first for the finishing punch).
func auto_target(from: Vector3) -> Node3D:
	var best: Kaiju = null
	var bd := INF
	for id in kaiju:
		var k: Kaiju = kaiju[id]
		if k.state == "home" or k.state == "gone" or k.state == "grabbed" or k.state == "thrown":
			continue
		var d := Vector2(k.position.x - from.x, k.position.z - from.z).length()
		if k.state == "dizzy":
			d -= 200.0
		elif not k.is_mini:
			d -= 25.0
		if d < bd:
			bd = d
			best = k
	return best


func mech_threatened() -> bool:
	return threat_t > 0.0


func is_beaming() -> bool:
	return mech.beam_on


func slot_busy(slot: int) -> bool:
	return UiMenu.slot_busy(slot)


# --- Effects (every machine) -------------------------------------------------------------------------

## Play an effect here and (host) on the TV machine too. send=false: local only (cosmetic spam).
func emit_fx(kind: String, args: Array, send: bool = true) -> void:
	play_fx(kind, args)
	if send and main.net.mode == "host":
		main.net.event("fx", [kind, args])


func play_fx(kind: String, a: Array) -> void:
	match kind:
		"burst":
			fx.burst(String(a[0]), a[1], float(a[2]), a[3] if a.size() > 3 else Color(0, 0, 0, 0))
		"ring":
			fx.ring(a[0], float(a[1]), a[2])
		"tracer":
			if a.size() < 4 or not main.party.is_local(int(a[3])):
				fx.tracer(a[0], a[1], a[2])
		"marker":
			fx.marker(a[0], float(a[1]), a[2], float(a[3]))
		"line":
			fx.line_marker(a[0], a[1], float(a[2]), a[3], float(a[4]))
		"debris":
			fx.debris(a[0], a[1], a[2], int(a[3]))
		"sfx":
			main.sfx.play_at(String(a[0]), a[1], float(a[2]), float(a[3]))
		"pop":
			HudKit.popup(main.world_root, a[0], String(a[1]), {"color": a[2], "size": float(a[3])})
		"shake":
			main.tv_shake(float(a[0]))
		"slowmo":
			_start_slowmo(float(a[0]))
		"tree":
			if main.toys != null:
				main.toys.on_tree(a)
		"wobble":
			if main.toys != null:
				main.toys.wobble(int(a[0]))


func _start_slowmo(real_seconds: float) -> void:
	_slowmo = real_seconds
	Engine.time_scale = 0.3
	get_tree().create_timer(real_seconds, true, false, true).timeout.connect(func() -> void:
		_slowmo = 0.0
		Engine.time_scale = 1.0)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# --- Networking (kaiju + boulders) -------------------------------------------------------------------

func pack_kaiju() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for id in kaiju:
		var k: Kaiju = kaiju[id]
		if k.state == "gone":
			continue
		out.append_array(k.pack())
	return out


## TV machine: mirror the host's kaiju (12 floats each).
func apply_kaiju(a: PackedFloat32Array) -> void:
	var seen := {}
	var all := Kaiju.all_kinds()
	var o := 0
	while o + 12 <= a.size():
		var id := int(a[o])
		var ki := int(a[o + 1])
		seen[id] = true
		var k: Kaiju = kaiju.get(id, null)
		if k == null and ki >= 0 and ki < all.size():
			k = _make_kaiju(id, all[ki], int(a[o + 2]))
			k.simulate_paint_decay = false
		if k != null:
			k.apply_pack(a, o)
		o += 12
	for id in kaiju.keys():
		if not seen.has(id):
			(kaiju[id] as Node).queue_free()
			kaiju.erase(id)


func client_tick(delta: float) -> void:
	for id in kaiju:
		(kaiju[id] as Kaiju).client_tick(delta)


func pack_boulders() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for id in boulders:
		var p := (boulders[id] as Node3D).global_position
		out.append_array([float(id), snappedf(p.x, 0.05), snappedf(p.y, 0.05), snappedf(p.z, 0.05)])
	return out


func apply_boulders(a: PackedFloat32Array) -> void:
	var seen := {}
	var o := 0
	while o + 4 <= a.size():
		var id := int(a[o])
		var p := Vector3(a[o + 1], a[o + 2], a[o + 3])
		seen[id] = true
		var b: Node3D = boulders.get(id, null)
		if b == null:
			b = _make_boulder(id, p)
		b.global_position = b.global_position.lerp(p, 0.5)
		o += 4
	for id in boulders.keys():
		if not seen.has(id):
			(boulders[id] as Node).queue_free()
			boulders.erase(id)
