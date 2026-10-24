extends Node3D
## SHEEP ROUND-UP: fluffy sheep wander a green field; get them all into the pen before the clock runs out.
## TV players are sheepdogs: run near sheep to push them (A = WOOF, scares them further).
## The VR player is the giant farmer: grab a sheep with the right trigger and drop it in the pen;
## any low hand shoos sheep away, touching sheep / dogs / the fence makes them bounce.
## Each round won adds a few more sheep. Results show by themselves, then the next round starts.
## Built on the shared engine (see games/engine_template/): party seats, split view, camera rigs,
## VR rig, state store + snapshots, hud_kit / hints / awards / creatures / mesh_kit / sky_kit.

const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const Party := preload("res://core/party.gd")
const SplitView := preload("res://core/split_view.gd")
const VrRig := preload("res://core/vr_rig.gd")
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
const SheepScript := preload("res://games/sheep_round_up/sheep.gd")

const GAME_ID := "sheep_round_up"
const ARENA := 8.0  # field radius
const PEN := 1.6  # pen half size (square at the centre)
const GAP := 0.75  # half width of the four gates
const DOG_SPEED := 4.8
const FLEE_SPEED := 3.0
const SCARE_R := 2.4
const BARK_R := 4.5
const FIRST_SHEEP := 5
const MORE_SHEEP := 3
const MAX_SHEEP := 20
const INTRO := {
	"title": "SHEEP ROUND-UP",
	"goal": "Get the sheep in the pen!",
	"vr": {"role": "THE FARMER", "controls": [["TRIGGER", "Grab a sheep"], ["L-STICK", "Walk"]]},
	"tv": {"role": "THE SHEEPDOGS", "controls": [["L-STICK", "Run"], ["A", "Woof!"]]},
}

var round_time := 120.0  ## seconds per round (bots shorten it)
var results_wait := 9.0  ## seconds the results stay up before the next round starts by itself

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
var sky: SkyKit.SkyRig

var dogs := {}  # slot -> Node3D (Creatures dog): TV players, every machine
var last_pos := {}  # slot -> Vector3, for walk animation
var bark_t := {}  # slot -> seconds left of a bark's big scare (host / local)
var bark_cd := {}  # slot -> cooldown (host / local)
var cams := {}  # slot -> CameraRig
var group_cam: CameraRig
var huds := {}  # slot -> UiKit root (-1 = shared view)
var count_labels := {}  # slot -> Label
var timers := {}  # slot -> HudKit.TimerPill
var join_prompt: Control
var vr_avatar: VrRig.Avatar
var vr_label: Label3D  # host: "3/5  1:20" on the back of the left glove
var vr_banner: Node3D
var tv_banner: Control
var results_ui: Control
var vr_results: Node
var sign_label: Label3D  # big "3 / 5" over the pen (world-locked, every machine)
var fence: Node3D
var ring: MeshInstance3D  # VR: glows under the sheep the right hand can grab
var sheep: Array = []  # of SheepScript nodes; index = id in snapshots
var held := -1  # host: index of the sheep in the right glove
var send_t := 0.0
var time_left := 0.0
var results_t := 0.0
var fence_cd := 0.0
var dog_touch_cd := 0.0
var clock := 0.0


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
	sfx.add_recipe("baa", {"len": 0.6, "peak": 0.55, "jit": 0.08, "layers": [
		{"w": "saw", "f": 340.0, "f1": 290.0, "len": 0.55, "atk": 0.03, "rel": 0.2, "vib": [8.0, 0.9], "lp": 2000.0, "vol": 0.8},
		{"w": "square", "f": 680.0, "f1": 590.0, "len": 0.5, "atk": 0.03, "rel": 0.2, "vib": [8.0, 0.9], "lp": 1500.0, "vol": 0.25}]})
	sfx.add_recipe("woof", {"len": 0.3, "peak": 0.7, "jit": 0.05, "layers": [
		{"w": "saw", "f": 480.0, "f1": 170.0, "len": 0.2, "atk": 0.005, "dec": 9.0, "lp": 1300.0, "vol": 0.9},
		{"w": "noise", "len": 0.09, "dec": 20.0, "lp": 1000.0, "vol": 0.35}]})
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("town")
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


func _setup(mode: String) -> void:
	flat_host = mode == "host" and not net.has_vr
	if VrRig.wanted(mode) and not flat_host:
		vr_rig = VrRig.new()
		vr_rig.bounds = Rect2(-ARENA, -ARENA, ARENA * 2.0, ARENA * 2.0)
		vr_rig.move_speed = 2.5
		add_child(vr_rig)
		vr_rig.place(Vector3(0.0, 0.0, PEN + 0.7), 0.0)  # just south of the pen, facing it
		vr_label = UiKit.label3d("", 0.035, "gold", true)
		vr_label.position = Vector3(0.0, 0.05, 0.06)  # back of the hand, clear of the wrist MENU
		vr_label.rotation = Vector3(-1.2, 0.0, 0.0)
		vr_rig.hand_l.add_child(vr_label)
		hints.set_vr_rig(vr_rig, self)
	_build_world(vr_rig != null)
	if mode != "host" or flat_host:  # every machine with a screen of its own (a flat host too)
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		group_cam = CameraRig.new()
		group_cam.camera = split.shared_camera()
		group_cam.group_min_distance = 11.0
		add_child(group_cam)
		group_cam.follow_group([], -55.0, 0.0, 0.0)
		_make_hud(-1, split.shared_hud())
		hints.add_view(huds[-1], -1)
		if vr_rig != null:
			split.set_bubble(vr_rig.mirror)
	party.allow_slot0 = (mode == "local" and vr_rig == null) or flat_host
	awards.set_player(0, "FARMER" if vr_rig != null or mode == "client" else party.name_of(0))
	if mode != "client":
		net.state_set("best", int(save.data["best"]))
		net.state_set("flock", FIRST_SHEEP)
		_start_round()
	hints.intro(INTRO, {"duration": 7.0})
	if vr_rig != null:
		hints.hint("vr_grab", "Grab a sheep with the TRIGGER!", {"to": "vr"})
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Sheep Round-Up: %s mode%s" % [mode, " with a VR player" if vr_rig != null else ""])


# --- World --------------------------------------------------------------------------------

func _build_world(vr: bool) -> void:
	sky = SkyKit.apply(self, "day", vr)
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = ARENA + 16.0
	disc.bottom_radius = ARENA + 16.0
	disc.height = 0.2
	disc.radial_segments = 32
	ground.mesh = disc
	ground.material_override = MeshKit.material(Color(0.46, 0.78, 0.34))
	ground.position.y = -0.1
	add_child(ground)
	add_child(MeshKit.scatter_random(MeshKit.prop("tree"), 20, Vector3.ZERO, ARENA + 12.0, ARENA + 2.5, 0.9, 1.4, PackedColorArray(), 3))
	add_child(MeshKit.scatter_random(MeshKit.prop("bush"), 18, Vector3.ZERO, ARENA + 2.2, ARENA + 0.6, 0.8, 1.2, PackedColorArray(), 4))
	add_child(MeshKit.scatter_random(MeshKit.prop("flower"), 50, Vector3.ZERO, ARENA - 0.3, PEN + 1.0, 0.7, 1.1,
		PackedColorArray([Color(1.0, 0.5, 0.6), Color(1.0, 0.9, 0.4), Color(0.75, 0.6, 1.0), Color(1.0, 1.0, 1.0)]), 5))
	# The pen: straw floor, a wooden fence with a gate in each side, glowing arrows into the gates.
	var b := MeshKit.Builder.new()
	b.box(Vector3(PEN * 2.0, 0.03, PEN * 2.0), MeshKit.at(Vector3(0.0, 0.015, 0.0)), Color(0.95, 0.8, 0.42))
	var wood := Color(0.62, 0.4, 0.22)
	for side in 4:
		var rot := Basis(Vector3.UP, side * PI * 0.5)
		for seg in [-1.0, 1.0]:
			var s: float = seg
			var a := rot * Vector3(s * GAP, 0.0, PEN)
			var c := rot * Vector3(s * PEN, 0.0, PEN)
			for h in [0.22, 0.45]:
				var y: float = h
				b.tube(a + Vector3.UP * y, c + Vector3.UP * y, 0.04, 0.04, wood)
			b.box(Vector3(0.12, 0.62, 0.12), MeshKit.at(a + Vector3.UP * 0.31), wood.darkened(0.15))
			b.box(Vector3(0.12, 0.62, 0.12), MeshKit.at(c + Vector3.UP * 0.31), wood.darkened(0.15))
		for k in 3:
			b.sphere(0.06 + k * 0.015, MeshKit.at(rot * Vector3(0.0, 0.08, PEN + 1.3 - k * 0.4)), Color(1.0, 0.85, 0.2), 8, true)
	# Sign post on the north fence.
	b.box(Vector3(0.12, 1.5, 0.12), MeshKit.at(Vector3(0.0, 0.75, -PEN - 0.3)), wood.darkened(0.2))
	b.rounded_box(Vector3(1.3, 0.6, 0.08), 0.06, MeshKit.at(Vector3(0.0, 1.6, -PEN - 0.3)), Color(0.75, 0.52, 0.3))
	fence = MeshKit.instance(b.build())
	add_child(fence)
	sign_label = UiKit.label3d("0 / 0", 0.42, "text", true)
	sign_label.outline_size = 26
	sign_label.position = Vector3(0.0, 1.6, -PEN - 0.24)  # reads from +Z: towards the farmer's start
	fence.add_child(sign_label)
	if vr:
		ring = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.3
		tm.outer_radius = 0.38
		tm.rings = 16
		tm.ring_segments = 6
		ring.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = Color(1.0, 0.9, 0.2)
		ring.material_override = rm
		ring.visible = false
		add_child(ring)
	sfx.play_loop("birds", -16.0)


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
	var l := UiKit.label("SHEEP 0/0", "number")
	row.add_child(l)
	count_labels[slot] = l
	timers[slot] = HudKit.timer(ui, {"seconds": float(net.state_get("time", round_time))})
	if slot < 0:
		join_prompt = UiKit.panel("pill")
		join_prompt.add_child(UiKit.prompts([["A", "Join the game"]]))
		ui.add_child(join_prompt)
		UiKit.pin(join_prompt, Control.PRESET_CENTER_BOTTOM)
		join_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
		join_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
		join_prompt.offset_top = -60.0
		join_prompt.offset_bottom = -60.0
	_refresh_hud()


func _refresh_hud() -> void:
	var home := int(net.state_get("home", 0))
	var total := int(net.state_get("total", 0))
	for slot in count_labels:
		var l: Label = count_labels[slot]
		if is_instance_valid(l):
			l.text = "SHEEP %d/%d" % [home, total]
	if join_prompt != null:
		join_prompt.visible = party.local_slots().is_empty()
	if sign_label != null:
		sign_label.text = "%d / %d" % [home, total]
		sign_label.modulate = Color(0.5, 1.0, 0.45) if total > 0 and home >= total else Color(1.0, 1.0, 1.0)
	if vr_label != null:
		vr_label.text = "%d/%d   %s" % [home, total, HudKit.clock_text(float(net.state_get("time", 0)))]


func _all_huds() -> Array:
	var out: Array = []
	for k in huds:
		if is_instance_valid(huds[k]):
			out.append(huds[k])
	return out


# --- Players (sheepdogs) --------------------------------------------------------------------

func _on_player_joined(slot: int, _device: int) -> void:
	var d := _ensure_dog(slot)
	if party.is_local(slot) and split != null:
		var c := CameraRig.new()
		c.camera = split.camera(slot)
		c.party = party
		c.slot = slot
		c.pivot_height = 0.6
		c.pitch = -0.55
		add_child(c)
		c.follow(d, 5.5, 0.0)
		cams[slot] = c
		_make_hud(slot, split.hud(slot))
		hints.add_view(huds[slot], slot)
		hints.hint("herd", "Run behind the sheep!", {"to": slot, "button": "A"})
	awards.set_player(slot, party.name_of(slot))
	_refresh_group()
	_refresh_hud()
	sound("woof", -4.0)


func _on_player_left(slot: int) -> void:
	for dd in [dogs, cams]:
		var dict: Dictionary = dd
		if dict.has(slot):
			(dict[slot] as Node).queue_free()
			dict.erase(slot)
	last_pos.erase(slot)
	net_target.erase(slot)
	bark_t.erase(slot)
	bark_cd.erase(slot)
	if huds.has(slot):
		var h: Control = huds[slot]
		if is_instance_valid(h):
			h.queue_free()
		huds.erase(slot)
	count_labels.erase(slot)
	timers.erase(slot)
	hints.remove_view(slot)
	_refresh_group()
	_refresh_hud()


func _ensure_dog(slot: int) -> Node3D:
	if dogs.has(slot) and is_instance_valid(dogs[slot]):
		return dogs[slot]
	var col := party.color_of(slot)
	var d := Creatures.monster("dog", {"color": col.lerp(Color(0.95, 0.85, 0.7), 0.35), "scale": 1.1, "seed": slot})
	d.name = "Dog%d" % slot
	add_child(d)
	var a := slot * 1.3
	d.position = Vector3(sin(a), 0.0, cos(a)) * (PEN + 3.0)
	HudKit.nameplate(d, party.name_of(slot), slot, Creatures.height_of(d) + 0.3, 0.16)
	dogs[slot] = d
	last_pos[slot] = d.position
	return d


func _refresh_group() -> void:
	if group_cam != null:
		var t: Array = dogs.values()
		if t.is_empty():
			t = sheep.duplicate()
		group_cam.set_targets(t)


## Local dogs run with the left stick relative to their camera; A barks. The TV machine moves its
## own dogs instantly and sends where they are to the host.
func _move_local_players(delta: float) -> void:
	send_t -= delta
	var send := send_t <= 0.0
	if send:
		send_t = 1.0 / 30.0
	var playing := String(net.state_get("phase", "play")) == "play"
	for slot in party.local_slots():
		if not dogs.has(slot):
			continue
		var d: Node3D = dogs[slot]
		var mv := party.stick(slot, "move") if playing else Vector2.ZERO
		if mv != Vector2.ZERO:
			var cam := split.active_camera(slot)
			var f := -cam.global_basis.z
			f.y = 0.0
			f = f.normalized()
			var r := Vector3(-f.z, 0.0, f.x)
			var dir := r * mv.x - f * mv.y
			var p := d.position + dir * DOG_SPEED * delta
			p.y = 0.0
			d.position = p.limit_length(ARENA)
			Creatures.anim(d).face(dir)
		if net.mode == "client" and send:
			net.send_state(d.position, d.rotation.y, 0.0, slot)
		if playing and party.just_pressed(slot, "accept") and not net.just_unpaused():
			net.request(slot, "bark")


func _animate_dogs(delta: float) -> void:
	for slot in dogs:
		var d: Node3D = dogs[slot]
		var prev: Vector3 = last_pos.get(slot, d.position)
		var v := Vector2(d.position.x - prev.x, d.position.z - prev.z).length() / maxf(delta, 0.001)
		Creatures.anim(d).walk(v if v > 0.3 else 0.0)
		last_pos[slot] = d.position


## Host: a player on another machine moved.
func on_remote_state(slot: int, pos: Vector3, yaw: float, _pitch: float) -> void:
	if dogs.has(slot) and not party.is_local(slot):
		if not net_target.has(slot):
			(dogs[slot] as Node3D).position = pos  # first update: no glide in from the spawn point
		net_target[slot] = [pos, yaw]


## Every machine: other machines' players glide to where their machine (or the host) says they are.
func _follow_remote(delta: float) -> void:
	var k := 1.0 - exp(-18.0 * delta)
	for slot in net_target:
		if not dogs.has(slot) or party.is_local(slot):
			continue
		var a: Node3D = dogs[slot]
		var t: Array = net_target[slot]
		a.position = a.position.lerp(t[0], k)
		a.rotation.y = lerp_angle(a.rotation.y, float(t[1]), k)


## Host: one machine left. core/party.gd frees just its seats (player_left for each removes their
## avatars, views and per-player state); only that machine's leftovers are dropped here.
func on_machine_left(peer: int) -> void:
	for slot in party.slots_of(peer):
		net_target.erase(slot)


## TV machine: the VR player as seen from here (only when the host has one), plus the little window into their view.
func _make_vr_avatar() -> void:
	vr_avatar = VrRig.Avatar.new()
	add_child(vr_avatar)
	if split != null:
		split.set_bubble(VrRig.build_mirror(self, vr_avatar.head, false))


func on_request(slot: int, action: String, _args: Array) -> void:
	match action:
		"bark":
			if float(bark_cd.get(slot, 0.0)) <= 0.0 and dogs.has(slot):
				bark_cd[slot] = 0.7
				bark_t[slot] = 0.5
				bark_fx(slot)
		"next_round":
			if results_showing():
				_start_round()


## Every machine: a dog barks (sound, hop, a puff of rings). The host sends it as an event.
func bark_fx(slot: int) -> void:
	if not dogs.has(slot):
		return
	var d: Node3D = dogs[slot]
	sfx.play_at("woof", d.position + Vector3.UP * 0.5, 2.0, 0.9 + randf() * 0.25)
	Creatures.anim(d).play("jump", 0.4)
	HudKit.popup(self, d.position + Vector3.UP * 1.2, "WOOF!", {"color": party.color_of(slot), "size": 1.1})
	if party.is_local(slot):
		party.rumble(slot, 0.3, 0.0, 0.12)
	net.event("bark", [slot])


func on_pause_changed(paused: bool, by_slot: int) -> void:
	var why := "%s  -  %s" % [party.name_of(by_slot), "wrist MENU: carry on" if vr_rig != null else "Start: menu"]
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
			UiKit.pin(tv_banner, Control.PRESET_CENTER)
			tv_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
			tv_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
		(tv_banner.find_child("Why", true, false) as Label).text = why
		tv_banner.visible = paused
		if paused:
			UiKit.pop_in(tv_banner)


func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"home", "total", "best":
			_refresh_hud()
		"time":
			for slot in timers:
				var t: HudKit.TimerPill = timers[slot]
				if is_instance_valid(t):
					t.set_time(float(value))
			_refresh_hud()
		"round":
			var sub := "%d sheep!" % int(net.state_get("total", 0))
			HudKit.banner(_all_huds(), "ROUND %d" % int(value), sub, {"duration": 2.2})
			if vr_rig != null:
				HudKit.vr_banner(self, vr_rig.camera, "ROUND %d" % int(value), sub, {"duration": 2.2, "sound": ""})
			sound("whistle", -4.0)
		"phase":
			if String(value) == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()


# --- Rounds -------------------------------------------------------------------------------

func _start_round() -> void:
	_clear_sheep()
	held = -1
	awards.reset()
	var n := int(net.state_get("flock", FIRST_SHEEP))
	for i in n:
		var p: Vector3
		if i < 2:
			# the first two start close to a gate: an easy first catch for everyone
			var side := Basis(Vector3.UP, (i * 2 + 1) * PI * 0.5)
			p = side * Vector3(randf_range(-0.4, 0.4), 0.0, PEN + 1.4)
		else:
			var a := randf() * TAU
			p = Vector3(cos(a), 0.0, sin(a)) * randf_range(PEN + 2.0, ARENA - 1.0)
		_make_sheep(p)
	time_left = round_time
	net.state_set("total", n)
	net.state_set("home", 0)
	net.state_set("time", int(ceil(time_left)))
	net.state_set("phase", "play")
	net.state_set("round", int(net.state_get("round", 0)) + 1)
	_refresh_group()


func _end_round(all_home: bool) -> void:
	var home := int(net.state_get("home", 0))
	var total := int(net.state_get("total", 0))
	var rnd := int(net.state_get("round", 1))
	if all_home:
		net.state_set("flock", mini(total + MORE_SHEEP, MAX_SHEEP))
		if rnd > int(save.data["best"]):
			save.data["best"] = rnd
			save.mark_dirty()
			net.state_set("best", rnd)
	var data := awards.results({"title": "ALL HOME!" if all_home else "TIME'S UP!",
		"subtitle": "%d of %d sheep home" % [home, total], "style": "victory",
		"stats": [["ROUND", str(rnd)], ["BEST", str(int(net.state_get("best", 0)))]], "score_format": "%d SHEEP"})
	net.state_set("results", data)
	net.state_set("phase", "results")
	results_t = 0.0
	if all_home:
		celebrate()


## Every machine: confetti over the pen when the whole flock is home.
func celebrate() -> void:
	for k in 3:
		burst(Vector3(randf_range(-1.0, 1.0), 1.2 + k * 0.4, randf_range(-1.0, 1.0)), Color.from_hsv(randf(), 0.7, 1.0), 26)
	sfx.play("party_horn")
	net.event("celebrate", [])


func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
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


# --- Sheep ---------------------------------------------------------------------------------

func _make_sheep(pos: Vector3) -> Node3D:
	var s: Node3D = SheepScript.new()
	s.position = pos
	add_child(s)
	sheep.append(s)
	return s


func _clear_sheep() -> void:
	for s in sheep:
		(s as Node).queue_free()
	sheep.clear()


static func in_pen(p: Vector3, margin: float = 0.0) -> bool:
	return absf(p.x) < PEN - margin and absf(p.z) < PEN - margin


## A walking sheep outside the pen may only get in through a gate.
static func fence_block(from: Vector3, to: Vector3) -> Vector3:
	if not in_pen(to) or in_pen(from):
		return to
	var r := to
	if absf(from.x) >= PEN and absf(from.z) < PEN:
		if absf(to.z) > GAP:
			r.x = signf(from.x) * PEN
	elif absf(from.z) >= PEN and absf(from.x) < PEN:
		if absf(to.x) > GAP:
			r.z = signf(from.z) * PEN
	else:
		r = from
	return r


func _sim_sheep(delta: float) -> void:
	var hands: Array[Vector3] = []
	if vr_rig != null:
		var lp := vr_rig.hand_point(VrRig.LEFT)  # the left glove shoos; the right one grabs
		if lp.y < 0.7:
			hands.append(lp)
	for i in sheep.size():
		var s: Node3D = sheep[i]
		match int(s.get("state")):
			SheepScript.HELD:
				if vr_rig != null:
					s.position = vr_rig.hand_point(VrRig.RIGHT) + Vector3(0.0, -0.32, 0.0)
				continue
			SheepScript.FLY:
				_fly(s, delta)
				continue
		var penned: bool = s.get("penned")
		var vel: Vector3 = s.get("vel")
		var want := Vector3.ZERO
		var scared := false
		if not penned:
			var push := Vector3.ZERO
			var herder := -1  # the dog pushing hardest towards the pen gets the credit
			var herd_best := 0.0
			var to_pen := -Vector3(s.position.x, 0.0, s.position.z).normalized()
			for slot in dogs:
				var dp: Vector3 = (dogs[slot] as Node3D).position
				var r := BARK_R if float(bark_t.get(slot, 0.0)) > 0.0 else SCARE_R
				var away := s.position - dp
				away.y = 0.0
				var dd := away.length()
				if dd < r and dd > 0.001:
					var f := away / dd * (1.0 - dd / r) * (2.0 if r > SCARE_R else 1.0)
					push += f
					# A dog waiting in the pen scares sheep away from it: never its point (kids, 2026-10-24)
					var toward := f.dot(to_pen)
					if toward > herd_best and not in_pen(dp):
						herd_best = toward
						herder = int(slot)
			if herder >= 0:
				s.set("last_by", herder)
			for hp in hands:
				var away := s.position - hp
				away.y = 0.0
				var dd := away.length()
				if dd < 0.9 and dd > 0.001:
					push += away / dd * (1.0 - dd / 0.9) * 1.5
					s.set("last_by", 0)
			if push.length() > 0.05:
				scared = true
				want = push.normalized() * FLEE_SPEED * clampf(push.length() * 1.6, 0.5, 1.4)
		if not scared:
			var wt: float = float(s.get("wander_t")) - delta
			if wt <= 0.0:
				wt = randf_range(1.5, 4.0)
				var a := randf() * TAU
				s.set("wander_dir", Vector3(cos(a), 0.0, sin(a)) * (0.5 if randf() < 0.6 else 0.0))
			s.set("wander_t", wt)
			want = s.get("wander_dir")
		# keep apart from the others
		for j in sheep.size():
			if j == i:
				continue
			var o: Node3D = sheep[j]
			var dv := s.position - o.position
			dv.y = 0.0
			var dl := dv.length()
			if dl < 0.55 and dl > 0.001:
				want += dv / dl * (0.55 - dl) * 4.0
		vel = vel.lerp(want, 1.0 - exp(-(8.0 if scared else 3.0) * delta))
		var to := s.position + vel * delta
		to.y = 0.0
		if penned:
			var m := PEN - 0.3
			to.x = clampf(to.x, -m, m)
			to.z = clampf(to.z, -m, m)
		else:
			to = fence_block(s.position, to)
			if to.length() > ARENA - 0.3:
				to = to.limit_length(ARENA - 0.3)
				vel = -vel * 0.3
		s.position = to
		s.set("vel", vel)
		if not penned and in_pen(to, 0.3):
			_pen_sheep(i)
	_vr_hands()


func _fly(s: Node3D, delta: float) -> void:
	var vel: Vector3 = s.get("vel")
	vel.y -= 9.8 * delta
	var p := s.position + vel * delta
	if Vector2(p.x, p.z).length() > ARENA - 0.3:
		var flat := Vector2(p.x, p.z).limit_length(ARENA - 0.3)
		p.x = flat.x
		p.z = flat.y
		vel.x *= -0.4
		vel.z *= -0.4
	if p.y <= 0.0:
		p.y = 0.0
		if vel.y < -2.0:
			vel = Vector3(vel.x * 0.6, -vel.y * 0.4, vel.z * 0.6)
			sheep_fx(p, "boing")
		else:
			vel = Vector3.ZERO
			s.set("state", SheepScript.WALK)
			var i := sheep.find(s)
			if in_pen(p):
				var m := PEN - 0.3
				p.x = clampf(p.x, -m, m)
				p.z = clampf(p.z, -m, m)
				s.position = p
				if not bool(s.get("penned")):
					_pen_sheep(i)
				return
			sheep_fx(p, "baa")
	s.position = p
	s.set("vel", vel)


func _pen_sheep(i: int) -> void:
	var s: Node3D = sheep[i]
	s.set("penned", true)
	var by: int = s.get("last_by")
	if results_showing():
		sheep_fx(s.position, "baa")
		return
	if by >= 0:
		awards.add(by, "score")
	var home := 0
	for o in sheep:
		if bool((o as Node).get("penned")):
			home += 1
	net.state_set("home", home)
	sheep_fx(s.position, "home", by)
	if home >= sheep.size():
		_end_round(true)


## Every machine: a sheep sound + bounce at `pos` ("baa", "boing", "home" = got into the pen).
func sheep_fx(pos: Vector3, kind: String, by: int = -1) -> void:
	var s := _sheep_near(pos)
	match kind:
		"baa":
			sfx.play_at("baa", pos, 0.0, randf_range(0.9, 1.25))
			if s != null:
				s.call("boing", 0.8)
		"boing":
			sfx.play_at("boing", pos, -4.0, randf_range(0.9, 1.2))
			if s != null:
				s.call("boing", 1.0)
		"home":
			sfx.play_at("baa", pos, 2.0, 1.3)
			sfx.play("ding", -2.0, 1.0 + 0.05 * float(net.state_get("home", 0)))
			burst(pos + Vector3.UP * 0.4, Color(1.0, 0.9, 0.3), 18)
			HudKit.score(self, pos + Vector3.UP * 0.7, 1, {"color": party.color_of(by) if by >= 0 else "gold", "size": 1.4})
			if s != null:
				s.call("boing", 1.0)
			if by >= 0 and dogs.has(by):
				Creatures.anim(dogs[by]).play("cheer", 0.6)
	net.event("sheep", [pos, kind, by])


func _sheep_near(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := 0.8
	for o in sheep:
		var n: Node3D = o
		var d := n.position.distance_to(Vector3(pos.x, n.position.y, pos.z))
		if d < bd:
			bd = d
			best = n
	return best


# --- The farmer's hands (host / local with VR) -------------------------------------------------

func _vr_hands() -> void:
	if vr_rig == null:
		return
	var hp := vr_rig.hand_point(VrRig.RIGHT)
	var playing := not results_showing()
	# What the right glove could grab: the nearest free sheep under it.
	var near := -1
	var nd := 1.4
	for i in sheep.size():
		var s: Node3D = sheep[i]
		if int(s.get("state")) == SheepScript.HELD:
			continue
		var d := Vector2(s.position.x - hp.x, s.position.z - hp.z).length()
		if d < nd and hp.y - s.position.y < 1.1:
			nd = d
			near = i
	var can := near >= 0 and nd < 0.55 and hp.y - (sheep[near] as Node3D).position.y < 0.9
	if ring != null:
		ring.visible = held < 0 and near >= 0 and playing
		if ring.visible:
			var s: Node3D = sheep[near]
			ring.position = Vector3(s.position.x, 0.04, s.position.z)
			var k := 1.0 + 0.12 * sin(clock * 8.0)
			ring.scale = Vector3(k, 1.0, k) * (1.0 if can else 0.8)
			(ring.material_override as StandardMaterial3D).albedo_color = Color(0.4, 1.0, 0.4) if can else Color(1.0, 0.9, 0.2)
	if held < 0 and can and playing and vr_rig.trigger_pressed():
		held = near
		var s: Node3D = sheep[near]
		s.set("state", SheepScript.HELD)
		s.set("last_by", 0)
		vr_rig.pulse(VrRig.RIGHT, 0.6, 0.08)
		sheep_fx(s.position, "baa")
		sfx.play("pop", -6.0)
	elif held >= 0 and (not vr_rig.trigger_down() or not playing):
		var s: Node3D = sheep[held]
		held = -1
		s.set("state", SheepScript.FLY)
		s.set("vel", vr_rig.hand_velocity(VrRig.RIGHT).limit_length(8.0) * 0.9)
		vr_rig.pulse(VrRig.RIGHT, 0.3, 0.05)
		sfx.play("whoosh", -6.0)
	# Touches: sheep boing, dogs jump, the fence wobbles.
	for h in 2:
		var p := vr_rig.hand_point(h)
		if h == VrRig.RIGHT and held >= 0:
			continue
		for o in sheep:
			var s: Node3D = o
			if int(s.get("state")) == SheepScript.WALK and float(s.get("touch_cd")) <= 0.0 and p.distance_to(s.position + Vector3.UP * 0.3) < 0.35:
				s.set("touch_cd", 1.0)
				vr_rig.pulse(h, 0.3, 0.05)
				sheep_fx(s.position, "baa")
		if dog_touch_cd <= 0.0:
			for slot in dogs:
				var d: Node3D = dogs[slot]
				if p.distance_to(d.position + Vector3.UP * 0.4) < 0.4:
					dog_touch_cd = 0.8
					vr_rig.pulse(h, 0.3, 0.05)
					bark_fx(int(slot))
					break
		if fence_cd <= 0.0 and p.y < 0.75 and absf(maxf(absf(p.x), absf(p.z)) - PEN) < 0.12:
			fence_cd = 0.5
			vr_rig.pulse(h, 0.25, 0.04)
			wobble_fence()


## Every machine: the pen wobbles (a hand bumped it).
func wobble_fence() -> void:
	sfx.play_at("block", Vector3(0.0, 0.5, PEN), -6.0, randf_range(0.8, 1.1))
	var tw := create_tween()
	fence.scale = Vector3(1.04, 0.94, 1.04)
	tw.tween_property(fence, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	net.event("fence", [])


func burst(pos: Vector3, color: Color, amount: int = 14) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector3(0.0, -5.0, 0.0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.mesh = ResCache.get_or_make("sheep_bit_%s" % color.to_html(false), func() -> Resource:
		var bm := SphereMesh.new()
		bm.radius = 0.06
		bm.height = 0.12
		bm.radial_segments = 6
		bm.rings = 3
		bm.material = MeshKit.material(color, 1.5)
		return bm)
	add_child(p)
	p.position = pos
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play(sound_name, volume_db, pitch)


# --- Game loop ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	clock += delta
	if split != null:
		_move_local_players(delta)
	_follow_remote(delta)
	_animate_dogs(delta)
	if net.mode == "client":
		_follow_snapshot(delta)
		return
	for slot in bark_t.keys():
		bark_t[slot] = maxf(0.0, float(bark_t[slot]) - delta)
	for slot in bark_cd.keys():
		bark_cd[slot] = maxf(0.0, float(bark_cd[slot]) - delta)
	fence_cd = maxf(0.0, fence_cd - delta)
	dog_touch_cd = maxf(0.0, dog_touch_cd - delta)
	if results_showing():
		_sim_sheep(delta)  # penned sheep keep bouncing about
		results_t += delta
		if results_t > results_wait:
			_start_round()
		return
	time_left -= delta
	if int(ceil(time_left)) != int(net.state_get("time", 0)):
		net.state_set("time", maxi(0, int(ceil(time_left))))
	if time_left <= 0.0:
		_end_round(false)
		return
	_sim_sheep(delta)


func _follow_snapshot(delta: float) -> void:
	var k := 1.0 - exp(-15.0 * delta)
	for o in sheep:
		var s: Node3D = o
		s.position = s.position.lerp(s.get("net_target"), k)


# --- Networking ---------------------------------------------------------------------------

## Host, 30 Hz: the farmer's pose and the flock (positions + one flag byte each).
func make_snapshot() -> Array:
	var pos := PackedVector3Array()
	var flags := PackedByteArray()
	for o in sheep:
		var s: Node3D = o
		pos.append(s.position.snapped(Vector3.ONE * 0.01))
		flags.append((1 if bool(s.get("penned")) else 0) | (2 if int(s.get("state")) != SheepScript.WALK else 0))
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	# Every player avatar (slot, position, yaw): each machine sees the other machines' players.
	var av_slots := PackedByteArray()
	var av_pos := PackedVector3Array()
	var av_yaw := PackedFloat32Array()
	for slot in dogs:
		var a: Node3D = dogs[slot]
		av_slots.append(int(slot))
		av_pos.append(a.position)
		av_yaw.append(a.rotation.y)
	return [pose, pos, flags, av_slots, av_pos, av_yaw]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 6 or (s[1] as PackedVector3Array).size() != (s[2] as PackedByteArray).size():
		return
	var pose: PackedFloat32Array = s[0]
	if pose.size() > 0 and vr_avatar == null:
		_make_vr_avatar()
	if vr_avatar != null:
		vr_avatar.apply_pose(pose)
	var av_slots: PackedByteArray = s[3]
	var av_pos: PackedVector3Array = s[4]
	var av_yaw: PackedFloat32Array = s[5]
	for i in av_slots.size():
		var slot: int = av_slots[i]
		if dogs.has(slot) and not party.is_local(slot):
			if not net_target.has(slot):
				(dogs[slot] as Node3D).position = av_pos[i]
			net_target[slot] = [av_pos[i], av_yaw[i]]
	var pos: PackedVector3Array = s[1]
	var flags: PackedByteArray = s[2]
	if pos.size() != sheep.size():
		_clear_sheep()
		for p in pos:
			_make_sheep(p)
		_refresh_group()
	for i in pos.size():
		var n: Node3D = sheep[i]
		n.set("net_target", pos[i])
		n.set("penned", (flags[i] & 1) != 0)
		n.set("state", SheepScript.FLY if (flags[i] & 2) != 0 else SheepScript.WALK)


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"sheep":
			sheep_fx(args[0], String(args[1]), int(args[2]))
		"bark":
			bark_fx(int(args[0]))
		"fence":
			wobble_fence()
		"celebrate":
			celebrate()
