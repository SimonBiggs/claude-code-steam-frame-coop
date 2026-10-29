extends RefCounted
## BLOCK BUILDERS story (SIMPLE_MODE): PUFF, a little cloud, lost all his cloud friends in a big wind.
## After the eight lesson levels the team goes on SKY ADVENTURES (coursegen.gd: a new seeded course each
## time, a bit bigger as they go). On every course one lost cloud FRIEND waits on a little side island
## off the path; a runner who reaches it brings it home. Rescued friends float round the course for good
## (saved: the flock grows over the days, each friend its own colour and name). Leaving a friend is fine
## (the flag clears the level) - it waits in a later course. The first adventure each day is TODAY'S SKY
## (the same course on every machine). Level indices (main.level, sent in snapshots): 0..7 lessons,
## LESSONS + n = adventure n (seeded from the family's world seed), DAILY_INDEX = today's sky.
## Pure data + small functions; lines are a word or two (the bot's headline check).

const Seeded := preload("res://core/seeded.gd")
const CourseGen := preload("res://games/block_builders/coursegen.gd")

const LESSONS := 8  ## levels.gd SIMPLE_LEVELS
const ADVENTURES := 990  ## adventures before the indices run out (one a minute for 16 hours)
const DAILY_INDEX := LESSONS + ADVENTURES  ## TODAY'S SKY
const PUFF_COLOR := Color(0.75, 0.88, 1.0)
const FRIENDS: Array = [["PIP", Color(1.0, 0.75, 0.8)], ["SUNNY", Color(1.0, 0.9, 0.45)], ["MINT", Color(0.6, 1.0, 0.75)],
	["BLUEBELL", Color(0.55, 0.7, 1.0)], ["PEACH", Color(1.0, 0.75, 0.55)], ["LILAC", Color(0.8, 0.65, 1.0)],
	["SNOWY", Color(0.97, 0.97, 1.0)], ["RUBY", Color(1.0, 0.5, 0.55)], ["LIME", Color(0.8, 1.0, 0.45)],
	["SKY", Color(0.6, 0.9, 1.0)], ["COCOA", Color(0.8, 0.65, 0.5)], ["ROSIE", Color(1.0, 0.6, 0.85)],
	["GOLDIE", Color(1.0, 0.82, 0.3)], ["STORMY", Color(0.6, 0.62, 0.75)], ["CORAL", Color(1.0, 0.62, 0.5)],
	["MISTY", Color(0.82, 0.88, 0.95)]]


static func save_defaults() -> Dictionary:
	return {"lessons_done": false, "adventure": 0, "world": -1, "friends": [], "daily": {}, "courses": 0, "best_level": 0}


static func level_index(adv: int) -> int:
	return LESSONS + clampi(adv, 0, ADVENTURES - 1)


static func is_adventure(i: int) -> bool:
	return i >= LESSONS


static func is_daily(i: int) -> bool:
	return i == DAILY_INDEX


static func adventure_of(i: int) -> int:
	return i - LESSONS


## A sky course's headline ("SKY 12", "TODAY": coursegen.gd names).
static func is_course_name(t: String) -> bool:
	return t == "TODAY" or (t.begins_with("SKY ") and t.substr(4).is_valid_int())


## TODAY'S SKY (pass `date` in tests): a mid-sized adventure from the day's seed.
static func daily_course(date: String = "") -> Dictionary:
	return CourseGen.generate(Seeded.daily_seed("block_builders", date), 3, "TODAY")


## The course for level index i (adventures and today's sky; lessons come from levels.gd).
static func course(world: int, i: int) -> Dictionary:
	if is_daily(i):
		return daily_course()
	var adv := adventure_of(i)
	return CourseGen.generate(Seeded.derive(world, "sky%d" % adv), adv)


## The friend waiting on course i: the first one not rescued yet (they come in order), or a repeat
## (an old friend visiting) once everyone is home.
static func friend_for(rescued: Array) -> int:
	for k in FRIENDS.size():
		if not rescued.has(k):
			return k
	return -1
