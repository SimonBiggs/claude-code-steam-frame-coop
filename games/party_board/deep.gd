extends RefCounted
## PARTY BOARD second pass (pure data + small functions; tests/party_board_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked once a session on the pick orbs before the
##             first party (the family's last mode in the middle): how many red spaces a board has (partygen.gd
##             red_target, in the party's desc so every machine builds the same board), how far a red space slides
##             you back, and how often / how many / how big Mango's warned BOARD SURPRISES are.
##   GIFTS     MANGO'S GIFTS: from the second round, before the round starts, whoever is furthest behind (fewest
##             STARS; a person first, then whoever is furthest from the STAR) picks one of three gifts on the pick
##             orbs and keeps it until it is used: LUCKY DIE (the next roll is 4, 5 or 6), SHORTCUT (the next roll
##             hops SHORTCUT_HOPS more), UMBRELLA (the next push back - a red space or a surprise - does nothing),
##             DOUBLE STAR (the next STAR counts two; opens as Mango's party hall grows). Gifts never change the board,
##             the STAR's route or anyone else: a die never shows more than 6 and a turn never hops further than
##             two dice could (the test proves it), so partygen.gd check() still holds with every gift.
##   SURPRISES warned by steady core/warn_rings.gd discs ON THE SPACES, told when a round starts (never in round 1,
##             so everyone gets a whole round of turns to see them) and they go off when the round's last turn ends:
##               ROCK   an orange disc on one space: a rock from the volcano lands there.
##               SPLASH cyan discs on a few spaces in a row: a big wave splashes over them.
##             A token standing in one then slides back (deep.gd MODES hz_back; whoever is behind at most one; the
##             UMBRELLA keeps you dry). Never on START, the STAR, a chest, a present or special space, a junction,
##             or a space somebody stands on when it is told (zones() picks, problems() proves).
##   SEASONS   Seeded.season dresses every board: season_kit.gd props on the beach and petals / pollen / leaves /
##             snow drifting over the island (season.gd), and the party's opening banner (SPRING PARTY...).
##   HALL      MANGO'S PARTY HALL: Mango's trophy wall grows into a party hall, one step per finished party (with a
##             person playing): posts, bunting, a striped roof, balloons, a disco ball, fairy lights, a giant cake and
##             a gold star, and a present for every party stacked beside it (hall.gd; saved hall_n).
##   PICK ROWS the VR giant: three small orbs an arm's reach in front of the eyes, just under eye level ("vr"; placed
##             from the head after the VR height fit, so the island never hides them standing or seated; the hand
##             moves into one and stays DWELL s). No VR: three big orbs high over the middle of the island ("board").
##             TV / Deck players: the stick moves a dot in their colour between the orbs, A takes that one.

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")

## red_add: red spaces (partygen.gd red_target); back: a red space slides you back this many; hz_every: a surprise
## round every this many rounds (from round HZ_FROM); hz_n: surprises in such a round; wave: spaces a SPLASH covers;
## hz_back: a surprise slides you back this many.
const MODES := {
	"gentle": {"red_add": -1, "back": 1, "hz_every": 2, "hz_n": 1, "wave": 2, "hz_back": 1},
	"brave": {"red_add": 0, "back": 2, "hz_every": 1, "hz_n": 1, "wave": 3, "hz_back": 1},
	"hard": {"red_add": 1, "back": 2, "hz_every": 1, "hz_n": 2, "wave": 3, "hz_back": 2},
}
const MAX_BACK := 2  # nothing slides anyone back further than this
const HZ_FROM := 2  # no surprise in round 1
const HZ_MAX_SHARE := 0.2  # surprises never cover more than this share of the board at once
const KINDS: Array[String] = ["rock", "wave"]
const ROCK_COLOR := Color(1.0, 0.5, 0.08)  # rock orange
const WAVE_COLOR := Color(0.0, 0.82, 0.86)  # splash cyan
const KIND_PICS := {"rock": "boulder", "wave": "wave"}
const KIND_NAMES := {"rock": "ROCK!", "wave": "SPLASH!"}
const RING_R := 1.15  # a tell's disc on a space (board units; a tile is 1.8 across)
const RING_Y := 0.22  # over the tile's top
## Gifts: id, name (SIMPLE: one or two words), picture, colour, party hall steps needed.
const GIFTS: Array[Dictionary] = [
	{"id": "lucky", "name": "LUCKY DIE", "pic": "luckydie", "color": Color(0.45, 0.95, 0.5), "unlock": 0},
	{"id": "shortcut", "name": "SHORTCUT", "pic": "rainbow", "color": Color(0.85, 0.55, 1.0), "unlock": 0},
	{"id": "shield", "name": "UMBRELLA", "pic": "umbrella", "color": Color(0.5, 0.8, 1.0), "unlock": 0},
	{"id": "double", "name": "DOUBLE STAR", "pic": "doublestar", "color": Color(1.0, 0.85, 0.3), "unlock": 2},
]
const LUCKY_MIN := 4  # LUCKY DIE: a roll under this counts 3 more (1 -> 4, 2 -> 5, 3 -> 6)
const SHORTCUT_HOPS := 3
const DOUBLE_STARS := 2
const DIE_MAX := 6
const MAX_DICE := 2  # 2 DICE / ROCKET
const MAX_TURN_HOPS := DIE_MAX * MAX_DICE + 2  # the most a turn could ever hop without gifts (doubles: +2)
## Season -> the opening banner, its picture, the drift colour.
const SEASONS := {
	"spring": {"name": "SPRING PARTY", "pic": "daisy", "drift": Color(1.0, 0.72, 0.86)},
	"summer": {"name": "SUNNY PARTY", "pic": "sun", "drift": Color(1.0, 0.95, 0.6)},
	"autumn": {"name": "LEAFY PARTY", "pic": "pumpkin", "drift": Color(0.95, 0.5, 0.15)},
	"winter": {"name": "SNOWY PARTY", "pic": "snowflake", "drift": Color(0.97, 0.98, 1.0)},
}
## Mango's party hall: [finished parties, step id]. A present per party (up to HALL_PRESENTS) beside it.
const HALL_STEPS: Array = [[1, "posts"], [2, "bunting"], [3, "roof"], [5, "balloons"], [7, "disco"], [10, "lights"],
	[14, "cake"], [20, "star"]]
const HALL_PRESENTS := 12
## The pick rows. VR (metres): an arm's reach in front of the eyes, just under eye level; GENTLE on the left.
const VR_X: Array[float] = [-0.3, 0.0, 0.3]
const VR_AHEAD := 0.5  # (the names over the balls stay past core/vr_view_check.gd FACE_D)
const VR_BELOW := 0.14
const VR_SCALE := 0.11
const HAND_R := 0.05  # a hand this near an orb's ball touches it ...
const DWELL := 0.35  # ... for this long (deliberate: a hand sweeping past never picks)
## Board row (board units, no VR): high over the middle of the island (above the volcano's top and every token's name),
## GENTLE on the TV's left (+X: the TV looks south).
const BOARD_X: Array[float] = [5.2, 0.0, -5.2]
const BOARD_Y := 7.5
const BOARD_Z := 0.5
const BOARD_SCALE := 2.2
const ROW_WAIT := {"mode": 15.0, "gift": 10.0}  # nobody took one: the middle
const EMPTY_WAIT := 6.0  # nobody here who could pick at all
const CPU_PICK := 1.2  # a CPU takes its gift this long after the orbs open


static func mode_of(id: String) -> String:
	var m := String(PickOrbs.ALIASES.get(id, id))
	return m if MODES.has(m) else "brave"


static func mode_data(id: String) -> Dictionary:
	return MODES[mode_of(id)]


static func season_data(s: String) -> Dictionary:
	return SEASONS.get(s, SEASONS.spring)


static func wait_for(stage: String, nobody: bool) -> float:
	return EMPTY_WAIT if nobody else float(ROW_WAIT.get(stage, 10.0))


## Red spaces on a board for the family's level in a mode (partygen.gd uses it; never above max, never under 2).
static func red_target(level: int, mode: String, red_min: int, red_max: int) -> int:
	return clampi(red_min + maxi(0, level) + int(mode_data(mode).red_add), red_min - 1, red_max)


## Problems with the mode table (GENTLE <= BRAVE <= HARD in every way that makes it harder).
static func ordered(red_min: int = 3, red_max: int = 9) -> Array:
	var out: Array = []
	var g: Dictionary = MODES.gentle
	var b: Dictionary = MODES.brave
	var h: Dictionary = MODES.hard
	for k in ["red_add", "back", "hz_n", "wave", "hz_back"]:  # more is harder
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			out.append("%s not gentle <= brave <= hard" % k)
	if not (int(g.hz_every) >= int(b.hz_every) and int(b.hz_every) >= int(h.hz_every)):
		out.append("hz_every not least often on gentle")
	for m in MODES:
		var md: Dictionary = MODES[m]
		if int(md.back) > MAX_BACK or int(md.hz_back) > MAX_BACK:
			out.append("%s slides back too far" % m)
		if int(md.hz_every) < 1 or int(md.hz_n) < 1 or int(md.wave) < 2:
			out.append("%s surprises odd" % m)
	for level in 12:
		var rg := red_target(level, "gentle", red_min, red_max)
		var rb := red_target(level, "brave", red_min, red_max)
		var rh := red_target(level, "hard", red_min, red_max)
		if not (rg <= rb and rb <= rh):
			out.append("level %d reds not gentle <= brave <= hard (%d %d %d)" % [level, rg, rb, rh])
	for rounds in range(2, 9):
		var sg := surprise_rounds(rounds, "gentle").size()
		var sb := surprise_rounds(rounds, "brave").size()
		var sh := surprise_rounds(rounds, "hard").size()
		if not (sg <= sb and sb <= sh):
			out.append("%d rounds: surprise rounds not gentle <= brave <= hard" % rounds)
	return out


# --- Surprises ------------------------------------------------------------------------------------------

## Rounds (1-based) a party of `rounds` has surprises in.
static func surprise_rounds(rounds: int, mode: String) -> Array:
	var md := mode_data(mode)
	var out: Array = []
	for r in range(HZ_FROM, rounds + 1):
		if (r - HZ_FROM) % int(md.hz_every) == 0:
			out.append(r)
	return out


## A space a surprise may cover (before looking at who stands where): an ordinary blue / red space on the way,
## not START, a junction or right next to START.
static func plain(data, types: Array, i: int) -> bool:
	if i <= 0 or i >= types.size():
		return false
	var t := String(types[i])
	return (t == "blue" or t == "red") and not data.is_junction(i) and data.next_of(i).size() == 1 and data.distance(0, i) >= 2


## The spaces a surprise of `kind` starting at space i covers ([] when it can't start there).
static func cover(data, types: Array, kind: String, i: int, mode: String) -> Array:
	if not plain(data, types, i):
		return []
	var out: Array = [i]
	if kind == "wave":
		var at := i
		for k in int(mode_data(mode).wave) - 1:
			at = int(data.next_of(at)[0])
			if not plain(data, types, at) or out.has(at):
				return []
			out.append(at)
	return out


static func kind_at(seed_value: int, round_n: int, k: int) -> String:
	return KINDS[Seeded.rng(seed_value, "hz kind %d %d" % [round_n, k]).randi() % KINDS.size()]


## The round's surprises: [{kind, spaces: [ids]}] (the same on every machine for the same board and places).
## star: the STAR's space; chest: PIRATE COVE's chest (-1); stands: spaces tokens stand on now.
static func zones(data, types: Array, seed_value: int, round_n: int, rounds: int, mode: String, star: int, chest: int,
		stands: Array) -> Array:
	if not surprise_rounds(rounds, mode).has(round_n):
		return []
	var md := mode_data(mode)
	var used := {}
	var out: Array = []
	var cap := floori(types.size() * HZ_MAX_SHARE)
	var cand: Array = Seeded.shuffled(Seeded.rng(seed_value, "hz spots %d" % round_n), range(types.size()))
	for k in int(md.hz_n):
		var kind := kind_at(seed_value, round_n, k)
		for i in cand:
			var c := cover(data, types, kind, int(i), mode)
			if c.is_empty() or used.size() + c.size() > cap:
				continue
			var ok := true
			for s in c:
				if used.has(s) or int(s) == star or int(s) == chest or stands.has(int(s)):
					ok = false
					break
			if ok:
				for s in c:
					used[s] = true
				out.append({"kind": kind, "spaces": c})
				break
	return out


## Reasons a round's surprises are unfair (empty = fine).
static func problems(zs: Array, data, types: Array, mode: String, star: int, chest: int, stands: Array) -> Array:
	var why: Array = []
	var md := mode_data(mode)
	var seen := {}
	if zs.size() > int(md.hz_n):
		why.append("%d surprises (%s allows %d)" % [zs.size(), mode, int(md.hz_n)])
	for z in zs:
		var kind := String((z as Dictionary).get("kind", ""))
		var sp: Array = (z as Dictionary).get("spaces", [])
		if not KINDS.has(kind):
			why.append("unknown surprise %s" % kind)
			continue
		if sp.size() != (int(md.wave) if kind == "wave" else 1):
			why.append("%s covers %d spaces in %s" % [kind, sp.size(), mode])
		for j in sp.size():
			var s := int(sp[j])
			if not plain(data, types, s):
				why.append("%s on space %d (%s)" % [kind, s, String(types[s]) if s >= 0 and s < types.size() else "?"])
			if s == star:
				why.append("%s on the STAR (%d)" % [kind, s])
			if s == chest:
				why.append("%s on the chest (%d)" % [kind, s])
			if stands.has(s):
				why.append("%s on space %d where somebody stands" % [kind, s])
			if seen.has(s):
				why.append("two surprises on space %d" % s)
			seen[s] = true
			if j > 0 and not data.next_of(int(sp[j - 1])).has(s):
				why.append("%s spaces not in a row (%d, %d)" % [kind, int(sp[j - 1]), s])
	if seen.size() > floori(types.size() * HZ_MAX_SHARE):
		why.append("surprises cover %d of %d spaces" % [seen.size(), types.size()])
	return why


static func color_of(kind: String) -> Color:
	return ROCK_COLOR if kind == "rock" else WAVE_COLOR


## Is space s inside any of the zones?
static func hit(zs: Array, s: int) -> bool:
	for z in zs:
		if ((z as Dictionary).get("spaces", []) as Array).has(s):
			return true
	return false


# --- Gifts ----------------------------------------------------------------------------------------------

static func unlocked(hall_n: int) -> Array:
	var out: Array = []
	for g in GIFTS:
		if hall_n >= int(g.unlock):
			out.append(String(g.id))
	return out


static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return {}


## Three different unlocked gifts: the newest unlock always among them (the same on every machine for a seed).
static func gift_choices(hall_n: int, seed_value: int) -> Array:
	var un := unlocked(hall_n)
	var newest: String = un[un.size() - 1]
	var pool: Array = Seeded.shuffled(Seeded.rng(seed_value, "gifts"), un.filter(func(id: String) -> bool: return id != newest))
	var out: Array = [newest]
	for id in pool:
		if out.size() >= 3:
			break
		out.append(id)
	return Seeded.shuffled(Seeded.rng(seed_value, "gift order"), out)


## A die with a gift on (LUCKY DIE: 1-3 count 3 more). Never more than DIE_MAX.
static func die(v: int, gift_id: String) -> int:
	v = clampi(v, 1, DIE_MAX)
	return v + 3 if gift_id == "lucky" and v < LUCKY_MIN else v


## Hops a roll moves with a gift (SHORTCUT: more).
static func hops(total: int, gift_id: String) -> int:
	return total + (SHORTCUT_HOPS if gift_id == "shortcut" else 0)


## What a STAR is worth with a gift.
static func star_value(gift_id: String) -> int:
	return DOUBLE_STARS if gift_id == "double" else 1


## Who gets Mango's gift: whoever has the fewest STARS (a person first, then whoever is furthest from the STAR).
## recs: [{pid, stars, cpu, dist}] -> pid (-1 when nobody).
static func gift_to(recs: Array) -> int:
	var best := -1
	var key := 1 << 30
	for r in recs:
		var d: Dictionary = r
		var k: int = int(d.stars) * 100000 + (10000 if bool(d.cpu) else 0) + (1000 - mini(999, int(d.dist)))
		if best < 0 or k < key:
			best = int(d.pid)
			key = k
	return best


## Reasons the gifts could break the party's fairness (empty = fine): a die over 6, a turn hopping further than two
## dice, a STAR worth more than DOUBLE_STARS, a gift going to someone who isn't furthest behind.
static func gift_problems(seed_value: int) -> Array:
	var why: Array = []
	for g in GIFTS:
		var id := String(g.id)
		for v in range(1, DIE_MAX + 1):
			if die(v, id) > DIE_MAX or die(v, id) < v:
				why.append("%s turns %d into %d" % [id, v, die(v, id)])
		if hops(DIE_MAX, id) > MAX_TURN_HOPS:
			why.append("%s hops %d in a turn" % [id, hops(DIE_MAX, id)])
		if star_value(id) > DOUBLE_STARS or star_value(id) < 1:
			why.append("%s STAR worth %d" % [id, star_value(id)])
	var r := Seeded.rng(seed_value, "gift_to")
	for k in 20:
		var recs: Array = []
		for p in r.randi_range(1, 7):
			recs.append({"pid": p, "stars": r.randi_range(0, 4), "cpu": r.randf() < 0.5, "dist": r.randi_range(0, 30)})
		var who := gift_to(recs)
		var lo := 1 << 30
		var got := -1
		for d in recs:
			lo = mini(lo, int(d.stars))
			if int(d.pid) == who:
				got = int(d.stars)
		if got != lo:
			why.append("a gift went to %d with %d stars (fewest %d)" % [who, got, lo])
	for n in [0, 1, 2, 5, 20]:
		var ch := gift_choices(n, seed_value)
		if ch.size() != mini(3, unlocked(n).size()):
			why.append("%d gifts offered at hall %d" % [ch.size(), n])
		for id in ch:
			if not unlocked(n).has(id):
				why.append("%s offered before it opens" % id)
	return why


# --- Mango's party hall ----------------------------------------------------------------------------------

static func hall_steps(hall_n: int) -> Array:
	var out: Array = []
	for s in HALL_STEPS:
		if hall_n >= int(s[0]):
			out.append(String(s[1]))
	return out


# --- The pick rows ----------------------------------------------------------------------------------------

## The VR row: an arm's reach in front of the eyes (head: its world transform; metres, world).
static func vr_spots(head: Transform3D, n: int = 3) -> Array:
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	var out: Array = []
	for i in n:
		var x: float = VR_X[i] if n == 3 else lerpf(VR_X[0], VR_X[2], float(i) / maxf(1.0, n - 1))
		out.append(head.origin + fwd * VR_AHEAD + right * x + Vector3.DOWN * VR_BELOW)
	return out


## The board row (board units).
static func board_spots(n: int = 3) -> Array:
	var out: Array = []
	for i in n:
		var x: float = BOARD_X[i] if n == 3 else lerpf(BOARD_X[0], BOARD_X[2], float(i) / maxf(1.0, n - 1))
		out.append(Vector3(x, BOARD_Y, BOARD_Z))
	return out


## TV players' order (left to right on the TV, which looks south: +X is on the left): orb indices.
static func tv_order(spots: Array) -> Array:
	var idx: Array = range(spots.size())
	idx.sort_custom(func(a: int, b: int) -> bool: return (spots[a] as Vector3).x > (spots[b] as Vector3).x)
	return idx
