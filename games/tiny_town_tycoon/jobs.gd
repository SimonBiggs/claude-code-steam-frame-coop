extends RefCounted
## The job board (host / local only): what the town's vehicles should do next.
##   deliver (truck): FOOD / BREAD from a farm or bakery to a shop or bakery
##   build   (crane): BRICKS from the Town Hall (or WOOD from a sawmill) to a building site
##   bus     (bus):   people waiting at a home, out to a shop, park, school or the festival
##   fire    (fire engine): splash out a fire
##   help    (police car): lead a stray cow home, lead the parade
##   visit   (anyone with nothing to do): a quick hello at a building, a coin and a cheer
## Every job is a pickup (step 0) and a drop-off (step 1) at buildings; main.gd moves the vehicles,
## this file decides when they arrive and what happens then. Everything is automatic on arrival:
## drive into the glowing ring.

const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Town := preload("res://games/tiny_town_tycoon/town.gd")
const Sim := preload("res://games/tiny_town_tycoon/sim.gd")

## How close (in cells, from the footprint's edge) a vehicle must be to load or unload.
const NEAR := 0.95
const FIRE_RANGE := 1.8
const STOCK_CAP := 10

var town: Town
var sim: Sim
var jobs := {}  ## id -> Dictionary {id, type, from, to, res, qty, carry, step, vid, wait, sub, pos}
var next_id := 1
## main.gd callbacks: on_event(kind, args) for effects; on_reward(vid, stat, amount) for awards.
var on_event: Callable
var on_reward: Callable
## Extra jobs from events (police): main.gd sets {"sub": "cow"/"parade", "pos": Vector3} or {}.
var help_target := {}
## SIMPLE_MODE: the starter house blueprint (the drivers' practice delivery): the AI crane leaves it
## alone for a good while so a TV driver who joins a bit late still gets it.
var practice_site := -1


func setup(t: Town, s: Sim) -> void:
	town = t
	sim = s
	jobs.clear()
	next_id = 1


func job_type(kind: String) -> String:
	return String(Defs.V.get(kind, {}).get("job", "deliver"))


func _add(j: Dictionary) -> Dictionary:
	j["id"] = next_id
	next_id += 1
	for k in ["from", "to", "qty", "carry", "step", "wait"]:
		if not j.has(k):
			j[k] = 0
	if not j.has("vid"):
		j["vid"] = -1
	if not j.has("res"):
		j["res"] = ""
	jobs[int(j["id"])] = j
	return j


func _count(type: String, key: String, bid: int, res: String = "") -> int:
	var n := 0
	for id in jobs:
		var j: Dictionary = jobs[id]
		if String(j["type"]) == type and int(j[key]) == bid and (res == "" or String(j["res"]) == res):
			n += 1
	return n


func _b(id: int) -> Dictionary:
	return town.buildings.get(id, {})


# --- Making jobs (each sim tick) ----------------------------------------------------------------------

func generate() -> void:
	_cleanup()
	for id in jobs:
		if int(jobs[id]["vid"]) == -1:
			jobs[id]["age"] = int(jobs[id].get("age", 0)) + 1
	# deliveries: shops want food or bread, bakeries want food
	for id in town.buildings:
		var c: Dictionary = town.buildings[id]
		var kind := String(c["kind"])
		if int(c["stage"]) < 1 or not town.on_road(c):
			continue
		var wants: Array[String] = []
		if kind == "shop":
			wants = ["bread", "food"]
		elif kind == "bakery":
			wants = ["food"]
		for res in wants:
			if int(c[res]) <= 3 and _count("deliver", "to", int(id), res) == 0:
				var p := _producer(res, c)
				if not p.is_empty():
					_add({"type": "deliver", "from": int(p["id"]), "to": int(id), "res": res, "qty": 4})
	# construction: one or two loads on the way to each site
	for id in town.buildings:
		var b: Dictionary = town.buildings[id]
		if int(b["stage"]) != 0:
			continue
		var missing := int(b["need"]) - int(b["mats"])
		var open := _count("build", "to", int(id))
		if missing > 0 and open < mini(missing, 2):
			var src := _material_source()
			if not src.is_empty():
				var wood := String(src["kind"]) == "sawmill"
				_add({"type": "build", "from": int(src["id"]), "to": int(id), "res": "wood" if wood else "bricks", "qty": 2 if wood else 1})
	# buses: people waiting at home
	for id in town.buildings:
		var h: Dictionary = town.buildings[id]
		if String(h["kind"]) != "house" or int(h["wait"]) <= 0 or _count("bus", "from", int(id)) > 0:
			continue
		var dest := _destination(h)
		if not dest.is_empty():
			_add({"type": "bus", "from": int(id), "to": int(dest["id"]), "res": "people", "qty": mini(int(h["wait"]), 6)})
	# fires
	for id in town.buildings:
		var f: Dictionary = town.buildings[id]
		if int(f["fire"]) > 0 and _count("fire", "to", int(id)) == 0:
			_add({"type": "fire", "to": int(id), "step": 1})
	# police help from events
	var have_help := false
	for id in jobs:
		if String(jobs[id]["type"]) == "help":
			have_help = true
	if not help_target.is_empty() and not have_help:
		_add({"type": "help", "step": 1, "sub": String(help_target.get("sub", "cow")), "pos": help_target.get("pos", Defs.CENTER)})


func _cleanup() -> void:
	for id in jobs.keys():
		var j: Dictionary = jobs[id]
		var gone := false
		match String(j["type"]):
			"deliver", "build", "bus", "visit":
				if int(j["step"]) == 0 and _b(int(j["from"])).is_empty() and String(j["type"]) != "visit":
					gone = true
				if _b(int(j["to"])).is_empty():
					gone = true
				if String(j["type"]) == "build" and not _b(int(j["to"])).is_empty() and int(_b(int(j["to"]))["stage"]) != 0:
					gone = true
			"fire":
				var b := _b(int(j["to"]))
				gone = b.is_empty() or int(b["fire"]) <= 0
			"help":
				gone = help_target.is_empty()
		if gone:
			jobs.erase(id)


func _producer(res: String, near: Dictionary) -> Dictionary:
	var kind := "farm" if res == "food" else ("bakery" if res == "bread" else "sawmill")
	var best := {}
	var bd := INF
	var c := town.center_of(near)
	for p in town.of_kind(kind):
		if not town.on_road(p) or int(p[res]) < 1:
			continue
		var d := town.center_of(p).distance_to(c) - float(p[res]) * 0.01
		if d < bd:
			bd = d
			best = p
	return best


func _material_source() -> Dictionary:
	for s in town.of_kind("sawmill"):
		if int(s["wood"]) >= 2 and town.on_road(s):
			return s
	var halls := town.of_kind("hall")
	return halls[0] if not halls.is_empty() else {}


func _destination(h: Dictionary) -> Dictionary:
	if sim.festival_t > 0.0 and town.buildings.has(sim.festival_bid):
		return town.buildings[sim.festival_bid]
	var options: Array[Dictionary] = []
	for kind in ["shop", "park", "school", "landmark", "ferris", "hall", "bakery", "station"]:
		for b in town.of_kind(String(kind)):
			if town.on_road(b):
				options.append(b)
	if options.is_empty():
		return {}
	return options[(int(h["id"]) * 3 + int(h["wait"]) + next_id) % options.size()]


# --- Who does what ----------------------------------------------------------------------------------------

## Give every idle vehicle the nearest open job of its type (players with nothing to do get a visit).
## vehicles: vid -> vehicle node (fields kind, job_id, is_player, position via global_position).
## SIMPLE_MODE: drivers (whatever they drive) bring the bricks first, the job that teaches itself (a
## glowing pick-up, a glowing new building); the AI crane leaves a site to them for a while.
func assign(vehicles: Dictionary) -> void:
	var order: Array = vehicles.keys()
	var drivers := false
	if Defs.SIMPLE_MODE:
		order.sort()  # players (vid = slot) before the AI (100+)
		for vid in order:
			drivers = drivers or bool(vehicles[vid].get("is_player"))
	var open_build := false
	if drivers:
		for id in jobs:
			open_build = open_build or (String(jobs[id]["type"]) == "build" and int(jobs[id]["vid"]) == -1)
	for vid in order:
		var v: Node3D = vehicles[vid]
		var cur := int(v.get("job_id"))
		if open_build and cur != 0 and jobs.has(cur) and String(jobs[cur]["type"]) == "visit" and bool(v.get("is_player")):
			jobs.erase(cur)  # SIMPLE_MODE: a new building beats a hello
		elif cur != 0 and jobs.has(cur):
			continue
		v.set("job_id", 0)
		var t := job_type(String(v.get("kind")))
		var player := bool(v.get("is_player"))
		var best := -1
		var bd := INF
		if Defs.SIMPLE_MODE and player:
			for id in jobs:
				var jb: Dictionary = jobs[id]
				if String(jb["type"]) == "build" and int(jb["vid"]) == -1:
					var db := target_of(jb).distance_to(v.global_position)
					if db < bd:
						bd = db
						best = int(id)
		var own_jobs := best < 0
		for id in jobs:
			if not own_jobs:
				break
			var j: Dictionary = jobs[id]
			if String(j["type"]) != t or int(j["vid"]) != -1:
				continue
			if Defs.SIMPLE_MODE and not player and t == "build":
				var age := int(j.get("age", 0))
				if (drivers and age < 12) or (int(j["to"]) == practice_site and age < 30):
					continue
			var d := target_of(j).distance_to(v.global_position)
			if d < bd:
				bd = d
				best = int(id)
		if best < 0 and bool(v.get("is_player")):
			best = _visit_for(v)
		if best >= 0:
			jobs[best]["vid"] = int(vid)
			v.set("job_id", best)


func _visit_for(v: Node3D) -> int:
	var list: Array = town.buildings.keys()
	if list.is_empty():
		return -1
	list.sort()
	var pick := int(list[(next_id * 7 + int(v.get("vid")) * 3) % list.size()])
	var b: Dictionary = town.buildings[pick]
	if int(b["stage"]) < 1 or town.dist_to(b, v.global_position) < 3.0 * Defs.CELL:
		pick = int(list[(next_id * 5 + 1) % list.size()])
	var j := _add({"type": "visit", "to": pick, "step": 1})
	return int(j["id"])


## A vehicle went away (player left / AI retired): its job goes back on the board.
func release(job_id: int) -> void:
	if not jobs.has(job_id):
		return
	var j: Dictionary = jobs[job_id]
	j["vid"] = -1
	if String(j["type"]) == "visit":
		jobs.erase(job_id)


## Where the vehicle should drive for this job right now.
func target_of(j: Dictionary) -> Vector3:
	match String(j["type"]):
		"help":
			return j.get("pos", Defs.CENTER)
		"fire":
			var b := _b(int(j["to"]))
			return town.center_of(b) if not b.is_empty() else Defs.CENTER
	var bid := int(j["from"]) if int(j["step"]) == 0 else int(j["to"])
	var bb := _b(bid)
	if bb.is_empty():
		return Defs.CENTER
	var dc := town.door_cell(bb)
	return Defs.cell_center(dc.x, dc.y)


## The building the vehicle is heading to (empty for help jobs).
func target_building(j: Dictionary) -> Dictionary:
	if String(j["type"]) == "help":
		return {}
	if String(j["type"]) == "fire":
		return _b(int(j["to"]))
	return _b(int(j["from"]) if int(j["step"]) == 0 else int(j["to"]))


# --- Arriving ---------------------------------------------------------------------------------------------------

## Check one vehicle (host, 10+ times a second). `spraying` comes back true for fire engines at work.
func update_vehicle(v: Node3D, dt: float) -> void:
	var jid := int(v.get("job_id"))
	if jid == 0 or not jobs.has(jid):
		v.set("spraying", false)
		return
	var j: Dictionary = jobs[jid]
	var pos := v.global_position
	var vid := int(v.get("vid"))
	var type := String(j["type"])
	v.set("spraying", false)
	match type:
		"fire":
			var b := _b(int(j["to"]))
			if b.is_empty():
				_finish(j, v)
				return
			if town.dist_to(b, pos) < FIRE_RANGE * Defs.CELL:
				v.set("spraying", true)
				b["fire"] = maxi(0, int(b["fire"]) - int(ceil(45.0 * dt)))
				if int(b["fire"]) <= 0:
					sim.counters["fires"] = int(sim.counters["fires"]) + 1
					sim.add_coins(8)
					_reward(vid, "fires", 1)
					_emit("fire_out", [int(b["id"]), vid])
					_finish(j, v)
		"help":
			var p: Vector3 = j.get("pos", Defs.CENTER)
			if not help_target.is_empty():
				p = help_target.get("pos", p)
				j["pos"] = p
			if Vector2(p.x - pos.x, p.z - pos.z).length() < 1.1 * Defs.CELL:
				sim.add_coins(6)
				_reward(vid, "helps", 1)
				_emit("helped", [String(j.get("sub", "cow")), vid])
				_finish(j, v)
		"visit":
			var b2 := _b(int(j["to"]))
			if b2.is_empty():
				_finish(j, v)
				return
			if town.dist_to(b2, pos) < NEAR * Defs.CELL:
				sim.counters["visits"] = int(sim.counters["visits"]) + 1
				sim.add_coins(1)
				_reward(vid, "visits", 1)
				_emit("visited", [int(b2["id"]), vid])
				_finish(j, v)
		_:
			_carry_job(j, v, dt)


func _carry_job(j: Dictionary, v: Node3D, dt: float) -> void:
	var pos := v.global_position
	var vid := int(v.get("vid"))
	var type := String(j["type"])
	var res := String(j["res"])
	if int(j["step"]) == 0:
		var from := _b(int(j["from"]))
		if from.is_empty():
			_finish(j, v)
			return
		if town.dist_to(from, pos) > NEAR * Defs.CELL:
			return
		var take := 0
		match type:
			"deliver":
				take = mini(int(j["qty"]), int(from[res]))
				from[res] = int(from[res]) - take
			"build":
				if res == "wood":
					take = mini(2, int(from["wood"]))
					from["wood"] = int(from["wood"]) - take
					if take == 0:
						j["res"] = "bricks"
						res = "bricks"
						take = 1
				else:
					take = 1
			"bus":
				take = mini(int(j["qty"]), int(from["wait"]))
				from["wait"] = int(from["wait"]) - take
		if take <= 0:
			j["wait"] = int(j["wait"]) + 1
			if float(j["wait"]) * dt > 8.0:
				_finish(j, v)  # nothing to load after a while: try something else
			return
		j["carry"] = take
		j["step"] = 1
		v.set("cargo", res)
		_emit("pickup", [vid, res, take, int(from["id"])])
		return
	var to := _b(int(j["to"]))
	if to.is_empty():
		v.set("cargo", "")
		_finish(j, v)
		return
	if town.dist_to(to, pos) > NEAR * Defs.CELL:
		return
	var carry := int(j["carry"])
	match type:
		"deliver":
			to[res] = mini(STOCK_CAP, int(to[res]) + carry)
			sim.counters["deliveries"] = int(sim.counters["deliveries"]) + 1
			sim.add_coins(3 + carry)
			_reward(vid, "deliveries", 1)
		"build":
			to["mats"] = mini(int(to["need"]), int(to["mats"]) + carry)
			sim.counters["loads"] = int(sim.counters["loads"]) + 1
			sim.add_coins(2)
			_reward(vid, "loads", 1)
		"bus":
			sim.counters["passengers"] = int(sim.counters["passengers"]) + carry
			sim.add_coins(2 * carry)
			_reward(vid, "passengers", carry)
	v.set("cargo", "")
	_emit("dropoff", [vid, res, carry, int(to["id"])])
	_finish(j, v)


func _finish(j: Dictionary, v: Node3D) -> void:
	jobs.erase(int(j["id"]))
	v.set("job_id", 0)


func _emit(kind: String, args: Array) -> void:
	if on_event.is_valid():
		on_event.call(kind, args)


func _reward(vid: int, stat: String, amount: int) -> void:
	if on_reward.is_valid():
		on_reward.call(vid, stat, amount)


# --- Words for the job cards ------------------------------------------------------------------------------------

## A job for the HUD: [type, step, title, line, target x (q), target z (q), icon, res]. Plain data (the
## net store sends it to the TV machine).
func describe(j: Dictionary) -> Array:
	var type := String(j["type"])
	var step := int(j["step"])
	var res := String(j["res"])
	var rn: String = String(Defs.RES_NAMES.get(res, res.to_upper()))
	var title := ""
	var line := ""
	var icon := "flag"
	var tb := target_building(j)
	var tname := Defs.building_name(String(tb["kind"]), int(tb["id"])) if not tb.is_empty() else ""
	match type:
		"deliver":
			title = "DELIVER " + rn
			icon = "bag"
			line = ("Pick up %s at %s" % [rn, tname]) if step == 0 else ("Bring the %s to %s" % [rn, tname])
		"build":
			var site := _b(int(j["to"]))
			var what: String = String(Defs.def(String(site.get("kind", "house"))).get("name", "HOUSE"))
			title = "BUILD THE " + what
			icon = "plus"
			line = ("Load %s at %s" % [rn, tname]) if step == 0 else ("Bring the %s to the new %s" % [rn, what.capitalize()])
		"bus":
			title = "BUS RIDE"
			icon = "person"
			line = ("Pick up %d people at %s" % [int(j["qty"]), tname]) if step == 0 else ("Take everyone to %s" % tname)
		"fire":
			title = "FIRE!"
			icon = "fire"
			line = "Rush to %s and splash out the fire!" % tname
		"help":
			if String(j.get("sub", "cow")) == "parade":
				title = "PARADE!"
				icon = "music"
				line = "Drive to the parade and lead the way!"
			else:
				title = "STRAY COW!"
				icon = "exclaim"
				line = "A cow is loose! Drive up to her to lead her home."
		"visit":
			title = "SAY HELLO"
			icon = "star"
			line = "Drive by %s and honk hello!" % tname
	var tp := target_of(j)
	return [type, step, title, line, Defs.q(tp.x), Defs.q(tp.z), icon, res]
