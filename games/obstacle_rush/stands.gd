extends Node3D
## OBSTACLE RUSH: COACH JELLY's GRANDSTAND (story.gd) on the picnic table behind the course: bleachers of
## fan beans that grows and stays. Every fan the team wins takes a seat (popping in with a hop); a new
## stand is built when one fills (centre first, then left, right, far left, far right), and the stands
## get flags, balloons, a band, fireworks, a giant trophy and gold trim as the crowd grows. The fans
## cheer (jump up and down) whenever a runner reaches the flag.
## The host owns the number (net state "fans"); every machine draws it with apply(fans).
## Cheap: one merged mesh for the bleachers and decorations (rebuilt only when a stand or decoration is
## added), and three MultiMeshes for the fans (body tinted per fan, face, party hat tinted per fan).
## Also COACH JELLY himself: a big jelly bean in a cap with a whistle on a podium by the start line.

const Story := preload("res://games/obstacle_rush/story.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const RunnerLook := preload("res://games/obstacle_rush/runner_look.gd")

const TABLE_Y := -3.5  ## (giant.gd TABLE_Y)
const STAND_X: Array[float] = [0.0, -7.2, 7.2, -14.4, 14.4]
const STAND_W := 6.6
const PER_ROW := Story.SEATS / 2
const ROW_Y: Array[float] = [2.3, 3.0]  ## seat tops above the table
const ROW_Z: Array[float] = [-5.1, -6.1]
const FAN_S := 0.78
const STAND_COLS: Array[Color] = [Color(0.55, 0.8, 1.0), Color(1.0, 0.6, 0.75), Color(0.6, 0.9, 0.62), Color(1.0, 0.85, 0.45), Color(0.8, 0.65, 1.0)]
const GOLD := Color(1.0, 0.82, 0.25)

var fans := -1
var built_stands := -1
var unlocked: Array = []
var t := 0.0
var cheer_t := 0.0
var pop := {}  ## fan index -> seconds since it arrived
var mm: Array[MultiMesh] = []  ## body, face, hat
var static_mi: MeshInstance3D
var deco: Node3D  ## balloons (they bob)
var coach: Node3D
var coach_body: Node3D
var coach_t := 0.0  ## > 0: the coach jumps for joy
var whistle_t := 0.0  ## > 0: the coach blows the whistle


func _ready() -> void:
	var meshes := [_fan_body(), _fan_face(), _fan_hat()]
	for k in 3:
		var m := MultiMesh.new()
		m.transform_format = MultiMesh.TRANSFORM_3D
		m.use_colors = true
		m.mesh = meshes[k]
		m.instance_count = Story.MAX_FANS
		m.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = m
		mmi.material_override = MeshKit.vertex_material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		mm.append(m)
	for k in Story.MAX_FANS:
		var look := Story.fan_look(k)
		mm[0].set_instance_color(k, RunnerLook.CPU_COLORS[int(look[0]) % RunnerLook.CPU_COLORS.size()])
		mm[1].set_instance_color(k, Color.WHITE)
		mm[2].set_instance_color(k, STAND_COLS[(int(look[1]) + k) % STAND_COLS.size()].lightened(0.1))
	_make_coach()
	apply(0)


## The crowd size from the host (every machine). New fans pop into their seats.
func apply(n: int) -> void:
	n = clampi(n, 0, Story.MAX_FANS)
	if n == fans:
		return
	if fans >= 0:
		for k in range(fans, n):
			pop[k] = 0.0
	fans = n
	for m in mm:
		m.visible_instance_count = n
	var want := Story.stands_for(n)
	var unl := Story.unlocked(n)
	if want != built_stands or var_to_str(unl) != var_to_str(unlocked):
		built_stands = want
		unlocked = unl
		_build_static()
	_place_fans()


## Where fan k sits (feet), in stand order.
static func seat(k: int) -> Vector3:
	var st := k / Story.SEATS
	var i := k % Story.SEATS
	var row := i / PER_ROW
	var col := i % PER_ROW
	var x := STAND_X[st] + (float(col) - (PER_ROW - 1) * 0.5) * (STAND_W - 0.8) / float(PER_ROW - 1)
	return Vector3(x, TABLE_Y + ROW_Y[row], ROW_Z[row])


## Everyone jumps for joy (a runner reached the flag).
func cheer(seconds: float = 2.0) -> void:
	cheer_t = maxf(cheer_t, seconds)
	coach_t = maxf(coach_t, seconds * 0.6)


func whistle() -> void:
	whistle_t = 0.8


func _process(delta: float) -> void:
	t += delta
	cheer_t = maxf(0.0, cheer_t - delta)
	coach_t = maxf(0.0, coach_t - delta)
	whistle_t = maxf(0.0, whistle_t - delta)
	for k in pop.keys():
		pop[k] = float(pop[k]) + delta
		if float(pop[k]) > 1.0:
			pop.erase(k)
	_place_fans()
	if deco != null:
		deco.position.y = sin(t * 1.3) * 0.15
	if coach_body != null:
		var hop := absf(sin(t * 9.0)) * 0.5 * minf(1.0, coach_t) if coach_t > 0.0 else 0.0
		coach_body.position.y = hop + sin(t * 2.0) * 0.03
		coach_body.rotation.z = sin(t * 1.7) * 0.06
		coach_body.scale = Vector3.ONE * (1.0 + (sin(t * 30.0) * 0.04 if whistle_t > 0.0 else 0.0))


func _place_fans() -> void:
	if fans <= 0:
		return
	for k in fans:
		var p := seat(k)
		var s := FAN_S
		if pop.has(k):
			var a := float(pop[k])
			s *= clampf(a * 3.0, 0.05, 1.0)
			p.y += sin(clampf(a, 0.0, 1.0) * PI) * 0.9
		elif cheer_t > 0.0:
			p.y += absf(sin(t * 8.0 + k * 1.7)) * 0.45 * minf(1.0, cheer_t)
		else:
			p.y += absf(sin(t * 2.0 + k * 0.9)) * 0.04
		var yaw := sin(t * 0.7 + k) * 0.25
		var xf := Transform3D(Basis(Vector3.UP, PI + yaw).scaled(Vector3.ONE * s), p)  # facing the course (+Z)
		for m in mm:
			m.set_instance_transform(k, xf)


func _build_static() -> void:
	if static_mi != null:
		static_mi.queue_free()
	if deco != null:
		deco.queue_free()
		deco = null
	var b := MeshKit.Builder.new()
	var gold := unlocked.has("gold")
	for st in built_stands:
		var x := STAND_X[st]
		var col := STAND_COLS[st % STAND_COLS.size()]
		var trim := GOLD if gold else Color(0.98, 0.97, 0.94)
		for row in 2:
			var h := ROW_Y[row]
			var z := ROW_Z[row]
			b.box(Vector3(STAND_W, h, 1.0), MeshKit.at(Vector3(x, TABLE_Y + h * 0.5, z)), col if row == 0 else col.darkened(0.12))
			b.box(Vector3(STAND_W + 0.1, 0.1, 1.05), MeshKit.at(Vector3(x, TABLE_Y + h + 0.03, z)), trim)
		b.box(Vector3(STAND_W, ROW_Y[1] + 1.4, 0.2), MeshKit.at(Vector3(x, TABLE_Y + (ROW_Y[1] + 1.4) * 0.5, ROW_Z[1] - 0.6)), col.darkened(0.25))
		b.box(Vector3(STAND_W + 0.2, 0.18, 0.3), MeshKit.at(Vector3(x, TABLE_Y + ROW_Y[1] + 1.45, ROW_Z[1] - 0.6)), trim)
		if unlocked.has("flags"):  # bunting along the back
			for k in 11:
				var fx := x - STAND_W * 0.5 + 0.3 + k * (STAND_W - 0.6) / 10.0
				var fc := STAND_COLS[(k + st) % STAND_COLS.size()]
				b.cone(0.22, 0.45, MeshKit.at(Vector3(fx, TABLE_Y + ROW_Y[1] + 1.15, ROW_Z[1] - 0.45), Vector3(1.0, 1.0, 0.25), Vector3(PI, 0, 0)), fc, 3)
		if unlocked.has("band") and st == 0:  # a drum and a horn at the front of the centre stand
			b.cylinder(0.55, 0.55, 0.6, MeshKit.at(Vector3(x - STAND_W * 0.5 - 0.7, TABLE_Y + 0.3, -5.0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.95, 0.3, 0.35), 16)
			b.cylinder(0.5, 0.5, 0.62, MeshKit.at(Vector3(x - STAND_W * 0.5 - 0.7, TABLE_Y + 0.3, -5.0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.98, 0.97, 0.94), 16)
			b.cone(0.35, 0.9, MeshKit.at(Vector3(x + STAND_W * 0.5 + 0.7, TABLE_Y + 0.9, -5.0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), GOLD, 12, true)
	if unlocked.has("trophy"):  # a giant golden cup on top of the centre stand
		var tp := Vector3(0.0, TABLE_Y + ROW_Y[1] + 1.55, ROW_Z[1] - 0.6)
		b.cylinder(0.5, 0.7, 0.3, MeshKit.at(tp + Vector3(0, 0.15, 0)), GOLD, 16, true)
		b.cylinder(0.12, 0.12, 0.6, MeshKit.at(tp + Vector3(0, 0.6, 0)), GOLD, 8, true)
		b.cylinder(0.9, 0.35, 1.1, MeshKit.at(tp + Vector3(0, 1.45, 0)), GOLD, 18, true)
		for s in [-1.0, 1.0]:
			b.torus(0.32, 0.07, MeshKit.at(tp + Vector3(s * 0.95, 1.5, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), GOLD, 14, 6, true)
	static_mi = MeshKit.instance(b.build())
	add_child(static_mi)
	if unlocked.has("balloons"):
		deco = Node3D.new()
		add_child(deco)
		var bb := MeshKit.Builder.new()
		for st in built_stands:
			for s in [-1.0, 1.0]:
				var base := Vector3(STAND_X[st] + s * (STAND_W * 0.5 - 0.1), TABLE_Y + ROW_Y[1] + 1.5, ROW_Z[1] - 0.6)
				for k in 3:
					var top := base + Vector3(s * 0.3 * (k - 1), 1.6 + k * 0.35, 0.2 * (k - 1))
					bb.tube(base, top, 0.015, 0.015, Color(0.95, 0.95, 0.95), 4)
					bb.ellipsoid(Vector3(0.32, 0.4, 0.32), MeshKit.at(top + Vector3(0, 0.38, 0)), STAND_COLS[(k + st * 2) % STAND_COLS.size()], 10)
		deco.add_child(MeshKit.instance(bb.build(), false))


## Fan meshes: a little bean (tinted per fan), its face, a party hat (tinted per fan).
static func _fan_body() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.capsule(RunnerLook.RADIUS, RunnerLook.HEIGHT, MeshKit.at(Vector3(0, RunnerLook.HEIGHT * 0.5, 0)), Color.WHITE, 8)
	for s in [-1.0, 1.0]:  # arms up
		b.capsule(0.08, 0.42, MeshKit.at(Vector3(s * 0.42, 0.85, 0.0), Vector3.ONE, Vector3(0, 0, -s * 0.5)), Color.WHITE, 6)
	return b.build()


static func _fan_face() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	for s in [-1.0, 1.0]:
		b.ellipsoid(Vector3(0.1, 0.12, 0.05), MeshKit.at(Vector3(s * 0.12, 0.84, -0.31)), RunnerLook.EYE_WHITE, 6)
		b.sphere(0.055, MeshKit.at(Vector3(s * 0.115, 0.83, -0.355)), RunnerLook.SKIN_DARK, 5)
	b.ellipsoid(Vector3(0.09, 0.05, 0.03), MeshKit.at(Vector3(0, 0.67, -0.34)), RunnerLook.SKIN_DARK, 6)
	return b.build()


static func _fan_hat() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.cone(0.17, 0.38, MeshKit.at(Vector3(0, RunnerLook.HEIGHT + 0.12, 0)), Color.WHITE, 8)
	b.sphere(0.06, MeshKit.at(Vector3(0, RunnerLook.HEIGHT + 0.33, 0)), Color.WHITE, 5)
	return b.build()


## COACH JELLY: a big orange bean in a blue cap with a silver whistle, on a candy podium.
func _make_coach() -> void:
	coach = Node3D.new()
	coach.name = "Coach"
	add_child(coach)
	var pod := MeshKit.Builder.new()
	pod.cylinder(0.7, 0.75, 0.5, MeshKit.at(Vector3(0, -0.25, 0)), Color(1.0, 0.6, 0.75), 16)
	pod.torus(0.7, 0.08, MeshKit.at(Vector3(0, 0.0, 0)), Color(0.98, 0.97, 0.94), 16, 6)
	pod.cylinder(0.3, 0.4, 3.6, MeshKit.at(Vector3(0, -2.3, 0)), Color(0.85, 0.5, 0.62), 10)
	coach.add_child(MeshKit.instance(pod.build()))
	coach_body = Node3D.new()
	coach.add_child(coach_body)
	var mi := MeshInstance3D.new()
	mi.mesh = RunnerLook.body_mesh(Story.COACH_COLOR, "cap", "belly")
	mi.material_override = MeshKit.vertex_material()
	mi.scale = Vector3.ONE * 1.5
	coach_body.add_child(mi)
	var wb := MeshKit.Builder.new()
	wb.tube(Vector3(-0.25, 1.35, -0.42), Vector3(0.0, 0.85, -0.55), 0.02, 0.02, Color(0.95, 0.3, 0.35), 4)
	wb.capsule(0.07, 0.22, MeshKit.at(Vector3(0.0, 0.8, -0.6), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.8, 0.82, 0.88), 8, true)
	coach_body.add_child(MeshKit.instance(wb.build(), false))


## Put the coach by the start line of the course (every course build), facing the runners.
func place_coach(start_x: float, half_w: float) -> void:
	if coach != null:
		coach.position = Vector3(start_x + 0.5, 0.0, -half_w - 0.9)
		coach.rotation.y = PI  # facing +Z: the runners and the giant
