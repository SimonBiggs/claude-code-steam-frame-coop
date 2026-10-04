extends Node3D
const VrText := preload("res://core/vr_text.gd")
## Snowball Blitz: defend the snow fort in the village square from waves of mischievous snowmen.
## VR player (host): the team's sniper, throwing real snowballs with their hands.
## TV players: lob charged snowballs and pack the fort walls back up. Hot cocoa warms you up.

const PlayerScript := preload("res://games/snowball_blitz/player.gd")
const SnowmanScript := preload("res://games/snowball_blitz/snowman.gd")
const SnowballScript := preload("res://games/snowball_blitz/snowball.gd")
const CocoaScript := preload("res://games/snowball_blitz/cocoa.gd")
const WorldScript := preload("res://games/snowball_blitz/world.gd")
const HudScript := preload("res://games/snowball_blitz/hud.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const JoinInputScript := preload("res://games/snowball_blitz/join_input.gd")
const DirectorScript := preload("res://games/snowball_blitz/director.gd")

## Waves 4 and 8 bring the Snow King; wave 12 is the finale with the YETI. Then endless mode.
const FINALE_WAVE := 12
const MEGA_R := 0.45
const MEGA_DMG := 6.0
const MEGA_SPLASH := 2.6
const EXTRA_SOUNDS := {
	"whoosh": [0.4, 300.0, 900.0, 0.25, "sine", 0.6],
	"thud": [0.4, 160.0, 40.0, 0.6, "saw", 0.6],
	"fanfare": [1.6, 392.0, 1568.0, 0.4, "tri", 0.0],
	"roar": [0.9, 150.0, 45.0, 0.6, "saw", 0.45],
}

const ARENA_RADIUS := 20.0
const FORT_RADIUS := 6.0
const SEGMENTS := 8
const SEG_MAX := 100.0
const SEG_WIDTH := 3.4
const SEG_DEPTH := 0.9
const SEG_HEIGHT := 1.25
const GRAVITY := 12.0
const BOSS_EVERY := 4
const MAX_TV_PLAYERS := 6  # TV players are indices 1..6 when networked (0..5 in local split screen)
const PLAYER_COLORS: Array[Color] = [Color(0.95, 0.35, 0.3), Color(0.3, 0.7, 1.0), Color(0.5, 0.85, 0.35),
	Color(1.0, 0.82, 0.25), Color(0.75, 0.45, 1.0), Color(1.0, 0.55, 0.15), Color(0.3, 0.95, 0.85)]
const SCARF_COLORS: Array[Color] = [Color(0.9, 0.2, 0.25), Color(0.2, 0.55, 0.95), Color(0.95, 0.75, 0.2), Color(0.3, 0.75, 0.4), Color(0.75, 0.35, 0.85)]
const BUBBLE_SHADER := """
shader_type canvas_item;
uniform vec4 ring_color : source_color = vec4(1.0, 0.6, 0.3, 1.0);
void fragment() {
	float r = length(UV - 0.5);
	vec4 c = texture(TEXTURE, UV);
	float inside = 1.0 - smoothstep(0.485, 0.5, r);
	float ring = smoothstep(0.45, 0.47, r);
	COLOR = vec4(mix(c.rgb, ring_color.rgb, ring), inside);
}
"""

# Instance copies of the constants (other scripts read them through `main`).
var gravity := GRAVITY
var fort_r := FORT_RADIUS
var arena_radius := ARENA_RADIUS
var seg_max := SEG_MAX
var segments := SEGMENTS

var players: Array = []
var ready_to_play := false
var net: Node
var sfx: Node
var music: Node
var mats := {}
var meshes := {}
var cameras: Array[Camera3D] = []
var xr_interface: XRInterface
var mirror_vp: SubViewport
var mirror_t := 0.0
var ghost_cam: Camera3D
var ghost_nodes := {}
var synced := false
var net_ids := 0

var wave := 0
var score := 0
var to_spawn := 0
var spawn_timer := 0.0
var break_timer := 4.0
var in_break := true
var game_over := false
var game_over_time := 0.0
var cocoa_timer := 14.0
var repair_score := 0.0
var stats := []
var view_grid: GridContainer
var join_listener: Node
var pad_memory := {}  # joypad device id -> player index it last controlled (rejoins on reconnect)
var join_sent := {}  # player index -> msec of the last join request sent to the host
var boss_hp := -1.0  # fraction, -1 when no Snow King is around
var boss_name := ""
var dir_node: Node

var seg_hp: Array[float] = []
var seg_nodes: Array = []  # per segment: {stack, mat, bar, bar_mat, shape}

var info_label: Label
var center_label: Label
var help_label: Label
var center_tween: Tween
var vr_center: Label3D
var vr_hurt_mat: StandardMaterial3D
var vr_hurt := 0.0


func _ready() -> void:
	randomize()
	var xr := XRServer.find_interface("OpenXR")
	var will_vr := xr != null and xr.is_initialized() and not OS.has_environment("DUO_JOIN")
	WorldScript.build(self, ARENA_RADIUS, will_vr)
	_build_fort()
	_build_hud()
	var menu := PauseMenuScript.new()
	menu.main = self
	add_child(menu)
	net = NetScript.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	Input.joy_connection_changed.connect(_on_joy_changed)
	if OS.has_environment("DUO_JOIN"):
		_show_center("Connecting to the VR player…", 0.0)
		net.join_finished.connect(func(ok: bool) -> void: _setup_game("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if will_vr or OS.has_environment("DUO_HOST"):
			net.host()
		_setup_game(net.mode)


func _setup_game(mode: String) -> void:
	_build_players(mode)
	_build_views(mode)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_assign_joypads()
	ready_to_play = true
	_ensure_party()
	if mode == "host":
		_show_center("Waiting for the TV players to join…", 0.0)
	elif mode == "client":
		_show_center("CONNECTED!", 1.5)
	else:
		_show_center("SNOWBALL BLITZ\nDefend the fort!", 2.5)


func next_net_id() -> int:
	net_ids += 1
	return net_ids


# --- Shared materials, meshes and effects ------------------------------------

func make_material(color: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.75
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


## Cached materials by name, shared by every snowman/snowball so the GPU can batch them.
func mat(mat_name: String) -> StandardMaterial3D:
	if mats.has(mat_name):
		return mats[mat_name]
	var m: StandardMaterial3D
	match mat_name:
		"snow":
			m = make_material(Color(0.95, 0.97, 1.0), 0.0)
			m.roughness = 0.9
			m.rim_enabled = true
			m.rim = 0.5
		"fort":
			m = make_material(Color(0.88, 0.93, 1.0), 0.0)
			m.roughness = 0.95
		"coal":
			m = make_material(Color(0.06, 0.06, 0.08), 0.0)
		"carrot":
			m = make_material(Color(1.0, 0.5, 0.12), 0.25)
		"hat":
			m = make_material(Color(0.12, 0.1, 0.14), 0.0)
		"hat_band":
			m = make_material(Color(0.85, 0.15, 0.2), 0.3)
		"stick":
			m = make_material(Color(0.4, 0.25, 0.15), 0.0)
		"crown":
			m = make_material(Color(1.0, 0.8, 0.25), 1.2)
			m.metallic = 0.8
			m.roughness = 0.3
		"gem":
			m = make_material(Color(0.4, 0.8, 1.0), 3.0)
		"sled":
			m = make_material(Color(0.85, 0.2, 0.2), 0.0)
		"snowball":
			m = make_material(Color(1.0, 1.0, 1.0), 0.35)
		"enemy_ball":
			m = make_material(Color(0.6, 0.85, 1.0), 1.4)
		"ice":
			m = make_material(Color(0.6, 0.85, 1.0, 0.45), 0.6)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.1
		"thaw":
			m = make_material(Color(1.0, 0.65, 0.3, 0.35), 1.0)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		"skin":
			m = make_material(Color(1.0, 0.8, 0.65), 0.0)
		"lid":
			m = make_material(Color(0.8, 0.82, 0.86), 0.0)
			m.metallic = 0.9
			m.roughness = 0.25
		"mug":
			m = make_material(Color(0.85, 0.2, 0.2), 0.0)
		"cocoa":
			m = make_material(Color(0.4, 0.22, 0.12), 0.0)
		"cocoa_ring":
			m = make_material(Color(1.0, 0.65, 0.3), 2.0)
		"steam":
			m = make_material(Color(1, 1, 1, 0.35), 0.0)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_:
			if mat_name.begins_with("scarf"):
				m = make_material(SCARF_COLORS[int(mat_name.substr(5)) % SCARF_COLORS.size()], 0.15)
			else:
				m = make_material(Color.MAGENTA, 0.0)
	mats[mat_name] = m
	return m


func sphere_mesh(r: float) -> SphereMesh:
	var key := "s%.3f" % r
	if meshes.has(key):
		return meshes[key]
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 14
	sm.rings = 7
	meshes[key] = sm
	return sm


## Local-only puff of snow (both machines make their own for snowball splats).
func puff(pos: Vector3, color: Color, amount: int = 10, size: float = 0.08) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	m.material = make_material(color, 0.3) if color != Color(1, 1, 1) else mat("snowball")
	p.mesh = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


## Networked burst: shown here and on the TV.
func burst(pos: Vector3, color: Color, amount: int = 16, size: float = 0.1) -> void:
	puff(pos, color, amount, size)
	if net:
		net.event("burst", [pos, color, amount, size])


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
	if not sfx.has_meta("sb_sounds") and sfx.has_method("add_sound"):
		sfx.set_meta("sb_sounds", true)
		for k in EXTRA_SOUNDS:
			sfx.add_sound(k, EXTRA_SOUNDS[k])
	sfx.play(sound_name, volume_db, pitch)
	if net:
		net.event("sound", [sound_name, volume_db, pitch])


## Floating 3D text that rises and fades; shown on both machines.
func popup(pos: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.font_size = 64
	l.outline_size = 16
	l.pixel_size = 0.007
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	l.global_position = pos
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "global_position", pos + Vector3.UP * 1.4, 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.45)
	t.tween_property(l, "outline_modulate:a", 0.0, 0.9).set_delay(0.45)
	t.chain().tween_callback(l.queue_free)
	if net:
		net.event("popup", [pos, text, color])


## A snowman collapses: a burst of snow, a pile that slowly settles, and its hat flying off.
func collapse_fx(pos: Vector3, size: float, kind: String) -> void:
	puff(pos + Vector3.UP * size, Color(1, 1, 1), 26 + int(size * 14.0), 0.1 * size)
	var pile := MeshInstance3D.new()
	pile.mesh = sphere_mesh(0.6)
	pile.material_override = mat("snow")
	pile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pile)
	pile.global_position = pos
	pile.scale = Vector3(1.0, 1.4, 1.0) * size
	var carrot := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.05
	cm.height = 0.32
	cm.radial_segments = 8
	cm.rings = 1
	carrot.mesh = cm
	carrot.material_override = mat("carrot")
	pile.add_child(carrot)
	carrot.position = Vector3(0.1, 0.5, -0.2)
	carrot.rotation = Vector3(-1.2, randf() * TAU, 0.3)
	carrot.scale = Vector3.ONE / size
	var t := pile.create_tween()
	t.tween_property(pile, "scale", Vector3(1.5, 0.45, 1.5) * size, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(3.0)
	t.tween_property(pile, "scale", Vector3(1.6, 0.02, 1.6) * size, 2.0)
	t.tween_callback(pile.queue_free)
	if kind != "sled":
		var hat := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.19 * size
		hm.bottom_radius = 0.22 * size
		hm.height = 0.34 * size
		hm.radial_segments = 10
		hat.mesh = hm
		hat.material_override = mat("crown" if kind == "king" else "hat")
		add_child(hat)
		var start := pos + Vector3.UP * 2.0 * size
		hat.global_position = start
		var side := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 1.5 * size
		var ht := hat.create_tween().set_parallel()
		ht.tween_property(hat, "global_position:x", start.x + side.x, 0.9)
		ht.tween_property(hat, "global_position:z", start.z + side.z, 0.9)
		ht.tween_property(hat, "global_position:y", start.y + 1.2 * size, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		ht.tween_property(hat, "global_position:y", pos.y + 0.15, 0.55).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD).set_delay(0.35)
		ht.tween_property(hat, "rotation", Vector3(randf_range(3, 8), randf_range(-3, 3), randf_range(2, 5)), 0.9)
		ht.chain().tween_interval(2.5)
		ht.chain().tween_callback(hat.queue_free)
	if net:
		net.event("collapse", [pos, size, kind])


# --- The fort ----------------------------------------------------------------

func seg_center(i: int) -> Vector3:
	var a := TAU * i / SEGMENTS
	return Vector3(cos(a), 0, sin(a)) * FORT_RADIUS


func _build_fort() -> void:
	for i in SEGMENTS:
		seg_hp.append(SEG_MAX)
		var a := TAU * i / SEGMENTS
		var radial := Vector3(cos(a), 0, sin(a))
		var tangent := Vector3(-sin(a), 0, cos(a))
		var root := Node3D.new()
		add_child(root)
		root.global_transform = Transform3D(Basis(tangent, Vector3.UP, -radial), radial * FORT_RADIUS)
		var stack := Node3D.new()
		root.add_child(stack)
		var m := mat("fort").duplicate() as StandardMaterial3D
		var wall := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(SEG_WIDTH, SEG_HEIGHT, SEG_DEPTH)
		wall.mesh = bm
		wall.material_override = m
		wall.position.y = SEG_HEIGHT / 2.0
		stack.add_child(wall)
		# Snow-block crenellations along the top.
		var merlon := BoxMesh.new()
		merlon.size = Vector3(0.6, 0.35, SEG_DEPTH * 0.9)
		for x in [-1.2, 0.0, 1.2]:
			var mi := MeshInstance3D.new()
			mi.mesh = merlon
			mi.material_override = m
			mi.position = Vector3(x, SEG_HEIGHT + 0.17, 0)
			stack.add_child(mi)
		# Health bar above the wall (shown when damaged).
		var bar := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(SEG_WIDTH * 0.8, 0.08, 0.08)
		bar.mesh = bb
		var bar_mat := make_material(Color(0.4, 1.0, 0.5), 2.0)
		bar.material_override = bar_mat
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bar.position.y = SEG_HEIGHT + 0.75
		root.add_child(bar)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(SEG_WIDTH, SEG_HEIGHT + 0.4, SEG_DEPTH)
		cs.shape = shape
		cs.position.y = (SEG_HEIGHT + 0.4) / 2.0
		body.add_child(cs)
		root.add_child(body)
		seg_nodes.append({"stack": stack, "mat": m, "bar": bar, "bar_mat": bar_mat, "shape": cs, "shown": 1.0})
	# A snowy mound in the middle: the VR player's scooping spot.
	var mound := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.6
	tm.outer_radius = 1.6
	tm.rings = 24
	tm.ring_segments = 8
	mound.mesh = tm
	mound.material_override = mat("snow")
	mound.scale = Vector3(1.0, 0.6, 1.0)
	add_child(mound)


func _update_fort_visuals(delta: float) -> void:
	for i in SEGMENTS:
		var n: Dictionary = seg_nodes[i]
		var frac := seg_hp[i] / SEG_MAX
		var shown: float = lerpf(n.shown, frac, 1.0 - exp(-10.0 * delta))
		n.shown = shown
		var stack: Node3D = n.stack
		stack.scale = Vector3(1.0, maxf(0.08, shown), 1.0)
		var m: StandardMaterial3D = n.mat
		m.albedo_color = Color(0.62, 0.7, 0.9).lerp(Color(0.9, 0.94, 1.0), frac)
		if director().ice_walls():
			# ICE WALLS upgrade: shiny, blue and faintly glowing.
			m.albedo_color = m.albedo_color.lerp(Color(0.6, 0.85, 1.0), 0.6)
			if not m.emission_enabled:
				m.emission_enabled = true
				m.emission = Color(0.3, 0.6, 1.0)
				m.emission_energy_multiplier = 0.3
				m.metallic = 0.4
				m.roughness = 0.25
		var bar: MeshInstance3D = n.bar
		bar.visible = frac < 0.97
		bar.scale = Vector3(maxf(frac, 0.02), 1.0, 1.0)
		var bm: StandardMaterial3D = n.bar_mat
		bm.albedo_color = Color(1.0, 0.3, 0.2).lerp(Color(0.4, 1.0, 0.5), frac)
		bm.emission = bm.albedo_color
		var cs: CollisionShape3D = n.shape
		var off := frac < 0.15
		if cs.disabled != off:
			cs.set_deferred("disabled", off)


func fort_fraction() -> float:
	var total := 0.0
	for h in seg_hp:
		total += h
	return total / (SEG_MAX * SEGMENTS)


## Which standing fort wall (if any) does a ball at p touch?
func seg_hit(p: Vector3, r: float) -> int:
	var flat := Vector2(p.x, p.z)
	var d := flat.length()
	if absf(d - FORT_RADIUS) > SEG_DEPTH / 2.0 + r:
		return -1
	var a := atan2(p.z, p.x)
	var i := posmod(roundi(a / (TAU / SEGMENTS)), SEGMENTS)
	if seg_hp[i] <= 0.0:
		return -1
	var c := seg_center(i)
	var tangent := Vector3(-sin(TAU * i / SEGMENTS), 0, cos(TAU * i / SEGMENTS))
	if absf((p - c).dot(tangent)) > SEG_WIDTH / 2.0 + r:
		return -1
	var top := (SEG_HEIGHT + 0.35) * maxf(0.08, seg_hp[i] / SEG_MAX)
	return i if p.y < top + r else -1


func damage_segment(i: int, amount: float) -> void:
	if seg_hp[i] <= 0.0:
		return
	if director().ice_walls():
		amount *= 0.65
	seg_hp[i] = maxf(0.0, seg_hp[i] - amount)
	if seg_hp[i] <= 0.0:
		var c := seg_center(i)
		burst(c + Vector3.UP * 0.6, Color(0.85, 0.92, 1.0), 30, 0.14)
		sound("big_kill", -3.0, 0.9)
		popup(c + Vector3.UP * 2.2, "WALL DOWN!", Color(1.0, 0.45, 0.35))
		print("Fort wall %d knocked down (fort %d%%)" % [i, int(fort_fraction() * 100.0)])


func repair_segment(i: int, amount: float, who: int) -> void:
	if i < 0 or i >= SEGMENTS or game_over:
		return
	var before := seg_hp[i]
	seg_hp[i] = minf(SEG_MAX, seg_hp[i] + amount)
	var gained := seg_hp[i] - before
	stat_add(who, "packed", gained)
	repair_score += gained * 0.5
	if repair_score >= 1.0:
		score += int(repair_score)
		repair_score -= int(repair_score)
	if before < SEG_MAX and seg_hp[i] >= SEG_MAX:
		popup(seg_center(i) + Vector3.UP * 2.0, "PACKED!", Color(0.7, 0.9, 1.0))
		sound("pickup", -4.0, 0.8)


## Nearest damaged wall segment within reach of pos, or -1.
func repair_target(pos: Vector3) -> int:
	var best := -1
	var best_d := 2.6
	for i in SEGMENTS:
		if seg_hp[i] >= SEG_MAX - 0.5:
			continue
		var c := seg_center(i)
		var dd := Vector2(pos.x - c.x, pos.z - c.z).length()
		if dd < best_d:
			best_d = dd
			best = i
	return best


## Little puffs while a player packs snow onto a wall (local only).
func pack_puff(i: int, color: Color) -> void:
	var c := seg_center(i) + Vector3.UP * (0.4 + SEG_HEIGHT * seg_hp[i] / SEG_MAX)
	var tangent := Vector3(-sin(TAU * i / SEGMENTS), 0, cos(TAU * i / SEGMENTS))
	puff(c + tangent * randf_range(-1.4, 1.4), Color(1, 1, 1) if randf() < 0.7 else color.lightened(0.5), 5, 0.06)
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
	sfx.play("zap", -16.0, 0.35)


# --- Snowballs ---------------------------------------------------------------

func spawn_ball(origin: Vector3, v: Vector3, r: float, dmg: float, team: String, owner_index: int, visual_only: bool = false) -> void:
	var b := SnowballScript.new()
	b.main = self
	b.vel = v
	b.radius = r
	b.damage = dmg
	b.team = team
	b.owner_index = owner_index
	b.visual_only = visual_only
	add_child(b)
	b.global_position = origin
	var from_remote: bool = owner_index >= 0 and players[owner_index].remote
	if not visual_only and not from_remote:
		net.event("ball", [origin, v, r, team])


## A player threw: on the TV machine it's drawn right away and the host makes the real one.
func player_throw(p, origin: Vector3, v: Vector3, r: float, dmg: float) -> void:
	stat_add(p.index, "thrown", 1)
	if net.mode == "client":
		spawn_ball(origin, v, r, dmg, "p", p.index, true)
		net.send_action("throw", [origin, v, r, dmg], p.index)
	else:
		spawn_ball(origin, v, r, dmg, "p", p.index)


## Initial velocity for a lob from `from` that lands on `to` (flight time from the distance).
func lob_velocity(from: Vector3, to: Vector3, speed: float) -> Vector3:
	var flight := clampf(from.distance_to(to) / speed, 0.35, 2.2)
	return (to - from) / flight + Vector3.UP * 0.5 * GRAVITY * flight


## VR aim assist (kids' arms get tired): a throw roughly towards a snowman (within 14 degrees) is bent
## onto a lob that reaches it at the same throwing speed, keeping a bit of the real throw.
func assist_aim(from: Vector3, v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0, v.z)
	if flat.length() < 0.5:
		return v
	var best_angle := deg_to_rad(14.0)
	var best_pt := Vector3.ZERO
	var found := false
	for s in get_tree().get_nodes_in_group("snowmen"):
		if s.dead:
			continue
		var pt: Vector3 = s.global_position + Vector3.UP * s.height * 0.5
		for bn in s.balloon_nodes:
			if bn.visible:
				pt = bn.global_position  # balloon snowmen: aim for the balloons
				break
		var to: Vector3 = pt - from
		to.y = 0.0
		if to.length() < 1.0 or to.length() > 30.0:
			continue
		var ang := flat.angle_to(to)
		if ang < best_angle:
			best_angle = ang
			best_pt = pt
			found = true
	if not found:
		return v
	var to2 := best_pt - from
	var hd := Vector2(to2.x, to2.z).length()
	var hspeed := maxf(flat.length(), 6.0)
	var flight := clampf(hd / hspeed, 0.15, 2.5)
	var ideal := Vector3(to2.x, 0.0, to2.z).normalized() * (hd / flight) + Vector3.UP * ((to2.y + 0.5 * GRAVITY * flight * flight) / flight)
	return v.lerp(ideal, 0.7)


## Called by every snowball each step. Returns true if it hit something (and should vanish).
## The host applies the damage; visual-only balls just splat.
func ball_step(b) -> bool:
	var p: Vector3 = b.global_position
	var r: float = b.radius
	var real: bool = not b.visual_only and net.mode != "client"
	if p.y <= r * 0.5:
		puff(Vector3(p.x, 0.05, p.z), Color(1, 1, 1), 6, 0.05)
		if b.team == "p" and real:
			if r >= MEGA_R * 0.9:
				_mega_splash(Vector3(p.x, 0.0, p.z), b.owner_index)
			else:
				director().on_miss(b.owner_index)
		elif r >= MEGA_R * 0.9:
			puff(Vector3(p.x, 0.2, p.z), Color(1, 1, 1), 30, 0.12)
		return true
	if b.team == "p":
		for s in get_tree().get_nodes_in_group("snowmen"):
			if s.dead:
				continue
			var bi: int = s.balloon_hit(p, r)
			if bi >= 0:
				if real:
					s.pop_balloon(bi)
					stat_add(b.owner_index, "pops", 1)
					director().on_hit(b.owner_index, p)
				return true
			if not s.hit_test(p, r):
				continue
			puff(p, Color(1, 1, 1), 10, 0.07)
			if real:
				_on_snowman_hit(s, b)
			elif r >= MEGA_R * 0.9:
				puff(p, Color(1, 1, 1), 30, 0.12)
			return true
		return false
	for pl in players:
		if pl.active and not pl.is_down and pl.lid_blocks(p, r):
			puff(p, Color(0.8, 0.9, 1.0), 10, 0.06)
			if real:
				pl.on_block()
				stat_add(pl.index, "blocked", 1)
				sound("zap", -6.0, 0.6)
				popup(p + Vector3.UP * 0.3, "BLOCKED!", Color(0.8, 0.9, 1.0))
			return true
	var si := seg_hit(p, r)
	if si >= 0:
		puff(p, Color(0.8, 0.9, 1.0), 8, 0.07)
		if real:
			damage_segment(si, b.damage * 0.6)
		return true
	for pl in players:
		if pl.active and not pl.is_down and pl.hit_test(p, r):
			puff(p, Color(0.8, 0.9, 1.0), 10, 0.07)
			if real:
				var v: Vector3 = b.vel
				pl.take_damage(b.damage, p - v.normalized() * 6.0)
			return true
	return false


func _on_snowman_hit(s, b) -> void:
	var who: int = b.owner_index
	var mega: bool = b.radius >= MEGA_R * 0.9
	if mega:
		_mega_splash(s.global_position, who)
	if s.shield_blocks(b.vel):
		s.hit_shield(mega)
		stat_add(who, "hits", 1)
		if s.shield_hp > 0:
			director().hint("Their ICE SHIELD blocks flat throws - LOB a high one over it, or hit them from the side!", 4.0, "shield_tip")
			return
	director().on_hit(who, s.global_position + Vector3.UP * s.height)
	s.take_hit(b.damage, b.vel, who)
	sound("hit", -6.0, 1.3 if b.radius < 0.15 else 0.9)
	if who >= 0 and who < players.size():
		stat_add(who, "hits", 1)
		var p = players[who]
		if p.remote:
			net.event("hitmark", [who])
		else:
			p.on_ball_hit()
		# The VR sniper gets a little cheer for long throws.
		if p.vr or (who == 0 and net.mode == "host"):
			var dist: float = s.global_position.distance_to(p.global_position)
			if dist > 10.0 and not s.dead:
				popup(s.global_position + Vector3.UP * (s.height + 0.4), "SNIPE!", Color(1.0, 0.85, 0.4))


## A MEGA SNOWBALL landed: knocks every snowman nearby.
func _mega_splash(pos: Vector3, who: int) -> void:
	print("Mega splash by P%d" % (who + 1))
	puff(pos + Vector3.UP * 0.4, Color(1, 1, 1), 40, 0.14)
	net.event("burst", [pos + Vector3.UP * 0.4, Color(1, 1, 1), 40, 0.14])
	sound("thud", 0.0)
	popup(pos + Vector3.UP * 2.0, "MEGA SPLASH!", Color(0.7, 0.9, 1.0))
	for s in get_tree().get_nodes_in_group("snowmen"):
		if s.dead:
			continue
		var to: Vector3 = s.global_position - pos
		to.y = 0.0
		if to.length() < MEGA_SPLASH + s.radius():
			if s.shield_hp > 0:
				s.hit_shield(true)
			s.take_hit(MEGA_DMG * 0.5, to.normalized() * 8.0 if to.length() > 0.01 else Vector3.FORWARD, who)
	for p in players:
		if p.camera and not p.vr:
			p.shake = maxf(p.shake, 0.35)


## A glowing MEGA SNOWBALL to pick up (next throw is a giant one).
func drop_mega(pos: Vector3) -> void:
	if net.mode == "client":
		return
	for c in get_tree().get_nodes_in_group("cocoa"):
		if c.kind == "mega":
			return  # one at a time
	var c := CocoaScript.new()
	c.main = self
	c.kind = "mega"
	c.net_id = next_net_id()
	c.position = Vector3(pos.x, 0, pos.z)
	add_child(c)


func director() -> Node:
	if dir_node == null or not is_instance_valid(dir_node):
		dir_node = DirectorScript.new()
		dir_node.main = self
		add_child(dir_node)
	return dir_node


## The yeti stomps: everyone's view shakes.
func yeti_stomp(pos: Vector3) -> void:
	for p in players:
		if p.camera and not p.vr:
			p.shake = maxf(p.shake, 0.6)
		if p.vr:
			p.hand_l.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.2, 0.0)
			p.hand_r.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.2, 0.0)
	popup(pos + Vector3.UP * 5.0, "STOMP!", Color(0.7, 0.85, 1.0))


# --- Snowmen and waves -------------------------------------------------------

func nearest_player(pos: Vector3):
	var best = null
	var best_d := INF
	for p in players:
		if p.is_down or not p.active:
			continue
		var dd: float = pos.distance_squared_to(p.global_position)
		if dd < best_d:
			best_d = dd
			best = p
	return best


func _nearest_seg(pos: Vector3) -> int:
	return posmod(roundi(atan2(pos.z, pos.x) / (TAU / SEGMENTS)), SEGMENTS)


func _spawn_snowman(kind: String, pos: Vector3, grace: float = 0.8) -> void:
	var s := SnowmanScript.new()
	s.setup(kind, wave, self, _nearest_seg(pos))
	s.net_id = next_net_id()
	s.spawn_grace = grace
	s.position = pos
	if kind == "yeti":
		s.max_hp *= 1.0 + 0.25 * extra_players()
		s.hp = s.max_hp
	add_child(s)
	director().on_snowman_spawned(kind)


func summon_minions(pos: Vector3, count: int, kind: String = "snowman") -> void:
	for i in count:
		var a := randf() * TAU
		_spawn_snowman(kind, pos + Vector3(cos(a), 0, sin(a)) * 2.5, 0.6)
	burst(pos + Vector3.UP * 2.0, Color(0.6, 0.85, 1.0), 20, 0.12)
	sound("wave", -4.0, 0.6)


func on_snowman_collapsed(s, who: int) -> void:
	var pos: Vector3 = s.global_position
	var pts: int = s.d.points
	score += pts
	if who >= 0 and who < players.size():
		stat_add(who, "felled", 1)
	var size: float = s.s
	if size > 1.5:
		sound("big_kill", 0.0, 1.6 / size)
	else:
		sound("kill", -4.0, 1.3)
	collapse_fx(pos, size, s.kind)
	popup(pos + Vector3.UP * (size * 2.4 + 0.3), "+%d" % pts, Color(1.0, 0.9, 0.6))
	if s.kind != "king" and s.kind != "yeti" and randf() < (0.25 if s.kind == "giant" else 0.03):
		drop_mega.call_deferred(pos)
	for p in players:
		if p.camera and not p.vr:
			p.shake = maxf(p.shake, clampf(0.1 + size * 0.15 - p.global_position.distance_to(pos) * 0.01, 0.0, 0.6))
	if s.kind == "yeti":
		boss_hp = -1.0
		_show_center("THE YETI IS DOWN!", 2.5)
		sound("fanfare", 0.0)
		for i in 4:
			_drop_cocoa.call_deferred(pos + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
	elif s.kind == "king":
		boss_hp = -1.0
		_show_center("THE SNOW KING MELTED!", 2.5)
		for i in 3:
			_drop_cocoa.call_deferred(pos + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
	elif randf() < float(s.d.cocoa):
		_drop_cocoa.call_deferred(pos)


func _pick_kind() -> String:
	var r := randf()
	if wave >= 3 and r < 0.1 + wave * 0.012:
		return "giant"
	if wave >= 2 and r < 0.34:
		return "sled"
	if wave >= 2 and r < 0.44:
		return "bunny"
	if wave >= 3 and r < 0.54:
		return "balloon"
	if wave >= 4 and r < 0.63:
		return "shield"
	return "snowman"


func _spawn_wave_snowman() -> void:
	var best_pos := Vector3.ZERO
	var best_d := -1.0
	for attempt in 3:
		var a := randf() * TAU
		var pos := Vector3(cos(a), 0, sin(a)) * (ARENA_RADIUS - 1.0)
		var dd := INF
		for p in players:
			dd = minf(dd, pos.distance_to(p.global_position))
		if dd > best_d:
			best_d = dd
			best_pos = pos
	var kind := _pick_kind()
	if kind == "bunny":
		var side := Vector3(best_pos.z, 0.0, -best_pos.x).normalized()
		for i in 3:
			_spawn_snowman("bunny", best_pos + side * (i - 1) * 1.1)
		return
	_spawn_snowman(kind, best_pos)


func _start_wave() -> void:
	wave += 1
	in_break = false
	to_spawn = int((4 + wave * 3) * (1.0 + 0.22 * extra_players()))
	spawn_timer = 0.5
	print("Wave %d started" % wave)
	sound("wave")
	if wave == 3:
		create_tween().tween_property(help_label, "modulate:a", 0.0, 1.0)
	var boss := ""
	if wave == FINALE_WAVE:
		boss = "yeti"
	elif wave % BOSS_EVERY == 0:
		boss = "king" if (wave / BOSS_EVERY) % 2 == 1 or wave < FINALE_WAVE else "yeti"
	director().on_wave_started(wave, boss)
	if boss != "":
		to_spawn /= 2
		var a := randf() * TAU
		_spawn_snowman(boss, Vector3(cos(a), 0, sin(a)) * (ARENA_RADIUS - 1.0), 1.5)
		if boss == "yeti" and wave == FINALE_WAVE:
			_show_center("FINAL WAVE!\nTHE YETI IS COMING!", 2.5)
			sound("roar", 0.0, 0.7)
		elif boss == "yeti":
			_show_center("WAVE %d\nTHE YETI IS BACK!" % wave, 2.0)
		else:
			_show_center("WAVE %d\nTHE SNOW KING APPROACHES!" % wave, 2.0)
	elif wave < FINALE_WAVE:
		_show_center("WAVE %d of %d" % [wave, FINALE_WAVE], 1.4)
	else:
		_show_center("WAVE %d\nENDLESS" % wave, 1.4)


func _end_wave() -> void:
	in_break = true
	break_timer = 5.0
	for i in SEGMENTS:
		seg_hp[i] = minf(SEG_MAX, seg_hp[i] + 25.0)
	for p in players:
		if not p.active:
			continue
		if p.is_down:
			p.revive(0.5)
		else:
			p.heal(30.0)
	var upgrade: String = director().on_wave_cleared(wave)
	if wave == FINALE_WAVE and not director().won:
		director().won = true
		break_timer = 14.0
		score += 2000
		sound("fanfare", 0.0)
		print("VICTORY: the village is safe (score %d)" % score)
		_show_center("VICTORY!\nThe YETI is beaten and the village is safe!\n+2000\n\n%s\n\nEndless snowball fight next…" % director().awards_text(), 13.0)
		return
	_show_center("WAVE %d CLEARED!\nThe fort gets a fresh layer of snow%s" % [wave, upgrade], 2.6)
	sound("clear")
	print("Wave %d cleared, score %d, fort %d%%" % [wave, score, int(fort_fraction() * 100.0)])


func _drop_cocoa(pos: Vector3) -> void:
	if get_tree().get_nodes_in_group("cocoa").size() >= 5 + extra_players():
		return
	var c := CocoaScript.new()
	c.main = self
	c.net_id = next_net_id()
	c.position = Vector3(pos.x, 0, pos.z)
	add_child(c)


func _update_cocoa(delta: float) -> void:
	if not in_break:
		cocoa_timer -= delta
		if cocoa_timer <= 0.0:
			cocoa_timer = randf_range(14.0, 20.0) / (1.0 + 0.2 * extra_players())
			var a := randf() * TAU
			_drop_cocoa(Vector3(cos(a), 0, sin(a)) * randf_range(2.0, 4.5))
	for c in get_tree().get_nodes_in_group("cocoa"):
		if c.is_queued_for_deletion():
			continue
		var at: Vector3 = c.grab_point()
		for p in players:
			if not p.active or p.is_down:
				continue
			var got := false
			if p.vr:
				got = p.hand_l.global_position.distance_to(at) < 0.45 or p.hand_r.global_position.distance_to(at) < 0.45 \
					or Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length() < 0.8
			else:
				got = Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length() < 1.1
			if got and c.kind == "mega":
				if p.mega:
					continue
				p.mega = true
				if p.vr:
					p.hand_r.trigger_haptic_pulse("haptic", 0.0, 0.8, 0.15, 0.0)
				burst(at, Color(0.7, 0.9, 1.0), 20, 0.09)
				sound("pickup", 0.0, 0.6)
				popup(at + Vector3.UP * 0.8, "MEGA SNOWBALL!", Color(0.7, 0.9, 1.0))
				director().hint("MEGA SNOWBALL! Your next throw is GIANT and splashes every snowman nearby!", 4.0, "mega")
				c.queue_free()
				break
			if got:
				p.heal(45.0)
				if p.vr:
					p.hand_l.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.1, 0.0)
				stat_add(p.index, "cocoa", 1)
				burst(at, Color(1.0, 0.7, 0.4), 14, 0.07)
				sound("pickup", -2.0, 0.9)
				popup(at + Vector3.UP * 0.8, "COCOA! +WARMTH", Color(1.0, 0.75, 0.45))
				c.queue_free()
				break


func on_player_frozen(p) -> void:
	popup(p.global_position + Vector3.UP * 2.2, "P%d FROZE!" % (p.index + 1), Color(0.6, 0.85, 1.0))


func stat_add(who: int, key: String, amount: float) -> void:
	if who < 0 or who > MAX_TV_PLAYERS:
		return
	var st := stats_for(who)
	st[key] = st.get(key, 0.0) + amount


func stats_for(who: int) -> Dictionary:
	while stats.size() <= who:
		stats.append({})
	return stats[who]


## How many players (VR + TV) are in the game right now.
func party_size() -> int:
	var n := 0
	for p in players:
		if p.active:
			n += 1
	return n


## Extra players beyond the classic VR + 2 TV players: used to scale the waves.
func extra_players() -> int:
	return clampi(party_size() - 3, 0, 4)


func boss_text() -> String:
	if boss_hp < 0.0:
		return ""
	return "%s %d%%" % [boss_name if boss_name != "" else "SNOW KING", int(boss_hp * 100.0)]


# --- Main loop ---------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	_ensure_party()
	_update_fort_visuals(delta)
	_update_vr_center()
	_update_vr_hurt(delta)
	if music == null:
		music = MusicScript.new()
		add_child(music)
		music.volume_db = -17.0
	if music.has_method("play_track"):
		music.play_track(1 if boss_hp >= 0.0 else maxi(wave - 1, 0) / 3)
	director().tick(delta)
	if ghost_cam:
		ghost_cam.global_transform = players[0].net_head
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_update_hud()
	_check_join(delta)
	if net.mode == "client":
		if game_over:
			game_over_time += delta
			if game_over_time > 1.5 and _restart_pressed():
				game_over_time = 0.0
				net.send_action("restart", [])
		return
	if game_over:
		game_over_time += delta
		var vr_restart: bool = players[0].vr_trigger_held()
		if game_over_time > 1.5 and (_restart_pressed() or vr_restart):
			get_tree().reload_current_scene()
		return
	if net.mode == "host" and not net.connected:
		if wave == 0:
			director().howto()  # the VR player reads how to play while waiting
		return  # hold the waves until a TV player joins
	if wave == 0:
		director().howto()
	_update_cocoa(delta)
	boss_hp = -1.0
	for s in get_tree().get_nodes_in_group("snowmen"):
		if (s.kind == "king" or s.kind == "yeti") and not s.dead:
			boss_hp = maxf(0.0, s.hp / s.max_hp)
			boss_name = "THE YETI" if s.kind == "yeti" else "SNOW KING"
	if in_break:
		break_timer -= delta
		if break_timer <= 0.0:
			_start_wave()
	elif to_spawn > 0:
		spawn_timer -= delta
		var alive := get_tree().get_nodes_in_group("snowmen").size()
		var extra := extra_players()
		if spawn_timer <= 0.0 and alive < 6 + wave + extra * 2:
			_spawn_wave_snowman()
			to_spawn -= 1
			spawn_timer = maxf(0.45, (1.8 - wave * 0.1) / (1.0 + 0.15 * extra))
	elif get_tree().get_nodes_in_group("snowmen").is_empty():
		_end_wave()
	var all_down := true
	for p in players:
		if p.active and not p.is_down:
			all_down = false
	if all_down:
		_on_game_over("EVERYONE FROZE SOLID!")
	elif fort_fraction() <= 0.0:
		_on_game_over("THE FORT FELL!")


func _on_game_over(reason: String) -> void:
	game_over = true
	game_over_time = 0.0
	sound("gameover")
	print("Game over (%s): wave %d, score %d" % [reason, wave, score])
	var best := _load_best()
	var best_line := "Best: wave %d  ·  score %d" % [best.wave, best.score]
	if score > int(best.score):
		best_line = "NEW BEST SCORE!  (previous %d)" % best.score
		_save_best(wave, score)
	var saved := "The village was saved!  ·  " if director().won else ""
	_show_center("%s\nWave %d  ·  Score %d\n%s%s\n\n%s\n\nPress A / Enter (VR: trigger) to play again" % [reason, wave, score, saved, best_line, director().awards_text()], 0.0)


func _load_best() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load("user://snowball_blitz_best.cfg")
	return {"wave": cfg.get_value("best", "wave", 0), "score": cfg.get_value("best", "score", 0)}


func _save_best(best_wave: int, best_score: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("best", "wave", best_wave)
	cfg.set_value("best", "score", best_score)
	cfg.save("user://snowball_blitz_best.cfg")


func _restart_pressed() -> bool:
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_R):
		return true
	for id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(id, JOY_BUTTON_A):
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_F11:
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


# --- Players and views -------------------------------------------------------

## How many player nodes this mode has: the VR player + six TV players networked, six in split screen.
func _player_count(mode: String) -> int:
	return MAX_TV_PLAYERS + 1 if mode != "local" else MAX_TV_PLAYERS


func _spawn_spot(i: int, mode: String) -> Vector3:
	var tv: Array[Vector3] = [Vector3(-2.2, 0, 2.6), Vector3(2.2, 0, 2.6), Vector3(0, 0, 3.6), Vector3(-3.6, 0, 0.8),
		Vector3(3.6, 0, 0.8), Vector3(0, 0, -2.8)]
	if mode == "local":
		if i == 0:
			return Vector3(-2.0, 0, 2.6)
		if i == 1:
			return Vector3(2.0, 0, 2.6)
		return tv[clampi(i, 0, tv.size() - 1)]
	if i == 0:
		return Vector3.ZERO
	return tv[clampi(i - 1, 0, tv.size() - 1)]


## Creates any missing player nodes (lazily, so a hot reload of an older game grows the party too).
## Networked: VR player + TV players 2-7. Local split screen: players 1-6. As before, only the first
## two start in the game; the others wait (inactive) until someone presses A / Start on a controller.
func _build_players(mode: String) -> void:
	for i in range(players.size(), _player_count(mode)):
		var p := PlayerScript.new()
		p.index = i
		p.color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		p.main = self
		p.remote = mode == "host" and i >= 1
		p.ghost = mode == "client" and i == 0
		if mode == "local" and i == 0:
			p.mouse_look = true
		elif mode != "local" and i == 2:
			p.key_set = 0
			p.mouse_look = true
		elif i >= 2:
			p.key_set = -2  # extra players are controller-only
		p.position = _spawn_spot(i, mode)
		add_child(p)
		players.append(p)
		if i >= 2:
			p.set_active(false)


func _is_local_tv(p) -> bool:
	return not p.remote and not p.ghost and not p.vr


## Lazily grows the party / views / input hook (safe to call every frame).
func _ensure_party() -> void:
	if join_listener == null or not is_instance_valid(join_listener):
		join_listener = JoinInputScript.new()
		join_listener.main = self
		add_child(join_listener)
	if players.size() < _player_count(net.mode):
		_build_players(net.mode)
		_ensure_views()
		_sync_view_visibility()


func _apply_vr_performance() -> void:
	for n in get_children():
		if n is WorldEnvironment:
			var e: Environment = n.environment
			e.ssao_enabled = false
			e.fog_enabled = false
			e.glow_intensity = 0.6
		elif n is DirectionalLight3D:
			n.shadow_enabled = false


func _build_views(mode: String) -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized() and mode != "client":
		xr_interface = xr
		print("VR headset found: player 1 throws snowballs in VR")
		Engine.physics_ticks_per_second = 90
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_2X
		_apply_vr_performance()
		var origin := XROrigin3D.new()
		add_child(origin)
		origin.global_position = players[0].global_position
		var cam := XRCamera3D.new()
		origin.add_child(cam)
		var left := XRController3D.new()
		left.tracker = "left_hand"
		left.pose = "aim"
		origin.add_child(left)
		var right := XRController3D.new()
		right.tracker = "right_hand"
		right.pose = "aim"
		origin.add_child(right)
		players[0].attach_xr(origin, cam, left, right)
		_build_vr_mirror(cam)
		if mode == "local":
			_build_flat_window(players[1])
	elif OS.has_environment("BOT_VR") and mode != "client":
		# Test bots: the real VR code with XR nodes the bot moves by hand (no headset, no extra window).
		print("BOT_VR: fake VR snowball thrower")
		var origin := XROrigin3D.new()
		add_child(origin)
		origin.global_position = players[0].global_position
		var cam := XRCamera3D.new()
		origin.add_child(cam)
		cam.position = Vector3(0.0, 1.5, 0.0)
		var left := XRController3D.new()
		left.tracker = "left_hand"
		origin.add_child(left)
		left.position = Vector3(-0.25, 1.1, -0.3)
		var right := XRController3D.new()
		right.tracker = "right_hand"
		origin.add_child(right)
		right.position = Vector3(0.25, 1.2, -0.3)
		players[0].attach_xr(origin, cam, left, right)
		_build_vr_mirror(cam)
	else:
		print("No VR headset: split screen")
	_ensure_views()
	_sync_view_visibility()


## A split-screen view for every TV player on this machine, in a grid (hidden until they join).
func _ensure_views() -> void:
	if view_grid == null:
		var layer := CanvasLayer.new()
		layer.layer = -1
		add_child(layer)
		var bg := ColorRect.new()
		bg.color = Color(0.05, 0.05, 0.1)
		layer.add_child(bg)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		view_grid = GridContainer.new()
		view_grid.add_theme_constant_override("h_separation", 4)
		view_grid.add_theme_constant_override("v_separation", 4)
		layer.add_child(view_grid)
		view_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for p in players:
		if not _is_local_tv(p):
			continue
		if p.has_meta("view"):
			var old: Control = p.get_meta("view")
			if is_instance_valid(old) and old.get_parent() != view_grid and old is SubViewportContainer:
				old.reparent(view_grid, false)  # views made by an older version of this script
			continue
		if p.camera != null:
			continue  # e.g. player 2's own window when VR runs without a TV machine
		if players[0].vr and p.index >= 2:
			continue  # VR without a TV machine: only player 2's window (no screen for more)
		_build_view(p)


func _build_view(p) -> void:
	var container := SubViewportContainer.new()
	p.set_meta("view", container)
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view_grid.add_child(container)
	var vp := SubViewport.new()
	vp.world_3d = get_world_3d()
	vp.msaa_3d = Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	container.add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	cameras.append(cam)
	p.attach_camera(cam)
	var hud_layer := CanvasLayer.new()
	vp.add_child(hud_layer)
	var hud := HudScript.new()
	hud.player = p
	hud.main = self
	hud_layer.add_child(hud)
	p.hud = hud
	if net.mode == "client":
		if ghost_cam == null:
			_build_ghost_mirror()
		_add_bubble(hud, mirror_vp, PLAYER_COLORS[0])


func _sync_view_visibility() -> void:
	for p in players:
		if p.has_meta("view"):
			var v: Control = p.get_meta("view")
			v.visible = p.active
	_layout_views()


## 1 view full screen, 2 side by side, 3-4 as 2x2, 5-6 as 3x2. More views: lower 3D resolution.
func _layout_views() -> void:
	if view_grid == null:
		return
	var shown: Array[SubViewportContainer] = []
	for c in view_grid.get_children():
		var svc := c as SubViewportContainer
		if svc != null and svc.visible:
			shown.append(svc)
	var n := shown.size()
	view_grid.columns = 1 if n <= 1 else (2 if n <= 4 else 3)
	var scale_3d := 1.0 if n <= 2 else (0.7 if n <= 4 else 0.55)
	for svc in shown:
		for c in svc.get_children():
			var vp := c as SubViewport
			if vp != null:
				vp.scaling_3d_scale = scale_3d
				vp.msaa_3d = Viewport.MSAA_2X if n <= 2 else Viewport.MSAA_DISABLED
	for c in get_children():
		var sun := c as DirectionalLight3D
		if sun != null and sun.shadow_enabled:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if n <= 2 else DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = 45.0 if n <= 4 else 30.0
		var we := c as WorldEnvironment
		if we != null and we.environment != null:
			if not we.has_meta("base_glow"):
				we.set_meta("base_glow", we.environment.glow_enabled)
			we.environment.glow_enabled = bool(we.get_meta("base_glow")) and n <= 4


## Low-res copy of the VR view, recorded by gdev (group gdev_capture) so others can watch.
func _build_vr_mirror(xr_cam: XRCamera3D) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(480, 480)
	vp.world_3d = get_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	mirror_vp = vp
	vp.add_to_group("gdev_capture")
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 90.0
	cam.cull_mask = xr_cam.cull_mask
	vp.add_child(cam)
	cam.current = true
	var follow := RemoteTransform3D.new()
	xr_cam.add_child(follow)
	follow.remote_path = follow.get_path_to(cam)
	return vp


## Client: a camera that follows the VR player's replicated head, for the bubble view.
func _build_ghost_mirror() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(480, 480)
	vp.world_3d = get_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	mirror_vp = vp
	add_child(vp)
	ghost_cam = Camera3D.new()
	ghost_cam.fov = 90.0
	ghost_cam.cull_mask = players[0].camera_cull_mask()
	vp.add_child(ghost_cam)
	ghost_cam.current = true
	return vp


## Round picture-in-picture of the VR player's view on the TV player's HUD.
func _add_bubble(hud: Control, source: SubViewport, color: Color) -> void:
	var bubble := TextureRect.new()
	bubble.texture = source.get_texture()
	bubble.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bubble.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = BUBBLE_SHADER
	m.set_shader_parameter("ring_color", color)
	bubble.material = m
	hud.add_child(bubble)
	bubble.size = Vector2(260, 260)
	bubble.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 30)
	var tag := Label.new()
	tag.text = "P1 (VR)"
	tag.add_theme_font_size_override("font_size", 24)
	tag.add_theme_constant_override("outline_size", 6)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_color_override("font_color", color)
	bubble.add_child(tag)
	tag.position = Vector2(90, 262)


## VR without a TV machine: player 2 gets a window on this device.
func _build_flat_window(p) -> void:
	var win := Window.new()
	win.title = "Snowball Blitz - Player 2"
	win.size = Vector2i(1920, 1080)
	win.world_3d = get_world_3d()
	win.msaa_3d = Viewport.MSAA_2X
	win.content_scale_size = Vector2i(1920, 1080)
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.scaling_3d_scale = 0.6
	add_child(win)
	var cam := Camera3D.new()
	win.add_child(cam)
	cam.current = true
	cameras.append(cam)
	p.attach_camera(cam)
	var hud_layer := CanvasLayer.new()
	win.add_child(hud_layer)
	var hud := HudScript.new()
	hud.player = p
	hud.main = self
	hud_layer.add_child(hud)
	p.hud = hud
	if mirror_vp:
		_add_bubble(hud, mirror_vp, PLAYER_COLORS[0])


## Controllers fill these players in order at the start (as before): networked P2 then P3,
## local split screen P2 then P1. Any further controller joins with A / Start.
func _base_slots() -> Array[int]:
	var slots: Array[int] = []
	if net.mode == "client":
		slots = [1, 2]
	elif net.mode == "local" and players.size() > 1:
		slots.append(1)
		if not players[0].vr:
			slots.append(0)
	return slots


func _assign_joypads() -> void:
	var pads := Input.get_connected_joypads()
	var slots := _base_slots()
	for i in slots.size():
		var slot: int = slots[i]
		players[slot].joy = pads[i] if i < pads.size() else -1
		if i < pads.size():
			pad_memory[pads[i]] = slot


func _player_with_pad(device: int):
	for p in players:
		if p.joy == device and _is_local_tv(p):
			return p
	return null


## Each controller belongs to exactly one player (by device id). Unplugging a controller-only
## player makes them leave; plugging the same controller back in rejoins them.
func _on_joy_changed(device: int, connected: bool) -> void:
	if not ready_to_play:
		return
	if connected:
		if _player_with_pad(device) != null:
			return
		var back: int = pad_memory.get(device, -1)
		if back >= 0 and back < players.size() and _is_local_tv(players[back]) and players[back].joy < 0:
			players[back].joy = device
			print("Controller %d reconnected: P%d" % [device, back + 1])
			if not players[back].active and not players[back].has_keyboard():
				_request_join(back)
			return
		for slot in _base_slots():
			if players[slot].joy < 0:
				players[slot].joy = device
				pad_memory[device] = slot
				return
		print("Controller %d connected: press A / Start to join" % device)
	else:
		var p = _player_with_pad(device)
		if p == null:
			return
		p.joy = -1
		pad_memory[device] = p.index
		print("Controller %d disconnected (P%d)" % [device, p.index + 1])
		if p.active and not p.has_keyboard():
			_request_leave(p.index)


## The first TV player slot that's free for a new controller, or -1 when the party is full.
func _free_slot() -> int:
	for p in players:
		if _is_local_tv(p) and not p.active and p.joy < 0 and p.camera != null:
			return p.index
	return -1


## Called by join_input.gd: A / Start on a controller that isn't playing yet joins the game.
func handle_join_input(event: InputEvent) -> bool:
	var b := event as InputEventJoypadButton
	if b == null or not b.pressed or not ready_to_play or game_over or get_tree().paused or net.mode == "host":
		return false
	if b.button_index != JOY_BUTTON_A and b.button_index != JOY_BUTTON_START:
		return false
	var p = _player_with_pad(b.device)
	if p != null:
		if p.active:
			return false
		_request_join(p.index)
		return true
	var slot := _free_slot()
	if slot < 0:
		return false
	players[slot].joy = b.device
	pad_memory[b.device] = slot
	print("Controller %d is now P%d" % [b.device, slot + 1])
	_request_join(slot)
	return true


## A waiting player with a keyboard or controller joins by holding throw (as P3 always could).
func _check_join(_delta: float) -> void:
	if game_over or net.mode == "host":
		return
	for p in players:
		if p.active or not _is_local_tv(p) or p.camera == null:
			continue
		if (p.joy >= 0 or p.has_keyboard()) and p._throw_held():
			_request_join(p.index)


func _request_join(i: int) -> void:
	if net.mode == "client":
		var now := Time.get_ticks_msec()
		if now - int(join_sent.get(i, -100000)) < 800:
			return
		join_sent[i] = now
		net.send_action("join", [], i)
	else:
		_activate_player(i)


func _request_leave(i: int) -> void:
	if net.mode == "client":
		net.send_action("leave", [], i)
	else:
		_deactivate_player(i)


## Test hooks: spawn a kind, start a weather event, jump to a wave, grant every fort upgrade.
func debug_spawn(kind: String) -> void:
	if net.mode == "client":
		return
	var a := randf() * TAU
	var at := Vector3(cos(a), 0, sin(a)) * (ARENA_RADIUS - 1.0)
	if kind == "bunny":
		for i in 3:
			_spawn_snowman("bunny", at + Vector3(i - 1, 0, 0))
	else:
		_spawn_snowman(kind, at)


func debug_event(ev: String) -> void:
	director().start_event(ev)


func debug_skip_to_wave(n: int) -> void:
	if net.mode == "client":
		return
	for sm in get_tree().get_nodes_in_group("snowmen"):
		sm.remove_from_group("snowmen")
		sm.queue_free()
	to_spawn = 0
	wave = n - 1
	in_break = true
	break_timer = 0.5


func debug_upgrades() -> void:
	for w in director().UPGRADES:
		var u: Array = director().UPGRADES[w]
		if not director().upgrades.has(u[0]):
			director().upgrades.append(u[0])


## Test hook (bots / scripted demos): TV player i joins as if they pressed A on a new controller.
func debug_join(i: int) -> void:
	if i >= 0 and i < players.size() and _is_local_tv(players[i]) and not players[i].active:
		_request_join(i)


## Host / local: a player joins (fresh and warm).
func _activate_player(i: int) -> void:
	if i < 0 or i >= players.size() or players[i].active:
		return
	var p = players[i]
	p.set_active(true)
	p.hp = PlayerScript.MAX_HP
	if p.is_down:
		p.is_down = false
		p._apply_down_pose(false)
	p.invuln_t = 2.0
	if p.remote:
		p.net_started = false  # snap to the TV player's next reported position
	elif not p.vr:
		p.global_position = _spawn_spot(i, net.mode)
	_show_center("PLAYER %d JOINED!" % (i + 1), 1.5)
	print("Net: player %d joined the game (%d playing)" % [i + 1, party_size()])
	on_player_activity_changed(p)


## Host / local: a player leaves (their controller was unplugged).
func _deactivate_player(i: int) -> void:
	if i < 0 or i >= players.size() or not players[i].active:
		return
	var p = players[i]
	p.set_active(false)
	p.charging = false
	p.repairing = false
	if p.is_down:
		p.is_down = false
		p._apply_down_pose(false)
	_show_center("PLAYER %d LEFT" % (i + 1), 1.5)
	print("Net: player %d left the game (%d playing)" % [i + 1, party_size()])
	on_player_activity_changed(p)


func on_player_activity_changed(p) -> void:
	_sync_view_visibility()
	print("Player %d is now %s on this screen" % [p.index + 1, "playing" if p.active else "waiting"])


# --- Networked co-op (see docs/GAME_DEV_GUIDE.md) ----------------------------

func on_client_joined() -> void:
	_show_center("THE TV PLAYERS JOINED!", 1.5)


func on_client_left() -> void:
	_show_center("The TV players left - waiting for them to rejoin…", 0.0)


func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	if index < 0 or index >= players.size():
		return
	var p = players[index]
	match action:
		"throw":
			if not p.active or p.is_down:
				return
			stat_add(index, "thrown", 1)
			var r: float = clampf(args[2], 0.05, 0.3)
			var dmg: float = clampf(args[3], 0.5, 2.0)
			if p.mega and float(args[2]) >= MEGA_R * 0.9:
				p.mega = false
				r = MEGA_R
				dmg = MEGA_DMG
			spawn_ball(args[0], args[1], r, dmg, "p", index)
		"repair":
			if p.active and not p.is_down:
				repair_segment(int(args[0]), clampf(float(args[1]), 0.0, 8.0), index)
		"join":
			_activate_player(index)
		"leave":
			_deactivate_player(index)
		"restart":
			if game_over:
				get_tree().reload_current_scene()
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, "A TV player opened the menu")
			get_tree().paused = paused


func _set_pause_banner(paused: bool, who: String) -> void:
	_show_center("PAUSED\n" + who if paused else "", 0.0, false)
	_update_vr_center()


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_set_pause_banner(paused, "Press the menu button to resume")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var ps := []
	for p in players:
		var st := [p.global_position, p.yaw, p.pitch, p.hp, p.is_down, p.revive_progress, p.active, p.held_amount()]
		if p.index == 0:
			st.append_array([p.head_transform(), p.hand_transform(), p.left_hand_transform()])  # drawn on the TV
		if p.mega:
			st.append(true)  # MEGA SNOWBALL ready (left out when false: small snapshots)
		ps.append(st)
	var sm := []
	for s in get_tree().get_nodes_in_group("snowmen"):
		if not s.dead:
			var item := [s.net_id, s.kind, s.global_position, s.rotation.y, s.hp / s.max_hp, s.bashing]
			if s.net_aux() != 0:
				item.append(s.net_aux())  # balloons / shield, only for those kinds
			sm.append(item)
	var ck := []
	for c in get_tree().get_nodes_in_group("cocoa"):
		ck.append([c.net_id, c.global_position, c.kind] if c.kind != "cocoa" else [c.net_id, c.global_position])
	return [wave, score, game_over, seg_hp, ps, sm, ck, boss_hp, director().pack(), boss_name if boss_hp >= 0.0 else ""]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play:
		return
	synced = true
	wave = s[0]
	score = s[1]
	game_over = s[2]
	var hp_list: Array = s[3]
	for i in mini(SEGMENTS, hp_list.size()):
		seg_hp[i] = float(hp_list[i])
	var ps: Array = s[4]
	for i in mini(players.size(), ps.size()):
		players[i].apply_net_state(ps[i])
	_sync_ghosts(s[5], "snowman")
	_sync_ghosts(s[6], "cocoa")
	boss_hp = s[7]
	if s.size() > 9:
		director().unpack(s[8])
		boss_name = s[9]


func _sync_ghosts(list: Array, kind: String) -> void:
	var seen := {}
	for item in list:
		var key := "%s:%d" % [kind, item[0]]
		seen[key] = true
		var g = ghost_nodes.get(key)
		if g == null or not is_instance_valid(g):
			g = _make_ghost(kind, item)
			ghost_nodes[key] = g
		g.apply_net(item)
	for key in ghost_nodes.keys():
		if key.begins_with(kind + ":") and not seen.has(key):
			var g = ghost_nodes[key]
			if is_instance_valid(g):
				g.queue_free()
			ghost_nodes.erase(key)


func _make_ghost(kind: String, item: Array) -> Node3D:
	if kind == "snowman":
		var s := SnowmanScript.new()
		s.setup(item[1], maxi(wave, 1), self, 0)
		s.ghost = true
		s.net_id = item[0]
		s.position = item[2]
		s.rotation.y = item[3]
		add_child(s)
		return s
	var c := CocoaScript.new()
	c.main = self
	c.ghost = true
	c.net_id = item[0]
	c.position = item[1]
	if item.size() > 2:
		c.kind = item[2]
	add_child(c)
	return c


func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			sound(args[0], args[1], args[2])
		"burst":
			puff(args[0], args[1], args[2], args[3])
		"popup":
			popup(args[0], args[1], args[2])
		"collapse":
			collapse_fx(args[0], args[1], args[2])
		"ball":
			spawn_ball(args[0], args[1], args[2], 1.0, args[3], -1, true)
		"center":
			_show_center(args[0], args[1])
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The VR player paused the game")
		"hurt":
			var hi: int = args[0]
			players[hi].on_remote_hurt(args[1])
		"hitmark":
			var mi: int = args[0]
			if players[mi].hud:
				players[mi].hud.hit_marker()
		"hint", "catapult":
			director().client_event(kind, args)


# --- HUD ---------------------------------------------------------------------

func _make_label(font: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_constant_override("outline_size", maxi(6, font / 5))
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.1, 0.95))
	l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	info_label = _make_label(30)
	layer.add_child(info_label)
	info_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	info_label.offset_top = 18
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label = _make_label(58)
	layer.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	help_label = _make_label(22)
	layer.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	help_label.offset_top = 70
	help_label.offset_bottom = 170
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.text = "Controller: left stick move · right stick look · hold RT to charge a snowball, let go to throw · hold X / LB at a crumbling wall to pack it\n" \
		+ "Keyboard: P1 WASD + mouse, hold click / Space to throw, E / right-click to pack  ·  P2 arrows, Enter throw, Ctrl pack\n" \
		+ "More controllers: press A / Start to join (up to 6 TV players)  ·  Grab hot cocoa to warm up · stand next to a frozen friend to thaw them\n" \
		+ "Survive %d waves and beat the YETI to save the village!" % FINALE_WAVE


func _show_center(text: String, duration: float, broadcast: bool = true) -> void:
	if net and broadcast:
		net.event("center", [text, duration])
	center_label.text = text
	center_label.add_theme_font_size_override("font_size", 58 if text.count("\n") < 6 else 36)
	center_label.modulate.a = 1.0
	if center_tween:
		center_tween.kill()
	if duration > 0.0:
		center_tween = create_tween()
		center_tween.tween_interval(duration)
		center_tween.tween_property(center_label, "modulate:a", 0.0, 0.5)


func _update_hud() -> void:
	if net.mode == "client" and not synced:
		info_label.text = "Syncing with the VR player…"
		return
	var wave_text := ("WAVE %d / %d" % [wave, FINALE_WAVE]) if wave <= FINALE_WAVE and not director().won else ("WAVE %d  ENDLESS" % wave)
	info_label.text = "%s      SCORE %d      FORT %d%%" % [wave_text, score, int(fort_fraction() * 100.0)]
	var boss := boss_text()
	if boss != "":
		info_label.text += "      " + boss
	var ev: String = director().event_name
	if ev != "":
		info_label.text += "\n" + str(director().EVENTS[ev][0])


## VR can't show 2D overlays: mirror the centre banner on a panel in front of the VR player.
func _update_vr_center() -> void:
	if players.is_empty() or not players[0].vr:
		return
	if vr_center == null:
		vr_center = Label3D.new()
		vr_center.font_size = 48
		vr_center.outline_size = 26
		vr_center.no_depth_test = true
		vr_center.render_priority = 10
		vr_center.outline_render_priority = 9
		vr_center.width = 900.0
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vr_center.pixel_size = 0.0026
		vr_center.position = Vector3(0.0, -0.1, -1.8)
		vr_center.modulate = Color(1.0, 0.95, 0.85)
		players[0].xr_camera.add_child(vr_center)
		players[0]._set_layers(vr_center, players[0].viewmodel_layer())
	vr_center.text = center_label.text
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate = Color(0, 0, 0, center_label.modulate.a)
	VrText.follow(vr_center, players[0].xr_camera, self, -0.1, 1.8)


func vr_hurt_flash() -> void:
	vr_hurt = 1.0


## A frosty shell around the VR player's head that flashes when they're hit.
func _update_vr_hurt(delta: float) -> void:
	if players.is_empty() or not players[0].vr:
		return
	var p = players[0]
	if vr_hurt_mat == null:
		var shell := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.25
		sphere.height = 0.5
		sphere.radial_segments = 16
		sphere.rings = 8
		shell.mesh = sphere
		vr_hurt_mat = StandardMaterial3D.new()
		vr_hurt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		vr_hurt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		vr_hurt_mat.cull_mode = BaseMaterial3D.CULL_FRONT
		vr_hurt_mat.no_depth_test = true
		vr_hurt_mat.render_priority = 20
		vr_hurt_mat.albedo_color = Color(0.7, 0.9, 1.0, 0.0)
		shell.material_override = vr_hurt_mat
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.xr_camera.add_child(shell)
		p._set_layers(shell, p.viewmodel_layer())
	vr_hurt = maxf(0.0, vr_hurt - delta * 3.0)
	var cold := 0.25 if p.is_down else (0.08 if p.hp < 30.0 else 0.0)
	vr_hurt_mat.albedo_color.a = maxf(vr_hurt * 0.35, cold)
