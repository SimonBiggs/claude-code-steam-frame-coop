extends RefCounted
## PARTY ISLAND: the board's spaces, how they connect, and the island's shape (heights and zones),
## in board units (a token is ~1.4 units tall; main.gd scales the whole stage: 1 unit = 1 m on the
## TV, 6.5 cm on the VR player's table).
## Layout (seen from above, +X east, +Z south = towards the VR player):
##   - the RING: 28 spaces round the coast, counter-clockwise: Sunny Beach (south, START), Candy
##     Forest (east), Volcano Ridge (north), Meadow River (west, a bridge over the river);
##   - the VOLCANO TRAIL: a risky 6-space shortcut from the east junction over the volcano's foot to
##     the west (more red / event / duel spaces);
##   - the LAGOON BOARDWALK: a 5-space pier over the lagoon from the south-west junction to the
##     south-east, skipping START.
## Space types: blue (+coins), red (-coins), event (a random happening), shop (items), duel, start.
## Star spots: blue spaces the STAR can sit on (it moves after every purchase).

const RING := 28
const RING_TYPES := ["start", "blue", "blue", "event", "blue", "red", "blue", "blue", "shop", "blue",
	"event", "blue", "red", "duel", "blue", "blue", "event", "blue", "red", "shop", "blue", "blue", "red",
	"event", "blue", "duel", "blue", "red"]
## Volcano trail (from ring 7 to ring 21) and lagoon boardwalk (from ring 23 to ring 3).
const TRAIL_POINTS := [Vector2(7.3, -1.1), Vector2(4.6, 0.25), Vector2(1.6, 0.8), Vector2(-1.5, 0.8),
	Vector2(-4.5, 0.3), Vector2(-7.5, -0.5)]
const TRAIL_TYPES := ["blue", "red", "event", "duel", "red", "event"]
const LAGOON_POINTS := [Vector2(-6.6, 4.1), Vector2(-3.5, 4.55), Vector2(-0.3, 4.75), Vector2(2.9, 4.7),
	Vector2(5.9, 5.5)]
const LAGOON_TYPES := ["blue", "event", "blue", "red", "blue"]
const TRAIL_FROM := 7
const TRAIL_TO := 21
const LAGOON_FROM := 23
const LAGOON_TO := 3

const ISLAND_R := 13.2
const WATER_Y := 0.0
const GROUND_Y := 0.55
const VOLCANO := Vector2(0.0, -4.7)
const VOLCANO_R := 4.4
const VOLCANO_H := 6.2
const LAGOON := Vector2(-0.2, 4.9)
const LAGOON_R := 2.4
const RIVER := [Vector2(-3.4, -3.6), Vector2(-5.3, -1.7), Vector2(-6.3, -0.15), Vector2(-7.7, 1.7),
	Vector2(-9.8, 3.45), Vector2(-14.0, 5.4)]
const RIVER_W := 0.75

## Space colours (tile, emblem).
const TYPE_COLORS := {
	"blue": [Color(0.25, 0.55, 1.0), Color(1, 1, 1)],
	"red": [Color(0.95, 0.3, 0.3), Color(1, 1, 1)],
	"event": [Color(0.3, 0.85, 0.45), Color(1.0, 0.95, 0.4)],
	"shop": [Color(1.0, 0.7, 0.2), Color(1, 1, 1)],
	"duel": [Color(0.65, 0.4, 0.95), Color(1, 1, 1)],
	"start": [Color(0.98, 0.98, 1.0), Color(0.25, 0.55, 1.0)],
}
const TYPE_NAMES := {"blue": "BLUE SPACE", "red": "RED SPACE", "event": "EVENT SPACE", "shop": "ITEM SHOP",
	"duel": "DUEL SPACE", "start": "START"}

## spaces[i] = {id, pos (Vector3, on the ground), type, next (Array of ids), zone, star_ok, junction}
var spaces: Array = []
var simple := false  ## SIMPLE_MODE board: only blue (good), red (bad) and START (make_simple())
## SEEDED LAYOUTS (partygen.gd layout()): {ring: spaces round the coast, wob: [amplitude, phase] of the coast
## road's wiggle (and its middle radius, 10.15 when left out), trail: [from ring id, to ring id, [Vector2 points]] or [], pier: the same or []}. The classic
## island (LAYOUT_CLASSIC) is what BD.new() builds. A seeded layout keeps the island's shape (volcano, lagoon,
## river) but changes how many spaces the coast road has, how it wiggles, which shortcuts exist and how long.
var layout: Dictionary = {}
var ring := RING
var trail_from := -1  ## ring id where the volcano trail starts (-1 = no trail)
var trail_to := -1
var trail0 := -1  ## first trail space id
var trail_n := 0
var pier_from := -1
var pier_to := -1
var pier0 := -1
var pier_n := 0


func _init() -> void:
	build_layout(classic_layout())


static func classic_layout() -> Dictionary:
	return {"ring": RING, "wob": [0.45, 0.7], "trail": [TRAIL_FROM, TRAIL_TO, TRAIL_POINTS.duplicate()],
		"pier": [LAGOON_FROM, LAGOON_TO, LAGOON_POINTS.duplicate()]}


## A coast-road spot for ring space i of n (with the layout's wiggle).
static func ring_point(i: int, n: int, wob: Array) -> Vector2:
	var th := float(i) / float(n) * TAU
	var r := (float(wob[2]) if wob.size() > 2 else 10.15) + float(wob[0]) * sin(2.0 * th + float(wob[1]))
	return Vector2(sin(th) * r * 1.03, cos(th) * r)


## Build the spaces from a layout (see `layout`). Space types: the classic ones on the classic layout,
## otherwise blue (partygen.gd colours them in).
func build_layout(lay: Dictionary) -> void:
	layout = lay
	spaces.clear()
	ring = int(lay.get("ring", RING))
	var wob: Array = lay.get("wob", [0.45, 0.7])
	var classic := ring == RING and var_to_str(lay) == var_to_str(classic_layout())
	for i in ring:
		_add(ring_point(i, ring, wob), String(RING_TYPES[i]) if classic else ("start" if i == 0 else "blue"))
	trail_from = -1
	trail_to = -1
	trail0 = -1
	trail_n = 0
	pier_from = -1
	pier_to = -1
	pier0 = -1
	pier_n = 0
	var tr: Array = lay.get("trail", [])
	if tr.size() == 3 and not (tr[2] as Array).is_empty():
		trail_from = int(tr[0])
		trail_to = int(tr[1])
		trail0 = spaces.size()
		var pts: Array = tr[2]
		trail_n = pts.size()
		for i in pts.size():
			_add(pts[i], String(TRAIL_TYPES[i % TRAIL_TYPES.size()]) if classic else "blue")
	var pr: Array = lay.get("pier", [])
	if pr.size() == 3 and not (pr[2] as Array).is_empty():
		pier_from = int(pr[0])
		pier_to = int(pr[1])
		pier0 = spaces.size()
		var pts2: Array = pr[2]
		pier_n = pts2.size()
		for i in pts2.size():
			_add(pts2[i], String(LAGOON_TYPES[i % LAGOON_TYPES.size()]) if classic else "blue")
	for i in ring:
		_link(i, (i + 1) % ring)
	if trail_n > 0:
		_link(trail_from, trail0)
		for i in trail_n - 1:
			_link(trail0 + i, trail0 + i + 1)
		_link(trail0 + trail_n - 1, trail_to)
	if pier_n > 0:
		_link(pier_from, pier0)
		for i in pier_n - 1:
			_link(pier0 + i, pier0 + i + 1)
		_link(pier0 + pier_n - 1, pier_to)
	for s in spaces:
		var sp: Dictionary = s
		var nx: Array = sp["next"]
		sp["junction"] = nx.size() > 1
		sp["zone"] = zone_at(Vector2(sp["pos"].x, sp["pos"].z))
		sp["star_ok"] = String(sp["type"]) == "blue" and not sp["junction"]


func _add(p: Vector2, type: String) -> void:
	var id := spaces.size()
	var y := maxf(height(p.x, p.y), WATER_Y + 0.35)
	spaces.append({"id": id, "pos": Vector3(p.x, y + 0.02, p.y), "type": type, "next": [], "zone": "", "star_ok": false,
		"junction": false})


func _link(a: int, b: int) -> void:
	var nx: Array = spaces[a]["next"]
	nx.append(b)


## SIMPLE_MODE: event, shop and duel spaces become plain blue ones (nothing to explain), so the board
## only has blue (good: a bonus hop forward), red (bad: slide back) and START; the STAR can sit on any
## blue space that isn't a junction.
func make_simple() -> void:
	simple = true
	for s in spaces:
		var sp: Dictionary = s
		if String(sp["type"]) in ["event", "shop", "duel"]:
			sp["type"] = "blue"
		sp["star_ok"] = String(sp["type"]) == "blue" and not sp["junction"]


## A seeded party's space types (partygen.gd: blue / red / start per space); star spots follow.
func set_types(types: Array) -> void:
	for i in mini(types.size(), spaces.size()):
		var sp: Dictionary = spaces[i]
		sp["type"] = String(types[i])
		sp["star_ok"] = String(sp["type"]) == "blue" and not sp["junction"]


## The space types as an Array (what the board looks like now).
func types() -> Array:
	var out: Array = []
	for s in spaces:
		out.append(String(s["type"]))
	return out


# --- Queries --------------------------------------------------------------------------------------

func count() -> int:
	return spaces.size()


func pos(id: int) -> Vector3:
	return spaces[clampi(id, 0, spaces.size() - 1)]["pos"]


func type_of(id: int) -> String:
	return String(spaces[clampi(id, 0, spaces.size() - 1)]["type"])


func next_of(id: int) -> Array:
	return spaces[clampi(id, 0, spaces.size() - 1)]["next"]


func is_junction(id: int) -> bool:
	return bool(spaces[clampi(id, 0, spaces.size() - 1)]["junction"])


## Spaces that lead to `id` (used to put a warped player "just before" the star).
func prev_of(id: int) -> Array:
	var out: Array = []
	for s in spaces:
		var nx: Array = s["next"]
		if nx.has(id):
			out.append(int(s["id"]))
	return out


## Every space the star may sit on.
func star_spots() -> Array:
	var out: Array = []
	for s in spaces:
		if bool(s["star_ok"]):
			out.append(int(s["id"]))
	return out


## Fewest steps from `from` to `to` (following the arrows), or 999.
func distance(from: int, to: int) -> int:
	if from == to:
		return 0
	var seen := {from: 0}
	var q: Array = [from]
	while not q.is_empty():
		var c: int = q.pop_front()
		for n in next_of(c):
			var ni := int(n)
			if seen.has(ni):
				continue
			seen[ni] = int(seen[c]) + 1
			if ni == to:
				return int(seen[ni])
			q.append(ni)
	return 999


## Friendly name of a path choice at a junction (for menus and arrows).
func branch_name(from: int, to: int) -> String:
	if from == trail_from and to == trail0:
		return "VOLCANO TRAIL"
	if from == pier_from and to == pier0:
		return "LAGOON PIER"
	return "COAST ROAD"


# --- Island shape ---------------------------------------------------------------------------------

## Ground height at (x, z): beach slope, volcano, lagoon and river beds (water is at y = 0).
static func height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var d := p.length()
	var wob := 0.5 * sin(atan2(z, x) * 5.0) + 0.3 * sin(atan2(z, x) * 3.0 + 1.0)
	var coast := ISLAND_R + wob
	var h := GROUND_Y * clampf((coast - d) / 2.2, 0.0, 1.0)
	h -= 1.2 * clampf((d - coast) / 3.0, 0.0, 1.0)
	h += 0.18 * sin(x * 0.7) * cos(z * 0.6) * clampf((coast - d) / 3.0, 0.0, 1.0)
	var dv := p.distance_to(VOLCANO)
	if dv < VOLCANO_R:
		var k := 1.0 - dv / VOLCANO_R
		h += VOLCANO_H * pow(k, 1.5)
		if dv < 1.0:
			h -= 1.3 * (1.0 - dv)  # crater
	var dl := p.distance_to(LAGOON)
	if dl < LAGOON_R + 0.8:
		h = lerpf(h, -0.6, clampf((LAGOON_R + 0.8 - dl) / 1.2, 0.0, 1.0))
	var dr := river_distance(p)
	if dr < RIVER_W + 0.5 and dv > VOLCANO_R * 0.75:
		h = lerpf(h, -0.45, clampf((RIVER_W + 0.5 - dr) / 0.7, 0.0, 1.0))
	return h


## Distance from p to the river's centre line.
static func river_distance(p: Vector2) -> float:
	var best := INF
	for i in RIVER.size() - 1:
		var a: Vector2 = RIVER[i]
		var b: Vector2 = RIVER[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Which part of the island (x, z) is in: "beach", "candy", "volcano", "meadow", "lagoon".
static func zone_at(p: Vector2) -> String:
	if p.distance_to(LAGOON) < LAGOON_R + 1.6:
		return "lagoon"
	if p.distance_to(VOLCANO) < VOLCANO_R + 1.4:
		return "volcano"
	var a := rad_to_deg(atan2(p.x, p.y))  # 0 = south, 90 = east
	if a < 0.0:
		a += 360.0
	if a < 55.0 or a > 305.0:
		return "beach"
	if a < 145.0:
		return "candy"
	if a < 215.0:
		return "volcano"
	return "meadow"


## Ground colour for the island mesh, dressed for a board (boards.gd ids: island, sweet, pirate, haunted, space).
static func ground_color(x: float, z: float, h: float, theme: String = "island") -> Color:
	var p := Vector2(x, z)
	var d := p.length()
	var zone := zone_at(p)
	var c := Color(0.45, 0.78, 0.36)
	var vk := clampf(h / VOLCANO_H, 0.0, 1.0)
	match zone:
		"candy":
			var s := 0.5 + 0.5 * sin(x * 1.3 + z * 0.9)
			c = Color(1.0, 0.7, 0.85).lerp(Color(0.72, 0.95, 0.85), s * 0.6)
		"volcano":
			c = Color(0.5, 0.42, 0.38).lerp(Color(0.36, 0.3, 0.3), vk)
		"meadow":
			c = Color(0.42, 0.76, 0.32).lerp(Color(0.55, 0.82, 0.35), 0.5 + 0.5 * sin(x * 0.8))
		"beach":
			c = Color(0.5, 0.8, 0.38)
		"lagoon":
			c = Color(0.55, 0.82, 0.42)
	var sand_c := Color(0.98, 0.88, 0.62)
	var wave := 0.5 + 0.5 * sin(x * 0.9 + z * 0.7)
	match theme:
		"sweet":  # mint and strawberry icing, a chocolate mountain with a pink frosting top, biscuit beaches
			c = Color(0.75, 0.95, 0.85).lerp(Color(1.0, 0.75, 0.88), 0.5 + 0.5 * sin(x * 0.8 + z * 1.1))
			if zone == "volcano":
				c = Color(0.48, 0.3, 0.2).lerp(Color(1.0, 0.65, 0.82), smoothstep(0.35, 0.6, vk))
			sand_c = Color(0.93, 0.76, 0.5)
		"pirate":  # deep jungle, grey skull rock, golden sand
			c = Color(0.22, 0.58, 0.28).lerp(Color(0.35, 0.68, 0.3), wave)
			if zone == "volcano":
				c = Color(0.55, 0.55, 0.56).lerp(Color(0.38, 0.38, 0.42), vk)
			sand_c = Color(1.0, 0.86, 0.5)
		"haunted":  # dusky moss, a purple hill, misty grey sand (spooky but friendly)
			c = Color(0.32, 0.42, 0.33).lerp(Color(0.4, 0.36, 0.48), wave * 0.6)
			if zone == "volcano":
				c = Color(0.38, 0.32, 0.45).lerp(Color(0.26, 0.22, 0.32), vk)
			sand_c = Color(0.7, 0.66, 0.62)
		"space":  # moon dust with craters, a metal dome hill, pale grey shores
			var crater := 0.5 + 0.5 * sin(x * 2.1) * sin(z * 1.9)
			c = Color(0.62, 0.62, 0.7).lerp(Color(0.5, 0.48, 0.62), crater)
			if zone == "volcano":
				c = Color(0.7, 0.72, 0.78).lerp(Color(0.55, 0.58, 0.66), vk)
			sand_c = Color(0.8, 0.8, 0.86)
	var coast := ISLAND_R + 0.5 * sin(atan2(z, x) * 5.0) + 0.3 * sin(atan2(z, x) * 3.0 + 1.0)
	var sand := clampf((d - (coast - 2.6)) / 1.2, 0.0, 1.0)
	if zone == "beach":
		sand = clampf((d - (coast - 4.2)) / 1.5, 0.0, 1.0)
	if h < 0.25:
		sand = maxf(sand, 1.0 - clampf(h / 0.25, 0.0, 1.0))
	c = c.lerp(sand_c, sand)
	if h < -0.05:
		c = c.lerp(sand_c.darkened(0.15), 0.5)
	if zone == "volcano" and Vector2(x, z).distance_to(VOLCANO) < 1.4:
		c = {"sweet": Color(1.0, 0.95, 0.97), "pirate": Color(0.3, 0.3, 0.33), "haunted": Color(0.22, 0.18, 0.28),
			"space": Color(0.45, 0.48, 0.55)}.get(theme, Color(0.3, 0.22, 0.2))
	return c
