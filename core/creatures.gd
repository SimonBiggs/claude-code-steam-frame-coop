extends RefCounted
## Creatures: cute, consistent procedural characters built with core/mesh_kit.gd: a chibi humanoid
## (24 classes/outfits, hats, held items, hair styles, beards) and 24 monsters/animals, each a handful
## of draw calls, plus an animation helper node (idle, walk, blink, squash, hurt flash, attack lunge,
## cast, cheer, wave, talk, jump, faint).
##
##   const Creatures := preload("res://core/creatures.gd")
##   var hero := Creatures.humanoid({"class": "knight", "hair": Color(0.9, 0.6, 0.2)})
##   add_child(hero)
##   var anim := Creatures.anim(hero)
##   anim.walk(2.0)                  # m/s; 0 = stand
##   anim.face(Vector3(1, 0, 0))     # turn smoothly towards +X
##   anim.play("attack")             # await anim.action_finished for battle sequencing
##   var slime := Creatures.monster("slime", {"color": Color(0.4, 0.8, 1.0)})
##
## Conventions: origin at the feet (y = 0), FRONT = +Z (Godot's MODEL_FRONT, like imported glTF; use
## anim.face(dir) or `look_at(target, Vector3.UP, true)`), character's left = +X. A humanoid is
## ~1.1 m tall at scale 1 (opts.scale scales it). Meshes are cached per look (ResCache), so a crowd of
## identical goblins shares its meshes.
## Draw calls (near LOD): humanoid 6 (torso, head, 2 arms, 2 legs; +1 while blinking, +1 per glowing
## item/hat surface, +1 for the astronaut's glass bubble). Monsters: see MONSTER_INFO. opts.lod = "far"
## gives ONE merged mesh (no limb animation, still bobs/hops/flashes); "auto" switches at lod_distance.

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Me := preload("res://core/creatures.gd")

const VERSION := "v1"

const CLASSES: Array[String] = ["knight", "mage", "healer", "thief", "archer", "bard", "pirate", "astronaut",
	"chef", "detective", "monk", "ninja", "king", "queen", "princess", "villager", "scientist", "farmer", "viking",
	"crew", "pilot", "golfer", "host", "athlete"]
const HATS: Array[String] = ["none", "helmet", "wizard", "hood", "crown", "tiara", "tricorn", "beret", "chef", "fedora",
	"deerstalker", "cap", "straw", "headband", "bandana", "beanie", "space_helmet", "viking", "top_hat", "party",
	"feather_cap", "ninja", "goggles", "pilot_helmet", "hard_hat", "flower", "bow", "halo"]
const ITEMS: Array[String] = ["none", "sword", "dagger", "katana", "cutlass", "axe", "hammer", "spear", "club", "staff",
	"rod", "wand", "bow", "shield", "round_shield", "lute", "ladle", "magnifier", "flask", "torch", "pitchfork",
	"sceptre", "book", "lantern", "blaster", "wrench", "golf_club", "microphone", "pan", "fishing_rod", "broom",
	"tablet", "flag"]
const HAIR_STYLES: Array[String] = ["short", "long", "spiky", "bob", "ponytail", "bun", "curly", "mohawk", "pigtails", "bald"]
const BEARDS: Array[String] = ["none", "short", "long", "moustache"]
const MONSTERS: Array[String] = ["slime", "bat", "goblin", "skeleton", "wolf", "dragon", "robot", "ghost", "fish",
	"bird", "mushroom", "mimic", "frog", "spider", "penguin", "bunny", "bee", "crab", "golem", "cat", "dog", "fox",
	"pig", "sheep"]
## kind -> [rig, near draw calls]. Glowing eyes (skeleton, robot, golem, mimic, boss variants) are
## included; boss variants may add one more.
const MONSTER_INFO := {
	"slime": ["blob", 1], "bat": ["flyer", 3], "goblin": ["biped", 6], "skeleton": ["biped", 7], "wolf": ["quad", 6],
	"dragon": ["flyer", 6], "robot": ["biped", 7], "ghost": ["float", 3], "fish": ["swim", 2], "bird": ["flyer", 3],
	"mushroom": ["biped", 3], "mimic": ["chest", 3], "frog": ["blob", 1], "spider": ["crawler", 3],
	"penguin": ["biped", 5], "bunny": ["blob", 1], "bee": ["flyer", 3], "crab": ["biped", 3], "golem": ["biped", 7],
	"cat": ["quad", 6], "dog": ["quad", 6], "fox": ["quad", 6], "pig": ["quad", 6], "sheep": ["quad", 6],
}
const ACTIONS: Array[String] = ["attack", "hurt", "cast", "cheer", "jump", "wave", "talk", "nod", "victory", "faint"]

const SKIN_TONES: Array[Color] = [Color(1.0, 0.87, 0.76), Color(0.98, 0.79, 0.64), Color(0.88, 0.67, 0.52),
	Color(0.74, 0.52, 0.38), Color(0.56, 0.38, 0.27), Color(0.42, 0.29, 0.21)]
const HAIR_COLORS: Array[Color] = [Color(0.3, 0.2, 0.14), Color(0.13, 0.11, 0.12), Color(0.58, 0.37, 0.2),
	Color(0.97, 0.82, 0.46), Color(0.88, 0.42, 0.2), Color(0.92, 0.92, 0.95), Color(0.98, 0.58, 0.72),
	Color(0.42, 0.58, 0.98), Color(0.6, 0.44, 0.86), Color(0.38, 0.78, 0.58)]
const OUTFIT_COLORS: Array[Color] = [Color(1.0, 0.5, 0.45), Color(0.4, 0.7, 1.0), Color(0.45, 0.85, 0.6),
	Color(1.0, 0.85, 0.35), Color(0.7, 0.55, 0.95), Color(1.0, 0.68, 0.45), Color(0.28, 0.72, 0.72), Color(0.95, 0.45, 0.65)]

const STEEL := Color(0.74, 0.78, 0.86)
const GOLD := Color(1.0, 0.8, 0.32)
const WOOD := Color(0.58, 0.38, 0.24)
const EYE := Color(0.13, 0.1, 0.16)
const WHITE := Color(0.97, 0.97, 0.95)
const DARK := Color(0.18, 0.18, 0.24)

## Per-class look: outfit colours, default hat/items/hair and extras (cape, robe, belt, ...).
const LOOKS := {
	"knight": {"outfit": STEEL, "outfit2": Color(0.25, 0.45, 0.9), "pants": Color(0.46, 0.5, 0.58), "shoes": Color(0.36, 0.37, 0.44),
		"hat": "helmet", "weapon": "sword", "offhand": "shield", "cape": Color(0.88, 0.22, 0.27),
		"extras": ["cape", "tabard", "pauldrons", "belt", "boots", "gauntlets"]},
	"mage": {"outfit": Color(0.45, 0.32, 0.85), "outfit2": GOLD, "pants": Color(0.32, 0.22, 0.6), "shoes": Color(0.35, 0.25, 0.2),
		"hat": "wizard", "weapon": "staff", "offhand": "none", "extras": ["robe", "sash"]},
	"healer": {"outfit": WHITE, "outfit2": Color(0.92, 0.32, 0.38), "pants": Color(0.85, 0.85, 0.82), "shoes": Color(0.6, 0.45, 0.3),
		"hat": "hood", "weapon": "rod", "offhand": "none", "extras": ["robe", "trim"]},
	"thief": {"outfit": Color(0.3, 0.38, 0.42), "outfit2": Color(0.75, 0.25, 0.32), "pants": Color(0.22, 0.25, 0.3), "shoes": Color(0.3, 0.22, 0.18),
		"hat": "bandana", "weapon": "dagger", "offhand": "dagger", "extras": ["scarf", "belt", "boots"]},
	"archer": {"outfit": Color(0.35, 0.65, 0.35), "outfit2": Color(0.6, 0.42, 0.26), "pants": Color(0.5, 0.36, 0.24), "shoes": Color(0.38, 0.26, 0.18),
		"hat": "feather_cap", "weapon": "none", "offhand": "bow", "extras": ["quiver", "belt", "boots"]},
	"bard": {"outfit": Color(0.95, 0.45, 0.32), "outfit2": Color(1.0, 0.85, 0.4), "pants": Color(0.4, 0.3, 0.6), "shoes": Color(0.4, 0.28, 0.2),
		"hat": "beret", "weapon": "lute", "offhand": "none", "extras": ["sash", "belt"]},
	"pirate": {"outfit": WHITE, "outfit2": Color(0.88, 0.26, 0.28), "pants": Color(0.2, 0.25, 0.45), "shoes": Color(0.2, 0.16, 0.14),
		"hat": "tricorn", "weapon": "cutlass", "offhand": "none", "extras": ["stripes", "belt", "boots", "eyepatch"]},
	"astronaut": {"outfit": Color(0.95, 0.95, 0.97), "outfit2": Color(1.0, 0.55, 0.22), "pants": Color(0.9, 0.9, 0.93), "shoes": Color(0.6, 0.62, 0.68),
		"hat": "space_helmet", "weapon": "none", "offhand": "none", "extras": ["backpack", "chest_panel", "boots", "gauntlets"]},
	"chef": {"outfit": WHITE, "outfit2": Color(0.9, 0.28, 0.28), "pants": Color(0.3, 0.3, 0.34), "shoes": Color(0.2, 0.2, 0.22),
		"hat": "chef", "weapon": "ladle", "offhand": "none", "extras": ["apron", "buttons", "neckerchief"]},
	"detective": {"outfit": Color(0.8, 0.66, 0.45), "outfit2": Color(0.5, 0.36, 0.24), "pants": Color(0.35, 0.3, 0.28), "shoes": Color(0.3, 0.2, 0.15),
		"hat": "deerstalker", "weapon": "magnifier", "offhand": "none", "extras": ["coat", "belt", "buttons"]},
	"monk": {"outfit": Color(0.98, 0.6, 0.2), "outfit2": Color(0.75, 0.3, 0.2), "pants": Color(0.9, 0.5, 0.18), "shoes": Color(0.55, 0.4, 0.28),
		"hat": "none", "weapon": "spear", "offhand": "none", "hair_style": "bald", "extras": ["robe", "sash", "beads"]},
	"ninja": {"outfit": Color(0.17, 0.18, 0.26), "outfit2": Color(0.86, 0.22, 0.27), "pants": Color(0.15, 0.16, 0.22), "shoes": Color(0.12, 0.12, 0.16),
		"hat": "ninja", "weapon": "katana", "offhand": "none", "extras": ["sash", "boots", "gauntlets"]},
	"king": {"outfit": Color(0.82, 0.16, 0.22), "outfit2": WHITE, "pants": Color(0.55, 0.12, 0.2), "shoes": Color(0.3, 0.18, 0.14),
		"hat": "crown", "weapon": "sceptre", "offhand": "none", "cape": Color(0.82, 0.16, 0.22), "beard": "short",
		"extras": ["robe", "cape", "fur", "belt"]},
	"queen": {"outfit": Color(0.62, 0.3, 0.75), "outfit2": GOLD, "pants": Color(0.5, 0.22, 0.6), "shoes": Color(0.6, 0.4, 0.5),
		"hat": "crown", "weapon": "sceptre", "offhand": "none", "hair_style": "long", "cape": Color(0.45, 0.2, 0.6),
		"extras": ["robe", "cape", "fur", "trim"]},
	"princess": {"outfit": Color(1.0, 0.62, 0.78), "outfit2": Color(1.0, 0.9, 0.95), "pants": Color(0.95, 0.55, 0.7), "shoes": Color(0.95, 0.5, 0.65),
		"hat": "tiara", "weapon": "wand", "offhand": "none", "hair_style": "long", "extras": ["robe", "trim", "puff_sleeves"]},
	"villager": {"outfit": Color(0.45, 0.65, 0.9), "outfit2": Color(0.6, 0.42, 0.26), "pants": Color(0.55, 0.4, 0.28), "shoes": Color(0.4, 0.28, 0.2),
		"hat": "none", "weapon": "none", "offhand": "none", "extras": ["belt", "short_sleeves"]},
	"scientist": {"outfit": WHITE, "outfit2": Color(0.35, 0.65, 0.95), "pants": Color(0.3, 0.32, 0.4), "shoes": Color(0.25, 0.25, 0.3),
		"hat": "goggles", "weapon": "flask", "offhand": "none", "extras": ["coat", "buttons", "pocket"]},
	"farmer": {"outfit": Color(0.9, 0.35, 0.3), "outfit2": Color(0.3, 0.45, 0.75), "pants": Color(0.3, 0.45, 0.75), "shoes": Color(0.4, 0.28, 0.2),
		"hat": "straw", "weapon": "pitchfork", "offhand": "none", "extras": ["overalls", "boots", "short_sleeves"]},
	"viking": {"outfit": Color(0.55, 0.4, 0.3), "outfit2": Color(0.8, 0.72, 0.6), "pants": Color(0.4, 0.42, 0.5), "shoes": Color(0.35, 0.25, 0.18),
		"hat": "viking", "weapon": "axe", "offhand": "round_shield", "beard": "long", "hair_style": "long",
		"extras": ["fur", "belt", "boots", "gauntlets"]},
	"crew": {"outfit": Color(0.95, 0.75, 0.25), "outfit2": Color(0.15, 0.15, 0.2), "pants": Color(0.15, 0.15, 0.2), "shoes": Color(0.1, 0.1, 0.12),
		"hat": "none", "weapon": "tablet", "offhand": "none", "extras": ["collar", "badge", "boots"]},
	"pilot": {"outfit": Color(0.45, 0.55, 0.4), "outfit2": Color(0.95, 0.55, 0.2), "pants": Color(0.4, 0.5, 0.36), "shoes": Color(0.2, 0.2, 0.22),
		"hat": "pilot_helmet", "weapon": "none", "offhand": "none", "extras": ["harness", "boots", "gauntlets", "badge"]},
	"golfer": {"outfit": Color(0.5, 0.82, 0.95), "outfit2": WHITE, "pants": Color(0.95, 0.92, 0.82), "shoes": WHITE,
		"hat": "cap", "weapon": "golf_club", "offhand": "none", "extras": ["polo", "belt", "short_sleeves"]},
	"host": {"outfit": Color(0.3, 0.22, 0.55), "outfit2": Color(0.95, 0.2, 0.35), "pants": Color(0.22, 0.17, 0.4), "shoes": Color(0.12, 0.1, 0.12),
		"hat": "none", "weapon": "microphone", "offhand": "none", "extras": ["suit", "bow_tie"]},
	"athlete": {"outfit": Color(1.0, 0.45, 0.3), "outfit2": WHITE, "pants": Color(0.2, 0.25, 0.45), "shoes": Color(0.95, 0.95, 0.95),
		"hat": "headband", "weapon": "none", "offhand": "none", "extras": ["side_stripes", "short_sleeves", "number"]},
}

# Biped layout (model space, scale 1): pivots and the head centre relative to the neck pivot.
const NECK := Vector3(0.0, 0.6, 0.0)
const HC := Vector3(0.0, 0.24, 0.0)
const SHOULDER := Vector3(0.215, 0.555, 0.0)
const HIP := Vector3(0.09, 0.28, 0.0)
const HAND := Vector3(0.032, -0.25, 0.0)
## Hats that hide the hair completely, and hats that flatten spiky/curly/bun/mohawk styles.
const HIDES_HAIR: Array[String] = ["ninja", "pilot_helmet"]
const COVERS_TOP: Array[String] = ["helmet", "wizard", "hood", "tricorn", "beret", "chef", "fedora", "deerstalker", "cap",
	"straw", "bandana", "beanie", "viking", "top_hat", "feather_cap", "hard_hat", "crown", "party", "space_helmet"]


# --- Public API -------------------------------------------------------------------------------------

## A chibi humanoid (Node3D, origin at the feet, facing +Z) with an "Anim" child. opts (all optional):
## class (CLASSES), skin, hair (Color), hair_style (HAIR_STYLES), eye_color, outfit, outfit2, pants,
## shoes, cape (Color), hat (HATS, "" = class default), weapon / offhand (ITEMS, right / left hand),
## beard (BEARDS), ears ("round" / "pointy"), seed (random skin/hair for unset keys), scale,
## lod ("near" / "far" / "auto"), lod_distance (m, default 14).
static func humanoid(opts: Dictionary = {}) -> Node3D:
	var o := resolve_humanoid(opts)
	var spec := _cached_spec("human", o)
	return _assemble(spec, "humanoid", o)


## Fill in every humanoid option (class defaults, random skin/hair from the seed). Handy for saving a look.
static func resolve_humanoid(opts: Dictionary) -> Dictionary:
	var cls: String = str(opts.get("class", "villager"))
	if not LOOKS.has(cls):
		push_warning("Creatures: unknown class '%s'" % cls)
		cls = "villager"
	var look: Dictionary = LOOKS[cls]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", hash(cls)))
	var o := {}
	o["class"] = cls
	o["body"] = str(opts.get("body", "human"))
	o["skin"] = opts.get("skin", SKIN_TONES[rng.randi() % SKIN_TONES.size()])
	o["hair"] = opts.get("hair", HAIR_COLORS[rng.randi() % 5])
	var styles: Array[String] = ["short", "long", "spiky", "bob", "ponytail", "bun", "curly", "pigtails"]
	o["hair_style"] = str(opts.get("hair_style", look.get("hair_style", styles[rng.randi() % styles.size()])))
	o["eye_color"] = opts.get("eye_color", EYE)
	for k in ["outfit", "outfit2", "pants", "shoes"]:
		o[k] = opts.get(k, look[k])
	o["cape"] = opts.get("cape", look.get("cape", look["outfit2"]))
	var hat: String = str(opts.get("hat", ""))
	o["hat"] = hat if hat != "" else str(look["hat"])
	var weapon: String = str(opts.get("weapon", ""))
	o["weapon"] = weapon if weapon != "" else str(look["weapon"])
	var offhand: String = str(opts.get("offhand", ""))
	o["offhand"] = offhand if offhand != "" else str(look["offhand"])
	o["beard"] = str(opts.get("beard", look.get("beard", "none")))
	o["ears"] = str(opts.get("ears", "round"))
	var extras: Array = look["extras"]
	o["extras"] = opts.get("extras", extras.duplicate())
	o["scale"] = float(opts.get("scale", 1.0))
	o["lod"] = str(opts.get("lod", "near"))
	o["lod_distance"] = float(opts.get("lod_distance", 14.0))
	return o


## Random but tasteful humanoid options for `seed` (class, colours, hair); override any key after.
static func random_humanoid_opts(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cls: String = CLASSES[rng.randi() % CLASSES.size()]
	var o := {"class": cls, "seed": seed_value}
	o["skin"] = SKIN_TONES[rng.randi() % SKIN_TONES.size()]
	o["hair"] = HAIR_COLORS[rng.randi() % HAIR_COLORS.size()]
	if cls == "villager" or cls == "athlete" or cls == "golfer":
		o["outfit"] = OUTFIT_COLORS[rng.randi() % OUTFIT_COLORS.size()]
	return o


## A monster or animal (Node3D, origin at the feet/bottom, facing +Z) with an "Anim" child.
## kind: see MONSTERS. opts: color, color2, eye_color, scale, boss (bigger, spikier, glowing eyes),
## lod ("near" / "far" / "auto"), lod_distance, weapon (goblin/skeleton), seed.
static func monster(kind: String, opts: Dictionary = {}) -> Node3D:
	if not MONSTER_INFO.has(kind):
		push_warning("Creatures: unknown monster '%s'" % kind)
		kind = "slime"
	var o := opts.duplicate()
	o["kind"] = kind
	o["scale"] = float(opts.get("scale", 1.0))
	o["lod"] = str(opts.get("lod", "near"))
	o["lod_distance"] = float(opts.get("lod_distance", 14.0))
	o["boss"] = bool(opts.get("boss", false))
	if kind == "goblin" or kind == "skeleton":
		var h := {"class": "villager", "seed": int(opts.get("seed", 3))}
		if kind == "goblin":
			h["body"] = "goblin"
			h["skin"] = opts.get("color", Color(0.5, 0.78, 0.35))
			h["ears"] = "pointy"
			h["hair_style"] = "mohawk" if bool(o.boss) else "bald"
			h["hair"] = Color(0.3, 0.2, 0.15)
			h["outfit"] = opts.get("color2", Color(0.58, 0.42, 0.28))
			h["outfit2"] = Color(0.45, 0.32, 0.22)
			h["pants"] = Color(0.45, 0.32, 0.22)
			h["shoes"] = Color(0.35, 0.25, 0.18)
			h["weapon"] = str(opts.get("weapon", "club"))
			h["offhand"] = str(opts.get("offhand", "none"))
			h["hat"] = "crown" if bool(o.boss) else "none"
			h["extras"] = ["rags", "belt"]
		else:
			h["body"] = "skeleton"
			h["skin"] = opts.get("color", Color(0.95, 0.93, 0.86))
			h["hair_style"] = "bald"
			h["outfit"] = h["skin"]
			h["outfit2"] = Color(0.5, 0.45, 0.4)
			h["pants"] = h["skin"]
			h["shoes"] = h["skin"]
			h["weapon"] = str(opts.get("weapon", "sword"))
			h["offhand"] = str(opts.get("offhand", "round_shield" if bool(o.boss) else "none"))
			h["hat"] = "helmet" if bool(o.boss) else "none"
			h["extras"] = []
		h["eye_color"] = opts.get("eye_color", EYE if kind == "goblin" else Color(1.0, 0.35, 0.25))
		h["scale"] = float(o.scale) * (0.85 if kind == "goblin" else 1.0) * (1.4 if bool(o.boss) else 1.0)
		h["lod"] = o.lod
		h["lod_distance"] = o.lod_distance
		var ho := resolve_humanoid(h)
		ho["kind"] = kind
		var hs := _cached_spec("human", ho)
		return _assemble(hs, kind, ho)
	if bool(o.boss):
		o["scale"] = float(o.scale) * (3.0 if kind == "dragon" else 1.8)
	var spec := _cached_spec(kind, o)
	return _assemble(spec, kind, o)


## A crowd (audience, spectators, villagers far away) as MultiMeshes of far-LOD meshes: `looks`
## random humanoid looks (or colour variants of a monster `kind`), so the whole crowd costs `looks`
## draw calls. transforms: Array of Transform3D (feet positions, facing +Z). Set crowd.cheer (0-1)
## to make them bounce; crowd.animate = false freezes them (no per-frame cost).
static func crowd(transforms: Array, looks: int = 4, seed_value: int = 1, kind: String = "humanoid") -> Crowd:
	var c := Crowd.new()
	c.name = "Crowd"
	looks = clampi(looks, 1, 16)
	var groups: Array = []
	for l in looks:
		groups.append([])
	for i in transforms.size():
		var g: Array = groups[i % looks]
		g.append(transforms[i])
	for l in looks:
		var mesh: Mesh
		if kind == "humanoid":
			var o := resolve_humanoid(random_humanoid_opts(seed_value * 101 + l * 7))
			mesh = _cached_spec("human", o).far
		else:
			var mo := {"kind": kind, "lod": "far", "scale": 1.0, "boss": false}
			if l > 0:
				mo["color"] = OUTFIT_COLORS[(seed_value + l) % OUTFIT_COLORS.size()]
			mesh = _cached_spec(kind if MONSTER_INFO.has(kind) and kind != "goblin" and kind != "skeleton" else "slime", mo).far
		var xfs: Array = groups[l]
		if xfs.is_empty():
			continue
		var mmi := MeshKit.scatter(mesh, xfs, PackedColorArray(), PackedColorArray(), false)
		c.add_child(mmi)
		c.add_group(mmi.multimesh, xfs)
	return c


## The names monster() understands.
static func list_kinds() -> Array[String]:
	return MONSTERS.duplicate()


## The animation helper of a creature made here (null for other nodes).
static func anim(creature: Node) -> Anim:
	if creature == null:
		return null
	return creature.get_node_or_null("Anim") as Anim


## Height in metres of a creature made here (including its scale), e.g. to place a name tag above it.
static func height_of(creature: Node) -> float:
	if creature == null:
		return 1.0
	return float(creature.get_meta("creature_height", 1.0))


## Turn a creature (or any Node3D) to face `dir` on the ground plane immediately (front = +Z).
static func face_now(node: Node3D, dir: Vector3) -> void:
	if node != null and Vector2(dir.x, dir.z).length() > 0.0001:
		node.rotation.y = atan2(dir.x, dir.z)


# --- Spec / assembly ----------------------------------------------------------------------------------

class Spec extends Resource:
	## Cached description of a creature: its meshes and where the animated parts pivot.
	var rig := "biped"
	var height := 1.0
	var meshes := {}       # part name -> Mesh ("Torso" sits directly under Model)
	var pivots := {}       # part name -> [Vector3 pivot, Vector3 rest rotation, String parent part ("" = Model)]
	var extras := {}       # extra mesh name -> parent part name; not merged into the far LOD
	var hidden := {}       # extra mesh names hidden at start ("Blink")
	var transparent := false
	var far: Mesh


static func _cached_spec(kind: String, o: Dictionary) -> Spec:
	var keys: Array = o.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		if k in ["lod", "lod_distance", "scale", "seed"]:
			continue
		parts.append("%s=%s" % [k, str(o[k])])
	var key := "cr_%s_%s_%d" % [VERSION, kind, hash(",".join(parts))]
	var cached := ResCache.fetch(key) as Spec
	if cached != null:
		return cached
	var spec: Spec
	if kind == "human":
		spec = _human_spec(o)
	else:
		spec = _monster_spec(kind, o)
	spec.far = _merge_far(spec)
	ResCache.put(key, spec)
	return spec


static func _merge_far(spec: Spec) -> Mesh:
	var b := MeshKit.Builder.new()
	if spec.meshes.has("Torso"):
		b.add_mesh(spec.meshes["Torso"])
	for part in spec.pivots:
		if not spec.meshes.has(part):
			continue
		b.add_mesh(spec.meshes[part], _part_xf(spec, str(part)))
	var mat: Material = MeshKit.vertex_material(false, true) if spec.transparent else null
	return b.build(mat)


static func _part_xf(spec: Spec, part: String) -> Transform3D:
	var p: Array = spec.pivots[part]
	var pos: Vector3 = p[0]
	var rest: Vector3 = p[1]
	var parent: String = p[2]
	var xf := Transform3D(Basis.from_euler(rest), pos)
	if parent != "" and spec.pivots.has(parent):
		return _part_xf(spec, parent) * xf
	return xf


static func _assemble(spec: Spec, kind: String, o: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = kind.capitalize().replace(" ", "")
	var model := Node3D.new()
	model.name = "Model"
	var s: float = o.get("scale", 1.0)
	model.scale = Vector3.ONE * s
	root.add_child(model)
	var lod: String = o.get("lod", "near")
	var dist: float = o.get("lod_distance", 14.0)
	var shadows := true
	if lod != "far":
		if spec.meshes.has("Torso"):
			var torso := MeshKit.instance(spec.meshes["Torso"], shadows)
			torso.name = "Torso"
			model.add_child(torso)
			if lod == "auto":
				torso.visibility_range_end = dist
		var nodes := {}
		var order: Array = []
		for part in spec.pivots:  # parents (attached to Model) first
			var pp: Array = spec.pivots[part]
			if str(pp[2]) == "":
				order.append(part)
		for part in spec.pivots:
			var pp2: Array = spec.pivots[part]
			if str(pp2[2]) != "":
				order.append(part)
		for part in order:
			var p: Array = spec.pivots[part]
			var pivot := Node3D.new()
			pivot.name = str(part)
			pivot.position = p[0]
			pivot.rotation = p[1]
			pivot.set_meta("rest", p[1])
			var parent_name: String = p[2]
			var parent: Node3D = nodes.get(parent_name, model) if parent_name != "" else model
			parent.add_child(pivot)
			nodes[str(part)] = pivot
			if spec.meshes.has(part):
				var mi := MeshKit.instance(spec.meshes[part], shadows)
				mi.name = "Mesh"
				pivot.add_child(mi)
				if lod == "auto":
					mi.visibility_range_end = dist
		for extra in spec.extras:
			var parent_part: String = spec.extras[extra]
			var host: Node3D = nodes.get(parent_part, model) if parent_part != "" else model
			var emi := MeshKit.instance(spec.meshes[extra], false)
			emi.name = str(extra)
			emi.visible = not spec.hidden.has(extra)
			host.add_child(emi)
			if lod == "auto":
				emi.visibility_range_end = dist
	if lod == "far" or lod == "auto":
		var far := MeshKit.instance(spec.far, shadows)
		far.name = "Far"
		model.add_child(far)
		if lod == "auto":
			far.visibility_range_begin = dist
	root.set_meta("creature", kind)
	root.set_meta("creature_rig", spec.rig)
	root.set_meta("creature_height", spec.height * s)
	var a := Anim.new()
	a.name = "Anim"
	a.rig = spec.rig
	a.flying = spec.rig == "flyer" and kind != "dragon"
	root.add_child(a)
	return root


static func _new_spec(rig: String, height: float) -> Spec:
	var s := Spec.new()
	s.rig = rig
	s.height = height
	return s


static func _pivot(spec: Spec, part: String, mesh: Mesh, pos: Vector3, rest: Vector3 = Vector3.ZERO, parent: String = "") -> void:
	spec.pivots[part] = [pos, rest, parent]
	if mesh != null:
		spec.meshes[part] = mesh


# --- Shared face pieces -------------------------------------------------------------------------------

## Two dot eyes with highlights on a face whose centre/orientation is `xf` (front = +Z of xf).
static func _eyes(b: MeshKit.Builder, xf: Transform3D, spacing: float, size: float, col: Color, glow: bool = false) -> void:
	for sx in [-1.0, 1.0]:
		var x: float = sx * spacing
		_eye(b, xf * MeshKit.at(Vector3(x, 0.0, 0.0)), size, col, glow)


## One dot eye (with a highlight unless it glows) facing +Z of `xf`.
static func _eye(b: MeshKit.Builder, xf: Transform3D, size: float, col: Color, glow: bool) -> void:
	b.ellipsoid(Vector3(size * 0.72, size, size * 0.45), xf, col, 10, glow)
	if not glow:
		b.sphere(size * 0.3, xf * MeshKit.at(Vector3(-size * 0.25, size * 0.38, size * 0.4)), Color(1, 1, 1), 6)


static func _blush(b: MeshKit.Builder, xf: Transform3D, spacing: float, size: float, skin: Color) -> void:
	var pink := skin.lerp(Color(1.0, 0.45, 0.5), 0.45)
	for sx in [-1.0, 1.0]:
		var x: float = sx * spacing
		b.ellipsoid(Vector3(size, size * 0.55, size * 0.3), xf * MeshKit.at(Vector3(x, 0.0, 0.0)), pink, 8)


# --- Humanoid -------------------------------------------------------------------------------------------

static func _human_spec(o: Dictionary) -> Spec:
	var body: String = o.body
	var spec := _new_spec("biped", 1.1)
	var extras: Array = o.extras
	var skin: Color = o.skin
	# Torso
	var bt := MeshKit.Builder.new()
	if body == "skeleton":
		_skeleton_torso(bt, o)
	else:
		_torso(bt, o, extras)
	spec.meshes["Torso"] = bt.build()
	# Head (+ blink lids, + glass bubble)
	var bh := MeshKit.Builder.new()
	_head(bh, o)
	_pivot(spec, "Head", bh.build(), NECK)
	if body != "skeleton":
		var bl := MeshKit.Builder.new()
		for sx in [-1.0, 1.0]:
			var x: float = sx * 0.085
			bl.ellipsoid(Vector3(0.037, 0.05, 0.024), MeshKit.at(HC + Vector3(x, -0.03, 0.228)), skin, 8)
		spec.meshes["Blink"] = bl.build()
		spec.extras["Blink"] = "Head"
		spec.hidden["Blink"] = true
	if str(o.hat) == "space_helmet":
		var bb := MeshKit.Builder.new()
		bb.sphere(0.37, MeshKit.at(HC + Vector3(0, 0.0, 0.0)), Color(0.75, 0.92, 1.0, 0.22), 16)
		bb.sphere(0.06, MeshKit.at(HC + Vector3(-0.17, 0.2, 0.25), Vector3(1, 1.6, 0.4)), Color(1, 1, 1, 0.55), 6)
		spec.meshes["Bubble"] = bb.build(MeshKit.vertex_material(false, true))
		spec.extras["Bubble"] = "Head"
	# Arms (left = +X) and legs
	for side in [1.0, -1.0]:
		var sx: float = side
		var ba := MeshKit.Builder.new()
		_arm(ba, o, sx, extras)
		var item: String = o.offhand if sx > 0.0 else o.weapon
		var rest := Vector3(0.0, 0.0, 0.12 * sx)
		if item != "none":
			_item(ba, item, o, sx)
			rest.x = -0.3
		_pivot(spec, "ArmL" if sx > 0.0 else "ArmR", ba.build(), Vector3(SHOULDER.x * sx, SHOULDER.y, SHOULDER.z), rest)
		var bg := MeshKit.Builder.new()
		_leg(bg, o, sx, extras)
		_pivot(spec, "LegL" if sx > 0.0 else "LegR", bg.build(), Vector3(HIP.x * sx, HIP.y, HIP.z))
	return spec


static func _torso(b: MeshKit.Builder, o: Dictionary, extras: Array) -> void:
	var skin: Color = o.skin
	var outfit: Color = o.outfit
	var outfit2: Color = o.outfit2
	var pants: Color = o.pants
	var goblin: bool = str(o.body) == "goblin"
	b.cylinder(0.065, 0.07, 0.1, MeshKit.at(NECK), skin, 8)
	if goblin:
		b.rounded_box(Vector3(0.36, 0.34, 0.27), 0.12, MeshKit.at(Vector3(0, 0.43, 0.01)), skin, 2)
	else:
		b.rounded_box(Vector3(0.34, 0.32, 0.25), 0.1, MeshKit.at(Vector3(0, 0.44, 0)), outfit, 2)
	b.rounded_box(Vector3(0.31, 0.12, 0.23), 0.05, MeshKit.at(Vector3(0, 0.3, 0)), pants, 1)
	for e in extras:
		match str(e):
			"belt":
				b.rounded_box(Vector3(0.35, 0.05, 0.26), 0.025, MeshKit.at(Vector3(0, 0.31, 0)), Color(0.42, 0.28, 0.18), 1)
				b.box(Vector3(0.06, 0.05, 0.02), MeshKit.at(Vector3(0, 0.31, 0.13)), GOLD)
			"cape":
				var cape: Color = o.cape
				b.rounded_box(Vector3(0.36, 0.5, 0.03), 0.015, MeshKit.at(Vector3(0, 0.36, -0.15), Vector3.ONE, Vector3(-0.12, 0, 0)), cape, 1)
				b.torus(0.12, 0.03, MeshKit.at(Vector3(0, 0.6, -0.01), Vector3(1, 1, 0.8)), cape.darkened(0.1), 12, 5)
			"tabard":
				b.box(Vector3(0.17, 0.3, 0.02), MeshKit.at(Vector3(0, 0.43, 0.126)), outfit2)
				b.prism(4, 0.04, 0.02, MeshKit.at(Vector3(0, 0.47, 0.138), Vector3(1, 1, 1), Vector3(PI * 0.5, 0, 0)), GOLD)
			"robe":
				b.cylinder(0.175, 0.25, 0.27, MeshKit.at(Vector3(0, 0.2, 0)), outfit, 14)
				b.torus(0.245, 0.02, MeshKit.at(Vector3(0, 0.075, 0)), outfit2, 14, 4)
			"coat":
				b.cylinder(0.18, 0.22, 0.17, MeshKit.at(Vector3(0, 0.24, 0)), outfit, 12)
				b.wedge(Vector3(0.1, 0.12, 0.03), MeshKit.at(Vector3(0.06, 0.53, 0.12), Vector3.ONE, Vector3(0, 0, 0.5)), outfit.darkened(0.12))
				b.wedge(Vector3(0.1, 0.12, 0.03), MeshKit.at(Vector3(-0.06, 0.53, 0.12), Vector3.ONE, Vector3(0, 0, -0.5)), outfit.darkened(0.12))
			"sash":
				b.box(Vector3(0.06, 0.4, 0.27), MeshKit.at(Vector3(0, 0.43, 0), Vector3.ONE, Vector3(0, 0, 0.75)), outfit2)
			"trim":
				b.box(Vector3(0.05, 0.3, 0.02), MeshKit.at(Vector3(0, 0.43, 0.126)), outfit2)
				b.torus(0.13, 0.02, MeshKit.at(Vector3(0, 0.59, 0.0), Vector3(1, 1, 0.85)), outfit2, 12, 4)
			"pauldrons":
				pass  # on the arms
			"scarf":
				b.torus(0.1, 0.045, MeshKit.at(Vector3(0, 0.6, 0.0)), outfit2, 12, 6)
				b.ellipsoid(Vector3(0.04, 0.1, 0.02), MeshKit.at(Vector3(0.07, 0.5, 0.13), Vector3.ONE, Vector3(0, 0, 0.3)), outfit2)
			"quiver":
				b.cylinder(0.055, 0.05, 0.36, MeshKit.at(Vector3(0.09, 0.5, -0.17), Vector3.ONE, Vector3(0, 0, -0.35)), Color(0.55, 0.35, 0.22), 8)
				for k in 3:
					b.cone(0.025, 0.07, MeshKit.at(Vector3(0.16 + k * 0.025, 0.7 - k * 0.01, -0.17 + (k - 1) * 0.025)), Color(0.95, 0.95, 0.9), 4)
				b.box(Vector3(0.04, 0.48, 0.27), MeshKit.at(Vector3(0, 0.44, 0), Vector3.ONE, Vector3(0, 0, -0.75)), Color(0.45, 0.3, 0.2))
			"stripes":
				for k in 3:
					b.rounded_box(Vector3(0.345, 0.035, 0.255), 0.03, MeshKit.at(Vector3(0, 0.37 + k * 0.07, 0)), outfit2, 1)
			"eyepatch":
				pass  # on the head
			"backpack":
				b.rounded_box(Vector3(0.28, 0.3, 0.12), 0.04, MeshKit.at(Vector3(0, 0.46, -0.17)), outfit.darkened(0.1), 1)
				b.cylinder(0.04, 0.04, 0.26, MeshKit.at(Vector3(0.09, 0.47, -0.24)), outfit2, 8)
				b.cylinder(0.04, 0.04, 0.26, MeshKit.at(Vector3(-0.09, 0.47, -0.24)), outfit2, 8)
			"chest_panel":
				b.rounded_box(Vector3(0.14, 0.09, 0.03), 0.015, MeshKit.at(Vector3(0, 0.47, 0.125)), Color(0.35, 0.4, 0.5), 1)
				b.sphere(0.014, MeshKit.at(Vector3(-0.035, 0.47, 0.142)), Color(0.4, 1.0, 0.5), 6)
				b.sphere(0.014, MeshKit.at(Vector3(0.0, 0.47, 0.142)), Color(1.0, 0.4, 0.35), 6)
				b.sphere(0.014, MeshKit.at(Vector3(0.035, 0.47, 0.142)), Color(0.4, 0.7, 1.0), 6)
			"apron":
				b.rounded_box(Vector3(0.26, 0.3, 0.02), 0.02, MeshKit.at(Vector3(0, 0.36, 0.128)), WHITE.darkened(0.04), 1)
			"buttons":
				for k in 3:
					b.sphere(0.014, MeshKit.at(Vector3(0, 0.38 + k * 0.06, 0.128)), outfit2 if str(o["class"]) != "chef" else Color(0.3, 0.3, 0.35), 6)
			"neckerchief":
				b.torus(0.085, 0.03, MeshKit.at(Vector3(0, 0.59, 0)), outfit2, 10, 5)
				b.cone(0.05, 0.08, MeshKit.at(Vector3(0, 0.55, 0.1), Vector3.ONE, Vector3(PI, 0, 0)), outfit2, 6)
			"beads":
				b.torus(0.15, 0.022, MeshKit.at(Vector3(0, 0.55, 0.03), Vector3(1, 1, 0.9), Vector3(-0.45, 0, 0)), Color(0.55, 0.3, 0.2), 14, 4)
			"fur":
				b.torus(0.13, 0.05, MeshKit.at(Vector3(0, 0.59, 0)), outfit2, 12, 6)
				if extras.has("robe"):
					b.torus(0.25, 0.035, MeshKit.at(Vector3(0, 0.08, 0)), outfit2, 14, 5)
			"overalls":
				b.box(Vector3(0.2, 0.17, 0.02), MeshKit.at(Vector3(0, 0.43, 0.126)), outfit2)
				b.box(Vector3(0.04, 0.2, 0.27), MeshKit.at(Vector3(0.08, 0.49, 0)), outfit2)
				b.box(Vector3(0.04, 0.2, 0.27), MeshKit.at(Vector3(-0.08, 0.49, 0)), outfit2)
				b.cylinder(0.16, 0.16, 0.12, MeshKit.at(Vector3(0, 0.33, 0)), outfit2, 12)
			"collar":
				b.torus(0.09, 0.03, MeshKit.at(Vector3(0, 0.6, 0)), outfit2, 10, 5)
				b.rounded_box(Vector3(0.35, 0.1, 0.26), 0.05, MeshKit.at(Vector3(0, 0.56, 0)), outfit2, 1)
			"badge":
				b.prism(3, 0.035, 0.015, MeshKit.at(Vector3(0.08, 0.5, 0.128), Vector3.ONE, Vector3(PI * 0.5, 0, PI * 0.5)), GOLD)
			"harness":
				b.box(Vector3(0.035, 0.34, 0.27), MeshKit.at(Vector3(0.07, 0.44, 0)), Color(0.25, 0.25, 0.28))
				b.box(Vector3(0.035, 0.34, 0.27), MeshKit.at(Vector3(-0.07, 0.44, 0)), Color(0.25, 0.25, 0.28))
			"polo":
				b.wedge(Vector3(0.07, 0.05, 0.03), MeshKit.at(Vector3(0.045, 0.585, 0.11), Vector3.ONE, Vector3(0, 0, 0.6)), outfit2)
				b.wedge(Vector3(0.07, 0.05, 0.03), MeshKit.at(Vector3(-0.045, 0.585, 0.11), Vector3.ONE, Vector3(0, 0, -0.6)), outfit2)
				b.sphere(0.012, MeshKit.at(Vector3(0, 0.54, 0.126)), outfit2, 6)
			"suit":
				b.box(Vector3(0.1, 0.22, 0.02), MeshKit.at(Vector3(0, 0.48, 0.123)), WHITE)
				b.wedge(Vector3(0.07, 0.2, 0.03), MeshKit.at(Vector3(0.06, 0.48, 0.125), Vector3.ONE, Vector3(0, 0, 0.25)), outfit.darkened(0.2))
				b.wedge(Vector3(0.07, 0.2, 0.03), MeshKit.at(Vector3(-0.06, 0.48, 0.125), Vector3.ONE, Vector3(0, 0, -0.25)), outfit.darkened(0.2))
				b.sphere(0.013, MeshKit.at(Vector3(0, 0.36, 0.128)), GOLD, 6)
			"bow_tie":
				b.cone(0.035, 0.06, MeshKit.at(Vector3(0.03, 0.57, 0.13), Vector3.ONE, Vector3(0, 0, PI * 0.5)), outfit2, 6)
				b.cone(0.035, 0.06, MeshKit.at(Vector3(-0.03, 0.57, 0.13), Vector3.ONE, Vector3(0, 0, -PI * 0.5)), outfit2, 6)
				b.sphere(0.018, MeshKit.at(Vector3(0, 0.57, 0.135)), outfit2.darkened(0.15), 6)
			"side_stripes":
				b.box(Vector3(0.02, 0.3, 0.12), MeshKit.at(Vector3(0.172, 0.44, 0)), outfit2)
				b.box(Vector3(0.02, 0.3, 0.12), MeshKit.at(Vector3(-0.172, 0.44, 0)), outfit2)
			"number":
				b.rounded_box(Vector3(0.12, 0.1, 0.015), 0.01, MeshKit.at(Vector3(0, 0.46, 0.126)), outfit2, 1)
			"pocket":
				b.box(Vector3(0.06, 0.05, 0.015), MeshKit.at(Vector3(0.08, 0.5, 0.127)), outfit.darkened(0.08))
				b.box(Vector3(0.012, 0.06, 0.012), MeshKit.at(Vector3(0.09, 0.53, 0.13)), Color(0.3, 0.5, 0.95))
			"rags":
				b.cylinder(0.17, 0.21, 0.13, MeshKit.at(Vector3(0, 0.26, 0)), outfit, 7)
				b.box(Vector3(0.05, 0.36, 0.28), MeshKit.at(Vector3(0, 0.44, 0), Vector3.ONE, Vector3(0, 0, -0.7)), outfit)
			_:
				pass


static func _skeleton_torso(b: MeshKit.Builder, o: Dictionary) -> void:
	var bone: Color = o.skin
	b.cylinder(0.035, 0.035, 0.42, MeshKit.at(Vector3(0, 0.42, -0.04)), bone, 6)
	for k in 3:
		b.torus(0.11 - k * 0.012, 0.018, MeshKit.at(Vector3(0, 0.52 - k * 0.07, 0.0), Vector3(1.1, 1, 0.8)), bone, 12, 4)
	b.rounded_box(Vector3(0.24, 0.08, 0.14), 0.035, MeshKit.at(Vector3(0, 0.29, 0)), bone, 1)
	b.capsule_between(Vector3(-0.2, 0.57, 0), Vector3(0.2, 0.57, 0), 0.03, bone, 6)
	b.cylinder(0.04, 0.04, 0.1, MeshKit.at(NECK), bone, 6)


static func _head(b: MeshKit.Builder, o: Dictionary) -> void:
	var skin: Color = o.skin
	var hair: Color = o.hair
	var hat: String = o.hat
	var style: String = o.hair_style
	var body: String = o.body
	var eye: Color = o.eye_color
	var face := MeshKit.at(HC + Vector3(0, -0.03, 0.226))
	if body == "skeleton":
		b.ellipsoid(Vector3(0.24, 0.22, 0.23), MeshKit.at(HC + Vector3(0, 0.02, 0)), skin, 14)
		b.rounded_box(Vector3(0.22, 0.1, 0.18), 0.05, MeshKit.at(HC + Vector3(0, -0.15, 0.04)), skin, 1)
		for sx in [-1.0, 1.0]:
			var x: float = sx * 0.085
			b.ellipsoid(Vector3(0.06, 0.065, 0.03), MeshKit.at(HC + Vector3(x, -0.02, 0.2)), Color(0.1, 0.08, 0.12), 8)
			b.sphere(0.022, MeshKit.at(HC + Vector3(x, -0.02, 0.222)), eye, 6, true)
		b.prism(3, 0.03, 0.02, MeshKit.at(HC + Vector3(0, -0.09, 0.225), Vector3.ONE, Vector3(PI * 0.5, 0, -PI * 0.5)), Color(0.15, 0.12, 0.15))
		for k in 4:
			b.box(Vector3(0.025, 0.035, 0.02), MeshKit.at(HC + Vector3(-0.045 + k * 0.03, -0.14, 0.13)), skin.lightened(0.1))
	else:
		b.ellipsoid(Vector3(0.26, 0.24, 0.25), MeshKit.at(HC), skin, 16)
		_eyes(b, face, 0.085, 0.045, eye)
		_blush(b, MeshKit.at(HC + Vector3(0, -0.08, 0.182)), 0.15, 0.04, skin)
		b.sphere(0.018, MeshKit.at(HC + Vector3(0, -0.065, 0.236)), skin.darkened(0.08), 6)
		if str(o.beard) == "none":
			b.ellipsoid(Vector3(0.026, 0.011, 0.01), MeshKit.at(HC + Vector3(0, -0.112, 0.216)), Color(0.5, 0.22, 0.24), 6)
		# Ears
		if str(o.ears) == "pointy":
			for sx in [-1.0, 1.0]:
				var x: float = sx
				b.cone(0.055, 0.2, MeshKit.aim(HC + Vector3(x * 0.3, -0.0, -0.02), Vector3(x, 0.55, -0.15)), skin, 8)
		else:
			for sx in [-1.0, 1.0]:
				var x: float = sx
				b.ellipsoid(Vector3(0.03, 0.05, 0.04), MeshKit.at(HC + Vector3(x * 0.255, -0.04, 0.0)), skin, 8)
		if body == "goblin":
			b.sphere(0.035, MeshKit.at(HC + Vector3(0, -0.06, 0.25), Vector3(1.2, 1, 1)), skin.darkened(0.12), 6)
			b.cone(0.015, 0.04, MeshKit.at(HC + Vector3(0.04, -0.13, 0.215), Vector3.ONE, Vector3(0, 0, 0)), WHITE, 4)
			b.cone(0.015, 0.04, MeshKit.at(HC + Vector3(-0.04, -0.13, 0.215), Vector3.ONE, Vector3(0, 0, 0)), WHITE, 4)
		_hair(b, style, hair, hat)
		_beard(b, str(o.beard), hair)
		if (o.extras as Array).has("eyepatch"):
			b.ellipsoid(Vector3(0.05, 0.055, 0.02), MeshKit.at(HC + Vector3(-0.085, -0.03, 0.235)), Color(0.12, 0.1, 0.1), 8)
			b.torus(0.255, 0.008, MeshKit.at(HC + Vector3(0, 0.0, 0.0), Vector3.ONE, Vector3(0.0, 0.0, -0.45)), Color(0.12, 0.1, 0.1), 16, 3)
	_hat(b, hat, o)


static func _hair(b: MeshKit.Builder, style: String, c: Color, hat: String) -> void:
	if hat in HIDES_HAIR:
		return
	if hat in COVERS_TOP:
		match style:
			"spiky", "curly", "bun":
				style = "short"
			"mohawk":
				style = "bald"
	if style == "bald":
		return
	var cap_xf := MeshKit.at(HC + Vector3(0, 0.035, -0.03))
	if style != "mohawk":
		b.ellipsoid(Vector3(0.275, 0.26, 0.27), cap_xf, c, 14)
		if hat == "none" or hat == "headband" or hat == "flower" or hat == "bow" or hat == "halo" or hat == "goggles" or hat == "tiara":
			b.ellipsoid(Vector3(0.09, 0.06, 0.06), MeshKit.at(HC + Vector3(-0.11, 0.125, 0.175), Vector3.ONE, Vector3(0, 0, 0.3)), c, 8)
			b.ellipsoid(Vector3(0.09, 0.06, 0.06), MeshKit.at(HC + Vector3(0.0, 0.145, 0.19)), c, 8)
			b.ellipsoid(Vector3(0.09, 0.06, 0.06), MeshKit.at(HC + Vector3(0.11, 0.125, 0.175), Vector3.ONE, Vector3(0, 0, -0.3)), c, 8)
	match style:
		"long":
			b.ellipsoid(Vector3(0.25, 0.3, 0.13), MeshKit.at(HC + Vector3(0, -0.13, -0.16)), c, 12)
			for sx in [-1.0, 1.0]:
				var x: float = sx
				b.ellipsoid(Vector3(0.065, 0.18, 0.09), MeshKit.at(HC + Vector3(x * 0.225, -0.11, 0.0)), c, 8)
		"spiky":
			var dirs: Array[Vector3] = [Vector3(0, 1, -0.2), Vector3(0.6, 0.8, -0.2), Vector3(-0.6, 0.8, -0.2), Vector3(0.3, 0.6, -0.8),
				Vector3(-0.3, 0.6, -0.8), Vector3(0, 0.3, -1), Vector3(0.35, 0.95, 0.4), Vector3(-0.35, 0.95, 0.4)]
			for d in dirs:
				var dn := d.normalized()
				b.cone(0.085, 0.2, MeshKit.aim(HC + Vector3(0, 0.035, -0.03) + Vector3(dn.x * 0.25, dn.y * 0.24, dn.z * 0.25), dn), c, 6)
		"bob":
			for sx in [-1.0, 1.0]:
				var x: float = sx
				b.ellipsoid(Vector3(0.1, 0.17, 0.17), MeshKit.at(HC + Vector3(x * 0.2, -0.07, -0.03)), c, 10)
			b.ellipsoid(Vector3(0.24, 0.17, 0.13), MeshKit.at(HC + Vector3(0, -0.07, -0.15)), c, 10)
		"ponytail":
			b.sphere(0.05, MeshKit.at(HC + Vector3(0, 0.08, -0.27)), c.darkened(0.2), 8)
			b.ellipsoid(Vector3(0.08, 0.18, 0.08), MeshKit.at(HC + Vector3(0, -0.06, -0.33), Vector3.ONE, Vector3(0.35, 0, 0)), c, 10)
		"bun":
			b.sphere(0.1, MeshKit.at(HC + Vector3(0, 0.27, -0.1)), c, 10)
		"curly":
			for k in 12:
				var a := TAU * k / 12.0
				var y := 0.12 if k % 2 == 0 else 0.0
				b.sphere(0.075, MeshKit.at(HC + Vector3(cos(a) * 0.25, y + 0.05, sin(a) * 0.25 - 0.04)), c.lightened(0.05 * (k % 3)), 8)
			for k in 4:
				var a2 := TAU * k / 4.0
				b.sphere(0.08, MeshKit.at(HC + Vector3(cos(a2) * 0.12, 0.25, sin(a2) * 0.12 - 0.03)), c, 8)
		"mohawk":
			for k in 5:
				b.ellipsoid(Vector3(0.035, 0.08, 0.06), MeshKit.at(HC + Vector3(0, 0.25 - absf(k - 1.5) * 0.02, 0.12 - k * 0.075)), c, 8)
		"pigtails":
			for sx in [-1.0, 1.0]:
				var x: float = sx
				b.sphere(0.04, MeshKit.at(HC + Vector3(x * 0.25, 0.02, -0.08)), c.darkened(0.2), 6)
				b.ellipsoid(Vector3(0.07, 0.15, 0.07), MeshKit.at(HC + Vector3(x * 0.3, -0.1, -0.1), Vector3.ONE, Vector3(0, 0, x * 0.4)), c, 8)
		_:
			pass


static func _beard(b: MeshKit.Builder, beard: String, c: Color) -> void:
	match beard:
		"short":
			b.ellipsoid(Vector3(0.18, 0.11, 0.12), MeshKit.at(HC + Vector3(0, -0.15, 0.12)), c, 12)
			b.ellipsoid(Vector3(0.05, 0.022, 0.02), MeshKit.at(HC + Vector3(0.04, -0.095, 0.225), Vector3.ONE, Vector3(0, 0, -0.3)), c, 6)
			b.ellipsoid(Vector3(0.05, 0.022, 0.02), MeshKit.at(HC + Vector3(-0.04, -0.095, 0.225), Vector3.ONE, Vector3(0, 0, 0.3)), c, 6)
		"long":
			b.ellipsoid(Vector3(0.18, 0.11, 0.12), MeshKit.at(HC + Vector3(0, -0.15, 0.12)), c, 12)
			b.ellipsoid(Vector3(0.15, 0.22, 0.1), MeshKit.at(HC + Vector3(0, -0.27, 0.13)), c, 12)
			b.ellipsoid(Vector3(0.05, 0.022, 0.02), MeshKit.at(HC + Vector3(0.04, -0.095, 0.225), Vector3.ONE, Vector3(0, 0, -0.3)), c, 6)
			b.ellipsoid(Vector3(0.05, 0.022, 0.02), MeshKit.at(HC + Vector3(-0.04, -0.095, 0.225), Vector3.ONE, Vector3(0, 0, 0.3)), c, 6)
		"moustache":
			b.ellipsoid(Vector3(0.06, 0.025, 0.022), MeshKit.at(HC + Vector3(0.045, -0.095, 0.225), Vector3.ONE, Vector3(0, 0, -0.35)), c, 6)
			b.ellipsoid(Vector3(0.06, 0.025, 0.022), MeshKit.at(HC + Vector3(-0.045, -0.095, 0.225), Vector3.ONE, Vector3(0, 0, 0.35)), c, 6)
		_:
			pass


static func _hat(b: MeshKit.Builder, hat: String, o: Dictionary) -> void:
	var outfit: Color = o.outfit
	var outfit2: Color = o.outfit2
	var h := HC
	match hat:
		"helmet":
			b.dome(0.29, MeshKit.at(h + Vector3(0, 0.02, -0.01), Vector3(1, 1.05, 1)), STEEL, 14)
			b.torus(0.288, 0.022, MeshKit.at(h + Vector3(0, 0.02, -0.01)), STEEL.darkened(0.15), 16, 4)
			b.box(Vector3(0.04, 0.08, 0.42), MeshKit.at(h + Vector3(0, 0.29, -0.02)), STEEL.darkened(0.08))
			b.ellipsoid(Vector3(0.05, 0.1, 0.16), MeshKit.at(h + Vector3(0, 0.36, -0.08)), outfit2, 8)
			for sx in [-1.0, 1.0]:
				var x: float = sx
				b.ellipsoid(Vector3(0.05, 0.11, 0.09), MeshKit.at(h + Vector3(x * 0.245, -0.07, 0.04)), STEEL, 8)
		"wizard":
			b.cylinder(0.4, 0.4, 0.025, MeshKit.at(h + Vector3(0, 0.17, 0), Vector3.ONE, Vector3(-0.08, 0, 0.05)), outfit, 18)
			b.cone(0.23, 0.5, MeshKit.at(h + Vector3(0, 0.42, -0.04), Vector3.ONE, Vector3(-0.22, 0, 0.08)), outfit, 14)
			b.cylinder(0.215, 0.235, 0.05, MeshKit.at(h + Vector3(0, 0.2, -0.005), Vector3.ONE, Vector3(-0.08, 0, 0.05)), outfit2, 14, false, false)
			b.star(5, 0.05, 0.022, 0.015, MeshKit.at(h + Vector3(0, 0.35, 0.175), Vector3.ONE, Vector3(-0.3, 0, 0)), outfit2)
		"hood":
			b.ellipsoid(Vector3(0.3, 0.29, 0.29), MeshKit.at(h + Vector3(0, 0.02, -0.07)), outfit, 14)
			b.sphere(0.035, MeshKit.at(h + Vector3(0, -0.2, 0.12)), outfit2, 8)
			b.cone(0.1, 0.18, MeshKit.aim(h + Vector3(0, 0.12, -0.33), Vector3(0, -0.4, -1)), outfit, 8)
		"crown":
			b.cylinder(0.17, 0.16, 0.07, MeshKit.at(h + Vector3(0, 0.25, 0)), GOLD, 14, false, false)
			for k in 6:
				var a := TAU * k / 6.0 + PI * 0.5
				b.cone(0.04, 0.09, MeshKit.at(h + Vector3(cos(a) * 0.165, 0.32, sin(a) * 0.165)), GOLD, 6)
				b.sphere(0.018, MeshKit.at(h + Vector3(cos(a) * 0.165, 0.37, sin(a) * 0.165)), GOLD.lightened(0.3), 5)
			b.sphere(0.03, MeshKit.at(h + Vector3(0, 0.25, 0.17)), Color(0.9, 0.2, 0.3), 8)
		"tiara":
			b.torus(0.22, 0.014, MeshKit.at(h + Vector3(0, 0.15, 0.0), Vector3.ONE, Vector3(0.35, 0, 0)), GOLD, 16, 4)
			for k in 3:
				var x := (k - 1) * 0.07
				b.cone(0.022, 0.06 if k != 1 else 0.09, MeshKit.at(h + Vector3(x, 0.24 - absf(x) * 0.6, 0.15)), GOLD, 5)
			b.sphere(0.022, MeshKit.at(h + Vector3(0, 0.22, 0.17)), Color(0.4, 0.8, 1.0), 6)
		"tricorn":
			b.prism(3, 0.36, 0.05, MeshKit.at(h + Vector3(0, 0.18, 0), Vector3.ONE, Vector3(0, -PI * 0.5, 0)), Color(0.15, 0.13, 0.16))
			b.dome(0.22, MeshKit.at(h + Vector3(0, 0.18, 0), Vector3(1, 0.8, 1)), Color(0.18, 0.16, 0.2), 12)
			b.torus(0.22, 0.015, MeshKit.at(h + Vector3(0, 0.2, 0)), GOLD, 14, 3)
			b.sphere(0.03, MeshKit.at(h + Vector3(0, 0.27, 0.19), Vector3(1, 1, 0.4)), WHITE, 6)
		"beret":
			b.ellipsoid(Vector3(0.28, 0.08, 0.28), MeshKit.at(h + Vector3(0.03, 0.2, -0.02), Vector3.ONE, Vector3(0, 0, -0.22)), Color(0.55, 0.25, 0.6), 14)
			b.sphere(0.025, MeshKit.at(h + Vector3(0.05, 0.28, -0.02)), Color(0.4, 0.15, 0.45), 6)
			b.ellipsoid(Vector3(0.025, 0.14, 0.035), MeshKit.at(h + Vector3(-0.17, 0.3, -0.06), Vector3.ONE, Vector3(-0.3, 0, 0.6)), outfit2, 8)
		"chef":
			b.cylinder(0.235, 0.24, 0.12, MeshKit.at(h + Vector3(0, 0.2, 0)), WHITE, 14)
			for k in 4:
				var a := TAU * k / 4.0 + PI * 0.25
				b.sphere(0.14, MeshKit.at(h + Vector3(cos(a) * 0.12, 0.36, sin(a) * 0.12)), WHITE, 10)
			b.sphere(0.16, MeshKit.at(h + Vector3(0, 0.42, 0)), WHITE, 10)
		"fedora":
			var felt := Color(0.35, 0.3, 0.28)
			b.cylinder(0.35, 0.35, 0.025, MeshKit.at(h + Vector3(0, 0.17, 0), Vector3(1, 1, 1.05)), felt, 16)
			b.cylinder(0.17, 0.2, 0.18, MeshKit.at(h + Vector3(0, 0.27, 0)), felt, 14)
			b.torus(0.2, 0.02, MeshKit.at(h + Vector3(0, 0.2, 0)), Color(0.15, 0.12, 0.12), 14, 4)
		"deerstalker":
			var tw := Color(0.72, 0.6, 0.4)
			b.dome(0.275, MeshKit.at(h + Vector3(0, 0.04, -0.01), Vector3(1, 0.95, 1.05)), tw, 14)
			b.ellipsoid(Vector3(0.14, 0.02, 0.1), MeshKit.at(h + Vector3(0, 0.06, 0.27), Vector3.ONE, Vector3(-0.25, 0, 0)), tw.darkened(0.1), 10)
			b.ellipsoid(Vector3(0.14, 0.02, 0.1), MeshKit.at(h + Vector3(0, 0.06, -0.29), Vector3.ONE, Vector3(0.25, 0, 0)), tw.darkened(0.1), 10)
			b.sphere(0.03, MeshKit.at(h + Vector3(0, 0.3, 0)), tw.darkened(0.2), 6)
			for k in 3:
				b.torus(0.272, 0.006, MeshKit.at(h + Vector3(0, 0.08 + k * 0.06, -0.01), Vector3(1.0 - k * 0.12, 1, 1.05 - k * 0.12)), tw.darkened(0.25), 16, 3)
		"cap":
			b.dome(0.272, MeshKit.at(h + Vector3(0, 0.05, -0.01), Vector3(1, 0.88, 1)), outfit2 if str(o["class"]) != "golfer" else outfit, 14)
			b.ellipsoid(Vector3(0.17, 0.02, 0.15), MeshKit.at(h + Vector3(0, 0.07, 0.27), Vector3.ONE, Vector3(-0.15, 0, 0)), outfit.darkened(0.15), 12)
			b.sphere(0.025, MeshKit.at(h + Vector3(0, 0.29, -0.01)), outfit.darkened(0.15), 6)
		"straw":
			var straw := Color(0.95, 0.82, 0.5)
			b.cylinder(0.44, 0.44, 0.02, MeshKit.at(h + Vector3(0, 0.17, 0)), straw, 18)
			b.dome(0.22, MeshKit.at(h + Vector3(0, 0.17, 0), Vector3(1, 0.75, 1)), straw.darkened(0.05), 12)
			b.torus(0.21, 0.02, MeshKit.at(h + Vector3(0, 0.2, 0)), Color(0.85, 0.3, 0.3), 14, 4)
		"headband":
			b.torus(0.256, 0.025, MeshKit.at(h + Vector3(0, 0.1, 0), Vector3.ONE, Vector3(0.15, 0, 0)), outfit2 if str(o["class"]) != "athlete" else outfit, 18, 5)
			b.ellipsoid(Vector3(0.03, 0.09, 0.02), MeshKit.at(h + Vector3(0.04, 0.0, -0.27), Vector3.ONE, Vector3(0.3, 0, 0.3)), outfit, 6)
		"bandana":
			b.dome(0.276, MeshKit.at(h + Vector3(0, 0.05, -0.02), Vector3(1, 0.9, 1)), outfit2, 14)
			b.sphere(0.05, MeshKit.at(h + Vector3(0, 0.03, -0.29)), outfit2.darkened(0.1), 8)
			b.ellipsoid(Vector3(0.035, 0.1, 0.02), MeshKit.at(h + Vector3(0.04, -0.07, -0.3), Vector3.ONE, Vector3(0.2, 0, 0.3)), outfit2, 6)
			b.ellipsoid(Vector3(0.035, 0.1, 0.02), MeshKit.at(h + Vector3(-0.04, -0.07, -0.3), Vector3.ONE, Vector3(0.2, 0, -0.3)), outfit2, 6)
		"beanie":
			b.dome(0.278, MeshKit.at(h + Vector3(0, 0.06, -0.01), Vector3(1, 1.05, 1)), outfit2, 14)
			b.torus(0.27, 0.035, MeshKit.at(h + Vector3(0, 0.07, -0.01)), outfit2.darkened(0.12), 16, 5)
			b.sphere(0.06, MeshKit.at(h + Vector3(0, 0.36, -0.01)), WHITE, 8)
		"space_helmet":
			b.torus(0.22, 0.05, MeshKit.at(h + Vector3(0, -0.3, 0)), Color(0.85, 0.86, 0.9), 16, 6)
			b.cylinder(0.008, 0.008, 0.14, MeshKit.at(h + Vector3(0.18, 0.36, -0.1)), Color(0.6, 0.6, 0.65), 4)
			b.sphere(0.022, MeshKit.at(h + Vector3(0.18, 0.44, -0.1)), Color(1.0, 0.35, 0.3), 6)
		"viking":
			b.dome(0.285, MeshKit.at(h + Vector3(0, 0.03, -0.01), Vector3(1, 1.02, 1)), STEEL.darkened(0.1), 14)
			b.torus(0.284, 0.025, MeshKit.at(h + Vector3(0, 0.03, -0.01)), Color(0.55, 0.4, 0.25), 16, 4)
			b.box(Vector3(0.035, 0.12, 0.05), MeshKit.at(h + Vector3(0, -0.02, 0.27)), STEEL.darkened(0.2))
			for sx in [-1.0, 1.0]:
				var x: float = sx
				b.cone(0.06, 0.24, MeshKit.aim(h + Vector3(x * 0.32, 0.17, 0), Vector3(x, 1.1, 0.1)), Color(0.96, 0.93, 0.82), 8)
		"top_hat":
			b.cylinder(0.3, 0.3, 0.025, MeshKit.at(h + Vector3(0, 0.18, 0)), Color(0.12, 0.11, 0.13), 16)
			b.cylinder(0.18, 0.17, 0.34, MeshKit.at(h + Vector3(0, 0.36, 0)), Color(0.14, 0.13, 0.15), 14)
			b.cylinder(0.172, 0.172, 0.05, MeshKit.at(h + Vector3(0, 0.23, 0)), outfit2, 14, false, false)
		"party":
			b.cone(0.12, 0.3, MeshKit.at(h + Vector3(0.06, 0.37, 0), Vector3.ONE, Vector3(0, 0, -0.2)), outfit2, 12)
			b.sphere(0.04, MeshKit.at(h + Vector3(0.09, 0.52, 0)), Color(1.0, 0.9, 0.35), 8)
			b.torus(0.105, 0.012, MeshKit.at(h + Vector3(0.05, 0.29, 0), Vector3.ONE, Vector3(0, 0, -0.2)), Color(1.0, 0.9, 0.35), 12, 3)
		"feather_cap":
			b.ellipsoid(Vector3(0.29, 0.13, 0.3), MeshKit.at(h + Vector3(0, 0.15, -0.01)), outfit, 14)
			b.cone(0.11, 0.22, MeshKit.aim(h + Vector3(0, 0.22, -0.3), Vector3(0, 0.5, -1)), outfit, 8)
			b.ellipsoid(Vector3(0.025, 0.17, 0.035), MeshKit.at(h + Vector3(0.2, 0.28, -0.05), Vector3.ONE, Vector3(-0.4, 0, -0.5)), Color(0.9, 0.25, 0.25), 8)
		"ninja":
			var cloth: Color = outfit
			b.ellipsoid(Vector3(0.268, 0.252, 0.262), MeshKit.at(h + Vector3(0, 0.005, -0.012)), cloth, 14)
			b.ellipsoid(Vector3(0.245, 0.1, 0.22), MeshKit.at(h + Vector3(0, -0.17, 0.065)), cloth, 12)
			b.torus(0.262, 0.02, MeshKit.at(h + Vector3(0, 0.09, 0), Vector3.ONE, Vector3(0.12, 0, 0)), outfit2, 16, 4)
			b.ellipsoid(Vector3(0.03, 0.1, 0.02), MeshKit.at(h + Vector3(0.05, 0.0, -0.28), Vector3.ONE, Vector3(0.3, 0, 0.35)), outfit2, 6)
		"goggles":
			b.torus(0.258, 0.016, MeshKit.at(h + Vector3(0, 0.08, 0), Vector3.ONE, Vector3(0.25, 0, 0)), Color(0.3, 0.25, 0.22), 16, 4)
			for sx in [-1.0, 1.0]:
				var x: float = sx * 0.075
				var gxf := MeshKit.at(h + Vector3(x, 0.12, 0.215), Vector3.ONE, Vector3(PI * 0.5 - 0.5, 0, 0))
				b.cylinder(0.055, 0.055, 0.04, gxf, Color(0.35, 0.3, 0.28), 12)
				b.disc(0.042, gxf * MeshKit.at(Vector3(0, 0.021, 0)), Color(0.55, 0.85, 1.0), 12)
		"pilot_helmet":
			b.ellipsoid(Vector3(0.29, 0.275, 0.285), MeshKit.at(h + Vector3(0, 0.03, -0.03)), Color(0.9, 0.9, 0.92), 14)
			b.ellipsoid(Vector3(0.22, 0.09, 0.06), MeshKit.at(h + Vector3(0, 0.15, 0.22), Vector3.ONE, Vector3(-0.5, 0, 0)), Color(0.2, 0.3, 0.45), 12)
			b.box(Vector3(0.05, 0.3, 0.05), MeshKit.at(h + Vector3(0, 0.27, -0.05), Vector3.ONE, Vector3(-0.5, 0, 0)), outfit2)
			for sx in [-1.0, 1.0]:
				var x: float = sx
				b.cylinder(0.07, 0.07, 0.04, MeshKit.at(h + Vector3(x * 0.27, -0.03, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), outfit2, 10)
		"hard_hat":
			var y := Color(1.0, 0.82, 0.2)
			b.dome(0.27, MeshKit.at(h + Vector3(0, 0.07, 0), Vector3(1, 0.85, 1)), y, 14)
			b.cylinder(0.31, 0.31, 0.02, MeshKit.at(h + Vector3(0, 0.08, 0.02), Vector3(1, 1, 1.08)), y.darkened(0.05), 16)
			b.box(Vector3(0.05, 0.05, 0.4), MeshKit.at(h + Vector3(0, 0.3, 0)), y.darkened(0.1))
		"flower":
			var pc := Color(1.0, 0.55, 0.7)
			for k in 5:
				var a := TAU * k / 5.0
				b.ellipsoid(Vector3(0.04, 0.04, 0.015), MeshKit.at(h + Vector3(0.21 + cos(a) * 0.04, 0.13 + sin(a) * 0.04, 0.1), Vector3.ONE, Vector3(0, 0.6, 0)), pc, 6)
			b.sphere(0.022, MeshKit.at(h + Vector3(0.215, 0.13, 0.11)), Color(1.0, 0.85, 0.3), 6)
		"bow":
			var bc := Color(1.0, 0.4, 0.55)
			b.ellipsoid(Vector3(0.07, 0.05, 0.025), MeshKit.at(h + Vector3(0.08, 0.27, 0.06), Vector3.ONE, Vector3(0, 0, 0.3)), bc, 8)
			b.ellipsoid(Vector3(0.07, 0.05, 0.025), MeshKit.at(h + Vector3(0.22, 0.2, 0.06), Vector3.ONE, Vector3(0, 0, 0.3)), bc, 8)
			b.sphere(0.03, MeshKit.at(h + Vector3(0.15, 0.235, 0.07)), bc.darkened(0.15), 6)
		"halo":
			b.torus(0.15, 0.018, MeshKit.at(h + Vector3(0, 0.38, 0)), Color(1.0, 0.92, 0.5), 18, 4, true)
		_:
			pass


static func _arm(b: MeshKit.Builder, o: Dictionary, sx: float, extras: Array) -> void:
	var skin: Color = o.skin
	var sleeve: Color = o.outfit
	var body: String = o.body
	var hand := Vector3(HAND.x * sx, HAND.y, HAND.z)
	if body == "skeleton":
		b.capsule_between(Vector3(0, -0.01, 0), Vector3(sx * 0.025, -0.2, 0), 0.022, skin, 6)
		b.sphere(0.035, MeshKit.at(Vector3.ZERO), skin, 6)
		b.sphere(0.045, MeshKit.at(hand), skin, 8)
		return
	if body == "goblin":
		sleeve = skin
	var glove := skin
	if extras.has("gauntlets"):
		glove = sleeve.darkened(0.15) if str(o["class"]) != "astronaut" else Color(0.75, 0.76, 0.8)
	if extras.has("short_sleeves"):
		b.capsule_between(Vector3(0, -0.01, 0), Vector3(sx * 0.025, -0.19, 0), 0.05, skin, 10)
		b.cylinder(0.065, 0.062, 0.09, MeshKit.at(Vector3(sx * 0.004, -0.035, 0), Vector3.ONE, Vector3(0, 0, 0.12 * sx)), sleeve, 10)
	else:
		b.capsule_between(Vector3(0, -0.01, 0), Vector3(sx * 0.025, -0.19, 0), 0.056, sleeve, 10)
	if extras.has("puff_sleeves"):
		b.sphere(0.08, MeshKit.at(Vector3(sx * 0.01, -0.02, 0)), sleeve.lightened(0.1), 10)
	if extras.has("pauldrons"):
		b.dome(0.088, MeshKit.at(Vector3(sx * 0.012, -0.005, 0), Vector3(1.15, 0.85, 1.1)), STEEL, 10)
	if extras.has("fur") and str(o["class"]) == "viking":
		b.sphere(0.08, MeshKit.at(Vector3(sx * 0.01, -0.01, 0)), Color(0.8, 0.72, 0.6), 8)
	b.sphere(0.062, MeshKit.at(hand), glove, 10)


static func _leg(b: MeshKit.Builder, o: Dictionary, _sx: float, extras: Array) -> void:
	var pants: Color = o.pants
	var shoes: Color = o.shoes
	if str(o.body) == "skeleton":
		var bone: Color = o.skin
		b.capsule_between(Vector3(0, -0.01, 0), Vector3(0, -0.19, 0), 0.025, bone, 6)
		b.ellipsoid(Vector3(0.045, 0.03, 0.08), MeshKit.at(Vector3(0, -0.24, 0.03)), bone, 8)
		return
	if str(o.body) == "goblin":
		pants = o.skin
	b.capsule_between(Vector3(0, -0.02, 0), Vector3(0, -0.17, 0), 0.07, pants, 10)
	if extras.has("boots"):
		b.cylinder(0.077, 0.08, 0.12, MeshKit.at(Vector3(0, -0.175, 0)), shoes, 10)
	b.ellipsoid(Vector3(0.075, 0.06, 0.105), MeshKit.at(Vector3(0, -0.215, 0.03)), shoes, 10)


## A held item in the hand of an arm built in arm-local space (grip at the hand, length along +Y of
## the item, then tilted by its hold style). sx: +1 left arm, -1 right arm.
static func _item(b: MeshKit.Builder, item: String, o: Dictionary, sx: float) -> void:
	var hand := Vector3(HAND.x * sx, HAND.y, HAND.z)
	var fwd := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(55.0)), hand)       # pointing forward-up
	var up := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(8.0)), hand)         # upright staff
	var front := Transform3D(Basis(), hand + Vector3(0, 0.02, 0.08))           # held in front (shields, books)
	var across := Transform3D(Basis(Vector3.BACK, -0.9 * sx) * Basis(Vector3.RIGHT, 0.3), hand + Vector3(-sx * 0.06, 0.05, 0.12))
	var down := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(170.0)), hand)
	var outfit2: Color = o.outfit2
	var steel := Color(0.85, 0.88, 0.94)
	match item:
		"sword":
			b.box(Vector3(0.05, 0.4, 0.016), fwd * MeshKit.at(Vector3(0, 0.27, 0)), steel)
			b.prism(3, 0.03, 0.016, fwd * MeshKit.at(Vector3(0, 0.478, 0), Vector3(1, 1, 1), Vector3(PI * 0.5, 0, PI * 0.5)), steel)
			b.box(Vector3(0.16, 0.03, 0.04), fwd * MeshKit.at(Vector3(0, 0.065, 0)), GOLD)
			b.cylinder(0.018, 0.018, 0.1, fwd * MeshKit.at(Vector3(0, 0.0, 0)), Color(0.4, 0.25, 0.18), 6)
			b.sphere(0.026, fwd * MeshKit.at(Vector3(0, -0.06, 0)), GOLD, 6)
		"dagger":
			b.box(Vector3(0.04, 0.17, 0.012), fwd * MeshKit.at(Vector3(0, 0.15, 0)), steel)
			b.prism(3, 0.024, 0.012, fwd * MeshKit.at(Vector3(0, 0.247, 0), Vector3.ONE, Vector3(PI * 0.5, 0, PI * 0.5)), steel)
			b.box(Vector3(0.1, 0.022, 0.03), fwd * MeshKit.at(Vector3(0, 0.055, 0)), Color(0.5, 0.5, 0.55))
			b.cylinder(0.016, 0.016, 0.08, fwd, Color(0.3, 0.2, 0.15), 6)
		"katana":
			b.box(Vector3(0.03, 0.5, 0.012), fwd * MeshKit.at(Vector3(0, 0.33, 0.0), Vector3.ONE, Vector3(-0.06, 0, 0)), steel)
			b.cylinder(0.045, 0.045, 0.012, fwd * MeshKit.at(Vector3(0, 0.07, 0)), Color(0.3, 0.3, 0.32), 10)
			b.cylinder(0.018, 0.018, 0.14, fwd * MeshKit.at(Vector3(0, -0.01, 0)), Color(0.15, 0.15, 0.2), 6)
		"cutlass":
			b.box(Vector3(0.06, 0.36, 0.014), fwd * MeshKit.at(Vector3(0, 0.25, 0.01), Vector3.ONE, Vector3(-0.12, 0, 0)), steel)
			b.torus(0.06, 0.01, fwd * MeshKit.at(Vector3(0.0, 0.02, 0.02), Vector3(1, 1, 0.6), Vector3(0, 0, PI * 0.5)), GOLD, 10, 3)
			b.cylinder(0.018, 0.018, 0.09, fwd, Color(0.35, 0.22, 0.15), 6)
		"axe":
			b.cylinder(0.02, 0.022, 0.5, fwd * MeshKit.at(Vector3(0, 0.15, 0)), WOOD, 6)
			b.wedge(Vector3(0.025, 0.16, 0.14), fwd * MeshKit.at(Vector3(sx * -0.0, 0.34, 0.08), Vector3.ONE, Vector3(0, 0, 0)), steel)
			b.box(Vector3(0.03, 0.06, 0.05), fwd * MeshKit.at(Vector3(0, 0.36, -0.03)), steel.darkened(0.2))
		"hammer":
			b.cylinder(0.02, 0.022, 0.42, fwd * MeshKit.at(Vector3(0, 0.12, 0)), WOOD, 6)
			b.rounded_box(Vector3(0.1, 0.1, 0.2), 0.02, fwd * MeshKit.at(Vector3(0, 0.34, 0)), Color(0.55, 0.56, 0.62), 1)
		"spear":
			b.cylinder(0.018, 0.018, 1.1, up * MeshKit.at(Vector3(0, 0.25, 0)), WOOD, 6)
			b.cylinder(0.0, 0.045, 0.14, up * MeshKit.at(Vector3(0, 0.86, 0)), steel, 6)
			b.torus(0.022, 0.01, up * MeshKit.at(Vector3(0, 0.78, 0)), outfit2, 8, 3)
		"club":
			b.cylinder(0.065, 0.025, 0.38, fwd * MeshKit.at(Vector3(0, 0.17, 0)), Color(0.55, 0.38, 0.22), 8)
			b.sphere(0.03, fwd * MeshKit.at(Vector3(0.05, 0.3, 0.02)), Color(0.5, 0.34, 0.2), 5)
		"staff":
			b.cylinder(0.022, 0.026, 1.0, up * MeshKit.at(Vector3(0, 0.2, 0)), WOOD.darkened(0.1), 6)
			b.torus(0.06, 0.015, up * MeshKit.at(Vector3(0, 0.7, 0)), WOOD.darkened(0.25), 10, 4)
			b.sphere(0.065, up * MeshKit.at(Vector3(0, 0.76, 0)), outfit2.lerp(Color(0.4, 0.85, 1.0), 0.7), 10, true)
		"rod":
			b.cylinder(0.02, 0.022, 0.9, up * MeshKit.at(Vector3(0, 0.18, 0)), WHITE.darkened(0.08), 6)
			b.torus(0.075, 0.016, up * MeshKit.at(Vector3(0, 0.71, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), GOLD, 12, 4)
			b.sphere(0.03, up * MeshKit.at(Vector3(-0.022, 0.71, 0)), Color(1.0, 0.45, 0.55), 6, true)
			b.sphere(0.03, up * MeshKit.at(Vector3(0.022, 0.71, 0)), Color(1.0, 0.45, 0.55), 6, true)
			b.cone(0.04, 0.045, up * MeshKit.at(Vector3(0, 0.68, 0), Vector3.ONE, Vector3(PI, 0, 0)), Color(1.0, 0.45, 0.55), 6, true)
		"wand":
			b.cylinder(0.012, 0.015, 0.24, fwd * MeshKit.at(Vector3(0, 0.1, 0)), Color(0.95, 0.9, 0.95), 6)
			b.star(5, 0.05, 0.022, 0.02, fwd * MeshKit.at(Vector3(0, 0.25, 0)), Color(1.0, 0.85, 0.3), true)
		"bow":
			var bow_xf := Transform3D(Basis(Vector3.UP, sx * 0.3), hand)
			var prev := Vector3.ZERO
			for k in 7:
				var tt := -1.0 + float(k) / 3.0
				var p := Vector3(0, tt * 0.36, 0.13 * (1.0 - tt * tt))
				if k > 0:
					b.tube(bow_xf * prev, bow_xf * p, 0.017, 0.017, WOOD, 5)
				prev = p
			b.tube(bow_xf * Vector3(0, -0.36, 0), bow_xf * Vector3(0, 0.36, 0), 0.004, 0.004, Color(0.95, 0.95, 0.9), 3, false, false)
		"shield":
			var sh := front * Transform3D(Basis(Vector3.UP, sx * 0.3) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(sx * 0.03, 0, 0))
			b.cylinder(0.17, 0.17, 0.035, sh, outfit2, 16)
			b.torus(0.17, 0.02, sh, STEEL, 16, 4)
			b.sphere(0.04, sh * MeshKit.at(Vector3(0, 0.02, 0)), GOLD, 8)
			b.box(Vector3(0.05, 0.004, 0.22), sh * MeshKit.at(Vector3(0, 0.019, 0)), GOLD.darkened(0.1))
		"round_shield":
			var rs := front * Transform3D(Basis(Vector3.UP, sx * 0.3) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(sx * 0.03, 0, 0))
			b.cylinder(0.19, 0.19, 0.03, rs, Color(0.6, 0.4, 0.25), 14)
			b.torus(0.19, 0.018, rs, Color(0.45, 0.45, 0.5), 14, 4)
			b.dome(0.05, rs * MeshKit.at(Vector3(0, 0.015, 0)), Color(0.6, 0.6, 0.66), 8)
			b.box(Vector3(0.36, 0.004, 0.04), rs * MeshKit.at(Vector3(0, 0.016, 0)), outfit2)
		"lute":
			b.ellipsoid(Vector3(0.11, 0.14, 0.05), across * MeshKit.at(Vector3(0, 0.0, 0)), Color(0.75, 0.5, 0.28), 10)
			b.disc(0.035, across * MeshKit.at(Vector3(0, 0.02, 0.051), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.25, 0.15, 0.1), 10)
			b.box(Vector3(0.04, 0.24, 0.025), across * MeshKit.at(Vector3(0, 0.24, 0.02)), WOOD.darkened(0.2))
			b.box(Vector3(0.06, 0.07, 0.03), across * MeshKit.at(Vector3(0, 0.38, 0.0), Vector3.ONE, Vector3(-0.4, 0, 0)), WOOD.darkened(0.3))
		"ladle":
			b.cylinder(0.012, 0.014, 0.3, fwd * MeshKit.at(Vector3(0, 0.12, 0)), Color(0.8, 0.82, 0.86), 6)
			b.dome(0.06, fwd * MeshKit.at(Vector3(0, 0.29, 0.03), Vector3.ONE, Vector3(PI * 0.6, 0, 0)), Color(0.8, 0.82, 0.86), 10)
		"magnifier":
			b.cylinder(0.016, 0.018, 0.13, fwd * MeshKit.at(Vector3(0, 0.03, 0)), Color(0.35, 0.22, 0.15), 6)
			var lens := fwd * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.17, 0))
			b.torus(0.07, 0.013, lens, GOLD, 14, 4)
			b.cylinder(0.064, 0.064, 0.008, lens, Color(0.7, 0.9, 1.0), 14)
		"flask":
			var fl := Transform3D(Basis(), hand + Vector3(0, 0.07, 0.02))
			b.sphere(0.07, fl, Color(0.85, 0.95, 1.0), 10)
			b.sphere(0.06, fl * MeshKit.at(Vector3(0, -0.01, 0)), Color(0.4, 1.0, 0.5), 10)
			b.cylinder(0.025, 0.028, 0.07, fl * MeshKit.at(Vector3(0, 0.08, 0)), Color(0.85, 0.95, 1.0), 8)
			b.cylinder(0.022, 0.02, 0.03, fl * MeshKit.at(Vector3(0, 0.125, 0)), Color(0.65, 0.45, 0.3), 8)
		"torch":
			b.cylinder(0.018, 0.022, 0.32, fwd * MeshKit.at(Vector3(0, 0.08, 0)), WOOD.darkened(0.2), 6)
			b.sphere(0.05, fwd * MeshKit.at(Vector3(0, 0.27, 0), Vector3(1, 1.3, 1)), Color(1.0, 0.55, 0.15), 8, true)
			b.cone(0.035, 0.1, fwd * MeshKit.at(Vector3(0, 0.34, 0)), Color(1.0, 0.85, 0.3), 6, true)
		"pitchfork":
			b.cylinder(0.018, 0.018, 1.0, up * MeshKit.at(Vector3(0, 0.22, 0)), WOOD, 6)
			b.box(Vector3(0.14, 0.02, 0.02), up * MeshKit.at(Vector3(0, 0.72, 0)), steel)
			for k in 3:
				b.cylinder(0.008, 0.01, 0.14, up * MeshKit.at(Vector3(-0.06 + k * 0.06, 0.8, 0)), steel, 4)
		"sceptre":
			b.cylinder(0.016, 0.02, 0.4, up * MeshKit.at(Vector3(0, 0.1, 0)), GOLD, 6)
			b.sphere(0.05, up * MeshKit.at(Vector3(0, 0.34, 0)), Color(0.9, 0.2, 0.35), 10)
			b.torus(0.045, 0.012, up * MeshKit.at(Vector3(0, 0.3, 0)), GOLD, 10, 3)
		"book":
			var bk := front * Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3.ZERO)
			b.box(Vector3(0.17, 0.22, 0.04), bk, Color(0.65, 0.25, 0.25))
			b.box(Vector3(0.155, 0.2, 0.045), bk * MeshKit.at(Vector3(0.008, 0, 0)), Color(0.98, 0.95, 0.85))
			b.box(Vector3(0.02, 0.06, 0.005), bk * MeshKit.at(Vector3(0, 0, 0.023)), GOLD)
		"lantern":
			var ln := Transform3D(Basis(), hand + Vector3(0, -0.1, 0.03))
			b.torus(0.03, 0.006, ln * MeshKit.at(Vector3(0, 0.12, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.3, 0.3, 0.32), 8, 3)
			b.cylinder(0.05, 0.06, 0.03, ln * MeshKit.at(Vector3(0, 0.08, 0)), Color(0.3, 0.3, 0.32), 8)
			b.cylinder(0.045, 0.045, 0.1, ln * MeshKit.at(Vector3(0, 0.02, 0)), Color(1.0, 0.85, 0.45), 8, true)
			b.cylinder(0.06, 0.05, 0.025, ln * MeshKit.at(Vector3(0, -0.04, 0)), Color(0.3, 0.3, 0.32), 8)
		"blaster":
			var gun := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)), hand + Vector3(0, 0.02, 0.0))
			b.rounded_box(Vector3(0.06, 0.16, 0.08), 0.025, gun * MeshKit.at(Vector3(0, 0.07, 0.03)), Color(0.85, 0.87, 0.92), 1)
			b.cylinder(0.022, 0.026, 0.09, gun * MeshKit.at(Vector3(0, 0.18, 0.04)), Color(0.4, 0.42, 0.5), 8)
			b.sphere(0.02, gun * MeshKit.at(Vector3(0, 0.23, 0.04)), Color(0.3, 1.0, 0.8), 6, true)
			b.box(Vector3(0.04, 0.04, 0.09), gun * MeshKit.at(Vector3(0, 0.0, -0.01)), outfit2)
		"wrench":
			b.box(Vector3(0.035, 0.24, 0.015), fwd * MeshKit.at(Vector3(0, 0.08, 0)), Color(0.7, 0.72, 0.78))
			b.box(Vector3(0.1, 0.05, 0.018), fwd * MeshKit.at(Vector3(0, 0.22, 0)), Color(0.7, 0.72, 0.78))
			b.box(Vector3(0.025, 0.05, 0.018), fwd * MeshKit.at(Vector3(-0.038, 0.26, 0)), Color(0.7, 0.72, 0.78))
			b.box(Vector3(0.025, 0.05, 0.018), fwd * MeshKit.at(Vector3(0.038, 0.26, 0)), Color(0.7, 0.72, 0.78))
		"golf_club":
			b.cylinder(0.012, 0.012, 0.7, down * MeshKit.at(Vector3(0, 0.3, 0)), Color(0.75, 0.77, 0.82), 6)
			b.cylinder(0.02, 0.02, 0.1, down * MeshKit.at(Vector3(0, -0.02, 0)), Color(0.15, 0.15, 0.18), 6)
			b.rounded_box(Vector3(0.05, 0.04, 0.1), 0.015, down * MeshKit.at(Vector3(0, 0.66, 0.035)), Color(0.75, 0.77, 0.82), 1)
		"microphone":
			b.cylinder(0.018, 0.024, 0.13, up * MeshKit.at(Vector3(0, 0.04, 0.02)), Color(0.15, 0.15, 0.18), 8)
			b.sphere(0.042, up * MeshKit.at(Vector3(0, 0.13, 0.02)), Color(0.7, 0.72, 0.78), 10)
		"pan":
			b.cylinder(0.015, 0.018, 0.16, fwd * MeshKit.at(Vector3(0, 0.04, 0)), Color(0.15, 0.13, 0.12), 6)
			var pan := fwd * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.24, 0))
			b.cylinder(0.12, 0.1, 0.035, pan, Color(0.25, 0.25, 0.28), 14)
		"fishing_rod":
			b.cylinder(0.006, 0.016, 1.1, fwd * MeshKit.at(Vector3(0, 0.45, 0)), WOOD.lightened(0.1), 5)
			b.cylinder(0.03, 0.03, 0.03, fwd * MeshKit.at(Vector3(0.03, 0.04, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.5, 0.5, 0.55), 8)
		"broom":
			b.cylinder(0.016, 0.016, 0.9, up * MeshKit.at(Vector3(0, 0.15, 0)), WOOD, 6)
			b.cylinder(0.03, 0.09, 0.22, up * MeshKit.at(Vector3(0, -0.38, 0)), Color(0.9, 0.78, 0.45), 8)
		"tablet":
			var tb := front * Transform3D(Basis(Vector3.RIGHT, -0.7), Vector3(sx * -0.03, 0.03, 0))
			b.rounded_box(Vector3(0.18, 0.13, 0.015), 0.015, tb, Color(0.25, 0.27, 0.32), 1)
			b.panel(Vector2(0.155, 0.105), 0.01, tb * MeshKit.at(Vector3(0, 0, 0.0085)), Color(0.35, 0.85, 1.0), 2)
		"flag":
			b.cylinder(0.012, 0.012, 0.9, up * MeshKit.at(Vector3(0, 0.25, 0)), Color(0.85, 0.85, 0.88), 6)
			b.box(Vector3(0.3, 0.2, 0.01), up * MeshKit.at(Vector3(-sx * 0.15, 0.6, 0)), outfit2)
		_:
			pass


# --- Monsters and animals ---------------------------------------------------------------------------

static func _monster_spec(kind: String, o: Dictionary) -> Spec:
	match kind:
		"slime":
			return _slime(o)
		"bat":
			return _bat(o)
		"wolf", "cat", "dog", "fox", "pig", "sheep":
			return _quad(kind, o)
		"dragon":
			return _dragon(o)
		"robot":
			return _robot(o)
		"ghost":
			return _ghost(o)
		"fish":
			return _fish(o)
		"bird":
			return _bird(o)
		"mushroom":
			return _mushroom(o)
		"mimic":
			return _mimic(o)
		"frog":
			return _frog(o)
		"spider":
			return _spider(o)
		"penguin":
			return _penguin(o)
		"bunny":
			return _bunny(o)
		"bee":
			return _bee(o)
		"crab":
			return _crab(o)
		"golem":
			return _golem(o)
	return _slime(o)


static func _c(o: Dictionary, key: String, def: Color) -> Color:
	if o.has(key):
		var c: Color = o[key]
		return c
	return def


static func _slime(o: Dictionary) -> Spec:
	var spec := _new_spec("blob", 0.5)
	var c := _c(o, "color", Color(0.45, 0.85, 0.55))
	var b := MeshKit.Builder.new()
	b.dome(0.3, MeshKit.at(Vector3(0, 0.0, 0), Vector3(1.0, 1.25, 0.95)), c, 16)
	b.sphere(0.07, MeshKit.at(Vector3(-0.12, 0.27, 0.12), Vector3(1, 0.7, 0.6)), c.lightened(0.5), 8)
	_eyes(b, MeshKit.at(Vector3(0, 0.2, 0.255)), 0.075, 0.045, _c(o, "eye_color", EYE), bool(o.get("boss", false)))
	_blush(b, MeshKit.at(Vector3(0, 0.14, 0.24)), 0.15, 0.035, c)
	b.ellipsoid(Vector3(0.035, 0.018, 0.012), MeshKit.at(Vector3(0, 0.13, 0.275)), c.darkened(0.55), 6)
	if bool(o.get("boss", false)):
		b.cylinder(0.11, 0.1, 0.06, MeshKit.at(Vector3(0, 0.39, 0)), GOLD, 10, false, false)
		for k in 5:
			var a := TAU * k / 5.0
			b.cone(0.03, 0.07, MeshKit.at(Vector3(cos(a) * 0.105, 0.45, sin(a) * 0.105)), GOLD, 5)
	spec.meshes["Torso"] = b.build()
	return spec


static func _bat(o: Dictionary) -> Spec:
	var spec := _new_spec("flyer", 0.6)
	var c := _c(o, "color", Color(0.45, 0.35, 0.6))
	var b := MeshKit.Builder.new()
	var cy := 0.35
	b.sphere(0.17, MeshKit.at(Vector3(0, cy, 0)), c, 14)
	b.sphere(0.11, MeshKit.at(Vector3(0, cy - 0.04, 0.08), Vector3(1, 0.8, 0.6)), c.lightened(0.3), 10)
	for sx in [-1.0, 1.0]:
		var x: float = sx
		b.cone(0.06, 0.14, MeshKit.aim(Vector3(x * 0.1, cy + 0.17, -0.01), Vector3(x * 0.4, 1, 0)), c, 6)
		b.cone(0.03, 0.03, MeshKit.at(Vector3(x * 0.03, cy - 0.09, 0.15), Vector3.ONE, Vector3(PI, 0, 0)), WHITE, 4)
		b.capsule_between(Vector3(x * 0.05, cy - 0.15, 0), Vector3(x * 0.05, cy - 0.21, 0), 0.015, c.darkened(0.3), 5)
	_eyes(b, MeshKit.at(Vector3(0, cy + 0.04, 0.15)), 0.06, 0.035, _c(o, "eye_color", EYE), bool(o.get("boss", false)))
	spec.meshes["Torso"] = b.build()
	for sx in [1.0, -1.0]:
		var x: float = sx
		var w := MeshKit.Builder.new()
		var wc := c.darkened(0.15)
		w.tube(Vector3.ZERO, Vector3(x * 0.3, 0.08, 0), 0.015, 0.012, wc, 5)
		for k in 3:
			var tip := Vector3(x * (0.12 + k * 0.1), -0.12 + k * 0.03, 0)
			w.tube(Vector3(x * (0.1 + k * 0.1), 0.06, 0), tip, 0.01, 0.006, wc, 4)
		var pts := PackedVector2Array()
		pts.append(Vector2(0, 0.02))
		pts.append(Vector2(x * 0.3, 0.08))
		pts.append(Vector2(x * 0.32, -0.09))
		pts.append(Vector2(x * 0.22, -0.06))
		pts.append(Vector2(x * 0.17, -0.11))
		pts.append(Vector2(x * 0.1, -0.08))
		pts.append(Vector2(0, -0.1))
		_membrane(w, pts, c.darkened(0.05))
		_pivot(spec, "WingL" if x > 0.0 else "WingR", w.build(), Vector3(x * 0.13, cy + 0.03, -0.02))
	return spec


## A thin two-sided membrane (wings, fins) in the XY plane from a polygon fanned from its first point.
static func _membrane(b: MeshKit.Builder, pts: PackedVector2Array, c: Color) -> void:
	b.polygon(pts, 0.008, Transform3D.IDENTITY, c)


static func _quad(kind: String, o: Dictionary) -> Spec:
	var spec := _new_spec("quad", 0.7)
	var defaults := {"wolf": Color(0.55, 0.58, 0.68), "cat": Color(1.0, 0.68, 0.38), "dog": Color(0.85, 0.65, 0.42),
		"fox": Color(1.0, 0.52, 0.22), "pig": Color(1.0, 0.72, 0.75), "sheep": Color(0.97, 0.96, 0.92)}
	var c := _c(o, "color", defaults[kind])
	var c2 := _c(o, "color2", WHITE if kind != "sheep" else Color(0.3, 0.28, 0.3))
	var eye := _c(o, "eye_color", EYE)
	var leg_c := c.darkened(0.08) if kind != "sheep" else c2
	var big := kind == "wolf" or kind == "dog"
	var bl := 0.44 if big else 0.36          # body length
	var br := 0.2 if big else 0.165          # body radius
	var leg := 0.15 if big else (0.1 if kind == "pig" else 0.12)
	var body_y := leg + br * 0.75
	var b := MeshKit.Builder.new()
	if kind == "sheep":
		for k in 7:
			var a := TAU * k / 7.0
			b.sphere(0.12, MeshKit.at(Vector3(cos(a) * 0.12, body_y + sin(a) * 0.08 + 0.02, (k - 3) * 0.045)), c, 8)
		b.ellipsoid(Vector3(0.19, 0.17, 0.25), MeshKit.at(Vector3(0, body_y, 0)), c, 12)
	else:
		b.ellipsoid(Vector3(br, br, bl * 0.62), MeshKit.at(Vector3(0, body_y, 0)), c, 14)
		b.ellipsoid(Vector3(br * 0.7, br * 0.55, bl * 0.4), MeshKit.at(Vector3(0, body_y - br * 0.35, 0.02)), c2.lerp(c, 0.3), 10)
	# head
	var hz := bl * 0.62 + 0.06
	var hy := body_y + br * 0.75
	var hr := 0.18 if big else 0.165
	var head_c := c if kind != "sheep" else c2
	b.sphere(hr, MeshKit.at(Vector3(0, hy, hz)), head_c, 14)
	var face := MeshKit.at(Vector3(0, hy + 0.02, hz + hr * 0.88))
	_eyes(b, face, 0.06, 0.03, eye, bool(o.get("boss", false)))
	match kind:
		"wolf", "dog", "fox":
			var snout := 0.11 if kind != "fox" else 0.12
			b.ellipsoid(Vector3(0.07, 0.06, snout), MeshKit.at(Vector3(0, hy - 0.04, hz + hr * 0.75)), c2.lerp(c, 0.2) if kind != "dog" else c.lightened(0.2), 10)
			b.sphere(0.025, MeshKit.at(Vector3(0, hy - 0.01, hz + hr * 0.75 + snout - 0.01)), Color(0.15, 0.12, 0.14), 6)
			for sx in [-1.0, 1.0]:
				var x: float = sx
				if kind == "dog":
					b.ellipsoid(Vector3(0.04, 0.1, 0.06), MeshKit.at(Vector3(x * 0.13, hy - 0.01, hz - 0.02), Vector3.ONE, Vector3(0, 0, x * 0.3)), c.darkened(0.25), 8)
				else:
					b.cone(0.055, 0.13, MeshKit.aim(Vector3(x * 0.08, hy + 0.13, hz - 0.03), Vector3(x * 0.35, 1, -0.1)), c, 6)
					b.cone(0.03, 0.08, MeshKit.aim(Vector3(x * 0.08, hy + 0.135, hz - 0.015), Vector3(x * 0.35, 1, -0.1)), c2.lerp(Color(1, 0.7, 0.7), 0.4), 6)
		"cat":
			b.ellipsoid(Vector3(0.06, 0.04, 0.04), MeshKit.at(Vector3(0, hy - 0.05, hz + hr * 0.85)), c2, 8)
			b.sphere(0.016, MeshKit.at(Vector3(0, hy - 0.025, hz + hr * 0.98)), Color(1.0, 0.5, 0.55), 5)
			for sx in [-1.0, 1.0]:
				var x: float = sx
				b.cone(0.055, 0.1, MeshKit.aim(Vector3(x * 0.085, hy + 0.12, hz - 0.01), Vector3(x * 0.4, 1, 0)), c, 4)
				for k in 2:
					b.tube(Vector3(x * 0.05, hy - 0.04 + k * 0.02, hz + hr * 0.85), Vector3(x * 0.16, hy - 0.03 + k * 0.035, hz + hr * 0.8), 0.003, 0.002, WHITE, 3, false, false)
		"pig":
			b.cylinder(0.06, 0.065, 0.06, MeshKit.at(Vector3(0, hy - 0.03, hz + hr * 0.95), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), c.darkened(0.1), 10)
			for sx in [-1.0, 1.0]:
				var x: float = sx
				b.sphere(0.012, MeshKit.at(Vector3(x * 0.02, hy - 0.03, hz + hr * 0.95 + 0.032)), Color(0.5, 0.3, 0.3), 4)
				b.cone(0.05, 0.08, MeshKit.aim(Vector3(x * 0.09, hy + 0.12, hz), Vector3(x * 0.5, 0.8, 0.4)), c.darkened(0.05), 5)
		"sheep":
			for sx in [-1.0, 1.0]:
				var x: float = sx
				b.ellipsoid(Vector3(0.07, 0.03, 0.04), MeshKit.at(Vector3(x * 0.15, hy, hz - 0.02), Vector3.ONE, Vector3(0, 0, x * -0.3)), c2, 6)
			b.sphere(0.1, MeshKit.at(Vector3(0, hy + 0.11, hz - 0.03)), c, 8)
	_blush(b, MeshKit.at(Vector3(0, hy - 0.03, hz + hr * 0.8)), 0.09, 0.025, head_c)
	spec.meshes["Torso"] = b.build()
	# legs: Leg0 front-left, Leg1 front-right, Leg2 back-left, Leg3 back-right
	var lz := bl * 0.42
	var lx := br * 0.6
	var spots: Array[Vector3] = [Vector3(lx, body_y - br * 0.3, lz), Vector3(-lx, body_y - br * 0.3, lz), Vector3(lx, body_y - br * 0.3, -lz), Vector3(-lx, body_y - br * 0.3, -lz)]
	var hip_y := body_y - br * 0.3
	for i in 4:
		var lb := MeshKit.Builder.new()
		lb.capsule_between(Vector3(0, 0, 0), Vector3(0, -(hip_y - 0.045), 0), 0.045 if big else 0.04, leg_c, 8)
		lb.ellipsoid(Vector3(0.05, 0.035, 0.06), MeshKit.at(Vector3(0, -(hip_y - 0.03), 0.015)), leg_c.darkened(0.1) if kind != "pig" else Color(0.6, 0.45, 0.45), 8)
		_pivot(spec, "Leg%d" % i, lb.build(), spots[i])
	# tail
	var tb := MeshKit.Builder.new()
	match kind:
		"fox":
			tb.ellipsoid(Vector3(0.08, 0.08, 0.2), MeshKit.at(Vector3(0, 0.05, -0.17), Vector3.ONE, Vector3(-0.4, 0, 0)), c, 10)
			tb.sphere(0.06, MeshKit.at(Vector3(0, 0.12, -0.34)), WHITE, 8)
		"wolf", "dog":
			tb.ellipsoid(Vector3(0.05, 0.05, 0.15), MeshKit.at(Vector3(0, 0.06, -0.13), Vector3.ONE, Vector3(-0.6, 0, 0)), c.darkened(0.05), 8)
		"cat":
			tb.capsule_between(Vector3(0, 0, 0), Vector3(0, 0.12, -0.12), 0.025, c, 6)
			tb.capsule_between(Vector3(0, 0.12, -0.12), Vector3(0, 0.26, -0.1), 0.025, c, 6)
		"pig":
			tb.torus(0.03, 0.01, MeshKit.at(Vector3(0, 0.0, -0.03), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), c.darkened(0.05), 8, 4)
		"sheep":
			tb.sphere(0.06, MeshKit.at(Vector3(0, 0.0, -0.04)), c, 6)
	_pivot(spec, "Tail", tb.build(), Vector3(0, body_y + br * 0.3, -bl * 0.58))
	spec.height = hy + hr
	return spec


static func _dragon(o: Dictionary) -> Spec:
	var spec := _new_spec("flyer", 1.0)
	var boss := bool(o.get("boss", false))
	var c := _c(o, "color", Color(0.45, 0.78, 0.5) if not boss else Color(0.82, 0.25, 0.3))
	var c2 := _c(o, "color2", Color(1.0, 0.88, 0.55))
	var eye := _c(o, "eye_color", EYE if not boss else Color(1.0, 0.85, 0.2))
	var b := MeshKit.Builder.new()
	b.ellipsoid(Vector3(0.24, 0.27, 0.26), MeshKit.at(Vector3(0, 0.42, 0)), c, 14)
	b.ellipsoid(Vector3(0.17, 0.21, 0.08), MeshKit.at(Vector3(0, 0.39, 0.2)), c2, 12)
	for k in 4:
		b.box(Vector3(0.16 - k * 0.02, 0.012, 0.02), MeshKit.at(Vector3(0, 0.27 + k * 0.07, 0.275 - absf(k - 1.5) * 0.012)), c2.darkened(0.12))
	# head
	var hc := Vector3(0, 0.8, 0.08)
	b.sphere(0.24, MeshKit.at(hc, Vector3(1.05, 0.95, 1.0)), c, 14)
	b.ellipsoid(Vector3(0.15, 0.1, 0.12), MeshKit.at(hc + Vector3(0, -0.07, 0.19)), c.lightened(0.1), 12)
	for sx in [-1.0, 1.0]:
		var x: float = sx
		b.sphere(0.018, MeshKit.at(hc + Vector3(x * 0.05, -0.04, 0.305)), c.darkened(0.4), 5)
		b.cone(0.05, 0.2 if not boss else 0.3, MeshKit.aim(hc + Vector3(x * 0.12, 0.17, -0.06), Vector3(x * 0.3, 1, -0.6)), c2, 8)
		b.ellipsoid(Vector3(0.025, 0.06, 0.05), MeshKit.at(hc + Vector3(x * 0.23, 0.02, -0.02), Vector3.ONE, Vector3(0, 0, x * 0.5)), c.darkened(0.1), 6)
		# little front arms
		b.capsule_between(Vector3(x * 0.16, 0.42, 0.12), Vector3(x * 0.2, 0.3, 0.2), 0.045, c, 8)
	_eyes(b, MeshKit.at(hc + Vector3(0, 0.04, 0.215)), 0.09, 0.05, eye, boss)
	_blush(b, MeshKit.at(hc + Vector3(0, -0.04, 0.2)), 0.16, 0.035, c)
	for k in 4:
		var y := 0.72 - k * 0.16
		b.cone(0.045 if not boss else 0.07, 0.1 if not boss else 0.16, MeshKit.aim(Vector3(0, y, -0.2 - (0.04 if k == 0 else 0.0)), Vector3(0, 0.6, -1)), c2.darkened(0.1), 6)
	spec.meshes["Torso"] = b.build()
	# wings
	for sx in [1.0, -1.0]:
		var x: float = sx
		var w := MeshKit.Builder.new()
		var wc := c.darkened(0.15)
		w.tube(Vector3.ZERO, Vector3(x * 0.35, 0.25, -0.05), 0.025, 0.018, wc, 6)
		var pts := PackedVector2Array([Vector2(0, 0.0), Vector2(x * 0.35, 0.25), Vector2(x * 0.45, -0.05), Vector2(x * 0.3, 0.0), Vector2(x * 0.22, -0.12), Vector2(x * 0.1, -0.08)])
		_membrane(w, pts, c2.lerp(c, 0.5))
		_pivot(spec, "WingL" if x > 0.0 else "WingR", w.build(), Vector3(x * 0.15, 0.55, -0.15), Vector3(0, x * 0.35, 0))
	# tail
	var tb := MeshKit.Builder.new()
	tb.tube(Vector3.ZERO, Vector3(0, -0.05, -0.25), 0.1, 0.07, c, 10)
	tb.tube(Vector3(0, -0.05, -0.25), Vector3(0, 0.02, -0.45), 0.07, 0.035, c, 8)
	tb.cone(0.07, 0.12, MeshKit.aim(Vector3(0, 0.05, -0.5), Vector3(0, 0.3, -1)), c2, 4)
	_pivot(spec, "Tail", tb.build(), Vector3(0, 0.25, -0.2))
	for sx in [1.0, -1.0]:
		var x: float = sx
		var lg := MeshKit.Builder.new()
		lg.capsule_between(Vector3.ZERO, Vector3(0, -0.12, 0.02), 0.08, c, 8)
		lg.ellipsoid(Vector3(0.08, 0.05, 0.11), MeshKit.at(Vector3(0, -0.17, 0.05)), c2.darkened(0.1), 8)
		_pivot(spec, "LegL" if x > 0.0 else "LegR", lg.build(), Vector3(x * 0.13, 0.22, 0))
	spec.height = 1.05
	return spec


static func _robot(o: Dictionary) -> Spec:
	var spec := _new_spec("biped", 1.05)
	var c := _c(o, "color", Color(0.72, 0.78, 0.88))
	var c2 := _c(o, "color2", Color(0.35, 0.65, 1.0))
	var eye := _c(o, "eye_color", Color(0.35, 1.0, 0.85))
	var t := MeshKit.Builder.new()
	t.rounded_box(Vector3(0.36, 0.32, 0.26), 0.06, MeshKit.at(Vector3(0, 0.43, 0)), c, 2)
	t.rounded_box(Vector3(0.18, 0.12, 0.02), 0.02, MeshKit.at(Vector3(0, 0.45, 0.13)), Color(0.2, 0.22, 0.28), 1)
	for k in 3:
		t.sphere(0.015, MeshKit.at(Vector3(-0.05 + k * 0.05, 0.45, 0.145)), [Color(1, 0.4, 0.4), Color(1, 0.9, 0.35), Color(0.4, 1, 0.5)][k], 6)
	t.cylinder(0.05, 0.05, 0.08, MeshKit.at(NECK), c.darkened(0.3), 8)
	t.rounded_box(Vector3(0.28, 0.08, 0.2), 0.03, MeshKit.at(Vector3(0, 0.27, 0)), c.darkened(0.2), 1)
	spec.meshes["Torso"] = t.build()
	var h := MeshKit.Builder.new()
	h.rounded_box(Vector3(0.44, 0.36, 0.38), 0.09, MeshKit.at(HC), c, 2)
	h.rounded_box(Vector3(0.34, 0.22, 0.02), 0.05, MeshKit.at(HC + Vector3(0, -0.01, 0.19)), Color(0.12, 0.14, 0.2), 2)
	for sx in [-1.0, 1.0]:
		var x: float = sx
		h.ellipsoid(Vector3(0.035, 0.05, 0.01), MeshKit.at(HC + Vector3(x * 0.08, 0.0, 0.205)), eye, 8, true)
		h.cylinder(0.05, 0.05, 0.05, MeshKit.at(HC + Vector3(x * 0.235, 0, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), c2, 10)
	h.panel(Vector2(0.08, 0.02), 0.01, MeshKit.at(HC + Vector3(0, -0.07, 0.206)), eye, 2, true)
	h.cylinder(0.01, 0.01, 0.14, MeshKit.at(HC + Vector3(0, 0.25, 0)), c.darkened(0.3), 5)
	h.sphere(0.035, MeshKit.at(HC + Vector3(0, 0.33, 0)), Color(1.0, 0.4, 0.35), 8, true)
	_pivot(spec, "Head", h.build(), NECK)
	for sx in [1.0, -1.0]:
		var x: float = sx
		var a := MeshKit.Builder.new()
		a.sphere(0.06, MeshKit.at(Vector3.ZERO), c2, 8)
		a.tube(Vector3.ZERO, Vector3(x * 0.03, -0.2, 0), 0.035, 0.035, c.darkened(0.2), 8)
		a.rounded_box(Vector3(0.09, 0.09, 0.09), 0.03, MeshKit.at(Vector3(x * 0.032, -0.24, 0)), c, 1)
		var w: String = str(o.get("weapon", "none"))
		var rest := Vector3(0, 0, 0.1 * x)
		if x < 0.0 and w != "none":
			_item(a, w, {"outfit2": c2}, x)
			rest.x = -0.3
		_pivot(spec, "ArmL" if x > 0.0 else "ArmR", a.build(), Vector3(x * 0.23, 0.53, 0), rest)
		var l := MeshKit.Builder.new()
		l.tube(Vector3.ZERO, Vector3(0, -0.18, 0), 0.04, 0.04, c.darkened(0.2), 8)
		l.rounded_box(Vector3(0.12, 0.07, 0.17), 0.025, MeshKit.at(Vector3(0, -0.215, 0.025)), c, 1)
		_pivot(spec, "LegL" if x > 0.0 else "LegR", l.build(), Vector3(x * 0.09, 0.26, 0))
	spec.height = 1.25
	return spec


static func _ghost(o: Dictionary) -> Spec:
	var spec := _new_spec("float", 0.8)
	var c := _c(o, "color", Color(0.92, 0.93, 1.0, 0.85))
	spec.transparent = c.a < 0.999
	var b := MeshKit.Builder.new()
	b.sphere(0.25, MeshKit.at(Vector3(0, 0.5, 0)), c, 16)
	b.cylinder(0.25, 0.3, 0.3, MeshKit.at(Vector3(0, 0.36, 0)), c, 16, false, false)
	for k in 6:
		var a := TAU * k / 6.0
		b.cone(0.09, 0.14, MeshKit.at(Vector3(cos(a) * 0.22, 0.17, sin(a) * 0.22), Vector3.ONE, Vector3(PI, 0, 0)), c, 6)
	b.disc(0.3, MeshKit.at(Vector3(0, 0.21, 0), Vector3.ONE, Vector3(PI, 0, 0)), c, 16)
	var eye := _c(o, "eye_color", Color(0.15, 0.13, 0.25))
	_eyes(b, MeshKit.at(Vector3(0, 0.53, 0.235)), 0.08, 0.045, eye, bool(o.get("boss", false)))
	b.ellipsoid(Vector3(0.04, 0.05, 0.015), MeshKit.at(Vector3(0, 0.43, 0.245)), Color(0.25, 0.2, 0.35, c.a), 8)
	_blush(b, MeshKit.at(Vector3(0, 0.46, 0.22)), 0.15, 0.035, Color(c.r, c.g, c.b))
	var mat: Material = MeshKit.vertex_material(false, true) if spec.transparent else null
	spec.meshes["Torso"] = b.build(mat)
	for sx in [1.0, -1.0]:
		var x: float = sx
		var a := MeshKit.Builder.new()
		a.ellipsoid(Vector3(0.06, 0.12, 0.06), MeshKit.at(Vector3(x * 0.04, -0.08, 0.02), Vector3.ONE, Vector3(0, 0, x * 0.5)), c, 8)
		_pivot(spec, "ArmL" if x > 0.0 else "ArmR", a.build(mat), Vector3(x * 0.23, 0.45, 0), Vector3(0, 0, x * 0.2))
	return spec


static func _fish(o: Dictionary) -> Spec:
	var spec := _new_spec("swim", 0.4)
	var c := _c(o, "color", Color(1.0, 0.6, 0.3))
	var c2 := _c(o, "color2", WHITE)
	var b := MeshKit.Builder.new()
	b.ellipsoid(Vector3(0.11, 0.16, 0.24), MeshKit.at(Vector3(0, 0.2, 0)), c, 14)
	b.ellipsoid(Vector3(0.1, 0.1, 0.12), MeshKit.at(Vector3(0, 0.16, 0.07)), c2.lerp(c, 0.3), 10)
	for k in 2:
		b.torus(0.12 - k * 0.02, 0.012, MeshKit.at(Vector3(0, 0.2, -0.04 - k * 0.08), Vector3(0.9, 1.3, 1), Vector3(PI * 0.5, 0, 0)), c2, 12, 3)
	b.wedge(Vector3(0.015, 0.12, 0.16), MeshKit.at(Vector3(0, 0.38, -0.04)), c.darkened(0.15))
	for sx in [-1.0, 1.0]:
		var x: float = sx
		b.ellipsoid(Vector3(0.012, 0.05, 0.08), MeshKit.at(Vector3(x * 0.1, 0.13, 0.04), Vector3.ONE, Vector3(0.5, x * 0.4, 0)), c.darkened(0.1), 6)
		var exf := Transform3D(Basis(Vector3.UP, x * PI * 0.5 * 0.75), Vector3(x * 0.075, 0.24, 0.14))
		_eye(b, exf, 0.035, _c(o, "eye_color", EYE), false)
	b.ellipsoid(Vector3(0.03, 0.02, 0.015), MeshKit.at(Vector3(0, 0.17, 0.235)), c.darkened(0.45), 6)
	spec.meshes["Torso"] = b.build()
	var t := MeshKit.Builder.new()
	var pts := PackedVector2Array([Vector2(0, 0.02), Vector2(0.14, 0.12), Vector2(0.1, 0.0), Vector2(0.14, -0.12), Vector2(0, -0.02)])
	var fin := MeshKit.Builder.new()
	_membrane(fin, pts, c.darkened(0.1))
	t.add_mesh(fin.build(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0, -0.02)))
	_pivot(spec, "Tail", t.build(), Vector3(0, 0.2, -0.22))
	return spec


static func _bird(o: Dictionary) -> Spec:
	var spec := _new_spec("flyer", 0.45)
	var c := _c(o, "color", Color(0.4, 0.7, 1.0))
	var c2 := _c(o, "color2", Color(1.0, 0.95, 0.85))
	var b := MeshKit.Builder.new()
	b.sphere(0.14, MeshKit.at(Vector3(0, 0.2, 0), Vector3(1, 1, 1.1)), c, 14)
	b.ellipsoid(Vector3(0.1, 0.1, 0.06), MeshKit.at(Vector3(0, 0.17, 0.1)), c2, 10)
	b.sphere(0.11, MeshKit.at(Vector3(0, 0.36, 0.06)), c, 12)
	b.cone(0.035, 0.08, MeshKit.aim(Vector3(0, 0.34, 0.19), Vector3(0, -0.1, 1)), Color(1.0, 0.7, 0.2), 6)
	_eyes(b, MeshKit.at(Vector3(0, 0.38, 0.155)), 0.045, 0.028, _c(o, "eye_color", EYE))
	b.wedge(Vector3(0.1, 0.03, 0.14), MeshKit.at(Vector3(0, 0.2, -0.19), Vector3.ONE, Vector3(-0.3, PI, 0)), c.darkened(0.15))
	for sx in [-1.0, 1.0]:
		var x: float = sx
		b.tube(Vector3(x * 0.04, 0.09, 0.0), Vector3(x * 0.045, 0.0, 0.02), 0.01, 0.01, Color(1.0, 0.65, 0.2), 4)
		b.ellipsoid(Vector3(0.025, 0.012, 0.04), MeshKit.at(Vector3(x * 0.045, 0.006, 0.04)), Color(1.0, 0.65, 0.2), 5)
	b.ellipsoid(Vector3(0.015, 0.04, 0.03), MeshKit.at(Vector3(0, 0.48, 0.03), Vector3.ONE, Vector3(-0.4, 0, 0)), c.darkened(0.2), 5)
	spec.meshes["Torso"] = b.build()
	for sx in [1.0, -1.0]:
		var x: float = sx
		var w := MeshKit.Builder.new()
		w.ellipsoid(Vector3(0.13, 0.02, 0.08), MeshKit.at(Vector3(x * 0.11, 0, -0.02), Vector3.ONE, Vector3(0, 0, x * -0.15)), c.darkened(0.1), 8)
		_pivot(spec, "WingL" if x > 0.0 else "WingR", w.build(), Vector3(x * 0.1, 0.24, 0.0))
	return spec


static func _mushroom(o: Dictionary) -> Spec:
	var spec := _new_spec("biped", 0.6)
	var c := _c(o, "color", Color(0.92, 0.3, 0.28))
	var b := MeshKit.Builder.new()
	b.cylinder(0.13, 0.15, 0.26, MeshKit.at(Vector3(0, 0.2, 0)), Color(0.98, 0.93, 0.82), 12)
	b.dome(0.3, MeshKit.at(Vector3(0, 0.32, 0), Vector3(1, 0.8, 1)), c, 14)
	b.disc(0.3, MeshKit.at(Vector3(0, 0.32, 0), Vector3.ONE, Vector3(PI, 0, 0)), Color(0.95, 0.88, 0.75), 14)
	for k in 6:
		var a := TAU * k / 6.0
		b.sphere(0.045, MeshKit.at(Vector3(cos(a) * 0.19, 0.47, sin(a) * 0.19), Vector3(1, 0.45, 1)), WHITE, 6)
	b.sphere(0.05, MeshKit.at(Vector3(0, 0.56, 0), Vector3(1, 0.4, 1)), WHITE, 6)
	_eyes(b, MeshKit.at(Vector3(0, 0.22, 0.14)), 0.05, 0.03, _c(o, "eye_color", EYE), bool(o.get("boss", false)))
	_blush(b, MeshKit.at(Vector3(0, 0.18, 0.13)), 0.085, 0.022, Color(0.98, 0.93, 0.82))
	spec.meshes["Torso"] = b.build()
	for sx in [1.0, -1.0]:
		var x: float = sx
		var l := MeshKit.Builder.new()
		l.ellipsoid(Vector3(0.05, 0.05, 0.07), MeshKit.at(Vector3(0, -0.035, 0.02)), Color(0.85, 0.75, 0.6), 8)
		_pivot(spec, "LegL" if x > 0.0 else "LegR", l.build(), Vector3(x * 0.07, 0.08, 0))
	return spec


static func _mimic(o: Dictionary) -> Spec:
	var spec := _new_spec("chest", 0.6)
	var wood := _c(o, "color", Color(0.62, 0.4, 0.24))
	var b := MeshKit.Builder.new()
	b.rounded_box(Vector3(0.7, 0.34, 0.46), 0.04, MeshKit.at(Vector3(0, 0.17, 0)), wood, 1)
	b.box(Vector3(0.6, 0.02, 0.36), MeshKit.at(Vector3(0, 0.335, 0)), Color(0.45, 0.1, 0.15))
	for k in 6:
		b.cone(0.03, 0.06, MeshKit.at(Vector3(-0.25 + k * 0.1, 0.37, 0.2)), WHITE, 4)
	b.ellipsoid(Vector3(0.1, 0.03, 0.18), MeshKit.at(Vector3(0.05, 0.35, 0.05), Vector3.ONE, Vector3(0.1, 0.3, 0)), Color(1.0, 0.45, 0.55), 8)
	for x in [-0.25, 0.25]:
		var px: float = x
		b.box(Vector3(0.06, 0.36, 0.48), MeshKit.at(Vector3(px, 0.17, 0)), GOLD)
	spec.meshes["Torso"] = b.build()
	var lid := MeshKit.Builder.new()
	lid.cylinder(0.23, 0.23, 0.7, MeshKit.at(Vector3(0, 0.0, 0.23), Vector3(0.6, 1, 1), Vector3(0, 0, PI * 0.5)), wood.lightened(0.08), 12)
	for x in [-0.25, 0.25]:
		var px: float = x
		lid.torus(0.23, 0.03, MeshKit.at(Vector3(px, 0.0, 0.23), Vector3(0.6, 1, 1), Vector3(0, 0, PI * 0.5)), GOLD, 12, 4)
	for k in 6:
		lid.cone(0.03, 0.06, MeshKit.at(Vector3(-0.25 + k * 0.1, -0.03, 0.43), Vector3.ONE, Vector3(PI, 0, 0)), WHITE, 4)
	_eyes(lid, MeshKit.at(Vector3(0, 0.07, 0.42)), 0.1, 0.045, _c(o, "eye_color", Color(1.0, 0.85, 0.25)), true)
	_pivot(spec, "Lid", lid.build(), Vector3(0, 0.34, -0.23))
	return spec


static func _frog(o: Dictionary) -> Spec:
	var spec := _new_spec("blob", 0.4)
	var c := _c(o, "color", Color(0.45, 0.82, 0.35))
	var b := MeshKit.Builder.new()
	b.ellipsoid(Vector3(0.2, 0.15, 0.2), MeshKit.at(Vector3(0, 0.15, 0)), c, 14)
	b.ellipsoid(Vector3(0.15, 0.08, 0.12), MeshKit.at(Vector3(0, 0.09, 0.08)), Color(0.95, 0.95, 0.75), 10)
	for sx in [-1.0, 1.0]:
		var x: float = sx
		b.sphere(0.07, MeshKit.at(Vector3(x * 0.1, 0.27, 0.08)), c, 10)
		b.ellipsoid(Vector3(0.035, 0.045, 0.02), MeshKit.at(Vector3(x * 0.1, 0.28, 0.145)), _c(o, "eye_color", EYE), 8)
		b.sphere(0.012, MeshKit.at(Vector3(x * 0.1 - 0.012, 0.295, 0.16)), WHITE, 4)
		b.ellipsoid(Vector3(0.07, 0.04, 0.12), MeshKit.at(Vector3(x * 0.17, 0.04, -0.04)), c.darkened(0.1), 8)
		b.ellipsoid(Vector3(0.04, 0.03, 0.06), MeshKit.at(Vector3(x * 0.1, 0.025, 0.15)), c.darkened(0.1), 6)
	b.torus(0.08, 0.008, MeshKit.at(Vector3(0, 0.17, 0.12), Vector3(1, 1, 0.5), Vector3(PI * 0.5 + 0.3, 0, 0)), c.darkened(0.45), 12, 3)
	_blush(b, MeshKit.at(Vector3(0, 0.17, 0.17)), 0.13, 0.025, c)
	spec.meshes["Torso"] = b.build()
	return spec


static func _spider(o: Dictionary) -> Spec:
	var spec := _new_spec("crawler", 0.45)
	var c := _c(o, "color", Color(0.3, 0.26, 0.38))
	var b := MeshKit.Builder.new()
	b.sphere(0.2, MeshKit.at(Vector3(0, 0.3, -0.14), Vector3(1, 0.9, 1.1)), c, 14)
	b.sphere(0.14, MeshKit.at(Vector3(0, 0.25, 0.1)), c.lightened(0.1), 12)
	b.ellipsoid(Vector3(0.08, 0.02, 0.05), MeshKit.at(Vector3(0, 0.47, -0.16)), Color(0.9, 0.3, 0.35), 8)
	_eyes(b, MeshKit.at(Vector3(0, 0.29, 0.225)), 0.05, 0.035, _c(o, "eye_color", EYE), bool(o.get("boss", false)))
	b.sphere(0.015, MeshKit.at(Vector3(-0.035, 0.34, 0.215)), _c(o, "eye_color", EYE), 5)
	b.sphere(0.015, MeshKit.at(Vector3(0.035, 0.34, 0.215)), _c(o, "eye_color", EYE), 5)
	spec.meshes["Torso"] = b.build()
	for sx in [1.0, -1.0]:
		var x: float = sx
		var l := MeshKit.Builder.new()
		for k in 4:
			var z := 0.1 - k * 0.07
			var knee := Vector3(x * 0.18, 0.12, z + 0.02 * (1.5 - k))
			l.tube(Vector3(0, 0, z * 0.5), knee, 0.022, 0.02, c.darkened(0.1), 5)
			l.tube(knee, Vector3(x * 0.3, -0.22, z * 1.4), 0.02, 0.012, c.darkened(0.1), 5)
		_pivot(spec, "LegsL" if x > 0.0 else "LegsR", l.build(), Vector3(x * 0.08, 0.24, 0.0))
	return spec


static func _penguin(o: Dictionary) -> Spec:
	var spec := _new_spec("biped", 0.65)
	var c := _c(o, "color", Color(0.2, 0.22, 0.32))
	var b := MeshKit.Builder.new()
	b.ellipsoid(Vector3(0.2, 0.28, 0.18), MeshKit.at(Vector3(0, 0.32, 0)), c, 14)
	b.ellipsoid(Vector3(0.15, 0.22, 0.08), MeshKit.at(Vector3(0, 0.29, 0.11)), WHITE, 12)
	b.ellipsoid(Vector3(0.12, 0.1, 0.04), MeshKit.at(Vector3(0, 0.46, 0.13)), WHITE, 10)
	b.cone(0.04, 0.08, MeshKit.aim(Vector3(0, 0.45, 0.19), Vector3(0, -0.2, 1)), Color(1.0, 0.7, 0.2), 6)
	_eyes(b, MeshKit.at(Vector3(0, 0.5, 0.155)), 0.06, 0.03, _c(o, "eye_color", EYE))
	_blush(b, MeshKit.at(Vector3(0, 0.44, 0.15)), 0.1, 0.022, WHITE)
	spec.meshes["Torso"] = b.build()
	for sx in [1.0, -1.0]:
		var x: float = sx
		var a := MeshKit.Builder.new()
		a.ellipsoid(Vector3(0.03, 0.14, 0.07), MeshKit.at(Vector3(x * 0.02, -0.12, 0)), c, 8)
		_pivot(spec, "ArmL" if x > 0.0 else "ArmR", a.build(), Vector3(x * 0.19, 0.42, 0), Vector3(0, 0, x * 0.25))
		var l := MeshKit.Builder.new()
		l.ellipsoid(Vector3(0.06, 0.025, 0.09), MeshKit.at(Vector3(0, -0.035, 0.05)), Color(1.0, 0.65, 0.2), 8)
		_pivot(spec, "LegL" if x > 0.0 else "LegR", l.build(), Vector3(x * 0.08, 0.06, 0))
	return spec


static func _bunny(o: Dictionary) -> Spec:
	var spec := _new_spec("blob", 0.6)
	var c := _c(o, "color", Color(0.98, 0.95, 0.92))
	var b := MeshKit.Builder.new()
	b.ellipsoid(Vector3(0.16, 0.15, 0.2), MeshKit.at(Vector3(0, 0.15, -0.03)), c, 14)
	b.sphere(0.13, MeshKit.at(Vector3(0, 0.3, 0.12)), c, 14)
	for sx in [-1.0, 1.0]:
		var x: float = sx
		b.ellipsoid(Vector3(0.04, 0.14, 0.025), MeshKit.at(Vector3(x * 0.06, 0.52, 0.08), Vector3.ONE, Vector3(-0.15, 0, x * -0.15)), c, 8)
		b.ellipsoid(Vector3(0.022, 0.1, 0.012), MeshKit.at(Vector3(x * 0.06, 0.52, 0.1), Vector3.ONE, Vector3(-0.15, 0, x * -0.15)), Color(1.0, 0.7, 0.75), 6)
		b.ellipsoid(Vector3(0.05, 0.035, 0.1), MeshKit.at(Vector3(x * 0.1, 0.03, 0.02)), c.darkened(0.05), 8)
	b.sphere(0.06, MeshKit.at(Vector3(0, 0.17, -0.23)), WHITE, 8)
	_eyes(b, MeshKit.at(Vector3(0, 0.32, 0.24)), 0.055, 0.028, _c(o, "eye_color", EYE))
	b.sphere(0.018, MeshKit.at(Vector3(0, 0.285, 0.25)), Color(1.0, 0.55, 0.6), 5)
	_blush(b, MeshKit.at(Vector3(0, 0.27, 0.22)), 0.085, 0.022, c)
	spec.meshes["Torso"] = b.build()
	return spec


static func _bee(o: Dictionary) -> Spec:
	var spec := _new_spec("flyer", 0.45)
	var c := _c(o, "color", Color(1.0, 0.82, 0.25))
	var b := MeshKit.Builder.new()
	b.ellipsoid(Vector3(0.14, 0.13, 0.17), MeshKit.at(Vector3(0, 0.25, -0.02)), c, 14)
	for k in 2:
		b.torus(0.12 - k * 0.015, 0.025, MeshKit.at(Vector3(0, 0.25, -0.04 - k * 0.08), Vector3(1, 1, 1), Vector3(PI * 0.5, 0, 0)), Color(0.18, 0.15, 0.15), 14, 4)
	b.cone(0.025, 0.06, MeshKit.aim(Vector3(0, 0.25, -0.2), Vector3(0, 0, -1)), Color(0.18, 0.15, 0.15), 5)
	_eyes(b, MeshKit.at(Vector3(0, 0.28, 0.15)), 0.05, 0.03, _c(o, "eye_color", EYE))
	_blush(b, MeshKit.at(Vector3(0, 0.24, 0.14)), 0.085, 0.02, c)
	for sx in [-1.0, 1.0]:
		var x: float = sx
		b.tube(Vector3(x * 0.04, 0.36, 0.08), Vector3(x * 0.07, 0.45, 0.11), 0.007, 0.007, Color(0.18, 0.15, 0.15), 4)
		b.sphere(0.018, MeshKit.at(Vector3(x * 0.07, 0.455, 0.11)), Color(0.18, 0.15, 0.15), 5)
	spec.meshes["Torso"] = b.build()
	for sx in [1.0, -1.0]:
		var x: float = sx
		var w := MeshKit.Builder.new()
		w.ellipsoid(Vector3(0.1, 0.008, 0.06), MeshKit.at(Vector3(x * 0.09, 0.0, 0)), Color(0.85, 0.95, 1.0), 8)
		_pivot(spec, "WingL" if x > 0.0 else "WingR", w.build(), Vector3(x * 0.06, 0.36, -0.03))
	return spec


static func _crab(o: Dictionary) -> Spec:
	var spec := _new_spec("biped", 0.35)
	var c := _c(o, "color", Color(1.0, 0.42, 0.32))
	var b := MeshKit.Builder.new()
	b.ellipsoid(Vector3(0.22, 0.11, 0.17), MeshKit.at(Vector3(0, 0.16, 0)), c, 14)
	for sx in [-1.0, 1.0]:
		var x: float = sx
		b.tube(Vector3(x * 0.06, 0.24, 0.1), Vector3(x * 0.07, 0.32, 0.12), 0.01, 0.01, c, 4)
		b.sphere(0.035, MeshKit.at(Vector3(x * 0.07, 0.33, 0.12)), WHITE, 8)
		b.sphere(0.02, MeshKit.at(Vector3(x * 0.07, 0.335, 0.145)), _c(o, "eye_color", EYE), 6)
		for k in 3:
			b.tube(Vector3(x * 0.15, 0.13, -0.06 + k * 0.06), Vector3(x * 0.27, 0.0, -0.08 + k * 0.07), 0.018, 0.012, c.darkened(0.1), 4)
	_blush(b, MeshKit.at(Vector3(0, 0.17, 0.165)), 0.1, 0.025, c)
	spec.meshes["Torso"] = b.build()
	for sx in [1.0, -1.0]:
		var x: float = sx
		var a := MeshKit.Builder.new()
		a.tube(Vector3.ZERO, Vector3(x * 0.06, 0.02, 0.1), 0.025, 0.025, c, 6)
		a.ellipsoid(Vector3(0.07, 0.05, 0.09), MeshKit.at(Vector3(x * 0.08, 0.04, 0.17)), c.lightened(0.05), 10)
		a.cone(0.03, 0.08, MeshKit.aim(Vector3(x * 0.06, 0.08, 0.22), Vector3(-x * 0.2, 0.5, 1)), c.lightened(0.05), 5)
		_pivot(spec, "ArmL" if x > 0.0 else "ArmR", a.build(), Vector3(x * 0.17, 0.17, 0.08))
	return spec


static func _golem(o: Dictionary) -> Spec:
	var spec := _new_spec("biped", 1.4)
	var c := _c(o, "color", Color(0.58, 0.56, 0.6))
	var moss := _c(o, "color2", Color(0.45, 0.72, 0.35))
	var eye := _c(o, "eye_color", Color(0.45, 0.95, 1.0))
	var t := MeshKit.Builder.new()
	t.rounded_box(Vector3(0.6, 0.5, 0.4), 0.12, MeshKit.at(Vector3(0, 0.6, 0)), c, 1)
	t.rounded_box(Vector3(0.4, 0.2, 0.3), 0.08, MeshKit.at(Vector3(0, 0.33, 0)), c.darkened(0.1), 1)
	t.ellipsoid(Vector3(0.18, 0.06, 0.15), MeshKit.at(Vector3(-0.12, 0.86, -0.02)), moss, 8)
	t.sphere(0.06, MeshKit.at(Vector3(0, 0.62, 0.2)), eye.lightened(0.2), 8)
	spec.meshes["Torso"] = t.build()
	var h := MeshKit.Builder.new()
	h.rounded_box(Vector3(0.36, 0.3, 0.32), 0.1, MeshKit.at(Vector3(0, 0.15, 0.04)), c.lightened(0.05), 1)
	h.box(Vector3(0.28, 0.05, 0.05), MeshKit.at(Vector3(0, 0.2, 0.2)), c.darkened(0.25))
	for sx in [-1.0, 1.0]:
		var x: float = sx
		h.sphere(0.035, MeshKit.at(Vector3(x * 0.075, 0.15, 0.2)), eye, 8, true)
	h.ellipsoid(Vector3(0.12, 0.04, 0.1), MeshKit.at(Vector3(0.05, 0.31, 0.0)), moss, 8)
	_pivot(spec, "Head", h.build(), Vector3(0, 0.85, 0.02))
	for sx in [1.0, -1.0]:
		var x: float = sx
		var a := MeshKit.Builder.new()
		a.sphere(0.13, MeshKit.at(Vector3.ZERO), c.darkened(0.05), 10)
		a.tube(Vector3.ZERO, Vector3(x * 0.05, -0.3, 0), 0.1, 0.11, c, 8)
		a.rounded_box(Vector3(0.24, 0.22, 0.22), 0.07, MeshKit.at(Vector3(x * 0.06, -0.42, 0.02)), c.lightened(0.05), 1)
		_pivot(spec, "ArmL" if x > 0.0 else "ArmR", a.build(), Vector3(x * 0.4, 0.75, 0), Vector3(0, 0, x * 0.12))
		var l := MeshKit.Builder.new()
		l.tube(Vector3.ZERO, Vector3(0, -0.15, 0), 0.11, 0.12, c.darkened(0.1), 8)
		l.rounded_box(Vector3(0.24, 0.1, 0.28), 0.05, MeshKit.at(Vector3(0, -0.2, 0.03)), c, 1)
		_pivot(spec, "LegL" if x > 0.0 else "LegR", l.build(), Vector3(x * 0.15, 0.25, 0))
	spec.height = 1.25
	return spec


# =================================================================================================

class Crowd extends Node3D:
	## A MultiMesh crowd made by Creatures.crowd(). cheer 0 = idle sway, 1 = jumping and cheering.

	var cheer := 0.0
	## Set false to stop updating the instances (zero per-frame cost).
	var animate := true
	var _mms: Array[MultiMesh] = []
	var _base: Array = []
	var _phase: Array = []
	var _t := 0.0

	## Register one MultiMesh and its rest transforms (used by Creatures.crowd()).
	func add_group(mm: MultiMesh, xfs: Array) -> void:
		_mms.append(mm)
		_base.append(xfs.duplicate())
		var ph := PackedFloat32Array()
		for i in xfs.size():
			ph.append(randf() * TAU)
		_phase.append(ph)

	## Number of people in the crowd.
	func size() -> int:
		var n := 0
		for b in _base:
			var arr: Array = b
			n += arr.size()
		return n

	func _process(delta: float) -> void:
		if not animate:
			return
		_t += delta
		var rate := 2.5 + cheer * 6.0
		var hop_h := 0.012 + cheer * 0.2
		for m in _mms.size():
			var mm := _mms[m]
			var base: Array = _base[m]
			var ph: PackedFloat32Array = _phase[m]
			for i in base.size():
				var b: Transform3D = base[i]
				var p := ph[i]
				var hop := absf(sin(_t * rate + p)) * hop_h
				var sway := sin(_t * 1.3 + p) * 0.05 * (1.0 - cheer)
				mm.set_instance_transform(i, Transform3D(b.basis * Basis(Vector3.BACK, sway), b.origin + b.basis.y.normalized() * hop * b.basis.get_scale().y))


class Anim extends Node:
	## Procedural animation for a creature made by Creatures. Child "Anim" of the creature root.
	## Drives the "Model" node (bob, squash, lean, lunge) and named limb pivots (ArmL/ArmR/LegL/LegR,
	## Leg0-3, WingL/WingR, Tail, Head, Lid, LegsL/LegsR). Cheap: one _process with a few sines.

	## Emitted when a one-shot action (attack, hurt, cast, cheer, jump, wave, talk, nod) ends.
	signal action_finished(action: String)

	var rig := "biped"
	## Winged creatures flap and hover while true (bats, birds, bees; dragons default to walking).
	var flying := false
	## Walk/run speed in m/s (0 = idle). Set with walk().
	var speed := 0.0
	## Animation playback rate (1 = normal).
	var rate := 1.0

	var _model: Node3D
	var _limbs := {}
	var _rest := {}
	var _base_scale := Vector3.ONE
	var _t := 0.0
	var _phase := 0.0
	var _action := ""
	var _action_t := 0.0
	var _action_len := 0.0
	var _action_dir := Vector3.ZERO
	var _loop_action := ""
	var _down := 0.0
	var _down_target := 0.0
	var _sq := 0.0
	var _sq_v := 0.0
	var _blink_t := 2.0
	var _blink_left := 0.0
	var _flash := 0.0
	var _flash_len := 0.25
	var _flash_col := Color(1, 0.25, 0.25)
	var _overlay: StandardMaterial3D
	var _meshes: Array[GeometryInstance3D] = []
	var _yaw_target := 0.0
	var _turning := false
	var _hop := 0.0
	var _lids: Node3D

	func _ready() -> void:
		_t = randf() * 10.0
		_blink_t = randf_range(1.0, 4.0)
		var root := get_parent() as Node3D
		if root == null:
			return
		_model = root.get_node_or_null("Model") as Node3D
		if _model == null:
			return
		_base_scale = _model.scale
		_collect(_model)
		_lids = _model.get_node_or_null("Head/Blink") as Node3D
		_yaw_target = root.rotation.y

	func _collect(n: Node) -> void:
		for ch in n.get_children():
			var n3 := ch as Node3D
			if n3 == null:
				continue
			if n3 is GeometryInstance3D:
				_meshes.append(n3 as GeometryInstance3D)
			if n3.has_meta("rest"):
				_limbs[str(n3.name)] = n3
				var r: Vector3 = n3.get_meta("rest")
				_rest[str(n3.name)] = r
			_collect(n3)

	# --- Public API ---------------------------------------------------------------------------

	## Set the locomotion speed in m/s (0 = idle). Legs, arms, wings and hops follow it.
	func walk(new_speed: float) -> void:
		speed = maxf(0.0, new_speed)

	## Play a one-shot action: "attack", "hurt", "cast", "cheer", "jump", "wave", "talk", "nod", or the
	## looping "victory" (until stop()), or "faint" (stays down until revive()). dir: lunge/knockback
	## direction in world space (default: the creature's front). duration < 0 = the action's default.
	func play(action: String, duration: float = -1.0, dir: Vector3 = Vector3.ZERO) -> void:
		if action == "faint":
			faint()
			return
		if action == "victory":
			_loop_action = "cheer"
			action = "cheer"
		var lens := {"attack": 0.55, "hurt": 0.45, "cast": 0.9, "cheer": 1.2, "jump": 0.6, "wave": 1.4, "talk": 1.5, "nod": 0.5}
		_action = action
		_action_t = 0.0
		_action_len = duration if duration > 0.0 else float(lens.get(action, 0.6))
		_action_dir = dir
		if action == "jump":
			squash(0.25)
		elif action == "hurt":
			flash(Color(1.0, 0.25, 0.25))

	## Stop any action (and a looping victory).
	func stop() -> void:
		_loop_action = ""
		if _action != "":
			var a := _action
			_action = ""
			action_finished.emit(a)

	## True while a one-shot action is playing.
	func is_busy() -> bool:
		return _action != ""

	## Short hit reaction: knock back from `from_dir` (world, optional) and flash `color`.
	func hurt(color: Color = Color(1.0, 0.25, 0.25), from_dir: Vector3 = Vector3.ZERO) -> void:
		play("hurt", -1.0, from_dir)
		flash(color)

	## Tint the whole creature with `color` for `time` seconds (adds one draw pass while it lasts).
	func flash(color: Color = Color(1, 1, 1), time: float = 0.25) -> void:
		_flash_col = color
		_flash_len = maxf(0.05, time)
		_flash = 1.0
		if _overlay == null:
			_overlay = StandardMaterial3D.new()
			_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		for m in _meshes:
			if is_instance_valid(m):
				m.material_overlay = _overlay

	## Squash (positive) or stretch (negative) impulse; springs back.
	func squash(amount: float = 0.3) -> void:
		_sq_v -= amount * 9.0

	## Fall over and stay down (defeated / fainted).
	func faint() -> void:
		_down_target = 1.0
		_action = ""
		_loop_action = ""

	## Get back up after faint().
	func revive() -> void:
		_down_target = 0.0
		squash(0.2)

	## True while fainted.
	func is_down() -> bool:
		return _down_target > 0.5

	## Blink now.
	func blink() -> void:
		_blink_left = 0.12

	## Turn smoothly to face `dir` (world, ground plane); instant = snap.
	func face(dir: Vector3, instant: bool = false) -> void:
		if Vector2(dir.x, dir.z).length() < 0.0001:
			return
		_yaw_target = atan2(dir.x, dir.z)
		_turning = true
		var root := get_parent() as Node3D
		if instant and root != null:
			root.rotation.y = _yaw_target
			_turning = false

	## Turn smoothly to face a world position.
	func face_point(pos: Vector3) -> void:
		var root := get_parent() as Node3D
		if root != null:
			face(pos - root.global_position)

	# --- Per frame ----------------------------------------------------------------------------

	func _process(delta: float) -> void:
		if _model == null or not is_instance_valid(_model):
			return
		var dt := delta * rate
		_t += dt
		var root := get_parent() as Node3D
		if _turning and root != null:
			root.rotation.y = lerp_angle(root.rotation.y, _yaw_target, 1.0 - exp(-10.0 * dt))
			if absf(angle_difference(root.rotation.y, _yaw_target)) < 0.01:
				_turning = false
		var h := float(root.get_meta("creature_height", 1.0)) if root != null else 1.0
		# base pose
		var pos := Vector3.ZERO
		var rot := Vector3.ZERO
		var scl := Vector3.ONE
		for k in _limbs:
			var limb: Node3D = _limbs[k]
			limb.rotation = _rest[k]
		# breathing
		var breathe := sin(_t * 2.4)
		scl.y *= 1.0 + 0.018 * breathe
		scl.x *= 1.0 - 0.008 * breathe
		scl.z *= 1.0 - 0.008 * breathe
		# locomotion
		var moving := speed > 0.05
		var amp := clampf(speed * 0.32, 0.0, 0.85)
		if moving:
			_phase += dt * (5.0 + speed * 2.5)
		else:
			_phase = lerpf(_phase, roundf(_phase / PI) * PI, 1.0 - exp(-8.0 * dt))
		var sw := sin(_phase)
		match rig:
			"biped":
				_swing("LegL", Vector3(sw * amp, 0, 0))
				_swing("LegR", Vector3(-sw * amp, 0, 0))
				_swing("ArmL", Vector3(-sw * amp * 0.7, 0, 0))
				_swing("ArmR", Vector3(sw * amp * 0.7, 0, 0))
				if moving:
					pos.y += absf(sin(_phase)) * 0.035 * h
					rot.z += sin(_phase) * 0.04
					rot.x += amp * 0.08
				_swing("Head", Vector3(0, 0, sin(_t * 0.8) * 0.04))
			"quad":
				_swing("Leg0", Vector3(sw * amp, 0, 0))
				_swing("Leg3", Vector3(sw * amp, 0, 0))
				_swing("Leg1", Vector3(-sw * amp, 0, 0))
				_swing("Leg2", Vector3(-sw * amp, 0, 0))
				_swing("Tail", Vector3(0.2 + sin(_t * 2.0) * 0.1, sin(_t * (3.0 + speed * 2.0)) * (0.35 + amp * 0.3), 0))
				if moving:
					pos.y += absf(sin(_phase)) * 0.025 * h
					rot.x += sin(_phase * 2.0) * 0.03
			"flyer":
				var flap_rate := 14.0 if flying else 2.5
				var flap_amp := 0.75 if flying else 0.15
				var flap := sin(_t * flap_rate) * flap_amp
				_swing("WingL", Vector3(0, 0, flap))
				_swing("WingR", Vector3(0, 0, -flap))
				_swing("Tail", Vector3(sin(_t * 1.5) * 0.08, sin(_t * 2.2) * 0.25, 0))
				if flying:
					pos.y += 0.25 * h + sin(_t * 2.5) * 0.06 * h
					rot.x += amp * 0.25
				else:
					_swing("LegL", Vector3(sw * amp, 0, 0))
					_swing("LegR", Vector3(-sw * amp, 0, 0))
					if moving:
						pos.y += absf(sin(_phase)) * 0.03 * h
			"blob":
				if moving:
					var hop_p := fmod(_phase / PI, 1.0)
					pos.y += sin(hop_p * PI) * 0.18 * h
					if hop_p < _hop:
						squash(0.22)
					_hop = hop_p
				else:
					_hop = 0.0
			"float":
				pos.y += 0.08 * h + sin(_t * 2.0) * 0.05 * h
				rot.x += amp * 0.25
				_swing("ArmL", Vector3(sin(_t * 2.6) * 0.25, 0, sin(_t * 2.0) * 0.15))
				_swing("ArmR", Vector3(-sin(_t * 2.6) * 0.25, 0, -sin(_t * 2.0) * 0.15))
				rot.z += sin(_t * 1.3) * 0.05
			"swim":
				var wag := sin(_t * (6.0 + speed * 6.0)) * (0.35 + amp * 0.4)
				_swing("Tail", Vector3(0, wag, 0))
				rot.y += -wag * 0.12
				pos.y += sin(_t * 1.7) * 0.02
			"chest":
				_swing("Lid", Vector3(-0.08 - 0.06 * (0.5 + 0.5 * sin(_t * 1.8)), 0, 0))
				if moving:
					pos.y += absf(sin(_phase)) * 0.08 * h
					_swing("Lid", Vector3(-absf(sin(_phase)) * 0.4, 0, 0))
			"crawler":
				var wig := sin(_t * (3.0 + speed * 10.0)) * (0.08 + amp * 0.25)
				_swing("LegsL", Vector3(wig, 0, 0))
				_swing("LegsR", Vector3(-wig, 0, 0))
				pos.y += absf(sin(_t * 12.0)) * 0.01 * (1.0 if moving else 0.0)
		# one-shot actions
		if _action != "":
			_action_t += dt
			var p := clampf(_action_t / _action_len, 0.0, 1.0)
			var fwd := Vector3(0, 0, 1)
			if _action_dir.length() > 0.01 and root != null:
				fwd = (root.global_basis.inverse() * _action_dir)
				fwd.y = 0.0
				fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3(0, 0, 1)
			match _action:
				"attack":
					var lunge := sin(clampf((p - 0.25) / 0.6, 0.0, 1.0) * PI)
					pos += fwd * lunge * 0.22 * h
					rot.x += lunge * 0.18
					var wind := clampf(p / 0.3, 0.0, 1.0)
					var strike := clampf((p - 0.3) / 0.2, 0.0, 1.0)
					var back := clampf((p - 0.6) / 0.4, 0.0, 1.0)
					var arm := lerpf(lerpf(0.0, -2.3, wind), -0.5, strike)
					arm = lerpf(arm, 0.0, back)
					_swing("ArmR", Vector3(arm, 0, 0))
					_swing("Lid", Vector3(-lunge * 0.9, 0, 0))
					_swing("Head", Vector3(lunge * 0.25, 0, 0))
					if rig == "blob" or rig == "swim" or rig == "crawler" or rig == "quad":
						pos.y += lunge * 0.06 * h
				"hurt":
					var k := sin(p * PI)
					pos -= fwd * k * 0.12 * h
					rot.x -= k * 0.3
					rot.z += sin(p * 40.0) * 0.06 * (1.0 - p)
				"cast":
					var up := sin(clampf(p * 1.2, 0.0, 1.0) * PI * 0.5) * (1.0 - clampf((p - 0.75) / 0.25, 0.0, 1.0))
					_swing("ArmL", Vector3(-2.5 * up, 0, 0.3 * up))
					_swing("ArmR", Vector3(-2.5 * up, 0, -0.3 * up))
					_swing("WingL", Vector3(0, 0, 0.6 * up))
					_swing("WingR", Vector3(0, 0, -0.6 * up))
					pos.y += up * 0.05 * h + sin(_t * 20.0) * 0.006 * up
				"cheer":
					var hops := absf(sin(p * PI * 3.0))
					pos.y += hops * 0.14 * h
					var arms := sin(clampf(p * 4.0, 0.0, 1.0) * PI * 0.5) * (1.0 - clampf((p - 0.85) / 0.15, 0.0, 1.0))
					_swing("ArmL", Vector3(0, 0, 2.6 * arms + sin(_t * 18.0) * 0.15 * arms))
					_swing("ArmR", Vector3(0, 0, -2.6 * arms - sin(_t * 18.0) * 0.15 * arms))
					_swing("WingL", Vector3(0, 0, sin(_t * 18.0) * 0.6))
					_swing("WingR", Vector3(0, 0, -sin(_t * 18.0) * 0.6))
					_swing("Tail", Vector3(0, sin(_t * 16.0) * 0.6, 0))
				"jump":
					pos.y += 4.0 * p * (1.0 - p) * 0.35 * h
					_swing("ArmL", Vector3(-0.6 * sin(p * PI), 0, 0.4 * sin(p * PI)))
					_swing("ArmR", Vector3(-0.6 * sin(p * PI), 0, -0.4 * sin(p * PI)))
				"wave":
					var up2 := sin(clampf(p * 5.0, 0.0, 1.0) * PI * 0.5) * (1.0 - clampf((p - 0.85) / 0.15, 0.0, 1.0))
					_swing("ArmL", Vector3(0, 0, (2.5 + sin(_t * 12.0) * 0.35) * up2))
					_swing("Head", Vector3(0, 0, 0.1 * up2))
				"talk":
					var bob := sin(_t * 13.0)
					_swing("Head", Vector3(bob * 0.07, sin(_t * 3.0) * 0.08, 0))
					scl.y *= 1.0 + bob * 0.015
					_swing("ArmR", Vector3(-0.35 - sin(_t * 4.0) * 0.2, 0, 0))
					_swing("Lid", Vector3(-absf(bob) * 0.3, 0, 0))
				"nod":
					_swing("Head", Vector3(sin(p * TAU * 2.0) * 0.22, 0, 0))
					rot.x += sin(p * TAU * 2.0) * 0.04
			if _action_t >= _action_len:
				var done := _action
				if _loop_action != "" and done == _loop_action:
					_action_t = 0.0
				else:
					_action = ""
					action_finished.emit(done)
		# faint
		_down = move_toward(_down, _down_target, dt * 2.5)
		if _down > 0.0:
			var e := _down * _down * (3.0 - 2.0 * _down)
			rot.x -= e * PI * 0.5
			pos.z += e * 0.4 * h
			pos.y += e * 0.12 * h
		# squash spring
		_sq_v += (-140.0 * _sq - 10.0 * _sq_v) * dt
		_sq += _sq_v * dt
		var s := clampf(_sq, -0.45, 0.45)
		scl *= Vector3(1.0 + s * 0.5, 1.0 - s, 1.0 + s * 0.5)
		_model.position = pos
		_model.rotation = rot
		_model.scale = _base_scale * scl
		# blink
		_blink_t -= dt
		if _blink_t <= 0.0:
			_blink_t = randf_range(2.2, 5.0)
			_blink_left = 0.12
		var lids := _lids
		if lids != null and is_instance_valid(lids):
			lids.visible = _blink_left > 0.0 and _down < 0.5
			if _down >= 0.5:
				lids.visible = true
		_blink_left -= dt
		# flash
		if _flash > 0.0:
			_flash = maxf(0.0, _flash - dt / _flash_len)
			if _overlay != null:
				var fc := _flash_col
				fc.a = _flash * 0.85
				_overlay.albedo_color = fc
			if _flash <= 0.0:
				for m in _meshes:
					if is_instance_valid(m):
						m.material_overlay = null

	func _swing(limb: String, add: Vector3) -> void:
		if _limbs.has(limb):
			var n: Node3D = _limbs[limb]
			var r: Vector3 = _rest[limb]
			n.rotation = r + add
