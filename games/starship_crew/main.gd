extends Node3D
## STARSHIP CREW: fly a little starship home through space.
## - The VR player (slot 0, host) is the PILOT in the cockpit: take the flight stick (touch it, or
##   squeeze the trigger on it) and move the hand to slide the ship through the glowing rings.
##   Everything on the dashboard does something when touched (cockpit.gd).
## - TV players (slots 1..6, or 0 too in local play without a headset) are the GUNNERS: each moves
##   a crosshair in their colour with the left stick and zaps space rocks and silly aliens with A.
## - Rings, rocks and aliens all give stars; eight stars fill the dashboard and finish a mission.
##   Four short missions, one new thing each: rings (with practice), a rock shower, silly aliens,
##   then home to the space station (the ship docks by itself). No failure: a rock that reaches the
##   ship just bounces off the shield. No numbers: stars and planet lamps show the progress.
## - PRACTICE: the pilot gets a glowing ring that waits, and a ghost glove that shows how to push the
##   stick towards it (ghost_hand.gd); the gunners get one glowing rock that waits to be zapped.
## - Text: VR gets one short headline far out in front; the TV shows one short line at most.
## - Solo VR: a CPU gunner zaps now and then. Local play without a headset: a robot autopilot flies.
## Modes as in games/engine_template: local (one shared TV view), host (VR on the Steam Frame,
## simulates everything), client (the TV machine: mirrors the host, sends its zaps to the host).

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
const Awards := preload("res://core/awards.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const SkyKit := preload("res://core/sky_kit.gd")
const Art := preload("res://games/starship_crew/art.gd")
const Space := preload("res://games/starship_crew/space.gd")
const Cockpit := preload("res://games/starship_crew/cockpit.gd")
const GhostHand := preload("res://games/starship_crew/ghost_hand.gd")

const GAME_ID := "starship_crew"
const NEED := 8  ## stars per mission
const MISSIONS := 4
const NAMES: Array[String] = ["STAR RINGS!", "SPACE ROCKS!", "SILLY ALIENS!", "HOME!"]
## Seconds between new rings / rocks / aliens per mission (0 = none).
const RING_EVERY: Array[float] = [3.6, 5.5, 5.5, 4.5]
const ROCK_EVERY: Array[float] = [3.2, 1.1, 3.0, 2.0]
const UFO_EVERY: Array[float] = [0.0, 0.0, 3.2, 6.0]
const STEER_SPEED := 5.0
## The TV camera never moves (the ship stays at the origin), so the host can aim the TV crosshairs too.
const CAM_POS := Vector3(0.0, 3.4, 10.5)
const CAM_LOOK := Vector3(0.0, 0.6, -30.0)
const CAM_FOV := 60.0
const ASPECT := 16.0 / 9.0
const CROSS_SPEED := 1.3
const CPU_COLOR := Color(1.0, 0.95, 0.6)

# --- The networking contract ---
var net: Node
var ready_to_play := false
var party: Party
var split: SplitView
var vr_rig: VrRig
var save: Save
var sfx: Node
var music: Node
var awards: Awards
var sky: SkyKit.SkyRig

var space: Space
var cockpit: Cockpit
var ghost: GhostHand
var avatar: VrRig.Avatar
var shield: MeshInstance3D
var shield_mat: ShaderMaterial
var beam_mats := {}  ## colour html -> material

# Host
var vel := Vector2.ZERO
var mission_t := 0.0
var phase_t := 0.0
var ring_t := 2.0
var rock_t := 1.0
var ufo_t := 2.0
var cpu_t := 3.0
var prac_ring := -1
var prac_rock := -1
var station := -1
var log_rings := 0  ## bots: rings flown through
var log_pops := {}  ## bots: slot -> things zapped
var log_toys := {}  ## bots: toys pressed

# TV
var cross := {}  ## slot -> Vector2 (-1..1 screen, y up)
var cross_ui := {}  ## slot -> Crosshair
var zapped := {}  ## slot -> true once they zapped (the "A Zap!" pill goes away)
var cross_layer: Control
var hud: Control
var star_row: HBoxContainer
var flag_row: HBoxContainer
var pill: Control
var pill_text := ""
var results_ui: Control
var tv_banner: Control
var shake := 0.0
var lasers_seen := 0  ## bots (TV machine): laser beams drawn

# VR
var headline: Label3D
var headline_t := 0.0
var demo_tilt := Vector2.ZERO


## A gunner's crosshair: a ring in the player's colour.
class Crosshair extends Control:
	var col := Color.WHITE
	var kick := 0.0

	func _process(delta: float) -> void:
		if kick > 0.0:
			kick = maxf(0.0, kick - delta * 4.0)
			queue_redraw()

	func _draw() -> void:
		var r := 30.0 * (1.0 + kick * 0.5)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0, 0, 0, 0.55), 11.0)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, col, 6.0)
		for k in 4:
			var d := Vector2.RIGHT.rotated(k * PI * 0.5)
			draw_line(d * (r - 12.0), d * (r + 12.0), col, 5.0)
		draw_circle(Vector2.ZERO, 5.0, col)


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
	save.defaults = {"trips": 0}
	add_child(save)
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("space")
	music.prepare(["victory"])
	awards = Awards.new()
	awards.define("zapper", "SUPER ZAPPER", "%s space rocks zapped", "zaps")
	awards.define("alien_pal", "ALIEN FRIEND", "%s silly aliens spun", "ufos")
	awards.define("ace", "ACE PILOT", "%s rings flown", "rings")
	awards.define("honker", "HONK HONK", "%s honks", "honks")
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
		vr_rig.locomotion = false
		vr_rig.turn_mode = "none"
		vr_rig.eye_height = 1.2  # seated in the cockpit
		vr_rig.fit_limits = Vector2(-0.6, 0.6)
		add_child(vr_rig)
		vr_rig.camera.far = 1200.0
		vr_rig.place(Vector3(0.0, 0.0, 0.12), 0.0)
	sky = SkyKit.apply(self, "space", vr_rig != null)
	space = Space.new()
	space.name = "Space"
	add_child(space)
	cockpit = Cockpit.new()
	cockpit.name = "Cockpit"
	add_child(cockpit)
	cockpit.setup(self, vr_rig)
	_build_shield()
	if vr_rig != null:
		ghost = GhostHand.new()
		add_child(ghost)
		awards.set_player(0, "PILOT")
	if mode != "host":
		split = SplitView.new()
		split.camera_far = 1200.0
		add_child(split)
		split.bind_party(party)
		split.set_shared(true)
		var sc := split.shared_camera()
		sc.fov = CAM_FOV
		sc.global_transform = _cam_xf()
		_make_hud(split.shared_hud())
		if mode == "client":
			avatar = VrRig.Avatar.new()
			add_child(avatar)
			split.set_bubble(VrRig.build_mirror(self, avatar.head, false))
		elif vr_rig != null:
			split.set_bubble(vr_rig.mirror)
		else:
			cockpit.add_robot()
	party.allow_slot0 = mode == "local" and vr_rig == null
	if mode != "client":
		_start_show()
	else:
		space.set_planet(int(net.state_get("mission", 0)))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Starship Crew: %s mode%s" % [mode, " with a VR pilot" if vr_rig != null else ""])


static func _cam_xf() -> Transform3D:
	return Transform3D(Basis.looking_at(CAM_LOOK - CAM_POS, Vector3.UP), CAM_POS)


func _build_shield() -> void:
	shield = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 20
	sm.rings = 10
	shield.mesh = sm
	shield.scale = Vector3(4.6, 2.6, 6.0)
	shield.position = Vector3(0.0, 0.3, 0.3)
	var sh := Shader.new()
	sh.code = Space.GLOW_SHADER
	shield_mat = ShaderMaterial.new()
	shield_mat.shader = sh
	shield_mat.set_shader_parameter("col", Color(0.4, 0.8, 1.0, 0.0))
	shield.material_override = shield_mat
	shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shield.visible = false
	add_child(shield)


# --- The show (host / local) -----------------------------------------------------------------------

func _start_show() -> void:
	awards.reset()
	if vr_rig != null:
		awards.set_player(0, "PILOT")
	for s in _crew_slots():
		awards.set_player(s, party.name_of(s))
	space.clear()
	space.speed = 10.0
	station = -1
	cockpit.show_again(false)
	net.state_set("missions", 0)
	var first := 0
	if OS.has_environment("SC_MISSION") and not has_meta("started"):
		first = clampi(int(OS.get_environment("SC_MISSION")), 0, MISSIONS - 1)
	if not has_meta("started"):
		net.state_set("practice", 0 if first == 0 else 3)
		net.state_set("missions", first)
	set_meta("started", true)
	_go_mission(first)


func _go_mission(i: int) -> void:
	mission_t = 0.0
	ring_t = 2.0
	rock_t = 1.5
	ufo_t = 1.0
	net.state_set("stars", 0)
	net.state_set("mission", i)
	net.state_set("phase", "play")
	space.set_planet(i)
	if i == 0 and int(net.state_get("practice", 0)) != 3:
		var pr := int(net.state_get("practice", 0))
		if vr_rig == null:
			pr |= 1  # no pilot to teach: the robot flies
		if pr & 1 == 0:
			prac_ring = space.add(Space.RING, Vector3(space.off.x + 4.0, space.off.y, -16.0), true)
		if pr & 2 == 0:
			prac_rock = space.add(Space.ROCK, Vector3(space.off.x - 3.0, space.off.y + 1.6, -24.0), true)
		net.state_set("practice", pr)
	music.play_mood("space")


func _mission_done() -> void:
	var m := int(net.state_get("mission", 0))
	net.state_set("missions", m + 1)
	if m + 1 >= MISSIONS:
		net.state_set("phase", "dock")
		station = space.add(Space.STATION, Vector3(space.off.x * 0.5, space.off.y * 0.5, -120.0))
	else:
		net.state_set("phase", "cheer")
	phase_t = 0.0
	sound_at("fanfare", Vector3(0, 1, -3), -4.0)
	sound_at("applause", Vector3(0, 1, -3), -6.0)
	_pulse_both(0.6, 0.2)


func _arrived() -> void:
	save.data["trips"] = int(save.data["trips"]) + 1
	save.mark_dirty()
	sound_at("party_horn", Vector3(0, 1, -4), -2.0)
	sound_at("cheer", Vector3(0, 1, -4), -2.0)
	confetti(Vector3(0, 2.5, -6), Color(1.0, 0.5, 0.7), 60)
	net.event("confetti", [Vector3(0, 2.5, -6), Color(1.0, 0.5, 0.7), 60])
	var data := awards.results({"title": "HOME SWEET HOME!", "style": "victory", "score_stat": "stars",
		"score_format": "%d STARS", "continue": "Again!"})
	net.state_set("results", data)
	net.state_set("phase", "results")
	phase_t = 0.0


func _crew_slots() -> Array[int]:
	var out: Array[int] = []
	for s in party.active_slots():
		if s != 0 or vr_rig == null:
			out.append(s)
	return out


# --- Host rules --------------------------------------------------------------------------------------

func _host_step(delta: float) -> void:
	var phase := String(net.state_get("phase", "play"))
	var mission := int(net.state_get("mission", 0))
	# Steering: the pilot's hands, or the robot autopilot.
	var want := Vector2.ZERO
	if vr_rig != null:
		cockpit.update_vr(delta)
		want = cockpit.steer
		_ghost(delta)
	else:
		want = _autopilot()
		cockpit.steer = cockpit.steer.lerp(want, 1.0 - exp(-6.0 * delta))
	if phase == "dock" or phase == "results":
		want = Vector2.ZERO
	vel = vel.move_toward(want * STEER_SPEED, 9.0 * delta)
	space.off += vel * delta
	# Rings gently pull the ship in when it's close (kids get them more often).
	var rid := space.next_ring()
	if rid >= 0:
		var rp: Vector3 = space.objs[rid]["p"]
		var to := Vector2(rp.x, rp.y) - space.off
		if rp.z > -25.0 and to.length() < 4.5 and not bool(space.objs[rid]["held"]):  # not the practice ring
			space.off += to * minf(1.0, 0.9 * delta)
	if station >= 0 and space.objs.has(station):
		var sp: Vector3 = space.objs[station]["p"]
		space.off = space.off.lerp(Vector2(sp.x, sp.y), minf(1.0, 0.7 * delta))
		space.speed = clampf(-(sp.z + 4.0) / 3.0, 2.0 if phase == "dock" else 0.0, 10.0)
		if phase == "dock" and sp.z > -6.0:
			_arrived()
	space.off = space.off.clamp(-Space.LIMIT, Space.LIMIT)
	for e in space.step(delta):
		_space_event(e)
	_practice()
	mission_t += delta
	if phase == "play":
		_spawn(mission, delta)
		_cpu_crew(delta)
		if int(net.state_get("stars", 0)) >= NEED:
			_mission_done()
	elif phase == "cheer":
		phase_t += delta
		if phase_t > 4.0:
			_go_mission(mission + 1)
	elif phase == "dock":
		_cpu_crew(delta)
	elif phase == "results":
		phase_t += delta
		if phase_t > 45.0:
			_start_show()


func _autopilot() -> Vector2:
	var rid := prac_ring if space.objs.has(prac_ring) else space.next_ring()
	if rid >= 0:
		var rp: Vector3 = space.objs[rid]["p"]
		if rp.z > -80.0:
			return ((Vector2(rp.x, rp.y) - space.off) / 2.0).limit_length(1.0)
	return (-space.off / 6.0).limit_length(0.5)


func _spawn(mission: int, delta: float) -> void:
	if mission == 0 and int(net.state_get("practice", 3)) != 3 and mission_t < 40.0:
		return
	var off := space.off
	ring_t -= delta
	if ring_t <= 0.0:
		ring_t = RING_EVERY[mission]
		var p := Vector3(off.x * 0.6 + randf_range(-5.0, 5.0), off.y * 0.6 + randf_range(-2.5, 2.5), Space.SPAWN_Z)
		p.x = clampf(p.x, -Space.LIMIT.x, Space.LIMIT.x)
		p.y = clampf(p.y, -Space.LIMIT.y, Space.LIMIT.y)
		space.add(Space.RING, p)
	rock_t -= delta
	if rock_t <= 0.0:
		rock_t = ROCK_EVERY[mission] * randf_range(0.8, 1.2)
		var n := 3 if mission == 1 and randf() < 0.35 else 1
		var c := Vector3(off.x + randf_range(-7.0, 7.0), off.y + randf_range(-3.0, 4.0), Space.SPAWN_Z + randf_range(0.0, 10.0))
		for k in n:
			var id := space.add(Space.ROCK, c + Vector3(k * 2.6, k * 1.2, k * 3.0))
			space.objs[id]["v"] = Vector3(randf_range(-0.6, 0.6), randf_range(-0.3, 0.3), randf_range(-2.0, 2.0))
	if UFO_EVERY[mission] > 0.0:
		ufo_t -= delta
		var ufos := 0
		for id in space.objs:
			if int(space.objs[id]["kind"]) == Space.UFO:
				ufos += 1
		if ufo_t <= 0.0 and ufos < 3:
			ufo_t = UFO_EVERY[mission]
			space.add(Space.UFO, Vector3(off.x + randf_range(-4.0, 4.0), off.y + randf_range(0.5, 2.5), -95.0))


## The practice ring waits until the pilot lines up with it, then flies through.
func _practice() -> void:
	if prac_ring >= 0 and space.objs.has(prac_ring) and bool(space.objs[prac_ring]["held"]):
		var rp: Vector3 = space.objs[prac_ring]["p"]
		if Vector2(rp.x, rp.y).distance_to(space.off) < 1.6:
			space.release(prac_ring, 12.0)
			sound_at("whoosh", Vector3(0, 1.2, -8), -4.0, 1.2)


func _space_event(e: Array) -> void:
	var id: int = e[1]
	match String(e[0]):
		"ring":
			var p := Vector3(0.0, Space.SHIP_Y, -0.5)
			if bool(e[2]):
				log_rings += 1
				sound_at("ding", p, -2.0, 1.3)
				sound_at("whoosh", p, -6.0, 1.4)
				confetti(p + Vector3(0, 0, -3), Color(0.5, 1.0, 0.95), 30)
				net.event("confetti", [p + Vector3(0, 0, -3), Color(0.5, 1.0, 0.95), 30])
				_pulse_both(0.5, 0.1)
				awards.add(0, "rings")
				if id == prac_ring:
					prac_ring = -1
					net.state_set("practice", int(net.state_get("practice", 0)) | 1)
					show_headline("YES!")
				_add_stars(2, p + Vector3(0, 0, -3), 0)
			else:
				sound_at("whoosh", p, -12.0, 0.8)
				if id == prac_ring:  # missed the practice ring somehow: another one waits
					prac_ring = space.add(Space.RING, Vector3(space.off.x - 4.0, space.off.y, -16.0), true)
		"bump":
			var w := space.world_pos(id)
			sound_at("bounce", w, -2.0, 0.9)
			sound_at("boing", w, -6.0, 0.8)
			_bump_fx()
			net.event("bump", [])
			_pulse_both(0.4, 0.12)


func _cpu_crew(delta: float) -> void:
	if not _crew_slots().is_empty():
		return
	cpu_t -= delta
	if cpu_t > 0.0:
		return
	cpu_t = 2.4
	var pick := -1
	if prac_rock >= 0 and space.objs.has(prac_rock):
		if mission_t < 6.0:
			return
		pick = prac_rock
	else:
		var ids := space.zappables()
		ids.shuffle()
		for id in ids:
			if (space.objs[id]["p"] as Vector3).z > -60.0:
				pick = id
				break
	if pick >= 0:
		zap(-1, project(space.world_pos(pick)))


## Where a world point shows on the TV screen (-1..1, y up), or far off-screen behind the camera.
static func project(w: Vector3) -> Vector2:
	var q := _cam_xf().affine_inverse() * w
	if q.z > -0.5:
		return Vector2(9.0, 9.0)
	var t := tan(deg_to_rad(CAM_FOV) * 0.5)
	return Vector2(q.x / (-q.z * t * ASPECT), q.y / (-q.z * t))


static func screen_ray(uv: Vector2) -> Vector3:
	var t := tan(deg_to_rad(CAM_FOV) * 0.5)
	return (_cam_xf().basis * Vector3(uv.x * t * ASPECT, uv.y * t, -1.0)).normalized()


## Host: a gunner (slot, or -1 = the CPU gunner) zaps at a point on the TV screen. Generous aim.
func zap(slot: int, uv: Vector2) -> void:
	var best := -1
	var best_s := INF
	var t := tan(deg_to_rad(CAM_FOV) * 0.5)
	for id in space.zappables():
		var w := space.world_pos(id)
		var q := _cam_xf().affine_inverse() * w
		if q.z > -2.0:
			continue
		var s := project(w)
		var d := Vector2((s.x - uv.x) * ASPECT, s.y - uv.y).length()
		var tol := 0.14 + float(space.objs[id]["r"]) / (-q.z * t)
		if d < tol and d - tol < best_s:
			best_s = d - tol
			best = id
	var col: Color = CPU_COLOR if slot < 0 else party.color_of(slot)
	var from: Vector3 = Art.TURRETS[0 if uv.x < 0.0 else 1]
	var to := CAM_POS + screen_ray(uv) * 90.0
	if best >= 0:
		to = space.world_pos(best)
	laser(from, to, col)
	net.event("laser", [from, to, col])
	sound_at("laser", from, -8.0, randf_range(1.1, 1.3))
	if best >= 0:
		_pop(best, slot, col)


func _pop(id: int, slot: int, col: Color) -> void:
	var w := space.world_pos(id)
	var kind: int = space.objs[id]["kind"]
	space.remove(id)
	log_pops[slot] = int(log_pops.get(slot, 0)) + 1
	pop_fx(w, col, kind)
	net.event("pop", [w, col, kind])
	if kind == Space.UFO:
		sound_at("boing", w, 0.0, 1.4)
		sound_at("party_horn", w, -8.0, 1.2)
		if slot >= 0:
			awards.add(slot, "ufos")
	else:
		sound_at("pop", w, -2.0, randf_range(0.8, 1.1))
		sound_at("sparkle", w, -6.0)
		if slot >= 0:
			awards.add(slot, "zaps")
	if id == prac_rock:
		prac_rock = -1
		net.state_set("practice", int(net.state_get("practice", 0)) | 2)
	_add_stars(2 if kind == Space.UFO else 1, w, slot)


func _add_stars(n: int, from: Vector3, slot: int) -> void:
	if String(net.state_get("phase", "play")) != "play":
		return
	net.state_set("stars", mini(NEED, int(net.state_get("stars", 0)) + n))
	if slot >= 0:
		awards.add(slot, "stars", n)
	fly_stars(from, n)
	net.event("star", [from, n])


## Host: a toy in the cockpit was touched.
func on_toy(k: String) -> void:
	log_toys[k] = true
	var p := Vector3(0.0, 0.9, -0.6)
	match k:
		"honk":
			sound_at("honk", p, -2.0, randf_range(0.9, 1.1))
			awards.add(0, "honks")
		"disco":
			sound_at("power_up", p, -6.0)
		"bubbles":
			sound_at("bubbles", p, -2.0)
		"bobble":
			sound_at("boing", p, -6.0, 1.6)
		"again":
			on_request(0, "again", [])
			return
	toy_fx(k)
	net.event("toy", [k])


func _pulse_both(a: float, d: float) -> void:
	if vr_rig != null:
		vr_rig.pulse(VrRig.RIGHT, a, d)
		vr_rig.pulse(VrRig.LEFT, a, d)


## Host / local: a player asked for something (from any machine).
func on_request(slot: int, action: String, args: Array) -> void:
	match action:
		"zap":
			if args.size() >= 2 and String(net.state_get("phase", "")) in ["play", "dock", "cheer"]:
				zap(slot, Vector2(float(args[0]), float(args[1])))
		"again":
			if String(net.state_get("phase", "")) == "results":
				_start_show()


# --- Every machine --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if net.mode != "client":
		_host_step(delta)
	if split != null:
		_gunners(delta)
	if ghost != null and ghost.visible and cockpit.held_by < 0:
		cockpit.steer = demo_tilt
	cockpit.animate(delta)
	space.animate(delta)
	cockpit.set_progress(int(net.state_get("stars", 0)), int(net.state_get("missions", 0)))
	_headline(delta)
	if shield.visible:
		var c: Color = shield_mat.get_shader_parameter("col")
		c.a = maxf(0.0, c.a - delta * 1.5)
		shield_mat.set_shader_parameter("col", c)
		shield.visible = c.a > 0.0
	if split != null:
		shake = maxf(0.0, shake - delta * 2.0)
		var sc := split.shared_camera()
		sc.global_transform = _cam_xf()
		if shake > 0.0:
			sc.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * shake * 0.25
		_update_pill()


func _ghost(delta: float) -> void:
	var playing := String(net.state_get("phase", "play")) == "play"
	var practicing := prac_ring >= 0 and space.objs.has(prac_ring) and bool(space.objs[prac_ring]["held"])
	var idle := cockpit.idle_t > 30.0 and cockpit.held_t > 0.0
	var on := playing and cockpit.held_by < 0 and (practicing or idle) and mission_t > 1.0
	var dir := Vector2(1.0, 0.0)
	if practicing:
		var rp: Vector3 = space.objs[prac_ring]["p"]
		dir = (Vector2(rp.x, rp.y) - space.off).limit_length(1.0)
		if dir.length() < 0.3:
			dir = Vector2(1.0, 0.0)
		dir = dir.normalized()
	else:
		var rid := space.next_ring()
		if rid >= 0:
			var rp2: Vector3 = space.objs[rid]["p"]
			var d2 := Vector2(rp2.x, rp2.y) - space.off
			if d2.length() > 0.3:
				dir = d2.normalized()
	demo_tilt = ghost.show_demo(on, cockpit.handle_point(), dir, delta)


## TV: each local gunner moves a crosshair with the left stick and zaps with A.
func _gunners(delta: float) -> void:
	var playing := String(net.state_get("phase", "")) in ["play", "dock", "cheer"]
	for slot in party.local_slots():
		if not cross.has(slot):
			_add_cross(slot)
		var c: Vector2 = cross[slot]
		var mv := party.stick(slot, "move")
		if mv.length() > 0.15:
			c += Vector2(mv.x, -mv.y) * CROSS_SPEED * delta
			c = c.clamp(Vector2(-0.95, -0.9), Vector2(0.95, 0.9))
			cross[slot] = c
		var ui: Crosshair = cross_ui[slot]
		var sz := cross_layer.size
		ui.position = Vector2((c.x + 1.0) * 0.5 * sz.x, (1.0 - c.y) * 0.5 * sz.y)
		ui.visible = playing
		if playing and (party.just_pressed(slot, "accept") or party.just_pressed(slot, "rt")):
			zapped[slot] = true
			ui.kick = 1.0
			party.rumble(slot, 0.2, 0.0, 0.08)
			net.request(slot, "zap", [c.x, c.y])
	for slot in cross.keys():
		if not party.is_local(int(slot)):
			_remove_cross(int(slot))


func _add_cross(slot: int) -> void:
	var ui := Crosshair.new()
	ui.col = party.color_of(slot)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross_layer.add_child(ui)
	cross_ui[slot] = ui
	var n := cross.size()
	cross[slot] = Vector2(-0.3 + 0.2 * (n % 4), 0.1 - 0.15 * (n >> 2))
	if vr_rig == null and net.mode != "client":
		awards.set_player(slot, party.name_of(slot))


func _remove_cross(slot: int) -> void:
	if cross_ui.has(slot):
		(cross_ui[slot] as Node).queue_free()
	cross_ui.erase(slot)
	cross.erase(slot)


func _on_player_joined(slot: int, _device: int) -> void:
	sfx.play("ui_notify", -6.0)
	if net.mode != "client" and (slot != 0 or vr_rig == null):
		awards.set_player(slot, party.name_of(slot))


func _on_player_left(slot: int) -> void:
	_remove_cross(slot)


# --- Effects (every machine) -------------------------------------------------------------------------

func laser(from: Vector3, to: Vector3, col: Color) -> void:
	lasers_seen += 1
	var key := col.to_html(false)
	if not beam_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col.lightened(0.3)
		beam_mats[key] = m
	var mi := MeshInstance3D.new()
	mi.mesh = Art.beam()
	mi.material_override = beam_mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var ln := from.distance_to(to)
	mi.global_transform = Transform3D(Basis.looking_at(to - from, Vector3.UP).scaled(Vector3(1.0, 1.0, ln)), from)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(0.05, 0.05, ln), 0.2)
	tw.tween_callback(mi.queue_free)


func pop_fx(w: Vector3, col: Color, kind: int) -> void:
	confetti(w, col, 40 if kind == Space.UFO else 24)
	if kind == Space.UFO:  # the saucer spins away into the distance, wheee
		var mi := MeshKit.instance(Art.ufo(), false)
		add_child(mi)
		mi.global_position = w
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position", w + Vector3(randf_range(-20, 20), 18.0, -40.0), 1.4)
		tw.tween_property(mi, "rotation", Vector3(2.0, 18.0, 1.0), 1.4)
		tw.tween_property(mi, "scale", Vector3.ONE * 0.2, 1.4)
		tw.chain().tween_callback(mi.queue_free)


## Stars fly from where they were won into the dashboard.
func fly_stars(from: Vector3, n: int) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	for k in n:
		var mi := MeshInstance3D.new()
		mi.mesh = Art.star()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = from
		mi.scale = Vector3.ONE * 0.5
		var to := Vector3(-0.3 + k * 0.6, 1.2, -1.2)
		var tw := mi.create_tween()
		tw.tween_interval(k * 0.15)
		tw.tween_property(mi, "global_position", to, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(mi, "scale", Vector3.ONE * 0.06, 0.7)
		tw.tween_callback(mi.queue_free)
	sfx.play_at("pickup", from.lerp(Vector3(0, 1, -1), 0.7), -8.0, 1.2)


func toy_fx(k: String) -> void:
	cockpit.toy_fx(k)
	if k == "bubbles":
		var cp := CPUParticles3D.new()
		cp.one_shot = true
		cp.amount = 24
		cp.lifetime = 2.5
		cp.explosiveness = 0.4
		cp.direction = Vector3(0, 0.3, -1)
		cp.spread = 25.0
		cp.initial_velocity_min = 2.0
		cp.initial_velocity_max = 4.0
		cp.gravity = Vector3.ZERO
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		sm.radial_segments = 10
		sm.rings = 5
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.7, 0.9, 1.0, 0.45)
		m.metallic_specular = 1.0
		sm.material = m
		cp.mesh = sm
		add_child(cp)
		cp.position = Vector3(0.0, 1.2, -2.2)
		cp.emitting = true
		get_tree().create_timer(3.0).timeout.connect(cp.queue_free)


func _bump_fx() -> void:
	shield.visible = true
	shield_mat.set_shader_parameter("col", Color(0.4, 0.8, 1.0, 0.6))
	shake = 1.0


func sound_at(n: String, p: Vector3, db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play_at(n, p, db, pitch)
	if net.mode == "host":
		net.event("sfx", [n, p, db, pitch])


func confetti(p: Vector3, col: Color, amount: int) -> void:
	var cp := CPUParticles3D.new()
	cp.one_shot = true
	cp.amount = amount
	cp.lifetime = 1.4
	cp.explosiveness = 0.95
	cp.direction = Vector3.UP
	cp.spread = 180.0
	cp.initial_velocity_min = 3.0
	cp.initial_velocity_max = 7.0
	cp.gravity = Vector3.ZERO
	cp.damping_min = 2.0
	cp.damping_max = 4.0
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.2, 0.04)
	bm.material = MeshKit.vertex_material(true)
	cp.mesh = bm
	var g := Gradient.new()
	g.colors = PackedColorArray([col, Color(1.0, 0.9, 0.3), Color(1.0, 0.5, 0.7), Color(0.5, 0.9, 1.0)])
	g.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	cp.color_initial_ramp = g
	add_child(cp)
	cp.position = p
	cp.emitting = true
	get_tree().create_timer(1.8).timeout.connect(cp.queue_free)


# --- VR headline ----------------------------------------------------------------------------------

## VR: one short headline far out in front of the ship (world-locked, facing the pilot).
func show_headline(text: String, secs: float = 3.0) -> void:
	if vr_rig == null:
		return
	if headline == null:
		headline = Label3D.new()
		headline.font_size = 96
		headline.pixel_size = 0.006
		headline.outline_size = 26
		headline.modulate = Color(1.0, 0.92, 0.35)
		headline.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
		headline.double_sided = false
		headline.process_mode = Node.PROCESS_MODE_ALWAYS
		headline.position = Vector3(0.0, 2.6, -7.0)
		add_child(headline)
	headline.text = text
	headline.visible = true
	headline_t = secs


func _headline(delta: float) -> void:
	if headline == null or not headline.visible or headline_t < 0.0:
		return
	headline_t -= delta
	if headline_t <= 0.0:
		headline.visible = false


# --- TV HUD -------------------------------------------------------------------------------------------

func _make_hud(parent: Control) -> void:
	cross_layer = Control.new()
	cross_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cross_layer)
	hud = UiKit.ui_root(parent)
	var card := UiKit.panel("card")
	hud.add_child(card)
	card.position = Vector2(24.0, 20.0)
	var col := VBoxContainer.new()
	card.add_child(col)
	flag_row = UiKit.hbox(6)
	col.add_child(flag_row)
	star_row = UiKit.hbox(4)
	col.add_child(star_row)
	pill = UiKit.panel("pill")
	hud.add_child(pill)
	pill.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pill.offset_top = -60.0
	pill.offset_bottom = -60.0
	_refresh_hud()


func _update_pill() -> void:
	var want := ""
	if party.local_slots().is_empty():
		want = "Join"
	else:
		for s in party.local_slots():
			if not zapped.has(s):
				want = "Zap!"
	if String(net.state_get("phase", "")) == "results":
		want = ""
	if want != pill_text:
		pill_text = want
		for c in pill.get_children():
			c.queue_free()
		if want != "":
			pill.add_child(UiKit.prompts([["A", want]]))
	pill.visible = want != ""


## Top-left: four planet flags (missions done) and eight stars (this mission). No numbers.
func _refresh_hud() -> void:
	if star_row == null:
		return
	for c in star_row.get_children():
		c.queue_free()
	for c in flag_row.get_children():
		c.queue_free()
	var stars := int(net.state_get("stars", 0))
	var done := int(net.state_get("missions", 0))
	for k in MISSIONS:
		flag_row.add_child(UiKit.icon("flag", "gold" if k < done else "dim", 30.0))
	for k in NEED:
		star_row.add_child(UiKit.icon("star", "gold" if k < stars else "dim", 34.0))


# --- Store, results, pause ----------------------------------------------------------------------

func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"stars", "missions":
			_refresh_hud()
		"mission":
			space.set_planet(int(value))
		"phase":
			var ph := String(value)
			if ph == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()
			match ph:
				"play":
					var m := int(net.state_get("mission", 0))
					music.play_mood("space")
					if split != null:
						HudKit.banner([hud], NAMES[m], "", {"duration": 1.8})
					if m == 0 and int(net.state_get("practice", 3)) & 1 == 0:
						show_headline("FLY THROUGH THE RING!", 6.0)
					else:
						show_headline(NAMES[m])
				"cheer":
					music.play_mood("victory")
					show_headline("HOORAY!")
				"dock":
					music.play_mood("victory")
					show_headline("HOME!")


func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
	if split != null:
		var screen := Awards.results_screen(hud, data, {"party": party, "min_time": 5.0})
		screen.continued.connect(func() -> void:
			var seats := party.local_slots()
			net.request(seats[0] if not seats.is_empty() else 0, "again"))
		results_ui = screen
	if vr_rig != null:
		show_headline("HOME SWEET HOME!", 8.0)
		cockpit.show_again(true)


func _hide_results() -> void:
	if results_ui != null and is_instance_valid(results_ui):
		results_ui.queue_free()
	results_ui = null
	cockpit.show_again(false)


func results_showing() -> bool:
	return String(net.state_get("phase", "")) == "results"


func on_pause_changed(paused: bool, _by_slot: int) -> void:
	if vr_rig != null:
		if paused:
			show_headline("PAUSED", -1.0)
		elif headline != null:
			headline.visible = false
	if split != null:
		if tv_banner == null:
			var ui := UiKit.ui_root(self, 6)
			ui.process_mode = Node.PROCESS_MODE_ALWAYS
			tv_banner = UiKit.panel("accent")
			ui.add_child(tv_banner)
			tv_banner.add_child(UiKit.title("PAUSED"))
			tv_banner.set_anchors_preset(Control.PRESET_CENTER)
			tv_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
			tv_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
		tv_banner.visible = paused
		if paused:
			UiKit.pop_in(tv_banner)


# --- Networking -----------------------------------------------------------------------------------

func make_snapshot() -> Array:
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	var s := space.pack()
	return [pose, space.off, cockpit.steer, space.speed, s[0], s[1], s[2]]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 7:
		return
	var dt := get_process_delta_time()
	if avatar != null:
		avatar.apply_pose(s[0])
	var off: Vector2 = s[1]
	space.off = off if space.off.distance_to(off) > 5.0 else space.off.lerp(off, 1.0 - exp(-20.0 * dt))
	var st: Vector2 = s[2]
	cockpit.steer = st
	space.speed = float(s[3])
	space.unpack([s[4], s[5], s[6]], dt)


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"sfx":
			sfx.play_at(String(args[0]), args[1], float(args[2]), float(args[3]))
		"confetti":
			confetti(args[0], args[1], int(args[2]))
		"laser":
			laser(args[0], args[1], args[2])
		"pop":
			pop_fx(args[0], args[1], int(args[2]))
		"star":
			fly_stars(args[0], int(args[1]))
		"toy":
			toy_fx(String(args[0]))
		"bump":
			_bump_fx()
