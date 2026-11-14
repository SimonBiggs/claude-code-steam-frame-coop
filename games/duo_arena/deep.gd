extends RefCounted
## DUO ARENA, second deepening pass (data + generators; deep_play.gd runs them in the game, main.gd decides):
## - NOVA'S FRIENDS: one light-bot friend is lost in each far zone (SPROUT in DINO JUNGLE, EMBER on LAVA RIM, FLURRY on
##   ICE RINK, COMET on STAR DECK). While the family fights in that zone the friend floats in a bubble over the far
##   wall; beat the zone's boss and the friend is SAVED for good (saved "friends"): it flies to Nova, follows her in
##   every later game, gets a little house in the city and brings a new gift for Nova's gift orbs.
## - NOVA'S GIFTS: after every boss the team picks ONE of three gifts on the pick orbs (everyone votes: team_picks.gd;
##   the middle one if nobody does). A gift lasts the rest of the game and they add up: NOVA ZAP (Nova zaps monsters),
##   BUBBLE (every wave starts in a shield bubble), HEARTS (hearts fall now and then), and the friends' gifts MAGNET,
##   FIRE, SLEEPY (slower monsters), ZOOM.
## - TOLD SURPRISES: from wave 3 (never on a boss wave) each zone has its own surprise: falling CRATES (Neon City),
##   COCONUTS and a ROLLING LOG (Dino Jungle), LAVA ROCKS (Lava Rim), a GIANT SNOWBALL (Ice Rink), COMETS (Star Deck).
##   Each is TOLD first by a steady warn ring on the floor (core/warn_rings.gd: a circle where it lands, a band where it
##   rolls) for the mode's tell seconds; then it lands / rolls through. plan() makes a wave's surprises from the run
##   seed; check_plan() proves them fair (late enough, told long enough, room to step out, a rest between).
## - SEASONS (core/season_kit.gd override: ARCADE_SEASON / ARCADE_SEASON_DUO_ARENA) dress the stands with seasonal props
##   and drifting blossom / leaves / snow; NOVA'S CITY grows: a new tower for every TOWER_EVERY waves the family has
##   ever cleared (past the 40 city lights) and a house for every friend saved.

const Seeded := preload("res://core/seeded.gd")
const Gen := preload("res://games/duo_arena/arenagen.gd")

const GAME_ID := "duo_arena"
const SEASONS: Array[String] = ["spring", "summer", "autumn", "winter"]

const FRIENDS: Array[Dictionary] = [
	{"id": "sprout", "name": "SPROUT", "zone": "jungle", "pic": "sproutbot", "color": Color(0.45, 1.0, 0.5), "gift": "magnet"},
	{"id": "ember", "name": "EMBER", "zone": "lava", "pic": "emberbot", "color": Color(1.0, 0.55, 0.25), "gift": "fire"},
	{"id": "flurry", "name": "FLURRY", "zone": "ice", "pic": "flurrybot", "color": Color(0.8, 0.95, 1.0), "gift": "sleepy"},
	{"id": "comet", "name": "COMET", "zone": "star", "pic": "cometbot", "color": Color(1.0, 0.85, 0.35), "gift": "zoom"},
]

## Gifts (picks.gd shows them on the orbs: id, name <= 9 letters, pic, color, fx = none: deep_play.gd runs them).
## friend: the friend who brings it (saved first), "" = Nova's own.
const GIFTS: Array[Dictionary] = [
	{"id": "helper", "name": "NOVA ZAP", "pic": "novazap", "color": Color(0.35, 0.85, 1.0), "friend": "", "fx": [], "waves": 0},
	{"id": "bubble", "name": "BUBBLE", "pic": "shieldbubble", "color": Color(0.5, 0.7, 1.0), "friend": "", "fx": [], "waves": 0},
	{"id": "hearts", "name": "HEARTS", "pic": "heart", "color": Color(1.0, 0.45, 0.6), "friend": "", "fx": [], "waves": 0},
	{"id": "magnet", "name": "MAGNET", "pic": "starmagnet", "color": Color(0.45, 1.0, 0.5), "friend": "sprout", "fx": [], "waves": 0},
	{"id": "fire", "name": "FIRE", "pic": "fireball", "color": Color(1.0, 0.55, 0.25), "friend": "ember", "fx": [], "waves": 0},
	{"id": "sleepy", "name": "SLEEPY", "pic": "sleepydust", "color": Color(0.75, 0.7, 1.0), "friend": "flurry", "fx": [], "waves": 0},
	{"id": "zoom", "name": "ZOOM", "pic": "speedup", "color": Color(1.0, 0.85, 0.35), "friend": "comet", "fx": [], "waves": 0},
]
const GIFT_OFFER := 3
## Gift numbers.
const ZAP_EVERY := 1.8  # NOVA ZAP: seconds between zaps
const ZAP_DAMAGE := 3.0  # + ZAP_GROW a wave
const ZAP_GROW := 0.4
const ZAP_RANGE := 30.0
const BUBBLE_SECS := 6.0  # BUBBLE: a shield at every wave's start
const HEART_EVERY := 16.0  # HEARTS: one falls this often during a wave
const MAGNET_R := 7.0  # MAGNET: pickups this near fly to you
const MAGNET_SPEED := 7.0
const FIRE_K := 1.2  # FIRE: everyone's shots hit harder
const SLEEPY_K := 0.85  # SLEEPY: monsters (not bosses) walk slower
const ZOOM_K := 1.12  # ZOOM: everyone runs faster

## Told surprises: name (a banner), pic (story picture), shape ("drop" = a circle where it lands, "roll" = a band it
## rolls along), color (its warn ring: palette.gd checks it on every floor).
const SURPRISES := {
	"crate": {"name": "CRATES!", "pic": "fallcrate", "shape": "drop", "color": Color(1.0, 0.6, 0.1)},
	"coconut": {"name": "COCONUTS!", "pic": "coconut", "shape": "drop", "color": Color(1.0, 0.85, 0.3)},
	"log": {"name": "ROLLING LOG!", "pic": "rolllog", "shape": "roll", "color": Color(1.0, 0.55, 0.2)},
	"rock": {"name": "LAVA ROCKS!", "pic": "meteor", "shape": "drop", "color": Color(1.0, 0.3, 0.1)},
	"snowball": {"name": "SNOWBALL!", "pic": "bigsnowball", "shape": "roll", "color": Color(1.0, 0.25, 0.2)},
	"comet": {"name": "COMETS!", "pic": "starrain", "shape": "drop", "color": Color(1.0, 0.9, 0.3)},
}
const ZONE_SURPRISES := {"neon": ["crate"], "jungle": ["coconut", "log"], "lava": ["rock"], "ice": ["snowball"],
	"star": ["comet"]}
## Per mode: surprises a wave (more from wave MORE_FROM), tell seconds, damage.
const SURPRISE_MODE := {
	"gentle": {"count": 1, "tell": 2.6, "damage": 4.0},
	"brave": {"count": 2, "tell": 2.0, "damage": 8.0},
	"hard": {"count": 3, "tell": 1.6, "damage": 10.0},
}
const FROM_WAVE := 3  # no surprise in waves 1-2 (or on a boss wave: the boss tells its own attacks)
const MORE_FROM := 8
const MAX_COUNT := 4
const FIRST_AT := 6.0  # seconds into the wave
const LAST_AT := 45.0
const GAP := 7.0  # between two surprises, at least
const MIN_TELL := 1.5
const REACT := 0.6  # seconds to notice a ring before running
const RUN_SPEED := 5.6  # the slowest hero's run (player.gd SPEED 7 x the 0.8 speed cap): m/s
const DROP_R := 2.0
const DROP_OFF := 2.5  # a drop lands up to this far from the player it falls by (never a bullseye: off >= 0.3)
const ROLL_W := 2.4  # the band's width
const ROLL_SECS := 1.0  # the roller takes this long across the arena
const MAX_HIT := 12.0

## NOVA'S CITY grows: a tower for every TOWER_EVERY waves cleared ever (up to TOWERS), a house per friend saved.
const TOWER_EVERY := 3
const TOWERS := 48


static func friend(id: String) -> Dictionary:
	for f in FRIENDS:
		if String(f.id) == id:
			return f
	return {}


static func friend_for_zone(zone_id: String) -> Dictionary:
	for f in FRIENDS:
		if String(f.zone) == zone_id:
			return f
	return {}


static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return {}


## Gifts the family can be offered: Nova's own + every saved friend's.
static func open_gifts(saved: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for g in GIFTS:
		if String(g.friend) == "" or int(saved.get(String(g.friend), 0)) > 0:
			out.append(String(g.id))
	return out


## The gift orbs after leg `leg`'s boss: GIFT_OFFER of the open gifts the team doesn't have yet, seeded per run + leg.
static func gift_offer(run_seed: int, leg: int, open: Array, owned: Array) -> Array:
	var pool: Array = []
	for id in open:
		if not owned.has(id):
			pool.append(String(id))
	var r := Seeded.rng(Seeded.derive(run_seed, "gifts%d" % leg), "offer")
	var out := Seeded.shuffled(r, pool)
	return out.slice(0, mini(GIFT_OFFER, out.size()))


## Problems with a gift offer (empty = fair).
static func check_gift_offer(ids: Array, open: Array, owned: Array) -> Array[String]:
	var why: Array[String] = []
	var left := 0
	for id in open:
		if not owned.has(id):
			left += 1
	if ids.size() != mini(GIFT_OFFER, left):
		why.append("gift offer has %d orbs (want %d)" % [ids.size(), mini(GIFT_OFFER, left)])
	var seen := {}
	for id in ids:
		if seen.has(id):
			why.append("gift %s offered twice" % id)
		seen[id] = true
		if not open.has(id):
			why.append("gift %s before its friend is saved" % id)
		if owned.has(id):
			why.append("gift %s offered again" % id)
		if gift(String(id)).is_empty():
			why.append("no gift called %s" % id)
	return why


## A wave's told surprises: [{t, id, shape, ang, off, who}] (t: seconds into the wave; ang / off place it round the
## player number `who` (mod the players up): deep_play.gd spot()).
static func plan(run_seed: int, wave: int, zone_id: String, mode: String) -> Array:
	var out: Array = []
	if wave < FROM_WAVE or wave % Gen.LEG == 0:
		return out
	var kinds: Array = ZONE_SURPRISES.get(zone_id, [])
	if kinds.is_empty():
		return out
	var m: Dictionary = SURPRISE_MODE.get(mode, SURPRISE_MODE.brave)
	var n := mini(MAX_COUNT, int(m.count) + (1 if wave >= MORE_FROM and mode != "gentle" else 0))
	var r := Seeded.rng(Seeded.derive(run_seed, "surprise%d" % wave), zone_id)
	var t := FIRST_AT + snappedf(r.randf_range(0.0, 4.0), 0.1)
	for i in n:
		if t > LAST_AT:
			break
		out.append({"t": t, "id": String(Seeded.pick(r, kinds)), "ang": snappedf(r.randf() * TAU, 0.01),
			"off": snappedf(r.randf_range(0.3, 1.0), 0.01), "who": r.randi_range(0, 5)})
		t += GAP + float(m.tell) + snappedf(r.randf_range(0.0, 6.0), 0.1)
	return out


static func tell_for(mode: String) -> float:
	return float(SURPRISE_MODE.get(mode, SURPRISE_MODE.brave).tell)


static func damage_for(mode: String) -> float:
	return float(SURPRISE_MODE.get(mode, SURPRISE_MODE.brave).damage)


## Where a surprise goes, round the player standing at `at`: {kind: "circle" | "line", pos, dir, size} (WarnRings).
## A drop lands DROP_OFF * off from the player (inside the wall); a roll crosses the arena wall to wall on a band
## passing off * 1.5 m beside the player.
static func spot(e: Dictionary, at: Vector3) -> Dictionary:
	var a := float(e.ang)
	var shape := String(SURPRISES.get(String(e.id), {}).get("shape", "drop"))
	var lim := Gen.ARENA_RADIUS - 1.0
	if shape == "roll":
		var d := Vector2.from_angle(a)
		var c := Vector2(at.x, at.z) + Vector2(-d.y, d.x) * float(e.off) * 1.5
		c = c.limit_length(lim - 3.0)
		# the chord through c along d: |c + s d| = lim
		var b := c.dot(d)
		var disc := b * b - (c.length_squared() - lim * lim)
		var s := sqrt(maxf(disc, 0.0))
		var from := c + d * (-b - s)
		return {"kind": "line", "pos": Vector3(from.x, 0.0, from.y), "dir": Vector3(d.x, 0.0, d.y),
			"size": Vector2(2.0 * s, ROLL_W)}
	var p := Vector2(at.x, at.z) + Vector2.from_angle(a) * float(e.off) * DROP_OFF
	p = p.limit_length(lim - DROP_R)
	return {"kind": "circle", "pos": Vector3(p.x, 0.0, p.y), "dir": Vector3.FORWARD, "size": Vector2(DROP_R, 0.0)}


## Problems with a wave's surprises (empty = fair): late enough, never on a boss wave, the zone's own kinds, told
## long enough to step out (even the slowest hero, after a moment to notice), a rest between, soft hits, and every spot
## (round players anywhere on the floor) inside the wall.
static func check_plan(p: Array, wave: int, zone_id: String, mode: String) -> Array[String]:
	var why: Array[String] = []
	if p.is_empty():
		return why
	var tag := "%s wave %d %s" % [zone_id, wave, mode]
	if wave < FROM_WAVE:
		why.append("%s: a surprise before wave %d" % [tag, FROM_WAVE])
	if wave % Gen.LEG == 0:
		why.append("%s: a surprise on a boss wave" % tag)
	if p.size() > MAX_COUNT:
		why.append("%s: %d surprises" % [tag, p.size()])
	var tell := tell_for(mode)
	if tell < (2.4 if mode == "gentle" else MIN_TELL):
		why.append("%s: told only %.1f s" % [tag, tell])
	if damage_for(mode) > MAX_HIT:
		why.append("%s: hits for %.0f" % [tag, damage_for(mode)])
	var out_drop := (DROP_R + 0.4) / RUN_SPEED + REACT
	var out_roll := (ROLL_W * 0.5 + 0.4) / RUN_SPEED + REACT
	if out_drop > tell or out_roll > tell:
		why.append("%s: no time to step out (%.1f s / %.1f s, told %.1f s)" % [tag, out_drop, out_roll, tell])
	var prev := -INF
	for e in p:
		var t := float(e.t)
		if t < FIRST_AT or t > LAST_AT:
			why.append("%s: a surprise at %.1f s" % [tag, t])
		if t - prev < GAP + tell - 0.01:
			why.append("%s: two surprises %.1f s apart" % [tag, t - prev])
		prev = t
		if not (ZONE_SURPRISES.get(zone_id, []) as Array).has(String(e.id)):
			why.append("%s: %s isn't a %s surprise" % [tag, e.id, zone_id])
		if float(e.off) < 0.3 - 0.001:
			why.append("%s: a bullseye drop" % tag)
		for at in [Vector3.ZERO, Vector3(16.5, 0, 0), Vector3(-11, 0, -11), Vector3(0, 0, 16.9), Vector3(5, 0, 4)]:
			var s := spot(e, at)
			var pos: Vector3 = s.pos
			if String(s.kind) == "circle" and Vector2(pos.x, pos.z).length() + DROP_R > Gen.ARENA_RADIUS:
				why.append("%s: a drop through the wall" % tag)
			if String(s.kind) == "line" and (float((s.size as Vector2).x) < 8.0 or Vector2(pos.x, pos.z).length() > Gen.ARENA_RADIUS):
				why.append("%s: a roll that doesn't cross the arena" % tag)
	return why


## How many new towers stand in Nova's city.
static func towers(waves_total: int) -> int:
	return clampi(waves_total / TOWER_EVERY, 0, TOWERS)
