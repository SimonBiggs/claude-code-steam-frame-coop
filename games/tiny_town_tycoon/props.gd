extends Node3D
## SIMPLE_MODE: everything on the table reacts when the mayor touches it (Simon's rule: if you can
## reach it, touching it does something). Either glove, just by touching:
##   - houses and buildings jiggle; trees sway; little people hop and wave (town_view.poke_*)
##   - four sheep on the grass hop with a boing
##   - three fluffy clouds over the island puff and drift away, then float back
##   - a hot-air balloon circling the island bounces up and away, then sails back
##   - a little windmill on a rock in the sea spins its sails fast
## and with the RIGHT trigger: pick a tree up and replant it anywhere on the grass (it goes back
## home if you let go somewhere it can't grow).
## Every machine draws the props (cheap: the clouds and sheep are one MultiMesh each, the balloon and
## windmill a couple of meshes); only the VR host feels touches. A touch goes through main._fx("prop")
## so the TV sees the same reaction. Trees live in the town (host request "tree_take" / "tree_plant").

const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Art := preload("res://games/tiny_town_tycoon/art.gd")
const Town := preload("res://games/tiny_town_tycoon/town.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")
const UiKit := preload("res://core/ui_kit.gd")

const CLOUDS := 3
const PUFFS := 4
const SHEEP := 4
const WINDMILL_AT := Vector3(0.6, Defs.SEA_Y, 0.46)
const TOUCH_GROUND := 0.07  ## how far above the grass a glove still touches the town

var main: Node
var t := 0.0
var cloud_mm: MultiMesh
var cloud_off: Array[Vector3] = []
var cloud_vel: Array[Vector3] = []
var sheep_mm: MultiMesh
var sheep_home: Array[Vector3] = []
var sheep_hop: Array[float] = []
var _sheep_t := 0.0
var balloon: Node3D
var balloon_kick := Vector3.ZERO
var balloon_off := Vector3.ZERO
var windmill_sails: Node3D
var spin := 0.0
var spin_speed := 1.2
var touching := {}  ## key -> true while a glove is on it (one reaction per touch)
var touched := {}  ## kind -> true once ever (bots)
var held_tree := -1  ## cell index the held tree came from (-1 = none)
var tree_mi: MeshInstance3D
var _poke_t := 0.0


func _ready() -> void:
	_build_clouds()
	_build_sheep()
	_build_balloon()
	_build_windmill()


func _build_clouds() -> void:
	var puff := SphereMesh.new()
	puff.radius = 1.0
	puff.height = 2.0
	puff.radial_segments = 12
	puff.rings = 6
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1)
	m.roughness = 1.0
	m.emission_enabled = true
	m.emission = Color(0.5, 0.52, 0.58)
	puff.material = m
	cloud_mm = MultiMesh.new()
	cloud_mm.transform_format = MultiMesh.TRANSFORM_3D
	cloud_mm.mesh = puff
	cloud_mm.instance_count = CLOUDS * PUFFS
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = cloud_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	for i in CLOUDS:
		cloud_off.append(Vector3.ZERO)
		cloud_vel.append(Vector3.ZERO)


func _build_sheep() -> void:
	var mesh := Art.cached("sheep", func() -> Resource:
		var b := MeshKit.Builder.new()
		var wool := Color(0.97, 0.97, 0.94)
		var dark := Color(0.2, 0.18, 0.18)
		b.ellipsoid(Vector3(0.008, 0.007, 0.011), MeshKit.at(Vector3(0, 0.011, 0)), wool, 10)
		b.sphere(0.0045, MeshKit.at(Vector3(0, 0.014, 0.011)), dark, 8)
		for k in 4:
			var x := -0.004 if k % 2 == 0 else 0.004
			var z := -0.006 if k < 2 else 0.006
			b.cylinder(0.0014, 0.0014, 0.006, MeshKit.at(Vector3(x, 0.003, z)), dark, 5)
		return b.build())
	sheep_mm = MultiMesh.new()
	sheep_mm.transform_format = MultiMesh.TRANSFORM_3D
	sheep_mm.mesh = mesh
	sheep_mm.instance_count = SHEEP
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = sheep_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	for i in SHEEP:
		sheep_home.append(Defs.CENTER)
		sheep_hop.append(0.0)


func _build_balloon() -> void:
	balloon = Node3D.new()
	balloon.name = "Balloon"
	add_child(balloon)
	var mesh := Art.cached("balloon", func() -> Resource:
		var b := MeshKit.Builder.new()
		var cols: Array[Color] = [Color(1.0, 0.35, 0.35), Color(1.0, 0.85, 0.3)]
		for k in 6:
			var a := k * TAU / 6.0
			b.ellipsoid(Vector3(0.024, 0.05, 0.024), MeshKit.at(Vector3(cos(a) * 0.024, 0.06, sin(a) * 0.024)), cols[k % 2], 10)
		b.box(Vector3(0.022, 0.016, 0.022), MeshKit.at(Vector3(0, 0.0, 0)), Color(0.6, 0.4, 0.24))
		for k in 4:
			var a2 := k * TAU / 4.0 + PI * 0.25
			b.tube(Vector3(cos(a2) * 0.011, 0.008, sin(a2) * 0.011), Vector3(cos(a2) * 0.02, 0.02, sin(a2) * 0.02), 0.0008, 0.0008, Color(0.4, 0.3, 0.2), 4)
		return b.build())
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	balloon.add_child(mi)


func _build_windmill() -> void:
	var base := Node3D.new()
	base.name = "Windmill"
	add_child(base)
	base.position = WINDMILL_AT
	var rock := MeshKit.Builder.new()
	rock.ellipsoid(Vector3(0.07, 0.02, 0.06), MeshKit.at(Vector3(0, 0.0, 0)), Color(0.5, 0.72, 0.36), 12)
	rock.ellipsoid(Vector3(0.05, 0.016, 0.04), MeshKit.at(Vector3(0.03, -0.004, 0.02)), Color(0.62, 0.6, 0.58), 10)
	var rmi := MeshInstance3D.new()
	rmi.mesh = rock.build()
	rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base.add_child(rmi)
	var s := 0.1
	var body := MeshInstance3D.new()
	body.mesh = Art.building_mesh("windmill", 0, 1, false)
	body.scale = Vector3.ONE * s
	body.position.y = 0.012
	body.rotation.y = atan2(-WINDMILL_AT.x, -WINDMILL_AT.z) + PI  # its door (+Z) faces the table's middle side
	base.add_child(body)
	windmill_sails = Node3D.new()
	body.add_child(windmill_sails)
	windmill_sails.position = Vector3(0, 0.62, 0.25)
	var sails := MeshInstance3D.new()
	sails.mesh = Art.windmill_sails()
	sails.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	windmill_sails.add_child(sails)


# --- Where things are -----------------------------------------------------------------------------

func cloud_pos(i: int) -> Vector3:
	var a := t * 0.05 + i * TAU / CLOUDS
	var r := 0.3 + 0.08 * float(i % 2)
	return Vector3(cos(a) * r, Defs.GROUND_Y + 0.42 + 0.05 * float(i), sin(a) * r) + cloud_off[i]


func balloon_pos() -> Vector3:
	var a := -t * 0.08 + 1.0
	return Vector3(cos(a) * 0.42, Defs.GROUND_Y + 0.3 + sin(t * 0.7) * 0.03, sin(a) * 0.42) + balloon_off


func sheep_pos(i: int) -> Vector3:
	var a := t * 0.25 + i * 1.7
	return sheep_home[i] + Vector3(sin(a) * 0.012, 0.0, cos(a * 0.7) * 0.012)


func windmill_top() -> Vector3:
	return WINDMILL_AT + Vector3(0, 0.08, 0)


## Fresh grass spots for the sheep (away from roads and buildings).
func _place_sheep() -> void:
	var town: Town = main.town
	var spots: Array[Vector2i] = []
	for z in Defs.GRID:
		for x in Defs.GRID:
			var d := Vector2(x - Defs.GRID * 0.5, z - Defs.GRID * 0.5).length()
			if d < 4.0 or d > 8.0 or town.terrain(x, z) != Defs.T_GRASS:
				continue
			if town.layer(x, z) != Defs.L_NONE or not town.building_at(x, z).is_empty() or town.trees[Town.idx(x, z)] > 0:
				continue
			spots.append(Vector2i(x, z))
	for i in SHEEP:
		var c: Vector2i = spots[(i * 37 + 11) % spots.size()] if not spots.is_empty() else Vector2i(Defs.GRID / 2, Defs.GRID / 2)
		var home := Defs.cell_center(c.x, c.y)
		var cc := Defs.world_cell(sheep_home[i])
		var still_ok := sheep_home[i] != Defs.CENTER and town.layer(cc.x, cc.y) == Defs.L_NONE and town.building_at(cc.x, cc.y).is_empty() \
			and town.terrain(cc.x, cc.y) == Defs.T_GRASS
		if not still_ok:
			sheep_home[i] = home


# --- Per frame --------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if main == null or main.town == null:
		return
	t += delta
	_sheep_t -= delta
	if _sheep_t <= 0.0:
		_sheep_t = 3.0
		_place_sheep()
	# clouds drift home after a puff
	for i in CLOUDS:
		cloud_vel[i] = cloud_vel[i] * exp(-2.0 * delta) - cloud_off[i] * 1.2 * delta
		cloud_off[i] += cloud_vel[i] * delta
		var c := cloud_pos(i)
		for k in PUFFS:
			var o := Vector3(-0.04 + k * 0.027, (0.012 if k == 1 or k == 2 else 0.0), sin(k * 2.1) * 0.012)
			var r := 0.026 if k == 1 or k == 2 else 0.019
			cloud_mm.set_instance_transform(i * PUFFS + k, Transform3D(Basis().scaled(Vector3(r, r * 0.8, r)), c + o))
	balloon_kick = balloon_kick * exp(-1.5 * delta) - balloon_off * 1.0 * delta
	balloon_off += balloon_kick * delta
	balloon.position = balloon_pos()
	balloon.rotation.y = t * 0.3
	spin_speed = lerpf(spin_speed, 1.2, 1.0 - exp(-0.6 * delta))
	spin += spin_speed * delta
	windmill_sails.rotation.z = spin
	for i in SHEEP:
		sheep_hop[i] = maxf(0.0, sheep_hop[i] - delta)
		var p := sheep_pos(i)
		var h := sheep_hop[i]
		var lift := absf(sin(h * 14.0)) * 0.012 * minf(1.0, h * 2.0)
		var yaw := t * 0.25 + i * 1.7
		sheep_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), p + Vector3(0, lift, 0)))
	if main.mayor != null and main.vr_rig != null and main.playing() and not get_tree().paused:
		_touches(delta)
		_carry_tree()


## Every glove touch (VR host only): one reaction per touch, sent to the TV as a "prop" effect.
func _touches(delta: float) -> void:
	var rig: VrRig = main.vr_rig
	_poke_t -= delta
	var now := {}
	for h in [VrRig.LEFT, VrRig.RIGHT]:
		var p: Vector3 = rig.hand_point(int(h))
		if rig.in_wrist_zone(p, 0.05):
			continue
		for i in CLOUDS:
			if p.distance_to(cloud_pos(i)) < 0.075:
				_touch(now, "cloud%d" % i, "cloud", i, p)
		if p.distance_to(balloon.global_position + Vector3(0, 0.05, 0)) < 0.075:
			_touch(now, "balloon", "balloon", 0, p)
		if p.distance_to(windmill_top()) < 0.09:
			_touch(now, "windmill", "windmill", 0, p)
		if p.y > Defs.GROUND_Y + TOUCH_GROUND or p.y < Defs.GROUND_Y - 0.03:
			continue
		for i in SHEEP:
			if p.distance_to(sheep_pos(i) + Vector3(0, 0.01, 0)) < 0.03:
				_touch(now, "sheep%d" % i, "sheep", i, p)
		var c := Defs.world_cell(p)
		if not Defs.inside(c.x, c.y):
			continue
		var b: Dictionary = main.town.building_at(c.x, c.y)
		if not b.is_empty() and int(b["stage"]) >= 1:
			_touch(now, "b%d" % int(b["id"]), "building", int(b["id"]), p)
		var ci := Town.idx(c.x, c.y)
		if main.town.trees[ci] > 0 and p.y < Defs.GROUND_Y + 0.04:
			_touch(now, "t%d" % ci, "tree", ci, p)
		if p.y < Defs.GROUND_Y + 0.03 and _poke_t <= 0.0:
			_poke_t = 0.15
			if int(main.view.call("poke_walkers", p, Defs.CELL * 0.6)) > 0:
				_poke_t = 0.8  # one cheer at a time
				touched["people"] = true
				main._fx("prop", ["people", c.x + c.y * Defs.GRID])
	for k in touching.keys():
		if not now.has(k):
			touching.erase(k)


func _touch(now: Dictionary, key: String, kind: String, i: int, _p: Vector3) -> void:
	now[key] = true
	if touching.has(key):
		return
	touching[key] = true
	touched[kind] = true
	main.vr_rig.pulse(VrRig.LEFT, 0.15, 0.03)
	main.vr_rig.pulse(VrRig.RIGHT, 0.15, 0.03)
	main._fx("prop", [kind, i])


## Every machine: show a touch (the host's own touches come through here too).
func react(kind: String, i: int) -> void:
	match kind:
		"cloud":
			if i >= 0 and i < CLOUDS:
				var away := cloud_pos(i) - Defs.CENTER
				away.y = 0.0
				cloud_vel[i] += away.normalized() * 0.25 + Vector3(0, 0.08, 0)
				main.sfx.play_at("whoosh", cloud_pos(i), -8.0, 1.4)
				main.view.call("burst", cloud_pos(i), Color(1, 1, 1), 8, 0.6)
		"balloon":
			var away2 := balloon.position - Defs.CENTER
			away2.y = 0.0
			balloon_kick += away2.normalized() * 0.2 + Vector3(0, 0.25, 0)
			main.sfx.play_at("boing", balloon.position, -6.0, 0.8)
		"windmill":
			spin_speed = 14.0
			main.sfx.play_at("whoosh", windmill_top(), -6.0, 1.1)
		"sheep":
			if i >= 0 and i < SHEEP:
				sheep_hop[i] = 0.9
				main.sfx.play_at("boing", sheep_pos(i), -8.0, 1.8)
		"building":
			main.view.call("poke_building", i)
			var b: Dictionary = main.town.buildings.get(i, {})
			if not b.is_empty():
				main.sfx.play_at("boing", main.town.center_of(b), -10.0, randf_range(1.1, 1.4))
		"tree":
			main.view.call("poke_tree", i)
			main.sfx.play_at("swish", Defs.cell_center(i % Defs.GRID, i / Defs.GRID), -12.0, 1.3)
		"people":
			var at := Defs.cell_center(i % Defs.GRID, i / Defs.GRID)
			if main.net.mode == "client":
				main.view.call("poke_walkers", at, Defs.CELL * 0.9)
			main.sfx.play_at("pop", at, -8.0, 1.7)
		"plant":
			var at2 := Defs.cell_center(i % Defs.GRID, i / Defs.GRID)
			main.view.call("burst", at2 + Vector3(0, 0.01, 0), Color(0.5, 1.0, 0.4), 10, 0.6)
			main.sfx.play_at("pop", at2, -6.0, 1.2)
			main.view.call("poke_tree", i)


# --- Trees: pick up and replant (right trigger) -----------------------------------------------------

## The mayor's right trigger went down with nothing in hand and no tray block near: a tree under the
## glove? Then it comes up into the hand. True if one did.
func try_grab_tree(p: Vector3) -> bool:
	if held_tree >= 0 or p.y > Defs.GROUND_Y + TOUCH_GROUND or p.y < Defs.GROUND_Y - 0.03:
		return false
	var c := Defs.world_cell(p)
	var best := -1
	var bd := INF
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var x := c.x + dx
			var z := c.y + dz
			if not Defs.inside(x, z) or main.town.trees[Town.idx(x, z)] == 0:
				continue
			var d := Defs.cell_center(x, z).distance_to(Vector3(p.x, Defs.GROUND_Y, p.z))
			if d < bd and d < Defs.CELL * 1.0:
				bd = d
				best = Town.idx(x, z)
	if best < 0:
		return false
	held_tree = best
	main.net.request(0, "tree_take", [best])
	if tree_mi == null:
		tree_mi = MeshInstance3D.new()
		tree_mi.mesh = MeshKit.prop(String(Defs.island(main.town.island).get("tree", "tree")))
		tree_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tree_mi)
	tree_mi.scale = Vector3.ONE * 0.015
	tree_mi.visible = true
	main.vr_rig.pulse(VrRig.RIGHT, 0.4, 0.06)
	UiKit.sound("ui_select", -6.0)
	touched["tree_grab"] = true
	return true


func holding() -> bool:
	return held_tree >= 0


func _carry_tree() -> void:
	if held_tree < 0:
		return
	var rig: VrRig = main.vr_rig
	var p := rig.hand_point(VrRig.RIGHT)
	tree_mi.global_position = p + Vector3(0, -0.02, 0)
	tree_mi.rotation = Vector3(sin(t * 6.0) * 0.1, 0.0, 0.0)
	if rig.trigger_down():
		return
	# let go: plant it under the glove if a tree can grow there, else back home
	var c := Defs.world_cell(p)
	var to := held_tree
	if Defs.inside(c.x, c.y) and p.y < Defs.GROUND_Y + 0.25 and can_plant(c.x, c.y):
		to = Town.idx(c.x, c.y)
	main.net.request(0, "tree_plant", [to, held_tree])
	if to != held_tree:
		touched["tree_plant"] = true
	held_tree = -1
	tree_mi.visible = false
	rig.pulse(VrRig.RIGHT, 0.3, 0.05)


func can_plant(x: int, z: int) -> bool:
	var town: Town = main.town
	var tr := town.terrain(x, z)
	return (tr == Defs.T_GRASS or tr == Defs.T_SAND) and town.layer(x, z) == Defs.L_NONE and town.building_at(x, z).is_empty() \
		and town.trees[Town.idx(x, z)] < 3


## Bots: where to touch things.
func bot_targets() -> Dictionary:
	return {"cloud": cloud_pos(0), "balloon": balloon.global_position + Vector3(0, 0.05, 0), "windmill": windmill_top(),
		"sheep": sheep_pos(0) + Vector3(0, 0.01, 0)}
