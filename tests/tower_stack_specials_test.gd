extends SceneTree
## TOWER STACK special blocks in REAL physics (no game scene, no window): games/tower_stack/specials.gd does what the
## validator (towergen.gd stability) assumes:
##   - honey glues: a cube hanging off a honey block stays up (the same overhang on a plain cube falls);
##   - balloons lift: a balloon block falls slower than a cube and a wind push moves it further;
##   - bouncy: a cube dropped on a bouncy block bounces back up, and players bounce off it (bounce_jump);
##   - glue lets go when the block is lifted (unglue on grab).
##   godot-test --headless --path . -s res://tests/tower_stack_specials_test.gd     Prints BOT RESULT: PASS / FAIL.

const G := preload("res://games/tower_stack/towergen.gd")
const Specials := preload("res://games/tower_stack/specials.gd")


class FakeMain extends Node3D:
	var blocks := {}
	var bkind := {}
	var bstate := {}
	var stage: StaticBody3D
	var specials: Node

	func _physics_process(_d: float) -> void:
		specials.tick(self)

	func _poke(_id: int, _a: float) -> void:
		pass

	## pos: local to this little scene.
	func block(id: int, kind: int, pos: Vector3) -> RigidBody3D:
		var rb := RigidBody3D.new()
		rb.mass = G.MASS[kind]
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = G.size_of(kind)
		cs.shape = box
		rb.add_child(cs)
		Specials.setup(rb, kind, id)
		rb.position = pos
		add_child(rb)
		blocks[id] = rb
		bkind[id] = kind
		bstate[id] = "free"
		return rb


var fails := 0
var frames := 0
var scenes: Array = []
var phase := 0
var marks := {}


func _initialize() -> void:
	# Scene A: honey under an overhang. Scene B: the same overhang on a cube. Scene C: balloon vs cube falling.
	# Scene D: a cube dropped on a bouncy block.
	for i in 4:
		var m := FakeMain.new()
		m.specials = Specials.new()
		m.add_child(m.specials)
		root.add_child(m)
		m.position = Vector3(i * 20.0, 0, 0)
		var floor_body := StaticBody3D.new()
		var fs := CollisionShape3D.new()
		var fb := BoxShape3D.new()
		fb.size = Vector3(10, 1, 10)
		fs.shape = fb
		floor_body.add_child(fs)
		var pm := PhysicsMaterial.new()
		pm.friction = 1.0
		floor_body.physics_material_override = pm
		m.add_child(floor_body)
		floor_body.position = Vector3(0, -0.5, 0)
		m.stage = floor_body
		scenes.append(m)
	scenes[0].block(1, G.K_STICKY, Vector3(0, G.B * 0.5, 0))
	scenes[1].block(1, G.K_CUBE, Vector3(0, G.B * 0.5, 0))
	scenes[2].block(1, G.K_BALLOON, Vector3(-1, 3.0, 0))
	scenes[2].block(2, G.K_CUBE, Vector3(1, 3.0, 0))
	scenes[3].block(1, G.K_BOUNCY, Vector3(0, G.B * 0.5, 0))


func _physics_process(_delta: float) -> bool:
	frames += 1
	match frames:
		30:  # let the bottom blocks settle and the honey glue to the floor, then add the overhangs
			for i in 2:
				var m: FakeMain = scenes[i]
				m.block(2, G.K_CUBE, Vector3(G.B * 0.75, G.B * 1.5 + 0.005, 0))
			var c: FakeMain = scenes[2]
			marks["fall"] = [c.blocks[1].global_position.y, c.blocks[2].global_position.y]
			var d: FakeMain = scenes[3]
			d.block(2, G.K_CUBE, Vector3(0, 2.0, 0))
		45:
			var c2: FakeMain = scenes[2]
			_expect(c2.blocks[1].global_position.y > c2.blocks[2].global_position.y + 0.1,
				"a balloon block falls slower than a cube (%.2f vs %.2f)" % [c2.blocks[1].global_position.y, c2.blocks[2].global_position.y])
	if frames >= 30 and frames < 120:
		var d2: FakeMain = scenes[3]
		if d2.blocks.has(2):
			marks["up"] = maxf(float(marks.get("up", 0.0)), (d2.blocks[2] as RigidBody3D).linear_velocity.y)
	if frames == 150:
		var a: FakeMain = scenes[0]
		var b: FakeMain = scenes[1]
		_expect(not a.specials.glued(2).is_empty() or not a.specials.glued(1).is_empty(), "honey glued to what it touches")
		_expect(a.blocks[1].position.y > 0.2 and b.blocks[1].position.y > 0.2, "the bottom blocks stand on the floor")
		_expect(a.blocks[2].global_position.y > G.B * 1.2, "a cube hanging off a honey block stays up (y %.2f)" % a.blocks[2].global_position.y)
		_expect(b.blocks[2].global_position.y < G.B * 1.2, "the same overhang on a plain cube falls (y %.2f)" % b.blocks[2].global_position.y)
		_expect(float(marks.get("up", 0.0)) > 1.0, "a cube dropped on a bouncy block bounces back up (%.2f m/s)" % float(marks.get("up", 0.0)))
		_expect(Specials.bounce_jump(G.K_BOUNCY) > 7.5 and Specials.bounce_jump(G.K_CUBE) == 0.0, "players bounce off bouncy blocks only")
		# Lifting a glued block lets the glue go.
		a.bstate[1] = "held"
		a.specials.tick(a)
		_expect(a.specials.glued(1).is_empty() and a.specials.glued(2).is_empty(), "glue lets go of a lifted block")
		print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
		for m in scenes:
			m.queue_free()
		quit(0 if fails == 0 else 1)
	return false


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: %s" % what)
