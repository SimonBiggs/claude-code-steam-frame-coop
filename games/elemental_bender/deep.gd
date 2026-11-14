extends RefCounted
## ELEMENTAL BENDER, the second pass (data + generators; every machine computes the same from the same numbers):
## - MODES: after practice the team votes GENTLE / BRAVE / HARD on Kiko's altar (picks.gd on the shared pick flow's
##   vote mode, core/pick_flow.gd: the most votes, a tie stays gentler; the shared core/pick_orbs.gd MODES: names, colours).
##   GENTLE: fewer, softer, slower raiders, kind bosses, long warnings, soft surprises. HARD: more, tougher raiders and two surprises a wave. The family's last mode sits in the middle stone (saved "mode").
## - SURPRISES (Kiko's island tricks, from wave 3, never on a boss wave): every island has two, always TOLD first by a
##   steady warning on the ground (the shared core/warn_rings.gd) for tell() seconds, then they go off:
##     RAIN  (a few circles): FALLING ROCKS / ICICLES / LAVA BOMBS / LIGHTNING drop into them
##     SWEEP (a band across the island, never over the temple): BIG WAVE / AVALANCHE / LAVA FLOW / GUST rolls along
##           it: raiders inside are swept towards the sea (a ring-out if you lure them in!), benders get a small bump
##           towards home.
##   surprises(temple_seed, wave, arena, mode) -> [{kind, at, tell, shapes: [[shape, pos, dir, size]...]}], and
##   check_surprises() is the validator (tests/elemental_bender_gen_test.gd, over many seeds and 400 TODAY'S days).
## - SPIRIT FRIENDS (story): every island's boss holds a little element spirit (the Shadow General: PEBBLE, the
##   Frost Giant: DRIP, the Lava Drake: EMBER, the Storm Hawk: PUFF). Beat the boss and the friend is FREE: it flies
##   round the Spirit Tree for good, a bit bigger every time that boss falls again (levels from the saved "bosses").
##   Every SPIRIT_HOUSE_EVERY bosses beaten (all kinds), a little spirit house lights up in the Spirit Tree.
## - SEASONS: SeasonKit.override (ARCADE_SEASON / ARCADE_SEASON_ELEMENTAL_BENDER) or the real season: season props on
##   every island's beach rim, the season's petals / leaves / snow drifting over it, and Kiko's seasonal outfit.

const Seeded := preload("res://core/seeded.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const Arenas := preload("res://games/elemental_bender/arenas.gd")
const WaveGen := preload("res://games/elemental_bender/wavegen.gd")
const E := preload("res://games/elemental_bender/elem.gd")

const GAME_ID := "elemental_bender"

# --- Modes -------------------------------------------------------------------------------------------

## count / hp / speed: raider multipliers; kid: the slow-kid model's damage for this mode (the little ones play
## GENTLE, the big ones HARD: tests/elemental_bender_gen_test.gd); rush: surprises a wave; tell: their warning.
const MODES := {
	"gentle": {"count": 0.7, "hp": 0.8, "speed": 0.85, "kid": 0.85, "kind_boss": true, "rush": 1, "tell": 3.0, "dmg": 0.5},
	"brave": {"count": 1.0, "hp": 1.0, "speed": 1.0, "kid": 1.0, "kind_boss": false, "rush": 1, "tell": 2.2, "dmg": 1.0},
	"hard": {"count": 1.25, "hp": 1.15, "speed": 1.0, "kid": 1.45, "kind_boss": false, "rush": 2, "tell": 1.8, "dmg": 1.0},
}
const MODE_IDS: Array[String] = ["gentle", "brave", "hard"]


## The numbers of a mode (old / unknown ids: BRAVE; aliases through PickOrbs).
static func mode(id: String) -> Dictionary:
	var m := String(PickOrbs.mode(id).get("id", "brave"))
	return MODES.get(m, MODES["brave"])


static func mode_id(id: String) -> String:
	var m := String(PickOrbs.mode(id).get("id", "brave"))
	return m if MODES.has(m) else "brave"


# --- Surprises ---------------------------------------------------------------------------------------

const KID_SPEED := 3.0  # m/s a small kid surely walks (benders run 7)
const MIN_TELL := 1.6  # no surprise is told for less (HARD's 1.8 has room)
const FIRST_AT := 8.0  # seconds into a wave before the first one
const GAP := 7.0  # seconds of calm between one going off and the next tell
const RAIN_R := 2.4
const RAIN_GAP := 6.0  # between rain circles' centres (stepping out of one never lands you in another)
const SWEEP_W := 4.4
const SWEEP_D := Vector2(14.0, 24.0)  # the band's middle line this far from the temple
const TEMPLE_KEEP := 9.6  # nothing ever goes off nearer the middle than this (the temple steps: the VR master)
const MAX_DMG := 10.0
const RAIN_DMG := 8.0
const SWEEP_DMG := 4.0
const RAIDER_DMG := 20.0
const SWEEP_PUSH := 14.0

## Every island's two tricks: name, picture (story_pictures.gd), warning colour, sound.
const TRICKS := {
	"temple": {"rain": {"name": "FALLING ROCKS", "pic": "rockrain", "color": Color(1.0, 0.62, 0.15), "snd": "crash"},
		"sweep": {"name": "BIG WAVE", "pic": "bigwave", "color": Color(0.1, 0.45, 1.0), "snd": "splash"}},
	"ice": {"rain": {"name": "ICICLES", "pic": "icicles", "color": Color(0.1, 0.35, 0.95), "snd": "ice"},
		"sweep": {"name": "AVALANCHE", "pic": "avalanche", "color": Color(0.55, 0.2, 0.9), "snd": "crash"}},
	"volcano": {"rain": {"name": "LAVA BOMBS", "pic": "lavabomb", "color": Color(1.0, 0.8, 0.1), "snd": "explosion"},
		"sweep": {"name": "LAVA FLOW", "pic": "lavaflow", "color": Color(1.0, 0.25, 0.5), "snd": "fire"}},
	"sky": {"rain": {"name": "LIGHTNING", "pic": "lightning", "color": Color(0.95, 0.2, 0.75), "snd": "zap"},
		"sweep": {"name": "BIG GUST", "pic": "biggust", "color": Color(0.2, 0.3, 0.95), "snd": "whoosh"}},
}


static func trick(arena: String, kind: String) -> Dictionary:
	return (TRICKS.get(arena, TRICKS["temple"]) as Dictionary).get(kind, TRICKS.temple.rain)


static func tell(mode_name: String) -> float:
	return float(mode(mode_name).tell)


## A surprise's damage to a bender (GENTLE: half).
static func damage(kind: String, mode_name: String) -> float:
	return (RAIN_DMG if kind == "rain" else SWEEP_DMG) * float(mode(mode_name).dmg)


## The surprises of wave n on an island (none in waves 1-2 or on a boss wave). Plain data, the same everywhere.
## shapes: [shape, pos, dir, size] for WarnRings.shape / inside ("circle": size.x radius; "line": length, width).
static func surprises(temple_seed: int, n: int, arena: String, mode_name: String) -> Array:
	if n <= 2 or WaveGen.is_boss(n):
		return []
	var lay := Arenas.layout(arena, Arenas.layout_seed(temple_seed, arena))
	var rng := Seeded.rng(WaveGen.wave_seed(temple_seed, n), "surprise_" + arena)
	var want := int(mode(mode_name).rush)
	var secs := tell(mode_name)
	var out: Array = []
	var t := FIRST_AT + snappedf(rng.randf_range(0.0, 6.0), 0.01)
	for k in want:
		var kind := "rain" if n <= 3 or rng.randf() < 0.55 else "sweep"
		var shapes := _rain(rng, lay, 2 if mode_id(mode_name) == "gentle" else 3) if kind == "rain" else _sweep(rng, lay)
		if shapes.is_empty():
			continue
		out.append({"kind": kind, "at": snappedf(t, 0.01), "tell": secs, "shapes": shapes})
		t += secs + GAP + snappedf(rng.randf_range(4.0, 9.0), 0.01)
	return out


static func _rain(rng: RandomNumberGenerator, lay: Dictionary, count: int) -> Array:
	var out: Array = []
	var tries := 0
	while out.size() < count and tries < 200:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(TEMPLE_KEEP + RAIN_R + 0.6, Arenas.ISLAND_R - RAIN_R - 3.0)
		var p := Vector3(snappedf(cos(a) * r, 0.01), 0.0, snappedf(sin(a) * r, 0.01))
		var ok := Arenas.reachable(p, lay)
		for o in out:
			if (o[1] as Vector3).distance_to(p) < RAIN_GAP:
				ok = false
		if ok:
			out.append(["circle", p, Vector3.FORWARD, Vector2(RAIN_R, 0.0)])
	return out


## A band across the island along a chord, its middle line SWEEP_D from the temple (it never touches the steps).
static func _sweep(rng: RandomNumberGenerator, _lay: Dictionary) -> Array:
	var a := rng.randf() * TAU
	var d := snappedf(rng.randf_range(SWEEP_D.x, SWEEP_D.y), 0.01)
	var normal := Vector3(cos(a), 0.0, sin(a))
	var along := Vector3(-normal.z, 0.0, normal.x)
	if rng.randf() < 0.5:
		along = -along
	var half := sqrt(maxf(0.0, pow(Arenas.ISLAND_R - 1.0, 2.0) - d * d))
	var start := normal * d - along * half
	start = Vector3(snappedf(start.x, 0.01), 0.0, snappedf(start.z, 0.01))
	along = Vector3(snappedf(along.x, 0.0001), 0.0, snappedf(along.z, 0.0001))
	return [["line", start, along, Vector2(snappedf(half * 2.0, 0.01), SWEEP_W)]]


## Which way a sweep pushes a raider (away from the temple, to the sea) at p.
static func sweep_out(shape: Array, p: Vector3) -> Vector3:
	var flat := Vector3(p.x, 0.0, p.z)
	return flat.normalized() if flat.length() > 0.1 else Vector3.FORWARD


## Is p inside any shape of a surprise (pad metres extra)?
static func inside(s: Dictionary, p: Vector3, pad: float = 0.0) -> bool:
	const WR := preload("res://core/warn_rings.gd")
	for sh in s.get("shapes", []):
		if WR.inside(String(sh[0]), sh[1], sh[2], sh[3], p, pad):
			return true
	return false


## The nearest point of a shape to the temple's middle (how close it comes to the steps).
static func nearest_to_temple(sh: Array) -> float:
	var pos: Vector3 = sh[1]
	var size: Vector2 = sh[3]
	if String(sh[0]) == "circle":
		return Vector2(pos.x, pos.z).length() - size.x
	var dir: Vector3 = sh[2]
	var a := Vector2(pos.x, pos.z)
	var f := Vector2(dir.x, dir.z).normalized()
	var along := clampf(-a.dot(f), 0.0, size.x)
	return (a + f * along).length() - size.y * 0.5


## Problems with one wave's surprises (empty = fair).
static func check_surprises(list: Array, n: int, arena: String, aseed: int, mode_name: String) -> Array[String]:
	var why: Array[String] = []
	if (n <= 2 or WaveGen.is_boss(n)) and not list.is_empty():
		why.append("wave %d has surprises (none in waves 1-2 or on a boss wave)" % n)
	if list.size() > int(mode(mode_name).rush):
		why.append("wave %d has %d surprises (%s wants %d)" % [n, list.size(), mode_name, int(mode(mode_name).rush)])
	var lay := Arenas.layout(arena, aseed)
	var last_end := -INF
	for s in list:
		var tag := "wave %d %s %s" % [n, arena, String(s.kind)]
		var secs := float(s.tell)
		if secs < MIN_TELL - 0.001:
			why.append("%s: told for only %.1f s" % [tag, secs])
		if mode_id(mode_name) == "gentle" and secs < 2.8:
			why.append("%s: a GENTLE warning of only %.1f s" % [tag, secs])
		if float(s.at) < FIRST_AT - 0.001:
			why.append("%s: told %.1f s into the wave (too soon)" % [tag, float(s.at)])
		if float(s.at) - last_end < GAP - 0.001:
			why.append("%s: comes %.1f s after the last one went off" % [tag, float(s.at) - last_end])
		last_end = float(s.at) + secs
		if damage(String(s.kind), mode_name) > MAX_DMG:
			why.append("%s: hurts %.0f" % [tag, damage(String(s.kind), mode_name)])
		var shapes: Array = s.shapes
		if shapes.is_empty():
			why.append("%s: nothing to warn about" % tag)
		for i in shapes.size():
			var sh: Array = shapes[i]
			var size: Vector2 = sh[3]
			if nearest_to_temple(sh) < TEMPLE_KEEP - 0.01:
				why.append("%s: reaches the temple steps (%.1f m from the middle)" % [tag, nearest_to_temple(sh)])
			var escape := (size.x if String(sh[0]) == "circle" else size.y * 0.5) / KID_SPEED
			if escape > secs - 0.3:
				why.append("%s: a small kid needs %.1f s to get out (told %.1f s)" % [tag, escape, secs])
			if String(sh[0]) == "circle":
				var p: Vector3 = sh[1]
				if Vector2(p.x, p.z).length() + size.x > Arenas.ISLAND_R - 1.0:
					why.append("%s: a circle hangs over the sea" % tag)
				if not Arenas.reachable(p, lay):
					why.append("%s: a circle nobody can walk to (%.0f, %.0f)" % [tag, p.x, p.z])
				for j in i:
					if (shapes[j][1] as Vector3).distance_to(p) < RAIN_GAP - 0.01:
						why.append("%s: two circles overlap" % tag)
	return why

# --- Spirit friends ----------------------------------------------------------------------------------

const FRIENDS := {
	"general": {"id": "pebble", "name": "PEBBLE", "element": E.EARTH, "pic": "pebble"},
	"giant": {"id": "drip", "name": "DRIP", "element": E.WATER, "pic": "drip"},
	"drake": {"id": "ember", "name": "EMBER", "element": E.FIRE, "pic": "ember"},
	"hawk": {"id": "puff", "name": "PUFF", "element": E.AIR, "pic": "puffspirit"},
}
const FRIEND_ORDER: Array[String] = ["general", "giant", "drake", "hawk"]
const FRIEND_MAX_LEVEL := 3
const SPIRIT_HOUSE_EVERY := 2
const SPIRIT_HOUSES_MAX := 6


static func friend(boss_kind: String) -> Dictionary:
	return FRIENDS.get(boss_kind, {})


## The friends the family has freed: [[boss kind, level 1..3]...] from the saved {boss kind: times beaten}.
static func friends(bosses: Dictionary) -> Array:
	var out: Array = []
	for k in FRIEND_ORDER:
		var times := int(bosses.get(k, 0))
		if times > 0:
			out.append([k, mini(FRIEND_MAX_LEVEL, 1 + int((times - 1) / 2))])
	return out


static func spirit_houses(bosses: Dictionary) -> int:
	var total := 0
	for k in bosses:
		total += maxi(0, int(bosses[k]))
	return mini(SPIRIT_HOUSES_MAX, int(total / SPIRIT_HOUSE_EVERY))


## Where friend i flies round the Spirit Tree at time t (relative to the tree's foot): a slow loop round the crown.
static func friend_at(i: int, t: float, stage: int) -> Vector3:
	var a := t * (0.6 + 0.07 * i) + i * TAU / 4.0
	var r := WaveGen.crown_r(stage) + 1.5 + 0.3 * (i % 2)
	return Vector3(cos(a) * r, WaveGen.tree_height(stage) * 0.7 + 0.8 + 0.3 * sin(t * 1.7 + i), sin(a) * r)


## Spirit house i hangs under the crown (relative to the tree's foot).
static func house_at(i: int, stage: int) -> Vector3:
	var a := i * TAU / SPIRIT_HOUSES_MAX + 0.3
	var r := WaveGen.crown_r(stage) * 0.8
	return Vector3(cos(a) * r, WaveGen.tree_height(stage) - WaveGen.crown_r(stage) * 1.15, sin(a) * r)

# --- Seasons -----------------------------------------------------------------------------------------

const SEASONS := {
	"spring": {"drift": Color(1.0, 0.75, 0.85), "line": "Blossom time!", "pic": "spirittree"},
	"summer": {"drift": Color(1.0, 0.95, 0.6), "line": "Sunny days!", "pic": "sun"},
	"autumn": {"drift": Color(0.95, 0.5, 0.15), "line": "Leaves are falling!", "pic": "tree"},
	"winter": {"drift": Color(0.97, 0.98, 1.0), "line": "Snowy temple!", "pic": "snowman"},
}
const SEASON_PROPS := 6
const SEASON_R := 33.0  # on the beach rim: outside every portal (<= 31 m) and every raider's walk


## The season now (the shared ARCADE_SEASON override, else the real one).
static func season() -> String:
	return SeasonKit.override(GAME_ID, Seeded.season(), SEASONS)


static func season_data(s: String) -> Dictionary:
	return SEASONS.get(s, SEASONS["summer"])


## The season props' spots on an island's beach rim (decoration: no collision; clear of its props).
static func season_spots(lay: Dictionary) -> Array:
	var out: Array = []
	var rng := Seeded.rng(int(lay.get("seed", 7)), "season_" + String(lay.get("id", "temple")))
	var tries := 0
	while out.size() < SEASON_PROPS and tries < 120:
		tries += 1
		var a := float(out.size()) * TAU / SEASON_PROPS + rng.randf_range(-0.25, 0.25)
		var p := Vector3(snappedf(cos(a) * SEASON_R, 0.01), 0.0, snappedf(sin(a) * SEASON_R, 0.01))
		var ok := true
		for pr in lay.get("props", []):
			if Vector2((pr.p as Vector3).x - p.x, (pr.p as Vector3).z - p.z).length() < float(pr.r) + 1.4:
				ok = false
		if ok or tries > 100:
			out.append(p)
	return out


## Problems with the season props of an island (empty = fine): on the rim, outside every portal ring, off props.
static func check_season(lay: Dictionary) -> Array[String]:
	var why: Array[String] = []
	var sp := season_spots(lay)
	if sp.size() < SEASON_PROPS:
		why.append("%s: only %d season props" % [String(lay.get("id", "?")), sp.size()])
	for p in sp:
		var r := Vector2(p.x, p.z).length()
		if r < WaveGen.GATE_R.y + WaveGen.JITTER + 0.5:
			why.append("a season prop at %.1f m stands where portals open" % r)
		if r > Arenas.ISLAND_R - 1.0:
			why.append("a season prop in the sea")
	return why
