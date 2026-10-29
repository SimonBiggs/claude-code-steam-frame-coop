extends RefCounted
## OBSTACLE RUSH story: COACH JELLY (a big orange jelly bean with a cap and a whistle) runs the toy course
## on the giant's picnic table and dreams of a FULL GRANDSTAND. Every course the team clears and every
## star they grab brings a new fan bean to the stands beside the course (stands.gd), and the fans STAY
## (saved): a new stand is built when one fills, and the stands get flags, balloons, a band, fireworks,
## a giant trophy and finally turn gold as the crowd grows.
## The SHOW: the family's very first show is the four lessons (HOP HOP, SPINNER, BOING, DOORS). After
## that every show is four seeded courses (coursegen.gd) from this family's own world seed, one tier
## harder as the shows go by (more pieces, wider gaps, more pretend doors, a faster spinner, more stars),
## the last course of a show a little harder still. The first show of each day opens with TODAY'S COURSE
## (the same everywhere all day).

const Seeded := preload("res://core/seeded.gd")
const CourseGen := preload("res://games/obstacle_rush/coursegen.gd")

const GAME_ID := "obstacle_rush"
const COACH := "COACH JELLY"
const COACH_COLOR := Color(1.0, 0.55, 0.25)
const SEATS := 20  ## fans per stand
const STANDS := 5
const MAX_FANS := SEATS * STANDS
const COURSES := 4  ## courses per show
const FAN_COURSE := 1  ## fans for every course cleared
const FAN_STAR := 1  ## ... every star grabbed
const FAN_SHOW := 2  ## ... and every show finished

## Things the stands get as the crowd grows (stands.gd draws them; story cards announce them).
const MILESTONES: Array[Dictionary] = [
	{"fans": 6, "id": "flags", "pic": "flag", "line": "Flags for the fans!"},
	{"fans": 15, "id": "balloons", "pic": "balloon", "line": "Balloons!"},
	{"fans": 30, "id": "band", "pic": "music", "line": "A band!"},
	{"fans": 50, "id": "fireworks", "pic": "star", "line": "Fireworks!"},
	{"fans": 75, "id": "trophy", "pic": "trophy", "line": "A giant trophy!"},
	{"fans": 100, "id": "gold", "pic": "crown", "line": "The stands are FULL!"},
]

const LINES := {
	"welcome": "Welcome to my course!",
	"new_show": ["A brand-new course!", "New course! Let's go!", "Ready? Run!", "The fans are waiting!"],
	"daily": "TODAY'S COURSE!",
	"star": "A star! A new fan!",
	"seats": "More seats!",
	"show_end": ["What a show!", "The fans love it!", "Hooray, runners!"],
}


static func save_defaults() -> Dictionary:
	return {"crowns": 0, "shows": 0, "fans": 0, "stars": 0, "courses": 0, "world": -1, "daily": {}}


## How hard this show's courses are (0 = the first show after the lessons).
static func tier_for(shows: int, course_i: int) -> int:
	return clampi(shows - 1, 0, CourseGen.tier_count() - 2) + (1 if course_i == COURSES - 1 and shows > 1 else 0)


## The recipe for course i of show number `shows` (before describe(): seeds and tiers only).
## daily_due: this show opens with TODAY'S COURSE.
static func recipe(shows: int, world: int, i: int, daily_due: bool, date: String = "") -> Dictionary:
	if shows <= 0:
		return {"k": "lesson", "i": i, "s": Seeded.derive(world, "lesson%d" % i) + 1}
	if daily_due and i == 0:
		return {"k": "daily", "s": daily_seed(date), "tier": 2}
	return {"k": "gen", "s": Seeded.derive(world, "show%d/%d" % [shows, i]), "tier": tier_for(shows, i)}


## A recipe made concrete for every machine: generated courses get the attempt that passed.
static func describe(rec: Dictionary) -> Dictionary:
	if String(rec.get("k", "")) == "lesson":
		return rec.duplicate()
	return CourseGen.describe(String(rec.k), int(rec.s), int(rec.get("tier", 0)))


static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


## TODAY'S COURSE (compact description).
static func daily_desc(date: String = "") -> Dictionary:
	return describe({"k": "daily", "s": daily_seed(date), "tier": 2})


## Stands built for this many fans (one more as soon as the last one has a fan in it).
static func stands_for(fans: int) -> int:
	return clampi(1 + maxi(0, fans - 1) / SEATS, 1, STANDS)


## Milestones reached with this many fans (ids).
static func unlocked(fans: int) -> Array:
	var out: Array = []
	for m in MILESTONES:
		if fans >= int(m.fans):
			out.append(String(m.id))
	return out


## Milestones passed going from `before` to `after` fans.
static func new_milestones(before: int, after: int) -> Array:
	var out: Array = []
	for m in MILESTONES:
		if before < int(m.fans) and after >= int(m.fans):
			out.append(m)
	return out


## A fan's look, the same on every machine: [colour index, costume index, pattern index].
static func fan_look(k: int) -> Array:
	var r := Seeded.rng(k, "fan")
	return [r.randi() % 8, r.randi() % 13, r.randi() % 4]


static func pick(r: RandomNumberGenerator, key: String) -> String:
	var v: Variant = LINES.get(key, "")
	if v is Array:
		return String(Seeded.pick(r, v))
	return String(v)


## Story rules the tests check.
static func self_check() -> Array:
	var why: Array = []
	var last := 0
	for m in MILESTONES:
		if int(m.fans) <= last:
			why.append("milestones out of order at %s" % str(m.id))
		last = int(m.fans)
		if String(m.line).length() > 24:
			why.append("milestone line too long: %s" % m.line)
	if last > MAX_FANS:
		why.append("a milestone needs more fans than the stands hold")
	if stands_for(0) != 1 or stands_for(SEATS) != 1 or stands_for(SEATS + 1) != 2 or stands_for(MAX_FANS * 2) != STANDS:
		why.append("stands_for is off")
	# Shows: lessons first, then generated courses, rising tiers, TODAY'S COURSE first when due.
	for i in COURSES:
		if String(recipe(0, 5, i, true).k) != "lesson":
			why.append("the first show isn't the lessons")
	if String(recipe(1, 5, 0, true, "2026-10-29").k) != "daily" or String(recipe(1, 5, 1, true).k) != "gen":
		why.append("TODAY'S COURSE doesn't open the show")
	if tier_for(1, 0) != 0 or tier_for(9, 0) <= tier_for(2, 0) or tier_for(30, 3) > CourseGen.tier_count() - 1:
		why.append("tiers don't rise (or run past the last)")
	if var_to_str(recipe(3, 5, 2, false)) == var_to_str(recipe(4, 5, 2, false)):
		why.append("two shows have the same course")
	for key in LINES:
		var v: Variant = LINES[key]
		for line in (v if v is Array else [v]):
			if String(line).length() > 24:
				why.append("line too long: %s" % line)
	return why
