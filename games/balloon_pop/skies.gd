extends RefCounted
## BALLOON POP second pass (pure data + small pure functions: the host, TV machines and tests agree):
##   MODES    GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES, picked on the pick orbs once a session): how busy the
##            waves are, how fast balloons rise (never past wavegen.gd's reach limit), how many grumpies and how many
##            WIND GUSTS come, how early they are told and how far they blow.
##   GIFTS    POPPY'S GIFTS (picked on the pick orbs before every round, the whole team gets it for that round):
##            DART (pop from further), PUMP (every pop pumps an extra ticket into Poppy's ride), SLOW (balloons float
##            up slowly), then unlocked by Poppy's balloon PARADE: MAGNET (balloons near you drift to you) and
##            POP POP (a pop pops the good balloons next to it too).
##   SKIES    TODAY'S SKY THEME by the time of day (the host's clock: morning, day, sunset, starry night) and the
##            season (the grass: spring green, summer, autumn gold, winter snow; a winter day is a snowy sky).
##            Every balloon colour must stand out against every sky and every grass (contrast_problems(); the
##            snow-sheep lesson from Sheep Round-Up). At night the balloons glow.
##   GUSTS    WIND GUSTS told first by warn rings (events.gd): a flashing stripe across the park shows which way, then
##            every balloon drifts that way for a moment. gusts(rd, mode) makes a round's list from its seed, keeping
##            only directions that leave every balloon reachable; gust_problems() proves it.
##   PARADE   POPPY'S BALLOON PARADE: a balloon joins the ring circling high over the fair for every round with a star
##            (two for three stars, one for today's sky). It grows over days (saved) and unlocks gifts.

const PickOrbs := preload("res://core/pick_orbs.gd")
const Seeded := preload("res://core/seeded.gd")
const SkyKit := preload("res://core/sky_kit.gd")
const WaveGen := preload("res://games/balloon_pop/wavegen.gd")

## Per mode. busy: waves come this much faster (wavegen.gd gap / busy). rise: balloons rise this much faster (still
## capped by wavegen.gd max_rise, so every balloon stays reachable). grumpy: x the ride's grumpy chance. gusts: wind
## gusts in a 2 minute round (fewer in shorter ones, at least one from 12 s). warn: seconds the rings show first.
## gust: drift speed (m/s) for gust_secs.
const MODES := {
	"gentle": {"busy": 0.8, "rise": 0.85, "grumpy": 0.5, "gusts": 1, "warn": 3.0, "gust": 0.25, "gust_secs": 2.4},
	"brave": {"busy": 1.0, "rise": 1.0, "grumpy": 1.0, "gusts": 2, "warn": 2.5, "gust": 0.32, "gust_secs": 2.8},
	"hard": {"busy": 1.22, "rise": 1.15, "grumpy": 1.4, "gusts": 4, "warn": 2.0, "gust": 0.4, "gust_secs": 3.0},
}
const MIN_WARN := 2.0
const MAX_DRIFT := 1.3  # metres a gust may blow a balloon
const GUST_COLOR := Color(0.55, 0.85, 1.0)

## Poppy's gifts. unlock: balloons in Poppy's parade (save "parade") before it can be picked.
const GIFTS: Array[Dictionary] = [
	{"id": "dart", "name": "DART", "pic": "dart", "color": Color(1.0, 0.35, 0.35), "unlock": 0, "line": "Darts! Pop from further!"},
	{"id": "pump", "name": "PUMP", "pic": "pump", "color": Color(0.4, 0.75, 1.0), "unlock": 0, "line": "Pump! Rides grow fast!"},
	{"id": "slow", "name": "SLOW", "pic": "snail", "color": Color(0.5, 0.95, 0.45), "unlock": 0, "line": "Slow balloons!"},
	{"id": "magnet", "name": "MAGNET", "pic": "balloonmagnet", "color": Color(1.0, 0.75, 0.2), "unlock": 5, "line": "Magnet! Come here!"},
	{"id": "poppop", "name": "POP POP", "pic": "popburst", "color": Color(1.0, 0.5, 0.9), "unlock": 12, "line": "POP POP! Pop lots!"},
]
## Gift effects (main.gd reads these).
const DART_REACH := 0.22  # metres added to every touch
const PUMP_EXTRA := 1  # tickets per pop
const SLOW_RISE := 0.75  # x every balloon's rise
const MAGNET_R := 2.0  # balloons this close (flat) drift to a player ...
const MAGNET_SPEED := 0.6  # ... this fast (m/s)
const POPPOP_R := 1.0  # a pop pops good balloons this close too

## Poppy's parade.
const PARADE_DRAWN := 48  # most balloons drawn circling (the count keeps growing)
const PARADE_MILESTONE := 8  # Poppy cheers every this many

const SEASONS: Array[String] = ["spring", "summer", "autumn", "winter"]
const TIMES: Array[String] = ["dawn", "day", "sunset", "night"]
## The grass per season (the park's ground and the flowers on it).
const GROUND := {"spring": Color(0.45, 0.78, 0.36), "summer": Color(0.42, 0.72, 0.32), "autumn": Color(0.62, 0.45, 0.22),
	"winter": Color(0.86, 0.9, 0.96)}
const FLOWERS := {"spring": [Color(1.0, 0.6, 0.8), Color(1.0, 0.95, 0.5), Color(0.8, 0.7, 1.0)],
	"summer": [Color(1.0, 0.45, 0.4), Color(1.0, 0.9, 0.3), Color(0.6, 0.6, 1.0)],
	"autumn": [Color(1.0, 0.55, 0.15), Color(0.85, 0.3, 0.15), Color(1.0, 0.8, 0.3)],
	"winter": [Color(0.6, 0.85, 1.0), Color(1.0, 1.0, 1.0), Color(0.8, 0.9, 1.0)]}
const TIME_NAMES := {"dawn": "MORNING SKY", "day": "SUNNY SKY", "sunset": "SUNSET SKY", "night": "STARRY SKY", "snow": "SNOWY SKY"}
const TIME_PICS := {"dawn": "sun", "day": "sun", "sunset": "sun", "night": "nightsky", "snow": "snowflake"}
const TIME_LINES := {"dawn": "Good morning, balloons!", "day": "What a sunny day!", "sunset": "A sunset sky!",
	"night": "Night! Balloons glow!", "snow": "Snow! Brrr!"}
## The sky presets any round may show (themes + story.gd SKIES for today's sky).
const DAILY_SKIES: Array[String] = ["day", "dawn", "sunset", "snowy"]

## Every colour a balloon can be (balloon.gd COLORS + the special kinds) must differ from every sky and grass by at
## least this much (Oklab distance; 0.1 is a clear difference at a glance).
const MIN_CONTRAST := 0.1


static func mode_of(id: String) -> Dictionary:
	var m := String(PickOrbs.mode(id).get("id", "brave"))
	return MODES.get(m, MODES["brave"])


static func mode_id(id: String) -> String:
	return String(PickOrbs.mode(id).get("id", "brave"))


## A story / daily spec with the mode in it (wavegen.gd reads busy / rise; story.gd's grumpy chance scaled).
static func apply(spec: Dictionary, mode: String) -> Dictionary:
	var s := spec.duplicate(true)
	var m := mode_of(mode)
	s["busy"] = float(m.busy)
	s["rise"] = float(m.rise)
	s["grumpy"] = minf(0.3, float(s.get("grumpy", 0.0)) * float(m.grumpy))
	s["mode"] = mode_id(mode)
	return s


# --- Gifts ---------------------------------------------------------------------------------------

static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return {}


static func unlocked(parade: int) -> Array:
	var out: Array = []
	for g in GIFTS:
		if parade >= int(g.unlock):
			out.append(String(g.id))
	return out


## Three gift ids to offer (seeded): the newest unlock always among them, the last gift only if there's no other.
static func gift_choices(parade: int, last: String, seed_value: int) -> Array:
	var ids := unlocked(parade)
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


## Balloons a round adds to Poppy's parade.
static func parade_gain(stars: int, daily: bool) -> int:
	return (1 if stars >= 1 else 0) + (1 if stars >= 3 else 0) + (1 if daily and stars >= 1 else 0)


# --- Sky themes ----------------------------------------------------------------------------------

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


static func time_of(hour: int) -> String:
	if hour >= 6 and hour < 9:
		return "dawn"
	if hour >= 9 and hour < 17:
		return "day"
	if hour >= 17 and hour < 20:
		return "sunset"
	return "night"


## The sky theme for an hour on a date (BP_SKY=dawn/day/sunset/night/snow and BP_SEASON force one: What's New
## "try" and bots). {id, time, season, preset, ground, flowers, name, pic, line, glow}
static func theme_of(hour: int, date: String) -> Dictionary:
	var season := season_of(date)
	if OS.has_environment("BP_SEASON") and SEASONS.has(OS.get_environment("BP_SEASON")):
		season = OS.get_environment("BP_SEASON")
	var tm := time_of(hour)
	if OS.has_environment("BP_SKY"):
		var want := OS.get_environment("BP_SKY")
		if want == "snow":
			season = "winter"
			tm = "day"
		elif TIMES.has(want):
			tm = want
	return theme(tm, season)


static func theme(tm: String, season: String) -> Dictionary:
	var look := tm
	var preset := tm
	if tm == "day" and season == "winter":
		look = "snow"
		preset = "snowy"
	return {"id": "%s_%s" % [tm, season], "time": tm, "season": season, "preset": preset, "ground": GROUND[season],
		"flowers": FLOWERS[season], "name": TIME_NAMES[look], "pic": TIME_PICS[look], "line": TIME_LINES[look],
		"glow": tm == "night"}


static func theme_by_id(id: String) -> Dictionary:
	var p := id.split("_")
	if p.size() == 2 and TIMES.has(p[0]) and SEASONS.has(p[1]):
		return theme(p[0], p[1])
	return theme("day", "spring")


## Every theme there is (validator).
static func all_themes() -> Array:
	var out: Array = []
	for s in SEASONS:
		for tm in TIMES:
			out.append(theme(tm, s))
	return out


static func _oklab(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	var a := pow(0.4122214708 * l.r + 0.5363325363 * l.g + 0.0514459929 * l.b, 1.0 / 3.0)
	var m := pow(0.2119034982 * l.r + 0.6806995451 * l.g + 0.1073969566 * l.b, 1.0 / 3.0)
	var s := pow(0.0883024619 * l.r + 0.2817188376 * l.g + 0.6299787005 * l.b, 1.0 / 3.0)
	return Vector3(0.2104542553 * a + 0.7936177850 * m - 0.0040720468 * s, 1.9779984951 * a - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * a + 0.7827717662 * m - 0.8086757660 * s)


## How different two colours look (Oklab distance: 0 = the same, 0.1 = clear at a glance).
static func contrast(a: Color, b: Color) -> float:
	return _oklab(a).distance_to(_oklab(b))


## Every balloon colour against every sky (top and horizon) and every grass: [] = fine.
## balloon_colors: [[name, Color], ...] (tests pass balloon.gd's).
static func contrast_problems(balloon_colors: Array) -> Array:
	var why: Array = []
	var backs: Array = []  # [name, Color]
	var presets := {}
	for th in all_themes():
		presets[String(th.preset)] = true
	for p in DAILY_SKIES:
		presets[p] = true
	for p in presets:
		var pr: Dictionary = SkyKit.PRESETS[SkyKit.resolve(String(p))]
		backs.append(["%s sky" % p, pr.top])
		backs.append(["%s horizon" % p, pr.horizon])
	for s in GROUND:
		backs.append(["%s grass" % s, GROUND[s]])
	for bc in balloon_colors:
		for bk in backs:
			var c := contrast(bc[1], bk[1])
			if c < MIN_CONTRAST:
				why.append("a %s balloon is hard to see on the %s (%.3f)" % [bc[0], bk[0], c])
	return why


# --- Wind gusts ----------------------------------------------------------------------------------

## How many gusts a round of `time` seconds gets in a mode.
static func gust_count(mode: String, time: float) -> int:
	if time < 12.0:
		return 0
	return maxi(1, roundi(int(mode_of(mode).gusts) * time / 120.0))


## Would a balloon s (wavegen.gd [t, kind, x, z, y0, rise, colour, set]) still be fair to reach if blown by `drift`?
static func _blown_ok(s: Array, drift: Vector2) -> bool:
	var kind := int(s[1])
	if kind == WaveGen.GRUMPY:
		return true
	var p := Vector2(float(s[2]), float(s[3])) + drift
	if p.length() > WaveGen.ARENA - 0.3:
		return false
	var y0 := float(s[4])
	var rise := float(s[5])
	return WaveGen.vr_window(kind, y0, rise) >= WaveGen.vr_need(kind, p) and WaveGen.tv_window(kind, y0, rise) >= WaveGen.tv_need(kind, p)


## The balloons up at any time in [t0, t1].
static func _up_during(rd: Dictionary, t0: float, t1: float) -> Array:
	var out: Array = []
	for s in rd.get("spawns", []):
		var at := float(s[0])
		if at <= t1 and at + WaveGen.up_time(s) >= t0:
			out.append(s)
	return out


## A round's wind gusts: [[t (when it starts blowing), dx, dz], ...] (unit direction). The same round + mode = the
## same list on every machine. A direction that would blow any balloon out of reach is never used (another one is
## tried; none fits = no gust then).
static func gusts(rd: Dictionary, mode: String) -> Array:
	var m := mode_of(mode)
	var time := float(rd.get("time", 0.0))
	var n := gust_count(mode, time)
	var r := Seeded.rng(int(rd.get("seed", 0)), "bp_gusts_" + mode_id(mode))
	var out: Array = []
	var drift := float(m.gust) * float(m.gust_secs)
	for i in n:
		var t := time * (i + 1.0) / (n + 1.0) + r.randf_range(-1.0, 1.0)
		t = snappedf(clampf(t, float(m.warn) + 2.0, time - float(m.gust_secs) - 1.0), 0.1)
		var up := _up_during(rd, t, t + float(m.gust_secs))
		var first := r.randi() % 8
		for k in 8:
			var a := ((first + k * 3) % 8) * TAU / 8.0
			var dir := Vector2(snappedf(cos(a), 0.001), snappedf(sin(a), 0.001))
			var ok := true
			for s in up:
				if not _blown_ok(s, dir * drift):
					ok = false
					break
			if ok:
				out.append([t, dir.x, dir.y])
				break
	return out


## Reasons a round's gusts are unfair ([] = fine): told early enough, never blowing far, never two at once, never
## at the very start or end, and every balloon up during a gust still reachable where it is blown to.
static func gust_problems(rd: Dictionary, list: Array, mode: String) -> Array:
	var why: Array = []
	var m := mode_of(mode)
	var time := float(rd.get("time", 0.0))
	if float(m.warn) < MIN_WARN:
		why.append("told too late (%.1f s)" % float(m.warn))
	var drift := float(m.gust) * float(m.gust_secs)
	if drift > MAX_DRIFT:
		why.append("a gust blows %.1f m" % drift)
	var last_end := -INF
	for g in list:
		var t := float(g[0])
		var dir := Vector2(float(g[1]), float(g[2]))
		if absf(dir.length() - 1.0) > 0.01:
			why.append("a gust without a direction")
		if t - float(m.warn) < 1.5:
			why.append("a gust before the balloons get going (%.1f s)" % t)
		if t + float(m.gust_secs) > time:
			why.append("a gust after the round (%.1f s)" % t)
		if t < last_end + 0.5:
			why.append("two gusts at once (%.1f s)" % t)
		last_end = t + float(m.gust_secs)
		for s in _up_during(rd, t, t + float(m.gust_secs)):
			if not _blown_ok(s, dir * drift):
				why.append("the gust at %.1f s blows the %s from %.1f s out of reach" % [t, WaveGen.KIND_NAMES[int(s[1])], float(s[0])])
	return why


## The order the difficulty must rise in (tests): every number gentle <= brave <= hard (warn: >=).
static func ordered() -> Array:
	var why: Array = []
	var g: Dictionary = MODES.gentle
	var b: Dictionary = MODES.brave
	var h: Dictionary = MODES.hard
	for k in ["busy", "rise", "grumpy", "gusts", "gust", "gust_secs"]:
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			why.append("%s not gentle <= brave <= hard" % k)
	if not (float(g.warn) >= float(b.warn) and float(b.warn) >= float(h.warn)):
		why.append("warn not gentle >= brave >= hard")
	return why
