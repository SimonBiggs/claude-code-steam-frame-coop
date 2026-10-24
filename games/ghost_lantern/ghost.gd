extends Node3D
## A mischievous ghost. Only visible inside the spirit lantern's light cone (main.ghost_material()).
## Host: simulated here (steal photos, spook players, flee the bell, get stunned and vacuumed).
## Client (`puppet`): drawn from the host's snapshots.
## Kinds: thief (bandit mask, steals photos), spooker (witch hat, says BOO), sprite (bow, fast),
## shy (only a FOCUSED beam shows it; steals photos), snuffer (always-visible snuffer hat: blows the
## lantern out), golden (rare, flees, sparkly trail, big points) and the GHOST KING (boss: crown and
## cape always visible, carries the lost photos, needs several vacuums at once).

const KINDS := {
	"thief": {"color": Color(0.55, 1.0, 0.72), "radius": 0.42, "speed": 1.7, "tough": 1.0, "points": 100},
	"spooker": {"color": Color(0.78, 0.58, 1.0), "radius": 0.55, "speed": 1.35, "tough": 1.4, "points": 150},
	"sprite": {"color": Color(1.0, 0.62, 0.9), "radius": 0.32, "speed": 2.5, "tough": 0.7, "points": 120},
	"shy": {"color": Color(0.6, 0.85, 1.0), "radius": 0.4, "speed": 1.6, "tough": 1.0, "points": 200},
	"snuffer": {"color": Color(1.0, 0.78, 0.5), "radius": 0.4, "speed": 1.9, "tough": 0.9, "points": 180},
	"golden": {"color": Color(1.0, 0.85, 0.3), "radius": 0.36, "speed": 2.9, "tough": 0.8, "points": 500},
	"king": {"color": Color(0.75, 0.9, 1.0), "radius": 0.95, "speed": 1.05, "tough": 5.0, "points": 1500},
	# Simple mode: a plain friendly ghost, the VR practice ghost (asleep, shows in the light) and the TV
	# practice ghost (always glowing, so it can be vacuumed without the lantern).
	"plain": {"color": Color(0.6, 1.0, 0.75), "radius": 0.45, "speed": 1.6, "tough": 0.8, "points": 100},
	"sleepy": {"color": Color(0.75, 0.88, 1.0), "radius": 0.45, "speed": 0.0, "tough": 0.6, "points": 0},
	"glowy": {"color": Color(0.6, 1.0, 0.75), "radius": 0.45, "speed": 0.0, "tough": 0.5, "points": 0},
}
const PRACTICE := ["sleepy", "glowy"]
const LIFE := 50.0  # simple mode: an uncaught ghost giggles and floats away through the ceiling after this
const STEALERS := ["thief", "shy"]
const STUN_TIME := 1.1  # seconds in the lantern beam to stun (half that with a focused beam)

var main
var puppet := false
var net_id := 0
var kind := "thief"
var night := 1
var radius := 0.42
var speed := 1.7
var tough := 1.0
var points := 100
var color := Color.WHITE

var reveal := 0.0  # how much the lantern lights this ghost (host-computed; mirrored to the client)
var capture := 0.0  # vacuum progress 0..1
var beam_t := 0.0
var stun_t := 0.0
var stun_cd := 0.0
var scared_t := 0.0
var sucked_t := 0.0
var flee_t := 0.0
var spook_cd := 1.5
var target_photo := -1
var carrying := -1
var grab_t := 0.0
var exit_point := Vector3.ZERO
var wander_point := Vector3.ZERO
var vel := Vector3.ZERO
var pull_from := Vector3.ZERO
var scare_from := Vector3.ZERO
var t := 0.0
var struggle_t := 0.0
var net_target := Vector3.ZERO
var net_rot := 0.0
var net_started := false

var body: Node3D
var skirt: MeshInstance3D
var meshes: Array[MeshInstance3D] = []
var stars: Node3D
var bar_bg: MeshInstance3D
var bar_fill: MeshInstance3D
var bar_mesh: QuadMesh
var arms: Array[Node3D] = []
var eye_nodes: Array[MeshInstance3D] = []
var blink_t := 2.0
var carried: Array[int] = []  # the Ghost King carries several photos
var minion_t := 14.0
var life_t := 0.0  # golden ghost: leaves after a while
var trail: CPUParticles3D
var crown: Node3D
var leaving := false  # simple mode: giggling off through the ceiling
var home_y := 1.4

func setup(k: String, n: int, m) -> void:
	kind = k
	night = n
	main = m
	var d: Dictionary = KINDS[k]
	color = d.color
	radius = d.radius
	speed = d.speed + 0.1 * (n - 1)
	tough = d.tough * (1.0 + 0.06 * (n - 1))
	points = d.points
	if m.simple:
		# Night 1 ghosts drift slowly; they speed up a little each night.
		speed = d.speed * (0.5 + 0.06 * mini(n - 1, 6))
		tough = d.tough * (0.5 if k == "king" else 1.0)


func _ready() -> void:
	add_to_group("ghosts")
	t = randf() * 10.0
	_build()
	_build_extras()
	wander_point = global_position
	net_target = global_position


func _build() -> void:
	var shared: ShaderMaterial = main.ghost_material()
	body = Node3D.new()
	add_child(body)
	var head := _sphere(radius, Vector3.ZERO, 1.0)
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.98
	cm.bottom_radius = radius * 0.3
	cm.height = radius * 1.8
	cm.radial_segments = 14
	cm.rings = 2
	cm.cap_top = false
	skirt = MeshInstance3D.new()
	skirt.mesh = cm
	skirt.position.y = -radius * 0.85
	body.add_child(skirt)
	meshes.append(skirt)
	for sx in [-1.0, 1.0]:
		# Little arms on a pivot so they can wave.
		var arm := Node3D.new()
		arm.position = Vector3(sx * radius * 0.8, -radius * 0.2, -radius * 0.1)
		body.add_child(arm)
		arm.set_meta("side", sx)
		arms.append(arm)
		var hand := _sphere(radius * 0.26, Vector3(sx * radius * 0.22, -radius * 0.15, -radius * 0.05), 1.3)
		hand.reparent(arm, false)
	var dark := Color(0.1, 0.04, 0.16)
	var eyes: Array[MeshInstance3D] = []
	for sx in [-1.0, 1.0]:
		eyes.append(_sphere(radius * 0.17, Vector3(sx * radius * 0.36, radius * 0.18, -radius * 0.86), 1.25))
	eye_nodes = eyes
	var mouth := _sphere(radius * 0.13, Vector3(0, -radius * 0.22, -radius * 0.9), 1.0)
	for mi in meshes:
		mi.material_override = shared
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_instance_shader_parameter("color", color)
	for mi in eyes:
		mi.set_instance_shader_parameter("color", dark)
	mouth.set_instance_shader_parameter("color", Color(0.45, 0.12, 0.3))
	head.set_instance_shader_parameter("color", color)
	# Dizzy stars (always visible: a hint where a stunned ghost is).
	stars = Node3D.new()
	stars.position.y = radius + 0.25
	add_child(stars)
	var star_mat := StandardMaterial3D.new()
	star_mat.albedo_color = Color(1.0, 0.9, 0.3)
	star_mat.emission_enabled = true
	star_mat.emission = Color(1.0, 0.9, 0.3)
	star_mat.emission_energy_multiplier = 3.0
	for i in 3:
		var s := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * 0.08
		s.mesh = bm
		s.material_override = star_mat
		var a := TAU * i / 3.0
		s.position = Vector3(cos(a) * 0.3, 0, sin(a) * 0.3)
		s.rotation = Vector3(0.6, a, 0.6)
		stars.add_child(s)
	stars.visible = false
	# Capture bar (billboard), shown while a vacuum is pulling.
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.albedo_color = Color(0.05, 0.02, 0.08)
	bg_mat.no_depth_test = false
	bg_mat.render_priority = 5
	var fill_mat: StandardMaterial3D = bg_mat.duplicate()
	fill_mat.albedo_color = Color(0.45, 1.0, 0.6)
	fill_mat.render_priority = 6
	bar_bg = MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(0.9, 0.12)
	bar_bg.mesh = bq
	bar_bg.material_override = bg_mat
	bar_bg.position.y = radius + 0.5
	add_child(bar_bg)
	bar_fill = MeshInstance3D.new()
	bar_mesh = QuadMesh.new()
	bar_mesh.size = Vector2(0.84, 0.08)
	bar_fill.mesh = bar_mesh
	bar_fill.material_override = fill_mat
	bar_fill.position.y = radius + 0.5
	add_child(bar_fill)
	for b in [bar_bg, bar_fill]:
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.visible = false


## A part drawn with the lantern-only ghost shader (shows up only in the light, like the body).
func _ghost_part(mesh: Mesh, pos: Vector3, tint: Color, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = main.ghost_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else body).add_child(mi)
	mi.set_instance_shader_parameter("color", tint)
	if kind == "shy":
		mi.set_instance_shader_parameter("shy", 1.0)
	meshes.append(mi)
	return mi


## A part that is ALWAYS visible (a give-away for the TV players: the snuffer's hat, the king's crown).
func _solid_part(mesh: Mesh, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else body).add_child(mi)
	return mi


func _cone(bottom: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = 10
	c.rings = 1
	return c


func _blob(r: float, squash: float) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0 * squash
	sm.radial_segments = 10
	sm.rings = 5
	return sm


## Hats, masks and trails that tell the kinds apart.
func _build_extras() -> void:
	var r := radius
	if kind == "shy":
		for mi in meshes:
			mi.set_instance_shader_parameter("shy", 1.0)
	if kind == "glowy":
		for mi in meshes:
			mi.set_instance_shader_parameter("glow", 1.0)  # shows without the lantern
	match kind:
		"thief":
			var mask := BoxMesh.new()
			mask.size = Vector3(r * 1.5, r * 0.3, r * 0.3)
			_ghost_part(mask, Vector3(0, r * 0.18, -r * 0.74), Color(0.12, 0.08, 0.2))
			for e in eye_nodes:
				e.set_instance_shader_parameter("color", Color(1.0, 1.0, 0.8))
				e.position.z -= r * 0.08
		"spooker":
			_ghost_part(_cone(r * 0.55, r * 1.3), Vector3(0, r * 1.35, 0.0), Color(0.32, 0.12, 0.48))
			var brim := CylinderMesh.new()
			brim.top_radius = r * 0.95
			brim.bottom_radius = r * 0.95
			brim.height = r * 0.06
			brim.radial_segments = 14
			_ghost_part(brim, Vector3(0, r * 0.78, 0.0), Color(0.32, 0.12, 0.48))
		"sprite":
			for sx in [-1.0, 1.0]:
				var bow := _ghost_part(_blob(r * 0.3, 0.6), Vector3(sx * r * 0.3, r * 1.0, 0.0), Color(1.0, 0.35, 0.6))
				bow.rotation.z = sx * 0.5
		"shy":
			for sx in [-1.0, 1.0]:
				_ghost_part(_blob(r * 0.14, 0.5), Vector3(sx * r * 0.55, -r * 0.05, -r * 0.8), Color(1.0, 0.55, 0.7))
		"snuffer":
			var brass := StandardMaterial3D.new()
			brass.albedo_color = Color(0.95, 0.7, 0.3)
			brass.metallic = 0.8
			brass.roughness = 0.3
			brass.emission_enabled = true
			brass.emission = Color(1.0, 0.6, 0.2)
			brass.emission_energy_multiplier = 1.2
			_solid_part(_cone(r * 0.5, r * 0.9), Vector3(0, r * 1.25, 0), brass)
			var handle := CylinderMesh.new()
			handle.top_radius = r * 0.05
			handle.bottom_radius = r * 0.05
			handle.height = r * 1.2
			handle.radial_segments = 6
			var h := _solid_part(handle, Vector3(r * 0.45, r * 1.5, 0), brass)
			h.rotation.z = -0.9
			for sx in [-1.0, 1.0]:
				_ghost_part(_blob(r * 0.22, 0.8), Vector3(sx * r * 0.55, -r * 0.1, -r * 0.7), Color(1.0, 0.6, 0.5))  # puffed cheeks
		"golden":
			trail = CPUParticles3D.new()
			trail.amount = 16
			trail.lifetime = 0.9
			trail.local_coords = false
			trail.direction = Vector3.UP
			trail.spread = 60.0
			trail.initial_velocity_min = 0.2
			trail.initial_velocity_max = 0.6
			trail.gravity = Vector3(0, -0.6, 0)
			var tm := BoxMesh.new()
			tm.size = Vector3.ONE * 0.05
			var gm := StandardMaterial3D.new()
			gm.albedo_color = Color(1.0, 0.85, 0.3)
			gm.emission_enabled = true
			gm.emission = Color(1.0, 0.8, 0.3)
			gm.emission_energy_multiplier = 4.0
			tm.material = gm
			trail.mesh = tm
			add_child(trail)
		"king":
			crown = Node3D.new()
			crown.position = Vector3(0, r * 0.95, 0)
			body.add_child(crown)
			var gold := StandardMaterial3D.new()
			gold.albedo_color = Color(1.0, 0.8, 0.25)
			gold.metallic = 1.0
			gold.roughness = 0.25
			gold.emission_enabled = true
			gold.emission = Color(1.0, 0.75, 0.2)
			gold.emission_energy_multiplier = 2.0
			var band := CylinderMesh.new()
			band.top_radius = r * 0.5
			band.bottom_radius = r * 0.45
			band.height = r * 0.22
			band.radial_segments = 12
			_solid_part(band, Vector3.ZERO, gold, crown)
			for i in 5:
				var a := TAU * i / 5.0
				var spike := _solid_part(_cone(r * 0.1, r * 0.35), Vector3(cos(a) * r * 0.45, r * 0.25, sin(a) * r * 0.45), gold, crown)
				spike.rotation.y = a
			var gem := StandardMaterial3D.new()
			gem.albedo_color = Color(1.0, 0.2, 0.4)
			gem.emission_enabled = true
			gem.emission = Color(1.0, 0.2, 0.4)
			gem.emission_energy_multiplier = 3.0
			_solid_part(_blob(r * 0.08, 1.0), Vector3(0, 0.0, -r * 0.48), gem, crown)
			var cape := BoxMesh.new()
			cape.size = Vector3(r * 1.6, r * 1.8, r * 0.08)
			var c := _ghost_part(cape, Vector3(0, -r * 0.5, r * 0.75), Color(0.35, 0.2, 0.7))
			c.rotation.x = 0.25
			for sx in [-1.0, 1.0]:
				var stache := _ghost_part(_blob(r * 0.16, 0.45), Vector3(sx * r * 0.18, -r * 0.08, -r * 0.92), Color(0.95, 0.95, 1.0))
				stache.rotation.z = sx * 0.4
			if main.simple:
				return  # no name tag: the crown says it
			var tag := Label3D.new()
			tag.name = "KingTag"
			tag.font_size = 56
			tag.outline_size = 14
			tag.pixel_size = 0.008
			tag.modulate = Color(1.0, 0.85, 0.35)
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.position.y = r * 2.0 + 0.4
			add_child(tag)


func _sphere(r: float, pos: Vector3, squash: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0 * squash
	sm.radial_segments = 14
	sm.rings = 7
	mi.mesh = sm
	mi.position = pos
	body.add_child(mi)
	meshes.append(mi)
	return mi


# --- Host simulation ---------------------------------------------------------

func _physics_process(delta: float) -> void:
	if puppet or main == null or main.game_over:
		return
	t += delta
	stun_t -= delta
	stun_cd -= delta
	scared_t -= delta
	flee_t -= delta
	spook_cd -= delta
	reveal = main.lantern_reveal(global_position, radius)
	if kind == "shy" and not main.players[0].focus:
		reveal = 0.0  # only the focused beam finds shy ghosts
	reveal = maxf(reveal, main.storm_flash)  # lightning shows everyone for a moment
	if kind == "glowy":
		reveal = 1.0
	if main.simple and _simple_extras(delta):
		return
	if reveal > 0.5 and stun_t <= 0.0:
		beam_t += delta * (2.0 if main.players[0].focus else 1.0)
		if beam_t >= STUN_TIME * (2.2 if kind == "king" else 1.0) and stun_cd <= 0.0:
			_stun()
	elif reveal <= 0.5:
		beam_t = maxf(0.0, beam_t - delta)
	if sucked_t > 0.0:
		sucked_t -= delta
	else:
		capture = maxf(0.0, capture - delta * 0.3)

	var desired := Vector3.ZERO
	var spd := speed
	var target_y := 1.4
	if stun_t > 0.0:
		spd = 0.0
		target_y = 1.1
	elif sucked_t > 0.0:
		# Struggle: pulled toward the nozzle, wriggling sideways.
		var to := pull_from - global_position
		to.y = 0.0
		var side := Vector3(-to.z, 0.0, to.x).normalized()
		desired = to.normalized() * 0.5 + side * sin(t * 9.0) * 0.8
		spd = 1.2
		target_y = clampf(pull_from.y, 0.9, 1.8)
	elif scared_t > 0.0:
		desired = global_position - scare_from
		desired.y = 0.0
		spd = speed * 1.6
	elif flee_t > 0.0:
		desired = wander_point - global_position
		desired.y = 0.0
	elif main.simple and kind != "golden":
		if kind == "king":
			minion_t -= delta
			if minion_t <= 0.0:
				minion_t = 16.0
				main.king_summon(self)
		var sr := _simple_move()
		desired = Vector3(sr.x, 0.0, sr.z)
		target_y = sr.y
		if kind in PRACTICE:
			spd = 0.0
		elif leaving:
			spd = 0.3
	elif main.director().event_name == "party" and carrying < 0 and kind != "king":
		# Ghost party in the ballroom: everyone dances in a ring (dizzy: easy to catch).
		var a := t * 0.8 + float(net_id) * 1.3
		var spot := Vector3(14.0 + cos(a) * 3.0, 0.0, 0.5 + sin(a) * 3.0)
		desired = spot - global_position
		desired.y = 0.0
		spd = speed * 1.3
		target_y = 1.3 + absf(sin(t * 4.0 + float(net_id))) * 0.5
	elif kind in STEALERS:
		var r := _thief(delta)
		desired = Vector3(r.x, 0.0, r.z)
		target_y = r.y
	elif kind == "snuffer":
		desired = _chase_lantern()
		target_y = 1.5
	elif kind == "golden":
		life_t += delta
		desired = _golden(delta)
		target_y = 1.5
	elif kind == "king":
		desired = _chase()
		target_y = 1.6
		minion_t -= delta
		if minion_t <= 0.0:
			minion_t = 16.0
			main.king_summon(self)
	else:
		desired = _chase()
		target_y = 1.2
	if desired.length() > 0.01:
		desired = desired.normalized()
	if reveal > 0.5:
		spd *= 0.75  # the lantern's light makes ghosts sluggish
	vel = vel.lerp(desired * spd, 1.0 - exp(-3.0 * delta))
	position += vel * delta
	position.y = lerpf(position.y, target_y + sin(t * 2.0) * 0.12, 1.0 - exp(-2.0 * delta))
	if Vector2(vel.x, vel.z).length() > 0.2:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-vel.x, -vel.z), 1.0 - exp(-6.0 * delta))
	if carrying >= 0 or (kind == "golden" and life_t > 24.0):
		if absf(position.x) > 22.5 or absf(position.z) > 9.8:
			main.ghost_escaped(self)
			return
	else:
		position.x = clampf(position.x, -24.0, 24.0)
		position.z = clampf(position.z, -11.0, 11.0)
	_check_touch()
	if sucked_t > 0.0:
		struggle_t -= delta
		if struggle_t <= 0.0:
			struggle_t = 0.3
			main.sound("hit", -10.0, 0.8 + capture)


## Returns a direction (x, z) plus the wanted height in y.
func _thief(delta: float) -> Vector3:
	if carrying >= 0:
		var to := exit_point - global_position
		return Vector3(to.x, 1.6, to.z)
	if target_photo < 0 or not main.photo_available(target_photo, self):
		target_photo = main.pick_photo(self)
		grab_t = 0.0
	if target_photo < 0:
		var c := _chase()
		return Vector3(c.x, 1.2, c.z)
	var spot: Vector3 = main.photo_grab_point(target_photo)
	var flat := Vector3(spot.x - global_position.x, 0.0, spot.z - global_position.z)
	if flat.length() < 0.5:
		grab_t += delta
		if grab_t > 1.0:
			carrying = target_photo
			main.grab_photo(self, target_photo)
			exit_point = _pick_exit()
		return Vector3(0.0, spot.y, 0.0)
	grab_t = 0.0
	return Vector3(flat.x, spot.y if flat.length() < 3.0 else 1.5, flat.z)


func _pick_exit() -> Vector3:
	var z := 11.0 if global_position.z > 0.0 else -11.0
	if randf() < 0.35:
		return Vector3(24.0 * signf(global_position.x + 0.01), 1.6, global_position.z)
	return Vector3(global_position.x + randf_range(-3.0, 3.0), 1.6, z)


func _chase() -> Vector3:
	var p = main.nearest_player(global_position)
	if p == null:
		return wander_point - global_position
	var to: Vector3 = p.global_position - global_position
	to.y = 0.0
	return to


func _check_touch() -> void:
	if main.simple:
		_simple_touch()
		return
	if kind in STEALERS or kind == "golden" or spook_cd > 0.0 or stun_t > 0.0 or scared_t > 0.0 or sucked_t > 0.0:
		return
	if main.director().event_name == "party" and kind != "king":
		return
	for p in main.players:
		if not p.active or p.is_down:
			continue
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z)
		if d.length() < radius + 0.45:
			if kind == "snuffer":
				if p.index != 0:
					continue  # snuffers only want the lantern
				main.snuff_lantern(self)
			else:
				main.spook_player(p, self)
			spook_cd = 3.0
			flee_t = 2.2
			var away := -Vector3(d.x, 0.0, d.y).normalized()
			wander_point = global_position + away * 5.0
			return


func _stun() -> void:
	stun_t = 2.6
	stun_cd = 4.5
	beam_t = 0.0
	if kind == "sleepy":
		main.practice_ghost_done(self)
		return
	if kind == "king":
		# Each stun shakes one photo loose; catching him returns the rest.
		if not carried.is_empty():
			main.return_photo(carried.pop_back(), true, main.players[0])
	else:
		drop_photo(main.players[0])
	main.on_ghost_stunned(self)


func drop_photo(by = null) -> void:
	if carrying >= 0:
		main.return_photo(carrying, true, by)
	for i in carried:
		main.return_photo(i, true, by)
	carried.clear()
	carrying = -1
	target_photo = -1
	grab_t = 0.0


## Snuffer: fly at the lantern-bearer to blow the lantern out.
func _chase_lantern() -> Vector3:
	var p = main.players[0]
	if not p.active or p.is_down or not p.lantern_lit():
		return _chase()
	var to: Vector3 = p.global_position - global_position
	to.y = 0.0
	return to


## Golden ghost: keeps its distance from everyone, then slips out after a while.
func _golden(_delta: float) -> Vector3:
	if life_t > 24.0:
		if exit_point == Vector3.ZERO:
			exit_point = _pick_exit()
		return exit_point - global_position
	var p = main.nearest_player(global_position)
	if p == null:
		return wander_point - global_position
	var away: Vector3 = global_position - p.global_position
	away.y = 0.0
	if away.length() < 6.0:
		return away.normalized() + Vector3(sin(t), 0.0, cos(t * 0.7)) * 0.5
	if global_position.distance_to(wander_point) < 1.0 or int(t * 10.0) % 40 == 0:
		wander_point = Vector3(randf_range(-19.0, 19.0), 0.0, randf_range(-6.5, 6.5))
	return wander_point - global_position


## The hand bell: flee from `from` for a few seconds and let go of any photo.
func scare(from: Vector3) -> void:
	scared_t = 3.0 if kind != "king" else 1.2
	scare_from = from
	if kind == "king":
		return  # the king is too proud to drop everything for a bell
	drop_photo(main.players[0])


## Host: a vacuum at `from` is pulling this (revealed) ghost.
func suck(from: Vector3, amount: float, by) -> void:
	sucked_t = 0.15
	pull_from = from
	capture += amount * (1.8 if stun_t > 0.0 else 1.0) * (1.5 if main.director().event_name == "party" else 1.0) / tough
	if capture >= 1.0:
		main.capture_ghost(self, by)


func is_stunned() -> bool:
	return stun_t > 0.0


# --- Simple mode (host) --------------------------------------------------------

## Life timer, floating away, and the solo lantern catch. Returns true if the ghost is gone.
func _simple_extras(delta: float) -> bool:
	if kind in PRACTICE:
		return false
	if kind != "golden":
		life_t += delta
	if not leaving and life_t > LIFE * (1.8 if kind == "king" else 1.0) and stun_t <= 0.0 and capture < 0.05:
		leaving = true
		main.sound("giggle", -4.0, randf_range(0.9, 1.2))
	if leaving and position.y > 4.6:
		main.ghost_floated_away(self)
		return true
	# No TV vacuums around (solo VR): a stunned ghost held in the light gets slurped into the lantern.
	if stun_t > 0.0 and reveal > 0.5 and not main.has_vacuums():
		sucked_t = 0.15
		pull_from = main.lantern_xform().origin
		capture += delta * 0.55 / tough
		if capture >= 1.0:
			main.capture_ghost(self, main.players[0])
			return true
	return false


## Direction (x, z) plus the wanted height (y): drift between spots near the players.
func _simple_move() -> Vector3:
	if kind in PRACTICE:
		return Vector3(0.0, home_y, 0.0)
	if leaving:
		return Vector3(0.0, 7.0, 0.0)
	var flat := Vector3(wander_point.x - global_position.x, 0.0, wander_point.z - global_position.z)
	if flat.length() < 0.8 or flee_t > -0.1 and flee_t < 0.0:
		_pick_wander()
		flat = Vector3(wander_point.x - global_position.x, 0.0, wander_point.z - global_position.z)
	return Vector3(flat.x, wander_point.y, flat.z)


func _pick_wander() -> void:
	var anchors: Array = []
	for p in main.players:
		if p.active and not p.ghost and (not p.remote or main.net.connected or p.index == 0):
			anchors.append(p.global_position)
	var a: Vector3 = anchors.pick_random() if not anchors.is_empty() else Vector3.ZERO
	var off := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * randf_range(2.5, 6.0)
	wander_point = Vector3(clampf(a.x + off.x, -19.5, 19.5), randf_range(1.1, 1.9), clampf(a.z + off.z, -7.0, 7.0))


## Bumping into someone: a giggle and a little float away (no harm done).
func _simple_touch() -> void:
	if kind in PRACTICE or kind == "golden" or spook_cd > 0.0 or stun_t > 0.0 or sucked_t > 0.0 or leaving:
		return
	for p in main.players:
		if not p.active:
			continue
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z)
		if d.length() < radius + 0.45:
			main.sound("giggle", -6.0, randf_range(1.0, 1.4))
			spook_cd = 3.0
			flee_t = 2.2
			var away := -Vector3(d.x, 0.0, d.y).normalized()
			wander_point = global_position + away * 4.0
			wander_point.y = 1.6
			return


# --- Visuals (both machines) -------------------------------------------------

func _process(delta: float) -> void:
	if puppet:
		t += delta
		global_position = global_position.lerp(net_target, 1.0 - exp(-12.0 * delta))
		body.rotation.y = lerp_angle(body.rotation.y, net_rot, 1.0 - exp(-10.0 * delta))
		stun_t -= delta
	body.position.y = sin(t * 2.3) * 0.05
	skirt.rotation.z = sin(t * 3.1) * 0.12
	skirt.rotation.x = sin(t * 2.7) * 0.1
	var squish := capture * (0.7 + 0.3 * sin(t * 20.0))
	body.scale = Vector3(1.0 - squish * 0.25, 1.0 + squish * 0.2, 1.0 + squish * 0.35)
	if stun_t > 0.0:
		body.rotation.z = sin(t * 6.0) * 0.25
	else:
		body.rotation.z = lerpf(body.rotation.z, 0.0, 1.0 - exp(-5.0 * delta))
	stars.visible = stun_t > 0.0
	if stars.visible:
		stars.rotation.y += delta * 4.0
	for arm in arms:
		var side: float = arm.get_meta("side")
		if kind == "shy":
			arm.rotation.x = -1.2 + sin(t * 2.0) * 0.1  # hands over its face
		elif capture > 0.05:
			arm.rotation.z = side * (0.9 + sin(t * 18.0) * 0.4)  # flailing
		else:
			arm.rotation.z = side * sin(t * 3.0 + side) * 0.5
			arm.rotation.x = 0.0
	blink_t -= delta
	var shut := blink_t < 0.12
	if blink_t <= 0.0:
		blink_t = randf_range(2.0, 4.5)
	if kind == "sleepy" and reveal < 0.5:
		shut = true  # asleep until the light wakes it up
	for e in eye_nodes:
		e.scale.y = 0.2 if shut else 1.0
	if crown != null:
		crown.rotation.z = sin(t * 2.0) * 0.08
		var tag := get_node_or_null("KingTag") as Label3D
		if tag != null:
			var n := carried.size()
			tag.text = "GHOST KING" + ("\nhas %d photo%s!" % [n, "" if n == 1 else "s"] if n > 0 else "")
	var show_bar := capture > 0.02
	bar_bg.visible = show_bar
	bar_fill.visible = show_bar
	if show_bar:
		var w := 0.84 * clampf(capture, 0.0, 1.0)
		bar_mesh.size = Vector2(maxf(w, 0.001), 0.08)
		bar_mesh.center_offset = Vector3(-0.42 + w / 2.0, 0.0, 0.001)
	var flash := capture * 0.8 + (0.5 + 0.5 * sin(t * 12.0)) * 0.3 * float(stun_t > 0.0)
	for mi in meshes:
		mi.set_instance_shader_parameter("flash", flash)


## Client: [id, kind, pos, rot_y, reveal, capture, stunned, scared, photos carried]
func apply_net(item: Array) -> void:
	net_target = item[2]
	net_rot = item[3]
	reveal = item[4]
	capture = item[5]
	if item.size() > 8 or not carried.is_empty():
		var n: int = item[8] if item.size() > 8 else 0
		while carried.size() < n:
			carried.append(-1)
		while carried.size() > n:
			carried.pop_back()
	var stunned: bool = item[6]
	stun_t = 0.5 if stunned else 0.0
	if not net_started:
		net_started = true
		global_position = net_target


func net_state() -> Array:
	var st := [net_id, kind, global_position, body.rotation.y, reveal, capture, stun_t > 0.0, scared_t > 0.0]
	if not carried.is_empty():
		st.append(carried.size())  # only the Ghost King carries several photos
	return st
