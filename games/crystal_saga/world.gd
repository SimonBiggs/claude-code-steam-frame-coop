extends Node3D
## CRYSTAL SAGA live world: loads the current area (maps.gd scenery + its living things) on every
## machine, and on the host runs what happens in it: roaming monsters that start battles when they
## touch the party, interactions (talk, read, open chests by hand, save crystals, puzzle crystals,
## guardian shards, pets), story triggers, exits to the next area and the Sky Bridge's wind gusts.
## Things' looks follow the replicated story flags, so the host and the TV machine always agree.
## The VR hero interacts by TOUCHING things with a glove (or pulling the trigger when close and facing
## them); TV players walk up and press A (net.request "interact").

const Maps := preload("res://games/crystal_saga/maps.gd")
const Nav := preload("res://games/crystal_saga/nav.gd")
const Data := preload("res://games/crystal_saga/data.gd")
const Story := preload("res://games/crystal_saga/story.gd")
const Creatures := preload("res://core/creatures.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const UiKit := preload("res://core/ui_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")

const TALK_RANGE_VR := 2.4
const TALK_RANGE_TV := 2.0
const TOUCH_R := 0.42
const ENC_TOUCH := 1.35
const ENC_AGGRO := 6.0

var main: Node
var area := ""
var def: Dictionary = {}
var nav: Nav
var root: Node3D
var things := {}  # id -> {"t": def dict, "node": Node3D, "prompt": Label3D, ...}
var encs := {}  # encounter index -> {"node": Node3D, "home": Vector3, "target": Vector3, "t": float}
var grace := 0.0  # host: seconds before monsters may start another battle
var exit_msg_t := 0.0
var wind_t := 0.0  # host: gust cycle clock
var wind_state := 0  # 0 calm, 1 rising, 2 gusting
var wind_fx: Array[CPUParticles3D] = []
var puzzle_fails := 0
var _anim_t := 0.0
var _touch_latch := {}  # thing id -> true while a glove stays on it (one interaction per touch)
var _trigger_seen := {}  # story trigger ids already fired this visit


## Build area `id` (frees the previous one). Every machine.
func load_area(id: String) -> void:
	unload()
	area = id
	def = Maps.build(id, main.vr_rig != null)
	nav = def["nav"]
	root = def["root"]
	add_child(root)
	things.clear()
	encs.clear()
	_trigger_seen.clear()
	puzzle_fails = 0
	for t in def["things"]:
		_make_thing(t)
	for e in def["encounters"]:
		_make_enc(e)
	refresh_things()
	sync_encounters()
	wind_t = 0.0
	wind_state = 0
	if (def["wind"] as Array).size() > 0:
		_make_wind_fx()
	grace = 2.5


func unload() -> void:
	if root != null and is_instance_valid(root):
		root.queue_free()
	for id in things:
		var n: Node3D = things[id]["node"]
		if is_instance_valid(n):
			n.queue_free()
	for i in encs:
		var en: Node3D = encs[i]["node"]
		if is_instance_valid(en):
			en.queue_free()
	for w in wind_fx:
		if is_instance_valid(w):
			w.queue_free()
	wind_fx.clear()
	things.clear()
	encs.clear()
	root = null


## Hide the map while a battle stage is up (and show it again after).
func set_shown(on: bool) -> void:
	if root != null:
		root.visible = on
	for id in things:
		var n: Node3D = things[id]["node"]
		if is_instance_valid(n):
			n.visible = on and bool(things[id].get("shown", true))
	for i in encs:
		var en: Node3D = encs[i]["node"]
		if is_instance_valid(en):
			en.visible = on and bool(encs[i].get("alive", true))


# --- Nav helpers -----------------------------------------------------------------------------------

func slide(from: Vector3, to: Vector3) -> Vector3:
	if nav == null:
		return to
	return nav.slide(from, to)


func nav_nearest(p: Vector3) -> Vector3:
	if nav == null:
		return p
	return nav.nearest(p)


## Walking speed multiplier at p (the Sky Bridge wind slows you down).
func speed_scale(p: Vector3) -> float:
	if wind_state == 2 and in_wind(p):
		return 0.22
	return 1.0


func in_wind(p: Vector3) -> bool:
	for w in def.get("wind", []):
		var r: Vector2 = w
		if p.z > r.x and p.z < r.y and absf(p.x) < 2.5:
			return true
	return false


## The VR rig's move filter: slide along edges, slowed by the wind.
func vr_filter(from: Vector3, to: Vector3) -> Vector3:
	if main.phase() != "explore":
		return from  # no stick walking in battles / cutscenes / conversations (real walking is fine)
	var s := speed_scale(from)
	var t := from + (to - from) * s
	var f2 := Vector3(from.x, 0, from.z)
	var r := slide(f2, Vector3(t.x, 0, t.z))
	return Vector3(r.x, to.y, r.z)


# --- Things ------------------------------------------------------------------------------------------

func _make_thing(t: Dictionary) -> void:
	var kind := String(t["kind"])
	var n := Node3D.new()
	n.name = "Thing_" + String(t["id"])
	add_child(n)
	n.position = t["pos"]
	n.rotation.y = float(t.get("yaw", 0.0))
	var entry := {"t": t, "node": n, "shown": true}
	match kind:
		"npc":
			var c: Node3D
			if t.has("model"):
				c = Creatures.monster(String(t["model"]), {"color": t.get("mcolor", Color(1, 1, 1)), "scale": 1.6})
			else:
				var look: Dictionary = (t["look"] as Dictionary).duplicate()
				look["scale"] = float(look.get("scale", 1.0)) * 1.42
				look["lod"] = "auto"
				look["lod_distance"] = 16.0
				c = Creatures.humanoid(look)
			n.add_child(c)
			entry["creature"] = c
			HudKit.nameplate(n, String(t["name"]), t.get("color", "accent"), Creatures.height_of(c) + 0.3, 0.18)
			entry["marker"] = _marker(n, Creatures.height_of(c) + 0.75)
			entry["home"] = n.position
		"pet":
			var p := Creatures.monster(String(t["model"]), {"color": t.get("color", Color(1, 1, 1)), "scale": 1.3})
			n.add_child(p)
			entry["creature"] = p
			entry["home"] = n.position
		"chest":
			_build_chest(n, entry)
		"save":
			_build_save(n, entry)
		"sign":
			_build_sign(n, t)
		"pcrystal":
			_build_pcrystal(n, entry, t["color"])
		"door":
			_build_door(n, entry)
		"barrier":
			_build_barrier(n, entry)
		"shard":
			_build_shard(n, entry, t["color"])
		"pedestal":
			_build_pedestal(n, entry)
		"trigger":
			pass
	entry["prompt"] = _prompt_label(n, kind)
	things[String(t["id"])] = entry


func _marker(n: Node3D, h: float) -> Label3D:
	var l := UiKit.label3d("!", 0.32, "gold", true)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.position = Vector3(0, h, 0)
	l.visible = false
	n.add_child(l)
	return l


func _prompt_label(n: Node3D, kind: String) -> Label3D:
	if kind == "trigger" or kind == "door" or kind == "barrier":
		return null
	var l := UiKit.label3d("", 0.1, "accent", true)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.position = Vector3(0, 1.0 if kind in ["chest", "pcrystal", "pet"] else (2.0 if kind in ["save", "shard", "sign"] else 2.9), 0)
	l.visible = false
	n.add_child(l)
	return l


func _build_chest(n: Node3D, entry: Dictionary) -> void:
	var b := MeshKit.Builder.new()
	b.rounded_box(Vector3(0.9, 0.5, 0.6), 0.05, MeshKit.at(Vector3(0, 0.25, 0)), Color(0.62, 0.38, 0.2))
	b.box(Vector3(0.94, 0.06, 0.64), MeshKit.at(Vector3(0, 0.12, 0)), Color(1.0, 0.8, 0.3))
	b.box(Vector3(0.94, 0.06, 0.64), MeshKit.at(Vector3(0, 0.42, 0)), Color(1.0, 0.8, 0.3))
	n.add_child(MeshKit.instance(b.build()))
	var lid := Node3D.new()
	lid.position = Vector3(0, 0.5, -0.3)  # hinge at the back edge
	n.add_child(lid)
	var lb := MeshKit.Builder.new()
	lb.rounded_box(Vector3(0.92, 0.22, 0.62), 0.08, MeshKit.at(Vector3(0, 0.1, 0.3)), Color(0.68, 0.42, 0.22))
	lb.box(Vector3(0.14, 0.16, 0.06), MeshKit.at(Vector3(0, 0.02, 0.62)), Color(1.0, 0.85, 0.35))
	lid.add_child(MeshKit.instance(lb.build()))
	entry["lid"] = lid
	var glow := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.3
	sm.radial_segments = 10
	sm.rings = 4
	glow.mesh = sm
	glow.material_override = MeshKit.material(Color(1.0, 0.9, 0.5, 0.35), 2.0)
	glow.position = Vector3(0, 0.55, 0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.visible = false
	n.add_child(glow)
	entry["glow"] = glow
	entry["touch"] = Vector3(0, 0.62, 0.15)


func _build_save(n: Node3D, entry: Dictionary) -> void:
	var b := MeshKit.Builder.new()
	b.cylinder(0.55, 0.65, 0.25, MeshKit.at(Vector3(0, 0.12, 0)), Color(0.75, 0.78, 0.88), 14)
	b.torus(0.5, 0.04, MeshKit.at(Vector3(0, 0.27, 0)), Color(0.4, 0.9, 1.0), 20, 4, true)
	n.add_child(MeshKit.instance(b.build()))
	var cb := MeshKit.Builder.new()
	cb.cylinder(0.0, 0.32, 0.55, MeshKit.at(Vector3(0, 0.27, 0)), Color(0.45, 0.9, 1.0), 4, true)
	cb.cylinder(0.32, 0.0, 0.55, MeshKit.at(Vector3(0, -0.27, 0)), Color(0.35, 0.75, 1.0), 4, true)
	var gem := MeshKit.instance(cb.build(), false)
	gem.position = Vector3(0, 1.35, 0)
	n.add_child(gem)
	entry["spin"] = gem
	entry["touch"] = Vector3(0, 1.35, 0)


func _build_sign(n: Node3D, t: Dictionary) -> void:
	if not bool(t.get("no_post", false)):
		n.add_child(MeshKit.instance(MeshKit.prop("sign")))
	var l := UiKit.label3d(String(t.get("title", "")), 0.075, Color(0.25, 0.15, 0.08), true, 1.0)
	l.outline_size = 0
	l.no_depth_test = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector3(0, 1.15, 0.09) if not bool(t.get("no_post", false)) else Vector3(0, 1.0, 0.05)
	l.modulate = Color(0.25, 0.15, 0.08) if not bool(t.get("no_post", false)) else Color(0.95, 0.9, 0.7)
	n.add_child(l)


func _build_pcrystal(n: Node3D, entry: Dictionary, col: Color) -> void:
	var b := MeshKit.Builder.new()
	b.cylinder(0.45, 0.55, 0.5, MeshKit.at(Vector3(0, 0.25, 0)), Color(0.45, 0.43, 0.5), 8)
	n.add_child(MeshKit.instance(b.build()))
	var on := MeshKit.Builder.new()
	on.cylinder(0.0, 0.3, 0.9, MeshKit.at(Vector3(0, 0.45, 0)), col, 6, true)
	on.cylinder(0.3, 0.0, 0.5, MeshKit.at(Vector3(0, -0.25, 0)), col, 6, true)
	var off := MeshKit.Builder.new()
	off.cylinder(0.0, 0.3, 0.9, MeshKit.at(Vector3(0, 0.45, 0)), col.darkened(0.65), 6)
	off.cylinder(0.3, 0.0, 0.5, MeshKit.at(Vector3(0, -0.25, 0)), col.darkened(0.7), 6)
	var lit := MeshKit.instance(on.build(), false)
	var dark := MeshKit.instance(off.build(), false)
	for g in [lit, dark]:
		var gi: Node3D = g
		gi.position = Vector3(0, 1.05, 0)
		n.add_child(gi)
	entry["lit"] = lit
	entry["dark"] = dark
	entry["touch"] = Vector3(0, 1.2, 0)


func _build_door(n: Node3D, entry: Dictionary) -> void:
	var b := MeshKit.Builder.new()
	b.rounded_box(Vector3(5.4, 4.2, 0.6), 0.1, MeshKit.at(Vector3(0, 2.1, 0)), Color(0.42, 0.4, 0.5))
	var cols: Array[Color] = [Color(1.0, 0.35, 0.3), Color(0.3, 0.6, 1.0), Color(0.35, 0.95, 0.45), Color(1.0, 0.85, 0.3)]
	for k in 4:
		b.sphere(0.22, MeshKit.at(Vector3(-1.2 + k * 0.8, 2.6, 0.32)), cols[k], 10, true)
	b.torus(1.5, 0.06, MeshKit.at(Vector3(0, 2.4, 0.31), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.8, 0.85, 1.0), 24, 4, true)
	var slab := MeshKit.instance(b.build())
	n.add_child(slab)
	entry["slab"] = slab


func _build_barrier(n: Node3D, entry: Dictionary) -> void:
	var b := MeshKit.Builder.new()
	for k in 7:
		var x := -2.4 + k * 0.8
		b.cylinder(0.0, 0.32, 3.2 + float(k % 3) * 0.6, MeshKit.at(Vector3(x, 1.6, 0)), Color(0.55, 0.85, 1.0) if k % 2 == 0 else Color(0.75, 0.6, 1.0), 5, true)
	var w := MeshKit.instance(b.build(), false)
	n.add_child(w)
	entry["wall"] = w


func _build_shard(n: Node3D, entry: Dictionary, col: Color) -> void:
	var b := MeshKit.Builder.new()
	b.cylinder(0.0, 0.28, 0.7, MeshKit.at(Vector3(0, 0.35, 0)), col.lightened(0.2), 5, true)
	b.cylinder(0.28, 0.0, 0.45, MeshKit.at(Vector3(0, -0.22, 0)), col, 5, true)
	var gem := MeshKit.instance(b.build(), false)
	gem.position = Vector3(0, 1.4, 0)
	n.add_child(gem)
	entry["spin"] = gem
	entry["touch"] = Vector3(0, 1.4, 0)
	var ring := MeshKit.Builder.new()
	ring.torus(0.7, 0.03, MeshKit.at(Vector3(0, 0.05, 0)), col, 24, 4, true)
	n.add_child(MeshKit.instance(ring.build(), false))


func _build_pedestal(n: Node3D, entry: Dictionary) -> void:
	var b := MeshKit.Builder.new()
	b.cylinder(0.0, 0.55, 1.3, MeshKit.at(Vector3(0, 0.65, 0)), Color(0.75, 0.95, 1.0), 6, true)
	b.cylinder(0.55, 0.0, 0.8, MeshKit.at(Vector3(0, -0.4, 0)), Color(0.6, 0.85, 1.0), 6, true)
	var gem := MeshKit.instance(b.build(), false)
	gem.position = Vector3(0, 2.6, 0)
	n.add_child(gem)
	entry["spin"] = gem
	entry["gem"] = gem


## Re-apply the story flags to every thing (chests open, shards shown, doors open...). Every machine.
func refresh_things() -> void:
	var f: Dictionary = main.flags()
	for id in things:
		var e: Dictionary = things[id]
		var t: Dictionary = e["t"]
		var n: Node3D = e["node"]
		var shown := true
		if t.has("if"):
			shown = main.flag_test(String(t["if"]))
		match String(t["kind"]):
			"chest":
				var opened := bool(f.get("chest_" + String(id), false))
				var lid: Node3D = e["lid"]
				if opened and lid.rotation.x > -1.0:
					var tw := lid.create_tween()
					tw.tween_property(lid, "rotation:x", -1.9, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
					(e["glow"] as Node3D).visible = true
					var gl: Node3D = e["glow"]
					get_tree().create_timer(1.2, false).timeout.connect(func() -> void:
						if is_instance_valid(gl):
							gl.visible = false)
				elif not opened:
					lid.rotation.x = 0.0
				e["done"] = opened
			"pcrystal":
				var lit_n := int(main.net.state_get("puzzle", 0))
				var on := bool(f.get("seal_open", false)) or int(t["order"]) < lit_n
				(e["lit"] as Node3D).visible = on
				(e["dark"] as Node3D).visible = not on
				e["done"] = bool(f.get("seal_open", false))
			"door", "barrier":
				var open := bool(f.get(String(t["flag"]), false))
				nav.set_gate(String(t["gate"]), not open, t["pos"], Vector2(5.4, 1.0))
				if open and n.visible and e.get("opened", false) == false:
					e["opened"] = true
					var body: Node3D = e.get("slab", e.get("wall", null))
					if body != null:
						var tw2 := body.create_tween()
						tw2.tween_property(body, "position:y", -4.6, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
						tw2.tween_callback(func() -> void: n.visible = false)
				elif open:
					n.visible = false
				shown = not open
			"shard":
				var s := String(t["summon"])
				shown = shown and not (main.summons_unlocked() as Array).has(s)
			"pedestal":
				shown = not bool(f.get("shattered", false)) or bool(f.get("restored", false))
			"npc":
				var mk: Label3D = e.get("marker", null)
				if mk != null:
					mk.visible = _has_news(String(id), f)
		if String(t["kind"]) != "door" and String(t["kind"]) != "barrier":
			n.visible = shown and (root == null or root.visible)
		e["shown"] = shown


func _has_news(id: String, f: Dictionary) -> bool:
	match id:
		"elder":
			return not bool(f.get("quest", false))
		"lina":
			return (bool(f.get("quest", false)) and not bool(f.get("tobi_quest", false))) or (bool(f.get("tobi_saved", false)) and not bool(f.get("tobi_thanked", false)))
		"pip", "hopper":
			return bool(f.get("quest", false)) and not bool(f.get("shopped", false))
	return false


func thing_pos(id: String) -> Vector3:
	if not things.has(id):
		return Vector3.ZERO
	var n: Node3D = things[id]["node"]
	return n.global_position


func _touch_point(e: Dictionary) -> Vector3:
	var n: Node3D = e["node"]
	var tp: Vector3 = e.get("touch", Vector3(0, 1.3, 0))
	return n.global_transform * tp


func _interactable(e: Dictionary) -> bool:
	if not bool(e.get("shown", true)) or bool(e.get("done", false)):
		return false
	var kind := String(e["t"]["kind"])
	return kind in ["npc", "pet", "chest", "save", "sign", "pcrystal", "shard", "door", "barrier"] and (kind != "door" and kind != "barrier")


func _verb(kind: String) -> String:
	match kind:
		"npc":
			return "TALK"
		"pet":
			return "PET"
		"chest":
			return "OPEN"
		"save":
			return "SAVE"
		"sign":
			return "READ"
		"pcrystal":
			return "LIGHT"
		"shard":
			return "TAKE"
	return "LOOK"


# --- Encounters -------------------------------------------------------------------------------------

func _make_enc(e: Dictionary) -> void:
	var forms: Array = Data.FORMATIONS.get(area, [])
	if forms.is_empty():
		return
	var f: Array = forms[int(e["f"]) % forms.size()]
	var mon: Dictionary = Data.MONSTERS[String(f[0])]
	var opts := {"scale": float(mon.get("scale", 1.4)), "lod": "auto", "lod_distance": 16.0}
	if mon.has("color"):
		opts["color"] = mon["color"]
	var c := Creatures.monster(String(mon["model"]), opts)
	c.name = "Enc%d" % int(e["i"])
	add_child(c)
	c.position = e["pos"]
	if bool(mon.get("fly", false)):
		Creatures.anim(c).flying = true
	var bang := UiKit.label3d("!", 0.36, "bad", true)
	bang.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	bang.position = Vector3(0, Creatures.height_of(c) + 0.5, 0)
	bang.visible = false
	c.add_child(bang)
	encs[int(e["i"])] = {"node": c, "home": e["pos"], "target": e["pos"], "t": randf() * 2.0, "f": int(e["f"]),
		"roam": float(e["roam"]), "alive": true, "bang": bang, "last": c.position}


## Show only the monsters still alive this visit (replicated "menc" list).
func sync_encounters() -> void:
	var alive: Array = main.net.state_get("menc", [])
	for i in encs:
		var e: Dictionary = encs[i]
		var on := alive.has(int(i))
		if bool(e["alive"]) and not on and (e["node"] as Node3D).visible:
			main.fx.poof((e["node"] as Node3D).global_position + Vector3.UP * 0.5, Color(1, 1, 1))
		e["alive"] = on
		(e["node"] as Node3D).visible = on and (root == null or root.visible)


func pack_encounters() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in encs:
		var e: Dictionary = encs[i]
		if bool(e["alive"]):
			var n: Node3D = e["node"]
			out.append_array([float(i), snappedf(n.position.x, 0.01), snappedf(n.position.z, 0.01), 1.0 if (e["bang"] as Node3D).visible else 0.0])
	return out


func unpack_encounters(p: PackedFloat32Array) -> void:
	var i := 0
	while i + 3 < p.size():
		var k := int(p[i])
		if encs.has(k):
			var n: Node3D = encs[k]["node"]
			var target := Vector3(p[i + 1], 0, p[i + 2])
			var d := target - n.position
			if d.length() > 0.02:
				Creatures.anim(n).face(d)
			n.position = n.position.lerp(target, 0.5)
			(encs[k]["bang"] as Node3D).visible = p[i + 3] > 0.5
		i += 4


# --- Per frame ------------------------------------------------------------------------------------

func update(delta: float) -> void:
	if root == null:
		return
	_anim_t += delta
	for id in things:
		var e: Dictionary = things[id]
		if e.has("spin"):
			var sp: Node3D = e["spin"]
			sp.rotation.y += delta * 1.2
			sp.position.y = (2.6 if e.has("gem") else 1.35 if String(e["t"]["kind"]) == "save" else 1.4) + sin(_anim_t * 2.0) * 0.08
		if e.has("creature") and e["t"].has("wander"):
			_wander(e, delta)
	var ph: String = main.phase()
	_update_prompts(ph == "explore")
	for i in encs:
		var en: Dictionary = encs[i]
		var n: Node3D = en["node"]
		var v := (n.position - (en["last"] as Vector3)).length() / maxf(delta, 0.001)
		Creatures.anim(n).walk(v if v > 0.2 else 0.0)
		en["last"] = n.position
	if main.net.mode == "client":
		_wind_visuals()
		return
	if ph != "explore":
		return
	grace = maxf(0.0, grace - delta)
	exit_msg_t = maxf(0.0, exit_msg_t - delta)
	_update_encounters(delta)
	_check_triggers()
	_check_exits()
	_update_wind(delta)
	if main.vr_rig != null:
		_vr_interact()


func _wander(e: Dictionary, delta: float) -> void:
	var c: Node3D = e["node"]
	var home: Vector3 = e["home"]
	var r := float(e["t"]["wander"])
	e["wt"] = float(e.get("wt", 0.0)) - delta
	if float(e["wt"]) <= 0.0:
		e["wt"] = randf_range(2.0, 5.0)
		e["goal"] = home + Vector3(randf_range(-r, r), 0, randf_range(-r, r))
	var goal: Vector3 = e.get("goal", home)
	var d := goal - c.position
	d.y = 0.0
	var cr: Node3D = e["creature"]
	if d.length() > 0.2:
		var step := d.normalized() * minf(d.length(), 1.0 * delta)
		c.position = slide(c.position, c.position + step)
		Creatures.anim(cr).walk(1.0)
		Creatures.anim(cr).face(d)
	else:
		Creatures.anim(cr).walk(0.0)


func _update_encounters(delta: float) -> void:
	var targets: Array = main.party_positions()
	for i in encs:
		var e: Dictionary = encs[i]
		if not bool(e["alive"]):
			continue
		var n: Node3D = e["node"]
		var home: Vector3 = e["home"]
		var best := INF
		var best_p := Vector3.ZERO
		for tp in targets:
			var p: Vector3 = tp
			var dd := Vector2(p.x - n.position.x, p.z - n.position.z).length()
			if dd < best:
				best = dd
				best_p = p
		var bang: Label3D = e["bang"]
		if best < ENC_TOUCH and grace <= 0.0:
			main.start_encounter(int(i), int(e["f"]))
			return
		var goal: Vector3
		var speed := 1.0
		if best < ENC_AGGRO and grace <= 0.0 and best_p.distance_to(home) < 10.0:
			goal = best_p
			speed = 2.3
			if not bang.visible:
				bang.visible = true
				main.fx_all("sound", ["ui_notify", n.global_position, -6.0])
		else:
			bang.visible = false
			e["t"] = float(e["t"]) - delta
			if float(e["t"]) <= 0.0:
				e["t"] = randf_range(1.5, 3.5)
				var r := float(e["roam"])
				e["target"] = home + Vector3(randf_range(-r, r), 0, randf_range(-r, r))
			goal = e["target"]
		var d := goal - n.position
		d.y = 0.0
		if d.length() > 0.15:
			var step := d.normalized() * minf(d.length(), speed * delta)
			n.position = slide(n.position, n.position + step)
			Creatures.anim(n).face(d)


## Host: the monster `index` was beaten (or fled): remove it for this visit.
func defeat_encounter(index: int) -> void:
	var alive: Array = main.net.state_get("menc", [])
	alive.erase(index)
	main.net.state_set("menc", alive)
	grace = 3.0


func _check_triggers() -> void:
	var h: Node3D = main.actors.hero()
	if h == null:
		return
	for id in things:
		var e: Dictionary = things[id]
		var t: Dictionary = e["t"]
		var r := float(t.get("trigger", t.get("r", 0.0)))
		if r <= 0.0 or not bool(e.get("shown", true)) or _trigger_seen.has(id):
			continue
		if String(t["kind"]) != "trigger" and String(t["kind"]) != "npc":
			continue
		if h.position.distance_to(t["pos"]) < r:
			_trigger_seen[id] = true
			if String(t["kind"]) == "trigger":
				main.story_event(String(t["story"]))
			else:
				main.story_event(String(id))  # tobi_lost
			return


func _check_exits() -> void:
	var h: Node3D = main.actors.hero()
	if h == null:
		return
	for x in def["exits"]:
		var ex: Dictionary = x
		var p: Vector3 = ex["pos"]
		if Vector2(h.position.x - p.x, h.position.z - p.z).length() < float(ex["r"]):
			if ex.has("need") and not main.flag_test(String(ex["need"])):
				if exit_msg_t <= 0.0:
					exit_msg_t = 4.0
					main.notify(String(ex.get("block", "You can't go that way yet.")), "exclaim", "warn")
				return
			main.change_area(String(ex["to"]), String(ex["spawn"]))
			return


# --- Interaction ------------------------------------------------------------------------------------

## The interactable nearest to `p` within `r` (or "").
func nearest_thing(p: Vector3, r: float) -> String:
	var best := ""
	var bd := r
	for id in things:
		var e: Dictionary = things[id]
		if not _interactable(e):
			continue
		var n: Node3D = e["node"]
		var d := Vector2(n.global_position.x - p.x, n.global_position.z - p.z).length()
		if d < bd:
			bd = d
			best = String(id)
	return best


func _update_prompts(active: bool) -> void:
	var near := {}  # id -> text
	if active:
		if main.vr_rig != null:
			var head: Vector3 = main.vr_rig.head_position()
			var id := nearest_thing(Vector3(head.x, 0, head.z), TALK_RANGE_VR)
			if id != "":
				near[id] = "TOUCH IT: " + _verb(String(things[id]["t"]["kind"]))
		for slot in main.party.local_slots():
			var a: Node3D = main.actors.avatar(slot)
			if a == null:
				continue
			var id2 := nearest_thing(a.position, TALK_RANGE_TV)
			if id2 != "":
				near[id2] = "A: " + _verb(String(things[id2]["t"]["kind"]))
	for id in things:
		var e: Dictionary = things[id]
		var l: Label3D = e.get("prompt", null)
		if l == null:
			continue
		var on := near.has(id)
		if on:
			l.text = String(near[id])
		if on != l.visible:
			l.visible = on
			if on:
				l.scale = Vector3.ONE * 0.5
				l.create_tween().tween_property(l, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Local seats (TV / flat hero) pressing A near something. Called by main each frame.
func local_interact_input() -> void:
	if main.phase() != "explore":
		return
	for slot in main.party.local_slots():
		if main.menu_busy(slot) or not main.party.just_pressed(slot, "accept"):
			continue
		var a: Node3D = main.actors.avatar(slot)
		if a == null:
			continue
		var id := nearest_thing(a.position, TALK_RANGE_TV)
		if id != "":
			main.net.request(slot, "interact", [id])


## Host: VR gloves touching things, or the trigger pulled when close and facing them.
func _vr_interact() -> void:
	var rig: VrRig = main.vr_rig
	var head := rig.head_position()
	var fwd := rig.head_forward()
	for id in things:
		var e: Dictionary = things[id]
		if not _interactable(e):
			_touch_latch.erase(id)
			continue
		var tp := _touch_point(e)
		var touching := rig.touching_any(tp, TOUCH_R) >= 0
		if touching and not _touch_latch.has(id):
			_touch_latch[id] = true
			rig.pulse(rig.touching_any(tp, TOUCH_R), 0.5, 0.08)
			interact(String(id), 0)
			return
		if not touching:
			_touch_latch.erase(id)
	if rig.trigger_pressed():
		var id2 := nearest_thing(Vector3(head.x, 0, head.z), TALK_RANGE_VR)
		if id2 != "":
			var to := thing_pos(id2) - head
			to.y = 0.0
			if to.length() < 1.0 or fwd.angle_to(to.normalized()) < deg_to_rad(65.0):
				rig.pulse(VrRig.RIGHT, 0.4, 0.06)
				interact(id2, 0)


## Host: member `by` interacts with thing `id`.
func interact(id: String, by: int) -> void:
	if not things.has(id) or main.phase() != "explore":
		return
	var e: Dictionary = things[id]
	if not _interactable(e):
		return
	var a: Node3D = main.actors.avatar(by)
	if a != null and by != 0 and a.position.distance_to((e["node"] as Node3D).global_position) > TALK_RANGE_TV + 1.0:
		return
	var t: Dictionary = e["t"]
	var n: Node3D = e["node"]
	match String(t["kind"]):
		"npc":
			var c: Node3D = e.get("creature", null)
			if c != null and a != null:
				Creatures.anim(c).face_point(a.global_position)
				Creatures.anim(c).play("wave" if String(id) != "elder" else "talk")
			main.talk_npc(id)
		"pet":
			var p: Node3D = e["creature"]
			Creatures.anim(p).play("jump")
			main.fx_all("dmg", [n.global_position + Vector3.UP * 1.0, "<3", "heal", 1.2])
			main.fx_all("sound", ["boing" if String(t["model"]) == "cat" else "honk", n.global_position, -4.0])
			main.awards.add(by, "pets")
		"chest":
			main.open_chest(id, t, by)
		"save":
			main.save_at(n.global_position, by)
		"sign":
			main.talk(Story.sign_lines(String(t["title"]), String(t["text"])), "sign")
		"pcrystal":
			_light_crystal(id, t, by)
		"shard":
			main.story_event("shard_" + String(t["summon"]))


func _light_crystal(id: String, t: Dictionary, by: int) -> void:
	var lit := int(main.net.state_get("puzzle", 0))
	var pos: Vector3 = t["pos"]
	if int(t["order"]) < lit:
		return
	if int(t["order"]) == lit:
		lit += 1
		main.net.state_set("puzzle", lit)
		main.fx_all("spell", ["holy", pos + Vector3.UP * 1.0, 0.8])
		main.fx_all("sound", ["ding", pos, 0.0])
		main.awards.add(by, "clues")
		if lit >= 4:
			main.set_flag("seal_open")
			main.fx_all("sound", ["reveal", pos, 0.0])
			main.notify("The sealed door rumbles open!", "key", "good")
			main.crystal_gain(10)
		refresh_things()
	else:
		puzzle_fails += 1
		main.net.state_set("puzzle", 0)
		main.fx_all("sound", ["wrong", pos, -3.0])
		var tip := "Hmm, the crystals went dark. Look at the mural: RED, BLUE, GREEN, then GOLD!"
		main.notify(tip, "question", "warn")
		refresh_things()


# --- Sky Bridge wind ---------------------------------------------------------------------------------

func _make_wind_fx() -> void:
	for w in def["wind"]:
		var r: Vector2 = w
		var p := CPUParticles3D.new()
		p.amount = 40
		p.lifetime = 1.2
		p.emitting = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(0.5, 1.2, (r.y - r.x) * 0.5)
		p.direction = Vector3(1, 0, 0)
		p.spread = 8.0
		p.gravity = Vector3.ZERO
		p.initial_velocity_min = 9.0
		p.initial_velocity_max = 14.0
		var q := QuadMesh.new()
		q.size = Vector2(0.9, 0.03)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, 0.55)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.disable_fog = true
		q.material = mat
		p.mesh = q
		add_child(p)
		p.position = Vector3(-6.0, 1.0, (r.x + r.y) * 0.5)
		wind_fx.append(p)


func _update_wind(delta: float) -> void:
	if (def["wind"] as Array).is_empty():
		return
	wind_t += delta
	var cycle := fmod(wind_t, 10.5)
	var st := 0 if cycle < 5.0 else (1 if cycle < 6.8 else 2)
	if st != wind_state:
		wind_state = st
		main.net.state_set("wind", st)
		if st == 1:
			main.fx_all("sound", ["whoosh", null, -4.0])
			main.hint_all("wind", "The wind is rising! Wait on an island until it calms down.", "exclaim")
	if st == 2:
		for idv in main.actors.avatars:
			var id := int(idv)
			var a: Node3D = main.actors.avatars[idv]
			if in_wind(a.position) and id != 0:
				main.actors.pushes[id] = Vector3(1.6, 0, 0)
	_wind_visuals()


func _wind_visuals() -> void:
	var st := int(main.net.state_get("wind", 0))
	if main.net.mode == "client":
		wind_state = st
	for p in wind_fx:
		p.emitting = st == 2
	if main.sfx != null:
		if st == 2:
			main.sfx.play_loop("wind", -4.0)
		elif st == 1:
			main.sfx.play_loop("wind", -14.0)
		else:
			main.sfx.stop_loop("wind", 1.0)
