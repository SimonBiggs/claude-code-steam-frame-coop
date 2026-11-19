extends RefCounted
## SKY BOTS story: GRANNY GIZMO, a kind old teapot robot, looks after GIZMO TOWN on a little island in the clouds. Its
## SKY LAMP lights the whole sky - until CRANKY CRAB took the lamp's SPARKS and hid them on the islands around. The
## robots hop out to MEADOW HOP, GEAR WORKS and CRAB COVE, bring a spark home from each, find the GOLD GEARS hidden in
## secret rooms, and Gizmo Town grows: every spark and every gear builds something new (hub.gd PIECES), and the lamp
## shines brighter. Told with StoryCard pictures and one short line each. Saved: what's been cleared and found.
## CHAPTER TWO (after Crab Cove): KING KEYWIND, a huffy wind-up king, has shut LITTLE BOTS in BOT BOXES on the far
## islands - SNOWY PEAKS, JUNGLE JUMBLE and his CLOCKWORK KEEP. Every little bot let out moves to Gizmo Town (hub.gd)
## and they sew costume HATS for the robots (hats.gd). Boxes are on every island, the first ones too.

const ISLANDS := 6  ## (levelgen.gd ISLANDS)
const MAX_ORBS := 4  ## island orbs at once (Gizmo Town's front fits four)
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
	"chapter2": ["New islands! Little bots need help!", "tinybot"],
	"tiny": ["A little bot! Off home you go!", "tinybot"],
	"tiny_box": ["A bot box! Bump it open!", "botbox"],
	"hat": ["The little bots made a hat!", "hattop"],
	"spring": ["Boing! Hop on the spring!", "springpad"],
	"fan": ["Wind fans! Float across!", "windfan"],
	"belt": ["Moving floors! Keep running!", "beltpad"],
	"moves": ["In the air: X dash, B pound!", "skybot"],
	"king": ["King Keywind! Hop out of his way!", "kingkeywind"],
	"king_down": ["King Keywind needs a nap!", "kingkeywind"],
	"all_keys": ["Every island is safe again!", "skylamp"],
}


static func save_defaults() -> Dictionary:
	return {"world": -1, "cleared": 0, "visits": [0, 0, 0, 0, 0, 0, 0], "sparks": 0, "gears": 0, "gear_isles": 0, "bolts": 0,
		"best_bolts": 0, "crabs": 0, "kings": 0, "daily": "", "daily_done": "", "mode": "", "intro": false, "grown": 0,
		"tiny": 0, "hats": {}, "ch2": false}


## An older save's visits list grows to every island (an island added later starts at 0 visits).
static func fix_save(data: Dictionary) -> bool:
	var v: Array = data.get("visits", [])
	if v.size() >= ISLANDS + 1:
		return false
	while v.size() < ISLANDS + 1:
		v.append(0)
	data["visits"] = v
	return true


static func line(key: String) -> Dictionary:
	var l: Array = LINES.get(key, ["Hello!", "gizmo"])
	var crab := (String(l[1]) == "crankycrab" and key != "crab_down") or key == "king"
	return {"who": "CRANKY CRAB" if key == "intro2" else "GRANNY GIZMO", "line": String(l[0]), "pic": String(l[1]),
		"color": CRAB_COLOR if crab else COLOR, "duration": 3.5}


## How much Gizmo Town has grown: a spark (an island cleared, any time) and a gold gear each build one more thing.
static func power(data: Dictionary) -> int:
	return int(data.get("sparks", 0)) + int(data.get("gears", 0))


## Which islands may be picked: island 1 always, each one after the one before was cleared; TODAY'S ISLAND (0) once
## island 1 has been cleared.
static func open_islands(cleared: int) -> Array:
	var out: Array = [1]
	for i in range(2, ISLANDS + 1):
		if cleared & (1 << (i - 2)):
			out.append(i)
	if cleared & 1:
		out.append(0)
	return out


## The islands on the pick orbs (at most MAX_ORBS): the suggested one always, TODAY'S ISLAND when it's open, then the
## other open islands newest first, shown in island order with TODAY last.
static func pick_set(cleared: int, daily_done_today: bool) -> Array:
	var open := open_islands(cleared)
	if daily_done_today:
		open.erase(0)
	var sug := suggest(cleared, daily_done_today)
	var want: Array = [sug]
	if open.has(0) and sug != 0:
		want.append(0)
	var rest: Array = open.filter(func(i: int) -> bool: return i != 0 and not want.has(i))
	rest.sort()
	rest.reverse()
	for i in rest:
		if want.size() >= MAX_ORBS:
			break
		want.append(i)
	var isles: Array = want.filter(func(i: int) -> bool: return i != 0)
	isles.sort()
	if want.has(0):
		isles.append(0)
	return isles


## The island to suggest (the glowing middle orb): the first not cleared yet, else TODAY'S ISLAND if not done today,
## else Crab Cove.
static func suggest(cleared: int, daily_done_today: bool) -> int:
	for i in range(1, ISLANDS + 1):
		if not cleared & (1 << (i - 1)):
			return i
	return ISLANDS if daily_done_today else 0


## Sparks lit on the Sky Lamp's first ring (the first three islands) and its second (the far three).
static func sparks_lit(cleared: int) -> int:
	var n := 0
	for i in ISLANDS:
		n += (cleared >> i) & 1
	return n
