extends Node3D
## TINY TOWN TYCOON: a cosy co-op town builder on a garden table.
## The VR player is the MAYOR: a toy island on a table, a tray of building blocks beside them; grab a
## block with the right trigger and plonk it on the grid (roads are drawn by holding the trigger).
## TV players drive the town's tiny vehicles: the delivery truck, the bus, the fire engine, the crane
## (it builds the mayor's blueprints, so building is teamwork) and the police car. Vehicles nobody
## drives are driven by friendly AI, so the town works with any number of players.
## Without a headset (local play) slot 0 is a TV seat with a flat cursor-based building mode.
##
## Files: defs.gd (data), town.gd (the board + path finding), sim.gd (economy and growth),
## jobs.gd (the job board), vehicle.gd + fleet.gd (vehicles), events.gd (rain, festival, parade,
## cow, fire), town_view.gd + art.gd (drawing), mayor_vr.gd (VR tray and tools), mayor_flat.gd (flat
## mayor), hud.gd (TV HUD and menus). This file: modes, networking, phases, the sim loop, goals,
## saves, effects.
##
## Net: the host simulates. The town board goes through the state store ("ter", "lay", "trees" and
## one "b<id>" key per building, only changed ones are sent); vehicles, the VR pose, the cow and the
## parade go in snapshots; one-off effects are "fx" events. TV players' own vehicles are simulated
## on the TV machine (instant) and sent with net.send_state.

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
const SkyKit := preload("res://core/sky_kit.gd")
const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Art := preload("res://games/tiny_town_tycoon/art.gd")
const Town := preload("res://games/tiny_town_tycoon/town.gd")
const Sim := preload("res://games/tiny_town_tycoon/sim.gd")
const Jobs := preload("res://games/tiny_town_tycoon/jobs.gd")
const EventsScript := preload("res://games/tiny_town_tycoon/events.gd")
const TownViewScript := preload("res://games/tiny_town_tycoon/town_view.gd")
const FleetScript := preload("res://games/tiny_town_tycoon/fleet.gd")
const MayorVrScript := preload("res://games/tiny_town_tycoon/mayor_vr.gd")
const MayorFlatScript := preload("res://games/tiny_town_tycoon/mayor_flat.gd")
const HudScript := preload("res://games/tiny_town_tycoon/hud.gd")

const GAME_ID := "tiny_town_tycoon"
const DAY_LEN := 420.0  ## seconds for a whole day
const INTRO := {
	"title": "TINY TOWN TYCOON",
	"goal": "Build a happy little town together! The mayor places buildings, the drivers bring them to life.",
	"vr": {"role": "THE MAYOR", "controls": [["TRIGGER", "Grab a block from the tray, let go on the grid"],
		["TRIGGER", "Hold with a road to draw roads"], ["TWIST / A", "Turn a building"], ["TOUCH", "See what a building needs"],
		["R-STICK", "Turn the table"], ["L-STICK", "Walk round the table"]]},
	"tv": {"role": "THE DRIVERS", "controls": [["L-STICK", "Drive"], ["R-STICK", "Look"], ["A", "Honk!"], ["X", "Change vehicle"],
		["Y", "Split / shared view"], ["START", "Pause"]], "tips": ["Follow the arrow to your next job!", "The crane builds new buildings."]},
}
const MAYOR_INTRO := {"role": "THE MAYOR", "controls": [["L-STICK", "Move the cursor"], ["LB / RB", "Pick a building"], ["A", "Build (hold for roads)"],
	["X", "Turn"], ["B", "Bulldozer"], ["R-STICK", "Turn and zoom"]]}

# --- The networking contract ---
var net: Node
var ready_to_play := false
# --- Engine modules (names core/ looks for) ---
var party: Party
var split: SplitView
var vr_rig: VrRig
var save: Save
var sfx: Node
var music: Node
var hints: Hints
var awards: Awards
var sky: SkyKit.SkyRig

# --- The game ---
var town: Town
var sim: Sim  ## host / local
var jobs: Jobs  ## host / local
var events: Node3D
var view: Node3D
var fleet: Node3D
var mayor: Node3D  ## the VR mayor's tools (host with a headset)
var flat: Node3D  ## the flat mayor (local play without a headset, slot 0)
var hud: Node
var fast := 1.0  ## TT_FAST=1: the town grows four times as fast (tests)
var hour := 8.5
var night := 0.0  ## 0 = day .. 1 = deep night (town_view reads it)
var cams := {}  ## slot -> CameraRig (TV views)
var group_cam: CameraRig
var vr_avatar: VrRig.Avatar
var tv_banner: Control
var vr_banner: Node3D
var results_ui: Control
var vr_results: Node
var island := -1  ## host: the island loaded
var goals_done: Array[bool] = []
var _sim_t := 0.0
var _slow_t := 0.0
var _sky_t := 0.0
var _save_t := 0.0
var _phase_t := 0.0
var _pub_b := {}  ## id -> PackedInt32Array last published
var _pub_lay := -1
var _pub_tree := -1
var _job_pub := {}  ## slot -> Array last published job card
var _isl_shown := -1  ## island drawn by the view
var _ter_dirty := false
var _mood := ""
var _last_veh := {}  ## host: slot -> the vehicle they drove (given back when they reconnect)


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
	save.defaults = {"stars": {}, "towns": {}, "last": 0}
	add_child(save)
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.warm([], true)
	music = MusicScript.new()
	add_child(music)
	music.play_mood("town")
	music.prepare(["victory", "party", "cosy"])
	awards = Awards.new()
	awards.define("deliveries", "SUPER COURIER", "%s deliveries", "deliveries")
	awards.define("loads", "MASTER BUILDER", "%s loads of bricks", "loads")
	awards.define("passengers", "BUS HERO", "%s passengers", "passengers")
	awards.define("fires", "FIRE CHIEF", "%s fires out", "fires")
	awards.define("helps", "TOWN HELPER", "%s good deeds", "helps")
	awards.define("builds", "TOWN PLANNER", "%s buildings placed", "builds")
	awards.define("visits", "FRIENDLY FACE", "%s hellos", "visits")
	hints = Hints.new()
	add_child(hints)
	hints.bind_party(party)
	if OS.has_environment("TT_FAST"):
		fast = 4.0
	if OS.has_environment("DUO_JOIN"):
		net.join_finished.connect(func(ok: bool) -> void: _setup("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if VrRig.headset_available() or OS.has_environment("DUO_HOST"):
			net.host()
		_setup(net.mode)


func _setup(mode: String) -> void:
	town = Town.new()
	if mode != "client":
		sim = Sim.new()
		sim.on_event = _on_sim_event
		jobs = Jobs.new()
		jobs.on_event = _on_sim_event
		jobs.on_reward = _on_reward
		sim.setup(town, false)
		jobs.setup(town, sim)
	if VrRig.wanted(mode):
		vr_rig = VrRig.new()
		vr_rig.eye_height = 1.45
		vr_rig.move_speed = 0.7
		vr_rig.turn_mode = "none"
		vr_rig.bounds = Rect2(-1.8, -1.8, 3.6, 3.6)
		add_child(vr_rig)
		vr_rig.place(Vector3(0.0, 0.0, 1.05), 0.0)
		# the drivers' job rings and beams are for their own TV views, not the mayor's
		var marker_bits := 0
		for k in 8:
			marker_bits |= 1 << (TownViewScript.MARKER_BIT0 + k)
		vr_rig.camera.cull_mask &= ~marker_bits
		hints.set_vr_rig(vr_rig, self)
	var vr := vr_rig != null
	sky = SkyKit.apply(self, "day", vr)
	if not vr and sky.sun != null:
		sky.sun.directional_shadow_max_distance = 4.0  # a toy town: short, crisp shadows
	view = TownViewScript.new()
	view.name = "TownView"
	add_child(view)
	view.call("setup", self, town, Defs.island(0), vr)
	events = EventsScript.new()
	events.name = "Events"
	events.set("main", self)
	events.set("town", town)
	events.set("vr", vr)
	add_child(events)
	fleet = FleetScript.new()
	fleet.name = "Fleet"
	add_child(fleet)
	fleet.call("setup", self, town, jobs)
	hud = HudScript.new()
	hud.name = "Hud"
	add_child(hud)
	hud.call("setup", self)
	if vr:
		mayor = MayorVrScript.new()
		mayor.name = "Mayor"
		add_child(mayor)
		mayor.call("setup", self, vr_rig, town)
	if mode != "host":
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		group_cam = CameraRig.new()
		group_cam.camera = split.shared_camera()
		_tiny_camera(split.shared_camera(), -1)
		group_cam.avoid_walls = false
		group_cam.group_min_distance = 0.45
		group_cam.group_max_distance = 2.2
		group_cam.group_margin = 0.12
		group_cam.max_shake_offset = 0.01
		add_child(group_cam)
		_overview(group_cam)
		hud.call("make_view", -1, split.shared_hud())
		hints.add_view(hud.call("root_of", -1), -1)
		if mode == "client":
			vr_avatar = VrRig.Avatar.new()
			add_child(vr_avatar)
			split.set_bubble(VrRig.build_mirror(self, vr_avatar.head, false))
		elif vr_rig != null:
			split.set_bubble(vr_rig.mirror)
	party.allow_slot0 = mode == "local" and vr_rig == null
	awards.set_player(0, "MAYOR")
	if mode != "client":
		net.state_set("shared", false)
		var last := clampi(int(save.data.get("last", 0)), 0, Defs.ISLANDS.size() - 1)
		load_island(last)
		_set_phase("select")
	hints.intro(INTRO, {"duration": 12.0})
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Tiny Town Tycoon: %s mode%s" % [mode, " with a VR mayor" if vr_rig != null else ""])


## TV cameras look at a 1.2 m toy town: tiny near plane, only their own job markers.
func _tiny_camera(cam: Camera3D, slot: int) -> void:
	cam.near = 0.004
	cam.far = 90.0
	cam.fov = 60.0
	cam.cull_mask = TownViewScript.view_mask(maxi(slot, 0)) if slot >= 1 else (TownViewScript.BASE_MASK | TownViewScript.AVATAR_BIT)


func _overview(rig: CameraRig) -> void:
	var c := Defs.CENTER
	rig.shot_look(c + Vector3(0.0, 0.85, 0.95), c + Vector3(0.0, -0.05, 0.05), 1.0, Vector3(0.0, 0.0, 0.0))


## The camera a TV seat sees through (vehicle steering is relative to it).
func view_camera(slot: int) -> Camera3D:
	if split == null:
		return null
	return split.active_camera(slot)


func phase() -> String:
	return String(net.state_get("phase", "select"))


func playing() -> bool:
	return phase() == "play"


# --- Islands, saves and goals (host / local) ---------------------------------------------------

## Load (or start) an island's town. The previous town is saved first.
func load_island(i: int) -> void:
	if island >= 0 and island != i:
		save_town()
	if island == i and town.buildings.size() > 0:
		return
	island = i
	var isl := Defs.island(i)
	var id := String(isl["id"])
	var towns: Dictionary = save.data.get("towns", {})
	var free := bool(isl.get("free", false))
	if towns.has(id):
		var d: Dictionary = towns[id]
		town.deserialize(d.get("town", {}))
		town.island = i
		sim.setup(town, free)
		sim.coins = int(d.get("coins", int(isl["start_coins"])))
		sim.tier = int(d.get("tier", 0))
		var c: Dictionary = d.get("counters", {})
		for k in c:
			sim.counters[k] = c[k]
		goals_done.clear()
		for g in d.get("goals", []):
			goals_done.append(bool(g))
		hour = float(d.get("hour", 8.5))
	else:
		town.generate(i)
		town.starter_town()
		sim.setup(town, free)
		sim.coins = int(isl["start_coins"])
		sim.tier = 3 if free else 0
		for k in sim.counters:
			sim.counters[k] = 0
		goals_done.clear()
		hour = 8.5
	if free:
		sim.tier = 3
	while goals_done.size() < (isl["goals"] as Array).size():
		goals_done.append(false)
	sim.pop = 0
	for bid in town.buildings:
		sim.pop += int(town.buildings[bid].get("res", 0))
	jobs.setup(town, sim)
	events.call("finish", sim, jobs)
	fleet.call("reset_positions")
	fleet.call("sync_ai", sim.tier)
	save.data["last"] = i
	save.mark_dirty()
	net.state_set("stars", (save.data.get("stars", {}) as Dictionary).duplicate(true))
	_show_island(i)
	_publish_town(true)
	_publish_stats()
	_check_goals(false)


## Keep the current town in the save (host / local).
func save_town() -> void:
	if island < 0 or sim == null:
		return
	var id := String(Defs.island(island)["id"])
	var towns: Dictionary = save.data.get("towns", {})
	towns[id] = {"town": town.serialize(), "coins": sim.coins, "tier": sim.tier, "counters": sim.counters.duplicate(),
		"goals": goals_done.duplicate(), "hour": hour}
	save.data["towns"] = towns
	save.mark_dirty()


## Every machine: draw island `i` (terrain mesh, sea colour, snow).
func _show_island(i: int) -> void:
	_isl_shown = i
	view.call("rebuild_island", Defs.island(i))
	if sky != null:
		sky.set_snow(bool(Defs.island(i).get("snow", false)))


func _goal_value(g: Array) -> int:
	match String(g[0]):
		"pop":
			return sim.pop
		"build":
			return town.count_kind(String(g[2]))
		"train":
			return 1 if bool(view.call("has_train")) else 0
		"festival":
			return int(sim.counters.get("festivals", 0))
		"deliver":
			return int(sim.counters.get("deliveries", 0))
		"happy":
			return sim.happy
	return 0


## Host: tick the goals, publish them, celebrate new stars and the island's completion.
func _check_goals(celebrate: bool) -> void:
	var isl := Defs.island(island)
	var goals: Array = isl["goals"]
	var out: Array = []
	var newly := -1
	for k in goals.size():
		var g: Array = goals[k]
		var have := _goal_value(g)
		if not goals_done[k] and have >= int(g[1]):
			goals_done[k] = true
			newly = k
		out.append([String(g[3]), mini(have, int(g[1])), int(g[1]), goals_done[k]])
	net.state_set("goals", out)
	if newly >= 0 and celebrate:
		var stars: Dictionary = save.data.get("stars", {})
		stars[String(isl["id"])] = goals_done.duplicate()
		save.data["stars"] = stars
		net.state_set("stars", stars.duplicate(true))
		save_town()
		_fx("goal", [String((goals[newly] as Array)[3])])
		var all := true
		for d in goals_done:
			all = all and d
		if all:
			_complete_island()


func _complete_island() -> void:
	var isl := Defs.island(island)
	var data := awards.results({"title": "%s COMPLETE!" % String(isl["name"]), "subtitle": "Three stars! Your town is wonderful.",
		"style": "victory", "stats": [["CITIZENS", str(sim.pop)], ["DELIVERIES", str(int(sim.counters["deliveries"]))],
			["BUILDINGS", str(town.buildings.size())]], "score_format": "%d"})
	net.state_set("results", data)
	_set_phase("complete")


func _set_phase(p: String) -> void:
	_phase_t = 0.0
	net.state_set("phase", p)


# --- Requests (host / local) -------------------------------------------------------------------

func on_request(slot: int, action: String, args: Array) -> void:
	match action:
		"preview":
			if phase() == "select" and args.size() > 0:
				load_island(clampi(int(args[0]), 0, Defs.ISLANDS.size() - 1))
		"pick_island":
			if phase() == "select" and args.size() > 0:
				load_island(clampi(int(args[0]), 0, Defs.ISLANDS.size() - 1))
				_set_phase("play")
		"menu":
			if phase() == "play":
				save_town()
				_set_phase("select")
		"continue":
			if phase() == "complete":
				_set_phase("play")
		"place":
			if args.size() >= 4 and playing():
				place(slot, String(args[0]), int(args[1]), int(args[2]), int(args[3]))
		"paint":
			if args.size() >= 2 and playing():
				paint(slot, String(args[0]), args[1])
		"vehicle":
			var kind := String(args[0]) if args.size() > 0 else ""
			if Defs.V.has(kind) and slot >= 1:
				net.state_set("veh%d" % slot, kind)
				fleet.call("set_player", slot, kind)
				fleet.call("sync_ai", sim.tier)
		"honk":
			fleet.call("honk", slot)
		"toggle_view":
			net.state_set("shared", not bool(net.state_get("shared", false)))


## Why `kind` can't go at x, z right now ("" = it can). Used by the mayors' ghosts too.
func place_problem(kind: String, x: int, z: int) -> String:
	if sim != null:
		if not sim.unlocked(kind):
			return "Unlocks at %s" % Defs.TIERS[int(Defs.def(kind).get("tier", 0))]
		if not sim.can_afford(kind):
			return "Needs %d coins" % Defs.cost_of(kind)
	else:
		var tier := int(net.state_get("tier", 0))
		if tier < int(Defs.def(kind).get("tier", 0)) and not bool(net.state_get("free", false)):
			return "Unlocks at %s" % Defs.TIERS[int(Defs.def(kind).get("tier", 0))]
		if int(net.state_get("coins", 0)) < Defs.cost_of(kind) and not bool(net.state_get("free", false)):
			return "Needs %d coins" % Defs.cost_of(kind)
	return town.can_place(kind, x, z)


## Host: the mayor placed a building (a blueprint: the crane builds it).
func place(slot: int, kind: String, x: int, z: int, rot: int) -> bool:
	if Defs.is_tool_kind(kind) or kind == "hall" or not Defs.B.has(kind):
		return false
	var why := place_problem(kind, x, z)
	if why != "":
		_fx("nope", [slot, why])
		return false
	if not sim.free_build:
		sim.add_coins(-Defs.cost_of(kind))
	var id := town.add_building(kind, x, z, rot, 0)
	awards.add(slot, "builds")
	_fx("placed", [id, slot])
	_publish_town(false)
	_publish_stats()
	return true


## Host: roads / rails / the bulldozer painted over some cells (packed x + z * GRID).
func paint(slot: int, kind: String, cells: Variant) -> void:
	var list := PackedInt32Array()
	if cells is PackedInt32Array:
		list = cells
	elif cells is Array:
		for c in cells:
			list.append(int(c))
	var changed := 0
	var why := ""
	for ci in list:
		var x := ci % Defs.GRID
		var z := ci / Defs.GRID
		match kind:
			"road", "rail":
				var p := town.can_place(kind, x, z)
				if p != "":
					why = p
					continue
				if kind == "rail" and not sim.unlocked("rail"):
					why = "Unlocks at TOWN"
					continue
				if kind == "rail" and not sim.can_afford("rail"):
					why = "Needs coins"
					continue
				if town.set_layer(x, z, Defs.L_ROAD if kind == "road" else Defs.L_RAIL):
					changed += 1
					if kind == "rail" and not sim.free_build:
						sim.add_coins(-Defs.cost_of("rail"))
					if kind == "road":
						sim.counters["roads"] = int(sim.counters["roads"]) + 1
			"bulldozer":
				if town.layer(x, z) != Defs.L_NONE:
					town.set_layer(x, z, Defs.L_NONE)
					changed += 1
				else:
					var b := town.building_at(x, z)
					if not b.is_empty() and String(b["kind"]) != "hall":
						var refund := Defs.cost_of(String(b["kind"])) / 2 if int(b["stage"]) >= 1 else Defs.cost_of(String(b["kind"]))
						town.remove_building(int(b["id"]))
						sim.add_coins(refund)
						changed += 1
	if changed > 0:
		_fx("painted", [kind, list[list.size() - 1] if list.size() > 0 else 0, changed])
		_publish_town(false)
		_publish_stats()
	elif why != "" and kind != "bulldozer":
		_fx("nope", [slot, why])


# --- Publishing the town (host) -------------------------------------------------------------------

func _publish_town(full: bool) -> void:
	if net.mode == "client":
		return
	if full:
		net.state_set("island", island)
		net.state_set("ter", town.ter.duplicate())
		net.state_set("free", sim.free_build)
		_pub_lay = -1
		_pub_tree = -1
	if town.lay_version != _pub_lay:
		_pub_lay = town.lay_version
		net.state_set("lay", town.lay.duplicate())
	if town.tree_version != _pub_tree:
		_pub_tree = town.tree_version
		net.state_set("trees", town.trees.duplicate())
	for id in town.buildings:
		var pk := Town.pack_building(town.buildings[id])
		if not _pub_b.has(id) or _pub_b[id] != pk:
			_pub_b[id] = pk
			net.state_set("b%d" % int(id), pk)
	for id in _pub_b.keys():
		if not town.buildings.has(id):
			_pub_b.erase(id)
			net.state_set("b%d" % int(id), null)


func _publish_stats() -> void:
	net.state_set("coins", sim.coins)
	net.state_set("pop", sim.pop)
	net.state_set("happy", sim.happy)
	net.state_set("tier", sim.tier)


## Host: each TV player's job card (only when it changes).
func _publish_jobs() -> void:
	for slot in party.active_slots():
		if slot < 1:
			continue
		var v: Node3D = fleet.call("vehicle_of", slot)
		var card: Array = []
		if v != null:
			var jid := int(v.get("job_id"))
			if jobs.jobs.has(jid):
				card = jobs.describe(jobs.jobs[jid])
		var old: Array = _job_pub.get(slot, [])
		if old != card:
			_job_pub[slot] = card
			net.state_set("job%d" % slot, card)


# --- The store, on every machine ---------------------------------------------------------------

func _on_state_changed(key: String, value: Variant) -> void:
	if key.begins_with("veh"):
		fleet.call("set_player", int(key.substr(3)), String(value) if value != null else "")
		hud.call("refresh")
		return
	if net.mode == "client":
		if key == "ter" and value is PackedByteArray:
			town.ter = (value as PackedByteArray).duplicate()
			_ter_dirty = true
		elif key == "island":
			town.island = int(value)
			_ter_dirty = true
		elif key == "lay" and value is PackedByteArray:
			town.lay = (value as PackedByteArray).duplicate()
			town.lay_version += 1
			town.version += 1
		elif key == "trees" and value is PackedByteArray:
			town.trees = (value as PackedByteArray).duplicate()
			town.tree_version += 1
		elif key.begins_with("b") and key.substr(1).is_valid_int():
			var id := int(key.substr(1))
			if value == null:
				town.remove_building(id)
			elif value is PackedInt32Array:
				var pk: PackedInt32Array = value
				var site := pk.size() > 4 and pk[4] == 0
				if town.apply_packed(id, pk) or site:
					view.call("mark_dirty")
	match key:
		"phase":
			_on_phase(String(value))
		"ev":
			var ev: Dictionary = value if value is Dictionary else {}
			if ev.is_empty():
				events.call("clear_event")
			else:
				events.call("show_event", ev)
			if sky != null:
				sky.set_rain(String(ev.get("kind", "")) == "rain")
		"hour":
			if net.mode == "client":
				hour = float(value)
		"shared":
			if split != null and playing():
				split.set_shared(bool(value))
		"coins", "pop", "happy", "tier", "goals", "free":
			hud.call("refresh")
			if mayor != null:
				mayor.call("refresh_board")
		_:
			if key.begins_with("job"):
				hud.call("refresh")


func _on_phase(p: String) -> void:
	hud.call("on_phase", p)
	if mayor != null:
		mayor.call("on_phase", p)
	if p != "complete":
		_hide_results()
	if split != null:
		if p == "select":
			split.set_shared(true)
			_overview(group_cam)
		elif p == "play":
			split.set_shared(bool(net.state_get("shared", false)))
			_refresh_group()
	match p:
		"play":
			music.play_mood("town")
			var isl := Defs.island(int(net.state_get("island", 0)))
			HudKit.banner(hud.call("all_roots"), String(isl["name"]), String(isl["blurb"]), {"duration": 2.5})
			if vr_rig != null:
				HudKit.vr_banner(self, vr_rig.camera, String(isl["name"]), String(isl["blurb"]), {"duration": 2.5})
			if mayor != null:
				hints.hint("vr_road", "Grab the ROAD from your tray and draw a street!", {"to": "vr", "icon": "plus"})
		"complete":
			_show_results(net.state_get("results", {}))


func _show_results(data: Dictionary) -> void:
	_hide_results()
	music.play_mood("victory")
	view.call("fireworks", 10)
	if split != null:
		split.set_shared(true)
		var screen := Awards.results_screen(hud.call("root_of", -1), data, {"party": party})
		screen.continued.connect(func() -> void:
			var seats := party.local_slots()
			net.request(seats[0] if not seats.is_empty() else 0, "continue"))
		results_ui = screen
	if vr_rig != null:
		var card := Awards.vr_summary(self, null, data, null, {"rig": vr_rig})
		card.continued.connect(func() -> void: net.request(0, "continue"))
		vr_results = card


func _hide_results() -> void:
	if results_ui != null and is_instance_valid(results_ui):
		results_ui.queue_free()
	results_ui = null
	if vr_results != null and is_instance_valid(vr_results):
		vr_results.call("finish")
	vr_results = null


func results_showing() -> bool:
	return phase() == "complete"


# --- Players ----------------------------------------------------------------------------------------

func _on_player_joined(slot: int, _device: int) -> void:
	awards.set_player(slot, party.name_of(slot) if slot > 0 or vr_rig == null else "MAYOR")
	if party.is_local(slot) and split != null:
		var cam := split.camera(slot)
		_tiny_camera(cam, slot)
		if slot == 0:
			flat = MayorFlatScript.new()
			flat.name = "FlatMayor"
			add_child(flat)
			flat.call("setup", self, town, cam)
			hud.call("make_view", slot, split.hud(slot))
			hints.add_view(hud.call("root_of", slot), slot)
			hints.intro({"title": "TINY TOWN TYCOON", "goal": INTRO["goal"], "tv": MAYOR_INTRO}, {"duration": 10.0, "slots": [slot]})
		else:
			var c := CameraRig.new()
			c.camera = cam
			c.party = party
			c.slot = slot
			c.pivot_height = 0.02
			c.distance = 0.3
			c.min_distance = 0.06
			c.pitch = -0.55
			c.pitch_min = -1.3
			c.pitch_max = -0.12
			c.avoid_walls = false
			c.auto_behind = 1.4
			c.max_shake_offset = 0.008
			add_child(c)
			cams[slot] = c
			_overview(c)
			hud.call("make_view", slot, split.hud(slot))
			hints.add_view(hud.call("root_of", slot), slot)
	if net.mode != "client" and slot >= 1 and _last_veh.has(slot) and String(net.state_get("veh%d" % slot, "")) == "":
		on_request(slot, "vehicle", [String(_last_veh[slot])])  # back after a reconnect: same vehicle
	_refresh_group()
	hud.call("refresh")
	sound("ui_notify", -6.0)


func _on_player_left(slot: int) -> void:
	if cams.has(slot):
		(cams[slot] as Node).queue_free()
		cams.erase(slot)
	if slot == 0 and flat != null:
		flat.queue_free()
		flat = null
	hud.call("remove_view", slot)
	hints.remove_view(slot)
	if net.mode != "client":
		var had := String(net.state_get("veh%d" % slot, ""))
		if had != "":
			_last_veh[slot] = had
		net.state_set("veh%d" % slot, null)
		net.state_set("job%d" % slot, null)
		_job_pub.erase(slot)
		fleet.call("set_player", slot, "")
		fleet.call("sync_ai", sim.tier)
	_refresh_group()
	hud.call("refresh")


## A local TV player's vehicle appeared (or changed): its camera follows it.
func vehicle_ready(slot: int) -> void:
	if cams.has(slot):
		var v: Node3D = fleet.call("vehicle_of", slot)
		if v != null:
			(cams[slot] as CameraRig).follow(v, 0.3, 0.8)
	_refresh_group()


func _refresh_group() -> void:
	if group_cam == null or not playing():
		return
	var targets: Array = []
	for slot in party.local_slots():
		var v: Node3D = fleet.call("vehicle_of", slot)
		if v != null:
			targets.append(v)
	if targets.is_empty():
		_overview(group_cam)
	else:
		group_cam.follow_group(targets, -50.0, 0.0)


## TV seats: buttons that aren't driving (honk, change vehicle, views).
func _tv_buttons() -> void:
	for slot in party.local_slots():
		if slot == 0 and flat != null:
			continue
		if hud.call("menu_open", slot):
			continue
		if party.just_pressed(slot, "y"):
			net.request(slot, "toggle_view")
		if not playing():
			continue
		if party.just_pressed(slot, "accept"):
			fleet.call("honk", slot)
			if net.mode == "client":
				net.request(slot, "honk")
		if party.just_pressed(slot, "x"):
			hud.call("open_vehicle_menu", slot)


# --- Pause ---------------------------------------------------------------------------------------

func on_pause_changed(paused: bool, by_slot: int) -> void:
	var why := "Paused by %s  -  %s" % [party.name_of(by_slot), "wrist MENU: carry on" if vr_rig != null else "Start: menu"]
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


# --- Game loop -------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	var p := phase()
	var is_play := p == "play"
	_phase_t += delta
	if _ter_dirty and net.mode == "client":
		_ter_dirty = false
		_show_island(town.island)
	# day and night (every machine runs the clock; the host's is the true one)
	hour = fposmod(hour + delta * 24.0 / DAY_LEN * fast * (1.0 if is_play else 0.0), 24.0)
	_sky_t -= delta
	if _sky_t <= 0.0:
		_sky_t = 0.1
		var h := hour
		night = clampf(maxf(smoothstep(17.5, 20.5, h), 1.0 - smoothstep(4.5, 7.5, h)), 0.0, 1.0)
		Art.set_night(night)
		if sky != null:
			sky.set_time_of_day(h)
	_tv_buttons()
	fleet.call("tick", delta, is_play)
	if flat != null:
		flat.call("tick", delta, is_play)
	hud.call("tick", delta)
	_slow_t -= delta
	if _slow_t <= 0.0:
		_slow_t = 1.0
		_music()
	if net.mode == "client":
		return
	# --- host / local ---
	if p == "select":
		if _phase_t > 40.0 and party.local_slots().is_empty() and vr_rig == null:
			on_request(0, "pick_island", [island])  # nobody to choose: carry on
		return
	if p == "complete":
		if _phase_t > 40.0:
			_set_phase("play")
		return
	events.call("tick", delta * fast, sim, jobs)
	_sim_t += delta * fast
	if _sim_t >= 1.0:
		_sim_t -= 1.0
		_sim_tick()
	_save_t += delta
	if _save_t > 30.0:
		_save_t = 0.0
		save_town()


func _sim_tick() -> void:
	sim.tick(1.0)
	jobs.generate()
	jobs.assign(fleet.get("vehicles"))
	fleet.call("sync_ai", sim.tier)
	view.call("set_walkers", sim.pop / 2 + 2 if sim.pop > 0 else 0)
	_publish_town(false)
	_publish_stats()
	_publish_jobs()
	net.state_set("hour", snappedf(hour, 0.05))
	_check_goals(true)
	_contextual_hints()


func _music() -> void:
	var want := "town"
	var evd: Variant = net.state_get("ev", {})
	var ev := String((evd as Dictionary).get("kind", "")) if evd is Dictionary else ""
	if ev == "festival" or ev == "parade":
		want = "party"
	elif night > 0.6:
		want = "cosy"
	if phase() == "complete":
		return
	if want != _mood:
		_mood = want
		music.play_mood(want, 2.5)


func _contextual_hints() -> void:
	if mayor == null and flat == null:
		return
	var to: Variant = "vr" if mayor != null else 0
	var houses := town.of_kind("house", true)
	if town.of_kind("windmill", true).is_empty() and not houses.is_empty():
		hints.hint("need_power", "Houses need power: build a WINDMILL nearby!", {"to": to, "icon": "bolt"})
	elif town.of_kind("water", true).is_empty() and not houses.is_empty():
		hints.hint("need_water", "Houses need water: build a WATER TOWER nearby!", {"to": to, "icon": "drop"})
	elif houses.size() >= 2 and town.of_kind("farm", true).is_empty():
		hints.hint("need_jobs", "People need jobs: build a FARM and a SHOP!", {"to": to, "icon": "person"})
	elif houses.is_empty() and _phase_t > 20.0:
		hints.hint("need_houses", "Build some HOUSES next to the road!", {"to": to, "icon": "plus"})


# --- Effects (host decides, both machines show) ---------------------------------------------------

func _on_sim_event(kind: String, args: Array) -> void:
	match kind:
		"tier":
			_fx("tier", args)
			fleet.call("sync_ai", sim.tier)
		"helped":
			events.call("helped", String(args[0]), jobs)
			_fx("helped", args)
		_:
			_fx(kind, args)


func _on_reward(vid: int, stat: String, amount: int) -> void:
	if vid >= 1 and vid < 100:
		awards.add(vid, stat, float(amount))


func _fx(kind: String, args: Array) -> void:
	show_fx(kind, args)
	if net.mode == "host":
		net.event("fx", [kind, args])


## Every machine: the look and sound of something that happened.
func show_fx(kind: String, args: Array) -> void:
	var roots: Array = hud.call("all_roots")
	match kind:
		"placed":
			var b := town.buildings.get(int(args[0]), {}) as Dictionary
			view.call("mark_dirty")
			if not b.is_empty():
				var c := town.center_of(b)
				view.call("dust", c, Defs.size_of(String(b["kind"])))
				sfx.play_at("land", c, 0.0, 0.9)
				sfx.play_at("pop", c, -4.0, 1.2)
				get_tree().create_timer(0.05).timeout.connect(func() -> void: view.call("plonk", int(args[0])))
				for slot in party.local_slots():
					if slot >= 1:
						hints.hint("crane_%d" % slot, "A new building! The CRANE brings bricks to build it.", {"to": slot, "icon": "plus"})
		"painted":
			var ci := int(args[1])
			var at := Defs.cell_center(ci % Defs.GRID, ci / Defs.GRID)
			sfx.play_at("block" if String(args[0]) != "bulldozer" else "crash", at, -8.0, randf_range(1.1, 1.3))
		"nope":
			if mayor != null and int(args[0]) == 0:
				mayor.call("nope", String(args[1]))
			if flat != null and int(args[0]) == 0:
				HudKit.toast(hud.call("root_of", 0), String(args[1]), {"icon": "cross", "color": "bad"})
			sound("ui_error", -6.0)
		"building":
			var b2 := town.buildings.get(int(args[0]), {}) as Dictionary
			if not b2.is_empty():
				sfx.play_at("block", town.center_of(b2), -6.0, 0.8)
		"built":
			var id := int(args[0])
			var b3 := town.buildings.get(id, {}) as Dictionary
			if not b3.is_empty():
				view.call("start_rise", id)
				var c3 := town.center_of(b3)
				sfx.play_at("sparkle", c3, -2.0)
				view.call("burst", c3 + Vector3(0, 0.03, 0), Color(1.0, 0.9, 0.4), 18, 1.0)
				HudKit.toast(roots, "%s is ready!" % Defs.building_name(String(b3["kind"]), id), {"icon": "check", "color": "good"})
				if mayor != null:
					mayor.call("built", id)
		"sale":
			var b4 := town.buildings.get(int(args[0]), {}) as Dictionary
			if not b4.is_empty():
				HudKit.popup(self, town.center_of(b4) + Vector3(0, 0.07, 0), "+%d" % int(args[1]), {"color": "gold", "size": 0.12})
				sfx.play_at("coin", town.center_of(b4), -12.0, 1.3)
		"move_in":
			var b5 := town.buildings.get(int(args[0]), {}) as Dictionary
			if not b5.is_empty():
				view.call("burst", town.center_of(b5) + Vector3(0, 0.04, 0), Color(0.5, 0.8, 1.0), 8, 0.7)
				sfx.play_at("pop", town.center_of(b5), -10.0, 1.5)
		"upgrade":
			var b6 := town.buildings.get(int(args[0]), {}) as Dictionary
			view.call("mark_dirty")
			if not b6.is_empty():
				view.call("dust", town.center_of(b6), 1)
				view.call("burst", town.center_of(b6) + Vector3(0, 0.05, 0), Color(1.0, 0.85, 0.3), 16, 1.0)
				sfx.play_at("power_up", town.center_of(b6), -6.0)
		"pickup", "dropoff":
			view.call("mark_dirty")
			var vid := int(args[0])
			var b7 := town.buildings.get(int(args[3]), {}) as Dictionary
			if not b7.is_empty():
				var c7 := town.center_of(b7)
				var res := String(args[1])
				var txt := ("+%d %s" if kind == "pickup" else "%d %s DELIVERED") % [int(args[2]), String(Defs.RES_NAMES.get(res, res.to_upper()))]
				HudKit.popup(self, c7 + Vector3(0, 0.08, 0), txt, {"color": Defs.RES_COLORS.get(res, Color.WHITE), "size": 0.1})
				sfx.play_at("pickup" if kind == "pickup" else "kaching", c7, -3.0)
				if kind == "dropoff":
					view.call("burst", c7 + Vector3(0, 0.03, 0), Defs.RES_COLORS.get(res, Color.WHITE), 12, 0.8)
			if vid >= 1 and vid < 100 and party.is_local(vid):
				party.rumble(vid, 0.3, 0.0, 0.12)
		"fire_out", "helped", "visited":
			var vid2 := int(args[1])
			var v: Node3D = fleet.call("vehicle_of", vid2)
			var at2: Vector3 = v.global_position if v != null else Defs.CENTER
			sfx.play_at("splash" if kind == "fire_out" else ("cheer" if kind == "helped" else "ding"), at2, -3.0)
			view.call("burst", at2 + Vector3(0, 0.04, 0), Color(0.5, 0.85, 1.0) if kind == "fire_out" else Color(1.0, 0.9, 0.4), 14, 0.9)
			view.call("mark_dirty")
			if kind == "fire_out":
				HudKit.toast(roots, "Fire out! Hooray for the fire engine!", {"icon": "drop", "color": "info"})
			elif kind == "helped":
				HudKit.toast(roots, "Great help, %s!" % party.name_of(vid2) if vid2 < 100 else "The police car helped out!", {"icon": "star", "color": "good"})
		"tier":
			var t := int(args[0])
			view.call("fireworks", 8)
			music.play_mood("victory")
			sfx.play("fanfare")
			var sub := "New buildings unlocked!"
			HudKit.banner(roots, "YOU'RE A %s!" % Defs.TIERS[t], sub, {"style": "level", "duration": 3.0})
			if vr_rig != null:
				HudKit.vr_banner(self, vr_rig.camera, "YOU'RE A %s!" % Defs.TIERS[t], sub, {"style": "level", "duration": 3.0})
				vr_rig.pulse(VrRig.RIGHT, 0.6, 0.2)
			if mayor != null:
				mayor.call("refresh_board")
		"goal":
			sfx.play("achievement")
			HudKit.banner(roots, "GOAL DONE!", String(args[0]), {"style": "victory", "duration": 2.5})
			if vr_rig != null:
				HudKit.vr_banner(self, vr_rig.camera, "GOAL DONE!", String(args[0]), {"style": "victory", "duration": 2.5})
			view.call("fireworks", 4)
		"train":
			sfx.play("whistle", -6.0)
		"event":
			var ek := String(args[0])
			var title := String(EventsScript.NAMES.get(ek, ek.to_upper()))
			var line := String(args[1])
			HudKit.banner(roots, title, line, {"style": "info", "duration": 2.5})
			if vr_rig != null:
				HudKit.vr_toast(self, vr_rig.camera, "%s! %s" % [title, line])
			sfx.play("bell" if ek != "fire" else "alarm", -4.0)


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	sfx.play(sound_name, volume_db, pitch)


# --- Events (events.gd calls these on the host) ------------------------------------------------------

func event_started(kind: String, ev: Dictionary) -> void:
	net.state_set("ev", ev)
	var line := ""
	match kind:
		"rain":
			line = "The farms love it: food grows faster!"
		"festival":
			line = "Party in the park! Buses, bring everyone!"
		"parade":
			line = "Police car: lead the parade!"
		"cow":
			line = "A cow got out! Police car, lead her home!"
		"fire":
			line = "Fire engine, quick!"
	_fx("event", [kind, line])


func event_ended(kind: String, _ev: Dictionary) -> void:
	net.state_set("ev", {})
	match kind:
		"rain":
			HudKit.toast(hud.call("all_roots"), "Look, a rainbow!", {"icon": "star", "color": "info"})
		"cow":
			HudKit.toast(hud.call("all_roots"), "The cow is safe at home!", {"icon": "check", "color": "good"})


## The toy train reached a station (town_view, every machine): the host pays a little.
func train_arrived() -> void:
	if net.mode == "client" or not playing():
		return
	sim.counters["trains"] = int(sim.counters["trains"]) + 1
	sim.add_coins(5)
	_fx("train", [])


## Tests: start an event now.
func debug_event(kind: String) -> bool:
	return bool(events.call("start", kind, sim, jobs))


# --- Networking ------------------------------------------------------------------------------------

func make_snapshot() -> Array:
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	var ghost := PackedInt32Array()
	if mayor != null:
		ghost = mayor.call("ghost_state")
	return [pose, fleet.call("pack"), events.call("make_snap"), ghost]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 4:
		return
	if vr_avatar != null:
		vr_avatar.apply_pose(s[0])
	fleet.call("apply", s[1])
	events.call("apply_snap", s[2])
	hud.call("mayor_ghost", s[3])


func apply_event(kind: String, args: Array) -> void:
	if kind == "fx" and args.size() >= 2:
		show_fx(String(args[0]), args[1])


func on_remote_state(slot: int, pos: Vector3, yaw: float, _pitch: float) -> void:
	fleet.call("remote_state", slot, pos, yaw)


func on_client_joined() -> void:
	_pub_b.clear()  # the store re-sends everything to a (re)joining TV machine anyway


func _exit_tree() -> void:
	if sim != null and island >= 0:
		save_town()
		save.save_now()
	XRServer.world_scale = 1.0
