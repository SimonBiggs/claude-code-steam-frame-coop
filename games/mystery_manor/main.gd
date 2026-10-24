extends Node3D
## MYSTERY MANOR: a cosy "who took it?" in a spooky old house, played like Guess Who (no reading).
## Something is missing! Six suspects wait in the grand hall, each with a hat and a coat colour.
## Sparkling clues are hidden around the manor: a scrap of the culprit's coat and the culprit's
## dropped hat (and the missing thing itself). Find a clue and every suspect who doesn't match steps
## back. When one suspect is left, walk up and press A (TV) or tap them (VR): CASE SOLVED!
## Guessing early is allowed; a wrong guess clears that suspect but costs a star.
## VR: the detective walks the manor (left stick, snap turn on the right), stairs blink you up or down,
## clues are picked up by walking to them, suspects are accused with a tap of the glove.
## TV / Deck: assistants run around in third person (split views), A accuses the suspect you stand by.
## Files: manor.gd (house layout, meshes, collision, nav grid), furniture.gd (props), case.gd (cases +
## deduction checker). Engine: core/party.gd, split_view, camera_rig, vr_rig, the state store, net.request,
## save, hud_kit, hints, awards, creatures, sky_kit. Many machines: any number of TV machines and Decks;
## a flat host (no VR) plays slot 0 itself.

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
const Manor := preload("res://games/mystery_manor/manor.gd")
const Case := preload("res://games/mystery_manor/case.gd")

const GAME_ID := "mystery_manor"
const PICK_RANGE := 1.3  ## walk this close to a clue to pick it up
const ACCUSE_RANGE := 1.5  ## stand this close to a suspect to accuse them (TV)
const HINT_AFTER := 45.0  ## seconds without progress before a light beam shows the way
const INTRO_TIME := 4.0
const SOLVED_TIME := 6.0
const RESULTS_AUTO := 40.0
const LOOKS: Array[String] = ["detective", "detective", "scientist", "detective", "archer", "detective", "pilot"]
const INTRO := {
	"title": "MYSTERY MANOR",
	"goal": "Something is missing! Find the sparkly clues, then catch who did it.",
	"vr": {"role": "THE DETECTIVE", "controls": [["L-STICK", "Walk"], ["R-STICK", "Turn"], ["WALK TO", "a sparkle"], ["TAP", "the one who did it"]]},
	"tv": {"role": "THE ASSISTANTS", "controls": [["L-STICK", "Run"], ["R-STICK", "Look"], ["A", "That's the one!"], ["START", "Pause"]],
		"tips": ["Clues make suspects step back."]},
}

var walk_speed := 3.6  ## bots speed it up

# --- The networking contract (see docs/engine/systems.md) ---
var net: Node
var ready_to_play := false
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

var flat_host := false
var manor: Manor.ManorNode
var avatars := {}  # slot -> Node3D (TV players, every machine)
var last_pos := {}
var net_target := {}  # slot -> [pos, yaw]
var cams := {}  # slot -> CameraRig
var huds := {}  # slot -> UiKit root
var hud_parts := {}  # slot -> {clues: Array[PanelContainer], people: Array[Control], prompt: Control}
var vr_avatar: VrRig.Avatar
var vr_banner: Node3D
var tv_banner: Control
var results_ui: Control
var vr_results: Node
var send_t := 0.0
# The case on screen (every machine builds it from the state store)
var case_seed := -1
var suspects: Array[Node3D] = []
var suspect_home: Array[Vector3] = []
var rings: Array[MeshInstance3D] = []
var clue_nodes: Array[Node3D] = []  # colour, hat, item (in the house)
var table_nodes: Array[Node3D] = []  # everything else this case built (board title, evidence)
var evidence: Array[Node3D] = []  # the clues on the evidence table once found
var beam: MeshInstance3D
var flash_t := 8.0
var vr_touch_t := 0.0
# Host / local
var phase_t := 0.0
var idle_t := 0.0  # seconds since the last clue (hint beam)


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
	if net.machine_kind == "deck":
		party.allow_keyboard = false  # a Steam Deck: one player on its built-in controls; more pads may drop in
	party.player_joined.connect(_on_player_joined)
	party.player_left.connect(_on_player_left)
	save = Save.new()
	save.game_id = GAME_ID
	save.defaults = {"solved": 0, "stars": 0}
	add_child(save)
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("mystery")
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
		vr_rig.bounds = Rect2(-15.4, -27.4, 30.8, 34.8)
		vr_rig.move_filter = func(from: Vector3, to: Vector3) -> Vector3: return _slide(from, to)
		add_child(vr_rig)
		vr_rig.place(Manor.VR_SPAWN, Manor.VR_SPAWN_YAW)
		hints.set_vr_rig(vr_rig, self)
	SkyKit.apply(self, "night", vr_rig != null)
	manor = Manor.build(self, vr_rig != null)
	manor.culling = vr_rig != null
	_build_beam()
	if mode != "host" or flat_host:
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		var gc := CameraRig.new()
		gc.camera = split.shared_camera()
		add_child(gc)
		gc.shot_look(Vector3(4.0, 3.0, 6.5), Vector3(-2.0, 1.0, 1.0), 0.0)  # the line-up, while nobody plays here
		_make_hud(-1, split.shared_hud())
		hints.add_view(huds[-1], -1)
		if vr_rig != null:
			split.set_bubble(vr_rig.mirror)
	party.allow_slot0 = (mode == "local" and vr_rig == null) or flat_host
	if mode != "client":
		net.state_set("vr", vr_rig != null)
		_new_case()
	hints.intro(INTRO, {"duration": 9.0})
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	_apply_case()
	print("Mystery Manor: %s mode%s" % [mode, " with a VR player" if vr_rig != null else ""])


## Move from `from` towards `to` without walking through walls or furniture (slides along them).
func _slide(from: Vector3, to: Vector3) -> Vector3:
	if manor == null or manor.walkable(to):
		return to
	var tx := Vector3(to.x, to.y, from.z)
	if manor.walkable(tx):
		return tx
	var tz := Vector3(from.x, to.y, to.z)
	if manor.walkable(tz):
		return tz
	return from


# --- The case: suspects, clues, evidence table (every machine, from the store) -------------------

func _apply_case() -> void:
	var c: Dictionary = net.state_get("case", {})
	if c.is_empty() or not ready_to_play:
		return
	if int(c["seed"]) != case_seed:
		case_seed = int(c["seed"])
		_build_case(c)
	_refresh_case()


## gdev calls this after reloading this script: rebuild the case's nodes with the new code.
func _on_hot_reload() -> void:
	case_seed = -1
	_apply_case()


func _build_case(c: Dictionary) -> void:
	for n in suspects + clue_nodes + table_nodes:
		(n as Node).queue_free()
	for r in rings:
		r.queue_free()
	suspects.clear()
	suspect_home.clear()
	rings.clear()
	clue_nodes.clear()
	table_nodes.clear()
	evidence.clear()
	for i in (c["suspects"] as Array).size():
		var s := Creatures.humanoid({"class": "villager", "hat": Case.hat_of(c, i), "outfit": Case.colour_of(c, i),
			"outfit2": Case.colour_of(c, i).lightened(0.3), "seed": int(c["seed"]) + i * 7, "weapon": "none", "offhand": "none"})
		s.name = "Suspect%d" % i
		var home: Vector3 = Manor.GATHER[i]
		s.position = home
		s.rotation.y = PI * 0.5  # creatures face +Z: turn them to face +X, into the hall
		add_child(s)
		suspects.append(s)
		suspect_home.append(home)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.38
		tm.outer_radius = 0.48
		tm.rings = 24
		tm.ring_segments = 6
		ring.mesh = tm
		ring.position = home + Vector3.UP * 0.03
		add_child(ring)
		rings.append(ring)
	# the case board: what is missing, in words and as a picture
	var title := UiKit.label3d(Case.title(c), 0.11, "gold", true, 2.2)
	title.position = Manor.HALL_BOARD_POS + Vector3(0.08, 0.5, 0.0)
	title.rotation.y = PI * 0.5  # a Label3D reads from +Z: turn it to face +X, into the hall
	add_child(title)
	table_nodes.append(title)
	var pic := _make_item(String((Case.ITEMS[int(c["item"])] as Dictionary)["id"]))
	pic.position = Manor.HALL_BOARD_POS + Vector3(0.25, -0.35, 0.0)
	pic.scale *= 1.6
	add_child(pic)
	table_nodes.append(pic)
	var spots: Array = c["spots"]
	for k in 3:
		var sp: Dictionary = Manor.SPOTS[int(spots[k])]
		var stand: Vector3 = sp["stand"]
		var at: Vector3 = sp["pos"]
		var p := at.lerp(Vector3(stand.x, at.y, stand.z), 0.45)
		p.y = maxf(at.y, Manor.LEVEL_Y[Manor.level_of_y(at.y)] + 0.7)
		var n := _clue_node(c, k, true)
		n.position = p
		add_child(n)
		clue_nodes.append(n)
		var t := _clue_node(c, k, false)
		t.position = Manor.EVIDENCE_TABLE + Vector3(0.0, 0.12, -0.45 + 0.45 * k)
		add_child(t)
		table_nodes.append(t)
		evidence.append(t)


## A clue: the coat scrap, the hat or the missing thing; `sparkly` adds the sparkles and the bobbing.
func _clue_node(c: Dictionary, k: int, sparkly: bool) -> Node3D:
	var root := Node3D.new()
	var culprit := int(c["culprit"])
	match k:
		Case.CLUE_COLOUR:
			var b := MeshKit.Builder.new()
			var col := Case.colour_of(c, culprit)
			b.box(Vector3(0.34, 0.025, 0.24), MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(0.0, 0.4, 0.1)), col)
			b.box(Vector3(0.16, 0.025, 0.12), MeshKit.at(Vector3(0.2, 0.01, 0.12), Vector3.ONE, Vector3(0.0, -0.6, -0.1)), col.darkened(0.15))
			root.add_child(MeshKit.instance(b.build(), false))
		Case.CLUE_HAT:
			var hat := MeshKit.instance(Creatures.hat_mesh(Case.hat_of(c, culprit)), false)
			hat.scale = Vector3.ONE * 1.3
			hat.position = -Creatures.HC * 1.3
			root.add_child(hat)
		Case.CLUE_ITEM:
			root.add_child(_make_item(String((Case.ITEMS[int(c["item"])] as Dictionary)["id"])))
	if sparkly:
		var p := CPUParticles3D.new()
		p.amount = 14
		p.lifetime = 1.2
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.35
		p.gravity = Vector3(0.0, 0.4, 0.0)
		p.initial_velocity_min = 0.05
		p.initial_velocity_max = 0.2
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.0
		var qm := QuadMesh.new()
		qm.size = Vector2.ONE * 0.06
		var mat := MeshKit.glow_material()
		qm.material = mat
		p.mesh = qm
		root.add_child(p)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.9, 0.5)
		light.omni_range = 1.6
		light.light_energy = 0.8
		light.shadow_enabled = false
		root.add_child(light)
		root.set_meta("sparkly", true)
	return root


## The missing thing (about 0.4 m).
func _make_item(id: String) -> Node3D:
	if id == "cake":
		var b := MeshKit.Builder.new()
		b.cylinder(0.2, 0.2, 0.14, MeshKit.at(Vector3(0.0, 0.07, 0.0)), Color(0.98, 0.75, 0.82), 20)
		b.cylinder(0.14, 0.14, 0.12, MeshKit.at(Vector3(0.0, 0.2, 0.0)), Color(1.0, 0.96, 0.9), 20)
		b.sphere(0.04, MeshKit.at(Vector3(0.0, 0.3, 0.0)), Color(0.9, 0.1, 0.15), 10)
		b.cylinder(0.205, 0.205, 0.02, MeshKit.at(Vector3(0.0, 0.135, 0.0)), Color(1.0, 1.0, 1.0), 20)
		return MeshKit.instance(b.build(), false)
	var mi := MeshKit.instance(MeshKit.prop(id), false)
	var scales := {"gem": 0.7, "chest": 0.45, "star": 0.6, "candle": 0.9, "heart": 0.6}
	mi.scale = Vector3.ONE * float(scales.get(id, 0.5))
	return mi


## Who is still a suspect: matching the clues found, and not wrongly accused.
func _still_suspects(c: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var cleared: Array = net.state_get("cleared", [])
	for i in Case.fits(c, net.state_get("found", [false, false, false])):
		if not cleared.has(i):
			out.append(i)
	return out


func _refresh_case() -> void:
	var c: Dictionary = net.state_get("case", {})
	if c.is_empty() or suspects.is_empty():
		return
	var found: Array = net.state_get("found", [false, false, false])
	var left := _still_suspects(c)
	var solved := String(net.state_get("phase", "")) in ["solved", "results"]
	for i in suspects.size():
		var still := left.has(i)
		var target := suspect_home[i] + (Vector3.ZERO if still else Vector3(-0.9, 0.0, 0.0))
		if solved and i == int(c["culprit"]):
			target = Manor.GATHER_CULPRIT + Vector3(0.6, 0.0, 0.0)
		suspects[i].set_meta("target", target)
		var col := Color(1.0, 0.82, 0.3) if still else Color(0.25, 0.25, 0.3)
		if solved:
			col = Color(1.0, 0.82, 0.3) if i == int(c["culprit"]) else Color(0.25, 0.25, 0.3)
		rings[i].material_override = MeshKit.material(col, 1.2 if col.v > 0.5 else 0.0)
	for k in mini(clue_nodes.size(), evidence.size()):
		var got := k < found.size() and bool(found[k])
		clue_nodes[k].visible = not got
		evidence[k].visible = got
	_refresh_beam()
	_refresh_huds()


# --- Hint beam -------------------------------------------------------------------------------

func _build_beam() -> void:
	beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.18
	cm.height = 3.3
	cm.radial_segments = 12
	beam.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.85, 0.4, 0.35)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = m
	beam.visible = false
	add_child(beam)


func _refresh_beam() -> void:
	var h := int(net.state_get("hint", -1))
	beam.visible = h >= 0 and h < clue_nodes.size() and clue_nodes[h].visible
	if beam.visible:
		var p := clue_nodes[h].position
		beam.position = Vector3(p.x, Manor.LEVEL_Y[Manor.level_of_y(p.y)] + 1.65, p.z)


# --- HUD (per TV view) -------------------------------------------------------------------------

func _make_hud(slot: int, parent: Control) -> void:
	var ui := UiKit.ui_root(parent)
	huds[slot] = ui
	var card := UiKit.panel("card")
	ui.add_child(card)
	card.position = Vector2(20.0, 18.0)
	var v := UiKit.vbox(8)
	card.add_child(v)
	var row := UiKit.hbox(8)
	v.add_child(row)
	if slot >= 0:
		row.add_child(UiKit.badge(party.name_of(slot), slot))
	var clues: Array[PanelContainer] = []
	for k in 3:
		var p := UiKit.panel("pill")
		p.custom_minimum_size = Vector2(52.0, 52.0)
		row.add_child(p)
		clues.append(p)
	var people_row := UiKit.hbox(2)
	v.add_child(people_row)
	var people: Array[Control] = []
	for i in 6:
		var ic := UiKit.icon("person", "text", 34.0)
		people_row.add_child(ic)
		people.append(ic)
	var prompt := UiKit.panel("pill")
	prompt.add_child(UiKit.prompts([["A", "That's the one!"]]))
	ui.add_child(prompt)
	UiKit.pin(prompt, Control.PRESET_CENTER_BOTTOM)
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt.offset_top = -40.0
	prompt.offset_bottom = -40.0
	prompt.visible = false
	hud_parts[slot] = {"clues": clues, "people": people, "prompt": prompt}
	if slot < 0:
		var join := UiKit.panel("pill")
		join.add_child(UiKit.prompts([["A", "Join the case"]]))
		ui.add_child(join)
		UiKit.pin(join, Control.PRESET_CENTER)
		join.grow_horizontal = Control.GROW_DIRECTION_BOTH
		join.grow_vertical = Control.GROW_DIRECTION_BOTH
		hud_parts[slot]["join"] = join
	_refresh_huds()


func _refresh_huds() -> void:
	var c: Dictionary = net.state_get("case", {})
	if c.is_empty():
		return
	var found: Array = net.state_get("found", [false, false, false])
	var left := _still_suspects(c)
	for slot in hud_parts:
		var parts: Dictionary = hud_parts[slot]
		var clues: Array = parts["clues"]
		for k in 3:
			var p: PanelContainer = clues[k]
			if not is_instance_valid(p):
				continue
			for ch in p.get_children():
				ch.queue_free()
			var got := k < found.size() and bool(found[k])
			if not got:
				p.add_child(UiKit.icon("question", "dim", 30.0))
			elif k == Case.CLUE_COLOUR:
				var sw := ColorRect.new()
				sw.color = Case.colour_of(c, int(c["culprit"]))
				sw.custom_minimum_size = Vector2(30.0, 30.0)
				sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
				p.add_child(sw)
			elif k == Case.CLUE_HAT:
				p.add_child(UiKit.icon("crown", "gold", 30.0))
			else:
				p.add_child(UiKit.icon("gem", "gold", 30.0))
		var people: Array = parts["people"]
		for i in people.size():
			var ic: Control = people[i]
			if not is_instance_valid(ic):
				continue
			ic.set("color", Case.colour_of(c, i))
			ic.modulate = Color(1, 1, 1, 1.0 if left.has(i) else 0.2)
			ic.queue_redraw()
		if parts.has("join"):
			(parts["join"] as Control).visible = party.local_slots().is_empty()


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
		var cr := CameraRig.new()
		cr.camera = split.camera(slot)
		cr.party = party
		cr.slot = slot
		cr.pivot_height = 1.0
		cr.pitch = -0.4
		cr.collision_mask = 1
		add_child(cr)
		cr.follow(a, 3.6, 0.0)
		cams[slot] = cr
		_make_hud(slot, split.hud(slot))
		hints.add_view(huds[slot], slot)
		hints.hint("sparkle", "Find the sparkles!", {"to": slot, "icon": "eye"})
	awards.set_player(slot, party.name_of(slot))
	_refresh_huds()
	sound("ui_notify", -6.0)


func _on_player_left(slot: int) -> void:
	for d in [avatars, cams]:
		var dict: Dictionary = d
		if dict.has(slot):
			(dict[slot] as Node).queue_free()
			dict.erase(slot)
	last_pos.erase(slot)
	net_target.erase(slot)
	if huds.has(slot):
		var h: Control = huds[slot]
		if is_instance_valid(h):
			h.queue_free()
		huds.erase(slot)
	hud_parts.erase(slot)
	hints.remove_view(slot)


func _ensure_avatar(slot: int) -> Node3D:
	if avatars.has(slot) and is_instance_valid(avatars[slot]):
		return avatars[slot]
	var a := Creatures.humanoid({"class": LOOKS[slot % LOOKS.size()], "outfit": party.color_of(slot), "seed": 50 + slot})
	a.name = "Avatar%d" % slot
	add_child(a)
	a.position = Manor.TV_SPAWNS[slot % Manor.TV_SPAWNS.size()]
	HudKit.nameplate(a, party.name_of(slot), slot, Creatures.height_of(a) + 0.35, 0.18)
	avatars[slot] = a
	last_pos[slot] = a.position
	return a


## Local TV players run with their left stick (relative to their camera) and accuse with A.
func _move_local_players(delta: float) -> void:
	send_t -= delta
	var send := send_t <= 0.0
	if send:
		send_t = 1.0 / 30.0
	var playing := String(net.state_get("phase", "")) == "play"
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
			a.position = _slide(a.position, a.position + dir * walk_speed * delta)
			Creatures.anim(a).face(dir)
		_portal(a)
		if net.mode == "client" and send:
			net.send_state(a.position, a.rotation.y, 0.0, slot)
		var near := _suspect_near(a.position, ACCUSE_RANGE)
		var parts: Dictionary = hud_parts.get(slot, {})
		if parts.has("prompt"):
			(parts["prompt"] as Control).visible = playing and near >= 0
		if playing and near >= 0 and party.just_pressed(slot, "accept") and not net.just_unpaused():
			net.request(slot, "accuse", [near])


## Walked into the stairs: blink up or down.
func _portal(a: Node3D) -> void:
	for p in Manor.PORTALS:
		var pp: Dictionary = p
		var z: Vector3 = pp["zone"]
		if Manor.level_of_y(a.position.y) == Manor.level_of_y(z.y) and Vector2(a.position.x - z.x, a.position.z - z.z).length() < float(pp["r"]):
			a.position = pp["to"]
			a.rotation.y = float(pp["yaw"])
			sound("whoosh", -6.0)
			var slot: Variant = avatars.find_key(a)
			if slot != null and cams.has(slot):
				(cams[slot] as CameraRig).snap()
			return


## The nearest suspect still in the line-up within `r` of p (-1 = none).
func _suspect_near(p: Vector3, r: float) -> int:
	var c: Dictionary = net.state_get("case", {})
	if c.is_empty():
		return -1
	var best := -1
	var bd := r
	for i in _still_suspects(c):
		if i >= suspects.size():
			continue
		var d := Vector2(suspects[i].position.x - p.x, suspects[i].position.z - p.z).length()
		if d < bd and absf(suspects[i].position.y - p.y) < 2.0:
			bd = d
			best = i
	return best


func _animate(delta: float) -> void:
	for slot in avatars:
		var a: Node3D = avatars[slot]
		var prev: Vector3 = last_pos.get(slot, a.position)
		var v := Vector2(a.position.x - prev.x, a.position.z - prev.z).length() / maxf(delta, 0.001)
		Creatures.anim(a).walk(v if v > 0.3 and v < 30.0 else 0.0)
		last_pos[slot] = a.position
	for i in suspects.size():
		var s := suspects[i]
		rings[i].position = s.position + Vector3.UP * 0.03  # the ring goes where the suspect goes
		var t: Vector3 = s.get_meta("target", s.position)
		var d := t - s.position
		if d.length() > 0.02:
			s.position = s.position.move_toward(t, 1.5 * delta)
			Creatures.anim(s).walk(1.5)
		else:
			Creatures.anim(s).walk(0.0)
	for n in clue_nodes:
		if n.visible:
			n.rotation.y += delta * 1.2
			(n.get_child(0) as Node3D).position.y = sin(Time.get_ticks_msec() * 0.003) * 0.05


func on_remote_state(slot: int, pos: Vector3, yaw: float, _pitch: float) -> void:
	if avatars.has(slot) and not party.is_local(slot):
		if not net_target.has(slot) or (avatars[slot] as Node3D).position.distance_to(pos) > 3.0:
			(avatars[slot] as Node3D).position = pos  # first update, or the stairs: no glide
		net_target[slot] = [pos, yaw]


func _follow_remote(delta: float) -> void:
	var k := 1.0 - exp(-18.0 * delta)
	for slot in net_target:
		if not avatars.has(slot) or party.is_local(slot):
			continue
		var a: Node3D = avatars[slot]
		var t: Array = net_target[slot]
		a.position = a.position.lerp(t[0], k)
		a.rotation.y = lerp_angle(a.rotation.y, float(t[1]), k)


func on_machine_left(peer: int) -> void:
	for slot in party.slots_of(peer):
		net_target.erase(slot)


# --- VR detective -------------------------------------------------------------------------

func _vr_update(delta: float) -> void:
	var head := vr_rig.head_position()
	var feet := Vector3(head.x, vr_rig.floor_height, head.z)
	manor.cull_for(feet)
	for p in Manor.PORTALS:
		var pp: Dictionary = p
		var z: Vector3 = pp["zone"]
		if Manor.level_of_y(feet.y) == Manor.level_of_y(z.y) and Vector2(feet.x - z.x, feet.z - z.z).length() < float(pp["r"]):
			vr_rig.place(pp["to"], float(pp["yaw"]))
			sound("whoosh", -6.0)
			break
	vr_touch_t = maxf(0.0, vr_touch_t - delta)
	if String(net.state_get("phase", "")) != "play" or vr_touch_t > 0.0:
		return
	var c: Dictionary = net.state_get("case", {})
	for i in _still_suspects(c):
		var s := suspects[i]
		var chest := s.position + Vector3.UP * 0.65
		var h := vr_rig.touching_any(chest, 0.42)
		if h < 0 and vr_rig.trigger_pressed() and _suspect_near(feet, ACCUSE_RANGE) == i:
			h = VrRig.RIGHT
		if h >= 0:
			vr_touch_t = 1.0
			vr_rig.pulse(h, 0.6, 0.1)
			on_request(0, "accuse", [i])
			return


# --- The game loop ------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if split != null:
		_move_local_players(delta)
	_follow_remote(delta)
	_animate(delta)
	if vr_rig != null:
		_vr_update(delta)
	_lightning(delta)
	if net.mode != "client":
		_run_case(delta)


## A storm outside: the windows flash now and then (soft thunder).
func _lightning(delta: float) -> void:
	flash_t -= delta
	if flash_t <= 0.0:
		flash_t = randf_range(14.0, 26.0)
		manor.set_flash(1.0)
		get_tree().create_timer(0.9).timeout.connect(func() -> void: sound("crash", -22.0, 0.5))
	elif manor.flash > 0.0:
		manor.set_flash(maxf(0.0, manor.flash - delta * 3.0))


func _run_case(delta: float) -> void:
	phase_t += delta
	match String(net.state_get("phase", "")):
		"intro":
			if phase_t > INTRO_TIME:
				_set_phase("play")
		"play":
			idle_t += delta
			_check_finds()
			if idle_t > HINT_AFTER and int(net.state_get("hint", -1)) < 0:
				var found: Array = net.state_get("found", [false, false, false])
				for k in 3:
					if not bool(found[k]):
						net.state_set("hint", k)
						break
		"solved":
			if phase_t > SOLVED_TIME:
				_end_case()
		"results":
			if phase_t > RESULTS_AUTO:
				_new_case()


func _set_phase(p: String) -> void:
	net.state_set("phase", p)
	phase_t = 0.0


func _new_case() -> void:
	var c := Case.generate(randi())
	while Case.check(c) != "":
		c = Case.generate(randi())
	awards.reset()
	net.state_set("found", [false, false, false])
	net.state_set("cleared", [])
	net.state_set("wrong", 0)
	net.state_set("hint", -1)
	net.state_set("case", c)
	net.state_set("cases", int(net.state_get("cases", 0)) + 1)
	idle_t = 0.0
	_set_phase("intro")


## Host: anyone close to a clue picks it up (TV players by walking, the VR detective by walking or reaching).
func _check_finds() -> void:
	var c: Dictionary = net.state_get("case", {})
	var found: Array = (net.state_get("found", [false, false, false]) as Array).duplicate()
	for k in 3:
		if bool(found[k]) or k >= clue_nodes.size():
			continue
		var p := clue_nodes[k].position
		var who := -1
		for slot in avatars:
			var a: Node3D = avatars[slot]
			if absf(a.position.y - p.y) < 2.0 and Vector2(a.position.x - p.x, a.position.z - p.z).length() < PICK_RANGE:
				who = int(slot)
		if who < 0 and vr_rig != null:
			var head := vr_rig.head_position()
			if (absf(vr_rig.floor_height - p.y) < 2.0 and Vector2(head.x - p.x, head.z - p.z).length() < PICK_RANGE) or vr_rig.touching_any(p, 0.35) >= 0:
				who = 0
		if who >= 0:
			found[k] = true
			net.state_set("found", found)
			net.state_set("hint", -1)
			idle_t = 0.0
			awards.add(who, "clues")
			awards.add(who, "score", 100)
			net.event("found", [k, who, p])
			on_found(k, who, p)
			if c.size() > 0 and _still_suspects(c).size() == 1:
				net.event("one_left", [])
				on_one_left()


## Host / local: requests from any machine.
func on_request(slot: int, action: String, args: Array) -> void:
	match action:
		"accuse":
			if String(net.state_get("phase", "")) != "play" or args.is_empty():
				return
			var c: Dictionary = net.state_get("case", {})
			var i := int(args[0])
			if not _still_suspects(c).has(i):
				return
			if i == int(c["culprit"]):
				awards.add(slot, "score", 300)
				awards.add(slot, "solved")
				net.state_set("solved_by", slot)
				_set_phase("solved")
			else:
				var cleared: Array = (net.state_get("cleared", []) as Array).duplicate()
				cleared.append(i)
				net.state_set("cleared", cleared)
				net.state_set("wrong", int(net.state_get("wrong", 0)) + 1)
				net.event("nope", [i])
				on_nope(i)
		"next_case":
			if String(net.state_get("phase", "")) == "results":
				_new_case()


func _end_case() -> void:
	var stars := maxi(1, 3 - int(net.state_get("wrong", 0)))
	var found: Array = net.state_get("found", [false, false, false])
	save.data["solved"] = int(save.data["solved"]) + 1
	save.data["stars"] = int(save.data["stars"]) + stars
	save.mark_dirty()
	var c: Dictionary = net.state_get("case", {})
	var data := awards.results({"title": "CASE SOLVED!", "subtitle": Case.title(c), "style": "victory",
		"stats": [["STARS", "%d / 3" % stars], ["CLUES", "%d / 3" % found.count(true)], ["CASES SOLVED", str(int(save.data["solved"]))]],
		"score_format": "%d PTS", "continue": "Next case"})
	net.state_set("results", data)
	_set_phase("results")


## True while the results are on screen (bots).
func results_showing() -> bool:
	return String(net.state_get("phase", "")) == "results"


# --- What every machine shows ----------------------------------------------------------------

func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"case", "found", "cleared", "hint":
			_apply_case()
		"phase":
			_on_phase(String(value))


func _on_phase(p: String) -> void:
	_apply_case()
	match p:
		"intro":
			_hide_results()
			var c: Dictionary = net.state_get("case", {})
			HudKit.banner(_all_huds(), Case.title(c), "Find the clues!", {"duration": INTRO_TIME, "style": "boss"})
			if vr_rig != null:
				HudKit.vr_banner(self, vr_rig.camera, Case.title(c), "Find the clues!", {"duration": INTRO_TIME, "sound": ""})
				vr_rig.place(Manor.VR_SPAWN, Manor.VR_SPAWN_YAW)
			for slot in party.local_slots():
				if avatars.has(slot):
					(avatars[slot] as Node3D).position = Manor.TV_SPAWNS[slot % Manor.TV_SPAWNS.size()]
					if cams.has(slot):
						(cams[slot] as CameraRig).snap()
			music.play_mood("mystery")
		"solved":
			var c2: Dictionary = net.state_get("case", {})
			var culprit := int(c2["culprit"])
			if culprit < suspects.size():
				var s := suspects[culprit]
				Creatures.anim(s).play("victory", 2.5)
				_confetti(s.position + Vector3.UP * 1.2)
				var item := _make_item(String((Case.ITEMS[int(c2["item"])] as Dictionary)["id"]))
				item.position = Vector3(0.0, 1.45, 0.0)
				s.add_child(item)
			for a in avatars.values():
				Creatures.anim(a as Node3D).play("cheer", 2.0)
			HudKit.banner(_all_huds(), "CASE SOLVED!", "It was them!", {"duration": SOLVED_TIME - 1.0, "style": "victory"})
			if vr_rig != null:
				HudKit.vr_banner(self, vr_rig.camera, "CASE SOLVED!", "It was them!", {"duration": SOLVED_TIME - 1.0, "sound": ""})
			sound("fanfare", -2.0)
			sound("applause", -6.0)
		"results":
			_show_results(net.state_get("results", {}))


## Every machine: a clue was picked up.
func on_found(k: int, who: int, pos: Vector3) -> void:
	sound("sparkle", -2.0)
	sound("achievement", -6.0)
	_confetti(pos)
	var what: String = ["A COAT SCRAP!", "A HAT!", "FOUND IT!"][clampi(k, 0, 2)]
	HudKit.toast(_all_huds(), what, {"icon": "eye", "color": who if who >= 0 else "gold", "where": "top"})
	if vr_rig != null:
		HudKit.vr_toast(self, vr_rig.camera, what)
	if who >= 0 and avatars.has(who):
		Creatures.anim(avatars[who]).play("cheer", 1.0)
	if k != Case.CLUE_ITEM:
		hints.hint("step_back", "No match? They step back!", {"icon": "person"})


func on_one_left() -> void:
	sound("drumroll", -4.0)
	HudKit.toast(_all_huds(), "ONE SUSPECT LEFT!", {"icon": "exclaim", "color": "gold", "where": "top"})
	if vr_rig != null:
		HudKit.vr_toast(self, vr_rig.camera, "ONE LEFT! Tap them!")


## A wrong guess: that suspect shakes it off and steps back.
func on_nope(i: int) -> void:
	sound("wrong", -4.0)
	if i < suspects.size():
		Creatures.anim(suspects[i]).play("hurt", 0.6)
		HudKit.popup(self, suspects[i].position + Vector3.UP * 1.5, "NOT ME!", {"color": "bad"})


func _confetti(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 30
	p.lifetime = 1.2
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.06, 0.01)
	bm.material = MeshKit.material(Color(1.0, 0.8, 0.3), 1.5)
	p.mesh = bm
	add_child(p)
	p.position = pos
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


# --- Results -------------------------------------------------------------------------------

func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
	if split != null:
		split.set_shared(true)
		var screen := Awards.results_screen(huds[-1], data, {"party": party})
		screen.continued.connect(func() -> void:
			var seats := party.local_slots()
			net.request(seats[0] if not seats.is_empty() else 0, "next_case"))
		results_ui = screen
	if vr_rig != null:
		var card := Awards.vr_summary(self, null, data, null, {"rig": vr_rig})
		card.continued.connect(func() -> void: net.request(0, "next_case"))
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


func on_pause_changed(paused: bool, by_slot: int) -> void:
	var why := "Paused by %s" % party.name_of(by_slot)
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
			UiKit.pin(tv_banner, Control.PRESET_CENTER)
			tv_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
			tv_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
		(tv_banner.find_child("Why", true, false) as Label).text = why
		tv_banner.visible = paused
		if paused:
			UiKit.pop_in(tv_banner)


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play(sound_name, volume_db, pitch)


# --- Networking ---------------------------------------------------------------------------

## Host, 30 Hz: the VR pose and every TV avatar (slot, position, yaw). The case is in the state store.
func make_snapshot() -> Array:
	var slots := PackedByteArray()
	var apos := PackedVector3Array()
	var ayaw := PackedFloat32Array()
	for slot in avatars:
		var a: Node3D = avatars[slot]
		slots.append(int(slot))
		apos.append(a.position)
		ayaw.append(a.rotation.y)
	return [vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array(), slots, apos, ayaw]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 4:
		return
	var pose: PackedFloat32Array = s[0]
	if pose.size() > 0 and vr_avatar == null:
		vr_avatar = VrRig.Avatar.new()
		add_child(vr_avatar)
		if split != null:
			split.set_bubble(VrRig.build_mirror(self, vr_avatar.head, false))
	if vr_avatar != null:
		vr_avatar.apply_pose(pose)
	var slots: PackedByteArray = s[1]
	var apos: PackedVector3Array = s[2]
	var ayaw: PackedFloat32Array = s[3]
	for i in slots.size():
		var slot: int = slots[i]
		if avatars.has(slot) and not party.is_local(slot):
			if not net_target.has(slot) or (avatars[slot] as Node3D).position.distance_to(apos[i]) > 3.0:
				(avatars[slot] as Node3D).position = apos[i]
			net_target[slot] = [apos[i], ayaw[i]]


func apply_event(kind: String, args: Array) -> void:
	match kind:
		"found":
			on_found(int(args[0]), int(args[1]), args[2])
		"one_left":
			on_one_left()
		"nope":
			on_nope(int(args[0]))
