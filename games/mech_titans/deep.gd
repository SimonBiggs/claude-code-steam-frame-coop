extends Node3D
## MECH TITANS deep play (titans-deep), every machine builds one under the world:
##  - DISTRICT HAZARDS (host): the round's place throws its hazard now and then (districts.gd plan in the
##    round's "hazard"): a glowing warning on the ground first, then it lands exactly there.
##  - UPGRADE EFFECTS (upgrades.gd, net store "upg"): the host runs ROCKET FISTS, STUN STOMP, MAGNET HAND,
##    REPAIR BOTS, SHIELD DOME, JUMP JETS and the BUDDY DRONE's zaps; every machine shows the dome and the drone.
##  - SANCTUARY HOMES (sanctuary.gd, net store "sanct_h"): the homes on the hills by the waving friends.
## main.gd calls host_tick (host / local) and visual_tick (every machine) from _process.

const Data := preload("res://games/mech_titans/data.gd")
const Districts := preload("res://games/mech_titans/districts.gd")
const Upgrades := preload("res://games/mech_titans/upgrades.gd")
const Sanctuary := preload("res://games/mech_titans/sanctuary.gd")
const Picks := preload("res://games/mech_titans/picks.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")

var main: Node
var haz_t := 0.0
var pending: Array = []  ## host: hazards waiting to land [{t, shape, kind}]
var hazards_landed := 0  ## host: this session (bots, telemetry)
var hazards_hit := 0
var dome_cd := 0.0
var domes_popped := 0
var rocket_cd := 0.0
var rockets := 0
var buddy_t := 0.0
var buddy_zaps := 0
var stomp_stuns := 0
var magnet_fx_t := 0.0
var jumps := 0
var _was_dash := false
var _hit_idle := 0.0
var _last_armour := -1.0
var buddy: Node3D
var dome: MeshInstance3D
var dome_ring: MeshInstance3D
var homes_root: Node3D
var homes_key := ""
var _t := 0.0


func setup(p_main: Node) -> void:
	main = p_main
	name = "TitanDeep"


func upg() -> Array:
	var u: Variant = main.net.state_get("upg", [])
	return u if u is Array else []


func has(id: String) -> bool:
	return upg().has(id)


## Host: a new round starts: hazards wait a moment, the dome is ready.
func round_start() -> void:
	haz_t = 0.0
	pending.clear()
	dome_cd = 0.0
	if has("dome"):
		main.net.state_set("dome", true)


# --- Host -----------------------------------------------------------------------------------------------

func host_tick(delta: float, phase: String) -> void:
	rocket_cd = maxf(0.0, rocket_cd - delta)
	var mech: Node3D = main.mech
	# Dome: comes back after a while.
	if has("dome") and dome_cd > 0.0:
		dome_cd -= delta
		if dome_cd <= 0.0:
			main.net.state_set("dome", true)
			main.combat.emit_fx("sfx", ["power_up", mech.chest_world(), -2.0, 1.0])
	# Repair bots: armour mends when nothing hit the Titan for a moment.
	if _last_armour >= 0.0 and mech.armour < _last_armour - 0.01:
		_hit_idle = 0.0
	_hit_idle += delta
	if has("repair") and _hit_idle > 1.5 and mech.rebooting <= 0.0 and mech.armour < mech.armour_max:
		mech.armour = minf(mech.armour_max, mech.armour + Upgrades.REPAIR_PER_S * delta)
		mech.repair_fx = 0.2
	_last_armour = mech.armour
	# Jump jets: a dash is a jump; landing shakes the ground.
	var dashing: bool = mech.dash_t > 0.0
	if _was_dash and not dashing and has("jets") and phase == "play":
		_jets_land(mech.global_position)
	_was_dash = dashing
	if phase != "play" or main.missions == null:
		return
	_hazards(delta)
	if has("magnet"):
		_magnet(delta)
	if has("buddy"):
		buddy_t += delta
		if buddy_t >= Upgrades.BUDDY_EVERY:
			buddy_t = 0.0
			_buddy_zap()


func _hazards(delta: float) -> void:
	var m: Dictionary = main.missions.info
	var hz: Dictionary = m.get("hazard", {})
	var every := float(hz.get("every", 0.0))
	for i in range(pending.size() - 1, -1, -1):
		var e: Dictionary = pending[i]
		e["t"] = float(e["t"]) - delta
		if float(e["t"]) <= 0.0:
			pending.remove_at(i)
			_land(e, hz)
	if every <= 0.0 or not main.missions.playing():
		return
	haz_t += delta
	if haz_t < every:
		return
	haz_t = 0.0
	var place := String(m.get("place", "downtown"))
	var h := Districts.info(place)
	var tell := float(hz.get("tell", 2.0))
	var mech: Node3D = main.mech
	for c in int(hz.get("count", 1)):
		var at := Vector3.ZERO
		if bool(hz.get("aim", false)):
			var a := randf() * TAU
			at = mech.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(0.0, 3.0 + 4.0 * c)
		else:
			# gentle: somewhere nearby but never on the Titan
			var a2 := randf() * TAU
			at = mech.global_position + Vector3(cos(a2), 0, sin(a2)) * randf_range(float(h["r"]) + 9.0, 30.0)
		at.x = clampf(at.x, -Data.MAP + 6.0, Data.MAP - 6.0)
		at.z = clampf(at.z, -Data.MAP + 6.0, Data.MAP - 6.0)
		at.y = 0.0
		var shape := {}
		var col: Color = h["color"]
		if String(h["shape"]) == "line":
			# the harbour's wave washes along a stripe from the sea (north) to the south
			shape = {"kind": "line", "a": Vector3(at.x, 0, -Data.MAP), "b": Vector3(at.x, 0, Data.MAP), "w": float(h["r"]) * 2.0}
			main.combat.emit_fx("line", [shape["a"], shape["b"], shape["w"], col, tell])
		else:
			shape = {"kind": "circle", "pos": at, "r": float(h["r"])}
			main.combat.emit_fx("marker", [at, float(h["r"]), col, tell])
		main.combat.emit_fx("sfx", ["alarm", at, -8.0, 1.5])
		pending.append({"t": tell, "shape": shape, "kind": String(h["hazard"]), "place": place})


func _land(e: Dictionary, hz: Dictionary) -> void:
	var h := Districts.info(String(e["place"]))
	var shape: Dictionary = e["shape"]
	var combat: Node = main.combat
	var mech: Node3D = main.mech
	var col: Color = h["color"]
	hazards_landed += 1
	var center: Vector3
	if String(shape["kind"]) == "line":
		var a: Vector3 = shape["a"]
		var b: Vector3 = shape["b"]
		for k in 6:
			combat.emit_fx("burst", [String(h["fx"]), a.lerp(b, (k + 0.5) / 6.0) + Vector3.UP * 1.5, 3.5, col])
		center = Geometry3D.get_closest_point_to_segment(Vector3(mech.global_position.x, 0, mech.global_position.z), a, b)
	else:
		center = shape["pos"]
		combat.emit_fx("burst", [String(h["fx"]), center + Vector3.UP * 1.5, float(h["r"]) * 0.7, col])
		combat.emit_fx("ring", [center, float(h["r"]), col])
	combat.emit_fx("sfx", [String(h["sfx"]), center, 2.0, 0.7])
	if combat._shape_hits(shape, mech.global_position, 2.6):
		hazards_hit += 1
		if float(h["slow"]) > 0.0:
			mech.slowed = maxf(mech.slowed, float(h["slow"]))
		var push := float(h["push"])
		if push > 0.0:
			var away := Vector3(mech.global_position.x - center.x, 0, mech.global_position.z - center.z)
			if String(shape["kind"]) == "line":
				away = Vector3(0, 0, 1)  # the wave pushes south, away from the sea
			if away.length() < 0.1:
				away = -mech.forward()
			mech.position = main.city.push_out(mech.position + away.normalized() * push, 2.6)
		if float(h["dmg"]) > 0.0:
			combat.hurt_mech(float(h["dmg"]), null)
		else:
			main.cockpit_rattle(0.5)
	if String(h["hazard"]) == "lava" and String(shape["kind"]) == "circle":
		var bi: int = main.city.nearest_building(center, float(h["r"]))
		if bi >= 0 and main.city.set_fire(bi, true):
			combat.on_building_changed(bi)
	main.support.hit_shape(shape, combat)


func _magnet(delta: float) -> void:
	var mech: Node3D = main.mech
	magnet_fx_t -= delta
	for id in main.combat.kaiju:
		var k: Node3D = main.combat.kaiju[id]
		if not (k.state in ["roam", "enter", "stunned", "downed", "dizzy"]):
			continue
		var to := Vector3(mech.global_position.x - k.position.x, 0, mech.global_position.z - k.position.z)
		var gap: float = to.length() - k.radius - 2.6
		if gap < 4.0 or to.length() > Upgrades.MAGNET_R + k.radius:
			continue
		var spd := Upgrades.MAGNET_SPEED * (2.0 if k.is_mini else 1.0)
		var want: Vector3 = k.position + to.normalized() * minf(spd * delta, gap - 4.0)
		var p: Vector3 = main.combat.kaiju_push(k, want)
		k.position = Vector3(p.x, k.position.y, p.z)
		if magnet_fx_t <= 0.0 and not k.is_mini:
			magnet_fx_t = 0.9
			main.combat.emit_fx("tracer", [mech.fist_world(0), k.center(), Upgrades.info("magnet")["color"], -1])


func _buddy_zap() -> void:
	var from := buddy_pos()
	var best: Node3D = null
	var bd := Upgrades.BUDDY_R
	for id in main.combat.kaiju:
		var k: Node3D = main.combat.kaiju[id]
		if not k.is_active():
			continue
		var d: float = from.distance_to(k.center())
		if d < bd:
			bd = d
			best = k
	if best == null:
		return
	buddy_zaps += 1
	main.combat.emit_fx("tracer", [from, best.center(), Upgrades.info("buddy")["color"], -1])
	main.combat.emit_fx("burst", ["sparks", best.center(), 1.2])
	main.combat.damage_kaiju(best, Upgrades.BUDDY_DMG, -1, 0, "buddy")


## Host: ROCKET FISTS: a punch that hit nothing flies on to a kaiju ahead. True when one flew.
func rocket_fist(hand: int, dir: Vector3, strength: float) -> bool:
	if not has("rocket") or rocket_cd > 0.0 or String(main.net.state_get("phase", "")) != "play":
		return false
	var mech: Node3D = main.mech
	var from: Vector3 = mech.fist_world(hand)
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	if flat.length() < 0.5:
		flat = mech.forward()
	var best: Node3D = null
	var best_dot := cos(deg_to_rad(28.0))
	for id in main.combat.kaiju:
		var k: Node3D = main.combat.kaiju[id]
		if not k.is_active() or k.state == "practice":
			continue
		var to: Vector3 = k.center() - from
		if to.length() > Upgrades.ROCKET_RANGE:
			continue
		var d := Vector3(to.x, 0, to.z).normalized().dot(flat)
		if d > best_dot:
			best_dot = d
			best = k
	if best == null:
		return false
	rocket_cd = 0.45
	rockets += 1
	var hit: Vector3 = best.center()
	main.combat.emit_fx("tracer", [from, hit, Upgrades.info("rocket")["color"], -1])
	main.combat.emit_fx("burst", ["fire", from, 1.2])
	main.combat.emit_fx("burst", ["boom", hit, 2.4])
	main.combat.emit_fx("sfx", ["explosion", hit, 2.0, 0.8])
	main.combat.emit_fx("pop", [hit + Vector3.UP * 2.0, "POW!", Color(1.0, 0.6, 0.3), 3.0])
	main.combat.damage_kaiju(best, Upgrades.ROCKET_DMG * (0.6 + strength * 0.6) * float(main.punch_mult()), -1, 0, "rocket")
	best.stun = minf(100.0, best.stun + 8.0)
	main.pulse(hand, 0.7, 0.12)
	return true


## Host: SHIELD DOME takes this hit? (then it pops and comes back after DOME_COOLDOWN)
func absorb_hit() -> bool:
	if not has("dome") or dome_cd > 0.0 or not bool(main.net.state_get("dome", false)):
		return false
	dome_cd = Upgrades.DOME_COOLDOWN
	domes_popped += 1
	main.net.state_set("dome", false)
	var mech: Node3D = main.mech
	main.combat.emit_fx("burst", ["sparks", mech.chest_world(), 5.0, Upgrades.info("dome")["color"]])
	main.combat.emit_fx("ring", [mech.global_position + Vector3.UP, 9.0, Upgrades.info("dome")["color"]])
	main.combat.emit_fx("sfx", ["block", mech.chest_world(), 6.0, 0.9])
	main.cockpit_rattle(0.2)
	return true


## Host: STUN STOMP: each footstep of the Titan makes kaiju near it dizzier (minis get bonked).
func on_stomp(pos: Vector3) -> void:
	if not has("stomp") or String(main.net.state_get("phase", "")) != "play":
		return
	var any := false
	for id in main.combat.kaiju:
		var k: Node3D = main.combat.kaiju[id]
		if not k.is_active() or k.state == "practice" or k.fly_alt > 8.0:
			continue
		if k.surface_distance(pos) < Upgrades.STOMP_R:
			any = true
			if k.is_mini:
				main.combat.damage_kaiju(k, 12.0, -1, 0, "stomp")
			else:
				k.stun = minf(100.0, k.stun + Upgrades.STOMP_STUN)
				if k.stun >= 100.0:
					main.combat.stun_kaiju(k, 0)
	if any:
		stomp_stuns += 1
		main.combat.emit_fx("ring", [pos + Vector3.UP * 0.3, Upgrades.STOMP_R, Upgrades.info("stomp")["color"]])


func _jets_land(p: Vector3) -> void:
	jumps += 1
	var col: Color = Upgrades.info("jets")["color"]
	main.combat.emit_fx("ring", [p + Vector3.UP * 0.3, Upgrades.JETS_R, col])
	main.combat.emit_fx("burst", ["dust", p + Vector3.UP, 5.0])
	main.combat.emit_fx("sfx", ["land", p, 8.0, 0.5])
	main.combat.emit_fx("shake", [0.4])
	main.combat._impact(p, Upgrades.JETS_R, Upgrades.JETS_DMG, null)
	main.city.squash_at(p, Upgrades.JETS_R * 0.6)
	main.net.event("squash", [p, Upgrades.JETS_R * 0.6])


# --- Every machine --------------------------------------------------------------------------------------

## Where the buddy drone is (the same sum on every machine: it circles the Titan's head).
func buddy_pos() -> Vector3:
	var mech: Node3D = main.mech
	var a := _t * 1.3
	return mech.global_position + Vector3(cos(a) * 6.5, 11.5 + sin(_t * 2.1) * 0.6, sin(a) * 6.5)


func visual_tick(delta: float) -> void:
	_t += delta
	var mech: Node3D = main.mech
	mech.jump_jets = has("jets")
	# Buddy drone.
	if has("buddy"):
		if buddy == null:
			buddy = MeshKit.instance(Picks.icon_mesh("upgrade", "buddy"), false)
			buddy.name = "BuddyDrone"
			buddy.scale = Vector3.ONE * 2.2
			add_child(buddy)
		buddy.global_position = buddy_pos()
		buddy.rotation.y += delta * 3.0
	elif buddy != null:
		buddy.queue_free()
		buddy = null
	# Shield dome: a bubble round the Titan (the TV sees it; the VR pilot inside sees its glowing ring on the ground).
	var up := has("dome") and bool(main.net.state_get("dome", false))
	if up and dome == null:
		dome = MeshInstance3D.new()
		dome.name = "ShieldDome"
		var sm := SphereMesh.new()
		sm.radius = 8.5
		sm.height = 17.0
		sm.radial_segments = 24
		sm.rings = 12
		dome.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var c: Color = Upgrades.info("dome")["color"]
		m.albedo_color = Color(c.r, c.g, c.b, 0.12)
		dome.material_override = m
		dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dome.layers = Data.LAYER_EXTERIOR
		add_child(dome)
		dome_ring = MeshInstance3D.new()
		dome_ring.name = "ShieldRing"
		var tm := TorusMesh.new()
		tm.inner_radius = 8.2
		tm.outer_radius = 8.7
		tm.rings = 32
		tm.ring_segments = 6
		dome_ring.mesh = tm
		dome_ring.material_override = m
		dome_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(dome_ring)
	if dome != null:
		dome.visible = up
		dome_ring.visible = up
		if up:
			dome.global_position = mech.global_position + Vector3.UP * 4.0
			dome_ring.global_position = mech.global_position + Vector3.UP * 0.3
			var s := 1.0 + 0.02 * sin(_t * 3.0)
			dome.scale = Vector3(s, s, s)
	# Sanctuary homes (when the hearts change).
	var h := int(main.net.state_get("sanct_h", 0))
	var key := ",".join(PackedStringArray(Sanctuary.homes(h)))
	if key != homes_key:
		homes_key = key
		_build_homes(Sanctuary.homes(h))


func _build_homes(list: Array) -> void:
	if homes_root != null:
		homes_root.queue_free()
	homes_root = Node3D.new()
	homes_root.name = "SanctuaryHomes"
	add_child(homes_root)
	for i in list.size():
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := Vector3(side * 78.0, 0.0, 22.0 - 16.0 * float(i / 2))
		var node := MeshKit.instance(_home_mesh(String(list[i])), false)
		node.name = "Home_%s" % list[i]
		node.position = at
		node.rotation.y = -side * PI * 0.5
		homes_root.add_child(node)


static func _home_mesh(id: String) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	match id:
		"pond":
			b.cylinder(6.0, 6.5, 0.3, MeshKit.at(Vector3(0, 0.1, 0)), Color(0.4, 0.7, 1.0), 20)
			for k in 6:
				var a := TAU * k / 6.0
				b.sphere(0.9, MeshKit.at(Vector3(cos(a) * 6.4, 0.3, sin(a) * 6.4), Vector3(1, 0.6, 1)), Color(0.6, 0.6, 0.62), 8)
		"palms":
			for k in 3:
				var x := -5.0 + k * 5.0
				b.cylinder(0.35, 0.5, 8.0, MeshKit.at(Vector3(x, 4.0, 0)), Color(0.6, 0.42, 0.25), 8)
				for l in 5:
					var a2 := TAU * l / 5.0
					b.ellipsoid(Vector3(2.4, 0.3, 0.8), MeshKit.at(Vector3(x + cos(a2) * 1.8, 8.0, sin(a2) * 1.8), Vector3.ONE, Vector3(0, -a2, -0.3)), Color(0.3, 0.75, 0.35), 8)
		"igloo":
			b.dome(5.0, Transform3D.IDENTITY, Color(0.95, 0.97, 1.0), 16)
			b.cylinder(1.8, 1.8, 2.6, MeshKit.at(Vector3(0, 1.3, 4.6), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.9, 0.93, 1.0), 12)
		"spring":
			b.cylinder(5.0, 5.5, 0.6, MeshKit.at(Vector3(0, 0.3, 0)), Color(0.55, 0.5, 0.48), 18)
			b.cylinder(4.3, 4.3, 0.7, MeshKit.at(Vector3(0, 0.4, 0)), Color(0.5, 0.9, 0.95), 18, true)
		"moonrock":
			for k in 4:
				b.sphere(1.6 + k * 0.4, MeshKit.at(Vector3(-4.0 + k * 2.6, 1.2, sin(k * 2.0) * 2.0), Vector3(1, 0.8, 1)), Color(0.7, 0.7, 0.78), 10)
			b.sphere(0.5, MeshKit.at(Vector3(0, 3.2, 0)), Color(0.8, 0.6, 1.0), 8, true)
		"flowers":
			for k in 14:
				var a3 := k * 2.4
				var r := 1.0 + k * 0.4
				var col := [Color(1.0, 0.45, 0.6), Color(1.0, 0.85, 0.3), Color(0.7, 0.55, 1.0), Color(1.0, 0.6, 0.3)][k % 4] as Color
				b.cylinder(0.08, 0.08, 1.4, MeshKit.at(Vector3(cos(a3) * r, 0.7, sin(a3) * r)), Color(0.3, 0.7, 0.3), 5)
				b.sphere(0.5, MeshKit.at(Vector3(cos(a3) * r, 1.5, sin(a3) * r)), col, 8)
		"slide":
			b.box(Vector3(2.5, 6.0, 2.5), MeshKit.at(Vector3(-4.0, 3.0, 0)), Color(1.0, 0.75, 0.3))
			b.box(Vector3(2.2, 0.4, 10.0), MeshKit.at(Vector3(0.5, 3.0, 0), Vector3.ONE, Vector3(0, PI * 0.5, 0.55)), Color(0.4, 0.75, 1.0))
		"rainbow":
			var cols := [Color(1.0, 0.35, 0.35), Color(1.0, 0.65, 0.3), Color(1.0, 0.9, 0.35), Color(0.45, 0.9, 0.45), Color(0.4, 0.65, 1.0), Color(0.7, 0.5, 1.0)]
			for k in cols.size():
				b.torus(9.0 - k * 0.6, 0.3, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), cols[k], 28, 5, true)
	return b.build()
