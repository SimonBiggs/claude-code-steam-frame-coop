extends Node3D
## The ONE see-through teaching hand ("ghost hand") every game uses to SHOW a VR player a move instead
## of telling it in words: a glowing glove that reaches, grips, carries, swings, points, lets go.
## Games used to have 17 drifted copies of this (games/*/ghost_hand.gd); tests/shared_scripts_test.gd
## now fails any copy that comes back. The hand is the shared part; each game keeps only its own
## choreography (where to reach, what to carry) in its own code, driving this node with the helpers
## below. Usage:
##   const GhostHand := preload("res://core/ghost_hand.gd")
##   ghost = GhostHand.new()
##   ghost.size = 4.0               # options BEFORE add_child (see below)
##   add_child(ghost)
##   var knife := ghost.prop(box_mesh)        # see-through things it holds (on the hand) or shows (loose)
##   ... every frame:
##   if ghost.gate(want, delta, 1.2, busy):   # hidden until the player has idled for a moment
##       var t := ghost.play("chop", 2.2, delta)
##       var k := GhostHand.track([[0.0, a], [0.7, b, 1.0], ...], t)   # keyframed path + grip
##       ghost.pose(Transform3D(GhostHand.yaw_to(dir), k.p), k.grip)
##       ghost.set_alpha(ghost.fade(2.2))
## Cheap: a handful of unshaded meshes, one see-through material (UiKit.see_through), no shadows.

const UiKit := preload("res://core/ui_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")

const TINT := Color(0.75, 1.0, 0.95, 0.5)  ## the glow every ghost hand has
const ALPHA := 0.55  ## its usual peak opacity
const CURL := 1.3  ## finger curl (radians) at grip 1.0

enum Look {
	HAND,  ## palm + 4 poseable fingers (index first) + thumb: grips, points, fists, lets go
	GLOVE,  ## the player's own VrRig glove (one mesh, no finger poses): games whose real hands are VrRig gloves
}

# --- Options: set before add_child -------------------------------------------------------------
var look := Look.HAND
var left := false  ## a left hand (mirrored)
var size := 1.0  ## hand size (world-scaled games: a real-size hand in a giant's world)
var tint := TINT
var world_space := true  ## top_level: placed in world space with global_transform (false: follows its parent)
var layers := 0  ## render layers for every mesh, props included (0: leave the default); set_layers() later

# --- Parts and state ---------------------------------------------------------------------------
var hand: Node3D  ## pose this one (pose()); the meshes sit in a child scaled by `size`
var model: Node3D
var fingers: Array[Node3D] = []  ## index, middle, ring, little (Look.HAND); rotate .x to curl
var thumb: Node3D
var mat: StandardMaterial3D  ## the hand's (and plain props') see-through material
var t := 0.0  ## the loop clock (play())
var idle_t := 0.0  ## gate(): how long the player has been idle
var mode := ""  ## the demo playing now ("" = none); play() restarts the loop when it changes
var shown := false  ## bots: a demo has been on screen
var seen := {}  ## bots: mode -> true once that demo has been on screen
var alpha := 0.0
var _props: Array = []  # [MeshInstance3D, material, base alpha]


func _ready() -> void:
	top_level = world_space
	mat = make_mat(tint)
	hand = Node3D.new()
	hand.name = "Hand"
	add_child(hand)
	model = Node3D.new()
	model.scale = Vector3(-size if left else size, size, size)
	hand.add_child(model)
	if look == Look.GLOVE:
		_mesh(model, VrRig.glove_mesh(left, Color.WHITE, Color.WHITE), mat)
	else:
		_build_hand()
	if layers != 0:
		set_layers(layers)
	visible = false


## A real-size right hand (mirrored for left), palm down, fingers pointing -Z.
func _build_hand() -> void:
	var pm := BoxMesh.new()
	pm.size = Vector3(0.085, 0.028, 0.095)
	_mesh(model, pm, mat)
	for i in 4:
		var f := Node3D.new()
		f.position = Vector3(-0.03 + i * 0.02, 0.0, -0.047)
		model.add_child(f)
		_mesh(f, _capsule(0.009, 0.075), mat, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0, -0.075 * 0.45)))
		fingers.append(f)
	thumb = Node3D.new()
	thumb.position = Vector3(-0.045, -0.005, 0.015)
	thumb.rotation.y = 0.6
	model.add_child(thumb)
	_mesh(thumb, _capsule(0.011, 0.06), mat, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0, -0.06 * 0.45)))


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var cap := CapsuleMesh.new()
	cap.radius = r
	cap.height = h
	cap.radial_segments = 6
	cap.rings = 1
	return cap


func _mesh(parent: Node3D, mesh: Mesh, m: Material, at := Transform3D()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.transform = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if layers != 0:
		mi.layers = layers
	parent.add_child(mi)
	return mi


## The ghost look for anything: unshaded, see-through (UiKit.see_through: under VR cards), two-sided.
static func make_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	UiKit.see_through(m)
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## A see-through thing the demo uses. on_hand: it moves with the hand (a sword, knife, lantern), in
## the hand's own space (`at`, metres before `size`); else it's loose (a ball, a block) under this node:
## place it with global_transform / global_position. color: its own glow (alpha = its peak opacity,
## following set_alpha); a zero colour shares the hand's material.
func prop(mesh: Mesh, color := Color(0, 0, 0, 0), on_hand := true, at := Transform3D()) -> MeshInstance3D:
	var m := mat if color.a <= 0.0 else make_mat(color)
	var mi := _mesh(model if on_hand else self, mesh, m, at)
	if m != mat:
		_props.append([mi, m, color.a])
	return mi


## Turns a ready-made node tree (the game's watering can...) into a see-through prop: every mesh gets the
## hand's material. Same on_hand / loose rule as prop().
func ghostify(n: Node3D, on_hand := false) -> Node3D:
	(model if on_hand else self).add_child(n)
	var meshes: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		meshes.append(n)
	for mi: MeshInstance3D in meshes:
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if layers != 0:
		set_layers(layers)
	return n


## Draw everything (props too) on render layer mask l only (e.g. the VR player's view-model layer).
func set_layers(l: int) -> void:
	layers = l
	for vi in find_children("*", "VisualInstance3D", true, false):
		(vi as VisualInstance3D).layers = l


## The usual "show it once the player has idled a moment" gate. Returns false (and hides, restarting the
## loop) unless `want`; `busy` (the player is doing it right now) hides it and restarts the wait.
func gate(want: bool, delta: float, wait := 0.0, busy := false) -> bool:
	if not want or busy:
		hide_demo()
		return false
	idle_t += delta
	if idle_t < wait:
		visible = false
		return false
	return true


## Advance the loop clock of demo `what` (a new demo starts from 0) and mark it shown. Returns t.
func play(what: String, cycle: float, delta: float) -> float:
	if what != mode:
		mode = what
		t = 0.0
	t = fmod(t + delta, cycle)
	visible = true
	shown = true
	seen[what] = true
	return t


## Hide and restart (the next play() starts its loop from the beginning).
func hide_demo() -> void:
	visible = false
	t = 0.0
	idle_t = 0.0
	mode = ""


## Fade in over fade_in s, out over the last fade_out s of the cycle (at the loop clock t).
func fade(cycle: float, fade_in := 0.3, fade_out := 0.5, peak := ALPHA) -> float:
	var a := peak * minf(1.0, t / fade_in)
	if t > cycle - fade_out:
		a *= maxf(0.0, (cycle - t) / fade_out)
	return a


## The hand's (and its props') opacity. It doesn't change `visible`: that means "a demo is on" (play() /
## hide_demo()), which bots check, even while a loop has faded right out.
func set_alpha(a: float) -> void:
	alpha = a
	mat.albedo_color.a = a
	for p in _props:
		(p[1] as StandardMaterial3D).albedo_color.a = float(p[2]) * a / ALPHA


## Put the hand at `at` (world space when world_space) and curl its fingers (grip: 0 open .. 1 closed; -1 leaves them).
func pose(at: Transform3D, grip := -1.0) -> void:
	hand.global_transform = at
	if grip >= 0.0:
		set_grip(grip)


## Curl every finger and the thumb (0 open, 1 a grip; a little past 1 makes a fist; below 0 flicks open).
func set_grip(k: float) -> void:
	for f in fingers:
		f.rotation.x = -k * CURL
	if thumb != null:
		thumb.rotation.x = -minf(k, 1.0) * 0.7


## Point with the index finger (curl: how much it squeezes, e.g. a trigger) and fist the others.
func set_point(curl := 0.0) -> void:
	for i in fingers.size():
		fingers[i].rotation.x = -curl * CURL if i == 0 else -1.15 * CURL
	if thumb != null:
		thumb.rotation.x = -0.7


## The index fingertip in the hand's own space (at size): pose(Transform3D(b, tip - b * fingertip())) puts
## the fingertip on a button.
func fingertip() -> Vector3:
	return Vector3(-0.03 * (-1.0 if left else 1.0), 0.0, -0.047 - 0.075 * 0.95) * size


## A keyframed path for the loop clock t. keys: [[0.0, start_pos, start_grip?], [t_end, pos, grip?, curve?, arc?], ...]:
## from the previous key to each key the position eases (ease(k, curve), default -1.8: smooth in and out),
## lifting by sin(k*PI)*arc on the way; grip (default: the previous key's) changes linearly. Holds after
## the last key. Returns {p: Vector3, grip: float, seg: index of the key it moves towards, k: 0..1}.
static func track(keys: Array, at: float) -> Dictionary:
	var prev: Array = keys[0]
	var p: Vector3 = prev[1]
	var g: float = float(prev[2]) if prev.size() > 2 else 0.0
	for i in range(1, keys.size()):
		var key: Array = keys[i]
		var t0: float = prev[0]
		var t1: float = key[0]
		var to: Vector3 = key[1]
		var g1: float = float(key[2]) if key.size() > 2 else g
		if at < t1:
			var k := clampf((at - t0) / maxf(t1 - t0, 0.0001), 0.0, 1.0)
			var e := ease(k, float(key[3]) if key.size() > 3 else -1.8)
			var arc: float = float(key[4]) if key.size() > 4 else 0.0
			return {"p": p.lerp(to, e) + Vector3.UP * sin(e * PI) * arc, "grip": lerpf(g, g1, k), "seg": i, "k": k}
		p = to
		g = g1
		prev = key
	return {"p": p, "grip": g, "seg": keys.size(), "k": 1.0}


## A basis turned (about UP only) so -Z, the fingers, points along flat dir.
static func yaw_to(dir: Vector3) -> Basis:
	var d := Vector3(dir.x, 0.0, dir.z)
	return Basis(Vector3.UP, atan2(-d.x, -d.z) if d.length() > 0.01 else 0.0)


## The sword slash both sword games teach (Dungeon Delve, Crystal Saga): from the hero at `from`, the
## hand (holding a sword prop) swings right through `target` and back, on a 2.4 s loop clock t.
static func slash(t: float, target: Vector3, from: Vector3, cycle := 2.4) -> Transform3D:
	var b := yaw_to(target - from)
	var near := target + b * Vector3(0.0, 0.0, 0.6)  # the blade passes through the target
	var start := near + b * Vector3(0.5, 0.3, 0.0)
	var end := near + b * Vector3(-0.5, -0.15, 0.0)
	var p: Vector3
	var sweep := 0.0
	if t < 0.8:  # raise the sword
		p = start
		sweep = 0.7
	elif t < 1.15:  # SWING
		var k := ease((t - 0.8) / 0.35, 0.4)
		p = start.lerp(end, k)
		sweep = lerpf(0.7, -0.7, k)
	elif t < 1.6:
		p = end
		sweep = -0.7
	else:  # back up
		var k2 := (t - 1.6) / (cycle - 1.6)
		p = end.lerp(start, k2)
		sweep = lerpf(-0.7, 0.7, k2)
	return Transform3D(b * Basis(Vector3.UP, sweep) * Basis(Vector3.RIGHT, -0.15), p)