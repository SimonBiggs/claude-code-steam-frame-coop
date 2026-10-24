extends Node3D
## The town's vehicles on every machine.
## - TV players' vehicles (vid = their party slot): simulated on the machine whose controller drives
##   them (instant), sent to the host with net.send_state; the other machine mirrors them.
## - AI vehicles (vid 100+): one of each core kind nobody is driving (plus a police car and, in a big
##   town, a second truck and crane). The host drives them along A* paths to their jobs.
## - The host checks every vehicle against the job board (jobs.gd) and packs them all into the
##   snapshot (7 ints each); the TV machine mirrors the ones it doesn't drive.

const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Town := preload("res://games/tiny_town_tycoon/town.gd")
const Jobs := preload("res://games/tiny_town_tycoon/jobs.gd")
const VehicleScript := preload("res://games/tiny_town_tycoon/vehicle.gd")
const UiMenu := preload("res://core/ui_menu.gd")

const AI_BASE := 100
const CARGO: Array[String] = ["", "food", "bread", "wood", "bricks", "people"]
const PACK_N := 7

var main: Node
var town: Town
var jobs: Jobs  ## host / local only
var vehicles := {}  ## vid -> vehicle node
var _send_t := 0.0
var _honk_seen := {}  ## vid -> honks already played (mirrors)


func setup(p_main: Node, p_town: Town, p_jobs: Jobs) -> void:
	main = p_main
	town = p_town
	jobs = p_jobs


func vehicle_of(slot: int) -> Node3D:
	return vehicles.get(slot, null)


func is_ai(vid: int) -> bool:
	return vid >= AI_BASE


## Somewhere sensible to appear: the road by the town hall.
func spawn_point(vid: int) -> Vector3:
	var halls := town.of_kind("hall", true)
	var c := Vector2i(Defs.GRID / 2, Defs.GRID / 2)
	if not halls.is_empty():
		c = town.door_cell(halls[0])
	c = town.nearest_drivable(c)
	var p := Defs.cell_center(c.x, c.y)
	var a := float(vid) * 1.9
	return p + Vector3(cos(a), 0.0, sin(a)) * Defs.CELL * 0.25


func _make(vid: int, kind: String, slot: int) -> Node3D:
	var v: Node3D = VehicleScript.new()
	var col: Color = main.party.color_of(slot) if slot >= 0 else Color(Defs.V.get(kind, {}).get("color", Color(1, 1, 1)))
	v.call("setup", kind, vid, slot, col)
	add_child(v)
	v.position = spawn_point(vid)
	v.set("yaw", float(vid) * 0.7)
	vehicles[vid] = v
	return v


func _remove(vid: int) -> void:
	var v: Node3D = vehicles.get(vid, null)
	if v == null:
		return
	if jobs != null and int(v.get("job_id")) != 0:
		jobs.release(int(v.get("job_id")))
	v.queue_free()
	vehicles.erase(vid)
	_honk_seen.erase(vid)


## Every machine: a TV player's vehicle choice (store key "veh<slot>"; "" = none yet / left).
func set_player(slot: int, kind: String) -> void:
	if kind == "" or not Defs.V.has(kind):
		_remove(slot)
		return
	var v: Node3D = vehicles.get(slot, null)
	if v == null:
		v = _make(slot, kind, slot)
	else:
		if String(v.get("kind")) != kind and jobs != null and int(v.get("job_id")) != 0:
			jobs.release(int(v.get("job_id")))
			v.set("job_id", 0)
			v.set("cargo", "")
		v.call("set_kind", kind)
	# Simulated here if this machine owns the controller; otherwise a mirror of send_state / snapshots.
	v.set("mirror", not main.party.is_local(slot))
	v.set("net_pos", v.position)
	if main.party.is_local(slot):
		main.vehicle_ready(slot)


## Host: AI drivers for every job nobody is doing.
func sync_ai(tier: int) -> void:
	var taken := {}
	for vid in vehicles:
		if not is_ai(int(vid)):
			taken[String(vehicles[vid].get("kind"))] = true
	var want: Array[String] = []
	for k in Defs.CORE_FLEET:
		want.append(k if not taken.has(k) else "")
	want.append("police" if not taken.has("police") else "")
	if tier >= 2:
		want.append("truck")
		want.append("crane")
	for i in 8:
		var vid := AI_BASE + i
		var kind := want[i] if i < want.size() else ""
		var v: Node3D = vehicles.get(vid, null)
		if kind == "":
			if v != null:
				_remove(vid)
		elif v == null:
			_make(vid, kind, -1)


## Every vehicle's spot after a new town loads.
func reset_positions() -> void:
	for vid in vehicles:
		var v: Node3D = vehicles[vid]
		v.position = spawn_point(int(vid))
		v.set("net_pos", v.position)
		v.set("job_id", 0)
		v.set("cargo", "")
		v.set("path", [] as Array[Vector2i])


# --- Per frame --------------------------------------------------------------------------------------

func tick(delta: float, playing: bool) -> void:
	var host: bool = main.net.mode != "client"
	_send_t -= delta
	var send := _send_t <= 0.0
	if send:
		_send_t = 1.0 / 30.0
	for vid in vehicles:
		var v: Node3D = vehicles[vid]
		if bool(v.get("mirror")):
			v.call("mirror_update", delta)
			continue
		if is_ai(int(vid)):
			if host:
				_ai(v, delta, playing)
			continue
		var slot := int(vid)
		_player_drive(v, slot, delta, playing)
		if main.net.mode == "client" and send:
			main.net.send_state(v.position, float(v.get("yaw")), 0.0, slot)
	# soft bumpers between the vehicles simulated here
	var ids: Array = vehicles.keys()
	for i in ids.size():
		var a: Node3D = vehicles[ids[i]]
		if bool(a.get("mirror")) or (not host and is_ai(int(ids[i]))):
			continue
		for j in ids.size():
			if i != j:
				var b: Node3D = vehicles[ids[j]]
				a.call("separate", b.position, town)
	if host:
		for vid in vehicles:
			var v2: Node3D = vehicles[vid]
			if jobs != null and playing:
				jobs.update_vehicle(v2, delta)
				_spray_target(v2)


func _player_drive(v: Node3D, slot: int, delta: float, playing: bool) -> void:
	var mv := Vector2.ZERO
	if playing and not UiMenu.slot_busy(slot):
		mv = main.party.stick(slot, "move")
	var dir := Vector2.ZERO
	if mv.length() > 0.12:
		var cam: Camera3D = main.view_camera(slot)
		var f := Vector3.FORWARD
		if cam != null:
			f = -cam.global_basis.z
		f.y = 0.0
		f = f.normalized() if f.length() > 0.001 else Vector3.FORWARD
		var r := Vector3(-f.z, 0.0, f.x)
		var d := r * mv.x - f * mv.y
		dir = Vector2(d.x, d.z)
		if dir.length() > 1.0:
			dir = dir.normalized()
	v.call("drive", dir, delta, town)


func _ai(v: Node3D, delta: float, playing: bool) -> void:
	var jid := int(v.get("job_id"))
	if not playing or jobs == null or jid == 0 or not jobs.jobs.has(jid):
		# no job: potter back towards the town hall and wait there
		var home := spawn_point(int(v.get("vid")))
		if v.position.distance_to(home) > Defs.CELL * 1.5 and playing:
			v.call("ai_drive", home, delta, town)
		else:
			v.call("idle", delta, town)
		return
	var j: Dictionary = jobs.jobs[jid]
	v.call("ai_drive", jobs.target_of(j), delta, town)


func _spray_target(v: Node3D) -> void:
	if not bool(v.get("spraying")):
		return
	var jid := int(v.get("job_id"))
	if jobs.jobs.has(jid):
		var b := jobs.target_building(jobs.jobs[jid])
		if not b.is_empty():
			v.set("spray_target", town.center_of(b))


## Host: a TV machine player's vehicle moved there.
func remote_state(slot: int, pos: Vector3, yaw: float) -> void:
	var v: Node3D = vehicles.get(slot, null)
	if v != null:
		v.set("net_pos", Vector3(pos.x, v.position.y, pos.z))
		v.set("net_yaw", yaw)


func honk(vid: int) -> void:
	var v: Node3D = vehicles.get(vid, null)
	if v != null:
		v.call("honk")
		main.sfx.play_at("honk", v.global_position, -4.0, 1.0 + float(vid % 4) * 0.08)


# --- Snapshots --------------------------------------------------------------------------------------

func pack() -> PackedInt32Array:
	var out := PackedInt32Array()
	for vid in vehicles:
		var v: Node3D = vehicles[vid]
		var flags := (1 if bool(v.get("spraying")) else 0) | (int(v.get("honks")) % 64) << 1
		var sp: Vector3 = v.get("spray_target")
		out.append_array(PackedInt32Array([int(vid), Defs.V.keys().find(String(v.get("kind"))), Defs.q(v.position.x),
			Defs.q(v.position.z), int(round(float(v.get("yaw")) * 1000.0)), CARGO.find(String(v.get("cargo"))), flags]))
		if bool(v.get("spraying")):
			out.append_array(PackedInt32Array([-1, Defs.q(sp.x), Defs.q(sp.z)]))
	return out


func apply(a: PackedInt32Array) -> void:
	var seen := {}
	var kinds: Array = Defs.V.keys()
	var i := 0
	var last: Node3D = null
	while i < a.size():
		if a[i] == -1:
			if last != null and i + 2 < a.size():
				last.set("spray_target", Vector3(Defs.dq(a[i + 1]), Defs.GROUND_Y, Defs.dq(a[i + 2])))
			i += 3
			continue
		if i + PACK_N > a.size():
			break
		var vid := a[i]
		var kind: String = String(kinds[clampi(a[i + 1], 0, kinds.size() - 1)])
		var pos := Vector3(Defs.dq(a[i + 2]), 0.0, Defs.dq(a[i + 3]))
		var yaw := float(a[i + 4]) / 1000.0
		var cargo: String = CARGO[clampi(a[i + 5], 0, CARGO.size() - 1)]
		var flags := a[i + 6]
		i += PACK_N
		seen[vid] = true
		var v: Node3D = vehicles.get(vid, null)
		var local: bool = not is_ai(vid) and main.party.is_local(vid)
		if v == null:
			if local:
				continue  # our own vehicle appears from the store key, not the snapshot
			v = _make(vid, kind, vid if not is_ai(vid) else -1)
			v.position = Vector3(pos.x, v.position.y, pos.z)
		last = v
		if not local:
			v.set("mirror", true)
			if String(v.get("kind")) != kind:
				v.call("set_kind", kind)
			v.set("net_pos", Vector3(pos.x, v.position.y, pos.z))
			v.set("net_yaw", yaw)
			var honks := (flags >> 1) & 63
			if _honk_seen.has(vid) and int(_honk_seen[vid]) != honks:
				honk(vid)
			_honk_seen[vid] = honks
			v.set("honks", honks)
		v.set("cargo", cargo)
		v.set("spraying", (flags & 1) != 0)
	for vid in vehicles.keys():
		if not seen.has(vid) and not (not is_ai(int(vid)) and main.party.is_local(int(vid))):
			_remove(int(vid))
