extends Node3D
## SHEEP ROUND-UP: fluffy sheep wander a green field; get them all into the pen before the clock runs out.
## TV players are sheepdogs: run near sheep to push them (A = WOOF, scares them further).
## The VR player is the giant farmer: grab a sheep with the right trigger and drop it in the pen;
## any low hand shoos sheep away, touching sheep / dogs / the fence makes them bounce.
## STORY: a storm scattered Farmer Bo's sheep over the hills. Each round is a FIELD made from a seed
## (fieldgen.gd: shut gates, low hedges, bushes, a stream with bridges, new breeds as fields get harder);
## every sheep that reaches the pen goes home to Bo's HOME FIELD north of the play field, which fills up
## and grows a barn, haystacks, a windmill... (farm.gd, saved). Every sheep home = the next field.
## The first round each day (once a field is cleared) is TODAY'S FIELD, the same on every machine.
## Networked: the host sends the field's seed + spec ("field" state); every machine rebuilds it.
## Results show by themselves, then the next round starts. One RUN telemetry line per round / quit.
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
const FieldGen := preload("res://games/sheep_round_up/fieldgen.gd")
const FieldView := preload("res://games/sheep_round_up/field_view.gd")
const Farm := preload("res://games/sheep_round_up/farm.gd")
const Seeded := preload("res://core/seeded.gd")
const Telemetry := preload("res://core/telemetry.gd")
const StoryCard := preload("res://core/story_card.gd")

const GAME_ID := "sheep_round_up"
const ARENA := FieldGen.ARENA  # field radius
const PEN := FieldGen.PEN  # pen half size (square at the centre)
const GAP := FieldGen.GAP  # half width of the gates
const DOG_SPEED := 4.8
const FLEE_SPEED := 3.0
const SCARE_R := 2.4
const BARK_R := 4.5
const INTRO := {
	"title": "SHEEP ROUND-UP",
	"goal": "Get the sheep in the pen!",
	"vr": {"role": "THE FARMER", "controls": [["TRIGGER", "Grab a sheep"], ["L-STICK", "Walk"]]},
	"tv": {"role": "THE SHEEPDOGS", "controls": [["L-STICK", "Run"], ["A", "Woof!"]]},
}

var round_time := 120.0  ## seconds per round (bots shorten it)
var results_wait := 9.0  ## seconds the results stay up before the next round starts by itself
var fresh_save := false  ## bots: start a brand-new farm
var start_level := -1  ## tests (env SRU_LEVEL): play this field level

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
var field := {}  # every machine: the field being played (fieldgen.gd)
var field_key := ""  # the seed + spec it was made from (rebuild only when it changes)
var field_node: Node3D
var farm_node: Node3D
var round_desc := {}  # host: {k: "story" / "daily", seed, spec}
var daily_due := false
var run := {}  # host: this round's numbers for telemetry
var elapsed := 0.0
var vr_story: Node3D


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
	save.defaults = Farm.save_defaults()
	add_child(save)
	if fresh_save:
		save.data = Farm.save_defaults().duplicate(true)
	if int(save.data.world) < 0:
		save.data.world = Seeded.fresh_seed()  # this family's own fields
		save.mark_dirty()
	if OS.has_environment("SRU_LEVEL"):
		start_level = int(OS.get_environment("SRU_LEVEL"))
	if start_level >= 0:
		save.data.level = start_level
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
		var dd: Dictionary = save.data.daily
		daily_due = (int(save.data.level) >= 1 and not dd.has(Seeded.today()) and not OS.has_environment("BOT_NO_DAILY")) \
			or OS.has_environment("SRU_DAILY")
		_publish_farm()
		print("Bo's farm: %d sheep at home, field %d next, daily %s (world %d)" % [int(save.data.home), int(save.data.level) + 1,
			daily_due, int(save.data.world)])
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
	# The edge: a knee-high stone wall. No bushes or trees near it any more: a follow camera sits up to
	# ~4.7 m behind its dog, and a bush there once hid half of Nathanael's view (2026-10).
	add_child(FieldView.build_edge())
	sign_label = UiKit.label3d("0 / 0", 0.42, "text", true)
	sign_label.outline_size = 26
	sign_label.position = Vector3(0.0, FieldView.SIGN_Y, -PEN - 0.24)  # reads from +Z: towards the farmer's start
	_build_pen(15)
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


## The pen for this field's open gates (the sign moves along with it).
func _build_pen(gates: int) -> void:
	if fence != null:
		fence.remove_child(sign_label)
		fence.queue_free()
	fence = FieldView.build_pen(gates)
	add_child(fence)
	fence.add_child(sign_label)


## Every machine: build the field the host picked (its seed + spec in the "field" state).
func _apply_field(desc: Dictionary) -> void:
	var key := var_to_str([desc.get("seed", 0), desc.get("spec", {})])
	if key == field_key:
		return
	field_key = key
	var t0 := Time.get_ticks_usec()
	field = FieldGen.generate(int(desc.get("seed", 0)), desc.get("spec", {}))
	var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0
	if field_node != null:
		field_node.queue_free()
	field_node = FieldView.build_field(field)
	add_child(field_node)
	_build_pen(int(field.gates))
	# Our own dogs start the new field on clear ground (other machines move theirs).
	var spots: Array = field.dogs
	for slot in dogs:
		if party.is_local(slot) or (net.mode != "client" and not net_target.has(slot)):
			var sp: Array = spots[int(slot) % spots.size()]
			(dogs[slot] as Node3D).position = Vector3(sp[0], 0.0, sp[1])
			last_pos[slot] = (dogs[slot] as Node3D).position
	if net.mode == "client" and sheep.size() == (field.sheep as Array).size():
		for i in sheep.size():
			(sheep[i] as Node).call("set_breed", int(field.sheep[i][2]))
	print("Sheep Round-Up field: %s level %d seed %d, %d sheep, gates %d, %d hedges, %d bushes, stream %s (%.1f ms, try %d)" % [
		field.name, int(field.level), int(field.seed), (field.sheep as Array).size(), int(field.gates), (field.hedges as Array).size(),
		(field.bushes as Array).size(), not (field.stream as Dictionary).is_empty(), gen_ms, int(field.attempt)])
	if net.mode != "client":
		run["gen_ms"] = snappedf(gen_ms, 0.01)


## Host: tell every machine how the home farm looks (sheep at home by breed, the field number).
func _publish_farm() -> void:
	var counts := {}
	var br: Dictionary = save.data.breeds
	for b in FieldGen.BREEDS.size():
		var n := int(br.get(String(FieldGen.BREEDS[b].id), 0))
		if n > 0:
			counts[b] = n
	net.state_set("farm", {"home": int(save.data.home), "breeds": counts, "level": int(save.data.level)})


## Every machine: rebuild Bo's home farm from the "farm" state.
func _apply_farm(fd: Dictionary) -> void:
	if farm_node != null:
		farm_node.queue_free()
	var fn := FieldView.FarmNode.new()
	fn.name = "Farm"
	add_child(fn)
	fn.setup(int(fd.get("home", 0)), fd.get("breeds", {}))
	farm_node = fn


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
			var wet := FieldGen.water_at(field, d.position.x, d.position.z)  # dogs paddle across the stream
			var p := d.position + dir * DOG_SPEED * (FieldGen.DOG_SLOW if wet else 1.0) * delta
			p.y = 0.0
			d.position = FieldGen.move_dog(field, p.limit_length(ARENA))
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
				run["barks"] = int(run.get("barks", 0)) + 1
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
			vr_banner = HudKit.vr_paused(self, vr_rig.camera, "", {"width": 1.1})
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
			var fd: Dictionary = net.state_get("field", {})
			var daily := bool((fd.get("spec", {}) as Dictionary).get("daily", false))
			var title := "TODAY'S FIELD" if daily else "FIELD %d" % (int((fd.get("spec", {}) as Dictionary).get("level", 0)) + 1)
			var sub := String(field.get("name", "")) if not field.is_empty() else "%d sheep!" % int(net.state_get("total", 0))
			HudKit.banner(_all_huds(), title, sub, {"duration": 2.4})
			if vr_rig != null:
				HudKit.vr_banner(self, vr_rig.camera, title, sub, {"duration": 2.4, "sound": ""})
			sound("whistle", -4.0)
		"field":
			_apply_field(value)
		"farm":
			_apply_farm(value)
		"phase":
			if String(value) == "results":
				_show_results(net.state_get("results", {}))
			else:
				_hide_results()


# --- Rounds -------------------------------------------------------------------------------

## Host: the next field: TODAY'S FIELD first each day, otherwise the farm's next field (a fresh layout
## of the same level after a time's-up). Every machine builds it from the seed + spec.
func _start_round() -> void:
	_clear_sheep()
	held = -1
	awards.reset()
	var players := maxi(1, party.player_count() + (1 if vr_rig != null else 0))
	if daily_due:
		daily_due = false
		round_desc = {"k": "daily", "seed": FieldGen.daily_seed(), "spec": FieldGen.daily_spec(players, round_time)}
	else:
		round_desc = Farm.next_field(save.data, players, round_time)
	run = {"barks": 0, "grabs": 0, "throws": 0, "splash": 0}
	net.state_set("field", {"seed": int(round_desc.seed), "spec": round_desc.spec})
	_apply_field(net.state_get("field", {}))
	for sp in field.sheep:
		var sh := _make_sheep(Vector3(sp[0], 0.0, sp[1]), int(sp[2]))
		sh.set("wander_t", randf_range(0.0, 1.5))
	time_left = float(field.time)
	elapsed = 0.0
	net.state_set("total", sheep.size())
	net.state_set("home", 0)
	net.state_set("time", int(ceil(time_left)))
	net.state_set("phase", "play")
	net.state_set("round", int(net.state_get("round", 0)) + 1)
	_refresh_group()
	_round_story()


## Host: Bo's words as a field starts (the first time ever, a new kind of field, today's field).
func _round_story() -> void:
	var lines: Array = []
	if not bool(save.data.met_bo):
		save.data.met_bo = true
		save.mark_dirty()
		lines.append(_bo("A storm! My sheep ran off!"))
		lines.append(_bo("Bring them home, dogs!", "sheep", FieldGen.BREEDS[0].wool))
	if String(round_desc.k) == "daily":
		lines.append(_bo("Today's field! Go go go!"))
	var lv := int(field.level)
	var tips: Array = save.data.tips
	for k in Farm.TIPS:
		if lv >= int(k) and not tips.has(int(k)) and String(round_desc.k) == "story":
			tips.append(int(k))
			save.mark_dirty()
			lines.append(_bo(String(Farm.TIPS[k][0]), String(Farm.TIPS[k][1]), Color(0.4, 0.75, 0.35)))
	_story_queue(lines, 3.0)


## Host: show story beats one after another (`first` seconds from now, then 3.6 s apart).
func _story_queue(beats: Array, first: float = 0.0) -> void:
	for i in beats.size():
		var beat: Dictionary = beats[i]
		var wait := first + i * 3.6
		if wait <= 0.0:
			_story(beat)
		else:
			get_tree().create_timer(wait).timeout.connect(func() -> void:
				if is_inside_tree():
					_story(beat))


## A story beat: Bo (or a sheep / farm picture) and a few words, on every machine.
func _story(beat: Dictionary) -> void:
	if net.mode != "client":
		net.event("story", [beat.get("who", ""), beat.get("line", ""), beat.get("pic", ""), (beat.get("color", Farm.BO_COLOR) as Color).to_html()])
	show_story(beat)


func show_story(beat: Dictionary) -> void:
	StoryCard.show(_all_huds(), beat)
	if vr_rig != null:
		if vr_story != null and is_instance_valid(vr_story):
			vr_story.queue_free()
		vr_story = StoryCard.show_vr(self, vr_rig.camera, beat)


func _bo(line: String, pic: String = "shepherd", color: Color = Farm.BO_COLOR) -> Dictionary:
	return {"who": "BO", "line": line, "pic": pic, "color": color, "duration": 3.4}


func _end_round(all_home: bool) -> void:
	var home := int(net.state_get("home", 0))
	var total := int(net.state_get("total", 0))
	var rnd := int(net.state_get("round", 1))
	var daily := String(round_desc.get("k", "")) == "daily"
	var lv := int(field.get("level", 0))
	var st := Farm.stars(all_home, time_left, float(field.get("time", round_time)))
	# Every sheep in the pen goes home to Bo's farm for good.
	var before := int(save.data.home)
	var br: Dictionary = save.data.breeds
	var beats: Array = []
	for o in sheep:
		if bool((o as Node).get("penned")):
			var b := int((o as Node).get("breed"))
			var id := String(FieldGen.BREEDS[b].id)
			br[id] = int(br.get(id, 0)) + 1
	save.data.home = before + home
	save.data.rounds = int(save.data.rounds) + 1
	if all_home and not daily:
		save.data.level = lv + 1
		var bs: Dictionary = save.data.stars
		bs[str(lv)] = maxi(int(bs.get(str(lv), 0)), st)
	if daily:
		var dd: Dictionary = save.data.daily
		dd[Seeded.today()] = maxi(int(dd.get(Seeded.today(), -1)), int(ceil(time_left)) if all_home else -home)
		while dd.size() > 30:
			var keys := dd.keys()
			keys.sort()
			dd.erase(keys[0])
	if int(save.data.level) > int(save.data["best"]):
		save.data["best"] = int(save.data.level)
		net.state_set("best", int(save.data.level))
	save.mark_dirty()
	if all_home:
		beats.append(_bo(Farm.CHEERS[int(save.data.rounds) % Farm.CHEERS.size()]))
	elif home > 0:
		beats.append(_bo("%d sheep safe! Again!" % home))
	else:
		beats.append(_bo("Nearly! Try again!"))
	for m in Farm.new_milestones(before, int(save.data.home)):
		beats.append(_bo(String(m[3]), String(m[2]), Color(0.95, 0.35, 0.3)))
	_publish_farm()
	var stats: Array = [["FIELD", "TODAY" if daily else str(lv + 1)], ["STARS", "%d / 3" % st], ["AT HOME", str(int(save.data.home))]]
	var data := awards.results({"title": "ALL HOME!" if all_home else "TIME'S UP!",
		"subtitle": "%d of %d sheep home" % [home, total], "style": "victory",
		"stats": stats, "score_format": "%d SHEEP", "max_awards": 3})
	net.state_set("results", data)
	net.state_set("phase", "results")
	results_t = 0.0
	if all_home:
		celebrate()
	_telemetry("all_home" if all_home else "time", home, total, st)
	_story_queue(beats, 1.2)
	print("Sheep Round-Up round %d: %d/%d home, %d stars, %d at the farm, next field %d" % [rnd, home, total, st,
		int(save.data.home), int(save.data.level) + 1])


func _exit_tree() -> void:
	if ready_to_play and net != null and net.mode != "client" and String(net.state_get("phase", "")) == "play" and not field.is_empty():
		_telemetry("quit", int(net.state_get("home", 0)), int(net.state_get("total", 0)), 0)


## One RUN line per round (or quit mid-round): how the family really herds (balance).
func _telemetry(end: String, home: int, total: int, st: int) -> void:
	if net.mode == "client" or field.is_empty():
		return
	var info := run.duplicate()
	info.merge({"end": end, "mode": net.mode, "flat_host": flat_host, "vr": vr_rig != null,
		"players": party.player_count() + (1 if vr_rig != null else 0), "kind": String(round_desc.get("k", "")),
		"seed": int(field.seed), "level": int(field.level), "name": String(field.name), "sheep": total, "home": home,
		"time": int(field.time), "played_s": int(elapsed), "left_s": int(maxf(0.0, time_left)), "stars": st,
		"gates": int(field.gates), "hedges": (field.hedges as Array).size(), "bushes": (field.bushes as Array).size(),
		"stream": not (field.stream as Dictionary).is_empty(), "try": int(field.attempt),
		"farm": int(save.data.home), "next_level": int(save.data.level)}, true)
	Telemetry.run(GAME_ID, info)


## Every machine: confetti over the pen when the whole flock is home.
func celebrate() -> void:
	for k in 3:
		burst(Vector3(randf_range(-1.0, 1.0), 1.2 + k * 0.4, randf_range(-1.0, 1.0)), Color.from_hsv(randf(), 0.7, 1.0), 26)
	sfx.play("party_horn")
	if farm_node != null and is_instance_valid(farm_node):
		farm_node.call("cheer")
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

func _make_sheep(pos: Vector3, breed: int = 0) -> Node3D:
	var s: Node3D = SheepScript.new()
	s.position = pos
	s.set("breed", breed)
	add_child(s)
	sheep.append(s)
	return s


func _clear_sheep() -> void:
	for s in sheep:
		(s as Node).queue_free()
	sheep.clear()


static func in_pen(p: Vector3, margin: float = 0.0) -> bool:
	return FieldGen.in_pen(p, margin)


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
		var bd: Dictionary = FieldGen.BREEDS[int(s.get("breed"))]
		var spd := float(bd.speed)
		if not penned:
			var push := Vector3.ZERO
			var herder := -1  # the dog pushing hardest towards the pen gets the credit
			var herd_best := 0.0
			var to_pen := -Vector3(s.position.x, 0.0, s.position.z).normalized()
			for slot in dogs:
				var dp: Vector3 = (dogs[slot] as Node3D).position
				var r := (BARK_R if float(bark_t.get(slot, 0.0)) > 0.0 else SCARE_R) * float(bd.scare)
				var away := s.position - dp
				away.y = 0.0
				var dd := away.length()
				if dd < r and dd > 0.001:
					var f := away / dd * (1.0 - dd / r) * (2.0 if float(bark_t.get(slot, 0.0)) > 0.0 else 1.0)
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
				want = push.normalized() * FLEE_SPEED * spd * clampf(push.length() * 1.6, 0.5, 1.4)
		if not scared:
			var wt: float = float(s.get("wander_t")) - delta
			if wt <= 0.0:
				var wander := float(bd.wander)
				wt = randf_range(1.5, 4.0) / (1.0 + wander)
				var a := randf() * TAU
				s.set("wander_dir", Vector3(cos(a), 0.0, sin(a)) * (wander if randf() < 0.45 + wander * 0.3 else 0.0))
			s.set("wander_t", wt)
			want = s.get("wander_dir")
			if int(s.get("breed")) == FieldGen.LAMB and not penned:
				want += _to_mum(s) * 0.6  # lambs stay close to a grown-up sheep
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
			to = FieldGen.fence_block(s.position, to, int(field.get("gates", 15)))
			to = FieldGen.move_sheep(field, s.position, to)
			if to.length() > ARENA - 0.3:
				to = to.limit_length(ARENA - 0.3)
				vel = -vel * 0.3
		s.position = to
		s.set("vel", vel)
		if not penned and in_pen(to, 0.3):
			_pen_sheep(i)
	_vr_hands()


## A lamb's pull towards the nearest grown-up sheep outside the pen (zero when one is close or none).
func _to_mum(s: Node3D) -> Vector3:
	var best: Node3D = null
	var bd := 3.5
	for o in sheep:
		var m: Node3D = o
		if m == s or int(m.get("breed")) == FieldGen.LAMB or bool(m.get("penned")):
			continue
		var d := m.position.distance_to(s.position)
		if d < bd:
			bd = d
			best = m
	if best == null or bd < 0.9:
		return Vector3.ZERO
	var v := best.position - s.position
	v.y = 0.0
	return v.normalized()


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
			var dry := FieldGen.move_sheep(field, p, p)  # out of a hedge / bush / the stream
			if FieldGen.water_at(field, p.x, p.z):
				sheep_fx(p, "splash")
				run["splash"] = int(run.get("splash", 0)) + 1
			else:
				sheep_fx(p, "baa")
			p.x = dry.x
			p.z = dry.z
	s.position = p
	s.set("vel", vel)


func _pen_sheep(i: int) -> void:
	var s: Node3D = sheep[i]
	s.set("penned", true)
	var by: int = s.get("last_by")
	if results_showing():
		sheep_fx(s.position, "baa")
		return
	var b := int(s.get("breed"))
	if by >= 0:
		awards.add(by, "score", float(FieldGen.BREEDS[b].pts))
	var id := String(FieldGen.BREEDS[b].id)
	if b != FieldGen.WHITE and not (save.data.breeds as Dictionary).has(id) and not run.has("new_" + id):
		run["new_" + id] = true  # the first one ever: Bo meets a new breed
		_story(_bo(String(FieldGen.BREEDS[b].line), "sheep", FieldGen.BREEDS[b].wool))
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
		"splash":
			sfx.play_at("splash", pos, -2.0, randf_range(0.9, 1.2))
			burst(pos + Vector3.UP * 0.2, Color(0.55, 0.8, 1.0), 16)
			if s != null:
				s.call("boing", 1.0)
		"home":
			sfx.play_at("baa", pos, 2.0, 1.3)
			sfx.play("ding", -2.0, 1.0 + 0.05 * float(net.state_get("home", 0)))
			burst(pos + Vector3.UP * 0.4, Color(1.0, 0.9, 0.3), 18)
			var pts := 1 if s == null else int(FieldGen.BREEDS[int(s.get("breed"))].pts)
			HudKit.score(self, pos + Vector3.UP * 0.7, pts, {"color": party.color_of(by) if by >= 0 else "gold", "size": 1.4 + 0.1 * pts})
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
		run["grabs"] = int(run.get("grabs", 0)) + 1
		var s: Node3D = sheep[near]
		s.set("state", SheepScript.HELD)
		s.set("last_by", 0)
		vr_rig.pulse(VrRig.RIGHT, 0.6, 0.08)
		sheep_fx(s.position, "baa")
		sfx.play("pop", -6.0)
	elif held >= 0 and (not vr_rig.trigger_down() or not playing):
		var s: Node3D = sheep[held]
		held = -1
		run["throws"] = int(run.get("throws", 0)) + 1
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
	elapsed += delta
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
		var fs: Array = field.get("sheep", [])
		for i in pos.size():
			_make_sheep(pos[i], int(fs[i][2]) if fs.size() == pos.size() else 0)
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
		"story":
			show_story({"who": String(args[0]), "line": String(args[1]), "pic": String(args[2]), "color": Color.html(String(args[3])), "duration": 3.4})
