extends Node3D
## Gentle town events: a rainstorm (farms grow faster, then a rainbow), a festival in a park (party
## music, balloons, confetti, bus rides to it), a parade (a marching band along the roads; the police
## car leads it), a stray cow on the loose (the police car leads her home) and a small fire (the fire
## engine splashes it out). Nothing is ever lost: events are little jobs and treats.
## The host decides (tick / start / finish) and publishes the event in the net store key "ev"; the cow
## and the parade move through snapshots. Every machine draws the effects from that.

const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Art := preload("res://games/tiny_town_tycoon/art.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Town := preload("res://games/tiny_town_tycoon/town.gd")

const KINDS: Array[String] = ["rain", "festival", "parade", "cow", "fire"]
const NAMES := {"rain": "RAINSTORM", "festival": "FESTIVAL", "parade": "PARADE", "cow": "STRAY COW", "fire": "FIRE"}

var main: Node
var town: Town
var vr := false

# host state
var next_t := 75.0
var current := {}  ## {"kind", "t", "bid", "path", "home"} (also in the store as "ev")
var cow_pos := Vector3.ZERO
var cow_yaw := 0.0
var cow_state := 0  ## 0 wander, 1 going home
var cow_goal := Vector3.ZERO
var parade_s := 0.0  ## cells walked along the path
var parade_go := false
var parade_wait := 0.0

# visuals
var rain_fx: CPUParticles3D
var rainbow: MeshInstance3D
var rainbow_t := 0.0
var cow_node: MeshInstance3D
var marchers: Array[MeshInstance3D] = []
var balloons: Node3D
var confetti: CPUParticles3D
var _shown := ""
var _t := 0.0


func is_on(kind: String) -> bool:
	return String(current.get("kind", "")) == kind


# --- Host ---------------------------------------------------------------------------------------------

## Host: every simulated second-ish.
func tick(dt: float, sim: Object, jobs: Object) -> void:
	if current.is_empty():
		next_t -= dt
		if next_t <= 0.0:
			next_t = randf_range(70.0, 110.0)
			start(_pick(), sim, jobs)
		return
	current["t"] = float(current["t"]) - dt
	var kind := String(current["kind"])
	match kind:
		"cow":
			_cow_tick(dt, jobs)
		"parade":
			_parade_tick(dt, jobs)
		"fire":
			var b: Dictionary = town.buildings.get(int(current.get("bid", 0)), {})
			if b.is_empty() or int(b["fire"]) <= 0:
				finish(sim, jobs)
				return
	if float(current["t"]) <= 0.0 and kind != "fire":
		finish(sim, jobs)


func _pick() -> String:
	var options: Array[String] = ["rain"]
	if town.of_kind("park").size() > 0:
		options.append("festival")
	if town.of_kind("farm").size() > 0:
		options.append("cow")
	if _road_count() >= 6:
		options.append("parade")
	var built := 0
	for id in town.buildings:
		if int(town.buildings[id]["stage"]) >= 1:
			built += 1
	if built >= 5:
		options.append("fire")
	return options[randi() % options.size()]


func _road_count() -> int:
	var n := 0
	for i in town.lay.size():
		if town.lay[i] == Defs.L_ROAD or town.lay[i] == Defs.L_CROSS:
			n += 1
	return n


## Host: begin an event now (also used by tests: main.debug_event()).
func start(kind: String, sim: Object, jobs: Object) -> bool:
	if not current.is_empty():
		finish(sim, jobs)
	var ev := {"kind": kind, "t": 45.0, "bid": 0, "path": PackedInt32Array(), "home": 0}
	match kind:
		"rain":
			sim.set("rain_t", 45.0)
		"festival":
			var parks := town.of_kind("park")
			if parks.is_empty():
				return false
			var p: Dictionary = parks[randi() % parks.size()]
			ev["bid"] = int(p["id"])
			ev["t"] = 50.0
			sim.set("festival_t", 50.0)
			sim.set("festival_bid", int(p["id"]))
		"cow":
			var farms := town.of_kind("farm")
			if farms.is_empty():
				return false
			var f: Dictionary = farms[randi() % farms.size()]
			ev["home"] = int(f["id"])
			ev["t"] = 70.0
			cow_pos = _cow_spawn(f)
			cow_state = 0
			cow_goal = cow_pos
			jobs.set("help_target", {"sub": "cow", "pos": cow_pos})
		"parade":
			var path := _parade_path()
			if path.size() < 5:
				return false
			ev["path"] = path
			ev["t"] = 14.0 + path.size() * 1.6
			parade_s = 0.0
			parade_go = false
			parade_wait = 0.0
			jobs.set("help_target", {"sub": "parade", "pos": _path_point(path, 0.0)})
		"fire":
			var b := _fire_victim()
			if b.is_empty():
				return false
			b["fire"] = 100
			ev["bid"] = int(b["id"])
			ev["t"] = 999.0
		_:
			return false
	current = ev
	main.call("event_started", kind, ev)
	return true


func finish(sim: Object, jobs: Object) -> void:
	var kind := String(current.get("kind", ""))
	if kind == "":
		return
	match kind:
		"rain":
			sim.set("rain_t", 0.0)
		"festival":
			sim.set("festival_t", 0.0)
			var c: Dictionary = sim.get("counters")
			c["festivals"] = int(c["festivals"]) + 1
		"cow":
			var c2: Dictionary = sim.get("counters")
			c2["cows"] = int(c2["cows"]) + 1
	jobs.set("help_target", {})
	var ended := current.duplicate()
	current = {}
	main.call("event_ended", kind, ended)


func _fire_victim() -> Dictionary:
	var cands: Array[Dictionary] = []
	var stations := town.of_kind("fire_station")
	for id in town.buildings:
		var b: Dictionary = town.buildings[id]
		var k := String(b["kind"])
		if int(b["stage"]) < 1 or k == "hall" or k == "park" or k == "water" or k == "fire_station" or int(b["fire"]) > 0:
			continue
		var safe := false
		for s in stations:
			if town.center_of(s).distance_to(town.center_of(b)) < 6.0 * Defs.CELL:
				safe = true
		if safe and randf() < 0.7:
			continue
		cands.append(b)
	if cands.is_empty():
		return {}
	return cands[randi() % cands.size()]


func _cow_spawn(farm: Dictionary) -> Vector3:
	var fc := town.center_of(farm)
	var best := fc
	var bd := -1.0
	for z in Defs.GRID:
		for x in Defs.GRID:
			if not town.has_road(x, z):
				continue
			var p := Defs.cell_center(x, z)
			var d := p.distance_to(fc)
			if d > 2.5 * Defs.CELL and d < 7.0 * Defs.CELL and d > bd:
				bd = d
				best = p
	if bd < 0.0:
		var dc := town.door_cell(farm)
		best = Defs.cell_center(dc.x, dc.y)
	return best


func _cow_tick(dt: float, jobs: Object) -> void:
	var home: Dictionary = town.buildings.get(int(current.get("home", 0)), {})
	if cow_state == 0:
		# wander slowly between nearby drivable cells
		if cow_pos.distance_to(cow_goal) < Defs.CELL * 0.1:
			var c := Defs.world_cell(cow_pos)
			var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			var d := dirs[randi() % 4]
			var n := c + d
			if town.inside(n.x, n.y) and town.is_land(n.x, n.y) and town.owner_id[Town.idx(n.x, n.y)] == 0:
				cow_goal = Defs.cell_center(n.x, n.y)
		_cow_step(dt, 0.018)
		jobs.set("help_target", {"sub": "cow", "pos": cow_pos})
	else:
		var hp := town.center_of(home) if not home.is_empty() else cow_pos
		cow_goal = hp
		_cow_step(dt, 0.05)
		if cow_pos.distance_to(hp) < Defs.CELL * 0.4 or home.is_empty():
			current["t"] = 0.0


func _cow_step(dt: float, spd: float) -> void:
	var to := cow_goal - cow_pos
	to.y = 0.0
	if to.length() > 0.0001:
		cow_yaw = lerp_angle(cow_yaw, atan2(to.x, to.z), 1.0 - exp(-6.0 * dt))
		cow_pos += to.normalized() * minf(spd * dt, to.length())
	cow_pos.y = Defs.GROUND_Y


## Host: the police car reached the cow (jobs "helped" -> main) or the parade start.
func helped(sub: String, jobs: Object) -> void:
	if sub == "cow" and is_on("cow"):
		cow_state = 1
		current["t"] = 30.0
		jobs.set("help_target", {})
	elif sub == "parade" and is_on("parade"):
		parade_go = true
		jobs.set("help_target", {})


func _parade_path() -> PackedInt32Array:
	var halls := town.of_kind("hall")
	var start := Vector2i(-1, -1)
	if not halls.is_empty():
		for c in town.ring_cells(halls[0]):
			if town.has_road(c.x, c.y):
				start = c
				break
	if start.x < 0:
		for i in town.lay.size():
			if town.lay[i] == Defs.L_ROAD:
				start = Vector2i(i % Defs.GRID, i / Defs.GRID)
				break
	var out := PackedInt32Array()
	if start.x < 0:
		return out
	var seen := {}
	var cur := start
	for step in 18:
		out.append(Town.idx(cur.x, cur.y))
		seen[cur] = true
		var nexts: Array[Vector2i] = []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var dv: Vector2i = d
			var n := cur + dv
			if town.has_road(n.x, n.y) and not seen.has(n):
				nexts.append(n)
		if nexts.is_empty():
			break
		cur = nexts[(step * 3 + out.size()) % nexts.size()]
	return out


func _path_point(path: PackedInt32Array, s: float) -> Vector3:
	if path.is_empty():
		return Defs.CENTER
	var i := clampi(int(floor(s)), 0, path.size() - 1)
	var j := clampi(i + 1, 0, path.size() - 1)
	var a := Defs.cell_center(path[i] % Defs.GRID, path[i] / Defs.GRID)
	var b := Defs.cell_center(path[j] % Defs.GRID, path[j] / Defs.GRID)
	return a.lerp(b, clampf(s - floor(s), 0.0, 1.0))


func _parade_tick(dt: float, jobs: Object) -> void:
	var path: PackedInt32Array = current.get("path", PackedInt32Array())
	if not parade_go:
		parade_wait += dt
		if parade_wait > 10.0:
			parade_go = true  # off they go even if nobody came to lead
			jobs.set("help_target", {})
		return
	parade_s = minf(parade_s + dt * 0.7, float(path.size() - 1) + 0.99)
	if parade_s >= float(path.size() - 1):
		current["t"] = minf(float(current["t"]), 2.0)


# --- Snapshots ---------------------------------------------------------------------------------------------

func make_snap() -> PackedInt32Array:
	return PackedInt32Array([Defs.q(cow_pos.x), Defs.q(cow_pos.z), int(round(cow_yaw * 100.0)), int(round(parade_s * 100.0))])


func apply_snap(a: PackedInt32Array) -> void:
	if a.size() < 4:
		return
	var p := Vector3(Defs.dq(a[0]), Defs.GROUND_Y, Defs.dq(a[1]))
	cow_pos = cow_pos.lerp(p, 0.5) if cow_pos.distance_to(p) < 0.2 else p
	cow_yaw = lerp_angle(cow_yaw, float(a[2]) / 100.0, 0.5)
	parade_s = lerpf(parade_s, float(a[3]) / 100.0, 0.5)


# --- Visuals (every machine) ----------------------------------------------------------------------------------

## The event in the store changed (every machine): show / hide its effects.
func show_event(ev: Dictionary) -> void:
	var kind := String(ev.get("kind", ""))
	if kind != "":
		current = ev if main.get("net") != null and String(main.get("net").get("mode")) == "client" else current
	if kind == _shown:
		return
	_hide(_shown, ev)
	_shown = kind
	match kind:
		"rain":
			_ensure_rain()
			rain_fx.emitting = true
		"festival":
			var b: Dictionary = town.buildings.get(int(ev.get("bid", 0)), {})
			if not b.is_empty():
				_festival_fx(town.center_of(b))
		"cow":
			if cow_node == null:
				cow_node = MeshKit.instance(Art.cow_mesh())
				cow_node.scale = Vector3.ONE * Defs.CELL * 0.75
				add_child(cow_node)
			cow_node.visible = true
		"parade":
			_ensure_marchers()


func _hide(kind: String, _ev: Dictionary) -> void:
	match kind:
		"rain":
			if rain_fx != null:
				rain_fx.emitting = false
			_show_rainbow()
		"festival":
			if balloons != null:
				balloons.queue_free()
				balloons = null
			if confetti != null:
				confetti.queue_free()
				confetti = null
		"cow":
			if cow_node != null:
				cow_node.visible = false
		"parade":
			for m in marchers:
				m.visible = false


func clear_event() -> void:
	if main.get("net") != null and String(main.get("net").get("mode")) == "client":
		current = {}
	_hide(_shown, {})
	_shown = ""


func _ensure_rain() -> void:
	if rain_fx != null:
		return
	rain_fx = CPUParticles3D.new()
	rain_fx.amount = 160 if vr else 320
	rain_fx.lifetime = 0.7
	rain_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain_fx.emission_box_extents = Vector3(Defs.HALF + 0.1, 0.02, Defs.HALF + 0.1)
	rain_fx.direction = Vector3(0.05, -1, 0)
	rain_fx.spread = 3.0
	rain_fx.gravity = Vector3(0, -0.6, 0)
	rain_fx.initial_velocity_min = 0.45
	rain_fx.initial_velocity_max = 0.6
	var bm := BoxMesh.new()
	bm.size = Vector3(0.0008, 0.02, 0.0008)
	bm.material = MeshKit.material(Color(0.7, 0.82, 1.0, 0.6), 0.3)
	rain_fx.mesh = bm
	rain_fx.emitting = false
	add_child(rain_fx)
	rain_fx.position = Vector3(0.0, Defs.GROUND_Y + 0.42, 0.0)


func _show_rainbow() -> void:
	if rainbow == null:
		var b := MeshKit.Builder.new()
		var cols: Array[Color] = [Color(1, 0.3, 0.3), Color(1, 0.6, 0.2), Color(1, 0.95, 0.3), Color(0.4, 0.9, 0.4), Color(0.3, 0.6, 1), Color(0.6, 0.4, 1)]
		for i in cols.size():
			var r := 0.62 - i * 0.025
			for k in 20:
				var a0 := PI * float(k) / 20.0
				var a1 := PI * float(k + 1) / 20.0
				var p0 := Vector3(cos(a0) * r, sin(a0) * r, 0)
				var p1 := Vector3(cos(a1) * r, sin(a1) * r, 0)
				b.tube(p0, p1, 0.011, 0.011, cols[i], 4, true)
		rainbow = MeshKit.instance(b.build(), false)
		add_child(rainbow)
		rainbow.position = Vector3(0.0, Defs.GROUND_Y - 0.05, -0.35)
	rainbow.visible = true
	rainbow.transparency = 1.0
	rainbow_t = 14.0


func _festival_fx(at: Vector3) -> void:
	balloons = Node3D.new()
	add_child(balloons)
	balloons.position = at
	var b := MeshKit.Builder.new()
	var cols: Array[Color] = [Color(1, 0.4, 0.5), Color(1, 0.85, 0.3), Color(0.4, 0.8, 1), Color(0.6, 1, 0.5), Color(0.8, 0.5, 1)]
	for k in 7:
		var a := k * TAU / 7.0
		var p := Vector3(cos(a) * 0.04, 0.09 + (k % 3) * 0.012, sin(a) * 0.04)
		b.sphere(0.009, MeshKit.at(p, Vector3(1, 1.2, 1)), cols[k % cols.size()], 8)
		b.tube(p - Vector3(0, 0.009, 0), Vector3(cos(a) * 0.02, 0.01, sin(a) * 0.02), 0.0006, 0.0006, Color(1, 1, 1), 3)
	# bunting ring
	for k in 16:
		var a2 := k * TAU / 16.0
		var p2 := Vector3(cos(a2) * 0.06, 0.05, sin(a2) * 0.06)
		b.cone(0.005, 0.01, MeshKit.at(p2, Vector3.ONE, Vector3(PI, a2, 0)), cols[k % cols.size()], 3)
	balloons.add_child(MeshKit.instance(b.build(), false))
	confetti = CPUParticles3D.new()
	confetti.amount = 40 if vr else 70
	confetti.lifetime = 1.6
	confetti.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	confetti.emission_sphere_radius = 0.05
	confetti.direction = Vector3.UP
	confetti.spread = 50.0
	confetti.gravity = Vector3(0, -0.12, 0)
	confetti.initial_velocity_min = 0.08
	confetti.initial_velocity_max = 0.16
	var cm := BoxMesh.new()
	cm.size = Vector3(0.003, 0.003, 0.0006)
	var cmat := StandardMaterial3D.new()
	cmat.vertex_color_use_as_albedo = true
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.material = cmat
	confetti.mesh = cm
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 0.4, 0.6))
	grad.set_color(1, Color(0.4, 0.8, 1))
	confetti.color_initial_ramp = grad
	balloons.add_child(confetti)
	confetti.position = Vector3(0, 0.08, 0)
	confetti.emitting = true


func _ensure_marchers() -> void:
	if marchers.is_empty():
		for k in 6:
			var m := MeshKit.instance(Art.parade_mesh())
			m.scale = Vector3.ONE * Defs.CELL * 0.75
			add_child(m)
			marchers.append(m)
	for m in marchers:
		m.visible = true


func _process(delta: float) -> void:
	_t += delta
	if rainbow != null and rainbow.visible:
		rainbow_t -= delta
		rainbow.transparency = clampf(1.0 - minf(rainbow_t, 14.0 - rainbow_t) / 2.0, 0.0, 1.0)
		if rainbow_t <= 0.0:
			rainbow.visible = false
	if cow_node != null and cow_node.visible:
		cow_node.position = cow_pos + Vector3(0, absf(sin(_t * 6.0)) * 0.001, 0)
		cow_node.rotation.y = cow_yaw
	if not marchers.is_empty() and marchers[0].visible:
		var path: PackedInt32Array = current.get("path", PackedInt32Array())
		for k in marchers.size():
			var s := maxf(0.0, parade_s - k * 0.45)
			var p := _path_point(path, s)
			var ahead := _path_point(path, s + 0.2)
			var m := marchers[k]
			m.position = p + Vector3(0, absf(sin(_t * 7.0 + k)) * 0.002, 0)
			var d := ahead - p
			if d.length() > 0.0001:
				m.rotation.y = atan2(d.x, d.z)
	if balloons != null:
		balloons.position.y = Defs.GROUND_Y + sin(_t * 1.5) * 0.004
