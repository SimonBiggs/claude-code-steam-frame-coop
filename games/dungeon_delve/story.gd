extends RefCounted
## DUNGEON DELVE's story (BRAVE / HEROIC / TODAY'S runs): a reason to go down, a villain, and an ending.
##  SMUDGE, Cinder's grumpy big cousin (a purple dragon), grabbed her treasure and her little friends and hid
##  them down in the deep, behind his four bosses (Slime King, Bone Lord, Crystal Queen, Forge Golem).
##  - A run starts: Cinder says what happened, Smudge teases (the full two cards on the family's first few
##    runs, then one short line).
##  - A new biome: Cinder says one thing about it (and Smudge teases until the ending has been seen).
##  - A boss falls: Smudge grumbles and names the next one.
##  - The Forge Golem falls: THE ENDING. Smudge says why he did it (nobody played with him), Cinder asks him
##    to play with them, he says sorry. Saved (deep.story.ending): from then on Smudge sits with Cinder on her
##    hoard in the practice room and at the camp, and he cheers you on in the endless depths.
## Pure data + the dragon's look, so tests can check every beat (short lines, known pictures).
## Story lines are kind and short: kids read them on the TV and the Decks.

const MeshKit := preload("res://core/mesh_kit.gd")

const SMUDGE_COLOR := "b58cff"
const CINDER_COLOR := "ff9a40"
const GAP := 3.4  ## seconds between the cards of one beat (a card shows ~3 s; StoryCard queues anyway)
const INTRO_FULL_RUNS := 3  ## the first runs get the whole intro; after that one short line

const INTRO_FULL: Array = [
	{"who": "CINDER", "line": "Smudge took my treasure and my friends!", "pic": "cinder", "color": CINDER_COLOR, "duration": 3.4},
	{"who": "SMUDGE", "line": "Come down and get them! Hee hee!", "pic": "smudge", "color": SMUDGE_COLOR, "duration": 3.2},
]
const INTRO_SHORT: Array = [
	{"who": "CINDER", "line": "Down we go! Let's find Smudge!", "pic": "cinder", "color": CINDER_COLOR, "duration": 2.8},
]
const INTRO_AFTER_ENDING: Array = [
	{"who": "SMUDGE", "line": "Race you to the bottom!", "pic": "smudge_happy", "color": SMUDGE_COLOR, "duration": 2.8},
]
## Arriving in biome z (z = 1..3; the first biome has the intro).
const ZONE_BEATS: Array = [
	[],
	[{"who": "CINDER", "line": "Spooky bones! Stay close!", "pic": "cinder", "color": CINDER_COLOR, "duration": 2.8},
		{"who": "SMUDGE", "line": "My Bone Lord will rattle you!", "pic": "smudge", "color": SMUDGE_COLOR, "duration": 2.8}],
	[{"who": "CINDER", "line": "So sparkly! I smell smoke...", "pic": "cinder", "color": CINDER_COLOR, "duration": 2.8},
		{"who": "SMUDGE", "line": "The Crystal Queen is MY friend!", "pic": "smudge", "color": SMUDGE_COLOR, "duration": 2.8}],
	[{"who": "CINDER", "line": "So hot! Smudge lives here!", "pic": "cinder", "color": CINDER_COLOR, "duration": 2.8},
		{"who": "SMUDGE", "line": "Nobody gets past my Forge Golem!", "pic": "smudge", "color": SMUDGE_COLOR, "duration": 2.8}],
]
const ENDLESS_BEAT: Array = [
	{"who": "SMUDGE", "line": "Deeper? I know a secret way!", "pic": "smudge_happy", "color": SMUDGE_COLOR, "duration": 3.0},
]
## A boss of biome z fell (the last one starts the ending instead).
const BOSS_BEATS: Array = [
	[{"who": "SMUDGE", "line": "My Slime King! Grr! Try the crypt!", "pic": "smudge", "color": SMUDGE_COLOR, "duration": 3.0}],
	[{"who": "SMUDGE", "line": "Not my Bone Lord! Hmph!", "pic": "smudge", "color": SMUDGE_COLOR, "duration": 3.0}],
	[{"who": "SMUDGE", "line": "Okay, okay! But my Golem is BIG!", "pic": "smudge", "color": SMUDGE_COLOR, "duration": 3.0}],
]
const ENDING: Array = [
	{"who": "SMUDGE", "line": "You beat them ALL...", "pic": "smudge", "color": SMUDGE_COLOR, "duration": 3.2},
	{"who": "SMUDGE", "line": "Nobody ever played with me.", "pic": "smudge", "color": SMUDGE_COLOR, "duration": 3.2},
	{"who": "CINDER", "line": "Then come and play with US!", "pic": "cinder", "color": "ffd25a", "duration": 3.2},
	{"who": "SMUDGE", "line": "Really?! Here's your treasure. Sorry!", "pic": "smudge_happy", "color": SMUDGE_COLOR, "duration": 3.6},
]
## A later win (the ending was seen before): one happy card.
const ENDING_AGAIN: Array = [
	{"who": "SMUDGE", "line": "You did it AGAIN! Best friends!", "pic": "smudge_happy", "color": SMUDGE_COLOR, "duration": 3.2},
]


## The cards for the start of a run (runs = runs started before this one, ending = the ending was seen).
static func intro(runs: int, ending: bool) -> Array:
	if ending:
		return INTRO_AFTER_ENDING
	return INTRO_FULL if runs < INTRO_FULL_RUNS else INTRO_SHORT


## The cards when the party arrives in biome z (after the ending, Smudge is a friend: Cinder's line only).
static func zone_beats(z: int, ending: bool) -> Array:
	if z >= ZONE_BEATS.size():
		return ENDLESS_BEAT if z == ZONE_BEATS.size() else []
	var out: Array = (ZONE_BEATS[z] as Array).duplicate()
	if ending:
		out = out.filter(func(b: Dictionary) -> bool: return String(b["who"]) != "SMUDGE")
	return out


static func boss_beats(z: int, ending: bool) -> Array:
	if z == ZONE_BEATS.size() - 1:
		return ENDING_AGAIN if ending else ENDING
	if z < 0 or z >= BOSS_BEATS.size() or ending:
		return []
	return BOSS_BEATS[z]


## Every beat there is (the story test checks each one).
static func all_beats() -> Array:
	var out: Array = []
	for a in [INTRO_FULL, INTRO_SHORT, INTRO_AFTER_ENDING, ENDLESS_BEAT, ENDING, ENDING_AGAIN]:
		out.append_array(a)
	for z in ZONE_BEATS:
		out.append_array(z)
	for z2 in BOSS_BEATS:
		out.append_array(z2)
	return out


## The two dragons as little 3D figures (Cinder on her hoard; Smudge beside her after the ending). One mesh each.
static func dragon_mesh(body: Color, belly: Color, wing: Color, happy: bool = true) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.ellipsoid(Vector3(0.26, 0.24, 0.3), MeshKit.at(Vector3(0, 0.26, 0)), body, 14)
	b.ellipsoid(Vector3(0.17, 0.17, 0.1), MeshKit.at(Vector3(0, 0.24, 0.22)), belly, 12)
	b.sphere(0.2, MeshKit.at(Vector3(0, 0.58, 0.1)), body, 14)
	b.ellipsoid(Vector3(0.11, 0.08, 0.1), MeshKit.at(Vector3(0, 0.53, 0.28)), body.lightened(0.1), 10)
	for sx in [-1.0, 1.0]:
		b.sphere(0.055, MeshKit.at(Vector3(0.08 * sx, 0.64, 0.26)), Color(1, 1, 1), 8)
		b.sphere(0.03, MeshKit.at(Vector3(0.08 * sx, 0.64 if happy else 0.62, 0.3)), Color(0.12, 0.08, 0.1), 6)
		b.cone(0.045, 0.16, MeshKit.at(Vector3(0.1 * sx, 0.8, 0.04), Vector3.ONE, Vector3(-0.3, 0, -0.3 * sx)), belly, 6)
		b.polygon(PackedVector2Array([Vector2(0, 0), Vector2(0.34, 0.2), Vector2(0.3, -0.02), Vector2(0.24, 0.06), Vector2(0.18, -0.06)]), 0.02,
			MeshKit.at(Vector3(0.18 * sx, 0.38, -0.08), Vector3(sx, 1, 1), Vector3(0, -0.4 * sx, 0)), wing)
		b.sphere(0.07, MeshKit.at(Vector3(0.13 * sx, 0.05, 0.12)), body.darkened(0.15), 8)
	if not happy:  # a grumpy brow
		b.box(Vector3(0.22, 0.025, 0.02), MeshKit.at(Vector3(0, 0.71, 0.27), Vector3.ONE, Vector3(0, 0, 0)), body.darkened(0.4))
	b.cone(0.09, 0.4, MeshKit.at(Vector3(0, 0.18, -0.38), Vector3.ONE, Vector3(-1.9, 0, 0)), body.darkened(0.1), 8)
	return b.build()


static func cinder_mesh() -> ArrayMesh:
	return dragon_mesh(Color(1.0, 0.55, 0.2), Color(1.0, 0.88, 0.6), Color(0.95, 0.35, 0.3))


static func smudge_mesh() -> ArrayMesh:
	return dragon_mesh(Color(0.55, 0.4, 0.85), Color(0.85, 0.78, 1.0), Color(0.35, 0.25, 0.6))