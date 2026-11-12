extends Node3D
## COASTER CREW: BUTTONS' TOY FAIR on the living-room floor round the table (deep.gd FAIR: one ride every FAIR_EVERY
## coaster rides, saved for good as "fair"). Toy-sized rides at the VR builder's feet (they are a giant: a ride is a
## knee-high toy), seen from the TV views beyond the table edge: teacups, a swing ride, a helter-skelter, a drop tower,
## a pirate ship, bumper cars, a rocket ride and a big top. Each turns, swings or bobs gently. Main-space (the room,
## not the turning table). Every machine builds it from the state store ("fair").
##   set_count(n, animate)

const MeshKit := preload("res://core/mesh_kit.gd")
const Track := preload("res://games/roller_coaster/track.gd")
const Deep := preload("res://games/roller_coaster/deep.gd")

const R := 22.0  # from the middle of the table
const ANGLES: Array[float] = [42.0, -42.0, 78.0, -78.0, 116.0, -116.0, 156.0, -156.0]  # 0 = the builder's side (+Z)
const RUG_Y := Track.FLOOR_Y + 0.2

var count := 0
var rides: Array[Node3D] = []
var movers: Array = []  # [node, kind, phase]
var _t := 0.0


## Where fair ride i stands (main space).
static func spot(i: int) -> Vector3:
	var a := deg_to_rad(ANGLES[i % ANGLES.size()])
	return Vector3(sin(a) * R, RUG_Y, cos(a) * R)


func set_count(n: int, animate: bool) -> void:
	n = clampi(n, 0, Deep.FAIR.size())
	while count < n:
		var kind: String = Deep.FAIR[count]
		var node := _make(kind, count)
		node.name = "Fair_" + kind
		node.position = spot(count)
		node.rotation.y = atan2(-node.position.x, -node.position.z)  # (front towards the table)
		add_child(node)
		rides.append(node)
		if animate:
			node.scale = Vector3.ONE * 0.05
			create_tween().tween_property(node, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		count += 1


func _mover(parent: Node3D, b: MeshKit.Builder, at: Vector3, kind: String) -> Node3D:
	var n := Node3D.new()
	n.position = at
	n.add_child(MeshKit.instance(b.build(), false))
	parent.add_child(n)
	movers.append([n, kind, randf() * TAU])
	return n


func _make(kind: String, i: int) -> Node3D:
	var n := Node3D.new()
	var b := MeshKit.builder()
	var m := MeshKit.builder()
	match kind:
		"teacups":
			b.cylinder(3.2, 3.4, 0.4, MeshKit.at(Vector3(0, 0.2, 0)), Color(0.95, 0.75, 0.85), 24)
			var cols := [Color(0.4, 0.75, 1.0), Color(1.0, 0.5, 0.6), Color(0.6, 0.9, 0.45)]
			for k in 3:
				var a := TAU * k / 3.0
				var p := Vector3(cos(a), 0, sin(a)) * 1.9
				m.cylinder(0.95, 0.7, 1.0, MeshKit.at(p + Vector3(0, 0.5, 0)), cols[k], 14)
				m.torus(0.95, 0.1, MeshKit.at(p + Vector3(0, 1.0, 0)), Color.WHITE, 16, 4)
				m.torus(0.35, 0.09, Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, -a), p + Vector3(cos(a), 0, sin(a)) * 1.0 + Vector3(0, 0.6, 0)), Color.WHITE, 10, 4)
			m.sphere(0.5, MeshKit.at(Vector3(0, 1.0, 0)), Color(1.0, 0.85, 0.3), 10)
			n.add_child(MeshKit.instance(b.build(), false))
			_mover(n, m, Vector3(0, 0.4, 0), "spin")
		"swings":
			b.cylinder(2.2, 2.4, 0.4, MeshKit.at(Vector3(0, 0.2, 0)), Color(0.9, 0.85, 0.6), 20)
			b.cylinder(0.25, 0.3, 6.6, MeshKit.at(Vector3(0, 3.5, 0)), Color(1.0, 0.8, 0.3), 8)
			m.cone(2.8, 1.4, MeshKit.at(Vector3(0, 0.0, 0)), Color(0.4, 0.65, 1.0), 16)
			m.cylinder(2.8, 2.8, 0.3, MeshKit.at(Vector3(0, -0.15, 0)), Color(1.0, 0.95, 0.9), 16)
			for k in 6:
				var a := TAU * k / 6.0
				var top := Vector3(cos(a), 0, sin(a)) * 2.4
				var seat := Vector3(cos(a), 0, sin(a)) * 3.3 + Vector3(0, -3.4, 0)
				m.tube(top, seat, 0.04, 0.04, Color(0.85, 0.85, 0.9), 4)
				m.box(Vector3(0.6, 0.15, 0.6), MeshKit.at(seat), [Color(1, 0.4, 0.4), Color(1, 0.85, 0.3), Color(0.5, 0.9, 0.5)][k % 3])
			n.add_child(MeshKit.instance(b.build(), false))
			_mover(n, m, Vector3(0, 6.6, 0), "spin")
		"helter":
			for k in 7:
				b.cylinder(1.3, 1.35, 1.0, MeshKit.at(Vector3(0, 0.5 + k, 0)), Color(0.95, 0.3, 0.3) if k % 2 == 0 else Color(0.98, 0.95, 0.9), 14, false, k == 0)
			b.cone(1.7, 2.0, MeshKit.at(Vector3(0, 8.0, 0)), Color(0.35, 0.6, 1.0), 14)
			var turns := 2.2
			var segs := 30
			for k in segs:
				var a0 := TAU * turns * k / segs
				var a1 := TAU * turns * (k + 1) / segs
				var y0 := 6.6 - 6.2 * k / segs
				var y1 := 6.6 - 6.2 * (k + 1) / segs
				b.tube(Vector3(cos(a0) * 1.9, y0, sin(a0) * 1.9), Vector3(cos(a1) * 1.9, y1, sin(a1) * 1.9), 0.32, 0.32, Color(1.0, 0.85, 0.25), 6)
			n.add_child(MeshKit.instance(b.build(), false))
			m.cylinder(0.05, 0.05, 1.2, MeshKit.at(Vector3(0, 0.6, 0)), Color.WHITE, 4)
			m.box(Vector3(0.8, 0.5, 0.05), MeshKit.at(Vector3(0.4, 1.0, 0)), Color(1.0, 0.5, 0.7))
			_mover(n, m, Vector3(0, 9.0, 0), "flag")
		"droptower":
			b.cylinder(1.8, 2.0, 0.4, MeshKit.at(Vector3(0, 0.2, 0)), Color(0.8, 0.8, 0.85), 18)
			b.cylinder(0.35, 0.4, 10.0, MeshKit.at(Vector3(0, 5.2, 0)), Color(0.9, 0.9, 0.95), 10)
			b.sphere(0.7, MeshKit.at(Vector3(0, 10.4, 0)), Color(1.0, 0.4, 0.45), 12, true)
			m.torus(1.1, 0.3, Transform3D.IDENTITY, Color(0.55, 0.35, 0.95), 18, 6)
			for k in 6:
				var a := TAU * k / 6.0
				m.box(Vector3(0.45, 0.6, 0.35), Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a), 0.4, sin(a)) * 1.15), Color(1.0, 0.85, 0.3))
			n.add_child(MeshKit.instance(b.build(), false))
			_mover(n, m, Vector3(0, 1.2, 0), "drop")
		"pirate":
			for side in [-1.0, 1.0]:
				b.tube(Vector3(-2.2, 0, side * 1.1), Vector3(0, 6.0, side * 1.1), 0.18, 0.18, Color(0.55, 0.36, 0.2), 6)
				b.tube(Vector3(2.2, 0, side * 1.1), Vector3(0, 6.0, side * 1.1), 0.18, 0.18, Color(0.55, 0.36, 0.2), 6)
			b.tube(Vector3(0, 6.0, -1.2), Vector3(0, 6.0, 1.2), 0.15, 0.15, Color(0.4, 0.25, 0.15), 6)
			m.tube(Vector3.ZERO, Vector3(0, -3.4, 0), 0.12, 0.12, Color(0.4, 0.25, 0.15), 5)
			m.ellipsoid(Vector3(3.2, 0.9, 1.0), MeshKit.at(Vector3(0, -3.6, 0)), Color(0.6, 0.38, 0.2), 14)
			m.box(Vector3(5.2, 0.15, 1.5), MeshKit.at(Vector3(0, -3.0, 0)), Color(0.85, 0.65, 0.4))
			m.box(Vector3(0.1, 2.0, 1.4), MeshKit.at(Vector3(0, -1.7, 0)), Color(0.98, 0.95, 0.85))
			m.box(Vector3(0.6, 0.4, 0.05), MeshKit.at(Vector3(0.0, -0.5, 0)), Color(0.15, 0.15, 0.2))
			n.add_child(MeshKit.instance(b.build(), false))
			_mover(n, m, Vector3(0, 6.0, 0), "swing")
		"bumper":
			b.box(Vector3(7.0, 0.3, 5.0), MeshKit.at(Vector3(0, 0.15, 0)), Color(0.45, 0.45, 0.55))
			for side in [-1.0, 1.0]:
				b.box(Vector3(7.2, 0.5, 0.3), MeshKit.at(Vector3(0, 0.45, side * 2.5)), Color(1.0, 0.8, 0.3))
				b.box(Vector3(0.3, 0.5, 5.2), MeshKit.at(Vector3(side * 3.5, 0.45, 0)), Color(1.0, 0.8, 0.3))
			n.add_child(MeshKit.instance(b.build(), false))
			var cols := [Color(1.0, 0.35, 0.35), Color(0.35, 0.7, 1.0), Color(0.45, 0.9, 0.4)]
			for k in 3:
				var cb := MeshKit.builder()
				cb.rounded_box(Vector3(1.3, 0.6, 1.0), 0.25, MeshKit.at(Vector3(0, 0.3, 0)), cols[k])
				cb.cylinder(0.04, 0.04, 1.4, MeshKit.at(Vector3(-0.4, 1.0, 0)), Color(0.8, 0.8, 0.85), 4)
				var c := _mover(n, cb, Vector3(0, 0.3, 0), "bump")
				(movers.back() as Array)[2] = TAU * k / 3.0
				c.position = Vector3.ZERO
		"rocketride":
			b.cylinder(1.6, 1.8, 0.4, MeshKit.at(Vector3(0, 0.2, 0)), Color(0.3, 0.3, 0.45), 18)
			b.cylinder(0.3, 0.35, 4.0, MeshKit.at(Vector3(0, 2.2, 0)), Color(0.85, 0.85, 0.95), 8)
			var cols := [Color(1.0, 0.4, 0.4), Color(0.4, 0.75, 1.0), Color(1.0, 0.85, 0.3), Color(0.55, 0.9, 0.45)]
			for k in 4:
				var a := TAU * k / 4.0
				var p := Vector3(cos(a), 0, sin(a)) * 3.0
				m.tube(Vector3.ZERO, p, 0.1, 0.1, Color(0.85, 0.85, 0.95), 4)
				var bx := Basis(Vector3.UP, -a + PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5)
				m.cylinder(0.45, 0.45, 1.4, Transform3D(bx, p), cols[k], 10)
				m.cone(0.45, 0.7, Transform3D(bx, p + bx.y * 1.05), Color(0.98, 0.95, 0.9), 10)
				m.box(Vector3(1.2, 0.08, 0.5), Transform3D(bx, p - bx.y * 0.5), cols[k].darkened(0.3))
			m.sphere(0.5, Transform3D.IDENTITY, Color(1.0, 0.85, 0.3), 10, true)
			n.add_child(MeshKit.instance(b.build(), false))
			_mover(n, m, Vector3(0, 4.0, 0), "spin")
		"bigtop":
			b.cylinder(3.6, 3.6, 3.0, MeshKit.at(Vector3(0, 1.5, 0)), Color(0.95, 0.3, 0.35), 20)
			for k in 10:
				var a := TAU * k / 10.0
				b.box(Vector3(0.7, 3.02, 0.1), Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(cos(a), 0, sin(a)) * 3.58 + Vector3(0, 1.5, 0)), Color(0.98, 0.95, 0.9))
			b.cone(4.0, 3.2, MeshKit.at(Vector3(0, 4.6, 0)), Color(1.0, 0.85, 0.3), 20)
			b.box(Vector3(1.4, 2.0, 0.2), MeshKit.at(Vector3(0, 1.0, 3.55)), Color(0.25, 0.1, 0.12))
			b.cylinder(0.06, 0.06, 1.4, MeshKit.at(Vector3(0, 6.6, 0)), Color.WHITE, 4)
			n.add_child(MeshKit.instance(b.build(), false))
			m.box(Vector3(0.9, 0.55, 0.05), MeshKit.at(Vector3(0.45, 0.0, 0)), Color(0.4, 0.75, 1.0))
			_mover(n, m, Vector3(0, 7.0, 0), "flag")
	return n


func _process(delta: float) -> void:
	if movers.is_empty():
		return
	_t += delta
	for mv in movers:
		var node: Node3D = mv[0]
		var ph: float = mv[2]
		match String(mv[1]):
			"spin":
				node.rotation.y += delta * 0.8
			"flag":
				node.rotation.y = sin(_t * 1.3 + ph) * 0.5
			"drop":
				var k := fposmod(_t * 0.25 + ph, 1.0)
				node.position.y = 1.2 + 7.0 * (smoothstep(0.0, 0.45, k) if k < 0.6 else 1.0 - smoothstep(0.6, 0.72, k))
			"swing":
				node.rotation.z = sin(_t * 1.1 + ph) * 0.75
			"bump":
				var a := _t * 0.7 + ph
				node.position = Vector3(cos(a) * 2.2, 0.3, sin(a * 1.3) * 1.3)
				node.rotation.y = -a + sin(_t * 2.0 + ph) * 0.4
