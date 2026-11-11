extends RefCounted
## MARBLE MAZE second pass (pure data + small pure functions: host, TV machines and tests agree):
##   MODES    GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES, picked on the pick board each session): holes in the
##            story mazes, how many told events come, how early they are told and how strong they are.
##   MARBLES  Bobo's gift marbles (picked on the pick board before each new place and today's maze; the whole team
##            rolls as that kind until the next gift): HEAVY (quakes, bumpers and hole lips hardly move it), BOUNCY
##            (boings back out of a hole), MAGNET (pulled to the shiny and the goal when close), then unlocked by the
##            marble run's size STICKY (grips ice, quakes half) and ZOOMY (rolls faster).
##   WORLDS   TODAY'S WORLD (seeded by the date, weighted by the season; the same on every machine): SUNNY, SNOW DAY
##            (+1 ice room, snow falling), WINDY (+1 zoom-arrow run, leaves blowing), PARTY (+1 bumper, confetti),
##            STARRY NIGHT (a dark sky with stars; the board keeps its light) and FLOWER DAY (+1 loop, petals).
##            Worlds never recolour the board's floor: every marble colour must stand out on every floor
##            (contrast_problems(); 2026-11: white sheep vanished on Sheep Round-Up's snow).
##   EVENTS   told first by warn rings on the board (events.gd): TILT QUAKE (the board wobbles and pushes every
##            marble one way for a moment; a flashing stripe shows which way) and CLOSING GATE (a red disc pulses on
##            a narrow doorway along the way, then a gate pops up there for a few seconds and sinks again).
##            events(def, mode) makes a maze's list from its seed; event_problems() proves it fair (see below).

const PickOrbs := preload("res://core/pick_orbs.gd")
const Seeded := preload("res://core/seeded.gd")
const MazeGen := preload("res://games/marble_maze/mazegen.gd")

## Per mode. holes: added to a story / daily maze's holes. events: how many told events a maze may bring (one after
## another while it's played). first / gap: seconds of play before the first and between the next ones. warn: how
## long the rings are shown first. quake: the push (board units / s^2; a marble's own steering is MarbleScript.STEER
## = 0.45 and always wins). quake_secs / gate_secs: how long a quake pushes / a gate stays up.
const MODES := {
	"gentle": {"holes": -1, "events": 2, "first": 16.0, "gap": 22.0, "warn": 3.2, "quake": 0.14, "quake_secs": 1.4, "gate_secs": 4.0},
	"brave": {"holes": 0, "events": 4, "first": 11.0, "gap": 15.0, "warn": 2.6, "quake": 0.22, "quake_secs": 2.0, "gate_secs": 5.5},
	"hard": {"holes": 1, "events": 6, "first": 8.0, "gap": 11.0, "warn": 2.1, "quake": 0.3, "quake_secs": 2.4, "gate_secs": 7.0},
}
const STEER := 0.45  # marble.gd STEER (the validator proves every quake is weaker)
const MIN_WARN := 2.0
const MAX_GATE := 8.0

## Bobo's gift marbles. unlock: marbles on Bobo's marble run (save "rack") before it can be picked.
const MARBLES: Array[Dictionary] = [
	{"id": "heavy", "name": "HEAVY", "pic": "heavymarble", "color": Color(0.62, 0.68, 0.8), "unlock": 0},
	{"id": "bouncy", "name": "BOUNCY", "pic": "bouncymarble", "color": Color(1.0, 0.45, 0.8), "unlock": 0},
	{"id": "magnet", "name": "MAGNET", "pic": "magnetmarble", "color": Color(1.0, 0.3, 0.3), "unlock": 0},
	{"id": "sticky", "name": "STICKY", "pic": "stickymarble", "color": Color(0.55, 0.95, 0.3), "unlock": 6},
	{"id": "zoomy", "name": "ZOOMY", "pic": "zoomymarble", "color": Color(1.0, 0.75, 0.15), "unlock": 15},
]
## Effects (marble.gd / board.gd read these): how much of a quake / bumper kick / hole pull reaches the marble.
const QUAKE_K := {"heavy": 0.3, "sticky": 0.5}
const BUMP_K := {"heavy": 0.5}
const HOLE_K := {"heavy": 0.5}
const STEER_K := {"zoomy": 1.35}
const SPEED_K := {"zoomy": 1.15}
const MAGNET_ACC := 0.35
const MAGNET_CELLS := 3.0
const BOUNCE_COOL := 2.0

const SEASONS: Array[String] = ["spring", "summer", "autumn", "winter"]
## Today's world. spec: added to the maze spec. sky: the room's background (the floor never changes).
## weights: how likely per season.
const WORLDS: Array[Dictionary] = [
	{"id": "sunny", "name": "SUNNY DAY", "pic": "sun", "color": Color(1.0, 0.85, 0.3), "spec": {},
		"sky": Color(0.62, 0.84, 1.0), "fx": "", "weights": {"spring": 2.0, "summer": 4.0, "autumn": 1.5, "winter": 1.0}},
	{"id": "snow", "name": "SNOW DAY", "pic": "snowflake", "color": Color(0.75, 0.9, 1.0), "spec": {"ice": 1},
		"sky": Color(0.78, 0.84, 0.92), "fx": "snow", "weights": {"spring": 0.0, "summer": 0.0, "autumn": 0.5, "winter": 4.0}},
	{"id": "windy", "name": "WINDY DAY", "pic": "tree", "color": Color(1.0, 0.6, 0.25), "spec": {"arrows": 1},
		"sky": Color(0.7, 0.8, 0.9), "fx": "leaves", "weights": {"spring": 1.0, "summer": 0.5, "autumn": 4.0, "winter": 1.0}},
	{"id": "party", "name": "PARTY DAY", "pic": "gift", "color": Color(1.0, 0.5, 0.8), "spec": {"bumpers": 1},
		"sky": Color(0.95, 0.8, 1.0), "fx": "confetti", "weights": {"spring": 1.5, "summer": 1.5, "autumn": 1.5, "winter": 1.5}},
	{"id": "night", "name": "STARRY NIGHT", "pic": "star", "color": Color(0.55, 0.55, 1.0), "spec": {},
		"sky": Color(0.08, 0.08, 0.2), "fx": "stars", "weights": {"spring": 1.0, "summer": 1.0, "autumn": 1.5, "winter": 2.0}},
	{"id": "bloom", "name": "FLOWER DAY", "pic": "sunflower", "color": Color(0.5, 0.9, 0.4), "spec": {"loops": 1},
		"sky": Color(0.75, 0.92, 1.0), "fx": "petals", "weights": {"spring": 4.0, "summer": 2.0, "autumn": 0.0, "winter": 0.0}},
]
const EVENT_COLORS := {"quake": Color(1.0, 0.6, 0.15), "gate": Color(1.0, 0.25, 0.3)}
## The marble colours players roll as (main.gd PLAYER_COLORS 1..6; the giant's own solo marble is P2's).
const MARBLE_COLORS: Array[Color] = [Color(1.0, 0.3, 0.3), Color(0.25, 0.6, 1.0), Color(0.35, 0.9, 0.35),
	Color(1.0, 0.8, 0.1), Color(0.8, 0.4, 1.0), Color(1.0, 0.55, 0.15)]
const MIN_CONTRAST := 0.3


static func mode_of(id: String) -> Dictionary:
	var m := String(PickOrbs.mode(id).get("id", "brave"))
	return MODES.get(m, MODES["brave"])


static func marble(id: String) -> Dictionary:
	for m in MARBLES:
		if String(m.id) == id:
			return m
	return {}


static func marble_index(id: String) -> int:
	for i in MARBLES.size():
		if String(MARBLES[i].id) == id:
			return i
	return -1


## The gift marbles the team can pick with `rack` marbles on the run.
static func unlocked(rack: int) -> Array:
	var out: Array = []
	for m in MARBLES:
		if rack >= int(m.unlock):
			out.append(String(m.id))
	return out


## Three gift ids to offer (seeded): the newest unlock always among them, the last gift only if there's no other.
static func gift_choices(rack: int, last: String, seed_value: int) -> Array:
	var ids := unlocked(rack)
	var r := Seeded.rng(seed_value, "gifts")
	var newest: String = ids[ids.size() - 1]
	var pool: Array = []
	for id in ids:
		if id != newest and id != last:
			pool.append(id)
	pool = Seeded.shuffled(r, pool)
	var out: Array = [newest] if newest != last else []
	for id in pool:
		if out.size() < 3:
			out.append(id)
	if out.size() < 3 and last != "" and ids.has(last):
		out.append(last)
	return Seeded.shuffled(r, out)


static func season_of(date: String) -> String:
	var parts := date.split("-")
	var month := int(parts[1]) if parts.size() >= 2 else 6
	if month == 12 or month <= 2:
		return "winter"
	if month <= 5:
		return "spring"
	if month <= 8:
		return "summer"
	return "autumn"


## Today's world (MM_WORLD=<id> forces one: What's New "try" and bots).
static func world_of(date: String) -> Dictionary:
	if OS.has_environment("MM_WORLD"):
		for w in WORLDS:
			if String(w.id) == OS.get_environment("MM_WORLD"):
				return w
	var season := season_of(date)
	var r := Seeded.rng(Seeded.daily_seed("marble_maze_world", date), "world")
	var ws: Array = []
	for w in WORLDS:
		ws.append(float((w.weights as Dictionary).get(season, 0.0)))
	return WORLDS[Seeded.weighted(r, ws)]


static func world(id: String) -> Dictionary:
	for w in WORLDS:
		if String(w.id) == id:
			return w
	return WORLDS[0]


## A story / daily spec with the mode and today's world in it.
static func apply(spec: Dictionary, mode_id: String, world_id: String) -> Dictionary:
	var s := spec.duplicate()
	var m := mode_of(mode_id)
	s["holes"] = maxi(1, int(s.get("holes", 0)) + int(m.holes))
	var add: Dictionary = world(world_id).spec
	for k in add:
		s[k] = int(s.get(k, 0)) + int(add[k])
	return s


# --- Events --------------------------------------------------------------------------------------

static func _grid(def: Dictionary) -> Array:
	var g: Array = []
	for row in def.get("map", []):
		var a: Array = []
		for k in str(row):
			a.append(k)
		g.append(a)
	return g


## Narrow doorways along the way to the goal a closing gate may use: plain floor with walls on both sides across
## the way, nothing special next to it (start, goal, holes, bumpers, teleporters, zoom arrows, team pads / gates,
## the shiny, ice), so a gate only ever makes the team wait a moment.
static func gate_spots(def: Dictionary) -> Array:
	var g := _grid(def)
	if g.size() != MazeGen.H:
		return []
	var out: Array = []
	var path: Array = MazeGen._path(g)
	for i in range(2, path.size() - 2):
		var c: Vector2i = path[i]
		if MazeGen._at(g, c) != ".":
			continue
		if MazeGen._near(g, c, "SGOBTPDEQ*I><^v", true):
			continue
		var lr: bool = MazeGen._at(g, c + Vector2i(1, 0)) == "#" and MazeGen._at(g, c + Vector2i(-1, 0)) == "#"
		var ud: bool = MazeGen._at(g, c + Vector2i(0, 1)) == "#" and MazeGen._at(g, c + Vector2i(0, -1)) == "#"
		if lr != ud:
			out.append(c)
	return out


## A maze's told events: [t (seconds of play when it starts), kind, a, b]. quake: a, b = push direction (unit).
## gate: a, b = the doorway cell. Same def + mode = same list on every machine.
static func events(def: Dictionary, mode_id: String) -> Array:
	var m := mode_of(mode_id)
	var r := Seeded.rng(int(def.get("seed", 0)), "mm_events_" + String(PickOrbs.mode(mode_id).get("id", "brave")))
	var spots := gate_spots(def)
	var used := {}
	var out: Array = []
	for i in int(m.events):
		var t := float(m.first) + float(m.gap) * i + r.randf_range(-1.5, 1.5)
		var kind := "quake"
		if not spots.is_empty() and r.randf() < 0.5:
			kind = "gate"
		if kind == "gate":
			var c: Vector2i = spots[r.randi() % spots.size()]
			if used.has(c) and used.size() < spots.size():
				for s in spots:
					if not used.has(s):
						c = s
						break
			used[c] = true
			out.append([snappedf(t, 0.1), "gate", c.x, c.y])
		else:
			var a := r.randi() % 8 * TAU / 8.0
			out.append([snappedf(t, 0.1), "quake", snappedf(cos(a), 0.001), snappedf(sin(a), 0.001)])
	return out


## Reasons a maze's events are unfair ([] = fine): told early enough, weaker than a marble's own push, gates only on
## a doorway from gate_spots() (never the start, goal, shiny, a hole's edge ...), never up for long, never two
## events at once.
static func event_problems(def: Dictionary, list: Array, mode_id: String) -> Array:
	var why: Array = []
	var m := mode_of(mode_id)
	if float(m.warn) < MIN_WARN:
		why.append("told too late (%.1f s)" % float(m.warn))
	if float(m.quake) >= STEER * 0.8:
		why.append("a quake beats a marble's own push")
	if float(m.gate_secs) > MAX_GATE:
		why.append("a gate stays up too long")
	var spots := gate_spots(def)
	var last_end := -INF
	for e in list:
		var t := float(e[0])
		if t - float(m.warn) < 4.0:
			why.append("an event before the marbles get going (%.1f s)" % t)
		if t < last_end + 0.5:
			why.append("two events at once (%.1f s)" % t)
		var dur := float(m.quake_secs) if String(e[1]) == "quake" else float(m.gate_secs)
		last_end = t + dur
		if String(e[1]) == "gate":
			var c := Vector2i(int(e[2]), int(e[3]))
			if not spots.has(c):
				why.append("a gate on a cell that isn't a safe doorway %s" % str(c))
		elif String(e[1]) == "quake":
			if absf(Vector2(float(e[2]), float(e[3])).length() - 1.0) > 0.01:
				why.append("a quake without a direction")
		else:
			why.append("unknown event %s" % str(e[1]))
	return why


## Every marble colour stands out on every theme's floor in every world (worlds never recolour the floor, so the
## floors are THEMES' A / B colours): [] = fine.
static func contrast_problems(themes: Dictionary) -> Array:
	var why: Array = []
	for th in themes:
		var t: Array = themes[th]
		for f in [t[0], t[1]]:
			var fc: Color = f
			for mc in MARBLE_COLORS:
				var d := Vector3(fc.r - mc.r, fc.g - mc.g, fc.b - mc.b).length()
				if d < MIN_CONTRAST:
					why.append("marble %s hard to see on the %s floor" % [mc.to_html(false), th])
	return why


## The order the difficulty must rise in (tests): every number gentle <= brave <= hard (warn / first / gap: >=).
static func ordered() -> Array:
	var why: Array = []
	var g: Dictionary = MODES.gentle
	var b: Dictionary = MODES.brave
	var h: Dictionary = MODES.hard
	for k in ["holes", "events", "quake", "quake_secs", "gate_secs"]:
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			why.append("%s not gentle <= brave <= hard" % k)
	for k in ["warn", "first", "gap"]:
		if not (float(g[k]) >= float(b[k]) and float(b[k]) >= float(h[k])):
			why.append("%s not gentle >= brave >= hard" % k)
	return why
