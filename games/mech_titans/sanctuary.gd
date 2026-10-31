extends RefCounted
## MECH TITANS KAIJU SANCTUARY (saved): every lost kaiju the Titans send home moves into Momo's sanctuary on
## the hills round the city, and each one is a HEART (a boss counts BOSS_HEARTS and keeps its crown). As the
## hearts add up the sanctuary grows: new homes appear on the hills (a pond, palm trees, an igloo, a hot
## spring, moon rocks, a flower garden, a big slide, a rainbow arch) and more friends wave from them, and it
## unlocks new things for good: Titan frames (frames.gd), upgrades (upgrades.gd) and the BRAVE difficulty.
## The save: data["sanct"] = {"hearts": int, "bosses": {boss id: times sent home}} (progress.gd migrates old
## saves: every friend made before the sanctuary counts).

const Frames := preload("res://games/mech_titans/frames.gd")
const Upgrades := preload("res://games/mech_titans/upgrades.gd")

const BOSS_HEARTS := 3
## Homes on the hills: [hearts needed, id]. main.gd builds each one it has (and a few friends by it).
const HOMES: Array = [[1, "pond"], [4, "palms"], [8, "igloo"], [13, "spring"], [19, "moonrock"], [26, "flowers"], [35, "slide"], [48, "rainbow"]]
const BRAVE_HEARTS := 6  ## BRAVE difficulty opens (MEGA opens when a boss went home in BRAVE or MEGA)
const PARADE_MIN := 8
const PARADE_MAX := 16


static func hearts(data: Dictionary) -> int:
	var s: Variant = data.get("sanct", {})
	return maxi(0, int((s as Dictionary).get("hearts", 0))) if s is Dictionary else 0


## Hearts a round's kaiju bring: one per lost kaiju, BOSS_HEARTS for a boss.
static func hearts_for(m: Dictionary) -> int:
	if String(m.get("bigboss", "")) != "":
		return BOSS_HEARTS
	var steps: Array = m.get("steps", [])
	return maxi(1, ((steps[0] as Dictionary).get("boss", []) as Array).size()) if not steps.is_empty() else 1


## How many homes stand on the hills.
static func level(h: int) -> int:
	var n := 0
	for e in HOMES:
		if h >= int(e[0]):
			n += 1
	return n


static func homes(h: int) -> Array:
	var out: Array = []
	for e in HOMES:
		if h >= int(e[0]):
			out.append(String(e[1]))
	return out


## Friends waving from the hills at this many hearts.
static func parade_size(h: int) -> int:
	return mini(PARADE_MAX, PARADE_MIN + level(h))


## Everything that opens when the hearts go from `before` to `after`: [{"kind": "frame"/"upgrade"/"home"/"mode",
## "id": ..., "name": ...}] in order (the story cards after a round).
static func unlocks_between(before: int, after: int) -> Array:
	var out: Array = []
	for id in Frames.ORDER:
		var need := int(Frames.INFO[id]["hearts"])
		if before < need and after >= need:
			out.append({"kind": "frame", "id": id, "name": String(Frames.INFO[id]["name"])})
	for u in Upgrades.LIST:
		var need2 := int(u["hearts"])
		if before < need2 and after >= need2:
			out.append({"kind": "upgrade", "id": String(u["id"]), "name": String(u["name"])})
	if before < BRAVE_HEARTS and after >= BRAVE_HEARTS:
		out.append({"kind": "mode", "id": "brave", "name": "BRAVE"})
	for e in HOMES:
		if before < int(e[0]) and after >= int(e[0]):
			out.append({"kind": "home", "id": String(e[1]), "name": "SANCTUARY"})
	return out


## Everything unlocked so far past the start (the Trophy Hall's count).
static func unlock_count(h: int) -> int:
	return unlocks_between(0, h).size()
