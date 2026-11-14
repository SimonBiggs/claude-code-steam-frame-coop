extends Node
## SPECIAL BLOCKS' physics (Tower Stack, second pass; host / local only: TV machines just draw the blocks).
## The numbers come from towergen.gd so the game behaves the way the validator assumes:
##   BOUNCY  physics material FRIC / BOUNCE (slippery and springy); a TV player who lands on one bounces sky-high
##           (main.gd _move_local_players asks bounce_jump()).
##   STICKY  honey: once it rests, it is glued (a locked Generic6DOFJoint3D) to every block or the stage it touches,
##           so nothing tips or slides where it sits. Grabbing / lifting a glued block unglues it.
##   BALLOON lifted by (1 - HEAVY) of its weight every physics frame while it's free, so it is light and the wind
##           pushes it about more (main.gd's wind pushes every free block by its whole mass).
##   MORTAR  (Wren's STICKY MORTAR gift, gifts.gd) any block main.gd marks with mortar(id) - one resting in its plan
##           spot - glues down exactly like honey.
##   specials.setup(rb, kind, id)    tick(main)    unglue(id)    glued(id) -> Array of ids (-1 = the stage)

const G := preload("res://games/tower_stack/towergen.gd")
const ResCache := preload("res://core/res_cache.gd")

const BOUNCE_JUMP := 12.5  # a TV player's bounce off a bouncy block (main.gd JUMP is 7.5)
const GLUE_SPEED := 0.4  # honey glues once it moves slower than this

var joints := {}  # id -> {other id: Joint3D} (both ends listed)
var glues_made := 0  # telemetry
var mortared := {}  # id -> true: glues like honey (the STICKY MORTAR gift)
var mortar_glues := 0  # glue joints the mortar made (telemetry, bots)
var _g := 9.8


func _ready() -> void:
	name = "Specials"
	_g = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


## Authority: give a new block its kind's physics material (and contact reports for honey).
static func setup(rb: RigidBody3D, kind: int, id: int) -> void:
	rb.set_meta("ts_id", id)
	rb.physics_material_override = ResCache.get_or_make("tower_stack_block_pm_v2_%d" % kind, func() -> Resource:
		var pm := PhysicsMaterial.new()
		pm.friction = G.FRIC[kind]
		pm.bounce = G.BOUNCE[kind]
		return pm)
	if kind == G.K_STICKY:
		rb.contact_monitor = true
		rb.max_contacts_reported = 6


## How high a TV player bounces off the block they land on (0 = an ordinary landing).
static func bounce_jump(kind: int) -> float:
	return BOUNCE_JUMP if kind == G.K_BOUNCY else 0.0


## Authority, every physics frame: balloons lift, resting honey glues, glue on lifted blocks lets go.
func tick(main: Node) -> void:
	var blocks: Dictionary = main.blocks
	for id in blocks:
		var kind := int(main.bkind.get(id, 0))
		if kind != G.K_BALLOON and kind != G.K_STICKY and not mortared.has(id):
			continue
		var rb: RigidBody3D = blocks[id]
		var st := String(main.bstate.get(id, ""))
		if kind == G.K_BALLOON:
			if st == "free" and not rb.freeze:
				rb.apply_central_force(Vector3.UP * rb.mass * _g * (1.0 - G.HEAVY[kind]))
			if not mortared.has(id):
				continue
		if st != "free" or rb.freeze or rb.linear_velocity.length() > GLUE_SPEED:
			continue
		for body in rb.get_colliding_bodies():
			var other := -1 if body == main.stage else int(body.get_meta("ts_id", -2))
			if other == -2 or (other >= 0 and (not blocks.has(other) or String(main.bstate.get(other, "")) != "free")):
				continue
			if (joints.get(id, {}) as Dictionary).has(other):
				continue
			_glue(main, int(id), rb, other, body as PhysicsBody3D)
	# Glue lets go of anything the giant, the crane or the pad lifts.
	for id in joints.keys():
		var st2 := String(main.bstate.get(id, ""))
		if not blocks.has(id) or not st2 in ["free", "done"]:
			unglue(int(id))


func _glue(main: Node, id: int, rb: RigidBody3D, other: int, body: PhysicsBody3D) -> void:
	var j := Generic6DOFJoint3D.new()
	j.name = "Glue%d_%d" % [id, other]
	main.add_child(j)
	j.global_position = (rb.global_position + body.global_position) * 0.5
	j.node_a = j.get_path_to(rb)
	j.node_b = j.get_path_to(body)
	var mine: Dictionary = joints.get(id, {})
	mine[other] = j
	joints[id] = mine
	if other >= 0:
		var theirs: Dictionary = joints.get(other, {})
		theirs[id] = j
		joints[other] = theirs
	glues_made += 1
	if mortared.has(id):
		mortar_glues += 1
	if main.has_method("_poke"):
		main._poke(id, 0.3)


## Free every glue joint of this block (before it is grabbed, lifted or removed).
func unglue(id: int) -> void:
	var mine: Dictionary = joints.get(id, {})
	for other in mine:
		var j: Node = mine[other]
		if is_instance_valid(j):
			j.queue_free()
		if joints.has(other):
			(joints[other] as Dictionary).erase(id)
			if (joints[other] as Dictionary).is_empty():
				joints.erase(other)
	joints.erase(id)


## The blocks (and -1 for the stage) this block is glued to.
func glued(id: int) -> Array:
	return (joints.get(id, {}) as Dictionary).keys()


func clear() -> void:
	for id in joints.keys():
		unglue(int(id))
	mortared = {}


## Authority: this block (resting in its plan spot with the STICKY MORTAR gift on) glues down like honey from now on.
func mortar(id: int, rb: RigidBody3D) -> void:
	if mortared.has(id):
		return
	mortared[id] = true
	rb.contact_monitor = true
	rb.max_contacts_reported = maxi(rb.max_contacts_reported, 6)


## The gift is over (a new job): blocks glued so far stay glued, nothing new glues.
func end_mortar() -> void:
	mortared = {}
