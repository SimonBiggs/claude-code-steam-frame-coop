extends RefCounted
## MECH TITANS rounds (SIMPLE_MODE): the first three are the hand-made lessons (punch, then the beam,
## then the dash: data.gd SIMPLE_ROUNDS). From round 4 on every round is made from a seed: a lost
## kaiju (a colour / size variant with its own name, "TINY ZAPPY", "PINK WOBBLES"), a place on the
## island (new places open as the team makes kaiju friends), the sky, the city, sometimes little
## helpers (mini kaiju) and every fifth made round TWO lost kaiju. It gets a little tougher each round
## (more health, quicker, attacks a bit more often) but never too much. Round 4 of every session is
## TODAY'S kaiju (a golden one, the same on every machine all day).
## Same (round, seed, friends) -> same round. tests/mech_titans_rounds_test.gd checks many seeds,
## including that every city made can be driven / walked from the start to every rescue spot.

const Data := preload("res://games/mech_titans/data.gd")
const Seeded := preload("res://core/seeded.gd")

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
const PAINTS: Array = [["PINK", Color(1.0, 0.5, 0.75), Color(1.0, 0.85, 0.95)], ["BLUE", Color(0.4, 0.6, 1.0), Color(0.8, 0.9, 1.0)],
	["MINTY", Color(0.45, 0.9, 0.7), Color(0.9, 1.0, 0.85)], ["SUNNY", Color(1.0, 0.8, 0.3), Color(1.0, 0.95, 0.7)],
	["PURPLE", Color(0.65, 0.45, 0.95), Color(0.9, 0.8, 1.0)], ["", Color(), Color()]]
const GOLDEN := ["GOLDEN", Color(1.0, 0.82, 0.25), Color(1.0, 0.97, 0.75)]
const HP_MIN := 0.4
const HP_MAX := 0.95
const SLOW_MAX := 1.0
const CALM_MIN := 1.05


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
static func make(i: int, run_seed: int, friends: int) -> Dictionary:
	if i < LESSONS:
		var m := Data.simple_round(i)
		m["index"] = i
		m["gen"] = false
		m["daily"] = false
		m["variant"] = {}
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
	var twins := lap % 5 == 4
	var choices: Array = BOSSES[place]
	var boss: String = choices[Seeded.weighted(r, [3, 2, 1])]
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
	var hp := clampf(0.5 + 0.035 * lap, HP_MIN, HP_MAX) * (0.7 if twins else 1.0)
	var slow := minf(0.8 + 0.015 * lap, SLOW_MAX)
	var calm := maxf(1.6 - 0.04 * lap, CALM_MIN)
	var step := {"boss": bosses}
	if lap >= 2 and r.randf() < 0.5:
		step["extra"] = [MINIS[place], mini(2 + lap / 4, 4), maxf(40.0 - lap, 25.0)]
	return {"name": kname, "place": place, "sky": sky, "seed": r.randi() % 100000, "protect": "",
		"rescue": 3 + r.randi() % 3, "steps": [step], "star2": ["damage", 100], "star3": ["damage", 100], "brief": [],
		"hp": hp, "slow": slow, "calm": calm, "index": i, "gen": true, "daily": daily, "variant": variant}


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
	var hp := float(m.get("hp", 0.0))
	if hp < 0.25 or hp > HP_MAX + 0.001:
		out.append("hp %.2f out of range" % hp)
	if float(m.get("slow", 0.0)) > SLOW_MAX + 0.001 or float(m.get("calm", 0.0)) < CALM_MIN - 0.001:
		out.append("too quick or too fierce")
	var v: Dictionary = m.get("variant", {})
	if bool(m.get("gen", false)):
		var sz := float(v.get("size", 1.0))
		if sz < 0.75 or sz > 1.25:
			out.append("size %.2f out of range" % sz)
		var words := String(m.get("name", "")).split(" ", false)
		if words.size() > 2 or String(m.get("name", "")) != String(m.get("name", "")).to_upper():
			out.append("name '%s' must be one or two capital words (no how-to text)" % str(m.get("name")))
	if int(m.get("rescue", 0)) < 0 or int(m.get("rescue", 0)) > 6:
		out.append("rescue %d" % int(m.get("rescue", 0)))
	return out


const SkyKitNames := ["day", "dawn", "sunset", "night", "spooky", "dungeon", "space", "underwater", "stormy", "snowy", "indoor", "morning", "evening"]
