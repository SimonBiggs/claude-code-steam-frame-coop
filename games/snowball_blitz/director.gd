extends Node
## Snowball Blitz director: weather events (blizzard, sunshine, cocoa party), fort upgrades (snowball
## catapult, ice walls, campfire), hit streaks, per-player awards, short hints on the TV and in VR, and
## the sky going from dusk to an aurora night (and to morning when the village is saved).
## The host decides; the TV machine mirrors pack()/unpack() and gets one-off events.

const VrText := preload("res://core/vr_text.gd")

const EVENTS := {
	"blizzard": ["BLIZZARD!", "The snowmen can't see in the storm - they're SLOW now. Get them!", 15.0],
	"sunshine": ["SUNSHINE!", "The sun is out - the snowmen are MELTING!", 11.0],
	"cocoa": ["COCOA PARTY!", "Hot cocoa everywhere, and a MEGA SNOWBALL! Grab them!", 3.0],
}
## Fort upgrades, granted when these waves are cleared.
const UPGRADES := {
	2: ["catapult", "SNOWBALL CATAPULT!", "It throws snowballs at the snowmen all by itself"],
	5: ["ice", "ICE WALLS!", "The fort walls are frozen hard: snowmen break them slower"],
	8: ["fire", "CAMPFIRE!", "Stand by the fire inside the fort to warm up"],
}
const KIND_HINTS := {
	"sled": "SLED RIDERS zoom straight into the walls - hit them early!",
	"giant": "GIANT SNOWMEN are tough - everyone throw at the same one!",
	"bunny": "SNOW BUNNIES hop in threes - tiny and quick!",
	"balloon": "BALLOON SNOWMEN float over the walls! Pop their balloons and they tumble down.",
	"shield": "SHIELD SNOWMEN block flat throws! LOB a high snowball over the shield, or hit them from the side.",
	"king": "The SNOW KING calls more snowmen - knock him over!",
	"yeti": "THE YETI! The final boss stomps the walls - pack them up and throw everything!",
}
const AWARDS := [
	["SNOW SNIPER", "hits"],
	["SNOWMAN SMASHER", "felled"],
	["FORT BUILDER", "packed"],
	["SHIELD HERO", "blocked"],
	["BALLOON POPPER", "pops"],
	["STREAK STAR", "best_streak"],
	["COCOA LOVER", "cocoa"],
	["SNOWSTORM", "thrown"],
]
const STREAKS := [3, 5, 8, 12, 20]
const TV_HOWTO := "HOW TO PLAY: hold RT to charge a snowball, let go to throw! Hold X next to a crumbling wall to " \
	+ "pack it. Walk over hot cocoa to warm up. Grab a glowing MEGA SNOWBALL for a giant throw!"
const VR_HOWTO := "HOW TO PLAY\nSqueeze the RIGHT TRIGGER to make a snowball\n(reach DOWN to the snow for a big one)\n" \
	+ "Swing and let go to THROW - it helps you aim!\nLEFT HAND: the pan lid blocks icy snowballs\n" \
	+ "LEFT STICK walk   RIGHT STICK turn   touch cocoa to warm up"

var main
var event_name := ""
var event_t := 0.0
var pending_event := ""
var pending_t := 0.0
var last_event := ""
var upgrades: Array = []
var catapult_t := 3.0
var streaks := {}  # player index -> current hit streak
var told := {}
var won := false
var night := 0.0
var flash_t := 0.0
# Visual nodes (both machines, built lazily).
var catapult: Node3D
var catapult_arm: Node3D
var campfire: Node3D
var flames: Array[MeshInstance3D] = []
var aurora_mat: ShaderMaterial
var blizzard_fx: CPUParticles3D
# UI.
var layer: CanvasLayer
var hint_label: Label
var hint_3d: Label3D
var hint_tween: Tween

const AURORA_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float strength = 0.0;
void fragment() {
	float x = UV.x * 6.2831 * 3.0;
	float wave = sin(x + TIME * 0.3) * 0.5 + sin(x * 2.3 - TIME * 0.5) * 0.25;
	float band = smoothstep(0.0, 0.35, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	float curtain = 0.5 + 0.5 * sin(UV.x * 140.0 + wave * 6.0 + TIME * 0.8);
	vec3 col = mix(vec3(0.2, 1.0, 0.55), vec3(0.65, 0.35, 1.0), clamp(UV.y + wave * 0.3, 0.0, 1.0));
	ALBEDO = col * band * (0.35 + 0.65 * curtain) * strength * 0.7;
}
"""


func _ready() -> void:
	name = "Director"


func tick(delta: float) -> void:
	_ensure_ui()
	if main.net.mode != "client" and not main.game_over:
		_host_tick(delta)
	_update_world(delta)
	if hint_3d != null and _vr():
		VrText.follow(hint_3d, main.players[0].xr_camera, main, -0.62, 1.8)


func _host_tick(delta: float) -> void:
	if pending_event != "":
		pending_t -= delta
		if pending_t <= 0.0:
			var ev := pending_event
			pending_event = ""
			start_event(ev)
	if event_name != "":
		event_t -= delta
		if event_t <= 0.0:
			end_event()
	if upgrades.has("catapult") and not main.in_break:
		catapult_t -= delta
		if catapult_t <= 0.0:
			catapult_t = 3.0
			_fire_catapult()
	if upgrades.has("fire"):
		for p in main.players:
			if p.active and not p.is_down and Vector2(p.global_position.x - fire_pos().x, p.global_position.z - fire_pos().z).length() < 2.6:
				p.heal(6.0 * delta)


# --- Waves, events, upgrades ------------------------------------------------------

func on_wave_started(wave: int, boss: String) -> void:
	end_event()
	if boss != "":
		hint(KIND_HINTS.get(boss, "A BOSS IS COMING!"), 5.0, "boss_" + boss)
		return
	if wave >= 3 and randf() < 0.5:
		var choices: Array[String] = ["blizzard", "sunshine", "cocoa"]
		choices.erase(last_event)
		pending_event = choices.pick_random()
		pending_t = 8.0
	if wave % 3 == 0:
		main.drop_mega(Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0)))


func on_wave_cleared(wave: int) -> String:
	end_event()
	pending_event = ""
	if UPGRADES.has(wave):
		var u: Array = UPGRADES[wave]
		if not upgrades.has(u[0]):
			upgrades.append(u[0])
			print("Fort upgrade: %s" % u[0])
			hint("FORT UPGRADE: %s %s" % [u[1], u[2]], 5.0)
			return "\nFORT UPGRADE: %s" % u[1]
	return ""


func start_event(ev: String) -> void:
	if not EVENTS.has(ev) or main.net.mode == "client":
		return
	end_event()
	var info: Array = EVENTS[ev]
	event_name = ev
	event_t = info[2]
	last_event = ev
	print("Event: %s" % ev)
	main._show_center(info[0], 2.0)
	hint(info[1], 5.0)
	main.sound("wave", -2.0, 1.3)
	if ev == "cocoa":
		for i in 5:
			var a := TAU * i / 5.0
			main._drop_cocoa(Vector3(cos(a), 0.0, sin(a)) * randf_range(2.0, 4.5))
		main.drop_mega(Vector3(0.0, 0.0, 1.5))


func end_event() -> void:
	if event_name == "":
		return
	print("Event over: %s" % event_name)
	event_name = ""


func ice_walls() -> bool:
	return upgrades.has("ice")


func fire_pos() -> Vector3:
	return Vector3(-2.4, 0.0, 2.4)


func catapult_pos() -> Vector3:
	return Vector3(2.4, 0.0, -2.4)


## Host: the catapult lobs a snowball at the snowman nearest the fort.
func _fire_catapult() -> void:
	var best = null
	var best_d := 30.0
	for s in get_tree().get_nodes_in_group("snowmen"):
		if s.dead:
			continue
		var dd: float = Vector2(s.global_position.x, s.global_position.z).length()
		if dd < best_d:
			best_d = dd
			best = s
	if best == null:
		return
	var from := catapult_pos() + Vector3(0, 1.6, 0)
	var aim: Vector3 = best.global_position + Vector3.UP * best.height * 0.45
	var v: Vector3 = main.lob_velocity(from, aim, 11.0)
	main.spawn_ball(from, v, 0.17, 1.5, "p", -1)
	main.sound("dash", -6.0, 0.6)
	swing_catapult()
	if main.net.mode == "host":
		main.net.event("catapult", [])


func swing_catapult() -> void:
	if catapult_arm == null:
		return
	var t := catapult_arm.create_tween()
	t.tween_property(catapult_arm, "rotation:x", -1.2, 0.12)
	t.tween_property(catapult_arm, "rotation:x", 0.5, 0.6)


# --- Streaks, stats, awards ----------------------------------------------------------

func on_hit(who: int, pos: Vector3) -> void:
	if who < 0 or main.net.mode == "client":
		return
	var n: int = int(streaks.get(who, 0)) + 1
	streaks[who] = n
	var st: Dictionary = main.stats_for(who)
	st["best_streak"] = maxf(float(st.get("best_streak", 0.0)), float(n))
	if n in STREAKS:
		main.score += 25 * n
		main.popup(pos + Vector3.UP * 1.0, "x%d STREAK! +%d" % [n, 25 * n], Color(1.0, 0.8, 0.35))
		main.sound("pickup", -4.0, 1.0 + n * 0.03)
		if n == 3:
			hint("STREAK! Hit snowmen in a row without missing for bonus points!", 3.5, "streak")


func on_miss(who: int) -> void:
	if who >= 0:
		streaks[who] = 0


func awards_text() -> String:
	var active: Array = main.players.filter(func(p) -> bool: return p.active)
	if active.is_empty():
		return ""
	var given := {}
	for p in active:
		given[p.index] = []
	for aw in AWARDS:
		var key: String = aw[1]
		var best = null
		var best_v := 0.0
		for p in active:
			var v: float = float(main.stats_for(p.index).get(key, 0.0))
			var mine: Array = given[p.index]
			if v > best_v + 0.01 and mine.size() < 2:
				best_v = v
				best = p
		if best != null:
			given[best.index].append(aw[0])
	var lines: Array[String] = ["★ AWARDS ★"]
	for p in active:
		var mine: Array = given[p.index]
		if mine.is_empty():
			mine.append("SNOW BUDDY")
		var st: Dictionary = main.stats_for(p.index)
		var who := "P%d%s" % [p.index + 1, " (VR)" if p.vr or (p.index == 0 and p.ghost) else ""]
		lines.append("%s  %s  (%d felled, %d hits)" % [who, " + ".join(PackedStringArray(mine)), int(st.get("felled", 0.0)), int(st.get("hits", 0.0))])
	return "\n".join(lines)


# --- Hints -------------------------------------------------------------------------

func hint(text: String, duration: float = 4.0, key: String = "") -> void:
	if key != "":
		if told.has(key):
			return
		told[key] = true
	if main.net.mode == "host":
		main.net.event("hint", [text, duration])
	show_hint(text, duration)


func on_snowman_spawned(kind: String) -> void:
	if KIND_HINTS.has(kind):
		hint("NEW: " + KIND_HINTS[kind], 4.5, "kind_" + kind)


func howto() -> void:
	var tv_ready: bool = main.net.mode != "host" or main.net.connected
	if not told.has("howto_tv") and tv_ready:
		told["howto_tv"] = true
		if main.net.mode == "host":
			main.net.event("hint", [TV_HOWTO, 12.0])
		if not _vr():
			show_hint(TV_HOWTO, 12.0)
	if not told.has("howto_vr") and _vr():
		told["howto_vr"] = true
		show_hint(VR_HOWTO, 16.0)


func show_hint(text: String, duration: float) -> void:
	_ensure_ui()
	hint_label.text = text
	var nodes: Array = [hint_label]
	if _vr():
		if hint_3d == null:
			hint_3d = Label3D.new()
			hint_3d.font_size = 40
			hint_3d.outline_size = 26
			hint_3d.outline_modulate = Color.BLACK
			hint_3d.pixel_size = 0.0022
			hint_3d.no_depth_test = true
			hint_3d.render_priority = 10
			hint_3d.outline_render_priority = 9
			hint_3d.width = 1100.0
			hint_3d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint_3d.modulate = Color(1.0, 0.92, 0.7)
			main.add_child(hint_3d)
			main.players[0]._set_layers(hint_3d, main.players[0].viewmodel_layer())
		hint_3d.text = text
		VrText.follow(hint_3d, main.players[0].xr_camera, main, -0.62, 1.8)
		nodes.append(hint_3d)
	if hint_tween:
		hint_tween.kill()
	hint_tween = create_tween().set_parallel()
	for n in nodes:
		n.modulate.a = 1.0
		hint_tween.tween_property(n, "modulate:a", 0.0, 0.5).set_delay(duration)
	if hint_3d != null and _vr():
		hint_3d.outline_modulate = Color(0, 0, 0, 1)
		hint_tween.tween_property(hint_3d, "outline_modulate:a", 0.0, 0.5).set_delay(duration)


# --- World look -------------------------------------------------------------------------

## Upgrade models, weather, the night sky and the sunrise (both machines).
func _update_world(delta: float) -> void:
	if upgrades.has("catapult") and catapult == null:
		_build_catapult()
	if upgrades.has("fire") and campfire == null:
		_build_campfire()
	for i in flames.size():
		var f := flames[i]
		f.scale = Vector3(1.0, 1.0 + 0.3 * sin(Time.get_ticks_msec() * 0.012 + i * 2.0), 1.0)
	# Dusk for the first waves, a starry aurora night later, morning once the village is saved.
	var want := 0.0
	if won and main.in_break:
		want = -1.0
	elif main.wave >= 3:
		want = clampf((main.wave - 2) / 4.0, 0.0, 1.0)
	night = move_toward(night, want, delta * (0.3 if want < night else 0.1))
	var sky: ProceduralSkyMaterial = main.get_meta("sky_mat", null)
	var env: Environment = main.get_meta("env", null)
	var sun: DirectionalLight3D = main.get_meta("sun", null)
	var sunny := event_name == "sunshine"
	if sky != null:
		var top := Color(0.12, 0.12, 0.32)
		var hor := Color(0.95, 0.55, 0.45)
		if night >= 0.0:
			top = top.lerp(Color(0.02, 0.03, 0.1), night)
			hor = hor.lerp(Color(0.18, 0.16, 0.38), night)
		else:
			top = top.lerp(Color(0.35, 0.55, 0.9), -night)
			hor = hor.lerp(Color(1.0, 0.82, 0.62), -night)
		if sunny:
			top = top.lerp(Color(0.4, 0.6, 0.95), 0.7)
			hor = hor.lerp(Color(1.0, 0.9, 0.7), 0.7)
		sky.sky_top_color = sky.sky_top_color.lerp(top, 1.0 - exp(-2.0 * delta))
		sky.sky_horizon_color = sky.sky_horizon_color.lerp(hor, 1.0 - exp(-2.0 * delta))
	if sun != null:
		var energy := 0.55 - 0.4 * maxf(night, 0.0) + 0.45 * maxf(-night, 0.0) + (0.6 if sunny else 0.0)
		sun.light_energy = lerpf(sun.light_energy, energy, 1.0 - exp(-2.0 * delta))
	if env != null:
		var amb := 0.75 - 0.25 * maxf(night, 0.0) + 0.2 * maxf(-night, 0.0) + (0.3 if sunny else 0.0)
		env.ambient_light_energy = lerpf(env.ambient_light_energy, amb, 1.0 - exp(-2.0 * delta))
	if aurora_mat == null:
		_build_aurora()
	aurora_mat.set_shader_parameter("strength", clampf((night - 0.4) * 1.7, 0.0, 1.0))
	# Blizzard: a second, fast slanting snowfall while it lasts.
	if blizzard_fx == null:
		_build_blizzard()
	blizzard_fx.emitting = event_name == "blizzard"
	var snow: CPUParticles3D = main.get_meta("snowfall", null)
	if snow != null:
		snow.speed_scale = 2.2 if event_name == "blizzard" else 1.0


func _build_aurora() -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 60.0
	cm.bottom_radius = 62.0
	cm.height = 22.0
	cm.radial_segments = 48
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	aurora_mat = ShaderMaterial.new()
	aurora_mat.shader = Shader.new()
	aurora_mat.shader.code = AURORA_SHADER
	mi.material_override = aurora_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 34.0
	main.add_child(mi)


func _build_blizzard() -> void:
	blizzard_fx = CPUParticles3D.new()
	blizzard_fx.amount = 200 if _vr() else 450
	blizzard_fx.lifetime = 2.5
	blizzard_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	blizzard_fx.emission_box_extents = Vector3(22, 0.5, 22)
	blizzard_fx.direction = Vector3(1.0, -0.6, 0.3)
	blizzard_fx.spread = 15.0
	blizzard_fx.initial_velocity_min = 6.0
	blizzard_fx.initial_velocity_max = 9.0
	blizzard_fx.gravity = Vector3(2.0, -2.0, 0.0)
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1, 1, 1, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = m
	blizzard_fx.mesh = q
	blizzard_fx.position = Vector3(-6, 9, 0)
	blizzard_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blizzard_fx.emitting = false
	main.add_child(blizzard_fx)


func _build_catapult() -> void:
	catapult = Node3D.new()
	main.add_child(catapult)
	catapult.position = catapult_pos()
	catapult.look_at(Vector3(catapult.position.x * 3.0, 0.0, catapult.position.z * 3.0), Vector3.UP)
	var wood := main.make_material(Color(0.5, 0.32, 0.18), 0.0) as StandardMaterial3D
	_box(catapult, Vector3(1.0, 0.25, 1.5), Vector3(0, 0.3, 0), wood)
	for x in [-0.55, 0.55]:
		for z in [-0.5, 0.5]:
			var w := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.22
			cm.bottom_radius = 0.22
			cm.height = 0.1
			cm.radial_segments = 10
			w.mesh = cm
			w.material_override = main.mat("stick")
			w.position = Vector3(x, 0.22, z)
			w.rotation.z = PI / 2.0
			catapult.add_child(w)
		_box(catapult, Vector3(0.12, 0.8, 0.12), Vector3(x * 0.7, 0.75, 0.0), wood)
	catapult_arm = Node3D.new()
	catapult_arm.position = Vector3(0, 0.95, 0.0)
	catapult_arm.rotation.x = 0.5
	catapult.add_child(catapult_arm)
	_box(catapult_arm, Vector3(0.12, 0.12, 1.4), Vector3(0, 0, 0.55), wood)
	var bucket := MeshInstance3D.new()
	bucket.mesh = main.sphere_mesh(0.2)
	bucket.material_override = main.mat("snowball")
	bucket.position = Vector3(0, 0.12, 1.2)
	catapult_arm.add_child(bucket)
	catapult.scale = Vector3.ONE * 0.05
	catapult.create_tween().tween_property(catapult, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_campfire() -> void:
	campfire = Node3D.new()
	main.add_child(campfire)
	campfire.position = fire_pos()
	var stones := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.45
	tm.outer_radius = 0.7
	tm.rings = 16
	tm.ring_segments = 6
	stones.mesh = tm
	stones.material_override = main.make_material(Color(0.45, 0.45, 0.5), 0.0)
	stones.scale = Vector3(1, 0.7, 1)
	campfire.add_child(stones)
	for a in [0.4, -0.4]:
		var log_mi := _box(campfire, Vector3(0.9, 0.14, 0.14), Vector3(0, 0.1, 0), main.mat("stick"))
		log_mi.rotation.y = a
	var cols: Array[Color] = [Color(1.0, 0.55, 0.15), Color(1.0, 0.8, 0.3), Color(1.0, 0.4, 0.1)]
	for i in 3:
		var f := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.18 - i * 0.03
		cm.height = 0.7 - i * 0.12
		cm.radial_segments = 8
		cm.rings = 1
		f.mesh = cm
		f.material_override = main.make_material(cols[i], 4.0)
		f.position = Vector3((i - 1) * 0.12, 0.35, (i % 2) * 0.08)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		campfire.add_child(f)
		flames.append(f)
	var sparks := CPUParticles3D.new()
	sparks.amount = 12
	sparks.lifetime = 1.4
	sparks.direction = Vector3.UP
	sparks.spread = 20.0
	sparks.initial_velocity_min = 0.8
	sparks.initial_velocity_max = 1.6
	sparks.gravity = Vector3(0, 0.3, 0)
	var sm := BoxMesh.new()
	sm.size = Vector3.ONE * 0.04
	sm.material = main.make_material(Color(1.0, 0.7, 0.3), 4.0)
	sparks.mesh = sm
	sparks.position.y = 0.5
	campfire.add_child(sparks)


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


# --- Network ------------------------------------------------------------------------

const UPGRADE_BITS := ["catapult", "ice", "fire"]


func pack() -> Array:
	var bits := 0
	for i in UPGRADE_BITS.size():
		if upgrades.has(UPGRADE_BITS[i]):
			bits |= 1 << i
	return [event_name, bits, won]


func unpack(a: Array) -> void:
	if a.size() < 3:
		return
	event_name = a[0]
	var bits: int = a[1]
	for i in UPGRADE_BITS.size():
		if bits & (1 << i) and not upgrades.has(UPGRADE_BITS[i]):
			upgrades.append(UPGRADE_BITS[i])
	won = a[2]


func client_event(kind: String, args: Array) -> void:
	match kind:
		"hint":
			show_hint(args[0], args[1])
		"catapult":
			swing_catapult()


# --- UI --------------------------------------------------------------------------

func _vr() -> bool:
	return not main.players.is_empty() and main.players[0].vr


func _ensure_ui() -> void:
	if layer != null and is_instance_valid(layer):
		return
	layer = CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	hint_label = main._make_label(28)
	hint_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(hint_label)
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.offset_left = -820
	hint_label.offset_right = 820
	hint_label.offset_top = -280
	hint_label.offset_bottom = -150
	hint_label.modulate.a = 0.0
