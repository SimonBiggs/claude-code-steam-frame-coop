extends Node3D
## PAPER PLANES: everyone sends paper planes through slowly drifting hoops for one team score.
## VR: grab a plane from the paper stack beside you (touch it, or pull the trigger anywhere) and
## throw it with a flick (or let go of the trigger). TV: each player flies a little plane with the
## left stick. A rainbow hoop is worth 3. Rounds last `round_time` s, then a results screen and an
## automatic next round. Built on the shared engine (see games/engine_template).

const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const Party := preload("res://core/party.gd")
const SplitView := preload("res://core/split_view.gd")
const VrRig := preload("res://core/vr_rig.gd")
const Save := preload("res://core/save.gd")
const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const Hints := preload("res://core/hints.gd")
const Awards := preload("res://core/awards.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Creatures := preload("res://core/creatures.gd")
const SkyKit := preload("res://core/sky_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Meshes := preload("res://games/paper_planes/meshes.gd")

const GAME_ID := "paper_planes"
const VR_FEET := Vector3(0.0, 0.0, 5.0)
const HOOP_MIN := Vector3(-6.5, 1.4, -10.0)  ## hoops drift around inside this box
const HOOP_MAX := Vector3(6.5, 4.8, 1.8)
const HOOP_COUNT := 5
const FLY_SPEED := 6.5  ## TV planes always fly forward
const TURN_RATE := 1.9
const PITCH_MAX := 0.65
const DART_SCALE := 0.3  ## the VR player's paper planes are 30 cm long
const MAX_DARTS := 10
const STACK_OFFSET := Vector3(0.5, 0.0, -0.35)  ## from the VR rig's origin: right, a bit ahead
const STACK_TOP := 0.95
const SIGN_POS := Vector3(0.0, 8.0, -19.0)

var round_time := 150.0  ## seconds per round (bots shorten it)
var results_wait := 12.0  ## then the next round starts by itself


class Hoop:
	var id := 0
	var kind := 0  # 0 plain, 1 rainbow (3 points)
	var ci := 0
	var node: Node3D
	var mesh: MeshInstance3D
	var home := Vector3.ZERO
	var amp := 1.0
	var phase := 0.0
	var yaw0 := 0.0
	var wob := 0.0
	var age := 0.0
	var target := Vector3.ZERO
	var target_yaw := 0.0


class Dart:  # one of the VR player's paper planes
	var id := 0
	var node: Node3D
	var body: Node3D
	var state := 0  # 0 held, 1 flying, 2 landed
	var hand := 1
	var ci := 0
	var vel := Vector3.ZERO
	var prev := Vector3.ZERO
	var t := 0.0
	var size := 1.0
	var target := Vector3.ZERO
	var dir := Vector3.FORWARD


class Flyer:  # a TV player's plane
	var slot := 0
	var node: Node3D
	var body: Node3D
	var yaw := PI
	var pitch := 0.0
	var roll := 0.0
	var loop_t := -1.0
	var prev := Vector3.ZERO
	var target := Vector3.ZERO
	var target_yaw := PI
	var target_pitch := 0.0
	var has_target := false
	var bop_cd := 0.0
	var cam_ready := false


# --- The networking contract ---
var net: Node
var ready_to_play := false
# --- Engine modules ---
var party: Party
var split: SplitView
var vr_rig: VrRig
var save: Save
var sfx: Node
var music: Node
var hints: Hints
var awards: Awards
var sky: SkyKit.SkyRig

var hoops := {}  # id -> Hoop
var darts := {}  # id -> Dart
var flyers := {}  # slot -> Flyer
var held: Array = [null, null]  # VR: the Dart in each hand
var hand_cd := PackedFloat32Array([0.0, 0.0])
var respawns: Array[float] = []
var next_id := 0
var clock := 0.0
var time_left := 0.0
var results_t := 0.0
var send_t := 0.0
var stack_node: Node3D
var stack_mesh: MeshInstance3D
var stack_wob := 0.0
var sign_score: Label3D
var sign_time: Label3D
var huds := {}  # slot -> UiKit root (-1 = shared view)
var score_labels := {}
var timers := {}
var join_prompt: Control
var vr_avatar: VrRig.Avatar
var vr_banner: Node3D
var tv_banner: Control
var results_ui: Control
var vr_results: Node
var throws := 0  # host: darts thrown (bots read it)
var hoops_passed := 0  # host / local: hoops flown through this session
var scored_by := {}  # host / local: slot -> hoops this session (bots)


func _ready() -> void:
	var menu := PauseMenuScript.new()
	menu.main = self
	add_child(menu)
	net = NetScript.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	net.state_changed.connect(_on_state_changed)
	party = Party.new()
	party.name = "Party"
	add_child(party)
	party.player_joined.connect(_on_player_joined)
	party.player_left.connect(_on_player_left)
	save = Save.new()
	save.game_id = GAME_ID
	save.defaults = {"best": 0}
	add_child(save)
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("party")
	music.prepare(["victory"])
	awards = Awards.new()
	awards.define("rainbow", "RAINBOW ACE", "%s rainbow hoops", "rainbows")
	hints = Hints.new()
	add_child(hints)
	hints.bind_party(party)
	if OS.has_environment("DUO_JOIN"):
		net.join_finished.connect(func(ok: bool) -> void: _setup("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if VrRig.headset_available() or OS.has_environment("DUO_HOST"):
			net.host()
		_setup(net.mode)


func _setup(mode: String) -> void:
	if VrRig.wanted(mode):
		vr_rig = VrRig.new()
		vr_rig.bounds = Rect2(-4.0, 2.5, 8.0, 5.0)
		add_child(vr_rig)
		vr_rig.place(VR_FEET, 0.0)
		hints.set_vr_rig(vr_rig, self)
	_build_world()
	if vr_rig != null or mode == "client":
		stack_node = Node3D.new()
		stack_node.name = "PaperStack"
		add_child(stack_node)
		stack_mesh = MeshKit.instance(Meshes.stack(), false)
		stack_node.add_child(stack_mesh)
		stack_node.position = VR_FEET + STACK_OFFSET
		stack_node.visible = vr_rig != null
	if mode != "host":
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		var sc := split.shared_camera()
		sc.position = Vector3(0.0, 9.0, 17.0)
		sc.look_at(Vector3(0.0, 2.5, -4.0), Vector3.UP)
		_make_hud(-1, split.shared_hud())
		hints.add_view(huds[-1], -1)
		if mode == "client":
			vr_avatar = VrRig.Avatar.new()
			add_child(vr_avatar)
			split.set_bubble(VrRig.build_mirror(self, vr_avatar.head, false))
		elif vr_rig != null:
			split.set_bubble(vr_rig.mirror)
		sfx.play_loop("wind", -20.0)
	party.allow_slot0 = mode == "local" and vr_rig == null
	if vr_rig != null:
		awards.set_player(0, "THROWER")
		hints.hint("vr_grab", "Grab a plane. Throw it!", {"to": "vr", "icon": "play"})
	if mode != "client":
		net.state_set("best", int(save.data["best"]))
		_start_round()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Paper Planes: %s mode%s" % [mode, " with a VR player" if vr_rig != null else ""])


# --- World --------------------------------------------------------------------------------

func _build_world() -> void:
	sky = SkyKit.apply(self, "day", vr_rig != null)
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 45.0
	disc.bottom_radius = 45.0
	disc.height = 0.2
	disc.radial_segments = 40
	ground.mesh = disc
	ground.material_override = MeshKit.material(Color(0.5, 0.78, 0.38))
	ground.position.y = -0.1
	add_child(ground)
	add_child(MeshKit.scatter_random(MeshKit.prop("tree"), 22, Vector3(0.0, 0.0, -4.0), 34.0, 24.0, 1.2, 1.9, PackedColorArray(), 3))
	add_child(MeshKit.scatter_random(MeshKit.prop("bush"), 14, Vector3(0.0, 0.0, -4.0), 22.0, 14.0, 1.0, 1.5, PackedColorArray(), 4))
	add_child(MeshKit.scatter_random(MeshKit.prop("flower"), 60, Vector3(0.0, 0.0, -4.0), 16.0, 1.0, 0.8, 1.2,
		PackedColorArray([Color(1.0, 0.5, 0.6), Color(1.0, 0.9, 0.4), Color(0.7, 0.6, 1.0), Color(1.0, 1.0, 1.0)]), 5))
	# The launch deck the VR player stands on.
	var b := MeshKit.Builder.new()
	b.cylinder(1.3, 1.4, 0.12, MeshKit.at(Vector3(0.0, 0.06, 0.0)), Color(0.85, 0.65, 0.42), 24)
	b.cylinder(1.0, 1.0, 0.02, MeshKit.at(Vector3(0.0, 0.13, 0.0)), Color(0.95, 0.85, 0.55), 24)
	var deck := MeshKit.instance(b.build(), false)
	deck.position = VR_FEET
	add_child(deck)
	# The big world-locked scoreboard in the sky (readable from VR, seen by the TV planes too).
	sign_score = UiKit.label3d("0", 2.4, "gold", true)
	sign_score.outline_size = 26
	sign_score.position = SIGN_POS
	add_child(sign_score)
	sign_time = UiKit.label3d("", 0.9, "text", true)
	sign_time.outline_size = 26
	sign_time.position = SIGN_POS + Vector3(0.0, -1.9, 0.0)
	add_child(sign_time)


# --- HUD ----------------------------------------------------------------------------------

func _make_hud(slot: int, parent: Control) -> void:
	var ui := UiKit.ui_root(parent)
	huds[slot] = ui
	var card := UiKit.panel("card")
	ui.add_child(card)
	card.position = Vector2(24.0, 20.0)
	var row := UiKit.hbox()
	card.add_child(row)
	if slot >= 0:
		row.add_child(UiKit.badge(party.name_of(slot), slot))
	row.add_child(UiKit.icon("star", "gold", 38.0))
	var l := UiKit.label("0", "number")
	row.add_child(l)
	score_labels[slot] = l
	timers[slot] = HudKit.timer(ui, {"seconds": float(net.state_get("time", round_time)), "warn": 10})
	if slot < 0:
		join_prompt = UiKit.panel("pill")
		join_prompt.add_child(UiKit.prompts([["A", "Join"]]))
		ui.add_child(join_prompt)
		join_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		join_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
		join_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
		join_prompt.offset_top = -60.0
		join_prompt.offset_bottom = -60.0
	_refresh_hud()


func _refresh_hud() -> void:
	var score := int(net.state_get("score", 0))
	for slot in score_labels:
		var l: Label = score_labels[slot]
		if is_instance_valid(l):
			l.text = str(score)
	if join_prompt != null:
		join_prompt.visible = party.local_slots().is_empty()
	if sign_score != null:
		sign_score.text = str(score)


func _all_huds() -> Array:
	var out: Array = []
	for k in huds:
		if is_instance_valid(huds[k]):
			out.append(huds[k])
	return out


# --- TV players ---------------------------------------------------------------------------

func _on_player_joined(slot: int, _device: int) -> void:
	_ensure_flyer(slot)
	if party.is_local(slot) and split != null:
		_make_hud(slot, split.hud(slot))
		hints.add_view(huds[slot], slot)
		hints.hint("fly", "Fly through the hoops!", {"to": slot, "icon": "star"})
	awards.set_player(slot, party.name_of(slot))
	_refresh_hud()
	sound("ui_notify", -6.0)


func _on_player_left(slot: int) -> void:
	if flyers.has(slot):
		var f: Flyer = flyers[slot]
		f.node.queue_free()
		flyers.erase(slot)
	if huds.has(slot):
		var h: Control = huds[slot]
		if is_instance_valid(h):
			h.queue_free()
		huds.erase(slot)
	score_labels.erase(slot)
	timers.erase(slot)
	hints.remove_view(slot)
	_refresh_hud()


func _ensure_flyer(slot: int) -> Flyer:
	if flyers.has(slot):
		return flyers[slot]
	var f := Flyer.new()
	f.slot = slot
	f.node = Node3D.new()
	f.node.name = "Plane%d" % slot
	add_child(f.node)
	f.body = Node3D.new()
	f.node.add_child(f.body)
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.plane()
	mi.material_override = Meshes.plane_material(party.color_of(slot).lerp(Color.WHITE, 0.2))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.body.add_child(mi)
	var pilot := Creatures.humanoid({"class": "pilot", "outfit": party.color_of(slot), "seed": slot, "scale": 0.3, "lod": "far"})
	pilot.position = Vector3(0.0, 0.0, 0.12)
	pilot.rotation.y = PI  # creatures face +Z, the plane's nose is -Z
	f.body.add_child(pilot)
	var trail := CPUParticles3D.new()
	trail.amount = 16
	trail.lifetime = 0.6
	trail.local_coords = false
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 0.1
	trail.scale_amount_min = 0.6
	trail.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	trail.scale_amount_curve = curve
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = MeshKit.material(party.color_of(slot).lerp(Color.WHITE, 0.5), 1.0)
	trail.mesh = sm
	trail.position = Vector3(0.0, 0.0, 0.5)
	f.node.add_child(trail)
	if vr_rig == null:  # nameplates billboard: TV only
		HudKit.nameplate(f.node, party.name_of(slot), slot, 0.6, 0.18)
	var lane := float((slot - 1) % 5) - 2.0
	f.node.position = Vector3(lane * 3.0, 3.0 + absf(lane) * 0.4, -15.0)
	f.prev = f.node.position
	f.target = f.node.position
	f.node.basis = Basis.from_euler(Vector3(0.0, f.yaw, 0.0))
	flyers[slot] = f
	return f


## The TV machine (and local play) flies its own planes instantly and tells the host where they are.
func _fly_local(delta: float) -> void:
	send_t -= delta
	var send := send_t <= 0.0
	if send:
		send_t = 1.0 / 30.0
	var playing := String(net.state_get("phase", "play")) == "play"
	for slot in party.local_slots():
		if not flyers.has(slot):
			continue
		var f: Flyer = flyers[slot]
		var mv := party.stick(slot, "move") if playing else Vector2.ZERO
		var yaw_rate := -mv.x * TURN_RATE
		var want_pitch := -mv.y * PITCH_MAX
		var p := f.node.position
		var fwd := _forward(f.yaw, f.pitch)
		# A gentle helping hand towards a hoop just ahead.
		var aim: Variant = _assist_target(p, fwd, 11.0, 0.5)
		if aim != null:
			var d: Vector3 = (aim as Vector3) - p
			yaw_rate += clampf(wrapf(atan2(-d.x, -d.z) - f.yaw, -PI, PI) * 1.4, -0.9, 0.9)
			if absf(mv.y) < 0.3:
				want_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -PITCH_MAX, PITCH_MAX)
		# Stay in the sky over the park.
		if absf(p.x) > 14.0 or p.z < -21.0 or p.z > 11.0:
			var c := Vector3(-p.x, 0.0, -4.0 - p.z)
			yaw_rate += clampf(wrapf(atan2(-c.x, -c.z) - f.yaw, -PI, PI) * 2.0, -TURN_RATE, TURN_RATE)
		if p.y < 1.0:
			want_pitch = maxf(want_pitch, 0.35)
		elif p.y > 9.5:
			want_pitch = minf(want_pitch, -0.3)
		f.yaw = wrapf(f.yaw + yaw_rate * delta, -PI, PI)
		f.pitch = lerpf(f.pitch, want_pitch, 1.0 - exp(-3.0 * delta))
		f.roll = lerpf(f.roll, clampf(yaw_rate * 0.45, -0.8, 0.8), 1.0 - exp(-5.0 * delta))
		f.prev = p
		p += _forward(f.yaw, f.pitch) * FLY_SPEED * delta
		f.node.position = p
		f.node.basis = Basis.from_euler(Vector3(f.pitch, f.yaw, 0.0))
		if net.mode == "client":
			if send:
				net.send_state(p, f.yaw, f.pitch, slot)
		elif playing:
			var id := _check_pass(f.prev, p, 0.3)
			if id >= 0:
				_score_hoop(id, slot, p)
		_chase_camera(f, delta)


func _chase_camera(f: Flyer, delta: float) -> void:
	if split == null:
		return
	var cam := split.camera(f.slot)
	if cam == null:
		return
	var p := f.node.position
	var flat := Vector3(-sin(f.yaw), 0.0, -cos(f.yaw))
	var want := p - flat * 4.4 + Vector3.UP * (1.4 - f.pitch * 1.5)
	if not f.cam_ready:
		f.cam_ready = true
		cam.global_position = want
	cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-5.0 * delta))
	var look := p + _forward(f.yaw, f.pitch) * 3.0 + Vector3.UP * 0.3
	if cam.global_position.distance_to(look) > 0.1:
		cam.look_at(look, Vector3.UP)


## Every machine: planes the host only hears about glide to their reported spot; barrel rolls.
func _animate_flyers(delta: float) -> void:
	for slot in flyers:
		var f: Flyer = flyers[slot]
		f.bop_cd -= delta
		if f.has_target and not party.is_local(int(slot)):
			var k := 1.0 - exp(-15.0 * delta)
			var old_yaw := f.yaw
			f.node.position = f.node.position.lerp(f.target, k)
			f.yaw = lerp_angle(f.yaw, f.target_yaw, k)
			f.pitch = lerpf(f.pitch, f.target_pitch, k)
			var rate := wrapf(f.yaw - old_yaw, -PI, PI) / maxf(delta, 0.001)
			f.roll = lerpf(f.roll, clampf(rate * 0.45, -0.8, 0.8), 1.0 - exp(-5.0 * delta))
			f.node.basis = Basis.from_euler(Vector3(f.pitch, f.yaw, 0.0))
		var spin := 0.0
		if f.loop_t >= 0.0:
			f.loop_t += delta / 0.7
			spin = ease(minf(f.loop_t, 1.0), -2.0) * TAU
			if f.loop_t >= 1.0:
				f.loop_t = -1.0
				spin = 0.0
		f.body.rotation = Vector3(0.0, 0.0, f.roll + spin)


## Host: a TV player's plane moved on the TV machine.
func on_remote_state(slot: int, pos: Vector3, yaw: float, pitch: float) -> void:
	if not party.is_active(slot):
		return  # a late (unreliable) packet from a player who just left: don't bring back a ghost plane
	var f := _ensure_flyer(slot)
	var from := f.target if f.has_target else pos
	f.target = pos
	f.target_yaw = yaw
	f.target_pitch = pitch
	if not f.has_target:
		f.has_target = true
		f.node.position = pos
	if String(net.state_get("phase", "")) == "play":
		var id := _check_pass(from, pos, 0.3)
		if id >= 0:
			_score_hoop(id, slot, pos)


static func _forward(yaw: float, pitch: float) -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


# --- Hoops (host / local simulate; the TV machine mirrors) -------------------------------------

func _make_hoop(id: int, kind: int, ci: int, pos: Vector3) -> Hoop:
	var h := Hoop.new()
	h.id = id
	h.kind = kind
	h.ci = ci
	h.node = Node3D.new()
	h.node.name = "Hoop%d" % id
	add_child(h.node)
	h.node.position = pos
	h.mesh = MeshKit.instance(Meshes.hoop(kind, ci), false)
	h.mesh.scale = Vector3.ONE * 0.01
	h.node.add_child(h.mesh)
	if kind == 1:
		var sp := CPUParticles3D.new()
		sp.amount = 12
		sp.lifetime = 1.2
		sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		sp.emission_sphere_radius = 1.0
		sp.gravity = Vector3(0.0, 0.4, 0.0)
		sp.initial_velocity_max = 0.2
		sp.mesh = ResCache.get_or_make("pp_sparkle_v1", func() -> Resource:
			var bm := BoxMesh.new()
			bm.size = Vector3.ONE * 0.07
			bm.material = MeshKit.material(Color(1.0, 0.95, 0.6), 2.0)
			return bm)
		h.node.add_child(sp)
	h.target = pos
	hoops[id] = h
	return h


func _spawn_hoop(first: bool = false) -> void:
	next_id += 1
	var kind := 0
	var has_rainbow := false
	for id in hoops:
		if (hoops[id] as Hoop).kind == 1:
			has_rainbow = true
	if not first and not has_rainbow and randf() < 0.25:
		kind = 1
	var home := Vector3(0.0, 1.5, 2.3)
	if not first:
		for attempt in 14:
			home = Vector3(randf_range(HOOP_MIN.x, HOOP_MAX.x), randf_range(HOOP_MIN.y, HOOP_MAX.y), randf_range(HOOP_MIN.z, HOOP_MAX.z))
			var ok := true
			for id in hoops:
				if (hoops[id] as Hoop).home.distance_to(home) < 3.2:
					ok = false
			if ok:
				break
	var h := _make_hoop(next_id, kind, next_id % Meshes.HOOP_COLORS.size(), home)
	h.home = home
	h.amp = 0.25 if first else randf_range(0.7, 1.1)
	h.phase = randf() * TAU
	var to_vr := VR_FEET - home
	h.yaw0 = atan2(to_vr.x, to_vr.z) + (0.0 if first else randf_range(-0.4, 0.4))
	_move_hoop(h)
	sfx.play("pop", -10.0, 1.4)


func _move_hoop(h: Hoop) -> void:
	var t := clock
	h.node.position = h.home + Vector3(sin(t * 0.33 + h.phase) * 1.3, sin(t * 0.51 + h.phase * 1.7) * 0.45,
		sin(t * 0.26 + h.phase * 0.6) * 0.9) * h.amp
	h.node.rotation.y = h.yaw0 + sin(t * 0.21 + h.phase) * 0.3 * h.amp


## Every machine: pop-in, wobble and the rainbow's spin.
func _animate_hoops(delta: float) -> void:
	for id in hoops:
		var h: Hoop = hoops[id]
		h.age += delta
		h.wob = move_toward(h.wob, 0.0, delta * 1.4)
		var grow := clampf(h.age / 0.5, 0.0, 1.0)
		var s := (1.0 + sin(grow * PI) * 0.25) * grow if grow < 1.0 else 1.0
		s *= 1.0 + sin(clock * 20.0) * 0.14 * h.wob
		h.mesh.scale = Vector3.ONE * maxf(s, 0.01)
		if h.kind == 1:
			h.mesh.rotation.z += delta * 1.2


## Which hoop the segment from -> to flies through (its id), or -1.
func _check_pass(from: Vector3, to: Vector3, margin: float) -> int:
	if from.is_equal_approx(to):
		return -1
	for id in hoops:
		var h: Hoop = hoops[id]
		if h.age < 0.4:
			continue
		var inv := h.node.global_transform.affine_inverse()
		var a := inv * from
		var b := inv * to
		if (a.z > 0.0) == (b.z > 0.0):
			continue
		var c := a.lerp(b, a.z / (a.z - b.z))
		if Vector2(c.x, c.y).length() < Meshes.HOOP_R + margin:
			return int(id)
	return -1


## The centre of the best hoop ahead of `pos` along `dir` (within `max_angle` rad), or null.
func _assist_target(pos: Vector3, dir: Vector3, max_dist: float, max_angle: float) -> Variant:
	var best: Variant = null
	var best_a := max_angle
	for id in hoops:
		var h: Hoop = hoops[id]
		if h.age < 0.4:
			continue
		var d := h.node.position - pos
		if d.length() > max_dist or d.length() < 0.3:
			continue
		var a := dir.angle_to(d)
		var facing := absf(d.normalized().dot(h.node.global_basis.z))
		if a < best_a and facing > 0.35:
			best_a = a
			best = h.node.position
	return best


func _score_hoop(id: int, by: int, pos: Vector3) -> void:
	var h: Hoop = hoops[id]
	var pts := 3 if h.kind == 1 else 1
	hoops.erase(id)
	var at := h.node.position
	h.node.queue_free()
	respawns.append(1.2)
	hoops_passed += 1
	scored_by[by] = int(scored_by.get(by, 0)) + 1
	awards.add(by, "score", pts)
	if h.kind == 1:
		awards.add(by, "rainbows")
	var score := int(net.state_get("score", 0)) + pts
	net.state_set("score", score)
	if score > int(save.data["best"]):
		save.data["best"] = score
		save.mark_dirty()
		net.state_set("best", score)
	hoop_fx(at, h.kind, h.ci, by, pts)
	net.event("pass", [id, at, by, h.kind, h.ci, pts])


## Burst, "+1", sounds, rumble: on both machines.
func hoop_fx(at: Vector3, kind: int, ci: int, by: int, pts: int) -> void:
	var cols: Array[Color] = [Meshes.HOOP_COLORS[ci % Meshes.HOOP_COLORS.size()], Color.WHITE]
	if kind == 1:
		cols = Meshes.RAINBOW.duplicate()
	burst(at, cols, 40 if kind == 1 else 22, 1.0 if kind == 1 else 0.7)
	HudKit.score(self, at + Vector3.UP * 1.1, pts, {"color": "gold" if kind == 1 else party.color_of(by), "size": 3.0 if kind == 1 else 2.2})
	sfx.play_at("ding", at, 0.0, 1.0 + randf() * 0.15)
	sfx.play("sparkle", -6.0)
	if kind == 1:
		sfx.play("achievement", -2.0)
	if sign_score != null:
		var tw := sign_score.create_tween()
		sign_score.scale = Vector3.ONE * 1.3
		tw.tween_property(sign_score, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if by > 0 and party.is_local(by):
		party.rumble(by, 0.4, 0.7, 0.25)
	if by == 0 and vr_rig != null:
		vr_rig.pulse(VrRig.LEFT, 0.6, 0.1)
		vr_rig.pulse(VrRig.RIGHT, 0.6, 0.1)


func burst(at: Vector3, cols: Array[Color], amount: int, speed: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector3(0.0, -4.0, 0.0)
	p.initial_velocity_min = 3.0 * speed
	p.initial_velocity_max = 6.0 * speed
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6
	# Cached: one confetti mesh, one colour ramp per palette (no allocations per burst).
	p.mesh = ResCache.get_or_make("pp_confetti_v1", func() -> Resource:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.12, 0.02)
		bm.material = MeshKit.vertex_material(true)
		return bm)
	var key := "pp_ramp"
	for c in cols:
		key += "_" + c.to_html(false)
	p.color_initial_ramp = ResCache.get_or_make(key, func() -> Resource:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0])
		g.colors = PackedColorArray([cols[0]])
		for i in range(1, cols.size()):
			g.add_point(float(i) / float(cols.size() - 1), cols[i])
		return g)
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	add_child(p)
	p.position = at
	p.emitting = true
	get_tree().create_timer(1.3).timeout.connect(p.queue_free)


# --- The VR player's paper planes (host / local) --------------------------------------------

func _make_dart(id: int, ci: int) -> Dart:
	var d := Dart.new()
	d.id = id
	d.ci = ci
	d.node = Node3D.new()
	d.node.name = "Dart%d" % id
	add_child(d.node)
	d.body = MeshInstance3D.new()
	(d.body as MeshInstance3D).mesh = Meshes.plane()
	(d.body as MeshInstance3D).material_override = Meshes.plane_material(Meshes.HOOP_COLORS[ci % Meshes.HOOP_COLORS.size()].lerp(Color.WHITE, 0.45))
	(d.body as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	d.body.scale = Vector3.ONE * DART_SCALE
	d.node.add_child(d.body)
	darts[id] = d
	return d


func _vr_hands(delta: float) -> void:
	var o := vr_rig.global_transform
	var sp := o * STACK_OFFSET
	sp.y = vr_rig.floor_height
	stack_node.global_position = sp
	stack_node.rotation.y = vr_rig.global_rotation.y
	stack_wob = move_toward(stack_wob, 0.0, delta * 2.0)
	stack_mesh.rotation = Vector3(sin(clock * 24.0) * 0.06 * stack_wob, 0.0, cos(clock * 21.0) * 0.06 * stack_wob)
	var top := sp + Vector3.UP * STACK_TOP
	var fwd := vr_rig.head_forward()
	for w in 2:
		hand_cd[w] -= delta
		var d: Dart = held[w]
		if d == null:
			var near := vr_rig.touching(w, top, 0.28)
			if near and stack_wob < 0.5:
				stack_wob = 1.0
				sfx.play("card", -8.0, 1.3)
			if (near and hand_cd[w] <= 0.0) or (w == VrRig.RIGHT and vr_rig.trigger_pressed()):
				_grab(w)
		else:
			var hv := vr_rig.hand_velocity(w)
			var flick := hv.length() > 2.4 and hv.dot(fwd) > 1.4
			if flick or (w == VrRig.RIGHT and vr_rig.trigger_released()):
				_throw(w)
			else:
				var hand := vr_rig.hand(w)
				var b := hand.global_basis.orthonormalized()
				d.node.global_transform = Transform3D(b, vr_rig.hand_point(w) - b.z * 0.07)
	# Everything in reach reacts: hoops wobble, TV planes do a barrel roll.
	for id in hoops:
		var h: Hoop = hoops[id]
		var hand_i := -1
		for w in 2:
			var lp := h.node.global_transform.affine_inverse() * vr_rig.hand_point(w)
			if absf(Vector2(lp.x, lp.y).length() - Meshes.HOOP_R - 0.1) < 0.2 and absf(lp.z) < 0.25:
				hand_i = w
		if hand_i >= 0 and h.wob < 0.4:
			h.wob = 1.0
			sfx.play_at("boing", h.node.position, -4.0)
			vr_rig.pulse(hand_i, 0.5, 0.08)
			net.event("wob", [int(id)])
	for slot in flyers:
		var f: Flyer = flyers[slot]
		if f.bop_cd <= 0.0 and vr_rig.touching_any(f.node.position, 0.55) >= 0:
			_bop(int(slot))


func _grab(w: int) -> void:
	next_id += 1
	var d := _make_dart(next_id, next_id % Meshes.HOOP_COLORS.size())
	d.hand = w
	held[w] = d
	d.node.global_position = vr_rig.hand_point(w)
	d.body.scale = Vector3.ONE * 0.05
	var tw := d.body.create_tween()
	tw.tween_property(d.body, "scale", Vector3.ONE * DART_SCALE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	stack_wob = 1.0
	sfx.play("card", -2.0)
	vr_rig.pulse(w, 0.3, 0.05)
	_trim_darts()


func _throw(w: int) -> void:
	var d: Dart = held[w]
	held[w] = null
	hand_cd[w] = 0.6
	var hv := vr_rig.hand_velocity(w)
	var dir: Vector3 = hv.normalized() if hv.length() > 0.8 else -vr_rig.hand(w).global_basis.z
	dir = (dir + Vector3.UP * 0.08).normalized()
	d.vel = dir * clampf(hv.length() * 1.6, 4.5, 13.0)
	d.state = 1
	d.t = 0.0
	d.prev = d.node.global_position
	throws += 1
	sfx.play_at("whoosh", d.prev, 0.0, 1.2)
	vr_rig.pulse(w, 0.5, 0.06)
	net.event("whoosh", [d.prev])


func _trim_darts() -> void:
	var loose: Array[int] = []
	for id in darts:
		if (darts[id] as Dart).state != 0:
			loose.append(int(id))
	loose.sort()
	while loose.size() > MAX_DARTS:
		var id: int = loose.pop_front()
		(darts[id] as Dart).node.queue_free()
		darts.erase(id)


func _fly_darts(delta: float) -> void:
	var playing := String(net.state_get("phase", "")) == "play"
	for id in darts.keys():
		var d: Dart = darts[id]
		if d.state == 1:
			d.t += delta
			var v := d.vel
			var hs := Vector2(v.x, v.z).length()
			v.y += (-4.3 + minf(hs * 0.4, 3.6)) * delta
			v -= v * 0.07 * delta
			var aim: Variant = _assist_target(d.node.position, v, 14.0, 0.55)
			if aim != null:
				var want := ((aim as Vector3) - d.node.position).normalized()
				var dir := v.normalized()
				var ang := dir.angle_to(want)
				if ang > 0.001:
					v = dir.slerp(want, minf(1.0, 1.8 * delta / ang)) * v.length()
			d.vel = v
			d.prev = d.node.position
			var p := d.prev + v * delta
			_orient_dart(d, v.normalized(), sin(d.t * 9.0) * 0.25)
			d.node.position = p
			if playing:
				var hid := _check_pass(d.prev, p, 0.15)
				if hid >= 0:
					_score_hoop(hid, 0, p)
			if p.y < 0.04 or d.t > 8.0:
				d.state = 2
				d.t = 0.0
				d.node.position.y = maxf(0.03, p.y)
				var flat := Vector3(v.x, 0.0, v.z)
				_orient_dart(d, flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD, 0.0)
				sfx.play_at("pop", d.node.position, -12.0, 0.8)
		elif d.state == 2:
			d.t += delta
			if d.t > 1.6:
				d.size = maxf(0.0, 1.0 - (d.t - 1.6) / 0.5)
				d.body.scale = Vector3.ONE * DART_SCALE * maxf(d.size, 0.01)
			if d.t > 2.1:
				d.node.queue_free()
				darts.erase(id)


static func _orient_dart(d: Dart, dir: Vector3, roll: float) -> void:
	if dir.length() < 0.01:
		return
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	d.node.basis = Basis.looking_at(dir, up) * Basis(Vector3.FORWARD, roll)


func _bop(slot: int) -> void:
	var f: Flyer = flyers[slot]
	f.bop_cd = 1.5
	f.loop_t = 0.0
	sfx.play_at("boing", f.node.position, 0.0, 1.2)
	if vr_rig != null:
		vr_rig.pulse(maxi(vr_rig.touching_any(f.node.position, 0.6), 0), 0.5, 0.08)
	if party.is_local(slot):
		party.rumble(slot, 0.6, 0.3, 0.2)
	net.event("bop", [slot])


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play(sound_name, volume_db, pitch)


# --- Rounds -------------------------------------------------------------------------------

func _start_round() -> void:
	for id in hoops:
		(hoops[id] as Hoop).node.queue_free()
	hoops.clear()
	for id in darts:
		(darts[id] as Dart).node.queue_free()
	darts.clear()
	held = [null, null]
	respawns.clear()
	awards.reset()
	time_left = round_time
	_spawn_hoop(true)
	for i in HOOP_COUNT - 1:
		_spawn_hoop()
	net.state_set("score", 0)
	net.state_set("time", int(ceil(time_left)))
	net.state_set("phase", "play")
	net.state_set("round", int(net.state_get("round", 0)) + 1)
	if vr_rig != null:
		vr_rig.guard_trigger()


func _end_round() -> void:
	var score := int(net.state_get("score", 0))
	var data := awards.results({"title": "GREAT FLYING!", "subtitle": "%d hoops together!" % score,
		"style": "victory", "stats": [["HOOPS", str(score)], ["BEST", str(int(net.state_get("best", 0)))]],
		"score_format": "%d"})
	net.state_set("results", data)
	net.state_set("phase", "results")
	results_t = 0.0


func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
	for i in 3:
		burst(SIGN_POS + Vector3(randf_range(-5.0, 5.0), -3.0, 3.0), Meshes.RAINBOW, 50, 1.4)
	sfx.play("party_horn")
	sfx.play("cheer", -4.0)
	if split != null:
		split.set_shared(true)
		var screen := Awards.results_screen(huds[-1], data, {"party": party})
		screen.continued.connect(func() -> void:
			var seats := party.local_slots()
			net.request(seats[0] if not seats.is_empty() else 0, "next_round"))
		results_ui = screen
	if vr_rig != null:
		var card := Awards.vr_summary(self, null, data, null, {"rig": vr_rig})
		card.continued.connect(func() -> void: net.request(0, "next_round"))
		vr_results = card


func _hide_results() -> void:
	if results_ui != null and is_instance_valid(results_ui):
		results_ui.queue_free()
	results_ui = null
	if vr_results != null and is_instance_valid(vr_results):
		vr_results.call("finish")
	vr_results = null
	if split != null:
		split.set_shared(false)


func results_showing() -> bool:
	return String(net.state_get("phase", "")) == "results"


func on_request(_slot: int, action: String, _args: Array) -> void:
	if action == "next_round" and results_showing():
		_start_round()


func on_pause_changed(paused: bool, by_slot: int) -> void:
	if vr_rig != null:
		if paused:
			vr_banner = HudKit.vr_card(self, vr_rig.camera, "PAUSED", "", {"width": 1.1})
			vr_banner.process_mode = Node.PROCESS_MODE_ALWAYS
		elif vr_banner != null and is_instance_valid(vr_banner):
			vr_banner.call("hide_card")
	if split != null:
		if tv_banner == null:
			var ui := UiKit.ui_root(self, 6)
			ui.process_mode = Node.PROCESS_MODE_ALWAYS
			tv_banner = UiKit.panel("accent")
			ui.add_child(tv_banner)
			var v := UiKit.vbox()
			tv_banner.add_child(v)
			v.add_child(UiKit.title("PAUSED"))
			var l := UiKit.label("", "small", "dim", HORIZONTAL_ALIGNMENT_CENTER)
			l.name = "Why"
			v.add_child(l)
			tv_banner.set_anchors_preset(Control.PRESET_CENTER)
			tv_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
			tv_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
		(tv_banner.find_child("Why", true, false) as Label).text = "by %s" % party.name_of(by_slot)
		tv_banner.visible = paused
		if paused:
			UiKit.pop_in(tv_banner)


func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"score", "best":
			_refresh_hud()
		"time":
			for slot in timers:
				var t: HudKit.TimerPill = timers[slot]
				if is_instance_valid(t):
					t.set_time(float(value))
			if sign_time != null:
				sign_time.text = HudKit.clock_text(float(value))
			if int(value) <= 5 and int(value) > 0 and not results_showing():
				sfx.play("tick", -2.0)
		"round":
			HudKit.banner(_all_huds(), "PAPER PLANES", "Fly through the hoops!", {"duration": 2.5})
			if vr_rig != null:
				HudKit.vr_banner(self, vr_rig.camera, "PAPER PLANES", "Throw through the hoops!", {"duration": 2.5, "sound": ""})
			sfx.play("go", -4.0)
		"phase":
			if String(value) == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()
				music.play_mood("party")


# --- Game loop ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	clock += delta
	if net.mode != "host":
		_fly_local(delta)
	_animate_flyers(delta)
	_animate_hoops(delta)
	if net.mode == "client":
		_mirror_darts(delta)
		return
	if vr_rig != null:
		_vr_hands(delta)
	_fly_darts(delta)
	for id in hoops:
		_move_hoop(hoops[id])
	if results_showing():
		results_t += delta
		if results_t > results_wait:
			_start_round()
		return
	for i in range(respawns.size() - 1, -1, -1):
		respawns[i] -= delta
		if respawns[i] <= 0.0:
			respawns.remove_at(i)
			_spawn_hoop()
	time_left -= delta
	if int(ceil(time_left)) != int(net.state_get("time", 0)):
		net.state_set("time", maxi(0, int(ceil(time_left))))
	if time_left <= 0.0:
		_end_round()


# --- Networking ---------------------------------------------------------------------------

func make_snapshot() -> Array:
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	var sp := stack_node.global_position if stack_node != null and vr_rig != null else Vector3(0.0, -50.0, 0.0)
	var hids := PackedInt32Array()
	var hf := PackedFloat32Array()
	var hk := PackedByteArray()
	for id in hoops:
		var h: Hoop = hoops[id]
		hids.append(int(id))
		var p := h.node.position
		hf.append_array([p.x, p.y, p.z, h.node.rotation.y, h.wob])
		hk.append(h.kind * 16 + h.ci)
	var dids := PackedInt32Array()
	var df := PackedFloat32Array()
	for id in darts:
		var d: Dart = darts[id]
		dids.append(int(id) * 8 + d.ci)
		var p := d.node.global_position
		var f := -d.node.global_basis.z
		df.append_array([p.x, p.y, p.z, f.x, f.y, f.z, d.size])
	return [pose, sp, hids, hf, hk, dids, df]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 7:
		return
	if vr_avatar != null:
		vr_avatar.apply_pose(s[0])
	var sp: Vector3 = s[1]
	if stack_node != null:
		stack_node.visible = sp.y > -10.0
		stack_node.position = sp
	var hids: PackedInt32Array = s[2]
	var hf: PackedFloat32Array = s[3]
	var hk: PackedByteArray = s[4]
	var seen := {}
	for i in hids.size():
		var id := hids[i]
		seen[id] = true
		var p := Vector3(hf[i * 5], hf[i * 5 + 1], hf[i * 5 + 2])
		var h: Hoop = hoops[id] if hoops.has(id) else _make_hoop(id, hk[i] / 16, hk[i] % 16, p)
		h.target = p
		h.target_yaw = hf[i * 5 + 3]
		h.wob = maxf(h.wob, hf[i * 5 + 4])
	for id in hoops.keys():
		if not seen.has(id):
			(hoops[id] as Hoop).node.queue_free()
			hoops.erase(id)
	var dids: PackedInt32Array = s[5]
	var df: PackedFloat32Array = s[6]
	var dseen := {}
	for i in dids.size():
		var id := dids[i] / 8
		dseen[id] = true
		var o := i * 7
		var d: Dart = darts[id] if darts.has(id) else _make_dart(id, dids[i] % 8)
		d.target = Vector3(df[o], df[o + 1], df[o + 2])
		d.dir = Vector3(df[o + 3], df[o + 4], df[o + 5])
		d.size = df[o + 6]
		if d.state == 0:
			d.state = 1
			d.node.position = d.target
	for id in darts.keys():
		if not dseen.has(id):
			(darts[id] as Dart).node.queue_free()
			darts.erase(id)


## TV machine: hoops and the VR player's planes glide to their snapshot spots.
func _mirror_darts(delta: float) -> void:
	var k := 1.0 - exp(-14.0 * delta)
	for id in hoops:
		var h: Hoop = hoops[id]
		h.node.position = h.node.position.lerp(h.target, k)
		h.node.rotation.y = lerp_angle(h.node.rotation.y, h.target_yaw, k)
	for id in darts:
		var d: Dart = darts[id]
		d.node.position = d.node.position.lerp(d.target, k)
		_orient_dart(d, d.dir, 0.0)
		d.body.scale = Vector3.ONE * DART_SCALE * maxf(d.size, 0.01)


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"pass":
			var id := int(args[0])
			if hoops.has(id):
				(hoops[id] as Hoop).node.queue_free()
				hoops.erase(id)
			hoop_fx(args[1], int(args[3]), int(args[4]), int(args[2]), int(args[5]))
		"whoosh":
			sfx.play_at("whoosh", args[0], 0.0, 1.2)
		"wob":
			if hoops.has(int(args[0])):
				var h: Hoop = hoops[int(args[0])]
				h.wob = 1.0
				sfx.play_at("boing", h.node.position, -4.0)
		"bop":
			var slot := int(args[0])
			if flyers.has(slot):
				var f: Flyer = flyers[slot]
				f.loop_t = 0.0
				sfx.play("boing", 0.0, 1.2)
				if party.is_local(slot):
					party.rumble(slot, 0.6, 0.3, 0.2)
