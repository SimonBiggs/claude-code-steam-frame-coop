extends Node3D
## MECH TITANS support team: the TV players' vehicles (SKY JET, RESCUE TRUCK, REPAIR DRONE, STUN TANK),
## AI vehicles that fill in when few (or no) TV players are there, and the citizens waiting for rescue.
## - Which vehicle each seat drives is in the net store ("veh": {id: kind}); ids 1..6 are TV seats,
##   AI_BASE.. are AI units (host decides). Every machine builds the same vehicles from it.
## - A seat's own vehicle moves on the machine its pad is on (instant), and its position / aim go to
##   the host with net.send_state(pos, aim_yaw, aim_pitch). Held buttons (A = action, X = target laser)
##   go to the host with net.request("hold"). The host decides every effect (combat.gd).
## - Citizens: groups waiting at city.rescue_spots (state per group in the store "cit": 0 waiting,
##   1 riding in a truck, 2 safe). Trucks pick them up by driving close, and drop them at a shelter.

const Data := preload("res://games/mech_titans/data.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Creatures := preload("res://core/creatures.gd")
const HudKit := preload("res://core/hud_kit.gd")
const Kaiju := preload("res://games/mech_titans/kaiju.gd")
const City := preload("res://games/mech_titans/city.gd")

const AI_BASE := 11
const ROADS: Array[float] = [-65.0, -39.0, -13.0, 13.0, 39.0, 65.0]
const PICKUP_R := 8.0
const SHELTER_R := 9.0
const TRUCK_CAP := 2  ## groups per trip
const PAINT_TIME := 6.0


## One support vehicle (every machine).
class Vehicle extends Node3D:
	var id := 0
	var kind := "jet"
	var ai := false
	var aim_yaw := 0.0
	var aim_pitch := 0.0
	var hold_a := false
	var hold_x := false
	var boost := 0.0
	var spin := 0.0
	var carry := 0  ## citizen groups on board (trucks)
	var cool := 0.0
	var vel := Vector3.ZERO
	var hop := 0.0
	var face := 0.0
	var model: Node3D
	var laser: MeshInstance3D
	var spray: CPUParticles3D
	var carry_sign: Label3D
	var net_pos := Vector3.ZERO
	var has_net := false
	var paint_hits := 0
	var ai_t := 0.0
	var ai_goal := Vector3.ZERO

	func aim_dir() -> Vector3:
		return Vector3(-sin(aim_yaw) * cos(aim_pitch), sin(aim_pitch), -cos(aim_yaw) * cos(aim_pitch))

	func pivot() -> Vector3:
		return global_position + Vector3(0, 2.5, 0)

	func flyer() -> bool:
		return bool(Data.VEHICLE_INFO[kind]["fly"])


var main: Node
var city: City
var vehicles := {}  ## id -> Vehicle
var groups: Array[Dictionary] = []  ## {pos, state, node}
var _hold_sent := {}  ## TV machine: slot -> [a, x] last sent
var _send_t := 0.0
var _fire_t := {}  ## building -> hose seconds
var _repair_fx_t := 0.0
var _t := 0.0


func setup(p_main: Node, p_city: City) -> void:
	main = p_main
	city = p_city


func vehicle(id: int) -> Vehicle:
	return vehicles.get(id, null)


func is_flyer(v: Node3D) -> bool:
	return (v as Vehicle).flyer()


# --- Building vehicles from the store ---------------------------------------------------------------

## Every machine: make the vehicles match {id: kind}.
func sync(veh: Dictionary) -> void:
	for id in vehicles.keys():
		if not veh.has(id) and not veh.has(str(id)):
			(vehicles[id] as Node).queue_free()
			vehicles.erase(id)
	for key in veh:
		var id := int(key)
		var kind := String(veh[key])
		var v: Vehicle = vehicles.get(id, null)
		if v != null and v.kind == kind:
			continue
		var at := _spawn_point(id, kind)
		if v != null:
			at = Vector3(v.global_position.x, 0, v.global_position.z)
			v.queue_free()
		v = _make(id, kind)
		v.position = at + Vector3(0, float(Data.VEHICLE_INFO[kind]["alt"]), 0)
		vehicles[id] = v
		main.on_vehicle_made(id, v)


func _spawn_point(id: int, kind: String) -> Vector3:
	var a := float(id) * 1.1
	var base := Vector3(0, 0, Data.MECH_START.z - 6.0)
	if kind == "truck" or kind == "tank":
		base = Vector3(-13.0 if id % 2 == 0 else 13.0, 0, 30.0 + float(id % 4) * 4.0)
		return base
	return base + Vector3(cos(a) * 10.0, 0, sin(a) * 4.0)


func _make(id: int, kind: String) -> Vehicle:
	var v := Vehicle.new()
	v.id = id
	v.kind = kind
	v.ai = id >= AI_BASE
	v.name = "Vehicle%d" % id
	add_child(v)
	v.model = Node3D.new()
	v.add_child(v.model)
	var color: Color = Data.VEHICLE_INFO[kind]["color"]
	if not v.ai:
		color = main.party.color_of(id).lerp(color, 0.35)
	v.model.add_child(MeshKit.instance(_mesh(kind, color)))
	# Target laser (everyone sees it), spray for hose / repair.
	v.laser = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.08
	cm.bottom_radius = 0.08
	cm.height = 1.0
	cm.radial_segments = 4
	cm.rings = 1
	v.laser.mesh = cm
	v.laser.material_override = MeshKit.material(Color(1.0, 0.2, 0.15), 4.0)
	v.laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.laser.top_level = true
	v.laser.visible = false
	v.add_child(v.laser)
	if kind == "truck" or kind == "drone":
		v.spray = CPUParticles3D.new()
		v.spray.amount = 32
		v.spray.lifetime = 0.7
		v.spray.emitting = false
		v.spray.local_coords = false
		v.spray.spread = 6.0
		v.spray.initial_velocity_min = 16.0 if kind == "truck" else 8.0
		v.spray.initial_velocity_max = 22.0 if kind == "truck" else 12.0
		v.spray.gravity = Vector3(0, -9.0 if kind == "truck" else 0.0, 0)
		var sm := SphereMesh.new()
		sm.radius = 0.25
		sm.height = 0.5
		sm.radial_segments = 6
		sm.rings = 3
		sm.material = MeshKit.material(Color(0.5, 0.8, 1.0) if kind == "truck" else Color(0.5, 1.0, 0.6), 1.5)
		v.spray.mesh = sm
		v.add_child(v.spray)
		v.spray.position = Vector3(0, 2.4, -1.6) if kind == "truck" else Vector3(0, -0.6, -0.8)
	if kind == "truck":
		v.carry_sign = Label3D.new()
		v.carry_sign.font_size = 64
		v.carry_sign.pixel_size = 0.02
		v.carry_sign.outline_size = 18
		v.carry_sign.modulate = Color(0.6, 1.0, 0.7)
		v.carry_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		v.carry_sign.layers = Data.LAYER_TV_ONLY
		v.carry_sign.position = Vector3(0, 4.2, 0)
		v.carry_sign.visible = false
		v.add_child(v.carry_sign)
	if not v.ai:
		HudKit.nameplate(v, main.party.name_of(id), id, 4.0 if kind != "drone" else 2.6, 0.9).layers = Data.LAYER_TV_ONLY
	return v


func _mesh(kind: String, c: Color) -> ArrayMesh:
	return ResCache.get_or_make("mt_veh_%s_%s_v1" % [kind, c.to_html(false)], func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		var dark := Color(0.25, 0.27, 0.32)
		var glass := Color(0.35, 0.65, 0.95)
		var white := Color(0.95, 0.95, 0.97)
		match kind:
			"jet":
				b.capsule(0.7, 5.0, MeshKit.at(Vector3(0, 0, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), c, 12)
				b.cone(0.7, 1.4, MeshKit.at(Vector3(0, 0, -3.1), Vector3.ONE, Vector3(-PI * 0.5, 0, 0)), white, 12)
				b.ellipsoid(Vector3(0.5, 0.45, 1.1), MeshKit.at(Vector3(0, 0.55, -1.2)), glass, 10)
				b.box(Vector3(6.4, 0.18, 1.6), MeshKit.at(Vector3(0, -0.1, 0.4)), c.darkened(0.1))
				b.box(Vector3(2.4, 0.15, 0.9), MeshKit.at(Vector3(0, 0.1, 2.3)), c.darkened(0.1))
				b.box(Vector3(0.15, 1.3, 1.0), MeshKit.at(Vector3(0, 0.8, 2.3)), white)
				b.cylinder(0.45, 0.5, 0.4, MeshKit.at(Vector3(0, 0, 2.7), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.6, 0.3), 10, true)
				for sx in [-1.0, 1.0]:
					b.sphere(0.15, MeshKit.at(Vector3(sx * 3.2, -0.1, 0.4)), Color(1.0, 0.3, 0.3) if sx < 0 else Color(0.3, 1.0, 0.4), 6, true)
			"truck":
				b.rounded_box(Vector3(2.4, 1.0, 5.2), 0.2, MeshKit.at(Vector3(0, 0.95, 0)), white)
				b.rounded_box(Vector3(2.3, 1.4, 1.8), 0.25, MeshKit.at(Vector3(0, 2.0, -1.5)), c)
				b.box(Vector3(2.0, 0.6, 0.1), MeshKit.at(Vector3(0, 2.2, -2.42)), glass)
				b.rounded_box(Vector3(2.3, 1.6, 3.1), 0.2, MeshKit.at(Vector3(0, 2.05, 1.0)), c)
				b.box(Vector3(0.5, 1.4, 0.06), MeshKit.at(Vector3(0, 2.05, 2.56)), white)
				b.box(Vector3(1.4, 0.45, 0.06), MeshKit.at(Vector3(0, 2.05, 2.57)), white)
				b.cylinder(0.18, 0.18, 2.6, MeshKit.at(Vector3(0, 3.0, -0.2), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), dark, 8)
				b.box(Vector3(1.2, 0.25, 0.4), MeshKit.at(Vector3(0, 2.85, -1.5)), Color(0.3, 0.6, 1.0), true)
				for sx in [-1.0, 1.0]:
					for z in [-1.6, 1.6]:
						b.cylinder(0.55, 0.55, 0.4, MeshKit.at(Vector3(sx * 1.15, 0.55, z), Vector3.ONE, Vector3(0, 0, PI * 0.5)), dark, 10)
			"drone":
				b.ellipsoid(Vector3(1.0, 0.6, 1.0), MeshKit.at(Vector3.ZERO), white, 12)
				b.ellipsoid(Vector3(0.75, 0.4, 0.75), MeshKit.at(Vector3(0, 0.3, 0)), c, 12)
				b.sphere(0.3, MeshKit.at(Vector3(0, -0.1, -0.85)), glass, 8, true)
				for k in 4:
					var a := k * TAU / 4.0 + PI * 0.25
					var p := Vector3(cos(a) * 1.6, 0.2, sin(a) * 1.6)
					b.tube(Vector3(0, 0.1, 0), p, 0.1, 0.1, dark)
					b.cylinder(0.75, 0.75, 0.08, MeshKit.at(p + Vector3(0, 0.15, 0)), Color(c.r, c.g, c.b).lightened(0.4), 12)
				b.box(Vector3(0.7, 0.15, 0.2), MeshKit.at(Vector3(0, 0.62, 0)), Color(1.0, 0.3, 0.3), true)
				b.box(Vector3(0.2, 0.15, 0.7), MeshKit.at(Vector3(0, 0.62, 0)), Color(1.0, 0.3, 0.3), true)
			"tank":
				b.rounded_box(Vector3(3.0, 1.0, 4.4), 0.25, MeshKit.at(Vector3(0, 0.8, 0)), c)
				for sx in [-1.0, 1.0]:
					b.rounded_box(Vector3(0.8, 0.9, 4.6), 0.35, MeshKit.at(Vector3(sx * 1.55, 0.5, 0)), dark)
				b.dome(1.2, MeshKit.at(Vector3(0, 1.3, 0.3)), c.lightened(0.15), 12)
				b.cylinder(0.25, 0.3, 3.0, MeshKit.at(Vector3(0, 1.9, -1.4), Vector3.ONE, Vector3(-PI * 0.5 + 0.35, 0, 0)), dark, 10)
				b.sphere(0.32, MeshKit.at(Vector3(0, 2.4, -2.8)), Color(0.75, 0.6, 1.0), 8, true)
				b.star(5, 0.45, 0.2, 0.08, MeshKit.at(Vector3(0, 1.32, 1.6), Vector3.ONE, Vector3(-PI * 0.5, 0, 0)), Color(1.0, 0.9, 0.4))
		return b.build())


# --- Citizens -------------------------------------------------------------------------------------------

## Every machine: build `count` citizen groups for this mission.
func build_citizens(count: int) -> void:
	for g in groups:
		var n: Node = g["node"]
		if is_instance_valid(n):
			n.queue_free()
	groups.clear()
	for i in mini(count, city.rescue_spots.size()):
		var p: Vector3 = city.rescue_spots[i]
		var node := Node3D.new()
		node.name = "Citizens%d" % i
		add_child(node)
		node.position = p
		for k in 3:
			var h := Creatures.humanoid({"class": ["villager", "chef", "farmer", "scientist", "detective"][(i + k) % 5], "seed": i * 7 + k, "lod": "far"})
			h.scale = Vector3.ONE * 0.6
			h.position = Vector3((k - 1) * 0.8, 0, (k % 2) * 0.5)
			node.add_child(h)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 2.6
		tm.outer_radius = 3.0
		tm.rings = 20
		tm.ring_segments = 4
		ring.mesh = tm
		ring.material_override = MeshKit.material(Color(0.4, 1.0, 0.5), 2.0)
		ring.scale = Vector3(1, 0.2, 1)
		ring.position.y = 0.15
		ring.name = "Ring"
		node.add_child(ring)
		var sign := Label3D.new()
		sign.text = "HELP!"
		sign.font_size = 72
		sign.pixel_size = 0.02
		sign.outline_size = 18
		sign.modulate = Color(1.0, 0.95, 0.5)
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.layers = Data.LAYER_TV_ONLY
		sign.position = Vector3(0, 2.6, 0)
		node.add_child(sign)
		groups.append({"pos": p, "state": 0, "node": node})


func citizen_states() -> PackedByteArray:
	var out := PackedByteArray()
	for g in groups:
		out.append(int(g["state"]))
	return out


## Every machine: show group states from the store.
func apply_citizens(bytes: PackedByteArray) -> void:
	for i in mini(bytes.size(), groups.size()):
		groups[i]["state"] = bytes[i]
		var n: Node3D = groups[i]["node"]
		n.visible = bytes[i] == 0


func waiting_groups() -> int:
	var n := 0
	for g in groups:
		if int(g["state"]) == 0:
			n += 1
	return n


func rescued_groups() -> int:
	var n := 0
	for g in groups:
		if int(g["state"]) == 2:
			n += 1
	return n


# --- Local driving (the machine a seat's pad is on) ------------------------------------------------------

## Drive this machine's seats' vehicles (TV machine and local play), camera-relative.
func drive_local(delta: float, can_act: bool) -> void:
	_send_t -= delta
	var send := _send_t <= 0.0
	if send:
		_send_t = 1.0 / 30.0
	for slot in main.party.local_slots():
		var v: Vehicle = vehicles.get(slot, null)
		if v == null:
			continue
		var cam: Camera3D = main.view_camera(slot)
		var busy: bool = main.slot_busy(slot) or not can_act
		var mv: Vector2 = Vector2.ZERO if busy else main.party.stick(slot, "move")
		if cam != null:
			var d := -cam.global_basis.z
			v.aim_yaw = atan2(-d.x, -d.z)
			v.aim_pitch = asin(clampf(d.y, -1.0, 1.0))
			if v.kind == "tank":
				v.aim_pitch += 0.25  # lob: the shell arcs to the crosshair
		var f := Vector3(-sin(v.aim_yaw), 0, -cos(v.aim_yaw))
		var r := Vector3(-f.z, 0, f.x)
		var want := (r * mv.x - f * mv.y)
		if not busy and main.party.just_pressed(slot, "b"):
			v.boost = 1.2
			main.sfx.play("dash", -4.0, 1.2 if v.flyer() else 0.8)
			if v.kind == "tank":
				v.hop = 1.0
		move_vehicle(v, want, delta)
		var a: bool = false if busy else main.party.pressed(slot, "accept")
		var x: bool = false if busy else main.party.pressed(slot, "x")
		if main.net.mode == "client":
			var last: Array = _hold_sent.get(slot, [false, false])
			if bool(last[0]) != a or bool(last[1]) != x:
				_hold_sent[slot] = [a, x]
				main.net.request(slot, "hold", [a, x])
			v.hold_a = a
			v.hold_x = x
			if send:
				main.net.send_state(v.global_position, v.aim_yaw, v.aim_pitch, slot)
			if a and v.kind == "jet" and v.spin <= 0.0:
				_local_jet_tracer(v, delta)
		else:
			v.hold_a = a
			v.hold_x = x
		if not busy and main.party.just_pressed(slot, "y"):
			main.net.request(slot, "vehicle_next", [])


## Move with the vehicle's handling (shared by players and AI).
func move_vehicle(v: Vehicle, want: Vector3, delta: float) -> void:
	var info: Dictionary = Data.VEHICLE_INFO[v.kind]
	v.boost = maxf(0.0, v.boost - delta)
	if v.spin > 0.0:
		v.spin = maxf(0.0, v.spin - delta)
		want = Vector3.ZERO
		v.model.rotation.y += delta * 14.0
	if want.length() > 1.0:
		want = want.normalized()
	var spd: float = float(info["speed"]) * (1.7 if v.boost > 0.0 else 1.0) * (0.8 if v.ai else 1.0)
	v.vel = v.vel.lerp(want * spd, 1.0 - exp(-(3.0 if v.flyer() else 5.0) * delta))
	var p := v.global_position + v.vel * delta
	p.x = clampf(p.x, -Data.MAP + 2.0, Data.MAP - 2.0)
	p.z = clampf(p.z, -Data.MAP + 2.0, Data.MAP - 2.0)
	if not v.flyer():
		p = city.push_out(p, 1.8)
		v.hop = maxf(0.0, v.hop - delta)
		p.y = sin(v.hop * PI) * 6.0 if v.hop > 0.0 else 0.0
	else:
		var alt: float = info["alt"]
		p.y = lerpf(v.global_position.y, alt + sin(_t * 1.3 + v.id) * 0.4, 1.0 - exp(-3.0 * delta))
	v.global_position = p
	var flat := Vector2(v.vel.x, v.vel.z)
	if flat.length() > 0.8:
		v.face = lerp_angle(v.face, atan2(-flat.x, -flat.y), 1.0 - exp(-6.0 * delta))
	v.rotation.y = v.face
	if v.spin <= 0.0:
		var bank := 0.0
		if v.flyer():
			var side := Vector3(cos(v.face), 0, -sin(v.face))
			bank = -clampf(side.dot(v.vel) / spd, -1.0, 1.0) * (0.45 if v.kind == "jet" else 0.2)
		v.model.rotation = Vector3(0, lerp_angle(v.model.rotation.y, 0.0, 1.0 - exp(-8.0 * delta)), lerpf(v.model.rotation.z, bank, 1.0 - exp(-4.0 * delta)))


func _local_jet_tracer(v: Vehicle, _delta: float) -> void:
	v.cool -= _delta
	if v.cool > 0.0:
		return
	v.cool = 0.14
	var from := v.pivot()
	var dir := v.aim_dir()
	var hit: Dictionary = main.combat._ray_kaiju(from, dir, 90.0, 1.2)
	var to := from + dir * (float(hit["t"]) if not hit.is_empty() else 90.0)
	main.fx.tracer(v.global_position, to, Color(1.0, 0.9, 0.4))
	main.sfx.play("laser", -14.0, 1.6)


## Host: a TV seat's vehicle moved on the TV machine.
func remote_state(slot: int, pos: Vector3, yaw: float, pitch: float) -> void:
	var v: Vehicle = vehicles.get(slot, null)
	if v == null:
		return
	var d := pos - v.global_position
	if Vector2(d.x, d.z).length() > 0.05:
		v.face = lerp_angle(v.face, atan2(-d.x, -d.z), 0.3)
		v.rotation.y = v.face
	v.global_position = pos
	v.aim_yaw = yaw
	v.aim_pitch = pitch


# --- Host: actions, AI, rescues -----------------------------------------------------------------------

func tick(delta: float) -> void:
	_repair_fx_t -= delta
	for id in vehicles:
		var v: Vehicle = vehicles[id]
		if v.ai:
			_ai(v, delta)
		v.cool -= delta
		if v.spin > 0.0 and not main.party.is_local(int(id)) and not v.ai:
			v.spin = maxf(0.0, v.spin - delta)
		if v.spin > 0.0:
			continue
		if v.hold_x:
			_laser(v)
		if v.hold_a:
			_action(v, delta)
		if v.kind == "truck":
			_rescue(v)


func _laser(v: Vehicle) -> void:
	if Data.SIMPLE_MODE:
		return  # SIMPLE_MODE: no weak-spot painting (it needed explaining); A is the one action
	var hit: Dictionary = main.combat._ray_kaiju(v.pivot(), v.aim_dir(), 140.0, 2.2)
	if hit.is_empty() or int(hit["weak"]) < 0:
		return
	var k: Kaiju = hit["k"]
	var wi: int = hit["weak"]
	if k.paint(wi, PAINT_TIME):
		main.combat.emit_fx("pop", [k.weak_world(wi) + Vector3.UP * 2.0, "x3!", Color(1.0, 0.45, 0.35), 3.0])
		main.combat.emit_fx("sfx", ["beep", k.weak_world(wi), 4.0, 1.4])
		main.awards.add(v.id, "assists")
		main.missions.add_score(v.id, 20, "paints")
		main.hint_vr("painted", "Red ring = weak spot! BEAM it: x3")


func _action(v: Vehicle, delta: float) -> void:
	var support_bonus: bool = main.has_upgrade("support")
	match v.kind:
		"jet":
			if v.cool > 0.0:
				return
			v.cool = 0.1 if support_bonus else 0.14
			var from := v.pivot()
			var dir := v.aim_dir()
			var hit: Dictionary = main.combat._ray_kaiju(from, dir, 90.0, 1.2)
			var to := from + dir * 90.0
			if not hit.is_empty():
				var k: Kaiju = hit["k"]
				to = from + dir * float(hit["t"])
				main.combat.damage_kaiju(k, 3.0 * (1.5 if int(hit["weak"]) >= 0 else 1.0), int(hit["weak"]), v.id, "jet")
				k.aggro["v%d" % v.id] = float(k.aggro.get("v%d" % v.id, 0.0)) + 1.2
				main.missions.add_score(v.id, 2, "hits")
				if randf() < 0.3:
					main.combat.emit_fx("burst", ["sparks", to, 0.8], false)
			main.combat.emit_fx("tracer", [v.global_position, to, Color(1.0, 0.9, 0.4), v.id])
			if v.ai or main.party.is_local(v.id):
				main.sfx.play_at("laser", v.global_position, -10.0, 1.6)
		"truck":
			var from2 := v.global_position + Vector3.UP * 2.5
			var dir2 := v.aim_dir()
			for i in city.burning():
				var to2 := city.building_top(i) - from2
				if to2.length() < 26.0 and Vector2(to2.x, to2.z).normalized().dot(Vector2(dir2.x, dir2.z).normalized()) > 0.75:
					_fire_t[i] = float(_fire_t.get(i, 0.0)) + delta
					if float(_fire_t[i]) > 1.0:
						_fire_t.erase(i)
						main.combat.put_out(i, v.id)
			for kid in main.combat.kaiju:
				var k2: Kaiju = main.combat.kaiju[kid]
				if k2.is_mini and k2.is_active() and (k2.center() - from2).length() < 20.0:
					k2.slip = 1.0
					main.combat.damage_kaiju(k2, 4.0 * delta, -1, v.id, "hose")
		"drone":
			var mech: Node3D = main.mech
			var heal := (13.0 if support_bonus else 9.0) * delta
			if v.global_position.distance_to(main.mech.chest_world()) < 18.0 and (main.mech.armour < main.mech.armour_max or main.mech.rebooting > 0.0):
				main.mech.repair(heal)
				main.awards.add(v.id, "healing", heal)
				if _repair_fx_t <= 0.0:
					_repair_fx_t = 0.35
					main.cockpit_sparks()
					main.combat.emit_fx("burst", ["repair", main.mech.chest_world() + (v.global_position - mech.global_position).normalized() * 3.0, 1.5])
					main.missions.add_score(v.id, 5, "repairs")
				return
			var bi := city.nearest_building(v.global_position, 18.0)
			var best := -1
			var bd := 18.0
			for i in city.buildings.size():
				var rec: Dictionary = city.buildings[i]
				if float(rec["hp"]) >= 100.0:
					continue
				var d := city.footprint_distance(i, v.global_position)
				if d < bd:
					bd = d
					best = i
			if best < 0:
				best = bi if bi >= 0 and float(city.buildings[bi]["hp"]) < 100.0 else -1
			if best >= 0:
				if city.repair_building(best, 30.0 * delta):
					main.combat.on_building_changed(best)
				main.missions.on_city_changed()
				if _repair_fx_t <= 0.0:
					_repair_fx_t = 0.4
					main.combat.emit_fx("burst", ["repair", city.building_top(best), 2.0])
					main.missions.add_score(v.id, 3, "repairs")
			elif city.landmark != null and v.global_position.distance_to(city.landmark_pos) < 22.0:
				main.missions.repair_landmark(8.0 * delta)
				if _repair_fx_t <= 0.0:
					_repair_fx_t = 0.4
					main.combat.emit_fx("burst", ["repair", city.landmark_pos + Vector3.UP * 6.0, 2.0])
		"tank":
			if v.cool > 0.0:
				return
			v.cool = 1.2 if support_bonus else 1.6
			var from3 := v.pivot()
			var dir3 := Vector3(-sin(v.aim_yaw) * cos(v.aim_pitch - 0.25), sin(v.aim_pitch - 0.25), -cos(v.aim_yaw) * cos(v.aim_pitch - 0.25))
			var hit3: Dictionary = main.combat._ray_kaiju(from3, dir3, 80.0, 1.6)
			var at := from3 + dir3 * 70.0
			if not hit3.is_empty():
				at = from3 + dir3 * float(hit3["t"])
			elif dir3.y < -0.02:
				at = from3 + dir3 * minf(-from3.y / dir3.y, 70.0)
			main.combat.emit_fx("tracer", [v.global_position + Vector3.UP * 2.4, at, Color(0.8, 0.6, 1.0), -1])
			main.combat.emit_fx("sfx", ["kick", v.global_position, 2.0, 0.6])
			var vid := v.id
			get_tree().create_timer(0.45).timeout.connect(func() -> void: _shell_lands(at, vid))


func _shell_lands(at: Vector3, by: int) -> void:
	if main.combat == null:
		return
	main.combat.emit_fx("burst", ["zap", at, 3.0])
	main.combat.emit_fx("ring", [at, 8.0, Color(0.75, 0.6, 1.0)])
	main.combat.emit_fx("sfx", ["zap", at, 6.0, 0.7])
	var stun := 55.0 if main.has_upgrade("support") else 40.0
	for kid in main.combat.kaiju:
		var k: Kaiju = main.combat.kaiju[kid]
		if not k.is_active():
			continue
		if k.surface_distance(at) < 7.0:
			if k.is_mini:
				main.combat.damage_kaiju(k, 14.0, -1, by, "shell")
			else:
				k.stun = minf(100.0, k.stun + stun)
				k.aggro["v%d" % by] = float(k.aggro.get("v%d" % by, 0.0)) + 4.0
				if k.fly_alt > 8.0 or k.stun >= 100.0:
					main.combat.stun_kaiju(k, by)
				main.missions.add_score(by, 10, "stuns")
				k.hit_fx(Color(0.7, 0.6, 1.0))


func _rescue(v: Vehicle) -> void:
	var changed := false
	if v.carry < TRUCK_CAP:
		for g in groups:
			if int(g["state"]) == 0 and Vector2(v.global_position.x - (g["pos"] as Vector3).x, v.global_position.z - (g["pos"] as Vector3).z).length() < PICKUP_R:
				g["state"] = 1
				g["truck"] = v.id
				v.carry += 1
				changed = true
				main.combat.emit_fx("sfx", ["pickup", g["pos"], 2.0, 1.2])
				main.combat.emit_fx("pop", [(g["pos"] as Vector3) + Vector3.UP * 3.0, "HOP IN!", Color(0.6, 1.0, 0.7), 2.0])
				main.hint_tv("shelter", "Take them to a green SHELTER!")
				if v.carry >= TRUCK_CAP:
					break
	if v.carry > 0:
		for s in city.shelters:
			if Vector2(v.global_position.x - s.x, v.global_position.z - s.z).length() < SHELTER_R:
				var n := 0
				for g2 in groups:
					if int(g2["state"]) == 1 and int(g2.get("truck", -1)) == v.id:
						g2["state"] = 2
						n += 1
				v.carry = 0
				changed = true
				main.combat.emit_fx("burst", ["stars", s + Vector3.UP * 3.0, 2.5])
				main.combat.emit_fx("sfx", ["cheer", s, 2.0, 1.0])
				main.combat.emit_fx("pop", [s + Vector3.UP * 5.0, "%d SAVED!" % (n * 3), Color(0.5, 1.0, 0.6), 3.0])
				main.awards.add(v.id, "rescues", n * 3)
				main.missions.add_score(v.id, 150 * n, "rescues")
				break
	if changed:
		main.missions.on_citizens_changed()


## Host: kaiju attack shapes spin vehicles around (kid-friendly: no damage).
func hit_shape(shape: Dictionary, combat: Node) -> void:
	for id in vehicles:
		var v: Vehicle = vehicles[id]
		if v.spin > 0.0:
			continue
		var p := v.global_position
		if v.flyer() and p.y > 12.0 and String(shape["kind"]) != "line":
			continue
		if bool(combat.call("_shape_hits", shape, p, 1.5)):
			spin_vehicle(int(id))


func spin_vehicle(id: int) -> void:
	var v: Vehicle = vehicles.get(id, null)
	if v == null:
		return
	if main.party.is_local(id) or v.ai:
		_apply_spin(v)
	if main.net.mode == "host" and not v.ai:
		main.net.event("spin", [id])
	main.combat.emit_fx("pop", [v.global_position + Vector3.UP * 3.0, "WHOA!", Color(1.0, 0.8, 0.4), 2.0])
	main.combat.emit_fx("sfx", ["boing", v.global_position, 0.0, 0.9])


## Any machine: a vehicle we drive got bumped by a kaiju attack.
func _apply_spin(v: Vehicle) -> void:
	v.spin = 1.4
	v.vel += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 10.0
	if main.party.is_local(v.id):
		main.party.rumble(v.id, 0.5, 0.8, 0.4)
		main.hint_tv("dizzy_vehicle", "Kaiju attacks spin you around: watch the red circles!", v.id)


func on_spin_event(id: int) -> void:
	var v: Vehicle = vehicles.get(id, null)
	if v != null and main.party.is_local(id):
		_apply_spin(v)


# --- AI support units (host) -----------------------------------------------------------------------------

func _ai(v: Vehicle, delta: float) -> void:
	v.ai_t -= delta
	var mech: Node3D = main.mech
	var goal := v.global_position
	var aim_at := Vector3.INF
	v.hold_a = false
	v.hold_x = false
	var bosses: Array = main.combat.active_bosses()
	var boss: Kaiju = null
	for b in bosses:
		var bk: Kaiju = b
		if bk.is_active() or bk.state == "dizzy":
			boss = bk
			break
	var playing: bool = main.missions.playing()
	match v.kind:
		"jet":
			var tgt: Kaiju = boss if boss != null else (main.combat.auto_target(v.global_position) as Kaiju)
			if tgt != null and playing:
				var a := _t * 0.35 + v.id
				goal = tgt.global_position + Vector3(cos(a), 0, sin(a)) * 26.0
				var wi := _unpainted_weak(tgt)
				if wi >= 0 and tgt.is_active():
					aim_at = tgt.weak_world(wi)
					v.hold_x = true
				else:
					aim_at = tgt.aim_point()
					v.hold_a = tgt.is_active()
			else:
				goal = mech.global_position + Vector3(cos(_t * 0.3) * 20.0, 0, sin(_t * 0.3) * 20.0)
		"drone":
			var hurt: bool = main.mech.armour < main.mech.armour_max * 0.92 or main.mech.rebooting > 0.0
			if hurt and playing:
				goal = mech.global_position + mech.global_basis.z * 5.0 + Vector3(0, 0, 0)
				v.hold_a = v.global_position.distance_to(main.mech.chest_world()) < 18.0
				aim_at = main.mech.chest_world()
			else:
				var bi := _damaged_building_near(mech.global_position, 45.0)
				if bi >= 0 and playing:
					goal = city.buildings[bi]["pos"]
					v.hold_a = city.footprint_distance(bi, v.global_position) < 14.0
				else:
					goal = mech.global_position + mech.global_basis.z * 8.0 + mech.global_basis.x * 6.0
		"truck":
			if v.carry > 0 and (waiting_groups() == 0 or v.carry >= TRUCK_CAP or _nearest_group(v.global_position) < 0):
				goal = _nearest_shelter(v.global_position)
			else:
				var gi := _nearest_group(v.global_position)
				if gi >= 0 and playing:
					goal = groups[gi]["pos"]
				else:
					var fires := city.burning()
					if not fires.is_empty() and playing:
						var fi: int = fires[0]
						var top := city.building_top(fi)
						goal = top + (v.global_position - top).normalized() * 14.0
						aim_at = top
						v.hold_a = v.global_position.distance_to(top) < 24.0
					else:
						goal = _nearest_shelter(v.global_position) + Vector3(8.0, 0, -6.0)
		"tank":
			var tgt2: Kaiju = boss if boss != null else null
			if tgt2 != null and tgt2.is_active() and playing:
				var to := tgt2.global_position - v.global_position
				to.y = 0.0
				goal = tgt2.global_position - to.normalized() * 30.0
				aim_at = tgt2.center() + Vector3.UP * 4.0
				v.hold_a = to.length() < 60.0 and v.ai_t <= 0.0
				if v.hold_a:
					v.ai_t = 2.4
			else:
				goal = mech.global_position + mech.global_basis.z * 14.0 - mech.global_basis.x * 8.0
	if aim_at != Vector3.INF:
		var d := (aim_at - v.pivot()).normalized()
		v.aim_yaw = atan2(-d.x, -d.z)
		v.aim_pitch = asin(clampf(d.y, -1.0, 1.0)) + (0.25 if v.kind == "tank" else 0.0)
	var want := Vector3.ZERO
	var step_to := goal if v.flyer() else _route(v.global_position, goal)
	var to2 := Vector3(step_to.x - v.global_position.x, 0, step_to.z - v.global_position.z)
	if to2.length() > 2.0:
		want = to2.normalized() * clampf(to2.length() / 8.0, 0.3, 1.0)
	move_vehicle(v, want, delta)


func _unpainted_weak(k: Kaiju) -> int:
	for i in k.weak.size():
		var w: Dictionary = k.weak[i]
		if not bool(w["broken"]) and float(w["painted"]) < 1.0:
			return i
	return -1


func _damaged_building_near(p: Vector3, r: float) -> int:
	var best := -1
	var bd := r
	for i in city.buildings.size():
		var rec: Dictionary = city.buildings[i]
		if float(rec["hp"]) >= 90.0:
			continue
		var d := city.footprint_distance(i, p)
		if d < bd:
			bd = d
			best = i
	return best


func _nearest_group(p: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in groups.size():
		if int(groups[i]["state"]) != 0:
			continue
		var d := p.distance_to(groups[i]["pos"])
		if d < bd:
			bd = d
			best = i
	return best


func _nearest_shelter(p: Vector3) -> Vector3:
	var best := city.shelters[0]
	for s in city.shelters:
		if p.distance_to(s) < p.distance_to(best):
			best = s
	return best


## Ground AI: follow the road grid when a building is in the way.
func _route(p: Vector3, goal: Vector3) -> Vector3:
	var to := Vector3(goal.x - p.x, 0, goal.z - p.z)
	var dist := to.length()
	if dist < 3.0:
		return goal
	if city.ray_hit(Vector3(p.x, 1.0, p.z), to / dist, dist) == INF:
		return goal
	var rx := _nearest_road(p.x)
	var rz := _nearest_road(p.z)
	var tx := _nearest_road(goal.x)
	var tz := _nearest_road(goal.z)
	var on_x := absf(p.x - rx) < 2.5  # on a north-south road
	var on_z := absf(p.z - rz) < 2.5  # on an east-west road
	if on_z and absf(goal.z - rz) < PICKUP_R and absf(p.x - goal.x) > 2.0:
		return Vector3(goal.x, 0, rz)  # a stop right beside the goal (citizens wait by the road)
	if on_x and absf(p.z - tz) > 2.0:
		return Vector3(rx, 0, tz)
	if on_z and absf(p.x - tx) > 2.0:
		return Vector3(tx, 0, rz)
	if on_x or on_z:
		return goal
	# Off the grid: get onto the nearest road first.
	if absf(p.x - rx) < absf(p.z - rz):
		return Vector3(rx, 0, p.z)
	return Vector3(p.x, 0, rz)


func _nearest_road(v: float) -> float:
	var best := ROADS[0]
	for r in ROADS:
		if absf(v - r) < absf(v - best):
			best = r
	return best


# --- Every machine: visuals ----------------------------------------------------------------------------

func visual_tick(delta: float) -> void:
	_t += delta
	for id in vehicles:
		var v: Vehicle = vehicles[id]
		var lasing := v.hold_x and v.spin <= 0.0
		v.laser.visible = lasing
		if lasing:
			var from := v.global_position + Vector3.UP * 1.0
			var hit: Dictionary = main.combat._ray_kaiju(v.pivot(), v.aim_dir(), 140.0, 2.2)
			var to := v.pivot() + v.aim_dir() * (float(hit["t"]) if not hit.is_empty() else 140.0)
			if not hit.is_empty() and int(hit["weak"]) >= 0:
				to = (hit["k"] as Kaiju).weak_world(int(hit["weak"]))
			var d := to - from
			v.laser.global_transform = Transform3D(_basis_y_to(d).scaled(Vector3(1, d.length(), 1)), from + d * 0.5)
		if v.spray != null:
			v.spray.emitting = v.hold_a and v.spin <= 0.0
			if v.spray.emitting:
				v.spray.direction = v.global_basis.inverse() * (v.aim_dir() if v.kind == "truck" else Vector3.DOWN)
		if v.carry_sign != null:
			v.carry_sign.visible = v.carry > 0
			v.carry_sign.text = "%d ON BOARD" % (v.carry * 3)
	for g in groups:
		if int(g["state"]) == 0:
			var n: Node3D = g["node"]
			var ring := n.get_node_or_null("Ring") as Node3D
			if ring != null:
				ring.scale = Vector3(1.0 + 0.15 * sin(_t * 4.0), 0.2, 1.0 + 0.15 * sin(_t * 4.0))
			for c in n.get_children():
				if c is Node3D and c != ring and not (c is Label3D):
					var cn := c as Node3D
					cn.position.y = maxf(0.0, sin(_t * 7.0 + cn.position.x * 3.0)) * 0.35  # jumping up and down: HELP!


static func _basis_y_to(v: Vector3) -> Basis:
	var y := v.normalized() if v.length() > 0.0001 else Vector3.UP
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


# --- Networking -------------------------------------------------------------------------------------------

## Host: 10 floats per vehicle: id, x, y, z, face, aim yaw, aim pitch, flags, carry, spin.
func pack() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for id in vehicles:
		var v: Vehicle = vehicles[id]
		var flags := (1 if v.hold_a else 0) | (2 if v.hold_x else 0) | (4 if v.boost > 0.0 else 0)
		var p := v.global_position
		out.append_array([float(id), snappedf(p.x, 0.02), snappedf(p.y, 0.02), snappedf(p.z, 0.02), snappedf(v.face, 0.01),
			snappedf(v.aim_yaw, 0.005), snappedf(v.aim_pitch, 0.005), float(flags), float(v.carry), snappedf(v.spin, 0.1)])
	return out


## TV machine: everyone else's vehicles (our own seats are driven here).
func apply(a: PackedFloat32Array) -> void:
	var o := 0
	while o + 10 <= a.size():
		var id := int(a[o])
		var v: Vehicle = vehicles.get(id, null)
		if v != null:
			v.carry = int(a[o + 8])
			if not main.party.is_local(id):
				v.net_pos = Vector3(a[o + 1], a[o + 2], a[o + 3])
				if not v.has_net:
					v.has_net = true
					v.global_position = v.net_pos
				v.face = a[o + 4]
				v.aim_yaw = a[o + 5]
				v.aim_pitch = a[o + 6]
				var flags := int(a[o + 7])
				v.hold_a = (flags & 1) != 0
				v.hold_x = (flags & 2) != 0
				v.spin = a[o + 9]
		o += 10


func client_tick(delta: float) -> void:
	for id in vehicles:
		var v: Vehicle = vehicles[id]
		if main.party.is_local(int(id)) or not v.has_net:
			continue
		v.global_position = v.global_position.lerp(v.net_pos, 1.0 - exp(-12.0 * delta))
		v.rotation.y = lerp_angle(v.rotation.y, v.face, 1.0 - exp(-10.0 * delta))
		if v.spin > 0.0:
			v.model.rotation.y += delta * 14.0
		else:
			v.model.rotation.y = 0.0
