extends Node3D
## BLOCK BUILDERS: PUFF'S BLOCK GIFTS at work on every machine (deep.gd GIFTS; the course's gift comes in the "deep"
## state). The gift is the whole team's for one sky course:
##   STICKY BRICKS  a green sticky puddle under every runner's feet (hazards.gd: wind and wobbles can't move them).
##   BIG BRICKS     every plank the builder puts down brings a free plank beside it (main.gd put, deep.gd big_extra).
##   BUILDER ROBOT  a little robot hovers over the glowing hint block; when the builder waits it puts it in (main.gd).
##   BLOCK BOX      one spare of every block in the tray (deep.gd tray).
##   JUMPY BOOTS    springy pink boots on every runner (runner.gd: jump higher).
## Cheap: one shared mesh per look (core/res_cache.gd).
##   set_gift(id), follow(runners, hint_at, delta) every frame, robot_put(at)

const ResCache := preload("res://core/res_cache.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Deep := preload("res://games/block_builders/deep.gd")

var main
var gift := ""
var looks := {}  # runner index -> Node3D
var robot: MeshInstance3D
var robot_to := Vector3.INF
var _t := 0.0


func _ready() -> void:
	name = "Gifts"


## Every machine: this course's gift ("" none).
func set_gift(id: String) -> void:
	if id == gift:
		return
	gift = id
	for k in looks:
		if is_instance_valid(looks[k]):
			(looks[k] as Node).queue_free()
	looks.clear()
	if robot != null and is_instance_valid(robot):
		robot.queue_free()
	robot = null
	robot_to = Vector3.INF
	if id == "robot":
		robot = MeshInstance3D.new()
		robot.name = "BuilderRobot"
		robot.mesh = _robot_mesh()
		robot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(robot)


## Every frame: the runners wear the gift; the robot hovers over the glowing hint block (or the start).
func follow(runners: Array, hint_at: Vector3, start: Vector3, delta: float) -> void:
	_t += delta
	if robot != null and is_instance_valid(robot):
		var want := (hint_at if hint_at != Vector3.INF else start) + Vector3(0.0, 2.2, 0.0)
		if robot_to != Vector3.INF:
			want = robot_to + Vector3(0.0, 1.4, 0.0)
		if robot.position == Vector3.ZERO:
			robot.position = want
		robot.position = robot.position.lerp(want, 1.0 - exp(-3.0 * delta)) + Vector3(0.0, sin(_t * 3.0) * 0.004, 0.0)
		robot.rotation.y = sin(_t * 1.3) * 0.5
		if robot_to != Vector3.INF and robot.position.distance_to(want) < 0.3:
			robot_to = Vector3.INF
	if gift != "sticky" and gift != "boots":
		return
	for r in runners:
		if not is_instance_valid(r) or not r.active:
			continue
		if looks.has(r.index) and is_instance_valid(looks[r.index]):
			continue
		var mi := MeshInstance3D.new()
		mi.name = "GiftLook"
		mi.mesh = _look_mesh(gift)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		r.add_child(mi)
		looks[r.index] = mi


## Every machine: the robot flies to a block it put in.
func robot_put(at: Vector3) -> void:
	robot_to = at


static func _look_mesh(id: String) -> Mesh:
	return ResCache.get_or_make("bb_gift_%s" % id, func() -> Resource:
		var b := MeshKit.Builder.new()
		var col: Color = Deep.gift(id).get("color", Color.WHITE)
		if id == "sticky":  # a sticky green puddle with a couple of blobs
			b.cylinder(0.36, 0.36, 0.03, MeshKit.at(Vector3(0.0, 0.02, 0.0)), col, 14)
			b.sphere(0.07, MeshKit.at(Vector3(0.22, 0.05, 0.12)), col.lightened(0.2), 8)
			b.sphere(0.05, MeshKit.at(Vector3(-0.2, 0.04, -0.15)), col.lightened(0.2), 8)
		else:  # jumpy boots: a pink boot with a coil under each foot
			for s in [-1.0, 1.0]:
				b.box(Vector3(0.16, 0.12, 0.24), MeshKit.at(Vector3(s * 0.12, 0.1, 0.0)), col)
				for k in 2:
					b.torus(0.07, 0.02, MeshKit.at(Vector3(s * 0.12, 0.02 - 0.04 * k, 0.0)), Color(0.85, 0.87, 0.9), 10, 4)
		return b.build()) as Mesh


static func _robot_mesh() -> Mesh:
	return ResCache.get_or_make("bb_robot", func() -> Resource:
		var b := MeshKit.Builder.new()
		var body := Color(0.7, 0.8, 1.0)
		b.box(Vector3(0.5, 0.45, 0.4), MeshKit.at(Vector3(0.0, 0.0, 0.0)), body)
		b.box(Vector3(0.4, 0.32, 0.34), MeshKit.at(Vector3(0.0, 0.4, 0.0)), body.lightened(0.2))
		b.sphere(0.06, MeshKit.at(Vector3(-0.09, 0.42, 0.17)), Color(0.15, 0.2, 0.35), 8)
		b.sphere(0.06, MeshKit.at(Vector3(0.09, 0.42, 0.17)), Color(0.15, 0.2, 0.35), 8)
		b.cylinder(0.015, 0.015, 0.2, MeshKit.at(Vector3(0.0, 0.66, 0.0)), Color(0.4, 0.4, 0.45), 6)
		b.sphere(0.05, MeshKit.at(Vector3(0.0, 0.78, 0.0)), Color(1.0, 0.35, 0.3), 8, true)
		b.cone(0.18, 0.25, MeshKit.at(Vector3(0.0, -0.33, 0.0), Vector3.ONE, Vector3(PI, 0, 0)), Color(1.0, 0.75, 0.3), 10, true)
		for s in [-1.0, 1.0]:
			b.box(Vector3(0.08, 0.3, 0.08), MeshKit.at(Vector3(s * 0.3, 0.0, 0.05), Vector3.ONE, Vector3(0.0, 0.0, s * 0.4)), body.darkened(0.2))
		return b.build()) as Mesh
