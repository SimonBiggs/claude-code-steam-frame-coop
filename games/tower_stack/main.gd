extends Node3D
## TOWER STACK: build the tallest tower together.
## Smiley jelly blocks drop into the park. TV players push them across the grass onto the bouncy
## pad, which boings them up to the VR giant's hands. The giant (world scale WS) grabs them with the
## right trigger and stacks them on the round stage. The gold hoop is the record: beat it! A falling
## tower is just a funny WOBBLE: keep going. 3-minute rounds, then results and an automatic replay.
## TV players can jump (A) and climb the tower. Without VR a helper crane does the stacking.
## Story + depth: WREN the builder bird (wren.gd) asks for one building after another (towergen.gd: a
## seeded JOB: the silhouette to match shown as a see-through plan on the stage, which blocks come
## (cubes, planks, slabs, heavy stones), wind and a wobbly jelly stage on later jobs, the gold hoop at
## the goal height). Reach the hoop and hold it: the tower gets its roof and joins THE TOWN behind the
## park (skyline.gd, saved, grows over days). TODAY'S TOWER: job 2 of the first round each day is gold.
## Telemetry: one RUN line per round and on quit.
## Built on the shared engine (see games/engine_template/main.gd and docs/engine/).

const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const Party := preload("res://core/party.gd")
const SplitView := preload("res://core/split_view.gd")
const VrRig := preload("res://core/vr_rig.gd")
const VrText := preload("res://core/vr_text.gd")
const CameraRig := preload("res://core/camera_rig.gd")
const Save := preload("res://core/save.gd")
const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const Hints := preload("res://core/hints.gd")
const Awards := preload("res://core/awards.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Creatures := preload("res://core/creatures.gd")
const SkyKit := preload("res://core/sky_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Looks := preload("res://games/tower_stack/looks.gd")
const JellyScript := preload("res://games/tower_stack/jelly.gd")
const G := preload("res://games/tower_stack/towergen.gd")
const WrenScript := preload("res://games/tower_stack/wren.gd")
const SkylineScript := preload("res://games/tower_stack/skyline.gd")
const Seeded := preload("res://core/seeded.gd")
const Telemetry := preload("res://core/telemetry.gd")
const StoryCard := preload("res://core/story_card.gd")
const WREN_COLOR := Color(0.62, 0.42, 0.25)
const TOWN_CHEERS := {1: "Our town!", 5: "Five towers!", 10: "Ten towers!", 20: "A big town!", 30: "A city!"}
const CHEER := 3.5  # seconds a finished tower stands with its roof before it flies to the town
const SNAP_R := 0.22  # a gentle place this close to a plan spot of the same block snaps onto it

const GAME_ID := "tower_stack"
const ARENA := 9.0
const WS := 2.5  # the VR player is a giant
const SPEED := 4.5
const JUMP := 7.5
const GRAVITY := 20.0
const STEP := 0.3
const BODY_R := 0.3
const B := Looks.BLOCK
const H := Looks.BLOCK * 0.5
const BASE_R := 1.2
const BASE_H := 0.2
const PAD := Vector3(1.7, 0.0, 1.5)
const PAD_R := 0.9
const VR_SPOT := Vector3(0.0, 0.0, 1.7)
const HOVER: Array[Vector3] = [Vector3(1.15, 2.7, 1.0), Vector3(1.15, 2.7, 1.65), Vector3(1.15, 2.7, 2.3)]
const GRAB_R := 0.65
const MAX_BLOCKS := 20
const MAX_LOOSE := 5
const CRANE_HOME := Vector3(2.6, 5.5, -0.5)
const LOOKS: Array[String] = ["knight", "mage", "archer", "bard", "pirate", "chef", "astronaut"]
const INTRO := {
	"title": "TOWER STACK",
	"goal": "Build the tallest tower together!",
	"vr": {"role": "THE GIANT", "controls": [["TRIGGER", "Grab a block"], ["L-STICK", "Walk"]]},
	"tv": {"role": "THE HELPERS", "controls": [["L-STICK", "Push blocks to the pad"], ["A", "Jump and climb"]]},
}

var round_time := 180.0  ## seconds per round (bots shorten it)

# --- Networking contract / engine members ---
var net: Node
var ready_to_play := false
var flat_host := false  # this machine hosts without VR: slot 0 is a pad / keyboard player here, like local play
var net_target := {}  # slot -> [pos, yaw]: where another machine's player is (smoothed towards every frame)
var party: Party
## Any number of TV machines (TV, Steam Decks) may join, and a flat host (no VR) works (docs/MULTI_MACHINE.md).
var multi_machine := true
var split: SplitView
var vr_rig: VrRig
var save: Save
var sfx: Node
var music: Node
var hints: Hints
var awards: Awards

var avatars := {}  # slot -> Node3D
var last_pos := {}  # slot -> Vector3 (walk animation)
var vys := {}  # slot -> float: vertical speed of a local TV player
var av_prev := {}  # slot -> Vector3 (authority: avatar velocity for pushing)
var av_vel := {}  # slot -> Vector3
var boop_cd := {}  # slot -> float
var cams := {}
var group_cam: CameraRig
var huds := {}
var height_labels := {}  # slot -> Label
var best_labels := {}  # slot -> Label
var timers := {}
var join_prompt: Control
var tv_banner: Control
var results_ui: Control
var vr_avatar: VrRig.Avatar
var vr_head_label: Label3D  # VR: the one big world-locked headline
var vr_head_t := 0.0
var vr_glove_label: Label3D  # VR: clock + height on the back of the left glove
var ring: MeshInstance3D
var ring_label: Label3D

# Blocks: id -> body (RigidBody3D on the host / local, a plain Node3D ghost on the TV machine).
var blocks := {}
var bstate := {}  # authority: id -> "free" | "held" | "hover" | "crane"
var ghost_t := {}  # TV machine: id -> Transform3D target
var hover: Array[int] = [-1, -1, -1]
var hover_t := {}  # id -> seconds since it was boinged up
var hover_from := {}  # id -> Vector3
var pusher := {}  # id -> slot that pushed it last
var placed := {}  # id -> true once the giant put it down by the tower
var poke_cd := {}
var next_id := 0
var held_id := -1
var held_off := Transform3D()
var crane: Node3D
var crane_state := "idle"
var crane_id := -1
var crane_goal := Vector3.ZERO
var crane_wait := 0.0
var crane_yaw := 0.0
var pad_idle_t := 0.0  # host: seconds the pad has had room but no block
var touch_cd := {}  # "pad" / "ring" -> clock time when it may react again

var time_left := 0.0
var results_t := 0.0
var spawn_t := 0.0
var height_t := 0.0
var tower_h := 0.0
var top_xz := Vector2.ZERO
var peak := 0.0
var peak_t := 0.0
var wobble_cd := 0.0
var clock := 0.0
var send_t := 0.0
# Totals over every round (bots check them).
var total_delivered := 0
var total_placed := 0
var max_height := 0.0
var total_built := 0
# Jobs (towergen.gd): the tower being built now, every machine rebuilds it from the "job" state.
var site := {}
var job_n := 0
var job_t := 0.0
var set_i := 0  # host: next block of the job's set to drop
var bkind := {}  # id -> towergen kind (every machine)
var bcolor := {}  # id -> colour index (every machine)
var fill := 0  # bitmask of plan spots holding a matching block ("fill" state)
var stable_t := 0.0
var done_t := -1.0  # host: >= 0 while a finished tower shows off its roof
var built_round := 0
var round_jobs: Array = []  # this round's finished jobs for telemetry [level, secs, perfect, daily]
var round_wobbles := 0
var session_seed := 0
var session_t := 0.0
var quit_logged := false
var wren: Node3D
var town: Node3D
var ghost_root: Node3D
var ghosts: Array[MeshInstance3D] = []
var sock: Node3D
var stage: Node3D  # the round stage: an AnimatableBody3D (host / local) that rocks on wobbly sites
var tilt := Vector2.ZERO
var ground_mi: MeshInstance3D
var path_mi: MeshInstance3D
var topper: Node3D
var built_labels := {}  # slot -> Label (towers built this round)


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
	save.defaults = {"best": 0.0, "built": 0, "town": [], "daily": "", "sessions": 0}
	add_child(save)
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm(["bounce", "boing", "pop", "jump", "land", "crash", "fanfare", "whoosh", "ding"], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("party")
	music.prepare(["victory"])
	awards = Awards.new()
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


func _exit_tree() -> void:
	XRServer.world_scale = 1.0  # global: never leave the giant scale behind for the next game
	_log_round("quit")


## One telemetry line per round (and when the game closes mid-round). Host / local only, once each.
func _log_round(end: String) -> void:
	if quit_logged or net == null or net.mode == "client" or not ready_to_play:
		return
	if end == "quit":
		quit_logged = true
		if results_showing() or job_n == 0:
			return  # the round already logged itself
	Telemetry.run(GAME_ID, {"end": end, "round": int(net.state_get("round", 0)), "towers": built_round,
		"jobs": round_jobs, "reached": job_n, "level": int(site.get("level", 0)), "rec": float(net.state_get("rec", 0.0)),
		"best": float(save.data.best), "wobbles": round_wobbles, "delivered": total_delivered, "placed": total_placed,
		"crew": party.player_count(), "vr": vr_rig != null, "secs": int(session_t), "seed": session_seed,
		"built": int(save.data.built), "town": (save.data.town as Array).size()})
	save.save_now()


func _setup(mode: String) -> void:
	flat_host = mode == "host" and not net.has_vr  # a flat host: slot 0 runs here, the crane is the giant
	if VrRig.wanted(mode) and not flat_host:
		vr_rig = VrRig.new()
		vr_rig.bounds = Rect2(-ARENA, -ARENA, ARENA * 2.0, ARENA * 2.0)
		vr_rig.move_speed = 3.5
		add_child(vr_rig)
		vr_rig.set_scale_of_world(WS)
		vr_rig.place(VR_SPOT, 0.0)
		vr_head_label = UiKit.label3d("", 0.14 * WS, "gold", true)
		add_child(vr_head_label)
		vr_head_label.visible = false
		vr_glove_label = UiKit.label3d("", 0.03 * WS, "gold", true)
		vr_glove_label.position = Vector3(0.0, 0.05, 0.06) * WS  # back of the hand, clear of the wrist MENU
		vr_glove_label.rotation = Vector3(-1.2, 0.0, 0.0)
		vr_rig.hand_l.add_child(vr_glove_label)
	session_seed = int(OS.get_environment("TS_SEED")) if OS.has_environment("TS_SEED") else Seeded.fresh_seed()
	_build_world()
	if mode != "host" or flat_host:  # every machine with a screen of its own (a flat host too)
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		group_cam = CameraRig.new()
		group_cam.camera = split.shared_camera()
		group_cam.group_min_distance = 11.0
		add_child(group_cam)
		group_cam.follow_group([], -35.0, 0.0, 0.0)
		_make_hud(-1, split.shared_hud())
		hints.add_view(huds[-1], -1)
		if vr_rig != null:
			split.set_bubble(vr_rig.mirror)
	party.allow_slot0 = (mode == "local" and vr_rig == null) or flat_host
	awards.set_player(0, "GIANT" if vr_rig != null or mode == "client" else party.name_of(0))
	if mode != "client":
		net.state_set("best", float(save.data["best"]))
		net.state_set("town", (save.data.town as Array).duplicate(true))
		save.data.sessions = int(save.data.sessions) + 1
		save.mark_dirty()
		print("Tower Stack town: %d towers (%d built in all), today's tower %s, session seed %d" % [
			(save.data.town as Array).size(), int(save.data.built),
			"done" if String(save.data.daily) == Seeded.today() else "due", session_seed])
		_start_round()
	hints.intro(INTRO, {"duration": 7.0})
	if vr_rig != null:
		_vr_say("TOWER STACK\nTRIGGER = GRAB", 5.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Tower Stack: %s mode%s" % [mode, " with a VR giant" if vr_rig != null else ""])


# --- World --------------------------------------------------------------------------------

func _build_world() -> void:
	SkyKit.apply(self, "day", vr_rig != null)
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = ARENA + 16.0
	disc.bottom_radius = ARENA + 16.0
	disc.height = 0.2
	disc.radial_segments = 32
	ground.mesh = disc
	ground.material_override = MeshKit.material(Color(0.45, 0.75, 0.38))
	ground.position.y = -0.1
	add_child(ground)
	ground_mi = ground
	var path := MeshInstance3D.new()
	var pdisc := CylinderMesh.new()
	pdisc.top_radius = ARENA
	pdisc.bottom_radius = ARENA
	pdisc.height = 0.02
	pdisc.radial_segments = 32
	path.mesh = pdisc
	path.material_override = MeshKit.material(Color(0.55, 0.82, 0.45))
	path.position.y = 0.005
	add_child(path)
	path_mi = path
	add_child(MeshKit.scatter_random(MeshKit.prop("tree"), 20, Vector3.ZERO, ARENA + 12.0, ARENA + 4.0, 0.9, 1.4, PackedColorArray(), 3))
	add_child(MeshKit.scatter_random(MeshKit.prop("flower"), 40, Vector3.ZERO, ARENA - 0.5, 2.5, 0.7, 1.1,
		PackedColorArray([Color(1.0, 0.5, 0.6), Color(1.0, 0.9, 0.4), Color(0.7, 0.6, 1.0)]), 5))
	# Physics floor + the tower stage (host / local only; the TV machine draws ghosts).
	# The stage: rocks gently on wobbly sites (host / local: an AnimatableBody3D carrying the blocks;
	# TV machines tilt a plain node from the snapshot).
	if net.mode != "client":
		var ab := AnimatableBody3D.new()
		ab.sync_to_physics = true
		var bs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = BASE_R
		cyl.height = BASE_H
		bs.shape = cyl
		bs.position.y = BASE_H * 0.5
		ab.add_child(bs)
		var spm := PhysicsMaterial.new()
		spm.friction = 1.0
		ab.physics_material_override = spm
		stage = ab
	else:
		stage = Node3D.new()
	stage.name = "Stage"
	add_child(stage)
	stage.add_child(MeshKit.instance(Looks.base_mesh(BASE_R, BASE_H)))
	ghost_root = Node3D.new()
	ghost_root.name = "Plan"
	stage.add_child(ghost_root)
	sock = MeshKit.instance(Looks.sock_mesh())
	sock.position = Vector3(-2.3, 0.0, -1.2)
	sock.visible = false
	add_child(sock)
	town = SkylineScript.new()
	add_child(town)
	wren = WrenScript.new()
	add_child(wren)
	var pad := MeshKit.instance(Looks.pad_mesh(PAD_R), false)
	pad.name = "Pad"
	pad.position = PAD
	add_child(pad)
	if net.mode != "client":
		var floor_body := StaticBody3D.new()
		var fs := CollisionShape3D.new()
		var fbox := BoxShape3D.new()
		fbox.size = Vector3(80.0, 1.0, 80.0)
		fs.shape = fbox
		fs.position.y = -0.5
		floor_body.add_child(fs)
		var pm := PhysicsMaterial.new()
		pm.friction = 1.0
		floor_body.physics_material_override = pm
		add_child(floor_body)
	ring = MeshKit.instance(Looks.ring_mesh(BASE_R + 0.35), false)
	add_child(ring)
	ring_label = UiKit.label3d("BEST", 0.35, "gold", true)
	if vr_rig == null:
		ring_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y  # TV only (VR text never billboards)
	add_child(ring_label)
	_place_ring(1.2)


## The gold hoop marks the job's goal height (Wren perches on it).
func _place_ring(y: float) -> void:
	if ring != null:
		ring.position = Vector3(0.0, y, 0.0)
		ring_label.position = Vector3(-BASE_R - 0.6, y + 0.3, 0.6)
		ring_label.text = "%.1f m" % y
	if wren != null:
		wren.perch(Vector3(-(BASE_R + 0.35), y + 0.04, 0.0))


## Every machine: show a job (from the "job" state): the plan ghosts, the hoop, wind sock, ground.
func _apply_site(s: Dictionary) -> void:
	site = s
	if s.is_empty():
		return
	_place_ring(float(s.top))
	for g in ghosts:
		g.queue_free()
	ghosts.clear()
	for b in s.plan:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = G.size_of(int(b[0])) * 1.02
		mi.mesh = bm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = MeshKit.material(Color(1.0, 1.0, 1.0, 0.18))
		mi.position = Vector3(float(b[1]), float(b[2]), float(b[3]))
		mi.rotation.y = PI * 0.5 * int(b[4])
		ghost_root.add_child(mi)
		ghosts.append(mi)
	_show_fill(int(net.state_get("fill", 0)))
	var windy := float(s.wind) > 0.0
	sock.visible = windy
	sock.rotation.y = -float(s.wind_dir)
	var cols: Array = G.GROUND_COLORS.get(String(s.ground), G.GROUND_COLORS["meadow"])
	if ground_mi != null:
		ground_mi.material_override = MeshKit.material(cols[0])
		path_mi.material_override = MeshKit.material(cols[1])
	if topper != null:
		topper.queue_free()
		topper = null


## Plan spots already holding the right block glow green; the rest stay a faint white outline.
func _show_fill(mask: int) -> void:
	for i in ghosts.size():
		var on := (mask >> i) & 1 == 1
		ghosts[i].material_override = MeshKit.material(Color(0.4, 1.0, 0.5, 0.28) if on else Color(1.0, 1.0, 1.0, 0.18))


## Wind direction as a flat vector (the sock points downwind).
func _wind_vec() -> Vector3:
	var a := float(site.get("wind_dir", 0.0))
	return Vector3(cos(a), 0.0, sin(a))


# --- HUD ----------------------------------------------------------------------------------

func _make_hud(slot: int, parent: Control) -> void:
	var ui := UiKit.ui_root(parent)
	huds[slot] = ui
	var card := UiKit.panel("card")
	ui.add_child(card)
	card.position = Vector2(24.0, 20.0)
	var v := UiKit.vbox()
	card.add_child(v)
	var row := UiKit.hbox()
	v.add_child(row)
	if slot >= 0:
		row.add_child(UiKit.badge(party.name_of(slot), slot))
	row.add_child(UiKit.icon("arrow_up", "gold", 34.0))
	var l := UiKit.label("0.0 m", "number")
	row.add_child(l)
	height_labels[slot] = l
	var row2 := UiKit.hbox()
	v.add_child(row2)
	row2.add_child(StoryCard.picture("tower", 40.0, Looks.COLORS[2]))
	var tl := UiKit.label("0", "number")
	row2.add_child(tl)
	built_labels[slot] = tl
	var bl := UiKit.label("", "small", "dim")
	v.add_child(bl)
	best_labels[slot] = bl
	timers[slot] = HudKit.timer(ui, {"seconds": float(net.state_get("time", round_time)), "warn": 15})
	if slot < 0:
		join_prompt = UiKit.panel("pill")
		join_prompt.add_child(UiKit.prompts([["A", "Join"]]))
		ui.add_child(join_prompt)
		UiKit.pin(join_prompt, Control.PRESET_CENTER_BOTTOM)
		join_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
		join_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
		join_prompt.offset_top = -60.0
		join_prompt.offset_bottom = -60.0
	_refresh_hud()


func _refresh_hud() -> void:
	var h := float(net.state_get("height", 0.0))
	var best := float(net.state_get("best", 0.0))
	for slot in height_labels:
		var l: Label = height_labels[slot]
		if is_instance_valid(l):
			l.text = "%.1f m" % h
		var bl: Label = best_labels.get(slot)
		if bl != null and is_instance_valid(bl):
			bl.text = "BEST %.1f m" % best
		var tl: Label = built_labels.get(slot)
		if tl != null and is_instance_valid(tl):
			tl.text = str(int(net.state_get("built", 0)))
	if join_prompt != null:
		join_prompt.visible = party.local_slots().is_empty()


func _all_huds() -> Array:
	var out: Array = []
	for k in huds:
		if is_instance_valid(huds[k]):
			out.append(huds[k])
	return out


## VR: one short world-locked headline (scaled for the giant), far from the eyes.
func _vr_say(text: String, secs: float) -> void:
	if vr_head_label == null:
		return
	vr_head_label.text = text
	vr_head_label.visible = true
	vr_head_t = secs
	VrText.snap(vr_head_label)
	VrText.follow(vr_head_label, vr_rig.camera, self, 0.25 * WS, 1.8 * WS)


func _update_vr_text(delta: float) -> void:
	if vr_rig == null:
		return
	if vr_head_label.visible:
		VrText.follow(vr_head_label, vr_rig.camera, self, 0.25 * WS, 1.8 * WS)
		if vr_head_t > 0.0:
			vr_head_t -= delta
			if vr_head_t <= 0.0:
				vr_head_label.visible = false
	var t := int(net.state_get("time", 0))
	vr_glove_label.text = "%d:%02d\n%.1f m" % [t / 60, t % 60, float(net.state_get("height", 0.0))]
	# The record sign turns (on Y only) to face the giant.
	var d := ring_label.global_position - vr_rig.camera.global_position
	ring_label.global_basis = Basis(Vector3.UP, atan2(-d.x, -d.z))


# --- Players ------------------------------------------------------------------------------

func _on_player_joined(slot: int, _device: int) -> void:
	var a := _ensure_avatar(slot)
	if party.is_local(slot) and split != null:
		var c := CameraRig.new()
		c.camera = split.camera(slot)
		c.party = party
		c.slot = slot
		c.pivot_height = 1.0
		c.pitch = -0.4
		add_child(c)
		c.follow(a, 7.0, 0.0)
		cams[slot] = c
		_make_hud(slot, split.hud(slot))
		hints.add_view(huds[slot], slot)
	awards.set_player(slot, party.name_of(slot))
	_refresh_group()
	_refresh_hud()
	sound("ui_notify", -6.0)


func _on_player_left(slot: int) -> void:
	for d in [avatars, cams]:
		var dict: Dictionary = d
		if dict.has(slot):
			(dict[slot] as Node).queue_free()
			dict.erase(slot)
	for d2 in [last_pos, vys, av_prev, av_vel, boop_cd, net_target]:
		(d2 as Dictionary).erase(slot)
	if huds.has(slot):
		var h: Control = huds[slot]
		if is_instance_valid(h):
			h.queue_free()
		huds.erase(slot)
	height_labels.erase(slot)
	best_labels.erase(slot)
	built_labels.erase(slot)
	timers.erase(slot)
	hints.remove_view(slot)
	_refresh_group()
	_refresh_hud()


func _ensure_avatar(slot: int) -> Node3D:
	if avatars.has(slot) and is_instance_valid(avatars[slot]):
		return avatars[slot]
	var a := Creatures.humanoid({"class": LOOKS[slot % LOOKS.size()], "outfit": party.color_of(slot), "seed": slot})
	a.name = "Avatar%d" % slot
	add_child(a)
	var ang := -1.2 - slot * 0.5
	a.position = Vector3(cos(ang), 0.0, sin(ang)) * 3.5
	HudKit.nameplate(a, party.name_of(slot), slot, Creatures.height_of(a) + 0.35, 0.18)
	avatars[slot] = a
	last_pos[slot] = a.position
	return a


func _refresh_group() -> void:
	if group_cam != null:
		group_cam.set_targets(avatars.values())


## Local TV players: run, jump (A), stand on blocks and the stage. Movement is instant on this
## machine; the host only hears where they are.
func _move_local_players(delta: float) -> void:
	send_t -= delta
	var send := send_t <= 0.0
	if send:
		send_t = 1.0 / 30.0
	var playing := String(net.state_get("phase", "play")) == "play"
	for slot in party.local_slots():
		if not avatars.has(slot):
			continue
		var a: Node3D = avatars[slot]
		var p := a.position
		var mv := party.stick(slot, "move") if playing else Vector2.ZERO
		if mv != Vector2.ZERO:
			var cam := split.active_camera(slot)
			var f := -cam.global_basis.z
			f.y = 0.0
			f = f.normalized()
			var r := Vector3(-f.z, 0.0, f.x)
			var dir := r * mv.x - f * mv.y
			p += dir * SPEED * delta
			Creatures.anim(a).face(dir)
		var flat := Vector2(p.x, p.z).limit_length(ARENA)
		p.x = flat.x
		p.z = flat.y
		p = _push_out(p)
		var vy: float = vys.get(slot, 0.0)
		var g := _ground_at(p)
		var on_ground := p.y <= g + 0.02 and vy <= 0.0
		if on_ground and playing and party.just_pressed(slot, "accept"):
			vy = JUMP
			Creatures.anim(a).play("jump")
			sfx.play_at("jump", p, -4.0, 1.0 + randf() * 0.15)
		vy -= GRAVITY * delta
		p.y += vy * delta
		if p.y <= g:
			if vy < -6.0:
				Creatures.anim(a).squash(0.25)
				sfx.play_at("land", p, -6.0)
			p.y = g
			vy = 0.0
		vys[slot] = vy
		a.position = p
		if net.mode == "client" and send:
			net.send_state(a.position, a.rotation.y, 0.0, slot)


## Highest floor under a player: the grass, the stage, or a block top no higher than a step up.
func _ground_at(p: Vector3) -> float:
	var g := 0.0
	if Vector2(p.x, p.z).length() < BASE_R + 0.1:
		g = BASE_H
	for id in blocks:
		if int(id) == held_id:
			continue
		var b: Node3D = blocks[id]
		var bp := b.global_position
		var e := _half(int(id))
		if absf(p.x - bp.x) < e.x + 0.15 and absf(p.z - bp.z) < e.z + 0.15:
			var top := bp.y + e.y
			if top <= p.y + STEP and top > g:
				g = top
	return g


## Players can't walk through blocks taller than a step: slide out along the shorter side.
func _push_out(p: Vector3) -> Vector3:
	for id in blocks:
		var b: Node3D = blocks[id]
		var bp := b.global_position
		var e := _half(int(id))
		if p.y >= bp.y + e.y - STEP or p.y + 1.0 < bp.y - e.y:
			continue
		var dx := p.x - bp.x
		var dz := p.z - bp.z
		var ox := e.x + BODY_R - absf(dx)
		var oz := e.z + BODY_R - absf(dz)
		if ox > 0.0 and oz > 0.0:
			if ox < oz:
				p.x += ox * (1.0 if dx >= 0.0 else -1.0)
			else:
				p.z += oz * (1.0 if dz >= 0.0 else -1.0)
	return p


## A block's half size along the world axes (its turn included).
func _half(id: int) -> Vector3:
	var b: Node3D = blocks.get(id)
	var h := G.size_of(int(bkind.get(id, 0))) * 0.5
	if b == null:
		return h
	var bas := b.global_basis.orthonormalized()
	return Vector3(
		h.x * absf(bas.x.x) + h.y * absf(bas.y.x) + h.z * absf(bas.z.x),
		h.x * absf(bas.x.y) + h.y * absf(bas.y.y) + h.z * absf(bas.z.y),
		h.x * absf(bas.x.z) + h.y * absf(bas.y.z) + h.z * absf(bas.z.z))


func _hop(slot: int) -> void:
	if avatars.has(slot):
		vys[slot] = 9.0
		Creatures.anim(avatars[slot]).play("jump")
		sfx.play_at("boing", (avatars[slot] as Node3D).position, -2.0, 1.2)


func _animate_avatars(delta: float) -> void:
	for slot in avatars:
		var a: Node3D = avatars[slot]
		var prev: Vector3 = last_pos.get(slot, a.position)
		var v := Vector2(a.position.x - prev.x, a.position.z - prev.z).length() / maxf(delta, 0.001)
		Creatures.anim(a).walk(v if v > 0.3 else 0.0)
		last_pos[slot] = a.position


## Host: a player on another machine moved.
func on_remote_state(slot: int, pos: Vector3, yaw: float, _pitch: float) -> void:
	if avatars.has(slot) and not party.is_local(slot):
		if not net_target.has(slot):
			(avatars[slot] as Node3D).position = pos  # first update: no glide in from the spawn point
		net_target[slot] = [pos, yaw]


## Every machine: other machines' players glide to where their machine (or the host) says they are.
func _follow_remote(delta: float) -> void:
	var k := 1.0 - exp(-18.0 * delta)
	for slot in net_target:
		if not avatars.has(slot) or party.is_local(slot):
			continue
		var a: Node3D = avatars[slot]
		var t: Array = net_target[slot]
		a.position = a.position.lerp(t[0], k)
		a.rotation.y = lerp_angle(a.rotation.y, float(t[1]), k)


## Host: one machine left. core/party.gd frees just its seats (player_left for each removes their
## avatars, views and per-player state); only that machine's leftovers are dropped here.
func on_machine_left(peer: int) -> void:
	for slot in party.slots_of(peer):
		net_target.erase(slot)


## TV machine: the giant as seen from here (only when the host has a VR player), plus the window into their view.
func _make_vr_avatar() -> void:
	vr_avatar = VrRig.Avatar.new()
	vr_avatar.process_priority = -10  # poses first, then _process scales the giant up
	add_child(vr_avatar)
	if split != null:
		split.set_bubble(VrRig.build_mirror(self, vr_avatar.head, false))


func on_request(_slot: int, action: String, _args: Array) -> void:
	if action == "next_round" and results_showing() and results_t > 2.0:
		_start_round()


func on_pause_changed(paused: bool, by_slot: int) -> void:
	if vr_rig != null:
		if paused:
			_vr_say("PAUSED", 0.0)
			vr_head_label.process_mode = Node.PROCESS_MODE_ALWAYS
		elif vr_head_label.text == "PAUSED":
			vr_head_label.visible = false
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
			UiKit.pin(tv_banner, Control.PRESET_CENTER)
			tv_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
			tv_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
		(tv_banner.find_child("Why", true, false) as Label).text = "by %s" % party.name_of(by_slot)
		tv_banner.visible = paused
		if paused:
			UiKit.pop_in(tv_banner)


func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"height":
			_refresh_hud()
		"best", "built":
			_refresh_hud()
		"job":
			_apply_site(G.from_job(value) if value is Array else {})
		"fill":
			_show_fill(int(value))
		"town":
			town.set_entries(value if value is Array else [])
		"time":
			for slot in timers:
				var t: HudKit.TimerPill = timers[slot]
				if is_instance_valid(t):
					t.set_time(float(value))
		"round":
			pass  # (each job's story card says what to build)
		"new_record":
			if int(value) > 0:
				HudKit.banner(_all_huds(), "NEW RECORD!", "", {"style": "victory", "duration": 2.2})
				_vr_say("NEW RECORD!", 2.5)
				sound("fanfare", -2.0)
		"phase":
			if String(value) == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()


# --- Rounds -------------------------------------------------------------------------------

func _start_round() -> void:
	for id in blocks.keys():
		_remove_block(int(id))
	hover = [-1, -1, -1]
	held_id = -1
	crane_id = -1
	crane_state = "idle"
	awards.reset()
	time_left = round_time
	spawn_t = 2.5
	tower_h = 0.0
	peak = 0.0
	job_n = 0
	built_round = 0
	round_jobs = []
	round_wobbles = 0
	net.state_set("built", 0)
	net.state_set("height", 0.0)
	net.state_set("rec", 0.0)
	net.state_set("new_record", 0)
	net.state_set("time", int(ceil(time_left)))
	net.state_set("phase", "play")
	net.state_set("round", int(net.state_get("round", 0)) + 1)
	if vr_rig != null:
		vr_rig.recenter()
		vr_rig.guard_trigger()
	_next_job()
	_spawn_block(PAD + Vector3(0.0, 6.0, 0.0))  # the first block bounces up for the giant (or the crane)


## Host: Wren asks for the next building (job n of this round; job DAILY_N is TODAY'S TOWER once a day).
func _next_job() -> void:
	job_n += 1
	var daily := job_n == G.DAILY_N and String(save.data.daily) != Seeded.today()
	var built := int(save.data.built)
	var seed_value := G.daily_seed() if daily else G.job_seed(session_seed, int(net.state_get("round", 1)), job_n)
	var s := G.site(seed_value, G.DAILY_LEVEL if daily else G.level(job_n, built), daily)
	set_i = 0
	stable_t = 0.0
	done_t = -1.0
	job_t = 0.0
	fill = 0
	net.state_set("fill", 0)
	net.state_set("job", G.job_of(s))  # every machine rebuilds it (_apply_site)
	print("Tower Stack job %d: %s level %d, %d blocks to %.2f m, wind %.2f, sway %.3f, seed %d%s" % [job_n, s.building,
		int(s.level), (s.plan as Array).size(), float(s.top), float(s.wind), float(s.sway), seed_value, " (TODAY'S TOWER)" if daily else ""])
	var beats: Array = []
	if job_n == 1 and int(net.state_get("round", 1)) == 1:
		beats.append(["Hi! I'm Wren!" if built == 0 else "Let's build!", "wren", WREN_COLOR])
	if daily:
		beats.append(["TODAY'S TOWER!", "tower", Color(1.0, 0.8, 0.2)])
	beats.append([String(s.name) + "!", "tower", Looks.COLORS[int(s.palette[0])]])
	if float(s.wind) > 0.0:
		beats.append(["Windy!", "cloud", Color(0.6, 0.8, 1.0)])
	if float(s.sway) > 0.0:
		beats.append(["Wobbly jelly!", "wave", Color(0.4, 0.9, 1.0)])
	for i in beats.size():
		var b: Array = beats[i]
		get_tree().create_timer(0.3 + 2.6 * i).timeout.connect(func() -> void:
			if is_inside_tree():
				story(b[0], b[1], b[2]))


## A story beat: a picture and a few words on every view; VR: the giant's headline. Host broadcasts.
func story(line: String, pic: String = "wren", color: Color = WREN_COLOR, broadcast: bool = true) -> void:
	StoryCard.show(_all_huds(), {"who": "WREN" if pic == "wren" else "", "line": line, "pic": pic, "color": color, "duration": 2.8})
	_vr_say(line, 2.4)
	if broadcast and net.mode == "host":
		net.event("story", [line, pic, color])


## Host: the tower reached the hoop and held: roof on, Wren cheers, it joins the town, next job.
func _tower_built() -> void:
	done_t = 0.0
	var perfect := fill == (1 << (site.plan as Array).size()) - 1
	built_round += 1
	total_built += 1
	net.state_set("built", built_round)
	round_jobs.append([int(site.level), snappedf(job_t, 0.1), perfect, bool(site.daily)])
	save.data.built = int(save.data.built) + 1
	var list: Array = save.data.town
	list.append(G.job_of(site))
	while list.size() > G.TOWN_KEEP:
		list.pop_front()
	if site.daily:
		save.data.daily = Seeded.today()
	save.mark_dirty()
	for id in blocks:  # the finished tower holds still while it shows off
		if String(bstate.get(id, "")) == "free" and _in_tower_zone((blocks[id] as Node3D).global_position):
			bstate[id] = "done"
			(blocks[id] as RigidBody3D).freeze = true
	awards.add(0, "built")
	print("Tower built: %s in %.1f s%s (%d this round, %d in all)" % [site.building, job_t, " PERFECT" if perfect else "", built_round, int(save.data.built)])
	built_fx(Vector3(top_xz.x, tower_h, top_xz.y), perfect)


## Every machine: roof pops on, Wren hops up, fanfare.
func built_fx(top: Vector3, perfect: bool) -> void:
	if site.is_empty():
		return
	if topper != null:
		topper.queue_free()
	topper = MeshKit.instance(Looks.topper_mesh(String(site.building), Looks.COLORS[int(site.palette[0])], bool(site.daily)))
	topper.position = top
	add_child(topper)
	topper.scale = Vector3.ONE * 0.01
	create_tween().tween_property(topper, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	wren.visit(top + Vector3(0.25, 0.0, 0.25), CHEER - 0.5)
	sound("fanfare", -3.0)
	sfx.play_at("ding", top, 0.0, 1.2)
	HudKit.banner(_all_huds(), "PERFECT!" if perfect else "BUILT!", "", {"style": "victory", "duration": 2.0, "sound": ""})
	_vr_say("PERFECT!" if perfect else "BUILT!", 2.0)
	for slot in avatars:
		Creatures.anim(avatars[slot]).play("cheer", 1.0)
	if net.mode != "client":
		net.event("built", [top, perfect])


## Host: the finished tower flies off to the town (its blocks go), and Wren asks for the next one.
func _tower_to_town() -> void:
	for id in blocks.keys():
		if String(bstate.get(id, "")) == "done":
			sfx.play_at("pop", (blocks[id] as Node3D).global_position, -8.0, 1.0 + randf() * 0.3)
			_remove_block(int(id))
	net.state_set("town", (save.data.town as Array).duplicate(true))
	peak = 0.0
	tower_h = 0.0
	var count := int(save.data.built)
	if TOWN_CHEERS.has(count):
		story(TOWN_CHEERS[count], "house", Looks.COLORS[int(site.palette[0])])
	_next_job()


func _end_round() -> void:
	if held_id >= 0:
		_release_held()
	var rec := float(net.state_get("rec", 0.0))
	var best := float(net.state_get("best", 0.0))
	var data := awards.results({"title": "%d TOWER%s!" % [built_round, "" if built_round == 1 else "S"] if built_round > 0 else "TOWER %.1f m!" % rec,
		"subtitle": "NEW RECORD!" if int(net.state_get("new_record", 0)) > 0 else "Best ever %.1f m" % best,
		"style": "victory", "stats": [["TOWERS", str(built_round)], ["TALLEST", "%.1f m" % rec], ["TOWN", str((save.data.town as Array).size())]],
		"score_format": "%d BLOCKS", "continue": "Play again"})
	_log_round("time")
	net.state_set("results", data)
	net.state_set("phase", "results")
	results_t = 0.0


func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
	sound("cheer", -4.0)
	if split != null:
		split.set_shared(true)
		var screen := Awards.results_screen(huds[-1], data, {"party": party})
		screen.continued.connect(func() -> void:
			var seats := party.local_slots()
			net.request(seats[0] if not seats.is_empty() else 0, "next_round"))
		results_ui = screen
	if vr_rig != null:
		_vr_say(String(data.get("title", "")), 0.0)


func _hide_results() -> void:
	if results_ui != null and is_instance_valid(results_ui):
		results_ui.queue_free()
	results_ui = null
	if vr_head_label != null and vr_head_t <= 0.0 and vr_head_label.text.begins_with("TOWER"):
		vr_head_label.visible = false
	if split != null:
		split.set_shared(false)


func results_showing() -> bool:
	return String(net.state_get("phase", "")) == "results"


# --- Game loop ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	clock += delta
	session_t += delta
	if split != null:
		_move_local_players(delta)
	_follow_remote(delta)
	_animate_avatars(delta)
	_update_vr_text(delta)
	if vr_avatar != null:
		vr_avatar.head.scale = Vector3.ONE * WS
		for g in vr_avatar.hands:
			(g as Node3D).scale = Vector3.ONE * WS
	if net.mode == "client":
		_follow_ghosts(delta)
		return
	_track_avatar_speed(delta)
	if results_showing():
		results_t += delta
		if vr_rig != null and results_t > 2.5 and (vr_rig.trigger_pressed() or vr_rig.a_pressed()):
			_start_round()
		elif results_t > 12.0:
			_start_round()  # automatic play again
		return
	time_left -= delta
	job_t += delta
	if done_t >= 0.0:
		done_t += delta
		if done_t >= CHEER:
			done_t = -1.0
			_tower_to_town()
	if int(ceil(time_left)) != int(net.state_get("time", 0)):
		net.state_set("time", maxi(0, int(ceil(time_left))))
	if time_left <= 0.0:
		_end_round()
		return
	spawn_t -= delta
	if spawn_t <= 0.0:
		spawn_t = G.SPAWN_SECS
		_maybe_spawn()
	# Helpers busy or stuck? Wren drops the block the plan needs next straight onto the pad.
	pad_idle_t = pad_idle_t + delta if hover.has(-1) and done_t < 0.0 else 0.0
	if pad_idle_t > G.PAD_HELP and blocks.size() < MAX_BLOCKS:
		pad_idle_t = 0.0
		_spawn_block(PAD + Vector3(0.0, 6.0, 0.0), _needed_kind())
	height_t -= delta
	if height_t <= 0.0:
		height_t = 0.2
		_measure_tower()


func _physics_process(delta: float) -> void:
	if not ready_to_play or net.mode == "client":
		return
	for id in poke_cd.keys():
		poke_cd[id] = float(poke_cd[id]) - delta
	if vr_rig != null:
		_vr_hands()
	elif not results_showing():
		_run_crane(delta)
	_update_hover(delta)
	_weather(delta)
	_push_blocks()
	_check_pad()
	_cleanup()


# --- Blocks -------------------------------------------------------------------------------

func _make_block_node(id: int, authority: bool, kind: int = 0, ci: int = 0) -> Node3D:
	kind = clampi(kind, 0, G.KINDS.size() - 1)
	bkind[id] = kind
	bcolor[id] = ci
	var n: Node3D
	if authority:
		var rb := RigidBody3D.new()
		rb.mass = G.MASS[kind]
		rb.linear_damp = 0.3
		rb.angular_damp = 1.5
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.physics_material_override = ResCache.get_or_make("tower_stack_block_pm_v1", func() -> Resource:
			var pm := PhysicsMaterial.new()
			pm.friction = 1.0
			pm.bounce = 0.05
			return pm)
		var cs := CollisionShape3D.new()
		cs.shape = ResCache.get_or_make("tower_stack_block_shape_v2_%d" % kind, func() -> Resource:
			var box := BoxShape3D.new()
			box.size = G.size_of(kind)
			return box)
		rb.add_child(cs)
		n = rb
	else:
		n = Node3D.new()
	n.name = "Block%d" % id
	var jelly := Node3D.new()
	jelly.set_script(JellyScript)
	jelly.name = "Jelly"
	jelly.set("on_bump", _on_bump.bind(id))
	n.add_child(jelly)
	var mi := MeshKit.instance(Looks.block_mesh(kind, ci))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	jelly.add_child(mi)
	add_child(n)
	blocks[id] = n
	return n


func _on_bump(pos: Vector3, k: float, id: int) -> void:
	sfx.play_at("bounce", pos, -14.0 + k * 10.0, 0.8 + 0.08 * float(posmod(id, 6)))


func _poke(id: int, amount: float) -> void:
	var b: Node3D = blocks.get(id)
	if b != null:
		var j := b.get_node_or_null("Jelly")
		if j != null:
			j.call("poke", amount)


## Host: drop the job's next block (then spares: cubes) at pos.
func _spawn_block(pos: Vector3, kind: int = -1) -> void:
	next_id += 1
	var set: Array = site.get("set", [])
	if kind < 0:
		kind = int(set[set_i]) if set_i < set.size() else G.K_CUBE
		set_i += 1
	var pal: Array = site.get("palette", [0, 1, 2])
	var rb := _make_block_node(next_id, true, kind, int(pal[next_id % pal.size()])) as RigidBody3D
	rb.global_position = pos
	rb.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	rb.angular_velocity = Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))
	bstate[next_id] = "free"
	sfx.play_at("whoosh", pos, -10.0, 1.3)


func _remove_block(id: int) -> void:
	var b: Node3D = blocks.get(id)
	if b != null:
		b.queue_free()
	blocks.erase(id)
	bstate.erase(id)
	hover_t.erase(id)
	hover_from.erase(id)
	pusher.erase(id)
	placed.erase(id)
	poke_cd.erase(id)
	ghost_t.erase(id)
	bkind.erase(id)
	bcolor.erase(id)
	var hi := hover.find(id)
	if hi >= 0:
		hover[hi] = -1
	if held_id == id:
		held_id = -1
	if crane_id == id:
		crane_id = -1


## The kind of block the lowest empty plan spot wants (a cube when the plan is full).
func _needed_kind() -> int:
	var plan: Array = site.get("plan", [])
	for i in plan.size():
		if (fill >> i) & 1 == 0:
			return int(plan[i][0])
	return G.K_CUBE


## Drop a new block: onto the pad when nobody is on the TV, else into the field for the TV players.
func _maybe_spawn() -> void:
	if blocks.size() >= MAX_BLOCKS:
		return
	var loose := 0
	for id in blocks:
		if String(bstate.get(id, "")) == "free" and not _in_tower_zone((blocks[id] as Node3D).global_position):
			loose += 1
	if loose >= MAX_LOOSE:
		return
	if party.player_count() == 0:
		if hover.has(-1):
			_spawn_block(PAD + Vector3(randf_range(-0.3, 0.3), 6.0, randf_range(-0.3, 0.3)))
		return
	for attempt in 12:
		var ang := randf() * TAU
		var p := Vector3(cos(ang), 0.0, sin(ang)) * randf_range(3.5, 7.5)
		if p.distance_to(PAD) < 3.0 or (p.z > 0.5 and absf(p.x) < 2.5):
			continue
		_spawn_block(p + Vector3.UP * 7.0)
		return


func _in_tower_zone(p: Vector3) -> bool:
	return Vector2(p.x, p.z).length() < BASE_R + 0.2


## How tall is the tower? The highest resting block over the stage.
func _measure_tower() -> void:
	var h := 0.0
	var xz := Vector2.ZERO
	for id in blocks:
		if not String(bstate.get(id, "")) in ["free", "done"]:
			continue
		var rb: RigidBody3D = blocks[id]
		var p := rb.global_position
		if not _in_tower_zone(p) or rb.linear_velocity.length() > 0.6:
			continue
		var top := p.y + _half(int(id)).y
		if top > h:
			h = top
			xz = Vector2(p.x, p.z)
	tower_h = h
	top_xz = xz
	max_height = maxf(max_height, h)
	_measure_job()
	var shown := snappedf(h, 0.1)
	if absf(shown - float(net.state_get("height", 0.0))) > 0.05:
		net.state_set("height", shown)
	var rec := float(net.state_get("rec", 0.0))
	if shown > rec:
		net.state_set("rec", shown)
		var best := float(net.state_get("best", 0.0))
		if shown > best:
			if best >= 1.0 and int(net.state_get("new_record", 0)) == 0:
				net.state_set("new_record", int(net.state_get("round", 1)))
			net.state_set("best", shown)
			save.data["best"] = shown
			save.mark_dirty()
	# A big drop = the tower fell over: make it funny, not sad.
	wobble_cd -= 0.2
	if done_t >= 0.0:
		peak = h
		return
	if h >= peak:
		peak = h
		peak_t = 0.0
	else:
		peak_t += 0.2
		if peak_t > 3.0:
			peak = h
	if peak - h >= 1.0 and wobble_cd <= 0.0:
		wobble_cd = 5.0
		peak = h
		round_wobbles += 1
		wobble(Vector3(0.0, maxf(h, 1.0), 0.0))


## Host, 5 times a second: which plan spots hold a matching block, and is the tower at the hoop?
func _measure_job() -> void:
	if site.is_empty() or done_t >= 0.0:
		return
	var plan: Array = site.plan
	var mask := 0
	for i in plan.size():
		if _spot_block(plan[i]) >= 0:
			mask |= 1 << i
	if mask != fill:
		fill = mask
		net.state_set("fill", mask)
	if tower_h >= float(site.top) - 0.12:
		stable_t += 0.2
		if stable_t >= 1.0:
			_tower_built()
	else:
		stable_t = 0.0


## The resting block of the right kind sitting in plan spot b ([kind, x, y, z, rot]), or -1.
func _spot_block(b: Array) -> int:
	var at := stage.global_transform * Vector3(float(b[1]), float(b[2]), float(b[3]))
	for id in blocks:
		if String(bstate.get(id, "")) != "free" or int(bkind.get(id, -1)) != int(b[0]):
			continue
		var rb: RigidBody3D = blocks[id]
		var p := rb.global_position
		if Vector2(p.x - at.x, p.z - at.z).length() > 0.2 or absf(p.y - at.y) > 0.2 or rb.linear_velocity.length() > 0.6:
			continue
		if int(b[0]) == G.K_PLANK:  # a plank must lie along the plan's line
			var ax := rb.global_basis.x
			var want := Vector3.RIGHT if int(b[4]) == 0 else Vector3.BACK
			if absf(Vector3(ax.x, 0.0, ax.z).normalized().dot(want)) < 0.85:
				continue
		return int(id)
	return -1


## Host: wind gusts push the tower's blocks; the jelly stage rocks (both capped by towergen.gd).
func _weather(_delta: float) -> void:
	if site.is_empty():
		return
	var sway := float(site.sway)
	if sway > 0.0 and stage is AnimatableBody3D:
		var w := TAU / maxf(1.0, float(site.sway_period))
		var a := clock * w * 0.3
		tilt = Vector2(cos(a), sin(a)) * sway * sin(clock * w)
		stage.rotation = Vector3(tilt.y, 0.0, -tilt.x)
	elif tilt != Vector2.ZERO:
		tilt = Vector2.ZERO
		stage.rotation = Vector3.ZERO
	var wind := float(site.wind)
	if wind <= 0.0 or results_showing():
		return
	var gust := 0.7 + 0.3 * sin(clock * 1.1) * sin(clock * 0.37 + 1.0)
	var f := _wind_vec() * wind * gust
	for id in blocks:
		if String(bstate.get(id, "")) != "free":
			continue
		var rb: RigidBody3D = blocks[id]
		if rb.freeze or not _in_tower_zone(rb.global_position) or rb.global_position.y < BASE_H + 0.25:
			continue
		rb.apply_central_force(f * rb.mass)


## The tower fell: boing, crash, shake (every machine).
func wobble(pos: Vector3) -> void:
	sfx.play_at("crash", pos, -6.0, 1.3)
	sound("boing", 0.0, 0.8)
	HudKit.banner(_all_huds(), "WOBBLE!", "Keep going!", {"duration": 1.8, "sound": ""})
	_vr_say("WOBBLE!", 1.8)
	if wren != null:
		wren.flutter()
	for slot in cams:
		(cams[slot] as CameraRig).shake(0.35)
	for slot in avatars:
		Creatures.anim(avatars[slot]).play("jump")
	if net.mode != "client":
		net.event("wobble", [pos])


## Authority: TV players push loose blocks they walk into (not the tower itself).
func _push_blocks() -> void:
	for slot in avatars:
		var a: Node3D = avatars[slot]
		var v: Vector3 = av_vel.get(slot, Vector3.ZERO)
		var sp := Vector2(v.x, v.z).length()
		if sp < 0.6:
			continue
		var dir := Vector3(v.x, 0.0, v.z) / sp
		for id in blocks:
			if String(bstate.get(id, "")) != "free":
				continue
			var rb: RigidBody3D = blocks[id]
			var bp := rb.global_position
			if _in_tower_zone(bp) or a.position.y >= bp.y + H - STEP or a.position.y + 1.0 < bp.y - H:
				continue
			var d := Vector3(bp.x - a.position.x, 0.0, bp.z - a.position.z)
			if absf(d.x) > H + BODY_R + 0.15 or absf(d.z) > H + BODY_R + 0.15 or d.dot(dir) <= 0.0:
				continue
			var lv := rb.linear_velocity
			var push := dir * maxf(sp + 0.3, 2.5) * (0.6 if int(bkind.get(id, 0)) == G.K_STONE else 1.0)
			if Vector2(lv.x, lv.z).length() < push.length():
				rb.linear_velocity = Vector3(push.x, maxf(lv.y, 0.6), push.z)
				rb.sleeping = false
				if int(pusher.get(id, -1)) != int(slot):
					_poke(int(id), 0.3)
				pusher[id] = slot


func _track_avatar_speed(delta: float) -> void:
	for slot in avatars:
		var p: Vector3 = (avatars[slot] as Node3D).position
		var prev: Vector3 = av_prev.get(slot, p)
		var inst := (p - prev) / maxf(delta, 0.001)
		var v: Vector3 = av_vel.get(slot, Vector3.ZERO)
		av_vel[slot] = v.lerp(inst, 0.35)
		av_prev[slot] = p


## Authority: a loose block on the pad boings up to the giant (or the crane).
func _check_pad() -> void:
	for id in blocks:
		if String(bstate.get(id, "")) != "free":
			continue
		var rb: RigidBody3D = blocks[id]
		var p := rb.global_position
		var to_pad := Vector2(PAD.x - p.x, PAD.z - p.z)
		if p.y < 1.0 and to_pad.length() < PAD_R + 1.6 and to_pad.length() >= PAD_R and not _in_tower_zone(p):
			# The pad's magnet: blocks nudged close enough glide in by themselves.
			var pull := to_pad.normalized() * 2.2
			var lv := rb.linear_velocity
			if Vector2(lv.x, lv.z).dot(to_pad.normalized()) < 2.0:
				rb.linear_velocity = Vector3(lerpf(lv.x, pull.x, 0.1), lv.y, lerpf(lv.z, pull.y, 0.1))
				rb.sleeping = false
		if p.y > 1.0 or to_pad.length() > PAD_R:
			continue
		var slot_i := hover.find(-1)
		if slot_i < 0:
			return
		hover[slot_i] = int(id)
		bstate[id] = "hover"
		rb.freeze = true
		hover_t[id] = 0.0
		hover_from[id] = p
		var by := int(pusher.get(id, -1))
		total_delivered += 1
		pad_idle_t = 0.0
		if by >= 0:  # (pushers are avatars: TV players, or a flat host's slot 0)
			awards.add(by, "score")
			awards.add(by, "delivered")
		boing(p, by)


## The pad's boing (every machine).
func boing(pos: Vector3, by: int) -> void:
	sfx.play_at("boing", pos, 0.0, 1.0 + randf() * 0.2)
	var pad := get_node_or_null("Pad") as Node3D
	if pad != null:
		var tw := create_tween()
		pad.scale = Vector3(1.15, 0.5, 1.15)
		tw.tween_property(pad, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if by >= 0:
		HudKit.score(self, pos + Vector3.UP * 0.8, 1, {"color": party.color_of(by), "size": 1.4})
		if avatars.has(by):
			Creatures.anim(avatars[by]).play("cheer", 0.8)
	if net.mode != "client":
		net.event("boing", [pos, by])


## Hovering blocks fly up from the pad with a bounce, then bob, waiting for the giant.
func _update_hover(delta: float) -> void:
	for i in hover.size():
		var id := hover[i]
		if id < 0 or not blocks.has(id):
			continue
		var rb: RigidBody3D = blocks[id]
		var t: float = float(hover_t.get(id, 0.0)) + delta
		hover_t[id] = t
		var from: Vector3 = hover_from.get(id, rb.global_position)
		var k := clampf(t / 0.6, 0.0, 1.0)
		var e := 1.0 + 2.2 * pow(k - 1.0, 3.0) + 1.2 * pow(k - 1.0, 2.0)  # ease-out-back
		var goal := HOVER[i] + Vector3.UP * sin(clock * 2.0 + i) * 0.06
		var pos := from.lerp(goal, e)
		pos.y += sin(k * PI) * 0.8
		rb.global_transform = Transform3D(Basis(Vector3.UP, clock * 0.6 + i), pos)


func _cleanup() -> void:
	for id in blocks.keys():
		var p: Vector3 = (blocks[id] as Node3D).global_position
		var flat := Vector2(p.x, p.z)
		if flat.length() > ARENA - 0.5 and p.y < 2.0 and String(bstate.get(id, "")) == "free":
			# The park's edge bounces blocks back in, so the TV players can always reach them.
			var rb: RigidBody3D = blocks[id]
			var inward := -flat.normalized() * 2.5
			if Vector2(rb.linear_velocity.x, rb.linear_velocity.z).dot(inward) < 2.0:
				rb.linear_velocity = Vector3(inward.x, maxf(rb.linear_velocity.y, 1.5), inward.y)
				rb.sleeping = false
		if p.y < -3.0 or Vector2(p.x, p.z).length() > ARENA + 5.0:
			_remove_block(int(id))


# --- The VR giant's hands ------------------------------------------------------------------

func _vr_hands() -> void:
	var playing := not results_showing()
	if held_id >= 0:
		if not blocks.has(held_id):
			held_id = -1
		elif not vr_rig.trigger_down():
			_release_held()
		else:
			var rb: RigidBody3D = blocks[held_id]
			rb.global_transform = vr_rig.hand_r.global_transform * held_off
	elif playing and vr_rig.trigger_pressed():
		var hp := vr_rig.hand_point(VrRig.RIGHT)
		var best := -1
		var bd := GRAB_R
		for id in blocks:
			if String(bstate.get(id, "")) == "crane":
				continue
			var d := (blocks[id] as Node3D).global_position.distance_to(hp)
			if d < bd:
				bd = d
				best = int(id)
		if best >= 0:
			_grab(best)
		else:
			vr_rig.pulse(VrRig.RIGHT, 0.15, 0.03)
	# Touching anything makes it react: blocks wobble and get knocked, TV players get booped.
	for w in 2:
		if w == VrRig.RIGHT and held_id >= 0:
			continue
		var hp := vr_rig.hand_point(w)
		var hv := vr_rig.hand_velocity(w)
		for id in blocks:
			if float(poke_cd.get(id, 0.0)) > 0.0:
				continue
			var b: Node3D = blocks[id]
			if b.global_position.distance_to(hp) > H + 0.2:
				continue
			poke_cd[id] = 0.3
			_poke(int(id), clampf(hv.length() * 0.2, 0.2, 0.8))
			vr_rig.pulse(w, 0.25, 0.04)
			if String(bstate.get(id, "")) == "free" and hv.length() > 0.8:
				var rb: RigidBody3D = b
				rb.sleeping = false
				rb.apply_central_impulse(hv.limit_length(6.0) * 0.35)
		_touch_scenery(w, hp)
		if hv.length() > 1.2:
			for slot in avatars:
				var a: Node3D = avatars[slot]
				if float(boop_cd.get(slot, 0.0)) > clock:
					continue
				if (a.position + Vector3.UP * 0.6).distance_to(hp) < 0.6:
					boop_cd[slot] = clock + 1.0
					vr_rig.pulse(w, 0.5, 0.08)
					if party.is_local(slot):
						_hop(int(slot))
					else:
						net.event("boop", [slot])
						sfx.play_at("boing", a.position, -2.0, 1.2)


## The pad boings and the record hoop rings when the giant touches them.
func _touch_scenery(w: int, hp: Vector3) -> void:
	if float(touch_cd.get("pad", 0.0)) < clock and hp.y < 0.5 and Vector2(hp.x - PAD.x, hp.z - PAD.z).length() < PAD_R:
		touch_cd["pad"] = clock + 0.6
		vr_rig.pulse(w, 0.4, 0.06)
		boing(PAD, -1)
	var rr := Vector2(hp.x, hp.z).length()
	if float(touch_cd.get("ring", 0.0)) < clock and absf(hp.y - ring.position.y) < 0.25 and absf(rr - (BASE_R + 0.35)) < 0.3:
		touch_cd["ring"] = clock + 0.5
		vr_rig.pulse(w, 0.3, 0.05)
		sfx.play_at("ding", hp, -4.0, 1.0 + randf() * 0.3)
		var tw := create_tween()
		ring.scale = Vector3(1.08, 1.0, 1.08)
		tw.tween_property(ring, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _grab(id: int) -> void:
	var rb: RigidBody3D = blocks[id]
	var hi := hover.find(id)
	if hi >= 0:
		hover[hi] = -1
	held_id = id
	bstate[id] = "held"
	rb.freeze = true
	held_off = vr_rig.hand_r.global_transform.affine_inverse() * rb.global_transform
	vr_rig.pulse(VrRig.RIGHT, 0.5, 0.06)
	_poke(id, 0.5)
	sfx.play_at("pop", rb.global_position, -4.0, 1.2)


func _release_held() -> void:
	var id := held_id
	held_id = -1
	if not blocks.has(id):
		return
	var rb: RigidBody3D = blocks[id]
	var v := vr_rig.hand_velocity(VrRig.RIGHT)
	_let_go(id)
	var gentle := v.length() < 1.5 or (_in_tower_zone(rb.global_position) and v.length() < 3.5)
	if gentle:
		# A gentle place: stand it up straight (keep its turn) so towers are buildable.
		var f := rb.global_basis.z
		rb.global_basis = Basis(Vector3.UP, atan2(f.x, f.z))
		rb.linear_velocity = v * 0.1
		_snap_to_plan(id)
	else:
		rb.linear_velocity = v.limit_length(9.0)  # a throw
	vr_rig.pulse(VrRig.RIGHT, 0.3, 0.04)
	if _in_tower_zone(rb.global_position) and not placed.has(id):
		placed[id] = true
		total_placed += 1
		awards.add(0, "score")
		awards.add(0, "placed")


## A gentle place near an empty plan spot for this block snaps onto it (lined up, a tiny drop).
func _snap_to_plan(id: int) -> void:
	if site.is_empty():
		return
	var rb: RigidBody3D = blocks[id]
	var plan: Array = site.plan
	for i in plan.size():
		var b: Array = plan[i]
		if (fill >> i) & 1 == 1 or int(b[0]) != int(bkind.get(id, -1)):
			continue
		var at := Vector3(float(b[1]), float(b[2]), float(b[3]))
		var p := rb.global_position
		if Vector2(p.x - at.x, p.z - at.z).length() < SNAP_R and p.y > at.y - 0.15 and p.y < at.y + 0.45:
			rb.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5 * int(b[4])), Vector3(at.x, maxf(p.y, at.y + 0.03), at.z))
			_poke(id, 0.4)
			return


func _let_go(id: int) -> void:
	var rb: RigidBody3D = blocks[id]
	bstate[id] = "free"
	rb.freeze = false
	rb.angular_velocity = Vector3.ZERO
	rb.sleeping = false
	pusher.erase(id)


# --- The helper crane (only when nobody is in VR) -----------------------------------------------

func _run_crane(delta: float) -> void:
	if crane == null:
		crane = _make_crane()
		crane.position = CRANE_HOME
	var target := CRANE_HOME
	match crane_state:
		"idle":
			crane_wait -= delta
			if crane_wait <= 0.0:
				for i in hover.size():
					var hid := hover[i]
					if hid >= 0 and float(hover_t.get(hid, 0.0)) > 0.8:
						crane_id = hid
						crane_state = "pick"
						break
		"pick":
			if not blocks.has(crane_id) or String(bstate.get(crane_id, "")) != "hover":
				crane_state = "idle"
			else:
				target = (blocks[crane_id] as Node3D).global_position + Vector3.UP * 0.55
				if crane.position.distance_to(target) < 0.1:
					var hi := hover.find(crane_id)
					if hi >= 0:  # (hover[-1] would clear the wrong spot)
						hover[hi] = -1
					bstate[crane_id] = "crane"
					_poke(crane_id, 0.4)
					sfx.play_at("pop", target, -4.0)
					var spot := _crane_spot(crane_id)
					if spot.is_empty():
						var off := Vector2(randf_range(-0.14, 0.14), randf_range(-0.14, 0.14))
						var xz := top_xz if tower_h > 0.3 else Vector2.ZERO
						crane_goal = Vector3(xz.x + off.x, -1.0, xz.y + off.y)
						crane_yaw = randf_range(-0.2, 0.2)
					else:
						crane_goal = Vector3(float(spot[1]), float(spot[2]), float(spot[3]))
						crane_yaw = PI * 0.5 * int(spot[4])
					crane_state = "carry"
		"carry", "lower":
			if not blocks.has(crane_id):
				crane_state = "up"
			else:
				var hi := maxf(tower_h, BASE_H) + _half(crane_id).y + 0.62
				if crane_goal.y > 0.0:  # a plan spot: lower it right into place
					hi = crane_goal.y + 0.04 + 0.62
				if crane_state == "carry":
					target = Vector3(crane_goal.x, maxf(hi + 1.2, 4.0), crane_goal.z)
					if crane.position.distance_to(target) < 0.05:
						crane_state = "lower"
				else:
					target = Vector3(crane_goal.x, hi, crane_goal.z)
					if crane.position.distance_to(target) < 0.05:
						var rb: RigidBody3D = blocks[crane_id]
						_let_go(crane_id)
						rb.global_basis = Basis(Vector3.UP, crane_yaw)
						rb.linear_velocity = Vector3.ZERO
						crane_id = -1
						crane_state = "up"
						crane_wait = 1.0
		"up":
			if crane.position.distance_to(CRANE_HOME) < 0.05:
				crane_state = "idle"
	crane.position = crane.position.move_toward(target, 3.5 * delta)
	if crane_id >= 0 and blocks.has(crane_id) and String(bstate.get(crane_id, "")) == "crane":
		var rb2: RigidBody3D = blocks[crane_id]
		var yaw := crane_yaw if crane_state in ["carry", "lower"] else 0.0
		rb2.global_transform = Transform3D(Basis(Vector3.UP, yaw + sin(clock * 3.0) * 0.04), crane.position - Vector3.UP * 0.62)


## The plan spot the crane fills with this block: the lowest empty spot, if it takes this kind
## (otherwise [] and the block goes on top).
func _crane_spot(id: int) -> Array:
	if site.is_empty():
		return []
	var plan: Array = site.plan
	for i in plan.size():
		if (fill >> i) & 1 == 0:
			return plan[i] if int(plan[i][0]) == int(bkind.get(id, -1)) else []
	return []


func _make_crane() -> Node3D:
	var c := Node3D.new()
	c.name = "Crane"
	c.add_child(MeshKit.instance(Looks.claw_mesh(), false))
	var cable := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 20.0, 0.06)
	cable.mesh = bm
	cable.material_override = MeshKit.material(Color(0.25, 0.25, 0.3))
	cable.position.y = 10.3
	c.add_child(cable)
	add_child(c)
	return c


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play(sound_name, volume_db, pitch)


# --- Networking ---------------------------------------------------------------------------

## Host, 30 Hz: the VR pose, every block's transform, the crane.
func make_snapshot() -> Array:
	var ids := PackedInt32Array()
	var xf := PackedFloat32Array()
	for id in blocks:
		var t: Transform3D = (blocks[id] as Node3D).global_transform
		var q := t.basis.get_rotation_quaternion()
		ids.append(int(id))
		xf.append_array([t.origin.x, t.origin.y, t.origin.z, q.x, q.y, q.z, q.w])
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	var cr := PackedFloat32Array()
	if crane != null:
		cr.append_array([crane.position.x, crane.position.y, crane.position.z])
	# Every player avatar (slot, position, yaw): each machine sees the other machines' players.
	var av_slots := PackedByteArray()
	var av_pos := PackedVector3Array()
	var av_yaw := PackedFloat32Array()
	for slot in avatars:
		var a: Node3D = avatars[slot]
		av_slots.append(int(slot))
		av_pos.append(a.position)
		av_yaw.append(a.rotation.y)
	# Each block's look: kind * 8 + colour (same order as ids); the stage's tilt.
	var looks := PackedByteArray()
	for id in blocks:
		looks.append(int(bkind.get(id, 0)) * 8 + int(bcolor.get(id, 0)))
	return [pose, ids, xf, cr, av_slots, av_pos, av_yaw, looks, tilt]


## TV machine: mirror the host's world (ghost blocks glide to their targets).
func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 7:
		return
	var pose: PackedFloat32Array = s[0]
	if pose.size() > 0 and vr_avatar == null:
		_make_vr_avatar()
	if vr_avatar != null:
		vr_avatar.apply_pose(pose)
	var av_slots: PackedByteArray = s[4]
	var av_pos: PackedVector3Array = s[5]
	var av_yaw: PackedFloat32Array = s[6]
	for i in av_slots.size():
		var slot: int = av_slots[i]
		if avatars.has(slot) and not party.is_local(slot):
			if not net_target.has(slot):
				(avatars[slot] as Node3D).position = av_pos[i]
			net_target[slot] = [av_pos[i], av_yaw[i]]
	var ids: PackedInt32Array = s[1]
	var xf: PackedFloat32Array = s[2]
	var looks: PackedByteArray = s[7] if s.size() > 8 and s[7] is PackedByteArray else PackedByteArray()
	if s.size() > 8 and s[8] is Vector2:
		tilt = s[8]
		stage.rotation = Vector3(tilt.y, 0.0, -tilt.x)
	var seen := {}
	for i in ids.size():
		var id := ids[i]
		seen[id] = true
		var o := i * 7
		var t := Transform3D(Basis(Quaternion(xf[o + 3], xf[o + 4], xf[o + 5], xf[o + 6]).normalized()), Vector3(xf[o], xf[o + 1], xf[o + 2]))
		if not blocks.has(id):
			var lk: int = looks[i] if i < looks.size() else 0
			_make_block_node(id, false, lk / 8, lk % 8).global_transform = t
		ghost_t[id] = t
	for id in blocks.keys():
		if not seen.has(id):
			_remove_block(int(id))
	var cr: PackedFloat32Array = s[3]
	if cr.size() >= 3:
		if crane == null:
			crane = _make_crane()
			crane.position = Vector3(cr[0], cr[1], cr[2])
		crane.position = crane.position.lerp(Vector3(cr[0], cr[1], cr[2]), 0.5)


func _follow_ghosts(delta: float) -> void:
	var k := 1.0 - exp(-18.0 * delta)
	for id in ghost_t:
		if blocks.has(id):
			var b: Node3D = blocks[id]
			b.global_transform = b.global_transform.interpolate_with(ghost_t[id], k)


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"boing":
			boing(args[0], int(args[1]))
		"wobble":
			wobble(args[0])
		"boop":
			if party.is_local(int(args[0])):
				_hop(int(args[0]))
		"built":
			built_fx(args[0], bool(args[1]))
		"story":
			story(String(args[0]), String(args[1]), args[2], false)
