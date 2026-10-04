extends RefCounted
## The town simulation (host / local only), ticked once per simulated second by main.gd:
## services (power / water / roads), jobs and workers, production (farm -> food, bakery -> bread,
## sawmill -> wood), shops selling to nearby homes, people moving in, house upgrades, happiness,
## coins, construction finishing, and the population tiers (HAMLET -> VILLAGE -> TOWN -> CITY).
## There is no failure: a town that lacks something just grows more slowly, and the needs show
## as icons over the buildings and as kind hints.

const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Town := preload("res://games/tiny_town_tycoon/town.gd")

const HOMES: Array[int] = [0, 4, 8, 14]  ## residents per house level
const STOCK_CAP := 10

var town: Town
var coins := 100
var pop := 0
var happy := 60
var tier := 0
var job_slots := 0
var free_build := false
## Counters for goals and the results screen.
var counters := {"deliveries": 0, "passengers": 0, "loads": 0, "fires": 0, "festivals": 0, "trains": 0, "cows": 0,
	"built": 0, "roads": 0, "upgrades": 0, "visits": 0}
## Effects from events: festival happiness boost (seconds left), rain (seconds left).
var festival_t := 0.0
var festival_bid := 0
var rain_t := 0.0
var _coin_frac := 0.0
var _move_t := {}  # house id -> seconds to the next person moving in
var _prod := {}  # building id -> production progress 0..1
var _sell_t := {}  # shop id -> seconds to the next sale
var _wait_t := {}  # house id -> seconds to the next passenger
var _build_t := {}  # site id -> seconds of building left
var _hall_t := 0.0

## Callbacks main.gd provides: event(kind: String, args: Array) for one-off effects.
var on_event: Callable


func setup(t: Town, free: bool) -> void:
	town = t
	free_build = free
	_move_t.clear()
	_prod.clear()
	_sell_t.clear()
	_wait_t.clear()
	_build_t.clear()


func _emit(kind: String, args: Array) -> void:
	if on_event.is_valid():
		on_event.call(kind, args)


func add_coins(n: int) -> void:
	coins = maxi(0, coins + n)


func can_afford(kind: String) -> bool:
	return free_build or coins >= Defs.cost_of(kind)


func unlocked(kind: String) -> bool:
	return free_build or tier >= int(Defs.def(kind).get("tier", 0))


## One simulated second (dt may be larger when the game runs fast).
func tick(dt: float) -> void:
	festival_t = maxf(0.0, festival_t - dt)
	rain_t = maxf(0.0, rain_t - dt)
	_construction(dt)
	_staff()
	_production(dt)
	_shops(dt)
	_homes(dt)
	_hall_t += dt
	if _hall_t >= 4.0:
		_hall_t -= 4.0
		add_coins(1)
	var new_tier := Defs.tier_for_pop(pop)
	if new_tier > tier:
		tier = new_tier
		_emit("tier", [tier])


# --- Construction ------------------------------------------------------------------------------------

func _construction(dt: float) -> void:
	for id in town.buildings:
		var b: Dictionary = town.buildings[id]
		if int(b["stage"]) != 0:
			continue
		if int(b["mats"]) < int(b["need"]):
			_build_t.erase(id)
			continue
		if not _build_t.has(id):
			_build_t[id] = 2.5
			_emit("building", [int(id)])
		_build_t[id] = float(_build_t[id]) - dt
		if float(_build_t[id]) <= 0.0:
			_build_t.erase(id)
			b["stage"] = 1
			counters["built"] = int(counters["built"]) + 1
			_emit("built", [int(id)])


## Seconds of building left on a finished site (for the rising animation), -1 if not building.
func building_left(id: int) -> float:
	return float(_build_t.get(id, -1.0))


# --- Workers ---------------------------------------------------------------------------------------------

func _staff() -> void:
	var workplaces: Array[Dictionary] = []
	job_slots = 0
	for id in town.buildings:
		var b: Dictionary = town.buildings[id]
		var jobs := int(Defs.def(String(b["kind"])).get("jobs", 0))
		if jobs <= 0 or int(b["stage"]) < 1:
			b["work"] = 0
			continue
		if not town.on_road(b):
			b["work"] = 0
			continue
		job_slots += jobs
		workplaces.append(b)
	workplaces.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return int(a["id"]) < int(c["id"]))
	var free_people := pop
	# Everyone gets one worker first, then fill up.
	for b in workplaces:
		var w := 1 if free_people > 0 else 0
		b["work"] = w
		free_people -= w
	for b in workplaces:
		var jobs2 := int(Defs.def(String(b["kind"])).get("jobs", 0))
		var more := mini(jobs2 - int(b["work"]), free_people)
		if more > 0:
			b["work"] = int(b["work"]) + more
			free_people -= more


func _rate(b: Dictionary) -> float:
	var jobs := int(Defs.def(String(b["kind"])).get("jobs", 1))
	var r := float(b["work"]) / maxf(1.0, float(jobs))
	if int(b["fire"]) > 0:
		r = 0.0
	return r


# --- Production --------------------------------------------------------------------------------------------

func _production(dt: float) -> void:
	for id in town.buildings:
		var b: Dictionary = town.buildings[id]
		if int(b["stage"]) < 1:
			continue
		var kind := String(b["kind"])
		var r := _rate(b)
		match kind:
			"farm":
				var boost := 1.6 if rain_t > 0.0 else 1.0
				_make(b, "food", r * boost * dt / 5.0, "")
			"sawmill":
				_make(b, "wood", r * dt / 6.0, "")
			"bakery":
				_make(b, "bread", r * dt / 5.0, "food")


func _make(b: Dictionary, res: String, amount: float, from: String) -> void:
	var id := int(b["id"])
	if int(b[res]) >= STOCK_CAP:
		return
	if from != "" and int(b[from]) <= 0:
		return
	var p := float(_prod.get(id, 0.0)) + amount
	if p >= 1.0:
		p -= 1.0
		b[res] = int(b[res]) + 1
		if from != "":
			b[from] = int(b[from]) - 1
	_prod[id] = p


# --- Shops ---------------------------------------------------------------------------------------------------

func _shops(dt: float) -> void:
	for id in town.buildings:
		var b: Dictionary = town.buildings[id]
		if String(b["kind"]) != "shop" or int(b["stage"]) < 1:
			continue
		if _rate(b) <= 0.0:
			continue
		var t := float(_sell_t.get(id, 3.0)) - dt
		if t <= 0.0:
			t += 3.5
			if _homes_near(b, 4.5) > 0:
				if int(b["bread"]) > 0:
					b["bread"] = int(b["bread"]) - 1
					add_coins(4)
					_emit("sale", [int(id), 4])
				elif int(b["food"]) > 0:
					b["food"] = int(b["food"]) - 1
					add_coins(3)
					_emit("sale", [int(id), 3])
		_sell_t[id] = t


func _homes_near(b: Dictionary, radius: float) -> int:
	var c := town.center_of(b)
	var n := 0
	for id in town.buildings:
		var h: Dictionary = town.buildings[id]
		if String(h["kind"]) == "house" and int(h["res"]) > 0 and town.center_of(h).distance_to(c) <= radius * Defs.CELL:
			n += int(h["res"])
	return n


func _shop_stocked_near(h: Dictionary) -> bool:
	var c := town.center_of(h)
	for s in town.of_kind("shop"):
		if town.center_of(s).distance_to(c) <= 4.5 * Defs.CELL and int(s["food"]) + int(s["bread"]) > 0:
			return true
	return false


# --- Homes -----------------------------------------------------------------------------------------------------

func _homes(dt: float) -> void:
	var total := 0
	var happy_sum := 0
	var houses := 0
	for id in town.buildings:
		var b: Dictionary = town.buildings[id]
		var kind := String(b["kind"])
		var d := Defs.def(kind)
		var needs := 0
		if int(b["stage"]) < 1:
			b["needs"] = 0
			continue
		var road := town.on_road(b)
		if not road:
			needs |= Defs.N_ROAD
		if int(b["fire"]) > 0:
			needs |= Defs.N_FIRE
		if kind == "house":
			houses += 1
			var power := town.near_kind(b, "windmill", 5.0)
			var water := town.near_kind(b, "water", 5.0)
			if not power:
				needs |= Defs.N_POWER
			if not water:
				needs |= Defs.N_WATER
			var cap: int = HOMES[clampi(int(b["lvl"]), 1, 3)]
			var shop := _shop_stocked_near(b)
			var fun := town.near_kind(b, "park", 3.5) or town.near_kind(b, "landmark", 8.0) or town.near_kind(b, "ferris", 8.0)
			if not shop:
				needs |= Defs.N_SHOP
			if not fun and tier >= 1:
				needs |= Defs.N_FUN
			var h := 45
			h += 15 if power else 0
			h += 10 if water else 0
			h += 12 if shop else 0
			h += 8 if town.near_kind(b, "park", 3.5) else 0
			h += 8 if town.near_kind(b, "school", 5.0) else 0
			h += 10 if town.near_kind(b, "landmark", 8.0) else 0
			h += 10 if town.near_kind(b, "ferris", 8.0) else 0
			h += 12 if festival_t > 0.0 else 0
			h -= 25 if int(b["fire"]) > 0 else 0
			b["happy"] = clampi(h, 0, 100)
			happy_sum += int(b["happy"])
			# moving in: powered, watered homes on a road with free beds, and work (or a little slack)
			var ok := power and water and road and int(b["fire"]) == 0
			var work_ok := pop < job_slots + 6
			if ok and not work_ok and int(b["res"]) < cap:
				needs |= Defs.N_JOBS
			if ok and work_ok and int(b["res"]) < cap:
				var t := float(_move_t.get(id, 3.0)) - dt * (0.6 + float(b["happy"]) / 100.0)
				if t <= 0.0:
					t = 7.0
					b["res"] = int(b["res"]) + 1
					_emit("move_in", [int(id)])
				_move_t[id] = t
			# bigger homes for happy, full houses as the town grows
			if int(b["res"]) >= cap:
				var lvl := int(b["lvl"])
				if (lvl == 1 and tier >= 1 and int(b["happy"]) >= 62) or (lvl == 2 and tier >= 2 and int(b["happy"]) >= 72):
					b["lvl"] = lvl + 1
					counters["upgrades"] = int(counters["upgrades"]) + 1
					_emit("upgrade", [int(id)])
			# taxes
			_coin_frac += float(b["res"]) * 0.03 * dt
			# people who'd like a bus ride out
			if int(b["res"]) > 0 and road:
				var wt := float(_wait_t.get(id, 12.0)) - dt
				if wt <= 0.0:
					wt = 16.0
					if int(b["wait"]) < 4:
						b["wait"] = int(b["wait"]) + 1
				_wait_t[id] = wt
			total += int(b["res"])
		else:
			if int(d.get("jobs", 0)) > 0 and road and int(b["work"]) == 0 and String(b["kind"]) != "hall":
				needs |= Defs.N_WORKERS
			if kind == "shop" and int(b["food"]) + int(b["bread"]) == 0:
				needs |= Defs.N_STOCK
			if kind == "bakery" and int(b["food"]) == 0:
				needs |= Defs.N_STOCK
		b["needs"] = needs
	if _coin_frac >= 1.0:
		var whole := int(_coin_frac)
		_coin_frac -= whole
		add_coins(whole)
	pop = total
	happy = int(round(float(happy_sum) / houses)) if houses > 0 else 60


## A short sentence about what a building needs (VR board, TV toasts), or a happy note.
static func needs_text(b: Dictionary) -> String:
	var n := int(b.get("needs", 0))
	var kind := String(b.get("kind", ""))
	if int(b.get("stage", 1)) < 1:
		return "Waiting for the crane: %d of %d loads of bricks." % [int(b["mats"]), int(b["need"])]
	if n & Defs.N_FIRE:
		return "FIRE! Call the fire engine!"
	var parts: PackedStringArray = []
	if n & Defs.N_ROAD:
		parts.append("a road")
	if n & Defs.N_POWER:
		parts.append("power (a windmill)")
	if n & Defs.N_WATER:
		parts.append("water (a water tower)")
	if n & Defs.N_JOBS:
		parts.append("jobs (a farm or a shop)")
	if n & Defs.N_WORKERS:
		parts.append("workers (more homes)")
	if n & Defs.N_STOCK:
		parts.append("a delivery" if kind != "bakery" else "food from a farm")
	if n & Defs.N_SHOP:
		parts.append("a shop nearby")
	if n & Defs.N_FUN:
		parts.append("a park nearby")
	if parts.is_empty():
		match kind:
			"house":
				return "Happy home! %d people live here." % int(b.get("res", 0))
			"farm":
				return "Growing food: %d crates ready." % int(b.get("food", 0))
			"bakery":
				return "Smells lovely! %d loaves ready." % int(b.get("bread", 0))
			"sawmill":
				return "Busy sawing: %d logs ready." % int(b.get("wood", 0))
			"shop":
				return "Open for business! %d on the shelves." % (int(b.get("food", 0)) + int(b.get("bread", 0)))
			_:
				return "All good here!"
	return "We need " + ", ".join(parts) + "."
