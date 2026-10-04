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


func _init() -> void:
	_build()


func _build() -> void:
	spaces.clear()
	for i in RING:
		var th := float(i) / float(RING) * TAU
		var r := 10.15 + 0.45 * sin(2.0 * th + 0.7)
		_add(Vector2(sin(th) * r * 1.03, cos(th) * r), String(RING_TYPES[i]))
	for i in TRAIL_POINTS.size():
		_add(TRAIL_POINTS[i], String(TRAIL_TYPES[i]))
	for i in LAGOON_POINTS.size():
		_add(LAGOON_POINTS[i], String(LAGOON_TYPES[i]))
	for i in RING:
		_link(i, (i + 1) % RING)
	var t0 := RING
	var l0 := RING + TRAIL_POINTS.size()
	_link(TRAIL_FROM, t0)
	for i in TRAIL_POINTS.size() - 1:
		_link(t0 + i, t0 + i + 1)
	_link(t0 + TRAIL_POINTS.size() - 1, TRAIL_TO)
	_link(LAGOON_FROM, l0)
	for i in LAGOON_POINTS.size() - 1:
		_link(l0 + i, l0 + i + 1)
	_link(l0 + LAGOON_POINTS.size() - 1, LAGOON_TO)
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
	if from == TRAIL_FROM and to == RING:
		return "VOLCANO TRAIL"
	if from == LAGOON_FROM and to == RING + TRAIL_POINTS.size():
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


## Ground colour for the island mesh.
static func ground_color(x: float, z: float, h: float) -> Color:
	var p := Vector2(x, z)
	var d := p.length()
	var zone := zone_at(p)
	var c := Color(0.45, 0.78, 0.36)
	match zone:
		"candy":
			var s := 0.5 + 0.5 * sin(x * 1.3 + z * 0.9)
			c = Color(1.0, 0.7, 0.85).lerp(Color(0.72, 0.95, 0.85), s * 0.6)
		"volcano":
			c = Color(0.5, 0.42, 0.38).lerp(Color(0.36, 0.3, 0.3), clampf(h / VOLCANO_H, 0.0, 1.0))
		"meadow":
			c = Color(0.42, 0.76, 0.32).lerp(Color(0.55, 0.82, 0.35), 0.5 + 0.5 * sin(x * 0.8))
		"beach":
			c = Color(0.5, 0.8, 0.38)
		"lagoon":
			c = Color(0.55, 0.82, 0.42)
	var coast := ISLAND_R + 0.5 * sin(atan2(z, x) * 5.0) + 0.3 * sin(atan2(z, x) * 3.0 + 1.0)
	var sand := clampf((d - (coast - 2.6)) / 1.2, 0.0, 1.0)
	if zone == "beach":
		sand = clampf((d - (coast - 4.2)) / 1.5, 0.0, 1.0)
	if h < 0.25:
		sand = maxf(sand, 1.0 - clampf(h / 0.25, 0.0, 1.0))
	c = c.lerp(Color(0.98, 0.88, 0.62), sand)
	if h < -0.05:
		c = c.lerp(Color(0.86, 0.78, 0.55), 0.5)
	if zone == "volcano" and Vector2(x, z).distance_to(VOLCANO) < 1.4:
		c = Color(0.3, 0.22, 0.2)
	return c
