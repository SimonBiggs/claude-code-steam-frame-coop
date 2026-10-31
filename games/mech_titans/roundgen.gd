extends RefCounted
## MECH TITANS rounds (SIMPLE_MODE): the first three are the hand-made lessons (punch, then the beam,
## then the dash: data.gd SIMPLE_ROUNDS). From round 4 on every round is made from a seed: a lost
## kaiju (a colour / size variant with its own name, "TINY ZAPPY", "PINK WOBBLES"), a place on the
## island (new places open as the team makes kaiju friends), the sky, the city, sometimes little
## helpers (mini kaiju) and every fifth made round TWO lost kaiju. It gets a little tougher each round
## (more health, quicker, attacks a bit more often) but never too much. Round 4 of every session is
## TODAY'S kaiju (a golden one, the same on every machine all day).
## DEEP (titans-deep): three difficulties (MODES: GENTLE for little ones, the default; BRAVE opens with the
## Kaiju Sanctuary; MEGA after a boss went home in BRAVE), each a smooth curve over the laps (curve()); every
## fifth made round is a BOSS KAIJU with a crown and a big readable move (bigboss.gd); every place is a
## district with its own hazard (districts.gd), timed by the curve.
## Same (round, seed, friends, mode) -> same round. tests/mech_titans_rounds_test.gd checks many seeds,
## including that every city made can be driven / walked from the start to every rescue spot.

const Data := preload("res://games/mech_titans/data.gd")
const Seeded := preload("res://core/seeded.gd")
const BigBoss := preload("res://games/mech_titans/bigboss.gd")
const Districts := preload("res://games/mech_titans/districts.gd")

const LESSONS := 3  ## rounds 0-2 are data.gd's hand-made lessons
## Places open as the team makes friends: [place, friends needed].
const PLACE_UNLOCKS: Array = [["downtown", 0], ["harbour", 2], ["powerplant", 4], ["snowy", 6], ["volcano", 8], ["moon", 12]]
const SKIES := {"downtown": ["day", "sunset", "night"], "harbour": ["day", "sunset"], "powerplant": ["night", "day"],
	"snowy": ["snowy"], "volcano": ["sunset", "day"], "moon": ["space"]}
## Lost kaiju that suit each place (the first ones are likelier). No crab (its shell needs the full game's
## weak-spot painting) and no mega kaiju (its phases are the full game's finale).
const BOSSES := {"downtown": ["lizard", "jelly", "eel"], "harbour": ["eel", "jelly", "lizard"], "powerplant": ["eel", "lizard", "moth"],
	"snowy": ["moth", "jelly", "eel"], "volcano": ["lizard_queen", "lizard", "jelly"], "moon": ["jelly", "eel", "moth"]}
const MINIS := {"downtown": "slimelet", "harbour": "jellylet", "powerplant": "batlet", "snowy": "mothlet", "volcano": "froglet", "moon": "slimelet"}
## Colour variants: [name word, colour, second colour].
const PAINTS: Array = [["PINK", Color(1.0, 0.45, 0.72), Color(1.0, 0.68, 0.85)], ["BLUE", Color(0.35, 0.55, 1.0), Color(0.6, 0.78, 1.0)],
	["MINTY", Color(0.35, 0.88, 0.62), Color(0.65, 0.98, 0.8)], ["SUNNY", Color(1.0, 0.78, 0.2), Color(1.0, 0.9, 0.5)],
	["PURPLE", Color(0.62, 0.4, 0.95), Color(0.8, 0.66, 1.0)], ["", Color(), Color()]]
const GOLDEN := ["GOLDEN", Color(1.0, 0.82, 0.25), Color(1.0, 0.97, 0.75)]
const HP_MIN := 0.4
const HP_MAX := 0.95  ## gentle
const SLOW_MAX := 1.0  ## gentle
const CALM_MIN := 1.05  ## gentle
## Difficulty curves: lap = made round number from 0. hp: lost kaiju health multiplier (from hp0, +hp_step a
## lap, up to hp_max); slow: walking speed multiplier; calm: attack cooldown multiplier (bigger = calmer);
## tell: wind-up multiplier of ordinary attacks; boss_tell: of a boss's big move; haz_*: district hazards
## (every s from haz0, -haz_step a lap, down to haz_min; from lap haz_from; aim: at the Titan; count: x2 from
## lap haz_double); dmg: how hard hits land on the Titan; minis: helpers [from lap, chance, count0, count_max,
## interval0, interval_min]; boss_hp: extra on a boss kaiju.
const MODES := {
	"gentle": {"name": "GENTLE", "hp0": 0.5, "hp_step": 0.035, "hp_max": 0.95, "slow0": 0.8, "slow_step": 0.015, "slow_max": 1.0,
		"calm0": 1.6, "calm_step": 0.04, "calm_min": 1.05, "tell": 1.0, "boss_tell": 2.0, "haz0": 18.0, "haz_step": 0.3, "haz_min": 13.0,
		"haz_from": 0, "haz_aim": false, "haz_double": 999, "haz_tell": 1.7, "dmg": 0.6, "minis": [2, 0.5, 2, 4, 40.0, 25.0], "boss_hp": 1.0},
	"brave": {"name": "BRAVE", "hp0": 0.75, "hp_step": 0.045, "hp_max": 1.5, "slow0": 0.9, "slow_step": 0.02, "slow_max": 1.15,
		"calm0": 1.3, "calm_step": 0.04, "calm_min": 0.9, "tell": 1.0, "boss_tell": 1.4, "haz0": 12.0, "haz_step": 0.3, "haz_min": 8.0,
		"haz_from": 0, "haz_aim": true, "haz_double": 10, "haz_tell": 1.0, "dmg": 1.0, "minis": [1, 0.6, 2, 4, 34.0, 22.0], "boss_hp": 1.0},
	"mega": {"name": "MEGA", "hp0": 1.0, "hp_step": 0.06, "hp_max": 2.2, "slow0": 1.0, "slow_step": 0.02, "slow_max": 1.3,
		"calm0": 1.05, "calm_step": 0.03, "calm_min": 0.7, "tell": 0.9, "boss_tell": 1.0, "haz0": 9.0, "haz_step": 0.25, "haz_min": 6.0,
		"haz_from": 0, "haz_aim": true, "haz_double": 4, "haz_tell": 1.0, "dmg": 1.25, "minis": [0, 1.0, 3, 4, 30.0, 20.0], "boss_hp": 1.15},
}
const MODE_ORDER: Array[String] = ["gentle", "brave", "mega"]
const BOSS_EVERY := 5  ## made rounds 5, 10, 15... (lap % 5 == 4) are boss kaiju
const TWIN_LAP := 2  ## twin rounds: lap % 5 == 2 (from the third made round)


static func valid_mode(mode: String) -> bool:
	return MODES.has(mode)


## The difficulty at made round `lap` (0 = the first made round) of `mode`.
static func curve(mode: String, lap: int) -> Dictionary:
	var d: Dictionary = MODES.get(mode, MODES["gentle"])
	var l := maxi(lap, 0)
	var haz := 0.0
	var double := l >= int(d["haz_double"])
	if l >= int(d["haz_from"]):
		haz = maxf(float(d["haz0"]) - float(d["haz_step"]) * l, float(d["haz_min"]))
		if double:
			haz *= 1.95  # two land at once from now on, but a little less often (no sudden jump)
	return {"hp": clampf(float(d["hp0"]) + float(d["hp_step"]) * l, HP_MIN, float(d["hp_max"])),
		"slow": minf(float(d["slow0"]) + float(d["slow_step"]) * l, float(d["slow_max"])),
		"calm": maxf(float(d["calm0"]) - float(d["calm_step"]) * l, float(d["calm_min"])),
		"tell": float(d["tell"]), "boss_tell": float(d["boss_tell"]), "haz_every": haz, "haz_aim": bool(d["haz_aim"]),
		"haz_count": 2 if double else 1, "haz_tell_mult": float(d["haz_tell"]), "dmg": float(d["dmg"]),
		"boss_hp": float(d["boss_hp"])}


## One number for how hard a curve point is (the validator checks it rises smoothly).
static func threat(c: Dictionary) -> float:
	var haz := 0.0 if float(c["haz_every"]) <= 0.0 else 6.0 / float(c["haz_every"]) * float(c["haz_count"]) * (1.5 if bool(c["haz_aim"]) else 1.0)
	return float(c["hp"]) * float(c["slow"]) / float(c["calm"]) * float(c["dmg"]) / float(c["tell"]) * (1.0 + haz)


## The places open with `friends` kaiju friends.
static func places_open(friends: int) -> Array:
	var out: Array = []
	for pu in PLACE_UNLOCKS:
		if friends >= int(pu[1]):
			out.append(String(pu[0]))
	return out


## A place that opens exactly when friends goes from `before` to `after` ("" if none).
static func place_opened(before: int, after: int) -> String:
	for pu in PLACE_UNLOCKS:
		if before < int(pu[1]) and after >= int(pu[1]):
			return String(pu[0])
	return ""


## Round i (0-based) of a session with `run_seed`, when the team has `friends` kaiju friends.
## Mission-shaped (like Data.simple_round) plus: index, gen (true when made from a seed), daily, variant.
static func make(i: int, run_seed: int, friends: int, mode: String = "gentle") -> Dictionary:
	if not MODES.has(mode):
		mode = "gentle"
	if i < LESSONS:
		var m := Data.simple_round(i)
		m["index"] = i
		m["gen"] = false
		m["daily"] = false
		m["variant"] = {}
		m["mode"] = "gentle"  # the lessons are always gentle
		m["bigboss"] = ""
		m["lap"] = -1
		m["hazard"] = {"every": 0.0}
		m["tell"] = 1.0
		m["boss_tell"] = 1.0
		m["dmg"] = float(MODES["gentle"]["dmg"])
		return m
	var lap := i - LESSONS
	var daily := lap == 0
	var r := Seeded.rng(Seeded.daily_seed("mech_titans") if daily else run_seed, "round%d" % (0 if daily else i))
	var open := places_open(friends)
	# Lean towards the newest place (a new place is exciting), but visit the others too.
	var weights: Array = []
	for k in open.size():
		weights.append(1.0 + (2.0 if k == open.size() - 1 else 0.0))
	var place: String = open[Seeded.weighted(r, weights)]
	var sky: String = Seeded.pick(r, SKIES[place])
	var cv := curve(mode, lap)
	var big := lap % BOSS_EVERY == BOSS_EVERY - 1
	var twins := not big and lap % BOSS_EVERY == TWIN_LAP and lap >= TWIN_LAP
	var bigboss := ""
	if big:
		bigboss = String(Seeded.pick(r, BigBoss.for_place(place)))
	var choices: Array = BOSSES[place]
	var boss: String = choices[Seeded.weighted(r, [3, 2, 1])]
	if big:
		boss = String(BigBoss.LIST[bigboss]["base"])
	var bosses: Array = [boss]
	if twins:
		var other: String = choices[(choices.find(boss) + 1 + r.randi() % (choices.size() - 1)) % choices.size()]
		bosses.append(other)
	# The look: a size and a colour, which also make the name.
	var size := 1.0
	var size_word := ""
	var sz := r.randf()
	if sz < 0.25:
		size = r.randf_range(0.8, 0.9)
		size_word = "TINY"
	elif sz > 0.8:
		size = r.randf_range(1.12, 1.22)
		size_word = "BIG"
	var paint: Array = GOLDEN if daily else PAINTS[r.randi() % PAINTS.size()]
	var word: String = size_word if size_word != "" and not daily else String(paint[0])
	var variant := {"size": size, "word": word, "golden": daily}
	if String(paint[0]) != "":
		variant["color"] = paint[1]
		variant["color2"] = paint[2]
	var base_name := String(Data.KAIJU[boss]["name"])
	var kname := (word + " " + base_name) if word != "" else base_name
	if twins:
		kname = "TWIN TROUBLE"
	var hp := float(cv["hp"]) * (0.7 if twins else 1.0)
	if big:
		var bb: Dictionary = BigBoss.LIST[bigboss]
		kname = String(bb["name"])
		variant = {"size": float(bb["size"]), "word": "", "golden": daily, "color": bb["color"],
			"color2": (bb["color"] as Color).lightened(0.35), "crown": true, "boss": bigboss}
		hp *= float(bb["hp"]) * float(cv["boss_hp"])
	var step := {"boss": bosses}
	var mn: Array = MODES[mode]["minis"]
	var mroll := r.randf()
	if not big and lap >= int(mn[0]) and mroll < float(mn[1]):
		step["extra"] = [MINIS[place], mini(int(mn[2]) + lap / 4, int(mn[3])), maxf(float(mn[4]) - lap, float(mn[5]))]
	var hz := Districts.plan(place, {"haz_every": cv["haz_every"], "tell": cv["haz_tell_mult"], "haz_aim": cv["haz_aim"],
		"haz_count": cv["haz_count"], "dmg": cv["dmg"]})
	hz["kind"] = String(Districts.info(place)["hazard"])
	return {"name": kname, "place": place, "sky": sky, "seed": r.randi() % 100000, "protect": "",
		"rescue": 3 + r.randi() % 3, "steps": [step], "star2": ["damage", 100], "star3": ["damage", 100], "brief": [],
		"hp": hp, "slow": float(cv["slow"]), "calm": float(cv["calm"]), "index": i, "gen": true, "daily": daily, "variant": variant,
		"mode": mode, "lap": lap, "bigboss": bigboss, "hazard": hz, "tell": float(cv["tell"]), "boss_tell": float(cv["boss_tell"]),
		"dmg": float(cv["dmg"])}


## Why a round is not fair (empty = fine). Pure data checks; the city checks are in the test.
static func check(m: Dictionary, friends: int) -> Array:
	var out: Array = []
	if not Data.PLACES.has(String(m.get("place", ""))):
		out.append("unknown place %s" % str(m.get("place")))
	elif bool(m.get("gen", false)) and not places_open(friends).has(String(m.place)):
		out.append("place %s is not open with %d friends" % [m.place, friends])
	if not SkyKitNames.has(String(m.get("sky", ""))):
		out.append("unknown sky %s" % str(m.get("sky")))
	var steps: Array = m.get("steps", [])
	if steps.size() != 1:
		out.append("has %d steps" % steps.size())
	for st in steps:
		var bosses: Array = st.get("boss", [])
		if bosses.is_empty() or bosses.size() > 2:
			out.append("%d lost kaiju" % bosses.size())
		for b in bosses:
			if not Data.KAIJU.has(String(b)) or String(b) == "mega" or String(b) == "crab":
				out.append("kaiju %s can't be in a simple round" % str(b))
		if bosses.size() == 2 and bosses[0] == bosses[1]:
			out.append("twin kaiju are the same")
		if st.has("extra"):
			var ex: Array = st.extra
			if not Data.MINIS.has(String(ex[0])) or int(ex[1]) < 1 or int(ex[1]) > 4 or float(ex[2]) < 20.0:
				out.append("bad helpers %s" % str(ex))
	var mode := String(m.get("mode", "gentle"))
	if not MODES.has(mode):
		out.append("unknown mode %s" % mode)
		mode = "gentle"
	var md: Dictionary = MODES[mode]
	var hp := float(m.get("hp", 0.0))
	var hp_top := float(md["hp_max"])
	var bb_id := String(m.get("bigboss", ""))
	if bb_id != "":
		if not BigBoss.LIST.has(bb_id):
			out.append("unknown boss %s" % bb_id)
		else:
			hp_top *= float(BigBoss.LIST[bb_id]["hp"]) * float(md["boss_hp"])
			if not BigBoss.for_place(String(m.get("place", ""))).has(bb_id):
				out.append("boss %s doesn't live in %s" % [bb_id, m.get("place")])
			if String(BigBoss.LIST[bb_id]["base"]) != String((steps[0] as Dictionary).get("boss", [""])[0]):
				out.append("boss %s isn't its own kaiju" % bb_id)
	if hp < 0.25 or hp > hp_top + 0.001:
		out.append("hp %.2f out of range" % hp)
	if float(m.get("slow", 0.0)) > float(md["slow_max"]) + 0.001 or float(m.get("calm", 0.0)) < float(md["calm_min"]) - 0.001:
		out.append("too quick or too fierce")
	if bool(m.get("gen", false)):
		var hz: Dictionary = m.get("hazard", {})
		if float(hz.get("every", 0.0)) > 0.0 and String(hz.get("kind", "")) != String(Districts.info(String(m.get("place", ""))).get("hazard", "")):
			out.append("the hazard %s isn't this district's" % str(hz.get("kind")))
	var v: Dictionary = m.get("variant", {})
	if bool(m.get("gen", false)):
		var sz := float(v.get("size", 1.0))
		if sz < 0.75 or sz > (1.5 if bb_id != "" else 1.25):
			out.append("size %.2f out of range" % sz)
		var words := String(m.get("name", "")).split(" ", false)
		if words.size() > 2 or String(m.get("name", "")) != String(m.get("name", "")).to_upper():
			out.append("name '%s' must be one or two capital words (no how-to text)" % str(m.get("name")))
	if int(m.get("rescue", 0)) < 0 or int(m.get("rescue", 0)) > 6:
		out.append("rescue %d" % int(m.get("rescue", 0)))
	return out


const SkyKitNames := ["day", "dawn", "sunset", "night", "spooky", "dungeon", "space", "underwater", "stormy", "snowy", "indoor", "morning", "evening"]
