extends RefCounted
## KART RACE second pass: pure data + small pure functions (tests/kart_deep_test.gd checks them; main.gd, surprises.gd,
## town.gd and track_props.gd use them).
##  - BOLT'S GIFTS: at every pit stop three picture orbs float over the road before the gates (core/pick_orbs.gd); drive
##    through one and it is yours for the whole next cup / tour place: BUBBLE START (a bubble at GO and every lap), STAR
##    START (a rainbow star at GO), TURBO LAPS (a zoom at GO and every lap) or BOX MAGNET (? boxes from far away). Nobody
##    has to pick: whoever drives past gets the glowing middle one. Gifts only ever help (CPUs never get one).
##  - SURPRISES: from the second race of a cup or tour place, something drops onto the road ahead: a GUMBALL (candy),
##    a COCONUT (jungle), a big SNOWBALL (ice / winter), a METEOR (space); on the tour the season's (spring bouncy
##    ball, summer beach ball, autumn acorn, winter snowball). It is ALWAYS told first: a steady glowing circle on the
##    road (core/warn_rings.gd) for TELL seconds before it lands, on the side of the road, leaving a wide clear lane
##    (trackgen.gd places and proves the spots). Landing in the circle = a harmless spin (a star / bubble saves you).
##    The cups' puddles and bumpers are told too: a glowing outline as you come up to them.
##  - SEASONS (Seeded.season): seasonal things by the roadside on every track (core/season_kit.gd props), drifting
##    blossom / pollen / leaves / snow, and the season's surprise on the tour.
##  - BOLT'S RACE TOWN: by the start line of every track, a little town grows: a new building every TOWN_EVERY races
##    finished (tyre tower, flags, garage, snack stand, control tower, balloon arch, hot-air balloon, Bolt's statue,
##    big wheel, fireworks tower), then balloons over it. Saved ("races"), the same on every machine (snapshot).

const Seeded := preload("res://core/seeded.gd")

## Gifts: id -> name, picture, colour. ORDER is the rotation the pit stops offer three from.
const GIFT_ORDER: Array[String] = ["bubble", "turbo", "star", "magnet"]
const GIFTS := {
	"bubble": {"name": "BUBBLE START", "pic": "bubble", "color": Color(0.5, 0.85, 1.0)},
	"turbo": {"name": "TURBO LAPS", "pic": "mushrooms", "color": Color(1.0, 0.45, 0.3)},
	"star": {"name": "STAR START", "pic": "star", "color": Color(1.0, 0.88, 0.3)},
	"magnet": {"name": "BOX MAGNET", "pic": "boxmagnet", "color": Color(0.85, 0.5, 1.0)},
}
const GIFT_D := 11.0  # metres past the start line: the gift orbs, before the first row of gates (pit.gd ROW_D 22)
const GIFT_LATS: Array[float] = [-3.4, 0.0, 3.4]  # across the road (11 m wide): one lane each
const MAGNET_REACH := 4.2  # ? boxes this far away jump to you (normal 1.9)
const STAR_START := 3.0  # seconds of star at GO

## Surprises: kind -> picture, colours (body, detail), the ring colour.
const SURPRISES := {
	"gumball": {"pic": "gumball", "body": Color(1.0, 0.4, 0.62), "detail": Color(1.0, 1.0, 1.0)},
	"coconut": {"pic": "coconut", "body": Color(0.5, 0.8, 0.3), "detail": Color(0.35, 0.25, 0.12)},  # a green one (brown hid on the mud road)
	"bigsnowball": {"pic": "bigsnowball", "body": Color(0.96, 0.98, 1.0), "detail": Color(0.75, 0.85, 0.95)},
	"meteor": {"pic": "meteor", "body": Color(0.45, 0.38, 0.4), "detail": Color(1.0, 0.55, 0.15)},
	"bouncyball": {"pic": "bouncyball", "body": Color(1.0, 0.3, 0.3), "detail": Color(1.0, 0.9, 0.3)},
	"beachball": {"pic": "beachball", "body": Color(1.0, 1.0, 1.0), "detail": Color(1.0, 0.3, 0.3)},
	"acorn": {"pic": "acorn", "body": Color(0.75, 0.48, 0.2), "detail": Color(0.45, 0.3, 0.15)},
}
const CUP_SURPRISE := {"candy": "gumball", "jungle": "coconut", "ice": "bigsnowball", "space": "meteor"}
const SEASON_SURPRISE := {"spring": "bouncyball", "summer": "beachball", "autumn": "acorn", "winter": "bigsnowball"}
const RING_COLOR := Color(1.0, 0.62, 0.12)  # the steady glowing circle: orange (palette.gd checks it on every road)
const HOT_COLOR := Color(1.0, 0.25, 0.2)  # the moment it lands
const HAZARD_TELL := Color(1.0, 0.9, 0.25)  # puddles' / bumpers' outlines as you come up to them
const TELL := 2.6  # seconds a surprise is told before it lands (it can't land sooner)
const STAY := 1.2  # seconds the landing spot is "hot" (it rolls about in the circle, then bounces off the road)
const R := 2.6  # the circle's radius (trackgen.gd keeps a CLEAR_LANE beside it)
const LAT := 2.6  # the circle's centre this far off the middle of the road (left or right)
const TRIGGER: Array[float] = [40.0, 140.0]  # a person this far before a spot may set it off (metres along the road)...
const LEAD: Array[float] = [0.3, 1.1]  # ...when they'd get there this many seconds after it lands (so it drops just ahead)
## Per speed: how many may be told at once, the chance a spot goes off when someone comes up to it, and none at all.
const RATE := {"gentle": {"max": 1, "chance": 0.45}, "zoom": {"max": 2, "chance": 0.8}, "trial": {"max": 0, "chance": 0.0}}
const SPOTS := 3  # surprise spots trackgen.gd tries to place on a track

## Bolt's race town: the buildings in the order they come, [id, picture for the card, name].
const TOWN: Array = [["tyres", "kart", "TYRE TOWER"], ["flags", "flag", "RACE FLAGS"], ["garage", "spanner", "A GARAGE"],
	["snacks", "icecream", "SNACK STAND"], ["tower", "tower", "CONTROL TOWER"], ["arch", "balloon", "BALLOON ARCH"],
	["hotair", "balloon", "HOT-AIR BALLOON"], ["statue", "boltbot", "BOLT STATUE"], ["wheel", "ferris", "BIG WHEEL"],
	["fireworks", "rocket", "FIREWORKS"]]
const TOWN_EVERY := 3  # races finished per new building
const TOWN_BALLOONS := 6  # after the town is built: one more balloon over it every TOWN_EVERY * 2 races


static func gift(id: String) -> Dictionary:
	return GIFTS.get(id, {})


## The three gifts offered at pit stop n (each pit stop a different three, the middle one the default).
static func gift_offer(n: int) -> Array[String]:
	var out: Array[String] = []
	for i in 3:
		out.append(GIFT_ORDER[posmod(n + i, GIFT_ORDER.size())])
	return out


## What drops at a race: the cup's thing, else the season's. "" = no surprises (today's track, first race of a series,
## time trial).
static func surprise_kind(desc_kind: String, cup_hz: String, race_in_series: int, speed: String, season: String) -> String:
	if desc_kind == "daily" or race_in_series < 1 or int(RATE.get(speed, RATE.gentle).max) <= 0:
		return ""
	if desc_kind == "cup":
		return String(CUP_SURPRISE.get(cup_hz, ""))
	return String(SEASON_SURPRISE.get(season, "bouncyball"))


## How many town buildings and extra balloons `races` finished races have built.
static func town_size(races: int) -> Vector2i:
	var b := clampi(races / TOWN_EVERY, 0, TOWN.size())
	var extra := 0
	if b >= TOWN.size():
		extra = clampi((races - TOWN.size() * TOWN_EVERY) / (TOWN_EVERY * 2), 0, TOWN_BALLOONS)
	return Vector2i(b, extra)


## Problems with the data (empty = fine).
static func check(has_picture: Callable) -> Array[String]:
	var why: Array[String] = []
	for g in GIFT_ORDER:
		if not GIFTS.has(g):
			why.append("gift %s has no data" % g)
		elif not has_picture.call(String(GIFTS[g].pic)):
			why.append("gift %s: no picture %s" % [g, GIFTS[g].pic])
	if GIFT_ORDER.size() < 3:
		why.append("fewer than three gifts to offer")
	for n in GIFT_ORDER.size():
		var o := gift_offer(n)
		if o.size() != 3 or o[0] == o[1] or o[1] == o[2] or o[0] == o[2]:
			why.append("pit stop %d offers %s" % [n, o])
	for k in SURPRISES:
		if not has_picture.call(String(SURPRISES[k].pic)):
			why.append("surprise %s: no picture" % k)
	for m in [CUP_SURPRISE, SEASON_SURPRISE]:
		for k in m:
			if not SURPRISES.has(String(m[k])):
				why.append("%s drops an unknown %s" % [k, m[k]])
	for s in ["spring", "summer", "autumn", "winter"]:
		if not SEASON_SURPRISE.has(s):
			why.append("no surprise for %s" % s)
	if TELL < 2.0:
		why.append("surprises told for under 2 s")
	# It goes off only for a kart that will get there after it lands, and never closer than TRIGGER[0] (seen coming).
	if LEAD[0] < 0.2 or TRIGGER[0] < 35.0:
		why.append("a surprise could go off right under someone")
	for t in TOWN:
		if not has_picture.call(String(t[1])):
			why.append("town %s: no picture %s" % [t[0], t[1]])
	if town_size(0) != Vector2i.ZERO or town_size(TOWN_EVERY).x != 1 or town_size(100000).x != TOWN.size() or town_size(100000).y != TOWN_BALLOONS:
		why.append("the town does not grow as it should")
	return why