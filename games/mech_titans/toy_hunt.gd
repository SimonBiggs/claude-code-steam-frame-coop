extends Node3D
## MECH TITANS deep2 (every machine builds one under the world; main.gd calls round_start / host_tick on the host
## and visual_tick everywhere):
##  - THE LOST TOY (tales.gd): the made round's toy on its street corner under a tall beam of light in its colour.
##    Host: the Titan walks up to it (or a TV jet / truck / drone goes through it) -> it zooms to the lost kaiju,
##    who calms right down (Tales.TOY_CALM of its health, a dizzy smile, pink stars), a story card with the toy, and
##    the toy is saved into Momo's toy park. Net store "toy": {n, id, at, got}.
##  - MOMO'S TOY PARK: every toy found stands on the hills outside the city's east / west edges (net store "park":
##    the newest Tales.PARK_MAX ids), growing all the time.
##  - SEASONS (core/season_kit.gd): the season's props on the open squares and its drift (blossom / leaves / snow)
##    round the Titan; the season comes from the round (roundgen.gd "season"), so every machine agrees.

const Data := preload("res://games/mech_titans/data.gd")
const Tales := preload("res://games/mech_titans/tales.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const UiKit := preload("res://core/ui_kit.gd")

## Season props stand on the corners of these open squares (the plaza, the start squares, the shelters).
const PROP_SQUARES: Array[Vector3] = [Vector3(0, 0, 0), Vector3(0, 0, 26), Vector3(-26, 0, 52), Vector3(26, 0, 52)]
const PROP_SIZE := 3.6
const DRIFT_COLORS := {"spring": Color(1.0, 0.72, 0.85), "autumn": Color(1.0, 0.55, 0.15), "winter": Color(1.0, 1.0, 1.0)}

var main: Node
var toys_found := 0  ## host: this session (bots, telemetry)
var got_round := -1  ## host: the round whose toy was found
var _toy_key := ""
var _toy_node: Node3D
var _toy_beam: MeshInstance3D
var _toy_at := Vector3.ZERO
var _fly_t := -1.0  ## every machine: seconds since the toy was found (it zooms to the kaiju)
var _fly_from := Vector3.ZERO
var _park_key := ""
var _park: Node3D
var _season_key := ""
var _season_root: Node3D
var _drift: CPUParticles3D
var season := ""
var _t := 0.0


func setup(p_main: Node) -> void:
	main = p_main
	name = "ToyHunt"


# --- Host ---------------------------------------------------------------------------------------------------

## Host: a round starts: its toy lands on its street corner (a lesson has none).
func round_start() -> void:
	var r := int(main.net.state_get("mission", 0))
	var m: Dictionary = main.mission_info(r)
	var id := String(m.get("toy", ""))
	if id == "" or main.city == null:
		main.net.state_set("toy", {})
		return
	var at := Tales.spot(main.city, int(m.get("toy_seed", 0)))
	if OS.has_environment("MT_TOY_NEAR"):  # bots / What's New try: the toy stands just ahead of the Titan
		at = main.city.push_out(main.mech.global_position + main.mech.forward() * 22.0, 4.0)
		at.y = 0.0
	main.net.state_set("toy", {"n": r, "id": id, "at": at, "got": false})


func host_tick(_delta: float, phase: String) -> void:
	if phase != "play":
		return
	var toy: Dictionary = main.net.state_get("toy", {})
	if toy.is_empty() or bool(toy.get("got", false)):
		return
	var at: Vector3 = toy["at"]
	var by := -1
	var mp: Vector3 = main.mech.global_position
	if Vector2(mp.x - at.x, mp.z - at.z).length() < Tales.TOUCH_TITAN:
		by = 0
	else:
		for id in main.support.vehicles:
			var v: Node3D = main.support.vehicles[id]
			if int(id) >= 10 or v == null or bool(v.get("ai")):
				continue
			if Vector2(v.global_position.x - at.x, v.global_position.z - at.z).length() < Tales.TOUCH_VEH:  # a jet flies over it, a truck drives by
				by = int(id)
				break
	if by >= 0:
		_found(toy, by)


func _found(toy: Dictionary, by: int) -> void:
	var t2 := toy.duplicate()
	t2["got"] = true
	main.net.state_set("toy", t2)
	toys_found += 1
	got_round = int(toy.get("n", -1))
	var id := String(toy["id"])
	var info := Tales.info(id)
	var combat: Node = main.combat
	var at: Vector3 = toy["at"]
	combat.emit_fx("burst", ["stars", at + Vector3.UP * 3.0, 4.0, info["color"]])
	combat.emit_fx("sfx", ["power_up", at, 6.0, 1.0])
	# The lost kaiju get their toy back: much happier (and calmer), pink stars and a dizzy smile.
	for kid in combat.kaiju:
		var k: Node3D = combat.kaiju[kid]
		if k.is_mini or not k.is_active() or k.state == "practice":
			continue
		var calm: float = minf(k.hp_max * Tales.TOY_CALM, k.hp - 1.0)
		if calm > 0.0:
			combat.damage_kaiju(k, calm, -1, 0, "toy")
		combat.emit_fx("burst", ["stars", k.center() + Vector3.UP * k.height * 0.4, 4.0, Color(1.0, 0.5, 0.7)])
		combat.emit_fx("pop", [k.center() + Vector3.UP * k.height * 0.6, "YAY!", Color(1.0, 0.6, 0.8), 3.5])
		combat.stun_kaiju(k, by)
	# Saved: into Momo's toy park.
	var save: Node = main.save
	var list: Array = save.data["toys"]
	list.append(id)
	while list.size() > 60:
		list.pop_front()
	save.data["toys_n"] = int(save.data.get("toys_n", 0)) + 1
	save.mark_dirty()
	publish_park()
	main.story({"who": String(info["name"]), "line": "YAY!", "pic": String(info["pic"]), "color": (info["color"] as Color).to_html(false),
		"duration": 3.0, "sound": "achievement"})
	var n := int(save.data["toys_n"])
	if n % Tales.PARK_EVERY == 0:
		get_tree().create_timer(3.2).timeout.connect(func() -> void:
			main.story({"who": "TOY PARK", "line": "GROWS!", "pic": "toypark", "color": "74d99a", "duration": 3.0, "sound": "fanfare"}))


## Host: the toy park on every machine (the newest PARK_MAX toys).
func publish_park() -> void:
	var list: Array = main.save.data.get("toys", [])
	main.net.state_set("park", list.slice(maxi(0, list.size() - Tales.PARK_MAX)))


## Host: did the team find this round's toy? (main.gd adds the bonus heart)
func found_in(round_i: int) -> bool:
	return got_round == round_i


# --- Every machine -----------------------------------------------------------------------------------------

func visual_tick(delta: float) -> void:
	_t += delta
	_tick_toy(delta)
	var park: Variant = main.net.state_get("park", [])
	var pk := var_to_str(park)
	if pk != _park_key and park is Array:
		_park_key = pk
		_build_park(park)
	var ri: Variant = main.net.state_get("round_info", {})
	var s := String((ri as Dictionary).get("season", "")) if ri is Dictionary else ""
	var place: String = main.city.place if main.city != null else ""
	var sk := "%s/%s/%d" % [s, place, main.city.get_instance_id() if main.city != null else 0]
	if s != "" and sk != _season_key:
		_season_key = sk
		_build_season(s, place)
	if _drift != null:
		var mp: Vector3 = main.mech.global_position
		_drift.global_position = Vector3(mp.x, 26.0, mp.z - 10.0)


func _tick_toy(delta: float) -> void:
	var toy: Variant = main.net.state_get("toy", {})
	var d: Dictionary = toy if toy is Dictionary else {}
	var key := "%s/%s" % [str(d.get("n", -1)), String(d.get("id", ""))]
	if key != _toy_key:
		_toy_key = key
		_clear_toy()
		if not d.is_empty() and not bool(d.get("got", false)):
			_make_toy(String(d["id"]), d["at"])
	if _toy_node == null:
		return
	if bool(d.get("got", false)) and _fly_t < 0.0:
		_fly_t = 0.0
		_fly_from = _toy_node.global_position
		if _toy_beam != null:
			_toy_beam.visible = false
	if _fly_t >= 0.0:
		_fly_t += delta
		var to := _fly_from + Vector3.UP * 14.0
		var k := _nearest_kaiju(_fly_from)
		if k != null:
			to = k.center() + Vector3.UP * k.height * 0.3
		var f := clampf(_fly_t / 1.2, 0.0, 1.0)
		_toy_node.global_position = _fly_from.lerp(to, f) + Vector3.UP * sin(f * PI) * 10.0
		_toy_node.scale = Vector3.ONE * Tales.TOY_SIZE * (1.0 - 0.6 * f)
		_toy_node.rotation.y += delta * 9.0
		if f >= 1.0:
			_clear_toy()
		return
	_toy_node.position = _toy_at + Vector3.UP * (0.6 + 0.4 * sin(_t * 2.2))
	_toy_node.rotation.y += delta * 0.8
	if _toy_beam != null:
		var m := _toy_beam.material_override as StandardMaterial3D
		var c := m.albedo_color
		m.albedo_color = Color(c.r, c.g, c.b, 0.16 + 0.08 * sin(_t * 4.0))


func _nearest_kaiju(p: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	if main.combat == null:
		return null
	for id in main.combat.kaiju:
		var k: Node3D = main.combat.kaiju[id]
		if k.is_mini or not k.visible:
			continue
		var dd := k.global_position.distance_to(p)
		if dd < bd:
			bd = dd
			best = k
	return best


func _make_toy(id: String, at: Vector3) -> void:
	_toy_at = at
	_fly_t = -1.0
	_toy_node = MeshKit.instance(Tales.toy_mesh(id), false)
	_toy_node.name = "LostToy"
	_toy_node.scale = Vector3.ONE * Tales.TOY_SIZE
	add_child(_toy_node)
	_toy_node.global_position = at
	_toy_beam = MeshInstance3D.new()
	_toy_beam.name = "ToyBeam"
	var cm := CylinderMesh.new()
	cm.top_radius = 1.6
	cm.bottom_radius = 2.4
	cm.height = Tales.BEAM_H
	cm.radial_segments = 16
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	_toy_beam.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	UiKit.see_through(m)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var c: Color = Tales.info(id)["color"]
	m.albedo_color = Color(c.r, c.g, c.b, 0.2)
	_toy_beam.material_override = m
	_toy_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_toy_beam)
	_toy_beam.global_position = at + Vector3.UP * Tales.BEAM_H * 0.5


func _clear_toy() -> void:
	if _toy_node != null:
		_toy_node.queue_free()
		_toy_node = null
	if _toy_beam != null:
		_toy_beam.queue_free()
		_toy_beam = null


## Is this machine showing a lost toy now? (bots)
func toy_showing() -> bool:
	return _toy_node != null and _toy_beam != null and _toy_beam.visible


func park_count() -> int:
	return _park.get_meta("n", 0) if _park != null else 0


func _build_park(list: Array) -> void:
	if _park != null:
		_park.queue_free()
		_park = null
	if list.is_empty():
		return
	var b := MeshKit.Builder.new()
	for i in list.size():
		var at := Tales.park_spot(i)
		var side := -1.0 if i % 2 == 0 else 1.0
		var xf := Transform3D(Basis(Vector3.UP, -side * PI * 0.5 + 0.3 * sin(i * 1.7)).scaled(Vector3.ONE * Tales.TOY_SIZE * 1.3), at)
		b.add_mesh(Tales.toy_mesh(String(list[i])), xf)
	_park = MeshKit.instance(b.build(), false)
	_park.name = "ToyPark"
	_park.set_meta("n", list.size())
	add_child(_park)


func _build_season(s: String, place: String) -> void:
	season = s
	if _season_root != null:
		_season_root.queue_free()
	_season_root = Node3D.new()
	_season_root.name = "Season_" + s
	add_child(_season_root)
	_drift = null
	if place == "moon":
		return  # no seasons on the moon
	var b := MeshKit.Builder.new()
	var i := 0
	for sq in PROP_SQUARES:
		for c in [Vector3(-6.5, 0, -6.5), Vector3(6.5, 0, -6.5), Vector3(-6.5, 0, 6.5), Vector3(6.5, 0, 6.5)]:
			var at: Vector3 = sq + c + Vector3(0, 0.16, 0)
			if sq == Vector3(0, 0, 26) and c.z < 0.0:
				continue  # the Titan walks out of the start square that way
			SeasonKit.prop(b, s, at, i, PROP_SIZE, Vector3(-c.x, 0, -c.z).normalized())
			i += 1
	_season_root.add_child(MeshKit.instance(b.build(), false))
	if DRIFT_COLORS.has(s):
		_drift = SeasonKit.drift(DRIFT_COLORS[s], s, {"box": Vector3(55.0, 2.0, 55.0), "at": Vector3(0, 26, 0), "amount": 320,
			"size": 0.3, "lifetime": 11.0, "speed": Vector2(1.0, 2.2)})
		_drift.local_coords = false
		_season_root.add_child(_drift)
