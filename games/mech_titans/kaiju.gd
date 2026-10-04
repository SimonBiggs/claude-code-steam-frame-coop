extends Node3D
## One kaiju (a boss from Data.KAIJU or a mini from Data.MINIS): a core/creatures.gd monster scaled up,
## glowing weak spots (paintable by the support team's target lasers: painted spots take TRIPLE beam
## damage), health, a stun meter, dizzy stars and the "going home" exit. Kid-friendly: nobody gets hurt,
## a defeated kaiju gets dizzy, then walks / swims / flies home.
## The host runs the brain (kaiju_ai.gd) and decides damage; the TV machine mirrors pack() snapshots.
## Creature convention: front = +Z, so the node's yaw is atan2(dir.x, dir.z).

const Data := preload("res://games/mech_titans/data.gd")
const Creatures := preload("res://core/creatures.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const UiKit := preload("res://core/ui_kit.gd")

## State codes (also sent in snapshots).
const STATES: Array[String] = ["enter", "roam", "windup", "attack", "recover", "stunned", "dizzy", "grabbed", "thrown", "home", "gone", "downed", "practice"]

var id := 0
var kind := "lizard"
var is_mini := false
var info: Dictionary = {}
var height := 10.0
var base_height := 1.0
var radius := 4.0
var hp := 100.0
var hp_max := 100.0
var state := "enter"
var state_t := 0.0
var stun := 0.0  ## 0..100: full = stunned for a few seconds
var fly_alt := 0.0
var alt := 0.0  ## current hover height (flying kaiju dip down when stunned / swooping)
var yaw := 0.0
var attack := ""
var attack_pos := Vector3.ZERO
var attack_dir := Vector3.FORWARD
var attack_target: Node3D
var cooldowns := {}
var phase := 1
var split_gen := 0
var shell_broken := false
var slip := 0.0
var goo := 0.0
var aggro := {}  ## source key -> amount (host)
var home_dir := Vector3.FORWARD
var hp_bar_frac := 1.0
var dizzy_wait := 0.0
var velocity := Vector3.ZERO  ## knockback / thrown motion
var can_punch := true  ## flying kaiju high up can't be punched
var high := false
var mega_shield := false  ## mega phase 1: armoured until both crystals break

## {name, pos (model space), r, hp, hp_max, painted (seconds left), broken, node, ring, tag}
var weak: Array[Dictionary] = []
var model: Node3D
var anim: Node
var dizzy_ring: Node3D
var _ground_marker: MeshInstance3D
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _has_net := false
var _t := 0.0
var _hit_shake := 0.0
var _glow_mat: StandardMaterial3D
var _paint_mat: StandardMaterial3D
var _broken_mat: StandardMaterial3D
var _practice_fx: Node3D  ## PRACTICE: a glowing target ring + arrow (every machine, lazily)


## Build the body. k: a Data.KAIJU or Data.MINIS key.
func setup(p_id: int, k: String, p_split_gen: int = 0) -> void:
	id = p_id
	kind = k
	split_gen = p_split_gen
	is_mini = Data.MINIS.has(k)
	info = Data.MINIS[k] if is_mini else Data.KAIJU[k]
	name = "Kaiju%d" % id
	height = float(info["height"])
	if kind == "jelly" and split_gen > 0:
		height *= pow(0.66, split_gen)
	hp_max = float(info["hp"])
	if kind == "jelly" and split_gen > 0:
		hp_max = float(info["hp"]) * pow(0.55, split_gen)
	hp = hp_max
	fly_alt = float(info.get("fly", 0.0))
	alt = fly_alt
	var opts := {"color": info["color"], "lod": "far" if is_mini else "near"}
	if info.has("color2"):
		opts["color2"] = info["color2"]
	if info.has("eye"):
		opts["eye_color"] = info["eye"]
	if bool(info.get("boss", false)):
		opts["boss"] = true
	model = Creatures.monster(String(info["monster"]), opts)
	add_child(model)
	anim = Creatures.anim(model)
	if fly_alt > 0.0 and anim != null:
		anim.set("flying", true)
	base_height = maxf(0.2, Creatures.height_of(model))
	var sc := height / base_height
	model.scale = Vector3.ONE * sc
	radius = height * (0.42 if not is_mini else 0.5)
	if String(info["monster"]) == "crab" or String(info["monster"]) == "bee":
		radius = height * 0.75
	if String(info["monster"]) == "fish":
		radius = height * 0.7
	mega_shield = kind == "mega"
	_glow_mat = MeshKit.material(Color(1.0, 0.85, 0.3), 3.0)
	_paint_mat = MeshKit.material(Color(1.0, 0.25, 0.2), 4.0)
	_broken_mat = MeshKit.material(Color(0.35, 0.33, 0.38))
	if not is_mini:
		for w in info["weak"]:
			var arr: Array = w
			_add_weak(String(arr[0]), arr[1], float(arr[2]), float(arr[3]))
	if kind == "mega":
		for w2 in weak:
			if String(w2["name"]) == "MEGA CORE":
				w2["broken"] = true  # opens in phase 3 (bosses.gd)
				(w2["node"] as Node3D).visible = false
	_build_dizzy()
	# Ground shadow marker for flyers (helps everyone judge where it is).
	if fly_alt > 0.0:
		_ground_marker = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = radius * 0.7
		cm.bottom_radius = radius * 0.7
		cm.height = 0.05
		cm.radial_segments = 20
		cm.rings = 1
		_ground_marker.mesh = cm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0, 0, 0, 0.3)
		_ground_marker.material_override = m
		_ground_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ground_marker.top_level = true
		add_child(_ground_marker)


func _add_weak(wname: String, frac: Vector3, rfrac: float, whp: float) -> void:
	var holder := Node3D.new()
	holder.name = "Weak%d" % weak.size()
	var body := model.get_node_or_null("Model") as Node3D
	(body if body != null else model).add_child(holder)  # model space: scaled with the body, bobs with it
	holder.position = frac * base_height
	var r := rfrac * base_height
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = _glow_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r * 1.6
	tm.outer_radius = r * 1.9
	tm.rings = 16
	tm.ring_segments = 4
	ring.mesh = tm
	ring.material_override = _paint_mat
	ring.rotation.x = PI * 0.5
	ring.visible = false
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(ring)
	var tag := Label3D.new()
	tag.text = "x3"
	tag.font_size = 72
	tag.pixel_size = 1.6 / 72.0 / maxf(model.scale.x, 0.001)
	tag.outline_size = 18
	tag.modulate = Color(1.0, 0.5, 0.35)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.layers = Data.LAYER_TV_ONLY
	tag.position = Vector3(0, r * 2.6, 0)
	tag.visible = false
	holder.add_child(tag)
	weak.append({"name": wname, "pos": frac * base_height, "r": r, "hp": whp, "hp_max": whp, "painted": 0.0,
		"broken": false, "node": holder, "mesh": mi, "ring": ring, "tag": tag})


func _build_dizzy() -> void:
	dizzy_ring = Node3D.new()
	dizzy_ring.name = "Dizzy"
	add_child(dizzy_ring)
	var star := MeshKit.prop("star")
	for k in 5:
		var s := MeshInstance3D.new()
		s.mesh = star
		s.material_override = MeshKit.material(Color(1.0, 0.88, 0.3), 2.0)
		var a := k * TAU / 5.0
		var rr := maxf(radius * 0.55, 1.2)
		s.position = Vector3(cos(a) * rr, 0, sin(a) * rr)
		s.scale = Vector3.ONE * maxf(1.4, height * 0.22)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dizzy_ring.add_child(s)
	dizzy_ring.visible = false


# --- Queries (every machine) ---------------------------------------------------------------------------

## Centre of the body in world space (what the beam / autopilot aims at).
func center() -> Vector3:
	return global_position + Vector3(0, height * 0.45, 0)


func aim_point() -> Vector3:
	var best := -1
	for i in weak.size():
		var w: Dictionary = weak[i]
		if bool(w["broken"]):
			continue
		if best < 0 or float(w["painted"]) > float(weak[best]["painted"]):
			best = i
	if best >= 0:
		return weak_world(best)
	return center()


func weak_world(i: int) -> Vector3:
	var n: Node3D = weak[i]["node"]
	return n.global_position


## World radius of weak spot i (generous: kids aim with lasers and beams).
func weak_radius(i: int) -> float:
	return float(weak[i]["r"]) * model.scale.x


## Ray test against the body (3 spheres up the middle) and weak spots. Returns {t, weak (-1 = body)} or {}.
## assist widens the weak-spot spheres (target lasers snap onto them).
func ray(from: Vector3, dir: Vector3, max_d: float, assist: float = 1.0) -> Dictionary:
	if state == "gone" or state == "home":
		return {}
	var best := INF
	var which := -2
	for i in weak.size():
		var w: Dictionary = weak[i]
		if bool(w["broken"]):
			continue
		var t := _ray_sphere(from, dir, weak_world(i), weak_radius(i) * 1.5 * assist)
		if t < best:
			best = t
			which = i
	var base := global_position
	for k in 3:
		var c := base + Vector3(0, height * (0.25 + k * 0.25), 0)
		var r := radius * (0.85 if k == 1 else 0.7)
		var t2 := _ray_sphere(from, dir, c, r)
		if t2 < best - 0.6:  # weak spots win when they're right on the surface
			best = t2
			which = -1
	if best > max_d or which == -2:
		return {}
	return {"t": best, "weak": which}


static func _ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var cc := oc.dot(oc) - r * r
	var disc := b * b - cc
	if disc < 0.0:
		return INF
	var s := sqrt(disc)
	var t := -b - s
	if t < 0.0:
		t = -b + s
	return t if t >= 0.0 else INF


## Is world point p touching the body (punch reach)? Returns the distance outside the body (<= 0 inside).
func surface_distance(p: Vector3) -> float:
	var base := global_position
	var best := INF
	for k in 3:
		var c := base + Vector3(0, height * (0.25 + k * 0.25), 0)
		var r := radius * (0.85 if k == 1 else 0.7)
		best = minf(best, p.distance_to(c) - r)
	return best


## The weak spot closest to p within `within` metres, or -1.
func weak_near(p: Vector3, within: float) -> int:
	var best := -1
	var bd := within
	for i in weak.size():
		if bool(weak[i]["broken"]):
			continue
		var d := p.distance_to(weak_world(i)) - weak_radius(i)
		if d < bd:
			bd = d
			best = i
	return best


func is_active() -> bool:
	return state != "home" and state != "gone" and state != "dizzy" and state != "grabbed" and state != "thrown"


func is_defeated() -> bool:
	return state == "dizzy" or state == "home" or state == "gone" or state == "grabbed" or state == "thrown"


func any_painted() -> bool:
	for w in weak:
		if float(w["painted"]) > 0.0 and not bool(w["broken"]):
			return true
	return false


# --- State changes (host) ---------------------------------------------------------------------------------

func set_state(s: String) -> void:
	state = s
	state_t = 0.0


func paint(i: int, seconds: float) -> bool:
	if i < 0 or i >= weak.size() or bool(weak[i]["broken"]):
		return false
	var was: bool = float(weak[i]["painted"]) > 0.0
	weak[i]["painted"] = maxf(float(weak[i]["painted"]), seconds)
	return not was


## Face a world direction smoothly (creatures face +Z).
func face_dir(dir: Vector3, delta: float, rate: float = 3.0) -> void:
	if Vector2(dir.x, dir.z).length() < 0.01:
		return
	var target := atan2(dir.x, dir.z)
	yaw = lerp_angle(yaw, target, 1.0 - exp(-rate * delta))
	rotation.y = yaw


# --- Visual update (every machine) -----------------------------------------------------------------------

func visual_tick(delta: float) -> void:
	_t += delta
	for i in weak.size():
		var w: Dictionary = weak[i]
		var painted: bool = float(w["painted"]) > 0.0
		var broken: bool = w["broken"]
		var mesh: MeshInstance3D = w["mesh"]
		var ring: MeshInstance3D = w["ring"]
		var tag: Label3D = w["tag"]
		(w["node"] as Node3D).visible = not (broken and String(w["name"]) == "MEGA CORE")  # opens in phase 3
		mesh.material_override = _broken_mat if broken else (_paint_mat if painted else _glow_mat)
		var pulse := 1.0 + 0.15 * sin(_t * (12.0 if painted else 4.0) + i)
		mesh.scale = Vector3.ONE * (0.6 if broken else pulse * (1.25 if painted else 1.0))
		ring.visible = painted and not broken
		tag.visible = painted and not broken
		if ring.visible:
			ring.rotation.z += delta * 3.0
			ring.scale = Vector3.ONE * (1.0 + 0.2 * sin(_t * 10.0))
		if painted and simulate_paint_decay:
			w["painted"] = maxf(0.0, float(w["painted"]) - delta)
	_tick_practice(delta)
	var dz := state == "dizzy" or state == "stunned" or state == "downed" or state == "grabbed"
	dizzy_ring.visible = dz
	if dz:
		dizzy_ring.position = Vector3(0, height * 1.02, 0)
		dizzy_ring.rotation.y += delta * 3.0
	if _ground_marker != null:
		_ground_marker.global_position = Vector3(global_position.x, 0.2, global_position.z)
		_ground_marker.visible = state != "gone"
	if _hit_shake > 0.0:
		_hit_shake = maxf(0.0, _hit_shake - delta * 4.0)
		model.position = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * _hit_shake * 0.3 + Vector3(0, model.position.y, 0)
	else:
		model.position.x = 0.0
		model.position.z = 0.0


## PRACTICE targets (missions.gd's warm-up): a big glowing ring that faces the Titan and a bouncing
## arrow above, so the pilot sees what to hit without reading anything.
func _tick_practice(_delta: float) -> void:
	var on := state == "practice"
	if not on:
		if _practice_fx != null:
			_practice_fx.visible = false
		return
	if _practice_fx == null:
		_practice_fx = Node3D.new()
		add_child(_practice_fx)
		var mat := MeshKit.material(Color(0.35, 1.0, 0.55), 3.0)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = height * 0.62
		tm.outer_radius = height * 0.74
		tm.rings = 24
		tm.ring_segments = 8
		ring.mesh = tm
		ring.material_override = mat
		ring.rotation.x = PI * 0.5  # stands up, facing +Z (the kaiju faces the Titan)
		ring.name = "Ring"
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_practice_fx.add_child(ring)
		var arrow := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = height * 0.3
		cm.bottom_radius = 0.0
		cm.height = height * 0.45
		cm.radial_segments = 12
		cm.rings = 1
		arrow.mesh = cm
		arrow.material_override = mat
		arrow.name = "Arrow"
		arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_practice_fx.add_child(arrow)
	_practice_fx.visible = true
	_practice_fx.position = Vector3(0, height * 0.45, 0)
	var ring2: Node3D = _practice_fx.get_node("Ring")
	ring2.scale = Vector3.ONE * (1.0 + 0.12 * sin(_t * 6.0))
	var arrow2: Node3D = _practice_fx.get_node("Arrow")
	arrow2.position = Vector3(0, height * (1.05 + 0.15 * absf(sin(_t * 4.0))), 0)


## Painted timers count down on the host (the TV machine gets them in snapshots).
var simulate_paint_decay := true


## A hit reaction: flash, shake (and the creature's own hurt animation).
func hit_fx(color: Color = Color(1, 1, 1), from_dir: Vector3 = Vector3.ZERO) -> void:
	_hit_shake = 1.0
	if anim != null:
		if state == "windup" or state == "attack":
			anim.call("flash", color, 0.2)
		else:
			anim.call("hurt", color, from_dir)


# --- Networking ---------------------------------------------------------------------------------------

## 12 floats: id, kind index, split gen, x, y, z, yaw, hp frac (0..255), state, flags, phase, stun.
func pack() -> PackedFloat32Array:
	var flags := 0
	for i in mini(weak.size(), 4):
		var w: Dictionary = weak[i]
		if float(w["painted"]) > 0.0:
			flags |= 1 << i
		if bool(w["broken"]):
			flags |= 1 << (i + 4)
	if shell_broken:
		flags |= 256
	if mega_shield:
		flags |= 512
	return PackedFloat32Array([float(id), float(kind_index(kind)), float(split_gen), snappedf(position.x, 0.02),
		snappedf(position.y, 0.02), snappedf(position.z, 0.02), snappedf(yaw, 0.002), roundf(hp / maxf(hp_max, 1.0) * 255.0),
		float(STATES.find(state)), float(flags), float(phase), roundf(stun)])


func apply_pack(a: PackedFloat32Array, o: int) -> void:
	var pos := Vector3(a[o + 3], a[o + 4], a[o + 5])
	if not _has_net:
		_has_net = true
		position = pos
		yaw = a[o + 6]
	_net_pos = pos
	_net_yaw = a[o + 6]
	hp = a[o + 7] / 255.0 * hp_max
	var si := int(a[o + 8])
	var new_state := STATES[si] if si >= 0 and si < STATES.size() else "roam"
	if new_state != state:
		state = new_state
		state_t = 0.0
	var flags := int(a[o + 9])
	for i in mini(weak.size(), 4):
		weak[i]["painted"] = 1.0 if (flags & (1 << i)) != 0 else 0.0
		weak[i]["broken"] = (flags & (1 << (i + 4))) != 0
	shell_broken = (flags & 256) != 0
	mega_shield = (flags & 512) != 0
	phase = int(a[o + 10])
	stun = a[o + 11]


## TV machine, every frame: glide to the snapshot pose and animate.
func client_tick(delta: float) -> void:
	var before := position
	var k := 1.0 - exp(-10.0 * delta)
	position = position.lerp(_net_pos, k)
	yaw = lerp_angle(yaw, _net_yaw, k)
	rotation.y = yaw
	if anim != null:
		var moved := Vector2(position.x - before.x, position.z - before.z).length() / maxf(delta, 0.001)
		anim.call("walk", moved / maxf(model.scale.x, 0.01) if moved > 0.5 else 0.0)
		if state == "dizzy" or state == "downed":
			if not bool(anim.call("is_down")) and state == "downed":
				anim.call("faint")
		elif bool(anim.call("is_down")):
			anim.call("revive")
	visual_tick(delta)


static func kind_index(k: String) -> int:
	var all := all_kinds()
	return all.find(k)


static func all_kinds() -> Array[String]:
	var out: Array[String] = []
	for k in Data.KAIJU:
		out.append(String(k))
	for k in Data.MINIS:
		out.append(String(k))
	return out
