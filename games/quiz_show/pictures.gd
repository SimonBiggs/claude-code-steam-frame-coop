extends RefCounted
## QUIZ SHOW picture round: what can hide behind the tiles on the big screen, and how to build it.
## Every machine builds the same 3D picture from its id (no meshes go over the network): animals and
## monsters (core/creatures.gd), people by job (Creatures humanoids), things (core/mesh_kit.gd props)
## and country flags (vertex-coloured MeshKit stripes, one draw call each).
## build(id) returns a Node3D whose origin is the bottom centre and which fits in about `size` metres.

const MeshKit := preload("res://core/mesh_kit.gd")
const Creatures := preload("res://core/creatures.gd")
const ResCache := preload("res://core/res_cache.gd")

## [id, tier, group, answer]. group: animal (Creatures.monster kind = id), person (humanoid class),
## thing (MeshKit prop), flag (FLAGS key).
const ITEMS := [
	["cat", 1, "animal", "Cat"], ["dog", 1, "animal", "Dog"], ["pig", 1, "animal", "Pig"],
	["sheep", 1, "animal", "Sheep"], ["penguin", 1, "animal", "Penguin"], ["bunny", 1, "animal", "Rabbit"],
	["bee", 1, "animal", "Bee"], ["crab", 1, "animal", "Crab"], ["frog", 1, "animal", "Frog"],
	["fish", 1, "animal", "Fish"], ["bird", 1, "animal", "Bluebird"], ["spider", 1, "animal", "Spider"],
	["fox", 2, "animal", "Fox"], ["wolf", 2, "animal", "Wolf"], ["bat", 2, "animal", "Bat"],
	["dragon", 2, "animal", "Dragon"], ["ghost", 2, "animal", "Ghost"], ["robot", 2, "animal", "Robot"],
	["knight", 1, "person", "Knight"], ["chef", 1, "person", "Chef"], ["astronaut", 1, "person", "Astronaut"],
	["pirate", 1, "person", "Pirate"], ["mage", 1, "person", "Wizard"], ["king", 1, "person", "King"],
	["princess", 1, "person", "Princess"], ["queen", 2, "person", "Queen"], ["ninja", 2, "person", "Ninja"],
	["viking", 2, "person", "Viking"], ["farmer", 2, "person", "Farmer"], ["detective", 2, "person", "Detective"],
	["scientist", 2, "person", "Scientist"], ["pilot", 2, "person", "Pilot"], ["archer", 2, "person", "Archer"],
	["tree", 1, "thing", "Oak tree"], ["mushroom", 1, "thing", "Mushroom"], ["chest", 1, "thing", "Treasure chest"],
	["candle", 1, "thing", "Candle"], ["chair", 1, "thing", "Chair"], ["cloud", 1, "thing", "Cloud"],
	["heart", 1, "thing", "Heart"], ["star", 1, "thing", "Star"], ["palm", 2, "thing", "Palm tree"],
	["pine", 2, "thing", "Pine tree"], ["barrel", 2, "thing", "Barrel"], ["lamp_post", 2, "thing", "Lamp post"],
	["bookshelf", 2, "thing", "Bookshelf"], ["gem", 2, "thing", "Gem"], ["fence", 2, "thing", "Fence"],
	["japan", 2, "flag", "Japan"], ["france", 2, "flag", "France"], ["italy", 2, "flag", "Italy"],
	["germany", 2, "flag", "Germany"], ["sweden", 2, "flag", "Sweden"], ["switzerland", 2, "flag", "Switzerland"],
	["ukraine", 2, "flag", "Ukraine"], ["canada", 2, "flag", "Canada"], ["ireland", 3, "flag", "Ireland"],
	["netherlands", 3, "flag", "Netherlands"], ["denmark", 3, "flag", "Denmark"], ["finland", 3, "flag", "Finland"],
	["poland", 3, "flag", "Poland"], ["belgium", 3, "flag", "Belgium"], ["austria", 3, "flag", "Austria"],
	["nigeria", 3, "flag", "Nigeria"], ["peru", 3, "flag", "Peru"], ["russia", 3, "flag", "Russia"],
	["hungary", 3, "flag", "Hungary"], ["estonia", 3, "flag", "Estonia"], ["lithuania", 3, "flag", "Lithuania"],
	["bangladesh", 3, "flag", "Bangladesh"], ["mali", 3, "flag", "Mali"], ["romania", 3, "flag", "Romania"],
	["colombia", 3, "flag", "Colombia"], ["norway", 3, "flag", "Norway"], ["thailand", 3, "flag", "Thailand"],
]

## What the host asks for each group.
const QUESTIONS := {
	"animal": "Who is hiding behind the tiles?",
	"person": "Which job does this person do?",
	"thing": "What is hiding behind the tiles?",
	"flag": "Which country's flag is this?",
}

## Extra wrong answers for flags (look-alike colours make it fun) beyond the other flags in the list.
const FLAG_DECOYS := ["Mexico", "Spain", "Portugal", "Chad", "Monaco", "Indonesia", "Iceland", "Latvia",
	"Bulgaria", "Luxembourg", "Ivory Coast", "Senegal", "Ghana", "Bolivia"]

const RED := Color(0.86, 0.12, 0.17)
const WHITE := Color(0.97, 0.97, 0.97)
const BLUE := Color(0.0, 0.2, 0.55)

## Flag looks. kind: "v" vertical stripes, "h" horizontal stripes (weights optional), "nordic" cross,
## "disc" a disc on a field, "plus" Swiss cross (square), "canada".
const FLAGS := {
	"japan": {"kind": "disc", "bg": WHITE, "fg": Color(0.74, 0.0, 0.18), "dx": 0.0},
	"bangladesh": {"kind": "disc", "bg": Color(0.0, 0.42, 0.31), "fg": Color(0.96, 0.16, 0.25), "dx": -0.1},
	"france": {"kind": "v", "c": [Color(0.0, 0.14, 0.58), WHITE, Color(0.93, 0.16, 0.22)]},
	"italy": {"kind": "v", "c": [Color(0.0, 0.57, 0.27), WHITE, Color(0.81, 0.17, 0.2)]},
	"ireland": {"kind": "v", "c": [Color(0.09, 0.6, 0.38), WHITE, Color(1.0, 0.53, 0.24)]},
	"belgium": {"kind": "v", "c": [Color(0.05, 0.05, 0.05), Color(0.99, 0.85, 0.13), Color(0.94, 0.2, 0.24)]},
	"romania": {"kind": "v", "c": [Color(0.0, 0.17, 0.5), Color(0.99, 0.82, 0.09), Color(0.81, 0.07, 0.15)]},
	"mali": {"kind": "v", "c": [Color(0.08, 0.71, 0.23), Color(0.99, 0.82, 0.09), Color(0.81, 0.07, 0.15)]},
	"nigeria": {"kind": "v", "c": [Color(0.0, 0.53, 0.32), WHITE, Color(0.0, 0.53, 0.32)]},
	"peru": {"kind": "v", "c": [Color(0.85, 0.06, 0.14), WHITE, Color(0.85, 0.06, 0.14)]},
	"germany": {"kind": "h", "c": [Color(0.05, 0.05, 0.05), Color(0.87, 0.0, 0.0), Color(1.0, 0.81, 0.0)]},
	"netherlands": {"kind": "h", "c": [Color(0.68, 0.11, 0.16), WHITE, Color(0.13, 0.27, 0.55)]},
	"russia": {"kind": "h", "c": [WHITE, Color(0.0, 0.22, 0.65), Color(0.84, 0.17, 0.12)]},
	"hungary": {"kind": "h", "c": [Color(0.81, 0.16, 0.22), WHITE, Color(0.28, 0.44, 0.27)]},
	"austria": {"kind": "h", "c": [Color(0.93, 0.16, 0.22), WHITE, Color(0.93, 0.16, 0.22)]},
	"poland": {"kind": "h", "c": [WHITE, Color(0.86, 0.08, 0.24)]},
	"ukraine": {"kind": "h", "c": [Color(0.0, 0.36, 0.73), Color(1.0, 0.84, 0.0)]},
	"estonia": {"kind": "h", "c": [Color(0.0, 0.45, 0.81), Color(0.05, 0.05, 0.05), WHITE]},
	"lithuania": {"kind": "h", "c": [Color(0.99, 0.73, 0.07), Color(0.0, 0.42, 0.27), Color(0.76, 0.15, 0.17)]},
	"colombia": {"kind": "h", "c": [Color(0.99, 0.82, 0.09), Color(0.0, 0.22, 0.58), Color(0.81, 0.07, 0.15)], "w": [2.0, 1.0, 1.0]},
	"thailand": {"kind": "h", "c": [Color(0.65, 0.1, 0.19), WHITE, Color(0.18, 0.16, 0.36), WHITE, Color(0.65, 0.1, 0.19)], "w": [1.0, 1.0, 2.0, 1.0, 1.0]},
	"sweden": {"kind": "nordic", "bg": Color(0.0, 0.42, 0.66), "cross": Color(1.0, 0.8, 0.0)},
	"denmark": {"kind": "nordic", "bg": Color(0.78, 0.06, 0.18), "cross": WHITE},
	"finland": {"kind": "nordic", "bg": WHITE, "cross": Color(0.0, 0.21, 0.5)},
	"norway": {"kind": "nordic", "bg": Color(0.73, 0.05, 0.18), "cross": WHITE, "inner": Color(0.0, 0.13, 0.36)},
	"switzerland": {"kind": "plus", "bg": Color(0.85, 0.0, 0.0), "fg": WHITE},
	"canada": {"kind": "canada", "bg": WHITE, "fg": Color(0.85, 0.12, 0.12)},
}

## A rough maple leaf outline (unit size, centred), for Canada.
const MAPLE := [Vector2(0.0, 1.0), Vector2(0.12, 0.72), Vector2(0.28, 0.78), Vector2(0.22, 0.42), Vector2(0.48, 0.62),
	Vector2(0.56, 0.5), Vector2(0.8, 0.56), Vector2(0.72, 0.3), Vector2(0.86, 0.22), Vector2(0.5, -0.04),
	Vector2(0.56, -0.2), Vector2(0.06, -0.14), Vector2(0.06, -0.5), Vector2(-0.06, -0.5), Vector2(-0.06, -0.14),
	Vector2(-0.56, -0.2), Vector2(-0.5, -0.04), Vector2(-0.86, 0.22), Vector2(-0.72, 0.3), Vector2(-0.8, 0.56),
	Vector2(-0.56, 0.5), Vector2(-0.48, 0.62), Vector2(-0.22, 0.42), Vector2(-0.28, 0.78), Vector2(-0.12, 0.72)]


## The item row for an id (empty if unknown).
static func item(id: String) -> Array:
	for it in ITEMS:
		var row: Array = it
		if String(row[0]) == id:
			return row
	return []


## Items of a tier or easier, optionally of one group ("" = any).
static func pool(max_tier: int, group: String = "") -> Array:
	var out: Array = []
	for it in ITEMS:
		var row: Array = it
		if int(row[1]) <= max_tier and (group == "" or String(row[2]) == group):
			out.append(row)
	return out


## Three wrong answers for an item: others of the same group (and flag look-alikes).
static func decoys(id: String, rng: RandomNumberGenerator) -> Array[String]:
	var row := item(id)
	var out: Array[String] = []
	if row.is_empty():
		return out
	var names: Array[String] = []
	for it in ITEMS:
		var r: Array = it
		if String(r[2]) == String(row[2]) and String(r[0]) != id:
			names.append(String(r[3]))
	if String(row[2]) == "flag":
		for d in FLAG_DECOYS:
			names.append(String(d))
	while out.size() < 3 and not names.is_empty():
		var k := rng.randi() % names.size()
		var n: String = names[k]
		names.remove_at(k)
		if n != String(row[3]) and not out.has(n):
			out.append(n)
	return out


# --- Building -------------------------------------------------------------------------------------

## The 3D picture for `id`, bottom centre at the origin, scaled to fit `size` metres (width and height).
static func build(id: String, size: float = 2.4) -> Node3D:
	var row := item(id)
	var root := Node3D.new()
	root.name = "Picture"
	if row.is_empty():
		return root
	var group := String(row[2])
	var body: Node3D
	match group:
		"animal":
			body = Creatures.monster(id, {"seed": 4})
		"person":
			body = Creatures.humanoid({"class": id, "seed": 11})
		"thing":
			body = MeshKit.instance(MeshKit.prop(id), false)
		"flag":
			body = MeshKit.instance(flag_mesh(id), false)
	if body == null:
		return root
	root.add_child(body)
	var box := _bounds(body, Transform3D.IDENTITY)
	if box.size.length() < 0.001:
		return root
	var k := size / maxf(box.size.y, maxf(box.size.x, box.size.z * 0.6))
	body.scale = Vector3.ONE * k
	body.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * k
	root.set_meta("flat", group == "flag")
	return root


## AABB of every mesh under `n` (local to n's parent through `xf`).
static func _bounds(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is GeometryInstance3D and (n as GeometryInstance3D).visible:
		var gi := n as GeometryInstance3D
		var local := gi.get_aabb()
		if local.size.length() > 0.0001:
			out = here * local
			first = false
	for c in n.get_children():
		if c is Node3D:
			var cb := _bounds(c, here)
			if cb.size.length() > 0.0001:
				out = cb if first else out.merge(cb)
				first = false
	return out


## A flag on a short gold-topped pole: one vertex-coloured mesh (cached per country).
static func flag_mesh(id: String) -> ArrayMesh:
	return ResCache.get_or_make("qs_flag_%s_v1" % id, func() -> Resource: return _make_flag(id))


static func _make_flag(id: String) -> ArrayMesh:
	var f: Dictionary = FLAGS.get(id, {"kind": "h", "c": [WHITE]})
	var b := MeshKit.Builder.new()
	var w := 2.4
	var h := 1.6
	if String(f["kind"]) == "plus":
		w = 1.6
	var base_y := 1.0  # the flag cloth hangs from y = base_y to base_y + h
	var x0 := -w * 0.5
	var cy := base_y + h * 0.5
	var d := 0.04
	match String(f["kind"]):
		"v":
			var cols: Array = f["c"]
			var sw := w / cols.size()
			for i in cols.size():
				b.box(Vector3(sw, h, d), MeshKit.at(Vector3(x0 + sw * (i + 0.5), cy, 0.0)), cols[i])
		"h":
			var cols2: Array = f["c"]
			var weights: Array = f.get("w", [])
			var total := 0.0
			for i in cols2.size():
				total += float(weights[i]) if i < weights.size() else 1.0
			var y := base_y + h
			for i in cols2.size():
				var wt := float(weights[i]) if i < weights.size() else 1.0
				var sh := h * wt / total
				b.box(Vector3(w, sh, d), MeshKit.at(Vector3(0.0, y - sh * 0.5, 0.0)), cols2[i])
				y -= sh
		"nordic":
			b.box(Vector3(w, h, d), MeshKit.at(Vector3(0.0, cy, 0.0)), f["bg"])
			var cx := x0 + w * 0.36
			var t := h * 0.2
			b.box(Vector3(w, t, d * 1.2), MeshKit.at(Vector3(0.0, cy, 0.0)), f["cross"])
			b.box(Vector3(t, h, d * 1.2), MeshKit.at(Vector3(cx, cy, 0.0)), f["cross"])
			if f.has("inner"):
				var ti := t * 0.5
				b.box(Vector3(w, ti, d * 1.4), MeshKit.at(Vector3(0.0, cy, 0.0)), f["inner"])
				b.box(Vector3(ti, h, d * 1.4), MeshKit.at(Vector3(cx, cy, 0.0)), f["inner"])
		"disc":
			b.box(Vector3(w, h, d), MeshKit.at(Vector3(0.0, cy, 0.0)), f["bg"])
			b.cylinder(h * 0.3, h * 0.3, d * 1.3, MeshKit.at(Vector3(w * float(f["dx"]), cy, 0.0), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), f["fg"], 24)
		"plus":
			b.box(Vector3(w, h, d), MeshKit.at(Vector3(0.0, cy, 0.0)), f["bg"])
			b.box(Vector3(w * 0.6, h * 0.19, d * 1.3), MeshKit.at(Vector3(0.0, cy, 0.0)), f["fg"])
			b.box(Vector3(w * 0.19, h * 0.6, d * 1.3), MeshKit.at(Vector3(0.0, cy, 0.0)), f["fg"])
		"canada":
			var red: Color = f["fg"]
			b.box(Vector3(w * 0.25, h, d), MeshKit.at(Vector3(x0 + w * 0.125, cy, 0.0)), red)
			b.box(Vector3(w * 0.5, h, d), MeshKit.at(Vector3(0.0, cy, 0.0)), f["bg"])
			b.box(Vector3(w * 0.25, h, d), MeshKit.at(Vector3(-x0 - w * 0.125, cy, 0.0)), red)
			var leaf := PackedVector2Array()
			for p in MAPLE:
				var v: Vector2 = p
				leaf.append(v * h * 0.42)
			b.polygon(leaf, d * 1.4, MeshKit.at(Vector3(0.0, cy, 0.0)), red)
	# pole on the left with a golden knob, and a little base
	var pole_x := x0 - 0.06
	b.cylinder(0.045, 0.05, base_y + h + 0.15, MeshKit.at(Vector3(pole_x, (base_y + h + 0.15) * 0.5, 0.0)), Color(0.85, 0.86, 0.9), 10)
	b.sphere(0.09, MeshKit.at(Vector3(pole_x, base_y + h + 0.2, 0.0)), Color(1.0, 0.8, 0.3), 10)
	b.cylinder(0.25, 0.3, 0.12, MeshKit.at(Vector3(pole_x, 0.06, 0.0)), Color(0.3, 0.3, 0.38), 14)
	return b.build()
