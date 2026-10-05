extends Node3D
## STARSHIP CREW: the little starship and the pilot's cockpit (every machine draws it; the VR pilot
## sits in it on the host). The ship stays at the world origin facing -Z, so the cockpit never moves,
## rolls or pitches: comfortable VR.
## In reach of the VR pilot, and everything does something when touched:
##  - the FLIGHT STICK (right of the seat): touch it or squeeze the trigger on it, then move the hand:
##    sideways slides the ship sideways, up / down lifts or lowers it (measured from where the hand
##    took the stick, no rest pose). The left thumbstick steers too.
##  - three big toy buttons: HONK (purple), DISCO lights (yellow), BUBBLES (blue);
##  - a wobbly alien bobble-head; the eight star lamps (the mission's progress) and four planet lamps
##    (missions done) chime when touched;
##  - at the end a big green AGAIN button pops up on the dashboard.
## Host with VR: update_vr() reads the hands and returns the steering; toys call main.on_toy(what).

const Art := preload("res://games/starship_crew/art.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")

const STICK_BASE := Vector3(0.36, 0.64, -0.32)
const HANDLE_UP := 0.2
const STICK_TRAVEL := 0.1  ## hand travel (m) for full steering
const TOYS := {
	"honk": [Vector3(-0.5, 0.8, -0.62), Color(0.75, 0.4, 1.0)],
	"disco": [Vector3(-0.3, 0.8, -0.66), Color(1.0, 0.85, 0.25)],
	"bubbles": [Vector3(-0.1, 0.8, -0.68), Color(0.35, 0.75, 1.0)],
}
const BOBBLE_AT := Vector3(0.14, 0.8, -0.7)
const AGAIN_AT := Vector3(0.0, 0.84, -0.5)
const STARS := 8
const MISSIONS := 4

var main: Node
var rig: VrRig
var steer := Vector2.ZERO  ## -1..1 each way (host: from the hands; others: mirrored)
var held_by := -1  ## hand holding the stick
var held_t := 0.0  ## seconds the stick has been held in total (the ghost hand stops once they get it)
var idle_t := 0.0  ## seconds since the stick was last held
var again_on := false

var stick: Node3D
var toys := {}  ## name -> Node3D (the cap moves down when pressed)
var bobble: Node3D
var star_mm: MultiMeshInstance3D
var planet_mm: MultiMeshInstance3D
var again_btn: Node3D
var light: OmniLight3D
var avatar_seat: Node3D  ## robot autopilot head (local play without a headset)

var _grab_at := Vector3.ZERO
var _grab_trigger := false
var _touch_on := [{}, {}]
var _bob := Vector2.ZERO
var _bob_v := Vector2.ZERO
var _disco_t := 0.0
var _lit := Vector2i(-1, -1)
var _t := 0.0


func setup(m: Node, r: VrRig) -> void:
	main = m
	rig = r
	var hull := MeshKit.instance(Art.ship(), false)
	add_child(hull)
	add_child(MeshKit.instance(Art.dash(), false))
	if r == null:  # the glass is only drawn for the TV (from inside it would just get in the way)
		add_child(MeshKit.instance(Art.canopy(), false))
	stick = Node3D.new()
	stick.position = STICK_BASE
	stick.add_child(MeshKit.instance(Art.stick(), false))
	add_child(stick)
	for k in TOYS:
		var d: Array = TOYS[k]
		var n := Node3D.new()
		n.position = d[0]
		n.add_child(MeshKit.instance(Art.button(d[1]), false))
		add_child(n)
		toys[k] = n
	bobble = Node3D.new()
	bobble.position = BOBBLE_AT
	bobble.add_child(MeshKit.instance(Art.bobble(), false))
	add_child(bobble)
	var sx: Array = []
	for i in STARS:
		sx.append(_star_xf(i))
	star_mm = MeshKit.scatter(Art.star(), sx, PackedColorArray([Color(0.3, 0.3, 0.4)]), PackedColorArray(), false)
	add_child(star_mm)
	var px: Array = []
	for i in MISSIONS:
		px.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.03), _planet_spot(i)))
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 12
	ball.rings = 6
	ball.material = MeshKit.vertex_material(true)
	planet_mm = MeshKit.scatter(ball, px, PackedColorArray([Color(0.3, 0.3, 0.4)]), PackedColorArray(), false)
	add_child(planet_mm)
	again_btn = Node3D.new()
	again_btn.position = AGAIN_AT
	var ab := MeshKit.Builder.new()
	ab.cylinder(0.09, 0.1, 0.05, MeshKit.at(Vector3(0, 0.025, 0)), Color(0.3, 1.0, 0.45), 18, true)
	ab.cylinder(0.12, 0.12, 0.02, MeshKit.at(Vector3(0, 0.0, 0)), Color(0.95, 0.95, 1.0), 18)
	again_btn.add_child(MeshKit.instance(ab.build(), false))
	again_btn.visible = false
	add_child(again_btn)
	light = OmniLight3D.new()
	light.position = Vector3(0.0, 1.9, -0.6)
	light.omni_range = 4.0
	light.light_energy = 0.0
	light.shadow_enabled = false
	add_child(light)


func _star_xf(i: int) -> Transform3D:
	var x := -0.455 + i * 0.13
	return Transform3D(Basis(Vector3.RIGHT, -0.35).scaled(Vector3.ONE * 0.035), Vector3(x, 0.86, -0.86))


func _planet_spot(i: int) -> Vector3:
	return Vector3(0.3 + i * 0.09, 0.8, -0.6)


## Local play without a headset: a little robot sits in the pilot's seat and steers.
func add_robot() -> void:
	avatar_seat = MeshKit.instance(Art.robot_head(), false)
	avatar_seat.position = Vector3(0.0, 1.15, 0.1)
	add_child(avatar_seat)


func handle_point() -> Vector3:
	return stick.global_transform * Vector3(0.0, HANDLE_UP, 0.0)


# --- Host with VR: the hands -----------------------------------------------------------------

func update_vr(delta: float) -> void:
	var trig := rig.trigger_down()
	# The flight stick.
	if held_by < 0:
		idle_t += delta
		for h in [VrRig.RIGHT, VrRig.LEFT]:
			var p := rig.hand_point(h)
			var near := p.distance_to(handle_point())
			if near < 0.1 or (h == VrRig.RIGHT and rig.trigger_pressed() and near < 0.17):
				held_by = h
				_grab_at = p
				_grab_trigger = h == VrRig.RIGHT and trig
				rig.pulse(h, 0.35, 0.05)
				main.sound_at("ui_tick", p, -8.0, 1.3)
				break
	if held_by >= 0:
		idle_t = 0.0
		held_t += delta
		var p2 := rig.hand_point(held_by)
		if held_by == VrRig.RIGHT and trig:
			_grab_trigger = true
		var d := p2 - _grab_at
		var v := Vector2(d.x, d.y) / STICK_TRAVEL
		v = v.limit_length(1.0)
		steer = Vector2.ZERO if v.length() < 0.15 else v
		var gone := (_grab_trigger and not trig) or (not _grab_trigger and d.length() > 0.25)
		if gone:
			held_by = -1
			steer = Vector2.ZERO
	else:
		var s := rig.stick_left()
		steer = s if s.length() > 0.2 else Vector2.ZERO
	# The toys.
	for h in 2:
		var p3 := rig.hand_point(h)
		var now := {}
		for k in toys:
			if p3.distance_to((toys[k] as Node3D).global_position + Vector3(0, 0.04, 0)) < 0.075:
				now[k] = true
				if not _touch_on[h].has(k):
					rig.pulse(h, 0.5, 0.06)
					main.on_toy(k)
		if p3.distance_to(bobble.global_position + Vector3(0, 0.08, 0)) < 0.09:
			now["bobble"] = true
			if not _touch_on[h].has("bobble"):
				rig.pulse(h, 0.3, 0.04)
				main.on_toy("bobble")
		for i in STARS:
			if p3.distance_to(_star_xf(i).origin) < 0.06:
				now["s%d" % i] = true
				if not _touch_on[h].has("s%d" % i):
					rig.pulse(h, 0.2, 0.03)
					main.sound_at("ding", p3, -10.0, 0.8 + i * 0.1)
		for i in MISSIONS:
			if p3.distance_to(_planet_spot(i)) < 0.06:
				now["p%d" % i] = true
				if not _touch_on[h].has("p%d" % i):
					rig.pulse(h, 0.2, 0.03)
					main.sound_at("bell", p3, -10.0, 0.8 + i * 0.15)
		if again_on and p3.distance_to(again_btn.global_position + Vector3(0, 0.05, 0)) < 0.13:
			now["again"] = true
			if not _touch_on[h].has("again"):
				rig.pulse(h, 0.6, 0.1)
				main.on_toy("again")
		_touch_on[h] = now


# --- Every machine: animation -----------------------------------------------------------------

## A toy was pressed (every machine plays the look; the host also plays the sound for everyone).
func toy_fx(k: String) -> void:
	if toys.has(k):
		var cap: Node3D = toys[k]
		var tw := cap.create_tween()
		tw.tween_property(cap, "scale", Vector3(1.0, 0.4, 1.0), 0.06)
		tw.tween_property(cap, "scale", Vector3.ONE, 0.2)
	match k:
		"disco":
			_disco_t = 4.0
		"bobble":
			_bob_v += Vector2(randf_range(-6.0, 6.0), randf_range(4.0, 7.0))


func set_progress(stars: int, missions: int) -> void:
	var key := Vector2i(stars, missions)
	if key == _lit:
		return
	_lit = key
	for i in STARS:
		star_mm.multimesh.set_instance_color(i, Color(1.0, 0.85, 0.2) if i < stars else Color(0.3, 0.3, 0.4))
	var pc: Array[Color] = [Color(1.0, 0.6, 0.4), Color(0.5, 0.75, 1.0), Color(0.75, 0.5, 1.0), Color(0.5, 0.95, 0.6)]
	for i in MISSIONS:
		planet_mm.multimesh.set_instance_color(i, pc[i] if i < missions else Color(0.3, 0.3, 0.4))


func show_again(on: bool) -> void:
	again_on = on
	again_btn.visible = on


func animate(delta: float) -> void:
	_t += delta
	stick.rotation = Vector3(steer.y * 0.35, 0.0, -steer.x * 0.4)
	# The bobble-head: a springy wobble.
	_bob_v += (-_bob * 60.0 - _bob_v * 2.5) * delta
	_bob += _bob_v * delta
	bobble.rotation = Vector3(_bob.y * 0.1, 0.0, _bob.x * 0.1)
	# Disco lights: the cabin light cycles colours for a few seconds.
	if _disco_t > 0.0:
		_disco_t -= delta
		light.light_energy = 1.6
		light.light_color = Color.from_hsv(fmod(_t * 1.5, 1.0), 0.8, 1.0)
	else:
		light.light_energy = move_toward(light.light_energy, 0.0, delta * 2.0)
	if again_on:
		again_btn.scale = Vector3.ONE * (1.0 + sin(_t * 6.0) * 0.1)
	if avatar_seat != null:
		avatar_seat.rotation = Vector3(0.0, -steer.x * 0.4, steer.x * 0.15)
