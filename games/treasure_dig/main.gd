extends Node3D
## TREASURE DIG: a little sandy island. TV players run around and press A to dig; treasure (coins,
## gems, a silly old boot) pops up and they carry it to the big chest. The VR player is a giant
## standing in the sea with a magic telescope: point it at the beach and pull the trigger to make
## a sparkle where treasure hides. The giant's hands can also poke a sparkle to dig it up, grab
## treasure and throw it into the chest, splash the sea, wobble the palms and tickle the diggers.
## 2-minute rounds; then the chest opens and everyone sees the haul. Then it starts again by itself.
##
## The island lives under `beach` (scaled by S), so the giant can reach it from the sea. All game
## positions below are beach-local unless they say "global".

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
const Props := preload("res://games/treasure_dig/props.gd")

const GAME_ID := "treasure_dig"
const S := 0.25  ## beach scale: 1 beach unit = 25 cm for the giant
const BEACH_Y := 0.8  ## global height of the sand (the giant stands in the sea, waist deep)
const SEA_Y := 0.7
const ISLAND := 7.0  ## sand radius
const R := 6.2  ## where diggers can walk
const SPEED := 4.5
const HIDDEN := 6  ## treasures buried at any time
const DIG_RADIUS := 1.25
const SPARKLE_TIME := 9.0
const CHEST_R := 1.9
const CARRY_H := 1.5
const LOOKS: Array[String] = ["pirate", "detective", "farmer", "villager", "athlete", "chef", "princess"]
const HAND_BASE := 10  ## carrier code for the giant's hands (10 = left, 11 = right)
const GROUND := -1
const FLYING := -2

var round_time := 120.0  ## seconds per round (bots shorten it)

# --- The networking contract ---
var net: Node
var ready_to_play := false
var party: Party
var split: SplitView
var vr_rig: VrRig
var save: Save
var sfx: Node
var music: Node
var hints: Hints
var awards: Awards
var sky: SkyKit.SkyRig

var beach: Node3D
var chest_lid: Node3D
var palms: Array[Node3D] = []
var avatars := {}  # slot -> Node3D (under beach)
var last_pos := {}
var cams := {}
var group_cam: CameraRig
var huds := {}
var score_labels := {}
var timers := {}
var join_prompt: Control
var vr_avatar: VrRig.Avatar
var vr_sign: Label3D  # host: big score + clock over the chest, turned to the giant
var vr_banner: Node3D
var tv_banner: Control
var results_ui: Control
var vr_results: Node
var telescope_beam: MeshInstance3D
var telescope_ring: MeshInstance3D

# items: id -> {"node": Node3D, "kind": int, "carrier": int, "vel": Vector3, "held_t": float}
var items := {}
var next_item := 0
var hidden: Array = []  # host: [Vector3 pos, int kind]
var sparkles: Array = []  # host: [Vector3 pos, float time_left]
var sparkle_nodes: Array[Node3D] = []  # every machine: pooled markers
var holes: Array = []  # untyped: entries may be freed by their tweens
var dig_cd := {}  # slot -> seconds (local machine)
var send_t := 0.0
var time_left := 0.0
var results_t := 0.0
var auto_sparkle_t := 4.0
var scope_cd := 0.0
var hand_was_low: Array[bool] = [false, false]
var hand_was_wet: Array[bool] = [false, false]
var touch_cd := {}  # String -> seconds
var haul: Array[int] = [0, 0, 0]
var found_total := 0  # bots / stats over all rounds
var stats := {"sparkles": 0, "giant_digs": 0, "giant_banks": 0, "throws": 0, "tv_digs": 0}  # bots


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
	music.play_mood("shop")
	music.prepare(["victory"])
	awards = Awards.new()
	awards.define("sparkles", "MAGIC EYE", "%s sparkles", "sparkles")
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
	_build_world()
	if VrRig.wanted(mode):
		vr_rig = VrRig.new()
		vr_rig.move_speed = 1.2
		vr_rig.move_filter = _keep_in_sea
		add_child(vr_rig)
		vr_rig.place(Vector3(0.0, 0.0, ISLAND * S + 0.25), 0.0)
		_build_telescope()
		hints.set_vr_rig(vr_rig, self)
	if mode != "host":
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		group_cam = CameraRig.new()
		group_cam.camera = split.shared_camera()
		group_cam.group_min_distance = 3.2
		group_cam.group_margin = 0.6
		add_child(group_cam)
		group_cam.follow_group([], -50.0, 0.0, 0.0)
		group_cam.shot_look(beach.to_global(Vector3(0, 0, 9.0)) + Vector3.UP * 1.6, beach.global_position, 0.0)
		_make_hud(-1, split.shared_hud())
		hints.add_view(huds[-1], -1)
		if mode == "client":
			vr_avatar = VrRig.Avatar.new()
			add_child(vr_avatar)
			split.set_bubble(VrRig.build_mirror(self, vr_avatar.head, false))
		elif vr_rig != null:
			split.set_bubble(vr_rig.mirror)
	party.allow_slot0 = mode == "local" and vr_rig == null
	awards.set_player(0, "GIANT" if vr_rig != null or mode == "client" else party.name_of(0))
	if mode != "client":
		net.state_set("best", int(save.data["best"]))
		_start_round()
	if vr_rig != null:
		hints.hint("vr_scope", "Point and pull the trigger!", {"to": "vr", "icon": "star"})
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Treasure Dig: %s mode%s" % [mode, " with a VR giant" if vr_rig != null else ""])


## The giant wades round the island but never onto it.
func _keep_in_sea(_from: Vector3, to: Vector3) -> Vector3:
	var flat := Vector2(to.x, to.z)
	var d := flat.length()
	var lo := ISLAND * S + 0.15
	var hi := ISLAND * S + 2.0
	if d < 0.001:
		return Vector3(0.0, to.y, lo)
	var c := clampf(d, lo, hi)
	flat = flat / d * c
	return Vector3(flat.x, to.y, flat.y)


# --- World --------------------------------------------------------------------------------

func _build_world() -> void:
	sky = SkyKit.apply(self, "day", vr_rig != null or VrRig.headset_available())
	# The sea: one big disc at the giant's waist.
	var sea := MeshInstance3D.new()
	var sd := CylinderMesh.new()
	sd.top_radius = 40.0
	sd.bottom_radius = 40.0
	sd.height = 0.05
	sd.radial_segments = 40
	sea.mesh = sd
	sea.material_override = MeshKit.material(Color(0.2, 0.62, 0.9, 1.0))
	sea.position.y = SEA_Y
	add_child(sea)
	beach = Node3D.new()
	beach.name = "Beach"
	beach.position = Vector3(0.0, BEACH_Y, 0.0)
	beach.scale = Vector3.ONE * S
	add_child(beach)
	# Sand + a wet rim, baked into one mesh.
	var b := MeshKit.Builder.new()
	b.cylinder(ISLAND, ISLAND + 0.8, 1.2, MeshKit.at(Vector3(0, -0.6, 0)), Color(0.98, 0.87, 0.6), 40)
	b.cylinder(ISLAND + 0.8, ISLAND + 1.6, 0.7, MeshKit.at(Vector3(0, -1.55, 0)), Color(0.85, 0.72, 0.48), 40)
	for k in 10:
		var a := k * TAU / 10.0 + 0.3
		b.sphere(0.35, MeshKit.at(Vector3(cos(a), 0.0, sin(a)) * (ISLAND - 0.4), Vector3(1.0, 0.4, 1.0)), Color(1.0, 0.75, 0.8), 8)  # shells
	var sand := MeshKit.instance(b.build(), false)
	sand.material_override = MeshKit.vertex_material()
	beach.add_child(sand)
	# The chest in the middle: base + a lid on its hinge.
	var chest := Node3D.new()
	chest.name = "Chest"
	beach.add_child(chest)
	chest.add_child(MeshKit.instance(Props.chest_base(), false))
	chest_lid = Node3D.new()
	chest_lid.position = Vector3(0.0, 0.9, -0.6)
	chest.add_child(chest_lid)
	var lid := MeshKit.instance(Props.chest_lid(), false)
	chest_lid.add_child(lid)
	# Palm trees round the rim (each its own node so it can wobble when touched).
	for k in 5:
		var a := k * TAU / 5.0 + 0.6
		var p := MeshKit.instance(MeshKit.prop("palm"), false)
		var holder := Node3D.new()
		holder.position = Vector3(cos(a), 0.0, sin(a)) * (ISLAND - 0.7)
		holder.rotation.y = randf() * TAU
		holder.scale = Vector3.ONE * 1.4
		holder.add_child(p)
		beach.add_child(holder)
		palms.append(holder)
	sfx.play_loop("waves", -14.0)


func _build_telescope() -> void:
	var t := MeshKit.instance(Props.telescope(), false)
	vr_rig.hand_r.add_child(t)
	telescope_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.004
	cm.bottom_radius = 0.004
	cm.height = 1.0
	cm.radial_segments = 6
	cm.rings = 1
	telescope_beam.mesh = cm
	telescope_beam.material_override = MeshKit.material(Color(1.0, 0.95, 0.5, 0.6), 2.0)
	telescope_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(telescope_beam)
	telescope_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.75
	tm.outer_radius = 0.95
	tm.rings = 20
	tm.ring_segments = 4
	telescope_ring.mesh = tm
	telescope_ring.material_override = MeshKit.material(Color(1.0, 0.95, 0.5), 2.0)
	beach.add_child(telescope_ring)
	vr_sign = UiKit.label3d("0", 0.16, "gold", true)
	vr_sign.outline_size = 26
	add_child(vr_sign)
	vr_sign.global_position = beach.to_global(Vector3(0.0, 5.0, 0.0))


# --- HUD ----------------------------------------------------------------------------------------

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
	row.add_child(UiKit.icon("coin", "gold", 40.0))
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


func _all_huds() -> Array:
	var out: Array = []
	for k in huds:
		if is_instance_valid(huds[k]):
			out.append(huds[k])
	return out


# --- Players ------------------------------------------------------------------------------

func _on_player_joined(slot: int, _device: int) -> void:
	var a := _ensure_avatar(slot)
	if party.is_local(slot) and split != null:
		var c := CameraRig.new()
		c.camera = split.camera(slot)
		c.party = party
		c.slot = slot
		c.pivot_height = 0.25
		c.pitch = -0.6
		c.min_distance = 0.3
		c.avoid_walls = false
		add_child(c)
		c.follow(a, 2.0, 0.0)
		cams[slot] = c
		_make_hud(slot, split.hud(slot))
		hints.add_view(huds[slot], slot)
		hints.hint("dig", "DIG!", {"to": slot, "button": "A", "times": 2})
	awards.set_player(slot, party.name_of(slot))
	_refresh_group()
	_refresh_hud()
	sfx.play("ui_notify", -6.0)


func _on_player_left(slot: int) -> void:
	_drop_carried(slot)
	for d in [avatars, cams]:
		var dict: Dictionary = d
		if dict.has(slot):
			(dict[slot] as Node).queue_free()
			dict.erase(slot)
	last_pos.erase(slot)
	if huds.has(slot):
		var h: Control = huds[slot]
		if is_instance_valid(h):
			h.queue_free()
		huds.erase(slot)
	score_labels.erase(slot)
	timers.erase(slot)
	hints.remove_view(slot)
	_refresh_group()
	_refresh_hud()


func _ensure_avatar(slot: int) -> Node3D:
	if avatars.has(slot) and is_instance_valid(avatars[slot]):
		return avatars[slot]
	var a := Creatures.humanoid({"class": LOOKS[slot % LOOKS.size()], "outfit": party.color_of(slot), "seed": slot + 11})
	a.name = "Avatar%d" % slot
	beach.add_child(a)
	var ang := slot * 0.9
	a.position = Vector3(cos(ang), 0.0, sin(ang)) * 3.2
	HudKit.nameplate(a, party.name_of(slot), slot, Creatures.height_of(a) + 0.35, 0.3)
	avatars[slot] = a
	last_pos[slot] = a.position
	return a


func _refresh_group() -> void:
	if group_cam != null:
		var t: Array = avatars.values()
		if t.is_empty():
			group_cam.shot_look(beach.to_global(Vector3(0, 0, 9.0)) + Vector3.UP * 1.6, beach.global_position, 1.0)
		else:
			group_cam.follow_group(t, -50.0)


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
		var mv := party.stick(slot, "move") if playing else Vector2.ZERO
		if mv != Vector2.ZERO:
			var cam := split.active_camera(slot)
			var f := -cam.global_basis.z
			f.y = 0.0
			f = f.normalized()
			var r := Vector3(-f.z, 0.0, f.x)
			var dir := r * mv.x - f * mv.y
			var p := a.position + dir * SPEED * delta
			p.y = 0.0
			p = p.limit_length(R)
			var flat := Vector2(p.x, p.z)
			if flat.length() < 1.3:  # walk round the chest
				flat = flat.normalized() * 1.3 if flat.length() > 0.01 else Vector2(0, 1.3)
				p = Vector3(flat.x, 0.0, flat.y)
			a.position = p
			Creatures.anim(a).face(dir)
		dig_cd[slot] = maxf(0.0, float(dig_cd.get(slot, 0.0)) - delta)
		if playing and party.just_pressed(slot, "accept") and float(dig_cd[slot]) <= 0.0:
			dig_cd[slot] = 0.4
			var fwd := a.global_basis.z
			fwd.y = 0.0
			var spot := a.position + fwd.normalized() * 0.6
			Creatures.anim(a).play("attack", 0.35)
			Creatures.anim(a).squash(0.25)
			party.rumble(slot, 0.3, 0.0, 0.08)
			net.request(slot, "dig", [spot])
		if net.mode == "client" and send:
			net.send_state(a.position, a.rotation.y, 0.0, slot)


func _animate_avatars(delta: float) -> void:
	for slot in avatars:
		var a: Node3D = avatars[slot]
		var prev: Vector3 = last_pos.get(slot, a.position)
		var v := Vector2(a.position.x - prev.x, a.position.z - prev.z).length() / maxf(delta, 0.001)
		Creatures.anim(a).walk(v if v > 0.3 else 0.0)
		last_pos[slot] = a.position


func on_remote_state(slot: int, pos: Vector3, yaw: float, _pitch: float) -> void:
	if avatars.has(slot):
		var a: Node3D = avatars[slot]
		a.position = pos
		a.rotation.y = yaw


func on_request(slot: int, action: String, args: Array) -> void:
	match action:
		"dig":
			if String(net.state_get("phase", "")) == "play" and not args.is_empty():
				var p: Vector3 = args[0]
				_dig(Vector3(p.x, 0.0, p.z).limit_length(R + 0.5), slot, DIG_RADIUS, true)
		"next_round":
			if String(net.state_get("phase", "")) == "results" and results_t > 2.0:
				_start_round()


func on_pause_changed(paused: bool, by_slot: int) -> void:
	var why := "%s  -  %s" % [party.name_of(by_slot), "wrist MENU" if vr_rig != null else "Start"]
	if vr_rig != null:
		if paused:
			vr_banner = HudKit.vr_card(self, vr_rig.camera, "PAUSED", why, {"width": 1.1})
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
		(tv_banner.find_child("Why", true, false) as Label).text = why
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
		"round":
			HudKit.banner(_all_huds(), "TREASURE DIG", "", {"duration": 2.2})
			if vr_rig != null:
				HudKit.vr_banner(self, vr_rig.camera, "TREASURE DIG", "", {"duration": 2.2, "sound": ""})
			_close_lid()
		"phase":
			if String(value) == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()


# --- Rounds -------------------------------------------------------------------------------------

func _start_round() -> void:
	for id in items.keys():
		(items[id]["node"] as Node).queue_free()
	items.clear()
	hidden.clear()
	sparkles.clear()
	for i in HIDDEN:
		_bury()
	awards.reset()
	haul = [0, 0, 0]
	time_left = round_time
	results_t = 0.0
	net.state_set("score", 0)
	net.state_set("time", int(ceil(time_left)))
	net.state_set("phase", "play")
	net.state_set("round", int(net.state_get("round", 0)) + 1)


func _end_round() -> void:
	for id in items.keys():
		var it: Dictionary = items[id]
		if int(it["carrier"]) != GROUND:
			_bank(int(id), int(it["carrier"]) if int(it["carrier"]) >= 0 and int(it["carrier"]) < HAND_BASE else 0)
	var score := int(net.state_get("score", 0))
	if score > int(save.data["best"]):
		save.data["best"] = score
		save.mark_dirty()
		net.state_set("best", score)
	var data := awards.results({"title": "WE FOUND %d!" % score, "subtitle": "Treasure chest", "style": "victory",
		"stats": [["COINS", str(haul[0])], ["GEMS", str(haul[1])], ["BOOTS", str(haul[2])], ["BEST", str(int(net.state_get("best", 0)))]],
		"score_format": "%d"})
	net.state_set("results", data)
	net.state_set("phase", "results")
	results_t = 0.0


func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
	_open_chest_show()
	var phase_round := int(net.state_get("round", 0))
	get_tree().create_timer(2.6).timeout.connect(func() -> void:
		if not results_showing() or int(net.state_get("round", 0)) != phase_round:
			return
		if split != null and huds.has(-1):
			split.set_shared(true)
			var screen := Awards.results_screen(huds[-1], data, {"party": party})
			screen.continued.connect(func() -> void:
				var seats := party.local_slots()
				net.request(seats[0] if not seats.is_empty() else 0, "next_round"))
			results_ui = screen
		if vr_rig != null:
			var card := Awards.vr_summary(self, null, data, null, {"rig": vr_rig})
			card.continued.connect(func() -> void: net.request(0, "next_round"))
			vr_results = card)


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


## Every machine: the lid flies open and treasure fountains out.
func _open_chest_show() -> void:
	if chest_lid == null:
		return
	var t := chest_lid.create_tween()
	t.tween_property(chest_lid, "rotation:x", -1.9, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	sfx.play("chest", 0.0)
	sfx.play("fanfare", -4.0)
	var center := Vector3(0.0, 1.2, 0.0)
	for k in 3:
		get_tree().create_timer(0.3 + k * 0.45).timeout.connect(func() -> void:
			Props.burst(beach, center, Color(1.0, 0.82, 0.25), 30, 9.0, 0.3, 2.0, -14.0)
			Props.burst(beach, center, Color(0.4, 0.9, 1.0), 12, 8.0, 0.25, 2.0, -14.0)
			sfx.play("kaching", -2.0, 1.0 + k * 0.12))


func _close_lid() -> void:
	if chest_lid != null:
		chest_lid.create_tween().tween_property(chest_lid, "rotation:x", 0.0, 0.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _bounce_lid() -> void:
	if chest_lid == null or results_showing():
		return
	var t := chest_lid.create_tween()
	t.tween_property(chest_lid, "rotation:x", -0.7, 0.1)
	t.tween_property(chest_lid, "rotation:x", 0.0, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


# --- Game loop ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if net.mode != "host":
		_move_local_players(delta)
	_animate_avatars(delta)
	_animate_items(delta)
	_animate_sparkles(delta)
	if vr_rig != null:
		_giant(delta)
	if net.mode == "client":
		return
	if results_showing():
		results_t += delta
		if results_t > 16.0:
			_start_round()
		return
	time_left -= delta
	if int(ceil(time_left)) != int(net.state_get("time", 0)):
		net.state_set("time", maxi(0, int(ceil(time_left))))
	if time_left <= 0.0:
		_end_round()
		return
	_tick_sparkles(delta)
	_tick_items(delta)


## Host: sparkles fade; when nobody is using the telescope, one appears by itself now and then.
func _tick_sparkles(delta: float) -> void:
	for i in range(sparkles.size() - 1, -1, -1):
		var sp: Array = sparkles[i]
		sp[1] = float(sp[1]) - delta
		if float(sp[1]) <= 0.0 or _hidden_near(sp[0], 0.3) < 0:
			sparkles.remove_at(i)
	auto_sparkle_t -= delta
	if auto_sparkle_t <= 0.0:
		auto_sparkle_t = 16.0 if vr_rig != null else 5.0
		if sparkles.size() < 2 and not hidden.is_empty():
			var h: Array = hidden[randi() % hidden.size()]
			_add_sparkle(h[0], -1)


func _add_sparkle(pos: Vector3, by: int) -> void:
	for sp in sparkles:
		if (sp[0] as Vector3).distance_to(pos) < 0.2:
			sp[1] = SPARKLE_TIME
			return
	sparkles.append([pos, SPARKLE_TIME])
	if by == 0:
		awards.add(0, "sparkles")
		stats["sparkles"] += 1
	fx("sparkle", [pos])
	hints.hint("sparkle_tv", "Dig at the sparkle!", {"to": "tv", "icon": "star"})


## Host: bury a new treasure somewhere free.
func _bury() -> void:
	var pos := Vector3.ZERO
	for tries in 30:
		var a := randf() * TAU
		pos = Vector3(cos(a), 0.0, sin(a)) * randf_range(2.2, R - 0.4)
		var ok := true
		for h in hidden:
			if (h[0] as Vector3).distance_to(pos) < 1.8:
				ok = false
				break
		if ok:
			break
	var roll := randf()
	var kind := Props.KIND_COIN if roll < 0.55 else (Props.KIND_GEM if roll < 0.8 else Props.KIND_BOOT)
	hidden.append([pos, kind])


func _hidden_near(pos: Vector3, radius: float) -> int:
	var best := -1
	var bd := radius
	for i in hidden.size():
		var d := Vector2(pos.x - (hidden[i][0] as Vector3).x, pos.z - (hidden[i][0] as Vector3).z).length()
		if d < bd:
			bd = d
			best = i
	return best


## Host: someone dug at `pos`. A TV digger carries what they find; the giant's poke makes it pop out.
func _dig(pos: Vector3, by: int, radius: float, carry: bool, toward: Vector3 = Vector3.INF) -> void:
	var i := _hidden_near(pos, radius)
	if i < 0:
		fx("dig", [pos, -1, by])
		return
	var h: Array = hidden[i]
	hidden.remove_at(i)
	_bury()
	var kind := int(h[1])
	var at: Vector3 = h[0]
	found_total += 1
	net.state_set("found", found_total)
	stats["giant_digs" if not carry else "tv_digs"] += 1
	awards.add(by, "pickups")
	fx("dig", [at, kind, by])
	var carrier := FLYING
	if carry and by >= 0 and by < HAND_BASE and _carrying(by) < 0 and avatars.has(by):
		carrier = by
		hints.hint("carry", "To the chest!", {"to": by, "icon": "chest"})
	var id := _make_item(-1, kind, at + Vector3.UP * 0.3)
	var it: Dictionary = items[id]
	it["carrier"] = carrier
	if carrier == FLYING:
		var out := Vector3(at.x, 0.0, at.z).normalized() * -1.5
		if toward != Vector3.INF:  # leap towards the giant
			var d := Vector3(toward.x - at.x, 0.0, toward.z - at.z)
			out = d.normalized() * maxf(d.length() - 2.0, 0.0) / 0.8
		it["vel"] = Vector3(out.x, 12.0, out.z)


func _carrying(slot: int) -> int:
	for id in items:
		if int(items[id]["carrier"]) == slot:
			return int(id)
	return -1


func _drop_carried(slot: int) -> void:
	var id := _carrying(slot)
	if id >= 0:
		items[id]["carrier"] = FLYING
		items[id]["vel"] = Vector3(0.0, 4.0, 0.0)


## Every machine: make an item node (host picks the id).
func _make_item(id: int, kind: int, pos: Vector3) -> int:
	if id < 0:
		next_item += 1
		id = next_item
	var n := Node3D.new()
	n.add_child(Props.item_mesh(kind))
	beach.add_child(n)
	n.position = pos
	n.scale = Vector3.ONE * 0.2
	n.create_tween().tween_property(n, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	items[id] = {"node": n, "kind": kind, "carrier": GROUND, "vel": Vector3.ZERO, "held_t": 0.0}
	return id


## Host: carried items follow, flying items fly, the chest swallows what reaches it.
func _tick_items(delta: float) -> void:
	for id in items.keys():
		if not items.has(id):
			continue
		var it: Dictionary = items[id]
		var n: Node3D = it["node"]
		var c := int(it["carrier"])
		if c == FLYING:
			var v: Vector3 = it["vel"]
			v.y -= 30.0 * delta
			var flat := Vector2(n.position.x, n.position.z)
			if v.y < 0.0 and flat.length() < 4.0 and it.has("thrower"):  # a friendly magnet into the chest
				v.x = lerpf(v.x, -n.position.x * 3.0, 2.0 * delta)
				v.z = lerpf(v.z, -n.position.z * 3.0, 2.0 * delta)
			n.position += v * delta
			it["vel"] = v
			if flat.length() < CHEST_R * 0.8 and n.position.y < 2.0 and v.y < 0.0:
				_bank(int(id), int(it.get("thrower", 0)))
				continue
			if n.position.y <= 0.0:
				n.position.y = 0.0
				if flat.length() > R:
					flat = flat.normalized() * (R - 0.3)
					n.position.x = flat.x
					n.position.z = flat.y
					fx("splash", [n.position])
				it["carrier"] = GROUND
				fx("land", [n.position])
		elif c >= 0 and c < HAND_BASE:
			if not avatars.has(c):
				it["carrier"] = GROUND
				continue
			var a: Node3D = avatars[c]
			n.position = a.position + Vector3.UP * CARRY_H
			if Vector2(a.position.x, a.position.z).length() < CHEST_R:
				_bank(int(id), c)
		elif c == GROUND:
			for slot in avatars:
				var a: Node3D = avatars[slot]
				if _carrying(int(slot)) < 0 and Vector2(a.position.x - n.position.x, a.position.z - n.position.z).length() < 0.9:
					it["carrier"] = int(slot)
					fx("pickup", [n.position, int(slot)])
					break


## Host: an item went into the chest.
func _bank(id: int, by: int) -> void:
	var it: Dictionary = items[id]
	var kind := int(it["kind"])
	var n: Node3D = it["node"]
	var pos := n.position
	n.queue_free()
	items.erase(id)
	haul[kind] += 1
	var v: int = Props.VALUES[kind]
	awards.add(by, "score", v)
	net.state_set("score", int(net.state_get("score", 0)) + v)
	fx("bank", [pos, kind, by])


# --- The giant (host / local with a VR rig) -----------------------------------------------------

func _giant(delta: float) -> void:
	scope_cd = maxf(0.0, scope_cd - delta)
	for k in touch_cd.keys():
		touch_cd[k] = float(touch_cd[k]) - delta
		if float(touch_cd[k]) <= 0.0:
			touch_cd.erase(k)
	# The telescope: a beam to the sand and a ring where it points.
	var o := vr_rig.hand_r.global_position
	var dir := -vr_rig.hand_r.global_basis.z.normalized()
	var hit := Vector3.ZERO
	var aiming := false
	if dir.y < -0.05:
		var t := (BEACH_Y - o.y) / dir.y
		if t > 0.0 and t < 12.0:
			hit = o + dir * t
			var local := beach.to_local(hit)
			aiming = Vector2(local.x, local.z).length() < ISLAND + 0.5
	telescope_beam.visible = aiming and not results_showing()
	telescope_ring.visible = telescope_beam.visible
	if aiming:
		var start := o + dir * 0.24
		var blen := start.distance_to(hit)
		telescope_beam.global_transform = Transform3D(MeshKit.aim(Vector3.ZERO, dir).basis * Basis.from_scale(Vector3(1.0, blen, 1.0)), (start + hit) * 0.5)
		var lh := beach.to_local(hit)
		telescope_ring.position = Vector3(lh.x, 0.06, lh.z)
		telescope_ring.rotation.y += delta * 2.0
	if net.mode == "client" or vr_sign == null:
		return
	# The sign over the chest turns to the giant (on Y only).
	vr_sign.text = "%d\n%s" % [int(net.state_get("score", 0)), HudKit.clock_text(float(net.state_get("time", 0)), false)]
	var to := vr_sign.global_position - vr_rig.head_position()
	to.y = 0.0
	if to.length() > 0.01:
		vr_sign.global_basis = Basis(Vector3.UP, atan2(-to.x, -to.z))
	if results_showing():
		return
	if aiming and vr_rig.trigger_pressed() and scope_cd <= 0.0:
		scope_cd = 0.5
		var lh := beach.to_local(hit)
		var i := _hidden_near(lh, 3.2)
		vr_rig.pulse(VrRig.RIGHT, 0.5 if i >= 0 else 0.15, 0.08)
		if i >= 0:
			var hp: Vector3 = hidden[i][0]
			_add_sparkle(hp, 0)
			if party.player_count() == 0:  # playing alone: the treasure leaps out to the giant
				var head := beach.to_local(vr_rig.head_position())
				get_tree().create_timer(0.8).timeout.connect(func() -> void:
					if not results_showing() and _hidden_near(hp, 0.2) >= 0:
						_dig(hp, 0, 0.2, false, head))
		else:
			fx("fizz", [Vector3(lh.x, 0.1, lh.z)])
	for h in 2:
		_giant_hand(h, delta)


func _giant_hand(h: int, delta: float) -> void:
	var gp := vr_rig.hand_point(h)
	var lp := beach.to_local(gp)
	var flat := Vector2(lp.x, lp.z).length()
	var held := -1
	for id in items:
		if int(items[id]["carrier"]) == HAND_BASE + h:
			held = int(id)
	# Holding treasure: follow the glove; drop it in the chest, or throw it.
	if held >= 0:
		var it: Dictionary = items[held]
		var n: Node3D = it["node"]
		n.position = lp + Vector3.DOWN * 0.3
		it["held_t"] = float(it["held_t"]) + delta
		if flat < CHEST_R and lp.y < 3.5:
			vr_rig.pulse(h, 0.6, 0.1)
			stats["giant_banks"] += 1
			_bank(held, 0)
		elif float(it["held_t"]) > 0.3 and vr_rig.hand_speed(h) > 2.0:
			it["carrier"] = FLYING
			it["thrower"] = 0
			it["vel"] = vr_rig.hand_velocity(h) / S * 0.8
			stats["throws"] += 1
			fx("throw", [n.position])
		return
	# Grab a treasure lying around (or flying past).
	for id in items:
		var it: Dictionary = items[id]
		var c := int(it["carrier"])
		if (c == GROUND or c == FLYING) and (it["node"] as Node3D).position.distance_to(lp) < 1.1:
			it["carrier"] = HAND_BASE + h
			it["held_t"] = 0.0
			vr_rig.pulse(h, 0.4, 0.06)
			fx("pickup", [lp, 0])
			return
	# Poke the sand: puff! A poke at a sparkle digs the treasure out.
	var low := lp.y < 0.35 and flat < ISLAND
	if low and not hand_was_low[h]:
		vr_rig.pulse(h, 0.3, 0.05)
		var sp := -1
		for i in sparkles.size():
			if Vector2((sparkles[i][0] as Vector3).x - lp.x, (sparkles[i][0] as Vector3).z - lp.z).length() < 1.6:
				sp = i
		if sp >= 0:
			_dig(sparkles[sp][0], 0, 0.5, false)
		else:
			_dig(Vector3(lp.x, 0.0, lp.z), 0, 0.9, false)
	hand_was_low[h] = low
	# Splash the sea.
	var wet := gp.y < SEA_Y and flat > ISLAND
	if wet and not hand_was_wet[h]:
		vr_rig.pulse(h, 0.3, 0.05)
		fx("splash", [Vector3(lp.x, (SEA_Y - BEACH_Y) / S, lp.z)])
	hand_was_wet[h] = wet
	# Wobble palms, bounce the lid, tickle diggers.
	for i in palms.size():
		var p: Node3D = palms[i]
		var key := "palm%d" % i
		if not touch_cd.has(key) and Vector2(p.position.x - lp.x, p.position.z - lp.z).length() < 1.4 and lp.y > 0.5 and lp.y < 4.5:
			touch_cd[key] = 0.8
			vr_rig.pulse(h, 0.3, 0.05)
			fx("palm", [i])
	if not touch_cd.has("lid") and flat < 1.6 and lp.y < 2.2:
		touch_cd["lid"] = 0.8
		vr_rig.pulse(h, 0.3, 0.05)
		fx("lid", [])
	for slot in avatars:
		var a: Node3D = avatars[slot]
		var key := "tickle%d" % int(slot)
		if not touch_cd.has(key) and lp.distance_to(a.position + Vector3.UP * 0.6) < 1.0:
			touch_cd[key] = 1.2
			vr_rig.pulse(h, 0.3, 0.05)
			fx("tickle", [int(slot)])


# --- Effects (every machine; the host sends each as an event) ----------------------------------

func fx(kind: String, args: Array) -> void:
	_play_fx(kind, args)
	if net.mode == "host":
		net.event(kind, args)


func _play_fx(fx_kind: String, args: Array) -> void:
	match fx_kind:
		"dig":
			var pos: Vector3 = args[0]
			var found := int(args[1])
			var by := int(args[2])
			Props.burst(beach, pos + Vector3.UP * 0.1, Color(0.95, 0.82, 0.55), 18, 6.0, 0.22)
			_make_hole(pos)
			_sound_at("footstep", pos, -2.0, 0.7)
			if found >= 0:
				Props.burst(beach, pos + Vector3.UP * 0.5, Color(1.0, 0.9, 0.4), 22, 9.0, 0.2, 2.5, -6.0)
				_sound_at(["coin", "kaching", "boing"][found], pos, 0.0)
				if found == Props.KIND_BOOT:
					_sound_at("honk", pos, -4.0, 1.3)
				HudKit.popup(self, beach.to_global(pos + Vector3.UP * 2.0), ["COIN!", "GEM!", "BOOT?!"][found],
					{"style": "score", "size": 0.6, "color": ["gold", Color(0.4, 0.9, 1.0), Color(0.8, 0.55, 0.3)][found]})
				if avatars.has(by):
					Creatures.anim(avatars[by]).play("cheer", 0.6)
		"bank":
			var pos: Vector3 = args[0]
			var kind := int(args[1])
			var by := int(args[2])
			var ghost := Node3D.new()
			ghost.add_child(Props.item_mesh(kind))
			beach.add_child(ghost)
			ghost.position = pos
			var t := ghost.create_tween()
			t.tween_property(ghost, "position", Vector3(0.0, 1.0, 0.0), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.tween_callback(ghost.queue_free)
			_bounce_lid()
			Props.burst(beach, Vector3(0.0, 1.2, 0.0), Color(1.0, 0.85, 0.3), 20, 6.0, 0.18, 2.5)
			_sound_at("kaching" if kind == Props.KIND_GEM else "coin", Vector3(0, 1, 0), 0.0, 1.0 + randf() * 0.15)
			HudKit.score(self, beach.to_global(Vector3(0.0, 3.0, 0.0)), int(Props.VALUES[kind]),
				{"color": party.color_of(by) if by > 0 else "gold", "size": 0.8})
			if avatars.has(by):
				Creatures.anim(avatars[by]).play("cheer", 0.6)
		"sparkle":
			var pos: Vector3 = args[0]
			Props.burst(beach, pos + Vector3.UP * 1.0, Color(1.0, 0.95, 0.5), 20, 6.0, 0.18, 3.0, 0.0)
			_sound_at("sparkle", pos, 0.0)
		"fizz":
			Props.burst(beach, args[0], Color(0.8, 0.85, 1.0), 8, 3.0, 0.12, 1.5, 0.0)
			_sound_at("pop", args[0], -6.0, 0.8)
		"pickup":
			_sound_at("pickup", args[0], -3.0)
			var slot := int(args[1])
			if avatars.has(slot):
				Creatures.anim(avatars[slot]).squash(0.2)
		"land":
			Props.burst(beach, args[0], Color(0.95, 0.82, 0.55), 8, 3.0, 0.15)
			_sound_at("land", args[0], -6.0)
		"throw":
			_sound_at("whoosh", args[0], -2.0)
		"splash":
			Props.burst(beach, args[0], Color(0.6, 0.85, 1.0), 24, 8.0, 0.22, 0.5)
			_sound_at("splash", args[0], 0.0)
		"palm":
			var i := int(args[0])
			if i < palms.size():
				var p: Node3D = palms[i]
				var t := p.create_tween()
				t.tween_property(p, "rotation:z", 0.25, 0.1)
				t.tween_property(p, "rotation:z", -0.18, 0.18)
				t.tween_property(p, "rotation:z", 0.08, 0.16)
				t.tween_property(p, "rotation:z", 0.0, 0.2)
				Props.burst(beach, p.position + Vector3.UP * 3.4, Color(0.35, 0.75, 0.3), 10, 3.0, 0.2)
				_sound_at("boing", p.position, -4.0, 0.8)
		"lid":
			_bounce_lid()
			_sound_at("chest", Vector3.ZERO, -6.0, 1.3)
		"tickle":
			var slot := int(args[0])
			if avatars.has(slot):
				Creatures.anim(avatars[slot]).play("jump", 0.5)
				_sound_at("boing", (avatars[slot] as Node3D).position, -2.0, 1.4)


func _sound_at(sound_name: String, local_pos: Vector3, db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play_at(sound_name, beach.to_global(local_pos), db, pitch)


func _make_hole(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45
	cm.bottom_radius = 0.45
	cm.height = 0.02
	cm.radial_segments = 12
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = MeshKit.material(Color(0.7, 0.55, 0.32))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beach.add_child(mi)
	mi.position = Vector3(pos.x, 0.015, pos.z)
	mi.scale = Vector3(0.2, 1.0, 0.2)
	var t := mi.create_tween()
	t.tween_property(mi, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(6.0)
	t.tween_property(mi, "scale", Vector3(0.01, 1.0, 0.01), 1.5)
	t.tween_callback(mi.queue_free)
	for i in range(holes.size() - 1, -1, -1):
		if not is_instance_valid(holes[i]):
			holes.remove_at(i)
	holes.append(mi)
	while holes.size() > 30:
		var old: Node3D = holes.pop_front()
		old.queue_free()


## Every machine: items spin and bob; the TV machine glues carried ones to its own diggers.
func _animate_items(delta: float) -> void:
	var tt := Time.get_ticks_msec() / 1000.0
	for id in items:
		var it: Dictionary = items[id]
		var n: Node3D = it["node"]
		if not is_instance_valid(n):
			continue
		var c := int(it["carrier"])
		n.rotation.y += delta * (3.0 if c == GROUND else 1.5)
		var mi: Node3D = n.get_child(0)
		mi.position.y = 0.15 + 0.12 * sin(tt * 4.0 + float(id)) if c == GROUND else 0.0
		if net.mode == "client" and c >= 0 and c < HAND_BASE and avatars.has(c) and party.is_local(c):
			n.position = (avatars[c] as Node3D).position + Vector3.UP * CARRY_H


func _animate_sparkles(delta: float) -> void:
	for n in sparkle_nodes:
		if n.visible:
			n.rotation.y += delta * 2.5
			var st: Node3D = n.get_node("Star")
			st.position.y = 0.15 * sin(Time.get_ticks_msec() / 250.0)


func _sync_sparkles(points: PackedVector3Array) -> void:
	while sparkle_nodes.size() < points.size():
		var m := Props.sparkle_marker()
		beach.add_child(m)
		sparkle_nodes.append(m)
	for i in sparkle_nodes.size():
		var n := sparkle_nodes[i]
		var show := i < points.size()
		if show and not n.visible:
			n.scale = Vector3.ONE * 0.1
			n.create_tween().tween_property(n, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		n.visible = show
		if show:
			n.position = points[i]


func _physics_process(_delta: float) -> void:
	if not ready_to_play or net.mode == "client":
		return
	var pts := PackedVector3Array()
	for sp in sparkles:
		pts.append(sp[0])
	_sync_sparkles(pts)


# --- Networking ---------------------------------------------------------------------------

func make_snapshot() -> Array:
	var ids := PackedInt32Array()
	var info := PackedInt32Array()
	var pos := PackedVector3Array()
	for id in items:
		var it: Dictionary = items[id]
		ids.append(int(id))
		info.append(int(it["kind"]) + (int(it["carrier"]) + 2) * 4)
		pos.append((it["node"] as Node3D).position)
	var sp := PackedVector3Array()
	for s in sparkles:
		sp.append(s[0])
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	return [pose, ids, info, pos, sp]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 5:
		return
	if vr_avatar != null:
		vr_avatar.apply_pose(s[0])
	var ids: PackedInt32Array = s[1]
	var info: PackedInt32Array = s[2]
	var pos: PackedVector3Array = s[3]
	var seen := {}
	for i in ids.size():
		var id := ids[i]
		seen[id] = true
		var kind := info[i] % 4
		var carrier := floori(info[i] / 4.0) - 2
		if not items.has(id):
			_make_item(id, kind, pos[i])
		var it: Dictionary = items[id]
		it["carrier"] = carrier
		var n: Node3D = it["node"]
		if not (carrier >= 0 and carrier < HAND_BASE and party.is_local(carrier)):
			n.position = n.position.lerp(pos[i], 0.5)
	for id in items.keys():
		if not seen.has(id):
			(items[id]["node"] as Node).queue_free()
			items.erase(id)
	_sync_sparkles(s[4])


func apply_event(kind: String, args: Array) -> void:
	_play_fx(kind, args)
