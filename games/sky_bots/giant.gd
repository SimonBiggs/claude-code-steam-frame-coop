extends Node3D
## SKY BOTS: the GIANT (the VR player, host). The islands float at waist height in front of a giant standing on the
## cloud floor (world scale S: a robot is about 10 cm tall), like a toy diorama. The giant HELPS with their hands:
##   - grab a LIFT's yellow handle with the right trigger and lift it up (or down) for the robots; let go and it carries
##     on by itself
##   - flick a GRUMBLE off its floor (touch it with a moving hand), poke CRANKY CRAB while it's dizzy
##   - poke the secret room's CRACKED WALL open, pick up bolts, boop a robot (a little hop)
##   - left stick walks along the islands, right stick snap-turns
## Without a VR giant the lifts just go up and down by themselves; everything can be done without one (levelgen.gd
## check() never counts on the giant).
## The TV machine draws the giant's head and gloves (giant-sized) from VrRig.pack_pose().

const VrRig := preload("res://core/vr_rig.gd")
const G := preload("res://games/sky_bots/levelgen.gd")

const S := 10.0  ## XR world scale: 10 units = 1 real metre
const FLOOR_Y := -8.0  ## the cloud floor the giant stands on (the islands are about 0.8 m up)
const FEET_Z := 7.0
const WALK_X := 34.0  ## levelgen.gd X_MIN / X_MAX
const GRAB_R := 1.3  ## a hand this near a lift's handle grabs it with the trigger
const TOUCH_R := 0.8

var main: Node
var rig: VrRig
var host := true
var held_lift := -1
var grab_dy := 0.0
var touch_on := [{}, {}]
var lifts_used := 0
var flicks := 0
var avatar_head: Node3D
var avatar_hands: Array[Node3D] = []


func setup(m: Node, r: VrRig, is_host: bool) -> void:
	main = m
	rig = r
	host = is_host
	if rig != null:
		rig.set_scale_of_world(S)
		rig.move_speed = 0.5 * S
		rig.bounds = Rect2(-WALK_X, FEET_Z - 2.0, WALK_X * 2.0, 5.0)
		rig.camera.far = 3000.0
		rig.camera.near = 0.05
		rig.place(feet(), 0.0)


## Where the giant stands: on the cloud floor in front of the islands (+Z), facing them (-Z).
static func feet() -> Vector3:
	return Vector3(0.0, FLOOR_Y, FEET_Z)


## Host, every physics frame while an island is up: the hands.
func step(_delta: float) -> void:
	if not host or rig == null:
		return
	var level: Node = main.level
	var playing := level != null and not (level.lv as Dictionary).is_empty() and String(main.net.state_get("phase", "")) == "play"
	if not playing:
		if held_lift >= 0 and level != null:
			level.hold_lift(held_lift, NAN)
		held_lift = -1
		return
	var hr := rig.hand_point(VrRig.RIGHT)
	if held_lift >= 0:
		if rig.trigger_down():
			level.hold_lift(held_lift, hr.y - grab_dy)
		else:
			level.hold_lift(held_lift, NAN)
			held_lift = -1
			rig.pulse(VrRig.RIGHT, 0.3, 0.05)
	elif rig.trigger_pressed():
		var best := -1
		var bd := GRAB_R
		for i in level.lifts():
			var d: float = level.handle_point(i).distance_to(hr)
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			held_lift = best
			grab_dy = hr.y - level.plat_pos(best).y
			lifts_used += 1
			main.on_lift_grabbed()
			main.sound_at("pop", hr, -6.0, 0.9)
			rig.pulse(VrRig.RIGHT, 0.5, 0.06)
	for h in 2:
		var p := rig.hand_point(h)
		var now := {}
		for i in level.grumbles.size():
			if level.grumble_alive(i) and p.distance_to(level.grumble_pos(i) + Vector3(0, 0.4, 0)) < TOUCH_R:
				now["g%d" % i] = true
				if not touch_on[h].has("g%d" % i):
					flicks += 1
					main.pop_grumble(i, "giant")
					rig.pulse(h, 0.5, 0.06)
		if level.near_wall(p, 0.4):
			now["wall"] = true
			if not touch_on[h].has("wall"):
				main.break_wall("giant")
				rig.pulse(h, 0.6, 0.08)
		var k: int = level.bolt_at(p, 0.6)
		if k >= 0:
			main.take_bolt(k, 0)
		var bx: int = level.box_near(p, 0.6)  # (a finger taps a bot box open)
		if bx >= 0:
			main.open_box(bx, 0)
			rig.pulse(h, 0.5, 0.06)
		if main.boss != null and main.boss.alive() and p.distance_to(main.boss.position + Vector3(0, 0.9, 0)) < 1.4:
			now["boss"] = true
			if not touch_on[h].has("boss") and main.boss_hit("giant"):
				rig.pulse(h, 0.7, 0.1)
		for rid in main.robots:
			var rb: Node3D = main.robots[rid]
			if p.distance_to(rb.position + Vector3(0, 0.6, 0)) < TOUCH_R:
				now["r%d" % int(rid)] = true
				if not touch_on[h].has("r%d" % int(rid)):
					main.boop(int(rid))
					rig.pulse(h, 0.3, 0.04)
		touch_on[h] = now


# --- The TV machine: the giant as seen from there ------------------------------------------------------------------

func make_avatar() -> void:
	var mat := VrRig.vertex_color_material()
	avatar_head = Node3D.new()
	add_child(avatar_head)
	var face := MeshInstance3D.new()
	face.mesh = VrRig.VrRigStatics.head_mesh(Color(0.4, 0.75, 1.0))
	face.material_override = mat
	face.scale = Vector3.ONE * S
	face.layers = VrRig.AVATAR_LAYER
	avatar_head.add_child(face)
	for i in 2:
		var n := Node3D.new()
		add_child(n)
		var g := MeshInstance3D.new()
		g.mesh = VrRig.glove_mesh(i == 0, Color(1.0, 0.86, 0.6), Color.WHITE)
		g.material_override = mat
		g.scale = Vector3.ONE * S
		g.layers = VrRig.AVATAR_LAYER
		n.add_child(g)
		avatar_hands.append(n)
	avatar_head.visible = false
	for n in avatar_hands:
		n.visible = false


func apply_pose(p: PackedFloat32Array, delta: float) -> void:
	if avatar_head == null:
		return
	if p.size() < 21:
		avatar_head.visible = false
		for n in avatar_hands:
			n.visible = false
		return
	var nodes: Array[Node3D] = [avatar_head, avatar_hands[0], avatar_hands[1]]
	for i in 3:
		var o := i * 7
		var t := Transform3D(Basis(Quaternion(p[o + 3], p[o + 4], p[o + 5], p[o + 6]).normalized()), Vector3(p[o], p[o + 1], p[o + 2]))
		var n := nodes[i]
		if not n.visible:
			n.global_transform = t
			n.visible = true
		else:
			n.global_transform = n.global_transform.interpolate_with(t, 1.0 - exp(-15.0 * delta))
