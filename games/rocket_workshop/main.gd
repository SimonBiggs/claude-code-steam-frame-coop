extends Node3D
## Rocket Workshop: a cosy talk-to-each-other puzzle game (no arena, no enemies).
## The pilot (VR, host, players[0]) stands at the rocket's control desk with buttons, plugs, a dial,
## switches and the big launch lever, but can't see any instructions. The TV crew (1-2 players) walk
## round the workshop, read the blueprint boards on the walls and SAY what to do. They also fetch fuel
## canisters and fix leaky pipes. Get every module done and pull the lever before the countdown ends!
## Mistakes just make the rocket burp and cost a few seconds.
##
## Files: puzzles.gd (module generation), panel.gd (pilot's desk), manual.gd (blueprint boards),
## jobs.gd (canister and pipe), rocket.gd (rocket + launch fx), operator.gd (pilot), player.gd (crew),
## world.gd (the workshop). The host is authoritative; modules travel to the TV in snapshots.

const P := preload("res://games/rocket_workshop/puzzles.gd")
const WorldScript := preload("res://games/rocket_workshop/world.gd")
const PanelScript := preload("res://games/rocket_workshop/panel.gd")
const ManualScript := preload("res://games/rocket_workshop/manual.gd")
const RocketScript := preload("res://games/rocket_workshop/rocket.gd")
const JobsScript := preload("res://games/rocket_workshop/jobs.gd")
const OperatorScript := preload("res://games/rocket_workshop/operator.gd")
const PlayerScript := preload("res://games/rocket_workshop/player.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")

const MANUAL_LAYER := 512  # blueprint content: drawn for the TV crew only
const PANEL_LAYER := 1024  # desk controls: drawn for the pilot only
const PAD_POS := Vector3(0, 0, -11.0)
const HATCH_POS := Vector3(0, 0, -8.0)
const LAUNCH_TIME := 8.5
const INTRO_TIME := 3.0
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.55, 0.25), Color(0.3, 0.65, 1.0), Color(0.55, 0.85, 0.35)]
const BOARD_PLACES := {"fuel": "left wall", "wires": "left wall", "gauge": "right wall", "switches": "right wall", "symbols": "back wall"}
const SOUNDS := {
	"boop": [0.09, 620.0, 900.0, 0.3, "sine", 0.0],
	"click": [0.03, 1600.0, 900.0, 0.2, "square", 0.3],
	"plug": [0.14, 300.0, 1000.0, 0.35, "tri", 0.1],
	"burp": [0.65, 150.0, 50.0, 0.65, "saw", 0.3],
	"solve": [0.4, 523.0, 1046.0, 0.35, "tri", 0.0],
	"allset": [0.9, 392.0, 1568.0, 0.4, "tri", 0.0],
	"tick": [0.06, 1300.0, 1300.0, 0.2, "sine", 0.0],
	"count": [0.3, 880.0, 870.0, 0.35, "sine", 0.0],
	"rumble": [3.2, 70.0, 28.0, 0.75, "saw", 0.9],
	"whoosh": [1.6, 300.0, 1400.0, 0.4, "sine", 0.7],
	"pop": [0.15, 400.0, 1400.0, 0.3, "sine", 0.1],
	"fix": [0.08, 2200.0, 700.0, 0.12, "saw", 0.6],
	"nap": [1.6, 400.0, 120.0, 0.4, "tri", 0.0],
}

var players: Array = []
var ready_to_play := false
var net: Node
var sfx: Node
var music: Node
var mats := {}
var meshes := {}
var xr_interface: XRInterface
var mirror_vp: SubViewport
var mirror_t := 0.0
var panel: Node3D
var manual: Node3D
var rocket: Node3D
var jobs: Node3D
var synced := false

var phase := "wait"  # wait, intro, work, ready, launch, over
var phase_t := 0.0
var rocket_n := 0
var rocket_name := ""
var modules: Array = []
var time_left := 0.0
var launched := 0
var mistakes := 0
var launch_t := 0.0
var game_over := false
var game_over_time := 0.0
var best := 0
var last_tick := -1
var msg := ""
var msg_t := 0.0
var lever_hint_t := 0.0

var info_label: Label
var list_label: Label
var center_label: Label
var help_label: Label
var center_tween: Tween
var vr_center: Label3D


func _ready() -> void:
	randomize()
	var xr := XRServer.find_interface("OpenXR")
	var will_vr := xr != null and xr.is_initialized() and not OS.has_environment("DUO_JOIN")
	WorldScript.build(self, will_vr)
	rocket = RocketScript.new()
	rocket.main = self
	add_child(rocket)
	manual = ManualScript.new()
	manual.main = self
	add_child(manual)
	jobs = JobsScript.new()
	jobs.main = self
	add_child(jobs)
	_build_hud()
	best = _load_best()
	var menu := PauseMenuScript.new()
	menu.main = self
	add_child(menu)
	net = NetScript.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	Input.joy_connection_changed.connect(_on_joy_changed)
	if OS.has_environment("DUO_JOIN"):
		_show_center("Connecting to the pilot…", 0.0)
		net.join_finished.connect(func(ok: bool) -> void: _setup_game("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if will_vr or OS.has_environment("DUO_HOST"):
			net.host()
		_setup_game(net.mode)


func _setup_game(mode: String) -> void:
	panel = PanelScript.new()
	panel.main = self
	panel.detail = mode != "client"
	add_child(panel)
	_build_players(mode)
	_build_views(mode)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mode == "client" else Input.MOUSE_MODE_VISIBLE
	_assign_joypads()
	ready_to_play = true
	if mode == "host":
		_show_center("Waiting for the TV crew to join…", 0.0)
	elif mode == "client":
		_show_center("CONNECTED!\nFind the blueprints and tell the pilot what to do!", 3.0)
	else:
		_show_center("ROCKET WORKSHOP\nPilot: work the desk.  Crew: read the blueprints out loud!", 3.0)


# --- Shared materials, meshes and effects ------------------------------------

func make_material(color: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


## Shared material per colour (so identical blobs batch together).
func color_mat(color: Color, glow: float) -> StandardMaterial3D:
	var key := "%s/%.2f" % [color.to_html(), glow]
	if not mats.has(key):
		mats[key] = make_material(color, glow)
	return mats[key]


func sphere_mesh(r: float) -> SphereMesh:
	var key := "s%.3f" % r
	if not meshes.has(key):
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 14
		sm.rings = 7
		meshes[key] = sm
	return meshes[key]


func box_mesh(size: Vector3) -> BoxMesh:
	var key := "b%s" % size
	if not meshes.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		meshes[key] = bm
	return meshes[key]


func cyl_mesh(r_top: float, r_bottom: float, h: float, seg: int) -> CylinderMesh:
	var key := "c%.3f/%.3f/%.3f/%d" % [r_top, r_bottom, h, seg]
	if not meshes.has(key):
		var cm := CylinderMesh.new()
		cm.top_radius = r_top
		cm.bottom_radius = r_bottom
		cm.height = h
		cm.radial_segments = seg
		cm.rings = 1
		meshes[key] = cm
	return meshes[key]


func capsule_mesh(r: float, h: float) -> CapsuleMesh:
	var key := "p%.3f/%.3f" % [r, h]
	if not meshes.has(key):
		var cm := CapsuleMesh.new()
		cm.radius = r
		cm.height = h
		cm.radial_segments = 12
		cm.rings = 4
		meshes[key] = cm
	return meshes[key]


## One of the six puzzle shapes, standing upright, about `size` metres across.
func shape_node(id: int, size: float) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	match id:
		0:
			mi.mesh = sphere_mesh(size * 0.5)
		1:
			mi.mesh = box_mesh(Vector3.ONE * size * 0.8)
			mi.rotation.y = 0.5
		2:
			mi.mesh = cyl_mesh(0.0, size * 0.5, size, 14)
		3:
			var tm := TorusMesh.new()
			tm.inner_radius = size * 0.22
			tm.outer_radius = size * 0.5
			tm.rings = 16
			tm.ring_segments = 8
			mi.mesh = tm
			mi.rotation.x = PI / 2.0
		4:
			mi.mesh = capsule_mesh(size * 0.22, size)
			mi.rotation.z = PI / 2.0
		_:
			var pm := PrismMesh.new()
			pm.size = Vector3(size, size * 0.8, size * 0.6)
			mi.mesh = pm
	mi.material_override = color_mat(P.SHAPE_COLORS[clampi(id, 0, 5)], 0.25)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	return n


func set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for c in node.get_children():
		set_layers(c, layers)


## Local-only puff of particles.
func puff(pos: Vector3, color: Color, amount: int = 10, size: float = 0.08) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0, 1.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	m.material = color_mat(color, 0.3)
	p.mesh = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


## Networked burst: shown here and on the TV.
func burst(pos: Vector3, color: Color, amount: int = 16, size: float = 0.1) -> void:
	puff(pos, color, amount, size)
	net.event("burst", [pos, color, amount, size])


func local_sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
	if SOUNDS.has(sound_name):
		sfx.add_sound(sound_name, SOUNDS[sound_name])
	sfx.play(sound_name, volume_db, pitch)


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	local_sound(sound_name, volume_db, pitch)
	if net:
		net.event("sound", [sound_name, volume_db, pitch])


## Floating 3D text that rises and fades; shown on both machines (upright, not billboarded).
func popup(pos: Vector3, text: String, color: Color, broadcast: bool = true) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.font_size = 64
	l.outline_size = 18
	l.pixel_size = 0.008
	l.no_depth_test = true
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	l.global_position = pos
	if not players.is_empty() and players[0].vr:
		# Face the pilot (fixed, world-locked text); the crew only see it from behind sometimes.
		var to: Vector3 = pos - players[0].xr_camera.global_position
		l.global_basis = Basis(Vector3.UP, atan2(-to.x, -to.z))
	else:
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "global_position", pos + Vector3.UP * 1.2, 1.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.9)
	t.tween_property(l, "outline_modulate:a", 0.0, 0.9).set_delay(0.9)
	t.chain().tween_callback(l.queue_free)
	if broadcast:
		net.event("popup", [pos, text, color])


# --- Puzzle state helpers ----------------------------------------------------

func module(type: String) -> Dictionary:
	for m in modules:
		if m.type == type:
			return m
	return {}


func _all_done() -> bool:
	for m in modules:
		if not m.done:
			return false
	return true


## Keep a crew member on the floor, out of the pilot's booth, the walls and the launch pad.
func clamp_walk(p: Vector3) -> Vector3:
	p.y = 0.0
	p.x = clampf(p.x, -10.5, 10.5)
	p.z = clampf(p.z, -17.0, 7.6)
	if absf(p.x) > 3.9 and absf(p.z + 6.15) < 0.45:
		p.z = -6.6 if p.z < -6.15 else -5.7
	if absf(p.x) < 1.4 and p.z > -1.3 and p.z < 1.05:
		var dx := 1.4 - absf(p.x)
		var dz_back := 1.05 - p.z
		var dz_front := p.z + 1.3
		if dx < dz_back and dx < dz_front:
			p.x = 1.4 * (1.0 if p.x >= 0.0 else -1.0)
		elif dz_back < dz_front:
			p.z = 1.05
		else:
			p.z = -1.3
	var flat := Vector2(p.x - PAD_POS.x, p.z - PAD_POS.z)
	if flat.length() < 2.7:
		flat = flat.normalized() * 2.7 if flat.length() > 0.01 else Vector2(0, 2.7)
		p.x = PAD_POS.x + flat.x
		p.z = PAD_POS.z + flat.y
	return p


func pipe_point() -> Vector3:
	var m := module("pipe")
	if m.is_empty():
		return Vector3.ZERO
	return P.PIPE_SPOTS[int(m.spot)]


func pipe_near(pos: Vector3) -> bool:
	var m := module("pipe")
	if m.is_empty() or m.done or (phase != "work" and phase != "ready"):
		return false
	var s := pipe_point()
	return Vector2(pos.x - s.x, pos.z - s.z).length() < 2.0


## Host: a crew member is working on the leaky pipe.
func fix_pipe(index: int, amount: float) -> void:
	var m := module("pipe")
	if m.is_empty() or m.done or index <= 0 or index >= players.size():
		return
	if not pipe_near(players[index].global_position):
		return
	m.progress = minf(1.0, float(m.progress) + clampf(amount, 0.0, 0.2))
	if float(m.progress) >= 1.0:
		burst(pipe_point(), Color(0.5, 0.8, 1.0), 20, 0.08)
		popup(pipe_point() + Vector3.UP * 1.2, "PIPE FIXED!", Color(0.5, 1.0, 0.6))
		_solve(m)


# --- Game flow (host) ----------------------------------------------------------

func _start_rocket(n: int) -> void:
	var r := P.make_rocket(n)
	rocket_n = n
	rocket_name = r.name
	modules = r.modules
	time_left = r.time
	phase = "intro"
	phase_t = INTRO_TIME
	launch_t = 0.0
	last_tick = -1
	var types: Array[String] = []
	for m in modules:
		types.append(m.type)
	print("Rocket %d (%s): %s, %.0f s" % [n, rocket_name, ", ".join(types), time_left])
	sound("pop", -2.0, 0.8)
	_show_center("ROCKET #%d IS ON THE PAD!\nCrew: find the glowing blueprints.  Pilot: say what you see!" % n, INTRO_TIME)


## Host: the pilot touched or moved something on the desk.
func on_panel(kind: String, args: Array) -> void:
	if kind == "lever":
		if phase == "ready":
			_start_launch()
		elif phase == "work" and lever_hint_t <= 0.0:
			lever_hint_t = 3.0
			_flash("Not yet! Finish every job first.")
			sound("boop", -6.0, 0.5)
		return
	if phase != "work" and phase != "ready":
		return
	match kind:
		"fuel":
			var m := module("fuel")
			if m.is_empty() or m.done:
				return
			var pressed: Array = m.pressed
			var answer: Array = m.answer
			pressed.append(int(args[0]))
			sound("plug", -4.0, 0.7 + int(args[0]) * 0.15)
			if pressed.size() >= answer.size():
				var mix := pressed.duplicate()
				mix.sort()
				if mix == answer:
					_solve(m)
				else:
					m.pressed = []
					_burp("That fuel mix was yucky!")
		"plug":
			var m := module("wires")
			if m.is_empty() or m.done:
				return
			var color := int(args[0])
			var socket := int(args[1])
			var order: Array = m.order
			var placed: Array = m.placed
			if placed.has(color) or socket < 0 or socket > 3 or int(placed[socket]) >= 0:
				return
			if socket < order.size() and int(order[socket]) == color:
				placed[socket] = color
				sound("plug", -2.0, 1.0)
				var all := true
				for i in order.size():
					if int(placed[i]) != int(order[i]):
						all = false
				if all:
					_solve(m)
			else:
				_burp("Wrong socket - zzzap!")
		"shape":
			var m := module("symbols")
			if m.is_empty() or m.done:
				return
			var layout: Array = m.layout
			var order: Array = m.order
			var step: int = m.step
			var shape := int(layout[int(args[0])])
			sound("boop", -4.0, 0.8 + step * 0.2)
			if shape == int(order[step]):
				m.step = step + 1
				if int(m.step) >= order.size():
					_solve(m)
			else:
				m.step = 0
				_burp("Wrong shape order!")
		"dial":
			var m := module("gauge")
			if not m.is_empty() and not m.done:
				m.value = clampi(int(args[0]), 1, 9)
		"set":
			var m := module("gauge")
			if m.is_empty() or m.done:
				return
			sound("boop", -4.0)
			if int(m.value) == int(m.answer):
				_solve(m)
			else:
				_burp("Too much pressure!" if int(m.value) > int(m.answer) else "Not enough pressure!")
		"switch":
			var m := module("switches")
			if m.is_empty() or m.done:
				return
			var state: Array = m.state
			var i := int(args[0])
			state[i] = not bool(state[i])
			sound("click", -4.0, 1.0)
		"check":
			var m := module("switches")
			if m.is_empty() or m.done:
				return
			sound("boop", -4.0)
			if m.state == m.answer:
				_solve(m)
			else:
				_burp("The switches are muddled!")


func _solve(m: Dictionary) -> void:
	m.done = true
	var title: String = P.TITLES[m.type]
	print("Module solved: %s (rocket %d, %.0f s left)" % [m.type, rocket_n, time_left])
	sound("solve", -2.0)
	_flash(title + " - DONE!")
	if not P.is_job(m.type) and manual.boards.has(m.type):
		var root: Node3D = manual.boards[m.type].root
		burst(root.global_position + root.global_basis.z * 0.5, Color(0.4, 1.0, 0.5), 18, 0.08)
	for p in players:
		if p.index == 0:
			p.haptic("r", 0.6)
	if _all_done() and phase == "work":
		phase = "ready"
		sound("allset", 0.0)
		print("All modules done: waiting for the launch lever")
		_show_center("ALL SYSTEMS GO!\nPilot: PULL THE BIG LAUNCH LEVER!", 3.5)


## A mistake: the rocket burps and the countdown loses a few seconds (never below 5).
func _burp(why: String) -> void:
	mistakes += 1
	time_left = maxf(minf(time_left, 5.0), time_left - P.MISTAKE_SECONDS)
	print("Oops: %s (mistake %d, %.0f s left)" % [why, mistakes, time_left])
	sound("burp", 2.0, randf_range(0.85, 1.1))
	rocket.burp()
	net.event("burp", [])
	popup(PAD_POS + Vector3(0, 6.2, 0), "BURP!", Color(0.6, 1.0, 0.4))
	_show_center("Oops! The rocket burped!\n%s  (-%d s)" % [why, int(P.MISTAKE_SECONDS)], 2.2)
	_flash("Oops! " + why)
	if players[0].vr:
		players[0].haptic("l", 0.8)
		players[0].haptic("r", 0.8)


func _flash(text: String) -> void:
	msg = text
	msg_t = 3.0


func _start_launch() -> void:
	phase = "launch"
	launch_t = 0.0
	launched += 1
	print("Rocket %d launched! (%d total, %.0f s to spare)" % [rocket_n, launched, time_left])
	_show_center("3", 0.9)
	sound("count", 0.0, 1.0)


func _launch_beats(prev: float, now: float) -> void:
	for k in [1, 2]:
		if prev < k and now >= k:
			_show_center(str(3 - k), 0.9)
			sound("count", 0.0, 1.0)
	if prev < 2.6 and now >= 2.6:
		sound("rumble", 2.0, 1.0)
	if prev < RocketScript.LIFTOFF and now >= RocketScript.LIFTOFF:
		_show_center("LIFT OFF!\nRocket #%d is off to space!" % rocket_n, 3.0)
		sound("count", 2.0, 2.0)
		sound("whoosh", 0.0, 1.0)
		sound("allset", -2.0, 1.2)
		popup(PAD_POS + Vector3(0, 4.0, 2.0), "WHEEE!", Color(1.0, 0.85, 0.3))


func _update_jobs() -> void:
	var m := module("canister")
	if m.is_empty() or m.done:
		return
	var carrier: int = m.carrier
	if carrier < 0:
		var at: Vector3 = m.pos
		for p in players:
			if p.index == 0 or not p.active:
				continue
			var pp: Vector3 = p.global_position
			if Vector2(pp.x - at.x, pp.z - at.z).length() < 1.4:
				m.carrier = p.index
				sound("pop", -2.0, 1.2)
				popup(at + Vector3.UP * 1.6, "GOT IT! To the rocket!", Color(1.0, 0.8, 0.4))
				print("Canister picked up by P%d" % (p.index + 1))
				break
	else:
		var p = players[carrier]
		var pp: Vector3 = p.global_position
		m.pos = Vector3(pp.x, 0.0, pp.z)
		if not p.active:
			m.carrier = -1
		elif Vector2(pp.x - HATCH_POS.x, pp.z - HATCH_POS.z).length() < 1.8:
			m.carrier = -1
			burst(HATCH_POS + Vector3.UP * 0.8, Color(1.0, 0.6, 0.2), 20, 0.1)
			popup(HATCH_POS + Vector3.UP * 2.0, "FUELLED UP!", Color(1.0, 0.8, 0.3))
			_solve(m)


func _host_update(delta: float) -> void:
	msg_t -= delta
	lever_hint_t -= delta
	match phase:
		"wait":
			if net.mode != "host" or net.connected:
				_start_rocket(1)
		"intro":
			phase_t -= delta
			if phase_t <= 0.0:
				phase = "work"
		"work", "ready":
			if net.mode == "host" and not net.connected:
				return  # hold the countdown while the TV crew is away
			time_left -= delta
			_update_jobs()
			var sec := ceili(time_left)
			if sec <= 10 and sec != last_tick and sec > 0:
				last_tick = sec
				sound("tick", -4.0 if sec > 5 else 0.0, 1.0 if sec > 5 else 1.3)
			if time_left <= 0.0:
				_on_game_over()
		"launch":
			var prev := launch_t
			launch_t += delta
			_launch_beats(prev, launch_t)
			if launch_t >= LAUNCH_TIME:
				_start_rocket(rocket_n + 1)
		"over":
			game_over_time += delta
			if game_over_time > 1.5 and (_restart_pressed() or players[0].vr_trigger_held()):
				get_tree().reload_current_scene()


func _on_game_over() -> void:
	phase = "over"
	game_over = true
	game_over_time = 0.0
	time_left = 0.0
	sound("nap", 0.0)
	print("Game over: %d rockets launched, %d burps" % [launched, mistakes])
	var best_line := "Best: %d rockets" % best
	if launched > best:
		best_line = "NEW BEST!  (before: %d)" % best
		best = launched
		_save_best(launched)
	_show_center("The rocket got sleepy and took a nap… Zzz\nRockets launched: %d   ·   Burps: %d\n%s\n\nPress A / Enter (VR: trigger) to play again" % [launched, mistakes, best_line], 0.0)


func _load_best() -> int:
	var cfg := ConfigFile.new()
	cfg.load("user://rocket_workshop_best.cfg")
	return int(cfg.get_value("best", "rockets", 0))


func _save_best(rockets: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("best", "rockets", rockets)
	cfg.save("user://rocket_workshop_best.cfg")


func _restart_pressed() -> bool:
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER):
		return true
	for id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(id, JOY_BUTTON_A):
			return true
	return false


func _clock() -> String:
	var s := maxi(0, ceili(time_left))
	return "%d:%02d" % [s / 60, s % 60]


## Text on the pilot's desk screen (world-space, only the pilot sees it).
func screen_text() -> String:
	var status := ""
	match phase:
		"wait":
			status = "Waiting for the TV crew…"
		"intro":
			status = "A new rocket! Tell your crew its name."
		"work":
			status = "Ask your crew what the blueprints say!"
		"ready":
			status = "PULL THE BIG LAUNCH LEVER!"
		"launch":
			status = "LIFT OFF!"
		"over":
			status = "Zzz… pull the trigger to play again"
	if msg_t > 0.0 and (phase == "work" or phase == "ready"):
		status = msg
	if rocket_n == 0:
		return "ROCKET WORKSHOP\n" + status
	return "ROCKET #%d  is called  %s\nTIME %s      LAUNCHED %d\n%s" % [rocket_n, rocket_name, _clock(), launched, status]


# --- Main loop ---------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play or not is_inside_tree():
		return
	if music == null:
		music = MusicScript.new()
		add_child(music)
		music.volume_db = -20.0
	if music.has_method("play_track"):
		music.play_track(2)
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if net.mode == "client":
		if phase == "launch":
			launch_t += delta
		_check_join(delta)
		if game_over:
			game_over_time += delta
			if game_over_time > 1.5 and _restart_pressed():
				game_over_time = 0.0
				net.send_action("restart", [])
	else:
		_host_update(delta)
		# The pilot's pointer needs a free mouse (the pause menu captures it on resume).
		if not players[0].vr and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	rocket.update_visual(rocket_n, phase, launch_t, delta)
	manual.update_boards(modules, rocket_n)
	jobs.update_visual(modules, delta)
	panel.update_panel(delta)
	_update_hud()
	_update_vr_center()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_F11:
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


# --- Players and views -------------------------------------------------------

func _build_players(mode: String) -> void:
	var op := OperatorScript.new()
	op.main = self
	op.ghost = mode == "client"
	add_child(op)
	players.append(op)
	var count := 3 if mode != "local" else 2
	var spots: Array[Vector3] = [Vector3(-2.2, 0, 4.5), Vector3(2.2, 0, 4.5)]
	for i in range(1, count):
		var p := PlayerScript.new()
		p.index = i
		p.color = PLAYER_COLORS[i]
		p.main = self
		p.remote = mode == "host"
		if mode == "local":
			p.key_set = 0
		else:
			p.key_set = 1 if i == 1 else 0
			p.mouse_look = i == 2
		p.position = spots[i - 1]
		add_child(p)
		players.append(p)


func _apply_vr_performance() -> void:
	for n in get_children():
		if n is WorldEnvironment:
			var e: Environment = n.environment
			e.ssao_enabled = false
			e.fog_enabled = false
			e.glow_intensity = 0.5
		elif n is DirectionalLight3D:
			n.shadow_enabled = false


func _build_views(mode: String) -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized() and mode != "client":
		xr_interface = xr
		print("VR headset found: player 1 is the pilot")
		Engine.physics_ticks_per_second = 90
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_2X
		_apply_vr_performance()
		var origin := XROrigin3D.new()
		add_child(origin)
		origin.global_position = Vector3(0, 0, 0.12)
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
	else:
		print("No VR headset: %s" % ("TV crew view" if mode == "client" else "split screen, player 1 works the desk with a pointer"))
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1)
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	layer.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for p in players:
		if p.vr or p.remote or p.ghost or p.camera != null:
			continue
		var container := SubViewportContainer.new()
		p.set_meta("view", container)
		container.stretch = true
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(container)
		var vp := SubViewport.new()
		vp.world_3d = get_world_3d()
		vp.msaa_3d = Viewport.MSAA_2X
		container.add_child(vp)
		var cam := Camera3D.new()
		vp.add_child(cam)
		cam.current = true
		p.attach_camera(cam)
	if players.size() > 2:
		players[2].set_active(false)
		if players[2].has_meta("view"):
			players[2].get_meta("view").visible = false


## Low-res copy of the VR view, recorded by gdev (group gdev_capture) so others can watch.
func _build_vr_mirror(xr_cam: XRCamera3D) -> void:
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


## VR without a TV machine: the crew member gets a window on this device.
func _build_flat_window(p) -> void:
	var win := Window.new()
	win.title = "Rocket Workshop - Crew"
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
	p.attach_camera(cam)


func _assign_joypads() -> void:
	var pads := Input.get_connected_joypads()
	var a: int = pads[0] if pads.size() > 0 else -1
	var b: int = pads[1] if pads.size() > 1 else -1
	if net.mode == "local" and not players[0].vr:
		players[1].joy = a
		players[0].joy = b
	elif net.mode == "host":
		players[0].joy = a if not players[0].vr else -1
	else:
		players[1].joy = a
		if players.size() > 2:
			players[2].joy = b


func _on_joy_changed(_device: int, _connected: bool) -> void:
	if ready_to_play:
		_assign_joypads()


## TV machine: player 3 joins by pressing ACTION on the second controller / keyboard / mouse.
var join_t := 0.0
func _check_join(delta: float) -> void:
	join_t -= delta
	if players.size() < 3 or players[2].active or join_t > 0.0 or game_over:
		return
	if players[2].action_held():
		join_t = 1.0
		net.send_action("join", [], 2)


func on_player_activity_changed(p) -> void:
	if p.has_meta("view"):
		p.get_meta("view").visible = p.active
	print("Player %d is now %s on this screen" % [p.index + 1, "playing" if p.active else "waiting"])


# --- Networked co-op (see docs/GAME_DEV_GUIDE.md) ----------------------------

func on_client_joined() -> void:
	_show_center("THE TV CREW JOINED!", 1.5)


func on_client_left() -> void:
	_show_center("The TV crew left - waiting for them to come back…", 0.0)


func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	var p = players[index]
	match action:
		"fix":
			if p.active and args.size() > 0:
				fix_pipe(index, float(args[0]))
		"join":
			if not p.active:
				p.set_active(true)
				_show_center("PLAYER %d JOINED THE CREW!" % (index + 1), 1.5)
				print("Net: player %d joined the game" % (index + 1))
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
	_set_pause_banner(paused, "Wrist RESUME: carry on\nPull the trigger: back to the arcade")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var ps := []
	for p in players:
		var st := [p.global_position, p.yaw, p.pitch, p.active]
		if p.index == 0:
			st.append_array([p.head_transform(), p.hand_r_transform(), p.hand_l_transform()])
		ps.append(st)
	# The rocket's name is left out on purpose: only the pilot can read it, the crew must ask.
	return [phase, rocket_n, launched, time_left, "", modules, ps, launch_t, mistakes, panel.top]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play:
		return
	synced = true
	phase = s[0]
	rocket_n = s[1]
	launched = s[2]
	time_left = s[3]
	modules = s[5]
	var ps: Array = s[6]
	for i in mini(players.size(), ps.size()):
		players[i].apply_net_state(ps[i])
	var lt: float = s[7]
	if phase != "launch" or absf(lt - launch_t) > 0.3:
		launch_t = lt
	mistakes = s[8]
	var top: float = s[9]
	if absf(top - panel.top) > 0.005:
		panel.set_top(top)
	if game_over != (phase == "over"):
		game_over = phase == "over"
		game_over_time = 0.0


func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			local_sound(args[0], args[1], args[2])
		"burst":
			puff(args[0], args[1], args[2], args[3])
		"popup":
			popup(args[0], args[1], args[2], false)
		"center":
			_show_center(args[0], args[1], false)
		"burp":
			rocket.burp()
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The pilot paused the game")


# --- HUD ---------------------------------------------------------------------

func _make_label(font: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_constant_override("outline_size", maxi(6, font / 5))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.15, 0.95))
	l.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	info_label = _make_label(32)
	layer.add_child(info_label)
	info_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	info_label.offset_top = 16
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list_label = _make_label(24)
	layer.add_child(list_label)
	list_label.position = Vector2(24, 70)
	center_label = _make_label(54)
	layer.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	help_label = _make_label(20)
	layer.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help_label.offset_top = -64
	help_label.offset_bottom = -12
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.text = "Crew: left stick / WASD / arrows walk · right stick / mouse / Q E look · hold A / X / Space / Enter to fix pipes · walk into fuel cans to carry them\n" \
		+ "Pilot (split screen): mouse or controller pointer · click buttons · hold and drag plugs, the dial and the launch lever"


func _show_center(text: String, duration: float, broadcast: bool = true) -> void:
	if net and broadcast:
		net.event("center", [text, duration])
	center_label.text = text
	center_label.modulate.a = 1.0
	if center_tween:
		center_tween.kill()
	if duration > 0.0:
		center_tween = create_tween()
		center_tween.tween_interval(duration)
		center_tween.tween_property(center_label, "modulate:a", 0.0, 0.5)


func _update_hud() -> void:
	if net.mode == "client" and not synced:
		info_label.text = "Syncing with the pilot…"
		return
	if rocket_n == 0:
		info_label.text = "ROCKET WORKSHOP"
		list_label.text = ""
		return
	info_label.text = "ROCKET #%d      TIME %s      LAUNCHED %d" % [rocket_n, _clock(), launched]
	var lines: Array[String] = ["THIS ROCKET NEEDS:"]
	for m in modules:
		var t: String = m.type
		var line: String = P.TITLES[t]
		if m.done:
			line = "DONE  " + line
		elif P.is_job(t):
			line = "TODO  " + line + ("  (carry it to the rocket)" if t == "canister" else "  (hold ACTION next to it)")
		else:
			line = "TODO  " + line + "  (blueprint on the %s)" % BOARD_PLACES.get(t, "wall")
		lines.append(line)
	if phase == "ready":
		lines.append("\nTell the pilot: PULL THE LAUNCH LEVER!")
	list_label.text = "\n".join(lines)


## VR can't show 2D overlays: mirror the centre banner on a world-space panel that lazily follows
## the pilot's view (it never sticks to the headset and doesn't billboard).
func _update_vr_center() -> void:
	if players.is_empty() or not players[0].vr:
		return
	if vr_center == null:
		vr_center = Label3D.new()
		vr_center.font_size = 46
		vr_center.outline_size = 26
		vr_center.no_depth_test = true
		vr_center.render_priority = 10
		vr_center.outline_render_priority = 9
		vr_center.width = 900.0
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vr_center.pixel_size = 0.0024
		vr_center.modulate = Color(1.0, 0.95, 0.85)
		add_child(vr_center)
		set_layers(vr_center, PANEL_LAYER)
	vr_center.text = center_label.text
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate = Color(0, 0, 0, center_label.modulate.a)
	_lazy_follow(vr_center, 0.3)


func _lazy_follow(l: Label3D, height: float) -> void:
	var cam: Node3D = players[0].xr_camera
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return
	fwd = fwd.normalized()
	var target := cam.global_position + fwd * 1.8 + Vector3(0.0, height, 0.0)
	if not l.has_meta("placed"):
		l.set_meta("placed", true)
		l.set_meta("moving", true)
		l.global_position = target
	var to := l.global_position - cam.global_position
	to.y = 0.0
	if fwd.angle_to(to.normalized()) > deg_to_rad(35.0) or to.length() > 2.6 or to.length() < 1.0:
		l.set_meta("moving", true)
	if l.get_meta("moving", false):
		l.global_position = l.global_position.lerp(target, 1.0 - exp(-4.0 * get_process_delta_time()))
		if l.global_position.distance_to(target) < 0.05:
			l.set_meta("moving", false)
	var face := l.global_position - cam.global_position
	face.y = 0.0
	if face.length() > 0.1:
		l.global_basis = Basis(Vector3.UP, atan2(-face.x, -face.z))  # front (+Z) towards the pilot, upright
