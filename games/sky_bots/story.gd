extends RefCounted
## SKY BOTS story: GRANNY GIZMO, a kind old teapot robot, looks after GIZMO TOWN on a little island in the clouds. Its
## SKY LAMP lights the whole sky - until CRANKY CRAB took the lamp's SPARKS and hid them on the islands around. The
## robots hop out to MEADOW HOP, GEAR WORKS and CRAB COVE, bring a spark home from each, find the GOLD GEARS hidden in
## secret rooms, and Gizmo Town grows: every spark and every gear builds something new (hub.gd PIECES), and the lamp
## shines brighter. Told with StoryCard pictures and one short line each. Saved: what's been cleared and found.

const COLOR := Color(0.55, 0.85, 1.0)  ## Granny Gizmo's cards
const CRAB_COLOR := Color(1.0, 0.5, 0.35)
const LINES := {
	"intro1": ["My Sky Lamp went dark!", "skylamp"],
	"intro2": ["Cranky Crab took the sparks!", "crankycrab"],
	"intro3": ["Hop out and bring them home!", "skyspark"],
	"back": ["Welcome home, little bots!", "gizmo"],
	"spark": ["A spark! The lamp glows!", "skylamp"],
	"gear": ["A gold gear! Shiny!", "goldgear"],
	"secret_hint": ["A cracked wall... punch it!", "goldgear"],
	"lift": ["Ride the lift up!", "liftpad"],
	"grumble": ["Grumbles! Punch or hop!", "grumble"],
	"zap": ["Zap pads! Wait for the flash!", "zappad"],
	"crab": ["Cranky Crab! Wait till it's dizzy!", "crankycrab"],
	"crab_down": ["Cranky Crab says sorry!", "crankycrab"],
	"all_sparks": ["The lamp is shining bright!", "skylamp"],
	"daily": ["A new island today!", "skyisland"],
	"pick": ["Where shall we hop?", "skyisland"],
	"mode": ["Easy or tricky?", "gizmo"],
}


static func save_defaults() -> Dictionary:
	return {"world": -1, "cleared": 0, "visits": [0, 0, 0, 0], "sparks": 0, "gears": 0, "gear_isles": 0, "bolts": 0,
		"best_bolts": 0, "crabs": 0, "daily": "", "daily_done": "", "mode": "", "intro": false, "grown": 0}


static func line(key: String) -> Dictionary:
	var l: Array = LINES.get(key, ["Hello!", "gizmo"])
	var crab := String(l[1]) == "crankycrab" and key != "crab_down"
	return {"who": "CRANKY CRAB" if key == "intro2" else "GRANNY GIZMO", "line": String(l[0]), "pic": String(l[1]),
		"color": CRAB_COLOR if crab else COLOR, "duration": 3.5}


## How much Gizmo Town has grown: a spark (an island cleared, any time) and a gold gear each build one more thing.
static func power(data: Dictionary) -> int:
	return int(data.get("sparks", 0)) + int(data.get("gears", 0))


## Which islands may be picked: island 1 always, each one after the one before was cleared; TODAY'S ISLAND (0) once
## island 1 has been cleared.
static func open_islands(cleared: int) -> Array:
	var out: Array = [1]
	for i in [2, 3]:
		if cleared & (1 << (i - 2)):
			out.append(i)
	if cleared & 1:
		out.append(0)
	return out


## The island to suggest (the glowing middle orb): the first not cleared yet, else TODAY'S ISLAND if not done today,
## else Crab Cove.
static func suggest(cleared: int, daily_done_today: bool) -> int:
	for i in [1, 2, 3]:
		if not cleared & (1 << (i - 1)):
			return i
	return 3 if daily_done_today else 0
